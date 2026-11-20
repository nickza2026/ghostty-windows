//! Storage-removal policy only: no filesystem access, process or VM control.
const std = @import("std");

pub const Header = extern struct { size: u32, device_type: u32, reserved: u32 = 0 };
pub const Volume = extern struct {
    header: Header = .{ .size = @sizeOf(Volume), .device_type = 2 },
    unit_mask: u32,
    flags: u16 = 0,
};

pub const Guard = struct {
    drive_mask: u32,

    /// Launch validation already refuses UNC/device paths and reparse ancestors.
    /// Do not derive this from cwd, an environment variable, or removable-drive
    /// classification: USB enclosures can report DRIVE_FIXED.
    pub fn fromRoot(root: []const u8) ?Guard {
        if (root.len < 3 or !std.ascii.isAlphabetic(root[0]) or root[1] != ':' or root[2] != '\\') return null;
        const index: u5 = @intCast(std.ascii.toUpper(root[0]) - 'A');
        return .{ .drive_mask = @as(u32, 1) << index };
    }

    pub fn volumeHeader(event: usize, header: Header) bool {
        // DBT_DEVICEREMOVECOMPLETE + DBT_DEVTYP_VOLUME only. Query-remove is
        // merely a request, not proof that storage has disappeared.
        return event == 0x8004 and header.device_type == 2 and header.size >= @sizeOf(Volume);
    }

    pub fn removed(self: Guard, event: usize, volume: Volume) bool {
        return volumeHeader(event, volume.header) and volume.flags & 2 == 0 and // !DBTF_NET
            volume.unit_mask & self.drive_mask != 0;
    }

    pub fn absent(self: Guard, logical_drives: u32) bool {
        // GetLogicalDrives returns zero on failure; unknown is not removal.
        // No Data-directory/file/SSH error is considered here.
        return logical_drives != 0 and logical_drives & self.drive_mask == 0;
    }
};

test "package drive comes from validated root, not a fixed USB drive letter" {
    try std.testing.expectEqual(@as(u32, 1), Guard.fromRoot("A:\\sandbox").?.drive_mask);
    try std.testing.expectEqual(@as(u32, 1) << 25, Guard.fromRoot("z:\\ไทย space's").?.drive_mask);
    for ([_][]const u8{ "", "A:", "A:relative", "A:/sandbox", "\\\\server\\share", "\\\\?\\A:\\sandbox", "1:\\sandbox" }) |root|
        try std.testing.expect(Guard.fromRoot(root) == null);
}

test "only completed removal of the package volume closes a session" {
    const guard = Guard.fromRoot("D:\\sandbox").?;
    const own = Volume{ .unit_mask = 1 << 3 };
    try std.testing.expect(guard.removed(0x8004, own));
    try std.testing.expect(guard.removed(0x8004, .{ .unit_mask = (1 << 3) | (1 << 7) }));
    try std.testing.expect(!guard.removed(0x8004, .{ .unit_mask = 1 << 7 }));
    try std.testing.expect(!guard.removed(0x8004, .{ .unit_mask = 0 }));
    try std.testing.expect(!guard.removed(0x8004, .{ .unit_mask = 1 << 3, .flags = 2 }));
    for ([_]usize{ 0x8000, 0x8001, 0x8002, 0x8003, 7, 0 }) |event|
        try std.testing.expect(!guard.removed(event, own));
}

test "truncated and wrong-type volume headers cannot authorize closing" {
    const guard = Guard.fromRoot("D:\\sandbox").?;
    for ([_]u32{ 0, @sizeOf(Header), @sizeOf(Volume) - 1 }) |size|
        try std.testing.expect(!guard.removed(0x8004, .{ .header = .{ .size = size, .device_type = 2 }, .unit_mask = 1 << 3 }));
    try std.testing.expect(!guard.removed(0x8004, .{ .header = .{ .size = @sizeOf(Volume), .device_type = 5 }, .unit_mask = 1 << 3 }));
}

test "fallback needs a known drive map with the package drive absent" {
    const guard = Guard.fromRoot("D:\\sandbox").?;
    try std.testing.expect(!guard.absent(0));
    try std.testing.expect(!guard.absent((1 << 2) | (1 << 3)));
    try std.testing.expect(guard.absent(1 << 2));
}
