//! CPU frame ownership shared by memory presenters. No graphics imports.
const std = @import("std");
const builtin = @import("builtin");
const Dmabuf = @import("Dmabuf.zig");
const Frame = @This();

// Keep the shared presenter's tag but make Unix descriptors impossible on Win32.
pub const Payload = union(enum) {
    pub const Memory = Frame.RgbaMemory;
    dmabuf: if (builtin.os.tag == .windows) noreturn else Dmabuf,
    memory: Memory,
    pub fn deinit(self: Payload) void {
        switch (self) {
            .dmabuf => |value| if (comptime builtin.os.tag == .windows) unreachable else value.deinit(),
            .memory => |value| value.deinit(),
        }
    }
};
pub const RgbaMemory = struct {
    width: u32,
    height: u32,
    pixels: []u8,
    alloc: std.mem.Allocator,
    /// Optional original allocation when pixels are a view after a wire header.
    /// Never shared IPC memory: ownership of a PRIVATE allocation is transferred.
    backing: ?[]u8 = null,
    pub fn deinit(self: RgbaMemory) void {
        self.alloc.free(self.backing orelse self.pixels);
    }
};

/// Clone validated premultiplied RGBA8/bottom-up bytes out of a reply allocation.
pub fn copyRgba(alloc: std.mem.Allocator, width: u32, height: u32, pixels: []const u8) !Payload {
    if (width == 0 or height == 0 or @as(u64, width) * height > std.math.maxInt(u64) / 4) return error.InvalidDimensions;
    if (@as(u64, width) * height * 4 != pixels.len) return error.InvalidPixelLength;
    return .{ .memory = .{ .width = width, .height = height, .pixels = try alloc.dupe(u8, pixels), .alloc = alloc } };
}

/// Takes an owned private allocation on success; leaves it untouched on error.
/// Caller may then free the emptied slice. Payload frees the ORIGINAL base,
/// never its interior pixel pointer. Does not adopt shared mappings/borrows.
pub fn takeRgba(alloc: std.mem.Allocator, width: u32, height: u32, owned: *[]u8, pixel_offset: usize) !Payload {
    if (width == 0 or height == 0 or @as(u64, width) * height > std.math.maxInt(u64) / 4) return error.InvalidDimensions;
    if (pixel_offset > owned.*.len) return error.InvalidPixelOffset;
    if (@as(u64, width) * height * 4 != owned.*.len - pixel_offset) return error.InvalidPixelLength;
    const backing = owned.*;
    owned.* = &.{};
    return .{ .memory = .{ .width = width, .height = height, .pixels = backing[pixel_offset..], .alloc = alloc, .backing = backing } };
}

test "CPU exported frame takes private reply base without interior free or copy" {
    const alloc = std.testing.allocator;
    var bytes = try alloc.dupe(u8, &.{ 99, 88, 1, 2, 3, 4 });
    errdefer alloc.free(bytes);
    const original = bytes.ptr;
    const value = try takeRgba(alloc, 1, 1, &bytes, 2);
    defer value.deinit();
    try std.testing.expectEqual(@as(usize, 0), bytes.len);
    alloc.free(bytes); // Simulates Reply.deinit after ownership transfer.
    try std.testing.expectEqual(original, value.memory.backing.?.ptr);
    try std.testing.expectEqual(original + 2, value.memory.pixels.ptr);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, value.memory.pixels);
}

test "CPU frame failed private reply adoption retains caller ownership" {
    const alloc = std.testing.allocator;
    var bytes = try alloc.alloc(u8, 8);
    defer alloc.free(bytes);
    const original = bytes.ptr;
    try std.testing.expectError(error.InvalidDimensions, takeRgba(alloc, 0, 1, &bytes, 4));
    try std.testing.expectError(error.InvalidDimensions, takeRgba(alloc, std.math.maxInt(u32), std.math.maxInt(u32), &bytes, 0));
    try std.testing.expectError(error.InvalidPixelOffset, takeRgba(alloc, 1, 1, &bytes, std.math.maxInt(usize)));
    try std.testing.expectError(error.InvalidPixelLength, takeRgba(alloc, 2, 1, &bytes, 4));
    try std.testing.expectEqual(original, bytes.ptr);
    try std.testing.expectEqual(@as(usize, 8), bytes.len);
}

test "CPU exported frame owns exact RGBA bytes without reply aliasing" {
    var bytes = [_]u8{ 1, 2, 3, 4 };
    const value = try Frame.copyRgba(std.testing.allocator, 1, 1, &bytes);
    defer value.deinit();
    bytes[0] = 99;
    try std.testing.expectEqual(@as(u8, 1), value.memory.pixels[0]);
    try std.testing.expectError(error.InvalidPixelLength, Frame.copyRgba(std.testing.allocator, 2, 1, &bytes));
}
