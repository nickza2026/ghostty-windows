function Assert-ExfatJob([string]$Job,[string]$Nonce){
    if($Nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'Invalid test nonce'}
    $expected='D:\works\ghostty-windows\zig-out\exfat-vhd-test-'+$Nonce
    if([IO.Path]::GetFullPath($Job).TrimEnd('\') -ine $expected){throw 'Test job escaped its fixed D: workspace'}
    for($p=$expected;$p;$p=[IO.Path]::GetDirectoryName($p)){
        if((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Reparse test job refused'}
    }
}
function Assert-ExfatDisk($Disk,[string]$Style){
    if(@($Disk).Count -ne 1 -or $null -eq $Disk){throw 'No unique disk associated with the new image'}
    if($Disk.IsBoot -ne $false -or $Disk.IsSystem -ne $false){throw 'Boot/system or unknown disk refused'}
    if([string]$Disk.BusType -notin @('File Backed Virtual','FileBackedVirtual')){throw 'Not a file-backed virtual disk'}
    if([uint64]$Disk.Size -ne 12GB -or [string]$Disk.PartitionStyle -ne $Style){throw 'Unexpected image size/partition style'}
    if($null -eq $Disk.Number -or [int64]$Disk.Number -lt 0){throw 'Invalid associated disk number'}
}
function Assert-NoExfatGuest($Processes,[string]$Drive){
    foreach($process in $Processes){
        if(-not $process.ExecutablePath){throw 'Unknown QEMU executable path; refusing detach'}
        if($process.ExecutablePath.StartsWith($Drive,[StringComparison]::OrdinalIgnoreCase)){throw 'Owned volume still has QEMU running; refusing detach'}
    }
}
function Test-ExfatSetupCleanup([bool]$ReadyPublished){return -not $ReadyPublished}
