param([Parameter(Mandatory=$true)][string]$Job,[Parameter(Mandatory=$true)][string]$Nonce,[switch]$PlanOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'exfat-vhd-guards.ps1')
Assert-ExfatJob $Job $Nonce
$image=Join-Path $Job 'test.vhdx'
$drive='Z:\'
function State([string]$Phase,[string]$Detail=''){
    $value=@{schema=1;nonce=$Nonce;phase=$Phase;image=$image;drive=$drive;detail=$Detail}
    $value|ConvertTo-Json -Compress|Set-Content -LiteralPath (Join-Path $Job 'state.next') -Encoding UTF8
    Move-Item -LiteralPath (Join-Path $Job 'state.next') -Destination (Join-Path $Job 'state.json') -Force
}
if($PlanOnly){@{image=$image;virtualBytes=12GB;filesystem='exFAT';drive=$drive;formatTarget='Only the partition returned for this freshly created image';physicalDisksModified=$false}|ConvertTo-Json -Compress;return}
if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'This disposable-volume helper requires explicit Administrator confirmation; no automatic elevation'}
if(-not (Test-Path -LiteralPath $Job -PathType Container)){throw 'Prepared job missing'}
if(Test-Path -LiteralPath $image){throw 'Fresh image required; existing files are never reused or formatted'}
if((Test-Path -LiteralPath $drive) -or (Get-PSDrive Z -ErrorAction SilentlyContinue) -or (Get-Volume -DriveLetter Z -ErrorAction SilentlyContinue)){throw 'Z: is already in use'}
$attached=$false;$finished=$false;$readyPublished=$false
try{
    State 'creating'
    # Diskpart is used ONLY to create a new file. No select disk/clean/format commands.
    $create=Join-Path $Job 'create.txt'
    ('create vdisk file="'+$image+'" maximum=12288 type=expandable')|Set-Content -LiteralPath $create -Encoding ASCII
    & "$env:SystemRoot\System32\diskpart.exe" /s $create | Out-File -LiteralPath (Join-Path $Job 'create.log') -Encoding UTF8
    if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $image -PathType Leaf)){throw 'New VHDX creation failed'}
    $createdTicks=(Get-Item -LiteralPath $image).CreationTimeUtc.Ticks
    Assert-ExfatJob $Job $Nonce
    if((Get-Item -LiteralPath $image -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse image refused'}
    Mount-DiskImage -ImagePath $image -NoDriveLetter -Access ReadWrite | Out-Null
    $attached=$true
    $img=Get-DiskImage -ImagePath $image
    if(-not $img.Attached -or [IO.Path]::GetFullPath($img.ImagePath) -ine $image){throw 'Image association mismatch'}
    $disk=@($img|Get-Disk);Assert-ExfatDisk $disk 'RAW';$number=$disk[0].Number
    # Every mutating disk operation is bound to the image-derived object, never an input disk number.
    Initialize-Disk -InputObject $disk[0] -PartitionStyle GPT | Out-Null
    $disk=@((Get-DiskImage -ImagePath $image)|Get-Disk);Assert-ExfatDisk $disk 'GPT'
    if($disk[0].Number -ne $number){throw 'Image disk changed before partition creation'}
    $partition=New-Partition -InputObject $disk[0] -UseMaximumSize -DriveLetter Z
    $disk=@((Get-DiskImage -ImagePath $image)|Get-Disk);Assert-ExfatDisk $disk 'GPT'
    if($disk[0].Number -ne $number -or $partition.DiskNumber -ne $number){throw 'Partition/image association changed before format'}
    Format-Volume -Partition $partition -FileSystem exFAT -NewFileSystemLabel ('GEX'+$Nonce.Substring(0,6)) -Confirm:$false | Out-Null
    if(([IO.DriveInfo]::new($drive)).DriveFormat -ine 'exFAT'){throw 'Formatted filesystem did not verify'}
    @{schema=1;nonce=$Nonce;kind='owned-disposable-exfat-test';image=$image}|ConvertTo-Json -Compress|Set-Content -LiteralPath ($drive+'ghostty-test-volume.json') -Encoding UTF8
    $readyPublished=$true
    State 'ready'
    $until=[DateTime]::UtcNow.AddMinutes(45)
    while([DateTime]::UtcNow -lt $until){
        $done=Join-Path $Job 'done.json'
        if(Test-Path -LiteralPath $done){
            $ack=Get-Content -LiteralPath $done -Raw|ConvertFrom-Json
            if($ack.nonce -cne $Nonce -or $ack.guestStopped -isnot [bool] -or -not $ack.guestStopped){throw 'Invalid cleanup acknowledgement'}
            # This is the sole guest executable allowed by the sandbox acquisition/policy.
            # A failed query or any unknown executable path must not imply no guest.
            $live=@(Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64.exe'")
            Assert-NoExfatGuest $live $drive
            Dismount-DiskImage -ImagePath $image
            $attached=$false
            if((Get-DiskImage -ImagePath $image).Attached){throw 'Image still attached'}
            Assert-ExfatJob $Job $Nonce
            if((Get-Item -LiteralPath $image).CreationTimeUtc.Ticks -ne $createdTicks){throw 'Test image changed; refusing deletion'}
            if((Get-Item -LiteralPath $image -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse cleanup image refused'}
            Remove-Item -LiteralPath $image
            $finished=$true;State 'cleaned';break
        }
        Start-Sleep -Seconds 1
    }
    if(-not $finished){State 'lease-expired' 'No automatic forced detach: inspect owned test processes before cleanup.'}
}catch{
    # Before ready there can be no coordinator guest. Do not detach a live test after ready.
    if($attached -and (Test-ExfatSetupCleanup $readyPublished)){try{Dismount-DiskImage -ImagePath $image;$attached=$false}catch{}}
    State 'failed' $_.Exception.Message
    exit 1
}
