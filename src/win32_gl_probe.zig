//! Native graphics capability/lifetime gate, deliberately without CoreSurface/PTY.
const std = @import("std");
const gl = @import("opengl");
const wgl = @import("renderer/opengl/wgl.zig");
const w = std.os.windows;
const window_diagnostics = @import("apprt/win32/window.zig");
extern fn localterm_win32_handle_inventory(*const fn (usize, u32, u32, u32, [*:0]const u8) callconv(.c) void) callconv(.c) u32;

// Explicit debugger-only marker. CDB can snapshot/diff handle traces here
// without break instructions, new warmups or production lifecycle changes.
export var localterm_htrace_phase: u32 = 0;
export fn localterm_htrace_marker(phase: u32) callconv(.c) void {
    @atomicStore(u32, &localterm_htrace_phase, phase, .seq_cst);
}

fn emitHandle(handle: usize, kind: u32, target: u32, access: u32, label: [*:0]const u8) callconv(.c) void {
    std.debug.print("WGL handle inventory handle=0x{x} kind={d} target={d} access=0x{x} type={s}\n", .{ handle, kind, target, access, std.mem.span(label) });
    if (kind == 2 and target != 0) window_diagnostics.describeThread(target);
}

fn inventory(phase: []const u8) !void {
    std.debug.print("WGL handle inventory phase={s}\n", .{phase});
    if (localterm_win32_handle_inventory(&emitHandle) != 0) return error.WglInventoryUnavailable;
}

extern "kernel32" fn GetCurrentProcess() callconv(.winapi) w.HANDLE;
extern "kernel32" fn GetProcessHandleCount(w.HANDLE, *u32) callconv(.winapi) i32;
extern "kernel32" fn GetEnvironmentVariableW([*:0]const u16, [*]u16, u32) callconv(.winapi) u32;
extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
extern "user32" fn GetGuiResources(w.HANDLE, u32) callconv(.winapi) u32;
extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
extern "user32" fn GetSystemMetrics(i32) callconv(.winapi) i32;
extern "user32" fn SetWindowPos(w.HWND, ?w.HWND, i32, i32, i32, i32, u32) callconv(.winapi) i32;

var corrupt_child_pixel = false;
var verified_draws = std.atomic.Value(u32).init(0);
var cycle_hold_ms: u32 = 3000;

fn childCycle() !void {
    var mode: [32]u16 = undefined;
    const n = GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("LOCALTERM_GL_CHILD_NEGATIVE"), &mode, mode.len);
    if (n >= mode.len) return error.InvalidChildControl;
    const missing = std.mem.eql(u16, mode[0..n], std.unicode.utf8ToUtf16LeStringLiteral("missing-receipt"));
    const hang = std.mem.eql(u16, mode[0..n], std.unicode.utf8ToUtf16LeStringLiteral("hang"));
    const long = std.mem.eql(u16, mode[0..n], std.unicode.utf8ToUtf16LeStringLiteral("long"));
    corrupt_child_pixel = std.mem.eql(u16, mode[0..n], std.unicode.utf8ToUtf16LeStringLiteral("bad-pixels"));
    if (n != 0 and !missing and !hang and !long and !corrupt_child_pixel) return error.InvalidChildControl;
    cycle_hold_ms = if (long) 15000 else 3000;
    const before = try Counts.read();
    try contextCycle(true, true); // Three verified draws and real UI/worker/UI handoff.
    if (hang) Sleep(60000); // Parent must fail closed and terminate only its job.
    const after = try Counts.read();
    if (verified_draws.load(.monotonic) != 3) return error.ChildDrawCoverageMissing;
    std.debug.print("GPU_CHILD_STATE pid={d} handles={d}->{d} GDI={d}->{d} USER={d}->{d}; process-global driver state is NOT waived in native gate\n", .{ GetCurrentProcessId(), before.handles, after.handles, before.gdi, after.gdi, before.user, after.user });
    if (!missing) std.debug.print("GPU_CHILD_OK pid={d} draws=3 rgba=16/16 hidden_noactivate=1 hold_ms={d}\n", .{ GetCurrentProcessId(), @as(u32, if (long) 15000 else 3000) });
}

