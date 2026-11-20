//! Private lifecycle fixture ledger. Records actual owned handles, not DLL
//! ownership. A returned join/deinit is deliberately NOT a native-close result.
const std = @import("std");
const builtin = @import("builtin");

pub const Role = enum { renderer, io, reader, renderer_iocp, io_iocp };
pub const End = enum { join_returned, deinit_returned };
/// libxev Dynamic collapses to the static backend when only one is available.
/// Inspect the instantiated type rather than assuming a union from its name.
pub fn loopHandle(loop: anytype) std.os.windows.HANDLE {
    if (comptime @hasField(@TypeOf(loop.*), "iocp_handle")) return loop.iocp_handle;
    return loop.backend.iocp.iocp_handle;
}
const Entry = struct {
    sequence: usize,
    generation: usize,
    role: Role,
    handle: usize,
    creator: u32,
    target: u32,
    created: u64,
    end_sequence: usize = 0,
    end: End = .deinit_returned,
};

pub fn Store(comptime capacity: usize) type {
    return struct {
        entries: [capacity]Entry = undefined,
        used: usize = 0,
        sequence: usize = 0,
        faults: usize = 0,

        fn begin(self: *@This(), generation: usize, role: Role, handle: usize, creator: u32, target: u32, created: u64) void {
            for (self.entries[0..self.used]) |entry| {
                if (entry.handle == handle and entry.end_sequence == 0) self.faults += 1;
            }
            if (self.used == capacity) {
                self.faults += 1;
                return;
            }
            self.sequence += 1;
            self.entries[self.used] = .{ .sequence = self.sequence, .generation = generation, .role = role, .handle = handle, .creator = creator, .target = target, .created = created };
            self.used += 1;
        }

        fn finish(self: *@This(), handle: usize, end: End) void {
            var index = self.used;
            while (index > 0) {
                index -= 1;
                const entry = &self.entries[index];
                if (entry.handle != handle or entry.end_sequence != 0) continue;
                self.sequence += 1;
                entry.end_sequence = self.sequence;
                entry.end = end;
                return;
            }
            self.faults += 1;
        }
    };
}

var enabled: std.atomic.Value(bool) = .init(false);
var locked: std.atomic.Value(bool) = .init(false);
var current_generation: usize = 0;
var store: Store(512) = .{};

