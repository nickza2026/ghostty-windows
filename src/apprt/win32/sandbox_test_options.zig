const std = @import("std");

pub fn offscreen(value: ?[]const u8) !bool {
    const v = value orelse return false;
    if (!std.mem.eql(u8, v, "1")) return error.InvalidSandboxOffscreenOption;
    return true;
}

/// Same BGRA red-dominance rule as App.checkTerminal; ANSI red need not be
/// pure RGB red or exceed twice the other channels.
pub fn redPixels(pixels: []const u8) usize {
    var count: usize = 0;
    var at: usize = 0;
    while (at + 3 < pixels.len) : (at += 4) {
        const b: u16 = pixels[at];
        const g: u16 = pixels[at + 1];
        const r: u16 = pixels[at + 2];
        if (r > g + 30 and r > b + 30) count += 1;
    }
    return count;
}

test "render diagnostic accepts muted ANSI red but rejects neutral pixels" {
    try std.testing.expectEqual(@as(usize, 1), redPixels(&.{ 102, 102, 204, 255 }));
    try std.testing.expectEqual(@as(usize, 0), redPixels(&.{ 102, 102, 102, 255, 255, 255, 255, 255 }));
}

test "sandbox diagnostic is absent or exactly one" {
    try std.testing.expect(!try offscreen(null));
    try std.testing.expect(try offscreen("1"));
    for ([_][]const u8{ "", "0", "true", " 1", "1\n" }) |bad| try std.testing.expectError(error.InvalidSandboxOffscreenOption, offscreen(bad));
}
