param([ValidateSet('control','collect')][string]$Mode='control')
$ErrorActionPreference='Stop'
$base=Join-Path $env:LOCALAPPDATA 'Letta/private-traces'
$ancestor=[IO.Path]::GetFullPath($base)
while($ancestor){
    if((Test-Path $ancestor) -and ((Get-Item $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Reparse private evidence ancestor refused'}
    $ancestor=[IO.Path]::GetDirectoryName($ancestor.TrimEnd('\'))
}
$nonce=[Guid]::NewGuid();$root=Join-Path $base ('ghostty-stream-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$nonce.ToString('N').Substring(0,8))
if(Test-Path $root){throw 'Fresh evidence directory required'}
$null=New-Item -ItemType Directory -Path $root
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
foreach($s in @($sid,(New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))){$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($s,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))}
Set-Acl $root $acl
$names=@('etw-handle-stream.c','etw-handle-decode.c','etw-handle-control.c','etw-stream-supervise.ps1','etw-suspended-launch.c')
foreach($name in $names){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $root $name)}
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64 -SkipAutomaticLocation|Out-Null
$zig='C:\Users\nickl\AppData\Local\Programs\Zig\zig-x86_64-windows-0.16.0\zig.exe'
$tests=@()
foreach($name in @('etw-handle-stream','etw-suspended-launch')){
    $exe=Join-Path $root ($name+'.exe')
    & $zig build-exe -target x86_64-windows-msvc -O ReleaseSafe --subsystem windows -lc -ladvapi32 -lshell32 -lole32 -lpsapi -lntdll -cflags -O0 -fno-omit-frame-pointer -fno-optimize-sibling-calls -- (Join-Path $root ($name+'.c')) ('-femit-bin='+$exe)
    if($LASTEXITCODE){throw ('Compile failed before ETW: '+$name)}
    $bytes=[IO.File]::ReadAllBytes($exe);$pe=[BitConverter]::ToInt32($bytes,60)
    if([BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664 -or [BitConverter]::ToUInt16($bytes,$pe+92) -ne 2){throw 'Headless x64 PE check failed'}
    $p=Start-Process $exe -ArgumentList '--selftest' -WindowStyle Hidden -PassThru;$null=$p.Handle
    if(-not $p.WaitForExit(5000)){$p.Kill();throw 'Data-only selftest timeout'}
    $code=$p.ExitCode;$p.Dispose();if($code){throw ('Data-only selftest failed '+$name+' '+$code)}
    $tests += [ordered]@{name=$name;exit=$code}
}
$stream=Join-Path $root 'etw-handle-stream.exe'
$cfg=[ordered]@{root=$root;mode=$Mode;session_name=('Localterm-Stream-'+$nonce.ToString('N'));guid=$nonce.ToString('B');stream_exe=$stream;stream_sha256=(Get-FileHash $stream -Algorithm SHA256).Hash;selftests=$tests;raw_global_etl=$false;source_hashes=@($names|ForEach-Object{[ordered]@{file=$_;sha256=(Get-FileHash (Join-Path $root $_) -Algorithm SHA256).Hash}})}
$cfg|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root 'config.json') -Encoding UTF8
Write-Output ('STREAM_PREPARED='+$root)
