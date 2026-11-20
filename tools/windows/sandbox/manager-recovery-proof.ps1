param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][int]$ClientPid,
    [Parameter(Mandatory=$true)][string]$ExpectedStateSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedRootId,
    [switch]$NoState
)
# Called only while the Node caller holds startup AND temporary manager leases.
# This process retains every disk proof handle through the actual archive move.
$ErrorActionPreference='Stop'
$held=[Collections.Generic.List[IDisposable]]::new()
$reason='UNKNOWN_EVIDENCE'
function Refuse([string]$Code){ $script:reason=$Code; throw 'Recovery refused' }
function Full([string]$Path){ return [IO.Path]::GetFullPath($Path) }
function SamePath([string]$A,[string]$B){ return [string]::Equals((Full $A),(Full $B),[StringComparison]::OrdinalIgnoreCase) }
function NoReparse([string]$Path,[bool]$Directory=$false){
    $full=Full $Path
    $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if([bool]$item.PSIsContainer -ne $Directory){Refuse 'UNEXPECTED_FILE_TYPE'}
    for($a=$full;$a;$a=[IO.Path]::GetDirectoryName($a)){
        $entry=Get-Item -LiteralPath $a -Force -ErrorAction Stop
        if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){Refuse 'REPARSE_PATH'}
    }
    return $full
}
function Hash([byte[]]$Bytes){
    $algorithm=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$algorithm.Dispose()}
}
function ReadBytes([IO.FileStream]$Stream,[int]$Limit=8192){
    if($Stream.Length -lt 1 -or $Stream.Length -gt $Limit){Refuse 'METADATA_SIZE'}
    $bytes=New-Object byte[] ([int]$Stream.Length);$Stream.Position=0;$offset=0
    while($offset -lt $bytes.Length){$count=$Stream.Read($bytes,$offset,$bytes.Length-$offset);if($count -le 0){Refuse 'INCOMPLETE_METADATA'};$offset+=$count}
    return ,$bytes
}
function Json([byte[]]$Bytes){return [Text.Encoding]::UTF8.GetString($Bytes)|ConvertFrom-Json}
function HasEntry([string]$Path){
    try{$null=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;return $true}
    catch [System.Management.Automation.ItemNotFoundException]{return $false}
}
function OpenMetadata([string]$Path,[bool]$AllowRename=$false){
    $path=NoReparse $Path
    $sharing=[IO.FileShare]::Read
    if($AllowRename){$sharing=$sharing -bor [IO.FileShare]::Delete}
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,$sharing)
    $held.Add($stream)
    $identity=[SandboxRecoveryFile]::Identity($stream.SafeFileHandle)
    if($identity.Links -ne 1){Refuse 'MULTIPLE_FILE_LINKS'}
    return $stream
}
function Port([object]$Value,[int]$Min=1){
    if($null -eq $Value -or $Value -isnot [ValueType] -or [double]$Value -ne [int]$Value -or [int]$Value -lt $Min -or [int]$Value -gt 65535){Refuse 'INVALID_PORT'}
    return [int]$Value
}
function RefusedPort([int]$Port){
    $socket=[Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Stream,[Net.Sockets.ProtocolType]::Tcp)
    $pending=$null
    try{
        $pending=$socket.BeginConnect([Net.IPAddress]::Loopback,$Port,$null,$null)
        # This host returned ConnectionRefused after ~2s for a closed loopback
        # port. Wait for the actual error, never equate a timeout with absence.
        if(-not $pending.AsyncWaitHandle.WaitOne(5000)){Refuse 'PORT_PROBE_TIMEOUT'}
        try{$socket.EndConnect($pending)}catch{
            $cause=$_.Exception
            while($cause -and $cause -isnot [Net.Sockets.SocketException]){$cause=$cause.InnerException}
            if($cause -and $cause.SocketErrorCode -eq [Net.Sockets.SocketError]::ConnectionRefused){return}
            Refuse 'PORT_PROBE_AMBIGUOUS'
        }
        Refuse 'LIVE_PORT'
    }finally{if($pending){$pending.AsyncWaitHandle.Dispose()};$socket.Dispose()}
}
function ReadOnlyImageInfo([string]$Executable){
    $p=[Diagnostics.Process]::new();$p.StartInfo=[Diagnostics.ProcessStartInfo]::new()
    $p.StartInfo.FileName=$Executable;$p.StartInfo.Arguments='info --output=json --backing-chain Data/guest.qcow2'
    $p.StartInfo.WorkingDirectory=$Root;$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
    $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    try{
        if(-not $p.Start()){Refuse 'IMAGE_INFO_START_FAILED'}
        $out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(10000)){
            # Only this newly-created read-only qemu-img probe, never a discovered
            # process, manager, QEMU VM, or saved PID, can be ended on its deadline.
            $p.Kill();$p.WaitForExit(2000)|Out-Null;Refuse 'IMAGE_INFO_TIMEOUT'
        }
        $text=$out.GetAwaiter().GetResult();$null=$err.GetAwaiter().GetResult()
        if($p.ExitCode -ne 0 -or $text.Length -gt 65536){Refuse 'IMAGE_INFO_FAILED'}
        return @($text|ConvertFrom-Json)
    }finally{$p.Dispose()}
}
try{
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $ClientPid -lt 1 -or $ExpectedStateSha256 -notmatch '^[a-f0-9]{64}$' -or $ExpectedRootId.Length -lt 16){Refuse 'INVALID_REQUEST'}
    $Root=NoReparse (Full $Root) $true
    $data=NoReparse ([IO.Path]::Combine($Root,'Data')) $true
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class SandboxRecoveryFile {
  [StructLayout(LayoutKind.Sequential)] private struct Info {
    public uint Attributes; public System.Runtime.InteropServices.ComTypes.FILETIME Creation;
    public System.Runtime.InteropServices.ComTypes.FILETIME Access;
    public System.Runtime.InteropServices.ComTypes.FILETIME Write;
    public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
  }
  public struct FileIdentity { public uint Links, Volume, IndexHigh, IndexLow; public long Creation; }
  [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetFileInformationByHandle(SafeFileHandle file, out Info info);
  public static FileIdentity Identity(SafeFileHandle file) {
    Info i; if(!GetFileInformationByHandle(file,out i)) throw new Win32Exception(Marshal.GetLastWin32Error());
    return new FileIdentity { Links=i.Links,Volume=i.Volume,IndexHigh=i.IndexHigh,IndexLow=i.IndexLow,
      Creation=((long)i.Creation.dwHighDateTime<<32)|(uint)i.Creation.dwLowDateTime };
  }
  public static bool Same(FileIdentity a,FileIdentity b) {
    return a.Links==b.Links&&a.Volume==b.Volume&&a.IndexHigh==b.IndexHigh&&a.IndexLow==b.IndexLow&&a.Creation==b.Creation;
  }
}
'@
    $ownerPath=[IO.Path]::Combine($Root,'sandbox-owned.json');$statePath=[IO.Path]::Combine($data,'manager.json')
    $ownerStream=OpenMetadata $ownerPath;$ownerBytes=ReadBytes $ownerStream;$owner=Json $ownerBytes
    if($owner.name -cne 'ghostty-sandbox-owned' -or $owner.schema -ne 1 -or $owner.nonce -cne $ExpectedRootId){Refuse 'OWNER_CHANGED'}
    $ports=[Collections.Generic.HashSet[int]]::new();$state=$null
    if($NoState){if(HasEntry $statePath){Refuse 'STATE_APPEARED'}}else{
        $stateStream=OpenMetadata $statePath $true;$stateBytes=ReadBytes $stateStream
        if((Hash $stateBytes) -cne $ExpectedStateSha256){Refuse 'STATE_CHANGED'}
        $stateIdentity=[SandboxRecoveryFile]::Identity($stateStream.SafeFileHandle);$state=Json $stateBytes
        if(-not (SamePath $state.root $Root) -or $state.rootId -cne $ExpectedRootId -or $state.token -cnotmatch '^[a-f0-9]{64}$' -or $state.managerNonce -cnotmatch '^[a-f0-9]{64}$' -or $state.phase -cnotin @('booting','ready','failed','stopping','stopped')){Refuse 'INVALID_MANAGER_STATE'}
        $null=$ports.Add((Port $state.port))
    }
    $vmPath=[IO.Path]::Combine($data,'vm.json');$factory=-not (HasEntry $vmPath);$vm=$null
    if($factory){
        if(-not $NoState){Refuse 'MISSING_VM_IDENTITY'}
        foreach($name in @('guest.qcow2','seed.img','bootstrap-verified.json','ssh','recovery','manager-last.json')){if(HasEntry ([IO.Path]::Combine($data,$name))){Refuse 'INCOMPLETE_FIRST_START'}}
    }else{
        $vmStream=OpenMetadata $vmPath;$vmBytes=ReadBytes $vmStream;$vm=Json $vmBytes
        if($vm.schema -ne 1 -or $vm.instanceId -cnotmatch '^portable-[a-f0-9]{32}$'){Refuse 'INVALID_VM_IDENTITY'}
        $null=$ports.Add((Port $vm.sshPort 1024))
    }
    $profilePath=[IO.Path]::Combine($Root,'guest-profile.json');$profilePresent=HasEntry $profilePath
    if($profilePresent){$profileStream=OpenMetadata $profilePath;$profileBytes=ReadBytes $profileStream;$profile=Json $profileBytes}
    else{$profile=[pscustomobject]@{schema=1;profile='sdk';ports=@()}}
    # Preserve guest-config.profile's established absent-file SDK default and
    # omitted-ports empty list. Explicit null/object port lists remain invalid.
    if(@($profile.PSObject.Properties.Name) -contains 'ports'){
        if($profile.ports -isnot [Array]){Refuse 'INVALID_GUEST_PROFILE'}
        $mappings=@($profile.ports)
    }else{$mappings=@()}
    $vmProfile=if($vm.guestProfile){$vm.guestProfile}else{'sdk'}
    if($profile.schema -ne 1 -or $profile.profile -cnotin @('sdk','clean','node') -or $mappings.Count -gt 8 -or (-not $factory -and $vmProfile -cne $profile.profile)){Refuse 'INVALID_GUEST_PROFILE'}
    $hostPorts=[Collections.Generic.HashSet[int]]::new();$guestPorts=[Collections.Generic.HashSet[int]]::new()
    foreach($mapping in $mappings){
        if(-not $mapping -or (@($mapping.PSObject.Properties.Name|Sort-Object)-join ',') -cne 'guestPort,hostPort'){Refuse 'INVALID_MAPPING'}
        $hp=Port $mapping.hostPort 1024;$gp=Port $mapping.guestPort 1024
        if(-not $hostPorts.Add($hp) -or -not $guestPorts.Add($gp) -or $hp -eq $vm.sshPort){Refuse 'DUPLICATE_MAPPING'}
        $null=$ports.Add($hp)
    }
    if($null -ne $state.activePorts){
        if(@($state.activePorts).Count -gt 10){Refuse 'INVALID_ACTIVE_PORT_SNAPSHOT'}
        foreach($p in @($state.activePorts)){$null=$ports.Add((Port $p))}
    }
    $node=NoReparse ([IO.Path]::Combine($Root,'Runtime\node\node.exe'))
    $qemuRoot=NoReparse ([IO.Path]::Combine($Root,'Runtime\qemu')) $true
    $entry=[IO.Path]::Combine($Root,'App\entry.cjs')
    $knownEntry='^"?'+[Regex]::Escape($node)+'"?\s+"?'+[Regex]::Escape($entry)+'"?\s+(terminal|ide)\s+"?'+[Regex]::Escape($Root)+'"?\s*$'
    $processes=@(Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='qemu-system-x86_64.exe'" -OperationTimeoutSec 8 -ErrorAction Stop)
    foreach($process in $processes){
        if(-not $process.ExecutablePath){Refuse 'PROCESS_IDENTITY_UNREADABLE'}
        if($process.Name -ieq 'qemu-system-x86_64.exe' -and $process.ExecutablePath.StartsWith($qemuRoot+'\',[StringComparison]::OrdinalIgnoreCase)){Refuse 'LIVE_PACKAGE_QEMU'}
        if((SamePath $process.ExecutablePath $node) -and $process.ProcessId -ne $ClientPid){
            if(-not $process.CommandLine -or $process.CommandLine -notmatch $knownEntry){Refuse 'LIVE_PACKAGE_NODE'}
        }
    }
    # QEMU paths may be nested in its verified public runtime. Do not traverse
    # reparse points while locating the read-only tool.
    $candidates=[Collections.Generic.List[string]]::new();$queue=[Collections.Generic.Queue[object]]::new();$queue.Enqueue(@($qemuRoot,0));$seen=0
    while($queue.Count){$row=$queue.Dequeue();foreach($item in Get-ChildItem -LiteralPath $row[0] -Force){
        $seen++;if($seen -gt 4096){Refuse 'RUNTIME_TREE_LIMIT'}
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){Refuse 'REPARSE_RUNTIME'}
        if($item.PSIsContainer){if($row[1] -ge 8){Refuse 'RUNTIME_DEPTH_LIMIT'};$queue.Enqueue(@($item.FullName,([int]$row[1]+1)))}
        elseif($item.Name -ieq 'qemu-img.exe'){$candidates.Add($item.FullName)}
    }}
    if($candidates.Count -ne 1){Refuse 'AMBIGUOUS_IMAGE_TOOL'}
    $null=OpenMetadata $candidates[0]
    $base=NoReparse ([IO.Path]::Combine($Root,'Runtime\base\debian.qcow2'))
    if(-not $factory){
    $disk=NoReparse ([IO.Path]::Combine($data,'guest.qcow2'));$seed=NoReparse ([IO.Path]::Combine($data,'seed.img'))
    $chain=ReadOnlyImageInfo $candidates[0]
    if($chain.Count -ne 2){Refuse 'UNEXPECTED_DISK_CHAIN'}
    for($i=0;$i -lt 2;$i++){
        $image=$chain[$i];$expected=@($disk,$base)[$i]
        $reported=$image.filename;if(-not [IO.Path]::IsPathRooted($reported)){$reported=[IO.Path]::Combine($Root,$reported)}
        if(-not (SamePath $reported $expected) -or $image.format -cne 'qcow2' -or $image.'format-specific'.data.corrupt -eq $true){Refuse 'CORRUPT_OR_UNEXPECTED_DISK'}
    }
    }
    $proofFiles=if($factory){@($base)}else{@($disk,$base,$seed)}
    foreach($file in $proofFiles){
        try{$stream=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)}catch{Refuse 'BUSY_DISK'}
        $held.Add($stream)
        if(([SandboxRecoveryFile]::Identity($stream.SafeFileHandle)).Links -ne 1){Refuse 'MULTIPLE_DISK_LINKS'}
    }
    foreach($p in $ports){RefusedPort $p}
    # These metadata handles disallow writes, and all are checked again before
    # the move. State permits rename only so the exact held node can be archived.
    if((Hash (ReadBytes $ownerStream)) -cne (Hash $ownerBytes) -or (-not $factory -and (Hash (ReadBytes $vmStream)) -cne (Hash $vmBytes))){Refuse 'METADATA_CHANGED'}
    if($profilePresent){if((Hash (ReadBytes $profileStream)) -cne (Hash $profileBytes)){Refuse 'METADATA_CHANGED'}}
    elseif(HasEntry $profilePath){Refuse 'METADATA_CHANGED'}
    if($NoState){
        if(HasEntry $statePath){Refuse 'STATE_APPEARED'}
        if($factory){foreach($name in @('vm.json','guest.qcow2','seed.img','bootstrap-verified.json','ssh','recovery','manager-last.json')){if(HasEntry ([IO.Path]::Combine($data,$name))){Refuse 'FACTORY_CHANGED'}}}
        @{vacant=$true}|ConvertTo-Json -Compress
        return
    }
    if((Hash (ReadBytes $stateStream)) -cne $ExpectedStateSha256){Refuse 'STATE_CHANGED'}
    $current=OpenMetadata $statePath $true
    if(-not [SandboxRecoveryFile]::Same($stateIdentity,[SandboxRecoveryFile]::Identity($current.SafeFileHandle))){Refuse 'STATE_IDENTITY_CHANGED'}
    $recovery=[IO.Path]::Combine($data,'recovery')
    if([IO.Directory]::Exists($recovery)){$null=NoReparse $recovery $true}else{if([IO.File]::Exists($recovery)){Refuse 'RECOVERY_PATH_OCCUPIED'};$null=[IO.Directory]::CreateDirectory($recovery);$null=NoReparse $recovery $true}
    $nonce=[Guid]::NewGuid().ToString();$archiveDirectory=[IO.Path]::Combine($recovery,$nonce)
    if(Test-Path -LiteralPath $archiveDirectory){Refuse 'ARCHIVE_COLLISION'}
    $null=[IO.Directory]::CreateDirectory($archiveDirectory);$null=NoReparse $archiveDirectory $true
    $archive=[IO.Path]::Combine($archiveDirectory,'manager.json')
    [IO.File]::Move($statePath,$archive)
    $archived=OpenMetadata $archive $true
    # exFAT's directory-entry-derived file index changes on a cross-directory
    # rename. Re-query the STILL-HELD original handle after the move, rather
    # than comparing the archived node to its obsolete pre-move index. Both
    # held handles must now identify the same file and preserve the exact bytes.
    $heldAfterMove=[SandboxRecoveryFile]::Identity($stateStream.SafeFileHandle)
    if(-not [SandboxRecoveryFile]::Same($heldAfterMove,[SandboxRecoveryFile]::Identity($archived.SafeFileHandle)) -or (Hash (ReadBytes $stateStream)) -cne $ExpectedStateSha256 -or (Hash (ReadBytes $archived)) -cne $ExpectedStateSha256){Refuse 'ARCHIVE_VERIFICATION_FAILED'}
    @{recovered=$true;archive="Data/recovery/$nonce/manager.json"}|ConvertTo-Json -Compress
}catch{
    [Console]::Error.WriteLine('RECOVERY_REFUSED: '+$reason)
    exit 1
}finally{
    for($i=$held.Count-1;$i -ge 0;$i--){$held[$i].Dispose()}
}
