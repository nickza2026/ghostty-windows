//! Bounded, OS-independent Windows clipboard image conversion.
//! Nothing in this module opens or modifies the clipboard.
//!
//! DIB: 40/108/124-byte headers, 24/32-bit BI_RGB and canonical 32-bit
//! BI_BITFIELDS, no palettes/profiles/compressed pixel streams. BI_RGB's
//! reserved fourth byte is ignored (opaque). Explicit V4/V5 alpha masks
//! preserve straight alpha; premultiplied input is not unpremultiplied.
//! RGB is treated as sRGB; calibrated/linked/embedded color profiles reject.
//! PNG: structural/chunk/CRC/dimension validation only, NOT IDAT decoding.
//! Callers must not describe validatePng as fully decoding an untrusted PNG.
const std = @import("std");

pub const max_bytes: usize = 64 * 1024 * 1024;
pub const max_pixels: usize = 8 * 1024 * 1024;
pub const max_dimension: usize = 16384;
const signature = "\x89PNG\r\n\x1a\n";

const Dib = struct {
    width: usize,
    height: usize,
    stride: usize,
    offset: usize,
    bpp: usize,
    top_down: bool,
    alpha: bool,
};

fn dimensions(width: usize, height: usize) !void {
    if (width == 0 or height == 0 or width > max_dimension or height > max_dimension)
        return error.InvalidImageDimensions;
    if (width > max_pixels / height) return error.ImageTooLarge;
}

fn le16(bytes: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .little);
}
fn le32(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}
fn be32(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .big);
}
fn put32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn parseDib(bytes: []const u8) !Dib {
    if (bytes.len > max_bytes) return error.ImageTooLarge;
    if (bytes.len < 40) return error.TruncatedDib;
    const header: usize = le32(bytes, 0);
    if (header != 40 and header != 108 and header != 124) return error.UnsupportedDibHeader;
    if (bytes.len < header) return error.TruncatedDib;
    const signed_width: i32 = @bitCast(le32(bytes, 4));
    const signed_height: i32 = @bitCast(le32(bytes, 8));
    if (signed_width <= 0 or signed_height == 0 or signed_height == std.math.minInt(i32))
        return error.InvalidImageDimensions;
    const width: usize = @intCast(signed_width);
    const height: usize = @intCast(@abs(signed_height));
    try dimensions(width, height);
    if (le16(bytes, 12) != 1) return error.InvalidDibPlanes;
    const bits = le16(bytes, 14);
    if (bits != 24 and bits != 32) return error.UnsupportedDibDepth;
    if (le32(bytes, 32) != 0) return error.UnsupportedDibPalette;
    const compression = le32(bytes, 16);
    var offset = header;
    var alpha = false;
    switch (compression) {
        0 => {}, // BI_RGB: BGR or BGRX, not BGRA.
        3 => {
            if (bits != 32) return error.UnsupportedDibMasks;
            if (header == 40) offset += 12;
            if (bytes.len < offset) return error.TruncatedDib;
            if (le32(bytes, 40) != 0x00ff0000 or
                le32(bytes, 44) != 0x0000ff00 or
                le32(bytes, 48) != 0x000000ff) return error.UnsupportedDibMasks;
            if (header >= 108) {
                const mask = le32(bytes, 52);
                if (mask != 0 and mask != 0xff000000) return error.UnsupportedDibMasks;
                alpha = mask != 0;
            }
        },
        else => return error.UnsupportedDibCompression,
    }
    // Embedded/linked profiles can change the location/meaning of pixels.
    // Do not follow profile paths or silently treat profile bytes as pixels.
    if (header == 124 and (le32(bytes, 112) != 0 or le32(bytes, 116) != 0))
        return error.UnsupportedDibProfile;
    if (header >= 108) {
        const color_space = le32(bytes, 56);
        if (color_space != 0 and color_space != 0x73524742 and color_space != 0x57696e20)
            return error.UnsupportedDibColorSpace; // sRGB / Windows color space only.
        // All-zero V4 fields are common for untagged RGB. Nonzero calibrated
        // endpoints/gamma need a color transform this small codec cannot do.
        if (color_space == 0) {
            for (bytes[60..108]) |value| if (value != 0) return error.UnsupportedDibColorSpace;
        }
    }
    const bpp: usize = bits / 8;
    const stride = (width * bpp + 3) & ~@as(usize, 3);
    const pixel_bytes = stride * height;
    if (offset > bytes.len or pixel_bytes > bytes.len - offset) return error.TruncatedDib;
    const declared: usize = le32(bytes, 20);
    if (declared != 0 and (declared < pixel_bytes or declared > bytes.len - offset))
        return error.InvalidDibImageSize;
    return .{ .width = width, .height = height, .stride = stride, .offset = offset, .bpp = bpp, .top_down = signed_height < 0, .alpha = alpha };
}

