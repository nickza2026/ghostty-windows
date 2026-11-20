//! Immutable, full text-frame payload for the first real-terminal worker path.
//! Text/background cells and BOTH atlases are owned bytes after encodeAlloc.
//! Images/overlays/custom shaders require a later schema, never silent omission.
const std = @import("std");
const data = @import("../GlslData.zig");
const shader = @import("ShaderPayload.zig");
const protocol = @import("Protocol.zig");

pub const magic: u32 = 0x31465243; // CRF1, inside a v2 submit_frame envelope.
pub const header_bytes = 48;
pub const Blending = enum(u8) { native = 0, linear = 1, linear_corrected = 2 };
pub const Row = std.ArrayListUnmanaged(data.CellText);
pub const Atlas = struct { size: u32, bytes: []const u8 };
pub const Input = struct {
    width: u32,
    height: u32,
    blending: Blending,
    uniforms: data.Uniforms,
    background: []const data.CellBg,
    foreground_rows: []const Row,
    grayscale: Atlas,
    color: Atlas,
};
pub const Limits = struct {
    dimension: u32,
    atlas_dimension: u32,
    cells: u32,
    bytes: u32,

    fn validate(self: Limits) !void {
        if (self.dimension == 0 or self.dimension > 32768 or self.atlas_dimension == 0 or
            self.atlas_dimension > 32768 or self.cells == 0 or self.cells > 1024 * 1024 or
            self.bytes == 0 or self.bytes > protocol.hard_payload_limit) return error.InvalidLimit;
    }
};
pub const Owned = struct {
    alloc: std.mem.Allocator,
    bytes: []u8,
    pub fn deinit(self: *Owned) void {
        self.alloc.free(self.bytes);
        self.* = undefined;
    }
};
const Sizes = struct { gray: u32, color: u32, total: usize };

fn sizes(width: u32, height: u32, bg: u32, fg: u32, gray: u32, color: u32, limits: Limits) !Sizes {
    try limits.validate();
    if (width == 0 or height == 0 or width > limits.dimension or height > limits.dimension) return error.InvalidDimensions;
    if (bg > limits.cells or fg > limits.cells) return error.TooManyCells;
    if (gray == 0 or color == 0 or gray > limits.atlas_dimension or color > limits.atlas_dimension) return error.InvalidAtlas;
    const gray_bytes = @as(u64, gray) * gray;
    const color_bytes = @as(u64, color) * color * 4;
    const total = header_bytes + shader.uniforms_bytes + @as(u64, bg) * 4 + @as(u64, fg) * shader.cell_bytes + gray_bytes + color_bytes;
    if (total > limits.bytes) return error.PayloadTooLarge;
    return .{ .gray = @intCast(gray_bytes), .color = @intCast(color_bytes), .total = @intCast(total) };
}
fn uniformGrid(uniforms: data.Uniforms, width: u32, height: u32, backgrounds: u32) !void {
    if (uniforms.screen_size[0] != @as(f32, @floatFromInt(width)) or
        uniforms.screen_size[1] != @as(f32, @floatFromInt(height))) return error.StaleDimensions;
    const cols: u32 = uniforms.grid_size[0];
    const rows: u32 = uniforms.grid_size[1];
    if (cols == 0 or rows == 0 or cols * rows != backgrounds) return error.InvalidGrid;
}
fn glyphBounds(cell: data.CellText, uniforms: data.Uniforms, gray: u32, color: u32) !void {
    const size = if (cell.atlas == .grayscale) gray else color;
    if (cell.glyph_size[0] > size or cell.glyph_size[1] > size or
        cell.glyph_pos[0] > size - cell.glyph_size[0] or cell.glyph_pos[1] > size - cell.glyph_size[1]) return error.InvalidGlyph;
    if (cell.grid_pos[0] >= uniforms.grid_size[0] or cell.grid_pos[1] >= uniforms.grid_size[1]) return error.InvalidGlyph;
}

