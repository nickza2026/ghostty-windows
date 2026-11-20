param([string]$FixtureRoot,[string]$ReadlineSource)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $FixtureRoot) {
    $FixtureRoot = Join-Path $workspace ('zig-out\herdr-launcher-tests-' + [guid]::NewGuid().ToString('N'))
}
$fixture = [IO.Path]::GetFullPath($FixtureRoot)
if (-not $fixture.StartsWith((Join-Path $workspace 'zig-out\'), [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $fixture)) {
    throw 'Tests require a new owned fixture below workspace zig-out.'
}
$null = [IO.Directory]::CreateDirectory($fixture)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$script:results = [Collections.Generic.List[object]]::new()
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Case([string]$Name, [scriptblock]$Body) {
    & $Body
    $script:results.Add([ordered]@{ name=$Name; passed=$true })
    Write-Output ('PASS ' + $Name)
}
function New-TestPackage([string]$Name) {
    $root = Join-Path $fixture $Name
    $null = [IO.Directory]::CreateDirectory((Join-Path $root 'bin\portable-data'))
    $null = [IO.Directory]::CreateDirectory((Join-Path $root 'support'))
    [IO.File]::WriteAllText((Join-Path $root 'bin\localterm-dev.exe'), 'owned fixture, never executed')
    [IO.File]::Copy((Join-Path $PSScriptRoot 'herdr-portable.ps1'), (Join-Path $root 'support\herdr-portable.ps1'))
    [IO.File]::Copy((Join-Path $PSScriptRoot 'herdr-private-shell.cs'), (Join-Path $root 'support\herdr-private-shell.cs'))
    [IO.File]::Copy((Join-Path $PSScriptRoot 'run-herdr-portable.cmd'), (Join-Path $root 'Run-Herdr.cmd'))
    [IO.File]::Copy((Join-Path $workspace 'third_party\herdr\source-pin.json'), (Join-Path $root 'support\herdr-source-pin.json'))
    return $root
}
function New-TestZip([string]$Path, [Collections.IDictionary]$Entries) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($name in $Entries.Keys) {
            $entry = $zip.CreateEntry([string]$name, [IO.Compression.CompressionLevel]::Optimal)
            $out = $entry.Open()
            try {
                $bytes = $Entries[$name]
                if ($bytes -isnot [byte[]]) { $bytes = [Text.Encoding]::UTF8.GetBytes([string]$bytes) }
                $out.Write($bytes, 0, $bytes.Length)
            } finally { $out.Dispose() }
        }
    } finally { $zip.Dispose(); $stream.Dispose() }
}
function Invoke-OwnedProcess([string]$Executable, [string]$Arguments, [string]$Directory, [int]$TimeoutMs=30000, [string]$InputText) {
    $si = [Diagnostics.ProcessStartInfo]::new()
    $si.FileName=$Executable; $si.Arguments=$Arguments; $si.WorkingDirectory=$Directory
    $si.UseShellExecute=$false; $si.CreateNoWindow=$true
    $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
    if ($InputText) { $si.RedirectStandardInput=$true }
    $process = [Diagnostics.Process]::new(); $process.StartInfo=$si
    try {
        $null=$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if ($InputText) { $process.StandardInput.WriteLine($InputText); $process.StandardInput.Close() }
        if (-not $process.WaitForExit($TimeoutMs)) { $process.Kill(); throw 'Owned non-GUI fixture process timed out.' }
        return [pscustomobject]@{ exit=$process.ExitCode; stdout=$stdout.Result; stderr=$stderr.Result }
    } finally { $process.Dispose() }
}
function Snapshot-Environment {
    $result=@{}; foreach($entry in Get-ChildItem Env:) { $result[$entry.Name]=$entry.Value }; return $result
}
function Restore-Environment($Snapshot) {
    foreach($entry in @(Get-ChildItem Env:)) { if (-not $Snapshot.ContainsKey($entry.Name)) { [Environment]::SetEnvironmentVariable($entry.Name,$null,'Process') } }
    foreach($key in $Snapshot.Keys) { [Environment]::SetEnvironmentVariable($key,$Snapshot[$key],'Process') }
}

