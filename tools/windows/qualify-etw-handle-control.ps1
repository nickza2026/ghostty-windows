param([Parameter(Mandatory=$true)][string]$Root,[string]$DecodedLeaf='decoded.jsonl')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($Root)
function Rows([string]$leaf){@(Get-Content -LiteralPath (Join-Path $root $leaf) -Encoding UTF8|ForEach-Object{if($_.Trim()){$_|ConvertFrom-Json}})}
function Hex([string]$value){[Convert]::ToUInt64(($value -replace '^0x',''),16)}
$super=Get-Content -LiteralPath (Join-Path $root 'supervisor.json') -Raw -Encoding UTF8|ConvertFrom-Json
if([IO.Path]::GetFileName($DecodedLeaf) -ne $DecodedLeaf){throw 'Decoded leaf only'}
$parentRows=Rows 'control.jsonl';$childRows=Rows 'child.jsonl';$decoded=Rows $DecodedLeaf
$result=@($parentRows|Where-Object{$_.kind -eq 'result'})
$parse=@($decoded|Where-Object{$_.kind -eq 'result'})
$qualified=$false;$failure=$null;$matched=@()
try{
    if($super.timeout -or $super.cleanup_exit -ne 0 -or -not $super.root_exit_confirmed -or $super.exit -ne 0){throw 'Controller/session cleanup not qualified'}
    if($result.Count -ne 1 -or -not $result[0].fixture_ok -or -not $result[0].child_ok -or -not $result[0].session_stopped -or $result[0].elapsed_ms -gt 30000){throw 'Native fixture failed or session deadline exceeded'}
    foreach($operation in @('start','enable_handle_only','stack_create_close_duplicate','disable_provider','stop_owned_session')){
        $s=@($parentRows|Where-Object{$_.kind -eq 'status' -and $_.operation -eq $operation})
        if($s.Count -ne 1 -or $s[0].code -ne 0){throw ('API status not qualified: '+$operation)}
    }
    $loss=@($parentRows|Where-Object{$_.kind -eq 'loss'})
    if($loss.Count -ne 1 -or $loss[0].events -ne 0 -or $loss[0].log_buffers -ne 0 -or $loss[0].realtime_buffers -ne 0){throw 'Trace loss or missing loss receipt'}
    if($parse.Count -ne 1 -or -not $parse[0].ok -or $parse[0].qualification -ne 'parse-only-not-callstack-gate' -or $parse[0].unsupportedVersions -ne 0){throw 'Offline parser not qualified'}
    $reuse=@($parentRows|Where-Object{$_.kind -eq 'slot_reuse'})
    if($reuse.Count -ne 1 -or -not $reuse[0].observed){throw 'Handle slot reuse not exercised'}
    $first=@($parentRows|Where-Object{$_.kind -eq 'expected'})
    $second=@($childRows|Where-Object{$_.kind -eq 'expected'})
    $childResult=@($childRows|Where-Object{$_.kind -eq 'child_result'})
    if($first.Count -ne 7 -or $second.Count -ne 3 -or $childResult.Count -ne 1 -or -not $childResult[0].ok){throw 'Known fixture operations incomplete'}
    $expected=@($first[0..2])+$second+@($first[3..6])
    $events=@($decoded|Where-Object{$_.kind -eq 'handle'}|Sort-Object {Hex $_.qpc})
    $stacks=@($decoded|Where-Object{$_.kind -eq 'stack'})
    $used=@{};$previous=[uint64]0;$objects=@{};$eventType=$null
    foreach($op in $expected){
        $handle=Hex $op.handle;$other=Hex $op.other_handle
        $opcode=if($op.operation -like 'create*'){32}elseif($op.operation -like 'duplicate*'){34}else{33}
        $wantedObject=switch($op.operation){
            'duplicate_self'{$objects.create_a};'duplicate_child'{$objects.create_a};'close_remote'{$objects.create_a};
            'close_a'{$objects.create_a};'close_duplicate'{$objects.create_a};'close_b'{$objects.create_b};'close_child'{$objects.create_child}
            default{$null}
        }
        $candidates=@($events|Where-Object{
            (Hex $_.qpc) -ge $previous -and -not $used.ContainsKey([string]$_.sequence) -and $_.opcode -eq $opcode -and
            (-not $wantedObject -or $_.object -eq $wantedObject) -and ($null -eq $eventType -or $_.objectType -eq $eventType) -and
            $(if($opcode -eq 34){$_.sourceProcessId -eq $op.source_pid -and $_.targetProcessId -eq $op.target_pid -and $_.sourceHandle -eq $handle -and $_.targetHandle -eq $other}
              else{$_.ownerPID -eq $op.pid -and $_.handle -eq $handle})
        })
        if(-not $candidates.Count){throw ('Missing exact returned-handle/owning-PID event: '+$op.operation)}
        $callerBegin=Hex $op.caller_begin;$callerEnd=Hex $op.caller_end
        if(-not $callerBegin -or $callerEnd -le $callerBegin){throw 'Known caller unwind range unavailable'}
        if($opcode -ne 33){
            # The child's CRT reused this numeric slot for a File before the
            # fixture's Event. Bind acquisition to independent creator PCs,
            # not the first event with the same PID/handle number.
            $proven=@(foreach($candidate in $candidates){
                $hits=@(foreach($s in @($stacks|Where-Object{$_.eventQPC -eq $candidate.qpc -and $_.pid -eq $op.pid -and $_.tid -eq $op.tid})){
                    foreach($pc in $s.frames){$n=Hex $pc;if($n -ge $callerBegin -and $n -lt $callerEnd){$pc}}
                })
                if($hits.Count){$candidate}
            })
            if($proven.Count -ne 1){throw ('No unique known user-mode caller acquisition: '+$op.operation)}
            $event=$proven[0]
        }else{$event=$candidates[0]}
        $used[[string]$event.sequence]=$true;$previous=Hex $event.qpc
        $object=[string]$event.object
        if($op.operation -eq 'create_a'){$eventType=$event.objectType}
        if($opcode -eq 32){$objects[$op.operation]=$object}
        if(-not $wantedObject){$wantedObject=$object}
        if(-not $wantedObject -or $object -ne $wantedObject){throw ('Object/lifetime mismatch: '+$op.operation)}
        $joined=@($stacks|Where-Object{$_.eventQPC -eq $event.qpc -and $_.pid -eq $op.pid -and $_.tid -eq $op.tid})
        $callerPCs=@(foreach($stack in $joined){foreach($pc in $stack.frames){$n=Hex $pc;if($n -ge $callerBegin -and $n -lt $callerEnd){$pc}}})
        # Acquisitions need demonstrated caller PCs; close history needs exact
        # object/owner/ordering, not an inferred success from a stack alone.
        if($opcode -ne 33 -and -not $callerPCs.Count){throw ('No known user-mode caller PC: '+$op.operation)}
        $matched += [pscustomobject]@{operation=$op.operation;pid=$op.pid;handle=$op.handle;sequence=$event.sequence;qpc=$event.qpc;object=$object;caller_pc_count=$callerPCs.Count;stack_records=$joined.Count}
    }
    if($objects.create_a -eq $objects.create_b){throw 'Reused handle did not distinguish two live object generations'}
    $cross=@($matched|Where-Object{$_.operation -eq 'duplicate_child'})
    if($cross.Count -ne 1 -or $first[2].source_pid -eq $first[2].target_pid){throw 'Distinct PID duplicate semantics not exercised'}
    $qualified=$true
}catch{$failure=$_.Exception.Message}
[ordered]@{qualified=$qualified;failure=$failure;matched=$matched;matched_count=$matched.Count;cross_pid_semantics_qualified=$qualified;slot_reuse_qualified=$qualified;raw_data_local_only=$true;terminal_launched=$false;not_a_resource_gate_pass=$true}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $root 'qualification.json') -Encoding UTF8
[ordered]@{qualified=$qualified;failure=$failure;matched_count=$matched.Count;terminal_launched=$false}|ConvertTo-Json -Compress
if(-not $qualified){exit 1}