const Counts = struct {
    handles: u32,
    gdi: u32,
    user: u32,
    fn read() !Counts {
        var handles: u32 = 0;
        const process = GetCurrentProcess();
        if (GetProcessHandleCount(process, &handles) == 0) return error.HandleCountFailed;
        return .{ .handles = handles, .gdi = GetGuiResources(process, 0), .user = GetGuiResources(process, 1) };
    }
};

pub fn main() !void {
    var setting: [2]u16 = undefined;
    const child = GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("LOCALTERM_GL_CHILD_CONTROL"), &setting, setting.len);
    if (child != 0) {
        if (child != 1 or setting[0] != '1') return error.InvalidChildControl;
        return childCycle();
    }
    const length = GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("LOCALTERM_GL_PACED_CONTROL"), &setting, setting.len);
    const paced = length != 0;
    if (paced and (length != 1 or setting[0] != '1')) return error.InvalidPacingControl;
    const trace_length = GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("LOCALTERM_GL_HTRACE_CONTROL"), &setting, setting.len);
    const htrace = trace_length != 0;
    if (htrace and (!paced or trace_length != 1 or setting[0] != '1')) return error.InvalidHandleTraceControl;
    if (htrace) std.debug.print("CDB handle-creation attribution control; normal heap; not readiness evidence\n", .{});
    if (paced) std.debug.print("paced WGL attribution control: hold each hidden context 3000ms; no core/PTY; not readiness evidence\n", .{});
    var baseline: Counts = undefined;
    for (0..21) |cycle| {
        try contextCycle(cycle == 0, paced);
        if (cycle == 0) {
            baseline = try Counts.read();
            if (paced) try inventory("baseline");
            if (htrace) @call(.never_inline, localterm_htrace_marker, .{@as(u32, 1)});
        }
        if (paced) {
            const counts = try Counts.read();
            std.debug.print("paced WGL cycle={d} handles={d} GDI={d} USER={d}\n", .{ cycle, counts.handles, counts.gdi, counts.user });
        }
    }
    const final = try Counts.read();
    if (paced) try inventory("final");
    if (htrace) @call(.never_inline, localterm_htrace_marker, .{@as(u32, 2)});
    std.debug.print("WGL probe: 20 cycles after warmup; handles {d}->{d}, GDI {d}->{d}, USER {d}->{d}; UI/worker/UI handoff and RGBA FBO readback; no core/PTY\n", .{ baseline.handles, final.handles, baseline.gdi, final.gdi, baseline.user, final.user });
    if (final.handles > baseline.handles or final.gdi > baseline.gdi or final.user > baseline.user)
        return error.GraphicsResourceGrowth;
}

fn contextCycle(describe: bool, paced: bool) !void {
    var context = try wgl.Context.create();
    defer context.deinit();
    // Keep even the invisible diagnostic host beyond all monitor bounds.
    const x = GetSystemMetrics(76) + GetSystemMetrics(78) + 64;
    const y = GetSystemMetrics(77);
    if (SetWindowPos(context.hwnd, null, x, y, 0, 0, 0x0015) == 0) return error.OffscreenPlacementFailed;
    try draw(&context, describe);
    // The owner has released current before the worker binds the same context.
    var work: Work = .{ .context = &context };
    const thread = try std.Thread.spawn(.{}, Work.run, .{&work});
    thread.join();
    if (work.failure) |err| return err;
    try draw(&context, false);
    // Match real-surface cycle lifetime, keeping the same one-warmup/21-cycle
    // counter gate. This does NOT prewarm extra contexts or alter the threshold.
    if (paced) Sleep(cycle_hold_ms);
}

