//! Stateful UTF-16 decoding for WM_CHAR. Emits Unicode scalars for the core's
//! KeyEvent.utf8 path, never the paste-oriented CoreSurface.textCallback.
const std = @import("std");

pub const Output = struct {
    codepoints: [2]u21 = @splat(0),
    len: usize = 0,

    fn append(self: *Output, cp: u21) void {
        std.debug.assert(self.len < self.codepoints.len);
        self.codepoints[self.len] = cp;
        self.len += 1;
    }
};

pub const Decoder = struct {
    high: ?u16 = null,

    pub fn feed(self: *Decoder, unit: u16) Output {
        var output: Output = .{};
        if (self.high) |high| {
            self.high = null;
            if (unit >= 0xdc00 and unit <= 0xdfff) {
                output.append(0x10000 + ((@as(u21, high) - 0xd800) << 10) + (@as(u21, unit) - 0xdc00));
                return output;
            }
            output.append(0xfffd);
        }
        if (unit >= 0xd800 and unit <= 0xdbff) {
            self.high = unit;
        } else if (unit >= 0xdc00 and unit <= 0xdfff) {
            output.append(0xfffd);
        } else {
            output.append(unit);
        }
        return output;
    }

    pub fn flush(self: *Decoder) ?u21 {
        if (self.high != null) {
            self.high = null;
            return 0xfffd;
        }
        return null;
    }

    pub fn reset(self: *Decoder) void {
        self.high = null;
    }
};

pub fn scalar(value: u32) u21 {
    if (value > 0x10ffff or (value >= 0xd800 and value <= 0xdfff)) return 0xfffd;
    return @intCast(value);
}

test "WM_CHAR decoder ASCII and Thai scalars" {
    var decoder: Decoder = .{};
    for ([_]u16{ 'A', 0x0e44, 0x0e17, 0x0e22 }) |unit| {
        const output = decoder.feed(unit);
        try std.testing.expectEqual(@as(usize, 1), output.len);
        try std.testing.expectEqual(@as(u21, unit), output.codepoints[0]);
    }
}

test "WM_CHAR decoder supplementary surrogate pair" {
    var decoder: Decoder = .{};
    try std.testing.expectEqual(@as(usize, 0), decoder.feed(0xd83d).len);
    const output = decoder.feed(0xde00);
    try std.testing.expectEqual(@as(usize, 1), output.len);
    try std.testing.expectEqual(@as(u21, 0x1f600), output.codepoints[0]);
    try std.testing.expect(decoder.high == null);
}

test "WM_CHAR decoder lone low surrogate is replacement" {
    var decoder: Decoder = .{};
    const output = decoder.feed(0xdc00);
    try std.testing.expectEqual(@as(usize, 1), output.len);
    try std.testing.expectEqual(@as(u21, 0xfffd), output.codepoints[0]);
}

test "WM_CHAR decoder high followed by ordinary emits both" {
    var decoder: Decoder = .{};
    _ = decoder.feed(0xd800);
    const output = decoder.feed('X');
    try std.testing.expectEqual(@as(usize, 2), output.len);
    try std.testing.expectEqual(@as(u21, 0xfffd), output.codepoints[0]);
    try std.testing.expectEqual(@as(u21, 'X'), output.codepoints[1]);
}

test "WM_CHAR decoder repeated high retains the latest pair" {
    var decoder: Decoder = .{};
    _ = decoder.feed(0xd800);
    try std.testing.expectEqual(@as(u21, 0xfffd), decoder.feed(0xd83d).codepoints[0]);
    try std.testing.expectEqual(@as(u21, 0x1f680), decoder.feed(0xde80).codepoints[0]);
}

test "WM_CHAR decoder flush and focus reset do not leak state" {
    var decoder: Decoder = .{};
    _ = decoder.feed(0xd800);
    try std.testing.expectEqual(@as(?u21, 0xfffd), decoder.flush());
    try std.testing.expect(decoder.flush() == null);
    _ = decoder.feed(0xd800);
    decoder.reset();
    try std.testing.expectEqual(@as(u21, 'B'), decoder.feed('B').codepoints[0]);
}

test "WM_UNICHAR scalar rejects surrogate and out-of-range values" {
    try std.testing.expectEqual(@as(u21, 0xfffd), scalar(0xd800));
    try std.testing.expectEqual(@as(u21, 0xfffd), scalar(0x110000));
    try std.testing.expectEqual(@as(u21, 0x10ffff), scalar(0x10ffff));
}
