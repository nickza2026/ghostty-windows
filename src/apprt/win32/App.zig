const App = @This();
const std = @import("std");
const apprt = @import("../../apprt.zig");
const CoreApp = @import("../../App.zig");
const global = @import("../../global.zig");
const window = @import("window.zig");
const Surface = @import("Surface.zig");
const Config = @import("../../config.zig").Config;
const inputpkg = @import("../../input.zig");
const text_input = @import("text_input.zig");
const ime = @import("ime.zig");
const mouse_input = @import("mouse_input.zig");
const clipboard_fixture = @import("clipboard_text_fixture.zig");
extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
extern "kernel32" fn WaitForSingleObject(std.os.windows.HANDLE, u32) callconv(.winapi) u32;

core_app: *CoreApp,
window_mutex: std.Io.Mutex = .init,
hwnd: ?std.os.windows.HWND = null,
generation: usize = 0,
wake_pending: bool = false, // Protected by window_mutex, one posted wake at most.
render_pending: bool = false, // UI thread only; present latest frame after drain.
ticks: usize = 0,
smoke: bool = false,
new_window_requests: usize = 0,
terminal: bool = false,
terminal_smoke: bool = false,
terminal_surface: ?*Surface = null,
frames: usize = 0,
paints: usize = 0,
renderer_failed: bool = false,
sandbox_offscreen: bool = false,
sandbox_painted: bool = false,
sandbox_natural_exit: bool = false,
sandbox_storage_lost: bool = false,
terminal_output_ok: bool = false,
input_smoke: bool = false,
midline_smoke: bool = false,
portable_tools_check: bool = false,
midline_state: @import("midline_edit_fixture.zig").State = .{},
text_decoder: text_input.Decoder = .{},
ime_active: bool = false,
dialog_active: bool = false,
lifecycle_smoke: bool = false,
worker_startup_failure: enum { none, renderer, io, title } = .none,
fixture: enum { none, exit, burst, bad_shell, profile, profile_paced, font_angsana, font_leelawadee, font_system, font_roomy, font_native, font_native_roomy, image_paste } = .none,
fixture_image_sent: bool = false,
fixture_image_entered: bool = false,
title_backpressure_smoke: bool = false,
mouse_down: [5]bool = @splat(false),
wheel_x_remainder: i32 = 0,
mouse_smoke: bool = false,
viewport_smoke: bool = false,
kitty_image_smoke: bool = false,
kitty_image_reference: bool = false,
kitty_image_stage: u8 = 0, // UI paint thread only; never an RPC receipt.
viewport_presentations: u32 = 0,
viewport_first: [2]u32 = .{ 0, 0 },
viewport_last: [2]u32 = .{ 0, 0 },
viewport_returned: bool = false,
viewport_seen_odd: bool = false,
mouse_smoke_stage: u8 = 0,
fixture_key_mods: ?inputpkg.Mods = null,
thai_tui_smoke: bool = false,
gpu_text_frame_check: bool = false,
remote_render_pending: std.atomic.Value(bool) = .init(false),
thai_tui_legacy: bool = false,
thai_tui_model_required: bool = false,
background_smoke: bool = false,
preview_background: ?u24 = null,

fn profiling(self: *const App) bool {
    return self.fixture == .profile or self.fixture == .profile_paced;
}

pub fn init(self: *App, core_app: *CoreApp, _: struct {}) !void {
    self.* = .{ .core_app = core_app };
}

/// UI-thread teardown only, after removing the surface from the registry.
/// Both reader and renderer can be blocked posting to our bounded mailbox.
/// Keep consuming stale messages until the producer has really stopped; no
/// worker may outlive its surface or HWND, and no force-termination shortcut.
pub fn joinWorkerDuringClose(self: *App, thread: std.Thread) void {
    std.debug.assert(self.terminal_surface == null);
    const handle = thread.getHandle();
    while (true) {
        switch (WaitForSingleObject(handle, 1)) {
            0 => break,
            258 => {}, // WAIT_TIMEOUT: producer still alive, so consume.
            else => @panic("invalid owned worker wait during Win32 teardown"),
        }
        // Native Surface.deinit deregisters before entering Core.deinit, so
        // these late surface messages are rejected without touching dead GPU
        // state. Normal message ownership/dispatch remains in the Core app.
        self.core_app.tick(self) catch |err| {
            std.log.err("shutdown mailbox drain failed: {}", .{err});
            self.renderer_failed = true;
        };
    }
    thread.join();
    // No messages from this joined producer may survive until a quarantined
    // surface address is freed and reused by a later startup.
    self.core_app.tick(self) catch @panic("failed to drain quarantined worker messages");
}