function Reject([scriptblock]$Body, [string]$Message) {
    $rejected=$false
    try { & $Body | Out-Null } catch { $rejected=$true }
    Assert $rejected $Message
}
$initialEnvironment = Snapshot-Environment
$userPathBefore=[Environment]::GetEnvironmentVariable('Path','User')
$machinePathBefore=[Environment]::GetEnvironmentVariable('Path','Machine')
$source=Join-Path $PSScriptRoot 'herdr-portable.ps1'
. $source
$productionPin=Read-HerdrPin
$script:fixturePin=$productionPin | ConvertTo-Json | ConvertFrom-Json
$script:receiveCount=0
$script:fixtureArchive=$null
# Dot-source-only test doubles: the shipped entrypoint has no such overrides.
function Read-HerdrPin { return $script:fixturePin }
function Receive-HerdrArchive([string]$Url,[string]$Destination) {
    $script:receiveCount++
    [IO.File]::Copy($script:fixtureArchive,$Destination,$false)
}
function Use-Archive([string]$Path) {
    $script:fixtureArchive=$Path
    $script:fixturePin.sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
try {
    $env:TEMP=$fixture; $env:TMP=$fixture
    $stub=Join-Path $fixture 'fixture-herdr.exe'
    $stubCode=@'
using System;
using System.Collections.Generic;
using System.IO;
using System.Web.Script.Serialization;
public static class PortableHerdrFixture {
    public static int Main(string[] args) {
        var data=new Dictionary<string,string>();
        foreach(var key in new[]{"HOME","USERPROFILE","APPDATA","LOCALAPPDATA","TEMP","TMP","XDG_CONFIG_HOME","XDG_STATE_HOME","XDG_CACHE_HOME","CODEX_HOME","LETTA_HOME","LETTA_LOCAL_BACKEND_DIR","NPM_CONFIG_PREFIX","NPM_CONFIG_CACHE","HERDR_SESSION","HERDR_CONFIG_PATH","HERDR_SOCKET_PATH","HERDR_CLIENT_SOCKET_PATH","PATH"})
            data[key]=Environment.GetEnvironmentVariable(key);
        data["secretPresent"]=(Environment.GetEnvironmentVariable("OPENAI_API_KEY")!=null).ToString();
        data["argv"]=new JavaScriptSerializer().Serialize(args);
        Directory.CreateDirectory(data["APPDATA"]);
        File.WriteAllText(Path.Combine(data["APPDATA"],"fixture-env.json"),new JavaScriptSerializer().Serialize(data));
        Console.WriteLine("synthetic Herdr fixture; no server or provider");
        return Array.IndexOf(args,"--fixture-exit")>=0 ? 37 : 0;
    }
}
'@
    Add-Type -TypeDefinition $stubCode -ReferencedAssemblies @('System.dll','System.Web.Extensions.dll') -OutputAssembly $stub -OutputType ConsoleApplication
    $entries=[ordered]@{}
    foreach($required in Get-HerdrRequiredFiles) { $entries[$required]='synthetic fixture, not a vendor binary' }
    $entries['herdr.exe']=[IO.File]::ReadAllBytes($stub)
    $goodZip=Join-Path $fixture 'valid-fixture.zip'
    New-TestZip $goodZip $entries
    Use-Archive $goodZip

    Case 'source-and-packager-PS51-syntax' {
        foreach($path in @($source,(Join-Path $PSScriptRoot 'package-portable.ps1'),(Join-Path $PSScriptRoot 'prepare-herdr-programs.ps1'))) {
            $tokens=$null; $parseErrors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
            Assert ($parseErrors.Count -eq 0) 'PowerShell parser errors.'
        }
    }
    Case 'missing-package-sentinel-rejected' {
        Reject { Get-HerdrPortableLayout (Join-Path $fixture 'missing') } 'Missing package marker accepted.'
        Reject { Get-HerdrPortableLayout 'relative-package' } 'Relative package path accepted.'
    }
    $goodRoot=New-TestPackage 'valid package'
    $goodLayout=Get-HerdrPortableLayout $goodRoot
    Case 'shell-generation-does-not-reattach-legacy-live-panes' {
        Assert ($goodLayout.Session -match '^portable-[a-f0-9]{24}-shell-v3$') 'Default launcher still reuses the pre-v3 server and its live host-PATH panes.'
        Assert ($goodLayout.LegacySession -match '^portable-[a-f0-9]{24}$' -and $goodLayout.LegacySession -ne $goodLayout.Session) 'Legacy session must remain separately addressable, not stopped or deleted.'
        Assert ((Get-HerdrPortableLayout $goodRoot).Session -ceq $goodLayout.Session) 'Same build generation creates a new daemon on every launch.'
    }
    Case 'first-install-full-manifest-and-notices' {
        $before=$script:receiveCount
        $installed=Install-HerdrPortablePayload $goodLayout
        Assert ($installed -eq $goodLayout.App) 'Wrong install directory.'
        Assert ($script:receiveCount -eq $before+1) 'First install did not use exactly one download.'
        Assert (Test-HerdrInstalledPayload $goodLayout) 'Installed manifest does not verify.'
        foreach($required in Get-HerdrRequiredFiles) { Assert (Test-Path -LiteralPath (Join-Path $installed $required)) 'Missing bundled ConPTY/license file.' }
        Assert (@(Get-ChildItem -LiteralPath $goodLayout.Apps -Force|Where-Object{$_.Name -like '.stage-*' -or $_.Name -like '.download-*'}).Count -eq 0) 'Owned install temporary files leaked.'
    }
    Case 'offline-reuse-preserves-config-and-account-sentinels' {
        $private=Join-Path $goodLayout.Profile 'home\.codex'
        $null=[IO.Directory]::CreateDirectory($private)
        $sentinel=Join-Path $private 'auth.json'
        [IO.File]::WriteAllText($sentinel,'owned synthetic account sentinel, never a credential')
        $beforeHash=(Get-FileHash -LiteralPath $sentinel).Hash
        $before=$script:receiveCount
        $null=Install-HerdrPortablePayload $goodLayout
        Assert ($script:receiveCount -eq $before) 'Valid reuse unexpectedly downloaded.'
        Assert ((Get-FileHash -LiteralPath $sentinel).Hash -eq $beforeHash) 'Existing private account sentinel changed.'
    }
    Case 'environment-and-server-routing-private-no-host-secrets' {
        $snapshot=Snapshot-Environment
        try {
            $env:HERDR_SOCKET_PATH='C:\synthetic-host\api.sock'
            $env:HERDR_CLIENT_SOCKET_PATH='C:\synthetic-host\client.sock'
            $env:HERDR_CONFIG_PATH='C:\synthetic-host\config.toml'
            $env:CODEX_HOME='C:\synthetic-host\codex'
            $env:OPENAI_API_KEY='synthetic-test-not-a-real-secret'
            $env:NODE_OPTIONS='--synthetic-invalid-option'
            $env:MEMORY_DIR='C:\synthetic-host\memory'
            $env:PATH='C:\synthetic-host\bin;'+$env:PATH
            Set-HerdrPrivateEnvironment $goodLayout
            foreach($name in @('HOME','USERPROFILE','APPDATA','LOCALAPPDATA','TEMP','TMP','XDG_CONFIG_HOME','XDG_STATE_HOME','XDG_CACHE_HOME','CODEX_HOME','LETTA_HOME','LETTA_LOCAL_BACKEND_DIR','NPM_CONFIG_PREFIX','NPM_CONFIG_CACHE')) {
                Assert ([Environment]::GetEnvironmentVariable($name,'Process').StartsWith($goodLayout.Profile,[StringComparison]::OrdinalIgnoreCase)) ('Non-private environment target: '+$name)
            }
            foreach($name in @('HERDR_SOCKET_PATH','HERDR_CLIENT_SOCKET_PATH','OPENAI_API_KEY','NODE_OPTIONS','MEMORY_DIR')) {
                Assert ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name,'Process'))) ('Inherited injection retained: '+$name)
            }
            Assert (-not $env:PATH.Contains('synthetic-host')) 'Host PATH retained.'
            Assert ($env:HERDR_SESSION -eq $goodLayout.Session) 'Wrong private session.'
            $output=& (Join-Path $goodLayout.App 'herdr.exe')
            Assert ($LASTEXITCODE -eq 0) 'Synthetic executable launch failed.'
            $proof=Get-Content -LiteralPath (Join-Path $env:APPDATA 'fixture-env.json') -Raw|ConvertFrom-Json
            Assert ($proof.CODEX_HOME -eq $env:CODEX_HOME -and $proof.secretPresent -eq 'False') 'Child environment does not match private setup.'
        } finally { Restore-Environment $snapshot }
    }
    Case 'absolute-launch-exit-code-propagation' {
        $snapshot=Snapshot-Environment
        try {
            Invoke-HerdrPortableMain -PackageRoot $goodRoot -HerdrArguments @('--fixture-exit') | Out-Null
            Assert ($script:HerdrPortableExitCode -eq 37) 'Child exit code not propagated.'
            $dispatch=Get-Content -LiteralPath (Join-Path $env:APPDATA 'fixture-env.json') -Raw|ConvertFrom-Json
            $argv=ConvertFrom-Json -InputObject $dispatch.argv
            Assert ($argv.Count -ge 2 -and $argv[0] -ceq '--session' -and $argv[1] -ceq $goodLayout.Session) 'Normal launch did not explicitly route away from the old daemon.'
        } finally { Restore-Environment $snapshot }
    }
    Case 'private-shell-NoProfile-bootstrap-and-private-history' {
        $snapshot=Snapshot-Environment
        try {
            # Exercise the real shipped module, not only the inbox fallback.
            # -NoExit autoload plus a forced second import used to duplicate cmdlets.
            if (-not $ReadlineSource) { $ReadlineSource=Join-Path $workspace 'zig-out\portable-packages\localterm-portable-tools-20261027\bin\powershell\PSReadLine' }
            if (-not (Test-Path -LiteralPath (Join-Path $ReadlineSource 'PSReadLine.psd1'))) { throw 'Bundled Readline regression resource missing; supply -ReadlineSource.' }
            $readlineDestination=Join-Path $goodRoot 'bin\powershell\PSReadLine'
            foreach($file in Get-HerdrTreeFiles $ReadlineSource) {
                $destination=Join-Path $readlineDestination $file.FullName.Substring($ReadlineSource.Length+1)
                $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
                [IO.File]::Copy($file.FullName,$destination,$false)
            }
            Set-HerdrPrivateEnvironment $goodLayout
            Set-HerdrPrivateShell $goodLayout
            $shim=Join-Path $goodLayout.Data 'apps\herdr-shell\v3\herdr-private-shell.exe'
            $command=@'
[pscustomobject]@{noProfile=([Environment]::CommandLine -match '-NoProfile');history=(Get-PSReadLineOption).HistorySavePath;home=$HOME;codex=$env:CODEX_HOME;assembly=[Microsoft.PowerShell.PSConsoleReadLine].Assembly.Location}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $env:APPDATA 'shell-bootstrap-proof.json') -Encoding UTF8;exit 0
'@
            $run=Invoke-OwnedProcess $shim '' $goodLayout.Profile 30000 $command
            Assert ($run.exit -eq 0) ('Private default shell failed: '+$run.stderr)
            $proof=Get-Content -LiteralPath (Join-Path $env:APPDATA 'shell-bootstrap-proof.json') -Raw|ConvertFrom-Json
            Assert $proof.noProfile 'PowerShell loaded without -NoProfile.'
            Assert ($proof.history.StartsWith($goodLayout.Profile,[StringComparison]::OrdinalIgnoreCase)) 'Shell history is not private.'
            Assert ($proof.home -eq $env:HOME -and $proof.codex -eq $env:CODEX_HOME) 'Shell bootstrap retained host HOME/account path.'
            Assert ($proof.assembly.StartsWith($readlineDestination,[StringComparison]::OrdinalIgnoreCase)) 'Inbox assembly bound instead of the bundled Readline DLL.'
            $config=$env:HERDR_CONFIG_PATH
            $before=(Get-FileHash -LiteralPath $config).Hash
            Set-HerdrPrivateShell $goodLayout
            Assert ((Get-FileHash -LiteralPath $config).Hash -eq $before) 'Existing private config rewritten.'
        } finally { Restore-Environment $snapshot }
    }
    Case 'private-npm-CLI-precedes-other-profile-shim' {
        $snapshot=Snapshot-Environment
        try {
            $shared=Join-Path $goodLayout.Data 'shims'; $null=[IO.Directory]::CreateDirectory($shared)
            [IO.File]::WriteAllText((Join-Path $shared 'letta.cmd'),'@echo wrong-profile')
            Set-HerdrPrivateEnvironment $goodLayout
            [IO.File]::WriteAllText((Join-Path $env:NPM_CONFIG_PREFIX 'letta.cmd'),'@echo correct-private-profile')
            Assert ((Get-Command letta.cmd -CommandType Application|Select-Object -First 1).Source.StartsWith($env:NPM_CONFIG_PREFIX,[StringComparison]::OrdinalIgnoreCase)) 'Shared shim shadows newly installed private CLI.'
        } finally { Restore-Environment $snapshot }
    }
    Case 'foreign-profile-sentinel-not-read-or-modified' {
        $foreign=Join-Path $fixture 'foreign-main-profile'
        $null=[IO.Directory]::CreateDirectory($foreign)
        $sentinel=Join-Path $foreign 'owned-synthetic-sentinel.txt'
        [IO.File]::WriteAllText($sentinel,'must not migrate or modify')
        $hash=(Get-FileHash -LiteralPath $sentinel).Hash
        $snapshot=Snapshot-Environment
        try {
            $env:HOME=$foreign; $env:USERPROFILE=$foreign; $env:CODEX_HOME=$foreign
            Set-HerdrPrivateEnvironment $goodLayout
            Assert ((Get-FileHash -LiteralPath $sentinel).Hash -eq $hash) 'Foreign sentinel changed.'
            Assert (-not (Test-Path -LiteralPath (Join-Path $goodLayout.Profile 'home\owned-synthetic-sentinel.txt'))) 'Foreign sentinel copied.'
        } finally { Restore-Environment $snapshot }
    }
    Case 'corrupt-installed-binary-rejected-without-redownload' {
        $binary=Join-Path $goodLayout.App 'herdr.exe'; $bytes=[IO.File]::ReadAllBytes($binary)
        try {
            [IO.File]::WriteAllText($binary,'corrupted fixture')
            $before=$script:receiveCount
            Reject { Install-HerdrPortablePayload $goodLayout } 'Corrupt runtime accepted.'
            Assert ($script:receiveCount -eq $before) 'Corrupt existing runtime was overwritten/redownloaded.'
        } finally { [IO.File]::WriteAllBytes($binary,$bytes) }
    }
    Case 'unexpected-installed-file-rejected' {
        $extra=Join-Path $goodLayout.App 'unexpected.txt'
        try { [IO.File]::WriteAllText($extra,'unexpected'); Reject { Test-HerdrInstalledPayload $goodLayout } 'Untracked file accepted.' }
        finally { [IO.File]::Delete($extra) }
    }
    Case 'hash-mismatch-fails-before-promotion-and-cleans-owned-temp' {
        $root=New-TestPackage 'hash failure'; $layout=Get-HerdrPortableLayout $root
        $old=$script:fixturePin.sha256; $script:fixturePin.sha256='0'*64
        try {
            Reject { Install-HerdrPortablePayload $layout } 'Archive digest mismatch accepted.'
            Assert (-not (Test-Path -LiteralPath $layout.App)) 'Failed archive was promoted.'
            Assert (@(Get-ChildItem -LiteralPath $layout.Apps -Force|Where-Object{$_.Name -like '.stage-*' -or $_.Name -like '.download-*'}).Count -eq 0) 'Failed download not cleaned.'
        } finally { $script:fixturePin.sha256=$old }
    }
    foreach($unsafe in @('../escape.txt','/absolute.txt','C:/drive.txt','bad\backslash.txt','bad./file.txt','CON.txt','NUL','aux/file.txt','folder/file:stream','folder//file.txt','.portable-manifest.json','HERDR.EXE')) {
        $unsafeName=$unsafe
        Case ('unsafe-ZIP-rejected '+$unsafeName) {
            # PowerShell [ordered] keys fold case and would replace herdr.exe,
            # rather than actually create the duplicate HERDR.EXE ZIP entry.
            $bad=[Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
            foreach($key in $entries.Keys) { $bad[$key]=$entries[$key] }; $bad[$unsafeName]='unsafe fixture'
            $zip=Join-Path $fixture ('bad-'+[guid]::NewGuid().ToString('N')+'.zip')
            New-TestZip $zip $bad; Use-Archive $zip
            $layout=Get-HerdrPortableLayout (New-TestPackage ('bad-'+[guid]::NewGuid().ToString('N')))
            Reject { Install-HerdrPortablePayload $layout } ('Unsafe archive accepted: '+$unsafeName)
            Assert (-not (Test-Path -LiteralPath $layout.App)) 'Unsafe archive promoted.'
        }
    }
    Case 'missing-required-conpty-file-rejected' {
        $bad=[ordered]@{}; foreach($key in $entries.Keys) { if($key -ne 'conpty/conpty.dll') { $bad[$key]=$entries[$key] } }
        $zip=Join-Path $fixture 'incomplete.zip'; New-TestZip $zip $bad; Use-Archive $zip
        $layout=Get-HerdrPortableLayout (New-TestPackage 'incomplete')
        Reject { Install-HerdrPortablePayload $layout } 'Incomplete ConPTY archive accepted.'
    }
    Use-Archive $goodZip
    Case 'exclusive-install-lock-fails-fast' {
        $layout=Get-HerdrPortableLayout (New-TestPackage 'locked')
        $null=[IO.Directory]::CreateDirectory($layout.Apps)
        $lock=[IO.File]::Open((Join-Path $layout.Apps '.install.lock'),[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try { Reject { Install-HerdrPortablePayload $layout } 'Concurrent install lock ignored.' }
        finally { $lock.Dispose() }
    }
    Case 'private-profile-file-collision-fails-closed' {
        $layout=Get-HerdrPortableLayout (New-TestPackage 'profile collision')
        $null=[IO.Directory]::CreateDirectory($layout.Profile)
        [IO.File]::WriteAllText((Join-Path $layout.Profile 'home'),'owned synthetic file; not a directory')
        $snapshot=Snapshot-Environment
        try { Reject { Set-HerdrPrivateEnvironment $layout } 'Invalid profile directory accepted.' }
        finally { Restore-Environment $snapshot }
    }
    Case 'private-Node-full-hashes-and-reparse-checks-retained' {
        $layout=Get-HerdrPortableLayout (New-TestPackage 'node validation')
        $node=Join-Path $layout.Data 'runtimes\node'
        $files=[ordered]@{}
        foreach($rel in @('node.exe','node_modules/npm/bin/npm-cli.js','node_modules/npm/bin/npx-cli.js','npm.cmd','npx.cmd','LICENSE')) {
            $file=Join-Path $node $rel; $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))
            [IO.File]::WriteAllText($file,'non-executable private Node validation fixture')
            $files[$rel]=(Get-FileHash -LiteralPath $file).Hash
        }
        @{files=$files}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $node 'provenance.json') -Encoding UTF8
        $snapshot=Snapshot-Environment
        try {
            Set-HerdrPrivateEnvironment $layout
            [IO.File]::WriteAllText((Join-Path $node 'node.exe'),'changed')
            Reject { Set-HerdrPrivateEnvironment $layout } 'Changed tracked Node file accepted.'
            [IO.File]::WriteAllText((Join-Path $node 'node.exe'),'non-executable private Node validation fixture')
            $target=Join-Path $fixture 'node-link-target'; $null=[IO.Directory]::CreateDirectory($target)
            $link=Join-Path $node 'linked-dir'; $null=New-Item -ItemType Junction -Path $link -Target $target
            try { Reject { Set-HerdrPrivateEnvironment $layout } 'Node descendant junction accepted.' }
            finally { [IO.Directory]::Delete($link) }
        } finally { Restore-Environment $snapshot }
    }
    Case 'junction-is-rejected-without-following-or-deleting-target' {
        $root=New-TestPackage 'junction'
        $outside=Join-Path $fixture 'junction-target'; $null=[IO.Directory]::CreateDirectory($outside)
        $sentinel=Join-Path $outside 'owned-target-sentinel.txt'; [IO.File]::WriteAllText($sentinel,'preserve')
        $link=Join-Path $root 'bin\portable-data\profiles'
        $null=New-Item -ItemType Junction -Path $link -Target $outside
        try {
            $layout=Get-HerdrPortableLayout $root
            Reject { Set-HerdrPrivateEnvironment $layout } 'Profile junction accepted.'
            Assert ([IO.File]::ReadAllText($sentinel) -eq 'preserve') 'Junction target changed.'
        } finally { [IO.Directory]::Delete($link) }
    }
    Case 'whole-package-relocation-reuses-manifest-and-private-root' {
        $oldSession=$goodLayout.Session
        $moved=Join-Path $fixture ('moved with spaces '+[char]0x0E44+[char]0x0E17+[char]0x0E22)
        [IO.Directory]::Move($goodRoot,$moved)
        $layout=Get-HerdrPortableLayout $moved
        Assert (Test-HerdrInstalledPayload $layout) 'Manifest cannot be reused after relocation.'
        Assert ($layout.Session -ne $oldSession) 'Relocated package retains old endpoint identity.'
        $snapshot=Snapshot-Environment
        try {
            Set-HerdrPrivateEnvironment $layout
            Assert ($env:HOME.StartsWith($moved,[StringComparison]::OrdinalIgnoreCase)) 'Relocation retains old profile path.'
            Assert (-not $env:PATH.Contains($goodRoot)) 'Relocation retains old PATH.'
        } finally { Restore-Environment $snapshot }
    }
    Case 'no-Windows-User-or-Machine-PATH-changes' {
        Assert ([Environment]::GetEnvironmentVariable('Path','User') -ceq $userPathBefore) 'Windows User PATH changed.'
        Assert ([Environment]::GetEnvironmentVariable('Path','Machine') -ceq $machinePathBefore) 'Windows Machine PATH changed.'
    }
    [ordered]@{ passed=$true; cases=@($script:results.ToArray()); fixtures=$fixture; real_account_access=$false; providers_called=$false; real_gui_started=$false }|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $fixture 'results.json') -Encoding UTF8
    Write-Output ('HERDR_TEST_RESULTS='+$fixture)
} finally { Restore-Environment $initialEnvironment }
