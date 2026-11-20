# Build-only helpers. Copy explicit program trees, never a used portable profile.
function Assert-HerdrProgramInput([string]$Root, [string]$Relative) {
    $path=[IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if(-not$path.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Program input escaped its declared root.'}
    for($p=$path;$p;$p=[IO.Path]::GetDirectoryName($p)){
        if((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Program input reparse point refused.'}
    }
    return $path
}

function Test-HerdrReadyProgramSource([string]$Root) {
    $rootPath=(Resolve-Path -LiteralPath $Root -ErrorAction Stop).ProviderPath.TrimEnd('\')
    $catalog=Assert-HerdrProgramInput $rootPath 'package-manifest.json'
    $m=Get-Content -LiteralPath $catalog -Raw|ConvertFrom-Json
    $entry=Assert-HerdrProgramInput $rootPath 'bin/portable-data/npm/node_modules/@letta-ai/letta-code/letta.js'
    $pkg=Get-Content -LiteralPath (Assert-HerdrProgramInput $rootPath 'bin/portable-data/npm/node_modules/@letta-ai/letta-code/package.json') -Raw|ConvertFrom-Json
    if($pkg.name -cne '@letta-ai/letta-code' -or $pkg.version -cne '0.34.23' -or
        $m.prepared_Letta.version -cne $pkg.version -or $m.prepared_Letta.existing_accounts_migrated -ne $false -or
        (Get-FileHash -LiteralPath $entry).Hash -ine $m.prepared_Letta.entry_sha256){throw 'Ready Letta public entry/provenance mismatch.'}
    foreach($rel in @('bin/portable-data/npm/node_modules','bin/portable-data/runtimes/git','bin/portable-data/apps/herdr/0.9.5')){
        $path=Assert-HerdrProgramInput $rootPath $rel
        # Walk just these public programs. A private HOME/profile is never read.
        $null=@(Get-SafeTree $path)
    }
    foreach($rel in @('bin/portable-data/shims/git.exe','bin/portable-data/shims/git.proxy.json')){
        $path=Assert-HerdrProgramInput $rootPath $rel
        $identity=@($m.files|Where-Object{$_.path -ceq $rel})
        if($identity.Count -ne 1 -or (Get-FileHash -LiteralPath $path).Hash -ine $identity[0].sha256){throw 'Ready Git proxy identity mismatch.'}
    }
    return $rootPath
}

function Initialize-HerdrReadyProfile($Layout) {
    if(Test-Path -LiteralPath (Join-Path $Layout.Profile 'home/.letta/local/memfs')){throw 'Ready profile initialization is build-only; refusing an already used agent profile.'}
    $config=Join-Path $Layout.Profile 'config/herdr/config.toml'
    $text=[IO.File]::ReadAllText($config)
    if($text -match '(?m)^\[(update|session)\]'){throw 'Ready defaults require the freshly generated shell config, not existing user preferences.'}
    # Restore the private shell/workspaces, not a persisted host agent command.
    # Starting an AI remains an explicit `letta --new` action in the ready pane.
    [IO.File]::AppendAllText($config,"`r`n[update]`r`nversion_check = false`r`nmanifest_check = false`r`n[session]`r`nresume_agents_on_restore = false`r`n",[Text.UTF8Encoding]::new($false))
    & (Join-Path $Layout.Data 'runtimes/node/node.exe') (Join-Path $Layout.Data 'npm/node_modules/@letta-ai/letta-code/letta.js') backend local | Out-Host
    if($LASTEXITCODE -ne 0){throw 'Fresh Letta local-backend default could not be prepared.'}
    foreach($privateHome in @((Join-Path $Layout.Data 'home'),(Join-Path $Layout.Profile 'home'))){
        & (Join-Path $Layout.Data 'runtimes/git/cmd/git.exe') config --file (Join-Path $privateHome '.gitconfig') core.longpaths true
        if($LASTEXITCODE -ne 0){throw 'Fresh private Git long-path setup failed.'}
    }
}

function Copy-HerdrReadyPrograms([string]$InputRoot,[string]$OutputRoot,[string]$ScriptsRoot) {
    & (Join-Path $OutputRoot 'bin/portable-data/runtimes/node/node.exe') (Join-Path $ScriptsRoot 'herdr-build-files.cjs') copy-ready $InputRoot $OutputRoot | Out-Host
    if($LASTEXITCODE -ne 0){throw 'Long-path-safe public program copy failed.'}
    . (Join-Path $ScriptsRoot 'install-portable-git.ps1')
    Invoke-PortableGitInstall $OutputRoot
    . (Join-Path $ScriptsRoot 'herdr-portable.ps1')
    $layout=Get-HerdrPortableLayout $OutputRoot
    $null=Install-HerdrPortablePayload $layout
    Set-HerdrPrivateEnvironment $layout
    Set-HerdrPrivateShell $layout
    Initialize-HerdrReadyProfile $layout
    return [ordered]@{schema=1;name='@letta-ai/letta-code';version='0.34.23';entry='bin/portable-data/npm/node_modules/@letta-ai/letta-code/letta.js';entry_sha256=(Get-FileHash (Join-Path $OutputRoot 'bin/portable-data/npm/node_modules/@letta-ai/letta-code/letta.js')).Hash;existing_accounts_migrated=$false;dependency_lifecycle_scripts_run=$false;public_program_trees_only=$true;provider_chat_verified=$false}
}
