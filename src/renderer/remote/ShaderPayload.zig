//! Explicit CPU GLSL-data serialization, excluding native alignment/padding.
//! Data decoding is not a draw command or GPU/resource-liveness validation.
const std = @import("std");
const data = @import("../GlslData.zig");

pub const uniforms_bytes = 124;
pub const cell_bytes = 30;
pub const image_bytes = 40;
pub const background_bytes = 5;

const Writer = struct {
    bytes: []u8,
    at: usize = 0,
    fn integer(self: *Writer, comptime T: type, value: T) !void {
        const n = @sizeOf(T);
        if (n > self.bytes.len - self.at) return error.OutputTooSmall;
        std.mem.writeInt(T, self.bytes[self.at..][0..n], value, .little);
        self.at += n;
    }
    fn float(self: *Writer, value: f32) !void {
        if (!std.math.isFinite(value)) return error.NonFiniteValue;
        try self.integer(u32, @bitCast(value));
    }
    fn finish(self: Writer, expected: usize) ![]const u8 {
        if (self.at != expected) return error.LayoutMismatch;
        return self.bytes[0..self.at];
    }
};
const Reader = struct {
    bytes: []const u8,
    at: usize = 0,
    fn integer(self: *Reader, comptime T: type) !T {
        const n = @sizeOf(T);
        if (n > self.bytes.len - self.at) return error.InvalidLength;
        const result = std.mem.readInt(T, self.bytes[self.at..][0..n], .little);
        self.at += n;
        return result;
    }
    fn float(self: *Reader) !f32 {
        const result: f32 = @bitCast(try self.integer(u32));
        if (!std.math.isFinite(result)) return error.NonFiniteValue;
        return result;
    }
};

pub fn encodeUniforms(dst: []u8, value: data.Uniforms) ![]const u8 {
    if (dst.len < uniforms_bytes) return error.OutputTooSmall;
    var writer: Writer = .{ .bytes = dst };
    for (value.projection_matrix) |column| {
        inline for (0..4) |row| try writer.float(column[row]);
    }
    for (value.screen_size) |v| try writer.float(v);
    for (value.cell_size) |v| try writer.float(v);
    for (value.grid_size) |v| try writer.integer(u16, v);
    for (value.grid_padding) |v| try writer.float(v);
    const padding: u32 = @bitCast(value.padding_extend);
    const flags: u32 = @bitCast(value.bools);
    if (padding & ~@as(u32, 15) != 0 or flags & ~@as(u32, 15) != 0) return error.InvalidFlags;
    try writer.integer(u32, padding);
    try writer.float(value.min_contrast);
    for (value.cursor_pos) |v| try writer.integer(u16, v);
    for (value.cursor_color) |v| try writer.integer(u8, v);
    for (value.bg_color) |v| try writer.integer(u8, v);
    try writer.integer(u32, flags);
    return writer.finish(uniforms_bytes);
}
pub fn decodeUniforms(src: []const u8) !data.Uniforms {
    if (src.len != uniforms_bytes) return error.InvalidLength;
    var reader: Reader = .{ .bytes = src };
    var value = std.mem.zeroes(data.Uniforms);
    for (&value.projection_matrix) |*column| {
        inline for (0..4) |row| column.*[row] = try reader.float();
    }
    for (&value.screen_size) |*v| v.* = try reader.float();
    for (&value.cell_size) |*v| v.* = try reader.float();
    for (&value.grid_size) |*v| v.* = try reader.integer(u16);
    for (&value.grid_padding) |*v| v.* = try reader.float();
    const padding = try reader.integer(u32);
    if (padding & ~@as(u32, 15) != 0) return error.InvalidFlags;
    value.padding_extend = @bitCast(padding);
    value.min_contrast = try reader.float();
    for (&value.cursor_pos) |*v| v.* = try reader.integer(u16);
    for (&value.cursor_color) |*v| v.* = try reader.integer(u8);
    for (&value.bg_color) |*v| v.* = try reader.integer(u8);
    const flags = try reader.integer(u32);
    if (flags & ~@as(u32, 15) != 0) return error.InvalidFlags;
    value.bools = @bitCast(flags);
    return value;
}

pub fn encodeCell(dst: []u8, value: data.CellText) ![]const u8 {
    if (dst.len < cell_bytes) return error.OutputTooSmall;
    var writer: Writer = .{ .bytes = dst };
    for (value.glyph_pos) |v| try writer.integer(u32, v);
    for (value.glyph_size) |v| try writer.integer(u32, v);
    for (value.bearings) |v| try writer.integer(i16, v);
    for (value.grid_pos) |v| try writer.integer(u16, v);
    for (value.color) |v| try writer.integer(u8, v);
    try writer.integer(u8, @intFromEnum(value.atlas));
    const flags: u8 = @bitCast(value.bools);
    if (flags & ~@as(u8, 3) != 0) return error.InvalidFlags;
    try writer.integer(u8, flags);
    return writer.finish(cell_bytes);
}
pub fn decodeCell(src: []const u8) !data.CellText {
    if (src.len != cell_bytes) return error.InvalidLength;
    var reader: Reader = .{ .bytes = src };
    var value: data.CellText = .{ .grid_pos = .{ 0, 0 }, .color = @splat(0), .atlas = .grayscale };
    for (&value.glyph_pos) |*v| v.* = try reader.integer(u32);
    for (&value.glyph_size) |*v| v.* = try reader.integer(u32);
    for (&value.bearings) |*v| v.* = try reader.integer(i16);
    for (&value.grid_pos) |*v| v.* = try reader.integer(u16);
    for (&value.color) |*v| v.* = try reader.integer(u8);
    value.atlas = std.enums.fromInt(data.CellText.Atlas, try reader.integer(u8)) orelse return error.InvalidEnum;
    const flags = try reader.integer(u8);
    if (flags & ~@as(u8, 3) != 0) return error.InvalidFlags;
    value.bools = @bitCast(flags);
    return value;
}

