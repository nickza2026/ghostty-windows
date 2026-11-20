$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'herdr-portable.ps1')
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$owned=Join-Path $workspace ('zig-out/herdr-shell-path-'+[guid]::NewGuid().ToString('N'))
New-HerdrDirectory $owned
[IO.File]::WriteAllText((Join-Path $owned '.owned'),'herdr-shell-path-test-v1')
$package=Join-Path $owned 'package'
New-HerdrDirectory (Join-Path $package 'bin')
[IO.File]::WriteAllText((Join-Path $package 'bin/localterm-dev.exe'),'inert fixture sentinel; never executed')
$layout=Get-HerdrPortableLayout $package
$env:HERDR_CONFIG_PATH=Join-Path $layout.Profile 'config/herdr/config.toml'
New-HerdrDirectory (Split-Path $env:HERDR_CONFIG_PATH)
Set-HerdrPrivateShell $layout
$probe=Join-Path $owned 'createprocess-probe.exe'
$compiler=Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
& $compiler /nologo /target:exe ('/out:'+$probe) (Join-Path $PSScriptRoot 'herdr-shell-createprocess-probe.cs')
if($LASTEXITCODE -ne 0){throw 'Native regression probe compilation failed'}
$cwd=Join-Path $owned 'empty cwd';New-HerdrDirectory $cwd
$proof=Join-Path $owned 'proof.txt'
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('[IO.File]::WriteAllText($env:HERDR_TEST_PROOF,(Get-Location).Path)'))
function Probe([string]$Application,[string]$Mode) {
    $si=[Diagnostics.ProcessStartInfo]::new();$si.FileName=$probe
    $si.Arguments='"'+$Application+'" "'+$cwd+'" '+$encoded+' '+$Mode
    $si.WorkingDirectory=$cwd;$si.UseShellExecute=$false;$si.CreateNoWindow=$true
    $si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
    foreach($key in @($si.EnvironmentVariables.Keys)){$si.EnvironmentVariables.Remove($key)}
    $windows=[Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    $si.EnvironmentVariables['SystemRoot']=$windows;$si.EnvironmentVariables['WINDIR']=$windows
    $si.EnvironmentVariables['PATH']=(Join-Path $layout.Data 'apps/herdr-shell/v3')+';'+(Join-Path $windows 'System32')
    $si.EnvironmentVariables['HOME']=$owned;$si.EnvironmentVariables['USERPROFILE']=$owned
    $si.EnvironmentVariables['TEMP']=$owned;$si.EnvironmentVariables['TMP']=$owned
    $si.EnvironmentVariables['HERDR_TEST_PROOF']=$proof
    $process=[Diagnostics.Process]::new();$process.StartInfo=$si
    try {
        $null=$process.Start();$o=$process.StandardOutput.ReadToEndAsync();$e=$process.StandardError.ReadToEndAsync()
        if(-not$process.WaitForExit(25000)){& (Join-Path $windows 'System32/taskkill.exe') /PID $process.Id /T /F;throw 'Owned native probe timeout'}
        if($process.ExitCode -ne 0){throw ('Explicit application launch failed: '+$o.Result+$e.Result)}
        Write-Output $o.Result.Trim()
    } finally {$process.Dispose()}
}
# This is the original defect: PATH includes the shell, but Win32 does not use it
# for a non-null relative application name. No user config or Herdr server runs.
Probe 'herdr-private-shell.exe' 'expect-missing'
$text=[IO.File]::ReadAllText($env:HERDR_CONFIG_PATH)
$value=[regex]::Match($text,'(?m)^default_shell\s*=\s*(.+)$').Groups[1].Value.Trim()
if($value.StartsWith('"')){$configured=ConvertFrom-Json $value}else{$configured=$value.Trim("'")}
Probe $configured 'success'
if(-not(Test-Path -LiteralPath $proof) -or [IO.File]::ReadAllText($proof) -cne $cwd){throw 'Private shell did not execute in owned working directory'}
$legacy="# private user comments`r`n[terminal]`r`ndefault_shell = 'herdr-private-shell.exe' # retain inline comment`r`nfont_size = 17`r`n[other]`r`ndefault_shell = 'herdr-private-shell.exe'`r`ntitle = 'synthetic settings'`r`n"
[IO.File]::WriteAllText($env:HERDR_CONFIG_PATH,$legacy,[Text.UTF8Encoding]::new($false))
Set-HerdrPrivateShell $layout
$updated=[IO.File]::ReadAllText($env:HERDR_CONFIG_PATH)
$expectedPath='"'+(Join-Path $layout.Data 'apps/herdr-shell/v3/herdr-private-shell.exe').Replace('\','\\')+'"'
$expected=$legacy.Replace("default_shell = 'herdr-private-shell.exe' # retain inline comment",'default_shell = '+$expectedPath+' # retain inline comment')
if($updated -cne $expected){throw 'Managed migration changed unrelated config bytes'}
foreach($version in @('v1','v2')){
    $oldPath=Join-Path $layout.Data ('apps/herdr-shell/'+$version+'/herdr-private-shell.exe')
    $oldConfig=$legacy.Replace("default_shell = 'herdr-private-shell.exe' # retain inline comment","default_shell = '"+$oldPath+"' # retain inline comment")
    [IO.File]::WriteAllText($env:HERDR_CONFIG_PATH,$oldConfig,[Text.UTF8Encoding]::new($false))
    Set-HerdrPrivateShell $layout
    if([IO.File]::ReadAllText($env:HERDR_CONFIG_PATH) -cne $expected){throw 'Managed old path was not migrated to v3 without other config changes'}
}
$backupCount=@(Get-ChildItem -LiteralPath (Split-Path $env:HERDR_CONFIG_PATH) -Filter '*.bak').Count
Set-HerdrPrivateShell $layout
if(@(Get-ChildItem -LiteralPath (Split-Path $env:HERDR_CONFIG_PATH) -Filter '*.bak').Count -ne $backupCount){throw 'Unchanged startup made needless backups'}
# Move this owned fixture, never an active delivery or any user profile.
$moved=Join-Path $owned ("moved 'quoted' spaces "+[char]0x0E44+[char]0x0E17+[char]0x0E22)
for($attempt=0;$attempt -lt 20;$attempt++){
    try{[IO.Directory]::Move($package,$moved);break}
    catch [IO.IOException]{if($attempt -eq 19){throw};Start-Sleep -Milliseconds 250}
}
$layout=Get-HerdrPortableLayout $moved
$env:HERDR_CONFIG_PATH=Join-Path $layout.Profile 'config/herdr/config.toml'
Set-HerdrPrivateShell $layout
$text=[IO.File]::ReadAllText($env:HERDR_CONFIG_PATH)
$value=[regex]::Match($text,'(?m)^default_shell\s*=\s*(.+?)\s+# retain').Groups[1].Value
$configured=[string](ConvertFrom-Json $value)
if(-not$configured.StartsWith($moved,[StringComparison]::OrdinalIgnoreCase) -or $text.Contains($package.Replace('\','\\'))){throw 'Relocated managed path remains stale'}
Probe $configured 'success'
$custom="[terminal]`r`ndefault_shell = 'pwsh.exe' # intentional user shell`r`n[other]`r`ndefault_shell = 'herdr-private-shell.exe'`r`n"
[IO.File]::WriteAllText($env:HERDR_CONFIG_PATH,$custom,[Text.UTF8Encoding]::new($false))
Set-HerdrPrivateShell $layout
if([IO.File]::ReadAllText($env:HERDR_CONFIG_PATH) -cne $custom){throw 'Custom user shell setting changed'}
$result=[ordered]@{passed=$true;fixture=$owned;explicit_Win32_bare_name_rejected_even_on_PATH=$true;fresh_absolute_shell_launched=$true;legacy_setting_migrated_only=$true;other_settings_and_comments_preserved=$true;private_backup_created=$backupCount -gt 0;same_path_did_not_rewrite=$true;relocated_Thai_spaces_apostrophes_shell_launched=$true;custom_shell_preserved=$true;GUI_started=$false;real_profiles_used=$false}
$result|ConvertTo-Json|Set-Content (Join-Path $owned 'results.json') -Encoding UTF8
Write-Output ($result|ConvertTo-Json)
Write-Output ('HERDR_SHELL_PATH_PASS='+$owned)
