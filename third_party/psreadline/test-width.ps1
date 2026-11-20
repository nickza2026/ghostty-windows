param([Parameter(Mandatory=$true)][string]$Manifest,
      [Parameter(Mandatory=$true)][ValidateSet('original','patched')][string]$Variant)
$ErrorActionPreference = 'Stop'
# Run only in a fresh -NoProfile -NonInteractive Windows PowerShell process.
if (Get-Module PSReadLine) { throw 'PSReadLine already loaded; use a fresh process' }
Import-Module Microsoft.PowerShell.Management
Import-Module Microsoft.PowerShell.Utility
$PSModuleAutoLoadingPreference = 'None'
Import-Module -Name $Manifest -ErrorAction Stop
Set-PSReadLineOption -HistorySaveStyle SaveNothing -HistorySavePath (Join-Path (Split-Path $Manifest) 'private-test-history.txt')
$t = [Microsoft.PowerShell.PSConsoleReadLine]
$m = $t.GetMethod('LengthInBufferCells', [Reflection.BindingFlags]'NonPublic,Static', $null, [type[]]@([char]), $null)
if (!$m) { throw 'Actual compiled width method missing' }
$cases = @(@(0x41,1), @(0x03,2), @(0x4e00,2), @(0x0e01,1), @(0x0e49,0), @(0x0e48,0), @(0x0e31,0), @(0x0301,0), @(0x20dd,0))
foreach ($case in $cases) {
    $expected = $case[1]
    if ($Variant -eq 'original' -and $expected -eq 0) { $expected = 1 }
    $actual = $m.Invoke($null, [object[]]@([char]$case[0]))
    if ($actual -ne $expected) { throw ('U+{0:X4}: expected {1}, got {2}' -f $case[0],$expected,$actual) }
}
$prefix = ([char[]]@(0x0e40,0x0e01,0x0e49,0x0e32,0x20,0x0e40,0x0e01,0x0e48,0x0e07,0x20,0x0e01,0x0e33,0x0e25,0x0e31,0x0e07,0x20)) -join ''
$sum = 0
foreach ($c in $prefix.ToCharArray()) { $sum += $m.Invoke($null,[object[]]@($c)) }
$expectedSum = if ($Variant -eq 'original') {16} else {13}
if ($sum -ne $expectedSum) { throw "Thai prefix width: $sum expected $expectedSum" }
[ordered]@{ variant=$Variant; tests=$cases.Count+1; thaiPrefixCells=$sum; assembly=$t.Assembly.Location; sha256=(Get-FileHash $t.Assembly.Location -Algorithm SHA256).Hash } | ConvertTo-Json
