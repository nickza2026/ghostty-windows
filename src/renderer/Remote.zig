//! Opt-in CPU-only Win32 host. GPU operations belong exclusively to Session's
//! child process. Unsupported local GPU resources fail closed, never acknowledge.
const std = @import("std");
const renderer = @import("../renderer.zig");
const apprt = @import("../apprt.zig");
const configpkg = @import("../config.zig");
const Session = @import("remote/Session.zig");
const Data = @import("GlslData.zig");
const Remote = @This();
extern "kernel32" fn GetModuleHandleW([*:0]const u16) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
extern "kernel32" fn GetStdHandle(u32) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetCurrentThread() callconv(.winapi) *anyopaque;
extern "kernel32" fn QueryThreadCycleTime(*anyopaque, *u64) callconv(.winapi) i32;
pub const is_remote = true;
pub const custom_shader_y_is_down = false;
pub const ExportedFrame = @import("CpuExportedFrame.zig").Payload;
pub const Target = void;
pub const Sampler = void;
pub const RenderPass = void;
pub const Frame = void;
pub fn Buffer(comptime _: type) type {
    return void;
}
// CPU image bookkeeping can name a texture but cannot create/own one here.
pub const Texture = struct {
    width: usize,
    height: usize,
    pub fn deinit(_: @This()) void {
        @panic("remote host cannot own a local GPU texture");
    }
};
pub const shaders = struct {
    pub const Uniforms = Data.Uniforms;
    pub const CellBg = Data.CellBg;
    pub const CellText = Data.CellText;
    pub const BgImage = Data.BgImage;
    pub const Shaders = struct {
        pub const uninit: @This() = .{};
    };
};
pub const Device = struct {
    pub const Options = struct {};
    pub fn init(alloc: std.mem.Allocator, _: Options) !*Device {
        const value = try alloc.create(Device);
        value.* = .{};
        return value;
    }
    pub fn deinit(self: *Device, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }
};
var next_session: std.atomic.Value(u64) = .init(1);
session: Session,
surface: *apprt.Surface,
blending: configpkg.Config.AlphaBlending,
reported_frame: bool = false,
viewport_fixture_replies: u32 = 0,
profile_enabled: bool = false,
profile_frames: u64 = 0,
profile_capture_cycles: u64 = 0,
profile_rpc_cycles: u64 = 0,
profile_publish_cycles: u64 = 0,
profile_packet_bytes: u64 = 0,

/// Profile fixtures only. CPU cycles exclude time blocked waiting for the GPU;
/// do not convert to wall time or compare across unrelated CPU frequencies.
pub fn profileTick(self: *Remote) u64 {
    if (!self.profile_enabled) return 0;
    var cycles: u64 = 0;
    if (QueryThreadCycleTime(GetCurrentThread(), &cycles) == 0) return 0;
    return cycles;
}
pub fn profileFrame(self: *Remote, points: [4]u64, bytes: usize) void {
    if (!self.profile_enabled or points[0] == 0 or points[1] < points[0] or points[2] < points[1] or points[3] < points[2]) return;
    self.profile_capture_cycles += points[1] - points[0];
    self.profile_rpc_cycles += points[2] - points[1];
    self.profile_publish_cycles += points[3] - points[2];
    self.profile_packet_bytes += bytes;
    self.profile_frames += 1;
}

fn verifyNoGpu() !void {
    inline for (.{ "opengl32.dll", "atio6axx.dll", "amdihk64.dll" }) |name| {
        if (GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral(name)) != null) return error.GpuModuleInRemoteHost;
    }
}

