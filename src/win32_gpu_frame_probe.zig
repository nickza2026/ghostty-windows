//! Dedicated trusted GPU producer for the bounded frame-IPC component PoC.
const std = @import("std");
const gl = @import("opengl");
const wgl = @import("renderer/opengl/wgl.zig");
const w = std.os.windows;
const wire = @cImport(@cInclude("gpu_frame_protocol.h"));
extern "kernel32" fn GetEnvironmentVariableW([*:0]const u16, [*]u16, u32) callconv(.winapi) u32;
extern "kernel32" fn MapViewOfFile(w.HANDLE, u32, u32, u32, usize) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn UnmapViewOfFile(*const anyopaque) callconv(.winapi) i32;
extern "kernel32" fn CloseHandle(w.HANDLE) callconv(.winapi) i32;
extern "kernel32" fn SetEvent(w.HANDLE) callconv(.winapi) i32;
extern "kernel32" fn WaitForSingleObject(w.HANDLE, u32) callconv(.winapi) u32;
extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
extern "kernel32" fn ExitProcess(u32) callconv(.winapi) noreturn;
extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
extern "user32" fn GetSystemMetrics(i32) callconv(.winapi) i32;
extern "user32" fn SetProcessDpiAwarenessContext(isize) callconv(.winapi) i32;
extern "user32" fn SetWindowPos(w.HWND, ?w.HWND, i32, i32, i32, i32, u32) callconv(.winapi) i32;

fn env(comptime name: []const u8, buf: []u16) ![]const u16 {
    const n = GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral(name), buf.ptr, @intCast(buf.len));
    if (n == 0 or n >= buf.len) return error.InvalidControl;
    return buf[0..n];
}
fn handle(comptime name: []const u8) !w.HANDLE {
    var b: [32]u16 = undefined;
    const text = try env(name, &b);
    var ascii: [32]u8 = undefined;
    for (text, 0..) |ch, i| {
        if (ch > 127) return error.InvalidControl;
        ascii[i] = @intCast(ch);
    }
    const value = try std.fmt.parseInt(usize, ascii[0..text.len], 16);
    if (value == 0 or value == std.math.maxInt(usize)) return error.InvalidControl;
    return @ptrFromInt(value);
}
fn isMode(mode: []const u16, comptime text: []const u8) bool {
    return std.mem.eql(u16, mode, std.unicode.utf8ToUtf16LeStringLiteral(text));
}

const Work = struct {
    context: *wgl.Context,
    map: *wire.GpuFrameMap,
    width: u32,
    height: u32,
    failure: ?anyerror = null,
    fn run(self: *Work) void {
        draw(self.context, self.map, self.width, self.height) catch |err| {
            self.failure = err;
        };
    }
};

