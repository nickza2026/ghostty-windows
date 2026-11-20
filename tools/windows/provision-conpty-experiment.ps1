param([string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\zig-out\conpty-ab\bin'))
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$output = [IO.Path]::GetFullPath($OutputDirectory)
$allowed = (Join-Path $workspace 'zig-out') + [IO.Path]::DirectorySeparatorChar
if (-not $output.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Experiment runtime must stay under this workspace zig-out.' }
$version = '1.25.260930003'
$hash = '02B07B349AF66D801159BDF9E440D4A1CE78BB951F37FC8609731665AFDAE7EE'
$cache = Join-Path $env:LOCALAPPDATA ('Letta\build-cache\ghostty-windows\conpty\' + $version)
$null = New-Item -ItemType Directory -Path $cache -Force
$package = Join-Path $cache ('microsoft.windows.console.conpty.' + $version + '.nupkg')
$url = 'https://api.nuget.org/v3-flatcontainer/microsoft.windows.console.conpty/' + $version + '/microsoft.windows.console.conpty.' + $version + '.nupkg'
if (-not (Test-Path -LiteralPath $package)) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $package }
if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ne $hash) { throw 'Pinned Microsoft ConPTY package hash mismatch.' }
for ($p = $output; $p -and $p.Length -ge $workspace.Length; $p = [IO.Path]::GetDirectoryName($p)) {
    if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Refusing runtime extraction through a reparse point.' }
}
$null = New-Item -ItemType Directory -Path $output -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($package)
try {
    $entries = @{
        'runtimes/win-x64/native/conpty.dll' = 'conpty.dll'
        'build/native/runtimes/x64/OpenConsole.exe' = 'OpenConsole.exe'
        'Microsoft.Windows.Console.ConPTY.nuspec' = 'ConPTY-package.nuspec'
        'inc/conpty.h' = 'ConPTY-api.h'
    }
    foreach ($name in $entries.Keys) {
        $entry = $zip.GetEntry($name)
        if (-not $entry) { throw "Missing pinned package entry: $name" }
        $dest = Join-Path $output $entries[$name]
        if (Test-Path -LiteralPath $dest) {
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $entryHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') } finally { $stream.Dispose(); $sha.Dispose() }
            if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $entryHash) { throw "Refusing to overwrite nonmatching experiment file: $dest" }
        } else { [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $false) }
    }
} finally { $zip.Dispose() }
$license = Join-Path $output 'ConPTY-LICENSE.txt'
if (-not (Test-Path -LiteralPath $license)) { Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/microsoft/terminal/main/LICENSE' -OutFile $license }
$files = @()
foreach ($name in @('conpty.dll','OpenConsole.exe')) {
    $path = Join-Path $output $name
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw "Microsoft runtime signature not valid: $name ($($signature.Status))" }
    $files += [ordered]@{ name = $name; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash; signature = [string]$signature.Status; signer = $signature.SignerCertificate.Subject }
}
[ordered]@{ package = 'Microsoft.Windows.Console.ConPTY'; version = $version; package_sha256 = $hash; source = $url; license = 'MIT'; experimental_only = $true; files = $files } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'ConPTY-experiment.json') -Encoding UTF8
Write-Output "Pinned, Microsoft-signed app-local ConPTY experiment provisioned: $output"
