param([Parameter(Mandatory=$true)][string]$Node,[Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Probe)
$ErrorActionPreference='Stop'
try {
    Add-Type -Path (Join-Path $PSScriptRoot 'test-conpty.cs')
    exit [SandboxConPtyTest]::Run($Node,$Root,$Probe)
} catch { [Console]::Error.WriteLine('Owned ConPTY test failed: '+$_.Exception.GetType().Name);exit 1 }