pub fn run(self: *App) !void {
    if (comptime @import("../../build_config.zig").windows_sandbox_default) {
        const value = global.environ().getAlloc(self.core_app.alloc, "LOCALTERM_SANDBOX_OFFSCREEN") catch |err| switch (err) {
            error.EnvironmentVariableMissing => null,
            else => return err,
        };
        defer if (value) |v| self.core_app.alloc.free(v);
        self.sandbox_offscreen = try @import("sandbox_test_options.zig").offscreen(value);
    }
    var env = try global.environMap();
    defer env.deinit();
    const smoke = if (env.get("LOCALTERM_WINDOW_SMOKE")) |value| std.mem.eql(u8, value, "1") else false;
    self.smoke = smoke;
    self.input_smoke = if (env.get("LOCALTERM_INPUT_SMOKE")) |value| std.mem.eql(u8, value, "1") else false;
    self.midline_smoke = if (env.get("LOCALTERM_MIDLINE_SMOKE")) |value| std.mem.eql(u8, value, "1") else false;
    self.portable_tools_check = if (env.get("LOCALTERM_PORTABLE_TOOLS_CHECK")) |value| std.mem.eql(u8, value, "1") else false;
    if (self.midline_smoke) self.input_smoke = true;
    self.lifecycle_smoke = if (env.get("LOCALTERM_LIFECYCLE_SMOKE")) |value| std.mem.eql(u8, value, "1") else false;
    const owned_ledger = if (env.get("LOCALTERM_LIFECYCLE_LEDGER")) |value| std.mem.eql(u8, value, "1") else false;
    if (owned_ledger and !self.lifecycle_smoke) return error.OwnershipLedgerRequiresLifecycleFixture;
    if (owned_ledger) @import("../../os/windows_resource_ledger.zig").start();
    defer if (owned_ledger) @import("../../os/windows_resource_ledger.zig").emit();
    self.mouse_smoke = if (env.get("LOCALTERM_MOUSE_SMOKE")) |value| std.mem.eql(u8, value, "1") else false;
    self.viewport_smoke = if (env.get("LOCALTERM_VIEWPORT_SMOKE")) |value| std.mem.eql(u8, value, "1") else false;
    self.kitty_image_smoke = if (env.get("LOCALTERM_KITTY_IMAGE_SMOKE")) |value| std.mem.eql(u8, value, "1") else false;
    self.kitty_image_reference = if (env.get("LOCALTERM_KITTY_IMAGE_REFERENCE")) |value| std.mem.eql(u8, value, "1") else false;
    self.thai_tui_smoke = if (env.get("LOCALTERM_THAI_TUI_SMOKE")) |value| std.mem.eql(u8, value, "1") else false;
    self.gpu_text_frame_check = if (env.get("LOCALTERM_GPU_TEXT_FRAME_CHECK")) |value| std.mem.eql(u8, value, "1") else false;
    if (self.gpu_text_frame_check and !self.thai_tui_smoke) return error.GpuTextCheckRequiresControlledThaiFixture;
    self.thai_tui_legacy = if (env.get("LOCALTERM_THAI_TUI_LEGACY")) |value| std.mem.eql(u8, value, "1") else false;
    if (self.thai_tui_legacy and !self.thai_tui_smoke) return error.ThaiWidthControlRequiresFixture;
    self.thai_tui_model_required = if (env.get("LOCALTERM_THAI_MODEL_REQUIRED")) |value| std.mem.eql(u8, value, "1") else false;
    if (self.thai_tui_model_required and !self.thai_tui_smoke) return error.ThaiModelRequiresFixture;
    self.background_smoke = if (env.get("LOCALTERM_BACKGROUND_SMOKE")) |value| std.mem.eql(u8, value, "1") else false;
    if (env.get("LOCALTERM_PREVIEW_BACKGROUND")) |hex| {
        if (hex.len != 6) return error.InvalidPreviewBackground;
        self.preview_background = try std.fmt.parseInt(u24, hex, 16);
    }
    if (env.get("LOCALTERM_TERMINAL_CASE")) |value| {
        self.fixture = if (std.mem.eql(u8, value, "exit")) .exit else if (std.mem.eql(u8, value, "burst")) .burst else if (std.mem.eql(u8, value, "bad-shell")) .bad_shell else if (std.mem.eql(u8, value, "profile")) .profile else if (std.mem.eql(u8, value, "profile-paced")) .profile_paced else if (std.mem.eql(u8, value, "font-angsana")) .font_angsana else if (std.mem.eql(u8, value, "font-leelawadee")) .font_leelawadee else if (std.mem.eql(u8, value, "font-system")) .font_system else if (std.mem.eql(u8, value, "font-roomy")) .font_roomy else if (std.mem.eql(u8, value, "font-native")) .font_native else if (std.mem.eql(u8, value, "font-native-roomy")) .font_native_roomy else if (std.mem.eql(u8, value, "image-paste")) .image_paste else return error.UnknownTerminalFixture;
    }
    if (self.fixture != .none and (self.input_smoke or self.lifecycle_smoke)) return error.IncompatibleSmokeModes;
    if (env.get("LOCALTERM_TITLE_BACKPRESSURE_SMOKE")) |value| {
        if (!std.mem.eql(u8, value, "1") or self.fixture != .burst) return error.InvalidTitleBackpressureControl;
        self.title_backpressure_smoke = true;
    }
    self.terminal_smoke = self.input_smoke or self.lifecycle_smoke or self.fixture != .none or (if (env.get("LOCALTERM_TERMINAL_SMOKE")) |value| std.mem.eql(u8, value, "1") else false);
    if (env.get("LOCALTERM_WORKER_STARTUP_FAILURE")) |value| {
        if (!self.terminal_smoke or self.input_smoke or self.lifecycle_smoke or smoke or
            self.fixture != .none or self.mouse_smoke or self.thai_tui_smoke)
            return error.InvalidWorkerStartupFixture;
        self.worker_startup_failure = if (std.mem.eql(u8, value, "renderer")) .renderer else if (std.mem.eql(u8, value, "io")) .io else if (std.mem.eql(u8, value, "title")) .title else return error.InvalidWorkerStartupFixture;
    }
    self.terminal = @import("../../build_config.zig").windows_sandbox_default or self.terminal_smoke or (!smoke and global.portablePaths() != null) or (if (env.get("LOCALTERM_TERMINAL")) |value| std.mem.eql(u8, value, "1") else false);
    if (global.portablePaths()) |layout| std.log.info("portable app root={s}; child accounts/environment unchanged", .{layout.root});
    if (self.mouse_smoke) {
        if (self.fixture != .none or self.input_smoke or self.lifecycle_smoke or smoke) return error.IncompatibleSmokeModes;
        self.terminal_smoke = true;
        self.terminal = true;
    }
    if (self.thai_tui_smoke) {
        if (self.fixture != .none or self.input_smoke or self.lifecycle_smoke or self.mouse_smoke or smoke) return error.IncompatibleSmokeModes;
        self.terminal_smoke = true;
        self.terminal = true;
    }
    if (smoke and self.terminal) return error.IncompatibleSmokeModes;
    if (self.background_smoke) {
        if (self.fixture != .none or self.input_smoke or self.lifecycle_smoke or self.mouse_smoke or self.thai_tui_smoke or smoke) return error.IncompatibleSmokeModes;
        self.terminal_smoke = true;
        self.terminal = true;
    }
    if (self.viewport_smoke) {
        if (!@import("../../build_config.zig").windows_remote_renderer or !self.terminal_smoke or self.input_smoke or self.lifecycle_smoke or self.mouse_smoke or self.thai_tui_smoke or self.background_smoke or self.fixture != .none or smoke)
            return error.InvalidViewportSmokeMode;
    }
    if (self.kitty_image_reference and !self.kitty_image_smoke) return error.InvalidKittyImageReferenceMode;
    if (self.kitty_image_smoke) {
        if (!self.terminal_smoke or self.input_smoke or self.lifecycle_smoke or self.mouse_smoke or self.thai_tui_smoke or self.background_smoke or self.viewport_smoke or self.fixture != .none or smoke)
            return error.InvalidKittyImageSmokeMode;
        if (self.kitty_image_reference) {
            if (@import("../../build_config.zig").windows_remote_renderer) return error.InvalidKittyImageReferenceMode;
            std.log.info("controlled Kitty legacy reference enabled; parent GL expected, not GPU isolation", .{});
        } else if (!@import("../../build_config.zig").windows_remote_images) return error.InvalidKittyImageSmokeMode;
    }
    try window.runWithHooks(smoke, .{
        .userdata = self,
        .initial_title = if (comptime @import("../../build_config.zig").windows_sandbox_default) std.unicode.utf8ToUtf16LeStringLiteral("Sandbox") else null,
        .ready = ready,
        .tick = tick,
        .closing = closing,
        .may_close = if (self.sandbox_offscreen) null else mayClose,
        .resized = resized,
        .dpi_changed = dpiChanged,
        .paint = paint,
        .auto_close_ms = if (self.lifecycle_smoke) 3000 else if (self.portable_tools_check) 30000 else if (self.profiling()) 15000 else if (self.terminal_smoke) 10000 else null,
        .profile_1080p = self.profiling(),
        .terminal_viewport_smoke = self.viewport_smoke,
        .viewport_presented = viewportPresented,
        .no_activate = smoke or self.terminal_smoke or self.sandbox_offscreen,
        .offscreen = smoke or self.terminal_smoke or self.sandbox_offscreen,
        .input = inputEvent,
        .mouse = mouseEvent,
        .focus = focusChanged,
        .input_smoke = self.input_smoke and !self.midline_smoke,
        .ime = imeEvent,
        .ime_enabled = self.terminal,
        .lifecycle_smoke = self.lifecycle_smoke,
        .lifecycle_pss = if (env.get("LOCALTERM_LIFECYCLE_PSS")) |value| !std.mem.eql(u8, value, "0") else true,
        .storage_guard = if (comptime @import("../../build_config.zig").windows_sandbox_default)
            @import("sandbox_storage.zig").Guard.fromRoot((global.sandboxContext() orelse return error.SandboxNotInitialized).plan.root)
        else
            null,
        .storage_lost = if (comptime @import("../../build_config.zig").windows_sandbox_default) storageLost else null,
    });
    if (self.sandbox_offscreen) {
        std.log.info("sandbox native diagnostic frames={d} paints={d} marker_painted={} natural_exit={} renderer_failed={} storage_lost={}", .{ self.frames, self.paints, self.sandbox_painted, self.sandbox_natural_exit, self.renderer_failed, self.sandbox_storage_lost });
        if (self.frames == 0 or self.paints == 0 or !self.sandbox_painted or (!self.sandbox_natural_exit and !self.sandbox_storage_lost) or self.renderer_failed or self.core_app.surfaces.items.len != 0)
            return error.SandboxNativePresentationFailed;
    }
    if (self.viewport_smoke) {
        if (self.viewport_presentations < 4 or !self.viewport_returned or !self.viewport_seen_odd) return error.ViewportPresentationCoverageFailed;
        std.log.info("controlled terminal viewport current-size frames verified presentations={d} returned_original=1; synthetic DPI only", .{self.viewport_presentations});
    }
    if (smoke) {
        // Ten notifications per cycle coalesce to one dispatch. The stale
        // generation must still be ignored, and all 21 mailbox requests arrive.
        if (self.ticks != 21) return error.CoreWakeCoverageFailed;
        if (self.new_window_requests != 21) return error.CoreMailboxNotDrained;
        std.log.info("Win32 runtime core ticks={d}; mailbox requests={d}; terminal surfaces={d}", .{ self.ticks, self.new_window_requests, self.core_app.surfaces.items.len });
        if (self.core_app.surfaces.items.len != 0) return error.UnexpectedTerminalSurface;
    }
    if (self.terminal_smoke) {
        std.log.info("native terminal smoke: frames={d} paints={d} remaining_surfaces={d}", .{ self.frames, self.paints, self.core_app.surfaces.items.len });
        if (self.frames == 0 or self.paints == 0 or !self.terminal_output_ok or self.renderer_failed or self.core_app.surfaces.items.len != 0)
            return error.TerminalPresentationFailed;
    }
}

fn ready(ctx: ?*anyopaque, hwnd: std.os.windows.HWND, generation: usize) !void {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    {
        self.window_mutex.lockUncancelable(global.io());
        defer self.window_mutex.unlock(global.io());
        self.hwnd = hwnd;
        self.generation = generation;
        self.wake_pending = false;
    }
    @import("../../os/windows_resource_ledger.zig").setGeneration(generation);
    self.render_pending = false;
    if (self.terminal) {
        self.terminal_output_ok = false;
        self.text_decoder.reset();
        var config = try self.terminalConfig();
        defer config.deinit();
        _ = try Surface.create(self, hwnd, &config);
    }
    // Drain work queued before the native message target was ready, then test
    // the same asynchronous wake path that core mailboxes use.
    try self.core_app.tick(self);
    self.wakeup();
    if (self.smoke) {
        // A stale generation must not dispatch the core tick callback.
        try window.wake(hwnd, 0);
        const worker = try std.Thread.spawn(.{}, smokeWorker, .{self});
        worker.join();
    }
}

