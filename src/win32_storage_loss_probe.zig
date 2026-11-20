//! Owned offscreen HWNDs only. Synthetic in-process messages, no device detach.
const std = @import("std");
const w = std.os.windows;
const window = @import("apprt/win32/window.zig");
const storage = @import("apprt/win32/sandbox_storage.zig");
extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
extern "kernel32" fn GetLogicalDrives() callconv(.winapi) u32;
extern "user32" fn SendMessageW(w.HWND, u32, usize, isize) callconv(.winapi) isize;
extern "user32" fn IsWindowVisible(w.HWND) callconv(.winapi) i32;
extern "user32" fn InvalidateRect(w.HWND, ?*const anyopaque, i32) callconv(.winapi) i32;
extern "user32" fn PeekMessageW(*Message, ?w.HWND, u32, u32, u32) callconv(.winapi) i32;
extern "user32" fn DispatchMessageW(*const Message) callconv(.winapi) isize;
const Message = extern struct { hwnd: ?w.HWND, message: u32, wp: usize, lp: isize, time: u32, x: i32, y: i32, private: u32 };
const Counter = std.atomic.Value(u32);
const Mode = enum { removal, nested_confirmation, disabled, fallback };

const Case = struct {
    mode: Mode,
    guard: storage.Guard,
    hwnd: w.HWND = undefined,
    thread: ?std.Thread = null,
    paints: Counter = .init(0),
    failures: Counter = .init(0),
    confirmations: Counter = .init(0),
    losses: Counter = .init(0),
    closes: Counter = .init(0),
    allow_close: Counter = .init(0),

    fn get(ctx: ?*anyopaque) *Case {
        return @ptrCast(@alignCast(ctx.?));
    }
    fn ready(ctx: ?*anyopaque, hwnd: w.HWND, _: usize) !void {
        const self = get(ctx);
        self.hwnd = hwnd;
        self.thread = try std.Thread.spawn(.{}, exercise, .{self});
    }
    fn paint(ctx: ?*anyopaque, _: w.HDC, _: i32, _: i32) !bool {
        _ = get(ctx).paints.fetchAdd(1, .monotonic);
        return false; // Production window performs genuine GDI FillRect/paint.
    }
    fn send(self: *Case, event: usize, volume: *const storage.Volume) void {
        _ = SendMessageW(self.hwnd, 0x0219, event, @bitCast(@intFromPtr(volume)));
    }
    fn lost(ctx: ?*anyopaque) void {
        const self = get(ctx);
        _ = self.losses.fetchAdd(1, .monotonic);
        // Reenter while the HWND and borrowed payload are certainly live.
        // Production must not notify or schedule teardown twice.
        const duplicate = storage.Volume{ .unit_mask = self.guard.drive_mask };
        self.send(0x8004, &duplicate);
    }
    fn mayClose(ctx: ?*anyopaque) bool {
        const self = get(ctx);
        _ = self.confirmations.fetchAdd(1, .monotonic);
        if (self.allow_close.load(.acquire) != 0) return true;
        if (self.mode == .nested_confirmation) {
            const own = storage.Volume{ .unit_mask = self.guard.drive_mask };
            self.send(0x8004, &own);
            // Simulate a confirmation dialog's nested pump without a visible
            // dialog or stealing focus. Leave WM_QUIT for the outer pump.
            var message: Message = undefined;
            if (PeekMessageW(&message, self.hwnd, 0x0010, 0x0010, 1) != 0)
                _ = DispatchMessageW(&message);
            return true; // Outer WM_CLOSE must notice nested destruction.
        }
        return false;
    }
    fn closing(ctx: ?*anyopaque) void {
        const self = get(ctx);
        _ = self.closes.fetchAdd(1, .monotonic);
        if (self.mode != .disabled and IsWindowVisible(self.hwnd) != 0)
            _ = self.failures.fetchAdd(1, .monotonic);
    }
    fn exercise(self: *Case) void {
        // A fully offscreen bare GDI window need not receive an automatic
        // paint. Request a real invalid region and production UpdateWindow,
        // not a synthetic WM_PAINT or a fabricated paint counter.
        for (0..1000) |_| {
            if (IsWindowVisible(self.hwnd) != 0) break;
            Sleep(10);
        }
        _ = InvalidateRect(self.hwnd, null, 0);
        window.flushPaint(self.hwnd);
        for (0..1000) |_| {
            if (self.paints.load(.acquire) > 0) break;
            Sleep(10);
        }
        if (self.paints.load(.acquire) == 0) {
            _ = self.failures.fetchAdd(1, .monotonic);
            self.allow_close.store(1, .release);
            window.requestClose(self.hwnd) catch {};
            return;
        }
        if (self.mode == .nested_confirmation) {
            _ = SendMessageW(self.hwnd, 0x0010, 0, 0);
            return;
        }
        _ = SendMessageW(self.hwnd, 0x0010, 0, 0); // Denied ordinary close.
        const own = storage.Volume{ .unit_mask = self.guard.drive_mask };
        self.send(0x8001, &own); // Query-remove is not actual removal.
        self.send(0x8000, &own); // Arrival cannot close.
        const other = storage.Volume{ .unit_mask = self.guard.drive_mask ^ 0x03ffffff };
        self.send(0x8004, &other);
        const short = storage.Volume{ .header = .{ .size = @sizeOf(storage.Header), .device_type = 2 }, .unit_mask = self.guard.drive_mask };
        self.send(0x8004, &short);
        const wrong = storage.Volume{ .header = .{ .size = @sizeOf(storage.Volume), .device_type = 5 }, .unit_mask = self.guard.drive_mask };
        self.send(0x8004, &wrong);
        _ = SendMessageW(self.hwnd, 0x0219, 0x8004, 0);
        if (self.losses.load(.acquire) != 0 or IsWindowVisible(self.hwnd) == 0)
            _ = self.failures.fetchAdd(1, .monotonic);
        if (self.mode == .fallback) return; // Only production timer may close.
        self.send(0x8004, &own);
        if (self.mode == .disabled) {
            if (self.losses.load(.acquire) != 0 or IsWindowVisible(self.hwnd) == 0)
                _ = self.failures.fetchAdd(1, .monotonic);
            self.allow_close.store(1, .release);
            window.requestClose(self.hwnd) catch {};
        }
    }
};

