//! Component cost only: offscreen WGL readback -> conversion -> memory-DC DIB.
//! Not terminal FPS, window/compositor latency, font shaping, or input latency.
const std = @import("std");
const gl = @import("opengl");
const wgl = @import("renderer/opengl/wgl.zig");
const presenter = @import("apprt/win32/presenter.zig");
const w = std.os.windows;
extern "kernel32" fn QueryPerformanceCounter(*i64) callconv(.winapi) i32;
extern "kernel32" fn QueryPerformanceFrequency(*i64) callconv(.winapi) i32;
extern "gdi32" fn CreateCompatibleDC(?w.HDC) callconv(.winapi) ?w.HDC;
extern "gdi32" fn DeleteDC(w.HDC) callconv(.winapi) i32;
extern "gdi32" fn CreateDIBSection(w.HDC, *const Bitmap, u32, *?*anyopaque, ?w.HANDLE, u32) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn SelectObject(w.HDC, *anyopaque) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn DeleteObject(*anyopaque) callconv(.winapi) i32;
extern "gdi32" fn GdiFlush() callconv(.winapi) i32;
const canvas_width = 1920;
const canvas_height = 1080;
const frames = 240;
const warmup = 30;
const Bitmap = extern struct {
    size: u32 = 40,
    width: i32 = canvas_width,
    height: i32 = -canvas_height,
    planes: u16 = 1,
    bits: u16 = 32,
    compression: u32 = 0,
    image_size: u32 = 0,
    xppm: i32 = 0,
    yppm: i32 = 0,
    colors_used: u32 = 0,
    colors_important: u32 = 0,
    unused_color: u32 = 0,
};
fn now() !i64 {
    var value: i64 = 0;
    if (QueryPerformanceCounter(&value) == 0) return error.ClockFailed;
    return value;
}
fn report(label: []const u8, samples: *[frames]u64, frequency: i64) void {
    var sum: u64 = 0;
    for (samples) |value| sum += value;
    std.mem.sort(u64, samples, {}, std.sort.asc(u64));
    const factor = 1000.0 / @as(f64, @floatFromInt(frequency));
    std.debug.print("{s}: mean_ms={d:.3} p50_ms={d:.3} p95_ms={d:.3} max_ms={d:.3}\n", .{
        label,
        @as(f64, @floatFromInt(sum)) * factor / frames,
        @as(f64, @floatFromInt(samples[frames / 2])) * factor,
        @as(f64, @floatFromInt(samples[(frames * 95 / 100) - 1])) * factor,
        @as(f64, @floatFromInt(samples[frames - 1])) * factor,
    });
}
pub fn main() !void {
    var frequency: i64 = 0;
    if (QueryPerformanceFrequency(&frequency) == 0 or frequency <= 0) return error.ClockFailed;
    var context = try wgl.Context.create();
    defer context.deinit();
    try context.makeCurrent();
    defer wgl.Context.releaseCurrent();
    _ = try gl.glad.load(&wgl.getProcAddress);
    defer gl.glad.unload();
    const api = &gl.glad.context;
    for ([_]gl.c.GLenum{ gl.c.GL_VENDOR, gl.c.GL_RENDERER, gl.c.GL_VERSION }) |key| {
        const ptr = api.GetString.?(key);
        if (ptr == null) return error.MissingGLDescription;
        std.debug.print("GL {x}: {s}\n", .{ key, std.mem.span(@as([*:0]const u8, @ptrCast(ptr))) });
    }
    var texture: gl.c.GLuint = 0;
    var framebuffer: gl.c.GLuint = 0;
    api.GenTextures.?(1, &texture);
    defer api.DeleteTextures.?(1, &texture);
    api.BindTexture.?(gl.c.GL_TEXTURE_2D, texture);
    api.TexParameteri.?(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MIN_FILTER, gl.c.GL_NEAREST);
    api.TexParameteri.?(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MAG_FILTER, gl.c.GL_NEAREST);
    api.TexImage2D.?(gl.c.GL_TEXTURE_2D, 0, gl.c.GL_RGBA8, canvas_width, canvas_height, 0, gl.c.GL_RGBA, gl.c.GL_UNSIGNED_BYTE, null);
    api.GenFramebuffers.?(1, &framebuffer);
    defer api.DeleteFramebuffers.?(1, &framebuffer);
    api.BindFramebuffer.?(gl.c.GL_FRAMEBUFFER, framebuffer);
    api.FramebufferTexture2D.?(gl.c.GL_FRAMEBUFFER, gl.c.GL_COLOR_ATTACHMENT0, gl.c.GL_TEXTURE_2D, texture, 0);
    if (api.CheckFramebufferStatus.?(gl.c.GL_FRAMEBUFFER) != gl.c.GL_FRAMEBUFFER_COMPLETE) return error.IncompleteFramebuffer;
    const alloc = std.heap.page_allocator;
    const rgba = try alloc.alloc(u8, canvas_width * canvas_height * 4);
    defer alloc.free(rgba);
    const dc = CreateCompatibleDC(null) orelse return error.MemoryDcFailed;
    defer _ = DeleteDC(dc);
    const bitmap: Bitmap = .{};
    var bits: ?*anyopaque = null;
    const dib = CreateDIBSection(dc, &bitmap, 0, &bits, null, 0) orelse return error.DibCreateFailed;
    defer _ = DeleteObject(dib);
    const old = SelectObject(dc, dib) orelse return error.DibSelectFailed;
    if (@intFromPtr(old) == std.math.maxInt(usize)) return error.DibSelectFailed;
    defer _ = SelectObject(dc, old);
    const destination: [*]const u8 = @ptrCast(bits orelse return error.DibCreateFailed);
    var readback: [frames]u64 = undefined;
    var conversion: [frames]u64 = undefined;
    var paint: [frames]u64 = undefined;
    var total: [frames]u64 = undefined;
    for (0..warmup + frames) |i| {
        const red: u8 = if (i % 2 == 0) 0 else 255;
        const start = try now();
        api.ClearColor.?(if (red == 0) 0 else 1, 0, 1, 1);
        api.Clear.?(gl.c.GL_COLOR_BUFFER_BIT);
        api.ReadPixels.?(0, 0, canvas_width, canvas_height, gl.c.GL_RGBA, gl.c.GL_UNSIGNED_BYTE, rgba.ptr);
        api.Finish.?();
        const read_done = try now();
        var image = try presenter.Image.fromRGBA(alloc, canvas_width, canvas_height, rgba);
        var image_live = true;
        defer if (image_live) image.deinit();
        const converted = try now();
        try image.paint(dc, canvas_width, canvas_height);
        if (GdiFlush() == 0) return error.DibFlushFailed;
        const painted = try now();
        const expected = [_]u8{ 255, 0, red, 255 };
        if (!std.mem.eql(u8, destination[0..4], &expected)) return error.DibPixelMismatch;
        image.deinit();
        image_live = false;
        const ended = try now();
        if (api.GetError.?() != gl.c.GL_NO_ERROR) return error.OpenGLFailure;
        if (i >= warmup) {
            const n = i - warmup;
            readback[n] = @intCast(read_done - start);
            conversion[n] = @intCast(converted - read_done);
            paint[n] = @intCast(painted - converted);
            total[n] = @intCast(ended - start);
        }
    }
    std.debug.print("component bench 1920x1080 RGBA8 bytes/frame=8294400 warmup=30 samples=240 allocator=page; no CoreSurface/PTY/window paint/compositor/font shaping; not app FPS\n", .{});
    report("clear+readback+finish", &readback, frequency);
    report("allocate+RGBA-to-BGRA+flip", &conversion, frequency);
    report("memory-DC DIB+GdiFlush", &paint, frequency);
    report("total including image free", &total, frequency);
}
