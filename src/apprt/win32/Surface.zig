//! Owned terminal surface. The default window-only runtime registers none;
//! explicit terminal experiments exercise creation/presentation/IO readiness.
const Surface = @This();
const std = @import("std");
const apprt = @import("../../apprt.zig");
const CoreSurface = @import("../../Surface.zig");
const App = @import("App.zig");
const renderer = @import("../../renderer.zig");
const global = @import("../../global.zig");
const Config = @import("../../config.zig").Config;
const clipboard = @import("clipboard.zig");
const ClipboardFiles = @import("clipboard_files.zig").Store;
const clipboard_paths = @import("clipboard_paths.zig");
const presenter = @import("presenter.zig");
const window = @import("window.zig");

app: *App,
core_surface: ?*CoreSurface = null,
size: apprt.SurfaceSize,
scale: apprt.ContentScale,
cursor: apprt.CursorPos = .{ .x = -1, .y = -1 },
title: ?[:0]const u8 = null,
initialized: bool = false,
registered: bool = false,
image: ?presenter.Image = null,
clipboard_images: ClipboardFiles = .{},
clipboard_exe_dir: ?[]u8 = null,
clipboard_portable: bool = false,
fixture_clipboard: ?[]u8 = null,
fixture_clipboard_writes: usize = 0,
fixture_clipboard_reads: usize = 0,

pub fn create(app: *App, hwnd: std.os.windows.HWND, config: *const Config) !*Surface {
    const alloc = app.core_app.alloc;
    const self = try alloc.create(Surface);
    errdefer alloc.destroy(self);
    const size = try window.clientSize(hwnd);
    const factor = @as(f32, @floatFromInt(try window.dpi(hwnd))) / 96.0;
    self.* = .{
        .app = app,
        .size = .{ .width = size.width, .height = size.height },
        .scale = .{ .x = factor, .y = factor },
        .core_surface = try alloc.create(CoreSurface),
    };
    errdefer self.deinit();
    self.clipboard_exe_dir = try std.process.executableDirPathAlloc(global.io(), alloc);
    // Same startup latch as config/resources/tmp, not a new per-surface choice.
    self.clipboard_portable = global.portablePaths() != null;
    app.terminal_surface = self;
    errdefer app.terminal_surface = null;
    try app.core_app.addSurface(self);
    self.registered = true;
    try self.core_surface.?.init(alloc, config, app.core_app, app, self);
    self.initialized = true;
    try self.core().displayRealized();
    try self.core().refreshCallback();
    return self;
}

