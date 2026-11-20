//! CPU-only candidate inline-Kitty resource record, NOT enabled on the wire yet.
//! Version1 is normalized straight-alpha RGBA8, tightly packed. IDs/generations
//! are application values, never pointers/GL handles. Borrowed decode views are
//! valid only while their containing packet lives; encode owns a complete copy.
const std = @import("std");
pub const header_bytes = 32;
const magic: u32 = 0x31474d49; // IMG1
pub const Limits = struct { dimension: u32 = 32768, bytes: u32 = 64 * 1024 * 1024 };
pub const Input = struct { id: u32, generation: u64, width: u32, height: u32, rgba: []const u8 };
pub const Owned = struct {
    alloc: std.mem.Allocator,
    bytes: []u8,
    pub fn deinit(self: *Owned) void {
        self.alloc.free(self.bytes);
        self.* = undefined;
    }
};
fn validate(input: Input, limits: Limits) !usize {
    if (limits.dimension == 0 or limits.dimension > 32768 or limits.bytes < header_bytes or limits.bytes > 64 * 1024 * 1024) return error.InvalidLimits;
    if (input.id == 0 or input.generation == 0) return error.InvalidIdentity;
    if (input.width == 0 or input.height == 0 or input.width > limits.dimension or input.height > limits.dimension) return error.InvalidDimensions;
    const pixels = @as(u64, input.width) * input.height * 4;
    if (pixels + header_bytes > limits.bytes) return error.ImageBudgetExceeded;
    if (pixels != input.rgba.len) return error.InvalidPixelLength;
    return @intCast(pixels + header_bytes);
}
pub fn encodeAlloc(alloc: std.mem.Allocator, input: Input, limits: Limits) !Owned {
    const length = try validate(input, limits); // All checks BEFORE allocation.
    const bytes = try alloc.alloc(u8, length);
    errdefer alloc.free(bytes);
    try encodeInto(bytes, input, limits);
    return .{ .alloc = alloc, .bytes = bytes };
}
pub fn encodedLength(input: Input, limits: Limits) !usize {
    return validate(input, limits);
}
/// Destination must not alias the source pixels. Aggregate codecs use this to
/// avoid a second full-sized temporary allocation for each image.
pub fn encodeInto(bytes: []u8, input: Input, limits: Limits) !void {
    if (bytes.len != try validate(input, limits)) return error.InvalidRecordLength;
    std.mem.writeInt(u32, bytes[0..4], magic, .little);
    std.mem.writeInt(u16, bytes[4..6], 1, .little);
    std.mem.writeInt(u16, bytes[6..8], header_bytes, .little);
    std.mem.writeInt(u32, bytes[8..12], input.id, .little);
    std.mem.writeInt(u32, bytes[12..16], input.width, .little);
    std.mem.writeInt(u32, bytes[16..20], input.height, .little);
    std.mem.writeInt(u32, bytes[20..24], @intCast(input.rgba.len), .little);
    std.mem.writeInt(u64, bytes[24..32], input.generation, .little);
    @memcpy(bytes[header_bytes..], input.rgba);
}
pub fn decode(bytes: []const u8, limits: Limits) !Input {
    if (bytes.len < header_bytes) return error.TruncatedImage;
    if (std.mem.readInt(u32, bytes[0..4], .little) != magic or std.mem.readInt(u16, bytes[4..6], .little) != 1 or std.mem.readInt(u16, bytes[6..8], .little) != header_bytes) return error.InvalidImageHeader;
    if (@as(u64, std.mem.readInt(u32, bytes[20..24], .little)) + header_bytes != bytes.len) return error.InvalidPixelLength;
    const input: Input = .{
        .id = std.mem.readInt(u32, bytes[8..12], .little),
        .width = std.mem.readInt(u32, bytes[12..16], .little),
        .height = std.mem.readInt(u32, bytes[16..20], .little),
        .generation = std.mem.readInt(u64, bytes[24..32], .little),
        .rgba = bytes[header_bytes..],
    };
    _ = try validate(input, limits);
    return input;
}
test "image resource owns pixels and keeps u64 generation without wire pointers" {
    var pixels = [_]u8{ 1, 2, 3, 255 };
    var packet = try encodeAlloc(std.testing.allocator, .{ .id = 7, .generation = 0x1122334455667788, .width = 1, .height = 1, .rgba = &pixels }, .{});
    defer packet.deinit();
    pixels[0] = 99;
    const view = try decode(packet.bytes, .{});
    try std.testing.expectEqual(@as(u8, 1), view.rgba[0]);
    try std.testing.expectEqual(@as(u64, 0x1122334455667788), view.generation);
    try std.testing.expectEqual(@as(u8, 0x88), packet.bytes[24]);
}
test "image resource rejects truncation version length and identity" {
    var packet = try encodeAlloc(std.testing.allocator, .{ .id = 7, .generation = 1, .width = 1, .height = 1, .rgba = &.{ 1, 2, 3, 4 } }, .{});
    defer packet.deinit();
    try std.testing.expectError(error.TruncatedImage, decode(packet.bytes[0..31], .{}));
    try std.testing.expectError(error.InvalidPixelLength, decode(packet.bytes[0..35], .{}));
    packet.bytes[4] = 2;
    try std.testing.expectError(error.InvalidImageHeader, decode(packet.bytes, .{}));
    packet.bytes[4] = 1;
    @memset(packet.bytes[24..32], 0);
    try std.testing.expectError(error.InvalidIdentity, decode(packet.bytes, .{}));
}
test "image resource checks multiplication and total packet budget before allocation" {
    const input: Input = .{ .id = 1, .generation = 1, .width = 32768, .height = 32768, .rgba = &.{} };
    try std.testing.expectError(error.ImageBudgetExceeded, encodeAlloc(std.testing.allocator, input, .{}));
    try std.testing.expectError(error.InvalidLimits, encodeAlloc(std.testing.allocator, input, .{ .dimension = 0 }));
}
fn allocationCase(alloc: std.mem.Allocator) !void {
    var packet = try encodeAlloc(alloc, .{ .id = 1, .generation = 2, .width = 1, .height = 1, .rgba = &.{ 0, 0, 0, 255 } }, .{});
    defer packet.deinit();
    _ = try decode(packet.bytes, .{});
}
test "image resource frees every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
