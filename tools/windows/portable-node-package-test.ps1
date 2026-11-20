param([Parameter(Mandatory=$true)][string]$NodeSource, [string]$StructuralSource)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$node=(Resolve-Path -LiteralPath $NodeSource).ProviderPath
if (-not $node.StartsWith((Join-Path $workspace 'zig-out')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Private staged Node required.' }
$root=Join-Path $workspace ('zig-out\node-fixture-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root)
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'package-portable.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach($name in @('Get-SafeTree','Test-FileManifest','Read-Provenance')) {
    $fn=$ast.Find({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
$tiny=Join-Path $root 'manifest-fixture'
$null=[IO.Directory]::CreateDirectory($tiny)
[IO.File]::WriteAllText((Join-Path $tiny 'present.txt'),'fixture')
$hash=(Get-FileHash -LiteralPath (Join-Path $tiny 'present.txt')).Hash
$good=[pscustomobject]@{'present.txt'=$hash}
Test-FileManifest $tiny $good 'provenance.json'
foreach($case in @(
    @{name='missing-listed';files=[pscustomobject]@{'present.txt'=$hash;'missing.txt'=$hash}},
    @{name='bad-digest';files=[pscustomobject]@{'present.txt'=('0'*64)}},
    @{name='unlisted';files=[pscustomobject]@{}},
    @{name='traversal';files=[pscustomobject]@{'../present.txt'=$hash}}
)) {
    $rejected=$false
    try { Test-FileManifest $tiny $case.files 'provenance.json' } catch { $rejected=$true }
    if(-not $rejected) { throw "Negative fixture accepted: $($case.name)" }
    "PASS $($case.name) rejection"
}
$rejected=$false
try { & (Join-Path $PSScriptRoot 'package-portable.ps1') -SourcePrefix $root -OutputDirectory $tiny } catch { if($_ -notmatch 'Output already exists') { throw }; $rejected=$true }
if(-not $rejected) { throw 'Output overwrite accepted.' }
'PASS package output-exists rejection'
$dupe=Join-Path $root 'duplicate.json'
foreach($json in @('{"files":{"a":"x","a":"y"}}','{"files":{"a":"x","A":"y"}}')) {
    [IO.File]::WriteAllText($dupe,$json)
    $rejected=$false
    try { $null=Read-Provenance $dupe } catch { $rejected=$true }
    if(-not $rejected) { throw 'Duplicate provenance JSON accepted.' }
}
'PASS exact/case-folded duplicate provenance rejection'
if ($StructuralSource) {
    $structural=(Resolve-Path -LiteralPath $StructuralSource).ProviderPath.TrimEnd('\')
    if (-not $structural.StartsWith((Join-Path $workspace 'zig-out')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Private structural source required.' }
    $null=@(Get-SafeTree $structural)
    $copy=Join-Path $root 'structural-source'
    Copy-Item -LiteralPath $structural -Destination $copy -Recurse
    # Older source fixture omitted the nuspec; use the same bundled provider evidence, never fabricate it.
    if (-not (Test-Path -LiteralPath (Join-Path $copy 'bin\ConPTY-package.nuspec'))) {
        Copy-Item -LiteralPath (Join-Path $workspace 'zig-out\portable-dev\bin\ConPTY-package.nuspec') -Destination (Join-Path $copy 'bin\ConPTY-package.nuspec')
    }
    & (Join-Path $PSScriptRoot 'package-portable.ps1') -SourcePrefix $copy -OutputDirectory (Join-Path $root 'package') -PortableTools -NodeSource $node
    foreach($rel in @('bin/portable-data/shims/node.cmd','bin/portable-data/shims/npm.cmd','bin/portable-data/shims/npx.cmd','bin/portable-data/shims/letta.cmd','bin/powershell/PSReadLine/UPSTREAM-LICENSE','bin/portable-data/runtimes/node/provenance.json')) {
        if(-not(Test-Path -LiteralPath (Join-Path $root ('package/'+$rel)))) { throw "Missing package mapping: $rel" }
    }
    'PASS structural package content mapping (old native executable; not launched)'
    $relocated=Join-Path $root ('relocated package '+[char]0x0E44+[char]0x0E17+[char]0x0E22)
    Move-Item -LiteralPath (Join-Path $root 'package') -Destination $relocated
    $packagedData=Join-Path $relocated 'bin\portable-data'
    & (Join-Path $packagedData 'shims\node.cmd') --version
    if($LASTEXITCODE) { throw 'Relocated Node wrapper failed.' }
    $exe=Join-Path $packagedData 'runtimes\node\node.exe'
    Move-Item -LiteralPath $exe -Destination ($exe+'.held')
    try {
        & (Join-Path $packagedData 'shims\node.cmd') --version
        if($LASTEXITCODE -ne 127) { throw 'Missing runtime wrapper did not fail closed.' }
    } finally { Move-Item -LiteralPath ($exe+'.held') -Destination $exe }
    'PASS relocated wrapper and missing runtime rejection'
}
foreach($part in @('home','roaming','local','tmp','cache','prefix','fixture')) { $null=[IO.Directory]::CreateDirectory((Join-Path $root $part)) }
$saved=@{}
$values=@{HOME='home';USERPROFILE='home';APPDATA='roaming';LOCALAPPDATA='local';TEMP='tmp';TMP='tmp';TMPDIR='tmp';NPM_CONFIG_PREFIX='prefix';NPM_CONFIG_CACHE='cache';NPM_CONFIG_USERCONFIG='user.npmrc';NPM_CONFIG_GLOBALCONFIG='global.npmrc'}
foreach($cfg in @('user.npmrc','global.npmrc')) { [IO.File]::WriteAllText((Join-Path $root $cfg),'') }
[IO.File]::WriteAllText((Join-Path $root 'fixture\package.json'),'{"name":"portable-local-fixture","version":"1.0.0","scripts":{"preinstall":"node -e \"process.exit(99)\""},"bin":{"portable-fixture":"cli.js"}}')
[IO.File]::WriteAllText((Join-Path $root 'fixture\cli.js'),"#!/usr/bin/env node`nconsole.log('fixture')`n")
try {
    foreach($key in $values.Keys) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process'); [Environment]::SetEnvironmentVariable($key,(Join-Path $root $values[$key]),'Process') }
    if ($StructuralSource) {
        & (Join-Path $packagedData 'shims\npm.cmd') --version
        if($LASTEXITCODE) { throw 'Relocated npm wrapper failed.' }
        & (Join-Path $packagedData 'shims\letta.cmd') --version
        if($LASTEXITCODE -ne 127) { throw 'Absent Letta wrapper did not fail closed.' }
    }
    & (Join-Path $node 'node.exe') (Join-Path $node 'node_modules\npm\bin\npm-cli.js') install --global --prefix (Join-Path $root 'prefix') (Join-Path $root 'fixture') --ignore-scripts --no-audit --no-fund --offline
    if($LASTEXITCODE -ne 0) { throw "npm fixture failed: $LASTEXITCODE" }
    if(-not(Test-Path -LiteralPath (Join-Path $root 'prefix\portable-fixture.cmd'))) { throw 'Missing fixture shim.' }
    'PASS local offline npm fixture, lifecycle hooks disabled'
    if ($StructuralSource) { & (Join-Path $PSScriptRoot 'portable-quoted-shim-test.ps1') -PackageDirectory $relocated }
    "FIXTURE_ROOT=$root"
} finally { foreach($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') } }
