//! Synthetic image-to-file pipeline tests. Never calls Windows clipboard APIs.
const std = @import("std");
const images = @import("clipboard_image.zig");
const paths = @import("clipboard_paths.zig");
const files = @import("clipboard_files.zig");

test "clipboard portable PNG pipeline Unicode path readback and cleanup" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDir(io, "โปรแกรม ทดสอบ", .default_dir);
    var exe = try temp.dir.openDir(io, "โปรแกรม ทดสอบ", .{});
    defer exe.close(io);
    try exe.createDir(io, "portable-data", .default_dir);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const exe_dir = buffer[0..try exe.realPath(io, &buffer)];
    const selected = try paths.portableSelected(a, io, exe_dir);
    const root = try paths.resolveSelected(a, io, exe_dir, "C:\\must-not-write-host", selected);
    defer a.free(root.path);
    try std.testing.expect(root.portable);
    try std.testing.expect(std.mem.startsWith(u8, root.path, exe_dir));
    var dib: [48]u8 = @splat(0);
    std.mem.writeInt(u32, dib[0..4], 40, .little);
    std.mem.writeInt(i32, dib[4..8], 2, .little);
    std.mem.writeInt(i32, dib[8..12], -1, .little);
    std.mem.writeInt(u16, dib[12..14], 1, .little);
    std.mem.writeInt(u16, dib[14..16], 24, .little);
    @memcpy(dib[40..46], &[_]u8{ 0, 0, 255, 0, 255, 0 });
    const png = try images.fromDib(a, &dib);
    defer a.free(png);
    try images.validatePng(png);
    var store: files.Store = .{};
    defer store.deinit(a, io);
    const quoted = try store.save(a, io, root.path, png);
    try std.testing.expect(quoted[0] == '\'');
    try std.testing.expect(std.mem.endsWith(u8, quoted, "' "));
    try std.testing.expect(std.mem.indexOfAny(u8, quoted, "\r\n\x1b") == null);
    const owned = try a.dupe(u8, store.items.items[0].path);
    defer a.free(owned);
    {
        const file = try std.Io.Dir.openFileAbsolute(io, owned, .{});
        defer file.close(io);
        const readback = try a.alloc(u8, png.len);
        defer a.free(readback);
        try std.testing.expectEqual(png.len, try file.readPositionalAll(io, readback, 0));
        try std.testing.expectEqualSlices(u8, png, readback);
        try images.validatePng(readback);
    }
    store.rollback(a, io);
    try std.testing.expectEqual(@as(usize, 0), store.bytes);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.openFileAbsolute(io, owned, .{}));
}

test "clipboard portable unusable cache does not select host directory" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDir(io, "portable-data", .default_dir);
    var data = try temp.dir.openDir(io, "portable-data", .{});
    defer data.close(io);
    const blocker = try data.createFile(io, "cache", .{});
    blocker.close(io);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const exe_dir = buffer[0..try temp.dir.realPath(io, &buffer)];
    try std.testing.expectError(error.InvalidPortableDataDirectory, paths.resolveSelected(a, io, exe_dir, "C:\\must-not-use-host", true));
}

test "clipboard image session quota bounds files and preserves unrelated file" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const unrelated = try temp.dir.createFile(io, "keep.txt", .{});
    unrelated.close(io);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buffer[0..try temp.dir.realPath(io, &buffer)];
    var store: files.Store = .{};
    defer store.deinit(a, io);
    for (0..files.max_files) |_| _ = try store.save(a, io, root, "synthetic fixture");
    try std.testing.expectError(error.ImagePasteLimit, store.save(a, io, root, "one too many"));
    store.deinit(a, io);
    const kept = try temp.dir.openFile(io, "keep.txt", .{});
    kept.close(io);
}
