//! Original Win32 window glue. API contracts: docs/reference-notes.md.
//! Deliberately independent of CoreSurface until graphics/IO readiness exists.
const std = @import("std");
const builtin = @import("builtin");
const w = std.os.windows;
const storage = @import("sandbox_storage.zig");
comptime {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64)
        @compileError("The window prototype currently supports Windows x86_64 only");
}

const Rect = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
const Point = extern struct { x: i32, y: i32 };
const MinMax = extern struct { reserved: Point, max_size: Point, max_pos: Point, min_track: Point, max_track: Point };
const WindowPos = extern struct { hwnd: ?w.HWND, after: ?w.HWND, x: i32, y: i32, width: i32, height: i32, flags: u32 };
const Message = extern struct {
    hwnd: ?w.HWND,
    message: u32,
    wparam: usize,
    lparam: isize,
    time: u32,
    point: Point,
    private: u32,
};
const WindowClass = extern struct {
    size: u32 = @sizeOf(WindowClass),
    style: u32 = 0,
    proc: *const fn (w.HWND, u32, usize, isize) callconv(.winapi) isize = windowProc,
    class_extra: i32 = 0,
    window_extra: i32 = 0,
    instance: w.HINSTANCE,
    icon: ?*anyopaque = null,
    cursor: ?*anyopaque,
    background: ?*anyopaque = null,
    menu: ?[*:0]const u16 = null,
    name: [*:0]const u16 = class_name,
    small_icon: ?*anyopaque = null,
};
const Paint = extern struct {
    dc: ?w.HDC,
    erase: i32,
    rect: Rect,
    restore: i32,
    incremental: i32,
    reserved: [32]u8,
};
comptime {
    std.debug.assert(@sizeOf(Message) == 48);
    std.debug.assert(@sizeOf(WindowClass) == 80);
    std.debug.assert(@sizeOf(Paint) == 72);
}

extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.winapi) ?w.HINSTANCE;
extern "kernel32" fn GetProcessHandleCount(w.HANDLE, *u32) callconv(.winapi) i32;
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) w.HANDLE;
extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
extern "kernel32" fn GetLogicalDrives() callconv(.winapi) u32;
extern "kernel32" fn CloseHandle(w.HANDLE) callconv(.winapi) i32;
extern "kernel32" fn CreateToolhelp32Snapshot(u32, u32) callconv(.winapi) w.HANDLE;
extern "kernel32" fn Thread32First(w.HANDLE, *ThreadEntry) callconv(.winapi) i32;
extern "kernel32" fn Thread32Next(w.HANDLE, *ThreadEntry) callconv(.winapi) i32;
extern "kernel32" fn OpenThread(u32, i32, u32) callconv(.winapi) ?w.HANDLE;
extern "kernel32" fn GetThreadDescription(w.HANDLE, *?[*:0]u16) callconv(.winapi) i32;
extern "kernel32" fn LocalFree(?*anyopaque) callconv(.winapi) ?*anyopaque;
// FROM_ADDRESS uses an arbitrary code address, not a UTF-16 string/alignment.
extern "kernel32" fn GetModuleHandleExW(u32, ?*const anyopaque, *?w.HINSTANCE) callconv(.winapi) i32;
extern "kernel32" fn GetModuleFileNameW(?w.HINSTANCE, [*]u16, u32) callconv(.winapi) u32;
extern "ntdll" fn NtQueryInformationThread(w.HANDLE, u32, *anyopaque, u32, ?*u32) callconv(.winapi) i32;
extern fn localterm_win32_thread_handles(*const fn (usize, u32) callconv(.c) void) callconv(.c) u32;
extern fn localterm_win32_handle_inventory(*const fn (usize, u32, u32, u32, [*:0]const u8) callconv(.c) void) callconv(.c) u32;
extern "kernel32" fn SetLastError(u32) callconv(.winapi) void;
extern "user32" fn RegisterClassExW(*const WindowClass) callconv(.winapi) u16;
extern "user32" fn UnregisterClassW([*:0]const u16, w.HINSTANCE) callconv(.winapi) i32;
extern "user32" fn CreateWindowExW(u32, [*:0]const u16, [*:0]const u16, u32, i32, i32, i32, i32, ?w.HWND, ?*anyopaque, w.HINSTANCE, ?*anyopaque) callconv(.winapi) ?w.HWND;
extern "user32" fn DefWindowProcW(w.HWND, u32, usize, isize) callconv(.winapi) isize;
extern "user32" fn DestroyWindow(w.HWND) callconv(.winapi) i32;
extern "user32" fn IsWindow(w.HWND) callconv(.winapi) i32;
extern "user32" fn IsIconic(w.HWND) callconv(.winapi) i32;
extern "user32" fn GetMessageW(*Message, ?w.HWND, u32, u32) callconv(.winapi) i32;
extern "user32" fn TranslateMessage(*const Message) callconv(.winapi) i32;
extern "user32" fn PeekMessageW(*Message, ?w.HWND, u32, u32, u32) callconv(.winapi) i32;
extern "user32" fn DispatchMessageW(*const Message) callconv(.winapi) isize;
extern "user32" fn PostQuitMessage(i32) callconv(.winapi) void;
extern "user32" fn PostMessageW(w.HWND, u32, usize, isize) callconv(.winapi) i32;
extern "user32" fn SendMessageW(w.HWND, u32, usize, isize) callconv(.winapi) isize;
extern "user32" fn GetWindowLongPtrW(w.HWND, i32) callconv(.winapi) isize;
extern "user32" fn SetWindowLongPtrW(w.HWND, i32, isize) callconv(.winapi) isize;
extern "user32" fn GetClientRect(w.HWND, *Rect) callconv(.winapi) i32;
extern "user32" fn ScreenToClient(w.HWND, *Point) callconv(.winapi) i32;
extern "user32" fn ClientToScreen(w.HWND, *Point) callconv(.winapi) i32;
extern "user32" fn SetCapture(w.HWND) callconv(.winapi) ?w.HWND;
extern "user32" fn GetCapture() callconv(.winapi) ?w.HWND;
extern "user32" fn ReleaseCapture() callconv(.winapi) i32;
extern "user32" fn SetFocus(?w.HWND) callconv(.winapi) ?w.HWND;
const MouseTracking = extern struct { size: u32 = @sizeOf(MouseTracking), flags: u32 = 2, hwnd: w.HWND, hover_ms: u32 = 0 };
extern "user32" fn TrackMouseEvent(*MouseTracking) callconv(.winapi) i32;
extern "user32" fn GetWindowRect(w.HWND, *Rect) callconv(.winapi) i32;
extern "user32" fn UpdateWindow(w.HWND) callconv(.winapi) i32;
extern "user32" fn AdjustWindowRectExForDpi(*Rect, u32, i32, u32, u32) callconv(.winapi) i32;
extern "user32" fn GetDpiForWindow(w.HWND) callconv(.winapi) u32;
extern "user32" fn GetKeyState(i32) callconv(.winapi) i16;
extern "user32" fn SetWindowTextW(w.HWND, [*:0]const u16) callconv(.winapi) i32;
extern "user32" fn InvalidateRect(w.HWND, ?*const Rect, i32) callconv(.winapi) i32;
extern "user32" fn MessageBoxW(?w.HWND, [*:0]const u16, [*:0]const u16, u32) callconv(.winapi) i32;
extern "user32" fn ShowWindow(w.HWND, i32) callconv(.winapi) i32;
extern "user32" fn GetSystemMetrics(i32) callconv(.winapi) i32;
extern "user32" fn GetForegroundWindow() callconv(.winapi) ?w.HWND;
extern "user32" fn SetWindowPos(w.HWND, ?w.HWND, i32, i32, i32, i32, u32) callconv(.winapi) i32;
extern "user32" fn SetTimer(w.HWND, usize, u32, ?*anyopaque) callconv(.winapi) usize;
extern "user32" fn KillTimer(w.HWND, usize) callconv(.winapi) i32;
extern "user32" fn LoadCursorW(?w.HINSTANCE, [*:0]const u16) callconv(.winapi) ?*anyopaque;
extern "user32" fn BeginPaint(w.HWND, *Paint) callconv(.winapi) ?w.HDC;
extern "user32" fn EndPaint(w.HWND, *const Paint) callconv(.winapi) i32;
extern "user32" fn FillRect(w.HDC, *const Rect, ?*anyopaque) callconv(.winapi) i32;
extern "user32" fn GetGuiResources(w.HANDLE, u32) callconv(.winapi) u32;
extern "gdi32" fn GetStockObject(i32) callconv(.winapi) ?*anyopaque;