pub fn encodeImage(dst: []u8, value: data.Image) ![]const u8 {
    if (dst.len < image_bytes) return error.OutputTooSmall;
    var writer: Writer = .{ .bytes = dst };
    for (value.grid_pos) |v| try writer.float(v);
    for (value.cell_offset) |v| try writer.float(v);
    for (value.source_rect) |v| try writer.float(v);
    for (value.dest_size) |v| try writer.float(v);
    return writer.finish(image_bytes);
}
pub fn decodeImage(src: []const u8) !data.Image {
    if (src.len != image_bytes) return error.InvalidLength;
    var reader: Reader = .{ .bytes = src };
    var value: data.Image = undefined;
    for (&value.grid_pos) |*v| v.* = try reader.float();
    for (&value.cell_offset) |*v| v.* = try reader.float();
    for (&value.source_rect) |*v| v.* = try reader.float();
    for (&value.dest_size) |*v| v.* = try reader.float();
    return value;
}

pub fn encodeBackground(dst: []u8, value: data.BgImage) ![]const u8 {
    if (dst.len < background_bytes) return error.OutputTooSmall;
    if (value.opacity < 0 or value.opacity > 1) return error.InvalidOpacity;
    var writer: Writer = .{ .bytes = dst };
    try writer.float(value.opacity);
    const info: u8 = @bitCast(value.info);
    if (info & 128 != 0) return error.InvalidFlags;
    try writer.integer(u8, info);
    return writer.finish(background_bytes);
}
pub fn decodeBackground(src: []const u8) !data.BgImage {
    if (src.len != background_bytes) return error.InvalidLength;
    var reader: Reader = .{ .bytes = src };
    const opacity = try reader.float();
    if (opacity < 0 or opacity > 1) return error.InvalidOpacity;
    const info = try reader.integer(u8);
    if (info & 128 != 0) return error.InvalidFlags;
    _ = std.enums.fromInt(data.BgImage.Info.Position, info & 15) orelse return error.InvalidEnum;
    return .{ .opacity = opacity, .info = @bitCast(info) };
}

test "remote shader uniforms omit padding and preserve all fields" {
    var value = std.mem.zeroes(data.Uniforms);
    value.projection_matrix[0][1] = 1.25;
    value.screen_size = .{ 960, 640 };
    value.cell_size = .{ 9, 17 };
    value.grid_size = .{ 106, 37 };
    value.grid_padding = .{ 1, 2, 3, 4 };
    value.padding_extend = .{ .right = true, .down = true };
    value.min_contrast = 1.5;
    value.cursor_pos = .{ 45, 11 };
    value.cursor_color = .{ 11, 12, 13, 14 };
    value.bg_color = .{ 12, 12, 12, 255 };
    value.bools = .{ .cursor_wide = true, .use_display_p3 = true, .use_linear_blending = false };
    var bytes: [uniforms_bytes]u8 = undefined;
    const encoded = try encodeUniforms(&bytes, value);
    try std.testing.expect(encoded.len < @sizeOf(data.Uniforms));
    try std.testing.expectEqualDeep(value, try decodeUniforms(encoded));
}

test "remote shader cells preserve signed bearings colors and atlas" {
    const value: data.CellText = .{ .glyph_pos = .{ 7, 9 }, .glyph_size = .{ 13, 17 }, .bearings = .{ -3, 6 }, .grid_pos = .{ 45, 11 }, .color = .{ 1, 2, 3, 4 }, .atlas = .color, .bools = .{ .is_cursor_glyph = true } };
    var bytes: [cell_bytes]u8 = undefined;
    const encoded = try encodeCell(&bytes, value);
    try std.testing.expect(encoded.len < @sizeOf(data.CellText));
    try std.testing.expectEqualDeep(value, try decodeCell(encoded));
    bytes[28] = 2;
    try std.testing.expectError(error.InvalidEnum, decodeCell(&bytes));
}

test "remote shader image and background omit native tail padding" {
    const image: data.Image = .{ .grid_pos = .{ 1, 2 }, .cell_offset = .{ -1, 3 }, .source_rect = .{ 1, 2, 3, 4 }, .dest_size = .{ 32, 24 } };
    var bytes: [image_bytes]u8 = undefined;
    try std.testing.expectEqualDeep(image, try decodeImage(try encodeImage(&bytes, image)));
    const background: data.BgImage = .{ .opacity = 0.5, .info = .{ .position = .br, .fit = .cover, .repeat = true } };
    try std.testing.expectEqualDeep(background, try decodeBackground(try encodeBackground(&bytes, background)));
}

test "remote shader rejects nonfinite scalars lengths and reserved flags" {
    var bytes: [uniforms_bytes]u8 = undefined;
    var value = std.mem.zeroes(data.Uniforms);
    value.min_contrast = std.math.nan(f32);
    try std.testing.expectError(error.NonFiniteValue, encodeUniforms(&bytes, value));
    value.min_contrast = 1;
    _ = try encodeUniforms(&bytes, value);
    bytes[100] = 128;
    try std.testing.expectError(error.InvalidFlags, decodeUniforms(&bytes));
    try std.testing.expectError(error.InvalidLength, decodeUniforms(bytes[0 .. uniforms_bytes - 1]));
    try std.testing.expectError(error.OutputTooSmall, encodeUniforms(bytes[0 .. uniforms_bytes - 1], value));
    const bad: data.BgImage = .{ .opacity = 2, .info = .{ .position = .tl, .fit = .contain, .repeat = false } };
    try std.testing.expectError(error.InvalidOpacity, encodeBackground(&bytes, bad));
}
