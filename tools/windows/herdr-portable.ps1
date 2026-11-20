param([string]$PackageRoot, [switch]$InstallOnly, [switch]$VersionOnly, [string[]]$HerdrArguments = @())

# Windows PowerShell 5.1. Dot-source to test functions without running main.
$script:HerdrScriptRoot = $PSScriptRoot
# A live pane's environment cannot be upgraded by reloading server config.
# Route each shell contract to a stable named session; keep legacy sessions
# alive/addressable instead of killing panes or silently attaching their v2 PATH.
$script:HerdrShellGeneration = 'v3'

function Assert-HerdrSafePath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path -notmatch '^[A-Za-z]:[\\/]') { throw 'An absolute local drive path is required.' }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points are not permitted in portable paths.' }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }; $cursor = $parent
    }
    return $full
}

function New-HerdrDirectory([string]$Path) {
    $safe = Assert-HerdrSafePath $Path
    if ((Test-Path -LiteralPath $safe) -and -not (Test-Path -LiteralPath $safe -PathType Container)) { throw 'Expected a private directory.' }
    [void][IO.Directory]::CreateDirectory($safe)
    [void](Assert-HerdrSafePath $safe)
}

function Read-HerdrPin {
    $path = Join-Path $script:HerdrScriptRoot 'herdr-source-pin.json'
    if (-not (Test-Path -LiteralPath $path)) {
        if ($script:HerdrScriptRoot -notmatch '[\\/]tools[\\/]windows$' -or
            -not (Test-Path -LiteralPath (Join-Path $script:HerdrScriptRoot '../../build.zig') -PathType Leaf)) { throw 'Packaged Herdr source pin is missing.' }
        $path = Join-Path $script:HerdrScriptRoot '../../third_party/herdr/source-pin.json'
    }
    [void](Assert-HerdrSafePath $path)
    $pin = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($pin.version -ne '0.9.5' -or $pin.tag -ne 'v0.9.5' -or
        $pin.url -cne 'https://github.com/herdrdev/herdr/releases/download/v0.9.5/herdr-windows-x86_64.zip' -or
        $pin.sha256 -cne 'd2c6c9c971c43a0bfdde8c692a9a1a7a45c3e4807cd01ae45662b4734fac1cbf') { throw 'Unsupported or invalid Herdr source pin.' }
    return $pin
}

function Get-HerdrPortableLayout([string]$PackageRoot) {
    $root = Assert-HerdrSafePath $PackageRoot
    $sentinel = Join-Path $root 'bin/localterm-dev.exe'
    [void](Assert-HerdrSafePath $sentinel)
    if (-not (Test-Path -LiteralPath $sentinel -PathType Leaf)) { throw 'Package terminal sentinel is missing.' }
    $data = Join-Path $root 'bin/portable-data'
    $profile = Join-Path $data 'profiles/herdr'
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $id = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant())))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    $legacySession='portable-' + $id.Substring(0,24)
    return [pscustomobject]@{ Root=$root; Data=$data; Profile=$profile; Apps=(Join-Path $data 'apps/herdr'); App=(Join-Path $data 'apps/herdr/0.9.5'); Session=($legacySession+'-shell-'+$script:HerdrShellGeneration); LegacySession=$legacySession }
}

function Get-HerdrTreeFiles([string]$Root) {
    [void](Assert-HerdrSafePath $Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw 'Payload root must be a directory.' }
    # The root's ancestors are checked once. Descendants are reached only via
    # already-checked parents; inspecting each entry before descent retains the
    # no-reparse guarantee without O(files * ancestor-depth) Get-Item calls.
    function Get-HerdrCheckedDescendants([string]$Directory) {
        foreach ($entry in Get-ChildItem -LiteralPath $Directory -Force -ErrorAction Stop) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points are not permitted in portable payloads.' }
            if ($entry.PSIsContainer) { Get-HerdrCheckedDescendants $entry.FullName } else { $entry }
        }
    }
    Get-HerdrCheckedDescendants $Root
}

