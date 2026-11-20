//! Bounded CPU resource payloads. These encode requests, not GPU execution ACKs.
//! No native struct/pointer/GL object bytes cross this boundary.
const std = @import("std");
const protocol = @import("Protocol.zig");

pub const Format = enum(u8) { r8 = 1, rgba8 = 2, bgra8_srgb = 3 };
pub const Target = enum(u8) { texture_2d = 1, rectangle = 2 };
pub const Filter = enum(u8) { nearest = 0, linear = 1 };
pub const Wrap = enum(u8) { clamp_to_edge = 0, repeat = 1, mirrored_repeat = 2 };
pub const BufferTarget = enum(u8) { vertex = 1, uniform = 2 };
pub const Usage = enum(u8) { stream = 1, dynamic = 2, static = 3 };

pub const Limits = struct {
    max_dimension: u32,
    max_bytes: u32,

    fn validate(self: Limits) !void {
        if (self.max_dimension == 0 or self.max_dimension > 32768 or self.max_bytes == 0 or
            self.max_bytes > protocol.hard_payload_limit - upload_header_bytes) return error.InvalidLimit;
    }
};

pub const Buffer = struct {
    id: protocol.ResourceId,
    byte_len: u32,
    target: BufferTarget,
    usage: Usage,
};
pub const Texture = struct {
    id: protocol.ResourceId,
    width: u32,
    height: u32,
    format: Format,
    target: Target,
    min: Filter = .nearest,
    mag: Filter = .nearest,
    wrap_s: Wrap = .clamp_to_edge,
    wrap_t: Wrap = .clamp_to_edge,
};
pub const Upload = struct {
    id: protocol.ResourceId,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    stride: u32,
    // Borrowed bytes: transport ownership/fence must remain held until copied.
    data: []const u8,
};
pub const buffer_bytes = 16;
pub const texture_bytes = 24;
pub const upload_header_bytes = 32;

fn checkedId(id: protocol.ResourceId) !void {
    if (id.generation == 0) return error.InvalidResourceId;
}
fn putId(dst: *[8]u8, id: protocol.ResourceId) !void {
    dst.* = try id.encode();
}
fn bytesFor(width: u32, height: u32, format: Format, limits: Limits) !u32 {
    try limits.validate();
    if (width == 0 or height == 0 or width > limits.max_dimension or height > limits.max_dimension) return error.InvalidDimensions;
    const channels: u64 = if (format == .r8) 1 else 4;
    const bytes = @as(u64, width) * height * channels;
    if (bytes > limits.max_bytes) return error.PayloadTooLarge;
    return @intCast(bytes);
}
fn enumeration(comptime T: type, byte: u8) !T {
    return std.enums.fromInt(T, byte) orelse error.InvalidEnum;
}

pub fn encodeBuffer(dst: []u8, value: Buffer, limits: Limits) ![]const u8 {
    try limits.validate();
    try checkedId(value.id);
    if (value.byte_len == 0 or value.byte_len > limits.max_bytes) return error.InvalidBufferSize;
    if (dst.len < buffer_bytes) return error.OutputTooSmall;
    try putId(dst[0..8], value.id);
    std.mem.writeInt(u32, dst[8..12], value.byte_len, .little);
    dst[12] = @intFromEnum(value.target);
    dst[13] = @intFromEnum(value.usage);
    @memset(dst[14..16], 0);
    return dst[0..buffer_bytes];
}
pub fn decodeBuffer(src: []const u8, limits: Limits) !Buffer {
    try limits.validate();
    if (src.len != buffer_bytes) return error.InvalidLength;
    if (src[14] != 0 or src[15] != 0) return error.InvalidFlags;
    const result: Buffer = .{
        .id = try protocol.ResourceId.decode(src[0..8]),
        .byte_len = std.mem.readInt(u32, src[8..12], .little),
        .target = try enumeration(BufferTarget, src[12]),
        .usage = try enumeration(Usage, src[13]),
    };
    if (result.byte_len == 0 or result.byte_len > limits.max_bytes) return error.InvalidBufferSize;
    return result;
}

