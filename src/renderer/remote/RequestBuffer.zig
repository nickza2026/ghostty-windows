//! Single-owner private serialization scratch. Never owns response/frame bytes.
const std = @import("std");
const Self = @This();
bytes: []u8 = &.{},

/// Returns exactly needed bytes; retained capacity never exceeds maximum.
/// Failed growth preserves the old allocation. Contents need not survive growth.
pub fn ensure(self: *Self, alloc: std.mem.Allocator, needed: usize, maximum: usize) ![]u8 {
    if (needed > maximum or self.bytes.len > maximum) return error.RequestBufferLimit;
    if (needed <= self.bytes.len) return self.bytes[0..needed];
    const doubled = std.math.mul(usize, self.bytes.len, 2) catch maximum;
    const capacity = @min(maximum, @max(needed, @max(@as(usize, 256), doubled)));
    const replacement = try alloc.alloc(u8, capacity);
    alloc.free(self.bytes);
    self.bytes = replacement;
    return self.bytes[0..needed];
}
pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    alloc.free(self.bytes);
    self.bytes = &.{};
}

test "request scratch reuses exact slices, grows within bound, cleans repeatedly" {
    var buffer: Self = .{};
    defer buffer.deinit(std.testing.allocator);
    const first = try buffer.ensure(std.testing.allocator, 48, 1000);
    const original = first.ptr;
    @memset(first, 99);
    const smaller = try buffer.ensure(std.testing.allocator, 12, 1000);
    try std.testing.expectEqual(original, smaller.ptr);
    try std.testing.expectEqual(@as(usize, 12), smaller.len);
    try std.testing.expectEqual(@as(usize, 256), buffer.bytes.len);
    _ = try buffer.ensure(std.testing.allocator, 600, 1000);
    _ = try buffer.ensure(std.testing.allocator, 900, 1000);
    try std.testing.expectEqual(@as(usize, 1000), buffer.bytes.len);
    try std.testing.expectError(error.RequestBufferLimit, buffer.ensure(std.testing.allocator, 1001, 1000));
    buffer.deinit(std.testing.allocator);
    buffer.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), buffer.bytes.len);
}

test "request scratch initial and growth OOM preserve ownership and reuse" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var empty: Self = .{};
    defer empty.deinit(failing.allocator());
    try std.testing.expectError(error.OutOfMemory, empty.ensure(failing.allocator(), 48, 1024));
    try std.testing.expectEqual(@as(usize, 0), empty.bytes.len);
    var growth = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var buffer: Self = .{};
    defer buffer.deinit(growth.allocator());
    const first = try buffer.ensure(growth.allocator(), 48, 1024);
    @memset(first, 77);
    const original = first.ptr;
    try std.testing.expectError(error.OutOfMemory, buffer.ensure(growth.allocator(), 257, 1024));
    try std.testing.expectEqual(original, buffer.bytes.ptr);
    try std.testing.expectEqual(@as(usize, 256), buffer.bytes.len);
    const reused = try buffer.ensure(growth.allocator(), 48, 1024);
    for (reused) |byte| try std.testing.expectEqual(@as(u8, 77), byte);
}
