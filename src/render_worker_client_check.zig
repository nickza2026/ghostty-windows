//! Real private transport plus worker-rendered CPU text/image fixtures.
//! Does NOT prove terminal-host integration or real Kitty/legacy image parity.
const std = @import("std");
const Client = @import("renderer/remote/Client.zig");
const protocol = @import("renderer/remote/Protocol.zig");
const Session = @import("renderer/remote/Session.zig");
const TextFrame = @import("renderer/remote/TextFrame.zig");
const ImageFrame = @import("renderer/remote/ImageFrame.zig");
const ImageSnapshot = @import("renderer/remote/ImageSnapshot.zig");
const ImageResource = @import("renderer/remote/ImageResource.zig");
const w = std.os.windows;
extern "kernel32" fn GetModuleHandleW([*:0]const u16) callconv(.winapi) ?w.HANDLE;
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) w.HANDLE;
extern "kernel32" fn GetProcessHandleCount(w.HANDLE, *u32) callconv(.winapi) i32;
extern fn rw_open(u64, u64, u32, u32, u32, usize, *?*anyopaque, *Client.Status) c_int;
extern fn rw_call(*anyopaque, [*]const u8, usize, [*]u8, usize, *usize, u32, *Client.Status) c_int;
extern fn rw_finish(*anyopaque, u32, *Client.Status) c_int;
extern fn rw_destroy(*anyopaque, u32, *Client.Status) c_int;
extern fn rw_check_kill_owned(*anyopaque) c_int;
extern fn rw_check_arm_close_exit_before_wait(*anyopaque) c_int;
extern fn rw_check_arm_cancel_close_exit_before_wait(*anyopaque) c_int;
extern fn rw_check_close_exit_was_observed() c_int;
extern fn rw_check_select_late_reply_worker(c_int) void;
extern fn rw_check_late_rendered_owned(*anyopaque, *u64, *u64, *u64, [*]u8) c_int;
extern fn rw_check_pause_owned(*anyopaque) ?*anyopaque;
extern fn rw_check_resume_owned(*anyopaque) c_int;
extern fn rw_check_late_close_owned(*anyopaque) c_int;
extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;

const Raw = struct {
    handle: ?*anyopaque = null,
    surface: u64,
    status: Client.Status = .{},
    response: [128]u8 = undefined,
    received: usize = 0,
    fn init(surface: u64) !Raw {
        var self: Raw = .{ .surface = surface };
        if (rw_open(surface, 1, 2 * 1024 * 1024 + 64, 4 * 1024 * 1024 + 80, 5000, 0, &self.handle, &self.status) == 0) return error.RawOpenFailed;
        return self;
    }
    fn abort(self: *Raw) !void {
        const handle = self.handle orelse return;
        self.handle = null;
        if (rw_destroy(handle, 5000, &self.status) == 0 or self.status.process_exited == 0 or self.status.job_empty == 0) return error.RawCleanupFailed;
    }
    fn packet(self: *Raw, kind: protocol.Kind, sequence: u64, epoch: u64) ![protocol.header_bytes]u8 {
        var bytes: [protocol.header_bytes]u8 = undefined;
        _ = try protocol.encode(&bytes, .{ .kind = kind, .surface = self.surface, .generation = 1, .sequence = sequence, .epoch = epoch }, &.{}, .{ .max_payload_bytes = 2 * 1024 * 1024 });
        return bytes;
    }
    fn call(self: *Raw, bytes: []const u8) bool {
        return self.callTimeout(bytes, 5000);
    }
    fn callTimeout(self: *Raw, bytes: []const u8, timeout: u32) bool {
        return rw_call(self.handle.?, bytes.ptr, bytes.len, &self.response, self.response.len, &self.received, timeout, &self.status) != 0;
    }
    fn expect(self: *Raw, kind: protocol.Kind, sequence: u64) !void {
        const reply = try protocol.decode(self.response[0..self.received], .{ .max_payload_bytes = 80 });
        try reply.header.expectReply(kind, self.surface, 1, sequence, 0);
    }
    fn hello(self: *Raw) !void {
        const bytes = try self.packet(.hello, 1, 0);
        if (!self.call(&bytes)) return error.RawHelloFailed;
        try self.expect(.hello_ack, 1);
    }
    fn close(self: *Raw) !void {
        const bytes = try self.packet(.close, 2, 0);
        if (!self.call(&bytes)) return error.RawCloseFailed;
        try self.expect(.closed, 2);
        if (rw_finish(self.handle.?, 5000, &self.status) == 0) return error.RawFinishFailed;
        try self.abort();
        if (self.status.forced != 0 or self.status.child_exit != 0 or self.status.close_ack == 0) return error.RawUnhealthyClose;
    }
};

