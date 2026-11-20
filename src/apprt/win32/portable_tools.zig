//! Opt-in fresh Node/npm/Letta child profile, never machine configuration.
const std = @import("std");
const global = @import("../../global.zig");
const Config = @import("../../config.zig").Config;
const owned = @import("owned_tool_files.zig");

const bootstrap =
    "& { $savedPreference=$ErrorActionPreference; try { $ErrorActionPreference='Stop'; " ++
    "Set-Variable -Name HOME -Scope Global -Value $env:USERPROFILE -Force; " ++
    "$history=Join-Path $env:LOCALTERM_PORTABLE_DATA 'home\\PowerShell\\PSReadLine\\ConsoleHost_history.txt'; " ++
    "Set-PSReadLineOption -HistorySavePath $history -HistorySaveStyle SaveIncrementally; " ++
    "function global:Invoke-LocaltermPortableNode { param([string]$Entry,[object[]]$Arguments) " ++
    "$n=Join-Path $env:LOCALTERM_PORTABLE_DATA 'runtimes\\node\\node.exe'; " ++
    "if(-not [IO.File]::Exists($n)){ $global:LASTEXITCODE=127; throw 'Portable Node missing; no Windows Node fallback' }; " ++
    "if($Entry){if(-not [IO.File]::Exists($Entry)){$global:LASTEXITCODE=127;throw 'Portable CLI missing; install it with portable npm first'}; & $n $Entry @Arguments} else { & $n @Arguments } }; " ++
    "function global:node { Invoke-LocaltermPortableNode -Entry '' -Arguments $args }; " ++
    "function global:npm { Invoke-LocaltermPortableNode -Entry (Join-Path $env:LOCALTERM_PORTABLE_DATA 'runtimes\\node\\node_modules\\npm\\bin\\npm-cli.js') -Arguments $args }; " ++
    "function global:npx { Invoke-LocaltermPortableNode -Entry (Join-Path $env:LOCALTERM_PORTABLE_DATA 'runtimes\\node\\node_modules\\npm\\bin\\npx-cli.js') -Arguments $args }; " ++
    "function global:letta { Invoke-LocaltermPortableNode -Entry (Join-Path $env:LOCALTERM_PORTABLE_DATA 'npm\\node_modules\\@letta-ai\\letta-code\\letta.js') -Arguments $args }; " ++
    "[Console]::Write(([char]27).ToString()+']0;PORTABLE_TOOLS_ACTIVE'+[char]7) " ++
    "} catch { [Console]::Error.WriteLine('Portable tools unavailable: '+$_.Exception.Message);exit 125 } finally { $ErrorActionPreference=$savedPreference } }; ";

fn put(config: *Config, key: []const u8, value: []const u8) !void {
    const a = config.arenaAlloc();
    try config.env.map.put(a, try a.dupeZ(u8, key), try a.dupeZ(u8, value));
}

