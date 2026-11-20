param([Parameter(Mandatory=$true)][string]$PackageDirectory)
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$package=(Resolve-Path -LiteralPath $PackageDirectory).ProviderPath
if(-not $package.StartsWith((Join-Path $workspace 'zig-out')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Owned package fixture required'}
$data=Join-Path $package 'bin\portable-data'
$test=Join-Path $workspace ('zig-out\quoted-shim-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($test)
[IO.File]::WriteAllText((Join-Path $test 'node.cmd'),"@echo HOST_CWD_POISON`r`n@exit /b 91`r`n",[Text.ASCIIEncoding]::new())
# npm's generated CMD shims invoke quoted bare "node" without CALL. That is
# deliberately different from direct-absolute or unquoted-bare wrapper tests.
$caller=Join-Path $test 'npm-style-caller.cmd'
[IO.File]::WriteAllText($caller,"@echo off`r`n`"node`" --version`r`nexit /b %ERRORLEVEL%`r`n",[Text.ASCIIEncoding]::new())
$names=@('PATH','NoDefaultCurrentDirectoryInExePath')
$saved=@{};$cwd=Get-Location
try{
    foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    $env:PATH=(Join-Path $data 'shims')+';'+(Join-Path $data 'runtimes\node')+';'+$env:SystemRoot+'\System32'
    $env:NoDefaultCurrentDirectoryInExePath='1'
    Set-Location -LiteralPath $test
    $result=& $caller
    $code=$LASTEXITCODE
    [ordered]@{output=$result;exit=$code;quoted_bare=$true;cwd_poison=$true;package=$package}|ConvertTo-Json|Set-Content (Join-Path $test 'result.json') -Encoding UTF8
    if($code -ne 0 -or $result -ne 'v24.22.1'){throw "Quoted-bare npm-style Node shim failed: exit=$code"}
    Write-Output "PASS quoted-bare npm-style shim ignores cwd poison and derives actual private runtime: $test"
}finally{
    Set-Location $cwd
    foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
}
