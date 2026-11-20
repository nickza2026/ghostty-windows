//! Opt-in app-local ConPTY experiment. Never search cwd/PATH or mix providers.
const std = @import("std");
const w = @import("os/main.zig").windows;
const log = std.log.scoped(.conpty);

const Create = *const fn (w.COORD, w.HANDLE, w.HANDLE, u32, *w.HPCON) callconv(.winapi) w.HRESULT;
const Resize = *const fn (w.HPCON, w.COORD) callconv(.winapi) w.HRESULT;
const Close = *const fn (w.HPCON) callconv(.winapi) void;
extern "kernel32" fn GetEnvironmentVariableW([*:0]const u16, [*]u16, u32) callconv(.winapi) u32;
extern "kernel32" fn GetModuleFileNameW(?std.os.windows.HMODULE, [*]u16, u32) callconv(.winapi) u32;
extern "kernel32" fn LoadLibraryExW([*:0]const u16, ?w.HANDLE, u32) callconv(.winapi) ?std.os.windows.HMODULE;
extern "kernel32" fn GetProcAddress(std.os.windows.HMODULE, [*:0]const u8) callconv(.winapi) ?*const anyopaque;
extern "kernel32" fn FreeLibrary(std.os.windows.HMODULE) callconv(.winapi) i32;

pub const Backend = struct {
    module: ?std.os.windows.HMODULE = null,
    create: Create = &w.exp.kernel32.CreatePseudoConsole,
    resize: Resize = &w.exp.kernel32.ResizePseudoConsole,
    close: Close = &w.exp.kernel32.ClosePseudoConsole,

    pub fn init() !Backend {
        var selection: [32]u16 = undefined;
        const n = GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("LOCALTERM_CONPTY_PROVIDER"), &selection, selection.len);
        if (n == 0) return .{};
        if (n >= selection.len) return error.InvalidConptyProvider;
        if (std.mem.eql(u16, selection[0..n], std.unicode.utf8ToUtf16LeStringLiteral("system"))) return .{};
        if (!std.mem.eql(u16, selection[0..n], std.unicode.utf8ToUtf16LeStringLiteral("app-local"))) return error.InvalidConptyProvider;
        const enabled = GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("LOCALTERM_CONPTY_EXPERIMENT"), &selection, selection.len);
        if (enabled != 1 or selection[0] != '1') return error.ConptyExperimentNotEnabled;

        var path: [32768]u16 = undefined;
        const length = GetModuleFileNameW(null, &path, path.len);
        if (length == 0 or length >= path.len) return error.ConptyExecutablePath;
        const separator = std.mem.lastIndexOfScalar(u16, path[0..length], '\\') orelse return error.ConptyExecutablePath;
        const dll = std.unicode.utf8ToUtf16LeStringLiteral("conpty.dll");
        const end = separator + 1 + dll.len;
        if (end >= path.len) return error.ConptyExecutablePath;
        @memcpy(path[separator + 1 .. end], dll);
        path[end] = 0;
        // DLL directory + System32 only. Never use the caller's cwd/PATH.
        const module = LoadLibraryExW(path[0..end :0].ptr, null, 0x00000900) orelse {
            log.err("app-local ConPTY load failed win32={}; refusing system fallback", .{w.GetLastError()});
            return error.ConptyLoadFailed;
        };
        errdefer _ = FreeLibrary(module);
        const result: Backend = .{
            .module = module,
            .create = @ptrCast(GetProcAddress(module, "ConptyCreatePseudoConsole") orelse return error.ConptyMissingCreate),
            .resize = @ptrCast(GetProcAddress(module, "ConptyResizePseudoConsole") orelse return error.ConptyMissingResize),
            .close = @ptrCast(GetProcAddress(module, "ConptyClosePseudoConsole") orelse return error.ConptyMissingClose),
        };
        log.info("experimental app-local ConPTY loaded from executable directory; Create/Resize/Close share provider; no system fallback", .{});
        return result;
    }

    /// Only after every HPCON created by this instance has been closed.
    pub fn deinit(self: *Backend) void {
        if (self.module) |module| _ = FreeLibrary(module);
        self.* = undefined;
    }
};
