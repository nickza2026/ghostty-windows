//! Win32 payload decoding only. Coordinates are signed physical pixels.
const std = @import("std");
pub const Point = struct { x: i32, y: i32 };
pub const Button = enum(u8) { left = 1, right = 2, middle = 3, four = 4, five = 5 };
pub const Event = union(enum) {
    move: Point,
    button: struct { pos: Point, button: Button, pressed: bool },
    wheel: struct { pos: Point, delta: i16, horizontal: bool },
    cancel,
    leave,
};
pub fn point(lp: isize) Point {
    const bits: usize = @bitCast(lp);
    return .{ .x = @as(i16, @bitCast(@as(u16, @truncate(bits)))), .y = @as(i16, @bitCast(@as(u16, @truncate(bits >> 16)))) };
}
pub fn decode(msg: u32, wp: usize, lp: isize) ?Event {
    return switch (msg) {
        0x0200 => .{ .move = point(lp) },
        0x0201...0x0209, 0x020b...0x020d => .{ .button = .{
            .pos = point(lp),
            .button = switch (msg) {
                0x0201...0x0203 => .left,
                0x0204...0x0206 => .right,
                0x0207...0x0209 => .middle,
                else => switch ((wp >> 16) & 0xffff) {
                    1 => .four,
                    2 => .five,
                    else => return null,
                },
            },
            .pressed = switch (msg) {
                0x0202, 0x0205, 0x0208, 0x020c => false,
                else => true,
            },
        } },
        0x020a, 0x020e => .{ .wheel = .{ .pos = point(lp), .delta = @bitCast(@as(u16, @truncate(wp >> 16))), .horizontal = msg == 0x020e } },
        0x001f, 0x0215 => .cancel, // WM_CANCELMODE / WM_CAPTURECHANGED
        0x02a3 => .leave,
        else => null,
    };
}
test "signed coordinates preserve outside-client drag and negative monitor origins" {
    const p = point(@as(isize, @bitCast(@as(usize, 0xfffeffff))));
    try std.testing.expectEqual(@as(i32, -1), p.x);
    try std.testing.expectEqual(@as(i32, -2), p.y);
}
test "buttons including double click and X buttons" {
    try std.testing.expect(decode(0x0203, 0, 0).?.button.pressed);
    try std.testing.expect(!decode(0x0202, 0, 0).?.button.pressed);
    try std.testing.expectEqual(Button.five, decode(0x020b, 2 << 16, 0).?.button.button);
    try std.testing.expect(decode(0x020b, 3 << 16, 0) == null);
}
test "wheel sign and partial deltas are preserved" {
    try std.testing.expectEqual(@as(i16, -120), decode(0x020a, @as(usize, @as(u16, @bitCast(@as(i16, -120)))) << 16, 0).?.wheel.delta);
    try std.testing.expectEqual(@as(i16, 30), decode(0x020a, 30 << 16, 0).?.wheel.delta);
    try std.testing.expect(decode(0x020e, 120 << 16, 0).?.wheel.horizontal);
    try std.testing.expect(decode(0x0100, 0, 0) == null);
    try std.testing.expectEqual(Event.cancel, decode(0x0215, 0, 0).?);
}
