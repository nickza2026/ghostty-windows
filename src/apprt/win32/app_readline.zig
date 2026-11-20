//! Explicit opt-in, executable-relative PSReadLine. Never install a module or
//! mutate process/machine environment; only the owned child's Config.env.
const std = @import("std");
const global = @import("../../global.zig");
const Config = @import("../../config.zig").Config;

const bootstrap =
    "& { $savedPreference=$ErrorActionPreference; try { $ErrorActionPreference='Stop'; " ++
    "$m=$env:LOCALTERM_APP_READLINE_MANIFEST; $base=[IO.Path]::GetFullPath((Split-Path -Parent $m)).TrimEnd('\\')+'\\'; " ++
    "$p=[IO.File]::ReadAllText((Join-Path $base 'build-provenance.json'))|ConvertFrom-Json; " ++
    "if($p.variant -ne 'patched'){throw 'App-owned patched PSReadLine provenance required'}; " ++
    "$loaded=Import-Module -Name $m -PassThru -ErrorAction Stop; $assembly=[Microsoft.PowerShell.PSConsoleReadLine].Assembly; " ++
    "if(-not $assembly.Location.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'App-owned PSReadLine was not loaded'}; " ++
    "$h=(Get-FileHash -LiteralPath $assembly.Location -Algorithm SHA256).Hash; " ++
    "if($h -ne $p.assemblySha256){throw 'App-owned PSReadLine assembly hash mismatch'}; " ++
    "[Console]::Write(([char]27).ToString()+']0;APP_READLINE_ACTIVE|'+$h+[char]7) " ++
    "} catch { [Console]::Error.WriteLine('App-owned PSReadLine unavailable: '+$_.Exception.Message); exit 125 } " ++
    "finally { $ErrorActionPreference=$savedPreference } }; ";

pub fn apply(config: *Config, powershell: []const u8, default_script: []const u8, controlled: bool, midline: bool, env: *const std.process.Environ.Map) !void {
    const arena = config.arenaAlloc();
    const args = switch (config.command orelse return error.AppReadlineRequiresPowerShell) {
        .direct => |direct| direct,
        else => return error.AppReadlineRequiresPowerShell,
    };
    if (args.len != 6 or !std.mem.eql(u8, args[0], powershell) or !std.mem.eql(u8, args[4], "-Command")) return error.AppReadlineRequiresPowerShell;
    // Do not silently replace a portable user's custom shell/command.
    if (!controlled and !std.mem.eql(u8, args[5], default_script)) return error.AppReadlineRequiresDefaultCommand;
    const exe = try std.process.executableDirPathAlloc(global.io(), arena);
    const parent = try std.fs.path.join(arena, &.{ exe, "powershell" });
    const module = try std.fs.path.join(arena, &.{ parent, "PSReadLine" });
    const manifest = try std.fs.path.joinZ(arena, &.{ module, "PSReadLine.psd1" });
    const owned = @import("owned_tool_files.zig");
    const provenance = try owned.verifyPayload(arena, global.io(), module, "build-provenance.json", &.{ "PSReadLine.psd1", "PSReadLine.psm1", "Microsoft.PowerShell.PSReadLine2.dll", "UPSTREAM-LICENSE" });
    if (!std.mem.eql(u8, try owned.string(provenance, "variant"), "patched")) return error.UnpatchedAppReadline;
    try owned.fileHash(arena, global.io(), manifest, try owned.string(provenance, "manifestSha256"));
    try owned.fileHash(arena, global.io(), try std.fs.path.join(arena, &.{ module, "Microsoft.PowerShell.PSReadLine2.dll" }), try owned.string(provenance, "assemblySha256"));
    for ([_][]const u8{ "PSReadLine.psd1", "Microsoft.PowerShell.PSReadLine2.dll", "build-provenance.json", "UPSTREAM-LICENSE" }) |name| {
        const path = try std.fs.path.join(arena, &.{ module, name });
        const file = try std.Io.Dir.cwd().openFile(global.io(), path, .{});
        file.close(global.io());
    }
    const existing: []const u8 = if (config.env.map.get("PSModulePath")) |value| value else env.get("PSModulePath") orelse "";
    const paths = try std.mem.concat(arena, u8, &.{ parent, ";", existing });
    try config.env.map.put(arena, try arena.dupeZ(u8, "PSModulePath"), try arena.dupeZ(u8, paths));
    try config.env.map.put(arena, try arena.dupeZ(u8, "LOCALTERM_APP_READLINE_MANIFEST"), manifest);
    if (midline) try config.env.map.put(arena, try arena.dupeZ(u8, "LOCALTERM_MIDLINE_MODULE"), manifest);
    const updated = try arena.dupe([:0]const u8, args);
    updated[5] = try arena.dupeZ(u8, try std.mem.concat(arena, u8, &.{ bootstrap, args[5] }));
    config.command = .{ .direct = updated };
    std.log.info("app-owned PSReadLine opt-in configured from executable directory; child environment only; fail closed", .{});
}
