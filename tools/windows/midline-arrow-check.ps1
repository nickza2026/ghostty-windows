# Fresh owned interactive PSReadLine cases, never the human preview/session.
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$zig=Join-Path $env:LOCALAPPDATA 'Programs\Zig\zig-x86_64-windows-0.16.0\zig.exe'
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$prefix=Join-Path $workspace ('zig-out\midline-arrow-'+$stamp)
$dir=Join-Path $env:LOCALAPPDATA ('Letta\build-logs\ghostty-windows\thai-midline\arrow-'+$stamp)
$null=[IO.Directory]::CreateDirectory($dir)
$inputs=@('src/apprt/win32/App.zig','src/apprt/win32/midline_edit_fixture.zig','tools/windows/runtime-smoke.ps1','tools/windows/midline-arrow-check.ps1','src/conpty_windows.zig','src/pty.zig')
$before=@($inputs|ForEach-Object{Get-FileHash (Join-Path $workspace $_)}|Select-Object Path,Hash)
$before|ConvertTo-Json|Set-Content (Join-Path $dir 'source-before.json') -Encoding UTF8
& $zig build -j2 -Dapp-runtime=win32 -Dtarget=x86_64-windows-msvc -Dcpu=baseline -Doptimize=ReleaseSafe -Demit-docs=false -p $prefix --summary all
if($LASTEXITCODE -ne 0){throw 'Interactive fixture build failed; not a reproduced product defect'}
$bin=Join-Path $prefix 'bin'
$prov=Get-Content (Join-Path $workspace 'zig-out/conpty-ab/bin/ConPTY-experiment.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($f in $prov.files){
    $src=Join-Path $workspace ('zig-out\conpty-ab\bin\'+$f.name)
    if((Get-FileHash $src).Hash -ne $f.sha256){throw 'Provider cache hash mismatch'}
    Copy-Item $src (Join-Path $bin $f.name)
}
Copy-Item (Join-Path $workspace 'zig-out/conpty-ab/bin/ConPTY-experiment.json') $bin
Copy-Item (Join-Path $workspace 'zig-out/conpty-ab/bin/ConPTY-LICENSE.txt') $bin
[ordered]@{prefix=$prefix;source_sha256=$before;binary_sha256=(Get-FileHash (Join-Path $bin 'localterm-dev.exe')).Hash;psreadline='installed Microsoft 2.0.0';history='private APPDATA, SaveNothing';input='owned Core key callbacks, 12 left arrows, 32 inserted a; no OS input/live preview';provider=$prov}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $dir 'provenance.json') -Encoding UTF8
Write-Output ('ARROW_REPRO_ARTIFACT='+$dir)
foreach($provider in @('system','app-local')){
    $failure=$null
    try { & (Join-Path $PSScriptRoot 'runtime-smoke.ps1') -Mode terminal -MidlineSmoke -TimeoutSeconds 45 -ConptyProvider $provider -Executable (Join-Path $bin 'localterm-dev.exe') }
    catch { $failure=$_.Exception.Message;Write-Output ($provider+'_FAILURE='+$failure) }
    [ordered]@{provider=$provider;supervisor_failure=$failure;automatic_fix_claim=$false}|ConvertTo-Json|Set-Content (Join-Path $dir ($provider+'-summary.json')) -Encoding UTF8
}
$after=@($inputs|ForEach-Object{Get-FileHash (Join-Path $workspace $_)}|Select-Object Path,Hash)
$changed=@(Compare-Object $before $after -Property Path,Hash).Count -ne 0
[ordered]@{source_changed=$changed;original_user_preview_touched=$false;product_fixed_claim=$false}|ConvertTo-Json|Set-Content (Join-Path $dir 'final.json') -Encoding UTF8
Write-Output ('ARROW_REPRO_COMPLETE='+$dir)
if($changed){throw 'Source changed during reproduction; evidence invalidated'}