fn smokeWorker(self: *App) void {
    const mailbox: CoreApp.Mailbox = .{ .rt_app = self, .mailbox = &self.core_app.mailbox };
    _ = mailbox.push(.{ .new_window = .{} }, .{ .forever = {} });
    for (0..8) |_| self.wakeup();
}

fn tick(ctx: ?*anyopaque) !void {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    {
        self.window_mutex.lockUncancelable(global.io());
        defer self.window_mutex.unlock(global.io());
        // Clear before draining: a producer racing the drain queues the next
        // wake instead of losing work published after the final mailbox pop.
        self.wake_pending = false;
    }
    try self.core_app.tick(self);
    self.ticks += 1;
    if (self.remote_render_pending.swap(false, .acquire) or self.render_pending) {
        self.render_pending = false;
        if (self.terminal_surface) |surface| {
            if (self.hwnd) |hwnd| {
                _ = try surface.present(hwnd);
                // WM_PAINT is low priority. Deliver an existing invalid region
                // before the next posted wake, not via a redraw/polling timer.
                window.flushPaint(hwnd);
                if (self.mouse_smoke) try self.checkMouseFixture(surface, hwnd);
                if (self.fixture == .image_paste and !self.fixture_image_sent) {
                    const alloc = self.core_app.alloc;
                    const text = text: {
                        const state = &surface.core().renderer_state;
                        state.mutex.lockUncancelable(global.io());
                        defer state.mutex.unlock(global.io());
                        break :text try state.terminal.plainString(alloc);
                    };
                    defer alloc.free(text);
                    if (std.mem.indexOf(u8, text, "LOCALTERM_IMAGE_READY") != null) {
                        self.fixture_image_sent = true;
                        try surface.pasteFixtureImage();
                        try window.fixtureEnter(hwnd);
                    }
                }
            }
        }
    }
}

fn storageLost(ctx: ?*anyopaque) void {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    self.sandbox_storage_lost = true;
}

fn closing(ctx: ?*anyopaque) void {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    if (self.terminal_surface) |surface| {
        if (self.sandbox_offscreen and surface.initialized) self.sandbox_natural_exit = surface.core().child_exited;
        if (self.terminal_smoke and surface.initialized) self.checkTerminal(surface) catch |err| {
            std.log.err("controlled terminal output check failed: {}", .{err});
            self.renderer_failed = true;
        };
        self.terminal_surface = null;
        if (self.title_backpressure_smoke and surface.initialized) {
            // Diagnostic only: reproduce a reader blocked on the bounded UI
            // mailbox while this UI thread starts synchronous teardown. Bell
            // messages are inline and discarded after deregistration, not rung.
            var filled: usize = 0;
            while (filled < 64) : (filled += 1) {
                if (self.core_app.mailbox.push(global.io(), .{ .surface_message = .{
                    .surface = surface.core(),
                    .message = .ring_bell,
                } }, .instant) == 0) break;
            }
            std.log.info("controlled title backpressure UI queue full; inserted={d}; not readiness evidence", .{filled});
            Sleep(100); // Give the active title producer a turn, not a warmup.
        }
        surface.deinit();
        self.core_app.alloc.destroy(surface);
        // Producers are joined and the registry is empty. Drain late messages
        // before any next-cycle allocation can reuse a CoreSurface address.
        self.core_app.tick(self) catch |err| {
            std.log.err("post-close mailbox drain failed: {}", .{err});
            self.renderer_failed = true;
        };
    }
    self.window_mutex.lockUncancelable(global.io());
    defer self.window_mutex.unlock(global.io());
    self.hwnd = null;
    self.wake_pending = false;
    self.render_pending = false;
}

fn checkMouseFixture(self: *App, surface: *Surface, hwnd: std.os.windows.HWND) !void {
    if (self.mouse_smoke_stage == 6) return;
    const core = surface.core();
    const alloc = self.core_app.alloc;
    const x: i32 = @intCast(core.size.padding.left + core.size.cell.width / 2);
    const y: i32 = @intCast(core.size.padding.top + core.size.cell.height / 2);
    if (self.mouse_smoke_stage == 0) {
        const fixture_ready = fixture_ready: {
            core.renderer_state.mutex.lockUncancelable(global.io());
            defer core.renderer_state.mutex.unlock(global.io());
            const text = try core.io.terminal.plainString(alloc);
            defer alloc.free(text);
            break :fixture_ready std.mem.indexOf(u8, text, "MOUSE_READY") != null;
        };
        if (!fixture_ready) return;
        try window.fixtureMouseSelect(hwnd, x, y, x + @as(i32, @intCast(core.size.cell.width * 6)));
        const selected = try core.selectionString(alloc) orelse return error.MouseSelectionMissing;
        defer alloc.free(selected);
        if (selected.len == 0) return error.MouseSelectionEmpty;
        // Exercise the actual native key handler and Core copy action, but
        // use an in-memory clipboard sink: never touch the user's clipboard.
        const before_ctrl_c = surface.fixture_clipboard_writes;
        try self.fixtureKey(0x43, 0x2e, .{ .ctrl = true });
        try surface.expectFixtureCopy(selected);
        if (surface.fixture_clipboard_writes != before_ctrl_c + 1) return error.CtrlCCopyWriteCount;
        try window.fixtureMouseSelect(hwnd, x, y, x + @as(i32, @intCast(core.size.cell.width * 6)));
        const shift_selected = try core.selectionString(alloc) orelse return error.MouseSelectionMissing;
        defer alloc.free(shift_selected);
        const before_shift_c = surface.fixture_clipboard_writes;
        try self.fixtureKey(0x43, 0x2e, .{ .ctrl = true, .shift = true });
        try surface.expectFixtureCopy(shift_selected);
        if (surface.fixture_clipboard_writes != before_shift_c + 1) return error.CtrlShiftCCopyWriteCount;
        try window.fixtureMouseSelect(hwnd, x, y, x + @as(i32, @intCast(core.size.cell.width * 6)));
        const right_selected = try core.selectionString(alloc) orelse return error.MouseSelectionMissing;
        defer alloc.free(right_selected);
        try window.fixtureRightClick(hwnd, x + @as(i32, @intCast(core.size.cell.width * 12)), y);
        try surface.expectFixtureCopy(right_selected);
        const writes = surface.fixture_clipboard_writes;
        try window.fixtureRightClick(hwnd, x, y);
        if (surface.fixture_clipboard_writes != writes) return error.RightClickCopiedWithoutSelection;
        if (try core.selectionString(alloc)) |remaining| {
            alloc.free(remaining);
            return error.NoSelectionClipboardFixtureExpected;
        }
        try self.fixtureKey(0x43, 0x2e, .{ .ctrl = true });
        if (surface.fixture_clipboard_writes != writes) return error.CtrlCCopiedWithoutSelection;
        std.log.info("{s}", .{clipboard_fixture.selected_copy_marker});
        self.mouse_smoke_stage = 1;
    } else if (self.mouse_smoke_stage == 1) {
        if (!try self.fixtureOutputContains(surface, clipboard_fixture.etx_marker)) return;
        std.log.info("{s}", .{clipboard_fixture.etx_verified_marker});
        try self.fixtureKey(0x56, 0x2f, .{ .ctrl = true });
        if (surface.fixture_clipboard_reads != 1) return error.CtrlVPasteReadCount;
        try self.fixtureKey(0x0d, 0x1c, .{});
        self.mouse_smoke_stage = 2;
    } else if (self.mouse_smoke_stage == 2) {
        const copied = surface.fixture_clipboard orelse return error.CopySinkMissing;
        const expected = try clipboard_fixture.acknowledgement(alloc, 1, copied);
        defer alloc.free(expected);
        if (!try self.fixtureOutputContains(surface, expected)) return;
        try surface.seedFixtureClipboard(clipboard_fixture.unicode_text);
        try self.fixtureKey(0x56, 0x2f, .{ .ctrl = true, .shift = true });
        if (surface.fixture_clipboard_reads != 2) return error.CtrlShiftVPasteReadCount;
        try self.fixtureKey(0x0d, 0x1c, .{});
        self.mouse_smoke_stage = 3;
    } else if (self.mouse_smoke_stage == 3) {
        const expected = try clipboard_fixture.acknowledgement(alloc, 2, clipboard_fixture.unicode_text);
        defer alloc.free(expected);
        if (!try self.fixtureOutputContains(surface, expected) or
            !try self.fixtureOutputContains(surface, "CLIPBOARD_TEXT_CHILD_COMPLETE")) return;
        std.log.info("{s}", .{clipboard_fixture.paste_verified_marker});
        self.mouse_smoke_stage = 4;
        try window.fixtureMouseWheel(hwnd, x, y, 120);
    } else {
        const bottom = bottom: {
            core.renderer_state.mutex.lockUncancelable(global.io());
            defer core.renderer_state.mutex.unlock(global.io());
            break :bottom core.io.terminal.screens.active.viewportIsBottom();
        };
        if (self.mouse_smoke_stage == 4 and !bottom) {
            self.mouse_smoke_stage = 5;
            try window.fixtureMouseWheel(hwnd, x, y, -120 * 100);
        } else if (self.mouse_smoke_stage == 5 and bottom) {
            try window.fixtureMouseCancel(hwnd, x, y);
            for (self.mouse_down) |down| if (down) return error.MouseCancelStateStuck;
            self.mouse_smoke_stage = 6;
            std.log.info("controlled mouse drag selection + wheel scrollback up/down + capture-loss release verified; no OS clipboard or global input", .{});
        }
    }
}

