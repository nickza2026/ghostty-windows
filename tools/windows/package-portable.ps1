param(
    [string]$SourcePrefix = (Join-Path $PSScriptRoot '..\..\zig-out\portable-dev'),
    [string]$OutputDirectory,
    [switch]$OmitInitialData,
    [switch]$PortableTools,
    [string]$NodeSource,
    [string]$ReadyHerdrSource
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowed = (Join-Path $workspace 'zig-out') + '\'
function Get-SafeTree([string]$Root) {
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($Root)
    while ($queue.Count) {
        $dir = $queue.Dequeue()
        if ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse directory refused.' }
        foreach ($item in Get-ChildItem -LiteralPath $dir -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse entry refused.' }
            $item
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) }
        }
    }
}
function Test-FileManifest([string]$Root, $Files, [string]$ProvenanceName) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($identity in $Files.PSObject.Properties) {
        $rel = $identity.Name
        if ($rel -match '(^|/)(\.|\.\.)(/|$)|[:\\]|[ .](/|$)' -or $rel.StartsWith('/') -or $rel.Contains('//') -or -not $seen.Add($rel) -or $identity.Value -notmatch '^[a-fA-F0-9]{64}$') { throw 'Unsafe/duplicate runtime identity.' }
        $file = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-FileHash -LiteralPath $file).Hash -ine $identity.Value) { throw "Missing or modified payload: $rel" }
    }
    foreach ($file in Get-SafeTree $Root) {
        if ($file.PSIsContainer) { continue }
        $rel = $file.FullName.Substring($Root.Length+1).Replace('\','/')
        if ($rel -ne $ProvenanceName -and -not $seen.Contains($rel)) { throw "Untracked payload file: $rel" }
    }
}
function Read-Provenance([string]$Path) {
    $raw = Get-Content -LiteralPath $Path -Raw
    # Flat filename-to-digest object: detect duplicate raw JSON keys before ConvertFrom-Json can collapse them.
    $match = [regex]::Match($raw, '"files"\s*:\s*\{([^{}]*)\}')
    if ($match.Success) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($key in [regex]::Matches($match.Groups[1].Value, '"((?:\\.|[^"\\])*)"\s*:')) {
            $decoded = ('{"key":"' + $key.Groups[1].Value + '"}' | ConvertFrom-Json).key
            if (-not $names.Add($decoded)) { throw 'Duplicate provenance file key.' }
        }
    }
    $raw | ConvertFrom-Json
}
$source = (Resolve-Path -LiteralPath $SourcePrefix).ProviderPath.TrimEnd('\')
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $workspace ('zig-out\portable-packages\localterm-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
}
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
foreach ($path in @($source, $output)) {
    if (-not $path.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Package source/output must stay in workspace zig-out.' }
    for ($p = $path; $p -and $p.Length -ge $workspace.Length; $p = [IO.Path]::GetDirectoryName($p)) {
        if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Refusing package paths through reparse points.' }
    }
}
if (Test-Path -LiteralPath $output) { throw 'Output already exists; never overwrite a package or user data.' }
if($ReadyHerdrSource){
    if(-not$PortableTools){throw 'ReadyHerdrSource requires PortableTools.'}
    $readyInput=[IO.Path]::GetFullPath($ReadyHerdrSource).TrimEnd('\')
    if(-not$readyInput.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Ready public programs must stay in workspace zig-out.'}
    . (Join-Path $PSScriptRoot 'prepare-herdr-programs.ps1')
    $readyInput=Test-HerdrReadyProgramSource $readyInput
}
if ($NodeSource -and -not $PortableTools) { throw 'NodeSource requires PortableTools.' }
if ($PortableTools) {
    if (-not $NodeSource -or $OmitInitialData) { throw 'PortableTools requires NodeSource and initial fresh data assets.' }
    $node = (Resolve-Path -LiteralPath $NodeSource).ProviderPath.TrimEnd('\')
    if (-not $node.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Node source must stay in workspace zig-out.' }
    for ($p = $node; $p -and $p.Length -ge $workspace.Length; $p = [IO.Path]::GetDirectoryName($p)) {
        if ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Node source reparse ancestor refused.' }
    }
    foreach ($item in Get-SafeTree $node) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Node source reparse entry refused.' }
    }
    $np = Read-Provenance (Join-Path $node 'provenance.json')
    $pin = Get-Content -LiteralPath (Join-Path $workspace 'third_party\node\source-pin.json') -Raw | ConvertFrom-Json
    if ($np.schema -ne 1 -or $np.version -cne $pin.version -or $np.archiveSha256 -ine $pin.archiveSha256 -or $np.archiveUrl -cne $pin.archiveUrl -or $np.licenseFile -cne 'LICENSE' -or $np.nodeExe -cne 'node.exe' -or $np.npmCli -cne 'node_modules/npm/bin/npm-cli.js' -or $np.npxCli -cne 'node_modules/npm/bin/npx-cli.js') { throw 'Node provenance does not match pin.' }
    foreach ($required in @('node.exe','node_modules/npm/bin/npm-cli.js','node_modules/npm/bin/npx-cli.js','npm.cmd','npx.cmd','LICENSE')) { if (-not $np.files.PSObject.Properties[$required]) { throw 'Missing runtime identity.' } }
    Test-FileManifest $node $np.files 'provenance.json'
    $readline = Join-Path $source 'bin\powershell\PSReadLine'
    $rp = Read-Provenance (Join-Path $readline 'build-provenance.json')
    $null = @(Get-SafeTree $readline)
    foreach ($entry in @('PSReadLine.psd1','Microsoft.PowerShell.PSReadLine2.dll','PSReadLine.psm1','PSReadLine.format.ps1xml','License.txt','UPSTREAM-LICENSE')) { if (-not (Test-Path -LiteralPath (Join-Path $readline $entry) -PathType Leaf)) { throw "Missing PSReadLine entry: $entry" } }
    if ($rp.PSObject.Properties['files']) { Test-FileManifest $readline $rp.files 'build-provenance.json' }
    if ($rp.variant -cne 'patched' -or (Get-FileHash -LiteralPath (Join-Path $readline 'Microsoft.PowerShell.PSReadLine2.dll')).Hash -ine $rp.assemblySha256 -or (Get-FileHash -LiteralPath (Join-Path $readline 'PSReadLine.psd1')).Hash -ine $rp.manifestSha256) { throw 'Patched PSReadLine identity mismatch.' }
    foreach ($license in @('License.txt','UPSTREAM-LICENSE')) { if (-not (Test-Path -LiteralPath (Join-Path $readline $license))) { throw 'PSReadLine license missing.' } }
}
foreach ($part in @('bin','share')) {
    $dir = Join-Path $source $part
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "Missing install directory: $part" }
    foreach ($item in @(Get-Item -LiteralPath $dir -Force) + @(Get-SafeTree $dir)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing source reparse points.' }
        if ($item.Name -eq 'portable-data') { throw 'Source contains portable data; package only a clean install prefix.' }
    }
}
$required = @('localterm-dev.exe','conpty.dll','OpenConsole.exe','ConPTY-LICENSE.txt','ConPTY-package.nuspec','ConPTY-experiment.json')
foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $source ('bin\'+$name)) -PathType Leaf)) { throw "Missing runtime/package evidence: $name" }
}
foreach ($name in @('conpty.dll','OpenConsole.exe')) {
    $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $source ('bin\'+$name))
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'Microsoft ConPTY signature invalid.' }
}
if (-not (Test-Path -LiteralPath (Join-Path $source 'share\terminfo\ghostty.terminfo') -PathType Leaf)) { throw 'Bundled terminfo sentinel missing.' }
$binFiles = @(Get-ChildItem -LiteralPath (Join-Path $source 'bin') -File | Where-Object {
    $_.Name -in $required -or $_.Extension -eq '.dll' -or $_.Name -eq 'ConPTY-api.h'
})
$unexpectedExe = @(Get-ChildItem -LiteralPath (Join-Path $source 'bin') -File -Filter '*.exe' | Where-Object { $_.Name -notin @('localterm-dev.exe','OpenConsole.exe') })
if ($unexpectedExe.Count -ne 0) { throw 'This default-renderer package refuses extra executables/test or GPU worker artifacts.' }
$null = New-Item -ItemType Directory -Path $output
$null = New-Item -ItemType Directory -Path (Join-Path $output 'bin')
foreach ($file in $binFiles) { [IO.File]::Copy($file.FullName, (Join-Path $output ('bin\'+$file.Name)), $false) }
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $source 'share') -File -Recurse) {
    $relative = $file.FullName.Substring($source.Length + 1)
    $destination = Join-Path $output $relative
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
    [IO.File]::Copy($file.FullName, $destination, $false)
}
[IO.File]::Copy((Join-Path $workspace 'LICENSE'), (Join-Path $output 'GHOSTTY-LICENSE.txt'), $false)
$data = Join-Path $output 'bin\portable-data'
if ($PortableTools) {
    $null = [IO.Directory]::CreateDirectory((Join-Path $output 'bin\powershell'))
    Copy-Item -LiteralPath $readline -Destination (Join-Path $output 'bin\powershell\PSReadLine') -Recurse
    # Optional first-run Herdr setup is explicit: Run.cmd never downloads it.
    # Ship only the launcher/support sources, never a used profile or account data.
    $support = Join-Path $output 'support'
    $null = [IO.Directory]::CreateDirectory($support)
    foreach ($entry in @(
        @('tools\windows\run-herdr-portable.cmd', 'Run-Herdr.cmd'),
        @('tools\windows\herdr-portable.ps1', 'support\herdr-portable.ps1'),
        @('tools\windows\herdr-private-shell.cs', 'support\herdr-private-shell.cs'),
        @('third_party\herdr\source-pin.json', 'support\herdr-source-pin.json'),
        @('tools\windows\install-portable-git.cmd', 'Install-Portable-Git.cmd'),
        @('tools\windows\install-portable-git.ps1', 'support\install-portable-git.ps1'),
        @('tools\windows\portable-git-proxy.cs', 'support\portable-git-proxy.cs'),
        @('third_party\git\source-pin.json', 'support\git-source-pin.json')
    )) {
        [IO.File]::Copy((Join-Path $workspace $entry[0]), (Join-Path $output $entry[1]), $false)
    }
    $null = [IO.Directory]::CreateDirectory((Join-Path $data 'runtimes'))
    Copy-Item -LiteralPath $node -Destination (Join-Path $data 'runtimes\node') -Recurse
    foreach ($part in @('npm','home','home\AppData\Roaming','home\AppData\Local','cache\npm')) { $null = [IO.Directory]::CreateDirectory((Join-Path $data $part)) }
    $shims = Join-Path $data 'shims'
    $null = [IO.Directory]::CreateDirectory($shims)
    foreach ($command in @('node','npm','npx','letta')) {
        $target = switch ($command) {
            'npm' { 'runtimes\node\node_modules\npm\bin\npm-cli.js' }
            'npx' { 'runtimes\node\node_modules\npm\bin\npx-cli.js' }
            'letta' { 'npm\node_modules\@letta-ai\letta-code\letta.js' }
            default { 'runtimes\node\node.exe' }
        }
        $wrapper = @'
@echo off
setlocal DisableDelayedExpansion
set "self=%~f0"
rem Quoted bare names from npm CMD shims make %%~dp0 resolve to cwd.
rem Search the explicit private PATH for our known CMD filename instead.
if /i "%~0"=="COMMAND" for %%S in (COMMAND.cmd) do set "self=%%~$PATH:S"
if not defined self exit /b 127
for %%D in ("%self%") do set "root=%%~dpD.."
for %%D in ("%root%") do set "root=%%~fD"
if not exist "%root%\runtimes\node\node.exe" (
  echo Portable Node is missing. No host fallback. 1>&2
  exit /b 127
)
if not exist "%root%\TARGET" (
  echo Portable COMMAND target is missing. No host fallback. 1>&2
  HINT
  exit /b 127
)
INVOKE
exit /b %ERRORLEVEL%
'@
        $invoke = '"%root%\runtimes\node\node.exe" %*'
        if ($command -ne 'node') { $invoke = '"%root%\runtimes\node\node.exe" "%root%\' + $target + '" %*' }
        $hint = 'rem No machine installation is performed.'
        if ($command -eq 'letta') { $hint = 'echo To install later by choice: "%~dp0npm.cmd" install --global @letta-ai/letta-code 1>&2' }
        $wrapper = $wrapper.Replace('TARGET',$target).Replace('COMMAND',$command).Replace('HINT',$hint).Replace('INVOKE',$invoke)
        [IO.File]::WriteAllText((Join-Path $shims ($command+'.cmd')),($wrapper -replace "`r?`n","`r`n"),[Text.ASCIIEncoding]::new())
    }
}
if (-not $OmitInitialData) {
    foreach ($part in @('config','data','cache','logs','tmp')) { $null = [IO.Directory]::CreateDirectory((Join-Path $data $part)) }
    $profileNote = if ($PortableTools) { '# Isolated tools use a fresh child profile inside portable-data.' } else { '# Child tool accounts are NOT redirected.' }
    [IO.File]::WriteAllText((Join-Path $data 'config\config.ghostty'), ("# Terminal-owned portable config.`r`n"+$profileNote+"`r`n# font-size = 14`r`n"), [Text.UTF8Encoding]::new($false))
}
$launcher = @'
@echo off
setlocal
for /f "tokens=1 delims==" %%v in ('set LOCALTERM_ 2^>nul') do set "%%v="
set "LOCALTERM_TERMINAL=1"
set "LOCALTERM_CONPTY_PROVIDER=app-local"
set "LOCALTERM_CONPTY_EXPERIMENT=1"
"%~dp0bin\localterm-dev.exe" %*
set "code=%ERRORLEVEL%"
if not "%code%"=="0" (
  echo Terminal failed with exit code %code%. No host storage fallback is intended.
  pause
)
exit /b %code%
'@
if ($PortableTools) { $launcher = $launcher.Replace('set "LOCALTERM_TERMINAL=1"', "set `"LOCALTERM_TERMINAL=1`"`r`nset `"LOCALTERM_PORTABLE_TOOLS=1`"`r`nset `"LOCALTERM_APP_READLINE=1`"") }
if ($PortableTools) {
    $gitPreflight=@'
if exist "%~dp0bin\portable-data\shims\git.exe" if exist "%~dp0bin\portable-data\runtimes\git\cmd\git.exe" if exist "%~dp0bin\portable-data\runtimes\git\usr\bin\bash.exe" goto portable_git_ready
call "%~dp0Install-Portable-Git.cmd"
if errorlevel 1 exit /b 1
:portable_git_ready
'@
    $launcher=$launcher.Replace('"%~dp0bin\localterm-dev.exe" %*',$gitPreflight+"`r`n"+'"%~dp0bin\localterm-dev.exe" %*')
}
[IO.File]::WriteAllText((Join-Path $output 'Run.cmd'), ($launcher -replace "`r?`n", "`r`n"), [Text.ASCIIEncoding]::new())
$readme = @'
LOCAL TEST CANDIDATE - not a qualified public release.
Run Run.cmd for the tested bundled app-local ConPTY provider.
Keep bin/ and share/ together. Move/rename the whole package, not only the EXE.
Terminal config: bin/portable-data/config/config.ghostty
Terminal-owned data/cache/tmp stay under bin/portable-data.
The logs directory is reserved; the app currently reports diagnostics to stderr.
Do not remove portable-data while running. Storage/resource failures must not select host paths.
Normal system ConPTY may be selected when bypassing Run.cmd; this is not the bundled-provider launch.
Herdr/Letta logins, HOME/APPDATA, shell history and OS/GPU caches are NOT isolated by this package.
Close the app and child processes before moving/replacing files. Never delete portable-data for updates.
This script does not perform data migrations, updates, signing, publishing or networking.
Clean-user/VM, real IME, permissions/disk-full and GPU qualification require separate evidence.
Do not distribute a used package: data, pasted images, paths and logs can contain private content.
'@
if ($PortableTools) {
    $readme += "`r`nExplicit isolated mode uses strict PATH: host Git and other host CLIs are excluded by default. Portable shims never fall back to host Node/npm/Letta. Fresh Node/Letta profile, no existing authentication migration. This is not confinement: project .npmrc, CLI flags and lifecycle scripts can override npm settings or execute arbitrary code; project writes remain intentional. Explicit absolute host programs remain possible.`r`n"
    $readme += "`r`nPortable Git: Run.cmd and normal Run-Herdr.cmd prepare missing pinned full PortableGit with Bash under bin/portable-data/runtimes/git before launching. First use can download about 60 MB plus the pinned standalone extractor under portable-data/runtimes/git-bootstrap; later use reuses the private runtime. Install-Portable-Git.cmd verifies/reuses or installs it explicitly. Git's self-extractor/post-install command never runs. The real git.exe forwarder under portable-data/shims supports Node child_process without host Git or User/Machine PATH changes. The installer seeds prefix-relative safe.directory for only Letta memfs in each private HOME Git config, so exFAT works after relocation; no host Git config or accounts are changed. The generic builder does not install Letta; a specifically prepared delivery can include its private CLI. See docs/windows-portable-git-th.md.`r`n"
    $readme += "`r`nOptional Herdr: double-click Run-Herdr.cmd. First use downloads the pinned official Windows ZIP and verifies it before installation; later runs verify/reuse the private payload. Herdr uses its own profile under bin/portable-data/profiles/herdr, without copying existing accounts. This launcher does not run install.ps1 or write Windows User PATH/Registry. Keep support/ with the package. Do not use Herdr's normal installer/update/channel commands for this manual portable payload; they can change User PATH. See the repository docs/windows-herdr-portable-th.md. This is not a sandbox. --version and --install-only diagnose Herdr without Git setup.`r`n"
    $readme = $readme.Replace('Herdr/Letta logins, HOME/APPDATA, shell history and OS/GPU caches are NOT isolated by this package.', 'PortableTools requests child-only HOME/APPDATA/npm/Letta storage under bin/portable-data from the matching native build. Fresh profile: no existing authentication is copied. No Letta installation is performed. This is NOT a sandbox: Windows/OS DLL and GPU caches may still use C:. Project files remain in their workspace. Do not redistribute a used package; portable data may contain secrets. GPU/DPI behavior is unqualified.')
    [IO.File]::WriteAllText((Join-Path $data 'config\config.ghostty'), "# Fresh portable tool profile; child storage isolation requires matching native build.`r`n", [Text.UTF8Encoding]::new($false))
}
if($ReadyHerdrSource){
    $preparedLetta=Copy-HerdrReadyPrograms $readyInput $output $PSScriptRoot
    $readme=$readme.Replace('No Letta installation is performed.','This ready build contains the prepared public Letta CLI.').Replace('First use downloads the pinned official Windows ZIP and verifies it before installation; later runs verify/reuse the private payload.','This ready build already includes the pinned Herdr payload; normal launch verifies it without a first-use download.')
    $readme+="`r`nReady Herdr/Letta candidate: double-click Run-Herdr.cmd, then run letta --new in its pane. Bundled Node, full Git/Bash, pinned Herdr, and Letta 0.34.23 are included. A shell-generation-specific persistent session prevents reattachment to pre-v3 live shells; earlier sessions/panes are preserved separately, never stopped. No manual v3 command, first-use program download, npm install, or host CLI is required. This is a fresh profile, not an account/provider migration or offline LLM. Connect your provider normally; no provider credentials are bundled.`r`n"
}
[IO.File]::WriteAllText((Join-Path $output 'README-portable.txt'), $readme, [Text.UTF8Encoding]::new($false))
$record=[ordered]@{ schema = 1; local_candidate = $true; created = (Get-Date).ToString('o'); source_prefix = $source; initial_data_seeded = (-not $OmitInitialData); user_data_copied = $false; published = $false }
if($ReadyHerdrSource){
    $record.prepared_Letta=$preparedLetta;$record.ready_Herdr=$true;$record.mutable_paths_not_catalogued=@('bin/portable-data/profiles','bin/portable-data/home','bin/portable-data/cache','bin/portable-data/tmp','bin/portable-data/logs')
    $metadata=Join-Path $output ('bin/portable-data/profiles/herdr/tmp/build-record-'+[guid]::NewGuid().ToString('N')+'.json')
    [IO.File]::WriteAllText($metadata,($record|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    try{
        # Do not round-trip a large array through WinPS 5.1: it adds a
        # {value,Count} wrapper and serializes extremely slowly.
        & (Join-Path $output 'bin/portable-data/runtimes/node/node.exe') (Join-Path $PSScriptRoot 'herdr-build-files.cjs') finalize $output $metadata
        if($LASTEXITCODE -ne 0){throw 'Long-path-safe ready factory finalization failed.'}
    }finally{[IO.File]::Delete($metadata)}
} else {
    $manifest = [Collections.Generic.List[object]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $output -File -Recurse) {
    $rel=$file.FullName.Substring($output.Length + 1).Replace('\','/')
    $manifest.Add([ordered]@{ path = $rel; bytes = $file.Length; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash })
    }
    $record.files=$manifest
    $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'package-manifest.json') -Encoding UTF8
}
Write-Output "PORTABLE_PACKAGE=$output"
