//! Unwired CPU-only inline-Kitty snapshot candidate. Full resources + placements;
//! resources sorted by ID, placements by z then ID. No local texture states.
const std = @import("std");
const Resource = @import("ImageResource.zig");
const Placement = @import("ImagePlacement.zig");
pub const header_bytes = 32;
const magic: u32 = 0x31534d49; // IMS1
pub const Limits = struct { images: u32 = 256, placements: u32 = 4096, dimension: u32 = 32768, bytes: u32 = 64 * 1024 * 1024 };
pub const Input = struct { images: []const Resource.Input, placements: []const Placement, cell_size: [2]f32 };
pub fn validateLimits(limits: Limits, cell: [2]f32) !void {
    if (limits.images == 0 or limits.images > 4096 or limits.placements == 0 or limits.placements > 65536 or limits.dimension == 0 or limits.dimension > 32768 or limits.bytes < header_bytes or limits.bytes > 64 * 1024 * 1024) return error.InvalidSnapshotLimits;
    for (cell) |value| if (!std.math.isFinite(value) or value <= 0 or value > @as(f32, @floatFromInt(limits.dimension))) return error.InvalidCellSize;
}
fn validateOffset(p: Placement, cell: [2]f32) !void {
    if (@as(f32, @floatFromInt(p.cell_offset_x)) > cell[0] or @as(f32, @floatFromInt(p.cell_offset_y)) > cell[1]) return error.CellOffsetOutOfBounds;
}
fn ordered(a: Placement, b: Placement) bool {
    return a.z < b.z or (a.z == b.z and a.image_id <= b.image_id);
}
fn lookup(images: []const Resource.Input, id: u32) !Resource.Input {
    var lo: usize = 0;
    var hi = images.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (images[mid].id == id) return images[mid];
        if (images[mid].id < id) lo = mid + 1 else hi = mid;
    }
    return error.MissingImageResource;
}
pub fn encodeAlloc(alloc: std.mem.Allocator, input: Input, limits: Limits) !Resource.Owned {
    try validateLimits(limits, input.cell_size);
    if (input.images.len > limits.images or input.placements.len > limits.placements) return error.SnapshotCountExceeded;
    var resource_bytes: u64 = 0;
    for (input.images, 0..) |image, index| {
        if (index != 0 and input.images[index - 1].id >= image.id) return error.ImageOrderInvalid;
        resource_bytes += try Resource.encodedLength(image, .{ .dimension = limits.dimension, .bytes = limits.bytes });
    }
    const total = header_bytes + @as(u64, input.images.len) * 4 + resource_bytes + @as(u64, input.placements.len) * Placement.record_bytes;
    if (total > limits.bytes) return error.SnapshotBudgetExceeded;
    for (input.placements, 0..) |p, index| {
        try p.validate(try lookup(input.images, p.image_id), limits.dimension);
        try validateOffset(p, input.cell_size);
        if (index != 0 and !ordered(input.placements[index - 1], p)) return error.PlacementOrderInvalid;
    }
    // Counts, all resources, crops, identity, ordering and aggregate budget have
    // been checked before the SINGLE output allocation. No per-image temporary.
    const bytes = try alloc.alloc(u8, @intCast(total));
    errdefer alloc.free(bytes);
    std.mem.writeInt(u32, bytes[0..4], magic, .little);
    std.mem.writeInt(u16, bytes[4..6], 1, .little);
    std.mem.writeInt(u16, bytes[6..8], header_bytes, .little);
    std.mem.writeInt(u32, bytes[8..12], @intCast(input.images.len), .little);
    std.mem.writeInt(u32, bytes[12..16], @intCast(input.placements.len), .little);
    std.mem.writeInt(u32, bytes[16..20], @intCast(resource_bytes), .little);
    std.mem.writeInt(u32, bytes[20..24], @intCast(total), .little);
    std.mem.writeInt(u32, bytes[24..28], @bitCast(input.cell_size[0]), .little);
    std.mem.writeInt(u32, bytes[28..32], @bitCast(input.cell_size[1]), .little);
    const resource_start = header_bytes + input.images.len * 4;
    var at = resource_start;
    for (input.images, 0..) |image, index| {
        std.mem.writeInt(u32, bytes[header_bytes + index * 4 ..][0..4], @intCast(at - resource_start), .little);
        const length = try Resource.encodedLength(image, .{ .dimension = limits.dimension, .bytes = limits.bytes });
        try Resource.encodeInto(bytes[at..][0..length], image, .{ .dimension = limits.dimension, .bytes = limits.bytes });
        at += length;
    }
    for (input.placements) |p| {
        const record = try p.encode(try lookup(input.images, p.image_id), limits.dimension);
        @memcpy(bytes[at..][0..Placement.record_bytes], &record);
        at += Placement.record_bytes;
    }
    return .{ .alloc = alloc, .bytes = bytes };
}
pub const View = struct {
    bytes: []const u8,
    image_count: u32,
    placement_count: u32,
    resource_bytes: u32,
    cell_size: [2]f32,
    limits: Limits,
    pub fn image(self: View, index: usize) !Resource.Input {
        if (index >= self.image_count) return error.IndexOutOfBounds;
        const begin = std.mem.readInt(u32, self.bytes[header_bytes + index * 4 ..][0..4], .little);
        const end = if (index + 1 < self.image_count) std.mem.readInt(u32, self.bytes[header_bytes + (index + 1) * 4 ..][0..4], .little) else self.resource_bytes;
        if (begin >= end or end > self.resource_bytes or (index == 0 and begin != 0)) return error.InvalidImageOffset;
        const base = header_bytes + @as(usize, self.image_count) * 4;
        return Resource.decode(self.bytes[base + begin .. base + end], .{ .dimension = self.limits.dimension, .bytes = self.limits.bytes });
    }
    fn find(self: View, id: u32) !Resource.Input {
        var lo: usize = 0;
        var hi: usize = self.image_count;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const item = try self.image(mid);
            if (item.id == id) return item;
            if (item.id < id) lo = mid + 1 else hi = mid;
        }
        return error.MissingImageResource;
    }
    pub fn placement(self: View, index: usize) !Placement {
        if (index >= self.placement_count) return error.IndexOutOfBounds;
        const at = header_bytes + @as(usize, self.image_count) * 4 + self.resource_bytes + index * Placement.record_bytes;
        const record = self.bytes[at..][0..Placement.record_bytes];
        const id = std.mem.readInt(u32, record[0..4], .little);
        const p = try Placement.decode(record, try self.find(id), self.limits.dimension);
        try validateOffset(p, self.cell_size);
        return p;
    }
};
pub fn decode(bytes: []const u8, limits: Limits) !View {
    if (bytes.len < header_bytes) return error.TruncatedSnapshot;
    if (std.mem.readInt(u32, bytes[0..4], .little) != magic or std.mem.readInt(u16, bytes[4..6], .little) != 1 or std.mem.readInt(u16, bytes[6..8], .little) != header_bytes) return error.InvalidSnapshotHeader;
    const view: View = .{ .bytes = bytes, .image_count = std.mem.readInt(u32, bytes[8..12], .little), .placement_count = std.mem.readInt(u32, bytes[12..16], .little), .resource_bytes = std.mem.readInt(u32, bytes[16..20], .little), .cell_size = .{ @bitCast(std.mem.readInt(u32, bytes[24..28], .little)), @bitCast(std.mem.readInt(u32, bytes[28..32], .little)) }, .limits = limits };
    try validateLimits(limits, view.cell_size);
    if (view.image_count > limits.images or view.placement_count > limits.placements) return error.SnapshotCountExceeded;
    const total = header_bytes + @as(u64, view.image_count) * 4 + view.resource_bytes + @as(u64, view.placement_count) * Placement.record_bytes;
    if (total > limits.bytes) return error.SnapshotBudgetExceeded;
    if (total != bytes.len or total != std.mem.readInt(u32, bytes[20..24], .little) or (view.image_count == 0 and view.resource_bytes != 0)) return error.InvalidSnapshotLength;
    var previous_id: u32 = 0;
    for (0..view.image_count) |index| {
        const item = try view.image(index);
        if (item.id <= previous_id) return error.ImageOrderInvalid;
        previous_id = item.id;
    }
    var previous: ?Placement = null;
    for (0..view.placement_count) |index| {
        const p = try view.placement(index);
        if (previous) |old| if (!ordered(old, p)) return error.PlacementOrderInvalid;
        previous = p;
    }
    return view;
}

