//! Shared production dispatch loop and deterministic queue regression cases.
const std = @import("std");

pub fn run(comptime Message: type, api: anytype) !Message {
    var message: Message = undefined;
    while (true) {
        const result = api.get(&message);
        if (result == -1) return error.MessageLoopFailed;
        if (result == 0) break;
        api.dispatch(&message);
        // Preserve the existing two bounded input/paint + timer priority passes.
        for (0..2) |pass| {
            const flags: u32 = if (pass == 0) 0x04270001 else 1;
            const filter: u32 = if (pass == 0) 0 else 0x0113;
            var priority: Message = undefined;
            if (!api.peek(&priority, filter, flags)) continue;
            // WM_QUIT may be removed by PeekMessage too. Return THAT message,
            // never the prior dispatched key/timer/wake's unrelated wparam.
            if (priority.message == 0x0012) return priority;
            api.dispatch(&priority);
        }
    }
    return message;
}

const TestMessage = struct { message: u32, wparam: usize };
const Queue = struct {
    ordinary: usize = 65,
    quit: usize = 0,
    priority_quit: bool = true,
    fail_get: bool = false,
    gets: usize = 0,
    dispatched: usize = 0,
    peek_count: usize = 0,
    filters: [2]u32 = .{ 0, 0 },
    flags: [2]u32 = .{ 0, 0 },

    fn get(self: *@This(), out: *TestMessage) i32 {
        if (self.fail_get) return -1;
        self.gets += 1;
        out.* = if (self.gets == 1) .{ .message = 0x8000, .wparam = self.ordinary } else .{ .message = 0x0012, .wparam = self.quit };
        return if (self.gets == 1) 1 else 0;
    }
    fn peek(self: *@This(), out: *TestMessage, filter: u32, flags: u32) bool {
        if (self.peek_count < 2) {
            self.filters[self.peek_count] = filter;
            self.flags[self.peek_count] = flags;
        }
        self.peek_count += 1;
        if (!self.priority_quit) return false;
        out.* = .{ .message = 0x0012, .wparam = self.quit };
        return true;
    }
    fn dispatch(self: *@This(), _: *const TestMessage) void {
        self.dispatched += 1;
    }
};

test "priority quit success must not use previous ordinary nonzero wparam" {
    var queue: Queue = .{};
    const quit = try run(TestMessage, &queue);
    try std.testing.expectEqual(@as(u32, 0x0012), quit.message);
    try std.testing.expectEqual(@as(usize, 0), quit.wparam);
    try std.testing.expectEqual(@as(usize, 1), queue.dispatched);
}

test "priority quit error must not be lost behind previous zero wparam" {
    var queue: Queue = .{ .ordinary = 0, .quit = 7 };
    const quit = try run(TestMessage, &queue);
    try std.testing.expectEqual(@as(usize, 7), quit.wparam);
}

test "ordinary GetMessage quit and bounded priority classes remain unchanged" {
    var queue: Queue = .{ .priority_quit = false, .quit = 9 };
    const quit = try run(TestMessage, &queue);
    try std.testing.expectEqual(@as(usize, 9), quit.wparam);
    try std.testing.expectEqual(@as(usize, 2), queue.peek_count);
    try std.testing.expectEqualSlices(u32, &.{ 0, 0x0113 }, &queue.filters);
    try std.testing.expectEqualSlices(u32, &.{ 0x04270001, 1 }, &queue.flags);
    try std.testing.expectEqual(@as(usize, 1), queue.dispatched);
}

test "GetMessage failure is still an error" {
    var queue: Queue = .{ .fail_get = true };
    try std.testing.expectError(error.MessageLoopFailed, run(TestMessage, &queue));
}
