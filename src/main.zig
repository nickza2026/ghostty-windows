const std = @import("std");
const build_config = @import("build_config.zig");

/// See build_config.ExeEntrypoint for why we do this.
const entrypoint = switch (build_config.exe_entrypoint) {
    .ghostty => @import("main_ghostty.zig"),
    .helpgen => @import("helpgen.zig"),
    .mdgen_ghostty_1 => @import("build/mdgen/main_ghostty_1.zig"),
    .mdgen_ghostty_5 => @import("build/mdgen/main_ghostty_5.zig"),
    .webgen_config => @import("build/webgen/main_config.zig"),
    .webgen_actions => @import("build/webgen/main_actions.zig"),
    .webgen_commands => @import("build/webgen/main_commands.zig"),
};

/// The main entrypoint for the program.
pub const main = entrypoint.main;

/// Standard options such as logger overrides.
pub const std_options: std.Options = if (@hasDecl(entrypoint, "std_options"))
    entrypoint.std_options
else
    .{};

comptime {
    // Force-reference our memset override so its export is emitted.
    // See quirks_memset.zig for details on why this exists.
    _ = @import("quirks_memset.zig");
}

test {
    // Zig 0.16.0 has made test logging more strict. Now, *anything* that gets
    // printed to stderr results in a "failed command" message, even if the
    // tests ultimately passed. To reduce confusion here (and honestly, test
    // log spam in general), we bump the default testing log level to error.
    std.testing.log_level = std.log.Level.err;
    _ = entrypoint;
    _ = @import("quirks_memset.zig");
}

// Keep this regression directly in the test root: app-runtime=none does not
// otherwise instantiate Config's tests through the native entrypoint.
test "sandbox manual clipboard shortcuts preserve interrupt and alternate bindings" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const testing = std.testing;
    const inputpkg = @import("input.zig");
    var cfg = try @import("config/Config.zig").default(testing.allocator);
    defer cfg.deinit();
    const read_policy = cfg.@"clipboard-read";
    const write_policy = cfg.@"clipboard-write";
    try testing.expect(cfg.keybind.set.getEvent(.{ .action = .press, .key = .key_c, .mods = .{ .ctrl = true }, .unshifted_codepoint = 'c' }) == null);
    try testing.expect(cfg.keybind.set.getEvent(.{ .action = .press, .key = .key_v, .mods = .{ .ctrl = true }, .unshifted_codepoint = 'v' }) == null);
    try @import("apprt/win32/sandbox_clipboard.zig").apply(&cfg);
    const copy = cfg.keybind.set.getEvent(.{ .action = .press, .key = .key_c, .mods = .{ .ctrl = true }, .unshifted_codepoint = 'c' });
    try testing.expect(copy != null);
    try testing.expect(copy.?.value_ptr.* == .leaf);
    try testing.expect(copy.?.value_ptr.leaf.action == .copy_to_clipboard);
    try testing.expect(copy.?.value_ptr.leaf.flags.performable);
    const paste = cfg.keybind.set.getEvent(.{ .action = .press, .key = .key_v, .mods = .{ .ctrl = true }, .unshifted_codepoint = 'v' });
    try testing.expect(paste != null);
    try testing.expect(paste.?.value_ptr.leaf.action == .paste_from_clipboard);
    try testing.expect(!paste.?.value_ptr.leaf.flags.performable);
    try testing.expectEqual(.copy, cfg.@"right-click-action");
    for ([_]inputpkg.Key{ .key_c, .key_v }) |key| {
        try testing.expect(cfg.keybind.set.getEvent(.{ .action = .press, .key = key, .mods = .{ .ctrl = true, .shift = true }, .unshifted_codepoint = if (key == .key_c) 'c' else 'v' }) != null);
    }
    try testing.expectEqual(read_policy, cfg.@"clipboard-read");
    try testing.expectEqual(write_policy, cfg.@"clipboard-write");
}