fn validateTexture(value: Texture, limits: Limits) !void {
    try checkedId(value.id);
    _ = try bytesFor(value.width, value.height, value.format, limits);
}
pub fn encodeTexture(dst: []u8, value: Texture, limits: Limits) ![]const u8 {
    try validateTexture(value, limits);
    if (dst.len < texture_bytes) return error.OutputTooSmall;
    try putId(dst[0..8], value.id);
    std.mem.writeInt(u32, dst[8..12], value.width, .little);
    std.mem.writeInt(u32, dst[12..16], value.height, .little);
    dst[16] = @intFromEnum(value.format);
    dst[17] = @intFromEnum(value.target);
    dst[18] = @intFromEnum(value.min);
    dst[19] = @intFromEnum(value.mag);
    dst[20] = @intFromEnum(value.wrap_s);
    dst[21] = @intFromEnum(value.wrap_t);
    @memset(dst[22..24], 0);
    return dst[0..texture_bytes];
}
pub fn decodeTexture(src: []const u8, limits: Limits) !Texture {
    if (src.len != texture_bytes) return error.InvalidLength;
    if (src[22] != 0 or src[23] != 0) return error.InvalidFlags;
    const result: Texture = .{
        .id = try protocol.ResourceId.decode(src[0..8]),
        .width = std.mem.readInt(u32, src[8..12], .little),
        .height = std.mem.readInt(u32, src[12..16], .little),
        .format = try enumeration(Format, src[16]),
        .target = try enumeration(Target, src[17]),
        .min = try enumeration(Filter, src[18]),
        .mag = try enumeration(Filter, src[19]),
        .wrap_s = try enumeration(Wrap, src[20]),
        .wrap_t = try enumeration(Wrap, src[21]),
    };
    try validateTexture(result, limits);
    return result;
}

fn validateUpload(value: Upload, texture: Texture, limits: Limits) !void {
    try validateTexture(texture, limits);
    try checkedId(value.id);
    if (!std.meta.eql(value.id, texture.id)) return error.StaleResource;
    const count = try bytesFor(value.width, value.height, texture.format, limits);
    // Validate sub-region without overflowing x+width or y+height.
    if (value.width > texture.width or value.height > texture.height or
        value.x > texture.width - value.width or value.y > texture.height - value.height) return error.InvalidRegion;
    const channels: u32 = if (texture.format == .r8) 1 else 4;
    if (value.stride != value.width * channels or value.data.len != count) return error.InvalidLength;
}
/// dst and value.data must not overlap; upload data is owned by the caller.
pub fn encodeUpload(dst: []u8, value: Upload, texture: Texture, limits: Limits) ![]const u8 {
    try validateUpload(value, texture, limits);
    const total = upload_header_bytes + value.data.len;
    if (dst.len < total) return error.OutputTooSmall;
    try putId(dst[0..8], value.id);
    std.mem.writeInt(u32, dst[8..12], value.x, .little);
    std.mem.writeInt(u32, dst[12..16], value.y, .little);
    std.mem.writeInt(u32, dst[16..20], value.width, .little);
    std.mem.writeInt(u32, dst[20..24], value.height, .little);
    std.mem.writeInt(u32, dst[24..28], @intCast(value.data.len), .little);
    std.mem.writeInt(u32, dst[28..32], value.stride, .little);
    @memcpy(dst[upload_header_bytes..total], value.data);
    return dst[0..total];
}
pub fn decodeUpload(src: []const u8, texture: Texture, limits: Limits) !Upload {
    try limits.validate();
    if (src.len < upload_header_bytes) return error.InvalidLength;
    const count = std.mem.readInt(u32, src[24..28], .little);
    if (count > limits.max_bytes) return error.PayloadTooLarge;
    if (count != src.len - upload_header_bytes) return error.InvalidLength;
    const result: Upload = .{
        .id = try protocol.ResourceId.decode(src[0..8]),
        .x = std.mem.readInt(u32, src[8..12], .little),
        .y = std.mem.readInt(u32, src[12..16], .little),
        .width = std.mem.readInt(u32, src[16..20], .little),
        .height = std.mem.readInt(u32, src[20..24], .little),
        .stride = std.mem.readInt(u32, src[28..32], .little),
        .data = src[upload_header_bytes..],
    };
    try validateUpload(result, texture, limits);
    return result;
}

