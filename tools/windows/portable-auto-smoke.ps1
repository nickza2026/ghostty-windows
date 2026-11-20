param([Parameter(Mandatory=$true)][string]$SourcePrefix)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$owned=Join-Path $workspace ('zig-out\portable-auto-validation\'+[Guid]::NewGuid().ToString('N'))
$thai=([char]0x0E44).ToString()+[char]0x0E17+[char]0x0E22
$first=Join-Path $owned ('first '+$thai+' space')
$moved=Join-Path $owned ('moved '+$thai+' space')
$bad=Join-Path $owned 'invalid-marker'
$logs=Join-Path $env:LOCALAPPDATA 'Letta\build-logs\ghostty-windows\portable'
$null=[IO.Directory]::CreateDirectory($logs)
$stamp='portable-auto-native-'+(Get-Date -Format 'yyyyMMdd-HHmmss')
& (Join-Path $PSScriptRoot 'package-portable.ps1') -SourcePrefix $SourcePrefix -OutputDirectory $first -OmitInitialData
& (Join-Path $PSScriptRoot 'package-portable.ps1') -SourcePrefix $SourcePrefix -OutputDirectory $bad -OmitInitialData
$keys=@('LOCALTERM_TERMINAL_SMOKE','GHOSTTY_RESOURCES_DIR')+@(Get-ChildItem Env:LOCALTERM_*|Select-Object -ExpandProperty Name)
$saved=@{}
function RunCase([string]$package,[string]$name,[int]$expected,[string]$pattern) {
    $o=Join-Path $logs ($stamp+'.'+$name+'.stdout.log'); $e=Join-Path $logs ($stamp+'.'+$name+'.stderr.log')
    # The fixture flag supplies bounded offscreen/no-activate and auto-close.
    # No LOCALTERM_TERMINAL/provider switches, launcher or seeded marker.
    $p=Start-Process (Join-Path $package 'bin\localterm-dev.exe') -WorkingDirectory $env:SystemRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
    try {
        $null=$p.Handle
        $done=$p.WaitForExit(30000)
        if(-not $done){ & taskkill.exe /PID $p.Id /T /F|Out-Null; $null=$p.WaitForExit(5000) }
        $code=$p.ExitCode; $text=Get-Content -LiteralPath $e -Raw -Encoding UTF8
        $pass=$done -and $code -eq $expected -and $text -match $pattern
        [ordered]@{name=$stamp;stage=$name;passed=$pass;exit_code=$code;timeout=(-not $done);stderr=$e;package=$package;scope='direct EXE first-run without seeded portable data/provider/terminal env; bounded offscreen fixture not literal Explorer double-click, real IME or fresh-machine acceptance'}|ConvertTo-Json -Compress|Add-Content(Join-Path $logs 'results.jsonl') -Encoding UTF8
        if(-not $pass){Get-Content $e -Encoding UTF8 -Tail 14;throw "Auto portable failed: $name"}
        Write-Host "PASS auto portable $name"
        return $text
    } finally { $p.Dispose() }
}
try {
    foreach($key in($keys|Select-Object -Unique)){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$null,'Process')}
    $env:LOCALTERM_TERMINAL_SMOKE='1'
    $env:GHOSTTY_RESOURCES_DIR='C:\must-not-use-host-resources'
    $data=Join-Path $first 'bin\portable-data'
    if(Test-Path -LiteralPath $data){throw 'First-run package unexpectedly has data marker'}
    $text=RunCase $first 'absent-data' 0 'controlled terminal marker\+Thai parsed'
    foreach($part in @('config','data','cache','logs','tmp')){if(-not(Test-Path -LiteralPath(Join-Path $data $part) -PathType Container)){throw 'First run failed to create app-owned directory'}}
    if($text -notmatch [regex]::Escape($data)){throw 'First-run root did not follow EXE'}
    $config=Join-Path $data 'config\config.ghostty';$keep=Join-Path $data 'data\keep-fixture.txt'
    [IO.File]::WriteAllText($config,"font-size = 19`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($keep,'existing-app-data-do-not-truncate')
    $configHash=(Get-FileHash $config).Hash;$keepHash=(Get-FileHash $keep).Hash
    $null=RunCase $first 'existing-data' 0 'portable config loaded.*font_size=19'
    if((Get-FileHash $config).Hash -ne $configHash -or (Get-FileHash $keep).Hash -ne $keepHash){throw 'Existing config/data changed'}
    foreach($path in @($first,$moved)){if(-not([IO.Path]::GetFullPath($path)).StartsWith($owned+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Move escaped owned fixture root'}}
    [IO.Directory]::Move($first,$moved)
    $text=RunCase $moved 'moved-data' 0 'portable config loaded.*font_size=19'
    if($text -match [regex]::Escape($first) -or $text -notmatch [regex]::Escape((Join-Path $moved 'share\ghostty'))){throw 'Moved auto package retained old path'}
    $badMarker=Join-Path $bad 'bin\portable-data'
    [IO.File]::WriteAllText($badMarker,'do-not-replace')
    $hash=(Get-FileHash $badMarker).Hash
    $null=RunCase $bad 'invalid-marker' 1 'InvalidPortableDataDirectory'
    if((Get-FileHash $badMarker).Hash -ne $hash){throw 'Invalid marker file was replaced'}
    Write-Output "PASS direct EXE auto first-run/existing data/move/invalid marker; owned fixtures=$owned"
} finally { foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')} }