pub fn core(self: *Surface) *CoreSurface {
    // Exactly like other runtime wrappers, only initialized/registered surfaces
    // may be passed to the core. An empty native window is not a core surface.
    return self.core_surface.?;
}
pub fn rtApp(self: *Surface) *App {
    return self.app;
}
pub fn failWorkerStartup(self: *Surface, io: bool) bool {
    const fail = if (io) self.app.worker_startup_failure == .io else self.app.worker_startup_failure == .renderer;
    if (fail) std.log.info("controlled worker startup injection={s}", .{if (io) "io" else "renderer"});
    return fail;
}
pub fn quarantineFailedStartup(self: *Surface) void {
    if (self.app.terminal_surface == self) self.app.terminal_surface = null;
    if (self.registered) {
        self.app.core_app.deleteSurface(self);
        self.registered = false;
    }
    if (self.app.worker_startup_failure != .none) std.log.info("controlled worker startup quarantined", .{});
}
pub fn noteWorkerStarted(self: *Surface, io: bool) void {
    if (self.app.worker_startup_failure != .none) std.log.info("controlled worker startup started={s}", .{if (io) "io" else "renderer"});
}
pub fn getSize(self: *const Surface) !apprt.SurfaceSize {
    return self.size;
}
pub fn getContentScale(self: *const Surface) !apprt.ContentScale {
    return self.scale;
}
pub fn getCursorPos(self: *const Surface) !apprt.CursorPos {
    return self.cursor;
}
pub fn getTitle(self: *Surface) ?[:0]const u8 {
    return self.title;
}
pub fn renderDeviceOptions(_: *Surface) !renderer.Device.Options {
    return .{};
}
pub fn wantsCpuTextFrameChecks(self: *const Surface) bool {
    return self.app.thai_tui_smoke;
}
pub fn wantsGpuTextFrameChecks(self: *const Surface) bool {
    return self.app.gpu_text_frame_check;
}
pub fn notifyRemoteFrame(self: *Surface) !void {
    self.app.remote_render_pending.store(true, .release);
    // HWND/generation stay alive until all surface workers join. Direct posted
    // wake avoids waiting on the UI window mutex while UI may be joining us.
    if (self.app.hwnd) |hwnd| try window.wake(hwnd, self.app.generation);
}
pub fn defaultTermioEnv(self: *Surface) !std.process.Environ.Map {
    var env = try global.environMap();
    _ = env.orderedRemove("LOCALTERM_WINDOW_SMOKE");
    _ = env.orderedRemove("LOCALTERM_TERMINAL_SMOKE");
    _ = env.orderedRemove("LOCALTERM_INPUT_SMOKE");
    _ = env.orderedRemove("LOCALTERM_LIFECYCLE_SMOKE");
    _ = env.orderedRemove("LOCALTERM_LIFECYCLE_PSS");
    _ = env.orderedRemove("LOCALTERM_WORKER_STARTUP_FAILURE");
    _ = env.orderedRemove("LOCALTERM_TERMINAL_CASE");
    _ = env.orderedRemove("LOCALTERM_GPU_TEXT_FRAME_CHECK");
    _ = env.orderedRemove("LOCALTERM_VIEWPORT_SMOKE");
    if (self.app.fixture != .image_paste) _ = env.orderedRemove("LOCALTERM_EXPECT_IMAGE_ROOT");
    return env;
}

pub fn deinit(self: *Surface) void {
    self.quarantineFailedStartup();
    if (self.core_surface) |surface| {
        if (self.initialized) {
            // WM_CLOSE joins/deinitializes all workers before DestroyWindow.
            // Do not take the renderer draw mutex first: Frame.complete can
            // hold it while waiting for this UI thread's bounded mailbox.
            surface.deinit();
        }
        self.app.core_app.alloc.destroy(surface);
        self.core_surface = null;
    }
    self.initialized = false;
    if (self.image) |*image| image.deinit();
    self.image = null;
    if (self.title) |title| self.app.core_app.alloc.free(title);
    self.title = null;
    // Core/child shutdown above finishes before their image paths disappear.
    self.clipboard_images.deinit(self.app.core_app.alloc, global.io());
    if (self.clipboard_exe_dir) |path| self.app.core_app.alloc.free(path);
    self.clipboard_exe_dir = null;
    if (self.fixture_clipboard) |bytes| self.app.core_app.alloc.free(bytes);
    self.fixture_clipboard = null;
}

pub fn close(self: *Surface, _: bool) void {
    // Every close path goes through the window's native confirmation boundary.
    self.app.requestClose() catch |err| std.log.err("close failed: {}", .{err});
}

pub fn present(self: *Surface, hwnd: std.os.windows.HWND) !bool {
    if (!self.initialized) return false;
    const frame = self.core().renderer.takeFrame() orelse return false;
    defer frame.deinit();
    switch (frame) {
        .memory => |memory| {
            if (self.app.viewport_smoke) {
                if (memory.width != self.size.width or memory.height != self.size.height) return error.StaleViewportPresented;
                self.app.noteViewportFrame(memory.width, memory.height);
            }
            const image = try presenter.Image.fromRGBA(self.app.core_app.alloc, memory.width, memory.height, memory.pixels);
            if (self.image) |*old| old.deinit();
            self.image = image;
            self.app.frames += 1;
            try window.invalidate(hwnd);
            return true;
        },
        .dmabuf => unreachable,
    }
}

