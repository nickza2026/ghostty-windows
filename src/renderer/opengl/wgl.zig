//! Windows desktop OpenGL context ownership. No EGL provider is needed.
//! Context hosts are hidden and independent of the visible DIB-painted window.
const std = @import("std");
const w = std.os.windows;
const root = @import("root");
const fixture_offscreen = if (@hasDecl(root, "gpu_worker_offscreen_context")) root.gpu_worker_offscreen_context else false;
const Allocator = std.mem.Allocator;
const Rect = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
const Class = extern struct {
    size: u32 = @sizeOf(Class),
    style: u32 = 0x0020, // CS_OWNDC
    proc: *const fn (w.HWND, u32, usize, isize) callconv(.winapi) isize = DefWindowProcW,
    class_extra: i32 = 0,
    window_extra: i32 = 0,
    instance: w.HINSTANCE,
    icon: ?*anyopaque = null,
    cursor: ?*anyopaque = null,
    brush: ?*anyopaque = null,
    menu: ?[*:0]const u16 = null,
    name: [*:0]const u16 = class_name,
    small_icon: ?*anyopaque = null,
};
const PixelFormat = extern struct {
    size: u16 = @sizeOf(PixelFormat),
    version: u16 = 1,
    flags: u32 = 0x0024, // PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL (FBO rendering)
    pixel_type: u8 = 0,
    color_bits: u8 = 32,
    red_bits: u8 = 0,
    red_shift: u8 = 0,
    green_bits: u8 = 0,
    green_shift: u8 = 0,
    blue_bits: u8 = 0,
    blue_shift: u8 = 0,
    alpha_bits: u8 = 8,
    alpha_shift: u8 = 0,
    accum_bits: u8 = 0,
    accum_red: u8 = 0,
    accum_green: u8 = 0,
    accum_blue: u8 = 0,
    accum_alpha: u8 = 0,
    depth_bits: u8 = 24,
    stencil_bits: u8 = 8,
    aux_buffers: u8 = 0,
    layer_type: u8 = 0,
    reserved: u8 = 0,
    layer_mask: u32 = 0,
    visible_mask: u32 = 0,
    damage_mask: u32 = 0,
};
comptime {
    std.debug.assert(@sizeOf(PixelFormat) == 40);
}

extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.winapi) ?w.HMODULE;
extern "kernel32" fn GetProcAddress(w.HMODULE, [*:0]const u8) callconv(.winapi) ?*const anyopaque;
extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;
extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
extern "user32" fn GetSystemMetrics(i32) callconv(.winapi) i32;
extern "user32" fn GetWindowRect(w.HWND, *Rect) callconv(.winapi) i32;
extern "user32" fn IsWindowVisible(w.HWND) callconv(.winapi) i32;
extern "user32" fn RegisterClassExW(*const Class) callconv(.winapi) u16;
extern "user32" fn UnregisterClassW([*:0]const u16, w.HINSTANCE) callconv(.winapi) i32;
extern "user32" fn CreateWindowExW(u32, [*:0]const u16, [*:0]const u16, u32, i32, i32, i32, i32, ?w.HWND, ?*anyopaque, w.HINSTANCE, ?*anyopaque) callconv(.winapi) ?w.HWND;
extern "user32" fn DefWindowProcW(w.HWND, u32, usize, isize) callconv(.winapi) isize;
extern "user32" fn DestroyWindow(w.HWND) callconv(.winapi) i32;
extern "user32" fn GetDC(w.HWND) callconv(.winapi) ?w.HDC;
extern "user32" fn ReleaseDC(w.HWND, w.HDC) callconv(.winapi) i32;
extern "gdi32" fn ChoosePixelFormat(w.HDC, *const PixelFormat) callconv(.winapi) i32;
extern "gdi32" fn SetPixelFormat(w.HDC, i32, *const PixelFormat) callconv(.winapi) i32;
extern "opengl32" fn wglCreateContext(w.HDC) callconv(.winapi) ?w.HGLRC;
extern "opengl32" fn wglDeleteContext(w.HGLRC) callconv(.winapi) i32;
extern "opengl32" fn wglMakeCurrent(?w.HDC, ?w.HGLRC) callconv(.winapi) i32;
extern "opengl32" fn wglGetProcAddress([*:0]const u8) callconv(.winapi) ?*const anyopaque;

const class_name = std.unicode.utf8ToUtf16LeStringLiteral("localterm-dev.wgl-context-host");
// Hosts are created/destroyed on the UI thread, never the renderer thread.
var host_count: usize = 0;

pub const Device = struct {
    pub const Options = struct {};
    owner_thread: u32,

    pub fn init(alloc: Allocator, _: Options) !*Device {
        const self = try alloc.create(Device);
        self.* = .{ .owner_thread = GetCurrentThreadId() };
        return self;
    }

    pub fn deinit(self: *Device, alloc: Allocator) void {
        std.debug.assert(GetCurrentThreadId() == self.owner_thread);
        alloc.destroy(self);
    }

    pub fn createContext(self: *const Device) !Context {
        if (GetCurrentThreadId() != self.owner_thread) return error.WrongContextHostThread;
        return Context.create();
    }
};

