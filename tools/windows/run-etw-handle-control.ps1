param([switch]$PrepareOnly,[switch]$PreserveCurrentPointer)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$base=Join-Path $env:LOCALAPPDATA 'Letta/private-traces'
function Assert-NoReparse([string]$path){
    $p=[IO.Path]::GetFullPath($path)
    while($p){
        if(Test-Path -LiteralPath $p){if((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse path refused'}}
        $parent=[IO.Path]::GetDirectoryName($p.TrimEnd('\'))
        if($parent -eq $p){break};$p=$parent
    }
}
Assert-NoReparse $base
$nonce=[Guid]::NewGuid()
$root=Join-Path $base ('ghostty-owned-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$nonce.ToString('N').Substring(0,8))
if(Test-Path -LiteralPath $root){throw 'Fresh evidence directory required'}
$null=New-Item -ItemType Directory -Path $root
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
foreach($s in @($sid,(New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))){
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($s,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
}
Set-Acl -LiteralPath $root -AclObject $acl
foreach($name in @('etw-handle-control.c','etw-handle-decode.c','etw-handle-supervise.ps1')){
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $root $name)
}
$sourceHashes=@(Get-ChildItem -LiteralPath $root -File|ForEach-Object{[ordered]@{file=$_.Name;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}})
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64 -SkipAutomaticLocation|Out-Null
$zig='C:\Users\nickl\AppData\Local\Programs\Zig\zig-x86_64-windows-0.16.0\zig.exe'
foreach($name in @('etw-handle-control','etw-handle-decode')){
    $exe=Join-Path $root ($name+'.exe')
    & $zig build-exe -target x86_64-windows-msvc -O ReleaseSafe --subsystem windows -lc -ladvapi32 -lshell32 -lole32 -lpsapi -lntdll -cflags -O0 -fno-omit-frame-pointer -fno-optimize-sibling-calls -- (Join-Path $root ($name+'.c')) ('-femit-bin='+$exe)
    if($LASTEXITCODE){throw ('Compile failed; no session: '+$name)}
    $bytes=[IO.File]::ReadAllBytes($exe);$pe=[BitConverter]::ToInt32($bytes,60)
    if($pe -lt 64 -or $pe+94 -ge $bytes.Length -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664 -or [BitConverter]::ToUInt16($bytes,$pe+92) -ne 2){throw 'x64 no-console PE preflight failed'}
}
$decoder=Join-Path $root 'etw-handle-decode.exe'
$test=Start-Process -FilePath $decoder -ArgumentList '--selftest' -WindowStyle Hidden -PassThru
$null=$test.Handle
if(-not $test.WaitForExit(5000)){$test.Kill();$null=$test.WaitForExit(1000);throw 'Decoder selftest timeout; no ETW session'}
$testExit=$test.ExitCode;$test.Dispose()
if($testExit){throw ('Decoder selftest failed '+$testExit+'; no ETW session')}
$control=Join-Path $root 'etw-handle-control.exe'
$cfg=[ordered]@{root=$root;session_name=('Localterm-Owned-'+$nonce.ToString('N'));guid=$nonce.ToString('B');control_exe=$control;control_exe_sha256=(Get-FileHash $control -Algorithm SHA256).Hash;decoder_exe=$decoder;decoder_exe_sha256=(Get-FileHash $decoder -Algorithm SHA256).Hash;source_hashes=$sourceHashes;selftest_exit=$testExit;approved_control_seconds=30;conditional_terminal_seconds=120;system_wide_metadata_possible=$true;raw_data_upload_allowed=$false}
$config=Join-Path $root 'config.json';$cfg|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $config -Encoding UTF8
# Repository gets only the path to private evidence, never ETL/foreign metadata.
if(-not $PreserveCurrentPointer){Set-Content -LiteralPath (Join-Path $repo 'zig-out/etw-control-current.txt') -Value $root -Encoding UTF8}
if($PrepareOnly){Write-Output ('ETW_PREPARED='+$root);return}
$supervisor=Join-Path $root 'etw-handle-supervise.ps1'
$args=@('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-File',('"'+$supervisor+'"'),'-Config',('"'+$config+'"'))
$elevated=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $args -Verb RunAs -WindowStyle Hidden -PassThru
$null=$elevated.Handle
if(-not $elevated.WaitForExit(60000)){throw 'Elevated supervisor did not complete; do not launch terminal'}
$elevated.Dispose()
$supervised=Get-Content -LiteralPath (Join-Path $root 'supervisor.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($supervised.timeout -or $supervised.cleanup_exit -ne 0 -or -not $supervised.root_exit_confirmed){throw 'Owned control/session cleanup not confirmed; stop'}
Write-Output ('ETW_CONTROL_PRIVATE='+$root)
Write-Output ('ETW_CONTROL_EXIT='+$supervised.exit)
if($supervised.exit -ne 0){Write-Output 'ETW_CONTROL_UNQUALIFIED_NO_TERMINAL';return}
$controlRows=@(Get-Content -LiteralPath (Join-Path $root 'control.jsonl') -Encoding UTF8|ForEach-Object{$_|ConvertFrom-Json})
$childRows=@(Get-Content -LiteralPath (Join-Path $root 'child.jsonl') -Encoding UTF8|ForEach-Object{$_|ConvertFrom-Json})
$parentId=@($controlRows|Where-Object{$_.kind -eq 'control'})[0].pid
$childId=@($childRows|Where-Object{$_.kind -eq 'child_result'})[0].pid
$decode=Start-Process -FilePath $decoder -ArgumentList @(('"'+(Join-Path $root 'handles.etl')+'"'),('"'+(Join-Path $root 'decoded.jsonl')+'"'),$parentId,$childId) -WindowStyle Hidden -PassThru
$null=$decode.Handle
if(-not $decode.WaitForExit(15000)){$decode.Kill();$null=$decode.WaitForExit(1000);throw 'Offline decoder deadline; no terminal'}
$decodeExit=$decode.ExitCode;$decode.Dispose()
Write-Output ('ETW_DECODE_EXIT='+$decodeExit)
Write-Output 'CALLSTACK_QUALIFICATION_PENDING_NO_TERMINAL'