/// Convert supported packed DIB data (without BITMAPFILEHEADER) into owned PNG.
/// The caller owns the returned allocation. OS clipboard padding is tolerated
/// after the complete DIB pixels, but never included in the encoded PNG.
pub fn fromDib(alloc: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const dib = try parseDib(bytes);
    const row = dib.width * 4 + 1;
    const raw_len = row * dib.height;
    const blocks = (raw_len + 65534) / 65535;
    const zlib_len = 2 + raw_len + blocks * 5 + 4;
    const total = 8 + 25 + 12 + zlib_len + 12;
    if (total > max_bytes) return error.ImageTooLarge;
    const out = try alloc.alloc(u8, total);
    errdefer alloc.free(out);
    @memcpy(out[0..8], signature);
    put32(out, 8, 13);
    @memcpy(out[12..16], "IHDR");
    put32(out, 16, @intCast(dib.width));
    put32(out, 20, @intCast(dib.height));
    @memcpy(out[24..29], &[_]u8{ 8, 6, 0, 0, 0 }); // RGBA8, no interlace.
    put32(out, 29, std.hash.Crc32.hash(out[12..29]));
    put32(out, 33, @intCast(zlib_len));
    @memcpy(out[37..41], "IDAT");
    var pos: usize = 41;
    out[pos] = 0x78;
    out[pos + 1] = 0x01; // zlib, stored DEFLATE blocks, valid FCHECK.
    pos += 2;
    var raw_pos: usize = 0;
    var a: u32 = 1;
    var b: u32 = 0;
    while (raw_pos < raw_len) {
        const count: u16 = @intCast(@min(raw_len - raw_pos, 65535));
        out[pos] = if (raw_pos + count == raw_len) 1 else 0;
        std.mem.writeInt(u16, out[pos + 1 ..][0..2], count, .little);
        std.mem.writeInt(u16, out[pos + 3 ..][0..2], ~count, .little);
        pos += 5;
        for (0..count) |_| {
            const y = raw_pos / row;
            const x = raw_pos % row;
            const value: u8 = if (x == 0) 0 else pixel: {
                const component = (x - 1) % 4;
                const column = (x - 1) / 4;
                const source_y = if (dib.top_down) y else dib.height - 1 - y;
                const source = dib.offset + source_y * dib.stride + column * dib.bpp;
                break :pixel switch (component) {
                    0 => bytes[source + 2],
                    1 => bytes[source + 1],
                    2 => bytes[source],
                    3 => if (dib.alpha) bytes[source + 3] else 255,
                    else => unreachable,
                };
            };
            out[pos] = value;
            pos += 1;
            raw_pos += 1;
            a = (a + value) % 65521;
            b = (b + a) % 65521;
        }
    }
    put32(out, pos, (b << 16) | a);
    pos += 4;
    put32(out, pos, std.hash.Crc32.hash(out[37..pos]));
    pos += 4;
    put32(out, pos, 0);
    @memcpy(out[pos + 4 ..][0..4], "IEND");
    put32(out, pos + 8, std.hash.Crc32.hash("IEND"));
    std.debug.assert(pos + 12 == out.len);
    return out;
}