fn fixtureOutputContains(self: *App, surface: *Surface, expected: []const u8) !bool {
    if (!self.mouse_smoke) return error.MouseFixtureNotSelected;
    const core = surface.core();
    core.renderer_state.mutex.lockUncancelable(global.io());
    defer core.renderer_state.mutex.unlock(global.io());
    const text = try core.io.terminal.plainString(self.core_app.alloc);
    defer self.core_app.alloc.free(text);
    return std.mem.indexOf(u8, text, expected) != null;
}

fn fixtureKey(self: *App, key: u32, scan: u8, mods: inputpkg.Mods) !void {
    if (!self.mouse_smoke or self.fixture_key_mods != null) return error.InvalidMouseFixtureKey;
    self.fixture_key_mods = mods;
    defer self.fixture_key_mods = null;
    const bits: usize = 1 | (@as(usize, scan) << 16);
    // Exercise the native keyboard handler and real Core binding dispatcher,
    // without changing the system keyboard state or posting global input.
    _ = try inputEvent(self, 0x0100, key, @bitCast(bits));
    _ = try inputEvent(self, 0x0101, key, @bitCast(bits | 0xc0000000));
}

fn checkTerminal(self: *App, surface: *Surface) !void {
    if (self.kitty_image_smoke) {
        if (self.kitty_image_stage != 3) return error.KittyImagePaintPhasesIncomplete;
        std.log.info("controlled Kitty image all phases verified after GDI paint; actual ConPTY stream, no clipboard; not legacy image parity", .{});
    }
    if (self.viewport_smoke) {
        const stale = surface.core().renderer.remote_stale_frames.load(.acquire);
        if (stale == 0) return error.ViewportStaleFrameNotRejected;
        std.log.info("controlled viewport actual stale returned frame discarded count={d}", .{stale});
    }
    if (self.mouse_smoke and self.mouse_smoke_stage != 6) {
        const core = surface.core();
        core.renderer_state.mutex.lockUncancelable(global.io());
        defer core.renderer_state.mutex.unlock(global.io());
        const text = try core.io.terminal.plainString(self.core_app.alloc);
        defer self.core_app.alloc.free(text);
        std.log.err("synthetic clipboard pending stage={d} writes={d} reads={d} output_tail={s}", .{ self.mouse_smoke_stage, surface.fixture_clipboard_writes, surface.fixture_clipboard_reads, text[text.len -| 2400..] });
        return error.MouseFixtureIncomplete;
    }
    if (self.fixture == .exit) {
        if (!surface.core().child_exited) return error.NaturalChildExitNotObserved;
        std.log.info("controlled natural child exit observed", .{});
    }
    if (self.fixture == .burst or self.profiling()) {
        if (surface.core().child_exited) return error.BurstStoppedBeforeClose;
        std.log.info("controlled output burst active at close", .{});
    }
    if (self.title_backpressure_smoke) {
        if (!std.mem.startsWith(u8, surface.getTitle() orelse return error.TitleStreamNotObserved, "LOCALTERM_TITLE_")) return error.TitleStreamNotObserved;
        std.log.info("controlled OSC title stream observed at close", .{});
    }
    const alloc = self.core_app.alloc;
    const text = text: {
        const state = &surface.core().renderer_state;
        state.mutex.lockUncancelable(global.io());
        defer state.mutex.unlock(global.io());
        break :text try state.terminal.plainString(alloc);
    };
    defer alloc.free(text);
    if (std.mem.indexOf(u8, text, "LOCALTERM_RENDER_SMOKE") == null or std.mem.indexOf(u8, text, "ไทย") == null) {
        // Only the synthetic, offscreen lifecycle fixture may expose a text
        // prefix. Normal terminal/preview input is never logged here.
        if (self.lifecycle_smoke) {
            const snapshot = @import("terminal_marker_diagnostic.zig").analyze(text);
            std.log.err("controlled lifecycle marker snapshot generation={d} bytes={d} marker={} thai={} sample_prefix_base64={s}", .{
                self.generation,                                   snapshot.byte_count, snapshot.has_marker, snapshot.has_thai,
                snapshot.prefix_base64[0..snapshot.prefix_length],
            });
        }
        return error.TerminalMarkerMissing;
    }
    if (self.background_smoke) {
        if (std.mem.indexOf(u8, text, "BACKGROUND_READY") == null) return error.BackgroundFixtureIncomplete;
        std.log.info("controlled background RGB/default/SGR49/EL fixture parsed; pixel inspection required", .{});
    }
    if (self.thai_tui_smoke) {
        if (std.mem.indexOf(u8, text, "TUI_READY") == null or std.mem.indexOf(u8, text, "CUP  | เขียนซ้ำ") == null)
            return error.ThaiTuiFixtureIncomplete;
        std.log.info("controlled Thai styled ANSI/CUP fixture parsed; diagnostic only, not visual acceptance", .{});
        const core = surface.core();
        if (self.gpu_text_frame_check and (core.renderer.gpu_text_parity.checks.load(.acquire) == 0 or core.renderer.gpu_text_parity.max_glyphs.load(.acquire) <= 1 or core.renderer.gpu_text_parity.failures.load(.acquire) != 0))
            return error.GpuTextParityNotVerified;
        if (core.renderer.cpu_text_frame_failures.load(.acquire) != 0)
            return error.CpuTextFrameValidationFailed;
        if (core.renderer.cpu_text_frames_checked.load(.acquire) == 0 or core.renderer.cpu_text_glyph_frames_checked.load(.acquire) == 0)
            return error.CpuTextFrameNotVerified;
        core.renderer_state.mutex.lockUncancelable(global.io());
        defer core.renderer_state.mutex.unlock(global.io());
        try @import("thai_tui_model.zig").compare(&core.io.terminal, alloc, self.thai_tui_model_required);
    }
    if (self.midline_smoke) {
        if (!self.midline_state.module_verified) return error.MidlineModuleNotVerified;
        if (self.midline_state.checked != 2) return error.MidlineFixtureIncomplete;
        if (self.midline_state.failures != 0) return error.MidlineCursorOrCellMismatch;
        std.log.info("controlled interactive PSReadLine arrow midline ASCII+Thai buffer/cells/caret matched; no user input or clipboard", .{});
    } else if (self.input_smoke) {
        if (std.mem.indexOf(u8, text, "LOCALTERM_INPUT_OK:aaสวัสดี😀") == null) {
            std.log.err("controlled input fixture screen: {s}", .{text});
            return error.InputRoundtripMissing;
        }
        std.log.info("keyboard KeyEvent roundtrip ASCII+Thai+surrogate+Enter verified; WM_CHAR repeat=2 verified", .{});
    }
    if (self.fixture == .image_paste) {
        if (!self.fixture_image_sent or !self.fixture_image_entered or std.mem.indexOf(u8, text, "LOCALTERM_IMAGE_OK") == null) {
            std.log.err("controlled image fixture screen: {s}", .{text});
            return error.ImageConsumerRoundtripMissing;
        }
        std.log.info("controlled image core/PTy quoted path parsed as one literal; independent GDI+ PNG pixels verified", .{});
    }
    const image = if (surface.image) |*image| image else return error.NoPresentedImage;
    var colored: usize = 0;
    var index: usize = 0;
    while (index < image.pixels.len) : (index += 4) {
        const b: u16 = image.pixels[index];
        const g: u16 = image.pixels[index + 1];
        const r: u16 = image.pixels[index + 2];
        if (r > g + 30 and r > b + 30) colored += 1;
    }
    if (colored == 0) return error.MissingColoredGlyphPixels;
    var env = try global.environMap();
    defer env.deinit();
    const local = env.get("LOCALAPPDATA") orelse return error.LocalAppDataMissing;
    const path = try std.fs.path.join(alloc, &.{ local, "Letta", "build-logs", "ghostty-windows", "phase3b-runtime", "terminal-frame.bmp" });
    defer alloc.free(path);
    try image.writeBmp(global.io(), path);
    std.log.info("controlled terminal marker+Thai parsed; red_pixels={d}; frame={s}", .{ colored, path });
    self.terminal_output_ok = true;
}

