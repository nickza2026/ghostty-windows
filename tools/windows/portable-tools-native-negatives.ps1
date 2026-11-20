param([Parameter(Mandatory=$true)][string]$PackageDirectory)
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$package=(Resolve-Path -LiteralPath $PackageDirectory).ProviderPath
$allowed=(Join-Path $workspace 'zig-out\portable-tools-fixtures')+'\'
if(-not $package.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Owned native test clone required, never a delivery or user package'}
$data=Join-Path $package 'bin\portable-data'
$exe=Join-Path $package 'bin\localterm-dev.exe'
$evidence=Join-Path $workspace ('zig-out\portable-tools-evidence\negative-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($evidence)
$keys=@('LOCALTERM_TERMINAL_SMOKE','LOCALTERM_INPUT_SMOKE','LOCALTERM_WINDOW_SMOKE','LOCALTERM_LIFECYCLE_SMOKE','LOCALTERM_TERMINAL_CASE','LOCALTERM_MIDLINE_SMOKE','LOCALTERM_APP_READLINE','LOCALTERM_PORTABLE_TOOLS','LOCALTERM_PORTABLE_TOOLS_CHECK','LOCALTERM_CONPTY_PROVIDER','LOCALTERM_CONPTY_EXPERIMENT')
$saved=@{};$results=@()
function AclRuleKeys($Acl){
    @($Acl.Access|ForEach-Object{[string]$_.IdentityReference+'|'+[int]$_.AccessControlType+'|'+[int]$_.FileSystemRights+'|'+[int]$_.InheritanceFlags+'|'+[int]$_.PropagationFlags+'|'+$_.IsInherited}|Sort-Object)
}
function RejectCase([string]$Name,[string]$Expected){
    $err=Join-Path $evidence ($Name+'.stderr.log');$out=Join-Path $evidence ($Name+'.stdout.log')
    $p=Start-Process -FilePath $exe -WorkingDirectory $workspace -WindowStyle Hidden -PassThru -RedirectStandardError $err -RedirectStandardOutput $out
    try{
        if(-not $p.WaitForExit(30000)){
            # Only the exact process we just created; timeout is never a pass.
            $p.Kill();$p.WaitForExit();throw "Negative native case timed out: $Name"
        }
        $p.WaitForExit();$text=[IO.File]::ReadAllText($err)
        if($p.ExitCode -eq 0 -or $text -notmatch $Expected -or $text -match 'started subcommand path='){
            throw "Native did not reject $Name before executing a child; exit=$($p.ExitCode), log=$err"
        }
        Write-Host "PASS native fail-closed $Name before child execution"
        return [ordered]@{name=$Name;exit=$p.ExitCode;expected=$Expected;child_started=$false;stderr=$err}
    }finally{$p.Dispose()}
}
try{
    foreach($key in $keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$null,'Process')}
    # No tool/readline opt-in: distribution default must not fall back either.
    $env:LOCALTERM_TERMINAL_SMOKE='1';$env:LOCALTERM_CONPTY_PROVIDER='system'
    $node=Join-Path $data 'runtimes\node\node.exe';$held=Join-Path $evidence 'held-node.exe'
    Move-Item -LiteralPath $node -Destination $held
    try{$results+=RejectCase 'missing-node' 'OwnedPathMissing'}finally{Move-Item -LiteralPath $held -Destination $node}
    $cli=Join-Path $data 'runtimes\node\node_modules\npm\bin\npm-cli.js';$bytes=[IO.File]::ReadAllBytes($cli)
    try{[IO.File]::AppendAllText($cli,"`n// owned negative hash fixture`n");$results+=RejectCase 'corrupt-npm-cli' 'OwnedDigestMismatch'}finally{[IO.File]::WriteAllBytes($cli,$bytes)}
    $extra=Join-Path $data 'runtimes\node\unlisted-fixture.cjs'
    if(Test-Path $extra){throw 'Unlisted fixture path exists'}
    try{[IO.File]::WriteAllText($extra,'throw new Error("must never execute")');$results+=RejectCase 'unlisted-runtime-code' 'UnlistedOwnedFile'}finally{[IO.File]::Delete($extra)}
    $psm=Join-Path $package 'bin\powershell\PSReadLine\PSReadLine.psm1';$bytes=[IO.File]::ReadAllBytes($psm)
    try{[IO.File]::AppendAllText($psm,"`nthrow 'must never import corrupted module'`n");$results+=RejectCase 'corrupt-powershell-module' 'OwnedDigestMismatch'}finally{[IO.File]::WriteAllBytes($psm,$bytes)}
    $license=Join-Path $package 'bin\powershell\PSReadLine\UPSTREAM-LICENSE';$held=Join-Path $evidence 'held-license'
    Move-Item -LiteralPath $license -Destination $held
    try{$results+=RejectCase 'missing-module-license' 'OwnedPathMissing'}finally{Move-Item -LiteralPath $held -Destination $license}
    $ownedHome=Join-Path $data 'home';$held=Join-Path $data 'held-home-owned-negative'
    if(Test-Path $held){throw 'Held home path exists'}
    Move-Item -LiteralPath $ownedHome -Destination $held
    try{[IO.File]::WriteAllText($ownedHome,'do not overwrite blocked home');$results+=RejectCase 'home-is-file' 'OwnedPathWrongKind'}finally{[IO.File]::Delete($ownedHome);Move-Item -LiteralPath $held -Destination $ownedHome}
    $target=Join-Path $evidence 'junction-target';$null=[IO.Directory]::CreateDirectory($target)
    $sentinel=Join-Path $target 'keep.txt';[IO.File]::WriteAllText($sentinel,'must not write through junction');$hash=(Get-FileHash $sentinel).Hash
    Move-Item -LiteralPath $ownedHome -Destination $held
    try{
        $null=New-Item -ItemType Junction -Path $ownedHome -Target $target
        $results+=RejectCase 'home-junction' 'OwnedPathReparsePoint'
        if((Get-FileHash $sentinel).Hash -ne $hash -or @(Get-ChildItem -LiteralPath $target -Force).Count -ne 1){throw 'Junction target modified'}
    }finally{
        if(Test-Path -LiteralPath $ownedHome){if(-not((Get-Item -LiteralPath $ownedHome -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Refuse unexpected home path cleanup'};[IO.Directory]::Delete($ownedHome)}
        Move-Item -LiteralPath $held -Destination $ownedHome
    }
    # Actual write denial on an owned nested destination, not readonly attrs.
    $cache=Join-Path $data 'cache\npm';$acl=Get-Acl -LiteralPath $cache;$original=$acl.GetSecurityDescriptorSddlForm('All')
    $beforeRules=AclRuleKeys $acl;$beforeOwner=$acl.Owner;$beforeGroup=$acl.Group;$beforeProtected=$acl.AreAccessRulesProtected
    try{
        $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
        $deny=New-Object Security.AccessControl.FileSystemAccessRule($sid,'Write','ContainerInherit,ObjectInherit','None','Deny')
        $changed=Get-Acl -LiteralPath $cache;$changed.AddAccessRule($deny);Set-Acl -LiteralPath $cache -AclObject $changed
        $results+=RejectCase 'npm-cache-write-denied' 'AccessDenied'
    }finally{
        $restore=New-Object Security.AccessControl.DirectorySecurity
        $restore.SetSecurityDescriptorSddlForm($original,[Security.AccessControl.AccessControlSections]::Access)
        Set-Acl -LiteralPath $cache -AclObject $restore
        $after=Get-Acl -LiteralPath $cache;$afterRules=AclRuleKeys $after
        # Persisting an unchanged Windows ACL adds D:AI metadata. Compare every
        # ACE plus owner/group/inheritance protection, not raw SDDL text alone.
        if(@(Compare-Object $beforeRules $afterRules).Count -or $after.Owner -ne $beforeOwner -or $after.Group -ne $beforeGroup -or $after.AreAccessRulesProtected -ne $beforeProtected){throw 'Owned fixture ACL permissions restore mismatch'}
        $probe=Join-Path $cache ('.restored-write-'+[guid]::NewGuid().ToString('N'))
        $file=[IO.File]::Open($probe,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$file.WriteByte(1)}finally{$file.Dispose()}
        [IO.File]::Delete($probe)
    }
    [ordered]@{package=$package;cases=$results;restored_all_mutations=$true;real_accounts_or_profiles_touched=$false}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $evidence 'results.json') -Encoding UTF8
    Write-Output "NATIVE_NEGATIVES_PASS=$evidence"
}finally{
    foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
}
