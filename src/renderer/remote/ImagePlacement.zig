//! CPU-only candidate placement record. Not enabled in submit_frame yet.
//! Fixed56-byte LE record, no native struct/pointer serialization. The eventual
//! aggregate must resolve image identity and preserve z/image-ID ordering.
const std = @import("std");
const Resource = @import("ImageResource.zig");
const Placement = @This();
pub const record_bytes = 56;
image_id: u32,
generation: u64,
x: i32,
y: i32,
z: i32,
width: u32,
height: u32,
cell_offset_x: u32 = 0,
cell_offset_y: u32 = 0,
source_x: u32,
source_y: u32,
source_width: u32,
source_height: u32,

pub fn validate(self: Placement, image: Resource.Input, dimension: u32) !void {
    if (dimension == 0 or dimension > 32768) return error.InvalidPlacementLimit;
    if (self.image_id == 0 or self.generation == 0 or self.image_id != image.id or self.generation != image.generation) return error.StaleImageResource;
    if (image.width == 0 or image.height == 0 or image.width > dimension or image.height > dimension or self.width == 0 or self.height == 0 or self.width > dimension or self.height > dimension) return error.InvalidPlacementDimensions;
    if (self.cell_offset_x > dimension or self.cell_offset_y > dimension) return error.InvalidCellOffset;
    if (self.source_width == 0 or self.source_height == 0 or @as(u64, self.source_x) + self.source_width > image.width or @as(u64, self.source_y) + self.source_height > image.height) return error.InvalidSourceCrop;
}
pub fn encode(self: Placement, image: Resource.Input, dimension: u32) ![record_bytes]u8 {
    try self.validate(image, dimension);
    var bytes: [record_bytes]u8 = undefined;
    std.mem.writeInt(u32, bytes[0..4], self.image_id, .little);
    std.mem.writeInt(u64, bytes[4..12], self.generation, .little);
    for ([_]i32{ self.x, self.y, self.z }, 0..) |value, index| {
        const at = 12 + index * 4;
        std.mem.writeInt(i32, bytes[at..][0..4], value, .little);
    }
    for ([_]u32{ self.width, self.height, self.cell_offset_x, self.cell_offset_y, self.source_x, self.source_y, self.source_width, self.source_height }, 0..) |value, index| {
        const at = 24 + index * 4;
        std.mem.writeInt(u32, bytes[at..][0..4], value, .little);
    }
    return bytes;
}
pub fn decode(bytes: []const u8, image: Resource.Input, dimension: u32) !Placement {
    if (bytes.len != record_bytes) return error.InvalidPlacementLength;
    const self: Placement = .{
        .image_id = std.mem.readInt(u32, bytes[0..4], .little),
        .generation = std.mem.readInt(u64, bytes[4..12], .little),
        .x = std.mem.readInt(i32, bytes[12..16], .little),
        .y = std.mem.readInt(i32, bytes[16..20], .little),
        .z = std.mem.readInt(i32, bytes[20..24], .little),
        .width = std.mem.readInt(u32, bytes[24..28], .little),
        .height = std.mem.readInt(u32, bytes[28..32], .little),
        .cell_offset_x = std.mem.readInt(u32, bytes[32..36], .little),
        .cell_offset_y = std.mem.readInt(u32, bytes[36..40], .little),
        .source_x = std.mem.readInt(u32, bytes[40..44], .little),
        .source_y = std.mem.readInt(u32, bytes[44..48], .little),
        .source_width = std.mem.readInt(u32, bytes[48..52], .little),
        .source_height = std.mem.readInt(u32, bytes[52..56], .little),
    };
    try self.validate(image, dimension);
    return self;
}
// Metadata fixtures only: the aggregate will obtain these from decoded,
// fully-validated ImageResource bytes, not upload these empty pixel views.
const image_meta: Resource.Input = .{ .id = 9, .generation = 3, .width = 4, .height = 3, .rgba = &.{} };
const fixture: Placement = .{ .image_id = 9, .generation = 3, .x = -123, .y = -5, .z = std.math.minInt(i32), .width = 12, .height = 8, .source_x = 2, .source_y = 1, .source_width = 2, .source_height = 2 };
test "placement preserves signed clipping coordinates z bands and exact crop" {
    const bytes = try fixture.encode(image_meta, 1024);
    const decoded = try decode(&bytes, image_meta, 1024);
    try std.testing.expect(std.meta.eql(fixture, decoded));
    try std.testing.expectEqual(@as(u8, 0x85), bytes[12]); // -123 LE
    try std.testing.expectEqual(@as(u8, 0x80), bytes[23]); // minInt i32 LE
}
test "placement requires exact resource generation independently of geometry" {
    var next = image_meta;
    next.generation += 1;
    try std.testing.expectError(error.StaleImageResource, fixture.encode(next, 1024));
    next = image_meta;
    next.id += 1;
    try std.testing.expectError(error.StaleImageResource, fixture.encode(next, 1024));
}
test "placement crop addition cannot wrap or escape resource" {
    var invalid = fixture;
    invalid.source_x = std.math.maxInt(u32);
    try std.testing.expectError(error.InvalidSourceCrop, invalid.encode(image_meta, 1024));
    invalid = fixture;
    invalid.source_height = 0;
    try std.testing.expectError(error.InvalidSourceCrop, invalid.encode(image_meta, 1024));
}
test "placement rejects truncated forged generation and oversized destination" {
    var bytes = try fixture.encode(image_meta, 1024);
    try std.testing.expectError(error.InvalidPlacementLength, decode(bytes[0..55], image_meta, 1024));
    bytes[4] = 4;
    try std.testing.expectError(error.StaleImageResource, decode(&bytes, image_meta, 1024));
    var invalid = fixture;
    invalid.width = 32769;
    try std.testing.expectError(error.InvalidPlacementDimensions, invalid.encode(image_meta, 32768));
}
