# Data-only checks of the reviewed smoke supervisor's startup-failure verdict.
# Load only its selected classification AST: never run the native launch body.
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'runtime-smoke.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Smoke supervisor must parse before classification tests.' }
$nodes = @($ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.IfStatementAst] -and
    $node.Extent.Text.StartsWith('if ($workerFailureFixture)')
}, $true))
if ($nodes.Count -ne 1) { throw 'Missing or ambiguous reviewed startup classification block.' }
$classify = [ScriptBlock]::Create($nodes[0].Extent.Text)
$io = "info: controlled worker startup started=renderer`ninfo: controlled worker startup injection=io`ninfo: controlled worker startup quarantined`ninfo(surface): Windows renderer joined before failed startup cleanup`nerror: ControlledIoSpawnFailure`n"
$renderer = "info: controlled worker startup injection=renderer`nerror: ControlledRendererSpawnFailure`n"
$title = "info: controlled worker startup injection=title`nerror: ControlledInitialTitleFailure`n"
$cases = @(
    @{ name='io rollback acknowledged'; kind='io'; text=$io; receipt=$true; critical=$false },
    @{ name='renderer never started'; kind='renderer'; text=$renderer; receipt=$true; critical=$false },
    @{ name='missing join cannot pass'; kind='io'; text=$io.Replace('Windows renderer joined before failed startup cleanup','not joined'); receipt=$false; critical=$false },
    @{ name='panic cannot hide behind expected error'; kind='io'; text=($io+"panic: simulated`n"); receipt=$true; critical=$true },
    @{ name='other error cannot hide'; kind='io'; text=($io+"error: UnexpectedFailure`n"); receipt=$true; critical=$true },
    @{ name='shell launch forbidden'; kind='io'; text=($io+"info: starting command command=synthetic`n"); receipt=$false; critical=$false },
    @{ name='absent renderer cannot claim join'; kind='renderer'; text=($renderer+"Windows renderer joined before failed startup cleanup`n"); receipt=$false; critical=$false },
    @{ name='missing quarantine cannot pass'; kind='io'; text=$io.Replace('controlled worker startup quarantined','not quarantined'); receipt=$false; critical=$false },
    @{ name='title failure starts no workers'; kind='title'; text=$title; receipt=$true; critical=$false },
    @{ name='title failure after worker start rejected'; kind='title'; text=($title+"controlled worker startup started=renderer`n"); receipt=$false; critical=$false }
)
foreach ($case in $cases) {
    $workerFailureFixture = $true
    $WorkerStartupFailure = $case.kind
    $text = $case.text
    $critical = $false
    $receipt = $false
    . $classify
    if ([bool]$critical -ne $case.critical -or [bool]$receipt -ne $case.receipt) {
        throw ('Startup classification failed: '+$case.name)
    }
}
Write-Output ('PASS '+$cases.Count+' startup-failure classification cases; no process launched.')
