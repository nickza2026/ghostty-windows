//! Executable-relative, trusted local-package consistency. Not a sandbox or
//! signed authenticity guarantee. Reject reparse paths before reads/creation.
const std = @import("std");
extern "kernel32" fn GetFileAttributesW([*:0]const u16) callconv(.winapi) u32;

fn attrs(a: std.mem.Allocator, path: []const u8) !u32 {
    const wide = try std.unicode.utf8ToUtf16LeAllocZ(a, path);
    defer a.free(wide);
    const value = GetFileAttributesW(wide);
    if (value == 0xffffffff) return error.OwnedPathMissing;
    if (value & 0x400 != 0) return error.OwnedPathReparsePoint;
    return value;
}

pub fn realPath(a: std.mem.Allocator, path: []const u8, directory: bool) !void {
    if (!std.fs.path.isAbsolute(path)) return error.OwnedPathNotAbsolute;
    const value = try attrs(a, path);
    if ((value & 0x10 != 0) != directory) return error.OwnedPathWrongKind;
    var parent = std.fs.path.dirname(path);
    while (parent) |p| : (parent = std.fs.path.dirname(p)) {
        if ((try attrs(a, p)) & 0x10 == 0) return error.OwnedPathWrongKind;
    }
}

pub fn safeRelative(path: []const u8) bool {
    if (path.len == 0 or std.mem.indexOfScalar(u8, path, ':') != null) return false;
    var parts = std.mem.splitAny(u8, path, "/\\");
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}

/// Create one checked path component at a time, never createDirPath through a
/// pre-existing unverified ancestor. Repeated startup preserves user data.
pub fn ensureDir(a: std.mem.Allocator, io: std.Io, root: []const u8, relative: []const u8) ![]const u8 {
    if (!safeRelative(relative)) return error.UnsafeOwnedRelativePath;
    try realPath(a, root, true);
    var current: []const u8 = root;
    var parts = std.mem.splitAny(u8, relative, "/\\");
    while (parts.next()) |part| {
        var parent = try std.Io.Dir.openDirAbsolute(io, current, .{ .follow_symlinks = false });
        defer parent.close(io);
        const next = try std.fs.path.join(a, &.{ current, part });
        _ = attrs(a, next) catch |err| switch (err) {
            error.OwnedPathMissing => blk: {
                try parent.createDir(io, part, .default_dir);
                break :blk try attrs(a, next);
            },
            else => return err,
        };
        try realPath(a, next, true);
        current = next;
    }
    return current;
}

pub fn writable(a: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    try realPath(a, path, true);
    var dir = try std.Io.Dir.openDirAbsolute(io, path, .{ .follow_symlinks = false });
    defer dir.close(io);
    var nonce: [16]u8 = undefined;
    io.random(&nonce);
    var buffer: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(&buffer, ".tools-probe-{s}", .{std.fmt.bytesToHex(nonce, .lower)});
    const file = try dir.createFile(io, name, .{ .exclusive = true });
    file.writeStreamingAll(io, "portable tools probe\n") catch |err| {
        file.close(io);
        dir.deleteFile(io, name) catch {};
        return err;
    };
    file.close(io);
    try dir.deleteFile(io, name);
}

pub fn blankConfig(a: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    const parent_path = std.fs.path.dirname(path) orelse return error.OwnedPathNotAbsolute;
    try realPath(a, parent_path, true);
    var parent = try std.Io.Dir.openDirAbsolute(io, parent_path, .{ .follow_symlinks = false });
    defer parent.close(io);
    const file = parent.createFile(io, std.fs.path.basename(path), .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => return realPath(a, path, false),
        else => return err,
    };
    file.close(io);
}

pub fn json(a: std.mem.Allocator, io: std.Io, path: []const u8) !std.json.Value {
    try realPath(a, path, false);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(4 * 1024 * 1024));
    const body = if (std.mem.startsWith(u8, bytes, &.{ 0xef, 0xbb, 0xbf })) bytes[3..] else bytes;
    return (try std.json.parseFromSlice(std.json.Value, a, body, .{ .allocate = .alloc_always })).value;
}

pub fn string(value: std.json.Value, name: []const u8) ![]const u8 {
    if (value != .object) return error.InvalidOwnedProvenance;
    const field = value.object.get(name) orelse return error.InvalidOwnedProvenance;
    if (field != .string) return error.InvalidOwnedProvenance;
    return field.string;
}

pub fn fileHash(a: std.mem.Allocator, io: std.Io, path: []const u8, expected: []const u8) !void {
    if (expected.len != 64) return error.InvalidOwnedDigest;
    try realPath(a, path, false);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(192 * 1024 * 1024));
    defer a.free(bytes);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    if (!std.ascii.eqlIgnoreCase(&hex, expected)) return error.OwnedDigestMismatch;
}

pub fn verifyPayload(a: std.mem.Allocator, io: std.Io, root: []const u8, metadata: []const u8, required: []const []const u8) !std.json.Value {
    try realPath(a, root, true);
    const document = try json(a, io, try std.fs.path.join(a, &.{ root, metadata }));
    if (document != .object) return error.InvalidOwnedProvenance;
    const files = document.object.get("files") orelse return error.InvalidOwnedProvenance;
    if (files != .object or files.object.count() == 0 or files.object.count() > 10000) return error.InvalidOwnedProvenance;
    for (required) |name| if (!files.object.contains(name)) return error.RequiredOwnedFileMissing;
    var entries = files.object.iterator();
    var folded: std.StringHashMapUnmanaged(void) = .empty;
    while (entries.next()) |entry| {
        const relative = entry.key_ptr.*;
        if (!safeRelative(relative) or entry.value_ptr.* != .string) return error.InvalidOwnedProvenance;
        const lower = try a.dupe(u8, relative);
        for (lower) |*c| c.* = std.ascii.toLower(c.*);
        if (try folded.fetchPut(a, lower, {})) |_| return error.DuplicateOwnedFile;
        try fileHash(a, io, try std.fs.path.join(a, &.{ root, relative }), entry.value_ptr.string);
    }
    // Enumerate the actual tree without following a junction: extras may also
    // be executable modules and must not escape the manifest verification.
    var pending: std.ArrayList([]const u8) = .empty;
    try pending.append(a, root);
    var count: usize = 0;
    while (pending.pop()) |path| {
        var dir = try std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true, .follow_symlinks = false });
        defer dir.close(io);
        var iterator = dir.iterate();
        while (try iterator.next(io)) |entry| {
            const full = try std.fs.path.join(a, &.{ path, entry.name });
            const value = try attrs(a, full);
            if (value & 0x10 != 0) {
                try pending.append(a, full);
            } else {
                const relative = try a.dupe(u8, full[root.len + 1 ..]);
                std.mem.replaceScalar(u8, relative, '\\', '/');
                if (!std.mem.eql(u8, relative, metadata) and !files.object.contains(relative)) return error.UnlistedOwnedFile;
                count += 1;
            }
        }
    }
    if (count != files.object.count() + 1) return error.RequiredOwnedFileMissing;
    return document;
}

test "owned metadata paths reject traversal drive relative and empty components" {
    for ([_][]const u8{ "../node.exe", "a/../b", "a\\..\\b", "D:node.exe", "/node.exe", "a//b", "a/./b", "" }) |bad| try std.testing.expect(!safeRelative(bad));
    try std.testing.expect(safeRelative("node_modules/npm/bin/npm-cli.js"));
}
