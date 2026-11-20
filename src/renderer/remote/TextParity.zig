//! Controlled real-terminal parity check. Capture while locked, RPC UNLOCKED.
//! Default sessions never instantiate a worker or retain diagnostic packets.
const std = @import("std");
const frame = @import("TextFrame.zig");
const Client = @import("Client.zig");
const State = @This();
var session: std.atomic.Value(u64) = .init(1);

pending: ?frame.Owned = null,
reference: ?struct { alloc: std.mem.Allocator, pixels: []u8 } = null,
client: ?Client = null,
epoch: u64 = 0,
width: u32 = 0,
height: u32 = 0,
checks: std.atomic.Value(u32) = .init(0),
max_glyphs: std.atomic.Value(u32) = .init(0),
failures: std.atomic.Value(u32) = .init(0),

pub fn discard(self: *State) void {
    if (self.pending) |*pending| pending.deinit();
    if (self.reference) |reference| reference.alloc.free(reference.pixels);
    self.pending = null;
    self.reference = null;
}
pub fn capture(self: *State, packet: frame.Owned) void {
    self.discard();
    self.pending = packet;
}
pub fn setReference(self: *State, alloc: std.mem.Allocator, pixels: []u8) void {
    if (self.reference) |old| old.alloc.free(old.pixels);
    self.reference = .{ .alloc = alloc, .pixels = pixels };
}
/// Renderer thread only, after leaving draw/font/UI locks. No UI callbacks.
pub fn process(self: *State, alloc: std.mem.Allocator) !void {
    if (self.pending == null) return;
    defer self.discard();
    errdefer _ = self.failures.fetchAdd(1, .release);
    const reference = self.reference orelse return error.MissingLegacyReference;
    const limits: frame.Limits = .{ .dimension = 32768, .atlas_dimension = 32768, .cells = 1024 * 1024, .bytes = 64 * 1024 * 1024 };
    const input = try frame.decode(self.pending.?.bytes, limits);
    if (self.client == null) {
        const token = session.fetchAdd(1, .monotonic);
        if (token == 0 or token == std.math.maxInt(u64)) return error.SessionExhausted;
        self.client = try Client.init(alloc, .{ .surface = token, .generation = 1, .request_limit = 64 * 1024 * 1024, .output_limit = 32 * 1024 * 1024 });
    }
    if (input.width != self.width or input.height != self.height) {
        self.epoch = std.math.add(u64, self.epoch, 1) catch return error.EpochExhausted;
        self.width = input.width;
        self.height = input.height;
    }
    var reply = try self.client.?.render(self.pending.?.bytes, self.epoch, limits);
    defer reply.deinit();
    const pixels = reply.packet.payload[16..];
    if (!std.mem.eql(u8, reference.pixels, pixels)) {
        std.log.err("controlled GPU text parity mismatch legacy_bytes={d} worker_bytes={d}", .{ reference.pixels.len, pixels.len });
        return error.GpuTextPixelMismatch;
    }
    _ = self.max_glyphs.fetchMax(@intCast(input.foreground.len / @import("ShaderPayload.zig").cell_bytes), .release);
    if (self.checks.fetchAdd(1, .release) == 0)
        std.log.info("controlled GPU worker real-terminal RGBA parity passed width={d} height={d} glyphs={d} different_bytes=0; legacy parent still GL", .{ input.width, input.height, input.foreground.len / @import("ShaderPayload.zig").cell_bytes });
}
/// Renderer exit, outside draw/font/UI locks. Never count forced cleanup as close.
pub fn close(self: *State) !void {
    self.discard();
    errdefer _ = self.failures.fetchAdd(1, .release);
    if (self.client) |*client| {
        defer {
            client.abort() catch {
                _ = self.failures.fetchAdd(1, .release);
                std.log.err("controlled GPU parity failure cleanup failed", .{});
            };
            self.client = null;
        }
        try client.close();
        std.log.info("controlled GPU text parity completed checks={d} max_glyphs={d} failures={d}", .{
            self.checks.load(.acquire), self.max_glyphs.load(.acquire), self.failures.load(.acquire),
        });
        std.log.info("controlled GPU text parity close ack=1 exit=0 jobempty=1 forced=0", .{});
    } else return error.GpuTextNeverChecked;
}
