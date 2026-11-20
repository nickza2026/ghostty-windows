//! CPU/Win32 transport owner. Never imports OpenGL or a GPU renderer.
//! Single owner thread; no exchange/close calls while holding draw/font/UI locks.
const std = @import("std");
const protocol = @import("Protocol.zig");
const text = @import("TextFrame.zig");
const ImageFrame = @import("ImageFrame.zig");
const RequestBuffer = @import("RequestBuffer.zig");

pub const Status = extern struct {
    win_error: u32 = 0,
    child_exit: u32 = 259,
    stage: u32 = 0,
    close_ack: c_int = 0,
    process_exited: c_int = 0,
    job_empty: c_int = 0,
    forced: c_int = 0,
};
const Opaque = opaque {};
extern fn rw_open(u64, u64, u32, u32, u32, usize, *?*Opaque, *Status) c_int;
extern fn rw_call(*Opaque, [*]const u8, usize, [*]u8, usize, *usize, u32, *Status) c_int;
extern fn rw_cancel(*Opaque) void;
extern fn rw_finish(*Opaque, u32, *Status) c_int;
extern fn rw_destroy(*Opaque, u32, *Status) c_int;

const Client = @This();
alloc: std.mem.Allocator,
handle: ?*Opaque = null,
surface: u64,
generation: u64,
sequence: u64 = 0,
timeout_ms: u32,
request_limit: u32,
output_limit: u32,
status: Status = .{},
inline_images: bool = false,
request_buffer: RequestBuffer = .{},

pub const Options = struct {
    surface: u64,
    generation: u64,
    timeout_ms: u32 = 5000,
    request_limit: u32,
    output_limit: u32,
    diagnostics_handle: usize = 0,
    inline_images: bool = false,
};
pub const Reply = struct {
    alloc: std.mem.Allocator,
    bytes: []u8,
    packet: protocol.Packet,
    pub fn deinit(self: *Reply) void {
        self.alloc.free(self.bytes);
        self.* = undefined;
    }
};

pub fn init(alloc: std.mem.Allocator, options: Options) !Client {
    if (options.surface == 0 or options.generation == 0 or options.timeout_ms == 0 or options.timeout_ms > 60000 or
        options.request_limit < 181 or options.request_limit > protocol.hard_payload_limit or
        options.output_limit < 4 or options.output_limit > protocol.hard_payload_limit - 16) return error.InvalidOptions;
    var self: Client = .{ .alloc = alloc, .surface = options.surface, .generation = options.generation, .timeout_ms = options.timeout_ms, .request_limit = options.request_limit, .output_limit = options.output_limit };
    if (rw_open(options.surface, options.generation, 16 + protocol.header_bytes + options.request_limit, 16 + protocol.header_bytes + 16 + options.output_limit, options.timeout_ms, options.diagnostics_handle, &self.handle, &self.status) == 0)
        return error.WorkerOpenFailed;
    errdefer self.abort() catch {
        std.log.err("render worker init cleanup failed stage={d} win_error={d}", .{ self.status.stage, self.status.win_error });
    };
    var requested: [4]u8 = undefined;
    const wanted = protocol.capability_text | (if (options.inline_images) protocol.capability_inline_images else @as(u32, 0));
    std.mem.writeInt(u32, &requested, wanted, .little);
    var hello = try self.exchange(.hello, 0, if (options.inline_images) &requested else &.{}, .hello_ack, protocol.header_bytes + 16);
    defer hello.deinit();
    const caps = hello.packet.payload;
    if (caps.len != 16 or std.mem.readInt(u32, caps[0..4], .little) != options.request_limit or
        std.mem.readInt(u32, caps[4..8], .little) != options.output_limit or
        std.mem.readInt(u16, caps[8..10], .little) != protocol.version or std.mem.readInt(u16, caps[10..12], .little) != 1 or
        std.mem.readInt(u32, caps[12..16], .little) != wanted) return error.UnsupportedCapabilities;
    self.inline_images = options.inline_images;
    return self;
}

