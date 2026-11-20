# Own GPU-only process, not other applications; no global GFlags or dumps.
param([string]$Debugger = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$exe = Join-Path $workspace 'zig-out\lifecycle-controls\bin\localterm-dev-gl-probe.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Build windows-gl-probe first.' }
$sig = Get-AuthenticodeSignature -LiteralPath $Debugger
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'CDB must have a valid Microsoft signature.' }
$logs = Join-Path $env:LOCALAPPDATA 'Letta\build-logs\ghostty-windows\phase3b-runtime'
$cache = Join-Path $env:LOCALAPPDATA 'Letta\tools\windows-debugger\symbols'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
$name = 'cdb-wgl-htrace-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$out = Join-Path $logs ($name + '.stdout.log')
$err = Join-Path $logs ($name + '.stderr.log')
$trace = Join-Path $logs ($name + '.debugger.log')
$symbols = 'srv*' + $cache + '*https://msdl.microsoft.com/download/symbols'
$args = @('-hd','-G','-nosqm','-y',('"'+$symbols+'"'),'-logo',('"'+$trace+'"'),'-cf',('"'+(Join-Path $PSScriptRoot 'wgl-htrace.cdb')+'"'),('"'+$exe+'"'))
$saved = @{}
try {
    foreach ($key in @('LOCALTERM_GL_PACED_CONTROL','LOCALTERM_GL_HTRACE_CONTROL')) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, '1', 'Process')
    }
    $p = Start-Process -FilePath $Debugger -ArgumentList $args -WorkingDirectory $workspace -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}
$done = $p.WaitForExit(240000)
if (-not $done) { $p.Kill(); $p.WaitForExit() }
$text = if (Test-Path -LiteralPath $trace) { [IO.File]::ReadAllText($trace) } else { '' }
$baseline = $text -match '(?m)^LOCALTERM_HTRACE_BASELINE\r?$'
$final = $text -match '(?m)^LOCALTERM_HTRACE_FINAL\r?$'
[ordered]@{
    name=$name; debugger=$Debugger; debugger_exit=$p.ExitCode; timed_out=(-not $done)
    baseline_marker=$baseline; final_marker=$final; readiness_evidence=$false
    source='own GPU-only process, htrace creation stacks, normal heap (-hd), unchanged one warmup/20 cycles'
    stdout=$out; stderr=$err; trace=$trace
} | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $logs 'results.jsonl') -Encoding UTF8
Write-Output ('CDB trace: ' + $trace)
if (-not $done -or -not $baseline -or -not $final) { Get-Content -LiteralPath $out -Tail 24; throw 'Incomplete CDB attribution; not a readiness pass.' }
Select-String -LiteralPath $trace -Pattern 'LOCALTERM_HTRACE|Handle tracing|Handles =|handle =|Handle =|amdihk|ntdll!|KERNELBASE!' | Select-Object -Last 35 | ForEach-Object { $_.Line }