pub fn init(alloc: std.mem.Allocator, _: *const Device, opts: renderer.Options) !Remote {
    try verifyNoGpu();
    if (opts.config.bg_image != null or opts.config.custom_shaders.value.items.len != 0 or opts.check_gpu_text_frames) return error.UnsupportedRemoteFeatures;
    const token = next_session.fetchAdd(1, .monotonic);
    if (token == 0 or token == std.math.maxInt(u64)) return error.SessionExhausted;
    if (comptime @import("../build_config.zig").windows_remote_images) std.log.info("remote host experimental inline image snapshot transport enabled; legacy/text-only defaults unchanged", .{});
    // Existing C transport explicitly duplicates/allowlists this single handle.
    // Diagnostic fixtures only; normal hosts still give the worker NUL stderr.
    const diagnostics: usize = if (opts.rt_surface.app.terminal_smoke) diag: {
        const handle = GetStdHandle(0xfffffff4) orelse break :diag 0;
        const value = @intFromPtr(handle);
        break :diag if (value == std.math.maxInt(usize)) 0 else value;
    } else 0;
    return .{ .session = try Session.init(alloc, .{ .surface = token, .generation = 1, .request_limit = 64 * 1024 * 1024, .output_limit = 32 * 1024 * 1024, .inline_images = @import("../build_config.zig").windows_remote_images, .diagnostics_handle = diagnostics }), .surface = opts.rt_surface, .blending = opts.config.blending, .profile_enabled = opts.rt_surface.app.fixture == .profile or opts.rt_surface.app.fixture == .profile_paced };
}
pub fn deinit(self: *Remote) void {
    if (self.session.client.handle != null) self.threadExit();
}
pub fn threadExit(self: *Remote) void {
    if (self.profile_enabled) std.log.info("remote renderer CPU phases frames={d} capture_cycles={d} rpc_cycles={d} publish_cycles={d} packet_bytes={d}; same-thread CPU cycles only, excludes blocked time/other threads/free after publish", .{ self.profile_frames, self.profile_capture_cycles, self.profile_rpc_cycles, self.profile_publish_cycles, self.profile_packet_bytes });
    verifyNoGpu() catch std.log.err("GPU module detected in remote parent at close", .{});
    if (self.session.client.handle == null) return;
    self.session.close() catch |err| {
        std.log.err("remote host worker close failed: {}", .{err});
        self.session.abort() catch std.log.err("remote host worker cleanup failed", .{});
        return;
    };
    std.log.info("remote host worker close ack=1 exit=0 jobempty=1 forced=0", .{});
}
pub fn render(self: *Remote, packet: []const u8, epoch: u64) !ExportedFrame {
    errdefer self.session.fail();
    try verifyNoGpu();
    const result = if (comptime @import("../build_config.zig").windows_remote_images)
        try self.session.renderImageFrame(packet, epoch, .{})
    else
        try self.session.render(packet, epoch, .{ .dimension = 32768, .atlas_dimension = 32768, .cells = 1024 * 1024, .bytes = 64 * 1024 * 1024 });
    errdefer result.deinit();
    if (self.surface.app.viewport_smoke) {
        self.viewport_fixture_replies += 1;
        if (self.viewport_fixture_replies == 2) {
            // Controlled fixture ONLY: keep the first queued A frame available
            // to UI, then hold this second REAL received frame outside all
            // draw/font/UI locks until UI has applied its actual window resize.
            // No RPC is pending and no child/driver thread is delayed here.
            const started = GetTickCount64();
            while (self.surface.core().renderer.remote_viewport.capture() <= epoch) {
                if (GetTickCount64() - started > 5000) return error.ViewportFixtureResizeTimeout;
                Sleep(1);
            }
            std.log.info("controlled viewport delayed real received frame until UI epoch advanced; must discard before publish", .{});
        }
    }
    try verifyNoGpu();
    if (!self.reported_frame) {
        std.log.info("remote host real frame received; parent no GL/AMD modules; worker owns GPU", .{});
        self.reported_frame = true;
    }
    return result;
}
pub fn notifyFrame(self: *Remote) !void {
    try self.surface.notifyRemoteFrame();
}
pub fn renderFailed(self: *Remote) void {
    self.session.fail();
}
