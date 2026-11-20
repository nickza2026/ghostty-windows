//! Low-memory adapter regression; no GUI, host clipboard, process or VM access.
const std = @import("std");
const clipboard = @import("sandbox_clipboard.zig");

const MockConfig = struct {
    arena: std.heap.ArenaAllocator,
    keybind: struct {
        values: [2][]const u8 = undefined,
        count: usize = 0,
        pub fn parseCLI(self: *@This(), alloc: std.mem.Allocator, value: []const u8) !void {
            if (self.count >= self.values.len) return error.UnexpectedClipboardBinding;
            self.values[self.count] = try alloc.dupe(u8, value);
            self.count += 1;
        }
    } = .{},
    @"right-click-action": enum { context_menu, copy } = .context_menu,
    @"clipboard-read": enum { ask, allow, deny } = .ask,
    @"clipboard-write": enum { ask, allow, deny } = .deny,
    pub fn arenaAlloc(self: *@This()) std.mem.Allocator {
        return self.arena.allocator();
    }
};

test "manual shortcut adapter registers conditional copy and explicit paste without guest permissions" {
    var cfg: MockConfig = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer cfg.arena.deinit();
    try clipboard.apply(&cfg);
    try std.testing.expectEqual(@as(usize, 2), cfg.keybind.count);
    try std.testing.expectEqualStrings("performable:ctrl+c=copy_to_clipboard", cfg.keybind.values[0]);
    try std.testing.expectEqualStrings("ctrl+v=paste_from_clipboard", cfg.keybind.values[1]);
    try std.testing.expectEqual(.copy, cfg.@"right-click-action");
    try std.testing.expectEqual(.ask, cfg.@"clipboard-read");
    try std.testing.expectEqual(.deny, cfg.@"clipboard-write");
}
