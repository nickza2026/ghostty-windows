$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$controlRoot=(Get-Content (Join-Path $repo 'zig-out/etw-stream-control-current.txt') -Raw).Trim()
$q=Get-Content (Join-Path $controlRoot 'qualification.json') -Raw|ConvertFrom-Json
if(-not $q.qualified -or $q.matched_count -ne 10){throw 'Streaming control not qualified'}
if((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Native actor must remain nonadmin'}
$old=Join-Path $repo 'zig-out/ownership-20261104-095534-477'
$build=Get-Content (Join-Path $old 'build.json') -Raw|ConvertFrom-Json
$inputs=Get-Content (Join-Path $old 'source-before.json') -Raw|ConvertFrom-Json
function Assert-Native {
    if((Get-FileHash $script:build.exe -Algorithm SHA256).Hash -ne $script:build.sha256){throw 'Native binary changed'}
    $changed=@($script:inputs|Where-Object{(Get-FileHash $_.path -Algorithm SHA256).Hash -ne $_.hash})
    # The new opt-in launcher branch is separately recorded; no app/build input
    # may be silently waived. This script is not a normal readiness invocation.
    $unexpected=@($changed|Where-Object{[IO.Path]::GetFullPath($_.path) -ne [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'runtime-smoke.ps1'))})
    if($unexpected.Count){throw 'Native build input changed'}
}
Assert-Native
$prepared=@(& (Join-Path $PSScriptRoot 'prepare-etw-stream.ps1') -Mode collect)
$paths=@($prepared|Where-Object{$_ -is [string] -and $_.StartsWith('STREAM_PREPARED=')})
if($paths.Count -ne 1){throw 'No unique prepared streaming collector'}
$root=$paths[0].Substring('STREAM_PREPARED='.Length)
$gate=Join-Path $root 'gate';$null=New-Item -ItemType Directory -Path $gate
Set-Content (Join-Path $repo 'zig-out/etw-stream-terminal-current.txt') $root -Encoding UTF8
function Fresh-Text([string]$p,[string]$text){
    $f=[IO.File]::Open($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$bytes=[Text.Encoding]::ASCII.GetBytes($text);$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
}
function Await-Json([string]$p,[int]$milliseconds){
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while($clock.ElapsedMilliseconds -lt $milliseconds){
        if(Test-Path $p){try{return Get-Content $p -Raw -Encoding UTF8|ConvertFrom-Json}catch [IO.IOException]{}}
        Start-Sleep -Milliseconds 20
    }
    throw ('Missing fresh handshake: '+[IO.Path]::GetFileName($p))
}
$elevated=$null;$wrapper=$null;$native=$null;$nativeId=$null;$receipt=$null;$failure=$null;$bound=$false;$resumed=$false;$modules=@{};$moduleFailures=0
$savedLedger=[Environment]::GetEnvironmentVariable('LOCALTERM_LIFECYCLE_LEDGER','Process')
try{
    $elevated=Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-File',('"'+(Join-Path $root 'etw-stream-supervise.ps1')+'"'),'-Config',('"'+(Join-Path $root 'config.json')+'"')) -Verb RunAs -WindowStyle Hidden -PassThru
    $null=$elevated.Handle;$ready=Await-Json (Join-Path $root 'ready.json') 10000
    Assert-Native
    [Environment]::SetEnvironmentVariable('LOCALTERM_LIFECYCLE_LEDGER','1','Process')
    $started=Get-Date
    $wrapper=Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-File',('"'+(Join-Path $PSScriptRoot 'runtime-smoke.ps1')+'"'),'-Mode','lifecycle','-TimeoutSeconds','120','-PssDiagnostics','enabled','-Executable',('"'+$build.exe+'"'),'-EtwLaunchHelper',('"'+(Join-Path $root 'etw-suspended-launch.exe')+'"'),'-EtwGateDirectory',('"'+$gate+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'harness.stdout.log') -RedirectStandardError (Join-Path $root 'harness.stderr.log')
    $null=$wrapper.Handle
    [Environment]::SetEnvironmentVariable('LOCALTERM_LIFECYCLE_LEDGER',$savedLedger,'Process')
    $identity=Await-Json (Join-Path $gate 'native-identity.json') 7000
    if($identity.native_image -ne $build.exe -or $identity.resumed -or $identity.native_pid -eq $identity.launcher_pid){throw 'Suspended actor identity invalid'}
    $native=Get-Process -Id $identity.native_pid;$null=$native.Handle;$nativeId=$native.Id
    if($native.HasExited -or $native.StartTime.ToFileTimeUtc() -ne [int64]$identity.native_creation_filetime){throw 'Native creation identity mismatch'}
    $parent=Get-CimInstance Win32_Process -Filter "ProcessId=$($identity.launcher_pid)" -Property ParentProcessId,ExecutablePath
    if($parent.ParentProcessId -ne $wrapper.Id -or $parent.ExecutablePath -ne (Join-Path $root 'etw-suspended-launch.exe')){throw 'Suspended launcher ownership mismatch'}
    Fresh-Text (Join-Path $root 'binding.txt') ([string]$nativeId)
    $ack=Await-Json (Join-Path $root 'binding-ack.json') 2000
    if($ack.pid -ne $nativeId -or -not $ack.bound){throw 'Collector did not bind exact native PID'}
    $bound=$true;Fresh-Text (Join-Path $gate 'resume.request') 'resume';$resumed=$true
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while(-not $wrapper.HasExited -and $clock.Elapsed.TotalSeconds -lt 124){
        if(-not $native.HasExited){try{foreach($m in $native.Modules){$base=$m.BaseAddress.ToInt64().ToString('x');$key=$base+'|'+$m.ModuleMemorySize+'|'+$m.FileName;if(-not $modules.ContainsKey($key)){$modules[$key]=[pscustomobject]@{base=$base;size=$m.ModuleMemorySize;path=$m.FileName;first_utc=[DateTimeOffset]::UtcNow.ToString('o')}}}}catch{$moduleFailures++}}
        Start-Sleep -Milliseconds 1000
    }
    if(-not $wrapper.HasExited -or -not $native.HasExited){throw 'Owned native/harness exit not confirmed'}
    $launcher=Await-Json (Join-Path $gate 'launcher.json') 1000
    if(-not $launcher.resumed -or -not $launcher.child_exited -or $launcher.cleanup){throw 'Native launcher did not exit naturally'}
    $logs=Join-Path $env:LOCALAPPDATA 'Letta/build-logs/ghostty-windows/phase3b-runtime/results.jsonl'
    $matches=@(Get-Content $logs -Encoding UTF8|ForEach-Object{if($_.Trim()){$r=$_|ConvertFrom-Json;if($r.executable -eq $build.exe -and [DateTimeOffset]::Parse($r.started) -ge $started){$r}}})
    if($matches.Count -ne 1 -or -not $matches[0].etw_suspended_diagnostic -or $matches[0].readiness_evidence){throw 'No unique diagnostic-only native receipt'}
    $receipt=$matches[0];$receipt|ConvertTo-Json -Depth 8|Set-Content (Join-Path $root 'native-receipt.json') -Encoding UTF8
    Assert-Native
}catch{$failure=$_.Exception.Message}
finally{
    [Environment]::SetEnvironmentVariable('LOCALTERM_LIFECYCLE_LEDGER',$savedLedger,'Process')
    if($native -and -not $native.HasExited){$native.Kill();$null=$native.WaitForExit(3000)}
    if($wrapper -and -not $wrapper.HasExited){$null=$wrapper.WaitForExit(5000);if(-not $wrapper.HasExited){$wrapper.Kill();$null=$wrapper.WaitForExit(1000)}}
    Fresh-Text (Join-Path $root 'stop.request') 'stop'
    if($elevated -and -not $elevated.HasExited){$null=$elevated.WaitForExit(10000)}
    @($modules.Values)|ConvertTo-Json -Depth 4|Set-Content (Join-Path $root 'native-modules.json') -Encoding UTF8
    $s=if(Test-Path (Join-Path $root 'supervisor.json')){Get-Content (Join-Path $root 'supervisor.json') -Raw|ConvertFrom-Json}else{$null}
    $rows=@(if(Test-Path (Join-Path $root 'decoded.jsonl')){Get-Content (Join-Path $root 'decoded.jsonl')|ForEach-Object{$_|ConvertFrom-Json}})
    $result=@($rows|Where-Object{$_.kind -eq 'result'})
    $complete=$bound -and $resumed -and -not $failure -and $s -and $s.exit -eq 0 -and $s.cleanup_exit -eq 0 -and -not $s.timeout -and $result.Count -eq 1 -and $result[0].ok -and -not @(Get-ChildItem $root -File -Filter '*.etl').Count
    [ordered]@{capture_complete=[bool]$complete;failure=$failure;native_pid=$nativeId;bound_before_resume=$bound;resumed=$resumed;native_exited=if($native){$native.HasExited}else{$false};native_passed=if($receipt){$receipt.passed}else{$false};readiness_evidence=$false;stream_result=$result;supervisor=$s;module_count=$modules.Count;module_failures=$moduleFailures;source_harness_sha256=(Get-FileHash (Join-Path $PSScriptRoot 'runtime-smoke.ps1') -Algorithm SHA256).Hash;raw_global_etl=$false}|ConvertTo-Json -Depth 7|Set-Content (Join-Path $root 'terminal-run.json') -Encoding UTF8
    if($native){$native.Dispose()};if($wrapper){$wrapper.Dispose()};if($elevated){$elevated.Dispose()}
}
Write-Output ('ETW_STREAM_TERMINAL_PRIVATE='+$root)
Get-Content (Join-Path $root 'terminal-run.json') -Raw
if($failure){throw $failure};if(-not $complete){throw 'Streaming incomplete; no Event attribution'}
