//! GPU image compositing component with numerical pixel assertions, not IPC or
//! real-terminal/legacy-parity qualification. Hidden context, no clipboard.
const std = @import("std");
const gl = @import("opengl");
const wgl = @import("renderer/opengl/wgl.zig");
const data = @import("renderer/GlslData.zig");
const Text = @import("renderer/remote/TextFrame.zig");
const Snapshot = @import("renderer/remote/ImageSnapshot.zig");
const Placement = @import("renderer/remote/ImagePlacement.zig");
const Bundle = @import("renderer/remote/ImageFrame.zig");
const Resource = @import("renderer/remote/ImageResource.zig");
const Executor = @import("renderer/remote/TextGpuExecutor.zig").Executor;
fn textPacket(alloc: std.mem.Allocator) !Text.Owned {
    var uniforms = std.mem.zeroes(data.Uniforms);
    uniforms.projection_matrix = @import("math.zig").ortho2d(0, 8, 4, 0);
    uniforms.screen_size = .{ 8, 4 };
    uniforms.cell_size = .{ 4, 4 };
    uniforms.grid_size = .{ 2, 1 };
    uniforms.cursor_pos = @splat(std.math.maxInt(u16));
    var fg = [_]data.CellText{.{ .glyph_size = .{ 1, 1 }, .bearings = .{ 0, 3 }, .grid_pos = .{ 0, 0 }, .color = .{ 255, 255, 255, 255 }, .atlas = .grayscale }};
    const rows = [_]Text.Row{.{ .items = &fg, .capacity = 1 }};
    return Text.encodeAlloc(alloc, .{ .width = 8, .height = 4, .blending = .native, .uniforms = uniforms, .background = &.{ .{ 12, 12, 12, 255 }, .{ 1, 2, 3, 255 } }, .foreground_rows = &rows, .grayscale = .{ .size = 1, .bytes = &.{255} }, .color = .{ .size = 1, .bytes = &.{ 255, 255, 255, 255 } } }, .{ .dimension = 1024, .atlas_dimension = 512, .cells = 16, .bytes = 4096 });
}
fn bundle(alloc: std.mem.Allocator, text: []const u8, images: []const Resource.Input, placements: []const Placement) !Resource.Owned {
    var snapshot = try Snapshot.encodeAlloc(alloc, .{ .images = images, .placements = placements, .cell_size = .{ 4, 4 } }, .{});
    defer snapshot.deinit();
    return Bundle.encodeAlloc(alloc, text, snapshot.bytes, .{});
}
const Counts = struct { red: u32 = 0, green: u32 = 0, white: u32 = 0 };
fn counts(pixels: []const u8) Counts {
    var result: Counts = .{};
    var at: usize = 0;
    while (at < pixels.len) : (at += 4) {
        const r = pixels[at];
        const g = pixels[at + 1];
        const b = pixels[at + 2];
        if (r >= 240 and g <= 15 and b <= 15) result.red += 1;
        if (g >= 240 and r <= 15 and b <= 15) result.green += 1;
        if (r >= 240 and g >= 240 and b >= 240) result.white += 1;
    }
    return result;
}
pub fn main() !void {
    const alloc = std.heap.page_allocator;
    const device = try wgl.Device.init(alloc, .{});
    defer device.deinit(alloc);
    var context = try device.createContext();
    defer context.deinit();
    try context.makeCurrent();
    defer wgl.Context.releaseCurrent();
    const version = try gl.glad.load(&wgl.getProcAddress);
    defer gl.glad.unload();
    if (gl.glad.versionMajor(@intCast(version)) < 4 or (gl.glad.versionMajor(@intCast(version)) == 4 and gl.glad.versionMinor(@intCast(version)) < 3)) return error.OpenGLOutdated;
    var gpu: Executor = .{};
    defer gpu.deinit(alloc);
    var text = try textPacket(alloc);
    defer text.deinit();
    const red: Resource.Input = .{ .id = 1, .generation = 1, .width = 1, .height = 1, .rgba = &.{ 255, 0, 0, 255 } };
    var placement: Placement = .{ .image_id = 1, .generation = 1, .x = 0, .y = 0, .z = 0, .width = 4, .height = 4, .source_x = 0, .source_y = 0, .source_width = 1, .source_height = 1 };
    const limit = std.math.minInt(i32) / 2;
    for ([_]i32{ std.math.minInt(i32), limit - 1, limit, -1, 0, 1 }, 0..) |z, index| {
        placement.z = z;
        var packet = try bundle(alloc, text.bytes, &.{red}, &.{placement});
        defer packet.deinit();
        var image = try gpu.renderImageFrame(alloc, packet.bytes, .{}, 4096);
        defer image.deinit();
        const actual = counts(image.pixels);
        const expected_red: u32 = if (index < 2) 0 else if (index < 4) 15 else 16;
        const expected_white: u32 = if (index < 4) 1 else 0;
        if (actual.red != expected_red or actual.white != expected_white or actual.green != 0) return error.ImageBandPixelsDiffer;
    }
    if (gpu.image_cache.created != 1 or gpu.image_cache.reused != 5) return error.PlacementOnlyUpdateUploadedPixels;
    const crop_image: Resource.Input = .{ .id = 1, .generation = 2, .width = 2, .height = 1, .rgba = &.{ 255, 0, 0, 255, 0, 255, 0, 255 } };
    placement.generation = 2;
    placement.x = -1;
    placement.width = 6;
    placement.source_x = 1;
    var cropped = try bundle(alloc, text.bytes, &.{crop_image}, &.{placement});
    defer cropped.deinit();
    {
        var image = try gpu.renderImageFrame(alloc, cropped.bytes, .{}, 4096);
        defer image.deinit();
        const actual = counts(image.pixels);
        if (actual.green != 8 or actual.red != 0 or actual.white != 0) return error.CroppedClippedImagePixelsDiffer;
    }
    var empty = try bundle(alloc, text.bytes, &.{}, &.{});
    defer empty.deinit();
    {
        var image = try gpu.renderImageFrame(alloc, empty.bytes, .{}, 4096);
        defer image.deinit();
        const actual = counts(image.pixels);
        if (actual.white != 1 or actual.red != 0 or actual.green != 0 or gpu.image_cache.entries.count() != 0) return error.EmptyImageFrameDidNotRestoreText;
    }
    placement.generation = 1;
    placement.x = 0;
    placement.width = 4;
    placement.source_x = 0;
    var again = try bundle(alloc, text.bytes, &.{red}, &.{placement});
    defer again.deinit();
    {
        var image = try gpu.renderImageFrame(alloc, again.bytes, .{}, 4096);
        defer image.deinit();
    }
    const texture = gpu.image_cache.entries.get(1).?.texture.texture.id;
    {
        var image = try gpu.render(alloc, text.bytes, .{ .dimension = 1024, .atlas_dimension = 512, .cells = 16, .bytes = 4096 }, 4096);
        defer image.deinit();
        if (counts(image.pixels).white != 1 or gpu.image_cache.entries.count() != 0 or gl.glad.context.IsTexture.?(texture) != 0) return error.PlainTextDidNotReleaseImages;
    }
    if (gpu.program_sets_created != 1 or gpu.completed_frames != 10) return error.ImageFrameResourceLifecycleFailed;
    std.debug.print("PASS GPU image compositing: 10 real frames; all three z bands/exact boundaries preserve or cover glyphs; placement-only updates reused upload; source crop+negative clipping; empty/plain text remove resources. Not IPC/terminal legacy parity.\n", .{});
}
