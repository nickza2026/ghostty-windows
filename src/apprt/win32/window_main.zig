//! Phase 3A entrypoint only. No Ghostty CoreSurface, GPU, or subprocess is created.
const std = @import("std");
const window = @import("window.zig");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    _ = args.next();
    var smoke = false;
    var profile_size = false;
    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--smoke-test")) {
            smoke = true;
        } else if (std.mem.eql(u8, arg, "--profile-size-probe")) {
            profile_size = true;
        } else return error.UnknownArgument;
    }
    if (args.next() != null) return error.UnexpectedArgument;
    try window.runWithHooks(smoke, .{
        .profile_1080p = profile_size,
        .no_activate = profile_size,
        .auto_close_ms = if (profile_size) 1000 else null,
    });
}
