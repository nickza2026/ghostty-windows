//! Built-in shader sources/CPU vertex layouts, without a GPU Pipeline import.
const std = @import("std");
const data = @import("GlslData.zig");

pub const VertexLayout = enum(u8) { none, cell_text, image, background_image };
pub const Step = enum(u8) { constant, per_vertex, per_instance };
pub const Description = struct {
    name: [:0]const u8,
    layout: VertexLayout = .none,
    vertex: [:0]const u8,
    fragment: [:0]const u8,
    step: Step = .per_vertex,
    blending: bool = true,
};
pub const full_screen_vertex = load("shaders/glsl/full_screen.v.glsl");
pub const builtin = [_]Description{
    .{ .name = "bg_color", .vertex = full_screen_vertex, .fragment = load("shaders/glsl/bg_color.f.glsl"), .blending = false },
    .{ .name = "cell_bg", .vertex = full_screen_vertex, .fragment = load("shaders/glsl/cell_bg.f.glsl") },
    .{ .name = "cell_text", .layout = .cell_text, .vertex = load("shaders/glsl/cell_text.v.glsl"), .fragment = load("shaders/glsl/cell_text.f.glsl"), .step = .per_instance },
    .{ .name = "image", .layout = .image, .vertex = load("shaders/glsl/image.v.glsl"), .fragment = load("shaders/glsl/image.f.glsl"), .step = .per_instance },
    .{ .name = "bg_image", .layout = .background_image, .vertex = load("shaders/glsl/bg_image.v.glsl"), .fragment = load("shaders/glsl/bg_image.f.glsl"), .step = .per_instance },
};

pub fn vertexAttributes(comptime layout: VertexLayout) ?type {
    return switch (layout) {
        .none => null,
        .cell_text => data.CellText,
        .image => data.Image,
        .background_image => data.BgImage,
    };
}

fn load(comptime path: []const u8) [:0]const u8 {
    return comptime includes(@embedFile(path), std.fs.path.dirname(path).?);
}
fn includes(contents: [:0]const u8, basedir: []const u8) [:0]const u8 {
    @setEvalBranchQuota(100_000);
    var i: usize = 0;
    while (i < contents.len) {
        if (std.mem.startsWith(u8, contents[i..], "#include")) {
            if (!std.mem.startsWith(u8, contents[i..], "#include \"")) @compileError("Unsupported built-in shader include");
            const start = i + "#include \"".len;
            const end = std.mem.indexOfScalarPos(u8, contents, start, '"') orelse @compileError("Unterminated built-in shader include");
            return std.fmt.comptimePrint("{s}{s}{s}", .{
                contents[0..i],
                @embedFile(basedir ++ "/" ++ contents[start..end]),
                includes(contents[end + 1 ..], basedir),
            });
        }
        if (std.mem.indexOfPos(u8, contents, i, "\n#")) |j| i = j + 1 else break;
    }
    return contents;
}

test "GLSL CPU catalog preserves builtin pipeline names and layouts" {
    try std.testing.expectEqual(@as(usize, 5), builtin.len);
    try std.testing.expectEqualStrings("bg_color", builtin[0].name);
    try std.testing.expect(!builtin[0].blending);
    try std.testing.expectEqualStrings("cell_text", builtin[2].name);
    try std.testing.expectEqual(Step.per_instance, builtin[2].step);
    try std.testing.expect(vertexAttributes(.cell_text).? == data.CellText);
    try std.testing.expect(vertexAttributes(.image).? == data.Image);
    try std.testing.expect(vertexAttributes(.background_image).? == data.BgImage);
    try std.testing.expect(vertexAttributes(.none) == null);
}

test "GLSL CPU catalog contains expanded vertex and fragment sources" {
    for (builtin) |description| {
        try std.testing.expect(description.vertex.len > 0 and description.fragment.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, description.vertex, "void main") != null);
        try std.testing.expect(std.mem.indexOf(u8, description.fragment, "void main") != null);
    }
}
