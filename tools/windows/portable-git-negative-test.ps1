param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'install-portable-git.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$owned=Join-Path $workspace ('zig-out\portable-git-negative-'+[guid]::NewGuid().ToString('N'))
New-PortableGitDirectory $owned
$script:PortableGitSyntheticZip=$null;$script:PortableGitSyntheticDownloads=0
function Receive-PortableGitArchive([string]$Url,[string]$Destination){
    $script:PortableGitSyntheticDownloads++
    [IO.File]::Copy($script:PortableGitSyntheticZip,$Destination,$false)
}
function Assert([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
function Reject([scriptblock]$Code){$failed=$false;try{&$Code}catch{$failed=$true};Assert $failed 'Expected safe rejection.'}
function New-Fixture([string]$Name){
    $root=Join-Path $owned $Name;New-PortableGitDirectory (Join-Path $root 'bin')
    [IO.File]::WriteAllText((Join-Path $root 'bin\localterm-dev.exe'),'inert sentinel; never execute')
    Get-PortableGitLayout $root
}
function New-Zip([string[]]$ExtraNames){
    $zip=Join-Path $owned ([guid]::NewGuid().ToString('N')+'.zip')
    $archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
    try{
        foreach($name in @((Get-PortableGitRequiredFiles))+$ExtraNames){
            $entry=$archive.CreateEntry($name);$stream=$entry.Open()
            try{$bytes=[Text.Encoding]::UTF8.GetBytes('inert synthetic Git file; never execute');$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
        }
    }finally{$archive.Dispose()}
    $script:PortableGitSyntheticZip=$zip
    return [pscustomobject]@{version='synthetic';url='https://invalid.example/not-used.zip';sha256=(Get-FileHash -LiteralPath $zip).Hash;size=(Get-Item -LiteralPath $zip).Length}
}
$cases=New-Object 'Collections.Generic.List[string]'
function Case([string]$Label,[scriptblock]$Code){&$Code;$cases.Add($Label);Write-Output ('PASS '+$Label)}
Case 'relative-package-path-rejected' {Reject {Get-PortableGitLayout 'relative-root'}}
Case 'Windows-alias-and-traversal-names-rejected' {
    foreach($name in @('../escape','/absolute','C:/drive','a\b','a/../b','a./b','NUL.txt','CONIN$',('COM'+[char]0x00b9+'.txt'))){Reject {Assert-PortableGitEntry $name}}
}
Case 'synthetic-first-install-reuse-and-complete-manifest' {
    $script:GoodLayout=New-Fixture 'good';$script:GoodPin=New-Zip @()
    Install-PortableGitRuntime $script:GoodLayout $script:GoodPin
    $before=$script:PortableGitSyntheticDownloads
    Install-PortableGitRuntime $script:GoodLayout $script:GoodPin
    Assert ($before -eq $script:PortableGitSyntheticDownloads) 'Verified reuse downloaded again.'
    Assert (Test-PortableGitRuntime $script:GoodLayout $script:GoodPin) 'Fixture manifest did not verify.'
}
Case 'changed-runtime-file-rejected-without-redownload' {
    $file=Join-Path $script:GoodLayout.Runtime 'cmd\git.exe';$original=[IO.File]::ReadAllBytes($file)
    $before=$script:PortableGitSyntheticDownloads
    try{[IO.File]::WriteAllText($file,'tampered');Reject {Install-PortableGitRuntime $script:GoodLayout $script:GoodPin}}finally{[IO.File]::WriteAllBytes($file,$original)}
    Assert ($before -eq $script:PortableGitSyntheticDownloads) 'Tamper attempted a silent redownload/repair.'
}
Case 'extra-runtime-file-rejected' {
    $file=Join-Path $script:GoodLayout.Runtime 'untracked.txt'
    try{[IO.File]::WriteAllText($file,'unexpected');Reject {Test-PortableGitRuntime $script:GoodLayout $script:GoodPin}}finally{[IO.File]::Delete($file)}
}
Case 'archive-hash-fails-before-promotion-and-cleans-owned-stage' {
    $layout=New-Fixture 'bad-hash';$pin=New-Zip @();$pin.sha256=('0'*64)
    Reject {Install-PortableGitRuntime $layout $pin}
    Assert (-not(Test-Path -LiteralPath $layout.Runtime)) 'Bad digest promoted runtime.'
    Assert (@(Get-ChildItem -LiteralPath (Split-Path $layout.Runtime) -Filter '.git-stage-*').Count -eq 0) 'Owned bad-digest stage leaked.'
}
foreach($name in @('../escape.txt','bad./file','CON.txt','CMD/GIT.EXE','.portable-git-manifest.json')){
    Case ('unsafe-ZIP-rejected '+$name) {
        $layout=New-Fixture ([guid]::NewGuid().ToString('N'));$pin=New-Zip @($name)
        Reject {Install-PortableGitRuntime $layout $pin}
        Assert (-not(Test-Path -LiteralPath $layout.Runtime)) 'Unsafe archive promoted runtime.'
    }
}
Case 'junction-rejected-without-following-or-deleting-target' {
    $target=Join-Path $owned 'junction-target';New-PortableGitDirectory $target
    $sentinel=Join-Path $target 'owned-target-sentinel.txt';[IO.File]::WriteAllText($sentinel,'preserve')
    $link=Join-Path $script:GoodLayout.Runtime 'linked'
    $null=New-Item -ItemType Junction -Path $link -Target $target
    try{Reject {Test-PortableGitRuntime $script:GoodLayout $script:GoodPin};Assert (Test-Path -LiteralPath $sentinel) 'Junction target was touched.'}finally{[IO.Directory]::Delete($link)}
}
$result=[ordered]@{passed=$true;cases=@($cases.ToArray());owned_fixture=$owned;executables_started=$false;network_requests=$false;real_accounts=$false}
$result|ConvertTo-Json -Depth 4|Set-Content (Join-Path $owned 'results.json') -Encoding UTF8
Write-Output ('PORTABLE_GIT_NEGATIVE_RESULTS='+$owned)
