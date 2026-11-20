//! Bounded, allocation-free snapshot for controlled lifecycle failures only.
//! The caller decides whether private fixture text may be logged.
const std = @import("std");

pub const Snapshot = struct {
    byte_count: usize,
    has_marker: bool,
    has_thai: bool,
    prefix_base64: [128]u8 = undefined,
    prefix_length: usize = 0,
};

pub fn analyze(text: []const u8) Snapshot {
    var result: Snapshot = .{
        .byte_count = text.len,
        .has_marker = std.mem.indexOf(u8, text, "LOCALTERM_RENDER_SMOKE") != null,
        .has_thai = std.mem.indexOf(u8, text, "ไทย") != null,
    };
    const prefix = text[0..@min(text.len, 96)];
    result.prefix_length = std.base64.standard.Encoder.encode(&result.prefix_base64, prefix).len;
    return result;
}

test "empty marker snapshot has no text or flags" {
    const result = analyze("");
    try std.testing.expectEqual(@as(usize, 0), result.byte_count);
    try std.testing.expectEqual(@as(usize, 0), result.prefix_length);
    try std.testing.expect(!result.has_marker and !result.has_thai);
}

test "ASCII marker and Thai presence are independent" {
    const ascii = analyze("LOCALTERM_RENDER_SMOKE");
    try std.testing.expect(ascii.has_marker and !ascii.has_thai);
    const thai = analyze("ไทย");
    try std.testing.expect(!thai.has_marker and thai.has_thai);
    const both = analyze("LOCALTERM_RENDER_SMOKE\nRED ไทย");
    try std.testing.expect(both.has_marker and both.has_thai);
}

test "snapshot caps raw prefix but searches complete text" {
    const prefix = "a" ** 96;
    const text = prefix ++ "LOCALTERM_RENDER_SMOKE ไทย";
    const result = analyze(text);
    try std.testing.expectEqual(text.len, result.byte_count);
    try std.testing.expect(result.has_marker and result.has_thai);
    try std.testing.expectEqual(@as(usize, 128), result.prefix_length);
    var decoded: [96]u8 = undefined;
    try std.base64.standard.Decoder.decode(&decoded, result.prefix_base64[0..result.prefix_length]);
    try std.testing.expectEqualStrings(prefix, &decoded);
}
