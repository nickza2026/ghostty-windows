# One existing functional suite; not GPU-busy/performance qualification.
param([ValidateRange(30,300)][int]$TimeoutSeconds=180)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$zig=Join-Path $env:LOCALAPPDATA 'Programs\Zig\zig-x86_64-windows-0.16.0\zig.exe'
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$name='worker-functional-'+$stamp
$prefix=Join-Path $workspace ('zig-out\'+$name)
$dir=Join-Path $env:LOCALAPPDATA ('Letta\build-logs\ghostty-windows\phase3b-runtime\'+$name)
$null=[IO.Directory]::CreateDirectory($dir)
$inputs=@('build.zig','src/render_worker_client.c','src/render_worker_client_check.c','src/render_worker_client_check.zig','src/renderer/remote/Client.zig','src/renderer/remote/Session.zig','src/renderer/opengl/wgl.zig','src/win32_render_text_worker.zig','src/win32_render_offscreen_test_worker.zig','src/win32_render_late_reply_test_worker.zig','tools/windows/worker-functional-repro.ps1')
$before=@($inputs|ForEach-Object{Get-FileHash -LiteralPath(Join-Path $workspace $_)}|Select-Object Path,Hash)
& $zig build windows-render-client-check -j2 -Dapp-runtime=win32 -Dtarget=x86_64-windows-msvc -Dcpu=baseline -Doptimize=ReleaseSafe -p $prefix --summary all
if($LASTEXITCODE -ne 0){throw 'Private offscreen fixture build failed; no runtime invoked'}
$exe=Join-Path $prefix 'bin\localterm-render-client-check.exe'
$ownedPaths=@($exe,(Join-Path $prefix 'bin\localterm-render-text-worker.exe'),(Join-Path $prefix 'bin\localterm-render-late-reply-test-worker.exe'))
function Get-PrivateProcesses {
    foreach($path in $ownedPaths){
        $escaped=$path.Replace('\','\\').Replace("'","\'")
        Get-CimInstance Win32_Process -Filter ("ExecutablePath = '"+$escaped+"'")|Select-Object ProcessId,ParentProcessId,CreationDate,ExecutablePath
    }
}
$p=[Diagnostics.Process]::new()
$p.StartInfo.FileName=$exe
$p.StartInfo.WorkingDirectory=$workspace
$p.StartInfo.UseShellExecute=$false
$p.StartInfo.CreateNoWindow=$true
$p.StartInfo.RedirectStandardOutput=$true
$p.StartInfo.RedirectStandardError=$true
$timedOut=$false;$forced=$false;$exitCode=$null;$rootExited=$false;$started=$false
$stdout='';$stderr='';$remaining=@();$failure=$null
try {
    if(-not $p.Start()){throw 'Private fixture did not start'}
    $started=$true
    $null=$p.Handle
    $outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync()
    if(-not $p.WaitForExit($TimeoutSeconds*1000)){
        $timedOut=$true;$forced=$true
        # Exact retained root HANDLE only. Child jobs are kill-on-parent-close.
        $p.Kill();$null=$p.WaitForExit(10000)
    }
    $rootExited=$p.HasExited
    if($rootExited){$exitCode=$p.ExitCode}
    $observeUntil=[DateTime]::UtcNow.AddSeconds(5)
    do {
        $remaining=@(Get-PrivateProcesses)
        if(-not $remaining.Count){break}
        Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $observeUntil)
    if($outTask.Wait(5000)){$stdout=$outTask.Result}else{$failure='stdout pipe not closed'}
    if($errTask.Wait(5000)){$stderr=$errTask.Result}else{$failure='stderr pipe not closed'}
}catch {
    $failure=$_.Exception.Message
}finally {
    if($started -and -not $rootExited -and -not $p.HasExited){$forced=$true;$p.Kill();$null=$p.WaitForExit(10000);$rootExited=$p.HasExited}
    $p.Dispose()
}
[IO.File]::WriteAllText((Join-Path $dir 'stdout.log'),$stdout,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $dir 'stderr.log'),$stderr,[Text.UTF8Encoding]::new($false))
$after=@($inputs|ForEach-Object{Get-FileHash -LiteralPath(Join-Path $workspace $_)}|Select-Object Path,Hash)
$changed=@(Compare-Object $before $after -Property Path,Hash).Count -ne 0
$offscreenCount=@([regex]::Matches($stderr,'WORKER_OFFSCREEN_OK')).Count
$finalMarker=$stderr -match 'PASS real GPU readback before50ms deadline'
$success=($exitCode -eq 0 -and -not $timedOut -and -not $forced -and $rootExited -and -not $remaining.Count -and -not $changed -and -not $failure -and $offscreenCount -gt 0 -and $finalMarker)
$result=[ordered]@{name=$name;executable=$exe;binary_sha256=@($ownedPaths|ForEach-Object{Get-FileHash $_}|Select-Object Path,Hash);source_sha256=$before;source_changed=$changed;exit_code=$exitCode;timed_out=$timedOut;outer_forced_cleanup=$forced;root_exit_confirmed=$rootExited;remaining_private_prefix_processes=$remaining;offscreen_context_markers=$offscreenCount;late_rendered_final_marker=$finalMarker;functional_suite_success=$success;failure=$failure;gpu_busy_or_performance_qualification=$false;historical_faults_automatically_resolved=$false}
$result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $dir 'result.json') -Encoding UTF8
Write-Output ('ARTIFACT='+$dir)
$stderr -split '\r?\n'|Where-Object{$_ -match 'PASS |error:|failure|receipt|OFFSCREEN_OK|diagnostic'}|Select-Object -Last 24
if(-not $success){throw 'Bounded functional reproduction failed; preserve its original status and diagnose, no retry-to-green'}
