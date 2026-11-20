# Manual interactive preview only. Does not run smoke or change system settings.
param([string]$Executable, [switch]$AppLocalConpty, [switch]$AppReadLine, [switch]$PortableTools, [ValidatePattern('^[0-9a-fA-F]{6}$')][string]$Background)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
# PowerShell Set-Location does not synchronize .NET's process cwd. Resolve
# user paths against the PowerShell provider location, not GetFullPath's cwd.
$exe = if ($Executable) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Executable) } else { Join-Path $workspace 'zig-out\bin\localterm-dev.exe' }
if (-not $exe.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($exe) -ne 'localterm-dev.exe') {
    throw 'Preview executable must be a localterm-dev.exe inside this workspace.'
}
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Build the native Win32 runtime before opening preview.' }
if ($AppLocalConpty) {
    foreach ($file in @('conpty.dll','OpenConsole.exe','ConPTY-experiment.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($exe)) $file) -PathType Leaf)) { throw "Missing app-local experiment file: $file" }
    }
}
if ($PortableTools) { $AppReadLine = $true }
if ($AppReadLine) {
    $module = Join-Path ([IO.Path]::GetDirectoryName($exe)) 'powershell\PSReadLine'
    foreach ($file in @('PSReadLine.psd1','Microsoft.PowerShell.PSReadLine2.dll','build-provenance.json','UPSTREAM-LICENSE')) {
        if (-not (Test-Path -LiteralPath (Join-Path $module $file) -PathType Leaf)) { throw "Missing app-owned PSReadLine file: $file" }
    }
    for ($ancestor = $module; $ancestor; $ancestor = [IO.Path]::GetDirectoryName($ancestor)) {
        if ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'App-owned PSReadLine ancestor reparse point refused.' }
    }
    $pending = [Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($module)
    while ($pending.Count) {
        $dir = $pending.Dequeue()
        if ((Get-Item -LiteralPath $dir).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'App-owned PSReadLine reparse point refused.' }
        foreach ($entry in Get-ChildItem -LiteralPath $dir -Force) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'App-owned PSReadLine reparse point refused.' }
            if ($entry.PSIsContainer) { $pending.Enqueue($entry.FullName) }
        }
    }
    $provenance = Get-Content -LiteralPath (Join-Path $module 'build-provenance.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($provenance.variant -ne 'patched' -or (Get-FileHash -LiteralPath (Join-Path $module 'Microsoft.PowerShell.PSReadLine2.dll')).Hash -ne $provenance.assemblySha256) { throw 'App-owned patched PSReadLine identity mismatch.' }
}
$names = @('LOCALTERM_WINDOW_SMOKE', 'LOCALTERM_TERMINAL_SMOKE', 'LOCALTERM_TERMINAL', 'LOCALTERM_INPUT_SMOKE', 'LOCALTERM_LIFECYCLE_SMOKE', 'LOCALTERM_LIFECYCLE_PSS', 'LOCALTERM_TERMINAL_CASE', 'LOCALTERM_TITLE_BACKPRESSURE_SMOKE', 'LOCALTERM_EXPECT_IMAGE_ROOT', 'LOCALTERM_MOUSE_SMOKE', 'LOCALTERM_THAI_TUI_SMOKE', 'LOCALTERM_THAI_TUI_LEGACY', 'LOCALTERM_CONPTY_WIDTH', 'LOCALTERM_CONPTY_PROVIDER', 'LOCALTERM_CONPTY_EXPERIMENT', 'LOCALTERM_THAI_MODEL_REQUIRED', 'LOCALTERM_BACKGROUND_SMOKE', 'LOCALTERM_PREVIEW_BACKGROUND')
$names += @('LOCALTERM_MIDLINE_SMOKE')
$names += @('LOCALTERM_MIDLINE_MODULE')
$names += @('LOCALTERM_APP_READLINE', 'LOCALTERM_APP_READLINE_MANIFEST')
$names += @('LOCALTERM_PORTABLE_TOOLS', 'LOCALTERM_PORTABLE_TOOLS_CHECK', 'LOCALTERM_PORTABLE_DATA')
$saved = @{}
$process = $null
try {
    foreach ($name in $names) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    $env:LOCALTERM_TERMINAL = '1'
    if ($AppReadLine) { $env:LOCALTERM_APP_READLINE = '1' }
    if ($PortableTools) { $env:LOCALTERM_PORTABLE_TOOLS = '1' }
    if ($AppLocalConpty) { $env:LOCALTERM_CONPTY_PROVIDER = 'app-local'; $env:LOCALTERM_CONPTY_EXPERIMENT = '1' }
    if ($Background) { $env:LOCALTERM_PREVIEW_BACKGROUND = $Background }
    # The human runs this command to request a visible, interactive window.
    $process = Start-Process -FilePath $exe -WorkingDirectory $workspace -PassThru -WindowStyle Normal
    $null = $process.Handle
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Native preview exited with code $($process.ExitCode)." }
} finally {
    if ($null -ne $process) { $process.Dispose() }
    foreach ($name in $names) {
        if ($saved.ContainsKey($name)) {
            [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
        }
    }
}
