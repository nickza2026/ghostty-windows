//! Candidate text+inline-image envelope. NOT negotiated/enabled by the worker.
//! Components remain immutable full snapshots. CPU decode allocates nothing;
//! encode owns one copy after combined budget and cross-component validation.
const std = @import("std");
const Text = @import("TextFrame.zig");
const Images = @import("ImageSnapshot.zig");
const Resource = @import("ImageResource.zig");
pub const header_bytes = 24;
const magic: u32 = 0x3142494b; // KIB1
pub const Limits = struct {
    payload: u32 = 64 * 1024 * 1024,
    text: Text.Limits = .{ .dimension = 32768, .atlas_dimension = 32768, .cells = 1024 * 1024, .bytes = 64 * 1024 * 1024 },
    images: Images.Limits = .{},
};
pub const View = struct { text: Text.Decoded, images: Images.View };
fn length(text: usize, images: usize, limits: Limits) !usize {
    if (limits.payload < header_bytes or limits.payload > 64 * 1024 * 1024) return error.InvalidImageFrameLimit;
    // Check individually before adding, including on 32-bit hosts/forged sizes.
    if (text > limits.payload or images > limits.payload) return error.ImageFrameBudgetExceeded;
    const total = header_bytes + @as(u64, text) + @as(u64, images);
    if (total > limits.payload) return error.ImageFrameBudgetExceeded;
    return @intCast(total);
}
fn components(text: []const u8, images: []const u8, limits: Limits) !View {
    const t = try Text.decode(text, limits.text);
    const i = try Images.decode(images, limits.images);
    if (!std.meta.eql(t.uniforms.cell_size, i.cell_size)) return error.ImageFrameCellMismatch;
    return .{ .text = t, .images = i };
}
pub fn encodeAlloc(alloc: std.mem.Allocator, text: []const u8, images: []const u8, limits: Limits) !Resource.Owned {
    const total = try length(text.len, images.len, limits);
    _ = try components(text, images, limits); // BEFORE allocation/copy.
    const bytes = try alloc.alloc(u8, total);
    std.mem.writeInt(u32, bytes[0..4], magic, .little);
    std.mem.writeInt(u16, bytes[4..6], 1, .little);
    std.mem.writeInt(u16, bytes[6..8], header_bytes, .little);
    std.mem.writeInt(u32, bytes[8..12], @intCast(text.len), .little);
    std.mem.writeInt(u32, bytes[12..16], @intCast(images.len), .little);
    std.mem.writeInt(u32, bytes[16..20], @intCast(total), .little);
    std.mem.writeInt(u32, bytes[20..24], 0, .little);
    @memcpy(bytes[header_bytes..][0..text.len], text);
    @memcpy(bytes[header_bytes + text.len ..], images);
    return .{ .alloc = alloc, .bytes = bytes };
}
pub fn decode(bytes: []const u8, limits: Limits) !View {
    if (bytes.len < header_bytes) return error.TruncatedImageFrame;
    if (std.mem.readInt(u32, bytes[0..4], .little) != magic or std.mem.readInt(u16, bytes[4..6], .little) != 1 or std.mem.readInt(u16, bytes[6..8], .little) != header_bytes) return error.InvalidImageFrameHeader;
    if (std.mem.readInt(u32, bytes[20..24], .little) != 0) return error.InvalidImageFrameFlags;
    const text_len = std.mem.readInt(u32, bytes[8..12], .little);
    const image_len = std.mem.readInt(u32, bytes[12..16], .little);
    const total = try length(text_len, image_len, limits);
    if (total != bytes.len or total != std.mem.readInt(u32, bytes[16..20], .little)) return error.InvalidImageFrameLength;
    return components(bytes[header_bytes..][0..text_len], bytes[header_bytes + text_len ..], limits);
}
// CPU validation fixtures only; real visual/GPU parity is a separate gate.
fn textFixture(alloc: std.mem.Allocator) !Text.Owned {
    var uniforms = std.mem.zeroes(@import("../GlslData.zig").Uniforms);
    uniforms.screen_size = .{ 8, 4 };
    uniforms.cell_size = .{ 4, 4 };
    uniforms.grid_size = .{ 2, 1 };
    return Text.encodeAlloc(alloc, .{ .width = 8, .height = 4, .blending = .native, .uniforms = uniforms, .background = &.{ .{ 12, 12, 12, 255 }, .{ 1, 2, 3, 255 } }, .foreground_rows = &.{}, .grayscale = .{ .size = 1, .bytes = &.{255} }, .color = .{ .size = 1, .bytes = &.{ 255, 255, 255, 255 } } }, .{ .dimension = 1024, .atlas_dimension = 512, .cells = 16, .bytes = 4096 });
}
fn imageFixture(alloc: std.mem.Allocator, cell: [2]f32) !Resource.Owned {
    return Images.encodeAlloc(alloc, .{ .images = &.{.{ .id = 1, .generation = 2, .width = 1, .height = 1, .rgba = &.{ 255, 0, 0, 255 } }}, .placements = &.{.{ .image_id = 1, .generation = 2, .x = -1, .y = 0, .z = 1, .width = 4, .height = 4, .source_x = 0, .source_y = 0, .source_width = 1, .source_height = 1 }}, .cell_size = cell }, .{});
}
test "image frame owns both components and validates shared cell geometry" {
    var text = try textFixture(std.testing.allocator);
    defer text.deinit();
    var images = try imageFixture(std.testing.allocator, .{ 4, 4 });
    defer images.deinit();
    var owned = try encodeAlloc(std.testing.allocator, text.bytes, images.bytes, .{});
    defer owned.deinit();
    text.bytes[0] = 0;
    images.bytes[0] = 0;
    const view = try decode(owned.bytes, .{});
    try std.testing.expectEqual(@as(u32, 8), view.text.width);
    try std.testing.expectEqual(@as(u8, 255), (try view.images.image(0)).rgba[0]);
}
test "image frame combined budget includes header and both valid components" {
    var text = try textFixture(std.testing.allocator);
    defer text.deinit();
    var images = try imageFixture(std.testing.allocator, .{ 4, 4 });
    defer images.deinit();
    try std.testing.expectError(error.ImageFrameBudgetExceeded, encodeAlloc(std.testing.allocator, text.bytes, images.bytes, .{ .payload = @intCast(text.bytes.len + images.bytes.len) }));
}
test "image frame rejects mismatched cells forged lengths flags and truncation" {
    var text = try textFixture(std.testing.allocator);
    defer text.deinit();
    var wrong = try imageFixture(std.testing.allocator, .{ 8, 4 });
    defer wrong.deinit();
    try std.testing.expectError(error.ImageFrameCellMismatch, encodeAlloc(std.testing.allocator, text.bytes, wrong.bytes, .{}));
    var images = try imageFixture(std.testing.allocator, .{ 4, 4 });
    defer images.deinit();
    var owned = try encodeAlloc(std.testing.allocator, text.bytes, images.bytes, .{});
    defer owned.deinit();
    try std.testing.expectError(error.InvalidImageFrameLength, decode(owned.bytes[0 .. owned.bytes.len - 1], .{}));
    owned.bytes[20] = 1;
    try std.testing.expectError(error.InvalidImageFrameFlags, decode(owned.bytes, .{}));
    owned.bytes[20] = 0;
    std.mem.writeInt(u32, owned.bytes[8..12], std.math.maxInt(u32), .little);
    try std.testing.expectError(error.ImageFrameBudgetExceeded, decode(owned.bytes, .{}));
}
fn allocationCase(alloc: std.mem.Allocator) !void {
    var text = try textFixture(alloc);
    defer text.deinit();
    var images = try imageFixture(alloc, .{ 4, 4 });
    defer images.deinit();
    var owned = try encodeAlloc(alloc, text.bytes, images.bytes, .{});
    defer owned.deinit();
    _ = try decode(owned.bytes, .{});
}
test "image frame cleans allocation failures across component and outer ownership" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
