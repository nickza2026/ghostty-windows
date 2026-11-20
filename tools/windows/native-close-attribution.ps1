# Diagnostic only: owned target, type-only metadata/basic stacks, no dumps/names.
# Return validation is per invocation; disabling breakpoints while gu executes
# creates a blind interval. Full histories remain necessary; never all-closes proof.
param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [ValidateSet('control','native')][string]$Mode='control',
    [string]$QualifiedControlReceipt,
    [ValidateRange(30,300)][int]$TimeoutSeconds=240
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$controllerHash=(Get-FileHash -LiteralPath $PSCommandPath).Hash
if($Mode -eq 'native'){
    if(-not $QualifiedControlReceipt){throw 'NOT QUALIFIED: completed private control receipt required before native tracing.'}
    $proof=Get-Content -LiteralPath $QualifiedControlReceipt -Raw -Encoding UTF8|ConvertFrom-Json
    if($proof.mode -ne 'control' -or $proof.controller_sha256 -ne $controllerHash -or $proof.controller_changed_during_run -or $proof.failure -or -not $proof.baseline -or -not $proof.final -or -not $proof.histories_complete -or $proof.timed_out -or $proof.forced_cleanup -or -not $proof.root_exit_confirmed -or -not $proof.target_exit_confirmed -or $proof.observed_remaining_descendants.Count -or $proof.selected_baseline_handles.Count -ne 4 -or $proof.validated_returns.Count -ne 4 -or @($proof.validated_returns|Where-Object{-not $_.successful_close}).Count){throw 'NOT QUALIFIED: complete four-slot control receipt from the same revision required.'}
}
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$exe=(Resolve-Path -LiteralPath $Executable).ProviderPath
if(-not $exe.StartsWith((Join-Path $workspace 'zig-out')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Owned zig-out target only'}
if($exe -match '["\r\n]'){throw 'Unsupported debugger path'}
# WinMain alone does not force GUI subsystem in Zig cc. Verify the actual PE
# before launching either control or native target; no console window fallback.
$peStream=[IO.File]::OpenRead($exe);$peReader=[IO.BinaryReader]::new($peStream)
try{$peStream.Position=0x3c;$peOffset=$peReader.ReadInt32();$peStream.Position=$peOffset+4+20+68;if($peReader.ReadUInt16() -ne 2){throw 'Only Windows-GUI subsystem targets; no console allocation'}}finally{$peReader.Dispose();$peStream.Dispose()}
$cdb='C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe'
$signature=Get-AuthenticodeSignature -LiteralPath $cdb
if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation'){throw 'Signed Microsoft debugger required'}
$base=Join-Path $env:LOCALAPPDATA 'Letta\build-logs\ghostty-windows\phase3b-runtime'
$name='close-attribution-'+$Mode+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$logs=Join-Path $base $name
$null=[IO.Directory]::CreateDirectory($logs)
$initial=Join-Path $logs 'initial.cdb'
$stdout=Join-Path $logs 'stdout.log'
$stderr=Join-Path $logs 'stderr.log'
$initialText=@'
!htrace -enable 0x10000
bm *!localterm_native_htrace_marker ".if (@rcx == 1) { .printf \"LC_BASE_PAUSED pid=%x\n\", @$tpid } .else { .echo LC_FINAL_PAUSED }"
g
'@
[IO.File]::WriteAllText($initial,$initialText,[Text.UTF8Encoding]::new($false))
$keys=@('LOCALTERM_WINDOW_SMOKE','LOCALTERM_TERMINAL_SMOKE','LOCALTERM_TERMINAL','LOCALTERM_INPUT_SMOKE','LOCALTERM_LIFECYCLE_SMOKE','LOCALTERM_LIFECYCLE_PSS','LOCALTERM_TERMINAL_CASE','LOCALTERM_MOUSE_SMOKE','LOCALTERM_THAI_TUI_SMOKE','LOCALTERM_THAI_TUI_LEGACY','LOCALTERM_BACKGROUND_SMOKE','LOCALTERM_THAI_MODEL_REQUIRED','LOCALTERM_TITLE_BACKPRESSURE_SMOKE','LOCALTERM_CONPTY_WIDTH','LOCALTERM_CONPTY_PROVIDER','LOCALTERM_CONPTY_EXPERIMENT','LOCALTERM_PREVIEW_BACKGROUND','LOCALTERM_GPU_TEXT_FRAME_CHECK','LOCALTERM_VIEWPORT_SMOKE','LOCALTERM_KITTY_IMAGE_SMOKE','LOCALTERM_KITTY_IMAGE_REFERENCE')
$saved=@{}
$p=[Diagnostics.Process]::new()
$p.StartInfo.FileName=$cdb
$p.StartInfo.WorkingDirectory=$workspace
$p.StartInfo.UseShellExecute=$false
$p.StartInfo.CreateNoWindow=$true
$p.StartInfo.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
$p.StartInfo.RedirectStandardInput=$true
$p.StartInfo.RedirectStandardOutput=$true
$p.StartInfo.RedirectStandardError=$true
$cache=Join-Path $env:LOCALAPPDATA 'Letta\tools\windows-debugger\symbols'
$symbols=[IO.Path]::GetDirectoryName($exe)+';srv*'+$cache+'*https://msdl.microsoft.com/download/symbols'
$p.StartInfo.Arguments='-hd -G -nosqm -y "'+$symbols+'" -cf "'+$initial+'" "'+$exe+'"'
$writer=[IO.StreamWriter]::new($stdout,$false,[Text.UTF8Encoding]::new($false))
$writer.AutoFlush=$true
$clock=[Diagnostics.Stopwatch]::StartNew()
$started=Get-Date
$baseline=$false;$final=$false;$query=$false;$history=$false;$currentHandle=$null
$controlHandles=[Collections.Generic.HashSet[UInt64]]::new()
$pending=$null;$targetId=$null;$stops=0;$timedOut=$false;$rootExited=$false
$selected=[Collections.Generic.List[string]]::new()
$active=[Collections.Generic.List[string]]::new()
$returns=[Collections.Generic.List[object]]::new()
$failure=$null;$errTask=$null;$exitCode=$null;$lines=0;$launched=$false
$targetProcess=$null;$targetExited=$false;$forcedCleanup=$false;$remaining=@()
function Hex([string]$s){[Convert]::ToUInt64(($s -replace '`',''),16)}
function Send([string]$s){$p.StandardInput.WriteLine($s);$p.StandardInput.Flush()}
function New-CloseCondition([string[]]$Handles){return ($Handles|ForEach-Object{'(@rcx == '+$_+')'}) -join ' or '}
function Arm-CloseBreakpoint {
    if($active.Count -eq 0){Send 'bc 1';return}
    $condition=New-CloseCondition $active.ToArray()
    Send ('bp1 ntdll!NtClose ".if ('+$condition+') { .printf \"LC_CLOSE_ENTER tid=%x handle=%p ret=%p sp=%p\n\", @$tid, @rcx, poi(@rsp), @rsp; k } .else { gc }"')
}
function Convert-CdbProtocolLine([string]$Line){
    # Redirected CDB can prefix extension/echo output with its thread prompt.
    # Strip only that prefix; command echoes still start with .echo/.printf and
    # must not be accepted as actual protocol receipts.
    return $Line -replace '^(?:\s*[0-9a-fA-F]+:[0-9a-fA-F]+>\s*)+',''
}
try {
    try {
        foreach($key in $keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$null,'Process')}
        if($Mode -eq 'native'){$env:LOCALTERM_LIFECYCLE_SMOKE='1';$env:LOCALTERM_LIFECYCLE_PSS='1';$env:LOCALTERM_CONPTY_PROVIDER='app-local';$env:LOCALTERM_CONPTY_EXPERIMENT='1'}
        if(-not $p.Start()){throw 'Debugger failed to start'}
        $launched=$true
        $null=$p.Handle
    } finally {foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}}
    $errTask=$p.StandardError.ReadToEndAsync()
    $read=$p.StandardOutput.ReadLineAsync()
    while($true){
        if($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;throw 'External debugger deadline exceeded'}
        if(-not $read.IsCompleted){Start-Sleep -Milliseconds 15;continue}
        $line=$read.GetAwaiter().GetResult()
        if($null -eq $line){break}
        $writer.WriteLine($line);$lines++
        $line=Convert-CdbProtocolLine $line
        if($line -match '^(Numeric expression missing|Syntax error|Couldn.t resolve error)'){throw ('Debugger command failure: '+$line)}
        if($lines -gt 24000){throw 'Diagnostic output cap exceeded'}
        if($line -match '^LC_CONTROL_HANDLE=([0-9a-fA-F`]+)$'){$null=$controlHandles.Add((Hex $Matches[1]))}
        if($line -match '^LC_BASE_PAUSED pid=([0-9a-fA-F]+)\b'){
            if($baseline){throw 'Duplicate baseline marker'}
            $targetId=Hex $Matches[1];$baseline=$true;$query=$true
            $targetProcess=Get-Process -Id ([int]$targetId)
            $null=$targetProcess.Handle
            if(-not [string]::Equals($targetProcess.MainModule.FileName,$exe,[StringComparison]::OrdinalIgnoreCase) -or $targetProcess.StartTime -lt $started){throw 'Owned debuggee identity mismatch'}
            Send '!handle 0 1'
            Send '.echo LC_QUERY_END'
        }elseif($query -and $line -match '^Handle\s+([0-9a-fA-F`]+)\s*$'){$currentHandle='0x{0:x}' -f (Hex $Matches[1])
        }elseif($query -and $line -match '^\s*Type\s+(.+?)\s*$'){
            $wanted=if($Mode -eq 'native'){'ALPC Port'}else{'Event'}
            if($Matches[1] -eq $wanted -and $null -ne $currentHandle){
                if($Mode -eq 'native' -or $controlHandles.Contains((Hex $currentHandle.Substring(2)))){$selected.Add($currentHandle)}
            }
        }elseif($line -eq 'LC_QUERY_END'){
            $query=$false
            if($selected.Count -eq 0 -or $selected.Count -gt 16){throw 'Missing/oversized same-run type selection'}
            if($Mode -eq 'control' -and ($controlHandles.Count -ne 4 -or $selected.Count -ne 4)){throw 'Control must select exactly its four private events'}
            foreach($h in $selected){Send ('!htrace '+$h)}
            Send '!htrace -snapshot'
            foreach($h in $selected){$active.Add($h)}
            Arm-CloseBreakpoint
            Send 'g'
        }elseif($line -match '^LC_CLOSE_ENTER tid=([0-9a-fA-F]+) handle=([0-9a-fA-F`]+) ret=([0-9a-fA-F`]+) sp=([0-9a-fA-F`]+)\b'){
            if($null -ne $pending){throw 'Unexpected overlapping close stops'}
            $stops++;if($stops -gt 16){throw 'Matching close stop cap exceeded'}
            $pending=[ordered]@{tid=(Hex $Matches[1]);handle=('0x{0:x}' -f (Hex $Matches[2]));return_address=(Hex $Matches[3]);entry_sp=(Hex $Matches[4])}
            Send 'bd *'
            Send 'gu'
            Send '.printf "LC_CLOSE_RETURN tid=%x ip=%p sp=%p status=%08x\n", @$tid, @rip, @rsp, @eax'
        }elseif($line -match '^LC_CLOSE_RETURN tid=([0-9a-fA-F]+) ip=([0-9a-fA-F`]+) sp=([0-9a-fA-F`]+) status=([0-9a-fA-F]+)$'){
            if($null -eq $pending){throw 'Unpaired return'}
            $tid=Hex $Matches[1];$ip=Hex $Matches[2];$sp=Hex $Matches[3];$status=Hex $Matches[4]
            $valid=$tid -eq $pending.tid -and $ip -eq $pending.return_address -and $sp -eq ($pending.entry_sp+8)
            $returns.Add([ordered]@{handle=$pending.handle;tid=$pending.tid;entry_sp=$pending.entry_sp;expected_return=$pending.return_address;return_tid=$tid;return_ip=$ip;return_sp=$sp;ntstatus=$status;invocation_verified=$valid;successful_close=($valid -and $status -eq 0)})
            if(-not $valid){throw 'Ambiguous gu stop; cannot attribute this return'}
            # Stop following a numeric slot after its first observed successful
            # close. Subsequent reuse is not the baseline object generation.
            if($status -eq 0){$null=$active.Remove($pending.handle)}
            $pending=$null
            Arm-CloseBreakpoint
            Send 'be *'
            Send 'g'
        }elseif($line -eq 'LC_FINAL_PAUSED'){
            if(-not $baseline -or $null -ne $pending){throw 'Incomplete phase protocol'}
            $final=$true
            Send 'bd *'
            Send '!htrace -diff'
            foreach($h in $selected){Send ('!htrace '+$h)}
            Send '.echo LC_HISTORY_END'
        }elseif($line -eq 'LC_HISTORY_END'){$history=$true;Send 'g'}
        $read=$p.StandardOutput.ReadLineAsync()
    }
    $rootExited=$p.WaitForExit(3000)
    if($rootExited){$exitCode=$p.ExitCode}
    if(-not $baseline -or -not $final -or -not $history -or -not $rootExited -or $returns.Count -eq 0){throw 'Incomplete bounded close control'}
    if($Mode -eq 'control' -and ($returns.Count -ne 4 -or @($returns|Where-Object{-not $_.successful_close}).Count -or $exitCode -ne 0)){throw 'Private four-slot control failed'}
}catch{$failure=[string]$_}
finally{
    if($launched -and -not $rootExited -and -not $p.HasExited){$forcedCleanup=$true;& taskkill.exe /PID $p.Id /T /F|Out-Null;$null=$p.WaitForExit(5000);$rootExited=$p.HasExited}
    if($null -ne $targetProcess){
        $targetExited=$targetProcess.HasExited
        if(-not $targetExited){$forcedCleanup=$true;$targetProcess.Kill();$null=$targetProcess.WaitForExit(5000);$targetExited=$targetProcess.HasExited}
    }
    if($launched){
        $parents=[Collections.Generic.Queue[int]]::new();$parents.Enqueue($p.Id)
        if($null -ne $targetId){$parents.Enqueue([int]$targetId)}
        $seen=[Collections.Generic.HashSet[int]]::new()
        while($parents.Count -gt 0){
            $parent=$parents.Dequeue();if(-not $seen.Add($parent)){continue}
            foreach($row in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$parent")){
                if($row.CreationDate -lt $started){continue}
                $remaining+=([int]$row.ProcessId);$parents.Enqueue([int]$row.ProcessId)
                $child=Get-Process -Id $row.ProcessId -ErrorAction SilentlyContinue
                if($null -ne $child){try{$null=$child.Handle;$check=Get-CimInstance Win32_Process -Filter "ProcessId=$($row.ProcessId)";if($null -ne $check -and $check.CreationDate -eq $row.CreationDate -and -not $child.HasExited){$forcedCleanup=$true;$child.Kill();$null=$child.WaitForExit(5000)}}finally{$child.Dispose()}}
            }
        }
    }
    if(($forcedCleanup -or -not $targetExited -or $remaining.Count -gt 0) -and -not $failure){$failure='Owned shutdown incomplete or required forced cleanup'}
    if($null -ne $errTask -and $errTask.Wait(3000)){[IO.File]::WriteAllText($stderr,$errTask.Result,[Text.UTF8Encoding]::new($false))}
    $writer.Dispose();$clock.Stop()
    $result=[ordered]@{name=$name;mode=$Mode;controller_sha256=$controllerHash;controller_changed_during_run=((Get-FileHash -LiteralPath $PSCommandPath).Hash -ne $controllerHash);executable=$exe;sha256=(Get-FileHash -LiteralPath $exe).Hash;debugger_sha256=(Get-FileHash -LiteralPath $cdb).Hash;target_pid=$targetId;baseline=$baseline;final=$final;histories_complete=$history;selected_baseline_handles=$selected.ToArray();validated_returns=$returns.ToArray();matching_stops=$stops;debugger_exit=$exitCode;timed_out=$timedOut;root_exit_confirmed=$rootExited;target_exit_confirmed=$targetExited;forced_cleanup=$forcedCleanup;observed_remaining_descendants=$remaining;failure=$failure;readiness_evidence=$false;scope='Partial close-caller attribution only; gu blind intervals; require per-slot history continuity; no leak/creator/ownership/normal-gate claim';stdout=$stdout;stderr=$stderr}
    [IO.File]::WriteAllText((Join-Path $logs 'result.json'),($result|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
    if($null -ne $targetProcess){$targetProcess.Dispose()};$p.Dispose()
}
Write-Output ($result|ConvertTo-Json -Depth 7)
if($failure){throw $failure}