/// Validate a complete PNG's wire structure, chunk CRCs and bounded dimensions.
/// IDAT is NOT inflated, decoded, or checked for valid filter/pixel data. The
/// limit bounds image area and encoded bytes, not ancillary decompressed data.
/// pngPayload validates logical PNG bytes and permits bounded zero HGLOBAL
/// padding. validatePng below is strict and rejects any trailing bytes.
pub fn pngPayload(bytes: []const u8) ![]const u8 {
    if (bytes.len > max_bytes) return error.ImageTooLarge;
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..8], signature)) return error.InvalidPngSignature;
    var pos: usize = 8;
    while (pos < bytes.len) {
        if (bytes.len - pos < 12) return error.TruncatedPng;
        const length: usize = be32(bytes, pos);
        if (length > bytes.len - pos - 12) return error.TruncatedPng;
        const end = pos + length + 12;
        if (std.mem.eql(u8, bytes[pos + 4 ..][0..4], "IEND")) {
            // HGLOBAL's allocation size may exceed the logical PNG length.
            // Accept only bounded zero padding; never forward padding bytes.
            if (bytes.len - end > 4096) return error.TrailingPngData;
            for (bytes[end..]) |c| if (c != 0) return error.TrailingPngData;
            try validatePng(bytes[0..end]);
            return bytes[0..end];
        }
        pos = end;
    }
    return error.TruncatedPng;
}

pub fn validatePng(bytes: []const u8) !void {
    if (bytes.len > max_bytes) return error.ImageTooLarge;
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..8], signature)) return error.InvalidPngSignature;
    var pos: usize = 8;
    var header = false;
    var palette = false;
    var transparency = false;
    var data = false;
    var data_ended = false;
    var data_bytes: usize = 0;
    var color: u8 = 0;
    var depth: u8 = 0;
    var palette_entries: usize = 0;
    while (pos < bytes.len) {
        if (bytes.len - pos < 12) return error.TruncatedPng;
        const length: usize = be32(bytes, pos);
        if (length > 0x7fffffff or length > bytes.len - pos - 12) return error.TruncatedPng;
        const name = bytes[pos + 4 ..][0..4];
        for (name) |c| if (!std.ascii.isAlphabetic(c)) return error.InvalidPngChunk;
        if (!std.ascii.isUpper(name[2])) return error.InvalidPngChunk;
        const payload = bytes[pos + 8 ..][0..length];
        const crc_pos = pos + 8 + length;
        if (std.hash.Crc32.hash(bytes[pos + 4 .. crc_pos]) != be32(bytes, crc_pos)) return error.InvalidPngCrc;
        if (!header and !std.mem.eql(u8, name, "IHDR")) return error.InvalidPngOrder;
        if (std.mem.eql(u8, name, "IHDR")) {
            if (header or pos != 8 or length != 13) return error.InvalidPngHeader;
            try dimensions(be32(payload, 0), be32(payload, 4));
            depth = payload[8];
            color = payload[9];
            const valid_depth = switch (color) {
                0 => depth == 1 or depth == 2 or depth == 4 or depth == 8 or depth == 16,
                2, 4, 6 => depth == 8 or depth == 16,
                3 => depth == 1 or depth == 2 or depth == 4 or depth == 8,
                else => false,
            };
            if (!valid_depth or payload[10] != 0 or payload[11] != 0 or payload[12] > 1) return error.InvalidPngHeader;
            header = true;
        } else if (std.mem.eql(u8, name, "PLTE")) {
            if (palette or data or transparency or color == 0 or color == 4 or length == 0 or length > 768 or length % 3 != 0)
                return error.InvalidPngPalette;
            palette_entries = length / 3;
            if (color == 3 and palette_entries > (@as(usize, 1) << @intCast(depth))) return error.InvalidPngPalette;
            palette = true;
        } else if (std.mem.eql(u8, name, "tRNS")) {
            if (transparency or data) return error.InvalidPngOrder;
            switch (color) {
                0 => if (length != 2) return error.InvalidPngTransparency,
                2 => if (length != 6) return error.InvalidPngTransparency,
                3 => if (!palette or length == 0 or length > palette_entries) return error.InvalidPngTransparency,
                else => return error.InvalidPngTransparency,
            }
            transparency = true;
        } else if (std.mem.eql(u8, name, "IDAT")) {
            if (data_ended or (color == 3 and !palette)) return error.InvalidPngOrder;
            data = true;
            data_bytes += length; // At most bytes.len, already bounded above.
        } else if (std.mem.eql(u8, name, "IEND")) {
            if (length != 0 or !data or data_bytes < 6) return error.InvalidPngOrder;
            if (crc_pos + 4 != bytes.len) return error.TrailingPngData;
            return;
        } else {
            if (std.ascii.isUpper(name[0])) return error.UnsupportedPngChunk;
            if (data) data_ended = true;
        }
        pos = crc_pos + 4;
    }
    return error.TruncatedPng;
}

