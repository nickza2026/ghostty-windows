//! Native clipboard acquisition in a C-created private window station only.
//! The helper must establish isolation before calling any of these exports.
const std = @import("std");
const clipboard = @import("apprt/win32/clipboard.zig");
const image = @import("apprt/win32/clipboard_image.zig");
extern fn localterm_private_clipboard_fixture() callconv(.c) c_int;

pub fn main() !void {
    if (localterm_private_clipboard_fixture() != 0) return error.PrivateClipboardProbeFailed;
}

fn fixturePng() ![]u8 {
    var dib: [48]u8 = @splat(0);
    std.mem.writeInt(u32, dib[0..4], 40, .little);
    std.mem.writeInt(i32, dib[4..8], 2, .little);
    std.mem.writeInt(i32, dib[8..12], -1, .little);
    std.mem.writeInt(u16, dib[12..14], 1, .little);
    std.mem.writeInt(u16, dib[14..16], 24, .little);
    @memcpy(dib[40..46], &[_]u8{ 0, 0, 255, 0, 255, 0 });
    return image.fromDib(std.heap.page_allocator, &dib);
}

export fn localterm_probe_png(buffer: [*]u8, capacity: usize) callconv(.c) usize {
    const bytes = fixturePng() catch return 0;
    defer std.heap.page_allocator.free(bytes);
    if (bytes.len > capacity) return 0;
    @memcpy(buffer[0..bytes.len], bytes);
    return bytes.len;
}

export fn localterm_probe_read(hwnd: std.os.windows.HWND, kind: u32) callconv(.c) u32 {
    const a = std.heap.page_allocator;
    if (kind == 5) {
        // Production write AND read APIs, but only after the C fixture has
        // established a noninteractive station with its own OS clipboard.
        const expected = "private copy/paste ไทย 😀";
        clipboard.write(a, hwnd, expected) catch return 11;
        const actual = (clipboard.read(a, hwnd) catch return 12) orelse return 13;
        defer a.free(actual);
        return if (std.mem.eql(u8, expected, actual)) 0 else 14;
    }
    if (kind == 3) {
        const text = (clipboard.read(a, hwnd) catch return 1) orelse return 2;
        defer a.free(text);
        return if (std.mem.eql(u8, text, "test ไทย")) 0 else 3;
    }
    if (kind == 4) {
        const bytes = clipboard.readImage(a, hwnd) catch return 0;
        if (bytes) |value| a.free(value);
        return 4; // Malformed DIB must fail, not turn into a success.
    }
    const bytes = (clipboard.readImage(a, hwnd) catch return 5) orelse return 6;
    defer a.free(bytes);
    image.validatePng(bytes) catch return 7;
    const expected = fixturePng() catch return 8;
    defer a.free(expected);
    if (!std.mem.eql(u8, expected, bytes)) return 9;
    const mimes = clipboard.mimeTypes();
    if (mimes.len != 1 or !std.mem.eql(u8, mimes[0], "image/png")) return 10;
    return 0;
}