fn exchange(self: *Client, kind: protocol.Kind, epoch: u64, payload: []const u8, expected: protocol.Kind, reply_capacity: usize) !Reply {
    const handle = self.handle orelse return error.Closed;
    if (payload.len > self.request_limit or reply_capacity < protocol.header_bytes or
        reply_capacity > protocol.header_bytes + 16 + self.output_limit) return error.PayloadTooLarge;
    const sequence = std.math.add(u64, self.sequence, 1) catch return error.SequenceExhausted;
    const request = try self.request_buffer.ensure(self.alloc, protocol.header_bytes + payload.len, protocol.header_bytes + @as(usize, self.request_limit));
    const encoded = try protocol.encode(request, .{ .kind = kind, .surface = self.surface, .generation = self.generation, .sequence = sequence, .epoch = epoch }, payload, .{ .max_payload_bytes = self.request_limit });
    const response = try self.alloc.alloc(u8, reply_capacity);
    errdefer self.alloc.free(response);
    self.sequence = sequence;
    errdefer self.cancel();
    var received: usize = 0;
    if (rw_call(handle, encoded.ptr, encoded.len, response.ptr, response.len, &received, self.timeout_ms, &self.status) == 0) return error.WorkerCommunicationFailed;
    if (received > response.len) return error.InvalidReply;
    const packet = try protocol.decode(response[0..received], .{ .max_payload_bytes = 16 + self.output_limit });
    try packet.header.expectReply(expected, self.surface, self.generation, sequence, epoch);
    return .{ .alloc = self.alloc, .bytes = response, .packet = packet };
}

/// Owns a response copy; no pointers into shared memory survive the call.
pub fn render(self: *Client, payload: []const u8, epoch: u64, limits: text.Limits) !Reply {
    const input = try text.decode(payload, limits);
    return self.renderPixels(.submit_frame, payload, epoch, input.width, input.height);
}
pub fn renderImageFrame(self: *Client, payload: []const u8, epoch: u64, limits: ImageFrame.Limits) !Reply {
    if (!self.inline_images) return error.ImageCapabilityNotNegotiated;
    if (payload.len > self.request_limit) return error.PayloadTooLarge;
    const input = try ImageFrame.decode(payload, limits);
    return self.renderPixels(.submit_image_frame, payload, epoch, input.text.width, input.text.height);
}
fn renderPixels(self: *Client, kind: protocol.Kind, payload: []const u8, epoch: u64, width: u32, height: u32) !Reply {
    const pixels = @as(u64, width) * height * 4;
    if (pixels > self.output_limit) return error.OutputTooLarge;
    var reply = try self.exchange(kind, epoch, payload, .frame_ready, protocol.header_bytes + 16 + @as(usize, @intCast(pixels)));
    errdefer reply.deinit();
    errdefer self.cancel();
    const body = reply.packet.payload;
    if (body.len != 16 + pixels or std.mem.readInt(u32, body[0..4], .little) != width or
        std.mem.readInt(u32, body[4..8], .little) != height or
        std.mem.readInt(u32, body[8..12], .little) != width * 4 or std.mem.readInt(u32, body[12..16], .little) != 1) return error.InvalidImageReply;
    return reply;
}

pub fn cancel(self: *Client) void {
    if (self.handle) |handle| rw_cancel(handle);
}

/// Healthy close requires a validated close ACK + natural exit(0) + empty job.
pub fn close(self: *Client) !void {
    defer self.request_buffer.deinit(self.alloc);
    var reply = try self.exchange(.close, 0, &.{}, .closed, protocol.header_bytes);
    defer reply.deinit();
    if (reply.packet.payload.len != 0) return error.InvalidReply;
    const handle = self.handle orelse return error.Closed;
    const finished = rw_finish(handle, self.timeout_ms, &self.status);
    if (finished == 0 or self.status.close_ack == 0 or
        self.status.process_exited == 0 or self.status.child_exit != 0 or self.status.job_empty == 0 or self.status.forced != 0)
    {
        // Record BEFORE Session.fail/abort can replace the original status.
        std.log.err("worker natural close failure surface={d} finished={d} budget_ms={d} stage={d} win_error={d} ack={d} exited={d} child_exit={d} job_empty={d} forced={d}", .{ self.surface, finished, self.timeout_ms, self.status.stage, self.status.win_error, self.status.close_ack, self.status.process_exited, self.status.child_exit, self.status.job_empty, self.status.forced });
        return error.WorkerCloseFailed;
    }
    self.handle = null;
    if (rw_destroy(handle, self.timeout_ms, &self.status) == 0 or self.status.forced != 0) return error.WorkerCleanupFailed;
}

/// Failure cleanup, never a successful close receipt. Caller must join users of
/// cancel/exchange before destroying this object. All waits are bounded.
pub fn abort(self: *Client) !void {
    self.request_buffer.deinit(self.alloc);
    const handle = self.handle orelse return;
    self.handle = null;
    if (rw_destroy(handle, self.timeout_ms, &self.status) == 0) return error.WorkerCleanupFailed;
}
