//! Owned, offscreen PSReadLine arrow/edit regression; no live user input.
const std = @import("std");
const global = @import("../../global.zig");
const Terminal = @import("../../terminal/main.zig").Terminal;

pub const prompt = "ML> ";
pub const suffix = "dawdawdawdaw";
pub const inserted = "a" ** 32;
pub const prefixes = [_][]const u8{ "ABCD EFGH IJKL ", "เก้า เก่ง กำลัง " };
pub const State = struct { checked: u8 = 0, failures: u8 = 0, awaiting: bool = false, module_verified: bool = false };

// Import only the installed system module; isolate its history before import.
// F12 emits an ordered OSC title AFTER ReadLine's repaint, without moving the
// cursor. It carries synthetic buffer/offset evidence, not user/session data.
pub const command =
    "$d=Join-Path $env:LOCALAPPDATA ('Letta\\build-logs\\ghostty-windows\\midline-shell\\'+[Guid]::NewGuid().ToString('N')); " ++
    "[IO.Directory]::CreateDirectory($d)|Out-Null; $env:APPDATA=$d; " ++
    "$m=$env:LOCALTERM_MIDLINE_MODULE; if(-not $m){$m=Join-Path $env:ProgramFiles 'WindowsPowerShell\\Modules\\PSReadLine\\2.0.0\\PSReadLine.psd1'}; " ++
    "$loaded=Import-Module -Name $m -PassThru -ErrorAction Stop; " ++
    "$assembly=[Microsoft.PowerShell.PSConsoleReadLine].Assembly; " ++
    "$base=[IO.Path]::GetFullPath((Split-Path -Parent $m)).TrimEnd('\\')+'\\'; " ++
    "if(-not $assembly.Location.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Selected PSReadLine assembly was not loaded'}; " ++
    "$moduleHash=(Get-FileHash -LiteralPath $assembly.Location -Algorithm SHA256).Hash; " ++
    "[Console]::Write(([char]27).ToString()+']0;MIDLINE_MODULE|'+$loaded.Version+'|'+$moduleHash+[char]7); " ++
    "Set-PSReadLineOption -HistorySaveStyle SaveNothing -HistorySavePath (Join-Path $d 'history.txt') -EditMode Windows; " ++
    "Set-PSReadLineKeyHandler -Key F11 -ScriptBlock { " ++
    "[Microsoft.PowerShell.PSConsoleReadLine]::RevertLine($null,$null); $z='';$n=0; " ++
    "[Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$z,[ref]$n); " ++
    "if($z.Length -ne 0){throw 'Synthetic line was not cleared'}; " ++
    "[Console]::Write(([char]27).ToString()+']0;MIDLINE_READY'+[char]7) }; " ++
    "Set-PSReadLineKeyHandler -Key F12 -ScriptBlock { " ++
    "$b='';$c=0;[Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$b,[ref]$c); " ++
    "$s=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($b)); " ++
    "[Console]::Write(([char]27).ToString()+']0;MIDLINE_CHECK|'+$c+'|'+[Console]::CursorLeft+'|'+$s+[char]7) }; " ++
    "function global:prompt { [Console]::Write(([char]27).ToString()+']0;MIDLINE_READY'+[char]7); 'ML> ' }; " ++
    "[Console]::Clear();[Console]::WriteLine('LOCALTERM_RENDER_SMOKE'); " ++
    "[Console]::WriteLine(([char]27).ToString()+'[31mRED'+[char]27+'[0m ไทย'); " ++
    "[Console]::WriteLine('MIDLINE_PSREADLINE_VERSION='+ (Get-Module PSReadLine).Version)";

// Caller holds the real terminal mutex. Compare complete visible row cells AND
// caret; a final-cursor-only check can miss ConPTY Thai cell corruption.
pub fn capture(state: *State, actual: *Terminal, alloc: std.mem.Allocator, title: []const u8) !void {
    if (state.checked >= prefixes.len or !state.awaiting) return error.MidlineUnexpectedBarrier;
    var parts = std.mem.splitScalar(u8, title, '|');
    if (!std.mem.eql(u8, parts.next() orelse return error.MidlineBadBarrier, "MIDLINE_CHECK")) return error.MidlineBadBarrier;
    const logical = try std.fmt.parseInt(usize, parts.next() orelse return error.MidlineBadBarrier, 10);
    const console_x = try std.fmt.parseInt(usize, parts.next() orelse return error.MidlineBadBarrier, 10);
    const encoded = parts.next() orelse return error.MidlineBadBarrier;
    if (parts.next() != null) return error.MidlineBadBarrier;
    const prefix = prefixes[state.checked];
    const expected = try std.mem.concat(alloc, u8, &.{ prefix, inserted, suffix });
    defer alloc.free(expected);
    const b64 = try alloc.alloc(u8, std.base64.standard.Encoder.calcSize(expected.len));
    defer alloc.free(b64);
    _ = std.base64.standard.Encoder.encode(b64, expected);
    const units = try std.unicode.utf8ToUtf16LeAlloc(alloc, prefix);
    defer alloc.free(units);
    const buffer_ok = std.mem.eql(u8, encoded, b64) and logical == units.len + inserted.len;
    var reference = try Terminal.init(global.io(), alloc, .{ .cols = actual.cols, .rows = actual.rows, .default_modes = .{ .grapheme_cluster = true } });
    defer reference.deinit(alloc);
    var stream = reference.vtStream();
    defer stream.deinit();
    stream.nextSlice(prompt);
    stream.nextSlice(prefix);
    stream.nextSlice(inserted);
    const want_x = reference.screens.active.cursor.x;
    stream.nextSlice(suffix);
    const cursor = actual.screens.active.cursor;
    var differences: usize = 0;
    for (0..actual.cols) |x| {
        const got = actual.screens.active.pages.getCell(.{ .viewport = .{ .x = @intCast(x), .y = cursor.y } }).?;
        const want = reference.screens.active.pages.getCell(.{ .viewport = .{ .x = @intCast(x), .y = 0 } }).?;
        const gc = got.cell.codepoint();
        const wc = want.cell.codepoint();
        const gm = got.node.page().lookupGrapheme(got.cell) orelse &.{};
        const wm = want.node.page().lookupGrapheme(want.cell) orelse &.{};
        if ((if (gc == 0) @as(u21, 32) else gc) != (if (wc == 0) @as(u21, 32) else wc) or !std.mem.eql(u21, gm, wm)) differences += 1;
    }
    const ok = buffer_ok and differences == 0 and cursor.x == want_x and console_x == want_x;
    std.log.info("MIDLINE_EDIT case={s} buffer_ok={} logical_cursor={d} console_x={d} actual_x={d} expected_x={d} cell_differences={d} passed={}", .{ if (state.checked == 0) "ascii" else "thai", buffer_ok, logical, console_x, cursor.x, want_x, differences, ok });
    if (!ok) state.failures += 1;
    state.checked += 1;
    state.awaiting = false;
}
