//! GPU-worker ONLY. Requires a current, loaded OpenGL >=4.3 context.
//! Reuses legacy pipelines/data layouts, but propagates every draw error.
//! Do not import this module into the remote-only terminal host.
const std = @import("std");
const gl = @import("opengl");
const frame = @import("TextFrame.zig");
const data = @import("../GlslData.zig");
const shaders = @import("../opengl/shaders.zig");
const Pipeline = @import("../opengl/Pipeline.zig");
const Target = @import("../opengl/Target.zig");
const Texture = @import("../opengl/Texture.zig");
const Buffer = @import("../opengl/buffer.zig").Buffer;
const ImageFrame = @import("ImageFrame.zig");
const ImageSnapshot = @import("ImageSnapshot.zig");
const ImageGpuCache = @import("ImageGpuCache.zig");

pub const Rgba = struct {
    alloc: std.mem.Allocator,
    width: u32,
    height: u32,
    // Same premultiplied RGBA8/bottom-up convention as legacy readPixelsAlloc.
    pixels: []u8,
    pub fn deinit(self: *Rgba) void {
        self.alloc.free(self.pixels);
        self.* = undefined;
    }
};

/// Owned by ONE current GPU context. Destroy before unloading GL/releasing it.
pub const Executor = struct {
    image_cache: ImageGpuCache = .{},
    programs: ?shaders.Shaders = null,
    grayscale: ?Texture = null,
    color: ?Texture = null,
    target: ?Target = null,
    targets_created: u64 = 0,
    program_sets_created: u64 = 0,
    atlas_created: u64 = 0,
    atlas_updated: u64 = 0,
    completed_frames: u64 = 0,

    pub fn deinit(self: *Executor, alloc: std.mem.Allocator) void {
        self.image_cache.deinit(alloc);
        if (self.target) |*target| target.deinit();
        if (self.grayscale) |texture| texture.deinit();
        if (self.color) |texture| texture.deinit();
        if (self.programs) |*programs| programs.deinit(alloc);
        self.grayscale = null;
        self.color = null;
        self.programs = null;
        self.target = null;
    }
    fn frameTarget(self: *Executor, width: u32, height: u32) !Target {
        if (self.target) |target| {
            if (target.width == width and target.height == height) return target;
        }
        // Stable-size frames reuse their FBO/textures. Resize allocates the
        // replacement first; failure must not acknowledge a lost target.
        const replacement = try Target.init(.{ .width = width, .height = height });
        if (self.target) |*old| old.deinit();
        self.target = replacement;
        self.targets_created += 1;
        return replacement;
    }
    fn atlas(self: *Executor, input: frame.Atlas, is_color: bool) !Texture {
        const slot = if (is_color) &self.color else &self.grayscale;
        if (slot.*) |texture| {
            if (texture.width == input.size and texture.height == input.size) {
                try texture.replaceRegion(0, 0, input.size, input.size, input.bytes);
                self.atlas_updated += 1;
                return texture;
            }
        }
        // Create the replacement first. Never destroy the old atlas then ACK a
        // failed replacement. A frame is acknowledged only after final readback.
        const replacement = try atlasTexture(input, is_color);
        if (slot.*) |old| old.deinit();
        slot.* = replacement;
        self.atlas_created += 1;
        return replacement;
    }

    pub fn render(self: *Executor, alloc: std.mem.Allocator, payload: []const u8, limits: frame.Limits, output_limit: u32) !Rgba {
        // Complete CPU validation and output budgeting precede any GPU allocations.
        const input = try frame.decode(payload, limits);
        return self.renderDecoded(alloc, input, null, output_limit);
    }

    /// Candidate GPU component only; worker transport does not accept this yet.
    pub fn renderImageFrame(self: *Executor, alloc: std.mem.Allocator, payload: []const u8, limits: ImageFrame.Limits, output_limit: u32) !Rgba {
        const input = try ImageFrame.decode(payload, limits);
        return self.renderDecoded(alloc, input.text, input.images, output_limit);
    }
    fn renderDecoded(self: *Executor, alloc: std.mem.Allocator, input: frame.Decoded, images: ?ImageSnapshot.View, output_limit: u32) !Rgba {
        if (output_limit == 0 or output_limit > 64 * 1024 * 1024) return error.InvalidOutputLimit;
        const output_bytes = @as(u64, input.width) * input.height * 4;
        if (output_bytes > output_limit) return error.OutputTooLarge;
        const api = &gl.glad.context;
        var max_texture: gl.c.GLint = 0;
        var max_rectangle: gl.c.GLint = 0;
        api.GetIntegerv.?(gl.c.GL_MAX_TEXTURE_SIZE, &max_texture);
        api.GetIntegerv.?(gl.c.GL_MAX_RECTANGLE_TEXTURE_SIZE, &max_rectangle);
        try gl.errors.getError();
        if (max_texture <= 0 or max_rectangle <= 0 or
            input.width > @as(u32, @intCast(max_texture)) or input.height > @as(u32, @intCast(max_texture)) or
            input.grayscale.size > @as(u32, @intCast(max_rectangle)) or input.color.size > @as(u32, @intCast(max_rectangle))) return error.UnsupportedDimensions;

        const background = try alloc.alloc(data.CellBg, input.background.len / 4);
        defer alloc.free(background);
        // CellBg is exactly four color bytes, not a padded native struct.
        @memcpy(std.mem.sliceAsBytes(background), input.background);
        const foreground = try alloc.alloc(data.CellText, input.foreground.len / @import("ShaderPayload.zig").cell_bytes);
        defer alloc.free(foreground);
        for (foreground, 0..) |*cell, i| cell.* = try input.cell(i);

        // Odd atlas widths must not make GL read implicit row padding past payload.
        api.PixelStorei.?(gl.c.GL_UNPACK_ALIGNMENT, 1);
        api.PixelStorei.?(gl.c.GL_PACK_ALIGNMENT, 1);
        try gl.enable(gl.c.GL_FRAMEBUFFER_SRGB);
        try gl.disable(gl.c.GL_SCISSOR_TEST);
        try gl.disable(gl.c.GL_DEPTH_TEST);
        try gl.disable(gl.c.GL_CULL_FACE);
        try gl.errors.getError();

        if (images) |view| {
            try self.image_cache.sync(alloc, view.bytes, view.limits);
        } else if (self.image_cache.entries.count() != 0) {
            self.image_cache.deinit(alloc); // A plain text snapshot has no images.
        }
        if (self.programs == null) {
            self.programs = try shaders.Shaders.init(alloc, &.{});
            self.program_sets_created += 1;
        }
        const programs = self.programs.?;
        const target = try self.frameTarget(input.width, input.height);
        const uniforms = try Buffer(data.Uniforms).initFill(.{}, &.{input.uniforms});
        defer uniforms.deinit();
        const bg = try Buffer(data.CellBg).initFill(.{}, background);
        defer bg.deinit();
        const fg = try Buffer(data.CellText).initFill(.{}, foreground);
        defer fg.deinit();
        const grayscale = try self.atlas(input.grayscale, false);
        const color = try self.atlas(input.color, true);

        {
            const binding = try target.framebuffer.bind(.framebuffer);
            defer binding.unbind();
            api.Viewport.?(0, 0, @intCast(input.width), @intCast(input.height));
            api.ClearColor.?(0, 0, 0, 0);
            api.Clear.?(gl.c.GL_COLOR_BUFFER_BIT);
            try gl.errors.getError();
        }
        // Same ordering as generic.drawFrameLocked for supported text-only frames.
        try draw(programs.pipelines.bg_color, target, uniforms.buffer, null, bg.buffer, null, null, .triangle, 3, 1);
        if (images) |view| try self.drawImages(view, .below_bg, programs.pipelines.image, target, uniforms.buffer, bg.buffer);
        try draw(programs.pipelines.cell_bg, target, uniforms.buffer, null, bg.buffer, null, null, .triangle, 3, 1);
        if (images) |view| try self.drawImages(view, .below_text, programs.pipelines.image, target, uniforms.buffer, bg.buffer);
        try draw(programs.pipelines.cell_text, target, uniforms.buffer, fg.buffer, bg.buffer, grayscale, color, .triangle_strip, 4, @intCast(foreground.len));
        if (images) |view| try self.drawImages(view, .above_text, programs.pipelines.image, target, uniforms.buffer, bg.buffer);
        const pixels = try target.readPixelsAlloc(alloc);
        errdefer alloc.free(pixels);
        gl.finish();
        try gl.errors.getError();
        if (pixels.len != output_bytes) return error.InvalidReadback;
        self.completed_frames += 1;
        return .{ .alloc = alloc, .width = input.width, .height = input.height, .pixels = pixels };
    }
    const ImageBand = enum { below_bg, below_text, above_text };
    fn drawImages(self: *Executor, view: ImageSnapshot.View, band: ImageBand, pipeline: Pipeline, target: Target, uniforms: gl.Buffer, background: gl.Buffer) !void {
        for (0..view.placement_count) |index| {
            const p = try view.placement(index);
            const actual: ImageBand = if (p.z < std.math.minInt(i32) / 2) .below_bg else if (p.z < 0) .below_text else .above_text;
            if (actual != band) continue;
            const entry = self.image_cache.entries.get(p.image_id) orelse return error.ImageNotUploaded;
            if (entry.generation != p.generation) return error.ImageNotUploaded;
            const vertex = try Buffer(data.Image).initFill(.{}, &.{.{
                .grid_pos = .{ @floatFromInt(p.x), @floatFromInt(p.y) },
                .cell_offset = .{ @floatFromInt(p.cell_offset_x), @floatFromInt(p.cell_offset_y) },
                .source_rect = .{ @floatFromInt(p.source_x), @floatFromInt(p.source_y), @floatFromInt(p.source_width), @floatFromInt(p.source_height) },
                .dest_size = .{ @floatFromInt(p.width), @floatFromInt(p.height) },
            }});
            defer vertex.deinit();
            try draw(pipeline, target, uniforms, vertex.buffer, background, entry.texture, null, .triangle_strip, 4, 1);
        }
    }
};

