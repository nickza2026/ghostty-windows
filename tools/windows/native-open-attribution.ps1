# Diagnostic only. Plain gu disables our breakpoints: partial capture/blind intervals.
param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [ValidateSet('control','native')][string]$Mode='control',
    [string]$QualifiedControlReceipt,
    [ValidateRange(0,240)][int]$TimeoutSeconds=0
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($TimeoutSeconds -eq 0){$TimeoutSeconds=if($Mode -eq 'control'){60}else{240}}
if($TimeoutSeconds -lt 30){throw 'Deadline minimum 30 seconds'}
function Convert-CdbProtocolLine([string]$Line){return $Line -replace '^(?:\s*[0-9a-fA-F]+:[0-9a-fA-F]+>\s*)+',''}
function Hex([string]$s){[Convert]::ToUInt64(($s -replace '`',''),16)}
function New-OpenCondition([string]$Api,[string]$Low,[string]$High){
    if($Api -eq 'CreateThread'){return "(@r8 >= $Low) and (@r8 < $High)"}
    $caller="(poi(@rsp) >= $Low) and (poi(@rsp) < $High)"
    if($Api -eq 'DuplicateHandle'){return "($caller) and (@rdx == 0xfffffffffffffffe)"}
    return $caller
}
function Test-OpenReturn($Entry,[UInt64]$Tid,[UInt64]$Ip,[UInt64]$Sp){return $Tid -eq $Entry.tid -and $Ip -eq $Entry.return_address -and $Sp -eq ($Entry.entry_sp+8)}
function Test-NativeResourceExit([string]$RunMode,[int]$Code,[string]$ActualStderr){
    if($RunMode -ne 'native' -or $Code -ne 1){return $false}
    $found=$false
    foreach($s in ($ActualStderr -split '\r?\n')){
        if($s -ceq 'error: ResourceGrowth' -or $s -ceq 'error:ResourceGrowth'){$found=$true;continue}
        if($s -match '(?i)(error(?:\([^)]*\))?\s*:|panic|critical|fatal)'){return $false}
    }
    return $found
}
$controllerHash=(Get-FileHash -LiteralPath $PSCommandPath).Hash
$source=Join-Path $PSScriptRoot 'open-attribution-control.c'
$sourceHash=(Get-FileHash -LiteralPath $source).Hash
if($Mode -eq 'native'){
    if(-not $QualifiedControlReceipt){throw 'NOT QUALIFIED: same-revision complete private control receipt required'}
    $proof=Get-Content -LiteralPath $QualifiedControlReceipt -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $proof.protocol_complete -or $proof.application_failure -or $proof.application_exit -ne 0 -or $proof.create_thread_site -ne 'KERNEL32!CreateThreadStub'){throw 'NOT QUALIFIED: ordinary-route protocol/control exit required'}
    if($proof.mode -ne 'control' -or -not $proof.control_qualified -or $proof.controller_sha256 -ne $controllerHash -or $proof.control_source_sha256 -ne $sourceHash -or $proof.controller_changed_during_run -or $proof.source_changed_during_run -or $proof.failure -or -not $proof.baseline -or -not $proof.final -or -not $proof.histories_complete -or $proof.timed_out -or $proof.forced_cleanup -or -not $proof.root_exit_confirmed -or -not $proof.target_exit_confirmed -or $proof.observed_remaining_descendants.Count -or $proof.validated_returns.Count -ne 3 -or $proof.expected_handles.Count -ne 3){throw 'NOT QUALIFIED: incomplete/different-revision control receipt'}
    foreach($api in @('CreateEventW','DuplicateHandle','CreateThread')){
        $r=@($proof.validated_returns|Where-Object{$_.api -eq $api -and $_.successful -and $_.invocation_verified})
        $e=@($proof.expected_handles|Where-Object{$_.api -eq $api})
        if($r.Count -ne 1 -or $e.Count -ne 1 -or $r[0].handle -ne $e[0].handle){throw 'NOT QUALIFIED: API-specific exact handle mismatch'}
    }
    if($proof.debugger_exit -ne 0 -or $proof.handle_histories.Count -ne 3 -or @($proof.handle_histories|Where-Object{-not $_.complete}).Count){throw 'NOT QUALIFIED: missing successful exit/per-handle histories'}
    foreach($r in $proof.validated_returns){if(@($proof.handle_histories|Where-Object{$_.handle -eq $r.handle -and $_.complete}).Count -ne 1){throw 'NOT QUALIFIED: unmatched handle history'}}
    if(-not (Test-Path -LiteralPath $proof.executable) -or (Get-FileHash -LiteralPath $proof.executable).Hash -ne $proof.sha256){throw 'NOT QUALIFIED: control executable changed'}
}
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$exe=(Resolve-Path -LiteralPath $Executable).ProviderPath
if(-not $exe.StartsWith((Join-Path $workspace 'zig-out')+'\',[StringComparison]::OrdinalIgnoreCase) -or $exe -match '["\r\n]'){throw 'Owned zig-out target only'}
if($Mode -eq 'native' -and ((Get-FileHash -LiteralPath $exe).Hash -ne '10ADEFA20075AC921A47CCF63DA56D11467E6E6D769A7916184EEDB197BA2741' -or $exe -ne (Join-Path $workspace 'zig-out\attributes-build-20261026-202012-333\bin\localterm-dev.exe'))){throw 'Fixed native revision only'}
if($Mode -eq 'control' -and [IO.Path]::GetFileName($exe) -ne 'open-attribution-control.exe'){throw 'Private control executable only'}
if($Mode -eq 'control' -and $TimeoutSeconds -gt 60){throw 'Control deadline maximum 60 seconds'}
$exeHash=(Get-FileHash -LiteralPath $exe).Hash
$stream=[IO.File]::OpenRead($exe);$reader=[IO.BinaryReader]::new($stream)
try{$stream.Position=0x3c;$offset=$reader.ReadInt32();$stream.Position=$offset;if($reader.ReadUInt32() -ne 0x4550){throw 'Invalid PE'};$stream.Position=$offset+4+20+68;if($reader.ReadUInt16() -ne 2){throw 'GUI subsystem 2 required'}}finally{$reader.Dispose();$stream.Dispose()}
$cdb='C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe'
$signature=Get-AuthenticodeSignature -LiteralPath $cdb
if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation'){throw 'Signed Microsoft debugger required'}
$base=Join-Path $env:LOCALAPPDATA 'Letta\build-logs\ghostty-windows\phase3b-runtime'
$name='open-attribution-'+$Mode+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$logs=Join-Path $base $name;$null=[IO.Directory]::CreateDirectory($logs)
$initial=Join-Path $logs 'initial.cdb';$stdout=Join-Path $logs 'stdout.log';$stderr=Join-Path $logs 'stderr.log'
$initialText=@'
!htrace -enable 0x10000
bm *!localterm_native_htrace_marker ".if (@rcx == 1) { .printf \"LO_BASE pid=%x\n\", @$tpid } .else { .echo LO_FINAL }"
g
'@
[IO.File]::WriteAllText($initial,$initialText,[Text.UTF8Encoding]::new($false))
$p=[Diagnostics.Process]::new();$p.StartInfo.FileName=$cdb;$p.StartInfo.WorkingDirectory=$workspace
$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.WindowStyle='Hidden'
$p.StartInfo.RedirectStandardInput=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
$cache=Join-Path $env:LOCALAPPDATA 'Letta\tools\windows-debugger\symbols'
$symbols=[IO.Path]::GetDirectoryName($exe)+';srv*'+$cache+'*https://msdl.microsoft.com/download/symbols'
$p.StartInfo.Arguments='-hd -G -nosqm -y "'+$symbols+'" -cf "'+$initial+'" "'+$exe+'"'
$writer=[IO.StreamWriter]::new($stdout,$false,[Text.UTF8Encoding]::new($false));$writer.AutoFlush=$true
$clock=[Diagnostics.Stopwatch]::StartNew();$started=Get-Date
$baseline=$false;$final=$false;$history=$false;$timedOut=$false;$rootExited=$false;$targetExited=$false;$forced=$false;$launched=$false
$failure=$null;$pending=$null;$target=$null;$targetId=$null;$exitCode=$null;$errTask=$null;$query=$null;$bounds=@{};$remaining=@();$lines=0;$stops=0
$actualStderr=$null;$protocolComplete=$false;$applicationFailure=$null
$historyHandle=$null;$historyText=[Collections.Generic.List[string]]::new();$histories=[Collections.Generic.List[object]]::new()
$returns=[Collections.Generic.List[object]]::new();$expected=[Collections.Generic.List[object]]::new()
function Send([string]$s){$p.StandardInput.WriteLine($s);$p.StandardInput.Flush()}
function Arm-OpenBreakpoints {
    $i=1
    foreach($api in @('CreateEventW','DuplicateHandle','CreateThread')){
        $range=if($api -eq 'CreateThread'){$bounds.amd}else{$bounds.rpc}
        $condition=New-OpenCondition $api $range[0] $range[1]
        $module=if($api -eq 'CreateThread'){'KERNEL32'}else{'KERNELBASE'}
        # Current Microsoft public symbols expose the ordinary Kernel32 export
        # as CreateThreadStub (verified by owned x kernel32!*CreateThread*).
        # Resolve by symbol in each process; never copy a prior run's address.
        $symbol=if($api -eq 'CreateThread'){'CreateThreadStub'}else{$api}
        Send ('bp'+$i+' '+$module+'!'+$symbol+' ".if ('+$condition+') { .printf \"LO_ENTER api='+$api+' tid=%x ret=%p sp=%p out=%p\n\", @$tid, poi(@rsp), @rsp, @r9; k } .else { gc }"')
        $i++
    }
}
# Inherit normal workload configuration; remove only smoke switches as existing
# diagnostic does. Native retains default lifecycle PSS, warmup and thresholds.
$keys=@('LOCALTERM_WINDOW_SMOKE','LOCALTERM_TERMINAL_SMOKE','LOCALTERM_TERMINAL','LOCALTERM_INPUT_SMOKE','LOCALTERM_LIFECYCLE_SMOKE','LOCALTERM_LIFECYCLE_PSS','LOCALTERM_TERMINAL_CASE','LOCALTERM_MOUSE_SMOKE','LOCALTERM_THAI_TUI_SMOKE','LOCALTERM_THAI_TUI_LEGACY','LOCALTERM_BACKGROUND_SMOKE','LOCALTERM_THAI_MODEL_REQUIRED','LOCALTERM_TITLE_BACKPRESSURE_SMOKE','LOCALTERM_CONPTY_WIDTH','LOCALTERM_CONPTY_PROVIDER','LOCALTERM_CONPTY_EXPERIMENT','LOCALTERM_PREVIEW_BACKGROUND','LOCALTERM_GPU_TEXT_FRAME_CHECK','LOCALTERM_VIEWPORT_SMOKE','LOCALTERM_KITTY_IMAGE_SMOKE','LOCALTERM_KITTY_IMAGE_REFERENCE')
$saved=@{};$rootStart=$null;$targetStart=$null
try{
    try{
        foreach($key in $keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$null,'Process')}
        if($Mode -eq 'native'){$env:LOCALTERM_LIFECYCLE_SMOKE='1';$env:LOCALTERM_LIFECYCLE_PSS='1';$env:LOCALTERM_CONPTY_PROVIDER='app-local';$env:LOCALTERM_CONPTY_EXPERIMENT='1'}
        if(-not $p.Start()){throw 'Debugger failed to start'};$launched=$true;$null=$p.Handle;$rootStart=$p.StartTime.ToUniversalTime().ToString('o')
    }finally{foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}}
    $errTask=$p.StandardError.ReadToEndAsync();$read=$p.StandardOutput.ReadLineAsync()
    while($true){
        if($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;throw 'Debugger deadline exceeded'}
        if(-not $read.IsCompleted){Start-Sleep -Milliseconds 15;continue}
        $line=$read.GetAwaiter().GetResult();if($null -eq $line){break}
        $writer.WriteLine($line);$lines++;$line=Convert-CdbProtocolLine $line
        if($lines -gt 24000){throw 'Output cap exceeded'}
        if($line -match '(?i)^(Numeric expression missing|Syntax error|Couldn.t resolve|Bad register|Unable to resolve|Memory access error|.*syntax error in)'){throw ('Debugger expression failure: '+$line)}
        if($line -match '^LO_HISTORY_BEGIN handle=(0x[0-9a-f]+)\b'){
            if($null -ne $historyHandle){throw 'Overlapping handle histories'}
            $historyHandle=$Matches[1];$historyText.Clear()
        }elseif($null -ne $historyHandle -and $line -eq 'LO_HANDLE_HISTORY_END'){
            $body=$historyText -join "`n"
            if($body -notmatch '(?i)Handle\s*=\s*(?:0x)?0*'+[regex]::Escape($historyHandle.Substring(2))+'\b' -or $body -notmatch '(?i)OPEN' -or $body -match '(?i)(unable|failed|no trace|not enabled|invalid handle)'){throw ('Missing complete OPEN history for '+$historyHandle)}
            $histories.Add([ordered]@{handle=$historyHandle;complete=$true});$historyHandle=$null
        }elseif($null -ne $historyHandle){$historyText.Add($line)}
        if($line -match '^LO_BASE pid=([0-9a-fA-F]+)\b'){
            if($baseline){throw 'Duplicate baseline'};$baseline=$true;$targetId=Hex $Matches[1]
            $target=Get-Process -Id ([int]$targetId);$null=$target.Handle
            $targetStart=$target.StartTime.ToUniversalTime().ToString('o')
            if(-not [string]::Equals($target.MainModule.FileName,$exe,[StringComparison]::OrdinalIgnoreCase) -or $target.StartTime -lt $started){throw 'Owned debuggee identity mismatch'}
            $query='rpc'
            if($Mode -eq 'control'){Send 'lm a @$exentry'}else{Send 'lm m RPCRT4'}
            Send '.echo LO_RPC_BOUNDS_END'
        }elseif($null -ne $query -and $line -match '^\s*([0-9a-fA-F`]{8,})\s+([0-9a-fA-F`]{8,})\s+\S+'){
            $lo=Hex $Matches[1];$hi=Hex $Matches[2]
            if($hi -le $lo -or $bounds.ContainsKey($query)){throw 'Ambiguous module range'}
            $bounds[$query]=@(('0x{0:x}' -f $lo),('0x{0:x}' -f $hi))
        }elseif($line -eq 'LO_RPC_BOUNDS_END'){
            if(-not $bounds.ContainsKey('rpc')){throw 'Missing current caller module bounds'}
            $query='amd';if($Mode -eq 'control'){Send 'lm a @$exentry'}else{Send 'lm m amdihk64'};Send '.echo LO_AMD_BOUNDS_END'
        }elseif($line -eq 'LO_AMD_BOUNDS_END'){
            if(-not $bounds.ContainsKey('amd')){throw 'Missing current thread-start module bounds'}
            $query=$null;Send '!htrace -snapshot';Arm-OpenBreakpoints;Send 'g'
        }elseif($line -match '^LO_ENTER api=(CreateEventW|DuplicateHandle|CreateThread) tid=([0-9a-fA-F]+) ret=([0-9a-fA-F`]+) sp=([0-9a-fA-F`]+) out=([0-9a-fA-F`]+)\b'){
            if(-not $baseline -or $final -or $null -ne $pending){throw 'Unexpected invocation'}
            $stops++;if($stops -gt 48){throw 'Filtered stop cap exceeded'}
            $pending=[ordered]@{api=$Matches[1];tid=(Hex $Matches[2]);return_address=(Hex $Matches[3]);entry_sp=(Hex $Matches[4]);output_pointer=(Hex $Matches[5])}
            Send 'bd *';Send 'gu';Send '.printf "LO_RETURN tid=%x ip=%p sp=%p value=%p\n", @$tid, @rip, @rsp, @rax'
        }elseif($line -match '^LO_RETURN tid=([0-9a-fA-F]+) ip=([0-9a-fA-F`]+) sp=([0-9a-fA-F`]+) value=([0-9a-fA-F`]+)\b'){
            if($null -eq $pending){throw 'Unpaired return'}
            $tid=Hex $Matches[1];$ip=Hex $Matches[2];$sp=Hex $Matches[3];$value=Hex $Matches[4]
            if(-not (Test-OpenReturn $pending $tid $ip $sp)){throw 'Ambiguous gu return TID/RIP/RSP'}
            $pending.return_tid=$tid;$pending.return_ip=$ip;$pending.return_sp=$sp;$pending.invocation_verified=$true;$pending.return_value=$value
            if($pending.api -eq 'DuplicateHandle' -and ($value -band 0xffffffff) -ne 0){
                if($pending.output_pointer -eq 0){throw 'Null successful DuplicateHandle output pointer'}
                Send ('.printf "LO_OUTPUT handle=%p\n", poi(0x{0:x})' -f $pending.output_pointer)
            }else{
                $handle=if($pending.api -eq 'DuplicateHandle'){[UInt64]0}else{$value}
                $pending.handle='0x{0:x}' -f $handle;$pending.successful=($handle -ne 0);$returns.Add($pending);$pending=$null
                Send 'be *';Send 'g'
            }
        }elseif($line -match '^LO_OUTPUT handle=([0-9a-fA-F`]+)\b'){
            if($null -eq $pending -or $pending.api -ne 'DuplicateHandle' -or -not $pending.invocation_verified){throw 'Unverified output-pointer read'}
            $handle=Hex $Matches[1];$pending.handle='0x{0:x}' -f $handle;$pending.successful=($handle -ne 0);$returns.Add($pending);$pending=$null;Send 'be *';Send 'g'
        }elseif($line -match '^LO_EXPECT api=(CreateEventW|DuplicateHandle|CreateThread) handle=([0-9a-fA-F`]+)\b'){
            if($Mode -ne 'control' -or -not $baseline -or $final){throw 'Unexpected private publication'}
            $expected.Add([ordered]@{api=$Matches[1];handle=('0x{0:x}' -f (Hex $Matches[2]))})
        }elseif($line -eq 'LO_FINAL'){
            if(-not $baseline -or $final -or $null -ne $pending){throw 'Incomplete phase protocol'};$final=$true
            Send 'bd *';Send '!htrace -diff'
            foreach($r in $returns){if($r.successful){Send ('.echo LO_HISTORY_BEGIN handle='+$r.handle);Send ('!htrace '+$r.handle);Send '.echo LO_HANDLE_HISTORY_END'}}
            Send '.echo LO_HISTORY_END'
        }elseif($line -eq 'LO_HISTORY_END'){
            if($null -ne $historyHandle -or $histories.Count -ne @($returns|Where-Object{$_.successful}).Count){throw 'Incomplete per-returned-handle histories'}
            $history=$true;Send 'g'
        }
        $read=$p.StandardOutput.ReadLineAsync()
    }
    $rootExited=$p.WaitForExit(3000);if($rootExited){$exitCode=$p.ExitCode}
    if(-not $baseline -or -not $final -or -not $history -or -not $rootExited -or $returns.Count -eq 0){throw 'Incomplete bounded creator-return diagnostic'}
    $protocolComplete=$true
    if(-not $errTask.Wait(3000)){throw 'Actual stderr capture incomplete'}
    $actualStderr=$errTask.Result
    if($actualStderr.Length -gt 1048576){throw 'Stderr output cap exceeded'}
    if($exitCode -ne 0){
        if(Test-NativeResourceExit $Mode $exitCode $actualStderr){$applicationFailure='ResourceGrowth'}
        else{throw ('Unexpected application/debugger exit: '+$exitCode)}
    }
    if($Mode -eq 'control'){
        if($returns.Count -ne 3 -or $expected.Count -ne 3){throw 'Private control requires all three API families'}
        foreach($api in @('CreateEventW','DuplicateHandle','CreateThread')){
            $r=@($returns|Where-Object{$_.api -eq $api -and $_.successful -and $_.invocation_verified});$e=@($expected|Where-Object{$_.api -eq $api})
            if($r.Count -ne 1 -or $e.Count -ne 1 -or $r[0].handle -ne $e[0].handle){throw ('Exact returned handle mismatch: '+$api)}
        }
    }
}catch{$failure=[string]$_}
finally{
    if($launched -and -not $rootExited -and -not $p.HasExited){$forced=$true;& taskkill.exe /PID $p.Id /T /F|Out-Null;$null=$p.WaitForExit(5000);$rootExited=$p.HasExited}
    if($null -ne $target){$targetExited=$target.HasExited;if(-not $targetExited){$forced=$true;$target.Kill();$null=$target.WaitForExit(5000);$targetExited=$target.HasExited}}
    if($launched){
        $parents=[Collections.Generic.Queue[int]]::new();$parents.Enqueue($p.Id);if($null -ne $targetId){$parents.Enqueue([int]$targetId)}
        $seen=[Collections.Generic.HashSet[int]]::new()
        while($parents.Count -gt 0){$parent=$parents.Dequeue();if(-not $seen.Add($parent)){continue}
            foreach($row in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$parent")){
                if($row.CreationDate -lt $started){continue};$remaining+=([int]$row.ProcessId);$parents.Enqueue([int]$row.ProcessId)
                $child=Get-Process -Id $row.ProcessId -ErrorAction SilentlyContinue
                if($null -ne $child){try{$null=$child.Handle;$check=Get-CimInstance Win32_Process -Filter "ProcessId=$($row.ProcessId)";if($null -ne $check -and $check.CreationDate -eq $row.CreationDate -and -not $child.HasExited){$forced=$true;$child.Kill();$null=$child.WaitForExit(5000)}}finally{$child.Dispose()}}
            }
        }
    }
    if(($forced -or -not $targetExited -or $remaining.Count) -and -not $failure){$failure='Shutdown incomplete/forced cleanup/remnants'}
    $controllerChanged=(Get-FileHash -LiteralPath $PSCommandPath).Hash -ne $controllerHash
    $sourceChanged=(Get-FileHash -LiteralPath $source).Hash -ne $sourceHash
    if(($controllerChanged -or $sourceChanged -or (Get-FileHash -LiteralPath $exe).Hash -ne $exeHash) -and -not $failure){$failure='Consumed source/executable changed during run'}
    if($null -ne $errTask -and $errTask.Wait(3000)){[IO.File]::WriteAllText($stderr,$errTask.Result,[Text.UTF8Encoding]::new($false))}
    $writer.Dispose();$clock.Stop()
    $result=[ordered]@{name=$name;mode=$Mode;controller_sha256=$controllerHash;control_source_sha256=$sourceHash;controller_changed_during_run=$controllerChanged;source_changed_during_run=$sourceChanged;executable=$exe;sha256=$exeHash;debugger_sha256=(Get-FileHash -LiteralPath $cdb).Hash;target_pid=$targetId;baseline=$baseline;final=$final;histories_complete=$history;module_bounds=$bounds;validated_returns=$returns.ToArray();expected_handles=$expected.ToArray();matching_stops=$stops;debugger_exit=$exitCode;timed_out=$timedOut;root_exit_confirmed=$rootExited;target_exit_confirmed=$targetExited;forced_cleanup=$forced;observed_remaining_descendants=$remaining;failure=$failure;control_qualified=($Mode -eq 'control' -and -not $failure);readiness_evidence=$false;scope='Diagnostic partial creator-return evidence only; gu blind intervals; no ownership/leak/normal-gate claim';stdout=$stdout;stderr=$stderr}
    $result.handle_histories=$histories.ToArray()
    $result.protocol_complete=$protocolComplete
    $result.application_failure=$applicationFailure
    $result.application_exit=$exitCode
    $result.normal_gate_pass=$false
    $result.create_thread_site='KERNEL32!CreateThreadStub'
    $result.root_identity=[ordered]@{pid=$(if($launched){$p.Id}else{$null});path=$cdb;start=$rootStart}
    $result.target_identity=[ordered]@{pid=$targetId;path=$exe;start=$targetStart}
    [IO.File]::WriteAllText((Join-Path $logs 'result.json'),($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    if($null -ne $target){$target.Dispose()};$p.Dispose()
}
Write-Output ($result|ConvertTo-Json -Depth 8)
if($failure){throw $failure}
