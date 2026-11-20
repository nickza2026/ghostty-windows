param([string]$WorkRoot,[switch]$ResumeOwned)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if(-not$WorkRoot){$WorkRoot=Join-Path $workspace ('zig-out\portable-git-tests-'+[guid]::NewGuid().ToString('N'))}
$work=[IO.Path]::GetFullPath($WorkRoot)
if(-not$work.StartsWith((Join-Path $workspace 'zig-out\'),[StringComparison]::OrdinalIgnoreCase)){throw 'An owned zig-out test root is required.'}
$root=Join-Path $work 'package'
if(Test-Path -LiteralPath $work){
    if(-not$ResumeOwned -or [IO.File]::ReadAllText((Join-Path $root '.portable-git-test-owned')) -cne 'portable-git-node-fixture-v1'){throw 'Existing root is not this owned resumable fixture.'}
}
$null=[IO.Directory]::CreateDirectory((Join-Path $root 'bin\portable-data\tmp'))
$null=[IO.Directory]::CreateDirectory((Join-Path $root 'support'))
[IO.File]::WriteAllText((Join-Path $root '.portable-git-test-owned'),'portable-git-node-fixture-v1')
[IO.File]::WriteAllText((Join-Path $root 'bin\localterm-dev.exe'),'owned inert fixture, never executed')
foreach($pair in @(@('install-portable-git.ps1','support\install-portable-git.ps1'),@('portable-git-proxy.cs','support\portable-git-proxy.cs'),@('install-portable-git.cmd','Install-Portable-Git.cmd'))){[IO.File]::Copy((Join-Path $PSScriptRoot $pair[0]),(Join-Path $root $pair[1]),[bool]$ResumeOwned)}
[IO.File]::Copy((Join-Path $workspace 'third_party\git\source-pin.json'),(Join-Path $root 'support\git-source-pin.json'),[bool]$ResumeOwned)
$node=Join-Path $workspace 'zig-out\portable-packages\localterm-herdr-portable-20261028\bin\portable-data\runtimes\node\node.exe'
if(-not(Test-Path -LiteralPath $node)){throw 'Bundled Node test runtime is missing.'}
$userPath=[Environment]::GetEnvironmentVariable('Path','User');$machinePath=[Environment]::GetEnvironmentVariable('Path','Machine')
function Run-Owned([string]$Exe,[string]$Arguments,[int]$TimeoutMs){
    $si=[Diagnostics.ProcessStartInfo]::new();$si.FileName=$Exe;$si.Arguments=$Arguments;$si.WorkingDirectory=$work
    $si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
    $si.EnvironmentVariables.Remove('NODE_OPTIONS')
    $p=[Diagnostics.Process]::new();$p.StartInfo=$si
    try{
        $null=$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync()
        if(-not$p.WaitForExit($TimeoutMs)){
            & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $p.Id /T /F
            throw 'Owned fixture process timed out.'
        }
        $r=[pscustomobject]@{exit=$p.ExitCode;stdout=$o.Result;stderr=$e.Result}
        if($r.exit -ne 0){throw ($r.stdout+"`n"+$r.stderr)}
        Write-Output $r.stdout
        return $r
    }finally{$p.Dispose()}
}
$cmd=Join-Path $env:SystemRoot 'System32\cmd.exe'
$install=Run-Owned $cmd ('/d /c ""'+(Join-Path $root 'Install-Portable-Git.cmd')+'""') 420000
$install|ConvertTo-Json|Set-Content (Join-Path $work 'first-install.json') -Encoding UTF8
$nodeScript=Join-Path $PSScriptRoot 'portable-git-node-test.cjs'
$beforeMove=Run-Owned $node ('"'+$nodeScript+'" "'+$root+'"') 90000
$beforeMove|ConvertTo-Json|Set-Content (Join-Path $work 'node-spawn-before-move.json') -Encoding UTF8
. (Join-Path $PSScriptRoot 'install-portable-git.ps1')
$layout=Get-PortableGitLayout $root;$pin=Read-PortableGitPin
if(-not(Test-PortableGitRuntime $layout $pin)){throw 'Installed full Git manifest verification failed.'}
$proxy=Join-Path $layout.Shims 'git.exe';$meta=Join-Path $layout.Shims 'git.proxy.json'
# Recover a deliberately simulated interruption between metadata and EXE moves.
[IO.File]::Delete($proxy)
Install-PortableGitProxy $layout
if(-not(Test-Path -LiteralPath $proxy)){throw 'Metadata-only interruption did not recover.'}
Write-Output 'PASS metadata-only-proxy-publication-recovers'
$metaBytes=[IO.File]::ReadAllBytes($meta)
try{
    [IO.File]::WriteAllText($meta,'{"sourceSha256":"not-ours","exeSha256":"not-ours","runtime":"runtimes/git/cmd/git.exe"}')
    $rejected=$false;try{Install-PortableGitProxy $layout}catch{$rejected=$true}
    if(-not$rejected){throw 'Unknown proxy metadata was overwritten.'}
}finally{[IO.File]::WriteAllBytes($meta,$metaBytes)}
Write-Output 'PASS unknown-proxy-state-preserved'
$moved=Join-Path $work ('moved spaces '+[char]0x0E44+[char]0x0E17+[char]0x0E22)
[IO.Directory]::Move($root,$moved)
$afterMove=Run-Owned $node ('"'+$nodeScript+'" "'+$moved+'"') 90000
$afterMove|ConvertTo-Json|Set-Content (Join-Path $work 'node-spawn-after-move.json') -Encoding UTF8
if([Environment]::GetEnvironmentVariable('Path','User') -cne $userPath -or [Environment]::GetEnvironmentVariable('Path','Machine') -cne $machinePath){throw 'Persistent Windows PATH changed.'}
$record=[ordered]@{passed=$true;fixture=$moved;runtime_under_portable_data=$true;Node_spawn_before_and_after_move=$true;stdio_and_exit_codes=$true;cancel_descendants=$true;metadata_only_retry=$true;unknown_proxy_preserved=$true;user_and_machine_path_unchanged=$true;real_accounts=$false;providers=$false;project_commits=$false;native_Zig_build=$false}
$record|ConvertTo-Json|Set-Content (Join-Path $work 'results.json') -Encoding UTF8
Write-Output ('PORTABLE_GIT_INTEGRATION='+$work)