const class_name = std.unicode.utf8ToUtf16LeStringLiteral("localterm-dev.window-prototype");
const title = std.unicode.utf8ToUtf16LeStringLiteral("localterm-dev — window prototype (no terminal)");
const userdata = -21;
const wm_close = 0x0010;
const wm_timer = 0x0113;
const wm_wake = 0x8000 + 0x4c;
var next_generation: usize = 1; // UI-thread only, monotonic across smoke cycles.

pub const Hooks = struct {
    userdata: ?*anyopaque = null,
    initial_title: ?[:0]const u16 = null,
    ready: ?*const fn (?*anyopaque, w.HWND, usize) anyerror!void = null,
    tick: ?*const fn (?*anyopaque) anyerror!void = null,
    closing: ?*const fn (?*anyopaque) void = null,
    may_close: ?*const fn (?*anyopaque) bool = null,
    resized: ?*const fn (?*anyopaque, u32, u32) anyerror!void = null,
    dpi_changed: ?*const fn (?*anyopaque, u32) anyerror!void = null,
    paint: ?*const fn (?*anyopaque, w.HDC, i32, i32) anyerror!bool = null,
    auto_close_ms: ?u32 = null,
    no_activate: bool = false,
    offscreen: bool = false,
    input: ?*const fn (?*anyopaque, u32, usize, isize) anyerror!bool = null,
    mouse: ?*const fn (?*anyopaque, u32, usize, isize) anyerror!bool = null,
    focus: ?*const fn (?*anyopaque, bool) anyerror!void = null,
    input_smoke: bool = false,
    ime: ?*const fn (?*anyopaque, w.HWND, u32, isize) anyerror!void = null,
    ime_enabled: bool = false,
    lifecycle_smoke: bool = false,
    lifecycle_pss: bool = true, // Diagnostic attribution only; counters/gate unchanged.
    profile_1080p: bool = false,
    terminal_viewport_smoke: bool = false,
    viewport_presented: ?*const fn (?*anyopaque, u32, u32) bool = null,
    storage_guard: ?storage.Guard = null,
    storage_lost: ?*const fn (?*anyopaque) void = null,
};

pub fn keyDown(vk: i32) bool {
    return GetKeyState(vk) < 0;
}

pub fn clientPoint(hwnd: w.HWND, x: i32, y: i32) !struct { x: i32, y: i32 } {
    var p: Point = .{ .x = x, .y = y };
    if (ScreenToClient(hwnd, &p) == 0) return error.MouseCoordinateConversionFailed;
    return .{ .x = p.x, .y = p.y };
}

fn mousePoint(x: i32, y: i32) !isize {
    const sx = std.math.cast(i16, x) orelse return error.FixtureCoordinateRange;
    const sy = std.math.cast(i16, y) orelse return error.FixtureCoordinateRange;
    return @bitCast(@as(usize, @as(u16, @bitCast(sx))) | (@as(usize, @as(u16, @bitCast(sy))) << 16));
}

