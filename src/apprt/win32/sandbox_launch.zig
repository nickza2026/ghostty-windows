//! Pre-spawn contract only. Caller supplies the actual native executable path.
//! Validation is a snapshot, not a race-proof substitute for secure spawning.
const std = @import("std");
const environment = @import("sandbox_environment.zig");
extern "kernel32" fn GetFileAttributesW([*:0]const u16) callconv(.winapi) u32;

pub const Plan = struct {
    allocator: std.mem.Allocator,
    root: []u8,
    node: []u8,
    entry: []u8,
    native_storage: []u8,
    env: std.process.Environ.Map,

    pub fn deinit(self: *Plan) void {
        self.env.deinit();
        inline for (.{ "root", "node", "entry", "native_storage" }) |field| self.allocator.free(@field(self, field));
        self.* = undefined;
    }
    pub fn argv(self: *const Plan) [4][]const u8 {
        return .{ self.node, self.entry, "terminal", self.root };
    }
    pub fn cwd(self: *const Plan) []const u8 {
        return self.root;
    }
};

fn validPath(path: []const u8) bool {
    // Deliberately refuse device/UNC namespaces rather than silently normalizing.
    if (path.len < 4 or !std.ascii.isAlphabetic(path[0]) or path[1] != ':' or path[2] != '\\') return false;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return false;
    var parts = std.mem.tokenizeAny(u8, path[3..], "\\/");
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..") or std.mem.indexOfScalar(u8, part, ':') != null) return false;
    }
    return true;
}

// Check every ancestor, including package ancestors, without opening any Data.
pub fn realPath(a: std.mem.Allocator, path: []const u8, directory: bool) !void {
    if (!validPath(path)) return error.InvalidExecutablePath;
    var end: usize = 3;
    while (true) {
        const wide = try std.unicode.wtf8ToWtf16LeAllocZ(a, path[0..end]);
        defer a.free(wide);
        const attrs = GetFileAttributesW(wide);
        if (attrs == 0xffffffff) return error.MissingDependency;
        if (attrs & 0x400 != 0) return error.ReparsePoint;
        if ((attrs & 0x10 != 0) != (end < path.len or directory)) return error.InvalidDependency;
        if (end == path.len) break;
        end += 1;
        while (end < path.len and path[end] != '\\' and path[end] != '/') : (end += 1) {}
    }
}

fn validateMarker(a: std.mem.Allocator, bytes: []const u8) !void {
    const parsed = std.json.parseFromSlice(std.json.Value, a, bytes, .{}) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return error.InvalidOwnership,
    };
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidOwnership;
    const obj = parsed.value.object;
    const name = obj.get("name") orelse return error.InvalidOwnership;
    const schema = obj.get("schema") orelse return error.InvalidOwnership;
    const nonce = obj.get("nonce") orelse return error.InvalidOwnership;
    if (name != .string or !std.mem.eql(u8, name.string, "ghostty-sandbox-owned")) return error.InvalidOwnership;
    const schema_ok = switch (schema) {
        .integer => |v| v == 1,
        .float => |v| v == 1,
        else => false,
    };
    if (!schema_ok or nonce != .string) return error.InvalidOwnership;
    // JavaScript String.length counts UTF-16 code units, not UTF-8 bytes.
    var it = (try std.unicode.Utf8View.init(nonce.string)).iterator();
    var units: usize = 0;
    while (it.nextCodepoint()) |cp| units += if (cp > 0xffff) @as(usize, 2) else 1;
    if (units < 16) return error.InvalidOwnership;
}

