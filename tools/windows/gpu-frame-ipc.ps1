# Trusted instrumented component fixture; not terminal/renderer integration.
param([switch]$Build)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$bin=Join-Path $workspace 'zig-out\gpu-frame-ipc\bin'
$logs=Join-Path $env:LOCALAPPDATA 'Letta\build-logs\ghostty-windows\phase3b-runtime'
$name='gpu-frame-ipc-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$root=Join-Path $logs $name
$null=New-Item -ItemType Directory -Path $root -Force
$parent=Join-Path $bin 'gpu-frame-parent.exe'
$child=Join-Path $bin 'localterm-dev-gpu-frame-child.exe'
if($Build){
    $vs='C:\Program Files\Microsoft Visual Studio\2022\Community'
    Import-Module (Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'
    $null=New-Item -ItemType Directory -Path $bin -Force
    Push-Location $workspace
    try{
        & cl.exe /nologo /TC /std:c17 /O2 /MT /W4 /WX /D_WIN32_WINNT=0x0602 /DUNICODE /D_UNICODE ('/Fo'+(Join-Path $bin 'gpu-frame-parent.obj')) ('/Fe'+$parent) tools/windows/gpu-frame-parent.c /link user32.lib gdi32.lib
        if($LASTEXITCODE -ne 0){throw 'IPC parent compile failed'}
        $zig=Join-Path $env:LOCALAPPDATA 'Programs\Zig\zig-x86_64-windows-0.16.0\zig.exe'
        $stdout=Join-Path $root 'build.stdout.log';$stderr=Join-Path $root 'build.stderr.log'
        $p=Start-Process $zig -ArgumentList @('build','windows-gpu-frame-probe','-j1','-Dapp-runtime=win32','-Demit-docs=false','-Doptimize=ReleaseSafe','-p','zig-out/gpu-frame-ipc','--summary','all') -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $null=$p.Handle
        $done=$p.WaitForExit(600000)
        if(-not $done){& taskkill.exe /PID $p.Id /T /F|Out-Null;$null=$p.WaitForExit(5000)}
        $code=if($p.HasExited){$p.ExitCode}else{$null}
        $p.Dispose()
        Get-Content -LiteralPath $stderr|Where-Object{$_.Length -lt 600}|Select-Object -Last 12
        if(-not $done -or $code -ne 0){throw 'IPC child build failed/timeout; no test pass'}
    }finally{Pop-Location}
}
$ph=(Get-FileHash -LiteralPath $parent).Hash;$ch=(Get-FileHash -LiteralPath $child).Hash
if(-not (Get-Command dumpbin.exe -ErrorAction SilentlyContinue)){
    $vs='C:\Program Files\Microsoft Visual Studio\2022\Community'
    Import-Module (Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'
}
$imports=@(& dumpbin.exe /imports $parent)
if($LASTEXITCODE -ne 0){throw 'Parent static import inspection failed'}
$imports|Set-Content -LiteralPath (Join-Path $root 'parent-imports.log') -Encoding UTF8
$dlls=@($imports|ForEach-Object{if($_ -match '^\s*([\w.-]+\.dll)\s*$'){$matches[1].ToUpperInvariant()}})
if($dlls.Count -eq 0 -or @($dlls|Where-Object{$_ -notin @('KERNEL32.DLL','USER32.DLL','GDI32.DLL')}).Count){throw 'Unexpected parent imports; no GPU isolation claim'}
$cases=@(
    @{name='positive';marker='GPU_FRAME_IPC_PASS warmup=1 cycles=20 frames=84 closed_children=21 no_parent_gl=1';exit=0},
    @{name='stale-sequence';marker='REJECT frame=0 paint_unchanged=1';exit=1},
    @{name='stale-epoch';marker='REJECT frame=1 paint_unchanged=1';exit=1},
    @{name='bad-stride';marker='REJECT frame=0 paint_unchanged=1';exit=1},
    @{name='bad-size';marker='REJECT frame=0 paint_unchanged=1';exit=1},
    @{name='bad-dimensions';marker='REJECT frame=0 paint_unchanged=1';exit=1},
    @{name='bad-version';marker='REJECT frame=0 paint_unchanged=1';exit=1},
    @{name='bad-commit';marker='REJECT frame=0 paint_unchanged=1';exit=1},
    @{name='bad-header';marker='REJECT frame=0 paint_unchanged=1';exit=1},
    @{name='bad-capacity';marker='REJECT frame=0 paint_unchanged=1';exit=1},
    @{name='truncated';marker='REJECT frame=0 paint_unchanged=1';exit=1},
    @{name='bad-pixel';marker='REJECT frame=0 paint_unchanged=1';exit=1},
    @{name='crash';marker='FAIL response deadline/crash';exit=1},
    @{name='hang';marker='FAIL response deadline/crash';exit=1},
    @{name='close-hang';marker='FAIL close acknowledgement';exit=1},
    @{name='bad-close';marker='FAIL close acknowledgement';exit=1},
    @{name='launch-failure';marker='FAIL launch';exit=1}
)
foreach($case in $cases){
    $dir=Join-Path $root $case.name;$null=New-Item -ItemType Directory -Path $dir
    $out=Join-Path $dir 'parent.stdout.log';$err=Join-Path $dir 'parent.stderr.log'
    $target=if($case.name -eq 'launch-failure'){Join-Path $root 'missing-child.exe'}else{$child}
    $mode=if($case.name -eq 'launch-failure'){'positive'}else{$case.name}
    $p=Start-Process $parent -ArgumentList @(('"'+$target+'"'),('"'+$dir+'"'),$mode) -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null=$p.Handle;$ownedPid=$p.Id;$done=$p.WaitForExit(240000);$killExit=$null;$confirmed=$done
    if(-not $done){& taskkill.exe /PID $ownedPid /T /F|Out-Null;$killExit=$LASTEXITCODE;$confirmed=$p.WaitForExit(5000)}
    $exit=if($confirmed){$p.ExitCode}else{$null};$p.Dispose()
    $text=[IO.File]::ReadAllText($out)+[IO.File]::ReadAllText($err)
    $ok=$done -and $exit -eq $case.exit -and $text.Contains($case.marker)
    if($case.exit -ne 0){$ok=$ok -and $text.Contains('OWNED_CLEANUP_OK') -and $text.Contains('PARENT_VIEW_CLEANUP_OK')}
    $ok=$ok -and (Get-FileHash $parent).Hash -eq $ph -and (Get-FileHash $child).Hash -eq $ch
    [ordered]@{name=$name;case=$case.name;passed=$ok;exit_code=$exit;expected_exit=$case.exit;timeout=(-not $done);owned_pid=$ownedPid;termination_confirmed=$confirmed;kill_exit=$killExit;parent_sha256=$ph;child_sha256=$ch;artifacts=$dir;readiness_evidence=$false;scope='shared-memory GPU component; not native resource gate or hardware attestation'}|ConvertTo-Json -Compress|Add-Content -LiteralPath (Join-Path $logs 'results.jsonl') -Encoding UTF8
    Write-Output "GPU IPC case=$($case.name) exit=$exit validated=$ok artifacts=$dir"
    if(-not $ok){Get-Content -LiteralPath $err -Tail 12;throw "IPC case failed: $($case.name)"}
}
Write-Output "IPC component complete; capture=$root\positive\frame-odd.bmp; original native gate unchanged"
