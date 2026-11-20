param([Parameter(Mandatory=$true)][string]$Directory,[switch]$AllowExfat)
$ErrorActionPreference='Stop'
$p=[IO.Path]::GetFullPath($Directory)
for($a=$p;$a;$a=[IO.Path]::GetDirectoryName($a)){
    if((Test-Path -LiteralPath $a) -and ((Get-Item -LiteralPath $a -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Private data reparse path refused'}
}
if(-not (Test-Path -LiteralPath $p -PathType Container)){throw 'Private directory must already exist'}
$format=([IO.DriveInfo]::new([IO.Path]::GetPathRoot($p))).DriveFormat
if($format -ieq 'exFAT'){
    if(-not $AllowExfat){throw 'exFAT has no per-user ACL protection. Explicit opt-in with Enable-ExFAT.cmd is required.'}
    '{"schema":1,"filesystem":"exFAT","protection":"reduced"}'
    return
}
if($format -ine 'NTFS'){throw 'Unsupported or unknown filesystem; no ACL failure fallback'}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$sections=[Security.AccessControl.AccessControlSections]::Access -bor [Security.AccessControl.AccessControlSections]::Owner
$acl=[IO.Directory]::GetAccessControl($p,$sections)
if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid.Value){throw 'Private data is not owned by the current user; no automatic ownership/elevation'}
$system=New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
$rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
$private=$acl.AreAccessRulesProtected -and $rules.Count -eq 2
foreach($rule in $rules){
    if($rule.IdentityReference.Value -notin @($sid.Value,$system.Value) -or
       $rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
       $rule.FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or
       $rule.InheritanceFlags -ne ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit)){$private=$false}
}
if($private){'{"schema":1,"filesystem":"NTFS","protection":"acl"}';return}
# Change only the DACL. Replacing a brand-new security descriptor with Set-Acl
# can request audit/SACL privileges on a later run; never request those rights.
$acl.SetAccessRuleProtection($true,$false)
foreach($rule in @($acl.GetAccessRules($true,$false,[Security.Principal.SecurityIdentifier]))){$acl.RemoveAccessRuleSpecific($rule)}
foreach($s in @($sid,$system)){
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($s,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
}
[IO.Directory]::SetAccessControl($p,$acl)
'{"schema":1,"filesystem":"NTFS","protection":"acl"}'
