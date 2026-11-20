//! Bounded text and explicit-user image reads. No clipboard is touched at module
//! init or by unit tests; OSC 52 stays text-only.
//! Native memory remains OS-owned on reads; SetClipboardData transfers ownership
//! only after success. Callers own the UTF-8 copy, never the clipboard HGLOBAL.
const std = @import("std");
const image = @import("clipboard_image.zig");
const w = std.os.windows;
const Handle = *anyopaque;
extern "user32" fn OpenClipboard(?w.HWND) callconv(.winapi) i32;
extern "user32" fn CloseClipboard() callconv(.winapi) i32;
extern "user32" fn IsClipboardFormatAvailable(u32) callconv(.winapi) i32;
extern "user32" fn GetClipboardData(u32) callconv(.winapi) ?Handle;
extern "user32" fn RegisterClipboardFormatW([*:0]const u16) callconv(.winapi) u32;
extern "user32" fn EmptyClipboard() callconv(.winapi) i32;
extern "user32" fn SetClipboardData(u32, Handle) callconv(.winapi) ?Handle;
extern "kernel32" fn GlobalAlloc(u32, usize) callconv(.winapi) ?Handle;
extern "kernel32" fn GlobalFree(Handle) callconv(.winapi) ?Handle;
extern "kernel32" fn GlobalLock(Handle) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(Handle) callconv(.winapi) i32;
extern "kernel32" fn GlobalSize(Handle) callconv(.winapi) usize;

const unicode_text = 13;
const max_bytes = 16 * 1024 * 1024;
const dib = 8;
const dib_v5 = 17;
const max_image_source_bytes = 64 * 1024 * 1024;

fn pngFormat() u32 {
    return RegisterClipboardFormatW(std.unicode.utf8ToUtf16LeStringLiteral("PNG"));
}

pub fn imageAvailable() bool {
    const png = pngFormat();
    return (png != 0 and IsClipboardFormatAvailable(png) != 0) or
        IsClipboardFormatAvailable(dib_v5) != 0 or IsClipboardFormatAvailable(dib) != 0;
}

pub fn mimeTypes() []const []const u8 {
    return formats(available(), imageAvailable());
}

fn formats(text: bool, png: bool) []const []const u8 {
    if (text and png) return &.{ "text/plain", "image/png" };
    if (text) return &.{"text/plain"};
    if (png) return &.{"image/png"};
    return &.{};
}

/// Called only after the UI has confirmed an explicit image-paste action.
/// Copy HGLOBAL while locked, release the clipboard before parsing/encoding.
pub fn readImage(alloc: std.mem.Allocator, hwnd: w.HWND) !?[]u8 {
    const Snapshot = struct { bytes: []u8, png: bool };
    const snapshot: Snapshot = blk: {
        if (OpenClipboard(hwnd) == 0) return error.ClipboardBusy;
        defer _ = CloseClipboard();
        const png = pngFormat();
        const native_formats = [_]u32{ png, dib_v5, dib };
        for (native_formats) |format| {
            if (format == 0 or IsClipboardFormatAvailable(format) == 0) continue;
            const handle = GetClipboardData(format) orelse return error.ClipboardUnavailable;
            const size = GlobalSize(handle);
            if (size == 0 or size > max_image_source_bytes) return error.InvalidClipboardImageLength;
            const memory = GlobalLock(handle) orelse return error.ClipboardLockFailed;
            defer _ = GlobalUnlock(handle);
            const bytes: [*]const u8 = @ptrCast(memory);
            break :blk .{ .bytes = try alloc.dupe(u8, bytes[0..size]), .png = format == png };
        }
        return null;
    };
    defer alloc.free(snapshot.bytes);
    if (snapshot.png) {
        return try alloc.dupe(u8, try image.pngPayload(snapshot.bytes));
    }
    return try image.fromDib(alloc, snapshot.bytes);
}

pub fn available() bool {
    return IsClipboardFormatAvailable(unicode_text) != 0;
}

pub fn read(alloc: std.mem.Allocator, hwnd: w.HWND) !?[:0]u8 {
    if (OpenClipboard(hwnd) == 0) return error.ClipboardBusy;
    defer _ = CloseClipboard();
    if (!available()) return null;
    const handle = GetClipboardData(unicode_text) orelse return error.ClipboardUnavailable;
    const count = try unitCount(GlobalSize(handle));
    const memory = GlobalLock(handle) orelse return error.ClipboardLockFailed;
    defer _ = GlobalUnlock(handle);
    const units: [*]const u16 = @ptrCast(@alignCast(memory));
    return try decode(alloc, units[0..count]);
}

