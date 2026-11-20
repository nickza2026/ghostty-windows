param(
    [ValidateSet('window', 'terminal', 'input', 'lifecycle', 'exit', 'burst', 'burst-title', 'bad-shell', 'profile', 'profile-paced', 'font-angsana', 'font-leelawadee', 'font-system', 'font-roomy', 'font-native', 'font-native-roomy', 'image-paste')][string]$Mode = 'window',
    [ValidateRange(15, 180)][int]$TimeoutSeconds = 60,
    [ValidateSet('enabled', 'disabled')][string]$PssDiagnostics = 'enabled',
    [ValidateSet('none', 'renderer', 'io', 'title')][string]$WorkerStartupFailure = 'none',
    [switch]$CaptureOwnedStacksOnTimeout,
    [switch]$MouseSmoke,
    [switch]$ThaiTuiSmoke,
    [switch]$MidlineSmoke,
    [string]$MidlineModule,
    [switch]$AppReadLine,
    [switch]$PortableTools,
    [switch]$PortableToolsCheck,
    [switch]$GpuTextFrameCheck,
    [switch]$ViewportSmoke,
    [switch]$KittyImageSmoke,
    [switch]$KittyImageLegacyReference,
    [switch]$ThaiTuiLegacy,
    [ValidateSet('system','wcswidth','graphemes')][string]$ConptyWidth = 'system',
    [ValidateSet('system','app-local')][string]$ConptyProvider = 'system',
    [switch]$RequireThaiModel,
    [switch]$BackgroundSmoke,
    [ValidatePattern('^[0-9a-fA-F]{6}$')][string]$PreviewBackground,
    [string]$Executable = (Join-Path $PSScriptRoot '..\..\zig-out\bin\localterm-dev.exe'),
    [string]$EtwLaunchHelper,
    [string]$EtwGateDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($WorkerStartupFailure -ne 'none' -and ($Mode -ne 'terminal' -or $MouseSmoke -or $ThaiTuiSmoke -or $MidlineSmoke -or $PortableTools -or $AppReadLine -or $GpuTextFrameCheck -or $ViewportSmoke -or $KittyImageSmoke -or $BackgroundSmoke)) { throw 'Worker startup failure requires standalone terminal mode without other fixtures.' }
if ($MidlineSmoke -and ($Mode -ne 'terminal' -or $ThaiTuiSmoke -or $MouseSmoke -or $GpuTextFrameCheck -or $ViewportSmoke -or $KittyImageSmoke)) { throw 'Midline fixture requires standalone terminal mode.' }
if ($KittyImageLegacyReference -and -not $KittyImageSmoke) { throw 'Legacy Kitty reference requires the explicit Kitty fixture.' }
if ($KittyImageSmoke -and ($Mode -ne 'terminal' -or $ConptyProvider -ne 'app-local' -or $ViewportSmoke -or $ThaiTuiSmoke -or $MouseSmoke -or $BackgroundSmoke -or $GpuTextFrameCheck)) { throw 'Kitty image fixture requires standalone terminal mode with app-local ConPTY and experimental image build.' }
if ($ViewportSmoke -and ($Mode -ne 'terminal' -or $ThaiTuiSmoke -or $MouseSmoke -or $BackgroundSmoke -or $GpuTextFrameCheck)) { throw 'Viewport fixture requires standalone remote terminal mode.' }
if ($PssDiagnostics -eq 'disabled' -and $Mode -ne 'lifecycle') { throw 'PSS diagnostic control is lifecycle-only.' }
if ($CaptureOwnedStacksOnTimeout -and $Mode -notin @('burst','burst-title')) { throw 'Post-timeout stack capture is a burst diagnostic only.' }
if ($MouseSmoke -and $Mode -ne 'terminal') { throw 'Mouse smoke requires terminal mode.' }
if ($ThaiTuiSmoke -and ($Mode -ne 'terminal' -or $MouseSmoke)) { throw 'Thai TUI diagnostic requires terminal mode without mouse smoke.' }
if ($ThaiTuiLegacy -and -not $ThaiTuiSmoke) { throw 'Legacy width control requires Thai TUI diagnostic.' }
if ($ConptyWidth -ne 'system' -and -not $ThaiTuiSmoke) { throw 'ConPTY width control requires Thai TUI diagnostic.' }
if ($ConptyProvider -ne 'system' -and $Mode -eq 'window') { throw 'App-local backend requires a terminal mode.' }
if ($RequireThaiModel -and -not $ThaiTuiSmoke) { throw 'Strict Thai model requires the controlled fixture.' }
if ($GpuTextFrameCheck -and (-not $ThaiTuiSmoke -or -not $RequireThaiModel)) { throw 'GPU text parity requires the controlled strict Thai fixture.' }
if ($BackgroundSmoke -and ($Mode -ne 'terminal' -or $ThaiTuiSmoke -or $MouseSmoke)) { throw 'Background diagnostic requires standalone terminal mode.' }
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$etwDiagnostic = [bool]($EtwLaunchHelper -or $EtwGateDirectory)
if ($etwDiagnostic) {
    if (-not $EtwLaunchHelper -or -not $EtwGateDirectory -or $Mode -ne 'lifecycle') { throw 'ETW suspended launch requires both paths and lifecycle mode.' }
    $allowedEtwParameters = @('Mode','TimeoutSeconds','PssDiagnostics','Executable','EtwLaunchHelper','EtwGateDirectory')
    foreach ($parameter in $PSBoundParameters.Keys) {
        if ($parameter -notin $allowedEtwParameters) { throw 'ETW suspended launch does not permit additional fixture flags.' }
    }
    if ($TimeoutSeconds -gt 120) { throw 'ETW suspended diagnostic deadline must not exceed 120 seconds.' }
    foreach ($path in @($EtwLaunchHelper,$EtwGateDirectory)) {
        if ($path -notmatch '^[A-Za-z]:\\' -or $path.Contains('"') -or $path.EndsWith('\') -or [IO.Path]::GetFullPath($path) -ne $path) { throw 'ETW paths must be canonical local absolute paths without quotes or trailing separators.' }
        for ($ancestor = $path; $ancestor; $ancestor = [IO.Path]::GetDirectoryName($ancestor)) {
            if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'ETW paths must not traverse reparse points.' }
        }
    }
    if (-not (Test-Path -LiteralPath $EtwLaunchHelper -PathType Leaf) -or -not (Test-Path -LiteralPath $EtwGateDirectory -PathType Container) -or @(Get-ChildItem -LiteralPath $EtwGateDirectory -Force).Count) { throw 'ETW helper must exist and gate must be an empty private directory.' }
}
if ($MidlineModule) {
    if (-not $MidlineSmoke) { throw 'Module selection is limited to the explicit midline fixture.' }
    $MidlineModule = (Resolve-Path -LiteralPath $MidlineModule).ProviderPath
    $allowedModuleRoots = @(
        ((Join-Path $workspace 'zig-out') + [IO.Path]::DirectorySeparatorChar)
        ((Join-Path $env:LOCALAPPDATA 'Letta\build-cache\ghostty-windows') + [IO.Path]::DirectorySeparatorChar)
    )
    if ([IO.Path]::GetFileName($MidlineModule) -ne 'PSReadLine.psd1' -or -not @($allowedModuleRoots | Where-Object { $MidlineModule.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count) { throw 'Module must be an app-owned PSReadLine manifest under the private output/cache root.' }
    if ((Get-Item -LiteralPath $MidlineModule).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing app-owned manifest reparse point.' }
    for ($ancestor = [IO.Path]::GetDirectoryName($MidlineModule); $ancestor; $ancestor = [IO.Path]::GetDirectoryName($ancestor)) {
        if ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing app-owned module path through a reparse point.' }
    }
    $moduleDirs = [Collections.Generic.Queue[string]]::new()
    $moduleDirs.Enqueue([IO.Path]::GetDirectoryName($MidlineModule))
    while ($moduleDirs.Count) {
        foreach ($entry in Get-ChildItem -LiteralPath $moduleDirs.Dequeue() -Force) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing reparse point in app-owned module contents.' }
            if ($entry.PSIsContainer) { $moduleDirs.Enqueue($entry.FullName) }
        }
    }
}
$exe = (Resolve-Path -LiteralPath $Executable).ProviderPath
if (-not $exe.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Smoke executable must live in this workspace.'
}
$logs = Join-Path $env:LOCALAPPDATA 'Letta\build-logs\ghostty-windows\phase3b-runtime'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$started = Get-Date
$stamp = $started.ToString('yyyyMMdd-HHmmss-fff', [Globalization.CultureInfo]::InvariantCulture)
$name = "$Mode-native-$stamp"
if ($PssDiagnostics -eq 'disabled') { $name = "$Mode-pss-control-native-$stamp" }
$stdout = Join-Path $logs "$name.stdout.log"
$stderr = Join-Path $logs "$name.stderr.log"
$keys = @('LOCALTERM_WINDOW_SMOKE', 'LOCALTERM_TERMINAL_SMOKE', 'LOCALTERM_TERMINAL', 'LOCALTERM_INPUT_SMOKE', 'LOCALTERM_LIFECYCLE_SMOKE', 'LOCALTERM_LIFECYCLE_PSS', 'LOCALTERM_TERMINAL_CASE', 'LOCALTERM_EXPECT_IMAGE_ROOT', 'LOCALTERM_TITLE_BACKPRESSURE_SMOKE', 'LOCALTERM_MOUSE_SMOKE', 'LOCALTERM_THAI_TUI_SMOKE', 'LOCALTERM_THAI_TUI_LEGACY', 'LOCALTERM_CONPTY_WIDTH', 'LOCALTERM_CONPTY_PROVIDER', 'LOCALTERM_CONPTY_EXPERIMENT', 'LOCALTERM_THAI_MODEL_REQUIRED', 'LOCALTERM_BACKGROUND_SMOKE', 'LOCALTERM_PREVIEW_BACKGROUND')
if ($Mode -eq 'lifecycle' -and -not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds = 120 }
$keys += 'LOCALTERM_GPU_TEXT_FRAME_CHECK'
$keys += 'LOCALTERM_VIEWPORT_SMOKE'
$keys += 'LOCALTERM_KITTY_IMAGE_SMOKE'
$keys += 'LOCALTERM_KITTY_IMAGE_REFERENCE'
$keys += @('LOCALTERM_MIDLINE_SMOKE')
$keys += @('LOCALTERM_MIDLINE_MODULE')
$keys += @('LOCALTERM_APP_READLINE', 'LOCALTERM_APP_READLINE_MANIFEST')
$keys += @('LOCALTERM_PORTABLE_TOOLS', 'LOCALTERM_PORTABLE_TOOLS_CHECK', 'LOCALTERM_PORTABLE_DATA')
$keys += 'LOCALTERM_WORKER_STARTUP_FAILURE'
if ($PortableToolsCheck -and (-not $PortableTools -or $Mode -ne 'terminal' -or $MidlineSmoke)) { throw 'PortableToolsCheck requires PortableTools and plain terminal mode.' }
if ($PortableTools) { $AppReadLine = $true }
$savedPSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
$saved = @{}
$process = $null
$timedOut = $false
$remaining = @()
$code = $null
$cpuMs = 0.0
$peakWorkingSet = 0L
$sampledWorkingSet = 0L
$resourceSamples = 0
$resourceElapsedMs = 0.0
$stackCapture = $null

function Get-OwnedDescendants([int]$RootId, [datetime]$Since) {
    $queue = [Collections.Generic.Queue[int]]::new()
    $queue.Enqueue($RootId)
    $seen = [Collections.Generic.HashSet[int]]::new()
    $result = [Collections.Generic.List[object]]::new()
    while ($queue.Count -gt 0) {
        $parent = $queue.Dequeue()
        foreach ($row in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$parent")) {
            if ($row.CreationDate -lt $Since -or -not $seen.Add([int]$row.ProcessId)) { continue }
            $result.Add($row)
            $queue.Enqueue([int]$row.ProcessId)
        }
    }
    return $result.ToArray()
}

function Stop-OwnedDescendants([object[]]$Rows) {
    # No name-based kill. Revalidate creation identity with a retained process
    # handle before terminating only descendants captured from this test tree.
    $reverse = @($Rows)
    [array]::Reverse($reverse)
    foreach ($row in $reverse) {
        $child = Get-Process -Id $row.ProcessId -ErrorAction SilentlyContinue
        if ($null -eq $child) { continue }
        try {
            $null = $child.Handle
            $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($row.ProcessId)"
            if ($null -ne $current -and $current.CreationDate -eq $row.CreationDate -and -not $child.HasExited) {
                $child.Kill()
                $null = $child.WaitForExit(5000)
            }
        } finally { $child.Dispose() }
    }
}

try {
    foreach ($key in $keys) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $null, 'Process')
    }
    $env:LOCALTERM_CONPTY_PROVIDER = $ConptyProvider
    if ($WorkerStartupFailure -ne 'none') { $env:LOCALTERM_WORKER_STARTUP_FAILURE = $WorkerStartupFailure }
    if ($MidlineSmoke) { $env:LOCALTERM_MIDLINE_SMOKE = '1' }
    if ($AppReadLine) { $env:LOCALTERM_APP_READLINE = '1' }
    if ($PortableTools) { $env:LOCALTERM_PORTABLE_TOOLS = '1' }
    if ($PortableToolsCheck) { $env:LOCALTERM_PORTABLE_TOOLS_CHECK = '1' }
    if ($MidlineModule) {
        $env:LOCALTERM_MIDLINE_MODULE = $MidlineModule
        # Windows PowerShell preloads PSReadLine before -NoExit/-Command.
        # Select it for this owned process BEFORE startup, not after duplicate
        # global cmdlets/assemblies have already been registered.
        $env:PSModulePath = (Split-Path -Parent (Split-Path -Parent $MidlineModule)) + ';' + $savedPSModulePath
    }
    if ($ConptyProvider -eq 'app-local') { $env:LOCALTERM_CONPTY_EXPERIMENT = '1' }
    if ($PreviewBackground) { $env:LOCALTERM_PREVIEW_BACKGROUND = $PreviewBackground }
    if ($BackgroundSmoke) { $env:LOCALTERM_BACKGROUND_SMOKE = '1' }
    if ($GpuTextFrameCheck) { $env:LOCALTERM_GPU_TEXT_FRAME_CHECK = '1' }
    if ($ViewportSmoke) { $env:LOCALTERM_VIEWPORT_SMOKE = '1' }
    if ($KittyImageSmoke) { $env:LOCALTERM_KITTY_IMAGE_SMOKE = '1' }
    if ($KittyImageLegacyReference) { $env:LOCALTERM_KITTY_IMAGE_REFERENCE = '1' }
    if ($ThaiTuiSmoke) { $env:LOCALTERM_THAI_TUI_SMOKE = '1'; $env:LOCALTERM_CONPTY_WIDTH = $ConptyWidth; if ($RequireThaiModel -or $ConptyProvider -eq 'app-local') { $env:LOCALTERM_THAI_MODEL_REQUIRED = '1' }; if ($ThaiTuiLegacy) { $env:LOCALTERM_THAI_TUI_LEGACY = '1' } }
    elseif ($MouseSmoke) { $env:LOCALTERM_MOUSE_SMOKE = '1' }
    elseif ($Mode -eq 'window') { $env:LOCALTERM_WINDOW_SMOKE = '1' }
    elseif ($Mode -eq 'input') { $env:LOCALTERM_INPUT_SMOKE = '1' }
    elseif ($Mode -eq 'lifecycle') {
        $env:LOCALTERM_LIFECYCLE_SMOKE = '1'
        $env:LOCALTERM_LIFECYCLE_PSS = if ($PssDiagnostics -eq 'disabled') { '0' } else { '1' }
    }
    elseif ($Mode -eq 'burst-title') {
        $env:LOCALTERM_TERMINAL_CASE = 'burst'
        $env:LOCALTERM_TITLE_BACKPRESSURE_SMOKE = '1'
    }
    elseif ($Mode -in @('exit', 'burst', 'bad-shell', 'profile', 'profile-paced', 'font-angsana', 'font-leelawadee', 'font-system', 'font-roomy', 'font-native', 'font-native-roomy', 'image-paste')) {
        if ($Mode -eq 'bad-shell' -and (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\localterm-owned-missing-shell-4a9130c0.exe'))) { throw 'Missing-shell fixture path unexpectedly exists; refusing launch.' }
        $env:LOCALTERM_TERMINAL_CASE = $Mode
        if ($Mode -eq 'image-paste') {
            $marker = Join-Path ([IO.Path]::GetDirectoryName($exe)) 'portable-data'
            $env:LOCALTERM_EXPECT_IMAGE_ROOT = if (Test-Path -LiteralPath $marker -PathType Container) { Join-Path $marker 'cache\clipboard' } else { $env:TEMP }
        }
    }
    else { $env:LOCALTERM_TERMINAL_SMOKE = '1' }

    if ($etwDiagnostic) {
        if ($exe.Contains('"')) { throw 'Invalid native executable path.' }
        $process = Start-Process -FilePath $EtwLaunchHelper -ArgumentList @('--launch', ('"' + $exe + '"'), ('"' + $EtwGateDirectory + '"')) -WorkingDirectory $workspace -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    } else {
        $process = Start-Process -FilePath $exe -WorkingDirectory $workspace -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    }
    # Retaining Handle before WaitForExit avoids the PS5.1 null ExitCode bug.
    $null = $process.Handle
    if ($Mode -in @('profile', 'profile-paced')) {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while (-not $process.WaitForExit(250)) {
            $process.Refresh()
            if ($process.HasExited) { break }
            $cpuMs = $process.TotalProcessorTime.TotalMilliseconds
            $peakWorkingSet = [Math]::Max($peakWorkingSet, $process.PeakWorkingSet64)
            $sampledWorkingSet = [Math]::Max($sampledWorkingSet, $process.WorkingSet64)
            $resourceSamples++
            $resourceElapsedMs = $watch.Elapsed.TotalMilliseconds
            if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) { $timedOut = $true; break }
        }
        $watch.Stop()
    } else { $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000) }
    if ($timedOut) {
        # The original deadline already failed. Never clear timedOut even if
        # the target exits during this bounded, post-verdict diagnostic.
        if ($CaptureOwnedStacksOnTimeout -and -not $process.HasExited) {
            $captureProcess = $null
            try {
                $cdb = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe'
                $sig = Get-AuthenticodeSignature -LiteralPath $cdb
                if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'Microsoft CDB signature required.' }
                if (-not [string]::Equals($process.MainModule.FileName, $exe, [StringComparison]::OrdinalIgnoreCase)) { throw 'Owned process executable identity mismatch.' }
                $stackCapture = Join-Path $logs ($name + '.post-timeout.stacks.log')
                $symbolCache = Join-Path $env:LOCALAPPDATA 'Letta\tools\windows-debugger\symbols'
                $symbolPath = [IO.Path]::GetDirectoryName($exe) + ';srv*' + $symbolCache + '*https://msdl.microsoft.com/download/symbols'
                # Only our retained root PID, never a name-based/foreign attach.
                # Basic stacks and lock ownership only: no memory/heap dumps.
                $captureArgs = @('-pv','-nosqm','-p',([string]$process.Id),'-y',('"'+$symbolPath+'"'),'-c','"~* k;!locks;q"')
                $captureProcess = Start-Process -FilePath $cdb -ArgumentList $captureArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput $stackCapture -RedirectStandardError ($stackCapture + '.stderr')
                $null = $captureProcess.Handle
                if (-not $captureProcess.WaitForExit(20000)) { $captureProcess.Kill(); $captureProcess.WaitForExit() }
            } catch { Write-Warning "Post-timeout stack capture failed: $_" }
            finally {
                if ($null -ne $captureProcess) {
                    if (-not $captureProcess.HasExited) { $captureProcess.Kill(); $captureProcess.WaitForExit() }
                    $captureProcess.Dispose()
                }
            }
        }
        $remaining = @(Get-OwnedDescendants $process.Id $started)
        Stop-OwnedDescendants $remaining
        if (-not $process.HasExited) { $process.Kill(); $null = $process.WaitForExit(5000) }
    }
    if ($process.HasExited) { $code = $process.ExitCode }
    # Keep the root handle alive so its PID cannot be recycled during this check.
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        $live = @(Get-OwnedDescendants $process.Id $started)
        if ($live.Count -eq 0) { break }
        Start-Sleep -Milliseconds 500
    }
    if ($live.Count -gt 0) {
        $remaining = $live
        Stop-OwnedDescendants $remaining
    }
} catch {
    $failure = $_
    # Even harness failures must not leave the exact process we started alive.
    if ($null -ne $process -and -not $process.HasExited) {
        try { $process.Kill(); $null = $process.WaitForExit(5000) }
        catch { Write-Warning "Owned root cleanup failed for test process $($process.Id): $_" }
    }
    throw $failure
} finally {
    foreach ($key in $keys) {
        if ($saved.ContainsKey($key)) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    }
    [Environment]::SetEnvironmentVariable('PSModulePath', $savedPSModulePath, 'Process')
}

