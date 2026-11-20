$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$out=Join-Path $workspace ('zig-out\portable-git-launcher-check-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($out)
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'package-portable.ps1'))
$base=[regex]::Match($source,"(?s)\`$launcher = @'\r?\n(.*?)\r?\n'@").Groups[1].Value
$pre=[regex]::Match($source,"(?s)\`$gitPreflight=@'\r?\n(.*?)\r?\n'@").Groups[1].Value
if(-not$base -or -not$pre){throw 'Source launcher template extraction failed.'}
# Exact preflight/dispatch, but replace terminal execution: no GUI is started.
$mock='echo native-called>"%~dp0native-called.txt"'+"`r`n"+'exit /b 0'
$launcher=$base.Replace('"%~dp0bin\localterm-dev.exe" %*',$pre+"`r`n"+$mock)
[IO.File]::WriteAllText((Join-Path $out 'Run.cmd'),$launcher,[Text.Encoding]::ASCII)
$stub='@echo off'+"`r`n"+'echo setup-called>"%~dp0setup-called.txt"'+"`r`n"+'exit /b 37'
[IO.File]::WriteAllText((Join-Path $out 'Install-Portable-Git.cmd'),$stub,[Text.Encoding]::ASCII)
function Run-HiddenCmd([string]$Arguments){
    $si=[Diagnostics.ProcessStartInfo]::new();$si.FileName=Join-Path $env:SystemRoot 'System32\cmd.exe'
    $si.Arguments=$Arguments;$si.WorkingDirectory=$out;$si.UseShellExecute=$false;$si.CreateNoWindow=$true
    $si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
    $p=[Diagnostics.Process]::new();$p.StartInfo=$si
    try{
        $null=$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        if(-not$p.WaitForExit(15000)){$p.Kill();throw 'Owned launcher test timeout.'}
        return $p.ExitCode
    }finally{$p.Dispose()}
}
$exit=Run-HiddenCmd ('/d /c ""'+(Join-Path $out 'Run.cmd')+'""')
if($exit -ne 1 -or -not(Test-Path (Join-Path $out 'setup-called.txt')) -or (Test-Path (Join-Path $out 'native-called.txt'))){throw 'Failed setup did not halt native launcher.'}
[IO.File]::Delete((Join-Path $out 'setup-called.txt'))
foreach($rel in @('bin\portable-data\shims\git.exe','bin\portable-data\runtimes\git\cmd\git.exe','bin\portable-data\runtimes\git\usr\bin\bash.exe')){
    $file=Join-Path $out $rel;$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))
    [IO.File]::WriteAllText($file,'inert test file; never executed')
}
$exit=Run-HiddenCmd ('/d /c ""'+(Join-Path $out 'Run.cmd')+'""')
if($exit -ne 0 -or (Test-Path (Join-Path $out 'setup-called.txt')) -or -not(Test-Path (Join-Path $out 'native-called.txt'))){throw 'Ready Git did not skip setup.'}
$herdr=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'run-herdr-portable.cmd'))
$herdr=[regex]::Replace($herdr,'(?m)^"%SystemRoot%[^\r\n]+','echo diagnostic-called>"%~dp0diagnostic-called.txt"'+"`r`n"+'exit /b 0')
[IO.File]::WriteAllText((Join-Path $out 'Run-Herdr.cmd'),$herdr,[Text.Encoding]::ASCII)
$exit=Run-HiddenCmd ('/d /c ""'+(Join-Path $out 'Run-Herdr.cmd')+'" --version"')
if($exit -ne 0 -or (Test-Path (Join-Path $out 'setup-called.txt')) -or -not(Test-Path (Join-Path $out 'diagnostic-called.txt'))){throw 'Herdr version invoked Git setup.'}
$record=[ordered]@{passed=$true;source_native_preflight_fail_closed=$true;source_ready_runtime_skips_setup=$true;source_herdr_version_skips_setup=$true;mocked_native_and_Herdr_execution=$true;real_gui=$false;provider=$false;live_package_changed=$false;fixture=$out}
$evidence=Join-Path $workspace 'zig-out\portable-tools-evidence\portable-git-20261028'
$null=[IO.Directory]::CreateDirectory($evidence)
$record|ConvertTo-Json|Set-Content (Join-Path $evidence 'source-launcher-preflight.json') -Encoding UTF8
Write-Output ($record|ConvertTo-Json)
