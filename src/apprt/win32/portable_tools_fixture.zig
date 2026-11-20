//! Owned offscreen-only proof. No provider/auth calls, user history or input.
pub const command =
    \\$ErrorActionPreference='Stop'
    \\$root=$env:LOCALTERM_PORTABLE_DATA
    \\$id=[guid]::NewGuid().ToString('N')
    \\$base=Join-Path $root ('tmp\fixture-'+$id)
    \\$null=[IO.Directory]::CreateDirectory($base)
    \\$proof=Join-Path $root ('data\devtools-proof-'+$id+'.json')
    \\$script=Join-Path $base 'proof.cjs'
    \\$js=@'
    \\const fs=require('fs'),path=require('path'),os=require('os'),assert=require('assert');
    \\const root=process.env.LOCALTERM_PORTABLE_DATA;
    \\const inside=p=>{const r=path.relative(root,p);return !r.startsWith('..')&&!path.isAbsolute(r)};
    \\const keys=['HOME','USERPROFILE','APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR','NPM_CONFIG_PREFIX','NPM_CONFIG_CACHE','NPM_CONFIG_USERCONFIG','NPM_CONFIG_GLOBALCONFIG','LETTA_HOME','LETTA_LOCAL_BACKEND_DIR'];
    \\for(const key of keys)assert(inside(process.env[key]),key+' escaped owned root');
    \\assert(inside(process.execPath));assert(inside(os.homedir()));assert(inside(os.tmpdir()));
    \\for(const key of ['NODE_OPTIONS','NODE_PATH','LETTA_API_KEY','OPENAI_API_KEY','NPM_CONFIG_REGISTRY'])assert.strictEqual(process.env[key],undefined,key+' inherited');
    \\fs.writeFileSync(process.argv[2],JSON.stringify({execPath:process.execPath,version:process.version,home:os.homedir(),tmp:os.tmpdir(),paths:Object.fromEntries(keys.map(k=>[k,process.env[k]])),args:process.argv.slice(3),sanitized:true},null,2));
    \\'@
    \\[IO.File]::WriteAllText($script,$js,[Text.UTF8Encoding]::new($false))
    \\[IO.File]::WriteAllText((Join-Path $base 'node.cmd'),"@echo HOST_NODE_POISON`r`n@exit /b 91`r`n",[Text.ASCIIEncoding]::new())
    \\Push-Location -LiteralPath $base
    \\try {
    \\  node $script $proof 'with space' 'ไทย';if($LASTEXITCODE -ne 0){throw 'Node environment proof failed'}
    \\  $report=[IO.File]::ReadAllText($proof)|ConvertFrom-Json
    \\  if($report.args.Count -ne 2 -or $report.args[0] -ne 'with space' -or $report.args[1] -ne 'ไทย'){throw 'Native argument roundtrip failed'}
    \\  $prefix=[string](npm prefix -g);if($LASTEXITCODE -ne 0 -or $prefix.Trim() -ne $env:NPM_CONFIG_PREFIX){throw 'npm global prefix escaped'}
    \\  $cache=[string](npm config get cache);if($LASTEXITCODE -ne 0 -or $cache.Trim() -ne $env:NPM_CONFIG_CACHE){throw 'npm cache escaped'}
    \\  $fixture=Join-Path $base 'package';$null=[IO.Directory]::CreateDirectory($fixture)
    \\  $pkg=@{name='localterm-private-fixture';version='1.0.0';bin=@{'portable-fixture'='bin.cjs'};scripts=@{preinstall='node -e "process.exit(53)"'}}|ConvertTo-Json -Depth 5
    \\  [IO.File]::WriteAllText((Join-Path $fixture 'package.json'),$pkg,[Text.UTF8Encoding]::new($false))
    \\  $bin=@'
    \\#!/usr/bin/env node
    \\const fs=require('fs');fs.writeFileSync(process.argv[2],JSON.stringify({execPath:process.execPath,args:process.argv.slice(3)}));
    \\'@
    \\  [IO.File]::WriteAllText((Join-Path $fixture 'bin.cjs'),$bin,[Text.UTF8Encoding]::new($false))
    \\  Push-Location -LiteralPath $fixture
    \\  try {$packed=npm pack --ignore-scripts --offline --json --no-audit --no-fund;if($LASTEXITCODE -ne 0){throw 'Offline npm pack failed'};$tar=Join-Path $fixture (($packed -join "`n"|ConvertFrom-Json)[0].filename)} finally {Pop-Location}
    \\  npm install -g $tar --ignore-scripts --offline --no-audit --no-fund;if($LASTEXITCODE -ne 0){throw 'Offline global fixture install failed'}
    \\  $binProof=Join-Path $base 'bin-proof.json'
    \\  & (Join-Path $env:NPM_CONFIG_PREFIX 'portable-fixture.cmd') $binProof 'with space' 'ไทย';if($LASTEXITCODE -ne 0){throw 'npm shim selected cwd poison or wrong Node'}
    \\  $b=[IO.File]::ReadAllText($binProof)|ConvertFrom-Json
    \\  if($b.execPath -ne $report.execPath -or $b.args[0] -ne 'with space' -or $b.args[1] -ne 'ไทย'){throw 'Installed CLI runtime/argument mismatch'}
    \\  if(-not [IO.File]::Exists((Join-Path $env:NPM_CONFIG_PREFIX 'node_modules\@letta-ai\letta-code\letta.js'))){$missing=$false;try {letta --version} catch {$missing=$true};if(-not $missing){throw 'Missing Letta silently selected host CLI'}}
    \\  $history=(Get-PSReadLineOption).HistorySavePath
    \\  if(-not $history.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or $HOME -ne $env:USERPROFILE){throw 'PowerShell HOME/history escaped'}
    \\  $report|Add-Member -NotePropertyName history -NotePropertyValue $history
    \\  $report|Add-Member -NotePropertyName npm_install -NotePropertyValue 'offline-private-global-prefix-ignore-scripts'
    \\  $report|Add-Member -NotePropertyName installed_bin_runtime -NotePropertyValue $b.execPath
    \\  [IO.File]::WriteAllText($proof,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    \\} finally {Pop-Location}
    \\$e=[string][char]27
    \\[Console]::Write($e+']0;PORTABLE_TOOLS_FIXTURE_OK'+[char]7)
    \\[Console]::WriteLine('LOCALTERM_RENDER_SMOKE')
    \\[Console]::WriteLine($e+'[31mRED'+$e+'[0m ไทย')
    \\[Threading.Thread]::Sleep(1000)
    \\exit 0
;
