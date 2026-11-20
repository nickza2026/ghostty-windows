//! Display branding only; internal window classes/protocols remain compatible.
const std = @import("std");

pub fn name(comptime sandbox: bool) []const u8 {
    return if (sandbox) "Sandbox" else "localterm-dev";
}

pub fn windowTitle(alloc: std.mem.Allocator, comptime sandbox: bool, text: []const u8) ![]u8 {
    if (sandbox) return alloc.dupe(u8, name(true));
    return std.fmt.allocPrint(alloc, "localterm-dev — {s}", .{text});
}

pub fn caption(comptime sandbox: bool, comptime suffix: []const u8) []const u8 {
    return comptime name(sandbox) ++ suffix;
}

pub fn launchFailure(comptime sandbox: bool) []const u8 {
    return if (sandbox) "Sandbox failed to launch the requested command:" else "Ghostty failed to launch the requested command:";
}

test "sandbox name and title never expose development or backend process labels" {
    try std.testing.expectEqualStrings("Sandbox", name(true));
    for ([_][]const u8{ "A:\\sandbox\\Runtime\\node\\node.exe", "", "guest shell" }) |text| {
        const title = try windowTitle(std.testing.allocator, true, text);
        defer std.testing.allocator.free(title);
        try std.testing.expectEqualStrings("Sandbox", title);
    }
}

test "ordinary native terminal title remains unchanged" {
    try std.testing.expectEqualStrings("localterm-dev", name(false));
    const title = try windowTitle(std.testing.allocator, false, "user shell");
    defer std.testing.allocator.free(title);
    try std.testing.expectEqualStrings("localterm-dev — user shell", title);
}

test "sandbox dialog and launch-error labels are branded without changing upstream labels" {
    try std.testing.expectEqualStrings("Sandbox — close session", caption(true, " — close session"));
    try std.testing.expectEqualStrings("localterm-dev — clipboard permission", caption(false, " — clipboard permission"));
    try std.testing.expectEqualStrings("Sandbox failed to launch the requested command:", launchFailure(true));
    try std.testing.expectEqualStrings("Ghostty failed to launch the requested command:", launchFailure(false));
}
