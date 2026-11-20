//! Dedicated text-frame GPU worker. Private inherited maps/events only.
//! Single outstanding request: producer retains ownership until matching reply.
//! Publication prefix: aligned u64 commit sequence + reserved u64 zero, followed
//! by the explicit LE Protocol packet. This is NOT the v1 quadrant fixture ABI.
const std = @import("std");
const gl = @import("opengl");
const wgl = @import("renderer/opengl/wgl.zig");
const protocol = @import("renderer/remote/Protocol.zig");
const text = @import("renderer/remote/TextFrame.zig");
const executor = @import("renderer/remote/TextGpuExecutor.zig");
const w = std.os.windows;
const prefix = 16;
// Declared only by the separate test root; production compiles this branch out.
const fault_fixture = if (@hasDecl(@import("root"), "gpu_worker_fault_fixture")) @import("root").gpu_worker_fault_fixture else false;
extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
extern "kernel32" fn Sleep(u32) callconv(.winapi) void;

extern "kernel32" fn GetEnvironmentVariableW([*:0]const u16, [*]u16, u32) callconv(.winapi) u32;
extern "kernel32" fn MapViewOfFile(w.HANDLE, u32, u32, u32, usize) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn UnmapViewOfFile(*const anyopaque) callconv(.winapi) i32;
extern "kernel32" fn WaitForMultipleObjects(u32, [*]const w.HANDLE, i32, u32) callconv(.winapi) u32;
extern "kernel32" fn SetEvent(w.HANDLE) callconv(.winapi) i32;
extern "kernel32" fn CloseHandle(w.HANDLE) callconv(.winapi) i32;
extern "kernel32" fn ExitProcess(u32) callconv(.winapi) noreturn;

fn environment(comptime name: []const u8) !u64 {
    var utf16: [32]u16 = undefined;
    const n = GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral(name), &utf16, utf16.len);
    if (n == 0 or n >= utf16.len) return error.InvalidControl;
    var ascii: [32]u8 = undefined;
    for (utf16[0..n], 0..) |c, i| {
        if (c > 127) return error.InvalidControl;
        ascii[i] = @intCast(c);
    }
    return std.fmt.parseInt(u64, ascii[0..n], 16);
}
fn handle(comptime name: []const u8) !w.HANDLE {
    const value = try environment(name);
    if (value == 0 or value >= std.math.maxInt(usize)) return error.InvalidControl;
    return @ptrFromInt(@as(usize, @intCast(value)));
}
fn capacity(comptime name: []const u8) !usize {
    const value = try environment(name);
    if (value < prefix + protocol.header_bytes + 16 or value > prefix + protocol.header_bytes + protocol.hard_payload_limit) return error.InvalidCapacity;
    return @intCast(value);
}
fn commit(memory: []u8) *u64 {
    return @ptrCast(@alignCast(memory.ptr));
}
fn readRequest(alloc: std.mem.Allocator, memory: []u8) ![]u8 {
    const published = @atomicLoad(u64, commit(memory), .acquire);
    if (published == 0 or std.mem.readInt(u64, memory[8..16], .little) != 0) return error.NotCommitted;
    var header: [protocol.header_bytes]u8 = undefined;
    @memcpy(&header, memory[prefix..][0..protocol.header_bytes]);
    const length: usize = std.mem.readInt(u32, header[12..16], .little);
    if (length > protocol.hard_payload_limit or length > memory.len - prefix - protocol.header_bytes) return error.InvalidLength;
    if (std.mem.readInt(u64, header[32..40], .little) != published) return error.InvalidCommit;
    const total = protocol.header_bytes + length;
    const bytes = try alloc.alloc(u8, total);
    errdefer alloc.free(bytes);
    @memcpy(bytes, memory[prefix..][0..total]);
    if (@atomicLoad(u64, commit(memory), .acquire) != published or
        !std.mem.eql(u8, &header, memory[prefix..][0..protocol.header_bytes]) or
        !std.mem.eql(u8, &header, bytes[0..protocol.header_bytes])) return error.ChangedCommit;
    return bytes;
}
fn publish(memory: []u8, event: w.HANDLE, request: protocol.Header, kind: protocol.Kind, payload: []const u8) !void {
    @atomicStore(u64, commit(memory), 0, .release);
    @memset(memory[8..16], 0);
    var response = request;
    response.kind = kind;
    _ = try protocol.encode(memory[prefix..], response, payload, .{ .max_payload_bytes = memory.len - prefix - protocol.header_bytes });
    @atomicStore(u64, commit(memory), response.sequence, .release);
    if (SetEvent(event) == 0) return error.EventFailed;
}

