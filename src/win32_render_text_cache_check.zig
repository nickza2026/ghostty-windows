//! GPU-context component check, NOT a GPU-free parent or terminal-host proof.
const std = @import("std");
const gl = @import("opengl");
const wgl = @import("renderer/opengl/wgl.zig");
const text = @import("renderer/remote/TextFrame.zig");
const data = @import("renderer/GlslData.zig");
const Executor = @import("renderer/remote/TextGpuExecutor.zig").Executor;

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
    const limits: text.Limits = .{ .dimension = 1024, .atlas_dimension = 512, .cells = 16, .bytes = 4096 };
    if (gpu.render(alloc, &.{}, limits, 4096)) |image_value| {
        var image = image_value;
        image.deinit();
        return error.InvalidFrameAccepted;
    } else |err| if (err != error.InvalidLength) return err;
    if (gpu.program_sets_created != 0 or gpu.atlas_created != 0 or gpu.targets_created != 0 or gpu.target != null) return error.GpuAllocatedBeforeValidation;

    var uniforms = std.mem.zeroes(data.Uniforms);
    uniforms.projection_matrix = @import("math.zig").ortho2d(0, 8, 4, 0);
    uniforms.screen_size = .{ 8, 4 };
    uniforms.cell_size = .{ 4, 4 };
    uniforms.grid_size = .{ 2, 1 };
    // Same hidden-cursor sentinel as the real renderer. A zeroed cursor at0,0
    // would replace our glyph's white color with transparent cursor_color.
    uniforms.cursor_pos = @splat(std.math.maxInt(u16));
    const bg = [_]data.CellBg{ .{ 12, 12, 12, 255 }, .{ 1, 2, 3, 255 } };
    var fg = [_]data.CellText{.{ .glyph_size = .{ 1, 1 }, .bearings = .{ 0, 3 }, .grid_pos = .{ 0, 0 }, .color = .{ 255, 255, 255, 255 }, .atlas = .grayscale }};
    const rows = [_]text.Row{.{ .items = &fg, .capacity = fg.len }};
    var gray = [_]u8{255} ** 9;
    var color = [_]u8{255} ** 100;
    var reference: ?[]u8 = null;
    var stable_target_id: u32 = 0;
    defer if (reference) |pixels| alloc.free(pixels);
    for ([_][2]u32{ .{ 1, 1 }, .{ 1, 1 }, .{ 3, 1 }, .{ 1, 5 }, .{ 1, 5 }, .{ 1, 5 }, .{ 1, 5 }, .{ 1, 5 }, .{ 1, 5 }, .{ 1, 5 } }, 0..) |sizes, index| {
        gray[0] = if (index == 5) 0 else 255;
        fg[0].atlas = if (index >= 7) .color else .grayscale;
        // Input format is BGRA; opaque red -> green -> white, no shader change.
        color[0] = if (index == 7 or index == 8) 0 else 255;
        color[1] = if (index == 7) 0 else 255;
        color[2] = if (index == 8) 0 else 255;
        var packet = try text.encodeAlloc(alloc, .{ .width = 8, .height = 4, .blending = .native, .uniforms = uniforms, .background = &bg, .foreground_rows = &rows, .grayscale = .{ .size = sizes[0], .bytes = gray[0 .. sizes[0] * sizes[0]] }, .color = .{ .size = sizes[1], .bytes = color[0 .. sizes[1] * sizes[1] * 4] } }, limits);
        defer packet.deinit();
        var image = try gpu.render(alloc, packet.bytes, limits, 4096);
        defer image.deinit();
        if (index == 0) stable_target_id = gpu.target.?.texture.id;
        if (stable_target_id == 0 or gpu.target.?.texture.id != stable_target_id or gpu.targets_created != 1) return error.StableTargetRecreated;
        var visible_glyph = false;
        var red_glyph = false;
        var green_glyph = false;
        var offset: usize = 0;
        while (offset < image.pixels.len) : (offset += 4) {
            if (image.pixels[offset] >= 240 and image.pixels[offset + 1] >= 240 and image.pixels[offset + 2] >= 240) visible_glyph = true;
            if (image.pixels[offset] >= 240 and image.pixels[offset + 1] <= 15 and image.pixels[offset + 2] <= 15) red_glyph = true;
            if (image.pixels[offset] <= 15 and image.pixels[offset + 1] >= 240 and image.pixels[offset + 2] <= 15) green_glyph = true;
        }
        if (index == 5) {
            if (visible_glyph or std.mem.eql(u8, reference.?, image.pixels)) return error.AtlasUpdateIgnored;
        } else if (index == 7 or index == 8) {
            if (visible_glyph or (index == 7 and !red_glyph) or (index == 8 and !green_glyph) or std.mem.eql(u8, reference.?, image.pixels)) return error.ColorAtlasUpdateIgnored;
        } else if (!visible_glyph) return error.GlyphNotDrawn else if (reference) |pixels| {
            if (!std.mem.eql(u8, pixels, image.pixels)) return error.CachedPixelsChanged;
        } else reference = try alloc.dupe(u8, image.pixels);
    }
    if (gpu.program_sets_created != 1 or gpu.atlas_created != 5 or gpu.atlas_updated != 15 or gpu.completed_frames != 10) return error.CacheLifetimeCountersFailed;
    for ([_][2]u32{ .{ 9, 5 }, .{ 8, 4 } }, 0..) |size, index| {
        const old_texture = gpu.target.?.texture.id;
        const old_export = gpu.target.?.export_texture.id;
        const old_framebuffer = gpu.target.?.framebuffer.id;
        const old_export_framebuffer = gpu.target.?.export_framebuffer.id;
        uniforms.screen_size = .{ @floatFromInt(size[0]), @floatFromInt(size[1]) };
        uniforms.projection_matrix = @import("math.zig").ortho2d(0, @floatFromInt(size[0]), @floatFromInt(size[1]), 0);
        var packet = try text.encodeAlloc(alloc, .{ .width = size[0], .height = size[1], .blending = .native, .uniforms = uniforms, .background = &bg, .foreground_rows = &rows, .grayscale = .{ .size = 1, .bytes = gray[0..1] }, .color = .{ .size = 5, .bytes = &color } }, limits);
        defer packet.deinit();
        var image = try gpu.render(alloc, packet.bytes, limits, 4096);
        defer image.deinit();
        if (gpu.targets_created != index + 2 or gpu.target.?.width != size[0] or gpu.target.?.height != size[1]) return error.TargetResizeNotApplied;
        if (gl.glad.context.IsTexture.?(old_texture) != 0 or gl.glad.context.IsTexture.?(old_export) != 0 or gl.glad.context.IsFramebuffer.?(old_framebuffer) != 0 or gl.glad.context.IsFramebuffer.?(old_export_framebuffer) != 0) return error.ReplacedTargetStillAlive;
        if (index == 1 and !std.mem.eql(u8, reference.?, image.pixels)) return error.ReturnedTargetPixelsChanged;
    }
    const target_id = gpu.target.?.texture.id;
    if (gpu.targets_created != 3 or gpu.completed_frames != 12) return error.TargetCacheLifetimeCountersFailed;
    const target_export = gpu.target.?.export_texture.id;
    const target_framebuffer = gpu.target.?.framebuffer.id;
    const target_export_framebuffer = gpu.target.?.export_framebuffer.id;
    const gray_id = gpu.grayscale.?.texture.id;
    const color_id = gpu.color.?.texture.id;
    gpu.deinit(alloc);
    if (gpu.programs != null or gpu.grayscale != null or gpu.color != null or gpu.target != null) return error.CacheResourcesStillOwned;
    if (gl.glad.context.IsTexture.?(target_id) != 0 or gl.glad.context.IsTexture.?(target_export) != 0 or gl.glad.context.IsFramebuffer.?(target_framebuffer) != 0 or gl.glad.context.IsFramebuffer.?(target_export_framebuffer) != 0) return error.TargetStillAlive;
    if (gl.glad.context.IsTexture.?(gray_id) != 0 or gl.glad.context.IsTexture.?(color_id) != 0) return error.CacheTextureStillAlive;
    try gl.errors.getError();
    std.debug.print("PASS GPU text resource cache: 10 real frames; grayscale mask hide/restore and BGRA color glyph red/green/white updates verified; shader set built1; atlas creates5/updates15 odd1/3/5; invalid frame allocated0; GL textures deleted. Not performance/terminal qualification.\n", .{});
    std.debug.print("PASS GPU target cache: stable10frames oneFBOtarget; resize9x5/return8x4 creates3total; replaced and final targets/textures destroyed; returned pixels exact. No cadence/protocol/budget change.\n", .{});
}
