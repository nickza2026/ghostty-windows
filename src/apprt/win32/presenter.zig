//! Opaque CPU presentation. GL readback is bottom-up RGBA; a top-down DIB is
//! BGRA. No GL operation is performed by this module or by WM_PAINT.
const std = @import("std");
const w = std.os.windows;

const Header = extern struct {
    size: u32 = @sizeOf(Header),
    width: i32,
    height: i32,
    planes: u16 = 1,
    bit_count: u16 = 32,
    compression: u32 = 0, // BI_RGB: opaque window, alpha byte is not composited.
    image_size: u32 = 0,
    x_pixels_per_meter: i32 = 0,
    y_pixels_per_meter: i32 = 0,
    colors_used: u32 = 0,
    colors_important: u32 = 0,
};
const Info = extern struct { header: Header, unused_color: u32 = 0 };
extern "gdi32" fn StretchDIBits(w.HDC, i32, i32, i32, i32, i32, i32, i32, i32, *const anyopaque, *const Info, u32, u32) callconv(.winapi) i32;

pub const Image = struct {
    alloc: std.mem.Allocator,
    width: u32,
    height: u32,
    pixels: []u8,

    pub fn fromRGBA(alloc: std.mem.Allocator, width: u32, height: u32, rgba: []const u8) !Image {
        if (width == 0 or height == 0 or width > std.math.maxInt(i32) or height > std.math.maxInt(i32)) return error.InvalidImageSize;
        const stride = try std.math.mul(usize, width, 4);
        const length = try std.math.mul(usize, stride, height);
        if (rgba.len != length) return error.InvalidFrameLength;
        const pixels = try alloc.alloc(u8, length);
        for (0..height) |y| {
            const src_row = (height - 1 - y) * stride;
            const dst_row = y * stride;
            for (0..width) |x| {
                const src = src_row + x * 4;
                const dst = dst_row + x * 4;
                pixels[dst..][0..4].* = .{ rgba[src + 2], rgba[src + 1], rgba[src], 255 };
            }
        }
        return .{ .alloc = alloc, .width = width, .height = height, .pixels = pixels };
    }

    pub fn deinit(self: *Image) void {
        self.alloc.free(self.pixels);
        self.* = undefined;
    }

    pub fn paint(self: *const Image, dc: w.HDC, client_width: i32, client_height: i32) !void {
        if (client_width <= 0 or client_height <= 0) return;
        const info: Info = .{ .header = .{ .width = @intCast(self.width), .height = -@as(i32, @intCast(self.height)) } };
        const lines = StretchDIBits(dc, 0, 0, client_width, client_height, 0, 0, @intCast(self.width), @intCast(self.height), self.pixels.ptr, &info, 0, 0x00cc0020);
        if (lines == 0 or lines == -1) return error.DibPaintFailed;
    }

    fn bmpHeader(self: *const Image) ![54]u8 {
        const length = std.math.cast(u32, self.pixels.len) orelse return error.ImageTooLarge;
        var header: [54]u8 = @splat(0);
        header[0..2].* = .{ 'B', 'M' };
        std.mem.writeInt(u32, header[2..][0..4], try std.math.add(u32, length, 54), .little);
        std.mem.writeInt(u32, header[10..][0..4], 54, .little);
        std.mem.writeInt(u32, header[14..][0..4], 40, .little);
        std.mem.writeInt(i32, header[18..][0..4], @intCast(self.width), .little);
        std.mem.writeInt(i32, header[22..][0..4], -@as(i32, @intCast(self.height)), .little);
        std.mem.writeInt(u16, header[26..][0..2], 1, .little);
        std.mem.writeInt(u16, header[28..][0..2], 32, .little);
        std.mem.writeInt(u32, header[34..][0..4], length, .little);
        return header;
    }

    pub fn writeBmp(self: *const Image, io: std.Io, path: []const u8) !void {
        const header = try self.bmpHeader();
        const file = try std.Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        var writer = file.writer(io, &.{});
        try writer.interface.writeAll(&header);
        try writer.interface.writeAll(self.pixels);
        try writer.interface.flush();
    }
};

test "DIB BMP header uses negative height for top-down opaque pixels" {
    var image = try Image.fromRGBA(std.testing.allocator, 1, 1, &.{ 1, 2, 3, 255 });
    defer image.deinit();
    const header = try image.bmpHeader();
    try std.testing.expectEqual(@as(u32, 58), std.mem.readInt(u32, header[2..][0..4], .little));
    try std.testing.expectEqual(@as(i32, -1), std.mem.readInt(i32, header[22..][0..4], .little));
    try std.testing.expectEqual(@as(u16, 32), std.mem.readInt(u16, header[28..][0..2], .little));
}

test "DIB channel swizzle and bottom-up to top-down rows" {
    // GL order: bottom-left red, bottom-right green, top-left blue, top-right white.
    const rgba = [_]u8{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 };
    var image = try Image.fromRGBA(std.testing.allocator, 2, 2, &rgba);
    defer image.deinit();
    const expected = [_]u8{ 255, 0, 0, 255, 255, 255, 255, 255, 0, 0, 255, 255, 0, 255, 0, 255 };
    try std.testing.expectEqualSlices(u8, &expected, image.pixels);
}

test "DIB rejects invalid dimensions and frame lengths before allocation" {
    try std.testing.expectError(error.InvalidImageSize, Image.fromRGBA(std.testing.allocator, 0, 1, &.{}));
    try std.testing.expectError(error.InvalidImageSize, Image.fromRGBA(std.testing.allocator, std.math.maxInt(u32), 1, &.{}));
    try std.testing.expectError(error.InvalidFrameLength, Image.fromRGBA(std.testing.allocator, 2, 2, &.{}));
}

test "DIB allocation failure has no owned buffer leak" {
    const Case = struct {
        fn run(alloc: std.mem.Allocator) !void {
            var image = try Image.fromRGBA(alloc, 1, 1, &.{ 1, 2, 3, 255 });
            defer image.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Case.run, .{});
}
