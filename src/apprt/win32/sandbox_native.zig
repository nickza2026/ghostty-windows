//! Native-only adapter. No process launch, ambient package selection or VM control.
const std = @import("std");
const launch = @import("sandbox_launch.zig");
const environment = @import("sandbox_environment.zig");

pub const Context = struct {
    executable: []u8,
    plan: launch.Plan,

    pub fn init(a: std.mem.Allocator, io: std.Io, executable: []const u8, metadata: environment.SystemMetadata) !Context {
        const owned = try a.dupe(u8, executable);
        errdefer a.free(owned);
        return .{ .executable = owned, .plan = try launch.init(a, io, executable, metadata) };
    }
    pub fn deinit(self: *Context) void {
        self.plan.allocator.free(self.executable);
        self.plan.deinit();
        self.* = undefined;
    }
    pub fn revalidate(self: *const Context, a: std.mem.Allocator, io: std.Io) !launch.Plan {
        return launch.init(a, io, self.executable, .{
            .system_root = self.plan.env.get("SystemRoot").?,
            .program_data = self.plan.env.get("ProgramData").?,
        });
    }
    pub fn freshEnvironment(self: *const Context, a: std.mem.Allocator) std.mem.Allocator.Error!std.process.Environ.Map {
        // Context.init already validated and owns this allowlist. Clone it rather
        // than widening global.environMap's established error contract with path
        // validation errors. Filesystem revalidation remains a separate step.
        return self.plan.env.clone(a);
    }
    /// Invoke only after finalize; every pointer belongs to the finalized arena.
    pub fn applyConfig(self: *const Context, config: anytype) !void {
        const a = config.arenaAlloc();
        const args = try a.alloc([:0]const u8, 4);
        for (self.plan.argv(), 0..) |arg, i| args[i] = try a.dupeZ(u8, arg);
        config.command = .{ .direct = args };
        config.@"working-directory" = .{ .path = try a.dupeZ(u8, self.plan.root) };
        config.@"shell-integration" = .none;
        config.@"wait-after-command" = false;
    }
};

test "fresh environment retains allocator-only errors and independent ownership" {
    const a = std.testing.allocator;
    var original = try environment.init(a, "R:\\sandbox", .{ .system_root = "C:\\Windows", .program_data = "C:\\ProgramData" });
    defer original.deinit();
    const context: Context = .{ .executable = undefined, .plan = .{
        .allocator = a,
        .root = undefined,
        .node = undefined,
        .entry = undefined,
        .native_storage = undefined,
        .env = original,
    } };
    const result: std.mem.Allocator.Error!std.process.Environ.Map = context.freshEnvironment(a);
    var cloned = try result;
    defer cloned.deinit();
    try std.testing.expectEqualStrings("R:\\sandbox\\Data", cloned.get("HOME").?);
    try cloned.put("HOME", "synthetic-independent-value");
    try std.testing.expectEqualStrings("R:\\sandbox\\Data", original.get("HOME").?);
    try std.testing.expect(cloned.get("OPENAI_API_KEY") == null);
}

test "native adapter keeps finalized policy in its destination arena" {
    const Mock = struct {
        arena: std.heap.ArenaAllocator,
        command: ?union(enum) { direct: []const [:0]const u8 } = null,
        @"working-directory": ?union(enum) { path: []const u8 } = null,
        @"shell-integration": enum { none, detect } = .detect,
        @"wait-after-command": bool = true,
        pub fn arenaAlloc(self: *@This()) std.mem.Allocator {
            return self.arena.allocator();
        }
    };
    const a = std.testing.allocator;
    var mock: Mock = .{ .arena = std.heap.ArenaAllocator.init(a) };
    defer mock.arena.deinit();
    // applyConfig borrows no source strings after it returns.
    var root = [_]u8{ 'R', ':', '\\', 'x' };
    const context: Context = .{ .executable = undefined, .plan = .{
        .allocator = a,
        .root = &root,
        .node = @constCast("R:\\x\\Runtime\\node\\node.exe"),
        .entry = @constCast("R:\\x\\App\\entry.cjs"),
        .native_storage = undefined,
        .env = undefined,
    } };
    try context.applyConfig(&mock);
    root[3] = 'y';
    try std.testing.expectEqualStrings("R:\\x", mock.command.?.direct[3]);
    try std.testing.expectEqualStrings("R:\\x", mock.@"working-directory".?.path);
    try std.testing.expectEqual(.none, mock.@"shell-integration");
    try std.testing.expect(!mock.@"wait-after-command");
}