fn draw(context: *wgl.Context, m: *wire.GpuFrameMap, width: u32, height: u32) !void {
    try context.makeCurrent();
    defer wgl.Context.releaseCurrent();
    const version = try gl.glad.load(&wgl.getProcAddress);
    defer gl.glad.unload();
    const major = gl.glad.versionMajor(@intCast(version));
    const minor = gl.glad.versionMinor(@intCast(version));
    if (major < 4 or (major == 4 and minor < 3)) return error.OpenGLOutdated;
    const api = &gl.glad.context;
    var texture: gl.c.GLuint = 0;
    var fbo: gl.c.GLuint = 0;
    api.GenTextures.?(1, &texture);
    defer api.DeleteTextures.?(1, &texture);
    api.BindTexture.?(gl.c.GL_TEXTURE_2D, texture);
    api.TexParameteri.?(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MIN_FILTER, gl.c.GL_NEAREST);
    api.TexParameteri.?(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MAG_FILTER, gl.c.GL_NEAREST);
    api.TexImage2D.?(gl.c.GL_TEXTURE_2D, 0, gl.c.GL_RGBA8, @intCast(width), @intCast(height), 0, gl.c.GL_RGBA, gl.c.GL_UNSIGNED_BYTE, null);
    api.GenFramebuffers.?(1, &fbo);
    defer api.DeleteFramebuffers.?(1, &fbo);
    api.BindFramebuffer.?(gl.c.GL_FRAMEBUFFER, fbo);
    api.FramebufferTexture2D.?(gl.c.GL_FRAMEBUFFER, gl.c.GL_COLOR_ATTACHMENT0, gl.c.GL_TEXTURE_2D, texture, 0);
    if (api.CheckFramebufferStatus.?(gl.c.GL_FRAMEBUFFER) != gl.c.GL_FRAMEBUFFER_COMPLETE) return error.IncompleteFramebuffer;
    api.Viewport.?(0, 0, @intCast(width), @intCast(height));
    api.Enable.?(gl.c.GL_SCISSOR_TEST);
    const colors = [_][4]f32{ .{ 1, 0, 0, 1 }, .{ 0, 1, 0, 1 }, .{ 0, 0, 1, 1 }, .{ 1, 1, 1, 1 } };
    for (colors, 0..) |color, i| {
        const x: u32 = if (i % 2 == 0) 0 else width / 2;
        const y: u32 = if (i / 2 == 0) 0 else height / 2;
        const rw = if (i % 2 == 0) width / 2 else width - width / 2;
        const rh = if (i / 2 == 0) height / 2 else height - height / 2;
        api.Scissor.?(@intCast(x), @intCast(y), @intCast(rw), @intCast(rh));
        api.ClearColor.?(color[0], color[1], color[2], color[3]);
        api.Clear.?(gl.c.GL_COLOR_BUFFER_BIT);
    }
    api.Disable.?(gl.c.GL_SCISSOR_TEST);
    api.ReadPixels.?(0, 0, @intCast(width), @intCast(height), gl.c.GL_RGBA, gl.c.GL_UNSIGNED_BYTE, &m.pixels);
    api.Finish.?();
    if (api.GetError.?() != gl.c.GL_NO_ERROR) return error.OpenGLFailure;
    // Validate every GPU readback pixel before publication; parent rechecks.
    for (0..height) |y| for (0..width) |x| {
        const q: usize = @as(usize, if (y < height / 2) 0 else 2) + @as(usize, if (x < width / 2) 0 else 1);
        const p = (y * width + x) * 4;
        for (0..4) |c| {
            const expected: u8 = if (colors[q][c] == 1) 255 else 0;
            if (m.pixels[p + c] != expected) return error.PixelReadbackMismatch;
        }
    };
}