/// Messages to our HWND only. Offscreen hooks explicitly suppress capture/focus.
pub fn fixtureMouseSelect(hwnd: w.HWND, x: i32, y: i32, end_x: i32) !void {
    _ = SendMessageW(hwnd, 0x0201, 1, try mousePoint(x, y));
    _ = SendMessageW(hwnd, 0x0200, 1, try mousePoint(end_x, y));
    _ = SendMessageW(hwnd, 0x0202, 0, try mousePoint(end_x, y));
}
pub fn fixtureMouseWheel(hwnd: w.HWND, x: i32, y: i32, delta: i16) !void {
    var p: Point = .{ .x = x, .y = y };
    if (ClientToScreen(hwnd, &p) == 0) return error.FixtureCoordinateConversion;
    _ = SendMessageW(hwnd, 0x020a, @as(usize, @as(u16, @bitCast(delta))) << 16, try mousePoint(p.x, p.y));
}
pub fn fixtureMouseCancel(hwnd: w.HWND, x: i32, y: i32) !void {
    _ = SendMessageW(hwnd, 0x0201, 1, try mousePoint(x, y));
    _ = SendMessageW(hwnd, 0x0215, 0, 0);
}

pub fn fixtureRightClick(hwnd: w.HWND, x: i32, y: i32) !void {
    _ = SendMessageW(hwnd, 0x0204, 2, try mousePoint(x, y));
    _ = SendMessageW(hwnd, 0x0205, 0, try mousePoint(x, y));
}
pub fn fixtureCopy(hwnd: w.HWND) !void {
    _ = SendMessageW(hwnd, 0x0100, 0x43, 0x002e0001);
    _ = SendMessageW(hwnd, 0x0101, 0x43, @bitCast(@as(usize, 0xc02e0001)));
}

pub fn fixtureEnter(hwnd: w.HWND) !void {
    // Only an owned test HWND, no global input injection or focus change.
    if (PostMessageW(hwnd, 0x0100, 0x0d, 0x001c0001) == 0 or
        PostMessageW(hwnd, 0x0101, 0x0d, @bitCast(@as(usize, 0xc01c0001))) == 0) return error.FixtureEnterFailed;
}

fn offscreenAnchor() !Point {
    const x = GetSystemMetrics(76); // SM_XVIRTUALSCREEN (includes all monitors)
    const y = GetSystemMetrics(77); // SM_YVIRTUALSCREEN
    const width = GetSystemMetrics(78);
    if (width <= 0 or GetSystemMetrics(79) <= 0) return error.InvalidVirtualDesktop;
    const right = try std.math.add(i32, x, width);
    return .{ .x = try std.math.add(i32, right, 64), .y = y };
}

fn placeOffscreen(hwnd: w.HWND) !void {
    const point = try offscreenAnchor();
    // SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE. The HWND stays shown so
    // paint/render coverage is still required; this is not SW_HIDE/minimize.
    if (SetWindowPos(hwnd, null, point.x, point.y, 0, 0, 0x0015) == 0) return error.OffscreenPlacementFailed;
    var rect: Rect = undefined;
    if (GetWindowRect(hwnd, &rect) == 0 or rect.left < point.x) return error.SmokeWindowOnscreen;
}

pub fn keyToggled(vk: i32) bool {
    return (@as(u16, @bitCast(GetKeyState(vk))) & 1) != 0;
}

pub fn clientSize(hwnd: w.HWND) !struct { width: u32, height: u32 } {
    var rect: Rect = undefined;
    if (GetClientRect(hwnd, &rect) == 0) return error.ClientSizeFailed;
    return .{ .width = @intCast(@max(0, rect.right - rect.left)), .height = @intCast(@max(0, rect.bottom - rect.top)) };
}

pub fn dpi(hwnd: w.HWND) !u32 {
    const value = GetDpiForWindow(hwnd);
    if (value == 0) return error.DpiFailed;
    return value;
}

pub fn setTitle(hwnd: w.HWND, alloc: std.mem.Allocator, title_utf8: []const u8) !void {
    const title_utf16 = try std.unicode.utf8ToUtf16LeAllocZ(alloc, title_utf8);
    defer alloc.free(title_utf16);
    if (SetWindowTextW(hwnd, title_utf16) == 0) return error.SetTitleFailed;
}

pub fn invalidate(hwnd: w.HWND) !void {
    if (InvalidateRect(hwnd, null, 0) == 0) return error.InvalidateFailed;
}

pub fn confirmClose(hwnd: ?w.HWND, comptime sandbox: bool) bool {
    return MessageBoxW(
        hwnd,
        std.unicode.utf8ToUtf16LeStringLiteral("Close this terminal and terminate its running process?"),
        std.unicode.utf8ToUtf16LeStringLiteral(@import("sandbox_branding.zig").caption(sandbox, " — close session")),
        0x0134, // MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2 (default No)
    ) == 6;
}

pub fn confirmClipboard(hwnd: w.HWND, comptime sandbox: bool, comptime message: []const u8) bool {
    return MessageBoxW(hwnd, std.unicode.utf8ToUtf16LeStringLiteral(message), std.unicode.utf8ToUtf16LeStringLiteral(@import("sandbox_branding.zig").caption(sandbox, " — clipboard permission")), 0x0134) == 6;
}

pub fn clipboardError(hwnd: w.HWND, comptime sandbox: bool, comptime message: []const u8) void {
    _ = MessageBoxW(hwnd, std.unicode.utf8ToUtf16LeStringLiteral(message), std.unicode.utf8ToUtf16LeStringLiteral(@import("sandbox_branding.zig").caption(sandbox, " — image paste failed")), 0x10);
}

pub fn wake(hwnd: w.HWND, generation: usize) !void {
    if (PostMessageW(hwnd, wm_wake, generation, 0) == 0) return error.WakeFailed;
}

pub fn flushPaint(hwnd: w.HWND) void {
    _ = UpdateWindow(hwnd); // Only paints a pending invalid region; no GL here.
}

pub fn requestClose(hwnd: w.HWND) !void {
    if (PostMessageW(hwnd, wm_close, 0, 0) == 0) return error.CloseMessageFailed;
}

