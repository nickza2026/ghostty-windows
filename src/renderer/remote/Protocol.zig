//! CPU-only, explicitly little-endian render-worker envelope (draft v2).
//! This is NOT a native struct ABI or a successful GPU execution receipt.
//! Payload schemas/transport and resource lookup must validate separately.
const std = @import("std");

pub const magic: u32 = 0x32525747; // GWR2
pub const version: u16 = 2;
pub const header_bytes = 48;
pub const hard_payload_limit = 64 * 1024 * 1024;
pub const capability_text: u32 = 1;
pub const capability_inline_images: u32 = 2;
/// Empty hello stays byte-for-byte compatible with the original text client.
pub fn helloCapabilities(payload: []const u8) !u32 {
    if (payload.len == 0) return capability_text;
    if (payload.len != 4) return error.UnsupportedCapabilities;
    const flags = std.mem.readInt(u32, payload[0..4], .little);
    if (flags != capability_text and flags != (capability_text | capability_inline_images)) return error.UnsupportedCapabilities;
    return flags;
}
test "optional image capabilities preserve empty text hello and require known bits" {
    try std.testing.expectEqual(capability_text, try helloCapabilities(&.{}));
    try std.testing.expectEqual(@as(u32, 3), try helloCapabilities(&.{ 3, 0, 0, 0 }));
    try std.testing.expectError(error.UnsupportedCapabilities, helloCapabilities(&.{ 2, 0, 0, 0 }));
    try std.testing.expectError(error.UnsupportedCapabilities, helloCapabilities(&.{ 7, 0, 0, 0 }));
    try std.testing.expectError(error.UnsupportedCapabilities, helloCapabilities(&.{3}));
    var bytes: [header_bytes]u8 = undefined;
    try std.testing.expectError(error.InvalidEpoch, encode(&bytes, .{ .kind = .submit_image_frame, .surface = 1, .generation = 1, .sequence = 1 }, &.{}, .{ .max_payload_bytes = 0 }));
}

pub const Kind = enum(u16) {
    hello = 1,
    hello_ack = 2,
    create_buffer = 3,
    write_buffer = 4,
    create_texture = 5,
    write_texture = 6,
    destroy_resource = 7,
    submit_frame = 8,
    frame_ready = 9,
    close = 10,
    closed = 11,
    create_pipeline = 12,
    create_target = 13,
    create_sampler = 14,
    resource_ack = 15,
    failure = 16,
    submit_image_frame = 17,
};

pub const Limits = struct {
    max_payload_bytes: usize,

    fn validate(self: Limits) !void {
        if (self.max_payload_bytes > hard_payload_limit) return error.InvalidLimit;
    }
};

pub const Header = struct {
    kind: Kind,
    // Opaque session token assigned before GPU/terminal initialization.
    // Never encode a CoreSurface pointer or assume its id is initialized yet.
    surface: u64,
    generation: u64,
    sequence: u64,
    epoch: u64 = 0,

    fn validate(self: Header) !void {
        if (self.surface == 0 or self.generation == 0 or self.sequence == 0) return error.InvalidIdentity;
        if ((self.kind == .submit_frame or self.kind == .submit_image_frame or self.kind == .frame_ready) and self.epoch == 0) return error.InvalidEpoch;
    }

    pub fn expectReply(self: Header, kind: Kind, surface: u64, generation: u64, sequence: u64, epoch: u64) !void {
        try self.validate();
        if (self.kind != kind) return error.UnexpectedKind;
        if (self.surface != surface or self.generation != generation) return error.StaleSession;
        if (self.sequence != sequence) return error.StaleSequence;
        if (self.epoch != epoch) return error.StaleEpoch;
    }
};

pub const Packet = struct {
    header: Header,
    // Borrowed immutable bytes. The transport must hold its ownership fence
    // until copied/consumed; decoding alone does not make shared memory stable.
    payload: []const u8,
};

pub fn encode(dst: []u8, header: Header, payload: []const u8, limits: Limits) ![]const u8 {
    try limits.validate();
    try header.validate();
    if (payload.len > limits.max_payload_bytes) return error.PayloadTooLarge;
    // The hard limit was checked before arithmetic and integer narrowing.
    const total = header_bytes + payload.len;
    if (dst.len < total) return error.OutputTooSmall;
    std.mem.writeInt(u32, dst[0..4], magic, .little);
    std.mem.writeInt(u16, dst[4..6], version, .little);
    std.mem.writeInt(u16, dst[6..8], header_bytes, .little);
    std.mem.writeInt(u16, dst[8..10], @intFromEnum(header.kind), .little);
    std.mem.writeInt(u16, dst[10..12], 0, .little); // Reserved flags must be zero.
    std.mem.writeInt(u32, dst[12..16], @intCast(payload.len), .little);
    std.mem.writeInt(u64, dst[16..24], header.surface, .little);
    std.mem.writeInt(u64, dst[24..32], header.generation, .little);
    std.mem.writeInt(u64, dst[32..40], header.sequence, .little);
    std.mem.writeInt(u64, dst[40..48], header.epoch, .little);
    @memcpy(dst[header_bytes..total], payload);
    return dst[0..total];
}