fn rejectedHeaders() !void {
    var raw = try Raw.init(9);
    defer raw.abort() catch @panic("header rejection cleanup failed");
    try raw.hello();
    for (0..5) |case| {
        var bytes = try raw.packet(.close, if (case == 4) 1 else 2, 0);
        switch (case) {
            0 => bytes[10] = 1, // Reserved flags.
            1 => bytes[4] = 99, // Wrong envelope version.
            2 => bytes[16] ^= 1, // Another surface.
            3 => bytes[12] = 1, // Truncated declared payload.
            4 => {}, // Replayed sequence.
            else => unreachable,
        }
        if (raw.call(&bytes) or raw.status.win_error != 13 or raw.received != 0) return error.InvalidHeaderAccepted;
    }
    // Rejected before publication: the worker remains usable, close sequence2.
    try raw.close();
}
fn rejectedWorkerCommand(handshake: bool, id: u64) !void {
    var raw = try Raw.init(id);
    defer raw.abort() catch @panic("worker rejection cleanup failed");
    if (handshake) try raw.hello();
    const bytes = try raw.packet(if (handshake) .create_buffer else .submit_frame, if (handshake) 2 else 1, if (handshake) 0 else 1);
    if (raw.call(&bytes) or raw.status.win_error != 1067) return error.WorkerRejectionNotProven; // PROCESS_ABORTED, not timeout.
    if (rw_finish(raw.handle.?, 100, &raw.status) != 0) return error.WorkerFailurePretendedHealthy;
    try raw.abort();
    if (raw.status.child_exit != 1 or raw.status.close_ack != 0 or raw.status.forced == 0) return error.InvalidWorkerFailureCleanup;
}
fn killedWorker() !void {
    var raw = try Raw.init(12);
    defer raw.abort() catch @panic("killed worker cleanup failed");
    try raw.hello();
    if (rw_check_kill_owned(raw.handle.?) == 0) return error.OwnedKillFailed;
    const bytes = try raw.packet(.close, 2, 0);
    if (raw.call(&bytes) or raw.status.win_error != 1067) return error.KilledWorkerNotDetected;
    if (rw_finish(raw.handle.?, 100, &raw.status) != 0) return error.KilledWorkerPretendedHealthy;
    try raw.abort();
    if (raw.status.child_exit != 77 or raw.status.close_ack != 0 or raw.status.forced == 0) return error.InvalidKilledWorkerCleanup;
}
fn timedOutWorker() !void {
    var raw = try Raw.init(13);
    defer raw.abort() catch @panic("timed out worker cleanup failed");
    try raw.hello();
    const thread = rw_check_pause_owned(raw.handle.?) orelse return error.OwnedPauseFailed;
    var paused = true;
    defer if (paused) {
        if (rw_check_resume_owned(thread) == 0) @panic("owned worker resume failed");
    };
    const bytes = try raw.packet(.close, 2, 0);
    const started = GetTickCount64();
    if (raw.callTimeout(&bytes, 50) or raw.status.win_error != 1460 or raw.received != 0) return error.TimeoutNotProven;
    const elapsed = GetTickCount64() - started;
    if (elapsed > 2000) return error.UnboundedTimeout;
    if (rw_finish(raw.handle.?, 100, &raw.status) != 0) return error.TimeoutPretendedHealthy;
    paused = false;
    if (rw_check_resume_owned(thread) == 0) return error.OwnedResumeFailed;
    if (rw_check_late_close_owned(raw.handle.?) == 0) return error.LateReplyNotObserved;
    // Even if the worker now emits a late closed packet, a timed-out client is
    // poisoned and must never accept that late reply as a healthy close.
    if (rw_finish(raw.handle.?, 100, &raw.status) != 0) return error.LateClosePretendedHealthy;
    try raw.abort();
    if (raw.status.forced == 0 or raw.status.close_ack != 0) return error.TimeoutCleanupNotProven;
    std.debug.print("PASS owned idle-worker timeout budget=50ms observed={d}ms; no driver threads paused; late-close never healthy; process/job reaped\n", .{elapsed});
}
fn renderedPacket(limits: TextFrame.Limits) !TextFrame.Owned {
    const data = @import("renderer/GlslData.zig");
    var uniforms = std.mem.zeroes(data.Uniforms);
    uniforms.projection_matrix = @import("math.zig").ortho2d(0, 8, 4, 0);
    uniforms.screen_size = .{ 8, 4 };
    uniforms.cell_size = .{ 4, 4 };
    uniforms.grid_size = .{ 2, 1 };
    uniforms.cursor_pos = @splat(std.math.maxInt(u16));
    const bg = [_]data.CellBg{ .{ 12, 12, 12, 255 }, .{ 1, 2, 3, 255 } };
    var fg = [_]data.CellText{.{ .glyph_size = .{ 1, 1 }, .bearings = .{ 0, 3 }, .grid_pos = .{ 0, 0 }, .color = .{ 255, 255, 255, 255 }, .atlas = .grayscale }};
    const rows = [_]TextFrame.Row{.{ .items = &fg, .capacity = fg.len }};
    return TextFrame.encodeAlloc(std.heap.page_allocator, .{ .width = 8, .height = 4, .blending = .native, .uniforms = uniforms, .background = &bg, .foreground_rows = &rows, .grayscale = .{ .size = 1, .bytes = &.{255} }, .color = .{ .size = 1, .bytes = &.{ 255, 255, 255, 255 } } }, limits);
}
fn failedSessions() !void {
    const limits = TextFrame.Limits{ .dimension = 32768, .atlas_dimension = 32768, .cells = 1024, .bytes = 2 * 1024 * 1024 };
    const baseline = try handleCount();
    for (0..4) |case| {
        var session = try Session.init(std.heap.page_allocator, .{ .surface = 14 + case, .generation = 1, .request_limit = 2 * 1024 * 1024, .output_limit = 4 * 1024 * 1024 });
        defer session.abort() catch @panic("failed session cleanup failed");
        if (case == 0) {
            if (session.render(&.{}, 1, limits)) |frame| {
                frame.deinit();
                return error.InvalidSessionFrameAccepted;
            } else |err| if (err != error.InvalidLength) return err;
        } else {
            if (case >= 2) {
                var packet = try renderedPacket(limits);
                defer packet.deinit();
                // Complete two real GPU frames before faulting: shader and
                // both atlases must be created, then reused by this live child.
                for (0..2) |_| {
                    const image = try session.render(packet.bytes, 1, limits);
                    defer image.deinit();
                    if (image.memory.width != 8 or image.memory.height != 4 or image.memory.pixels.len != 128) return error.InvalidRenderedSessionFrame;
                    var glyph = false;
                    var offset: usize = 0;
                    while (offset < image.memory.pixels.len) : (offset += 4) {
                        if (image.memory.pixels[offset] >= 240 and image.memory.pixels[offset + 1] >= 240 and image.memory.pixels[offset + 2] >= 240) glyph = true;
                    }
                    if (!glyph) return error.SessionGlyphNotDrawn;
                }
                try noGpu(); // Only the CHILD must load a graphics driver.
            }
            if (case == 3) session.client.cancel() else if (rw_check_kill_owned(@ptrCast(session.client.handle.?)) == 0) return error.SessionOwnedKillFailed;
            if (session.close()) |_| return error.KilledSessionClosedHealthy else |_| {}
            if (case != 3 and session.client.status.child_exit != 77) return error.KilledSessionExitNotReaped;
        }
        // No explicit caller abort before these assertions: production Session
        // failure handling itself must already have reaped the owned process.
        if (!session.poisoned or session.client.handle != null or session.client.status.process_exited == 0 or session.client.status.job_empty == 0 or session.client.status.forced == 0 or session.client.status.close_ack != 0) return error.FailedSessionCleanupNotProven;
        const sequence = session.client.sequence;
        if (session.render(&.{}, 1, limits)) |frame| {
            frame.deinit();
            return error.PoisonedSessionRendered;
        } else |err| if (err != error.WorkerSessionPoisoned) return err;
        if (session.close()) |_| return error.PoisonedSessionHealthyClose else |err| if (err != error.WorkerSessionPoisoned) return err;
        if (session.client.sequence != sequence) return error.PoisonedSessionSentAnotherRequest;
        if (try handleCount() != baseline) return error.FailedSessionCaseHandleGrowth;
    }
    std.debug.print("PASS failed production Session: invalid frame, idle kill77, kill77/cancel AFTER two real visible-glyph GPU frames with cached resources; auto-reap before caller cleanup; poison/no further IPC/no healthy close; parent no GL/AMD\n", .{});
}
fn imageTransport() !void {
    const baseline = try handleCount();
    {
        var plain = try Client.init(std.heap.page_allocator, .{ .surface = 40, .generation = 1, .request_limit = 2 * 1024 * 1024, .output_limit = 4 * 1024 * 1024 });
        defer plain.abort() catch @panic("plain capability cleanup failed");
        const sequence = plain.sequence;
        if (plain.renderImageFrame(&.{}, 1, .{})) |reply_value| {
            var reply = reply_value;
            reply.deinit();
            return error.UnnegotiatedImageSent;
        } else |err| if (err != error.ImageCapabilityNotNegotiated) return err;
        if (plain.sequence != sequence) return error.UnnegotiatedImageConsumedSequence;
        try plain.close();
    }
    if (try handleCount() != baseline) return error.PlainCapabilityHandleGrowth;
    {
        var raw = try Raw.init(41);
        defer raw.abort() catch @panic("unnegotiated image cleanup failed");
        try raw.hello();
        const bytes = try raw.packet(.submit_image_frame, 2, 1);
        if (raw.call(&bytes) or raw.status.win_error != 1067) return error.UnnegotiatedWorkerImageAccepted;
        if (rw_finish(raw.handle.?, 100, &raw.status) != 0) return error.UnnegotiatedImageHealthyClose;
        try raw.abort();
        if (raw.status.child_exit != 1 or raw.status.close_ack != 0 or raw.status.job_empty == 0) return error.UnnegotiatedImageFailureNotReaped;
    }
    if (try handleCount() != baseline) return error.RejectedImageHandleGrowth;
    {
        var client = try Client.init(std.heap.page_allocator, .{ .surface = 42, .generation = 1, .request_limit = 2 * 1024 * 1024, .output_limit = 4 * 1024 * 1024, .inline_images = true });
        defer client.abort() catch @panic("opt-in image cleanup failed");
        var text = try renderedPacket(.{ .dimension = 32768, .atlas_dimension = 32768, .cells = 1024, .bytes = 2 * 1024 * 1024 });
        defer text.deinit();
        for (0..2) |index| {
            var snapshot = try ImageSnapshot.encodeAlloc(std.heap.page_allocator, .{ .images = &.{.{ .id = 1, .generation = 1 + index, .width = 1, .height = 1, .rgba = if (index == 0) &.{ 255, 0, 0, 255 } else &.{ 0, 255, 0, 255 } }}, .placements = &.{.{ .image_id = 1, .generation = 1 + index, .x = 0, .y = 0, .z = 0, .width = 4, .height = 4, .source_x = 0, .source_y = 0, .source_width = 1, .source_height = 1 }}, .cell_size = .{ 4, 4 } }, .{});
            defer snapshot.deinit();
            var frame = try ImageFrame.encodeAlloc(std.heap.page_allocator, text.bytes, snapshot.bytes, .{});
            defer frame.deinit();
            var reply = try client.renderImageFrame(frame.bytes, 1, .{});
            defer reply.deinit();
            const pixels = reply.packet.payload[16..];
            var colored: u32 = 0;
            var at: usize = 0;
            while (at < pixels.len) : (at += 4) {
                const channel: usize = if (index == 0) 0 else 1;
                const other: usize = if (index == 0) 1 else 0;
                if (pixels[at + channel] >= 240 and pixels[at + other] <= 15 and pixels[at + 2] <= 15) colored += 1;
            }
            if (colored != 16) return error.RemoteImagePixelsDiffer;
            try noGpu();
        }
        try client.close();
        if (client.status.close_ack == 0 or client.status.child_exit != 0 or client.status.job_empty == 0 or client.status.forced != 0) return error.ImageSessionCloseNotHealthy;
    }
    if (try handleCount() != baseline) return error.ImageTransportHandleGrowth;
    std.debug.print("PASS opt-in image IPC: unchanged empty/text hello; unnegotiated local no-send and raw worker rejection; negotiated red/green images composited exact16pixels; healthy natural close/jobempty/handles0; parent no GL/AMD. Not real terminal Kitty parity.\n", .{});
}
fn imagePacket(text: []const u8, generation: u64, rgba: [4]u8) !ImageResource.Owned {
    var snapshot = try ImageSnapshot.encodeAlloc(std.heap.page_allocator, .{ .images = &.{.{ .id = 1, .generation = generation, .width = 1, .height = 1, .rgba = &rgba }}, .placements = &.{.{ .image_id = 1, .generation = generation, .x = 0, .y = 0, .z = 0, .width = 4, .height = 4, .source_x = 0, .source_y = 0, .source_width = 1, .source_height = 1 }}, .cell_size = .{ 4, 4 } }, .{});
    defer snapshot.deinit();
    return ImageFrame.encodeAlloc(std.heap.page_allocator, text, snapshot.bytes, .{});
}
fn imageSessions() !void {
    const baseline = try handleCount();
    var text = try renderedPacket(.{ .dimension = 32768, .atlas_dimension = 32768, .cells = 1024, .bytes = 2 * 1024 * 1024 });
    defer text.deinit();
    for (0..5) |case| {
        var session = try Session.init(std.heap.page_allocator, .{ .surface = 50 + case, .generation = 1, .request_limit = 2 * 1024 * 1024, .output_limit = 4 * 1024 * 1024, .inline_images = true });
        defer session.abort() catch @panic("image Session cleanup failed");
        var retained: ?@import("renderer/CpuExportedFrame.zig").Payload = null;
        defer if (retained) |image| image.deinit();
        var retained_reference: [128]u8 = undefined;
        for (0..2) |index| {
            var packet = try imagePacket(text.bytes, 1 + index, if (index == 0) .{ 255, 0, 0, 255 } else .{ 0, 255, 0, 255 });
            defer packet.deinit();
            const image = try session.renderImageFrame(packet.bytes, 2, .{});
            if (index == 0) retained = image;
            defer if (index != 0) image.deinit();
            const pixels = image.memory.pixels;
            if (image.memory.width != 8 or image.memory.height != 4 or pixels.len != 128) return error.ImageSessionInvalidCpuFrame;
            if (image.memory.backing == null or image.memory.backing.?.ptr == pixels.ptr) return error.PrivateReplyBackingNotTransferred;
            if (index == 0) @memcpy(&retained_reference, pixels);
            var colored: u32 = 0;
            var at: usize = 0;
            while (at < pixels.len) : (at += 4) {
                const channel: usize = if (index == 0) 0 else 1;
                const other: usize = if (index == 0) 1 else 0;
                if (pixels[at + channel] >= 240 and pixels[at + other] <= 15 and pixels[at + 2] <= 15) colored += 1;
            }
            if (colored != 16) return error.ImageSessionCompositedPixelsDiffer;
        }
        try noGpu();
        if (case == 4) {
            try session.close();
            if (session.poisoned or session.client.handle != null or session.client.status.close_ack == 0 or session.client.status.child_exit != 0 or session.client.status.job_empty == 0 or session.client.status.forced != 0) return error.ImageSessionHealthyCloseFailed;
        } else {
            if (case >= 2) {
                var packet = try imagePacket(text.bytes, if (case == 3) 1 else 3, .{ 255, 0, 0, 255 });
                defer packet.deinit();
                const sequence = session.client.sequence;
                if (session.renderImageFrame(packet.bytes, if (case == 2) 1 else 2, .{})) |image| {
                    image.deinit();
                    return error.StaleImageSessionFrameAccepted;
                } else |err| {
                    if (case == 2 and err != error.StaleViewportEpoch) return err;
                    if (case == 3 and err != error.WorkerCommunicationFailed) return err;
                }
                if (case == 2 and session.client.sequence != sequence) return error.StaleImageEpochSentIpc;
                if (case == 3 and (session.client.status.child_exit != 1 or session.client.status.win_error != 1067)) return error.WorkerImageGenerationFailureNotProven;
            } else {
                if (case == 0) {
                    if (rw_check_kill_owned(@ptrCast(session.client.handle.?)) == 0) return error.ImageSessionOwnedKillFailed;
                } else session.client.cancel();
                if (session.close()) |_| return error.FailedImageSessionClosedHealthy else |_| {}
                if (case == 0 and session.client.status.child_exit != 77) return error.ImageSessionKillExitNotReaped;
            }
            if (!session.poisoned or session.client.handle != null or session.client.status.process_exited == 0 or session.client.status.job_empty == 0 or session.client.status.close_ack != 0 or session.client.status.forced == 0) return error.ImageSessionFailureNotReaped;
            const sequence = session.client.sequence;
            if (session.renderImageFrame(&.{}, 2, .{})) |image| {
                image.deinit();
                return error.PoisonedImageSessionRendered;
            } else |err| if (err != error.WorkerSessionPoisoned) return err;
            if (session.close()) |_| return error.PoisonedImageSessionClosedHealthy else |err| if (err != error.WorkerSessionPoisoned) return err;
            if (session.client.sequence != sequence) return error.PoisonedImageSessionSentIpc;
        }
        if (!std.mem.eql(u8, &retained_reference, retained.?.memory.pixels)) return error.RetainedFrameChangedAfterNextReplyAndReap;
        if (try handleCount() != baseline) return error.ImageSessionCaseHandleGrowth;
    }
    std.debug.print("PASS production image Sessions: two actual red-green composited frames BEFORE kill77/cancel/local stale epoch/peer stale image generation; auto-reap+poison/no further IPC/no healthy close; separate natural close healthy; per-case handles0/no parent GL. No terminal Kitty parity.\n", .{});
    std.debug.print("PASS retained CPU frame owns private reply base; first red pixels unchanged after green reply and all five natural/failure reaps; no shared-map borrow or duplicate pixel allocation.\n", .{});
}

