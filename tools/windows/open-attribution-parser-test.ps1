# Offline AST extraction only; never execute the controller body.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$file=Join-Path $PSScriptRoot 'native-open-attribution.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($name in @('Convert-CdbProtocolLine','New-OpenCondition','Test-OpenReturn','Test-NativeResourceExit')){
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if($null -eq $fn){throw 'Missing parser function'};. ([scriptblock]::Create($fn.Extent.Text))
}
if((Convert-CdbProtocolLine '0:000> 0:001> LO_RETURN tid=1 ip=2 sp=3 value=4 symbol') -cne 'LO_RETURN tid=1 ip=2 sp=3 value=4 symbol'){throw 'Consecutive prompt regression'}
if((Convert-CdbProtocolLine '0:000> .echo LO_FINAL') -cne '.echo LO_FINAL'){throw 'Command echo incorrectly accepted'}
if((New-OpenCondition 'DuplicateHandle' '0x1000' '0x2000') -cne '((poi(@rsp) >= 0x1000) and (poi(@rsp) < 0x2000)) and (@rdx == 0xfffffffffffffffe)'){throw 'MASM caller/source filter regression'}
if((New-OpenCondition 'CreateThread' '0x1000' '0x2000') -cne '(@r8 >= 0x1000) and (@r8 < 0x2000)'){throw 'Start address filter regression'}
$entry=@{tid=[UInt64]1;return_address=[UInt64]32;entry_sp=[UInt64]64}
if(-not (Test-OpenReturn $entry 1 32 72)){throw 'Valid return rejected'}
foreach($case in @(@(2,32,72),@(1,33,72),@(1,32,64))){if(Test-OpenReturn $entry $case[0] $case[1] $case[2]){throw 'Unverified return accepted'}}
$text=[IO.File]::ReadAllText($file)
if(-not (Test-NativeResourceExit 'native' 1 "error: ResourceGrowth`r`n")){throw 'Expected native resource failure rejected'}
foreach($case in @(@('control',1,'error: ResourceGrowth'),@('native',2,'error: ResourceGrowth'),@('native',1,''),@('native',1,'error: SomethingElse'),@('native',1,"error: ResourceGrowth`npanic: broken"),@('native',1,'prefix error: ResourceGrowth'),@('native',1,"error: ResourceGrowth`nerror(conpty): unexpected"))){
    if(Test-NativeResourceExit $case[0] $case[1] $case[2]){throw 'Unexpected application exit accepted'}
}
if($text -notmatch "'KERNEL32'\}else\{'KERNELBASE'" -or [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'open-attribution-control.c')) -match 'GetProcAddress'){throw 'Ordinary public CreateThread route regression'}
if($text -notmatch '\$line=Convert-CdbProtocolLine \$line' -or $text -match '(?m)^\s*Send .*(~.*gu|\|\|)'){throw 'Actual reader/plain-gu wiring regression'}
Write-Output 'PASS offline parser/filter/return validation; no processes/windows launched'
