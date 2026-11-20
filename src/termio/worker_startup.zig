//! Windows surface worker startup transaction. The caller retains ownership
//! only after both workers start; partial startup must not outlive its state.
const std = @import("std");

pub fn start(comptime Operations: type, context: anytype) !void {
    try Operations.startRenderer(context);
    errdefer Operations.stopAndJoinRenderer(context);
    try Operations.startIo(context);
}

const Event = enum { renderer, io, stop_renderer, join_renderer, dependencies_destroyed };
const Fake = struct {
    fail_renderer: bool = false,
    fail_io: bool = false,
    renderer_live: bool = false,
    io_live: bool = false,
    dependencies_destroyed_while_live: bool = false,
    events: [8]Event = undefined,
    count: usize = 0,

    fn note(self: *Fake, event: Event) void {
        self.events[self.count] = event;
        self.count += 1;
    }
    pub fn startRenderer(self: *Fake) !void {
        self.note(.renderer);
        if (self.fail_renderer) return error.RendererSpawnFailed;
        self.renderer_live = true;
    }
    pub fn startIo(self: *Fake) !void {
        self.note(.io);
        if (self.fail_io) return error.IoSpawnFailed;
        self.io_live = true;
    }
    pub fn stopAndJoinRenderer(self: *Fake) void {
        std.debug.assert(self.renderer_live);
        self.note(.stop_renderer);
        self.note(.join_renderer);
        self.renderer_live = false;
    }
    fn destroyDependencies(self: *Fake) void {
        self.dependencies_destroyed_while_live = self.renderer_live or self.io_live;
        self.note(.dependencies_destroyed);
    }
};

test "worker startup success transfers both live workers without rollback" {
    var state: Fake = .{};
    try start(Fake, &state);
    try std.testing.expect(state.renderer_live and state.io_live);
    try std.testing.expectEqualSlices(Event, &.{ .renderer, .io }, state.events[0..state.count]);
}

test "worker startup renderer failure never starts IO or joins an absent worker" {
    var state: Fake = .{ .fail_renderer = true };
    try std.testing.expectError(error.RendererSpawnFailed, start(Fake, &state));
    state.destroyDependencies();
    try std.testing.expect(!state.dependencies_destroyed_while_live);
    try std.testing.expectEqualSlices(Event, &.{ .renderer, .dependencies_destroyed }, state.events[0..state.count]);
}

test "worker startup IO failure stops and joins renderer before dependency cleanup" {
    var state: Fake = .{ .fail_io = true };
    try std.testing.expectError(error.IoSpawnFailed, start(Fake, &state));
    state.destroyDependencies();
    try std.testing.expect(!state.dependencies_destroyed_while_live);
    try std.testing.expectEqualSlices(Event, &.{ .renderer, .io, .stop_renderer, .join_renderer, .dependencies_destroyed }, state.events[0..state.count]);
}