$text = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw -Encoding UTF8 } else { '' }
$critical = $text -match '(?im)^error(?:\(|:)|panic|Segmentation fault|reached unreachable|memory leaked'
if ($Mode -eq 'bad-shell') {
    # Negative fixture: allow only the exact expected FileNotFound error.
    $critical = $text -match '(?i)panic|Segmentation fault|reached unreachable|memory leaked' -or @([regex]::Matches($text, '(?im)^error(?:\([^)]*\))?:[^\r\n]*') | Where-Object { $_.Value -notmatch '^error: FileNotFound$' }).Count -gt 0
}
$bmp = Join-Path $logs 'terminal-frame.bmp'
$freshFrame = $false
$bmpHash = $null
$frameArtifact = $null
if ($Mode -ne 'window' -and (Test-Path -LiteralPath $bmp)) {
    $freshFrame = (Get-Item -LiteralPath $bmp).LastWriteTime -ge $started
    if ($freshFrame) {
        $bmpHash = (Get-FileHash -LiteralPath $bmp -Algorithm SHA256).Hash
        $frameArtifact = Join-Path $logs ($name + '.frame.bmp')
        Copy-Item -LiteralPath $bmp -Destination $frameArtifact
        if ((Get-FileHash -LiteralPath $frameArtifact -Algorithm SHA256).Hash -ne $bmpHash) { throw 'Controlled frame archive hash mismatch.' }
    }
}
$receipt = if ($Mode -ne 'window') { $text -match 'controlled terminal marker\+Thai parsed' -and $text -match 'native terminal smoke: frames=[1-9]' } else { $text -match 'core ticks=21; mailbox requests=21; terminal surfaces=0' }
if ($Mode -eq 'input') { $receipt = $receipt -and $text -match 'keyboard KeyEvent roundtrip ASCII\+Thai\+surrogate\+Enter verified' -and $text -match 'WM_CHAR repeat=2 verified' }
if ($MidlineSmoke) { $receipt = $receipt -and $text -match 'controlled interactive PSReadLine arrow midline ASCII\+Thai buffer/cells/caret matched' }
$actualAppReadLine = $AppReadLine -or $text -match 'app-owned PSReadLine startup verified: APP_READLINE_ACTIVE\|[0-9A-Fa-f]{64}'
$actualPortableTools = $PortableTools -or $text -match 'portable tools child bootstrap verified:'
if ($actualAppReadLine) { $receipt = $receipt -and $text -match 'app-owned PSReadLine startup verified: APP_READLINE_ACTIVE\|[0-9A-Fa-f]{64}' }
if ($PortableTools) { $receipt = $receipt -and $text -match 'portable tools child bootstrap verified: private home/history; exact node/npm/npx/letta entrypoints' }
if ($PortableToolsCheck) { $receipt = $receipt -and $text -match 'controlled portable tools Node/npm/profile/offline-install/installed-cli/cwd-guard verified' }
if ($Mode -eq 'lifecycle') { $receipt = $receipt -and $text -match 'terminal lifecycle 20 cycles after warmup' -and @([regex]::Matches($text, 'terminal cycle=\d+ handles=')).Count -eq 21 }
if ($Mode -eq 'exit') { $receipt = $receipt -and $text -match 'controlled natural child exit observed' }
if ($Mode -eq 'burst') { $receipt = $receipt -and $text -match 'controlled output burst active at close' }
if ($Mode -eq 'burst-title') { $receipt = $receipt -and $text -match 'controlled OSC title stream observed at close' -and $text -match 'controlled title backpressure UI queue full' }
if ($MouseSmoke) {
    $receipt = $receipt -and $text -match 'controlled mouse drag selection \+ wheel scrollback up/down \+ capture-loss release verified' `
        -and $text -match 'controlled CtrlC selected copy \+ CtrlShiftC \+ right-click copy match selected text; in-memory sink only' `
        -and $text -match 'controlled CtrlC without selection reached ConPTY child as ETX; sink unchanged' `
        -and $text -match 'controlled CtrlV \+ CtrlShiftV UTF8 paste roundtrip through ConPTY verified; synthetic clipboard only'
}
if ($ConptyProvider -eq 'app-local') { $receipt = $receipt -and $text -match 'experimental app-local ConPTY loaded from executable directory' }
if ($RequireThaiModel -or ($ThaiTuiSmoke -and $ConptyProvider -eq 'app-local')) { $receipt = $receipt -and $text -match 'paced redraw matched direct VT cells\+graphemes\+cursor; strict regression' }
if ($GpuTextFrameCheck) { $receipt = $receipt -and $text -match 'GPU worker real-terminal RGBA parity passed.*different_bytes=0' -and $text -match 'GPU text parity completed checks=[1-9][0-9]* max_glyphs=[0-9]+ failures=0' -and $text -match 'GPU text parity close ack=1 exit=0 jobempty=1 forced=0' }
if ($BackgroundSmoke) { $receipt = $receipt -and $text -match 'controlled background RGB/default/SGR49/EL fixture parsed' }
if ($KittyImageSmoke) {
    $receipt = $receipt -and $text -match 'Kitty image GDI phase=red pixels=' -and $text -match 'Kitty image GDI phase=green pixels=' -and $text -match 'Kitty image GDI phase=removed green_pixels=' -and $text -match 'Kitty image all phases verified after GDI paint'
    foreach ($phase in 1..3) { $receipt = $receipt -and $text -match "Kitty image raw frame phase=$phase bytes=[1-9][0-9]* sha256=[a-f0-9]{64}" }
    if ($KittyImageLegacyReference) { $receipt = $receipt -and $text -match 'Kitty legacy reference enabled; parent GL expected' }
    else { $receipt = $receipt -and $text -match 'remote host experimental inline image snapshot transport enabled' -and $text -match 'parent no GL/AMD modules; worker owns GPU' -and $text -match 'remote host worker close ack=1 exit=0 jobempty=1 forced=0' }
}
if ($ViewportSmoke) { $receipt = $receipt -and $text -match 'controlled terminal viewport odd resize/minimize/restore/return-size/synthetic-DPI dispatched' -and $text -match 'controlled terminal viewport current-size frames verified presentations=(?:[4-9]|[1-9][0-9]+) returned_original=1' -and $text -match 'controlled viewport delayed real received frame until UI epoch advanced' -and $text -match 'controlled viewport actual stale returned frame discarded count=[1-9][0-9]*' -and $text -match 'remote host worker close ack=1 exit=0 jobempty=1 forced=0' }
$profileCloseBudget = $null
if ($Mode -in @('profile', 'profile-paced')) {
    # Intended autoclose is15s. Allow startup/teardown margin, not48s starvation.
    $profileCloseBudget = ((Get-Date) - $started).TotalSeconds -le 25
    $receipt = $receipt -and $text -match 'controlled profile client=1920x1080 no-activate' -and $text -match 'controlled output burst active at close' -and $resourceSamples -gt 0 -and $profileCloseBudget
}
if ($Mode -eq 'bad-shell') { $receipt = $text -match 'controlled missing-shell preflight' -and $text -match '(?m)^error: FileNotFound\r?$' -and $text -notmatch 'starting command command=' }
if ($Mode -eq 'image-paste') { $receipt = $receipt -and $text -match 'controlled image core/PTy quoted path parsed as one literal; independent GDI\+ PNG pixels verified' -and $text -match 'controlled image staged portable=(true|false)' }
$workerFailureFixture = $WorkerStartupFailure -ne 'none'
if ($workerFailureFixture) {
    $expectedWorkerError = switch ($WorkerStartupFailure) { 'io' { 'ControlledIoSpawnFailure' }; 'title' { 'ControlledInitialTitleFailure' }; default { 'ControlledRendererSpawnFailure' } }
    $critical = $text -match '(?i)panic|Segmentation fault|reached unreachable|memory leaked' -or @([regex]::Matches($text, '(?im)^error(?:\([^)]*\))?:[^\r\n]*') | Where-Object { $_.Value -ne "error: $expectedWorkerError" }).Count -gt 0
    $receipt = $text -match "controlled worker startup injection=$WorkerStartupFailure" -and $text -match "(?m)^error: $expectedWorkerError\r?$" -and $text -notmatch 'starting command command='
    if ($WorkerStartupFailure -eq 'io') {
        $receipt = $receipt -and $text -match 'controlled worker startup started=renderer' -and $text -match 'controlled worker startup quarantined' -and $text -match 'Windows renderer joined before failed startup cleanup'
        $receipt = $receipt -and $text.IndexOf('controlled worker startup quarantined') -lt $text.IndexOf('Windows renderer joined before failed startup cleanup')
    } else { $receipt = $receipt -and $text -notmatch 'Windows renderer joined before failed startup cleanup|controlled worker startup started=' }
}
$expectedCode = if ($Mode -eq 'bad-shell' -or $workerFailureFixture) { 1 } else { 0 }
$passed = $null -ne $code -and $code -eq $expectedCode -and -not $timedOut -and $remaining.Count -eq 0 -and -not $critical -and $receipt -and ($workerFailureFixture -or $Mode -in @('window', 'bad-shell') -or $freshFrame)
$resultReceipt = [ordered]@{
    name = $name; mode = $Mode; executable = $exe; sha256 = (Get-FileHash -LiteralPath $exe).Hash
    worker_startup_failure = $WorkerStartupFailure
    pss_diagnostics = if ($Mode -eq 'lifecycle') { $PssDiagnostics } else { $null }
    readiness_evidence = -not $workerFailureFixture -and $PssDiagnostics -ne 'disabled' -and -not $CaptureOwnedStacksOnTimeout -and $Mode -ne 'burst-title' -and -not $MouseSmoke -and -not $ThaiTuiSmoke -and -not $MidlineSmoke -and -not $actualAppReadLine -and -not $actualPortableTools -and -not $BackgroundSmoke -and -not $PreviewBackground -and $ConptyProvider -eq 'system'
    mouse_smoke = [bool]$MouseSmoke
    thai_tui_diagnostic = [bool]$ThaiTuiSmoke
    midline_edit_diagnostic = [bool]$MidlineSmoke
    app_owned_readline = [bool]$actualAppReadLine
    portable_tools = [bool]$actualPortableTools
    portable_tools_check = [bool]$PortableToolsCheck
    midline_module_manifest = $MidlineModule
    midline_module_manifest_sha256 = if ($MidlineModule) { (Get-FileHash -LiteralPath $MidlineModule).Hash } else { $null }
    gpu_text_frame_check = [bool]$GpuTextFrameCheck
    thai_tui_legacy = [bool]$ThaiTuiLegacy
    conpty_width_diagnostic = $ConptyWidth
    conpty_provider_diagnostic = $ConptyProvider
    background_diagnostic = [bool]$BackgroundSmoke
    kitty_image_diagnostic = [bool]$KittyImageSmoke
    kitty_image_legacy_reference = [bool]$KittyImageLegacyReference
    preview_background = $PreviewBackground
    thai_model_required = [bool]($RequireThaiModel -or ($ThaiTuiSmoke -and $ConptyProvider -eq 'app-local'))
    post_timeout_stack_capture = $stackCapture
    started = $started.ToString('o'); finished = (Get-Date).ToString('o'); exit_code = $code
    passed = $passed; expected_exit_code = $expectedCode; timed_out = $timedOut; cleaned_descendants = @($remaining | ForEach-Object { $_.ProcessId })
    critical_log = $critical; fresh_frame = $freshFrame; frame_sha256 = $bmpHash
    frame_artifact = $frameArtifact
    profile_close_within_25s = $profileCloseBudget
    host_resources = if ($Mode -in @('profile', 'profile-paced')) { [ordered]@{ scope='native parent only; excludes PowerShell/ConHost/GPU/compositor; no-activate'; sample_interval_ms=250; samples=$resourceSamples; observed_until_ms=$resourceElapsedMs; cpu_ms_observed=$cpuMs; cpu_percent_one_core=if($resourceElapsedMs -gt 0){100.0*$cpuMs/$resourceElapsedMs}else{$null}; os_peak_working_set_bytes_observed=$peakWorkingSet; sampled_working_set_peak_bytes=$sampledWorkingSet } } else { $null }
    stdout = $stdout; stderr = $stderr
}
if ($etwDiagnostic) {
    $resultReceipt['etw_suspended_diagnostic'] = $true
    $resultReceipt['readiness_evidence'] = $false
}
$resultReceipt | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $logs 'results.jsonl') -Encoding UTF8
Get-Content -LiteralPath $stderr -Tail 20 -Encoding UTF8 | ForEach-Object {
    if ($_.Length -gt 800) { $_.Substring(0, 800) + ' ... [full line retained in stderr log]' } else { $_ }
}
if ($null -ne $process) { $process.Dispose() }
if (-not $passed) { throw "Native smoke failed; inspect $stderr and results.jsonl (exit=$code timeout=$timedOut)." }
if ($etwDiagnostic) { "DIAGNOSTIC $name exit=$code readiness_evidence=false" }
else { "PASS $name exit=$code" }