fn resizeOwnedClient(hwnd: w.HWND, width: u32, height: u32) !void {
    const client = try clientSize(hwnd);
    var outer: Rect = undefined;
    if (GetWindowRect(hwnd, &outer) == 0) return error.WindowRectFailed;
    const target_w = outer.right - outer.left + @as(i32, @intCast(width)) - @as(i32, @intCast(client.width));
    const target_h = outer.bottom - outer.top + @as(i32, @intCast(height)) - @as(i32, @intCast(client.height));
    // NOMOVE|NOZORDER|NOACTIVATE: preserve offscreen coordinates.
    if (SetWindowPos(hwnd, null, 0, 0, target_w, target_h, 0x0016) == 0) return error.ViewportResizeFailed;
}

const State = struct {
    hooks: Hooks = .{},
    generation: usize = 0,
    width: i32 = 0,
    height: i32 = 0,
    dpi: u32 = 96,
    tick: u32 = 0,
    resize_events: u32 = 0,
    dpi_events: u32 = 0,
    original_width: u32 = 0,
    original_height: u32 = 0,
    minimized: bool = false,
    destroyed: bool = false,
    failed: bool = false,
    storage_lost: bool = false,
    closing: bool = false,

    fn storageLost(self: *State, hwnd: w.HWND) void {
        if (self.storage_lost or self.closing or self.destroyed) return;
        self.storage_lost = true;
        _ = KillTimer(hwnd, 4);
        if (self.hooks.storage_lost) |lost| lost(self.hooks.userdata);
        // Disappear before joining workers: removal can stall child I/O.
        // Normal teardown still joins producers before destroying their HWND.
        _ = ShowWindow(hwnd, 0); // SW_HIDE, no activation or modal prompt.
        if (PostMessageW(hwnd, wm_close, 0, 0) == 0) self.fail(hwnd, "storage-loss close");
    }

    fn fail(self: *State, hwnd: w.HWND, operation: []const u8) void {
        std.log.err("{s}: Win32 error={d}", .{ operation, @intFromEnum(w.GetLastError()) });
        self.failed = true;
        if (PostMessageW(hwnd, wm_close, 0, 0) == 0) {
            _ = DestroyWindow(hwnd);
        }
    }
};

