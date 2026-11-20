# Targeted actual-Command regression supervisor. No interactive windows or app launch.
# Native fixture deadlines do not promise cancellation of synchronous Win32 APIs.
# The outer process deadline is a failure boundary, never a runtime-gate waiver.
param(
    [ValidateSet('red','green','adjacent')][string]$Label='green',
    [ValidateSet('Windows ConPTY','Command','Windows command process ownership')][string]$Filter='Windows ConPTY',
    [ValidateRange(30,900)][int]$TimeoutSeconds=600
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$zig=Join-Path $env:LOCALAPPDATA 'Programs\Zig\zig-x86_64-windows-0.16.0\zig.exe'
if(-not(Test-Path -LiteralPath $zig -PathType Leaf)){throw 'Reviewed Zig 0.16.0 executable is missing'}
$sources=@('build.zig','src/Command.zig','src/os/windows.zig','src/windows_command_inheritance_test.zig','tools/windows/command-inheritance-child.c','tools/windows/command-inheritance-check.ps1','src/render_worker_client.c')
$before=[ordered]@{}
foreach($relative in $sources){
    $file=Join-Path $workspace $relative
    if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw ('Missing reviewed test input: '+$relative)}
    $before[$relative]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}
$base=Join-Path $env:LOCALAPPDATA 'Letta\build-logs\ghostty-windows\launch-inheritance'
$name=$Label+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$logRoot=Join-Path $base $name
$null=[IO.Directory]::CreateDirectory($logRoot)
$stdout=Join-Path $logRoot 'stdout.log'
$stderr=Join-Path $logRoot 'stderr.log'
$args=@('build','test','-j1','-Dapp-runtime=none','-Demit-docs=false',('-Dtest-filter="'+$Filter+'"'),'--summary','all')
$started=(Get-Date).ToString('o')
$p=$null
$timedOut=$false
$forced=$false
$shutdownConfirmed=$false
$taskkillExitCode=$null
$exitCode=$null
try{
    $p=Start-Process -FilePath $zig -ArgumentList $args -WorkingDirectory $workspace -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    # Retain the process object/handle; do not rediscover a process by name/PID.
    $null=$p.Handle
    $done=$p.WaitForExit($TimeoutSeconds*1000)
    if(-not $done){
        $timedOut=$true
        if(-not $p.HasExited){
            $forced=$true
            & taskkill.exe /PID $p.Id /T /F | Out-Null
            $taskkillExitCode=$LASTEXITCODE
        }
        $shutdownConfirmed=$p.WaitForExit(5000)
    }else{
        $shutdownConfirmed=$true
    }
    if($p.HasExited){$exitCode=$p.ExitCode}
}finally{
    if($null -ne $p){$p.Dispose()}
}
$changed=@()
foreach($relative in $sources){
    if((Get-FileHash -LiteralPath(Join-Path $workspace $relative) -Algorithm SHA256).Hash -ne $before[$relative]){$changed+=$relative}
}
$result=[ordered]@{
    label=$Label
    started=$started
    ended=(Get-Date).ToString('o')
    executable=$zig
    executable_sha256=(Get-FileHash -LiteralPath $zig -Algorithm SHA256).Hash
    arguments=$args
    source_sha256=$before
    source_changed_during_run=$changed
    exit_code=$exitCode
    timed_out=$timedOut
    forced_owned_tree_cleanup=$forced
    supervisor_root_exit_confirmed=$shutdownConfirmed
    taskkill_exit_code=$taskkillExitCode
    descendant_shutdown_independently_verified=$false
    shutdown_evidence_note='The retained handle verifies only the Zig root process exit. Native fixture assertions verify its private child in a normal run; no whole-tree shutdown claim is made after timeout.'
    stdout=$stdout
    stderr=$stderr
    scope='Filtered core test using actual Command.start and private headless helper; not app/GPU/human qualification.'
}
$json=$result|ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $logRoot 'result.json'),$json,[Text.UTF8Encoding]::new($false))
Write-Output $json
foreach($file in @($stdout,$stderr)){
    if(Test-Path -LiteralPath $file){Get-Content -LiteralPath $file -Encoding UTF8|Where-Object{$_.Length -lt 1000}|Select-Object -Last 22}
}
if($timedOut -or $forced -or -not $shutdownConfirmed){throw 'Owned test invocation exceeded its deadline; no pass claimed. See result.json for shutdown evidence.'}
if($changed.Count){throw 'Source changed while consumed by test; result invalidated'}
if($exitCode -ne 0){throw ('Targeted test exited '+$exitCode+'; inspect exact failure before classifying an expected original-red.')}
