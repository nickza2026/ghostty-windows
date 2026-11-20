param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($Root)
function Json([string]$p){Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json}
function Rows([string]$p){@(Get-Content -LiteralPath $p -Encoding UTF8|ForEach-Object{if($_.Trim()){$_|ConvertFrom-Json}})}
function U64($v){
    $s=[string]$v
    if($s -match '^0[xX]([0-9a-fA-F]{1,16})$'){return [Convert]::ToUInt64($Matches[1],16)}
    if($s -notmatch '^\d+$'){throw 'Invalid unsigned integer'}
    return [UInt64]::Parse($s,[Globalization.CultureInfo]::InvariantCulture)
}
function H($v){'0x'+(U64 $v).ToString('x')}
$out=[ordered]@{status='blocked';reason=$null;slots=@();limitations=@(
    'Root ETW user workload begins after bind-before-resume; inherited prebind kernel handles are not covered.',
    'No exact PSS-QPC marker: acquisition candidates are not snapshot-time or closure proof.',
    'Independent ledger does not observe native close API success.',
    'Original NativeResourceGrowth is not fixed; this is not driver cause or leak proof.')}
try{
    if(-not (Test-Path -LiteralPath $root -PathType Container)){throw 'Private root missing'}
    $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    if($root.TrimEnd('\','/').StartsWith($repo.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $root -eq $repo){throw 'Root must be private, outside repository'}
    $run=Json (Join-Path $root 'terminal-run.json')
    foreach($k in @('capture_complete','bound_before_resume','native_exited','resumed')){if($run.$k -ne $true){throw ('Incomplete capture: '+$k)}}
    if($run.raw_global_etl -ne $false -or $run.readiness_evidence -ne $false){throw 'Not diagnostic-only streaming evidence'}
    $s=$run.supervisor
    if($null -eq $s -or $s.cleanup_exit -ne 0 -or $s.timeout -ne $false -or $s.exit -ne 0){throw 'Supervisor not qualified'}
    if(@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.etl').Count){throw 'Raw ETL present'}
    $receipt=Json (Join-Path $root 'native-receipt.json')
    if($receipt.exit_code -ne 0 -or $receipt.timed_out -ne $false -or $receipt.readiness_evidence -ne $false){throw 'Native receipt not qualified'}
    $identity=Json (Join-Path $root 'gate/native-identity.json')
    $native=U64 $identity.native_pid
    if($native -eq 0 -or $native -ne (U64 $run.native_pid)){throw 'Root identity mismatch'}
    $rows=Rows (Join-Path $root 'decoded.jsonl')
    $parse=@($rows|Where-Object{$_.kind -eq 'result'})
    if($parse.Count -ne 1 -or $parse[0].ok -ne $true -or $parse[0].qualification -ne 'parse-only-not-callstack-gate' -or $parse[0].error -ne 0 -or $parse[0].unsupportedVersions -ne 0 -or $parse[0].malformed -ne 0 -or $parse[0].unsupportedPayloads -ne 0){throw 'Parser not qualified'}
    # Control is a schema/type reference only, never a caller or PID source.
    $control=(Get-Content -LiteralPath (Join-Path $repo 'zig-out/etw-stream-control-current.txt') -Raw).Trim()
    $q=Json (Join-Path $control 'qualification.json')
    $gold=@($q.matched|Where-Object{$_.operation -eq 'create_a'})
    if($q.qualified -ne $true -or $q.matched_count -ne 10 -or $gold.Count -ne 1){throw 'Control type reference not qualified'}
    $typeRows=@(Rows (Join-Path $control 'decoded.jsonl')|Where-Object{$_.kind -eq 'handle' -and $_.sequence -eq $gold[0].sequence -and $_.opcode -eq 32})
    if($typeRows.Count -ne 1){throw 'No unique control Event type'}
    $eventType=$typeRows[0].objectType
    $text=Get-Content -LiteralPath $receipt.stderr -Raw -Encoding UTF8
    $summaries=[regex]::Matches($text,'(?m)^info: terminal lifecycle 20 cycles after warmup: handles (\d+)->(\d+), GDI (\d+)->(\d+), USER (\d+)->(\d+), threads (\d+)->(\d+)\r?$')
    if($summaries.Count -ne 1){throw 'No unique strict lifecycle summary'}
    $ledger=[regex]::Matches($text,'(?m)^info: ownedledger summary entries=105 active=0 faults=0 capacity=512 native_close_results=unobserved coverage=surface_workers_and_iocp_only\r?$')
    if($ledger.Count -ne 1){throw 'Independent ledger receipt missing'}
    $baseline=@{};$final=@{};$phase=$null;$phases=@()
    foreach($line in ($text -split '\r?\n')){
        if($line -match '^info: lifecycle handle inventory phase=(baseline|final)$'){$phase=$Matches[1];$phases+= $phase;continue}
        if($line -match '^info: lifecycle handle inventory handle=(0x[0-9a-fA-F]+) kind=\d+ target=\d+ access=0x[0-9a-fA-F]+ type=(\S+)$'){
            if(-not $phase){throw 'Inventory without phase'}
            $slot=H $Matches[1];$type=$Matches[2]
            $table=if($phase -eq 'baseline'){$baseline}else{$final}
            if($table.ContainsKey($slot)){throw 'Repeated inventory slot'};$table[$slot]=$type
        }
    }
    if(($phases -join ',') -ne 'baseline,final'){throw 'Inventory phases not unique and ordered'}
    $modules=@(Json (Join-Path $root 'native-modules.json'))
    $stacks=@($rows|Where-Object{$_.kind -eq 'stack'})
    $slots=@($final.Keys|Where-Object{$final[$_] -eq 'Event' -and -not ($baseline.ContainsKey($_) -and $baseline[$_] -eq 'Event')})
    foreach($slot in $slots){
        $candidates=@($rows|Where-Object{$_.kind -eq 'handle' -and $_.objectType -eq $eventType -and
            (($_.opcode -eq 32 -and $_.ownerPID -eq $native -and (U64 $_.handle) -eq (U64 $slot)) -or
             ($_.opcode -eq 34 -and $_.targetProcessId -eq $native -and (U64 $_.targetHandle) -eq (U64 $slot)))})
        $acquisitions=@(foreach($a in $candidates){
            $frames=@();$joined=@()
            if($a.executingPID -eq $native){$joined=@($stacks|Where-Object{(U64 $_.eventQPC) -eq (U64 $a.qpc) -and $_.tid -eq $a.executingTID -and $_.pid -eq $a.executingPID})}
            foreach($stack in $joined){foreach($pc in $stack.frames){
                $n=U64 $pc
                $ranges=@($modules|Where-Object{$b=U64 ('0x'+($_.base -replace '^0x',''));$n -ge $b -and ($n-$b) -lt (U64 $_.size)})
                if($ranges.Count -eq 1){$m=$ranges[0];$frames+= [ordered]@{class='module';module=[IO.Path]::GetFileName($m.path);rva=H ($n-(U64 ('0x'+($m.base -replace '^0x',''))));pc=H $n}}
                else{$frames+= [ordered]@{class='unknown';reason=if($ranges.Count){'ambiguous-range'}else{'unmapped'};pc=H $n}}
            }}
            [ordered]@{sequence=$a.sequence;opcode=$a.opcode;qpc_raw=[string]$a.qpc;stack_records=$joined.Count;caller_status=if($a.executingPID -ne $native){'unknown-foreign-executing-process'}elseif(-not $joined.Count){'unknown-no-stack'}else{'same-root-range-resolution-only'};frames=$frames}
        })
        $out.slots+= [ordered]@{slot=$slot;candidate_count=$candidates.Count;binding=if($candidates.Count -eq 1){'qualified-unique-acquisition-candidate'}else{'unresolved'};binding_basis='complete stream + final PSS Event type + exact root-owned slot acquisition; no snapshot-time marker';acquisitions=$acquisitions}
    }
    $out.status=if($slots.Count -gt 0 -and @($out.slots|Where-Object{$_.candidate_count -ne 1}).Count -eq 0){'qualified-candidates'}else{'unresolved'}
    $out.new_final_event_slots=$slots.Count
    $out.lifecycle_summary=$summaries[0].Value
    $out.independent_ledger='105 entries; active 0; faults 0; native close results unobserved'
}catch{
    # IO/parser exceptions can embed private filenames; do not print those.
    $out.reason=if($_.Exception -is [System.Management.Automation.RuntimeException] -and $_.Exception.Message -notmatch '[\\/]'){$_.Exception.Message}else{'Missing, invalid, or inaccessible qualification evidence'}
}
$out|ConvertTo-Json -Depth 14|Set-Content -LiteralPath (Join-Path $root 'event-analysis.json') -Encoding UTF8
Write-Output ('Event analysis: '+$out.status+'; new final Event slots='+$out.new_final_event_slots)
foreach($slot in $out.slots){
    Write-Output ('slot '+$slot.slot+': '+$slot.binding+'; candidates='+$slot.candidate_count)
    if($slot.candidate_count -eq 1){$names=@($slot.acquisitions[0].frames|Where-Object{$_.class -eq 'module'}|ForEach-Object{$_.module}|Sort-Object -Unique);Write-Output ('  caller='+$slot.acquisitions[0].caller_status+'; modules='+($names -join ','))}
}
if($out.status -eq 'blocked'){Write-Output ('Blocked: '+$out.reason);exit 1}