pub fn resize(self: *Surface, width: u32, height: u32) !void {
    if (width == 0 or height == 0) return;
    if (comptime @import("../../build_config.zig").windows_remote_renderer) {
        if (self.initialized and (self.size.width != width or self.size.height != height))
            try self.core().renderer.invalidateRemoteViewportFromUI(width, height, false);
    }
    self.size = .{ .width = width, .height = height };
    if (self.initialized) try self.core().sizeCallback(self.size);
}

pub fn setDpi(self: *Surface, dpi_value: u32) !void {
    const factor = @as(f32, @floatFromInt(dpi_value)) / 96.0;
    if (comptime @import("../../build_config.zig").windows_remote_renderer) {
        if (self.initialized and (self.scale.x != factor or self.scale.y != factor))
            try self.core().renderer.invalidateRemoteViewportFromUI(self.size.width, self.size.height, true);
    }
    self.scale = .{ .x = factor, .y = factor };
    if (self.initialized) try self.core().contentScaleCallback(self.scale);
}

pub fn setTitle(self: *Surface, hwnd: std.os.windows.HWND, text: []const u8) !void {
    if (self.app.worker_startup_failure == .title) {
        std.log.info("controlled worker startup injection=title", .{});
        return error.ControlledInitialTitleFailure;
    }
    const owned = try self.app.core_app.alloc.dupeZ(u8, text);
    errdefer self.app.core_app.alloc.free(owned);
    const display = try @import("sandbox_branding.zig").windowTitle(self.app.core_app.alloc, @import("../../build_config.zig").windows_sandbox_default, text);
    defer self.app.core_app.alloc.free(display);
    try window.setTitle(hwnd, self.app.core_app.alloc, display);
    if (self.title) |old| self.app.core_app.alloc.free(old);
    self.title = owned;
}

pub fn supportsClipboard(self: *const Surface, which: apprt.Clipboard) bool {
    return which == .standard and (!self.app.terminal_smoke or self.app.mouse_smoke);
}
pub fn clipboardRequest(self: *Surface, which: apprt.Clipboard, request: apprt.ClipboardRequest) !apprt.ClipboardReadResult {
    if (self.app.mouse_smoke) {
        // Test only the manual text-paste route. Refuse list/OSC/Kitty/image
        // requests before calling any Windows clipboard or dialog API.
        if (which != .standard or request != .paste) return .unsupported;
        const text = self.fixture_clipboard orelse return .unavailable;
        const contents: []const @import("../../terminal/clipboard.zig").Content = &.{.{ .mime = "text/plain", .data = text }};
        try self.core().completeClipboardRequest(request, .{ .contents = contents });
        self.fixture_clipboard_reads += 1;
        return .started;
    }
    if (self.app.terminal_smoke) return .unsupported; // No real reads in copy fixtures either.
    if (!self.supportsClipboard(which)) return .unsupported;
    const hwnd = self.app.hwnd orelse return .unavailable;
    switch (request) {
        .list => {
            try self.core().completeClipboardRequest(request, .{ .available = clipboard.mimeTypes() });
            return .started;
        },
        .kitty_read => return self.readClipboardMime(hwnd, request),
        .paste, .osc_52_read => {},
        else => return .unsupported, // Binary clipboard writes not supported.
    }
    if (request == .paste and clipboard.imageAvailable()) return self.pasteClipboardImage(hwnd);
    var confirmed = false;
    if (request == .osc_52_read) {
        if (!self.clipboardPermission("Allow the terminal application to read clipboard text?")) return .unsupported;
        confirmed = true;
    }
    const text = (clipboard.read(self.app.core_app.alloc, hwnd) catch |err| {
        std.log.warn("clipboard read unavailable: {}", .{err});
        return .unavailable;
    }) orelse return .unavailable;
    defer self.app.core_app.alloc.free(text);
    if (request == .paste and clipboard.multiline(text)) {
        if (!self.clipboardPermission("Clipboard text contains multiple lines. Paste it into this terminal?")) return .unsupported;
        confirmed = true;
    }
    const contents: []const @import("../../terminal/clipboard.zig").Content = &.{.{ .mime = "text/plain", .data = text }};
    self.core().completeClipboardRequest(request, .{ .contents = contents, .confirmed = confirmed }) catch |err| switch (err) {
        error.UnsafePaste, error.UnauthorizedPaste => {
            if (!self.clipboardPermission("Allow this clipboard operation? It may execute pasted commands.")) return .unsupported;
            try self.core().completeClipboardRequest(request, .{ .contents = contents, .confirmed = true });
        },
        else => return err,
    };
    return .started;
}

