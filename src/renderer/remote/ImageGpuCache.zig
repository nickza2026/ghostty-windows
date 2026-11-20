//! GPU-worker-only candidate. Requires its owner's current loaded GL context.
//! Full snapshot synchronization; no protocol ACK and no parent texture state.
const std = @import("std");
const gl = @import("opengl");
const Snapshot = @import("ImageSnapshot.zig");
const Texture = @import("../opengl/Texture.zig");
const Cache = @This();
// Non-cryptographic consistency fingerprint, not authentication/security proof.
pub const Entry = struct { generation: u64, fingerprint: u64, texture: Texture };
entries: std.AutoHashMapUnmanaged(u32, Entry) = .{},
created: u64 = 0,
reused: u64 = 0,
replaced: u64 = 0,
evicted: u64 = 0,
pub fn deinit(self: *Cache, alloc: std.mem.Allocator) void {
    var iterator = self.entries.valueIterator();
    while (iterator.next()) |entry| entry.texture.deinit();
    self.entries.deinit(alloc);
    self.entries = .{};
}
fn contains(view: Snapshot.View, id: u32) !bool {
    var lo: usize = 0;
    var hi: usize = view.image_count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const image = try view.image(mid);
        if (image.id == id) return true;
        if (image.id < id) lo = mid + 1 else hi = mid;
    }
    return false;
}
/// Caller must treat ANY error as fatal for the frame/session. A late GL failure
/// can leave a partially updated cache; no successful upload/draw ACK is implied.
pub fn sync(self: *Cache, alloc: std.mem.Allocator, packet: []const u8, limits: Snapshot.Limits) !void {
    const view = try Snapshot.decode(packet, limits); // Validate before GL access.
    var maximum: gl.c.GLint = 0;
    gl.glad.context.GetIntegerv.?(gl.c.GL_MAX_TEXTURE_SIZE, &maximum);
    try gl.errors.getError();
    if (maximum <= 0) return error.InvalidTextureLimit;
    // Preflight every resource before mutating even the first texture.
    for (0..view.image_count) |index| {
        const image = try view.image(index);
        if (image.width > @as(u32, @intCast(maximum)) or image.height > @as(u32, @intCast(maximum))) return error.UnsupportedImageDimensions;
        if (self.entries.get(image.id)) |old| {
            if (image.generation < old.generation) return error.StaleImageGeneration;
            if (image.generation == old.generation and (image.width != old.texture.width or image.height != old.texture.height)) return error.ImageGenerationDimensionMismatch;
            if (image.generation == old.generation and std.hash.Wyhash.hash(0, image.rgba) != old.fingerprint) return error.ImageGenerationContentMismatch;
        }
    }
    // Reserve for old + incoming, since obsolete IDs are evicted AFTER uploads.
    try self.entries.ensureTotalCapacity(alloc, self.entries.count() + view.image_count);
    var remove: std.ArrayList(u32) = .empty;
    defer remove.deinit(alloc);
    try remove.ensureTotalCapacity(alloc, self.entries.count());
    var iterator = self.entries.keyIterator();
    while (iterator.next()) |id| if (!try contains(view, id.*)) remove.appendAssumeCapacity(id.*);
    gl.glad.context.PixelStorei.?(gl.c.GL_UNPACK_ALIGNMENT, 1);
    try gl.errors.getError();
    for (0..view.image_count) |index| {
        const image = try view.image(index);
        if (self.entries.get(image.id)) |old| if (old.generation == image.generation) {
            self.reused += 1;
            continue;
        };
        const replacement = try Texture.init(.{ .format = .rgba, .internal_format = .srgba, .target = .@"2d", .min_filter = .linear, .mag_filter = .linear, .wrap_s = .clamp_to_edge, .wrap_t = .clamp_to_edge }, image.width, image.height, image.rgba);
        if (self.entries.getPtr(image.id)) |old| {
            const previous = old.texture;
            old.* = .{ .generation = image.generation, .fingerprint = std.hash.Wyhash.hash(0, image.rgba), .texture = replacement };
            previous.deinit();
            self.replaced += 1;
        } else self.entries.putAssumeCapacity(image.id, .{ .generation = image.generation, .fingerprint = std.hash.Wyhash.hash(0, image.rgba), .texture = replacement });
        self.created += 1;
    }
    for (remove.items) |id| {
        const entry = self.entries.fetchRemove(id).?;
        entry.value.texture.deinit();
        self.evicted += 1;
    }
    try gl.errors.getError();
}
