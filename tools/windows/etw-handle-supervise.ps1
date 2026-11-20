param([Parameter(Mandatory=$true)][string]$Config)
$ErrorActionPreference='Stop'
# This file is launched once through the user's approved UAC elevation. No
# ExecutionPolicy override, installs, persistent settings, or foreign sessions.
$cfg=Get-Content -LiteralPath $Config -Raw -Encoding UTF8|ConvertFrom-Json
$mode='control'
if($cfg.PSObject.Properties.Name -contains 'mode'){
    if($cfg.mode -cnotin @('control','collect')){throw 'Invalid capture mode'}
    $mode=$cfg.mode
}
$timeoutMs=if($mode -eq 'collect'){112000}else{24000}
$root=[IO.Path]::GetFullPath($cfg.root)
if((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse evidence directory refused'}
if(-not $cfg.session_name.StartsWith('Localterm-Owned-') -or ([Guid]$cfg.guid) -eq [Guid]::Empty){throw 'Invalid owned-session identity'}
foreach($name in @('control_exe','decoder_exe')){
    $file=[IO.Path]::GetFullPath($cfg.$name)
    if([IO.Path]::GetDirectoryName($file) -ne $root -or (Get-Item -LiteralPath $file).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Helper path refused'}
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $cfg.($name+'_sha256')){throw 'Helper binary changed'}
}
$p=$null;$timeout=$false;$cleanup=-1;$failure=$null;$exitCode=$null;$cleanupClock=$null
try{
    $args=@(('--'+$mode),('"'+$root+'"'),('"'+$cfg.session_name+'"'),('"'+$cfg.guid+'"'))
    $p=Start-Process -FilePath $cfg.control_exe -ArgumentList $args -WindowStyle Hidden -PassThru
    $null=$p.Handle
    if(-not $p.WaitForExit($timeoutMs)){
        $timeout=$true
        $cleanupClock=[Diagnostics.Stopwatch]::StartNew()
        if(-not $p.HasExited){
            $killer=Start-Process -FilePath "$env:SystemRoot\System32\taskkill.exe" -ArgumentList @('/PID',$p.Id,'/T','/F') -WindowStyle Hidden -PassThru
            if(-not $killer.WaitForExit(500)){if(-not $killer.HasExited){$killer.Kill()}}
            $killer.Dispose()
        }
    }
    if($p.HasExited){$exitCode=$p.ExitCode}else{throw 'Owned controller did not exit'}
}catch{$failure=$_.Exception.Message}
finally{
    if(-not $cleanupClock){$cleanupClock=[Diagnostics.Stopwatch]::StartNew()}
    # Query expected GUID before stopping only this newly created session.
    $stop=Start-Process -FilePath $cfg.control_exe -ArgumentList @('--stop-own',('"'+$cfg.session_name+'"'),('"'+$cfg.guid+'"')) -WindowStyle Hidden -PassThru
    $null=$stop.Handle
    $remaining=[Math]::Max(0,3000-[int]$cleanupClock.ElapsedMilliseconds)
    if($stop.WaitForExit($remaining)){$cleanup=$stop.ExitCode}else{if(-not $stop.HasExited){$stop.Kill()};$cleanup=-2}
    $stop.Dispose()
    [ordered]@{mode=$mode;controller_pid=if($p){$p.Id}else{$null};exit=$exitCode;timeout=$timeout;cleanup_exit=$cleanup;root_exit_confirmed=if($p){$p.HasExited}else{$true};failure=$failure;session=$cfg.session_name;guid=$cfg.guid;terminal_launched=$false}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $root 'supervisor.json') -Encoding UTF8
    # ETL can be created with Administrators as owner by an elevated token.
    # Restrict only this owned evidence tree to current user + LocalSystem.
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    foreach($f in Get-ChildItem -LiteralPath $root -File){
        if($f.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse output refused'}
        $acl=New-Object Security.AccessControl.FileSecurity
        $acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
        foreach($s in @($sid,(New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))){
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($s,'FullControl','Allow')))
        }
        Set-Acl -LiteralPath $f.FullName -AclObject $acl
    }
    if($p){$p.Dispose()}
}
