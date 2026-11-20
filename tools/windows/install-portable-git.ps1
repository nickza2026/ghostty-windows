param([string]$PackageRoot)
# Windows PowerShell 5.1; dot sourcing defines functions only.
$script:PortableGitScriptRoot = $PSScriptRoot

function Assert-PortableGitPath([string]$Path) {
    if ($Path -notmatch '^[A-Za-z]:[\\/]') { throw 'Portable Git requires an absolute local-drive package root.' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Portable Git paths may not contain reparse points.' }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }; $cursor = $parent
    }
    return $full
}
function New-PortableGitDirectory([string]$Path) {
    [void](Assert-PortableGitPath $Path)
    [void][IO.Directory]::CreateDirectory($Path)
    [void](Assert-PortableGitPath $Path)
}
function Get-PortableGitFiles([string]$Root) {
    [void](Assert-PortableGitPath $Root)
    foreach ($entry in Get-ChildItem -LiteralPath $Root -Force -ErrorAction Stop) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Portable Git tree contains a reparse point.' }
        if ($entry.PSIsContainer) { Get-PortableGitFiles $entry.FullName } else { $entry }
    }
}
function Remove-PortableGitStage([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $files = @(Get-PortableGitFiles $Path)
    foreach ($file in $files) { [IO.File]::Delete($file.FullName) }
    function Remove-PortableGitEmpty([string]$Directory) {
        foreach ($child in Get-ChildItem -LiteralPath $Directory -Force) { Remove-PortableGitEmpty $child.FullName }
        [IO.Directory]::Delete($Directory)
    }
    Remove-PortableGitEmpty $Path
}
function Read-PortableGitPin {
    $path = Join-Path $script:PortableGitScriptRoot 'git-source-pin.json'
    if (-not (Test-Path -LiteralPath $path)) {
        if ($script:PortableGitScriptRoot -notmatch '[\\/]tools[\\/]windows$') { throw 'Packaged Git source pin is missing.' }
        $path = Join-Path $script:PortableGitScriptRoot '../../third_party/git/source-pin.json'
    }
    [void](Assert-PortableGitPath $path)
    $pin = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($pin.version -cne '2.56.0.windows.4' -or $pin.tag -cne 'v2.56.0.windows.4' -or
        $pin.url -cne 'https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.4/PortableGit-2.56.0.4-64-bit.7z.exe' -or
        $pin.sha256 -cne 'b1f3e52216e2ed6882d1bebfd4d3fdf319bec40d2edbbf9fd26ec4fd3fce7ed1' -or $pin.size -ne 60087472 -or $pin.format -cne '7z-sfx') { throw 'Invalid portable Git source pin.' }
    return $pin
}
function Get-PortableGitLayout([string]$PackageRoot) {
    $root = Assert-PortableGitPath $PackageRoot
    $sentinel = Join-Path $root 'bin/localterm-dev.exe'
    [void](Assert-PortableGitPath $sentinel)
    if (-not (Test-Path -LiteralPath $sentinel -PathType Leaf)) { throw "Package terminal sentinel missing under $root" }
    $data = Join-Path $root 'bin/portable-data'
    return [pscustomobject]@{ Root=$root; Data=$data; Runtime=(Join-Path $data 'runtimes/git'); Shims=(Join-Path $data 'shims'); Tmp=(Join-Path $data 'tmp') }
}
function Receive-PortableGitArchive([string]$Url, [string]$Destination) {
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.Timeout = 60000; $request.ReadWriteTimeout = 60000
    $response=$null; $inputStream=$null; $output=$null
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    try {
        $response = $request.GetResponse()
        if ($response.ResponseUri.Scheme -ne 'https') { throw 'HTTPS is required.' }
        $inputStream = $response.GetResponseStream()
        $output = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew)
        $buffer = New-Object byte[] 65536; [long]$total=0
        while (($count=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $total += $count
            if ($total -gt 268435456 -or [DateTime]::UtcNow -gt $deadline) { throw 'Git archive download limit exceeded.' }
            $output.Write($buffer,0,$count)
        }
    } finally { if ($output) {$output.Dispose()}; if ($inputStream) {$inputStream.Dispose()}; if ($response) {$response.Dispose()} }
}
function Assert-PortableGitEntry([string]$Name) {
    if (-not $Name -or $Name.Contains('\') -or $Name.StartsWith('/') -or $Name.Contains(':')) { throw 'Invalid Git archive path.' }
    foreach ($part in $Name.TrimEnd('/').Split('/')) {
        if (-not $part -or $part -match '[\x00-\x1f<>"|?*]' -or $part -match '[. ]$' -or $part -eq '.' -or $part -eq '..' -or
            $part -match '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[0-9\u00b9\u00b2\u00b3]|LPT[0-9\u00b9\u00b2\u00b3])(?:\.|$)') { throw 'Unsafe Windows Git archive name.' }
    }
}
function Get-PortableGitFormat($Pin) {
    if ($null -ne $Pin -and $Pin.PSObject.Properties['format']) { return [string]$Pin.format }
    return 'zip'
}
function Get-PortableGitRequiredFiles($Pin) {
    @('cmd/git.exe','ucrt64/bin/git.exe','LICENSE.txt')
    if ((Get-PortableGitFormat $Pin) -eq '7z-sfx') {
        @('ucrt64/libexec/git-core/git-remote-https.exe','usr/bin/bash.exe','usr/bin/sh.exe','usr/bin/env.exe')
    } else { @('ucrt64/bin/git-remote-https.exe') }
}
function Invoke-PortableGitTar([string]$Arguments, [string]$Directory) {
    $tar=Join-Path ([Environment]::GetFolderPath('Windows')) 'System32/tar.exe'
    [void](Assert-PortableGitPath $tar)
    if (-not (Test-Path -LiteralPath $tar -PathType Leaf)) { throw 'Windows System32/tar.exe is required for PortableGit.' }
    $si=New-Object Diagnostics.ProcessStartInfo
    $si.FileName=$tar; $si.Arguments=$Arguments; $si.WorkingDirectory=$Directory
    $si.UseShellExecute=$false; $si.CreateNoWindow=$true
    $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process; $process.StartInfo=$si
    try {
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) { $process.Kill(); $process.WaitForExit(); throw 'PortableGit archive operation timed out.' }
        if ($process.ExitCode -ne 0) {
            $detail=$stderr.Result
            if ($detail.Length -gt 2400) { $detail=$detail.Substring(0,2400) }
            throw ('Windows tar rejected the PortableGit archive (exit '+$process.ExitCode+'): '+$detail)
        }
        if ($stdout.Result.Length -gt 33554432 -or $stderr.Result.Length -gt 1048576) { throw 'PortableGit archive listing limit exceeded.' }
        return $stdout.Result
    } finally { $process.Dispose() }
}
function Get-PortableGitExtractor($Layout) {
    # Official standalone 7zr is public domain. Windows libarchive cannot decode
    # the upstream archive's LZMA lc=8 stream; never execute Git's SFX RunProgram.
    $root=Join-Path $Layout.Data 'runtimes/git-bootstrap'
    New-PortableGitDirectory $root
    $exe=Join-Path $root '7zr.exe'
    $sha='9bf582b894dfa665f852d7e9112b02290a1c303c2d95a21fcdc41ffcb03143b7'
    $url='https://github.com/ip7z/7zip/releases/download/26.05/7zr.exe'
    [void](Assert-PortableGitPath $exe)
    if (Test-Path -LiteralPath $exe) {
        if ((Get-Item -LiteralPath $exe).Length -ne 602624 -or (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ine $sha) { throw 'Unknown or modified private Git extractor; refusing overwrite.' }
        return $exe
    }
    $pending=Join-Path $root ('.7zr-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try {
        Receive-PortableGitArchive $url $pending
        if ((Get-Item -LiteralPath $pending).Length -ne 602624 -or (Get-FileHash -LiteralPath $pending -Algorithm SHA256).Hash -ine $sha) { throw 'Official Git extractor identity mismatch.' }
        [IO.File]::Move($pending,$exe)
        @{version='26.05';url=$url;sha256=$sha;size=602624;license='7zr standalone: public domain';source='https://github.com/ip7z/7zip/tree/26.05'}|ConvertTo-Json|Set-Content (Join-Path $root 'provenance.json') -Encoding UTF8
    } finally { if (Test-Path -LiteralPath $pending) { [void](Assert-PortableGitPath $pending);[IO.File]::Delete($pending) } }
    return $exe
}
function Expand-PortableGitFullArchive([string]$Archive, [string]$Payload, $Layout) {
    # Never execute the Git self-extractor or its configured post-install command.
    # Validate metadata with Windows tar, then extract with pinned private 7zr.
    $names=Invoke-PortableGitTar ('-tf "'+$Archive+'"') (Split-Path $Archive)
    $seen=@{}; $count=0
    foreach ($name in ($names -split '\r?\n')) {
        if (-not $name) { continue }
        Assert-PortableGitEntry $name; $key=$name.TrimEnd('/')
        if ($seen.ContainsKey($key) -or $key -ieq '.portable-git-manifest.json') { throw 'Duplicate or reserved PortableGit archive entry.' }
        $seen[$key]=$true; $count++
        if ($count -gt 100000) { throw 'PortableGit archive entry limit exceeded.' }
    }
    if ($count -eq 0) { throw 'Empty PortableGit archive.' }
    $details=Invoke-PortableGitTar ('-tvf "'+$Archive+'"') (Split-Path $Archive)
    [long]$total=0; $detailCount=0
    foreach ($line in ($details -split '\r?\n')) {
        if (-not $line) { continue }
        # bsdtar verbose mode: type/mode, link count, owner, group, size, date, name.
        # Reject every special/link entry before allowing extraction.
        if ($line -notmatch '^[d-][rwxStTs-]{9}\s+\d+\s+\S+\s+\S+\s+(\d+)\s+') { throw 'Unsupported PortableGit archive entry metadata.' }
        $total += [long]$Matches[1]; $detailCount++
        if ($total -gt 2147483648) { throw 'PortableGit expanded archive limit exceeded.' }
    }
    if ($detailCount -ne $count) { throw 'PortableGit archive listing mismatch.' }
    $extractor=Get-PortableGitExtractor $Layout
    $si=New-Object Diagnostics.ProcessStartInfo
    $si.FileName=$extractor; $si.Arguments='x "'+$Archive+'" -o"'+$Payload+'" -y -bd'
    $si.WorkingDirectory=$Payload; $si.UseShellExecute=$false; $si.CreateNoWindow=$true
    $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process; $process.StartInfo=$si
    try {
        [void]$process.Start();$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) { $process.Kill();$process.WaitForExit();throw 'Private Git extraction timed out.' }
        if ($process.ExitCode -ne 0) { throw ('Private Git extraction failed: '+$stderr.Result) }
    } finally { $process.Dispose() }
    $files=@(Get-PortableGitFiles $Payload); [long]$actual=0
    foreach ($file in $files) {
        $relative=$file.FullName.Substring($Payload.Length+1).Replace('\','/')
        if (-not $seen.ContainsKey($relative)) { throw 'Unexpected extracted PortableGit file.' }
        $actual += $file.Length
        if ($actual -gt 2147483648) { throw 'PortableGit expanded archive limit exceeded.' }
    }
}
function Assert-PortableGitInactive([string]$Runtime) {
    $prefix=(Assert-PortableGitPath $Runtime).TrimEnd('\')+'\'
    foreach ($process in Get-CimInstance Win32_Process -Property ExecutablePath -ErrorAction Stop) {
        if ($process.ExecutablePath -and $process.ExecutablePath.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Close processes using the private Git runtime before upgrading.' }
    }
}
function Get-PortableGitLegacyPin {
    [pscustomobject]@{version='2.56.0.windows.4'; url='https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.4/MinGit-2.56.0.4-64-bit.zip'; sha256='e3bf78351fe777fba47ddee5950082f8a98bb0f02604fdc7ba3ee2cb68ffa877'; format='zip'}
}
function Test-PortableGitRuntime($Layout, $Pin) {
    [void](Assert-PortableGitPath $Layout.Runtime)
    if (-not (Test-Path -LiteralPath $Layout.Runtime)) { return $false }
    $manifestPath = Join-Path $Layout.Runtime '.portable-git-manifest.json'
    $actual = @(Get-PortableGitFiles $Layout.Runtime | Where-Object { $_.FullName -ne $manifestPath })
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($manifest.archiveSha256 -cne $Pin.sha256 -or $manifest.version -cne $Pin.version -or $manifest.url -cne $Pin.url) { throw 'Git provenance mismatch.' }
    if ($actual.Count -ne @($manifest.files).Count) { throw 'Git manifest file count mismatch.' }
    $seen=@{}
    foreach ($record in $manifest.files) {
        Assert-PortableGitEntry $record.path
        if ($seen.ContainsKey($record.path)) { throw 'Duplicate Git manifest path.' }; $seen[$record.path]=$true
        $path=Join-Path $Layout.Runtime $record.path
        [void](Assert-PortableGitPath $path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $record.sha256) { throw 'Git runtime integrity mismatch.' }
    }
    foreach ($required in Get-PortableGitRequiredFiles $Pin) { if (-not $seen.ContainsKey($required)) { throw "Required Git file missing: $required" } }
    return $true
}
function Install-PortableGitRuntime($Layout, $Pin) {
    $upgrade=$false
    if (Test-Path -LiteralPath $Layout.Runtime) {
        try { if (Test-PortableGitRuntime $Layout $Pin) { return } }
        catch {
            if ((Get-PortableGitFormat $Pin) -ne '7z-sfx') { throw }
            # Only our exact, fully intact legacy installation is upgradeable.
            if (-not (Test-PortableGitRuntime $Layout (Get-PortableGitLegacyPin))) { throw 'Unrecognized existing Git runtime.' }
            Assert-PortableGitInactive $Layout.Runtime
            $upgrade=$true
        }
    }
    New-PortableGitDirectory (Split-Path $Layout.Runtime)
    $stage=Join-Path (Split-Path $Layout.Runtime) ('.git-stage-'+[Guid]::NewGuid().ToString('N'))
    New-PortableGitDirectory $stage
    $zipPath=Join-Path $stage 'source.zip'; $payload=Join-Path $stage 'payload'
    try {
        Write-Host 'Downloading pinned private PortableGit runtime...'
        Receive-PortableGitArchive $Pin.url $zipPath
        if ((Get-Item -LiteralPath $zipPath).Length -ne $Pin.size -or (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ine $Pin.sha256) { throw 'Git archive size or SHA-256 mismatch.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        New-PortableGitDirectory $payload
        if ((Get-PortableGitFormat $Pin) -eq '7z-sfx') { Expand-PortableGitFullArchive $zipPath $payload $Layout }
        elseif ((Get-PortableGitFormat $Pin) -eq 'zip') {
        $zip=[IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $seen=@{}; [long]$total=0
            foreach ($entry in $zip.Entries) {
                $name=$entry.FullName; Assert-PortableGitEntry $name
                $key=$name.TrimEnd('/')
                if ($seen.ContainsKey($key) -or $key -ieq '.portable-git-manifest.json') { throw 'Duplicate or reserved Git archive entry.' }
                $seen[$key]=$true
                $unixType=($entry.ExternalAttributes -shr 16) -band 0xF000
                if ($unixType -ne 0 -and $unixType -ne 0x8000 -and $unixType -ne 0x4000) { throw 'Git archive links or special files are not allowed.' }
                if ($entry.ExternalAttributes -band 0x400) { throw 'Git archive reparse entry rejected.' }
                $total += $entry.Length
                if ($total -gt 2147483648 -or $zip.Entries.Count -gt 100000) { throw 'Git expanded archive limit exceeded.' }
            }
            foreach ($entry in $zip.Entries) {
                $target=Join-Path $payload $entry.FullName
                if ($entry.FullName.EndsWith('/')) { New-PortableGitDirectory $target; continue }
                New-PortableGitDirectory (Split-Path $target)
                $source=$null; $dest=$null
                try {
                    $source=$entry.Open(); $dest=[IO.File]::Open($target,[IO.FileMode]::CreateNew)
                    $buffer=New-Object byte[] 65536; [long]$written=0
                    while (($n=$source.Read($buffer,0,$buffer.Length)) -gt 0) {
                        $written += $n
                        if ($written -gt $entry.Length) { throw 'Git ZIP entry length mismatch.' }
                        $dest.Write($buffer,0,$n)
                    }
                    if ($written -ne $entry.Length) { throw 'Truncated Git ZIP entry.' }
                } finally { if ($dest) {$dest.Dispose()}; if ($source) {$source.Dispose()} }
            }
        } finally { $zip.Dispose() }
        } else { throw 'Unsupported Git archive format.' }
        foreach ($required in Get-PortableGitRequiredFiles $Pin) { if (-not (Test-Path -LiteralPath (Join-Path $payload $required) -PathType Leaf)) { throw "Required Git file missing: $required" } }
        $records=@(Get-PortableGitFiles $payload | ForEach-Object {
            @{ path=$_.FullName.Substring($payload.Length+1).Replace('\','/'); sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
        })
        @{version=$Pin.version; url=$Pin.url; archiveSha256=$Pin.sha256; files=$records} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $payload '.portable-git-manifest.json') -Encoding UTF8
        [void](Assert-PortableGitPath $Layout.Runtime)
        if ($upgrade) {
            # Revalidate immediately before moving the old tree, then keep it
            # outside stage cleanup until new promotion has succeeded.
            [void](Test-PortableGitRuntime $Layout (Get-PortableGitLegacyPin))
            Assert-PortableGitInactive $Layout.Runtime
            $backup=Join-Path (Split-Path $Layout.Runtime) ('.git-previous-'+[Guid]::NewGuid().ToString('N'))
            [IO.Directory]::Move($Layout.Runtime,$backup)
            try { [IO.Directory]::Move($payload,$Layout.Runtime) }
            catch { [IO.Directory]::Move($backup,$Layout.Runtime); throw }
            $oldLayout=[pscustomobject]@{Runtime=$backup}
            [void](Test-PortableGitRuntime $oldLayout (Get-PortableGitLegacyPin))
            Remove-PortableGitStage $backup
        } else { [IO.Directory]::Move($payload,$Layout.Runtime) }
    } finally { Remove-PortableGitStage $stage }
}
function Install-PortableGitProxy($Layout) {
    $source=Join-Path $script:PortableGitScriptRoot 'portable-git-proxy.cs'
    [void](Assert-PortableGitPath $source)
    $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    New-PortableGitDirectory $Layout.Shims
    $exe=Join-Path $Layout.Shims 'git.exe'; $meta=Join-Path $Layout.Shims 'git.proxy.json'
    [void](Assert-PortableGitPath $exe); [void](Assert-PortableGitPath $meta)
    $metadataOnly=$false
    if ((Test-Path -LiteralPath $exe) -or (Test-Path -LiteralPath $meta)) {
        $provenance=Get-Content -LiteralPath $meta -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($provenance.sourceSha256 -ine $sourceHash -or $provenance.runtime -cne 'runtimes/git/cmd/git.exe') { throw 'Existing Git proxy is unknown or modified; refusing overwrite.' }
        if (Test-Path -LiteralPath $exe) {
            if ($provenance.exeSha256 -ine (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash) { throw 'Existing Git proxy is unknown or modified; refusing overwrite.' }
            return
        }
        # Recover only our own interrupted metadata-first publication. An
        # executable-only or mismatched state is never overwritten.
        $metadataOnly=$true
    }
    New-PortableGitDirectory $Layout.Tmp
    $stage=Join-Path $Layout.Tmp ('git-compiler-'+[Guid]::NewGuid().ToString('N'))
    New-PortableGitDirectory $stage
    $oldTemp=$env:TEMP; $oldTmp=$env:TMP; $process=$null
    try {
        $env:TEMP=$stage; $env:TMP=$stage
        $compiler=Join-Path ([Environment]::GetFolderPath('Windows')) 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
        [void](Assert-PortableGitPath $compiler)
        if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'Windows .NET Framework C# compiler is required.' }
        $built=Join-Path $stage 'git.exe'
        $si=New-Object Diagnostics.ProcessStartInfo
        $si.FileName=$compiler
        $si.Arguments='/noconfig /nologo /target:exe /platform:anycpu /optimize+ /out:"'+$built+'" "'+$source+'"'
        $si.WorkingDirectory=$stage; $si.UseShellExecute=$false; $si.CreateNoWindow=$true
        $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
        $process=New-Object Diagnostics.Process; $process.StartInfo=$si
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(45000)) { $process.Kill(); throw 'Private Git proxy compilation timed out.' }
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $built -PathType Leaf)) { throw ('Portable Git proxy compilation failed: '+$stdout.Result+$stderr.Result) }
        $newMeta=Join-Path $stage 'git.proxy.json'
        @{sourceSha256=$sourceHash; exeSha256=(Get-FileHash -LiteralPath $built -Algorithm SHA256).Hash; runtime='runtimes/git/cmd/git.exe'} | ConvertTo-Json | Set-Content -LiteralPath $newMeta -Encoding UTF8
        [void](Assert-PortableGitPath $exe); [void](Assert-PortableGitPath $meta)
        # Publish provenance first: interruption leaves a fail-closed, non-executable record.
        if ($metadataOnly) { [IO.File]::Replace($newMeta,$meta,(Join-Path $stage 'previous-proxy-metadata.json')) }
        else { [IO.File]::Move($newMeta,$meta) }
        [IO.File]::Move($built,$exe)
    } finally { if ($process) {$process.Dispose()}; $env:TEMP=$oldTemp; $env:TMP=$oldTmp; Remove-PortableGitStage $stage }
}
function Initialize-PortableGitMemoryTrust($Layout) {
    # exFAT has no recorded file owner. Trust only this app's memory subtree,
    # in its own HOME config. %(prefix) follows the pinned movable Git runtime.
    # No bare '*', drive-wide rule, host config, or workspace exemption.
    $git=Join-Path $Layout.Runtime 'cmd/git.exe'
    [void](Assert-PortableGitPath $git)
    foreach($spec in @(@('home','%(prefix)/../../../home/.letta/local/memfs/*'),@('profiles/herdr/home','%(prefix)/../../../profiles/herdr/home/.letta/local/memfs/*'))) {
        $privateHome=Join-Path $Layout.Data $spec[0]
        New-PortableGitDirectory $privateHome
        $config=Join-Path $privateHome '.gitconfig'
        [void](Assert-PortableGitPath $config)
        if(Test-Path -LiteralPath $config -PathType Container){throw 'Private Git config must be a regular file.'}
        function Invoke-PrivateMemoryConfig([string]$Arguments) {
            $si=[Diagnostics.ProcessStartInfo]::new();$si.FileName=$git;$si.Arguments=$Arguments
            $si.WorkingDirectory=$privateHome;$si.UseShellExecute=$false;$si.CreateNoWindow=$true
            $si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
            foreach($key in @($si.EnvironmentVariables.Keys)){if($key -match '^GIT_'){$si.EnvironmentVariables.Remove($key)}}
            $si.EnvironmentVariables['HOME']=$privateHome;$si.EnvironmentVariables['USERPROFILE']=$privateHome
            $si.EnvironmentVariables['GIT_CONFIG_GLOBAL']=$config;$si.EnvironmentVariables['GIT_CONFIG_NOSYSTEM']='1'
            $process=[Diagnostics.Process]::new();$process.StartInfo=$si
            try {
                $null=$process.Start();$o=$process.StandardOutput.ReadToEndAsync();$e=$process.StandardError.ReadToEndAsync()
                if(-not$process.WaitForExit(15000)){$process.Kill();throw 'Owned private Git config operation timed out.'}
                return [pscustomobject]@{exit=$process.ExitCode;output=$o.Result}
            } finally {$process.Dispose()}
        }
        $probe=Invoke-PrivateMemoryConfig ('-c "portable.memoryPath='+$spec[1]+'" config --path --get portable.memoryPath')
        if($probe.exit -ne 0 -or -not$probe.output.Trim().EndsWith('/*')){throw 'Cannot verify pinned Git prefix interpolation.'}
        $expanded=[IO.Path]::GetFullPath($probe.output.Trim().Substring(0,$probe.output.Trim().Length-2).Replace('/','\')).TrimEnd('\')
        $expected=[IO.Path]::GetFullPath((Join-Path $privateHome '.letta/local/memfs')).TrimEnd('\')
        if(-not[string]::Equals($expanded,$expected,[StringComparison]::OrdinalIgnoreCase)){throw 'Git memory trust escaped its private HOME; no config change.'}
        $current=Invoke-PrivateMemoryConfig ('config --file "'+$config+'" --get-all safe.directory')
        if($current.exit -notin @(0,1)){throw 'Private Git config could not be read; not overwriting it.'}
        if(@($current.output -split '\r?\n') -ccontains $spec[1]){continue}
        if(Test-Path -LiteralPath $config){
            $backup=$config+'.before-memfs-trust-'+[guid]::NewGuid().ToString('N')+'.bak'
            [void](Assert-PortableGitPath $backup);[IO.File]::Copy($config,$backup,$false)
        }
        $write=Invoke-PrivateMemoryConfig ('config --file "'+$config+'" --add safe.directory "'+$spec[1]+'"')
        if($write.exit -ne 0){throw 'Scoped private memory trust could not be written; no host config fallback.'}
    }
}

function Invoke-PortableGitInstall([string]$PackageRoot) {
    $layout=Get-PortableGitLayout $PackageRoot; $pin=Read-PortableGitPin
    New-PortableGitDirectory $layout.Tmp
    $lockPath=Join-Path $layout.Tmp 'portable-git-install.lock'
    [void](Assert-PortableGitPath $lockPath)
    $lock=$null
    try {
        $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        Install-PortableGitRuntime $layout $pin
        Install-PortableGitProxy $layout
        Initialize-PortableGitMemoryTrust $layout
        Write-Host "Portable Git ready under $($layout.Data)"
    } finally { if ($lock) {$lock.Dispose()} }
}
if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-PortableGitInstall $PackageRoot }
    catch { Write-Error "Portable Git installation failed: $($_.Exception.Message)"; exit 1 }
}
