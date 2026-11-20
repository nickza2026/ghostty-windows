//! Clipboard-only portable storage foundation, not a full portable release.
//! An existing portable-data directory beside the executable opts in. Never
//! select from cwd and never silently fall back after portable was selected.
const std = @import("std");

pub const Root = struct { path: []u8, portable: bool };

pub const portableSelected = @import("portable_paths.zig").selected;

pub fn resolve(alloc: std.mem.Allocator, io: std.Io, exe_dir: []const u8, normal_temp: ?[]const u8) !Root {
    return resolveSelected(alloc, io, exe_dir, normal_temp, try portableSelected(alloc, io, exe_dir));
}

/// The runtime snapshots selected at surface creation, not at each paste.
/// Removing the marker/drive after portable startup must never select host TEMP.
pub fn resolveSelected(alloc: std.mem.Allocator, io: std.Io, exe_dir: []const u8, normal_temp: ?[]const u8, selected: bool) !Root {
    if (!std.fs.path.isAbsolute(exe_dir)) return error.RelativeExecutableDirectory;
    if (!selected) return .{ .path = try alloc.dupe(u8, normal_temp orelse return error.NoImageTempDirectory), .portable = false };
    const marker = try std.fs.path.join(alloc, &.{ exe_dir, "portable-data" });
    defer alloc.free(marker);
    const stat = std.Io.Dir.cwd().statFile(io, marker, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return error.PortableDataMissing,
        else => return err,
    };
    if (stat.kind != .directory) return error.InvalidPortableDataDirectory;
    var data = try std.Io.Dir.openDirAbsolute(io, marker, .{ .follow_symlinks = false });
    defer data.close(io);
    // Open each level without following links. Don't recursively make a path
    // that could traverse a pre-existing cache junction to host storage.
    try createChild(data, io, "cache");
    var cache = try data.openDir(io, "cache", .{ .follow_symlinks = false });
    defer cache.close(io);
    try createChild(cache, io, "clipboard");
    var images = try cache.openDir(io, "clipboard", .{ .follow_symlinks = false });
    defer images.close(io);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try images.realPath(io, &buffer);
    return .{ .path = try alloc.dupe(u8, buffer[0..len]), .portable = true };
}

fn createChild(parent: std.Io.Dir, io: std.Io, name: []const u8) !void {
    parent.createDir(io, name, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const stat = try parent.statFile(io, name, .{ .follow_symlinks = false });
    if (stat.kind != .directory) return error.InvalidPortableDataDirectory;
}

test "clipboard portable marker removed after startup never selects host TEMP" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDir(io, "portable-data", .default_dir);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const exe_dir = buffer[0..try temp.dir.realPath(io, &buffer)];
    const selected = try portableSelected(a, io, exe_dir);
    try std.testing.expect(selected);
    try temp.dir.deleteDir(io, "portable-data");
    try std.testing.expectError(error.PortableDataMissing, resolveSelected(a, io, exe_dir, "C:\\must-not-use-host-temp", selected));
}

test "clipboard portable storage follows executable not working directory" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDir(io, "portable-data", .default_dir);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const exe_dir = buffer[0..try temp.dir.realPath(io, &buffer)];
    const root = try resolve(a, io, exe_dir, "C:\\must-not-use-host-temp");
    defer a.free(root.path);
    try std.testing.expect(root.portable);
    try std.testing.expect(std.mem.startsWith(u8, root.path, exe_dir));
    try std.testing.expect(std.mem.endsWith(u8, root.path, "cache\\clipboard"));
}

test "clipboard portable invalid marker fails without host fallback" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const file = try temp.dir.createFile(io, "portable-data", .{});
    file.close(io);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const exe_dir = buffer[0..try temp.dir.realPath(io, &buffer)];
    try std.testing.expectError(error.InvalidPortableDataDirectory, resolve(a, io, exe_dir, "C:\\must-not-use-host-temp"));
}
