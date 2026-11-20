param([string]$Executable = (Join-Path $PSScriptRoot '..\..\zig-out\image-paste\bin\localterm-dev.exe'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$exe = (Resolve-Path -LiteralPath $Executable).ProviderPath
if (-not $exe.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture executable must be in this workspace.' }
$marker = Join-Path ([IO.Path]::GetDirectoryName($exe)) 'portable-data'
if (Test-Path -LiteralPath $marker) { throw 'Existing portable-data is user-owned; fixture requires an absent marker and will not modify it.' }
$logs = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Letta\build-logs\ghostty-windows\phase3b-runtime'))
$thai = ([char]0x0E44).ToString() + [char]0x0E17 + [char]0x0E22 # PS5.1 UTF-8-without-BOM safe.
$tempRoot = [IO.Path]::GetFullPath((Join-Path $logs ("image fixture's " + $thai + '-' + [Guid]::NewGuid().ToString('N'))))
if (-not $tempRoot.StartsWith($logs + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture TEMP escaped its owned log root.' }
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$oldTemp = [Environment]::GetEnvironmentVariable('TEMP', 'Process')
$createdMarker = $false
$completed = $false
$cleanupErrors = @()
try {
    $env:TEMP = $tempRoot
    & (Join-Path $PSScriptRoot 'runtime-smoke.ps1') -Mode image-paste -Executable $exe
    if (@(Get-ChildItem -LiteralPath $tempRoot -Force).Count -ne 0) { throw 'Normal image session retained fixture files.' }
    # No -Force: an unexpected concurrent marker creation fails closed.
    New-Item -ItemType Directory -Path $marker | Out-Null
    $createdMarker = $true
    & (Join-Path $PSScriptRoot 'runtime-smoke.ps1') -Mode image-paste -Executable $exe
    if (@(Get-ChildItem -LiteralPath $tempRoot -Force).Count -ne 0) { throw 'Portable session wrote into host fixture TEMP.' }
    $completed = $true
} finally {
    [Environment]::SetEnvironmentVariable('TEMP', $oldTemp, 'Process')
    $emptyOnly = @($tempRoot)
    if ($createdMarker) { $emptyOnly += @((Join-Path $marker 'cache\clipboard'), (Join-Path $marker 'cache'), (Join-Path $marker 'config'), (Join-Path $marker 'data'), (Join-Path $marker 'logs'), (Join-Path $marker 'tmp'), $marker) }
    foreach ($path in $emptyOnly) {
        # All are explicit, freshly owned absolute paths. NEVER recursively
        # delete unknown leftovers; retain evidence and fail instead.
        if (Test-Path -LiteralPath $path) {
            try { [IO.Directory]::Delete($path, $false) } catch { $cleanupErrors += $path }
        }
    }
    [ordered]@{
        name = 'image-paste-core-pty-normal-portable'; passed = $completed -and $cleanupErrors.Count -eq 0
        interactive_clipboard_access = $false; source = 'synthetic DIB, production staging/core paste, independent GDI+ decoder'
        cli_parser = 'one PowerShell string literal, never executed'; temp_has_spaces_quote_unicode = $true
        cleanup_empty_only = $true; retained_paths = $cleanupErrors
    } | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $logs 'results.jsonl') -Encoding UTF8
    if ($cleanupErrors.Count -ne 0) { Write-Warning ('Owned fixture paths retained (no recursive delete): ' + ($cleanupErrors -join ', ')) }
}
if (-not $completed -or $cleanupErrors.Count -ne 0) { throw 'Image E2E/cleanup failed; inspect receipts, never substitute OS clipboard validation.' }
Write-Output 'PASS normal+portable Core/PTy PNG consumer, quoting, expected-root, cleanup; no OS clipboard access'