pub fn decode(src: []const u8, limits: Limits) !Packet {
    try limits.validate();
    if (src.len < header_bytes) return error.TruncatedHeader;
    if (std.mem.readInt(u32, src[0..4], .little) != magic) return error.InvalidMagic;
    if (std.mem.readInt(u16, src[4..6], .little) != version) return error.UnsupportedVersion;
    if (std.mem.readInt(u16, src[6..8], .little) != header_bytes) return error.InvalidHeaderSize;
    if (std.mem.readInt(u16, src[10..12], .little) != 0) return error.UnsupportedFlags;
    const kind = std.enums.fromInt(Kind, std.mem.readInt(u16, src[8..10], .little)) orelse return error.UnknownKind;
    const length: usize = std.mem.readInt(u32, src[12..16], .little);
    if (length > limits.max_payload_bytes) return error.PayloadTooLarge;
    if (length != src.len - header_bytes) return error.InvalidLength;
    const header: Header = .{
        .kind = kind,
        .surface = std.mem.readInt(u64, src[16..24], .little),
        .generation = std.mem.readInt(u64, src[24..32], .little),
        .sequence = std.mem.readInt(u64, src[32..40], .little),
        .epoch = std.mem.readInt(u64, src[40..48], .little),
    };
    try header.validate();
    return .{ .header = header, .payload = src[header_bytes..] };
}

pub const ResourceId = struct {
    slot: u32,
    generation: u32,

    pub fn encode(self: ResourceId) ![8]u8 {
        if (self.generation == 0) return error.InvalidResourceId;
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u32, bytes[0..4], self.slot, .little);
        std.mem.writeInt(u32, bytes[4..8], self.generation, .little);
        return bytes;
    }

    pub fn decode(bytes: *const [8]u8) !ResourceId {
        const result: ResourceId = .{
            .slot = std.mem.readInt(u32, bytes[0..4], .little),
            .generation = std.mem.readInt(u32, bytes[4..8], .little),
        };
        if (result.generation == 0) return error.InvalidResourceId;
        return result; // A registry must still check slot bounds/liveness/type.
    }
};

const test_header: Header = .{ .kind = .frame_ready, .surface = 7, .generation = 9, .sequence = 11, .epoch = 13 };
const test_limits: Limits = .{ .max_payload_bytes = 128 };

test "remote protocol little endian envelope roundtrip" {
    var bytes: [64]u8 = undefined;
    const encoded = try encode(&bytes, test_header, &.{ 1, 2, 3 }, test_limits);
    try std.testing.expectEqualStrings("GWR2", encoded[0..4]);
    try std.testing.expectEqual(@as(u8, 7), encoded[16]);
    const packet = try decode(encoded, test_limits);
    try std.testing.expectEqualDeep(test_header, packet.header);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, packet.payload);
}

test "remote protocol rejects truncation trailing bytes and short output" {
    var bytes: [64]u8 = undefined;
    const encoded = try encode(&bytes, test_header, &.{1}, test_limits);
    try std.testing.expectError(error.TruncatedHeader, decode(encoded[0..47], test_limits));
    try std.testing.expectError(error.InvalidLength, decode(encoded[0..48], test_limits));
    try std.testing.expectError(error.InvalidLength, decode(bytes[0..50], test_limits));
    try std.testing.expectError(error.OutputTooSmall, encode(bytes[0..47], test_header, &.{}, test_limits));
}

test "remote protocol rejects unknown header version kind and flags" {
    var bytes: [48]u8 = undefined;
    _ = try encode(&bytes, test_header, &.{}, test_limits);
    bytes[4] = 99;
    try std.testing.expectError(error.UnsupportedVersion, decode(&bytes, test_limits));
    bytes[4] = version;
    bytes[8] = 255;
    try std.testing.expectError(error.UnknownKind, decode(&bytes, test_limits));
    bytes[8] = @intFromEnum(Kind.frame_ready);
    bytes[10] = 1;
    try std.testing.expectError(error.UnsupportedFlags, decode(&bytes, test_limits));
}

test "remote protocol bounds untrusted payload length before allocation" {
    var bytes: [48]u8 = undefined;
    _ = try encode(&bytes, test_header, &.{}, test_limits);
    std.mem.writeInt(u32, bytes[12..16], std.math.maxInt(u32), .little);
    try std.testing.expectError(error.PayloadTooLarge, decode(&bytes, test_limits));
    try std.testing.expectError(error.InvalidLimit, decode(&bytes, .{ .max_payload_bytes = hard_payload_limit + 1 }));
}

test "remote protocol rejects stale session sequence and resize epoch" {
    try test_header.expectReply(.frame_ready, 7, 9, 11, 13);
    try std.testing.expectError(error.StaleSession, test_header.expectReply(.frame_ready, 8, 9, 11, 13));
    try std.testing.expectError(error.StaleSession, test_header.expectReply(.frame_ready, 7, 10, 11, 13));
    try std.testing.expectError(error.StaleSequence, test_header.expectReply(.frame_ready, 7, 9, 12, 13));
    try std.testing.expectError(error.StaleEpoch, test_header.expectReply(.frame_ready, 7, 9, 11, 14));
}

test "remote protocol validates identity and frame epochs" {
    var bytes: [48]u8 = undefined;
    var header = test_header;
    header.surface = 0;
    try std.testing.expectError(error.InvalidIdentity, encode(&bytes, header, &.{}, test_limits));
    header = test_header;
    header.epoch = 0;
    try std.testing.expectError(error.InvalidEpoch, encode(&bytes, header, &.{}, test_limits));
}

test "remote resource ids are fixed width and reject invalid generation" {
    const id: ResourceId = .{ .slot = 0, .generation = 17 };
    const bytes = try id.encode();
    try std.testing.expectEqualDeep(id, try ResourceId.decode(&bytes));
    try std.testing.expectError(error.InvalidResourceId, (ResourceId{ .slot = 5, .generation = 0 }).encode());
    try std.testing.expectError(error.InvalidResourceId, ResourceId.decode(&@as([8]u8, @splat(0))));
}