pub const Context = struct {
    hwnd: w.HWND,
    dc: w.HDC,
    handle: w.HGLRC,
    instance: w.HINSTANCE,
    owner_thread: u32,

    pub fn create() !Context {
        const instance: w.HINSTANCE = @ptrCast(GetModuleHandleW(null) orelse return error.ModuleHandleFailed);
        const first = host_count == 0;
        if (first) {
            const class: Class = .{ .instance = instance };
            if (RegisterClassExW(&class) == 0) return error.RegisterContextClassFailed;
        }
        errdefer if (first) {
            _ = UnregisterClassW(class_name, instance);
        };
        // Private fixture roots only. Production keeps its original (0,0)
        // hidden host; no ShowWindow/focus or driver-setting change here.
        const x: i32 = if (fixture_offscreen) GetSystemMetrics(76) - 256 else 0;
        const y: i32 = if (fixture_offscreen) GetSystemMetrics(77) - 256 else 0;
        const hwnd = CreateWindowExW(0, class_name, class_name, 0x80000000, x, y, 1, 1, null, null, instance, null) orelse return error.ContextHostFailed;
        errdefer _ = DestroyWindow(hwnd);
        if (fixture_offscreen) {
            var rect: Rect = undefined;
            if (GetWindowRect(hwnd, &rect) == 0 or IsWindowVisible(hwnd) != 0 or
                rect.right >= GetSystemMetrics(76) or rect.bottom >= GetSystemMetrics(77)) return error.FixtureContextNotOffscreen;
            std.debug.print("WORKER_OFFSCREEN_OK pid={d} left={d} top={d} right={d} bottom={d} visible=0\n", .{ GetCurrentProcessId(), rect.left, rect.top, rect.right, rect.bottom });
        }
        const dc = GetDC(hwnd) orelse return error.ContextDCFailed;
        errdefer _ = ReleaseDC(hwnd, dc);
        const format: PixelFormat = .{};
        const index = ChoosePixelFormat(dc, &format);
        if (index == 0 or SetPixelFormat(dc, index, &format) == 0) return error.PixelFormatFailed;

        const bootstrap = wglCreateContext(dc) orelse return error.BootstrapContextFailed;
        var bootstrap_live = true;
        defer if (bootstrap_live) {
            _ = wglMakeCurrent(null, null);
            _ = wglDeleteContext(bootstrap);
        };
        if (wglMakeCurrent(dc, bootstrap) == 0) return error.MakeCurrentFailed;
        const proc = wglGetProcAddress("wglCreateContextAttribsARB") orelse return error.DesktopGL43Unavailable;
        if (!validProc(proc)) return error.DesktopGL43Unavailable;
        const Create = *const fn (w.HDC, ?w.HGLRC, [*:0]const i32) callconv(.winapi) ?w.HGLRC;
        const create_context: Create = @ptrCast(proc);
        // Request desktop GL 4.3 core, not OpenGL ES or a legacy fallback.
        const attributes = [_:0]i32{ 0x2091, 4, 0x2092, 3, 0x9126, 1 };
        if (wglMakeCurrent(null, null) == 0) return error.ReleaseCurrentFailed;
        const handle = create_context(dc, null, &attributes) orelse return error.DesktopGL43Unavailable;
        errdefer _ = wglDeleteContext(handle);
        if (wglDeleteContext(bootstrap) == 0) return error.DeleteBootstrapFailed;
        bootstrap_live = false;
        host_count += 1;
        return .{ .hwnd = hwnd, .dc = dc, .handle = handle, .instance = instance, .owner_thread = GetCurrentThreadId() };
    }

    pub fn makeCurrent(self: *const Context) !void {
        if (wglMakeCurrent(self.dc, self.handle) == 0) return error.MakeCurrentFailed;
    }

    pub fn releaseCurrent() void {
        if (wglMakeCurrent(null, null) == 0) std.log.err("WGL release current failed error={d}", .{@intFromEnum(w.GetLastError())});
    }

    pub fn deinit(self: *Context) void {
        std.debug.assert(GetCurrentThreadId() == self.owner_thread);
        // Renderer must have unbound and joined before this owner-thread call.
        if (wglDeleteContext(self.handle) == 0) {
            std.log.err("WGL delete context failed error={d}", .{@intFromEnum(w.GetLastError())});
            return; // Do not destroy the host beneath a still-live context.
        }
        _ = ReleaseDC(self.hwnd, self.dc); // CS_OWNDC itself belongs to the HWND.
        _ = DestroyWindow(self.hwnd);
        host_count -= 1;
        if (host_count == 0) _ = UnregisterClassW(class_name, self.instance);
        self.* = undefined;
    }
};

fn validProc(proc: *const anyopaque) bool {
    const address = @intFromPtr(proc);
    return address > 3 and address != std.math.maxInt(usize);
}

pub fn getProcAddress(name: [*:0]const u8) callconv(.c) ?*const fn () callconv(.c) void {
    if (wglGetProcAddress(name)) |proc| {
        if (validProc(proc)) return @ptrCast(proc);
    }
    const module = GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("opengl32.dll")) orelse return null;
    return @ptrCast(GetProcAddress(module, name));
}