function Test-HerdrInstalledPayload($Layout) {
    [void](Assert-HerdrSafePath $Layout.App)
    if (-not (Test-Path -LiteralPath $Layout.App)) { return $false }
    $manifestPath = Join-Path $Layout.App '.portable-manifest.json'
    [void](Assert-HerdrSafePath $manifestPath)
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($manifest.version -ne '0.9.5' -or $manifest.archiveSha256 -ne (Read-HerdrPin).sha256) { throw 'Installed manifest pin mismatch.' }
    $actual = @(Get-HerdrTreeFiles $Layout.App | Where-Object { $_.FullName -ne $manifestPath })
    if ($actual.Count -ne @($manifest.files).Count) { throw 'Installed payload file count mismatch.' }
    $seen = @{}
    foreach ($record in $manifest.files) {
        $name = [string]$record.path
        if (-not $name -or $name.Contains('\') -or $name.StartsWith('/') -or $name -match '(^|/)\.\.?(/|$)' -or $name.Contains(':') -or $seen.ContainsKey($name)) { throw 'Invalid installed manifest path.' }
        $seen[$name] = $true
        $path = Join-Path $Layout.App $name
        [void](Assert-HerdrSafePath $path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $record.sha256) { throw 'Installed payload integrity check failed.' }
    }
    foreach ($required in Get-HerdrRequiredFiles) { if (-not $seen.ContainsKey($required)) { throw 'Required release file is missing.' } }
    return $true
}

function Get-HerdrRequiredFiles {
    @('herdr.exe','conpty/conpty.dll','conpty/x64/OpenConsole.exe','conpty/arm64/OpenConsole.exe','conpty/herdr-conpty.json','THIRD-PARTY-NOTICES/Microsoft.Windows.Console.ConPTY-LICENSE.txt','THIRD-PARTY-NOTICES/Microsoft.Windows.Console.ConPTY-NOTICE.md')
}

# Small in-process test seam. No environment-controlled URL/hash overrides.
function Receive-HerdrArchive([string]$Url, [string]$Destination) {
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.AllowAutoRedirect = $true; $request.Timeout = 60000; $request.ReadWriteTimeout = 60000
    $response = $null; $inputStream = $null; $output = $null
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    try {
        $response = $request.GetResponse()
        if ($response.ResponseUri.Scheme -ne 'https') { throw 'HTTPS is required.' }
        $inputStream = $response.GetResponseStream()
        $output = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew)
        $buffer = New-Object byte[] 65536; [long]$total = 0
        while (($count = $inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $total += $count
            if ($total -gt 268435456 -or [DateTime]::UtcNow -gt $deadline) { throw 'Archive download limit exceeded.' }
            $output.Write($buffer,0,$count)
        }
    } finally { if ($output) {$output.Dispose()}; if ($inputStream) {$inputStream.Dispose()}; if ($response) {$response.Dispose()} }
}

function Remove-HerdrOwnedTree([string]$Path) {
    # Validate the complete tree before deleting anything; never follow links.
    [void](Assert-HerdrSafePath $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $files = @(Get-HerdrTreeFiles $Path)
    foreach ($file in $files) { [IO.File]::Delete($file.FullName) }
    function Remove-HerdrEmptyDirectories([string]$Directory) {
        foreach ($child in Get-ChildItem -LiteralPath $Directory -Force) { Remove-HerdrEmptyDirectories $child.FullName }
        [IO.Directory]::Delete($Directory)
    }
    Remove-HerdrEmptyDirectories $Path
}

function Install-HerdrPortablePayload($Layout) {
    $pin = Read-HerdrPin
    if (Test-HerdrInstalledPayload $Layout) {
        Write-Host 'Using the verified private Herdr installation (no download).'
        return $Layout.App
    }
    New-HerdrDirectory $Layout.Apps
    $lockPath = Join-Path $Layout.Apps '.install.lock'
    [void](Assert-HerdrSafePath $lockPath)
    $lock = $null; $stage = $null; $zipPath = $null
    try {
        $lock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        if (Test-HerdrInstalledPayload $Layout) { return $Layout.App }
        $token = [Guid]::NewGuid().ToString('N')
        $stage = Join-Path $Layout.Apps ('.stage-' + $token)
        $zipPath = Join-Path $Layout.Apps ('.download-' + $token + '.zip')
        Write-Host ('First run: downloading official Herdr ' + $pin.version + '. Please wait...')
        Receive-HerdrArchive $pin.url $zipPath
        [void](Assert-HerdrSafePath $zipPath)
        Write-Host 'Checking the pinned SHA-256 and extracting the complete package...'
        if ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ne $pin.sha256) { throw 'Herdr archive SHA-256 mismatch.' }
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            if ($zip.Entries.Count -gt 10000) { throw 'Too many ZIP entries.' }
            $names = @{}; $plan = @(); [long]$total = 0
            foreach ($entry in $zip.Entries) {
                $name = $entry.FullName
                if (-not $name -or $name.Contains('\') -or $name.StartsWith('/') -or $name.Contains(':')) { throw 'Unsafe ZIP path.' }
                $directory = $name.EndsWith('/'); $clean = $name.TrimEnd('/')
                foreach ($part in $clean.Split('/')) {
                    if (-not $part -or $part -match '[<>"|?*\x00-\x1f]' -or $part -match '[ .]$' -or $part -in @('.','..') -or $part -match '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[0-9\u00b9\u00b2\u00b3]|LPT[0-9\u00b9\u00b2\u00b3])(?:\.|$)') { throw 'Unsafe Windows ZIP component.' }
                }
                if ($names.ContainsKey($clean) -or $clean -ieq '.portable-manifest.json') { throw 'Duplicate or reserved ZIP name.' }
                $names[$clean] = $directory
                $unixType = ($entry.ExternalAttributes -shr 16) -band 61440
                if (($entry.ExternalAttributes -band 1024) -or ($unixType -ne 0 -and $unixType -ne 32768 -and $unixType -ne 16384)) { throw 'ZIP links or special files are forbidden.' }
                $total += $entry.Length
                if ($total -gt 1073741824 -or $entry.Length -gt 536870912) { throw 'Expanded ZIP limit exceeded.' }
                $plan += [pscustomobject]@{Entry=$entry; Name=$clean; Directory=$directory}
            }
            foreach ($item in $plan) {
                $parent = [IO.Path]::GetDirectoryName($item.Name).Replace('\','/')
                while ($parent) {
                    if ($names.ContainsKey($parent) -and -not $names[$parent]) { throw 'ZIP file/directory collision.' }
                    $parent = [IO.Path]::GetDirectoryName($parent).Replace('\','/')
                }
            }
            foreach ($required in Get-HerdrRequiredFiles) { if (-not $names.ContainsKey($required) -or $names[$required]) { throw 'Incomplete Herdr release ZIP.' } }
            New-HerdrDirectory $stage
            foreach ($item in $plan) {
                $dest = Join-Path $stage $item.Name
                if ($item.Directory) { New-HerdrDirectory $dest; continue }
                New-HerdrDirectory ([IO.Path]::GetDirectoryName($dest))
                $inputStream = $null; $output = $null; [long]$written = 0
                try {
                    $inputStream = $item.Entry.Open()
                    $output = [IO.File]::Open($dest,[IO.FileMode]::CreateNew)
                    $buffer = New-Object byte[] 65536
                    while (($count = $inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
                        $written += $count
                        if ($written -gt $item.Entry.Length -or $written -gt 536870912) { throw 'ZIP entry exceeded declared size.' }
                        $output.Write($buffer,0,$count)
                    }
                    if ($written -ne $item.Entry.Length) { throw 'Truncated ZIP entry.' }
                } finally { if ($output) { $output.Dispose() }; if ($inputStream) { $inputStream.Dispose() } }
            }
        } finally { $zip.Dispose() }
        $records = @(Get-HerdrTreeFiles $stage | ForEach-Object { [pscustomobject]@{path=$_.FullName.Substring($stage.Length+1).Replace('\','/'); sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} })
        $manifest = @{version=$pin.version; archiveSha256=$pin.sha256; files=$records} | ConvertTo-Json -Depth 5
        [IO.File]::WriteAllText((Join-Path $stage '.portable-manifest.json'),$manifest,(New-Object Text.UTF8Encoding($false)))
        [void](Assert-HerdrSafePath $Layout.App)
        [IO.Directory]::Move($stage,$Layout.App)
        $stage = $null
        if (-not (Test-HerdrInstalledPayload $Layout)) { throw 'Installed payload verification failed.' }
        return $Layout.App
    } finally {
        try { if ($stage) { Remove-HerdrOwnedTree $stage }; if ($zipPath -and (Test-Path -LiteralPath $zipPath)) { [void](Assert-HerdrSafePath $zipPath); [IO.File]::Delete($zipPath) } } finally { if ($lock) { $lock.Dispose() } }
    }
}

function Set-HerdrPrivateEnvironment($Layout) {
    $p = $Layout.Profile
    $homePath = Join-Path $p 'home'
    $values = @{
        HOME=$homePath; USERPROFILE=$homePath; APPDATA=(Join-Path $p 'config'); LOCALAPPDATA=(Join-Path $p 'state')
        XDG_CONFIG_HOME=(Join-Path $p 'config'); XDG_STATE_HOME=(Join-Path $p 'state'); XDG_CACHE_HOME=(Join-Path $p 'cache')
        TEMP=(Join-Path $p 'tmp'); TMP=(Join-Path $p 'tmp'); CODEX_HOME=(Join-Path $homePath '.codex')
        LETTA_HOME=(Join-Path $homePath '.letta'); LETTA_LOCAL_BACKEND_DIR=(Join-Path $homePath '.letta/local')
        NPM_CONFIG_PREFIX=(Join-Path $p 'npm'); NPM_CONFIG_CACHE=(Join-Path $p 'cache/npm')
    }
    foreach ($path in $values.Values) {
        New-HerdrDirectory $path
        $probe = Join-Path $path ('.write-probe-' + [Guid]::NewGuid().ToString('N'))
        $stream = [IO.File]::Open($probe,[IO.FileMode]::CreateNew); $stream.Dispose(); [IO.File]::Delete($probe)
    }
    New-HerdrDirectory (Join-Path $p 'config/herdr')
    foreach ($config in @('npm-user.npmrc','npm-global.npmrc')) {
        $file = Join-Path $p $config
        [void](Assert-HerdrSafePath $file)
        if (-not (Test-Path -LiteralPath $file)) { $s=[IO.File]::Open($file,[IO.FileMode]::CreateNew); $s.Dispose() }
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'Invalid private npm config.' }
    }
    $windows = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    [void](Assert-HerdrSafePath $windows)
    $node = Join-Path $Layout.Data 'runtimes/node'
    [void](Assert-HerdrSafePath $node)
    if (Test-Path -LiteralPath $node) {
        $nodeManifest = Join-Path $node 'provenance.json'
        [void](Assert-HerdrSafePath $nodeManifest)
        $provenance = Get-Content -LiteralPath $nodeManifest -Raw -ErrorAction Stop | ConvertFrom-Json
        $actualNodeFiles = @{}
        foreach ($file in Get-HerdrTreeFiles $node) {
            $rel = $file.FullName.Substring($node.Length+1).Replace('\','/')
            $actualNodeFiles[$rel] = $file.FullName
        }
        $tracked = @{}
        foreach ($record in $provenance.files.PSObject.Properties) {
            $rel = $record.Name
            if (-not $rel -or $rel -match '(^|/)(\.|\.\.)(/|$)|[:\\]|[ .](/|$)' -or $rel.StartsWith('/') -or $rel.Contains('//') -or $tracked.ContainsKey($rel) -or $record.Value -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid private Node runtime manifest.' }
            if (-not $actualNodeFiles.ContainsKey($rel) -or (Get-FileHash -LiteralPath $actualNodeFiles[$rel] -Algorithm SHA256).Hash -ne $record.Value) { throw 'Private Node runtime integrity check failed.' }
            $tracked[$rel] = $true
        }
        foreach ($required in @('node.exe','node_modules/npm/bin/npm-cli.js','node_modules/npm/bin/npx-cli.js','npm.cmd','npx.cmd','LICENSE')) { if (-not $tracked.ContainsKey($required)) { throw 'Incomplete private Node runtime.' } }
        foreach ($rel in $actualNodeFiles.Keys) {
            if ($rel -ne 'provenance.json' -and -not $tracked.ContainsKey($rel)) { throw 'Unexpected private Node runtime file.' }
        }
    }
    # Pinned Node wins for node/npm/npx. Newly installed private npm CLIs then
    # precede the shared shims (whose Letta target belongs to the other profile).
    $pathParts = @($node,(Join-Path $p 'npm'),(Join-Path $Layout.Data 'shims'),$Layout.App,(Join-Path $windows 'System32'),$windows,(Join-Path $windows 'System32/WindowsPowerShell/v1.0'))
    foreach ($path in $pathParts) { [void](Assert-HerdrSafePath $path) }
    $shims = Join-Path $Layout.Data 'shims'
    if (Test-Path -LiteralPath $shims) {
        if (-not (Test-Path -LiteralPath $shims -PathType Container)) { throw 'Private shims must be a directory.' }
        [void]@(Get-HerdrTreeFiles $shims)
    }
    foreach ($key in @([Environment]::GetEnvironmentVariables('Process').Keys)) {
        if ($key -match '^(NODE_|NPM_|NVM_|LETTA_|LETTACODE_|BUN_|OPENSSL_|AWS_|AZURE_|GIT_|SSH_|SECRET_|HERDR_|CODEX_|CLAUDE_|OPENCODE_|CURSOR_|VSCODE_)' -or
            $key -match '(_API_KEY|_APIKEY|_TOKEN|_SECRET|_PASSWORD|_PROXY)$' -or
            $key -in @('GOOGLE_APPLICATION_CREDENTIALS','CLOUDSDK_CONFIG','SSL_CERT_FILE','SSL_CERT_DIR','CURL_CA_BUNDLE','AGENT_ID','AGENT_NAME','CONVERSATION_ID','MEMORY_DIR','DATABASE_URL','REDIS_URL','PGPASSWORD','PGPASSFILE','NETRC','INIT_CWD')) { [Environment]::SetEnvironmentVariable($key,$null,'Process') }
    }
    $values.PATH = $pathParts -join ';'
    $values.HOMEDRIVE = [IO.Path]::GetPathRoot($homePath).TrimEnd('\')
    $values.HOMEPATH = $homePath.Substring(2)
    $values.NPM_CONFIG_USERCONFIG = Join-Path $p 'npm-user.npmrc'
    $values.NPM_CONFIG_GLOBALCONFIG = Join-Path $p 'npm-global.npmrc'
    $values.HERDR_SESSION = $Layout.Session
    $values.HERDR_CONFIG_PATH = Join-Path $p 'config/herdr/config.toml'
    [void](Assert-HerdrSafePath $values.HERDR_CONFIG_PATH)
    if (Test-Path -LiteralPath $values.HERDR_CONFIG_PATH -PathType Container) { throw 'Private Herdr config must be a regular file when present.' }
    foreach ($key in $values.Keys) { [Environment]::SetEnvironmentVariable($key,$values[$key],'Process') }
}

function Update-HerdrPrivateShellConfig([string]$Config,[string]$ShellExe) {
    [void](Assert-HerdrSafePath $Config)
    [void](Assert-HerdrSafePath $ShellExe)
    # TOML basic strings, not literal strings: drive separators must be escaped;
    # this also handles package names containing apostrophes or non-ASCII text.
    $quoted='"'+$ShellExe.Replace('\','\\').Replace('"','\"')+'"'
    if (-not (Test-Path -LiteralPath $Config)) {
        $text="# Fresh Herdr portable profile; launcher refreshes its private shell path.`r`n[terminal]`r`ndefault_shell = "+$quoted+"`r`n"
        $stream=[IO.File]::Open($Config,[IO.FileMode]::CreateNew)
        try {$bytes=[Text.Encoding]::UTF8.GetBytes($text);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
        return
    }
    $text=[IO.File]::ReadAllText($Config,[Text.UTF8Encoding]::new($false,$true))
    $originalHash=(Get-FileHash -LiteralPath $Config -Algorithm SHA256).Hash
    $sections=[regex]::Matches($text,'(?ms)^[ \t]*\[terminal\][ \t]*(?:#[^\r\n]*)?\r?\n(?<body>.*?)(?=^[ \t]*\[|\z)')
    if ($sections.Count -eq 0) {return} # Existing custom configuration is not ours.
    if ($sections.Count -ne 1) {throw 'Duplicate terminal sections; private configuration was not changed.'}
    $pattern=@'
(?m)^[ \t]*default_shell[ \t]*=[ \t]*(?<value>"(?:\\.|[^"\\])*"|'[^']*')[ \t]*(?:#[^\r\n]*)?\r?$
'@
    $settings=[regex]::Matches($sections[0].Groups['body'].Value,$pattern.Trim())
    if ($settings.Count -eq 0) {return}
    if ($settings.Count -ne 1) {throw 'Duplicate terminal shell settings; private configuration was not changed.'}
    $literal=$settings[0].Groups['value'].Value
    if ($literal.StartsWith('"')) {
        try {$value=[string](ConvertFrom-Json $literal)}catch{throw 'Unsupported shell string; private configuration was not changed.'}
    } else {$value=$literal.Substring(1,$literal.Length-2)}
    $normalized=$value.Replace('/','\')
    $managed=$normalized -ieq 'herdr-private-shell.exe' -or
        ($normalized -match '^[A-Za-z]:\\' -and $normalized -match '\\bin\\portable-data\\apps\\herdr-shell\\v[123]\\herdr-private-shell\.exe$')
    if (-not $managed -or $value -ceq $ShellExe) {return} # Preserve user-selected shells.
    $index=$sections[0].Groups['body'].Index+$settings[0].Groups['value'].Index
    $updated=$text.Remove($index,$literal.Length).Insert($index,$quoted)
    $pending=$Config+'.shell-path-'+[guid]::NewGuid().ToString('N')+'.tmp'
    $backup=$Config+'.before-shell-path-'+[guid]::NewGuid().ToString('N')+'.bak'
    [void](Assert-HerdrSafePath $pending);[void](Assert-HerdrSafePath $backup)
    try {
        [IO.File]::WriteAllText($pending,$updated,[Text.UTF8Encoding]::new($false))
        if ((Get-FileHash -LiteralPath $Config -Algorithm SHA256).Hash -cne $originalHash) {throw 'Private configuration changed concurrently; retry without overwriting it.'}
        # Backup stays beside the user's private config, never in shared evidence.
        [IO.File]::Replace($pending,$Config,$backup)
    } finally {if(Test-Path -LiteralPath $pending){[IO.File]::Delete($pending)}}
}

function Set-HerdrPrivateShell($Layout) {
    # Upstream accepts a shell executable only and omits -NoProfile for ordinary
    # PowerShell panes. A tiny private console shim adds it without a Herdr fork.
    $source = Join-Path $script:HerdrScriptRoot 'herdr-private-shell.cs'
    [void](Assert-HerdrSafePath $source)
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $shellRoot = Join-Path $Layout.Data ('apps/herdr-shell/'+$script:HerdrShellGeneration)
    $shellExe = Join-Path $shellRoot 'herdr-private-shell.exe'
    $manifestPath = Join-Path $shellRoot 'manifest.json'
    [void](Assert-HerdrSafePath $shellRoot)
    if (Test-Path -LiteralPath $shellRoot) {
        $shellFiles = @(Get-HerdrTreeFiles $shellRoot)
        [void](Assert-HerdrSafePath $manifestPath)
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json
        [void](Assert-HerdrSafePath $shellExe)
        if ($manifest.schema -ne 1 -or $manifest.sourceSha256 -ne $sourceHash -or
            (Get-FileHash -LiteralPath (Join-Path $shellRoot 'herdr-private-shell.cs') -Algorithm SHA256).Hash -ne $sourceHash -or
            (Get-FileHash -LiteralPath $shellExe -Algorithm SHA256).Hash -ne $manifest.exeSha256 -or
            $shellFiles.Count -ne 3) { throw 'Private shell integrity mismatch; existing files were not replaced.' }
    } else {
        $parent = Join-Path $Layout.Data 'apps/herdr-shell'
        New-HerdrDirectory $parent
        $stage = Join-Path $parent ('.stage-' + [Guid]::NewGuid().ToString('N'))
        New-HerdrDirectory $stage
        $process = $null
        try {
            $stagedSource = Join-Path $stage 'herdr-private-shell.cs'
            [IO.File]::Copy($source,$stagedSource,$false)
            $stagedExe = Join-Path $stage 'herdr-private-shell.exe'
            $compiler = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
            [void](Assert-HerdrSafePath $compiler)
            if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'Windows .NET compiler missing; no host shell fallback.' }
            $si = New-Object Diagnostics.ProcessStartInfo
            $si.FileName=$compiler
            $si.Arguments='/nologo /target:exe /out:"'+$stagedExe+'" "'+$stagedSource+'"'
            $si.WorkingDirectory=$stage; $si.UseShellExecute=$false; $si.CreateNoWindow=$true
            $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
            $process=New-Object Diagnostics.Process; $process.StartInfo=$si
            [void]$process.Start()
            $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(45000)) { $process.Kill(); throw 'Private shell compilation timed out.' }
            if ($process.ExitCode -ne 0) { throw ('Private shell compilation failed: '+$stdout.Result+$stderr.Result) }
            $manifest=@{schema=1;sourceSha256=$sourceHash;exeSha256=(Get-FileHash -LiteralPath $stagedExe -Algorithm SHA256).Hash}|ConvertTo-Json
            [IO.File]::WriteAllText((Join-Path $stage 'manifest.json'),$manifest,[Text.UTF8Encoding]::new($false))
            [IO.Directory]::Move($stage,$shellRoot); $stage=$null
        } finally {
            if ($process) { $process.Dispose() }
            if ($stage) { Remove-HerdrOwnedTree $stage }
        }
    }
    # PATH is useful inside the child shell, but Herdr's explicit Windows
    # lpApplicationName does not search it. Refresh the managed absolute path.
    $env:PATH=$shellRoot+';'+$env:PATH
    $env:LOCALTERM_HERDR_PACKAGE_ROOT=$Layout.Root
    $windows=[Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    $env:PSModulePath=Join-Path $windows 'System32/WindowsPowerShell/v1.0/Modules'
    # -NoExit autoloads PSReadLine before the encoded startup command. Select
    # our module at that first binding, not an inbox module followed by a
    # second DLL/cmdlet import (which causes duplicate cmdlet-name errors).
    $privateModules=Join-Path $Layout.Root 'bin/powershell'
    [void](Assert-HerdrSafePath $privateModules)
    if (Test-Path -LiteralPath $privateModules) {
        if (-not (Test-Path -LiteralPath $privateModules -PathType Container)) { throw 'Private module root must be a directory.' }
        $env:PSModulePath=$privateModules+';'+$env:PSModulePath
    }
    $env:ComSpec=Join-Path $windows 'System32/cmd.exe'
    $config=$env:HERDR_CONFIG_PATH
    [void](Assert-HerdrSafePath $config)
    Update-HerdrPrivateShellConfig $config $shellExe
}

function Invoke-HerdrPortableMain([string]$PackageRoot, [switch]$InstallOnly, [string[]]$HerdrArguments = @()) {
    $ErrorActionPreference = 'Stop'
    $layout = Get-HerdrPortableLayout $PackageRoot
    $app = Install-HerdrPortablePayload $layout
    Set-HerdrPrivateEnvironment $layout
    Set-HerdrPrivateShell $layout
    Write-Host 'Herdr pinned payload verified; private package profile ready.'
    $script:HerdrPortableExitCode=0
    if ($InstallOnly) { return }
    Push-Location $layout.Profile
    try {
        # Never capture this invocation in an exit expression or output pipe:
        # a TUI must retain its console handles and version output must be visible.
        & (Join-Path $app 'herdr.exe') --session $layout.Session @HerdrArguments
        $script:HerdrPortableExitCode=$LASTEXITCODE
    } finally { Pop-Location }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ($VersionOnly) { $HerdrArguments = @('--version') }
        Invoke-HerdrPortableMain -PackageRoot $PackageRoot -InstallOnly:$InstallOnly -HerdrArguments $HerdrArguments
        exit $script:HerdrPortableExitCode
    }
    catch { Write-Error ('Herdr portable failed: ' + $_.Exception.Message); exit 1 }
}
