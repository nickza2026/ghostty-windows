//! Child policy for the native sandbox launch seam, not the ordinary portable shell.
//! Build a complete fresh map BEFORE CreateProcess. This module does not spawn,
//! select a package, create storage, or modify the host environment.
const std = @import("std");

pub const SystemMetadata = struct {
    system_root: []const u8,
    program_data: []const u8,
};

fn absoluteDirectory(value: []const u8) bool {
    if (!std.fs.path.isAbsolute(value) or std.mem.indexOfScalar(u8, value, 0) != null) return false;
    var parts = std.mem.tokenizeAny(u8, value, "\\/");
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}

/// The caller must obtain package_root from the executable and verify its
/// ownership, real directories, dependencies and storage policy separately.
/// SystemMetadata is OS metadata only: never accept config/provider overrides.
/// Map values are owned by the returned map; the caller must deinit it.
pub fn init(
    alloc: std.mem.Allocator,
    package_root: []const u8,
    system: SystemMetadata,
) !std.process.Environ.Map {
    if (!absoluteDirectory(package_root)) return error.InvalidSandboxRoot;
    if (!absoluteDirectory(system.system_root) or !absoluteDirectory(system.program_data)) return error.InvalidSystemMetadata;

    var env = std.process.Environ.Map.init(alloc);
    errdefer env.deinit();
    const data = try std.fs.path.join(alloc, &.{ package_root, "Data" });
    defer alloc.free(data);
    const profile = try std.fs.path.join(alloc, &.{ data, "profile" });
    defer alloc.free(profile);
    const local = try std.fs.path.join(alloc, &.{ data, "local" });
    defer alloc.free(local);
    const system32 = try std.fs.path.join(alloc, &.{ system.system_root, "System32" });
    defer alloc.free(system32);

    try env.put("SystemRoot", system.system_root);
    // Inbox OpenSSH needs this OS metadata; this is not a provider/profile root.
    try env.put("ProgramData", system.program_data);
    try env.put("PATH", system32);
    for ([_][]const u8{ "HOME", "USERPROFILE", "TEMP", "TMP" }) |key| try env.put(key, data);
    try env.put("APPDATA", profile);
    try env.put("LOCALAPPDATA", local);
    try env.put("TERM", "xterm-256color");
    try env.put("NoDefaultCurrentDirectoryInExePath", "1");
    return env;
}

const test_system: SystemMetadata = .{ .system_root = "C:\\Windows", .program_data = "C:\\ProgramData" };

test "sandbox child is a fresh allowlist with no runtime injection or credentials" {
    var env = try init(std.testing.allocator, "R:\\sandbox", test_system);
    defer env.deinit();
    try std.testing.expectEqual(@as(usize, 11), env.count());
    for ([_][]const u8{ "NODE_OPTIONS", "NODE_COMPILE_CACHE", "NODE_PATH", "OPENAI_API_KEY", "LETTA_BASE_URL", "MEMORY_DIR", "SSH_AUTH_SOCK", "LOCALTERM_PORTABLE_TOOLS", "NPM_CONFIG_USERCONFIG", "HTTPS_PROXY" }) |key| {
        try std.testing.expect(env.get(key) == null);
    }
    try std.testing.expectEqualStrings("R:\\sandbox\\Data", env.get("USERPROFILE").?);
    try std.testing.expectEqualStrings("C:\\Windows\\System32", env.get("PATH").?);
    try std.testing.expectEqualStrings("C:\\ProgramData", env.get("ProgramData").?);
}

test "relocation uses the new explicit root including Thai spaces and apostrophe" {
    const root = "S:\\ชุดใหม่ space's\\Sandbox";
    var env = try init(std.testing.allocator, root, test_system);
    defer env.deinit();
    const expected = try std.fs.path.join(std.testing.allocator, &.{ root, "Data" });
    defer std.testing.allocator.free(expected);
    for ([_][]const u8{ "HOME", "USERPROFILE", "TEMP", "TMP" }) |key| try std.testing.expectEqualStrings(expected, env.get(key).?);
    try std.testing.expect(std.mem.startsWith(u8, env.get("APPDATA").?, expected));
    try std.testing.expect(std.mem.startsWith(u8, env.get("LOCALAPPDATA").?, expected));
}

test "invalid roots or OS metadata fail rather than selecting host storage" {
    for ([_][]const u8{ "", "relative", "R:\\sandbox\\..\\other", "R:\\sandbox\x00suffix" }) |root| {
        try std.testing.expectError(error.InvalidSandboxRoot, init(std.testing.allocator, root, test_system));
    }
    try std.testing.expectError(error.InvalidSystemMetadata, init(std.testing.allocator, "R:\\sandbox", .{ .system_root = "Windows", .program_data = "C:\\ProgramData" }));
    try std.testing.expectError(error.InvalidSystemMetadata, init(std.testing.allocator, "R:\\sandbox", .{ .system_root = "C:\\Windows", .program_data = "" }));
}

fn allocationProbe(alloc: std.mem.Allocator) !void {
    var env = try init(alloc, "R:\\sandbox", test_system);
    defer env.deinit();
}

test "allocation failure never returns a partial environment" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