const fixture_images = [_]Resource.Input{ .{ .id = 1, .generation = 2, .width = 1, .height = 1, .rgba = &.{ 255, 0, 0, 255 } }, .{ .id = 9, .generation = 3, .width = 1, .height = 1, .rgba = &.{ 0, 255, 0, 255 } } };
const fixture_placements = [_]Placement{ .{ .image_id = 9, .generation = 3, .x = -1, .y = 0, .z = std.math.minInt(i32), .width = 4, .height = 4, .source_x = 0, .source_y = 0, .source_width = 1, .source_height = 1 }, .{ .image_id = 1, .generation = 2, .x = 1, .y = 0, .z = 1, .width = 4, .height = 4, .source_x = 0, .source_y = 0, .source_width = 1, .source_height = 1 } };
const fixture: Input = .{ .images = &fixture_images, .placements = &fixture_placements, .cell_size = .{ 4, 4 } };
test "image snapshot resolves sorted resources separately from z-ordered placements" {
    var owned = try encodeAlloc(std.testing.allocator, fixture, .{});
    defer owned.deinit();
    const view = try decode(owned.bytes, .{});
    try std.testing.expectEqual(@as(u32, 1), (try view.image(0)).id);
    try std.testing.expectEqual(@as(i32, -1), (try view.placement(0)).x);
    try std.testing.expectEqual(@as(u32, 9), (try view.placement(0)).image_id);
}
test "image snapshot rejects aggregate budget offsets truncation and forged counts" {
    try std.testing.expectError(error.SnapshotBudgetExceeded, encodeAlloc(std.testing.allocator, fixture, .{ .bytes = 128 }));
    var owned = try encodeAlloc(std.testing.allocator, fixture, .{});
    defer owned.deinit();
    try std.testing.expectError(error.InvalidSnapshotLength, decode(owned.bytes[0 .. owned.bytes.len - 1], .{}));
    owned.bytes[32] = 1;
    try std.testing.expectError(error.InvalidImageOffset, decode(owned.bytes, .{}));
    owned.bytes[32] = 0;
    std.mem.writeInt(u32, owned.bytes[8..12], std.math.maxInt(u32), .little);
    try std.testing.expectError(error.SnapshotCountExceeded, decode(owned.bytes, .{}));
}
test "image snapshot rejects missing stale duplicate unordered and bad-cell placement" {
    var placements = fixture_placements;
    var input = fixture;
    input.placements = &placements;
    placements[0].image_id = 7;
    try std.testing.expectError(error.MissingImageResource, encodeAlloc(std.testing.allocator, input, .{}));
    placements = fixture_placements;
    placements[0].generation = 2;
    try std.testing.expectError(error.StaleImageResource, encodeAlloc(std.testing.allocator, input, .{}));
    placements = fixture_placements;
    placements[0].cell_offset_x = 5;
    try std.testing.expectError(error.CellOffsetOutOfBounds, encodeAlloc(std.testing.allocator, input, .{}));
    placements = .{ fixture_placements[1], fixture_placements[0] };
    try std.testing.expectError(error.PlacementOrderInvalid, encodeAlloc(std.testing.allocator, input, .{}));
    input = fixture;
    input.images = &.{ fixture_images[0], fixture_images[0] };
    try std.testing.expectError(error.ImageOrderInvalid, encodeAlloc(std.testing.allocator, input, .{}));
}
test "empty image snapshot represents removal without phantom resources" {
    var owned = try encodeAlloc(std.testing.allocator, .{ .images = &.{}, .placements = &.{}, .cell_size = .{ 4, 4 } }, .{});
    defer owned.deinit();
    const view = try decode(owned.bytes, .{});
    try std.testing.expectEqual(@as(u32, 0), view.image_count);
}
fn allocationCase(alloc: std.mem.Allocator) !void {
    var owned = try encodeAlloc(alloc, fixture, .{});
    defer owned.deinit();
    _ = try decode(owned.bytes, .{});
}
test "image snapshot frees every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