fn mayClose(ctx: ?*anyopaque) bool {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    if (self.dialog_active) return false;
    // This mode owns only its controlled test child, never a user's shell.
    if (self.terminal_smoke) return true;
    if (self.terminal_surface) |surface| {
        if (surface.initialized and surface.core().needsConfirmQuit()) {
            self.dialog_active = true;
            defer self.dialog_active = false;
            return window.confirmClose(self.hwnd, @import("../../build_config.zig").windows_sandbox_default);
        }
    }
    return true;
}

fn resized(ctx: ?*anyopaque, width: u32, height: u32) !void {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    if (self.terminal_surface) |surface| try surface.resize(width, height);
}

fn dpiChanged(ctx: ?*anyopaque, dpi_value: u32) !void {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    if (self.terminal_surface) |surface| try surface.setDpi(dpi_value);
}

fn paint(ctx: ?*anyopaque, dc: std.os.windows.HDC, width: i32, height: i32) !bool {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    const surface = self.terminal_surface orelse return false;
    if (surface.image) |*image| {
        try image.paint(dc, width, height);
        self.paints += 1;
        if (self.sandbox_offscreen and !self.sandbox_painted) try self.observeSandboxPaint(surface);
        if (self.kitty_image_smoke) self.observeKittyPaint(image.pixels);
        return true;
    }
    return false;
}

fn observeSandboxPaint(self: *App, surface: *Surface) !void {
    const a = self.core_app.alloc;
    const state = &surface.core().renderer_state;
    const text = text: {
        state.mutex.lockUncancelable(global.io());
        defer state.mutex.unlock(global.io());
        break :text try state.terminal.plainString(a);
    };
    defer a.free(text);
    const prefix = "LOCALTERM_SANDBOX_NATIVE_";
    const start = std.mem.indexOf(u8, text, prefix) orelse return;
    if (text.len < start + prefix.len + 32 or std.mem.indexOf(u8, text, "ไทย") == null) return;
    const image = if (surface.image) |*image| image else return;
    const red = @import("sandbox_test_options.zig").redPixels(image.pixels);
    if (red < 32) return;
    const layout = global.portablePaths() orelse return error.SandboxNotInitialized;
    try layout.verify(global.io());
    const path = try std.fs.path.join(a, &.{ layout.root, "logs", "sandbox-native-frame.bmp" });
    defer a.free(path);
    try image.writeBmp(global.io(), path);
    std.log.info("sandbox native painted marker={s} thai=true red_pixels={d} frame={s}", .{ text[start .. start + prefix.len + 32], red, path });
    self.sandbox_painted = true;
}

fn observeKittyPaint(self: *App, pixels: []const u8) void {
    const previous = self.kitty_image_stage;
    var red_pixels: usize = 0;
    var green_pixels: usize = 0;
    var at: usize = 0;
    while (at < pixels.len) : (at += 4) {
        // presenter.Image owns BGRA; read only AFTER successful GDI paint.
        const b = pixels[at];
        const g = pixels[at + 1];
        const r = pixels[at + 2];
        if (r >= 240 and g <= 15 and b <= 15) red_pixels += 1;
        if (g >= 240 and r <= 15 and b <= 15) green_pixels += 1;
    }
    if (self.kitty_image_stage == 0 and red_pixels >= 1024) {
        self.kitty_image_stage = 1;
        std.log.info("controlled Kitty image GDI phase=red pixels={d}", .{red_pixels});
    } else if (self.kitty_image_stage == 1 and green_pixels >= 1024 and red_pixels < 1024) {
        self.kitty_image_stage = 2;
        std.log.info("controlled Kitty image GDI phase=green pixels={d}", .{green_pixels});
    } else if (self.kitty_image_stage == 2 and green_pixels < 64 and red_pixels < 1024) {
        self.kitty_image_stage = 3;
        std.log.info("controlled Kitty image GDI phase=removed green_pixels={d}", .{green_pixels});
    }
    if (self.kitty_image_stage != previous) {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(pixels, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        std.log.info("controlled Kitty image raw frame phase={d} bytes={d} sha256={s}", .{ self.kitty_image_stage, pixels.len, &hex });
    }
}

fn cancelMouse(self: *App) !void {
    if (self.terminal_surface) |surface| if (surface.initialized) {
        for (&self.mouse_down, 0..) |*down, i| if (down.*) {
            down.* = false;
            _ = try surface.core().mouseButtonCallback(.release, @enumFromInt(i + 1), .{});
        };
    };
    self.mouse_down = @splat(false);
}

fn mouseEvent(ctx: ?*anyopaque, msg: u32, wp: usize, lp: isize) !bool {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    const surface = self.terminal_surface orelse return false;
    if (!surface.initialized) return false;
    const event = mouse_input.decode(msg, wp, lp) orelse return false;
    var mods: inputpkg.Mods = if (self.terminal_smoke) .{} else modifiers();
    mods.shift = wp & 4 != 0;
    mods.ctrl = wp & 8 != 0;
    switch (event) {
        .cancel => try self.cancelMouse(),
        .leave => {
            surface.cursor = .{ .x = -1, .y = -1 };
            try surface.core().cursorPosCallback(surface.cursor, mods);
        },
        .move, .button, .wheel => {
            var p: mouse_input.Point = switch (event) {
                .move => |v| v,
                .button => |v| v.pos,
                .wheel => |v| v.pos,
                else => unreachable,
            };
            if (event == .wheel) {
                const converted = try window.clientPoint(self.hwnd orelse return false, p.x, p.y);
                p = .{ .x = converted.x, .y = converted.y };
            }
            surface.cursor = .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) };
            try surface.core().cursorPosCallback(surface.cursor, mods);
            switch (event) {
                .button => |v| {
                    self.mouse_down[@intFromEnum(v.button) - 1] = v.pressed;
                    _ = try surface.core().mouseButtonCallback(if (v.pressed) .press else .release, @enumFromInt(@intFromEnum(v.button)), mods);
                },
                .wheel => |v| {
                    if (v.horizontal) {
                        self.wheel_x_remainder += v.delta;
                        const ticks = @divTrunc(self.wheel_x_remainder, 120);
                        self.wheel_x_remainder = @rem(self.wheel_x_remainder, 120);
                        if (ticks != 0) try surface.core().scrollCallback(@floatFromInt(ticks), 0, .{});
                    } else try surface.core().scrollCallback(0, @as(f64, @floatFromInt(v.delta)) / 120.0, .{});
                },
                else => {},
            }
        },
    }
    return true;
}

fn focusChanged(ctx: ?*anyopaque, focused: bool) !void {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    if (!focused) {
        try self.cancelMouse();
        self.text_decoder.reset();
        self.ime_active = false;
        if (self.terminal_surface) |surface| if (surface.initialized) try surface.core().preeditCallback(null);
    }
    if (self.terminal_surface) |surface| if (surface.initialized) try surface.core().focusCallback(focused);
}

fn modifiers() inputpkg.Mods {
    return .{
        .shift = window.keyDown(0x10),
        .ctrl = window.keyDown(0x11),
        .alt = window.keyDown(0x12),
        .super = window.keyDown(0x5b) or window.keyDown(0x5c),
        .caps_lock = window.keyToggled(0x14),
        .num_lock = window.keyToggled(0x90),
        .sides = .{
            .shift = if (window.keyDown(0xa1)) .right else .left,
            .ctrl = if (window.keyDown(0xa3)) .right else .left,
            .alt = if (window.keyDown(0xa5)) .right else .left,
            .super = if (window.keyDown(0x5c)) .right else .left,
        },
    };
}

