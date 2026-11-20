$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'exfat-vhd-guards.ps1')
function Refuses([scriptblock]$Action){$failed=$false;try{& $Action}catch{$failed=$true};if(-not $failed){throw 'Unsafe test input was accepted'}}
$nonce='a'*32;$job='D:\works\ghostty-windows\zig-out\exfat-vhd-test-'+$nonce
Assert-ExfatJob $job $nonce
Refuses {Assert-ExfatJob 'A:\' $nonce}
Refuses {Assert-ExfatJob ($job+'\..\outside') $nonce}
Refuses {Assert-ExfatJob $job ('b'*32)}
$base=@{Number=12;IsBoot=$false;IsSystem=$false;BusType='File Backed Virtual';Size=12GB;PartitionStyle='RAW'}
Assert-ExfatDisk ([pscustomobject]$base) 'RAW'
foreach($entry in @(@('IsBoot',$true),@('IsSystem',$true),@('BusType','SATA'),@('Size',1GB),@('PartitionStyle','GPT'),@('Number',$null),@('IsBoot',$null))){
    $bad=$base.Clone();$bad[$entry[0]]=$entry[1];Refuses {Assert-ExfatDisk ([pscustomobject]$bad) 'RAW'}
}
Refuses {Assert-ExfatDisk @([pscustomobject]$base,[pscustomobject]$base) 'RAW'}
Assert-NoExfatGuest @() 'Z:\'
Assert-NoExfatGuest @([pscustomobject]@{ExecutablePath='D:\known-other-test\qemu-system-x86_64.exe'}) 'Z:\'
Refuses {Assert-NoExfatGuest @([pscustomobject]@{ExecutablePath=$null}) 'Z:\'}
Refuses {Assert-NoExfatGuest @([pscustomobject]@{ExecutablePath='Z:\owned-test\qemu-system-x86_64.exe'}) 'Z:\'}
# Readiness is worker memory, not the continued existence of a mutable marker.
if(Test-ExfatSetupCleanup $true){throw 'Post-ready exception may detach a guest'}
if(-not (Test-ExfatSetupCleanup $false)){throw 'Pre-ready owned setup cleanup was disabled'}
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'exfat-vhd-worker.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
'{"passed":true,"guardNegativeCases":13,"cleanupReadinessCases":2,"diskCommandsExecuted":false}'
