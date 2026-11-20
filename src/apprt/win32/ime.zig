//! Original IMM32 composition adapter. Commit remains on DefWindowProcW's
//! WM_IME_CHAR -> WM_CHAR path: GCS_RESULTSTR is never sent to the PTY here.
const std = @import("std");
const w = std.os.windows;
const Context = *opaque {};
const Point = extern struct { x: i32, y: i32 };
const Rect = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
const Composition = extern struct { style: u32, point: Point, area: Rect };
const Candidate = extern struct { index: u32, style: u32, point: Point, area: Rect };
comptime {
    std.debug.assert(@sizeOf(Composition) == 28);
    std.debug.assert(@sizeOf(Candidate) == 32);
}
extern "imm32" fn ImmGetContext(w.HWND) callconv(.winapi) ?Context;
extern "imm32" fn ImmReleaseContext(w.HWND, Context) callconv(.winapi) i32;
extern "imm32" fn ImmGetCompositionStringW(Context, u32, ?*anyopaque, u32) callconv(.winapi) i32;
extern "imm32" fn ImmSetCompositionWindow(Context, *const Composition) callconv(.winapi) i32;
extern "imm32" fn ImmSetCandidateWindow(Context, *const Candidate) callconv(.winapi) i32;

pub const Session = struct {
    hwnd: w.HWND,
    context: Context,

    pub fn open(hwnd: w.HWND) ?Session {
        return .{ .hwnd = hwnd, .context = ImmGetContext(hwnd) orelse return null };
    }

    pub fn deinit(self: Session) void {
        _ = ImmReleaseContext(self.hwnd, self.context);
    }

    pub fn preedit(self: Session, alloc: std.mem.Allocator) ![]u8 {
        const bytes = ImmGetCompositionStringW(self.context, 8, null, 0); // GCS_COMPSTR
        if (bytes < 0) return error.CompositionUnavailable;
        if (bytes > 1024 * 1024 or @mod(bytes, 2) != 0) return error.InvalidCompositionLength;
        if (bytes == 0) return alloc.dupe(u8, "");
        const units = try alloc.alloc(u16, @intCast(@divExact(bytes, 2)));
        defer alloc.free(units);
        const actual = ImmGetCompositionStringW(self.context, 8, units.ptr, @intCast(bytes));
        if (actual < 0 or actual > bytes or @mod(actual, 2) != 0) return error.CompositionChanged;
        return std.unicode.utf16LeToUtf8Alloc(alloc, units[0..@intCast(@divExact(actual, 2))]);
    }

    pub fn position(self: Session, x: f64, y: f64, width: f64, height: f64, sx: f64, sy: f64) void {
        const rect = pixelRect(x, y, width, height, sx, sy);
        const composition: Composition = .{ .style = 2, .point = .{ .x = rect.left, .y = rect.top }, .area = rect };
        const candidate: Candidate = .{ .index = 0, .style = 0x80, .point = .{ .x = rect.left, .y = rect.bottom }, .area = rect };
        // Some TSF providers ignore IMM position hints; physical candidate UI
        // placement remains a human gate rather than an inferred success.
        _ = ImmSetCompositionWindow(self.context, &composition);
        _ = ImmSetCandidateWindow(self.context, &candidate);
    }
};

fn pixel(value: f64) i32 {
    if (!std.math.isFinite(value)) return 0;
    return @intFromFloat(std.math.clamp(value, 0, @as(f64, @floatFromInt(std.math.maxInt(i32)))));
}

fn pixelRect(x: f64, y: f64, width: f64, height: f64, sx: f64, sy: f64) Rect {
    // Core imePoint is logical and y is the bottom of the cell. Our per-monitor
    // aware HWND's IMM coordinates are physical client pixels, not screen pixels.
    return .{ .left = pixel(x * sx), .top = pixel((y - height) * sy), .right = pixel((x + width) * sx), .bottom = pixel(y * sy) };
}

test "IME candidate rectangle converts logical bottom-of-cell once" {
    const rect = pixelRect(10, 40, 8, 16, 1.5, 1.5);
    try std.testing.expectEqual(@as(i32, 15), rect.left);
    try std.testing.expectEqual(@as(i32, 36), rect.top);
    try std.testing.expectEqual(@as(i32, 27), rect.right);
    try std.testing.expectEqual(@as(i32, 60), rect.bottom);
}

test "IME candidate coordinates clamp invalid and oversized values" {
    try std.testing.expectEqual(@as(i32, 0), pixel(-1));
    try std.testing.expectEqual(@as(i32, 0), pixel(std.math.nan(f64)));
    try std.testing.expectEqual(std.math.maxInt(i32), pixel(1e30));
}
