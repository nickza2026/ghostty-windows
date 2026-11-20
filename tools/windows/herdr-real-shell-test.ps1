param([Parameter(Mandatory=$true)][string]$HerdrExe,[string]$ReadlineSource,[switch]$DiagnosticBootstrap,[string]$InstalledToolsRoot)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'herdr-portable.ps1')
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$owned=Join-Path $workspace ('zig-out/herdr-real-shell-'+[guid]::NewGuid().ToString('N'))
New-HerdrDirectory $owned
[IO.File]::WriteAllText((Join-Path $owned '.owned'),'herdr-real-shell-test-v1')
$hostTrap=Join-Path $owned 'host-path-trap';New-HerdrDirectory $hostTrap
foreach($name in @('node.exe','git.exe','letta.ps1')){[IO.File]::WriteAllText((Join-Path $hostTrap $name),'throw "Host PATH trap must never execute"')}
[void](Assert-HerdrSafePath $HerdrExe)
$package=Join-Path $owned 'package';New-HerdrDirectory (Join-Path $package 'bin')
[IO.File]::WriteAllText((Join-Path $package 'bin/localterm-dev.exe'),'inert fixture; never executed')
if($ReadlineSource){
    foreach($file in Get-HerdrTreeFiles $ReadlineSource){
        $dest=Join-Path $package ('bin/powershell/PSReadLine/'+$file.FullName.Substring($ReadlineSource.Length+1))
        New-HerdrDirectory (Split-Path $dest);[IO.File]::Copy($file.FullName,$dest,$false)
    }
}
if($DiagnosticBootstrap){
    $support=Join-Path $owned 'support';New-HerdrDirectory $support
    $code=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'herdr-private-shell.cs'))
    $diagnostic=('[IO.File]::WriteAllText(''{0}'', ($_ | Out-String)+[Environment]::NewLine+$env:PSModulePath+[Environment]::NewLine+((Get-Module PSReadLine|Select-Object Name,Path|ConvertTo-Json))); exit 1' -f (Join-Path $owned 'bootstrap-error.txt').Replace("'","''"))
    $code=$code.Replace("[Console]::Error.WriteLine('Private shell initialization failed; no host profile fallback.'); exit 1",$diagnostic)
    [IO.File]::WriteAllText((Join-Path $support 'herdr-private-shell.cs'),$code,[Text.UTF8Encoding]::new($false))
    [IO.File]::Copy((Join-Path $workspace 'third_party/herdr/source-pin.json'),(Join-Path $support 'herdr-source-pin.json'),$false)
    $script:HerdrScriptRoot=$support
}
$publicApp=Split-Path $HerdrExe
$manifest=Get-Content -LiteralPath (Join-Path $publicApp '.portable-manifest.json') -Raw|ConvertFrom-Json
if($manifest.version -ne '0.9.5' -or $manifest.archiveSha256 -ine (Read-HerdrPin).sha256){throw 'Public source runtime pin mismatch'}
$copyLayout=Get-HerdrPortableLayout $package
New-HerdrDirectory $copyLayout.App
foreach($file in Get-HerdrTreeFiles $publicApp){
    $rel=$file.FullName.Substring($publicApp.Length+1).Replace('\','/')
    if($rel -ne '.portable-manifest.json'){
        $entry=@($manifest.files|Where-Object{$_.path -ceq $rel})
        if($entry.Count -ne 1 -or (Get-FileHash -LiteralPath $file.FullName).Hash -ine $entry[0].sha256){throw 'Public source runtime integrity mismatch'}
    }
    $dest=Join-Path $copyLayout.App $rel;New-HerdrDirectory (Split-Path $dest)
    [IO.File]::Copy($file.FullName,$dest,$false)
}
$windows=[Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
$results=@()
function Run-Phase([string]$Root,[string]$Name,[bool]$Legacy) {
    $layout=Get-HerdrPortableLayout $Root
    Set-HerdrPrivateEnvironment $layout
    Set-HerdrPrivateShell $layout
    $session='shell-probe-'+[guid]::NewGuid().ToString('N').Substring(0,16)
    $phase=Join-Path $owned $Name;New-HerdrDirectory $phase
    $config=Join-Path $phase 'config.toml'
    $sourceConfig=[IO.File]::ReadAllText($env:HERDR_CONFIG_PATH)
    if($Legacy){$sourceConfig="[terminal]`r`ndefault_shell = 'herdr-private-shell.exe'`r`n"}
    [IO.File]::WriteAllText($config,$sourceConfig+"`r`n[update]`r`nversion_check = false`r`nmanifest_check = false`r`n",[Text.UTF8Encoding]::new($false))
    $toolsRoot=if($InstalledToolsRoot){(Get-HerdrPortableLayout $InstalledToolsRoot).Root}else{$Root}
    $toolsData=Join-Path $toolsRoot 'bin/portable-data'
    if($InstalledToolsRoot){Update-HerdrPrivateShellConfig $config (Join-Path $toolsData 'apps/herdr-shell/v3/herdr-private-shell.exe')}
    $allowed=@{}
    foreach($key in @('SystemRoot','WINDIR','ComSpec','PATH','PATHEXT','HOME','USERPROFILE','APPDATA','LOCALAPPDATA','XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_STATE_HOME','XDG_CACHE_HOME','TEMP','TMP','LOCALTERM_HERDR_PACKAGE_ROOT','PSModulePath','HOMEDRIVE','HOMEPATH')) {
        $value=[Environment]::GetEnvironmentVariable($key,'Process');if($value){$allowed[$key]=$value}
    }
    # Reproduce the observed unresolved-builder condition, independently of why
    # upstream lost/did not match that PATH entry. Both red and green use this.
    $privateShellRoot=Join-Path $layout.Data 'apps/herdr-shell/v3'
    $allowed.PATH=($allowed.PATH.Split(';')|Where-Object{$_ -ine $privateShellRoot}) -join ';'
    # Model the user's observed pane: correct HOME but machine PATH. Metadata
    # traps must neither win discovery nor execute, even when payloads are absent.
    $allowed.PATH=$hostTrap+';'+(Join-Path $windows 'System32')+';'+$windows+';'+(Join-Path $windows 'System32/WindowsPowerShell/v1.0')
    if($ReadlineSource){
        # A pane/server environment must not select the host module or retain
        # an old installation root. The shim binds both in its immediate child.
        $allowed.PSModulePath=Join-Path $windows 'System32/WindowsPowerShell/v1.0/Modules'
        $allowed.LOCALTERM_HERDR_PACKAGE_ROOT=Join-Path $owned 'synthetic-old-package-root'
    }
    $allowed.HERDR_SESSION=$session;$allowed.HERDR_CONFIG_PATH=$config
    $allowed.XDG_CONFIG_HOME=Join-Path $phase 'config';$allowed.XDG_STATE_HOME=Join-Path $phase 'state'
    foreach($p in @($allowed.XDG_CONFIG_HOME,$allowed.XDG_STATE_HOME)){New-HerdrDirectory $p}
    $endpoint=Join-Path $allowed.XDG_CONFIG_HOME ('herdr/sessions/'+$session+'/herdr.sock')
    [void](Assert-HerdrSafePath $endpoint)
    if(Test-Path -LiteralPath $endpoint){throw 'Fresh endpoint unexpectedly exists'}
    function Start-OwnProcess([string[]]$Arguments) {
        $si=[Diagnostics.ProcessStartInfo]::new();$si.FileName=Join-Path $layout.App 'herdr.exe'
        $si.Arguments=(@('--session',$session)+$Arguments|ForEach-Object{'"'+$_.Replace('"','\"')+'"'}) -join ' '
        $si.WorkingDirectory=$phase;$si.UseShellExecute=$false;$si.CreateNoWindow=$true
        $si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
        foreach($key in @($si.EnvironmentVariables.Keys)){$si.EnvironmentVariables.Remove($key)}
        foreach($key in $allowed.Keys){$si.EnvironmentVariables[$key]=$allowed[$key]}
        $process=[Diagnostics.Process]::new();$process.StartInfo=$si;$null=$process.Start()
        return $process
    }
    function Invoke-OwnCLI([string[]]$Arguments) {
        $process=Start-OwnProcess $Arguments
        try {
            $o=$process.StandardOutput.ReadToEndAsync();$e=$process.StandardError.ReadToEndAsync()
            if(-not$process.WaitForExit(20000)){& (Join-Path $windows 'System32/taskkill.exe') /PID $process.Id /T /F;throw 'Owned CLI timeout'}
            return [pscustomobject]@{exit=$process.ExitCode;stdout=$o.Result;stderr=$e.Result}
        } finally {$process.Dispose()}
    }
    $server=Start-OwnProcess @('server')
    $serverOutput=$server.StandardOutput.ReadToEndAsync();$serverError=$server.StandardError.ReadToEndAsync()
    $endpointOwned=$false
    try {
        $deadline=[DateTime]::UtcNow.AddSeconds(25)
        while(-not(Test-Path -LiteralPath $endpoint) -and -not$server.HasExited -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
        if(-not(Test-Path -LiteralPath $endpoint)){throw ('Owned server did not bind fixture endpoint; exited='+$server.HasExited)}
        $endpointOwned=$true
        $create=Invoke-OwnCLI @('workspace','create','--cwd',$phase,'--label',$session)
        [IO.File]::WriteAllText((Join-Path $phase 'workspace-create.txt'),$create.stdout+$create.stderr,[Text.UTF8Encoding]::new($false))
        if($Legacy) {
            if(($create.stdout+$create.stderr) -notmatch 'CreateProcessW|herdr-private-shell.exe|failed'){throw 'Legacy case did not reproduce actual Herdr spawn failure'}
            return [pscustomobject]@{phase=$Name;legacy_expected_failure=$true;passed=$true;session=$session;endpoint=$endpoint}
        }
        if($create.exit -ne 0){throw ('Actual Herdr workspace spawn failed: '+$create.stdout+$create.stderr)}
        $response=$create.stdout|ConvertFrom-Json
        if($response.result.type -ne 'workspace_created' -or -not$response.result.root_pane.pane_id -or -not$create.stdout.Contains($session)){throw 'Owned workspace response identity mismatch'}
        $pane=[string]$response.result.root_pane.pane_id
        $proof=Join-Path $phase 'spawn-proof.txt';$marker='own-shell-'+[guid]::NewGuid().ToString('N')
        $bootstrapProof=Join-Path $phase 'bootstrap-proof.json'
        $command="[pscustomobject]@{noProfile=([Environment]::CommandLine -match '-NoProfile');assembly=[Microsoft.PowerShell.PSConsoleReadLine].Assembly.Location;history=(Get-PSReadLineOption).HistorySavePath;path="+'$env:PATH'+";git=(Get-Command git -ErrorAction SilentlyContinue).Source;node=(Get-Command node -ErrorAction SilentlyContinue).Source;letta=(Get-Command letta -ErrorAction SilentlyContinue).Source;home="+'$HOME'+"}|ConvertTo-Json|Set-Content -Encoding UTF8 -LiteralPath '"+$bootstrapProof.Replace("'","''")+"';[IO.File]::WriteAllText('"+$proof.Replace("'","''")+"','"+$marker+"')"
        if($InstalledToolsRoot){
            $versions=Join-Path $phase 'actual-private-versions.json'
            $command="[pscustomobject]@{git=([string](& git --version));node=([string](& node --version));letta=([string](& letta --version))}|ConvertTo-Json|Set-Content -Encoding UTF8 -LiteralPath '"+$versions.Replace("'","''")+"';"+$command
        }
        $run=Invoke-OwnCLI @('pane','run',$pane,$command)
        if($run.exit -ne 0){throw ('Owned pane run failed: '+$run.stderr)}
        $deadline=[DateTime]::UtcNow.AddSeconds(15)
        while(-not(Test-Path -LiteralPath $proof) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
        $read=Invoke-OwnCLI @('pane','read',$pane)
        [IO.File]::WriteAllText((Join-Path $phase 'pane-read.txt'),$read.stdout+$read.stderr,[Text.UTF8Encoding]::new($false))
        if(-not(Test-Path -LiteralPath $proof) -or [IO.File]::ReadAllText($proof) -cne $marker){throw 'Actual Herdr pane did not execute unique private shell marker'}
        $bootstrap=Get-Content -LiteralPath $bootstrapProof -Raw -Encoding UTF8|ConvertFrom-Json
        if(-not$bootstrap.noProfile -or -not$bootstrap.history.StartsWith($layout.Profile,[StringComparison]::OrdinalIgnoreCase) -or $bootstrap.home -cne $allowed.HOME){throw 'Actual interactive bootstrap privacy proof failed'}
        $expectedNode=Join-Path $toolsData 'runtimes/node'
        if($bootstrap.path.Split(';')[0] -ine $expectedNode -or $bootstrap.path.Contains($hostTrap)){throw 'Actual interactive PATH escaped the package and retained host commands'}
        foreach($tool in @('git','node','letta')){if(($InstalledToolsRoot -and -not$bootstrap.$tool) -or ($bootstrap.$tool -and -not$bootstrap.$tool.StartsWith($toolsData+'\',[StringComparison]::OrdinalIgnoreCase))){throw 'Actual command discovery selected a host tool or missed private payload'}}
        if($ReadlineSource -and -not$bootstrap.assembly.StartsWith((Join-Path $toolsRoot 'bin/powershell/PSReadLine'),[StringComparison]::OrdinalIgnoreCase)){throw 'Actual ConPTY loaded inbox instead of bundled PSReadLine'}
        if($InstalledToolsRoot){$v=Get-Content -LiteralPath $versions -Raw|ConvertFrom-Json;if($v.git -notmatch '^git version ' -or $v.node -notmatch '^v\d+\.' -or $v.letta -notmatch '0\.34\.23'){throw 'Actual private payload versions did not execute'}}
        return [pscustomobject]@{phase=$Name;passed=$true;actual_Herdr_ConPTY_shell_marker=$true;bundled_Readline_verified=[bool]$ReadlineSource;NoProfile_and_private_HOME_history=$true;session=$session;endpoint=$endpoint}
    } finally {
        if($endpointOwned -and -not$server.HasExited){$stop=Invoke-OwnCLI @('server','stop');if($stop.exit -ne 0){Write-Warning 'Owned server graceful stop failed'}}
        if(-not$server.WaitForExit(10000)){& (Join-Path $windows 'System32/taskkill.exe') /PID $server.Id /T /F}
        [IO.File]::WriteAllText((Join-Path $phase 'server.txt'),$serverOutput.Result+$serverError.Result,[Text.UTF8Encoding]::new($false))
        $server.Dispose()
    }
}
if($InstalledToolsRoot){
    $results+=Run-Phase $package 'installed-private-tools' $false
    $result=[ordered]@{passed=$true;fixture=$owned;phases=$results;installed_private_Git_Node_Letta_executed_in_actual_Herdr_pane=$true;host_PATH_injected_and_excluded=$true;live_user_servers_contacted=$false;real_accounts_used=$false;GUI_windows_opened=$false}
    $result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $owned 'results.json') -Encoding UTF8
    Write-Output ($result|ConvertTo-Json -Depth 6);return
}
$results+=Run-Phase $package 'legacy-red' $true
$results+=Run-Phase $package 'absolute-green' $false
$moved=Join-Path $owned ("moved 'quoted' spaces "+[char]0x0E44+[char]0x0E17+[char]0x0E22)
# ConPTY/Windows loader handles can outlive a just-exited test server briefly.
# Bound the wait, never kill user processes or weaken path protections.
for($attempt=0;$attempt -lt 20;$attempt++){
    try{[IO.Directory]::Move($package,$moved);break}
    catch [IO.IOException]{if($attempt -eq 19){throw};Start-Sleep -Milliseconds 250}
}
$results+=Run-Phase $moved 'relocated-green' $false
$result=[ordered]@{passed=$true;fixture=$owned;phases=$results;pinned_app_and_ConPTY_payload_moved_together=$true;live_user_servers_contacted=$false;real_accounts_used=$false;GUI_windows_opened=$false;genuine_Herdr_ConPTY=$true}
$result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $owned 'results.json') -Encoding UTF8
Write-Output ($result|ConvertTo-Json -Depth 6)
