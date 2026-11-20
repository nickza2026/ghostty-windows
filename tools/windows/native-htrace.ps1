# Debug only the owned synthetic lifecycle executable, never a user preview.
param([string]$Debugger = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$exe = Join-Path $workspace 'zig-out\native-attribution\bin\localterm-dev.exe'
foreach ($f in @($exe, (Join-Path ([IO.Path]::GetDirectoryName($exe)) 'conpty.dll'))) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "Missing owned diagnostic file: $f" }
}
$sig = Get-AuthenticodeSignature -LiteralPath $Debugger
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'CDB must have a valid Microsoft signature.' }
$logs = Join-Path $env:LOCALAPPDATA 'Letta\build-logs\ghostty-windows\phase3b-runtime'
$cache = Join-Path $env:LOCALAPPDATA 'Letta\tools\windows-debugger\symbols'
$null = New-Item -ItemType Directory -Path $cache -Force
$name = 'cdb-native-htrace-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$out = Join-Path $logs ($name + '.stdout.log')
$err = Join-Path $logs ($name + '.stderr.log')
$trace = Join-Path $logs ($name + '.debugger.log')
$symbols = 'srv*' + $cache + '*https://msdl.microsoft.com/download/symbols'
$args = @('-hd','-G','-nosqm','-y',('"'+$symbols+'"'),'-logo',('"'+$trace+'"'),'-cf',('"'+(Join-Path $PSScriptRoot 'native-htrace.cdb')+'"'),('"'+$exe+'"'))
$envs = @{
    LOCALTERM_LIFECYCLE_SMOKE = '1'; LOCALTERM_LIFECYCLE_PSS = '1'
    LOCALTERM_CONPTY_PROVIDER = 'app-local'; LOCALTERM_CONPTY_EXPERIMENT = '1'
    LOCALTERM_PREVIEW_BACKGROUND = '0c0c0c'
}
foreach ($k in @('LOCALTERM_WINDOW_SMOKE','LOCALTERM_TERMINAL_SMOKE','LOCALTERM_INPUT_SMOKE','LOCALTERM_MOUSE_SMOKE','LOCALTERM_THAI_TUI_SMOKE','LOCALTERM_THAI_TUI_LEGACY','LOCALTERM_BACKGROUND_SMOKE','LOCALTERM_THAI_MODEL_REQUIRED','LOCALTERM_TERMINAL_CASE','LOCALTERM_TITLE_BACKPRESSURE_SMOKE','LOCALTERM_CONPTY_WIDTH')) { $envs[$k] = $null }
$saved = @{}
try {
    foreach ($key in $envs.Keys) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $envs[$key], 'Process')
    }
    $p = Start-Process -FilePath $Debugger -ArgumentList $args -WorkingDirectory $workspace -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}
$done = $p.WaitForExit(240000)
if (-not $done) { & taskkill.exe /PID $p.Id /T /F | Out-Null; $p.WaitForExit() }
$text = if (Test-Path -LiteralPath $trace) { [IO.File]::ReadAllText($trace) } else { '' }
$baseline = $text -match '(?m)^LOCALTERM_NATIVE_HTRACE_BASELINE\r?$'
$final = $text -match '(?m)^LOCALTERM_NATIVE_HTRACE_FINAL\r?$'
[ordered]@{
    name=$name; executable=$exe; sha256=(Get-FileHash -LiteralPath $exe).Hash
    debugger_exit=$p.ExitCode; timed_out=(-not $done); baseline_marker=$baseline; final_marker=$final
    readiness_evidence=$false; source='owned dummy-shell native lifecycle; same warmup/20 cycles; htrace/live creator stacks only; no dump'
    stdout=$out; stderr=$err; trace=$trace
} | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $logs 'results.jsonl') -Encoding UTF8
$p.Dispose()
Write-Output "Native attribution baseline=$baseline final=$final timeout=$(-not $done) trace=$trace; NOT a strict gate pass"
if (-not $done -or -not $baseline -or -not $final) { throw 'Incomplete native creator trace; not attribution proof.' }
