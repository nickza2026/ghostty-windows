# Offline only: execute our parser function, never the debugger controller body.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$tokens=$null;$errors=$null
$file=Join-Path $PSScriptRoot 'native-close-attribution.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Controller syntax error'}
$fn=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Convert-CdbProtocolLine'},$true)
if($null -eq $fn){throw 'Missing owned parser function'}
. ([scriptblock]::Create($fn.Extent.Text))
$conditionFn=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-CloseCondition'},$true)
if($null -eq $conditionFn){throw 'Missing condition generator'}
. ([scriptblock]::Create($conditionFn.Extent.Text))
if((New-CloseCondition @('0x68','0x228','0xbf4','0xbf8')) -cne '(@rcx == 0x68) or (@rcx == 0x228) or (@rcx == 0xbf4) or (@rcx == 0xbf8)'){throw 'CDB predicate must use MASM or, not unsupported C-style ||'}
$cases=@(
    @('LC_QUERY_END','LC_QUERY_END'),
    @('0:000> LC_QUERY_END','LC_QUERY_END'),
    @('0:000> 0:000> LC_CLOSE_ENTER tid=5c30 handle=000000ac ret=00001234 sp=00005678 Child-SP','LC_CLOSE_ENTER tid=5c30 handle=000000ac ret=00001234 sp=00005678 Child-SP'),
    @('12:00a> LC_FINAL_PAUSED','LC_FINAL_PAUSED'),
    @('0:000> .echo LC_QUERY_END','.echo LC_QUERY_END'),
    @('LC_CLOSE_ENTER tid=123 handle=000000ac ret=00001234 sp=00005678 Child-SP','LC_CLOSE_ENTER tid=123 handle=000000ac ret=00001234 sp=00005678 Child-SP')
)
foreach($case in $cases){$actual=Convert-CdbProtocolLine $case[0];if($actual -cne $case[1]){throw ('Protocol mismatch: input=['+$case[0]+'] actual=['+$actual+'] expected=['+$case[1]+']')}}
$source=[IO.File]::ReadAllText($file)
if($source -notmatch '\$line=Convert-CdbProtocolLine \$line'){throw 'Parser not wired into actual reader'}
Write-Output ('PASS offline protocol cases='+$cases.Count+'; no debugger/process/window launched')