fn fixture(header: u32, width: i32, height: i32, bits: u16, compression: u32) [256]u8 {
    var bytes: [256]u8 = @splat(0);
    std.mem.writeInt(u32, bytes[0..4], header, .little);
    std.mem.writeInt(i32, bytes[4..8], width, .little);
    std.mem.writeInt(i32, bytes[8..12], height, .little);
    std.mem.writeInt(u16, bytes[12..14], 1, .little);
    std.mem.writeInt(u16, bytes[14..16], bits, .little);
    std.mem.writeInt(u32, bytes[16..20], compression, .little);
    return bytes;
}

// Read our encoder's stored blocks independently in tests. Also verifies the
// LEN/NLEN complement, final-bit handling and Adler32 over the decoded pixels.
fn storedPixels(alloc: std.mem.Allocator, png: []const u8) ![]u8 {
    try validatePng(png);
    const encoded = png[41..][0..be32(png, 33)];
    try std.testing.expectEqualSlices(u8, &.{ 0x78, 0x01 }, encoded[0..2]);
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(alloc);
    var pos: usize = 2;
    var done = false;
    while (!done) {
        try std.testing.expect(encoded[pos] <= 1);
        done = encoded[pos] == 1;
        const count = le16(encoded, pos + 1);
        try std.testing.expectEqual(@as(u16, ~count), le16(encoded, pos + 3));
        pos += 5;
        try result.appendSlice(alloc, encoded[pos..][0..count]);
        pos += count;
    }
    try std.testing.expectEqual(encoded.len - 4, pos);
    var a: u32 = 1;
    var b: u32 = 0;
    for (result.items) |v| {
        a = (a + v) % 65521;
        b = (b + a) % 65521;
    }
    try std.testing.expectEqual((b << 16) | a, be32(encoded, pos));
    return result.toOwnedSlice(alloc);
}

test "clipboard image DIB24 bottom-up padding and PNG checksums" {
    var dib = fixture(40, 1, 2, 24, 0);
    @memcpy(dib[40..48], &[_]u8{ 255, 0, 0, 91, 0, 0, 255, 92 }); // blue bottom, red top.
    const png = try fromDib(std.testing.allocator, dib[0..48]);
    defer std.testing.allocator.free(png);
    const pixels = try storedPixels(std.testing.allocator, png);
    defer std.testing.allocator.free(pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 0, 255, 0, 0, 0, 255, 255 }, pixels);
    try std.testing.expectEqual(@as(u32, 1), be32(png, 16));
    try std.testing.expectEqual(@as(u32, 2), be32(png, 20));
}

test "clipboard image PNG allocation padding is stripped not forwarded" {
    const a = std.testing.allocator;
    const dib = fixture(40, 1, -1, 24, 0);
    const png = try fromDib(a, dib[0..44]);
    defer a.free(png);
    const padded = try a.alloc(u8, png.len + 8);
    defer a.free(padded);
    @memcpy(padded[0..png.len], png);
    @memset(padded[png.len..], 0);
    try std.testing.expectEqualSlices(u8, png, try pngPayload(padded));
    try std.testing.expectError(error.TrailingPngData, validatePng(padded));
    padded[padded.len - 1] = 7;
    try std.testing.expectError(error.TrailingPngData, pngPayload(padded));
}

test "clipboard image top-down RGB32 ignores reserved alpha" {
    var dib = fixture(40, 2, -1, 32, 0);
    @memcpy(dib[40..48], &[_]u8{ 3, 2, 1, 0, 6, 5, 4, 123 });
    const png = try fromDib(std.testing.allocator, dib[0..48]);
    defer std.testing.allocator.free(png);
    const pixels = try storedPixels(std.testing.allocator, png);
    defer std.testing.allocator.free(pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 3, 255, 4, 5, 6, 255 }, pixels);
}

test "clipboard image V5 explicit straight alpha and profile rejection" {
    var dib = fixture(124, 1, -1, 32, 3);
    std.mem.writeInt(u32, dib[40..44], 0xff0000, .little);
    std.mem.writeInt(u32, dib[44..48], 0xff00, .little);
    std.mem.writeInt(u32, dib[48..52], 0xff, .little);
    std.mem.writeInt(u32, dib[52..56], 0xff000000, .little);
    @memcpy(dib[124..128], &[_]u8{ 30, 20, 10, 40 });
    const png = try fromDib(std.testing.allocator, dib[0..128]);
    defer std.testing.allocator.free(png);
    const pixels = try storedPixels(std.testing.allocator, png);
    defer std.testing.allocator.free(pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 10, 20, 30, 40 }, pixels);
    dib[112] = 128;
    try std.testing.expectError(error.UnsupportedDibProfile, fromDib(std.testing.allocator, dib[0..128]));
}