pub fn main() !void {
    const drives = GetLogicalDrives();
    if (drives == 0) return error.UnknownDriveMap;
    const present: u5 = @intCast(@ctz(drives));
    const missing = ~drives & 0x03ffffff;
    if (missing == 0) return error.NoMissingDriveForFixture;
    const absent: u5 = @intCast(@ctz(missing));
    for ([_]Mode{ .removal, .nested_confirmation, .disabled, .fallback }) |mode| {
        var case = Case{ .mode = mode, .guard = .{ .drive_mask = @as(u32, 1) << (if (mode == .fallback) absent else present) } };
        defer if (case.thread) |thread| thread.join();
        try window.runWithHooks(false, .{
            .userdata = &case,
            .ready = Case.ready,
            .paint = Case.paint,
            .closing = Case.closing,
            .may_close = Case.mayClose,
            .no_activate = true,
            .offscreen = true,
            .auto_close_ms = 15000,
            .storage_guard = if (mode == .disabled) null else case.guard,
            .storage_lost = Case.lost,
        });
        std.debug.print("storage probe counters mode={s} failures={d} paints={d} closes={d} losses={d} confirmations={d}\n", .{ @tagName(mode), case.failures.load(.acquire), case.paints.load(.acquire), case.closes.load(.acquire), case.losses.load(.acquire), case.confirmations.load(.acquire) });
        if (case.failures.load(.acquire) != 0 or case.paints.load(.acquire) == 0 or case.closes.load(.acquire) != 1 or
            case.losses.load(.acquire) != (if (mode == .disabled) @as(u32, 0) else 1)) return error.StorageLossProbeFailed;
        std.debug.print("storage probe mode={s} painted=true teardown_once=true losses={d} confirmations={d}\n", .{ @tagName(mode), case.losses.load(.acquire), case.confirmations.load(.acquire) });
    }
}
