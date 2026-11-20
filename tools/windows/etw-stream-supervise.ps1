param([Parameter(Mandatory=$true)][string]$Config)
$ErrorActionPreference='Stop'
$cfg=Get-Content -LiteralPath $Config -Raw -Encoding UTF8|ConvertFrom-Json
if($cfg.mode -notin @('control','collect')){throw 'Invalid streaming mode'}
$root=[IO.Path]::GetFullPath($cfg.root)
$exe=[IO.Path]::GetFullPath($cfg.stream_exe)
if([IO.Path]::GetDirectoryName($exe) -ne $root -or ((Get-Item $root).Attributes -band [IO.FileAttributes]::ReparsePoint) -or ((Get-Item $exe).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe private helper path'}
if(-not $cfg.session_name.StartsWith('Localterm-Stream-') -or [Guid]$cfg.guid -eq [Guid]::Empty){throw 'Invalid streaming session identity'}
if((Get-FileHash $exe -Algorithm SHA256).Hash -ne $cfg.stream_sha256){throw 'Streaming binary changed'}
$proc=$null;$cleanup=-1;$timedOut=$false;$exitCode=$null;$failure=$null
try{
    $proc=Start-Process $exe -ArgumentList @(('--'+$cfg.mode),('"'+$root+'"'),('"'+$cfg.session_name+'"'),('"'+$cfg.guid+'"')) -WindowStyle Hidden -PassThru
    $null=$proc.Handle
    $limit=if($cfg.mode -eq 'control'){24000}else{112000}
    if(-not $proc.WaitForExit($limit)){
        $timedOut=$true
        $killer=Start-Process "$env:SystemRoot\System32\taskkill.exe" -ArgumentList @('/PID',$proc.Id,'/T','/F') -WindowStyle Hidden -PassThru
        $null=$killer.WaitForExit(500);if(-not $killer.HasExited){$killer.Kill()};$killer.Dispose()
    }
    if($proc.HasExited){$exitCode=$proc.ExitCode}else{throw 'Owned streaming collector did not exit'}
}catch{$failure=$_.Exception.Message}
finally{
    $stop=Start-Process $exe -ArgumentList @('--stop-own',('"'+$cfg.session_name+'"'),('"'+$cfg.guid+'"')) -WindowStyle Hidden -PassThru
    $null=$stop.Handle
    if($stop.WaitForExit(2500)){$cleanup=$stop.ExitCode}else{$stop.Kill();$cleanup=-2}
    $stop.Dispose()
    [ordered]@{mode=$cfg.mode;controller_pid=if($proc){$proc.Id}else{$null};exit=$exitCode;timeout=$timedOut;cleanup_exit=$cleanup;root_exit_confirmed=if($proc){$proc.HasExited}else{$true};failure=$failure;raw_global_etl=$false;session=$cfg.session_name;guid=$cfg.guid}|ConvertTo-Json|Set-Content (Join-Path $root 'supervisor.json') -Encoding UTF8
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    foreach($file in Get-ChildItem -LiteralPath $root -File){
        if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse output refused'}
        $acl=New-Object Security.AccessControl.FileSecurity
        $acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
        foreach($s in @($sid,(New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))){$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($s,'FullControl','Allow')))}
        Set-Acl -LiteralPath $file.FullName -AclObject $acl
    }
    if($proc){$proc.Dispose()}
}
