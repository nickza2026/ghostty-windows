//! First-run bootstrap for an explicitly portable build, not normal installs.
//! Only creates app-owned storage beside the running executable. No cwd/HOME
//! or host fallback; no child profile/account/credential changes.
const std = @import("std");
const paths = @import("portable_paths.zig");

pub fn init(alloc: std.mem.Allocator, io: std.Io, exe_dir: []const u8) !paths.Layout {
    if (!try paths.selected(alloc, io, exe_dir)) {
        var exe = try std.Io.Dir.openDirAbsolute(io, exe_dir, .{ .follow_symlinks = false });
        defer exe.close(io);
        exe.createDir(io, "portable-data", .default_dir) catch |err| switch (err) {
            // Another startup may have created it; Layout still validates it
            // as a real directory, rejects links/files, and checks writes.
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
    return (try paths.Layout.init(alloc, io, exe_dir)) orelse error.PortableDataMissing;
}

test "portable build creates absent storage beside explicit executable root" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "exe ไทย space", .default_dir);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const base = buffer[0..try tmp.dir.realPath(io, &buffer)];
    const exe = try std.fs.path.join(a, &.{ base, "exe ไทย space" });
    defer a.free(exe);
    try std.testing.expect(!try paths.selected(a, io, exe));
    var layout = try init(a, io, exe);
    defer layout.deinit();
    try layout.verify(io);
    try std.testing.expect(try paths.selected(a, io, exe));
    try std.testing.expect(std.mem.startsWith(u8, layout.root, exe));
    // Merely invoking the normal selector has no first-run creation effects.
    try std.testing.expect(!try paths.selected(a, io, base));
}

test "portable first run preserves existing config and rejects file marker" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const exe = buffer[0..try tmp.dir.realPath(io, &buffer)];
    const marker = try tmp.dir.createFile(io, "portable-data", .{});
    try marker.writeStreamingAll(io, "keep");
    marker.close(io);
    try std.testing.expectError(error.InvalidPortableDataDirectory, init(a, io, exe));
    try std.testing.expectEqual(@as(u64, 4), (try tmp.dir.statFile(io, "portable-data", .{})).size);
    try tmp.dir.deleteFile(io, "portable-data");
    var first = try init(a, io, exe);
    defer first.deinit();
    const file = try tmp.dir.createFile(io, "portable-data/config/config.ghostty", .{});
    try file.writeStreamingAll(io, "font-size = 19\n");
    file.close(io);
    var second = try init(a, io, exe);
    defer second.deinit();
    try std.testing.expectEqual(@as(u64, 15), (try tmp.dir.statFile(io, "portable-data/config/config.ghostty", .{})).size);
}
