//! CPU-only fence. Caller owns the draw lock for capture/advance/commit.
const std = @import("std");
const Epoch = @This();
value: std.atomic.Value(u64) = .init(1),
/// Atomic observation may be used without taking draw_mutex, but all mutations
/// and frame capture/commit still require that mutex for the associated state.
pub fn capture(self: *const Epoch) u64 {
    return self.value.load(.acquire);
}
pub fn advance(self: *Epoch) !void {
    const next = std.math.add(u64, self.capture(), 1) catch return error.ViewportEpochExhausted;
    self.value.store(next, .release);
}
pub fn accepts(self: *const Epoch, captured: u64, realized: bool) bool {
    return realized and captured != 0 and captured == self.capture();
}
test "viewport current frame accepted, hidden and zero rejected" {
    const epoch: Epoch = .{};
    try std.testing.expect(epoch.accepts(1, true));
    try std.testing.expect(!epoch.accepts(1, false));
    try std.testing.expect(!epoch.accepts(0, true));
}
test "viewport A to B to A never resurrects old frame" {
    var epoch: Epoch = .{};
    const captured = epoch.capture();
    try epoch.advance();
    try epoch.advance();
    try std.testing.expect(!epoch.accepts(captured, true));
    try std.testing.expect(epoch.accepts(epoch.capture(), true));
}
test "viewport epoch exhaustion fails without reusing zero" {
    var epoch: Epoch = .{ .value = .init(std.math.maxInt(u64)) };
    try std.testing.expectError(error.ViewportEpochExhausted, epoch.advance());
    try std.testing.expectEqual(std.math.maxInt(u64), epoch.capture());
}