const Work = struct {
    context: *wgl.Context,
    failure: ?anyerror = null,
    fn run(self: *Work) void {
        draw(self.context, false) catch |err| {
            self.failure = err;
        };
    }
};

fn draw(context: *wgl.Context, describe: bool) !void {
    try context.makeCurrent();
    defer wgl.Context.releaseCurrent();
    const version = try gl.glad.load(&wgl.getProcAddress);
    defer gl.glad.unload();
    const major = gl.glad.versionMajor(@intCast(version));
    const minor = gl.glad.versionMinor(@intCast(version));
    if (major < 4 or (major == 4 and minor < 3)) return error.OpenGLOutdated;
    const api = &gl.glad.context;
    if (describe) {
        for ([_]gl.c.GLenum{ gl.c.GL_VENDOR, gl.c.GL_RENDERER, gl.c.GL_VERSION }) |name| {
            const value = api.GetString.?(name);
            if (value == null) return error.MissingGLDescription;
            const text: [*:0]const u8 = @ptrCast(value);
            std.debug.print("GL {x}: {s}\n", .{ name, std.mem.span(text) });
        }
    }
    var texture: gl.c.GLuint = 0;
    var framebuffer: gl.c.GLuint = 0;
    api.GenTextures.?(1, &texture);
    defer api.DeleteTextures.?(1, &texture);
    api.BindTexture.?(gl.c.GL_TEXTURE_2D, texture);
    api.TexParameteri.?(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MIN_FILTER, gl.c.GL_NEAREST);
    api.TexParameteri.?(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MAG_FILTER, gl.c.GL_NEAREST);
    api.TexImage2D.?(gl.c.GL_TEXTURE_2D, 0, gl.c.GL_RGBA8, 2, 2, 0, gl.c.GL_RGBA, gl.c.GL_UNSIGNED_BYTE, null);
    api.GenFramebuffers.?(1, &framebuffer);
    defer api.DeleteFramebuffers.?(1, &framebuffer);
    api.BindFramebuffer.?(gl.c.GL_FRAMEBUFFER, framebuffer);
    api.FramebufferTexture2D.?(gl.c.GL_FRAMEBUFFER, gl.c.GL_COLOR_ATTACHMENT0, gl.c.GL_TEXTURE_2D, texture, 0);
    if (api.CheckFramebufferStatus.?(gl.c.GL_FRAMEBUFFER) != gl.c.GL_FRAMEBUFFER_COMPLETE)
        return error.IncompleteFramebuffer;
    api.Viewport.?(0, 0, 2, 2);
    api.Enable.?(gl.c.GL_SCISSOR_TEST);
    const colors = [_][4]f32{ .{ 1, 0, 0, 1 }, .{ 0, 1, 0, 1 }, .{ 0, 0, 1, 1 }, .{ 1, 1, 1, 1 } };
    for (colors, 0..) |color, index| {
        api.Scissor.?(@intCast(index % 2), @intCast(index / 2), 1, 1);
        api.ClearColor.?(color[0], color[1], color[2], color[3]);
        api.Clear.?(gl.c.GL_COLOR_BUFFER_BIT);
    }
    api.Disable.?(gl.c.GL_SCISSOR_TEST);
    var pixels: [16]u8 = undefined;
    api.ReadPixels.?(0, 0, 2, 2, gl.c.GL_RGBA, gl.c.GL_UNSIGNED_BYTE, &pixels);
    api.Finish.?();
    if (corrupt_child_pixel) pixels[0] ^= 1; // Negative control; never production.
    if (api.GetError.?() != gl.c.GL_NO_ERROR) return error.OpenGLFailure;
    const expected = [_]u8{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 };
    if (!std.mem.eql(u8, &pixels, &expected)) return error.PixelReadbackMismatch;
    _ = verified_draws.fetchAdd(1, .monotonic);
}