test "clipboard image header40 bitfield masks and absent alpha" {
    var dib = fixture(40, 1, 1, 32, 3);
    std.mem.writeInt(u32, dib[40..44], 0xff0000, .little);
    std.mem.writeInt(u32, dib[44..48], 0xff00, .little);
    std.mem.writeInt(u32, dib[48..52], 0xff, .little);
    @memcpy(dib[52..56], &[_]u8{ 3, 2, 1, 99 });
    const png = try fromDib(std.testing.allocator, dib[0..56]);
    defer std.testing.allocator.free(png);
    const pixels = try storedPixels(std.testing.allocator, png);
    defer std.testing.allocator.free(pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 3, 255 }, pixels);
    dib[40] = 1;
    try std.testing.expectError(error.UnsupportedDibMasks, fromDib(std.testing.allocator, dib[0..56]));
}

test "clipboard image malformed dimensions header planes depth and payload" {
    var dib = fixture(40, 1, 1, 24, 0);
    for (0..44) |length| try std.testing.expectError(error.TruncatedDib, fromDib(std.testing.allocator, dib[0..length]));
    dib = fixture(12, 1, 1, 24, 0);
    try std.testing.expectError(error.UnsupportedDibHeader, fromDib(std.testing.allocator, &dib));
    for ([_]i32{ 0, -1, std.math.minInt(i32), std.math.maxInt(i32) }) |width| {
        dib = fixture(40, width, 1, 24, 0);
        try std.testing.expectError(error.InvalidImageDimensions, fromDib(std.testing.allocator, &dib));
    }
    for ([_]i32{ 0, std.math.minInt(i32) }) |height| {
        dib = fixture(40, 1, height, 24, 0);
        try std.testing.expectError(error.InvalidImageDimensions, fromDib(std.testing.allocator, &dib));
    }
    dib = fixture(40, 4096, 4096, 32, 0);
    try std.testing.expectError(error.ImageTooLarge, fromDib(std.testing.allocator, &dib));
    dib = fixture(40, 1, 1, 16, 0);
    try std.testing.expectError(error.UnsupportedDibDepth, fromDib(std.testing.allocator, &dib));
    dib = fixture(40, 1, 1, 24, 1);
    try std.testing.expectError(error.UnsupportedDibCompression, fromDib(std.testing.allocator, &dib));
    dib = fixture(40, 1, 1, 24, 0);
    dib[12] = 2;
    try std.testing.expectError(error.InvalidDibPlanes, fromDib(std.testing.allocator, &dib));
    dib[12] = 1;
    dib[32] = 1;
    try std.testing.expectError(error.UnsupportedDibPalette, fromDib(std.testing.allocator, &dib));
    dib[32] = 0;
    dib[20] = 1;
    try std.testing.expectError(error.InvalidDibImageSize, fromDib(std.testing.allocator, &dib));
}

test "clipboard image multiblock deflate and allocator failure cleanup" {
    const alloc = std.testing.allocator;
    const width = 256;
    const height = 65;
    const dib = try alloc.alloc(u8, 40 + width * height * 4);
    defer alloc.free(dib);
    @memset(dib, 0);
    const head = fixture(40, width, height, 32, 0);
    @memcpy(dib[0..40], head[0..40]);
    const png = try fromDib(alloc, dib);
    defer alloc.free(png);
    const pixels = try storedPixels(alloc, png);
    defer alloc.free(pixels);
    try std.testing.expectEqual(@as(usize, (width * 4 + 1) * height), pixels.len);
    for (0..height) |y| {
        try std.testing.expectEqual(@as(u8, 0), pixels[y * (width * 4 + 1)]);
        try std.testing.expectEqual(@as(u8, 255), pixels[y * (width * 4 + 1) + 4]);
    }
    try std.testing.checkAllAllocationFailures(alloc, allocationProbe, .{});
}

fn allocationProbe(alloc: std.mem.Allocator) !void {
    const dib = fixture(40, 1, 1, 32, 0);
    const png = try fromDib(alloc, dib[0..44]);
    defer alloc.free(png);
    try validatePng(png);
}

