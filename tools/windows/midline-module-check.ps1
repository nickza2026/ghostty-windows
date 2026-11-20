# Same-binary, fresh-process old/new/old PSReadLine integration comparison.
param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$OriginalModule,
    [Parameter(Mandatory=$true)][string]$PatchedModule,
    [ValidateSet('system','app-local')][string[]]$Providers=@('system','app-local')
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($Providers.Count -eq 0 -or @($Providers | Select-Object -Unique).Count -ne $Providers.Count) { throw 'At least one unique provider is required.' }
$Executable=(Resolve-Path -LiteralPath $Executable).ProviderPath
$OriginalModule=(Resolve-Path -LiteralPath $OriginalModule).ProviderPath
$PatchedModule=(Resolve-Path -LiteralPath $PatchedModule).ProviderPath
$binaryHash=(Get-FileHash -LiteralPath $Executable).Hash
$logs=Join-Path $env:LOCALAPPDATA 'Letta\build-logs\ghostty-windows\phase3b-runtime'
$out=Join-Path $env:LOCALAPPDATA ('Letta\build-logs\ghostty-windows\thai-midline\module-ab-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$null=[IO.Directory]::CreateDirectory($out)
$results=@()
$sequence=@('original','patched','original','patched')
foreach($provider in $Providers){
    foreach($variant in $sequence){
        $manifest=if($variant -eq 'original'){$OriginalModule}else{$PatchedModule}
        $assemblies=@(Get-ChildItem -LiteralPath (Split-Path -Parent $manifest) -File -Recurse -Filter 'Microsoft.PowerShell.PSReadLine*.dll')
        if($assemblies.Count -ne 1){throw 'Expected exactly one app-owned PSReadLine implementation'}
        $assemblyHash=(Get-FileHash -LiteralPath $assemblies[0].FullName).Hash
        $since=Get-Date
        $failure=$null
        try{ & (Join-Path $PSScriptRoot 'runtime-smoke.ps1') -Mode terminal -MidlineSmoke -MidlineModule $manifest -ConptyProvider $provider -TimeoutSeconds 45 -Executable $Executable }
        catch{ $failure=$_.Exception.Message }
        $rows=@(Get-Content (Join-Path $logs 'results.jsonl') -Encoding UTF8 | ForEach-Object{$_|ConvertFrom-Json} | Where-Object{ $_.PSObject.Properties['executable'] -and $_.PSObject.Properties['conpty_provider_diagnostic'] -and $_.executable -eq $Executable -and $_.conpty_provider_diagnostic -eq $provider -and [DateTime]::Parse($_.started) -ge $since })
        if($rows.Count -ne 1){throw 'Missing or ambiguous current owned supervisor receipt'}
        $r=$rows[0]
        $text=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($r.stderr)).Replace([string][char]0,'')
        $ascii=[regex]::Match($text,'MIDLINE_EDIT case=ascii[^\r\n]+').Value
        $thai=[regex]::Match($text,'MIDLINE_EDIT case=thai[^\r\n]+').Value
        $loaded=[regex]::Match($text,'MIDLINE_MODULE loaded_version=([^ ]+) assembly_sha256=([0-9A-Fa-f]{64})')
        $complete=$loaded.Success -and $loaded.Groups[2].Value -eq $assemblyHash -and $ascii -match 'buffer_ok=true logical_cursor=47 console_x=51 actual_x=51 expected_x=51 cell_differences=0 passed=true' -and -not $r.timed_out -and $r.cleaned_descendants.Count -eq 0 -and $r.midline_edit_diagnostic -and -not $r.readiness_evidence -and $r.midline_module_manifest -eq $manifest -and $r.sha256 -eq $binaryHash
        $qualified=if($variant -eq 'original'){
            $complete -and $r.exit_code -eq 1 -and -not $r.passed -and $null -ne $failure -and $thai -match 'buffer_ok=true logical_cursor=48 console_x=52 actual_x=52 expected_x=49 cell_differences=0 passed=false' -and $text -match 'MidlineCursorOrCellMismatch'
        }else{
            $complete -and $r.exit_code -eq 0 -and $r.passed -and $null -eq $failure -and $thai -match 'buffer_ok=true logical_cursor=48 console_x=49 actual_x=49 expected_x=49 cell_differences=0 passed=true'
        }
        $entry=[ordered]@{provider=$provider;variant=$variant;name=$r.name;manifest=$manifest;manifest_sha256=(Get-FileHash -LiteralPath $manifest).Hash;expected_assembly_sha256=$assemblyHash;loaded_version=$loaded.Groups[1].Value;ascii=$ascii;thai=$thai;native_exit=$r.exit_code;qualified=$qualified;failure=$failure;stderr=$r.stderr}
        $results+=$entry
        $results|ConvertTo-Json -Depth 6|Set-Content (Join-Path $out 'results.json') -Encoding UTF8
        if(-not $qualified){throw ('Module A/B did not meet exact expected original-red/patched-green conditions: '+$r.name+'; '+$out)}
        if((Get-FileHash -LiteralPath $Executable).Hash -ne $binaryHash -or (Get-FileHash -LiteralPath $assemblies[0].FullName).Hash -ne $assemblyHash){throw 'Inputs changed during module comparison'}
    }
}
if ($results.Count -ne $Providers.Count * $sequence.Count) { throw 'Incomplete module comparison matrix.' }
Write-Output ('PASS MODULE_AB original-red/patched-green/original-red/patched-green; fresh processes; exact buffer/cells/console+terminal caret; '+$out)