/// One-shot compatibility wrapper. Actual worker uses its context-owned cache.
pub fn render(alloc: std.mem.Allocator, payload: []const u8, limits: frame.Limits, output_limit: u32) !Rgba {
    var instance: Executor = .{};
    defer instance.deinit(alloc);
    return instance.render(alloc, payload, limits, output_limit);
}

fn atlasTexture(atlas: frame.Atlas, color: bool) !Texture {
    return Texture.init(.{
        .format = if (color) .bgra else .red,
        .internal_format = if (color) .srgba else .red,
        .target = .rectangle,
        .min_filter = .nearest,
        .mag_filter = .nearest,
        .wrap_s = .clamp_to_edge,
        .wrap_t = .clamp_to_edge,
    }, atlas.size, atlas.size, atlas.bytes);
}

/// Unlike legacy RenderPass.step, every bind/draw failure propagates to caller.
fn draw(pipeline: Pipeline, target: Target, uniforms: gl.Buffer, vertex: ?gl.Buffer, background: gl.Buffer, gray: ?Texture, color: ?Texture, primitive: gl.Primitive, vertices: u32, instances: u32) !void {
    if (instances == 0) return;
    const program = try pipeline.program.use();
    defer program.unbind();
    const vao = try pipeline.vao.bind();
    defer vao.unbind();
    const framebuffer = try target.framebuffer.bind(.framebuffer);
    defer framebuffer.unbind();
    _ = try uniforms.bindBase(.uniform, 1);
    _ = try background.bindBase(.storage, 1);
    if (vertex) |buffer| try vao.bindVertexBuffer(0, buffer.id, 0, @intCast(pipeline.stride));
    if (gray) |texture| {
        try gl.Texture.active(0);
        _ = try texture.texture.bind(texture.target);
    }
    if (color) |texture| {
        try gl.Texture.active(1);
        _ = try texture.texture.bind(texture.target);
    }
    if (pipeline.blending_enabled) {
        try gl.enable(gl.c.GL_BLEND);
        try gl.blendFunc(gl.c.GL_ONE, gl.c.GL_ONE_MINUS_SRC_ALPHA);
    } else try gl.disable(gl.c.GL_BLEND);
    try gl.drawArraysInstanced(primitive, 0, @intCast(vertices), @intCast(instances));
    try gl.errors.getError();
}