fn run() !void {
    const alloc = std.heap.page_allocator;
    const request_map = try handle("LOCALTERM_RENDER_REQUEST_MAP");
    defer _ = CloseHandle(request_map);
    const response_map = try handle("LOCALTERM_RENDER_RESPONSE_MAP");
    defer _ = CloseHandle(response_map);
    const request_event = try handle("LOCALTERM_RENDER_REQUEST_EVENT");
    defer _ = CloseHandle(request_event);
    const response_event = try handle("LOCALTERM_RENDER_RESPONSE_EVENT");
    defer _ = CloseHandle(response_event);
    const stop_event = try handle("LOCALTERM_RENDER_STOP_EVENT");
    defer _ = CloseHandle(stop_event);
    const request_capacity = try capacity("LOCALTERM_RENDER_REQUEST_CAPACITY");
    const response_capacity = try capacity("LOCALTERM_RENDER_RESPONSE_CAPACITY");
    const surface = try environment("LOCALTERM_RENDER_SURFACE");
    const generation = try environment("LOCALTERM_RENDER_GENERATION");
    if (surface == 0 or generation == 0) return error.InvalidIdentity;
    const request_view = MapViewOfFile(request_map, 4, 0, 0, request_capacity) orelse return error.MapFailed;
    defer _ = UnmapViewOfFile(request_view);
    const response_view = MapViewOfFile(response_map, 2, 0, 0, response_capacity) orelse return error.MapFailed;
    defer _ = UnmapViewOfFile(response_view);
    const request_memory = @as([*]u8, @ptrCast(request_view))[0..request_capacity];
    const response_memory = @as([*]u8, @ptrCast(response_view))[0..response_capacity];
    const request_limit: u32 = @intCast(request_capacity - prefix - protocol.header_bytes);
    const output_limit: u32 = @intCast(response_capacity - prefix - protocol.header_bytes - 16);
    if (request_limit < text.header_bytes + @import("renderer/remote/ShaderPayload.zig").uniforms_bytes + 9 or output_limit < 4)
        return error.InvalidCapacity;

    var closing = false;
    defer if (closing) std.debug.print("worker teardown surface={d} phase=gpu-teardown-complete\n", .{surface});
    const device = try wgl.Device.init(alloc, .{});
    defer {
        if (closing) std.debug.print("worker teardown surface={d} phase=device-begin\n", .{surface});
        device.deinit(alloc);
        if (closing) std.debug.print("worker teardown surface={d} phase=device-end\n", .{surface});
    }
    var context = try device.createContext();
    defer {
        if (closing) std.debug.print("worker teardown surface={d} phase=context-begin\n", .{surface});
        context.deinit();
        if (closing) std.debug.print("worker teardown surface={d} phase=context-end\n", .{surface});
    }
    try context.makeCurrent();
    defer wgl.Context.releaseCurrent();
    const version = try gl.glad.load(&wgl.getProcAddress);
    defer gl.glad.unload();
    const major = gl.glad.versionMajor(@intCast(version));
    const minor = gl.glad.versionMinor(@intCast(version));
    if (major < 4 or (major == 4 and minor < 3)) return error.OpenGLOutdated;
    var graphics: executor.Executor = .{};
    defer {
        if (closing) std.debug.print("worker teardown surface={d} phase=executor-begin\n", .{surface});
        graphics.deinit(alloc); // Before GL unload/context release above.
        if (closing) std.debug.print("worker teardown surface={d} phase=executor-end\n", .{surface});
    }

    var ready = false;
    var image_mode = false;
    var previous: u64 = 0;
    const events = [_]w.HANDLE{ stop_event, request_event };
    while (true) {
        const which = WaitForMultipleObjects(events.len, &events, 0, 0xFFFFFFFF);
        if (which == 0) return error.Cancelled; // Not a cooperative close ACK.
        if (which != 1) return error.WaitFailed;
        const owned = try readRequest(alloc, request_memory);
        defer alloc.free(owned);
        const packet = try protocol.decode(owned, .{ .max_payload_bytes = request_limit });
        if (packet.header.surface != surface or packet.header.generation != generation) return error.StaleSession;
        if (packet.header.sequence <= previous) return error.StaleSequence;
        previous = packet.header.sequence;
        switch (packet.header.kind) {
            .hello => {
                if (ready) return error.UnexpectedHello;
                const requested = try protocol.helloCapabilities(packet.payload);
                var caps: [16]u8 = @splat(0);
                std.mem.writeInt(u32, caps[0..4], request_limit, .little);
                std.mem.writeInt(u32, caps[4..8], output_limit, .little);
                std.mem.writeInt(u16, caps[8..10], protocol.version, .little);
                std.mem.writeInt(u16, caps[10..12], 1, .little); // CRF1 body schema.
                std.mem.writeInt(u32, caps[12..16], requested, .little);
                try publish(response_memory, response_event, packet.header, .hello_ack, &caps);
                ready = true;
                image_mode = (requested & protocol.capability_inline_images) != 0;
            },
            .submit_frame, .submit_image_frame => {
                if (!ready) return error.HandshakeRequired;
                var image = if (packet.header.kind == .submit_image_frame) image_result: {
                    if (!image_mode) return error.ImageCapabilityNotNegotiated;
                    break :image_result try graphics.renderImageFrame(alloc, packet.payload, .{
                        .payload = request_limit,
                        .text = .{ .dimension = 32768, .atlas_dimension = 32768, .cells = 1024 * 1024, .bytes = request_limit },
                        .images = .{ .bytes = request_limit },
                    }, output_limit);
                } else try graphics.render(alloc, packet.payload, .{
                    .dimension = 32768,
                    .atlas_dimension = 32768,
                    .cells = 1024 * 1024,
                    .bytes = request_limit,
                }, output_limit);
                defer image.deinit();
                const reply = try alloc.alloc(u8, 16 + image.pixels.len);
                defer alloc.free(reply);
                std.mem.writeInt(u32, reply[0..4], image.width, .little);
                std.mem.writeInt(u32, reply[4..8], image.height, .little);
                std.mem.writeInt(u32, reply[8..12], image.width * 4, .little);
                std.mem.writeInt(u32, reply[12..16], 1, .little); // Premul RGBA8, bottom-up.
                @memcpy(reply[16..], image.pixels);
                // Test-only marker is beyond the tiny fixture's actual packet.
                // GPU draw/readback/finish COMPLETED before this CPU sleep.
                // Tests a late rendered reply, not a GPU/driver hang.
                if (comptime fault_fixture) {
                    if (graphics.completed_frames == 3) {
                        if (image.width != 8 or image.height != 4 or prefix + protocol.header_bytes + reply.len > response_memory.len - 32) return error.InvalidLateReplyFixture;
                        const marker = response_memory[response_memory.len - 32 ..];
                        @atomicStore(u64, commit(marker), GetTickCount64(), .release);
                        @atomicStore(u64, commit(marker[16..]), packet.header.sequence, .release);
                        Sleep(200);
                    }
                }
                try publish(response_memory, response_event, packet.header, .frame_ready, reply);
                if (comptime fault_fixture) {
                    if (graphics.completed_frames == 3) @atomicStore(u64, commit(response_memory[response_memory.len - 24 ..]), GetTickCount64(), .release);
                }
            },
            .close => {
                if (packet.payload.len != 0) return error.UnexpectedPayload;
                closing = true;
                try publish(response_memory, response_event, packet.header, .closed, &.{});
                std.debug.print("worker teardown surface={d} phase=closed-published\n", .{surface});
                return;
            },
            else => return error.UnsupportedCommand,
        }
    }
}

pub fn main() void {
    run() catch |err| {
        std.debug.print("render text worker error: {s}\n", .{@errorName(err)});
        ExitProcess(1);
    };
    std.debug.print("worker teardown phase=run-complete\n", .{});
}
