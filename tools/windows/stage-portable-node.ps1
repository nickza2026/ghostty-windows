param(
    [string]$PinPath = (Join-Path $PSScriptRoot '..\..\third_party\node\source-pin.json'),
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$pin = Get-Content -LiteralPath $PinPath -Raw | ConvertFrom-Json
if ($pin.version -notmatch '^v24\.\d+\.\d+$' -or $pin.platform -ne 'win-x64' -or $pin.archiveSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid maintained LTS pin.' }
$archiveName = "node-$($pin.version)-win-x64.zip"
$url = "https://nodejs.org/dist/$($pin.version)/$archiveName"
if ($pin.archiveUrl -cne $url -or $pin.shasumsUrl -cne "https://nodejs.org/dist/$($pin.version)/SHASUMS256.txt") { throw 'Pin must use official exact archive URLs.' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $workspace ('zig-out\node-stage-' + [Guid]::NewGuid().ToString('N')) }
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $output.StartsWith((Join-Path $workspace 'zig-out')+'\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Output must stay in workspace zig-out.' }
for ($p = $output; $p -and $p.Length -ge $workspace.Length; $p = [IO.Path]::GetDirectoryName($p)) {
    if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse output path refused.' }
}
if (Test-Path -LiteralPath $output) { throw 'Output already exists; refusing overwrite.' }
$null = [IO.Directory]::CreateDirectory($output)
$zipPath = Join-Path $output $archiveName
Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 180 -OutFile $zipPath
if ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ine $pin.archiveSha256) { throw 'Archive digest mismatch.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
$rootName = "node-$($pin.version)-win-x64/"
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$total = 0L
try {
    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName
        if (-not $name.StartsWith($rootName, [StringComparison]::Ordinal) -or $name.Contains('\') -or $name.Contains(':') -or $name -match '(^|/)(\.|\.\.)(/|$)' -or $name -match '[ .](/|$)' -or -not $seen.Add($name.TrimEnd('/'))) { throw "Unsafe/duplicate ZIP path: $name" }
        $mode = ($entry.ExternalAttributes -shr 16) -band 0xF000
        if ($mode -eq 0xA000 -or ($entry.ExternalAttributes -band 0x400)) { throw 'ZIP link/reparse entry refused.' }
        $total += $entry.Length
        if ($total -gt 1GB -or $zip.Entries.Count -gt 30000) { throw 'Archive expansion limit exceeded.' }
    }
    $payload = Join-Path $output 'payload'
    $null = [IO.Directory]::CreateDirectory($payload)
    foreach ($entry in $zip.Entries) {
        $relative = $entry.FullName.Substring($rootName.Length)
        if (-not $relative) { continue }
        $dest = [IO.Path]::GetFullPath((Join-Path $payload $relative))
        if (-not $dest.StartsWith($payload+'\', [StringComparison]::OrdinalIgnoreCase)) { throw 'ZIP path escaped payload.' }
        if ($entry.FullName.EndsWith('/')) { $null = [IO.Directory]::CreateDirectory($dest); continue }
        $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $false)
    }
} finally { $zip.Dispose() }
$identities = @{}
foreach ($required in @('node.exe','node_modules/npm/bin/npm-cli.js','node_modules/npm/bin/npx-cli.js','npm.cmd','npx.cmd','LICENSE')) { if (-not (Test-Path -LiteralPath (Join-Path $payload $required) -PathType Leaf)) { throw "Missing payload: $required" } }
foreach ($file in Get-ChildItem -LiteralPath $payload -File -Recurse) {
    $relative = $file.FullName.Substring($payload.Length+1).Replace('\','/')
    $identities[$relative] = (Get-FileHash -LiteralPath (Join-Path $payload $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
}
[ordered]@{ schema=1; version=$pin.version; archiveUrl=$url; archiveSha256=$pin.archiveSha256; licenseFile='LICENSE'; nodeExe='node.exe'; npmCli='node_modules/npm/bin/npm-cli.js'; npxCli='node_modules/npm/bin/npx-cli.js'; files=$identities } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $payload 'provenance.json') -Encoding UTF8
Write-Output "NODE_SOURCE=$payload"
Write-Output "NODE_SHA256=$($identities['node.exe'])"