pub fn main() !void {
    comptime {
        if (@offsetOf(wire.GpuFrameMap, "pixels") != wire.GF_HEADER_BYTES) @compileError("IPC ABI offset mismatch");
    }
    if (SetProcessDpiAwarenessContext(-4) == 0) return error.PhysicalCoordinatesUnavailable;
    const mapping = try handle("LOCALTERM_FRAME_MAP");
    defer _ = CloseHandle(mapping);
    const request = try handle("LOCALTERM_FRAME_REQUEST");
    defer _ = CloseHandle(request);
    const response = try handle("LOCALTERM_FRAME_RESPONSE");
    defer _ = CloseHandle(response);
    const raw = MapViewOfFile(mapping, 0x000f001f, 0, 0, @sizeOf(wire.GpuFrameMap)) orelse return error.MappingFailed;
    defer _ = UnmapViewOfFile(raw);
    const m: *wire.GpuFrameMap = @ptrCast(@alignCast(raw));
    if (m.magic != wire.GF_MAGIC or m.version != wire.GF_VERSION or m.mapping_bytes != @sizeOf(wire.GpuFrameMap) or m.capacity != wire.GF_CAPACITY) return error.InvalidMapping;
    var text: [40]u16 = undefined;
    const mode = try env("LOCALTERM_FRAME_MODE", &text);
    var known = false;
    inline for (.{ "positive", "crash", "hang", "close-hang", "bad-close", "stale-sequence", "stale-epoch", "bad-stride", "bad-size", "bad-version", "truncated", "bad-pixel", "bad-dimensions", "bad-commit", "bad-header", "bad-capacity" }) |name| {
        if (isMode(mode, name)) known = true;
    }
    if (!known) return error.InvalidControl;
    var context = try wgl.Context.create();
    defer context.deinit();
    if (SetWindowPos(context.hwnd, null, GetSystemMetrics(76) + GetSystemMetrics(78) + 64, GetSystemMetrics(77), 0, 0, 0x0015) == 0) return error.OffscreenFailed;
    var last_sequence: u32 = 0;
    var frames: u32 = 0;
    while (true) {
        if (WaitForSingleObject(request, 15000) != 0) return error.RequestDeadline;
        const seq = m.sequence;
        const epoch = m.epoch;
        if (seq == 0 or seq > std.math.maxInt(i32) or seq <= last_sequence or epoch == 0) return error.InvalidRequest;
        last_sequence = seq;
        if (m.command == wire.GF_CLOSE) {
            if (isMode(mode, "close-hang")) Sleep(60000);
            m.status = wire.GF_CLOSED;
            m.response_magic = wire.GF_MAGIC;
            m.response_version = wire.GF_VERSION;
            m.header_bytes = wire.GF_HEADER_BYTES;
            m.payload_bytes = 0;
            m.frame_sequence = seq;
            m.frame_epoch = epoch;
            if (isMode(mode, "bad-close")) m.frame_sequence = seq - 1;
            @atomicStore(i32, @as(*i32, @ptrCast(&m.commit)), @intCast(seq), .release);
            if (SetEvent(response) == 0) return error.PublishFailed;
            std.debug.print("GPU_FRAME_CHILD_OK pid={d} frames={d} closed=1\n", .{ GetCurrentProcessId(), frames });
            return;
        }
        if (m.command != wire.GF_RENDER or m.width < 2 or m.height < 2 or m.width > wire.GF_MAX_W or m.height > wire.GF_MAX_H) return error.InvalidRequest;
        if (isMode(mode, "crash")) ExitProcess(27);
        if (isMode(mode, "hang")) Sleep(60000);
        var work: Work = .{ .context = &context, .map = m, .width = m.width, .height = m.height };
        if (frames % 2 == 0) try draw(&context, m, m.width, m.height) else {
            const worker = try std.Thread.spawn(.{}, Work.run, .{&work});
            worker.join();
            if (work.failure) |err| return err;
        }
        m.status = wire.GF_FRAME;
        m.response_magic = wire.GF_MAGIC;
        m.response_version = wire.GF_VERSION;
        m.header_bytes = wire.GF_HEADER_BYTES;
        m.frame_epoch = epoch;
        m.frame_sequence = seq;
        m.frame_width = m.width;
        m.frame_height = m.height;
        m.stride = m.width * 4;
        m.payload_bytes = m.stride * m.height;
        if (isMode(mode, "stale-sequence")) m.frame_sequence = seq - 1;
        if (isMode(mode, "stale-epoch") and frames != 0) m.frame_epoch = epoch - 1;
        if (isMode(mode, "bad-stride")) m.stride = 0xfffffffc;
        if (isMode(mode, "bad-size")) m.payload_bytes = wire.GF_CAPACITY + 1;
        if (isMode(mode, "bad-version")) m.response_version = 99;
        if (isMode(mode, "bad-dimensions")) m.frame_width = 0xffffffff;
        if (isMode(mode, "bad-header")) m.header_bytes = wire.GF_HEADER_BYTES + 4;
        if (isMode(mode, "bad-capacity")) m.capacity = wire.GF_CAPACITY - 4;
        if (isMode(mode, "truncated")) m.payload_bytes -= 4;
        if (isMode(mode, "bad-pixel")) m.pixels[0] ^= 1;
        frames += 1;
        @atomicStore(i32, @as(*i32, @ptrCast(&m.commit)), @intCast(if (isMode(mode, "bad-commit")) seq - 1 else seq), .release);
        if (SetEvent(response) == 0) return error.PublishFailed;
    }
}