test "clipboard image PNG corruption truncation trailing bytes and dimensions" {
    const alloc = std.testing.allocator;
    const dib = fixture(40, 1, 1, 24, 0);
    const png = try fromDib(alloc, dib[0..44]);
    defer alloc.free(png);
    for (0..png.len) |length| try std.testing.expectError(if (length < 8) error.InvalidPngSignature else error.TruncatedPng, validatePng(png[0..length]));
    png[24] = 7;
    try std.testing.expectError(error.InvalidPngCrc, validatePng(png));
    put32(png, 29, std.hash.Crc32.hash(png[12..29]));
    try std.testing.expectError(error.InvalidPngHeader, validatePng(png));
    png[24] = 8;
    put32(png, 16, 0xffffffff);
    put32(png, 29, std.hash.Crc32.hash(png[12..29]));
    try std.testing.expectError(error.InvalidImageDimensions, validatePng(png));
    put32(png, 16, 1);
    put32(png, 29, std.hash.Crc32.hash(png[12..29]));
    const padded = try alloc.alloc(u8, png.len + 1);
    defer alloc.free(padded);
    @memcpy(padded[0..png.len], png);
    padded[png.len] = 0;
    try std.testing.expectError(error.TrailingPngData, validatePng(padded));
}

fn appendTestChunk(alloc: std.mem.Allocator, out: *std.ArrayList(u8), name: *const [4]u8, payload: []const u8) !void {
    const start = out.items.len;
    try out.resize(alloc, start + 12 + payload.len);
    put32(out.items, start, @intCast(payload.len));
    @memcpy(out.items[start + 4 ..][0..4], name);
    @memcpy(out.items[start + 8 ..][0..payload.len], payload);
    put32(out.items, start + 8 + payload.len, std.hash.Crc32.hash(out.items[start + 4 ..][0 .. payload.len + 4]));
}

test "clipboard image PNG critical chunks and chunk order" {
    const alloc = std.testing.allocator;
    const dib = fixture(40, 1, 1, 24, 0);
    const png = try fromDib(alloc, dib[0..44]);
    defer alloc.free(png);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);
    try out.appendSlice(alloc, png[0..33]);
    try appendTestChunk(alloc, &out, "ABCD", "");
    try std.testing.expectError(error.UnsupportedPngChunk, validatePng(out.items));
    out.shrinkRetainingCapacity(33);
    try appendTestChunk(alloc, &out, "IHDR", png[16..29]);
    try std.testing.expectError(error.InvalidPngHeader, validatePng(out.items));
    out.shrinkRetainingCapacity(33);
    try appendTestChunk(alloc, &out, "IDAT", "123456");
    try appendTestChunk(alloc, &out, "tEXt", "a\x00b");
    try appendTestChunk(alloc, &out, "IDAT", "123456");
    try std.testing.expectError(error.InvalidPngOrder, validatePng(out.items));
    out.shrinkRetainingCapacity(33);
    try appendTestChunk(alloc, &out, "PLTE", "xx");
    try std.testing.expectError(error.InvalidPngPalette, validatePng(out.items));
}

test "clipboard image PNG indexed palette and structural-only scope" {
    const alloc = std.testing.allocator;
    const dib = fixture(40, 1, 1, 24, 0);
    const png = try fromDib(alloc, dib[0..44]);
    defer alloc.free(png);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);
    try out.appendSlice(alloc, png[0..33]);
    out.items[24] = 1; // indexed 1-bit image
    out.items[25] = 3;
    put32(out.items, 29, std.hash.Crc32.hash(out.items[12..29]));
    try appendTestChunk(alloc, &out, "IDAT", "123456");
    try std.testing.expectError(error.InvalidPngOrder, validatePng(out.items));
    out.shrinkRetainingCapacity(33);
    try appendTestChunk(alloc, &out, "PLTE", &.{ 255, 0, 0 });
    try appendTestChunk(alloc, &out, "tRNS", &.{128});
    // Deliberately not a valid DEFLATE stream: this test documents that the
    // validator checks wire structure, not PNG decompression/pixel validity.
    try appendTestChunk(alloc, &out, "IDAT", "123456");
    try appendTestChunk(alloc, &out, "IEND", "");
    try validatePng(out.items);
}