const test_limits: Limits = .{ .max_dimension = 4096, .max_bytes = 1024 * 1024 };
const test_texture: Texture = .{ .id = .{ .slot = 3, .generation = 7 }, .width = 8, .height = 8, .format = .bgra8_srgb, .target = .rectangle };

test "remote commands buffer and color atlas descriptors roundtrip" {
    var bytes: [32]u8 = undefined;
    const buffer: Buffer = .{ .id = .{ .slot = 1, .generation = 2 }, .byte_len = 4096, .target = .uniform, .usage = .stream };
    try std.testing.expectEqualDeep(buffer, try decodeBuffer(try encodeBuffer(&bytes, buffer, test_limits), test_limits));
    try std.testing.expectEqualDeep(test_texture, try decodeTexture(try encodeTexture(&bytes, test_texture, test_limits), test_limits));
}

test "remote commands reject unknown enums reserved flags and dimensions" {
    var bytes: [24]u8 = undefined;
    _ = try encodeTexture(&bytes, test_texture, test_limits);
    bytes[16] = 255;
    try std.testing.expectError(error.InvalidEnum, decodeTexture(&bytes, test_limits));
    _ = try encodeTexture(&bytes, test_texture, test_limits);
    bytes[22] = 1;
    try std.testing.expectError(error.InvalidFlags, decodeTexture(&bytes, test_limits));
    _ = try encodeTexture(&bytes, test_texture, test_limits);
    std.mem.writeInt(u32, bytes[8..12], std.math.maxInt(u32), .little);
    try std.testing.expectError(error.InvalidDimensions, decodeTexture(&bytes, test_limits));
}

test "remote commands atlas upload preserves bytes and bounds region" {
    var bytes: [64]u8 = undefined;
    var upload: Upload = .{ .id = test_texture.id, .x = 2, .y = 3, .width = 2, .height = 2, .stride = 8, .data = &@as([16]u8, @splat(37)) };
    const decoded = try decodeUpload(try encodeUpload(&bytes, upload, test_texture, test_limits), test_texture, test_limits);
    try std.testing.expectEqualSlices(u8, upload.data, decoded.data);
    upload.x = std.math.maxInt(u32);
    try std.testing.expectError(error.InvalidRegion, encodeUpload(&bytes, upload, test_texture, test_limits));
}

test "remote commands reject stale resource truncated upload and bad stride" {
    var bytes: [64]u8 = undefined;
    var upload: Upload = .{ .id = test_texture.id, .x = 0, .y = 0, .width = 2, .height = 2, .stride = 8, .data = &@as([16]u8, @splat(0)) };
    const encoded = try encodeUpload(&bytes, upload, test_texture, test_limits);
    try std.testing.expectError(error.InvalidLength, decodeUpload(encoded[0 .. encoded.len - 1], test_texture, test_limits));
    upload.id.generation += 1;
    try std.testing.expectError(error.StaleResource, encodeUpload(&bytes, upload, test_texture, test_limits));
    upload.id = test_texture.id;
    upload.stride = std.math.maxInt(u32);
    try std.testing.expectError(error.InvalidLength, encodeUpload(&bytes, upload, test_texture, test_limits));
}

test "remote commands reject oversized products before allocating" {
    var bytes: [24]u8 = undefined;
    var texture = test_texture;
    texture.width = 32768;
    texture.height = 32768;
    try std.testing.expectError(error.PayloadTooLarge, encodeTexture(&bytes, texture, .{ .max_dimension = 32768, .max_bytes = 1024 * 1024 }));
    try std.testing.expectError(error.InvalidLimit, encodeTexture(&bytes, texture, .{ .max_dimension = 32769, .max_bytes = 1024 }));
}

test "remote commands grayscale atlas uses one byte per pixel" {
    var texture = test_texture;
    texture.format = .r8;
    var bytes: [48]u8 = undefined;
    const upload: Upload = .{ .id = texture.id, .x = 0, .y = 0, .width = 2, .height = 2, .stride = 2, .data = &.{ 1, 2, 3, 4 } };
    const decoded = try decodeUpload(try encodeUpload(&bytes, upload, texture, test_limits), texture, test_limits);
    try std.testing.expectEqualSlices(u8, upload.data, decoded.data);
}
