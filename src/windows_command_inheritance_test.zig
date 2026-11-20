//! Test-only production Command.start ConPTY regression.
//! ClosePseudoConsole is a synchronous Win32 API assumption, not a cancellable
//! operation. Keep draining throughout close. The parent must watchdog the entire
//! test invocation; timeout/forced process-tree cleanup is FAILURE, never a pass.
const std = @import("std");
const Command = @import("Command.zig");
const w = @import("os/windows.zig");
const H = std.os.windows.HANDLE;
const Atomic = std.atomic.Value(bool);

// Win32 ABI: BOOL is signed 32-bit, DWORD unsigned 32-bit, handles pointer-sized.
const Native = struct {
    const Security = extern struct { length: u32 = @sizeOf(Security), descriptor: ?*anyopaque = null, inherit: i32 = 1 };
    extern "kernel32" fn CreatePipe(*H, *H, ?*const Security, u32) callconv(.winapi) i32;
    extern "kernel32" fn CreateEventW(?*const Security, i32, i32, ?[*:0]const u16) callconv(.winapi) ?H;
    extern "kernel32" fn CloseHandle(H) callconv(.winapi) i32;
    extern "kernel32" fn GetCurrentProcess() callconv(.winapi) H;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
    extern "kernel32" fn GetFullPathNameW([*:0]const u16, u32, [*]u16, ?*anyopaque) callconv(.winapi) u32;
    extern "kernel32" fn GetModuleHandleW([*:0]const u16) callconv(.winapi) ?H;
    extern "kernel32" fn GetProcAddress(H, [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn DuplicateHandle(H, H, H, *H, u32, i32, u32) callconv(.winapi) i32;
    extern "kernel32" fn PeekNamedPipe(H, ?*anyopaque, u32, ?*u32, ?*u32, ?*u32) callconv(.winapi) i32;
    extern "kernel32" fn ReadFile(H, [*]u8, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn WriteFile(H, [*]const u8, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn CreateThread(?*anyopaque, usize, *const fn (?*anyopaque) callconv(.winapi) u32, ?*anyopaque, u32, ?*u32) callconv(.winapi) ?H;
    extern "kernel32" fn WaitForSingleObject(H, u32) callconv(.winapi) u32;
    extern "kernel32" fn GetExitCodeProcess(H, *u32) callconv(.winapi) i32;
    extern "kernel32" fn TerminateProcess(H, u32) callconv(.winapi) i32;
    extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
    extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
};

fn close(handle: *?H) void {
    if (handle.*) |h| {
        if (Native.CloseHandle(h) == 0) @panic("private ConPTY fixture CloseHandle failed");
        handle.* = null;
    }
}

const Drain = struct {
    pipe: H,
    stop: Atomic = .init(false),
    ready: Atomic = .init(false),
    ack: Atomic = .init(false),
    failed: Atomic = .init(false),

    fn thread(raw: ?*anyopaque) callconv(.winapi) u32 {
        const self: *Drain = @ptrCast(@alignCast(raw.?));
        var transcript: [16384]u8 = undefined;
        var used: usize = 0;
        const deadline = Native.GetTickCount64() + 60000;
        while (!self.stop.load(.acquire)) {
            if (Native.GetTickCount64() >= deadline) {
                self.failed.store(true, .release);
                return 1;
            }
            var available: u32 = 0;
            if (Native.PeekNamedPipe(self.pipe, null, 0, null, &available, null) == 0) {
                if (Native.GetLastError() != 109) self.failed.store(true, .release); // ERROR_BROKEN_PIPE
                return 0;
            }
            if (available == 0) {
                Native.Sleep(1);
                continue;
            }
            var bytes: [512]u8 = undefined;
            var read: u32 = 0;
            if (Native.ReadFile(self.pipe, &bytes, @min(available, bytes.len), &read, null) == 0 or read == 0) {
                self.failed.store(true, .release);
                return 1;
            }
            // Bounded storage; on overflow fail but keep draining for safe close.
            if (used + read > transcript.len) {
                self.failed.store(true, .release);
                continue;
            }
            @memcpy(transcript[used..][0..read], bytes[0..read]);
            used += read;
            if (std.mem.indexOf(u8, transcript[0..used], "READY") != null) self.ready.store(true, .release);
            if (std.mem.indexOf(u8, transcript[0..used], "ACK:CANARY-PING") != null) self.ack.store(true, .release);
        }
        return 0;
    }

    fn await(self: *Drain, flag: *Atomic) !void {
        const deadline = Native.GetTickCount64() + 5000;
        while (!flag.load(.acquire)) {
            if (self.failed.load(.acquire)) return error.ConPTYDrainFailed;
            if (Native.GetTickCount64() >= deadline) return error.ConPTYProtocolTimeout;
            Native.Sleep(1);
        }
    }
};

const Fixture = struct {
    input_read: ?H = null,
    input_write: ?H = null,
    output_read: ?H = null,
    output_write: ?H = null,
    pc: ?w.HPCON = null,
    canary: ?H = null,
    thread: ?H = null,
    drain: Drain = undefined,
    command: Command,
    exited: bool = false,

    fn cleanup(self: *Fixture) !void {
        var forced = false;
        if (self.command.pid) |child| {
            if (!self.exited) {
                // Only the process owned by this production Command instance.
                if (Native.WaitForSingleObject(child, 0) != 0) {
                    forced = true;
                    if (Native.TerminateProcess(child, 99) == 0) @panic("private child termination failed");
                }
                if (Native.WaitForSingleObject(child, 5000) != 0) @panic("private child shutdown unconfirmed");
            }
            self.command.deinit();
        }
        close(&self.input_write);
        if (self.pc) |pc| {
            // Explicit API assumption: synchronous close with the drainer active.
            // No timed closer thread and no unsafe thread termination.
            w.exp.kernel32.ClosePseudoConsole(pc);
            self.pc = null;
        }
        close(&self.input_read);
        close(&self.output_write);
        if (self.thread) |thread| {
            self.drain.stop.store(true, .release);
            if (Native.WaitForSingleObject(thread, 5000) != 0) @panic("private ConPTY drainer join failed");
            close(&self.thread);
        }
        close(&self.output_read);
        close(&self.canary);
        if (forced) return error.ConPTYForcedChildCleanup;
        if (self.drain.failed.load(.acquire)) return error.ConPTYDrainFailed;
    }
};

pub const AttributeCase = enum { success, before_initialize, after_initialize, after_update, launch_failure };

pub fn run() !void {
    try runCase(null);
}

pub fn runAttributes(case: AttributeCase) !void {
    try runCase(case);
}

fn expectAttributeReceipt(case: AttributeCase) !void {
    const r = Command.WindowsAttributeListTest.receipt;
    const initialized: usize = if (case == .before_initialize) 0 else 1;
    const updated: usize = switch (case) {
        .success, .after_update, .launch_failure => 1,
        else => 0,
    };
    const creates: usize = if (case == .success or case == .launch_failure) 1 else 0;
    std.debug.print("COMMAND_ATTRIBUTES case={s} init={d} update={d} create={d} delete={d} deleted_before_create={d} cleanup=healthy\n", .{ @tagName(case), r.initialized, r.updated, r.create_attempts, r.deleted, r.deleted_before_create });
    try std.testing.expectEqual(initialized, r.initialized);
    try std.testing.expectEqual(updated, r.updated);
    try std.testing.expectEqual(creates, r.create_attempts);
    try std.testing.expectEqual(@as(usize, 0), r.deleted_before_create);
    try std.testing.expectEqual(initialized, r.deleted);
}

fn runCase(attribute_case: ?AttributeCase) !void {
    Command.WindowsAttributeListTest.reset();
    defer Command.WindowsAttributeListTest.reset();
    if (attribute_case) |case| Command.WindowsAttributeListTest.failure = switch (case) {
        .before_initialize => .before_initialize,
        .after_initialize => .after_initialize,
        .after_update => .after_update,
        else => .none,
    };
    // Microsoft documents this Windows 10+ API in Kernelbase.dll, not Kernel32.
    // Borrow the already-loaded system module: no DLL search/load or fallback.
    // A missing comparison API fails the test; it never means canary absence.
    const kernelbase = Native.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("kernelbase.dll")) orelse return error.ConPTYCompareModuleMissing;
    const compare_objects: *const fn (H, H) callconv(.winapi) i32 = @ptrCast(Native.GetProcAddress(kernelbase, "CompareObjectHandles") orelse return error.ConPTYCompareApiMissing);
    // addOptionPath may emit a build-root-relative cache path. Resolve that
    // generated dependency before spawning; never search PATH for the helper.
    const dependency_w = try std.unicode.utf8ToUtf16LeAllocZ(std.testing.allocator, @import("windows_command_inheritance_options").child_path);
    defer std.testing.allocator.free(dependency_w);
    var full_path: [32768]u16 = undefined;
    const full_length = Native.GetFullPathNameW(dependency_w.ptr, full_path.len, &full_path, null);
    if (full_length == 0 or full_length >= full_path.len) return error.ConPTYHelperPathFailed;
    const path = try std.unicode.utf16LeToUtf8AllocZ(std.testing.allocator, full_path[0..full_length]);
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.fs.path.isAbsolute(path));
    var fixture: Fixture = .{ .command = .{
        .path = path,
        .args = &.{path},
        .os_pre_exec = null,
        .rt_pre_exec = null,
        .rt_post_fork = null,
        .rt_pre_exec_info = undefined,
        .rt_post_fork_info = undefined,
    } };
    // Initialize even before thread creation, so partial-init cleanup is valid.
    fixture.drain = .{ .pipe = undefined };
    var cleaned = false;
    defer if (!cleaned) fixture.cleanup() catch |err| {
        std.debug.panic("private ConPTY failure cleanup: {s}", .{@errorName(err)});
    };

    var read: H = undefined;
    var write: H = undefined;
    // NULL security attributes create NON-inheritable fixture pipes.
    if (Native.CreatePipe(&read, &write, null, 4096) == 0) return error.ConPTYPipeFailed;
    fixture.input_read = read;
    fixture.input_write = write;
    if (Native.CreatePipe(&read, &write, null, 4096) == 0) return error.ConPTYPipeFailed;
    fixture.output_read = read;
    fixture.output_write = write;
    fixture.drain.pipe = read;
    fixture.thread = Native.CreateThread(null, 0, Drain.thread, &fixture.drain, 0, null) orelse return error.ConPTYThreadFailed;
    var pc: w.HPCON = undefined;
    if (w.exp.kernel32.CreatePseudoConsole(.{ .X = 80, .Y = 24 }, fixture.input_read.?, fixture.output_write.?, 0, &pc) != 0)
        return error.ConPTYCreateFailed;
    fixture.pc = pc;
    close(&fixture.input_read);
    close(&fixture.output_write);

    // Deliberately AFTER ConPTY creation: only this private canary is inheritable.
    const security: Native.Security = .{};
    fixture.canary = Native.CreateEventW(&security, 1, 0, null) orelse return error.ConPTYCanaryFailed;
    fixture.command.pseudo_console = pc;
    if (attribute_case) |case| {
        if (case != .success) {
            // No filesystem guess or shell: this drive token is syntactically
            // invalid. Set args[0] too, since Command prefers args over path.
            if (case == .launch_failure) {
                fixture.command.path = "?:\\localterm-attribute-invalid.exe";
                fixture.command.args = &.{"?:\\localterm-attribute-invalid.exe"};
            }
            const expected: anyerror = switch (case) {
                .before_initialize => error.TestAttributeBeforeInitialize,
                .after_initialize => error.TestAttributeAfterInitialize,
                .after_update => error.TestAttributeAfterUpdate,
                .launch_failure => error.Unexpected,
                .success => unreachable,
            };
            try std.testing.expectError(expected, fixture.command.start(std.testing.allocator));
            try std.testing.expect(fixture.command.pid == null);
            cleaned = true;
            try fixture.cleanup();
            try expectAttributeReceipt(case);
            return;
        }
    }
    try fixture.command.start(std.testing.allocator);
    try fixture.drain.await(&fixture.drain.ready);

    // Probe only our child's designated numeric slot. Never CLOSE_SOURCE; never
    // enumerate handles. Object identity prevents numeric handle reuse false reds.
    var inherited_same_object = false;
    var duplicate: H = undefined;
    if (Native.DuplicateHandle(fixture.command.pid.?, fixture.canary.?, Native.GetCurrentProcess(), &duplicate, 0, 0, 2) != 0) {
        var local: ?H = duplicate;
        defer close(&local);
        inherited_same_object = compare_objects(duplicate, fixture.canary.?) != 0;
    } else if (Native.GetLastError() != 6) { // Only ERROR_INVALID_HANDLE means absence.
        return error.ConPTYCanaryProbeFailed;
    }

    const input = "CANARY-PING\r";
    var written: u32 = 0;
    if (Native.WriteFile(fixture.input_write.?, input, input.len, &written, null) == 0 or written != input.len)
        return error.ConPTYInputFailed;
    try fixture.drain.await(&fixture.drain.ack);
    if (Native.WaitForSingleObject(fixture.command.pid.?, 5000) != 0) return error.ConPTYChildExitTimeout;
    fixture.exited = true;
    var code: u32 = undefined;
    if (Native.GetExitCodeProcess(fixture.command.pid.?, &code) == 0) return error.ConPTYExitCodeFailed;
    try std.testing.expectEqual(@as(u32, 0), code);

    // Isolation is evaluated ONLY after protocol, exit 0, and clean owned teardown.
    cleaned = true;
    try fixture.cleanup();
    std.debug.print("COMMAND_INHERITANCE ready=1 ack=1 child_exit=0 cleanup=healthy inherited_canary={d}\n", .{@intFromBool(inherited_same_object)});
    try std.testing.expect(!inherited_same_object);
    if (attribute_case) |case| try expectAttributeReceipt(case);
}
