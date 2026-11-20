//! CPU resource reservations. Encoding/queuing a create is NOT a GPU ACK.
//! The caller validates the protocol reply identity before acknowledging here.
const std = @import("std");
const protocol = @import("Protocol.zig");
const Registry = @This();

pub const Kind = enum(u8) { buffer, texture, target, sampler, pipeline };
pub const Ref = struct { worker: u64, id: protocol.ResourceId };
const State = enum { vacant, creating, live, destroying, exhausted };
const Entry = struct { generation: u32 = 1, kind: Kind, state: State };
pub const hard_slot_limit = 65536;

alloc: std.mem.Allocator,
worker: u64,
limit: u32,
entries: std.ArrayListUnmanaged(Entry) = .empty,

pub fn init(alloc: std.mem.Allocator, worker: u64, limit: u32) !Registry {
    if (worker == 0) return error.InvalidWorker;
    if (limit == 0 or limit > hard_slot_limit) return error.InvalidLimit;
    return .{ .alloc = alloc, .worker = worker, .limit = limit };
}

pub fn deinit(self: *Registry) void {
    self.entries.deinit(self.alloc);
    self.* = undefined;
}

pub fn reserve(self: *Registry, kind: Kind) !Ref {
    for (self.entries.items, 0..) |*entry, i| {
        if (entry.state != .vacant) continue;
        entry.kind = kind;
        entry.state = .creating;
        return .{ .worker = self.worker, .id = .{ .slot = @intCast(i), .generation = entry.generation } };
    }
    if (self.entries.items.len >= self.limit) return error.ResourceLimit;
    const slot: u32 = @intCast(self.entries.items.len);
    try self.entries.append(self.alloc, .{ .kind = kind, .state = .creating });
    return .{ .worker = self.worker, .id = .{ .slot = slot, .generation = 1 } };
}

fn entryFor(self: *Registry, ref: Ref, kind: Kind) !*Entry {
    if (ref.worker != self.worker) return error.StaleWorker;
    if (ref.id.slot >= self.entries.items.len) return error.InvalidSlot;
    const entry = &self.entries.items[ref.id.slot];
    if (entry.generation != ref.id.generation or ref.id.generation == 0) return error.StaleResource;
    if (entry.kind != kind) return error.WrongKind;
    return entry;
}

pub fn acknowledgeCreate(self: *Registry, ref: Ref, kind: Kind) !void {
    const entry = try self.entryFor(ref, kind);
    if (entry.state != .creating) return error.UnexpectedState;
    entry.state = .live;
}

pub fn requireLive(self: *Registry, ref: Ref, kind: Kind) !void {
    const entry = try self.entryFor(ref, kind);
    if (entry.state != .live) return error.NotLive;
}

pub fn beginDestroy(self: *Registry, ref: Ref, kind: Kind) !void {
    const entry = try self.entryFor(ref, kind);
    if (entry.state != .live) return error.NotLive;
    entry.state = .destroying;
}

fn retire(entry: *Entry) void {
    if (entry.generation == std.math.maxInt(u32)) {
        entry.state = .exhausted; // Never wrap to an old resource identity.
    } else {
        entry.generation += 1;
        entry.state = .vacant;
    }
}

pub fn acknowledgeDestroy(self: *Registry, ref: Ref, kind: Kind) !void {
    const entry = try self.entryFor(ref, kind);
    if (entry.state != .destroying) return error.UnexpectedState;
    retire(entry);
}

/// Only for an explicit rejected-create reply confirming no child object exists.
pub fn rejectCreate(self: *Registry, ref: Ref, kind: Kind) !void {
    const entry = try self.entryFor(ref, kind);
    if (entry.state != .creating) return error.UnexpectedState;
    retire(entry);
}

/// Caller must first confirm the old worker/job exited. This does not restart
/// a process, destroy GPU objects, or reupload resources on the caller's behalf.
pub fn invalidateForRestart(self: *Registry, worker: u64) !void {
    if (worker <= self.worker) return error.InvalidWorker;
    for (self.entries.items) |*entry| {
        if (entry.state != .exhausted) retire(entry);
    }
    self.worker = worker;
}