/// Call with stable CPU cells and atlas read locks. Does no GPU/IPC/UI wait.
pub fn encodeAlloc(alloc: std.mem.Allocator, input: Input, limits: Limits) !Owned {
    try limits.validate();
    if (input.background.len > limits.cells) return error.TooManyCells;
    var foreground: u32 = 0;
    for (input.foreground_rows) |row| {
        if (row.items.len > limits.cells - foreground) return error.TooManyCells;
        foreground += @intCast(row.items.len);
    }
    const bg: u32 = @intCast(input.background.len);
    const required = try sizes(input.width, input.height, bg, foreground, input.grayscale.size, input.color.size, limits);
    if (input.grayscale.bytes.len != required.gray or input.color.bytes.len != required.color) return error.InvalidAtlas;
    try uniformGrid(input.uniforms, input.width, input.height, bg);
    const bytes = try alloc.alloc(u8, required.total);
    errdefer alloc.free(bytes);
    std.mem.writeInt(u32, bytes[0..4], magic, .little);
    std.mem.writeInt(u16, bytes[4..6], 1, .little);
    std.mem.writeInt(u16, bytes[6..8], header_bytes, .little);
    std.mem.writeInt(u32, bytes[8..12], input.width, .little);
    std.mem.writeInt(u32, bytes[12..16], input.height, .little);
    std.mem.writeInt(u32, bytes[16..20], bg, .little);
    std.mem.writeInt(u32, bytes[20..24], foreground, .little);
    std.mem.writeInt(u32, bytes[24..28], input.grayscale.size, .little);
    std.mem.writeInt(u32, bytes[28..32], input.color.size, .little);
    std.mem.writeInt(u32, bytes[32..36], required.gray, .little);
    std.mem.writeInt(u32, bytes[36..40], required.color, .little);
    bytes[40] = @intFromEnum(input.blending);
    bytes[41] = 0;
    std.mem.writeInt(u16, bytes[42..44], shader.uniforms_bytes, .little);
    @memset(bytes[44..48], 0);
    var at: usize = header_bytes;
    _ = try shader.encodeUniforms(bytes[at..], input.uniforms);
    at += shader.uniforms_bytes;
    for (input.background) |pixel| {
        @memcpy(bytes[at..][0..4], &pixel);
        at += 4;
    }
    // Includes leading AND trailing cursor rows, in the existing draw order.
    for (input.foreground_rows) |row| for (row.items) |cell| {
        try glyphBounds(cell, input.uniforms, input.grayscale.size, input.color.size);
        _ = try shader.encodeCell(bytes[at..], cell);
        at += shader.cell_bytes;
    };
    @memcpy(bytes[at..][0..required.gray], input.grayscale.bytes);
    at += required.gray;
    @memcpy(bytes[at..][0..required.color], input.color.bytes);
    return .{ .alloc = alloc, .bytes = bytes };
}

pub const Decoded = struct {
    width: u32,
    height: u32,
    blending: Blending,
    uniforms: data.Uniforms,
    background: []const u8,
    foreground: []const u8,
    grayscale: Atlas,
    color: Atlas,

    pub fn cell(self: Decoded, index: usize) !data.CellText {
        if (index >= self.foreground.len / shader.cell_bytes) return error.IndexOutOfBounds;
        return shader.decodeCell(self.foreground[index * shader.cell_bytes ..][0..shader.cell_bytes]);
    }
};

/// Borrowed immutable view only: caller retains the transport ownership fence.
/// Validates every glyph before the GPU executor may allocate/upload anything.
pub fn decode(src: []const u8, limits: Limits) !Decoded {
    try limits.validate();
    if (src.len < header_bytes) return error.InvalidLength;
    if (std.mem.readInt(u32, src[0..4], .little) != magic or std.mem.readInt(u16, src[4..6], .little) != 1 or
        std.mem.readInt(u16, src[6..8], .little) != header_bytes) return error.InvalidHeader;
    if (src[41] != 0 or std.mem.readInt(u32, src[44..48], .little) != 0) return error.InvalidFlags;
    if (std.mem.readInt(u16, src[42..44], .little) != shader.uniforms_bytes) return error.InvalidHeader;
    const width = std.mem.readInt(u32, src[8..12], .little);
    const height = std.mem.readInt(u32, src[12..16], .little);
    const bg = std.mem.readInt(u32, src[16..20], .little);
    const fg = std.mem.readInt(u32, src[20..24], .little);
    const gray = std.mem.readInt(u32, src[24..28], .little);
    const color = std.mem.readInt(u32, src[28..32], .little);
    const required = try sizes(width, height, bg, fg, gray, color, limits);
    if (required.total != src.len or std.mem.readInt(u32, src[32..36], .little) != required.gray or
        std.mem.readInt(u32, src[36..40], .little) != required.color) return error.InvalidLength;
    const blending = std.enums.fromInt(Blending, src[40]) orelse return error.InvalidEnum;
    var at: usize = header_bytes;
    const uniforms = try shader.decodeUniforms(src[at..][0..shader.uniforms_bytes]);
    try uniformGrid(uniforms, width, height, bg);
    at += shader.uniforms_bytes;
    const backgrounds = src[at..][0 .. @as(usize, bg) * 4];
    at += backgrounds.len;
    const foregrounds = src[at..][0 .. @as(usize, fg) * shader.cell_bytes];
    at += foregrounds.len;
    const gray_data = src[at..][0..required.gray];
    at += required.gray;
    const result: Decoded = .{ .width = width, .height = height, .blending = blending, .uniforms = uniforms, .background = backgrounds, .foreground = foregrounds, .grayscale = .{ .size = gray, .bytes = gray_data }, .color = .{ .size = color, .bytes = src[at..] } };
    for (0..fg) |i| try glyphBounds(try result.cell(i), uniforms, gray, color);
    return result;
}

