//! Actual GPU upload/cache component, not worker IPC or terminal image proof.
const std = @import("std");
const gl = @import("opengl");
const wgl = @import("renderer/opengl/wgl.zig");
const Snapshot = @import("renderer/remote/ImageSnapshot.zig");
const Resource = @import("renderer/remote/ImageResource.zig");
const Cache = @import("renderer/remote/ImageGpuCache.zig");
fn packet(alloc: std.mem.Allocator, id: u32, generation: u64, width: u32, pixels: []const u8) !Resource.Owned {
    return Snapshot.encodeAlloc(alloc, .{ .images = &.{.{ .id = id, .generation = generation, .width = width, .height = 1, .rgba = pixels }}, .placements = &.{}, .cell_size = .{ 4, 4 } }, .{});
}
fn readback(entry: Cache.Entry, expected: []const u8) !void {
    var bytes: [8]u8 = undefined;
    if (expected.len > bytes.len) return error.TestReadbackTooLarge;
    const binding = try entry.texture.texture.bind(.@"2d");
    defer binding.unbind();
    gl.glad.context.PixelStorei.?(gl.c.GL_PACK_ALIGNMENT, 1);
    gl.glad.context.GetTexImage.?(gl.c.GL_TEXTURE_2D, 0, gl.c.GL_RGBA, gl.c.GL_UNSIGNED_BYTE, @ptrCast(&bytes));
    try gl.errors.getError();
    if (!std.mem.eql(u8, expected, bytes[0..expected.len])) return error.ImageUploadPixelsDiffer;
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
    var cache: Cache = .{};
    defer cache.deinit(alloc);
    if (cache.sync(alloc, &.{}, .{})) |_| return error.InvalidImageSnapshotAccepted else |err| if (err != error.TruncatedSnapshot) return err;
    if (cache.created != 0) return error.InvalidSnapshotCreatedTexture;
    var red = try packet(alloc, 1, 1, 1, &.{ 255, 0, 0, 255 });
    defer red.deinit();
    try cache.sync(alloc, red.bytes, .{});
    const first = cache.entries.get(1).?.texture.texture.id;
    try readback(cache.entries.get(1).?, &.{ 255, 0, 0, 255 });
    try cache.sync(alloc, red.bytes, .{});
    if (cache.entries.get(1).?.texture.texture.id != first or cache.created != 1 or cache.reused != 1) return error.ImageNotReused;
    red.bytes[68] = 0; // 32B snapshot + one4B offset + 32B resource header.
    if (cache.sync(alloc, red.bytes, .{})) |_| return error.SameGenerationChangedPixelsAccepted else |err| if (err != error.ImageGenerationContentMismatch) return err;
    red.bytes[68] = 255;
    try readback(cache.entries.get(1).?, &.{ 255, 0, 0, 255 });
    var green = try packet(alloc, 1, 2, 1, &.{ 0, 255, 0, 255 });
    defer green.deinit();
    try cache.sync(alloc, green.bytes, .{});
    if (gl.glad.context.IsTexture.?(first) != 0) return error.ReplacedImageStillAlive;
    const second = cache.entries.get(1).?.texture.texture.id;
    try readback(cache.entries.get(1).?, &.{ 0, 255, 0, 255 });
    if (cache.sync(alloc, red.bytes, .{})) |_| return error.StaleImageAccepted else |err| if (err != error.StaleImageGeneration) return err;
    if (cache.entries.get(1).?.texture.texture.id != second) return error.StaleImageMutatedCache;
    var resized = try packet(alloc, 1, 3, 2, &.{ 0, 0, 255, 255, 255, 255, 255, 255 });
    defer resized.deinit();
    try cache.sync(alloc, resized.bytes, .{});
    if (gl.glad.context.IsTexture.?(second) != 0) return error.ResizedImageStillAlive;
    try readback(cache.entries.get(1).?, &.{ 0, 0, 255, 255, 255, 255, 255, 255 });
    const third = cache.entries.get(1).?.texture.texture.id;
    var other = try packet(alloc, 9, 1, 1, &.{ 255, 0, 0, 255 });
    defer other.deinit();
    try cache.sync(alloc, other.bytes, .{});
    if (cache.entries.count() != 1 or cache.entries.contains(1) or gl.glad.context.IsTexture.?(third) != 0) return error.MissingImageNotEvicted;
    const fourth = cache.entries.get(9).?.texture.texture.id;
    var empty = try Snapshot.encodeAlloc(alloc, .{ .images = &.{}, .placements = &.{}, .cell_size = .{ 4, 4 } }, .{});
    defer empty.deinit();
    try cache.sync(alloc, empty.bytes, .{});
    if (cache.entries.count() != 0 or gl.glad.context.IsTexture.?(fourth) != 0 or cache.created != 4 or cache.replaced != 2 or cache.evicted != 2) return error.EmptySnapshotDidNotDeleteImages;
    try cache.sync(alloc, red.bytes, .{}); // ID can be freshly reused after removal.
    const final_id = cache.entries.get(1).?.texture.texture.id;
    cache.deinit(alloc);
    if (gl.glad.context.IsTexture.?(final_id) != 0) return error.ImageCacheCleanupFailed;
    try gl.errors.getError();
    std.debug.print("PASS GPU image resource cache: actual RGBA2D/sRGBA pixel readback; reuse/generation replace/resize/stale reject/full-snapshot deletion/ID reuse/GL cleanup. No image draw/IPC/terminal claim.\n", .{});
}
