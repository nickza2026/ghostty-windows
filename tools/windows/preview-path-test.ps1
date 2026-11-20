# Regression only. Start-Process is intercepted: never launch a GUI here.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$helper = Join-Path $PSScriptRoot 'preview.ps1'
$expected = Join-Path $workspace 'zig-out\image-paste\bin\localterm-dev.exe'
if (-not (Test-Path -LiteralPath $expected -PathType Leaf)) { throw 'Build the image-paste candidate first.' }
$location = Get-Location
$cwd = [IO.Directory]::GetCurrentDirectory()
$oldCase = [Environment]::GetEnvironmentVariable('LOCALTERM_TERMINAL_CASE', 'Process')
$oldMidline = [Environment]::GetEnvironmentVariable('LOCALTERM_MIDLINE_SMOKE', 'Process')
$oldMidlineModule = [Environment]::GetEnvironmentVariable('LOCALTERM_MIDLINE_MODULE', 'Process')
$oldAppReadline = [Environment]::GetEnvironmentVariable('LOCALTERM_APP_READLINE', 'Process')
$oldAppManifest = [Environment]::GetEnvironmentVariable('LOCALTERM_APP_READLINE_MANIFEST', 'Process')
$launches = [Collections.Generic.List[string]]::new()
function Start-Process {
    param($FilePath, $WorkingDirectory, [switch]$PassThru, $WindowStyle)
    if ($FilePath -ne $expected -or $WorkingDirectory -ne $workspace -or $WindowStyle -ne 'Normal') { throw 'Unexpected preview launch arguments.' }
    if ($env:LOCALTERM_TERMINAL -ne '1' -or [Environment]::GetEnvironmentVariable('LOCALTERM_TERMINAL_CASE', 'Process')) { throw 'Preview environment not isolated.' }
    if ([Environment]::GetEnvironmentVariable('LOCALTERM_MIDLINE_SMOKE', 'Process')) { throw 'Preview inherited private midline fixture.' }
    if ([Environment]::GetEnvironmentVariable('LOCALTERM_MIDLINE_MODULE', 'Process')) { throw 'Preview inherited private midline module selector.' }
    if ([Environment]::GetEnvironmentVariable('LOCALTERM_APP_READLINE', 'Process') -or [Environment]::GetEnvironmentVariable('LOCALTERM_APP_READLINE_MANIFEST', 'Process')) { throw 'Preview inherited app-owned line editor without opt-in.' }
    $launches.Add($FilePath)
    throw 'PREVIEW_TEST_INTERCEPTED_NO_GUI'
}
try {
    Set-Location -LiteralPath $workspace
    [IO.Directory]::SetCurrentDirectory($env:WINDIR)
    $env:LOCALTERM_TERMINAL_CASE = 'preview-test-preserve'
    $env:LOCALTERM_MIDLINE_SMOKE = 'midline-test-preserve'
    $env:LOCALTERM_MIDLINE_MODULE = 'module-test-preserve'
    $env:LOCALTERM_APP_READLINE = 'app-test-preserve'
    $env:LOCALTERM_APP_READLINE_MANIFEST = 'manifest-test-preserve'
    foreach ($path in @('.\zig-out\image-paste\bin\localterm-dev.exe', $expected, '.\zig-out\image-paste\bin\..\bin\localterm-dev.exe')) {
        try { & $helper -Executable $path; throw 'Preview did not reach the intercepted launch.' }
        catch { if ($_.Exception.Message -ne 'PREVIEW_TEST_INTERCEPTED_NO_GUI') { throw } }
        if ($env:LOCALTERM_TERMINAL_CASE -ne 'preview-test-preserve') { throw 'Preview did not restore the environment.' }
        if ($env:LOCALTERM_MIDLINE_SMOKE -ne 'midline-test-preserve') { throw 'Preview did not restore the private fixture environment.' }
        if ($env:LOCALTERM_MIDLINE_MODULE -ne 'module-test-preserve') { throw 'Preview did not restore the private module environment.' }
        if ($env:LOCALTERM_APP_READLINE -ne 'app-test-preserve' -or $env:LOCALTERM_APP_READLINE_MANIFEST -ne 'manifest-test-preserve') { throw 'Preview did not restore the app-owned module environment.' }
    }
    if ($launches.Count -ne 3) { throw 'Expected three intercepted launches.' }
    foreach ($path in @(($workspace + '-other\localterm-dev.exe'), '.\PLAN.md')) {
        try { & $helper -Executable $path; throw 'Unsafe preview path was accepted.' }
        catch { if ($_.Exception.Message -notlike 'Preview executable must be*') { throw } }
    }
    if ($launches.Count -ne 3) { throw 'Rejected paths reached process creation.' }
    try { & $helper -Executable $expected -AppReadLine; throw 'Missing app-owned package was accepted.' }
    catch { if ($_.Exception.Message -notlike 'Missing app-owned PSReadLine file:*') { throw } }
    if ($launches.Count -ne 3) { throw 'Missing app-owned package reached process creation.' }
    Write-Output 'PASS preview paths: relative/absolute/normalized; .NET cwd differs; sibling/wrong-name rejected; environment restored; no GUI launched.'
} finally {
    Remove-Item Function:\Start-Process
    [Environment]::SetEnvironmentVariable('LOCALTERM_TERMINAL_CASE', $oldCase, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALTERM_MIDLINE_SMOKE', $oldMidline, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALTERM_MIDLINE_MODULE', $oldMidlineModule, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALTERM_APP_READLINE', $oldAppReadline, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALTERM_APP_READLINE_MANIFEST', $oldAppManifest, 'Process')
    [IO.Directory]::SetCurrentDirectory($cwd)
    Set-Location -LiteralPath $location.Path
}
