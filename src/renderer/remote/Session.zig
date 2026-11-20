//! GPU-free surface session for the forthcoming remote-only host backend.
//! Not selected by default. Caller transfers ownership to its renderer thread;
//! render/close must execute outside draw/font/UI locks.
const std = @import("std");
const Client = @import("Client.zig");
const TextFrame = @import("TextFrame.zig");
const ImageFrame = @import("ImageFrame.zig");
const CpuFrame = @import("../CpuExportedFrame.zig");
const protocol = @import("Protocol.zig");
const Session = @This();

alloc: std.mem.Allocator,
client: Client,
epoch: u64 = 0,
width: u32 = 0,
height: u32 = 0,
poisoned: bool = false,

pub fn init(alloc: std.mem.Allocator, options: Client.Options) !Session {
    return .{ .alloc = alloc, .client = try Client.init(alloc, options) };
}
pub fn render(self: *Session, payload: []const u8, epoch: u64, limits: TextFrame.Limits) !CpuFrame.Payload {
    if (self.poisoned) return error.WorkerSessionPoisoned;
    errdefer self.fail();
    const input = try TextFrame.decode(payload, limits);
    try self.useViewport(input.width, input.height, epoch);
    var reply = try self.client.render(payload, self.epoch, limits);
    defer reply.deinit();
    return CpuFrame.takeRgba(reply.alloc, input.width, input.height, &reply.bytes, protocol.header_bytes + 16);
}
pub fn renderImageFrame(self: *Session, payload: []const u8, epoch: u64, limits: ImageFrame.Limits) !CpuFrame.Payload {
    if (self.poisoned) return error.WorkerSessionPoisoned;
    errdefer self.fail();
    const input = try ImageFrame.decode(payload, limits);
    try self.useViewport(input.text.width, input.text.height, epoch);
    var reply = try self.client.renderImageFrame(payload, self.epoch, limits);
    defer reply.deinit();
    return CpuFrame.takeRgba(reply.alloc, input.text.width, input.text.height, &reply.bytes, protocol.header_bytes + 16);
}
fn useViewport(self: *Session, width: u32, height: u32, epoch: u64) !void {
    if (epoch == 0 or epoch < self.epoch) return error.StaleViewportEpoch;
    if (epoch == self.epoch and (width != self.width or height != self.height)) return error.ViewportEpochDimensionMismatch;
    self.epoch = epoch;
    self.width = width;
    self.height = height;
}
pub fn close(self: *Session) !void {
    if (self.poisoned) return error.WorkerSessionPoisoned;
    errdefer self.fail();
    try self.client.close();
}
/// Single-owner failure boundary, outside renderer/UI/font locks. Abort and
/// reap immediately; neither another render nor a late close can revive it.
/// No automatic relaunch while the parent PTY is alive.
pub fn fail(self: *Session) void {
    self.poisoned = true;
    self.client.abort() catch |err| std.log.err("remote failed-session cleanup failed: {}", .{err});
}
pub fn abort(self: *Session) !void {
    self.poisoned = true;
    try self.client.abort();
}
