# Offline numeric history audit only; never launches/attaches a process.
param([Parameter(Mandatory=$true)][string]$ResultJson)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$result=Get-Content -LiteralPath $ResultJson -Raw -Encoding UTF8|ConvertFrom-Json
if($result.failure -or -not $result.baseline -or -not $result.final -or -not $result.histories_complete -or $result.timed_out -or $result.forced_cleanup){throw 'Incomplete diagnostic receipt'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'native-close-attribution.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Owned parser syntax error'}
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Convert-CdbProtocolLine'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
function Hex([string]$s){[Convert]::ToUInt64(($s -replace '`',''),16)}
$baseline=[Collections.Generic.List[object]]::new()
$final=[Collections.Generic.List[object]]::new()
$records=[Collections.Generic.List[object]]::new()
$phase='initial';$pending=$null;$parsed=0
foreach($raw in Get-Content -LiteralPath $result.stdout -Encoding UTF8){
    $line=Convert-CdbProtocolLine $raw
    if($line -match '^LC_BASE_PAUSED pid=[0-9a-f]+\b'){$phase='baseline';continue}
    if($phase -eq 'baseline' -and $line -eq 'Handle tracing information snapshot successfully taken.'){$phase='running';continue}
    if($line -eq 'LC_FINAL_PAUSED'){$phase='diff';continue}
    if($phase -eq 'diff' -and $line -match '^Displayed 0x[0-9a-f]+ stack traces for outstanding handles opened since the previous snapshot\.'){$phase='final';$records.Clear();continue}
    if($phase -notin @('baseline','final')){continue}
    if($line -match '^Handle = 0x([0-9a-f]+) - (OPEN|CLOSE|BADREF)\s*$'){$pending=[ordered]@{handle=('0x{0:x}' -f (Hex $Matches[1]));operation=$Matches[2]};continue}
    if($line -match '^Thread ID = 0x([0-9a-f]+), Process ID = 0x([0-9a-f]+)\s*$'){
        if($null -eq $pending){throw 'Unpaired kernel trace record'}
        $records.Add([pscustomobject]@{handle=$pending.handle;operation=$pending.operation;tid=(Hex $Matches[1]);pid=(Hex $Matches[2])});$pending=$null;continue
    }
    if($line -match '^Parsed 0x([0-9a-f]+) stack traces\.'){$parsed=Hex $Matches[1];continue}
    if($line -match '^Dumped 0x([0-9a-f]+) stack traces\.'){
        if((Hex $Matches[1]) -ne $records.Count -or $null -ne $pending){throw 'Incomplete/truncated history block'}
        $block=[pscustomobject]@{records=$records.ToArray();total_database_records=$parsed}
        if($phase -eq 'baseline'){$baseline.Add($block)}else{$final.Add($block)}
        $records.Clear()
    }
}
if($baseline.Count -ne $result.selected_baseline_handles.Count -or $final.Count -ne $baseline.Count){throw 'Missing per-slot full history blocks'}
$audits=[Collections.Generic.List[object]]::new()
for($i=0;$i -lt $baseline.Count;$i++){
    $slot=$result.selected_baseline_handles[$i]
    $b=@($baseline[$i].records);$f=@($final[$i].records)
    foreach($record in @($b)+@($f)){if($record.handle -ne $slot -or $record.pid -ne $result.target_pid){throw 'Cross-slot/process history mismatch'}}
    $returns=@($result.validated_returns|Where-Object{$_.handle -eq $slot -and $_.successful_close})
    if($returns.Count -eq 0){continue}
    if($returns.Count -ne 1 -or $b.Count -eq 0 -or $b[0].operation -ne 'OPEN' -or $f.Count -le $b.Count){throw 'Ambiguous baseline generation'}
    if($final[$i].total_database_records -ge 0x10000){throw 'Trace capacity reached; continuity not established'}
    $added=$f.Count-$b.Count
    for($j=0;$j -lt $b.Count;$j++){
        if($b[$j].operation -ne $f[$added+$j].operation -or $b[$j].tid -ne $f[$added+$j].tid){throw 'Baseline history is not exact final suffix'}
    }
    # htrace prints newest first. The oldest added record must close the
    # baseline generation, not an object reusing that numeric slot later.
    $first=$f[$added-1]
    $sameTidCloses=@($f[0..($added-1)]|Where-Object{$_.operation -eq 'CLOSE' -and $_.tid -eq $returns[0].tid})
    if($first.operation -ne 'CLOSE' -or $first.tid -ne $returns[0].tid -or $sameTidCloses.Count -ne 1){throw 'Observed return cannot uniquely join first baseline close'}
    if(@($f|Where-Object{$_.operation -eq 'BADREF'}).Count){throw 'Invalid-handle trace disqualifies this slot'}
    $audits.Add([ordered]@{handle=$slot;baseline_type='ALPC Port (type-only selection)';baseline_history_records=$b.Count;final_history_records=$f.Count;new_records=$added;baseline_suffix_exact=$true;first_post_baseline_operation=$first.operation;first_close_tid=$first.tid;unique_close_for_observed_tid=$true;verified_native_status=$returns[0].ntstatus;later_slot_reuse_records=($added-1);total_database_records=$final[$i].total_database_records;configured_capacity=0x10000;conclusion='Verified observed close caller for baseline generation; later numeric reuse not attributed'})
}
if($audits.Count -eq 0){throw 'No baseline-generation closes established'}
$out=[ordered]@{source_receipt=$ResultJson;source_receipt_sha256=(Get-FileHash -LiteralPath $ResultJson).Hash;target_pid=$result.target_pid;audited_closes=$audits.ToArray();readiness_evidence=$false;scope='Same-run close caller only; no creator/ownership/leak/normal-gate inference'}
$path=Join-Path ([IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $ResultJson).ProviderPath)) 'history-audit.json'
[IO.File]::WriteAllText($path,($out|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Write-Output ($out|ConvertTo-Json -Depth 6)