fn inputEvent(ctx: ?*anyopaque, message: u32, wp: usize, lp: isize) !bool {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    const surface = self.terminal_surface orelse return false;
    if (!surface.initialized) return false;
    const bits: usize = @bitCast(lp);
    const sc: u8 = @truncate(bits >> 16);
    const extended = (bits & (1 << 24)) != 0;
    // Owned synthetic keyboard messages must not inherit modifier keys the
    // user is holding while working in another application. Physical input
    // and normal preview keep the real modifier path.
    const mods: inputpkg.Mods = if (self.mouse_smoke and self.fixture_key_mods != null) self.fixture_key_mods.? else if (self.input_smoke or self.fixture == .image_paste) .{} else modifiers();
    const action: inputpkg.Action = if ((bits & (1 << 30)) != 0) .repeat else .press;
    const repetitions = @max(1, bits & 0xffff);
    if (message == 0x0102 or message == 0x0106 or message == 0x0109) {
        const output = if (message == 0x0109)
            text_input.Output{ .codepoints = .{ text_input.scalar(@truncate(wp)), 0 }, .len = 1 }
        else
            self.text_decoder.feed(@truncate(wp));
        for (0..repetitions) |repeat_index| for (output.codepoints[0..output.len]) |cp| {
            // Enter/Tab/Backspace/Escape/Ctrl bytes are handled on keydown,
            // never twice through TranslateMessage's subsequent WM_CHAR.
            if (cp < 0x20 or cp == 0x7f) continue;
            var utf8: [4]u8 = undefined;
            const length = try std.unicode.utf8Encode(cp, &utf8);
            const altgr = mods.ctrl and mods.alt and mods.sides.alt == .right;
            const effect = try surface.core().keyCallback(.{
                .action = if (repeat_index > 0) .repeat else action,
                .key = physicalKey(sc, extended),
                .mods = mods,
                .consumed_mods = .{ .shift = mods.shift, .ctrl = altgr, .alt = altgr },
                .utf8 = utf8[0..length],
                .unshifted_codepoint = if (cp < 128) std.ascii.toLower(@intCast(cp)) else cp,
            });
            if (effect == .closed) return true;
        };
        return true;
    }
    if (self.ime_active) return false; // IME owns cancellation/selection keys.
    const special = specialKey(@truncate(wp), extended);
    const key = special orelse physicalKey(sc, extended);
    if (self.fixture == .image_paste and key == .enter and message == 0x0100) {
        self.fixture_image_entered = true;
        std.log.info("controlled image synthetic Enter dispatched; global modifiers isolated", .{});
    }
    if (message == 0x0101 or message == 0x0105) {
        _ = try surface.core().keyCallback(.{ .action = .release, .key = key, .mods = mods });
        return true;
    }
    const altgr = mods.ctrl and mods.alt and mods.sides.alt == .right;
    if (special != null or (mods.ctrl and !altgr)) {
        for (0..repetitions) |repeat_index| {
            const effect = try surface.core().keyCallback(.{ .action = if (repeat_index > 0) .repeat else action, .key = key, .mods = mods, .unshifted_codepoint = asciiKey(key) });
            if (effect == .closed) return true;
        }
        return true;
    }
    return false; // Printable layout/dead-key text arrives via WM_CHAR.
}

fn imeEvent(ctx: ?*anyopaque, hwnd: std.os.windows.HWND, message: u32, lp: isize) !void {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    const surface = self.terminal_surface orelse return;
    if (!surface.initialized) return;
    switch (message) {
        0x0051, 0x010e => {
            self.ime_active = false;
            self.text_decoder.reset();
            try surface.core().preeditCallback(null);
        },
        0x010d => {
            self.ime_active = true;
            self.text_decoder.reset();
            try surface.core().preeditCallback(null);
        },
        0x010f => {
            const flags: usize = @bitCast(lp);
            if (flags == 0) self.ime_active = false;
            if (flags == 0 or (flags & 0x800) != 0) try surface.core().preeditCallback(null);
            if ((flags & 8) != 0) {
                self.ime_active = true;
                const session = ime.Session.open(hwnd) orelse return;
                defer session.deinit();
                const text = try session.preedit(self.core_app.alloc);
                defer self.core_app.alloc.free(text);
                try surface.core().preeditCallback(if (text.len == 0) null else text);
            }
        },
        else => {},
    }
    const session = ime.Session.open(hwnd) orelse return;
    defer session.deinit();
    const point = surface.core().imePoint();
    const cell_width: f64 = @floatFromInt(surface.core().size.cell.width);
    session.position(point.x, point.y, @max(point.width, cell_width / @as(f64, surface.scale.x)), point.height, surface.scale.x, surface.scale.y);
}

fn specialKey(vk: u16, extended: bool) ?inputpkg.Key {
    if (vk >= 0x70 and vk <= 0x7b) return @enumFromInt(@intFromEnum(inputpkg.Key.f1) + vk - 0x70);
    return switch (vk) {
        0x08 => .backspace,
        0x09 => .tab,
        0x0d => if (extended) .numpad_enter else .enter,
        0x1b => .escape,
        0x21 => .page_up,
        0x22 => .page_down,
        0x23 => .end,
        0x24 => .home,
        0x25 => .arrow_left,
        0x26 => .arrow_up,
        0x27 => .arrow_right,
        0x28 => .arrow_down,
        0x2d => .insert,
        0x2e => .delete,
        else => null,
    };
}

fn physicalKey(sc: u8, extended: bool) inputpkg.Key {
    const q = [_]inputpkg.Key{ .key_q, .key_w, .key_e, .key_r, .key_t, .key_y, .key_u, .key_i, .key_o, .key_p };
    const a = [_]inputpkg.Key{ .key_a, .key_s, .key_d, .key_f, .key_g, .key_h, .key_j, .key_k, .key_l };
    const z = [_]inputpkg.Key{ .key_z, .key_x, .key_c, .key_v, .key_b, .key_n, .key_m };
    if (sc >= 0x10 and sc <= 0x19) return q[sc - 0x10];
    if (sc >= 0x1e and sc <= 0x26) return a[sc - 0x1e];
    if (sc >= 0x2c and sc <= 0x32) return z[sc - 0x2c];
    if (sc >= 0x02 and sc <= 0x0a) return @enumFromInt(@intFromEnum(inputpkg.Key.digit_1) + sc - 2);
    return switch (sc) {
        0x0b => .digit_0,
        0x0c => .minus,
        0x0d => .equal,
        0x1a => .bracket_left,
        0x1b => .bracket_right,
        0x27 => .semicolon,
        0x28 => .quote,
        0x29 => .backquote,
        0x2b => .backslash,
        0x33 => .comma,
        0x34 => .period,
        0x35 => if (extended) .numpad_divide else .slash,
        0x39 => .space,
        0x1d => if (extended) .control_right else .control_left,
        0x2a => .shift_left,
        0x36 => .shift_right,
        0x38 => if (extended) .alt_right else .alt_left,
        else => .unidentified,
    };
}

fn asciiKey(key: inputpkg.Key) u21 {
    const n = @intFromEnum(key);
    if (n >= @intFromEnum(inputpkg.Key.key_a) and n <= @intFromEnum(inputpkg.Key.key_z)) return @intCast('a' + n - @intFromEnum(inputpkg.Key.key_a));
    if (n >= @intFromEnum(inputpkg.Key.digit_0) and n <= @intFromEnum(inputpkg.Key.digit_9)) return @intCast('0' + n - @intFromEnum(inputpkg.Key.digit_0));
    return switch (key) {
        .space => ' ',
        .bracket_left => '[',
        .bracket_right => ']',
        .backslash => '\\',
        .minus => '-',
        .equal => '=',
        .semicolon => ';',
        .quote => '\'',
        .backquote => '`',
        .comma => ',',
        .period => '.',
        .slash => '/',
        else => 0,
    };
}