test "remote registry requires create ACK and refuses kind confusion" {
    var registry = try init(std.testing.allocator, 1, 2);
    defer registry.deinit();
    const ref = try registry.reserve(.texture);
    try std.testing.expectError(error.NotLive, registry.requireLive(ref, .texture));
    try std.testing.expectError(error.WrongKind, registry.acknowledgeCreate(ref, .buffer));
    try registry.acknowledgeCreate(ref, .texture);
    try registry.requireLive(ref, .texture);
    try std.testing.expectError(error.UnexpectedState, registry.acknowledgeCreate(ref, .texture));
}

test "remote registry cannot reuse a slot before destroy ACK" {
    var registry = try init(std.testing.allocator, 1, 1);
    defer registry.deinit();
    const first = try registry.reserve(.buffer);
    try registry.acknowledgeCreate(first, .buffer);
    try std.testing.expectError(error.UnexpectedState, registry.acknowledgeDestroy(first, .buffer));
    try registry.beginDestroy(first, .buffer);
    try std.testing.expectError(error.NotLive, registry.requireLive(first, .buffer));
    try std.testing.expectError(error.ResourceLimit, registry.reserve(.texture));
    try registry.acknowledgeDestroy(first, .buffer);
    const second = try registry.reserve(.buffer);
    try std.testing.expectEqual(first.id.slot, second.id.slot);
    try std.testing.expect(second.id.generation > first.id.generation);
    try std.testing.expectError(error.StaleResource, registry.acknowledgeDestroy(first, .buffer));
}

test "remote registry invalidates worker refs without pretending reupload" {
    var registry = try init(std.testing.allocator, 7, 1);
    defer registry.deinit();
    const old = try registry.reserve(.target);
    try registry.acknowledgeCreate(old, .target);
    try std.testing.expectError(error.InvalidWorker, registry.invalidateForRestart(7));
    try registry.invalidateForRestart(8);
    try std.testing.expectError(error.StaleWorker, registry.requireLive(old, .target));
    const fresh = try registry.reserve(.target);
    try std.testing.expectError(error.NotLive, registry.requireLive(fresh, .target));
    try registry.acknowledgeCreate(fresh, .target);
    try registry.requireLive(fresh, .target);
}

test "remote registry generation exhaustion cannot wrap or reuse" {
    var registry = try init(std.testing.allocator, 1, 1);
    defer registry.deinit();
    var ref = try registry.reserve(.sampler);
    registry.entries.items[0].generation = std.math.maxInt(u32);
    ref.id.generation = std.math.maxInt(u32);
    try registry.acknowledgeCreate(ref, .sampler);
    try registry.beginDestroy(ref, .sampler);
    try registry.acknowledgeDestroy(ref, .sampler);
    try std.testing.expectError(error.ResourceLimit, registry.reserve(.sampler));
    try registry.invalidateForRestart(2);
    try std.testing.expectError(error.ResourceLimit, registry.reserve(.sampler));
}

test "remote registry rejected create invalidates reservation and bad slots" {
    var registry = try init(std.testing.allocator, 1, 1);
    defer registry.deinit();
    const old = try registry.reserve(.pipeline);
    try registry.rejectCreate(old, .pipeline);
    try std.testing.expectError(error.StaleResource, registry.acknowledgeCreate(old, .pipeline));
    try std.testing.expectError(error.InvalidSlot, registry.requireLive(.{ .worker = 1, .id = .{ .slot = 3, .generation = 1 } }, .buffer));
}

fn allocationCase(alloc: std.mem.Allocator) !void {
    var registry = try init(alloc, 1, 3);
    defer registry.deinit();
    const ref = try registry.reserve(.buffer);
    try registry.acknowledgeCreate(ref, .buffer);
    try registry.beginDestroy(ref, .buffer);
    try registry.acknowledgeDestroy(ref, .buffer);
}

test "remote registry allocation failures retain ownership" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

test "remote registry rejects invalid session and capacity limits" {
    try std.testing.expectError(error.InvalidWorker, init(std.testing.allocator, 0, 1));
    try std.testing.expectError(error.InvalidLimit, init(std.testing.allocator, 1, 0));
    try std.testing.expectError(error.InvalidLimit, init(std.testing.allocator, 1, hard_slot_limit + 1));
}
