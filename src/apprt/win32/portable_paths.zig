//! App-owned portable paths. The marker follows the executable, never cwd/HOME.
//! Does NOT redirect child tools' accounts, shell history or OS/driver caches.
const std = @import("std");
pub const Kind = enum { config, data, cache, logs, tmp };

pub fn selected(alloc: std.mem.Allocator, io: std.Io, exe_dir: []const u8) !bool {
    if (!std.fs.path.isAbsolute(exe_dir)) return error.RelativeExecutableDirectory;
    const marker = try std.fs.path.join(alloc, &.{ exe_dir, "portable-data" });
    defer alloc.free(marker);
    const stat = std.Io.Dir.cwd().statFile(io, marker, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    if (stat.kind != .directory) return error.InvalidPortableDataDirectory;
    return true;
}

pub const Layout = struct {
    alloc: std.mem.Allocator,
    exe_dir: []u8,
    root: []u8,
    sandbox: bool = false,

    /// Explicit flavor only, never selected by an ownership marker's presence.
    /// Caller has already validated ownership/dependencies using sandbox_launch.
    pub fn initSandbox(alloc: std.mem.Allocator, io: std.Io, package_root: []const u8) !Layout {
        const check = @import("sandbox_launch.zig").realPath;
        try check(alloc, package_root, true);
        const exe = try alloc.dupe(u8, package_root);
        errdefer alloc.free(exe);
        var package = try std.Io.Dir.openDirAbsolute(io, package_root, .{ .follow_symlinks = false });
        defer package.close(io);
        package.createDir(io, "Data", .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const data_path = try std.fs.path.join(alloc, &.{ package_root, "Data" });
        defer alloc.free(data_path);
        try check(alloc, data_path, true);
        var data = try package.openDir(io, "Data", .{ .follow_symlinks = false });
        defer data.close(io);
        data.createDir(io, "native", .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const root = try std.fs.path.join(alloc, &.{ data_path, "native" });
        errdefer alloc.free(root);
        try check(alloc, root, true);
        var native = try data.openDir(io, "native", .{ .follow_symlinks = false });
        defer native.close(io);
        inline for (std.meta.fields(Kind)) |field| {
            native.createDir(io, field.name, .default_dir) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
        }
        var layout: Layout = .{ .alloc = alloc, .exe_dir = exe, .root = root, .sandbox = true };
        try layout.verify(io);
        try layout.checkWritable(io);
        return layout;
    }

    pub fn init(alloc: std.mem.Allocator, io: std.Io, exe_dir: []const u8) !?Layout {
        if (!try selected(alloc, io, exe_dir)) return null;
        const exe = try alloc.dupe(u8, exe_dir);
        errdefer alloc.free(exe);
        const root = try std.fs.path.join(alloc, &.{ exe_dir, "portable-data" });
        errdefer alloc.free(root);
        var directory = try std.Io.Dir.openDirAbsolute(io, root, .{ .follow_symlinks = false });
        defer directory.close(io);
        inline for (std.meta.fields(Kind)) |field| {
            directory.createDir(io, field.name, .default_dir) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
            const stat = try directory.statFile(io, field.name, .{ .follow_symlinks = false });
            if (stat.kind != .directory) return error.InvalidPortableDataDirectory;
            var child = try directory.openDir(io, field.name, .{ .follow_symlinks = false });
            child.close(io);
        }
        const layout: Layout = .{ .alloc = alloc, .exe_dir = exe, .root = root };
        try layout.checkWritable(io);
        return layout;
    }
    pub fn deinit(self: *Layout) void {
        self.alloc.free(self.exe_dir);
        self.alloc.free(self.root);
        self.* = undefined;
    }
    /// Revalidate selected storage. A removed marker must never reselect host.
    pub fn verify(self: *const Layout, io: std.Io) !void {
        if (self.sandbox) {
            try @import("sandbox_launch.zig").realPath(self.alloc, self.root, true);
        } else if (!try selected(self.alloc, io, self.exe_dir)) return error.PortableDataMissing;
        var directory = try std.Io.Dir.openDirAbsolute(io, self.root, .{ .follow_symlinks = false });
        defer directory.close(io);
        inline for (std.meta.fields(Kind)) |field| {
            if (self.sandbox) {
                const child_path = try std.fs.path.join(self.alloc, &.{ self.root, field.name });
                defer self.alloc.free(child_path);
                try @import("sandbox_launch.zig").realPath(self.alloc, child_path, true);
            }
            const stat = try directory.statFile(io, field.name, .{ .follow_symlinks = false });
            if (stat.kind != .directory) return error.InvalidPortableDataDirectory;
            var child = try directory.openDir(io, field.name, .{ .follow_symlinks = false });
            child.close(io);
        }
    }
    pub fn path(self: *const Layout, alloc: std.mem.Allocator, kind: Kind) ![]u8 {
        return std.fs.path.join(alloc, &.{ self.root, @tagName(kind) });
    }
    pub fn configFile(self: *const Layout, alloc: std.mem.Allocator) ![]u8 {
        return std.fs.path.join(alloc, &.{ self.root, "config", "config.ghostty" });
    }
    /// Actual exclusive write+delete probes, not Windows' unreliable readonly
    /// directory attribute. Never change ACLs or spill into host storage.
    pub fn checkWritable(self: *const Layout, io: std.Io) !void {
        var root = try std.Io.Dir.openDirAbsolute(io, self.root, .{ .follow_symlinks = false });
        defer root.close(io);
        inline for (std.meta.fields(Kind)) |field| {
            var dir = try root.openDir(io, field.name, .{ .follow_symlinks = false });
            defer dir.close(io);
            var nonce: [16]u8 = undefined;
            io.random(&nonce);
            var buffer: [64]u8 = undefined;
            const name = try std.fmt.bufPrint(&buffer, ".portable-probe-{s}", .{std.fmt.bytesToHex(nonce, .lower)});
            const file = try dir.createFile(io, name, .{ .exclusive = true });
            file.writeStreamingAll(io, "localterm portable write probe\n") catch |err| {
                file.close(io);
                dir.deleteFile(io, name) catch {};
                return err;
            };
            file.close(io);
            try dir.deleteFile(io, name);
        }
    }
    /// Only a flat package or the existing bin/ + share/ package. Never climb
    /// arbitrary ancestors or honor an inherited host resource directory.
    pub fn resources(self: *const Layout, alloc: std.mem.Allocator, io: std.Io) ![]u8 {
        if (self.sandbox) {
            const check = @import("sandbox_launch.zig").realPath;
            const ghostty = try std.fs.path.join(alloc, &.{ self.exe_dir, "share", "ghostty" });
            errdefer alloc.free(ghostty);
            try check(alloc, ghostty, true);
            const terminfo = try std.fs.path.join(alloc, &.{ self.exe_dir, "share", "terminfo", "ghostty.terminfo" });
            defer alloc.free(terminfo);
            try check(alloc, terminfo, false);
            return ghostty;
        }
        if (try resourceCandidate(alloc, io, self.exe_dir)) |path_| return path_;
        if (std.ascii.eqlIgnoreCase(std.fs.path.basename(self.exe_dir), "bin")) {
            if (std.fs.path.dirname(self.exe_dir)) |parent| {
                if (try resourceCandidate(alloc, io, parent)) |path_| return path_;
            }
        }
        return error.PortableResourcesMissing;
    }
};

fn resourceCandidate(alloc: std.mem.Allocator, io: std.Io, base: []const u8) !?[]u8 {
    var directory = try std.Io.Dir.openDirAbsolute(io, base, .{ .follow_symlinks = false });
    defer directory.close(io);
    var share = directory.openDir(io, "share", .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer share.close(io);
    var ghostty = share.openDir(io, "ghostty", .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer ghostty.close(io);
    var terminfo = share.openDir(io, "terminfo", .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer terminfo.close(io);
    const stat = terminfo.statFile(io, "ghostty.terminfo", .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    if (stat.kind != .file) return error.InvalidPortableResources;
    return try std.fs.path.join(alloc, &.{ base, "share", "ghostty" });
}

test "portable resources missing never discover unrelated ancestors" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "share/ghostty");
    try tmp.dir.createDirPath(io, "share/terminfo");
    const sentinel = try tmp.dir.createFile(io, "share/terminfo/ghostty.terminfo", .{});
    sentinel.close(io);
    try tmp.dir.createDirPath(io, "nested/candidate/portable-data");
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const parent = buffer[0..try tmp.dir.realPath(io, &buffer)];
    const exe = try std.fs.path.join(a, &.{ parent, "nested", "candidate" });
    defer a.free(exe);
    var layout = (try Layout.init(a, io, exe)).?;
    defer layout.deinit();
    try std.testing.expectError(error.PortableResourcesMissing, layout.resources(a, io));
    try tmp.dir.createDirPath(io, "nested/candidate/share/ghostty");
    try tmp.dir.createDirPath(io, "nested/candidate/share/terminfo");
    const local = try tmp.dir.createFile(io, "nested/candidate/share/terminfo/ghostty.terminfo", .{});
    local.close(io);
    const resources_ = try layout.resources(a, io);
    defer a.free(resources_);
    try std.testing.expect(std.mem.startsWith(u8, resources_, exe));
}

test "explicit sandbox storage is Data native and ordinary selection remains absent" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buf[0..try tmp.dir.realPath(io, &buf)];
    var layout = try Layout.initSandbox(a, io, root);
    defer layout.deinit();
    const expected = try std.fs.path.join(a, &.{ root, "Data", "native" });
    defer a.free(expected);
    try std.testing.expectEqualStrings(expected, layout.root);
    try std.testing.expect((try Layout.init(a, io, root)) == null);
    try layout.verify(io);
    try tmp.dir.deleteDir(io, "Data/native/tmp");
    try std.testing.expectError(error.MissingDependency, layout.verify(io));
}

test "portable layout explicit executable roots remain independent" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "terminal ไทย A", .default_dir);
    try tmp.dir.createDir(io, "terminal B", .default_dir);
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const base = buf[0..try tmp.dir.realPath(io, &buf)];
    inline for (.{ "terminal ไทย A", "terminal B" }) |name| {
        const exe = try std.fs.path.join(a, &.{ base, name });
        defer a.free(exe);
        try std.testing.expect((try Layout.init(a, io, exe)) == null);
        var dir = try tmp.dir.openDir(io, name, .{});
        defer dir.close(io);
        try dir.createDir(io, "portable-data", .default_dir);
        var layout = (try Layout.init(a, io, exe)).?;
        defer layout.deinit();
        try layout.verify(io);
        const config = try layout.configFile(a);
        defer a.free(config);
        try std.testing.expect(std.mem.startsWith(u8, config, exe));
        const cache = try layout.path(a, .cache);
        defer a.free(cache);
        try std.testing.expect(std.mem.startsWith(u8, cache, exe));
    }
}

test "portable layout rejects relative root and invalid marker or child" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    try std.testing.expectError(error.RelativeExecutableDirectory, Layout.init(a, io, "relative"));
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const exe = buf[0..try tmp.dir.realPath(io, &buf)];
    const marker = try tmp.dir.createFile(io, "portable-data", .{});
    marker.close(io);
    try std.testing.expectError(error.InvalidPortableDataDirectory, Layout.init(a, io, exe));
    try tmp.dir.deleteFile(io, "portable-data");
    try tmp.dir.createDir(io, "portable-data", .default_dir);
    var data = try tmp.dir.openDir(io, "portable-data", .{});
    defer data.close(io);
    const bad = try data.createFile(io, "cache", .{});
    bad.close(io);
    try std.testing.expectError(error.InvalidPortableDataDirectory, Layout.init(a, io, exe));
}

test "portable layout selected storage loss is fail closed" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "portable-data", .default_dir);
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const exe = buf[0..try tmp.dir.realPath(io, &buf)];
    var layout = (try Layout.init(a, io, exe)).?;
    defer layout.deinit();
    try tmp.dir.rename("portable-data", tmp.dir, "removed-data", io);
    try std.testing.expectError(error.PortableDataMissing, layout.verify(io));
}

test "portable startup write denial and no space propagate without fallback" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "portable-data", .default_dir);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const exe = buffer[0..try tmp.dir.realPath(io, &buffer)];
    inline for (.{ error.AccessDenied, error.NoSpaceLeft }) |failure| {
        const Fault = struct {
            fn create(_: ?*anyopaque, _: std.Io.Dir, _: []const u8, _: std.Io.Dir.CreateFileOptions) std.Io.File.OpenError!std.Io.File {
                return failure;
            }
        };
        var vtable = io.vtable.*;
        vtable.dirCreateFile = Fault.create;
        const failing_io: std.Io = .{ .userdata = io.userdata, .vtable = &vtable };
        try std.testing.expectError(failure, Layout.init(a, failing_io, exe));
    }
    // No ACL/volume manipulation: faults above exercise the production startup
    // path but do not substitute for a real read-only/full-volume acceptance.
    var recovered = (try Layout.init(a, io, exe)).?;
    defer recovered.deinit();
    try recovered.verify(io);
}