fn terminalConfig(self: *App) !Config {
    const alloc = self.core_app.alloc;
    // Theme/config replay may replace Config's entire arena. Runtime policy
    // snapshots must have independent ownership until finalization is done.
    var runtime_arena = std.heap.ArenaAllocator.init(alloc);
    defer runtime_arena.deinit();
    var config = try Config.default(alloc);
    errdefer config.deinit();
    if (comptime @import("../../build_config.zig").windows_sandbox_default) {
        const context = global.sandboxContext() orelse return error.SandboxNotInitialized;
        var validated = try context.revalidate(alloc, global.io());
        defer validated.deinit();
        // This flavor deliberately uses defaults, not host or recursive config.
        // Explicit cwd before finalize avoids home/cwd-derived default resolution.
        try context.applyConfig(&config);
        try @import("sandbox_clipboard.zig").apply(&config);
        try config.finalize();
        if (config._diagnostics.list.items.len != 0) return error.InvalidSandboxConfig;
        try context.applyConfig(&config);
        return config;
    }
    var env = try global.environMap();
    defer env.deinit();
    const root = env.get("SystemRoot") orelse return error.SystemRootMissing;
    const arena = config._arena.?.allocator();
    const path = if (self.fixture == .bad_shell)
        try std.fs.path.join(arena, &.{ root, "System32", "localterm-owned-missing-shell-4a9130c0.exe" })
    else
        try std.fs.path.join(arena, &.{ root, "System32", "WindowsPowerShell", "v1.0", "powershell.exe" });
    if (self.fixture == .bad_shell) std.log.info("controlled missing-shell preflight", .{});
    // Detect a missing binary before CoreSurface starts renderer/IO threads.
    const executable = try std.Io.Dir.cwd().openFile(global.io(), path, .{});
    executable.close(global.io());
    const powershell = try arena.dupeZ(u8, path);
    // Console-local policy: never alter the machine locale or registry.
    const utf8_init = "[Console]::InputEncoding=[Text.UTF8Encoding]::new($false); [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $global:OutputEncoding=[Console]::OutputEncoding; ";
    if (self.portable_tools_check and (!self.terminal_smoke or self.input_smoke or self.fixture != .none or !std.mem.eql(u8, env.get("LOCALTERM_PORTABLE_TOOLS") orelse "", "1"))) return error.InvalidPortableToolsFixture;
    const command: []const [:0]const u8 = if (self.portable_tools_check)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NoExit", "-Command", utf8_init ++ @import("portable_tools_fixture.zig").command }
    else if (self.background_smoke)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ @import("background_fixture.zig").command }
    else if (self.kitty_image_smoke)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ @import("kitty_image_fixture.zig").command }
    else if (self.thai_tui_smoke)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ @import("thai_tui_fixture.zig").command }
    else if (self.mouse_smoke)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ clipboard_fixture.command }
    else if (self.fixture == .exit)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ "[Console]::WriteLine('LOCALTERM_RENDER_SMOKE'); $e=[string][char]27; [Console]::WriteLine($e+'[31mRED'+$e+'[0m ไทย'); [System.Threading.Thread]::Sleep(1000); exit 0" }
    else if (self.fixture == .profile_paced)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ "$e=[string][char]27; $n=0; while($true) { [Console]::WriteLine('LOCALTERM_RENDER_SMOKE '+$n); [Console]::WriteLine($e+'[31mRED'+$e+'[0m ไทย'); $n++; [System.Threading.Thread]::Sleep(16) }" }
    else if (self.fixture == .profile)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ "$e=[string][char]27; $n=0; while($true) { [Console]::WriteLine('LOCALTERM_RENDER_SMOKE '+$n); [Console]::WriteLine($e+'[31mRED'+$e+'[0m ไทย'); $n++ }" }
    else if (self.title_backpressure_smoke)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ "$e=[string][char]27; $n=0; while($true) { [Console]::Write($e+']0;LOCALTERM_TITLE_'+$n+[char]7); [Console]::WriteLine('LOCALTERM_RENDER_SMOKE'); [Console]::WriteLine($e+'[31mRED'+$e+'[0m ไทย'); $n++ }" }
    else if (self.fixture == .burst)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ "$e=[string][char]27; while($true) { [Console]::WriteLine('LOCALTERM_RENDER_SMOKE'); [Console]::WriteLine($e+'[31mRED'+$e+'[0m ไทย') }" }
    else if (self.fixture == .font_angsana or self.fixture == .font_leelawadee or self.fixture == .font_system or self.fixture == .font_roomy or self.fixture == .font_native or self.fixture == .font_native_roomy)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ "[Console]::WriteLine('LOCALTERM_RENDER_SMOKE - Thai font comparison'); $e=[string][char]27; [Console]::WriteLine($e+'[31mRED'+$e+'[0m ไทย'); [Console]::WriteLine('ABC abc 0123456789 | [] {} ()'); [Console]::WriteLine('ไทย สวัสดี ภาษาไทย'); [Console]::WriteLine('ก กิ กี กึ กื กุ กู ก่ ก้ ก๊ ก๋ กิ่ กี้'); [Console]::WriteLine('น้ำ ผู้ใช้ กำลัง ทดสอบ ปี่ กุ้ง'); [Console]::WriteLine('abc ไทย 123 / สวัสดี 😀'); [System.Threading.Thread]::Sleep(60000)" }
    else if (self.fixture == .image_paste)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ @import("image_paste_fixture.zig").command }
    else if (self.midline_smoke)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NoExit", "-Command", utf8_init ++ @import("midline_edit_fixture.zig").command }
    else if (self.input_smoke)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ "[Console]::WriteLine('LOCALTERM_RENDER_SMOKE'); $e=[string][char]27; [Console]::WriteLine($e+'[31mRED'+$e+'[0m ไทย'); $s=[Console]::ReadLine(); [Console]::WriteLine('LOCALTERM_INPUT_OK:'+$s); [System.Threading.Thread]::Sleep(60000)" }
    else if (self.terminal_smoke)
        &.{ powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", utf8_init ++ "[Console]::WriteLine('LOCALTERM_RENDER_SMOKE'); $e=[string][char]27; [Console]::Write($e+'[31mRED'+$e+'[0m ไทย'); [System.Threading.Thread]::Sleep(60000)" }
    else
        &.{ powershell, "-NoLogo", "-NoProfile", "-NoExit", "-Command", utf8_init };
    config.command = .{ .direct = try arena.dupe([:0]const u8, command) };
    config.@"shell-integration" = .none;
    config.@"wait-after-command" = self.terminal_smoke and self.fixture != .exit;
    config.@"background-opacity" = 1;
    // Process-local appearance preview only; leave palette/app SGR unchanged.
    if (self.preview_background) |rgb| config.background = .{ .r = @truncate(rgb >> 16), .g = @truncate(rgb >> 8), .b = @truncate(rgb) };
    // An explicit user gesture: copy the current selection only, never paste
    // or replace it with the word under the right-click position.
    config.@"right-click-action" = .copy;
    // Diagnostic only; do not change production defaults before measurement.
    if (self.thai_tui_smoke and self.thai_tui_legacy) config.@"grapheme-width-method" = .legacy;
    const FontIterator = struct {
        index: usize = 0,
        thai_map: ?[]const u8 = null,
        system_font: bool = false,
        roomy: bool = false,
        native_hinting: bool = false,
        pub fn next(iter: *@This()) ?[]const u8 {
            const args = [_][]const u8{ if (iter.system_font) "--font-family=Leelawadee UI" else "--font-family=Consolas", "--clipboard-read=ask", "--clipboard-write=ask", "--keybind=ctrl+v=paste_from_clipboard", "--keybind=ctrl+shift+v=paste_from_clipboard", "--keybind=ctrl+shift+c=copy_to_clipboard" };
            defer iter.index += 1;
            if (iter.index < args.len) return args[iter.index];
            if (iter.index == args.len) return iter.thai_map;
            if (iter.index == args.len + 1) {
                if (iter.roomy) return "--adjust-cell-height=4";
                if (iter.native_hinting) return "--freetype-load-flags=no-light,no-autohint";
            }
            if (iter.index == args.len + 2 and iter.roomy and iter.native_hinting) return "--freetype-load-flags=no-light,no-autohint";
            return null;
        }
    };
    // Candidate Windows defaults: explicit Thai UI font, native TT hinting and
    // room for stacked marks. Comparisons keep their named control settings.
    const windows_defaults = switch (self.fixture) {
        .font_angsana, .font_leelawadee, .font_system, .font_roomy, .font_native, .font_native_roomy => false,
        else => true,
    };
    var fonts: FontIterator = .{ .system_font = self.fixture == .font_system, .roomy = windows_defaults or self.fixture == .font_roomy or self.fixture == .font_native_roomy, .native_hinting = windows_defaults or self.fixture == .font_native or self.fixture == .font_native_roomy, .thai_map = switch (self.fixture) {
        .font_angsana => "--font-codepoint-map=U+0E00-U+0E7F=Angsana New",
        .font_leelawadee, .font_roomy, .font_native, .font_native_roomy => "--font-codepoint-map=U+0E00-U+0E7F=Leelawadee UI",
        else => if (windows_defaults) "--font-codepoint-map=U+0E00-U+0E7F=Leelawadee UI" else null,
    } };
    try config.loadIter(alloc, &fonts);
    if (self.mouse_smoke) try @import("sandbox_clipboard.zig").apply(&config);
    if (global.portablePaths()) |layout| {
        try layout.verify(global.io());
        const portable_config = try layout.configFile(alloc);
        defer alloc.free(portable_config);
        // Keep controlled fixtures from being replaced by a config command.
        const runtime_command = if (config.command) |cmd| try cmd.clone(runtime_arena.allocator()) else null;
        switch (config.loadOptionalFile(alloc, portable_config)) {
            .loaded => {
                try config.loadRecursiveFiles(alloc);
                if (config._diagnostics.list.items.len != 0) return error.InvalidPortableConfig;
                std.log.info("portable config loaded path={s} font_size={d}", .{ portable_config, config.@"font-size" });
            },
            .not_found => std.log.info("portable config absent; candidate defaults only path={s}", .{portable_config}),
            .@"error" => return error.PortableConfigReadFailed,
        }
        if (self.terminal_smoke or config.command == null) {
            if (runtime_command) |cmd| config.command = try cmd.clone(config.arenaAlloc());
        }
    }
    if (global.portablePaths() != null) {
        const policy = .{
            .command = if (config.command) |cmd| try cmd.clone(runtime_arena.allocator()) else null,
            .shell = config.@"shell-integration",
            .wait = config.@"wait-after-command",
            .opacity = config.@"background-opacity",
            .right_click = config.@"right-click-action",
        };
        try config.finalize();
        if (config._diagnostics.list.items.len != 0) return error.InvalidPortableConfig;
        // Theme replay preserves parsed inputs, not programmatic Win32 policy.
        // Clone into the NEW arena, never reuse pointers from before finalize.
        if (policy.command) |cmd| config.command = try cmd.clone(config.arenaAlloc());
        config.@"shell-integration" = policy.shell;
        config.@"wait-after-command" = policy.wait;
        config.@"background-opacity" = policy.opacity;
        config.@"right-click-action" = policy.right_click;
        if (self.preview_background) |rgb| config.background = .{ .r = @truncate(rgb >> 16), .g = @truncate(rgb >> 8), .b = @truncate(rgb) };
        if (self.thai_tui_smoke and self.thai_tui_legacy) config.@"grapheme-width-method" = .legacy;
    } else try config.finalize();
    // Phase 4 deliberately does not load Ghostty's legacy config or profiles.
    if (env.get("LOCALTERM_PORTABLE_TOOLS")) |value| {
        if (!std.mem.eql(u8, value, "1")) return error.InvalidPortableToolsOptIn;
    }
    if (env.get("LOCALTERM_APP_READLINE")) |value| {
        if (!std.mem.eql(u8, value, "1")) return error.InvalidAppReadlineOptIn;
    }
    const portable_tools = @import("../../build_config.zig").windows_portable_tools_default or std.mem.eql(u8, env.get("LOCALTERM_PORTABLE_TOOLS") orelse "", "1");
    if (portable_tools) {
        try @import("portable_tools.zig").apply(&config, powershell, utf8_init, self.terminal_smoke, &env);
    }
    if (portable_tools or std.mem.eql(u8, env.get("LOCALTERM_APP_READLINE") orelse "", "1")) {
        try @import("app_readline.zig").apply(&config, powershell, utf8_init, self.terminal_smoke or portable_tools, self.midline_smoke, &env);
    }
    return config;
}