fn noGpu() !void {
    inline for (.{ "opengl32.dll", "atio6axx.dll", "amdihk64.dll" }) |name| {
        if (GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral(name)) != null) return error.GpuModuleInParent;
    }
}
fn handleCount() !u32 {
    var n: u32 = 0;
    if (GetProcessHandleCount(GetCurrentProcess(), &n) == 0) return error.HandleCountFailed;
    return n;
}
fn cycle(id: u64) !void {
    var client = try Client.init(std.heap.page_allocator, .{ .surface = id, .generation = 1, .request_limit = 2 * 1024 * 1024, .output_limit = 4 * 1024 * 1024 });
    defer client.abort() catch @panic("owned GPU worker cleanup failed");
    try noGpu();
    try client.close();
    if (client.status.forced != 0 or client.status.close_ack == 0 or client.status.process_exited == 0 or client.status.job_empty == 0 or client.status.child_exit != 0) return error.UnhealthyClose;
}
fn lateRenderedReply() !void {
    const baseline = try handleCount();
    rw_check_select_late_reply_worker(1);
    var client = Client.init(std.heap.page_allocator, .{ .surface = 90, .generation = 1, .request_limit = 2 * 1024 * 1024, .output_limit = 4 * 1024 * 1024 }) catch |err| {
        rw_check_select_late_reply_worker(0);
        return err;
    };
    rw_check_select_late_reply_worker(0);
    defer {
        client.timeout_ms = 5000; // Cleanup budget, not the failed 50ms RPC.
        client.abort() catch @panic("late rendered reply cleanup failed");
    }
    const limits: TextFrame.Limits = .{ .dimension = 32768, .atlas_dimension = 32768, .cells = 1024, .bytes = 2 * 1024 * 1024 };
    var packet = try renderedPacket(limits);
    defer packet.deinit();
    var reference: [128]u8 = undefined;
    for (0..2) |index| {
        var reply = try client.render(packet.bytes, 1, limits);
        defer reply.deinit();
        if (reply.packet.payload[16..].len != reference.len) return error.LateFixtureDimensionsWrong;
        if (index == 0) @memcpy(&reference, reply.packet.payload[16..]) else if (!std.mem.eql(u8, &reference, reply.packet.payload[16..])) return error.LateFixtureWarmPixelsChanged;
    }
    client.timeout_ms = 50;
    const started = GetTickCount64();
    if (client.render(packet.bytes, 1, limits)) |value| {
        var reply = value;
        reply.deinit();
        return error.LateRenderedReplyAccepted;
    } else |err| if (err != error.WorkerCommunicationFailed) return err;
    if (client.status.win_error != 1460) return error.LateRenderedDeadlineNotObserved;
    var rendered: u64 = 0;
    var published: u64 = 0;
    var sequence: u64 = 0;
    var pixels: [128]u8 = undefined;
    if (rw_check_late_rendered_owned(@ptrCast(client.handle.?), &rendered, &published, &sequence, &pixels) == 0) return error.ActualLateRenderedReplyNotProven;
    if (rendered < started or rendered - started >= 50 or published < started + 50 or sequence != client.sequence or !std.mem.eql(u8, &reference, &pixels)) return error.LateRenderedPixelsOrTimingMismatch;
    if (client.close()) |_| return error.LateRenderedClosePretendedHealthy else |err| if (err != error.WorkerCommunicationFailed) return err;
    client.timeout_ms = 5000;
    try client.abort();
    try client.abort();
    const after = try handleCount();
    std.debug.print("late-rendered cleanup receipt ack={d} exited={d} child={d} jobempty={d} forced={d} handles={d}->{d}\n", .{ client.status.close_ack, client.status.process_exited, client.status.child_exit, client.status.job_empty, client.status.forced, baseline, after });
    if (client.status.close_ack != 0 or client.status.process_exited == 0 or client.status.job_empty == 0 or client.status.forced == 0 or after != baseline) {
        std.debug.print("late-rendered cleanup diagnostic ack={d} exited={d} child={d} jobempty={d} forced={d} handles={d}->{d} rendered=+{d}ms published=+{d}ms\n", .{ client.status.close_ack, client.status.process_exited, client.status.child_exit, client.status.job_empty, client.status.forced, baseline, after, rendered - started, published - started });
        return error.LateRenderedCleanupFailed;
    }
    try noGpu();
    std.debug.print("PASS real GPU readback before50ms deadline at+{d}ms; identical128RGBA bytes published late at+{d}ms and never accepted/closed healthy; owned reap/handles0. Separate test worker CPU delay AFTER GPU finish; NOT GPU-busy/driver-hang proof.\n", .{ rendered - started, published - started });
}

