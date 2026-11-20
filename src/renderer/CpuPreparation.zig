//! Owned CPU-only renderer preparation. No GraphicsAPI/device/surface access.
//! Metrics are a caller-owned snapshot; ownership of the shaper transfers only
//! after renderer initialization succeeds, otherwise deinit cleans it up.
const CpuPreparation = @This();
const std = @import("std");
const font = @import("../font/main.zig");

shaper: ?font.Shaper,
metrics: font.Metrics,

pub fn init(alloc: std.mem.Allocator, options: font.shape.Options, metrics: font.Metrics) !CpuPreparation {
    return .{ .shaper = try font.Shaper.init(alloc, options), .metrics = metrics };
}

pub fn deinit(self: *CpuPreparation) void {
    if (self.shaper) |*shaper| shaper.deinit();
    self.shaper = null;
}

pub fn takeShaper(self: *CpuPreparation) font.Shaper {
    const result = self.shaper.?;
    self.shaper = null;
    return result;
}

test "CpuPreparation snapshots CPU metrics without a graphics device" {
    var metrics = std.mem.zeroes(font.Metrics);
    metrics.cell_width = 17;
    metrics.cell_height = 23;
    var prepared = try init(std.testing.allocator, .{}, metrics);
    defer prepared.deinit();
    metrics.cell_width = 99;
    try std.testing.expectEqual(@as(u32, 17), prepared.metrics.cell_width);
    try std.testing.expectEqual(@as(u32, 23), prepared.metrics.cell_height);
    try std.testing.expect(prepared.shaper != null);
}

test "CpuPreparation transfers shaper exactly once and permits empty cleanup" {
    var prepared = try init(std.testing.allocator, .{}, std.mem.zeroes(font.Metrics));
    defer prepared.deinit();
    var shaper = prepared.takeShaper();
    defer shaper.deinit();
    try std.testing.expect(prepared.shaper == null);
    prepared.deinit();
    prepared.deinit();
}

fn allocationCase(alloc: std.mem.Allocator) !void {
    var prepared = try init(alloc, .{ .features = &.{ "liga", "-calt" } }, std.mem.zeroes(font.Metrics));
    defer prepared.deinit();
}

test "CpuPreparation releases allocations on preparation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
