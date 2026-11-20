[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Run in Windows PowerShell 5.1 (local framework references)' }
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$assets = Join-Path $repo 'third_party/psreadline'
$pin = Get-Content -Raw (Join-Path $assets 'source-pin.json') | ConvertFrom-Json
$sdk = Join-Path $env:ProgramFiles "dotnet/sdk/$($pin.sdk)"
$csc = Join-Path $sdk 'Roslyn/bincore/csc.dll'
if (!(Test-Path -LiteralPath $csc)) { throw "Required SDK missing: $sdk" }
$dotnet = Join-Path $env:ProgramFiles 'dotnet/dotnet.exe'
$cache = Join-Path $env:LOCALAPPDATA 'Letta'
if (!(Test-Path -LiteralPath $cache -PathType Container)) { throw "Cache parent missing: $cache" }
if ((Get-Item -LiteralPath $cache).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse cache parent refused' }
$work = Join-Path $cache ('app-psreadline-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $work)
$zip = Join-Path $work 'upstream.zip'
Invoke-WebRequest -UseBasicParsing -Uri $pin.archiveUrl -OutFile $zip -TimeoutSec 60
if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $pin.archiveSha256) { throw 'Archive hash mismatch' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
    $root = "PSReadLine-$($pin.commit)/"
    $seen = @{}
    foreach ($entry in $archive.Entries) {
        $name = $entry.FullName
        if (!$name.StartsWith($root, [StringComparison]::Ordinal) -or $name.Contains('\') -or $name.Contains(':') -or $name -match '(^|/)\.\.?(/|$)') { throw "Unsafe archive path: $name" }
        if (($entry.ExternalAttributes -shr 16 -band 0xf000) -eq 0xa000) { throw 'Symlink archive entry refused' }
        if ($seen.ContainsKey($name)) { throw 'Duplicate archive entry refused' }
        $seen[$name] = $true
    }
    # Extract only the reviewed source/module inputs, never upstream build/config scripts.
    $src = Join-Path $work 'pristine'
    [void](New-Item -ItemType Directory $src)
    foreach ($entry in $archive.Entries) {
        $rel = $entry.FullName.Substring($root.Length)
        if ($rel -match '^PSReadLine/[^/]+\.(cs|resx|psd1|psm1|ps1xml|txt)$' -or $rel -eq 'LICENSE') {
            $leaf = [IO.Path]::GetFileName($rel)
            $dest = Join-Path $src $leaf
            if (Test-Path -LiteralPath $dest) { throw 'Extraction overwrite refused' }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $false)
        }
    }
} finally { $archive.Dispose() }
$framework = [Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
$sma = [System.Management.Automation.PSObject].Assembly.Location
$refs = @('mscorlib.dll','System.dll','System.Core.dll','Microsoft.CSharp.dll','System.Xml.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Runtime.InteropServices.RuntimeInformation.dll') | ForEach-Object { Join-Path $framework $_ }
$refs += $sma
foreach ($ref in $refs) { if (!(Test-Path -LiteralPath $ref)) { throw "Missing local reference $ref" } }
foreach ($variant in @('original','patched')) {
    $dir = Join-Path $work $variant
    [void](New-Item -ItemType Directory $dir)
    $source = Join-Path $dir 'source'
    [void](New-Item -ItemType Directory $source)
    Copy-Item -LiteralPath (Get-ChildItem -LiteralPath $src -Filter '*.cs').FullName -Destination $source
    Copy-Item -LiteralPath (Join-Path $assets 'BuildAssemblyInfo.cs') -Destination $source
    if ($variant -eq 'patched') {
        $render = Join-Path $source 'Render.cs'
        $text = [IO.File]::ReadAllText($render).Replace("`r`n","`n")
        $before = [IO.File]::ReadAllText((Join-Path $assets 'width-before.txt')).Replace("`r`n","`n").TrimEnd("`r","`n")
        $after = [IO.File]::ReadAllText((Join-Path $assets 'width-after.txt')).Replace("`r`n","`n").TrimEnd("`r","`n")
        if (($text.Split(@($before),[StringSplitOptions]::None)).Count -ne 2) { throw 'Patch anchor not unique' }
        [IO.File]::WriteAllText($render,$text.Replace($before,$after),[Text.UTF8Encoding]::new($false))
    }
    # resx contains string resources only; avoid arbitrary object deserialization.
    $xml = [xml][IO.File]::ReadAllText((Join-Path $src 'PSReadLineResources.resx'))
    $resource = Join-Path $dir 'PSReadLineResources.resources'
    $writer = [Resources.ResourceWriter]::new($resource)
    try {
        foreach ($data in $xml.root.data) {
            if ($data.HasAttribute('type') -or $data.HasAttribute('mimetype')) { throw 'Non-string resource refused' }
            $writer.AddResource([string]$data.name,[string]$data.value)
        }
        $writer.Generate()
    } finally { $writer.Dispose() }
    $module = Join-Path $dir 'PSReadLine'
    [void](New-Item -ItemType Directory $module)
    $dll = Join-Path $module 'Microsoft.PowerShell.PSReadLine2.dll'
    $argsFile = Join-Path $dir 'compile.rsp'
    $argsText = [IO.File]::ReadAllText((Join-Path $assets 'compiler.rsp')) + "`r`n"
    $argsText += '/out:"' + $dll + '"' + "`r`n"
    $argsText += '/resource:"' + $resource + '",Microsoft.PowerShell.PSReadLine.PSReadLineResources.resources' + "`r`n"
    foreach ($ref in $refs) { $argsText += '/reference:"' + $ref + '"' + "`r`n" }
    foreach ($file in (Get-ChildItem -LiteralPath $source -Filter '*.cs' | Sort-Object Name)) { $argsText += '"' + $file.FullName + '"' + "`r`n" }
    [IO.File]::WriteAllText($argsFile,$argsText)
    & $dotnet $csc /noconfig "@$argsFile"
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $variant exit $LASTEXITCODE" }
    foreach ($name in @('PSReadLine.psd1','PSReadLine.psm1','PSReadLine.format.ps1xml','License.txt')) { Copy-Item -LiteralPath (Join-Path $src $name) -Destination $module }
    Copy-Item -LiteralPath (Join-Path $assets 'LICENSE') -Destination (Join-Path $module 'UPSTREAM-LICENSE')
    $manifest = Join-Path $module 'PSReadLine.psd1'
    $text = [IO.File]::ReadAllText($manifest).Replace("Description = 'Great command line editing in the PowerShell console host'", "Description = 'App-owned unsigned source build ($variant); not a Microsoft-signed published release'")
    [IO.File]::WriteAllText($manifest,$text)
    $files = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $module -File -Recurse) {
        $relative = $file.FullName.Substring($module.Length + 1).Replace('\','/')
        $files[$relative] = (Get-FileHash -LiteralPath $file.FullName).Hash
    }
    $provenance = [ordered]@{variant=$variant;source=$pin;assembly=$dll;assemblySha256=(Get-FileHash $dll).Hash;manifest=$manifest;manifestSha256=(Get-FileHash $manifest).Hash;files=$files;compiler=(Get-FileHash $csc).Hash;references=@($refs | ForEach-Object { @{path=$_;sha256=(Get-FileHash $_).Hash} });patchBeforeSha256=(Get-FileHash (Join-Path $assets 'width-before.txt')).Hash;patchAfterSha256=(Get-FileHash (Join-Path $assets 'width-after.txt')).Hash}
    $provenance | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $module 'build-provenance.json') -Encoding UTF8
    & "$env:WINDIR/System32/WindowsPowerShell/v1.0/powershell.exe" -NoLogo -NoProfile -NonInteractive -File (Join-Path $assets 'test-width.ps1') -Manifest $manifest -Variant $variant
    if ($LASTEXITCODE -ne 0) { throw "Width test failed: $variant exit $LASTEXITCODE" }
    Write-Output "MANIFEST $variant $manifest"
}
Write-Output "BUILD_ROOT $work"
