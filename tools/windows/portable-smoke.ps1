param([string]$SourcePrefix = (Join-Path $PSScriptRoot '..\..\zig-out\portable-dev'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$source = (Resolve-Path -LiteralPath $SourcePrefix).ProviderPath.TrimEnd('\')
if (Test-Path -LiteralPath (Join-Path $source 'bin\portable-data')) { throw 'Normal source prefix has user-owned portable data; refusing test.' }
$owned = Join-Path $workspace ('zig-out\portable-validation\' + [Guid]::NewGuid().ToString('N'))
$thai = ([char]0x0E44).ToString() + [char]0x0E17 + [char]0x0E22
$first = Join-Path $owned ('original ' + $thai + ' space')
$moved = Join-Path $owned ('moved ' + $thai + ' space')
$logs = Join-Path $env:LOCALAPPDATA 'Letta\build-logs\ghostty-windows\portable'
$null = [IO.Directory]::CreateDirectory($logs)
$stamp = 'portable-relocation-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$results = Join-Path $logs 'results.jsonl'
& (Join-Path $PSScriptRoot 'package-portable.ps1') -SourcePrefix $source -OutputDirectory $first
$keys = @('LOCALTERM_TERMINAL','LOCALTERM_TERMINAL_SMOKE','LOCALTERM_WINDOW_SMOKE','LOCALTERM_CONPTY_PROVIDER','LOCALTERM_CONPTY_EXPERIMENT','XDG_CONFIG_HOME','GHOSTTY_RESOURCES_DIR')
$keys += @(Get-ChildItem Env:LOCALTERM_* | Select-Object -ExpandProperty Name)
$saved = @{}
$process = $null
function OwnedMove([string]$from, [string]$to) {
    foreach ($path in @($from,$to)) {
        if (-not ([IO.Path]::GetFullPath($path)).StartsWith($owned+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Move escaped owned fixture root.' }
    }
    [IO.Directory]::Move($from,$to)
}
function StartControlled([string]$exe, [string]$name) {
    $p = Start-Process $exe -WorkingDirectory $workspace -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs ($stamp+'.'+$name+'.stdout.log')) -RedirectStandardError (Join-Path $logs ($stamp+'.'+$name+'.stderr.log'))
    $null = $p.Handle
    return $p
}
function FinishControlled($p, [string]$name, [int]$expected, [string]$pattern) {
    $done = $p.WaitForExit(30000)
    if (-not $done) { & taskkill.exe /PID $p.Id /T /F | Out-Null; $null = $p.WaitForExit(5000) }
    $code = $p.ExitCode
    $p.Dispose()
    $stderr = Join-Path $logs ($stamp+'.'+$name+'.stderr.log')
    $text = Get-Content -LiteralPath $stderr -Raw -Encoding UTF8
    $passed = $done -and $code -eq $expected -and $text -match $pattern
    [ordered]@{name=$stamp;stage=$name;passed=$passed;exit_code=$code;timeout=(-not $done);stderr=$stderr;scope='owned offscreen/no-activate fixture, no OS clipboard or real account access; not physical IME/clean-machine/full file-access trace'} | ConvertTo-Json -Compress | Add-Content -LiteralPath $results -Encoding UTF8
    if (-not $passed) { Get-Content -LiteralPath $stderr -Tail 12 -Encoding UTF8; throw "Portable case failed: $name" }
    Write-Host "PASS portable $name"
    return $text
}
try {
    foreach ($key in ($keys|Select-Object -Unique)) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process'); [Environment]::SetEnvironmentVariable($key,$null,'Process') }
    $env:LOCALTERM_TERMINAL='1'; $env:LOCALTERM_TERMINAL_SMOKE='1'
    $env:LOCALTERM_CONPTY_PROVIDER='app-local'; $env:LOCALTERM_CONPTY_EXPERIMENT='1'
    $env:XDG_CONFIG_HOME=Join-Path $owned 'host-config-must-not-read'
    $env:GHOSTTY_RESOURCES_DIR=Join-Path $source 'share\ghostty'
    $hostThemes=Join-Path $env:XDG_CONFIG_HOME 'ghostty\themes'
    $null=[IO.Directory]::CreateDirectory($hostThemes)
    [IO.File]::WriteAllText((Join-Path $hostThemes 'portable-fixture'), 'invalid-host-theme-option=1')
    $data=Join-Path $first 'bin\portable-data'
    $null=[IO.Directory]::CreateDirectory((Join-Path $data 'config\themes'))
    [IO.File]::WriteAllText((Join-Path $data 'config\themes\portable-fixture'), "background = #112233`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $data 'config\config.ghostty'), "font-size = 19`ntheme = portable-fixture`n", [Text.UTF8Encoding]::new($false))
    $normal=StartControlled (Join-Path $source 'bin\localterm-dev.exe') 'normal-overlap'
    try {
        if ($normal.HasExited) { throw 'Normal control exited before overlap.' }
        $process=StartControlled (Join-Path $first 'bin\localterm-dev.exe') 'original'
        $text=FinishControlled $process 'original' 0 'portable config loaded.*font_size=19'
        $process=$null
        if ($text -notmatch [regex]::Escape((Join-Path $first 'share\ghostty'))) { throw 'Original bundle resources not proven.' }
        $normalText=FinishControlled $normal 'normal-overlap' 0 'native terminal smoke:'
        $normal=$null
        if ($normalText -match 'portable app root=') { throw 'Normal control unexpectedly selected portable.' }
    } finally { if ($null -ne $normal) { try { $null=FinishControlled $normal 'normal-overlap' 0 'native terminal smoke:' } catch { Write-Warning $_.Exception.Message } } }
    OwnedMove $first $moved
    $data=Join-Path $moved 'bin\portable-data'
    $exe=Join-Path $moved 'bin\localterm-dev.exe'
    $process=StartControlled $exe 'moved'
    $text=FinishControlled $process 'moved' 0 'portable config loaded.*font_size=19'
    $process=$null
    if ($text -notmatch [regex]::Escape((Join-Path $moved 'share\ghostty')) -or $text -match [regex]::Escape($first)) { throw 'Moved package retained old resource/config root.' }
    $share=Join-Path $moved 'share'; $hidden=Join-Path $moved 'share-disabled'
    OwnedMove $share $hidden
    try { $process=StartControlled $exe 'missing-resources'; $null=FinishControlled $process 'missing-resources' 1 'PortableResourcesMissing'; $process=$null } finally { OwnedMove $hidden $share }
    $config=Join-Path $data 'config\config.ghostty'; $original=[IO.File]::ReadAllText($config)
    [IO.File]::WriteAllText($config, 'invalid-portable-config-option=1')
    try { $process=StartControlled $exe 'invalid-config'; $null=FinishControlled $process 'invalid-config' 1 'InvalidPortableConfig'; $process=$null } finally { [IO.File]::WriteAllText($config,$original,[Text.UTF8Encoding]::new($false)) }
    $logDir=Join-Path $data 'logs'
    [IO.Directory]::Delete($logDir,$false) # Empty-only, fresh owned fixture.
    [IO.File]::WriteAllText($logDir,'fixture-not-a-directory')
    try { $process=StartControlled $exe 'invalid-storage'; $null=FinishControlled $process 'invalid-storage' 1 'InvalidPortableDataDirectory'; $process=$null } finally { [IO.File]::Delete($logDir); $null=[IO.Directory]::CreateDirectory($logDir) }
    $leftovers=@(Get-ChildItem -LiteralPath $data -Recurse -Force | Where-Object { $_.Name -like '.portable-probe-*' })
    if ($leftovers.Count) { throw 'Write probes left unexpected files.' }
    Write-Output "PASS portable relocation/config/theme/package-only resources/negative nofallback/normal overlap; fixture retained=$moved"
} finally {
    if ($null -ne $process) { try { $done=$process.WaitForExit(30000); if(-not $done){ & taskkill.exe /PID $process.Id /T /F | Out-Null }; $process.Dispose() } catch { Write-Warning $_.Exception.Message } }
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }
}