pub fn apply(config: *Config, powershell: []const u8, default_script: []const u8, controlled: bool, env: *const std.process.Environ.Map) !void {
    const a = config.arenaAlloc();
    const io = global.io();
    const layout = global.portablePaths() orelse return error.PortableToolsRequirePortableData;
    try layout.verify(io);
    try owned.realPath(a, layout.root, true);
    const args = switch (config.command orelse return error.PortableToolsRequirePowerShell) {
        .direct => |direct| direct,
        else => return error.PortableToolsRequirePowerShell,
    };
    if (args.len != 6 or !std.mem.eql(u8, args[0], powershell) or !std.mem.eql(u8, args[4], "-Command")) return error.PortableToolsRequirePowerShell;
    if (!controlled and !std.mem.eql(u8, args[5], default_script)) return error.PortableToolsRequireDefaultCommand;
    const node_root = try std.fs.path.join(a, &.{ layout.root, "runtimes", "node" });
    const provenance = try owned.verifyPayload(a, io, node_root, "provenance.json", &.{ "node.exe", "npm.cmd", "npx.cmd", "node_modules/npm/bin/npm-cli.js", "node_modules/npm/bin/npx-cli.js", "LICENSE" });
    // Same official pin as third_party/node/source-pin.json. No auto-download
    // or auto-upgrade; changing the runtime is a separately verified build.
    if (!std.mem.eql(u8, try owned.string(provenance, "version"), "v24.22.1") or !std.ascii.eqlIgnoreCase(try owned.string(provenance, "archiveSha256"), "d2046d28c2c3dcd211ac5145c0bf30e2047ef9dfb306693c8c6e2eccd8b95fa5")) return error.PortableNodePinMismatch;
    const home = try owned.ensureDir(a, io, layout.root, "home");
    const roaming = try owned.ensureDir(a, io, layout.root, "home/AppData/Roaming");
    const local = try owned.ensureDir(a, io, layout.root, "home/AppData/Local");
    const letta = try owned.ensureDir(a, io, layout.root, "home/.letta");
    const backend = try owned.ensureDir(a, io, layout.root, "home/.letta/lc-local-backend");
    _ = try owned.ensureDir(a, io, layout.root, "home/PowerShell/PSReadLine");
    const npm = try owned.ensureDir(a, io, layout.root, "npm");
    const shims = try std.fs.path.join(a, &.{ layout.root, "shims" });
    try owned.realPath(a, shims, true);
    for ([_][]const u8{ "node.cmd", "npm.cmd", "npx.cmd", "letta.cmd" }) |name| try owned.realPath(a, try std.fs.path.join(a, &.{ shims, name }), false);
    const cache = try owned.ensureDir(a, io, layout.root, "cache/npm");
    const temp = try owned.ensureDir(a, io, layout.root, "tmp");
    const config_dir = try owned.ensureDir(a, io, layout.root, "config");
    for ([_][]const u8{ home, roaming, local, letta, backend, npm, cache, temp, config_dir }) |path| try owned.writable(a, io, path);
    const userconfig = try std.fs.path.join(a, &.{ config_dir, "npm-user.npmrc" });
    const globalconfig = try std.fs.path.join(a, &.{ config_dir, "npm-global.npmrc" });
    try owned.blankConfig(a, io, userconfig);
    try owned.blankConfig(a, io, globalconfig);
    const system = env.get("SystemRoot") orelse return error.SystemRootMissing;
    const sys32 = try std.fs.path.join(a, &.{ system, "System32" });
    const wbem = try std.fs.path.join(a, &.{ sys32, "Wbem" });
    const ps = try std.fs.path.join(a, &.{ sys32, "WindowsPowerShell", "v1.0" });
    const path = try std.mem.join(a, ";", &.{ shims, node_root, npm, sys32, system, wbem, ps });
    try put(config, "PATH", path);
    try put(config, "PSModulePath", try std.fs.path.join(a, &.{ ps, "Modules" }));
    try put(config, "COMSPEC", try std.fs.path.join(a, &.{ sys32, "cmd.exe" }));
    try put(config, "PATHEXT", ".COM;.EXE;.BAT;.CMD");
    try put(config, "NoDefaultCurrentDirectoryInExePath", "1");
    try put(config, "LOCALTERM_PORTABLE_TOOLS", "1");
    try put(config, "LOCALTERM_PORTABLE_DATA", layout.root);
    try put(config, "HOME", home);
    try put(config, "USERPROFILE", home);
    if (home.len >= 3 and home[1] == ':') {
        try put(config, "HOMEDRIVE", home[0..2]);
        try put(config, "HOMEPATH", home[2..]);
    } else {
        try put(config, "HOMEDRIVE", "");
        try put(config, "HOMEPATH", home);
    }
    try put(config, "HOMESHARE", "");
    try put(config, "APPDATA", roaming);
    try put(config, "LOCALAPPDATA", local);
    for ([_][]const u8{ "TEMP", "TMP", "TMPDIR" }) |key| try put(config, key, temp);
    try put(config, "XDG_CONFIG_HOME", try owned.ensureDir(a, io, layout.root, "home/.config"));
    try put(config, "XDG_DATA_HOME", try owned.ensureDir(a, io, layout.root, "home/.local/share"));
    try put(config, "XDG_STATE_HOME", try owned.ensureDir(a, io, layout.root, "home/.local/state"));
    try put(config, "XDG_CACHE_HOME", try owned.ensureDir(a, io, layout.root, "cache/tools"));
    try put(config, "NPM_CONFIG_PREFIX", npm);
    try put(config, "NPM_CONFIG_CACHE", cache);
    try put(config, "NPM_CONFIG_USERCONFIG", userconfig);
    try put(config, "NPM_CONFIG_GLOBALCONFIG", globalconfig);
    try put(config, "NPM_CONFIG_AUDIT", "false");
    try put(config, "NPM_CONFIG_FUND", "false");
    try put(config, "LETTA_HOME", letta);
    try put(config, "LETTA_LOCAL_BACKEND_DIR", backend);
    try put(config, "LETTA_PACKAGE_MANAGER", "npm");
    try put(config, "DISABLE_AUTOUPDATER", "1");
    try put(config, "NODE_REPL_HISTORY", try std.fs.path.join(a, &.{ home, ".node_repl_history" }));
    const updated = try a.dupe([:0]const u8, args);
    updated[5] = try a.dupeZ(u8, try std.mem.concat(a, u8, &.{ bootstrap, args[5] }));
    config.command = .{ .direct = updated };
    std.log.info("portable tools verified; fresh child-only profile; exact Node launchers; strict PATH; inherited tool/auth injections removed before spawn; not a sandbox", .{});
}
