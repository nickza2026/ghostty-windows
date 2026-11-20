param([string]$OutputDirectory,[switch]$ResumeOwned)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$delivery=Join-Path $workspace 'zig-out\portable-packages\localterm-portable-tools-20261027'
if (-not $OutputDirectory) { $OutputDirectory=Join-Path $workspace ('zig-out\herdr-integration-'+[guid]::NewGuid().ToString('N')) }
$owned=[IO.Path]::GetFullPath($OutputDirectory)
if (-not $owned.StartsWith((Join-Path $workspace 'zig-out\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'An owned zig-out integration root is required.' }
$owner=Join-Path $owned '.herdr-integration-owned'
if ($ResumeOwned) {
    if (-not (Test-Path -LiteralPath $owner -PathType Leaf) -or [IO.File]::ReadAllText($owner) -ne 'herdr-portable-integration-test-v1') { throw 'Resume requires the owned integration marker.' }
} else {
    if(Test-Path -LiteralPath $owned) { throw 'A fresh owned integration root is required.' }
    $null=[IO.Directory]::CreateDirectory($owned)
    [IO.File]::WriteAllText($owner,'herdr-portable-integration-test-v1')
}
$baseline=Get-Content -LiteralPath (Join-Path $delivery 'package-manifest.json') -Raw|ConvertFrom-Json
$package=Join-Path $owned 'package'
$userPathBefore=[Environment]::GetEnvironmentVariable('Path','User')
$machinePathBefore=[Environment]::GetEnvironmentVariable('Path','Machine')
$packager=Join-Path $PSScriptRoot 'package-portable.ps1'
if (-not $ResumeOwned) {
    # This is a PowerShell script, not a native process: terminating exceptions
    # propagate; a fresh PS process need not have any LASTEXITCODE variable.
    & $packager -SourcePrefix $baseline.source_prefix -OutputDirectory $package -PortableTools -NodeSource (Join-Path $delivery 'bin\portable-data\runtimes\node')
}
function Invoke-VersionCommand([string]$Root,[string]$Mode,[int]$TimeoutMs) {
    $si=[Diagnostics.ProcessStartInfo]::new()
    $si.FileName=Join-Path $env:SystemRoot 'System32\cmd.exe'
    $si.Arguments='/d /c ""'+(Join-Path $Root 'Run-Herdr.cmd')+'" '+$Mode+'"'
    $si.WorkingDirectory=$Root; $si.UseShellExecute=$false; $si.CreateNoWindow=$true
    $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
    # Deliberate fake injections: the launcher must not inherit routing/account paths.
    $si.EnvironmentVariables['HERDR_SOCKET_PATH']='C:\synthetic-host\api.sock'
    $si.EnvironmentVariables['HERDR_CLIENT_SOCKET_PATH']='C:\synthetic-host\client.sock'
    $si.EnvironmentVariables['CODEX_HOME']='C:\synthetic-host\codex'
    $si.EnvironmentVariables['OPENAI_API_KEY']='synthetic-integration-not-a-credential'
    $si.EnvironmentVariables['NODE_OPTIONS']='--synthetic-invalid-option'
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$si
    try {
        $null=$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMs)) {
            # Terminate only this owned fixture process tree; never an existing Herdr server.
            & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $process.Id /T /F
            throw 'Owned integration command timed out.'
        }
        $result=[ordered]@{ mode=$Mode; exit=$process.ExitCode; stdout=$stdout.Result; stderr=$stderr.Result }
        if ($process.ExitCode -ne 0) { throw ($result.stdout+"`n"+$result.stderr) }
        return [pscustomobject]$result
    } finally { $process.Dispose() }
}
$first=Invoke-VersionCommand $package '--install-only' 390000
$installLog=Join-Path $owned 'first-install.log'
if (Test-Path -LiteralPath $installLog) { $installLog=Join-Path $owned 'final-install-validation.log' }
[IO.File]::WriteAllText($installLog,$first.stdout+"`n"+$first.stderr,[Text.UTF8Encoding]::new($false))
$app=Join-Path $package 'bin\portable-data\apps\herdr\0.9.5'
$manifestPath=Join-Path $app '.portable-manifest.json'
$manifestHash=(Get-FileHash -LiteralPath $manifestPath).Hash
$firstManifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
if ($firstManifest.archiveSha256 -ine 'd2c6c9c971c43a0bfdde8c692a9a1a7a45c3e4807cd01ae45662b4734fac1cbf') { throw 'Real payload did not match official pinned ZIP.' }
$second=Invoke-VersionCommand $package '--version' 90000
if ($second.stdout -notmatch '0\.9\.5' -or $second.stdout -match 'First run: downloading') { throw 'Offline version reuse did not use the expected installed release.' }
if ((Get-FileHash -LiteralPath $manifestPath).Hash -ne $manifestHash) { throw 'Reuse modified installed manifest.' }
$moved=Join-Path $owned ('relocated with spaces '+[char]0x0E44+[char]0x0E17+[char]0x0E22)
[IO.Directory]::Move($package,$moved)
$third=Invoke-VersionCommand $moved '--version' 90000
if ($third.stdout -notmatch '0\.9\.5' -or $third.stdout -match 'First run: downloading') { throw 'Relocated payload was not reused.' }
if ([Environment]::GetEnvironmentVariable('Path','User') -cne $userPathBefore -or [Environment]::GetEnvironmentVariable('Path','Machine') -cne $machinePathBefore) { throw 'Windows persistent PATH changed.' }
$records=[ordered]@{
    passed=$true; package=$moved; original_terminal_sha256=(Get-FileHash -LiteralPath (Join-Path $moved 'bin\localterm-dev.exe')).Hash
    official_herdr_version='0.9.5'; official_zip_sha256=$firstManifest.archiveSha256; payload_file_count=@($firstManifest.files).Count
    cmd_first_install=$first; cmd_verified_reuse_version=$second; cmd_relocated_version=$third
    persistent_user_and_machine_path_unchanged=$true; providers_called=$false; real_accounts_used=$false; real_gui_started=$false
}
$records|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $owned 'results.json') -Encoding UTF8
Write-Output ('HERDR_REAL_INTEGRATION='+$owned)