fn pasteClipboardImage(self: *Surface, hwnd: std.os.windows.HWND) !apprt.ClipboardReadResult {
    if (self.clipboard_images.items.items.len >= @import("clipboard_files.zig").max_files) return .unavailable;
    if (!self.clipboardPermission("Save clipboard image as a temporary PNG and paste its quoted path? The file is removed when this terminal closes.")) return .unsupported;
    const alloc = self.app.core_app.alloc;
    const png = (clipboard.readImage(alloc, hwnd) catch |err| {
        std.log.warn("clipboard image unavailable: {}", .{err});
        return .unavailable;
    }) orelse return .unavailable;
    defer alloc.free(png);
    return self.stageClipboardImage(hwnd, png);
}

fn stageClipboardImage(self: *Surface, hwnd: std.os.windows.HWND, png: []const u8) !apprt.ClipboardReadResult {
    const alloc = self.app.core_app.alloc;
    var env = try global.environMap();
    defer env.deinit();
    const exe_dir = self.clipboard_exe_dir orelse return .unavailable;
    const root = clipboard_paths.resolveSelected(alloc, global.io(), exe_dir, env.get("TEMP"), self.clipboard_portable) catch |err| {
        std.log.warn("clipboard image storage unavailable (no portable fallback): {}", .{err});
        self.imagePasteStorageError(hwnd);
        return .unavailable;
    };
    defer alloc.free(root.path);
    const path = self.clipboard_images.save(alloc, global.io(), root.path, png) catch |err| {
        std.log.warn("clipboard image staging failed: {}", .{err});
        self.imagePasteStorageError(hwnd);
        return .unavailable;
    };
    errdefer self.clipboard_images.rollback(alloc, global.io());
    try self.core().completeClipboardRequest(.{ .paste = .standard }, .{
        .contents = &.{.{ .mime = "text/plain", .data = path }},
        .confirmed = true,
    });
    return .started;
}

/// Only an explicitly selected synthetic fixture can call this. It exercises
/// the SAME production staging/core paste route without Windows clipboard IO.
pub fn pasteFixtureImage(self: *Surface) !void {
    if (self.app.fixture != .image_paste) return error.ImageFixtureNotSelected;
    const hwnd = self.app.hwnd orelse return error.WindowUnavailable;
    const png = try @import("image_paste_fixture.zig").png(self.app.core_app.alloc);
    defer self.app.core_app.alloc.free(png);
    if (try self.stageClipboardImage(hwnd, png) != .started) return error.ImageFixtureStagingFailed;
    std.log.info("controlled image staged portable={} bytes={d}; no OS clipboard access", .{ self.clipboard_portable, png.len });
}

fn imagePasteStorageError(self: *Surface, hwnd: std.os.windows.HWND) void {
    if (self.app.terminal_smoke) return; // Never show an automated failure modal.
    if (self.app.dialog_active) return;
    self.app.dialog_active = true;
    defer self.app.dialog_active = false;
    window.clipboardError(hwnd, @import("../../build_config.zig").windows_sandbox_default, "Cannot save clipboard image. Check storage permissions and session limits. Portable images are never redirected to host TEMP. See the error log for details.");
}