pub fn wakeup(self: *App) void {
    self.window_mutex.lockUncancelable(global.io());
    defer self.window_mutex.unlock(global.io());
    if (self.hwnd) |hwnd| {
        if (self.wake_pending) return;
        window.wake(hwnd, self.generation) catch |err| {
            std.log.err("Win32 app wake failed: {}", .{err});
            return;
        };
        self.wake_pending = true;
    }
}

pub fn noteViewportFrame(self: *App, width: u32, height: u32) void {
    if (width == 1117 and height == 709) self.viewport_seen_odd = true;
    const size = [2]u32{ width, height };
    if (std.meta.eql(size, self.viewport_last)) return;
    if (self.viewport_presentations == 0) self.viewport_first = size else if (std.meta.eql(size, self.viewport_first)) self.viewport_returned = true;
    self.viewport_last = size;
    self.viewport_presentations += 1;
    std.log.info("controlled viewport presented width={d} height={d}", .{ width, height });
}

fn viewportPresented(ctx: ?*anyopaque, width: u32, height: u32) bool {
    const self: *App = @ptrCast(@alignCast(ctx.?));
    return self.viewport_presentations != 0 and std.meta.eql(self.viewport_last, [2]u32{ width, height });
}

pub fn terminate(self: *App) void {
    closing(self);
    while (self.core_app.surfaces.items.len > 0) {
        const surface = self.core_app.surfaces.items[self.core_app.surfaces.items.len - 1];
        surface.deinit();
        self.core_app.alloc.destroy(surface);
    }
}

pub fn requestClose(self: *App) !void {
    self.window_mutex.lockUncancelable(global.io());
    defer self.window_mutex.unlock(global.io());
    if (self.hwnd) |hwnd| try window.requestClose(hwnd);
}

pub fn performAction(self: *App, target: apprt.Target, comptime action: apprt.Action.Key, value: apprt.Action.Value(action)) !bool {
    switch (action) {
        .quit => {
            try self.requestClose();
            return true;
        },
        .new_window => {
            self.new_window_requests += 1;
            return false; // Creation is not available before graphics/IO readiness.
        },
        .render => {
            _ = self.actionSurface(target) orelse return false;
            self.render_pending = true;
            self.wakeup();
            return true;
        },
        .set_title => {
            const surface = self.actionSurface(target) orelse return false;
            try surface.setTitle(self.hwnd orelse return false, value.title);
            if (std.mem.startsWith(u8, value.title, "APP_READLINE_ACTIVE|")) std.log.info("app-owned PSReadLine startup verified: {s}", .{value.title});
            if (std.mem.eql(u8, value.title, "PORTABLE_TOOLS_ACTIVE")) std.log.info("portable tools child bootstrap verified: private home/history; exact node/npm/npx/letta entrypoints", .{});
            if (self.portable_tools_check and std.mem.eql(u8, value.title, "PORTABLE_TOOLS_FIXTURE_OK")) std.log.info("controlled portable tools Node/npm/profile/offline-install/installed-cli/cwd-guard verified", .{});
            if (self.midline_smoke) try self.midlineBarrier(surface, value.title);
            return true;
        },
        .renderer_health => {
            if (value == .unhealthy) self.renderer_failed = true;
            return true;
        },
        // No terminal surface is registered until graphics/IO readiness exists.
        // Unsupported optional features are not reported as successful.
        else => return false,
    }
}

fn midlineBarrier(self: *App, surface: *Surface, title: []const u8) anyerror!void {
    const fixture = @import("midline_edit_fixture.zig");
    if (std.mem.startsWith(u8, title, "MIDLINE_MODULE|")) {
        var parts = std.mem.splitScalar(u8, title, '|');
        _ = parts.next();
        const version = parts.next() orelse return error.MidlineModuleIdentityInvalid;
        const hash = parts.next() orelse return error.MidlineModuleIdentityInvalid;
        if (version.len == 0 or version.len > 32 or hash.len != 64 or parts.next() != null) return error.MidlineModuleIdentityInvalid;
        for (hash) |c| if (!std.ascii.isHex(c)) return error.MidlineModuleIdentityInvalid;
        self.midline_state.module_verified = true;
        std.log.info("MIDLINE_MODULE loaded_version={s} assembly_sha256={s}; child verified selected-directory assembly", .{ version, hash });
    } else if (std.mem.eql(u8, title, "MIDLINE_READY")) {
        if (!self.midline_state.module_verified) return error.MidlineModuleNotVerified;
        if (self.midline_state.awaiting or self.midline_state.checked >= 2) return;
        self.midline_state.awaiting = true;
        const initial = try std.mem.concat(self.core_app.alloc, u8, &.{ fixture.prefixes[self.midline_state.checked], fixture.suffix });
        defer self.core_app.alloc.free(initial);
        var codepoints = (try std.unicode.Utf8View.init(initial)).iterator();
        while (codepoints.nextCodepoint()) |cp| _ = try inputEvent(self, 0x0109, cp, 1);
        for (0..fixture.suffix.len) |_| _ = try inputEvent(self, 0x0100, 0x25, 0x01000001);
        for (fixture.inserted) |cp| _ = try inputEvent(self, 0x0109, cp, 1);
        _ = try inputEvent(self, 0x0100, 0x7b, 1); // F12: ordered repaint barrier.
    } else if (std.mem.startsWith(u8, title, "MIDLINE_CHECK|")) {
        const core = surface.core();
        {
            core.renderer_state.mutex.lockUncancelable(global.io());
            defer core.renderer_state.mutex.unlock(global.io());
            try fixture.capture(&self.midline_state, &core.io.terminal, self.core_app.alloc, title);
        }
        // F11 clears/verifies the buffer and emits another readiness barrier
        // inside the same ReadLine. No Enter, synthetic text execution, OS
        // input, focus or clipboard access; no dependency on prompt caching.
        _ = try inputEvent(self, 0x0100, 0x7a, 1);
    }
}

fn actionSurface(self: *App, target: apprt.Target) ?*Surface {
    const surface = self.terminal_surface orelse return null;
    return switch (target) {
        .app => null,
        .surface => |core_surface| if (surface.core_surface == core_surface) surface else null,
    };
}

pub fn performIpc(_: std.mem.Allocator, _: apprt.ipc.Target, comptime action: apprt.ipc.Action.Key, _: apprt.ipc.Action.Value(action)) !bool {
    return false;
}

pub fn redrawInspector(_: *App, _: *Surface) void {
    std.log.warn("Win32 inspector UI is not supported yet", .{});
}
