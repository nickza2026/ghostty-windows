# This is a GPU-only process-boundary experiment, NOT the native strict gate.
param(
    [string]$Parent = (Join-Path $PSScriptRoot '..\..\zig-out\gpu-child-poc\bin\gpu-child-parent.exe'),
    [string]$Child = (Join-Path $PSScriptRoot '..\..\zig-out\gpu-child-poc\bin\localterm-dev-gl-probe.exe')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Parent = (Resolve-Path -LiteralPath $Parent).Path
$Child = (Resolve-Path -LiteralPath $Child).Path
$parentHash = (Get-FileHash -LiteralPath $Parent).Hash
$childHash = (Get-FileHash -LiteralPath $Child).Hash
$logs = Join-Path $env:LOCALAPPDATA 'Letta\build-logs\ghostty-windows\phase3b-runtime'
$name = 'gpu-child-poc-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$root = Join-Path $logs $name
$null = New-Item -ItemType Directory -Path $root
$cases = @(
    @{name='positive'; mode='positive'; expected=0; producer='parent'; marker='GPU_CHILD_POC_PASS warmup=1 cycles=20 long_controls=1 parent_gpu_modules=0 children_exited=22'},
    @{name='missing-receipt'; mode='missing-receipt'; expected=1; producer='parent'; marker='FAIL child receipt missing/invalid'},
    @{name='bad-pixels'; mode='bad-pixels'; expected=1; producer='child'; marker='PixelReadbackMismatch'},
    @{name='hang'; mode='hang'; expected=1; producer='parent'; marker='FAIL owned child deadline'},
    @{name='launch-failure'; mode='missing-receipt'; expected=1; producer='parent'; marker='FAIL child launch'},
    @{name='counter-error'; mode='counter-error'; expected=1; producer='parent'; marker='FAIL GUI counter error='}
)
foreach ($case in $cases) {
    $dir = Join-Path $root $case.name
    $null = New-Item -ItemType Directory -Path $dir
    $out = Join-Path $dir 'parent.stdout.log'
    $err = Join-Path $dir 'parent.stderr.log'
    $target = if ($case.name -eq 'launch-failure') { Join-Path $root 'nonexistent-probe.exe' } else { $Child }
    $args = @(('"'+$target+'"'),('"'+$dir+'"'),$case.mode)
    $p = Start-Process -FilePath $Parent -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle
    $done = $p.WaitForExit(300000)
    $ownedPid = $p.Id
    $killExit = $null
    $terminationConfirmed = $done
    if (-not $done) {
        & taskkill.exe /PID $ownedPid /T /F | Out-Null
        $killExit = $LASTEXITCODE
        $terminationConfirmed = $p.WaitForExit(5000)
    }
    $exit = if ($terminationConfirmed) { $p.ExitCode } else { $null }
    $p.Dispose()
    $parentText = [IO.File]::ReadAllText($out) + [IO.File]::ReadAllText($err)
    $childText = ''
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter 'child-*.log') { $childText += [IO.File]::ReadAllText($f.FullName) }
    $producerText = if ($case.producer -eq 'parent') { $parentText } else { $childText }
    $ok = $done -and $exit -eq $case.expected -and $producerText.Contains($case.marker)
    if ($case.expected -ne 0) { $ok = $ok -and $parentText.Contains('OWNED_CLEANUP_OK') }
    $ok = $ok -and (Get-FileHash -LiteralPath $Parent).Hash -eq $parentHash -and (Get-FileHash -LiteralPath $Child).Hash -eq $childHash
    [ordered]@{
        name=$name; case=$case.name; exit_code=$exit; expected_exit=$case.expected; timeout=(-not $done)
        passed=$ok; parent_sha256=$parentHash; child_sha256=$childHash; artifacts=$dir
        marker_producer=$case.producer; owned_pid=$ownedPid; kill_exit=$killExit; termination_confirmed=$terminationConfirmed
        readiness_evidence=$false; scope='GPU-only child boundary PoC; native strict failure remains open'
    } | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $logs 'results.jsonl') -Encoding UTF8
    Write-Output "GPU child PoC case=$($case.name) expected=$($case.expected) actual=$exit validated=$ok artifacts=$dir"
    if (-not $ok) { Get-Content -LiteralPath $err -Tail 12; throw "GPU child PoC failed: $($case.name)" }
}
Write-Output 'GPU-only boundary + fail-closed controls complete; NOT native renderer integration or native resource gate pass.'