fn lock() void {
    while (locked.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}
fn unlock() void {
    locked.store(false, .release);
}
pub fn start() void {
    lock();
    store = .{};
    current_generation = 0;
    unlock();
    enabled.store(true, .release);
}
pub fn setGeneration(value: usize) void {
    if (!enabled.load(.acquire)) return;
    lock();
    current_generation = value;
    unlock();
}

const Native = struct {
    const Time = extern struct { low: u32, high: u32 };
    extern "kernel32" fn GetThreadId(std.os.windows.HANDLE) callconv(.winapi) u32;
    extern "kernel32" fn GetProcessIdOfThread(std.os.windows.HANDLE) callconv(.winapi) u32;
    extern "kernel32" fn GetThreadTimes(std.os.windows.HANDLE, *Time, *Time, *Time, *Time) callconv(.winapi) i32;
    extern "kernel32" fn SetLastError(u32) callconv(.winapi) void;
};
fn createdAt(handle: std.os.windows.HANDLE) u64 {
    var created: Native.Time = undefined;
    var exited: Native.Time = undefined;
    var kernel: Native.Time = undefined;
    var user: Native.Time = undefined;
    if (Native.GetThreadTimes(handle, &created, &exited, &kernel, &user) == 0) return 0;
    return (@as(u64, created.high) << 32) | created.low;
}
pub fn acquire(role: Role, handle: std.os.windows.HANDLE) void {
    if (comptime builtin.os.tag != .windows) return;
    if (!enabled.load(.acquire)) return;
    const saved = std.os.windows.GetLastError();
    defer Native.SetLastError(@intFromEnum(saved));
    const thread = switch (role) {
        .renderer, .io, .reader => true,
        else => false,
    };
    const target = if (thread) Native.GetThreadId(handle) else 0;
    const created = if (thread) createdAt(handle) else 0;
    lock();
    defer unlock();
    store.begin(current_generation, role, @intFromPtr(handle), std.os.windows.GetCurrentThreadId(), target, created);
    if (thread and (target == 0 or created == 0)) store.faults += 1;
}
pub fn release(handle: std.os.windows.HANDLE, end: End) void {
    if (comptime builtin.os.tag != .windows) return;
    if (!enabled.load(.acquire)) return;
    lock();
    defer unlock();
    store.finish(@intFromPtr(handle), end);
}
/// Called only on the already-opened diagnostic thread handle. Check process
/// identity before reading creation time; enumeration TIDs may have been reused.
pub fn snapshotThread(handle: std.os.windows.HANDLE, tid: u32) void {
    if (comptime builtin.os.tag != .windows) return;
    if (!enabled.load(.acquire)) return;
    const saved = std.os.windows.GetLastError();
    defer Native.SetLastError(@intFromEnum(saved));
    if (Native.GetProcessIdOfThread(handle) != std.os.windows.GetCurrentProcessId()) return;
    std.log.info("ownedledger snapshot_thread tid={d} created={d}", .{ tid, createdAt(handle) });
}
pub fn emit() void {
    if (!enabled.swap(false, .acq_rel)) return;
    lock();
    const snapshot = store;
    unlock();
    var active: usize = 0;
    for (snapshot.entries[0..snapshot.used]) |entry| {
        if (entry.end_sequence == 0) active += 1;
        std.log.info("ownedledger seq={d} generation={d} role={s} handle=0x{x} creator={d} target={d} created={d} end_seq={d} end={s}", .{
            entry.sequence,                                                     entry.generation, @tagName(entry.role), entry.handle,
            entry.creator,                                                      entry.target,     entry.created,        entry.end_sequence,
            if (entry.end_sequence == 0) "unobserved" else @tagName(entry.end),
        });
    }
    std.log.info("ownedledger summary entries={d} active={d} faults={d} capacity=512 native_close_results=unobserved coverage=surface_workers_and_iocp_only", .{ snapshot.used, active, snapshot.faults });
}

test "ledger records returned join without pretending native close succeeded" {
    var data: Store(2) = .{};
    data.begin(1, .renderer, 44, 7, 8, 900);
    data.finish(44, .join_returned);
    try std.testing.expectEqual(@as(usize, 0), data.faults);
    try std.testing.expectEqual(End.join_returned, data.entries[0].end);
    try std.testing.expect(data.entries[0].end_sequence > data.entries[0].sequence);
}
test "ledger preserves generations across reused handle slots" {
    var data: Store(2) = .{};
    data.begin(1, .io_iocp, 44, 7, 0, 0);
    data.finish(44, .deinit_returned);
    data.begin(2, .renderer, 44, 7, 99, 901);
    try std.testing.expectEqual(@as(usize, 2), data.used);
    try std.testing.expectEqual(@as(usize, 0), data.entries[1].end_sequence);
    try std.testing.expectEqual(@as(usize, 1), data.entries[0].generation);
}
test "ledger overlapping lifetimes make coverage incomplete" {
    var data: Store(2) = .{};
    data.begin(1, .renderer, 44, 7, 8, 900);
    data.begin(1, .io, 44, 7, 9, 901);
    try std.testing.expectEqual(@as(usize, 1), data.faults);
}
test "ledger capacity does not overwrite earlier evidence" {
    var data: Store(1) = .{};
    data.begin(1, .renderer, 44, 7, 8, 900);
    data.begin(1, .io, 45, 7, 9, 901);
    try std.testing.expectEqual(@as(usize, 1), data.faults);
    try std.testing.expectEqual(@as(usize, 44), data.entries[0].handle);
}
test "ledger unmatched release is not silently accepted" {
    var data: Store(1) = .{};
    data.finish(99, .join_returned);
    try std.testing.expectEqual(@as(usize, 1), data.faults);
}

test "Windows metadata bindings use an owned worker handle" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const Worker = struct {
        fn run() void {}
    };
    start();
    defer enabled.store(false, .release);
    const worker = try std.Thread.spawn(.{}, Worker.run, .{});
    const handle = worker.getHandle();
    acquire(.reader, handle);
    snapshotThread(handle, store.entries[0].target);
    worker.join();
    release(handle, .join_returned);
    try std.testing.expectEqual(@as(usize, 1), store.used);
    try std.testing.expectEqual(@as(usize, 0), store.faults);
    try std.testing.expect(store.entries[0].target != 0 and store.entries[0].created != 0);
    try std.testing.expect(store.entries[0].end_sequence != 0);
}

test "Windows loop handle extraction supports static and dynamic backend shapes" {
    const Static = struct { iocp_handle: std.os.windows.HANDLE };
    var direct: Static = .{ .iocp_handle = @ptrFromInt(0x44) };
    var dynamic: struct { backend: union(enum) { iocp: Static } } = .{ .backend = .{ .iocp = direct } };
    try std.testing.expectEqual(@as(usize, 0x44), @intFromPtr(loopHandle(&direct)));
    try std.testing.expectEqual(@as(usize, 0x44), @intFromPtr(loopHandle(&dynamic)));
}