pub fn main() !void {
    try noGpu();
    std.debug.print("render worker private transport checks begin; no pixel/host readiness claim\n", .{});
    try cycle(1); // Explicit initialization warmup, not a measured leak sample.
    const baseline = try handleCount();
    for (2..7) |i| {
        try cycle(i);
        const after = try handleCount();
        if (after != baseline) {
            std.debug.print("parent handle mismatch before={d} after={d}\n", .{ baseline, after });
            return error.ParentHandleGrowth;
        }
    }
    var cancelled = try Client.init(std.heap.page_allocator, .{ .surface = 8, .generation = 1, .request_limit = 2 * 1024 * 1024, .output_limit = 4 * 1024 * 1024 });
    defer cancelled.abort() catch @panic("cancelled worker cleanup failed");
    cancelled.cancel();
    if (cancelled.close()) |_| return error.CancelPretendedHealthy else |_| {}
    try cancelled.abort();
    if (cancelled.status.forced == 0 or cancelled.status.process_exited == 0 or cancelled.status.job_empty == 0) return error.CancelCleanupNotProven;
    if (try handleCount() != baseline) return error.CancelHandleGrowth;
    try rejectedHeaders();
    if (try handleCount() != baseline) return error.HeaderRejectionHandleGrowth;
    try rejectedWorkerCommand(false, 10);
    if (try handleCount() != baseline) return error.HandshakeFailureHandleGrowth;
    try rejectedWorkerCommand(true, 11);
    if (try handleCount() != baseline) return error.UnsupportedCommandHandleGrowth;
    try killedWorker();
    if (try handleCount() != baseline) return error.KilledWorkerHandleGrowth;
    try timedOutWorker();
    if (try handleCount() != baseline) return error.TimeoutHandleGrowth;
    try failedSessions();
    if (try handleCount() != baseline) return error.FailedSessionHandleGrowth;
    try imageTransport();
    if (try handleCount() != baseline) return error.ImageTransportSuiteHandleGrowth;
    try imageSessions();
    if (try handleCount() != baseline) return error.ImageSessionSuiteHandleGrowth;
    try noGpu();
    std.debug.print("PASS negative transport: 5 malformed/replayed headers; submit before hello; unsupported resource command never ACKed; owned worker exit77 detected; idle timeout+actual late closed reply rejected; every case exit/jobempty/handle delta0. GPU-busy hang/late rendered frame/resize not yet covered.\n", .{});
    std.debug.print("PASS private GPU transport: hello/closed+exit0+jobempty 6 cycles; 5 measured handle deltas=0; cancel never healthy; parent no GL/AMD modules. No render/terminal-host proof.\n", .{});
    const before_close_race = try handleCount();
    var race = try Client.init(std.heap.page_allocator, .{ .surface = 70, .generation = 1, .request_limit = 2 * 1024 * 1024, .output_limit = 4 * 1024 * 1024 });
    defer race.abort() catch @panic("close race cleanup failed");
    if (rw_check_arm_close_exit_before_wait(@ptrCast(race.handle.?)) == 0) return error.CloseRaceHookNotOwned;
    race.close() catch |err| {
        if (rw_check_close_exit_was_observed() != 1) return error.CloseRaceNotObserved;
        try race.abort();
        if (try handleCount() != before_close_race) return error.CloseRaceHandleGrowth;
        std.debug.print("REPRODUCED close response race: real closed notification+natural process exit before parent wait; production rejected with {s}; handles0; no driver pause or budget extension. Separate from historical WorkerCloseFailed.\n", .{@errorName(err)});
        return err;
    };
    if (rw_check_close_exit_was_observed() != 1 or race.status.child_exit != 0 or race.status.close_ack == 0 or race.status.job_empty == 0 or race.status.forced != 0 or try handleCount() != before_close_race) return error.CloseRaceHealthyReceiptMissing;
    std.debug.print("PASS real closed reply+process exit simultaneously ready; natural exit/jobempty/handles0 and normal deadline, parent no GPU.\n", .{});
    var stop_race = try Client.init(std.heap.page_allocator, .{ .surface = 71, .generation = 1, .request_limit = 2 * 1024 * 1024, .output_limit = 4 * 1024 * 1024 });
    defer stop_race.abort() catch @panic("cancel close race cleanup failed");
    if (rw_check_arm_cancel_close_exit_before_wait(@ptrCast(stop_race.handle.?)) == 0) return error.CancelCloseRaceHookNotOwned;
    if (stop_race.close()) |_| return error.CancelCloseRacePretendedHealthy else |err| if (err != error.WorkerCommunicationFailed) return err;
    if (rw_check_close_exit_was_observed() != 1 or stop_race.status.win_error != 1223 or stop_race.status.close_ack != 0) return error.CancelCloseRacePriorityNotProven;
    try stop_race.abort();
    if (stop_race.status.process_exited == 0 or stop_race.status.job_empty == 0 or stop_race.status.forced == 0 or try handleCount() != before_close_race) return error.CancelCloseRaceCleanupFailed;
    try noGpu();
    std.debug.print("PASS simultaneous stop+natural process exit+real closed notification: cancel wins, no healthy ACK, owned reap/handles0; no deadline extension.\n", .{});
    for (0..3) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.heap.page_allocator, .{ .fail_index = fail_index });
        if (Client.init(failing.allocator(), .{ .surface = 80 + fail_index, .generation = 1, .request_limit = 2 * 1024 * 1024, .output_limit = 4 * 1024 * 1024 })) |value| {
            var owned = value;
            defer owned.abort() catch @panic("scratch OOM cleanup failed");
            if (fail_index != 2) return error.ExpectedInitScratchOom;
            if (owned.close()) |_| return error.ExpectedCloseReplyOom else |err| if (err != error.OutOfMemory) return err;
            if (owned.request_buffer.bytes.len != 0) return error.CloseOomRetainedScratch;
            try owned.abort();
            try owned.abort();
        } else |err| {
            if (fail_index == 2 or err != error.OutOfMemory) return err;
        }
        if (failing.allocated_bytes != failing.freed_bytes or try handleCount() != before_close_race) return error.ScratchOomAllocationOrHandleLeak;
    }
    std.debug.print("PASS request scratch init/request/reply/close OOM cleanup and repeated abort: allocated bytes balanced, handles0; response frames independently owned.\n", .{});
    try lateRenderedReply();
}
