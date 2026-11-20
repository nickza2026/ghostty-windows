param([Parameter(Mandatory=$true)][string]$PipeName)
$ErrorActionPreference='Stop'
try{
    Add-Type -Path (Join-Path $PSScriptRoot 'private-agent-bridge.cs')
    [GhosttyPrivateAgentBridge]::Run($PipeName)
}catch{
    [Console]::Error.WriteLine('Private agent transport failed; no global-agent fallback.')
    exit 1
}
