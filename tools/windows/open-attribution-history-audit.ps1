# Offline current-generation join. No process launch/attach or application data.
param([Parameter(Mandatory=$true)][string]$ResultJson)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$r=Get-Content -LiteralPath $ResultJson -Raw -Encoding UTF8|ConvertFrom-Json
if($r.failure -or -not $r.protocol_complete -or -not $r.histories_complete -or $r.timed_out -or $r.forced_cleanup){throw 'Incomplete creator diagnostic'}
function Hex([string]$s){[Convert]::ToUInt64(($s -replace '`',''),16)}
$blocks=@{};$slot=$null;$pending=$null;$parsed=0;$dumped=$null
$records=[Collections.Generic.List[object]]::new()
foreach($raw in Get-Content -LiteralPath $r.stdout -Encoding UTF8){
    $line=$raw -replace '^(?:\s*[0-9a-fA-F]+:[0-9a-fA-F]+>\s*)+',''
    if($line -match '^LO_HISTORY_BEGIN handle=(0x[0-9a-f]+)$'){$slot=$Matches[1];$records.Clear();$dumped=$null;continue}
    if($null -eq $slot){continue}
    if($line -match '^Handle = 0x([0-9a-f]+) - (OPEN|CLOSE|BADREF)\s*$'){$pending=@{handle=('0x{0:x}' -f (Hex $Matches[1]));operation=$Matches[2]};continue}
    if($line -match '^Thread ID = 0x([0-9a-f]+), Process ID = 0x([0-9a-f]+)\s*$'){
        if($null -eq $pending){throw 'Unpaired history record'}
        $records.Add([pscustomobject]@{handle=$pending.handle;operation=$pending.operation;tid=(Hex $Matches[1]);pid=(Hex $Matches[2])});$pending=$null;continue
    }
    if($line -match '^Parsed 0x([0-9a-f]+) stack traces\.'){$parsed=Hex $Matches[1]}
    if($line -match '^Dumped 0x([0-9a-f]+) stack traces\.'){$dumped=Hex $Matches[1]}
    if($line -eq 'LO_HANDLE_HISTORY_END'){
        if($blocks.ContainsKey($slot) -or $null -ne $pending -or $dumped -ne $records.Count -or $parsed -ge 0x10000){throw 'Duplicate/missing/truncated/capacity-limited history'}
        $blocks[$slot]=[pscustomobject]@{records=$records.ToArray();database_records=$parsed};$slot=$null
    }
}
$phase='';$inventory=@{};$threads=@{}
foreach($line in Get-Content -LiteralPath $r.stderr -Encoding UTF8){
    if($line -match '^info: lifecycle handle inventory phase=(baseline|final)$'){$phase=$Matches[1];continue}
    if($line -match '^info: lifecycle owned thread id=(\d+) name=.* start=0x([0-9a-f]+) module=(.+)$'){$threads[$Matches[1]]=@{start=(Hex $Matches[2]);module=$Matches[3]}}
    if($phase -eq 'final' -and $line -match '^info: lifecycle handle inventory handle=(0x[0-9a-f]+) kind=\d+ target=(\d+) access=0x[0-9a-f]+ type=(.+)$'){$inventory[$Matches[1]]=@{target=[UInt64]$Matches[2];type=$Matches[3]}}
}
$audits=[Collections.Generic.List[object]]::new()
foreach($value in $r.validated_returns){
    if(-not $value.successful -or -not $value.invocation_verified){continue}
    if(-not $blocks.ContainsKey($value.handle) -or -not $inventory.ContainsKey($value.handle)){throw 'Missing history or final own-process inventory'}
    $b=$blocks[$value.handle];$h=@($b.records)
    foreach($entry in $h){if($entry.handle -ne $value.handle -or $entry.pid -ne $r.target_pid){throw 'Cross-slot/process history'}}
    if($h.Count -eq 0 -or $h[0].operation -ne 'OPEN' -or $h[0].tid -ne $value.tid -or @($h|Where-Object{$_.operation -eq 'OPEN' -and $_.tid -eq $value.tid}).Count -ne 1){throw 'Returned creation cannot uniquely join latest retained generation'}
    $p=$inventory[$value.handle];$entryModule=$null
    if($value.api -eq 'CreateEventW' -and $p.type -ne 'Event'){throw 'Returned event type mismatch'}
    if($value.api -eq 'DuplicateHandle' -and ($p.type -ne 'Thread' -or $p.target -ne $value.tid)){throw 'Current-thread duplicate target mismatch'}
    if($value.api -eq 'CreateThread'){
        if($p.type -ne 'Thread' -or -not $threads.ContainsKey([string]$p.target)){throw 'Created thread target missing'}
        $t=$threads[[string]$p.target];$entryModule=$t.module
        if($t.start -lt (Hex $r.module_bounds.amd[0].Substring(2)) -or $t.start -ge (Hex $r.module_bounds.amd[1].Substring(2))){throw 'Thread entry outside captured current AMD bounds'}
    }
    $audits.Add([ordered]@{api=$value.api;returned_handle=$value.handle;creator_tid=$value.tid;final_type=$p.type;final_target=$p.target;target_entry_module=$entryModule;history_records=$h.Count;latest_operation='OPEN';latest_open_unique_for_captured_tid=$true;no_later_close_or_reopen=$true;older_generation_records_excluded=($h.Count-1);database_records=$b.database_records;conclusion='Exact observed API return joined to current retained handle generation; creator call stack must be read separately'})
}
if($audits.Count -eq 0){throw 'No retained creator returns established'}
$result=[ordered]@{source_receipt=$ResultJson;source_receipt_sha256=(Get-FileHash -LiteralPath $ResultJson).Hash;stdout_sha256=(Get-FileHash -LiteralPath $r.stdout).Hash;stderr_sha256=(Get-FileHash -LiteralPath $r.stderr).Hash;pid=$r.target_pid;audited_returns=$audits.ToArray();readiness_evidence=$false;scope='This diagnostic PID only; not normal-run identity, all-handles ownership, leak attribution or gate waiver'}
$dest=Join-Path ([IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $ResultJson).ProviderPath)) 'creator-history-audit.json'
[IO.File]::WriteAllText($dest,($result|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
Write-Output ($result|ConvertTo-Json -Depth 7)