const Fixture = struct {
    bg: [2]data.CellBg = .{ .{ 12, 12, 12, 255 }, .{ 1, 2, 3, 255 } },
    fg: [1]data.CellText = .{.{ .glyph_size = .{ 1, 1 }, .grid_pos = .{ 0, 0 }, .color = .{ 255, 255, 255, 255 }, .atlas = .grayscale }},
    rows: [1]Row = undefined,
    gray: [4]u8 = .{ 1, 2, 3, 4 },
    color: [16]u8 = @splat(7),
    fn input(self: *Fixture) Input {
        var uniforms = std.mem.zeroes(data.Uniforms);
        uniforms.screen_size = .{ 8, 4 };
        uniforms.cell_size = .{ 4, 4 };
        uniforms.grid_size = .{ 2, 1 };
        self.rows[0] = .{ .items = &self.fg, .capacity = 1 };
        return .{ .width = 8, .height = 4, .blending = .native, .uniforms = uniforms, .background = &self.bg, .foreground_rows = &self.rows, .grayscale = .{ .size = 2, .bytes = &self.gray }, .color = .{ .size = 2, .bytes = &self.color } };
    }
};
const test_limits: Limits = .{ .dimension = 1024, .atlas_dimension = 512, .cells = 16, .bytes = 4096 };

test "remote text frame owns cells uniforms and both atlases" {
    var fixture: Fixture = .{};
    var owned = try encodeAlloc(std.testing.allocator, fixture.input(), test_limits);
    defer owned.deinit();
    fixture.gray[0] = 99;
    fixture.fg[0].grid_pos[0] = 1;
    const view = try decode(owned.bytes, test_limits);
    try std.testing.expectEqual(@as(u8, 1), view.grayscale.bytes[0]);
    try std.testing.expectEqual(@as(u16, 0), (try view.cell(0)).grid_pos[0]);
    try std.testing.expectEqual(@as(usize, 16), view.color.bytes.len);
    try std.testing.expectError(error.IndexOutOfBounds, view.cell(1));
}

test "remote text frame rejects forged lengths flags dimensions and glyphs" {
    var fixture: Fixture = .{};
    var owned = try encodeAlloc(std.testing.allocator, fixture.input(), test_limits);
    defer owned.deinit();
    try std.testing.expectError(error.InvalidLength, decode(owned.bytes[0 .. owned.bytes.len - 1], test_limits));
    owned.bytes[41] = 1;
    try std.testing.expectError(error.InvalidFlags, decode(owned.bytes, test_limits));
    owned.bytes[41] = 0;
    const cell_start = header_bytes + shader.uniforms_bytes + 8;
    std.mem.writeInt(u32, owned.bytes[cell_start..][0..4], std.math.maxInt(u32), .little);
    try std.testing.expectError(error.InvalidGlyph, decode(owned.bytes, test_limits));
}

test "remote text frame rejects stale grid and byte caps before allocation" {
    var fixture: Fixture = .{};
    var input = fixture.input();
    input.width = 9;
    try std.testing.expectError(error.StaleDimensions, encodeAlloc(std.testing.allocator, input, test_limits));
    input = fixture.input();
    try std.testing.expectError(error.PayloadTooLarge, encodeAlloc(std.testing.allocator, input, .{ .dimension = 1024, .atlas_dimension = 512, .cells = 16, .bytes = 64 }));
}

fn allocationCase(alloc: std.mem.Allocator) !void {
    var fixture: Fixture = .{};
    var owned = try encodeAlloc(alloc, fixture.input(), test_limits);
    defer owned.deinit();
    _ = try decode(owned.bytes, test_limits);
}
test "remote text frame cleans up every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
