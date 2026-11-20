//! Per-surface temporary image paths. No clipboard or shell access here.
//! Files are exclusive-created, bounded, and removed only if their recorded
//! identity/size still match. A crash may leave files; no wildcard scavenging.
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const max_files = 16;
pub const max_total_bytes = 128 * 1024 * 1024;
const Item = struct {
    path: []u8,
    quoted: []u8,
    inode: std.Io.File.INode,
    size: u64,
};

pub const Store = struct {
    items: std.ArrayList(Item) = .empty,
    bytes: usize = 0,

    pub fn deinit(self: *Store, alloc: Allocator, io: std.Io) void {
        while (self.items.items.len != 0) self.rollback(alloc, io);
        self.items.deinit(alloc);
        self.* = .{};
    }

    /// The caller has validated PNG content. Returned text is borrowed until
    /// rollback/deinit. Quoting targets the current Win32 PowerShell shell.
    pub fn save(self: *Store, alloc: Allocator, io: std.Io, directory: []const u8, png: []const u8) ![]const u8 {
        if (self.items.items.len >= max_files or png.len == 0 or
            png.len > max_total_bytes - self.bytes) return error.ImagePasteLimit;
        try validateDirectory(directory);
        try self.items.ensureUnusedCapacity(alloc, 1);
        var nonce: [16]u8 = undefined;
        try std.Io.randomSecure(io, &nonce);
        const hex = std.fmt.bytesToHex(nonce, .lower);
        const filename = try std.fmt.allocPrint(alloc, "localterm-image-{s}.png", .{hex});
        defer alloc.free(filename);
        const path = try std.fs.path.join(alloc, &.{ directory, filename });
        errdefer alloc.free(path);
        const quoted = try quotePowerShell(alloc, path);
        errdefer alloc.free(quoted);
        const file = try std.Io.Dir.createFileAbsolute(io, path, .{ .exclusive = true, .read = true });
        var retained = false;
        defer if (!retained) std.Io.Dir.deleteFileAbsolute(io, path) catch {};
        defer file.close(io);
        try file.writeStreamingAll(io, png);
        const stat = try file.stat(io);
        self.items.appendAssumeCapacity(.{ .path = path, .quoted = quoted, .inode = stat.inode, .size = stat.size });
        self.bytes += png.len;
        retained = true;
        return quoted;
    }

    pub fn rollback(self: *Store, alloc: Allocator, io: std.Io) void {
        const item = self.items.pop() orelse return;
        defer alloc.free(item.path);
        defer alloc.free(item.quoted);
        self.bytes -= @intCast(item.size);
        // Never recursively delete a temp directory or sweep other sessions.
        const file = std.Io.Dir.openFileAbsolute(io, item.path, .{}) catch return;
        const stat = file.stat(io) catch {
            file.close(io);
            return;
        };
        file.close(io);
        if (stat.inode != item.inode or stat.size != item.size) return;
        std.Io.Dir.deleteFileAbsolute(io, item.path) catch |err| {
            std.log.warn("owned clipboard image cleanup failed: {}", .{err});
        };
    }
};

fn validateDirectory(path: []const u8) !void {
    // Clipboard images must not be staged onto an environment-supplied UNC
    // share. Only a local drive-qualified absolute temp directory is allowed.
    if (path.len < 3 or !std.ascii.isAlphabetic(path[0]) or path[1] != ':' or
        (path[2] != '\\' and path[2] != '/')) return error.InvalidImageTempDirectory;
    for (path) |c| if (c < 32 or c == 127) return error.InvalidImageTempDirectory;
}

pub fn quotePowerShell(alloc: Allocator, path: []const u8) ![]u8 {
    for (path) |c| if (c < 32 or c == 127) return error.InvalidImagePath;
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(alloc);
    try text.append(alloc, '\'');
    for (path) |c| {
        try text.append(alloc, c);
        if (c == '\'') try text.append(alloc, c);
    }
    try text.appendSlice(alloc, "' "); // No newline, Enter, command, or script.
    return text.toOwnedSlice(alloc);
}

test "clipboard image path quoting prevents PowerShell interpolation" {
    const a = std.testing.allocator;
    const text = try quotePowerShell(a, "C:\\user's data\\$(bad);image.png");
    defer a.free(text);
    try std.testing.expectEqualStrings("'C:\\user''s data\\$(bad);image.png' ", text);
    try std.testing.expectError(error.InvalidImagePath, quotePowerShell(a, "x\nexit"));
    try std.testing.expectError(error.InvalidImageTempDirectory, validateDirectory("\\\\server\\share"));
    try std.testing.expectError(error.InvalidImageTempDirectory, validateDirectory("relative"));
}

test "clipboard image staging and cleanup own only created files" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const a = std.testing.allocator;
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = buf[0..try dir.dir.realPath(io, &buf)];
    var store: Store = .{};
    defer store.deinit(a, io);
    _ = try store.save(a, io, path, "synthetic PNG fixture");
    const owned = try a.dupe(u8, store.items.items[0].path);
    defer a.free(owned);
    try std.testing.expectEqual(@as(usize, 1), store.items.items.len);
    store.rollback(a, io);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.openFileAbsolute(io, owned, .{}));
}