fn windowProc(hwnd: w.HWND, msg: u32, wp: usize, lp: isize) callconv(.winapi) isize {
    const ptr = GetWindowLongPtrW(hwnd, userdata);
    // Creation messages arrive before CreateWindowExW returns. They must not
    // dereference uninitialized application state.
    if (ptr == 0) return DefWindowProcW(hwnd, msg, wp, lp);
    const state: *State = @ptrFromInt(@as(usize, @bitCast(ptr)));
    switch (msg) {
        0x0219 => { // WM_DEVICECHANGE: borrowed payload, inspect synchronously.
            if (state.hooks.storage_guard) |guard| {
                if (wp == 0x8004 and lp != 0) {
                    const header: *align(1) const storage.Header = @ptrFromInt(@as(usize, @bitCast(lp)));
                    if (storage.Guard.volumeHeader(wp, header.*)) {
                        const volume: *align(1) const storage.Volume = @ptrFromInt(@as(usize, @bitCast(lp)));
                        if (guard.removed(wp, volume.*)) state.storageLost(hwnd);
                    }
                }
            }
            return DefWindowProcW(hwnd, msg, wp, lp);
        },
        0x0024 => { // WM_GETMINMAXINFO: profile only, not a global sizing policy.
            if (state.hooks.profile_1080p and lp != 0) {
                var rect: Rect = .{ .left = 0, .top = 0, .right = 1920, .bottom = 1080 };
                if (AdjustWindowRectExForDpi(&rect, 0x00cf0000, 0, 0, GetDpiForWindow(hwnd)) != 0) {
                    const limits: *MinMax = @ptrFromInt(@as(usize, @bitCast(lp)));
                    // The captioned 1080p client can exceed monitor track limits.
                    // Only permit this controlled off-screen-sized measurement;
                    // do not mislabel a clamped 1920x1061 client as 1080p.
                    limits.max_track.x = @max(limits.max_track.x, rect.right - rect.left);
                    limits.max_track.y = @max(limits.max_track.y, rect.bottom - rect.top);
                    return 0;
                }
            }
        },
        0x0051, 0x010d, 0x010e, 0x010f => {
            if (state.hooks.ime) |callback| callback(state.hooks.userdata, hwnd, msg, lp) catch |err| {
                // Transient IMM/provider failures must not terminate a session.
                std.log.warn("IME update failed: {}", .{err});
            };
            // Let IMM generate committed WM_IME_CHAR/WM_CHAR exactly once.
            return DefWindowProcW(hwnd, msg, wp, lp);
        },
        0x0281 => {
            if (state.hooks.ime_enabled) {
                const flags: usize = @bitCast(lp);
                return DefWindowProcW(hwnd, msg, wp, @bitCast(flags & ~@as(usize, 0x80000000)));
            }
            return DefWindowProcW(hwnd, msg, wp, lp);
        },
        0x0007, 0x0008 => {
            if (state.hooks.focus) |focus| focus(state.hooks.userdata, msg == 0x0007) catch |err| {
                std.log.err("surface focus failed: {}", .{err});
                state.fail(hwnd, "focus hook");
            };
            if (msg == 0x0008 and GetCapture() == hwnd) _ = ReleaseCapture();
        },
        0x0100, 0x0101, 0x0102, 0x0104, 0x0105, 0x0106, 0x0109, 0x0286 => {
            if (msg == 0x0109 and wp == 0xffff) return 1; // UNICODE_NOCHAR capability query.
            // Keep native Alt+F4 close and Alt+Space system menu behavior.
            if (((msg == 0x0104 or msg == 0x0105) and wp == 0x73) or
                ((msg == 0x0104 or msg == 0x0105 or msg == 0x0106) and wp == 0x20))
                return DefWindowProcW(hwnd, msg, wp, lp);
            if (state.hooks.input) |callback| {
                // Unicode WM_IME_CHAR has WM_CHAR payload. Handle it once and
                // do not also let DefWindowProc translate it into WM_CHAR.
                const consumed = callback(state.hooks.userdata, if (msg == 0x0286) 0x0102 else msg, wp, lp) catch |err| failed: {
                    std.log.err("surface input failed: {}", .{err});
                    // A failed paste/binding is not permission to close a
                    // running user session. Native smoke receipts still fail.
                    break :failed true;
                };
                if (consumed) return 0;
            }
        },
        0x0200...0x020e, 0x001f, 0x0215, 0x02a3 => {
            if (state.hooks.mouse) |callback| {
                const consumed = callback(state.hooks.userdata, msg, wp, lp) catch |err| {
                    std.log.err("surface mouse input failed: {}", .{err});
                    return 0;
                };
                if (consumed) {
                    if (msg == 0x0200) {
                        var tracking: MouseTracking = .{ .hwnd = hwnd };
                        _ = TrackMouseEvent(&tracking);
                    }
                    // Never steal capture/focus from the user's other work
                    // during synthetic offscreen tests. Real clicks may focus.
                    if (!state.hooks.no_activate) switch (msg) {
                        0x0201, 0x0203, 0x0204, 0x0206, 0x0207, 0x0209, 0x020b, 0x020d => {
                            _ = SetFocus(hwnd);
                            _ = SetCapture(hwnd);
                        },
                        0x0202, 0x0205, 0x0208, 0x020c => {
                            if (wp & 0x73 == 0 and GetCapture() == hwnd) _ = ReleaseCapture();
                        },
                        0x001f => {
                            if (GetCapture() == hwnd) _ = ReleaseCapture();
                        },
                        else => {},
                    };
                    return if (msg >= 0x020b and msg <= 0x020d) 1 else 0;
                }
            }
        },
        wm_wake => {
            if (wp != state.generation or state.destroyed) return 0;
            if (state.hooks.tick) |tick| tick(state.hooks.userdata) catch |err| {
                std.log.err("core tick failed: {}", .{err});
                state.fail(hwnd, "app tick");
            };
            return 0;
        },
        0x0005 => { // WM_SIZE: always query client pixels, not outer dimensions.
            state.minimized = wp == 1;
            var rect: Rect = undefined;
            if (GetClientRect(hwnd, &rect) == 0) {
                state.fail(hwnd, "GetClientRect");
            } else {
                state.width = rect.right - rect.left;
                state.height = rect.bottom - rect.top;
                state.resize_events += 1;
                if (!state.minimized and state.width > 0 and state.height > 0) {
                    if (state.hooks.resized) |resized| resized(state.hooks.userdata, @intCast(state.width), @intCast(state.height)) catch |err| {
                        std.log.err("surface resize failed: {}", .{err});
                        state.fail(hwnd, "surface resize");
                    };
                }
            }
            return 0;
        },
        0x0046 => { // WM_WINDOWPOSCHANGING: prevent ShowWindow/restore flashes.
            if (state.hooks.offscreen and lp != 0) {
                const pos: *WindowPos = @ptrFromInt(@as(usize, @bitCast(lp)));
                if (pos.flags & 0x0002 == 0) { // !SWP_NOMOVE
                    const point = offscreenAnchor() catch {
                        state.fail(hwnd, "offscreen window position");
                        return 0;
                    };
                    pos.x = point.x;
                    pos.y = point.y;
                }
                pos.flags |= 0x0010; // SWP_NOACTIVATE
            }
            return DefWindowProcW(hwnd, msg, wp, lp);
        },
        0x02e0 => { // WM_DPICHANGED: lParam rectangle is borrowed for this call.
            state.dpi = @intCast(wp & 0xffff);
            state.dpi_events += 1;
            if (lp == 0 or state.dpi == 0) {
                state.fail(hwnd, "invalid WM_DPICHANGED payload");
                return 0;
            }
            const rect: *const Rect = @ptrFromInt(@as(usize, @bitCast(lp)));
            const point: Point = if (state.hooks.offscreen) offscreenAnchor() catch {
                state.fail(hwnd, "offscreen DPI placement");
                return 0;
            } else .{ .x = rect.left, .y = rect.top };
            if (SetWindowPos(hwnd, null, point.x, point.y, rect.right - rect.left, rect.bottom - rect.top, 0x0014) == 0)
                state.fail(hwnd, "SetWindowPos/DPI");
            if (state.hooks.dpi_changed) |changed| changed(state.hooks.userdata, state.dpi) catch |err| {
                std.log.err("surface DPI failed: {}", .{err});
                state.fail(hwnd, "surface DPI");
            };
            return 0;
        },
        0x000f => { // WM_PAINT: opaque empty client area; no renderer is implied.
            var paint: Paint = undefined;
            if (BeginPaint(hwnd, &paint)) |dc| {
                const painted = if (state.hooks.paint) |callback| callback(state.hooks.userdata, dc, state.width, state.height) catch |err| failed: {
                    std.log.err("presenter paint failed: {}", .{err});
                    state.fail(hwnd, "paint hook");
                    break :failed false;
                } else false;
                if (!painted and FillRect(dc, &paint.rect, GetStockObject(4)) == 0)
                    state.fail(hwnd, "FillRect");
                if (EndPaint(hwnd, &paint) == 0) state.fail(hwnd, "EndPaint");
            } else state.fail(hwnd, "BeginPaint");
            return 0;
        },
        0x0014 => return 1, // WM_ERASEBKGND handled by WM_PAINT.
        wm_close => {
            if (state.closing or state.destroyed) return 0;
            if (!state.storage_lost) {
                if (state.hooks.may_close) |may_close| if (!may_close(state.hooks.userdata)) return 0;
            }
            // A confirmation dialog runs a nested pump. A storage-loss close
            // may already have torn down the window before that dialog returns.
            if (state.closing or state.destroyed) return 0;
            state.closing = true;
            _ = KillTimer(hwnd, 4);
            if (state.hooks.closing) |closing| closing(state.hooks.userdata);
            if (DestroyWindow(hwnd) == 0) {
                // Do not endlessly repost WM_CLOSE if native destruction fails.
                std.log.err("DestroyWindow: Win32 error={d}", .{@intFromEnum(w.GetLastError())});
                state.failed = true;
                PostQuitMessage(1);
            }
            return 0;
        },
        0x0002 => { // WM_DESTROY
            state.destroyed = true;
            PostQuitMessage(if (state.failed) 1 else 0);
            return 0;
        },
        0x0082 => { // WM_NCDESTROY: no later message may use the State pointer.
            _ = SetWindowLongPtrW(hwnd, userdata, 0);
            return DefWindowProcW(hwnd, msg, wp, lp);
        },
        wm_timer => {
            if (wp == 4) {
                if (state.hooks.storage_guard) |guard| {
                    if (guard.absent(GetLogicalDrives())) state.storageLost(hwnd);
                }
                return 0;
            }
            if (wp == 3) {
                _ = KillTimer(hwnd, 3);
                // Only this owned test HWND; never SendInput/global injection.
                for ([_]u16{ 'a', 0x0e2a, 0x0e27, 0x0e31, 0x0e2a, 0x0e14, 0x0e35, 0xd83d, 0xde00 }) |unit| {
                    const message: u32 = if (unit >= 0x0e00 and unit <= 0x0e7f) 0x0286 else 0x0102;
                    if (PostMessageW(hwnd, message, unit, if (unit == 'a') 2 else 1) == 0) state.fail(hwnd, "input smoke char");
                }
                if (PostMessageW(hwnd, 0x0100, 0x0d, 0x001c0001) == 0 or PostMessageW(hwnd, 0x0101, 0x0d, @bitCast(@as(usize, 0xc01c0001))) == 0)
                    state.fail(hwnd, "input smoke Enter");
                return 0;
            }
            if (wp == 2) {
                _ = KillTimer(hwnd, 2);
                if (PostMessageW(hwnd, wm_close, 0, 0) == 0) state.fail(hwnd, "auto close");
                return 0;
            }
            if (wp != 1) return DefWindowProcW(hwnd, msg, wp, lp);
            if (state.hooks.terminal_viewport_smoke) {
                // Fixture ONLY: each resize must have a genuine current-size
                // frame consumed by UI before advancing. Never sleep/block the
                // UI or stretch the existing auto-close deadline. In particular
                // do not race initial A's delivery with the first timer resize.
                const expected: ?[2]u32 = switch (state.tick) {
                    0, 5 => .{ state.original_width, state.original_height },
                    1 => .{ 1117, 709 },
                    4 => .{ 884, 561 },
                    else => null,
                };
                if (expected) |size| {
                    const presented = state.hooks.viewport_presented orelse {
                        state.fail(hwnd, "missing viewport presentation hook");
                        return 0;
                    };
                    if (!presented(state.hooks.userdata, size[0], size[1])) return 0;
                }
            }
            state.tick += 1;
            switch (state.tick) {
                1 => {
                    if (state.hooks.terminal_viewport_smoke) resizeOwnedClient(hwnd, 1117, 709) catch state.fail(hwnd, "odd client resize") else if (SetWindowPos(hwnd, null, 0, 0, 900, 600, 0x0016) == 0) state.fail(hwnd, "resize");
                },
                2 => {
                    _ = ShowWindow(hwnd, 7); // SW_SHOWMINNOACTIVE
                    if (IsIconic(hwnd) == 0) state.fail(hwnd, "minimize");
                },
                3 => {
                    _ = ShowWindow(hwnd, 4); // SW_SHOWNOACTIVATE: restore without stealing focus.
                    if (state.hooks.offscreen) placeOffscreen(hwnd) catch state.fail(hwnd, "offscreen restore");
                    if (IsIconic(hwnd) != 0) state.fail(hwnd, "restore");
                },
                4 => {
                    // A synthetic DPI notification tests payload/lifetime only,
                    // not a physical mixed-DPI monitor transition.
                    const rect: Rect = .{ .left = 100, .top = 100, .right = 1000, .bottom = 700 };
                    _ = SendMessageW(hwnd, 0x02e0, 144 | (144 << 16), @bitCast(@intFromPtr(&rect)));
                    if (state.dpi != 144 or state.dpi_events == 0) state.fail(hwnd, "DPI dispatch");
                    state.dpi = GetDpiForWindow(hwnd);
                },
                5 => {
                    if (state.hooks.terminal_viewport_smoke) {
                        resizeOwnedClient(hwnd, state.original_width, state.original_height) catch state.fail(hwnd, "return original client size");
                    } else {
                        _ = KillTimer(hwnd, 1);
                        if (PostMessageW(hwnd, wm_close, 0, 0) == 0) state.fail(hwnd, "PostMessageW/close");
                    }
                },
                6 => if (state.hooks.terminal_viewport_smoke) {
                    _ = KillTimer(hwnd, 1);
                    if (PostMessageW(hwnd, wm_close, 0, 0) == 0) state.fail(hwnd, "viewport close");
                },
                else => {},
            }
            return 0;
        },
        else => return DefWindowProcW(hwnd, msg, wp, lp),
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

const ThreadEntry = extern struct {
    size: u32 = @sizeOf(ThreadEntry),
    usage: u32 = 0,
    id: u32 = 0,
    owner: u32 = 0,
    base: i32 = 0,
    delta: i32 = 0,
    flags: u32 = 0,
};

fn retainedThreadHandle(handle: usize, id: u32) callconv(.c) void {
    std.log.info("lifecycle retained thread handle=0x{x} target={d}", .{ handle, id });
}

fn dumpThreadHandles() void {
    const status = localterm_win32_thread_handles(&retainedThreadHandle);
    if (status != 0) std.log.warn("own thread-handle snapshot unavailable code={d}", .{status});
}

fn inventoryHandle(handle: usize, kind: u32, target: u32, access: u32, label: [*:0]const u8) callconv(.c) void {
    std.log.info("lifecycle handle inventory handle=0x{x} kind={d} target={d} access=0x{x} type={s}", .{ handle, kind, target, access, std.mem.span(label) });
}

fn dumpHandleInventory() void {
    const status = localterm_win32_handle_inventory(&inventoryHandle);
    if (status != 0) std.log.warn("own numeric handle inventory unavailable code={d}", .{status});
}

pub fn describeThread(id: u32) void {
    const thread = OpenThread(0x40 | 0x800, 0, id) orelse return;
    defer _ = CloseHandle(thread);
    @import("../../os/windows_resource_ledger.zig").snapshotThread(thread, id);
    var description: ?[*:0]u16 = null;
    _ = GetThreadDescription(thread, &description);
    defer if (description) |text| {
        _ = LocalFree(text);
    };
    const alloc = std.heap.page_allocator;
    const name = std.unicode.utf16LeToUtf8Alloc(alloc, if (description) |text| std.mem.span(text) else &.{}) catch return;
    defer alloc.free(name);
    var address: ?*anyopaque = null;
    const status = NtQueryInformationThread(thread, 9, @ptrCast(&address), @sizeOf(usize), null);
    var module: ?w.HINSTANCE = null;
    var path: [512]u16 = undefined;
    const length = if (status >= 0 and address != null and GetModuleHandleExW(6, address, &module) != 0)
        GetModuleFileNameW(module, &path, path.len)
    else
        0;
    const module_name = std.unicode.utf16LeToUtf8Alloc(alloc, path[0..length]) catch return;
    defer alloc.free(module_name);
    std.log.info("lifecycle owned thread id={d} name={s} start=0x{x} module={s}", .{ id, name, @intFromPtr(address), module_name });
}

fn threadCount(describe: bool) !u32 {
    const snapshot = CreateToolhelp32Snapshot(4, 0); // TH32CS_SNAPTHREAD
    if (snapshot == w.INVALID_HANDLE_VALUE) return error.ThreadSnapshotFailed;
    defer _ = CloseHandle(snapshot);
    var entry: ThreadEntry = .{};
    if (Thread32First(snapshot, &entry) == 0) return error.ThreadEnumerationFailed;
    const process = GetCurrentProcessId();
    var count: u32 = 0;
    while (true) {
        if (entry.owner == process) {
            count += 1;
            if (describe) describeThread(entry.id);
        }
        entry.size = @sizeOf(ThreadEntry);
        if (Thread32Next(snapshot, &entry) == 0) break;
    }
    if (w.GetLastError() != .NO_MORE_FILES) return error.ThreadEnumerationFailed;
    return count;
}

const Counts = struct {
    handles: u32,
    gdi: u32,
    user: u32,
    threads: u32,

    fn read() !Counts {
        const threads = try threadCount(false);
        const process = GetCurrentProcess();
        var handles: u32 = 0;
        if (GetProcessHandleCount(process, &handles) == 0) return error.HandleCountFailed;
        return .{ .handles = handles, .gdi = GetGuiResources(process, 0), .user = GetGuiResources(process, 1), .threads = threads };
    }
};

pub fn run(smoke: bool) !void {
    try runWithHooks(smoke, .{});
}

pub fn runWithHooks(smoke: bool, hooks: Hooks) !void {
    const instance = GetModuleHandleW(null) orelse return error.ModuleHandleFailed;
    const class: WindowClass = .{
        .instance = instance,
        .cursor = LoadCursorW(null, @ptrFromInt(32512)) orelse return error.CursorFailed,
    };
    if (RegisterClassExW(&class) == 0) return error.RegisterClassFailed;
    defer _ = UnregisterClassW(class_name, instance);

    var baseline: Counts = undefined;
    const cycles: usize = if (smoke or hooks.lifecycle_smoke) 21 else 1; // First cycle warms up resources.
    var effective_hooks = hooks;
    effective_hooks.offscreen = smoke or hooks.offscreen;
    for (0..cycles) |cycle| {
        var state: State = .{ .hooks = effective_hooks, .generation = next_generation };
        next_generation += 1;
        const point: Point = if (effective_hooks.offscreen) try offscreenAnchor() else .{ .x = 100, .y = 100 };
        const extended_style: u32 = if (effective_hooks.offscreen) 0x08000000 else 0; // WS_EX_NOACTIVATE; keep normal caption metrics
        const hwnd = CreateWindowExW(extended_style, class_name, if (effective_hooks.initial_title) |value| value.ptr else title, 0x00cf0000, point.x, point.y, 1050, 700, null, null, instance, null) orelse return error.CreateWindowFailed;
        defer if (!state.destroyed and IsWindow(hwnd) != 0) {
            _ = SetWindowLongPtrW(hwnd, userdata, 0);
            _ = DestroyWindow(hwnd);
        };
        SetLastError(0);
        _ = SetWindowLongPtrW(hwnd, userdata, @bitCast(@intFromPtr(&state)));
        if (@intFromEnum(w.GetLastError()) != 0) return error.UserdataFailed;
        // Error-path fallback only: WM_CLOSE already notified and joined its
        // producers. Repeating that hook can double-deinit another adapter.
        defer if (!state.closing) {
            state.closing = true;
            if (hooks.closing) |closing| closing(hooks.userdata);
        };
        state.dpi = GetDpiForWindow(hwnd);
        if (state.dpi == 0) return error.DpiFailed;
        if (hooks.profile_1080p) {
            var outer: Rect = undefined;
            if (GetWindowRect(hwnd, &outer) == 0) return error.WindowRectFailed;
            const client = try clientSize(hwnd);
            if (SetWindowPos(hwnd, null, 0, 0, outer.right - outer.left + 1920 - @as(i32, @intCast(client.width)), outer.bottom - outer.top + 1080 - @as(i32, @intCast(client.height)), 0x0016) == 0)
                return error.ProfileResizeFailed; // NOACTIVATE | NOMOVE | NOZORDER
            const actual = try clientSize(hwnd);
            if (actual.width != 1920 or actual.height != 1080) {
                var result: Rect = undefined;
                _ = GetWindowRect(hwnd, &result);
                std.log.err("profile size mismatch: client={d}x{d} outer={d}x{d} dpi={d}; requested client=1920x1080", .{ actual.width, actual.height, result.right - result.left, result.bottom - result.top, state.dpi });
                return error.ProfileClientSizeMismatch;
            }
            std.log.info("controlled profile client=1920x1080 no-activate", .{});
        }
        const size = try clientSize(hwnd);
        state.width = @intCast(size.width);
        state.height = @intCast(size.height);
        if (hooks.ready) |ready| try ready(hooks.userdata, hwnd, state.generation);
        if (effective_hooks.offscreen) try placeOffscreen(hwnd);
        _ = ShowWindow(hwnd, if (smoke or hooks.no_activate or effective_hooks.offscreen) 4 else 5);
        if (effective_hooks.offscreen) {
            try placeOffscreen(hwnd);
            if (GetForegroundWindow() == hwnd) return error.SmokeStoleFocus;
            if (cycle == 0) std.log.info("smoke window offscreen x={d} y={d}; no-activate; render/paint still required", .{ point.x, point.y });
        }
        if (hooks.terminal_viewport_smoke) {
            const original = try clientSize(hwnd);
            state.original_width = original.width;
            state.original_height = original.height;
            if (SetTimer(hwnd, 1, 1000, null) == 0) return error.TimerFailed;
        } else if (smoke and SetTimer(hwnd, 1, 100, null) == 0) return error.TimerFailed;
        if (hooks.auto_close_ms) |milliseconds| {
            if (SetTimer(hwnd, 2, milliseconds, null) == 0) return error.TimerFailed;
        }
        if (hooks.input_smoke and SetTimer(hwnd, 3, 1000, null) == 0) return error.TimerFailed;
        if (hooks.storage_guard != null) {
            if (SetTimer(hwnd, 4, 1000, null) == 0) return error.TimerFailed;
        }
        defer if (!state.destroyed and hooks.storage_guard != null) {
            _ = KillTimer(hwnd, 4);
        };

        const Pump = struct {
            pub fn get(message: *Message) i32 {
                return GetMessageW(message, null, 0, 0);
            }
            pub fn peek(message: *Message, filter: u32, flags: u32) bool {
                return PeekMessageW(message, null, filter, filter, flags) != 0;
            }
            pub fn dispatch(message: *const Message) void {
                _ = TranslateMessage(message);
                _ = DispatchMessageW(message);
            }
        };
        const message = try @import("message_pump.zig").run(Message, Pump);
        if (!state.destroyed or state.failed or message.wparam != 0) return error.WindowLifecycleFailed;
        if (smoke) {
            if (state.tick != 5 or state.resize_events == 0 or state.dpi_events == 0) return error.SmokeCoverageFailed;
        }
        if (hooks.terminal_viewport_smoke) {
            if (state.tick != 6 or state.resize_events < 3 or state.dpi_events == 0) return error.ViewportSmokeCoverageFailed;
            std.log.info("controlled terminal viewport odd resize/minimize/restore/return-size/synthetic-DPI dispatched; no physical monitor-DPI claim", .{});
        }
        if ((smoke or hooks.lifecycle_smoke) and cycle == 0) {
            baseline = try Counts.read();
            if (hooks.lifecycle_smoke) {
                _ = try threadCount(true);
                if (hooks.lifecycle_pss) {
                    dumpThreadHandles();
                    std.log.info("lifecycle handle inventory phase=baseline", .{});
                    dumpHandleInventory();
                }
                @call(.never_inline, localterm_native_htrace_marker, .{@as(u32, 1)});
            }
        }
        if (hooks.lifecycle_smoke) {
            const counts = try Counts.read();
            std.log.info("terminal cycle={d} handles={d} GDI={d} USER={d} threads={d}", .{ cycle, counts.handles, counts.gdi, counts.user, counts.threads });
        }
    }
    if (smoke) {
        const final = try Counts.read();
        std.debug.print("window smoke: 20 cycles after warmup; handles {d}->{d}, GDI {d}->{d}, USER {d}->{d}; synthetic DPI only; no terminal surface/GPU/PTY\n", .{ baseline.handles, final.handles, baseline.gdi, final.gdi, baseline.user, final.user });
        if (final.handles > baseline.handles or final.gdi > baseline.gdi or final.user > baseline.user)
            return error.ResourceGrowth;
    }
    if (hooks.lifecycle_smoke) {
        _ = try threadCount(true);
        if (hooks.lifecycle_pss) {
            dumpThreadHandles();
            std.log.info("lifecycle handle inventory phase=final", .{});
            dumpHandleInventory();
        }
        const final = try Counts.read();
        std.log.info("terminal lifecycle 20 cycles after warmup: handles {d}->{d}, GDI {d}->{d}, USER {d}->{d}, threads {d}->{d}", .{ baseline.handles, final.handles, baseline.gdi, final.gdi, baseline.user, final.user, baseline.threads, final.threads });
        @call(.never_inline, localterm_native_htrace_marker, .{@as(u32, 2)});
        if (final.handles > baseline.handles or final.gdi > baseline.gdi or final.user > baseline.user or final.threads > baseline.threads)
            return error.ResourceGrowth;
    }
}

// Debugger boundary for owned lifecycle fixtures only. No allocations, extra
// warmup, waits, resource changes, or production-window calls. Not a waiver.
export fn localterm_native_htrace_marker(phase: u32) callconv(.c) void {
    std.mem.doNotOptimizeAway(phase);
}