pub fn write(alloc: std.mem.Allocator, hwnd: w.HWND, text: []const u8) !void {
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.EmbeddedClipboardNul;
    const units = try std.unicode.utf8ToUtf16LeAllocZ(alloc, text);
    defer alloc.free(units);
    const bytes = try std.math.mul(usize, try std.math.add(usize, units.len, 1), 2);
    if (bytes > max_bytes) return error.ClipboardTooLarge;
    // Zero allocator padding too: another clipboard reader can inspect GlobalSize,
    // not only the terminated string. Never expose recycled process heap bytes.
    const handle = GlobalAlloc(0x42, bytes) orelse return error.OutOfMemory; // GMEM_MOVEABLE | GMEM_ZEROINIT
    var transferred = false;
    defer if (!transferred) {
        _ = GlobalFree(handle);
    };
    const memory = GlobalLock(handle) orelse return error.ClipboardLockFailed;
    {
        defer _ = GlobalUnlock(handle);
        const destination: [*]u16 = @ptrCast(@alignCast(memory));
        @memcpy(destination[0..units.len], units);
        destination[units.len] = 0;
    }
    if (OpenClipboard(hwnd) == 0) return error.ClipboardBusy;
    defer _ = CloseClipboard();
    if (EmptyClipboard() == 0) return error.ClipboardEmptyFailed;
    if (SetClipboardData(unicode_text, handle) == null) return error.ClipboardSetFailed;
    transferred = true;
}

fn unitCount(bytes: usize) !usize {
    if (bytes == 0 or bytes > max_bytes or bytes % 2 != 0) return error.InvalidClipboardLength;
    return bytes / 2;
}

fn decode(alloc: std.mem.Allocator, units: []const u16) ![:0]u8 {
    const end = std.mem.indexOfScalar(u16, units, 0) orelse return error.UnterminatedClipboard;
    return std.unicode.utf16LeToUtf8AllocZ(alloc, units[0..end]);
}

pub fn multiline(text: []const u8) bool {
    return std.mem.indexOfAny(u8, text, "\r\n") != null;
}

test "clipboard image MIME listing is bounded and contains no invented formats" {
    try std.testing.expectEqual(@as(usize, 0), formats(false, false).len);
    try std.testing.expectEqualStrings("image/png", formats(false, true)[0]);
    try std.testing.expectEqualStrings("text/plain", formats(true, false)[0]);
    try std.testing.expectEqual(@as(usize, 2), formats(true, true).len);
}

test "clipboard decoder Thai combining and supplementary without OS access" {
    const value = try decode(std.testing.allocator, &.{ 'a', 0x0e2a, 0x0e27, 0x0e31, 0x0e2a, 0x0e14, 0x0e35, 0xd83d, 0xde00, 0 });
    defer std.testing.allocator.free(value);
    try std.testing.expectEqualStrings("aสวัสดี😀", value);
}

test "clipboard decoder bounded terminator and malformed UTF16" {
    try std.testing.expectError(error.UnterminatedClipboard, decode(std.testing.allocator, &.{ 'x', 'y' }));
    try std.testing.expectError(error.DanglingSurrogateHalf, decode(std.testing.allocator, &.{ 0xd800, 0 }));
}

test "clipboard multiline recognizes either CR or LF" {
    try std.testing.expect(multiline("a\rb"));
    try std.testing.expect(multiline("a\nb"));
    try std.testing.expect(!multiline("a b"));
}

test "clipboard native length is bounded before memory view" {
    try std.testing.expectError(error.InvalidClipboardLength, unitCount(0));
    try std.testing.expectError(error.InvalidClipboardLength, unitCount(3));
    try std.testing.expectError(error.InvalidClipboardLength, unitCount(max_bytes + 2));
    try std.testing.expectEqual(@as(usize, 1), try unitCount(2));
}

test "clipboard decoder allocation failure frees owned UTF8" {
    const Case = struct {
        fn run(alloc: std.mem.Allocator) !void {
            const value = try decode(alloc, &.{ 'x', 0 });
            defer alloc.free(value);
            try std.testing.expectEqualStrings("x", value);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Case.run, .{});
}