fn readClipboardMime(self: *Surface, hwnd: std.os.windows.HWND, request: apprt.ClipboardRequest) !apprt.ClipboardReadResult {
    const kitty = request.kitty_read;
    if (kitty.mimes.len == 0) {
        self.core().completeClipboardRequest(request, .{ .available = clipboard.mimeTypes(), .confirmed = true }) catch |err| {
            // Confirmed Kitty completion consumes its request even on failure.
            // Return started so the synchronous caller doesn't destroy it twice.
            std.log.warn("clipboard MIME listing completion failed: {}", .{err});
        };
        return .started;
    }
    if (!kitty.granted and !self.clipboardPermission("Allow the terminal application to read requested clipboard text or PNG image data?")) return .unsupported;
    var want_text = false;
    var want_png = false;
    for (kitty.mimes) |mime| {
        want_text = want_text or @import("../../terminal/clipboard.zig").isTextMime(mime);
        want_png = want_png or std.mem.eql(u8, mime, "image/png");
    }
    const alloc = self.app.core_app.alloc;
    const text = if (want_text) try clipboard.read(alloc, hwnd) else null;
    defer if (text) |bytes| alloc.free(bytes);
    const png = if (want_png) try clipboard.readImage(alloc, hwnd) else null;
    defer if (png) |bytes| alloc.free(bytes);
    var contents: [2]@import("../../terminal/clipboard.zig").Content = undefined;
    var count: usize = 0;
    if (text) |bytes| {
        contents[count] = .{ .mime = "text/plain", .data = bytes };
        count += 1;
    }
    if (png) |bytes| {
        contents[count] = .{ .mime = "image/png", .data = bytes };
        count += 1;
    }
    // Core restricts the response to the request's MIME list and owns the
    // protocol reply state. This binary route does not write images to disk.
    self.core().completeClipboardRequest(request, .{
        .contents = contents[0..count],
        .available = clipboard.mimeTypes(),
        .confirmed = true,
    }) catch |err| {
        std.log.warn("clipboard MIME completion failed after request consumption: {}", .{err});
    };
    return .started;
}

pub fn setClipboard(self: *Surface, which: apprt.Clipboard, contents: []const apprt.ClipboardContent, confirm: bool) !void {
    if (!self.supportsClipboard(which)) return error.ClipboardUnsupported;
    if (self.app.mouse_smoke) {
        for (contents) |content| {
            if (!std.mem.eql(u8, content.mime, "text/plain") and !std.mem.startsWith(u8, content.mime, "text/plain;")) continue;
            const owned = try self.app.core_app.alloc.dupe(u8, content.data);
            if (self.fixture_clipboard) |old| self.app.core_app.alloc.free(old);
            self.fixture_clipboard = owned;
            self.fixture_clipboard_writes += 1;
            return;
        }
        return error.ClipboardMimeUnsupported;
    }
    if (confirm and !self.clipboardPermission("Allow the terminal application to replace clipboard text?")) return;
    const hwnd = self.app.hwnd orelse return error.WindowUnavailable;
    for (contents) |content| {
        if (std.mem.eql(u8, content.mime, "text/plain") or std.mem.startsWith(u8, content.mime, "text/plain;")) {
            try clipboard.write(self.app.core_app.alloc, hwnd, content.data);
            return;
        }
    }
    return error.ClipboardMimeUnsupported;
}

fn clipboardPermission(self: *Surface, comptime message: []const u8) bool {
    if (self.app.dialog_active) return false;
    const hwnd = self.app.hwnd orelse return false;
    self.app.dialog_active = true;
    defer self.app.dialog_active = false;
    return window.confirmClipboard(hwnd, @import("../../build_config.zig").windows_sandbox_default, message);
}

pub fn expectFixtureCopy(self: *Surface, expected: []const u8) !void {
    if (!self.app.mouse_smoke) return error.MouseFixtureNotSelected;
    const actual = self.fixture_clipboard orelse return error.CopySinkMissing;
    if (!std.mem.eql(u8, expected, actual)) return error.CopySinkMismatch;
}

pub fn seedFixtureClipboard(self: *Surface, text: []const u8) !void {
    if (!self.app.mouse_smoke) return error.MouseFixtureNotSelected;
    const owned = try self.app.core_app.alloc.dupe(u8, text);
    if (self.fixture_clipboard) |old| self.app.core_app.alloc.free(old);
    self.fixture_clipboard = owned;
}
pub fn redrawInspector(_: *Surface) void {
    std.log.warn("Win32 inspector UI is not supported yet", .{});
}
