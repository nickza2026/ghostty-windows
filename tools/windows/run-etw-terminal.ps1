$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$controlRoot=(Get-Content (Join-Path $repo 'zig-out/etw-control-current.txt') -Raw).Trim()
$qualified=Get-Content (Join-Path $controlRoot 'qualification.json') -Raw|ConvertFrom-Json
$parseReceipt=Get-Content (Join-Path $controlRoot 'decode-v3-receipt.json') -Raw|ConvertFrom-Json
if(-not $qualified.qualified -or $qualified.matched_count -ne 10 -or $parseReceipt.selftest_exit -ne 0 -or -not $parseReceipt.input_unchanged){throw 'ETW control not qualified; no terminal'}
if((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Native actor must remain non-elevated'}
$previous=Join-Path $repo 'zig-out/ownership-20261104-095534-477'
$build=Get-Content (Join-Path $previous 'build.json') -Raw|ConvertFrom-Json
$before=Get-Content (Join-Path $previous 'source-before.json') -Raw|ConvertFrom-Json
function Assert-Source {
    if((Get-FileHash $script:build.exe -Algorithm SHA256).Hash -ne $script:build.sha256){throw 'Native candidate hash changed'}
    if(@($script:before|Where-Object{(Get-FileHash $_.path -Algorithm SHA256).Hash -ne $_.hash}).Count){throw 'Native source changed since candidate build'}
}
Assert-Source
$prepared=@(& (Join-Path $PSScriptRoot 'run-etw-handle-control.ps1') -PrepareOnly -PreserveCurrentPointer)
$paths=@($prepared|Where-Object{$_ -is [string] -and $_.StartsWith('ETW_PREPARED=')})
if($paths.Count -ne 1){throw 'No unique prepared collector'}
$root=$paths[0].Substring('ETW_PREPARED='.Length)
$config=Join-Path $root 'config.json'
$cfg=Get-Content $config -Raw|ConvertFrom-Json
$cfg|Add-Member -NotePropertyName mode -NotePropertyValue 'collect'
$cfg|Add-Member -NotePropertyName qualified_control_root -NotePropertyValue $controlRoot
$cfg|ConvertTo-Json -Depth 6|Set-Content $config -Encoding UTF8
Set-Content (Join-Path $repo 'zig-out/etw-terminal-current.txt') $root -Encoding UTF8
$elevated=$null;$wrapper=$null;$native=$null;$moduleMap=@{};$nativeId=$null
$failure=$null;$receipt=$null;$moduleFailures=0;$terminalStarted=$false;$actorStarted=$null
$savedLedger=[Environment]::GetEnvironmentVariable('LOCALTERM_LIFECYCLE_LEDGER','Process')
try{
    $supervisor=Join-Path $root 'etw-handle-supervise.ps1'
    $elevated=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-File',('"'+$supervisor+'"'),'-Config',('"'+$config+'"')) -Verb RunAs -WindowStyle Hidden -PassThru
    $null=$elevated.Handle
    $wait=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path (Join-Path $root 'ready.json')) -and -not $elevated.HasExited -and $wait.Elapsed.TotalSeconds -lt 10){Start-Sleep -Milliseconds 50}
    if(-not(Test-Path (Join-Path $root 'ready.json'))){throw 'No fresh armed ETW ready receipt; no terminal'}
    $ready=Get-Content (Join-Path $root 'ready.json') -Raw|ConvertFrom-Json
    Assert-Source
    [Environment]::SetEnvironmentVariable('LOCALTERM_LIFECYCLE_LEDGER','1','Process')
    $actorStarted=Get-Date
    $wrapper=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-File',('"'+(Join-Path $PSScriptRoot 'runtime-smoke.ps1')+'"'),'-Mode','lifecycle','-TimeoutSeconds','120','-PssDiagnostics','enabled','-Executable',('"'+$build.exe+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'harness.stdout.log') -RedirectStandardError (Join-Path $root 'harness.stderr.log')
    $null=$wrapper.Handle;$terminalStarted=$true
    [Environment]::SetEnvironmentVariable('LOCALTERM_LIFECYCLE_LEDGER',$savedLedger,'Process')
    $actorClock=[Diagnostics.Stopwatch]::StartNew();$nextModules=0
    while(-not $wrapper.HasExited -and $actorClock.Elapsed.TotalSeconds -lt 128){
        if(-not $native){
            $rows=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($wrapper.Id) AND Name='localterm-dev.exe'" -Property ProcessId,ExecutablePath,CreationDate|Where-Object{$_.ExecutablePath -eq $build.exe -and $_.CreationDate -ge $actorStarted.AddSeconds(-1)})
            if($rows.Count -gt 1){throw 'Ambiguous owned native child'}
            if($rows.Count -eq 1){
                $native=Get-Process -Id $rows[0].ProcessId;$null=$native.Handle;$nativeId=$native.Id
                [ordered]@{pid=$nativeId;parent_pid=$wrapper.Id;start_utc=$native.StartTime.ToUniversalTime().ToString('o');executable=$build.exe;sha256=$build.sha256;elevated=$false}|ConvertTo-Json|Set-Content (Join-Path $root 'native-identity.json') -Encoding UTF8
            }
        }
        if($native -and -not $native.HasExited -and $actorClock.ElapsedMilliseconds -ge $nextModules){
            $nextModules=$actorClock.ElapsedMilliseconds+1000
            try{foreach($m in $native.Modules){
                $base=$m.BaseAddress.ToInt64().ToString('x');$key=$base+'|'+$m.ModuleMemorySize+'|'+$m.FileName
                if(-not $moduleMap.ContainsKey($key)){$moduleMap[$key]=[pscustomobject]@{base=$base;size=$m.ModuleMemorySize;path=$m.FileName;first_observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}}
            }}catch{$moduleFailures++}
        }
        Start-Sleep -Milliseconds $(if($native){1000}else{50})
    }
    if(-not $wrapper.HasExited){throw 'Owned harness exceeded its native 120s deadline plus cleanup allowance'}
    if(-not $native -or -not $native.HasExited){throw 'Native identity/exit not confirmed'}
    $logs=Join-Path $env:LOCALAPPDATA 'Letta/build-logs/ghostty-windows/phase3b-runtime/results.jsonl'
    $matches=@(Get-Content $logs -Encoding UTF8|ForEach-Object{if($_.Trim()){$r=$_|ConvertFrom-Json;if($r.executable -eq $build.exe -and [DateTimeOffset]::Parse($r.started) -ge $actorStarted){$r}}})
    if($matches.Count -ne 1){throw 'Missing unique fresh native receipt'}
    $receipt=$matches[0]
    $receipt|ConvertTo-Json -Depth 8|Set-Content (Join-Path $root 'native-receipt.json') -Encoding UTF8
    Assert-Source
}catch{$failure=$_.Exception.Message}
finally{
    [Environment]::SetEnvironmentVariable('LOCALTERM_LIFECYCLE_LEDGER',$savedLedger,'Process')
    # The existing harness owns descendant cleanup. Only retained exact actors
    # may be stopped here on an exceptional harness failure, never by name.
    if($native -and -not $native.HasExited){$native.Kill();$null=$native.WaitForExit(3000)}
    if($wrapper -and -not $wrapper.HasExited){$null=$wrapper.WaitForExit(5000);if(-not $wrapper.HasExited){$wrapper.Kill();$null=$wrapper.WaitForExit(1000)}}
    $stopPath=Join-Path $root 'stop.request'
    $stopFile=[IO.File]::Open($stopPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$stopFile.Dispose()
    if($elevated -and -not $elevated.HasExited){$null=$elevated.WaitForExit(10000)}
    @($moduleMap.Values)|ConvertTo-Json -Depth 4|Set-Content (Join-Path $root 'native-modules.json') -Encoding UTF8
    $super=if(Test-Path (Join-Path $root 'supervisor.json')){Get-Content (Join-Path $root 'supervisor.json') -Raw|ConvertFrom-Json}else{$null}
    $collection=@(if(Test-Path (Join-Path $root 'collection.jsonl')){Get-Content (Join-Path $root 'collection.jsonl')|ForEach-Object{$_|ConvertFrom-Json}})
    $collected=@($collection|Where-Object{$_.kind -eq 'result'})
    $complete=$collected.Count -eq 1 -and $collected[0].complete -and $super -and $super.cleanup_exit -eq 0 -and -not $super.timeout
    [ordered]@{terminal_launched=$terminalStarted;native_pid=$nativeId;native_passed=if($receipt){$receipt.passed}else{$false};capture_complete=[bool]$complete;failure=$failure;collector_supervisor=$super;collection_result=$collected;module_count=$moduleMap.Count;module_query_failures=$moduleFailures;diagnostic_only=$true;source_unchanged=($null -eq $failure);control_qualified=$true}|ConvertTo-Json -Depth 7|Set-Content (Join-Path $root 'terminal-run.json') -Encoding UTF8
    if($native){$native.Dispose()};if($wrapper){$wrapper.Dispose()};if($elevated){$elevated.Dispose()}
}
Write-Output ('ETW_TERMINAL_PRIVATE='+$root)
Get-Content (Join-Path $root 'terminal-run.json') -Raw
if($failure){throw $failure}
if(-not $complete){throw 'Incomplete/lost/capped ETW capture; no same-run attribution claim'}