pub fn init(a: std.mem.Allocator, io: std.Io, actual_executable: []const u8, metadata: environment.SystemMetadata) !Plan {
    if (!validPath(actual_executable)) return error.InvalidExecutablePath;
    try realPath(a, actual_executable, false);
    const root = try a.dupe(u8, std.fs.path.dirname(actual_executable) orelse return error.InvalidExecutablePath);
    errdefer a.free(root);
    const marker = try std.fs.path.join(a, &.{ root, "sandbox-owned.json" });
    defer a.free(marker);
    try realPath(a, marker, false);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, marker, a, .limited(1024 * 1024));
    defer a.free(bytes);
    try validateMarker(a, bytes);
    const node = try std.fs.path.join(a, &.{ root, "Runtime", "node", "node.exe" });
    errdefer a.free(node);
    try realPath(a, node, false);
    const entry = try std.fs.path.join(a, &.{ root, "App", "entry.cjs" });
    errdefer a.free(entry);
    try realPath(a, entry, false);
    const native_storage = try std.fs.path.join(a, &.{ root, "Data", "native" });
    errdefer a.free(native_storage);
    return .{ .allocator = a, .root = root, .node = node, .entry = entry, .native_storage = native_storage, .env = try environment.init(a, root, metadata) };
}

const owner = "{\"name\":\"ghostty-sandbox-owned\",\"schema\":1,\"nonce\":\"1234567890123456\"}";
const system: environment.SystemMetadata = .{ .system_root = "C:\\Windows", .program_data = "C:\\ProgramData" };

test "ownership malformed and JS UTF16 nonce semantics" {
    const a = std.testing.allocator;
    for ([_][]const u8{ "{}", "[]", "bad", "{\"name\":\"ghostty-sandbox-owned\",\"schema\":\"1\",\"nonce\":\"1234567890123456\"}" }) |bad| try std.testing.expectError(error.InvalidOwnership, validateMarker(a, bad));
    try validateMarker(a, owner);
    try validateMarker(a, "{\"name\":\"ghostty-sandbox-owned\",\"schema\":1.0,\"nonce\":\"😀😀😀😀😀😀😀😀\",\"extra\":true}");
    try std.testing.expectError(error.InvalidOwnership, validateMarker(a, "{\"name\":\"ghostty-sandbox-owned\",\"schema\":1,\"nonce\":\"กกกกกกกก\"}"));
}

fn probe(a: std.mem.Allocator, exe: []const u8) !void {
    var plan = try init(a, std.testing.io, exe, system);
    defer plan.deinit();
}

test "synthetic relocated package direct argv missing dependencies and allocation cleanup" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "ไทย space's/Runtime/node");
    try tmp.dir.createDirPath(io, "ไทย space's/App");
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const base = buf[0..try tmp.dir.realPath(io, &buf)];
    const exe = try std.fs.path.join(a, &.{ base, "ไทย space's", "Sandbox.exe" });
    defer a.free(exe);
    for ([_][]const u8{ "Sandbox.exe", "Runtime/node/node.exe", "App/entry.cjs", "sandbox-owned.json" }) |name| {
        const rel = try std.fs.path.join(a, &.{ "ไทย space's", name });
        defer a.free(rel);
        const f = try tmp.dir.createFile(io, rel, .{});
        defer f.close(io);
        if (std.mem.eql(u8, name, "sandbox-owned.json")) try f.writeStreamingAll(io, owner);
    }
    var plan = try init(a, io, exe, system);
    defer plan.deinit();
    try std.testing.expectEqualStrings("terminal", plan.argv()[2]);
    try std.testing.expectEqualStrings(plan.cwd(), plan.argv()[3]);
    try std.testing.expectEqualStrings(plan.root, std.fs.path.dirname(exe).?);
    try std.testing.checkAllAllocationFailures(a, probe, .{exe});
    try tmp.dir.deleteFile(io, "ไทย space's/App/entry.cjs");
    try std.testing.expectError(error.MissingDependency, init(a, io, exe, system));
    try std.testing.expectError(error.InvalidExecutablePath, init(a, io, "Sandbox.exe", system));
}

test "reparse ancestor refused when unprivileged symlinks are supported" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "target", .default_dir);
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const base = buf[0..try tmp.dir.realPath(io, &buf)];
    const target = try std.fs.path.join(a, &.{ base, "target" });
    defer a.free(target);
    tmp.dir.symLink(io, target, "link", .{ .is_directory = true }) catch |err| switch (err) {
        error.AccessDenied, error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    const linked = try std.fs.path.join(a, &.{ base, "link", "absent.exe" });
    defer a.free(linked);
    try std.testing.expectError(error.ReparsePoint, realPath(a, linked, false));
}
