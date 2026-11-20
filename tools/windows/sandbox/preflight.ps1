$ErrorActionPreference='Stop'
if(-not ('PortableWhpPreflight' -as [type])){
    Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class PortableWhpPreflight { [DllImport("WinHvPlatform.dll",ExactSpelling=true)] public static extern int WHvGetCapability(uint code,out int present,uint size,out uint written); [DllImport("kernel32.dll",ExactSpelling=true)] public static extern bool IsProcessorFeaturePresent(uint feature); }'
}
$present=0;$written=[uint32]0
$hr=[PortableWhpPreflight]::WHvGetCapability(0,[ref]$present,4,[ref]$written)
if($hr -ne 0 -or $present -eq 0 -or $written -ne 4){throw 'WHPX unavailable. No Windows feature or driver was changed; no software/host-shell fallback.'}
foreach($feature in @(36,37,38)){
    if(-not [PortableWhpPreflight]::IsProcessorFeaturePresent($feature)){throw 'This guest needs host SSSE3/SSE4.1/SSE4.2 support. No software or host-shell fallback was opened.'}
}
'WHPX_READY'
