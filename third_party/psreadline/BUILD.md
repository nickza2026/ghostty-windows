# App-owned PSReadLine comparison build

Run from the repository using Windows PowerShell 5.1:

    powershell.exe -NoLogo -NoProfile -NonInteractive -File tools/windows/build-app-psreadline.ps1

This creates a new private `%LOCALAPPDATA%/Letta/app-psreadline-<GUID>` directory
and prints both absolute manifest paths. It never installs a module. Import only
the selected absolute manifest in a fresh owned process. Both modules are unsigned
app-owned source builds, not Microsoft-signed published releases.

`source-pin.json` pins the official annotated v2.0.0 tag, peeled commit, and ZIP
SHA256. The upstream LICENSE (MIT) is preserved here and in each module, alongside
the upstream module's License.txt. Reviewed upstream csproj targets net461 and
netcoreapp2.1 with floating PowerShellStandard.Library/Microsoft.CSharp packages;
upstream build scripts can install modules, clean, sign/catalog, and publish.
None of those projects/scripts/configs are executed or imported.

Our compiler.rsp and script directly run installed SDK 9.0.203's Roslyn compiler
against this machine's Windows .NET Framework and Windows PowerShell 5.1 assembly
references. No NuGet/feed/restore, signing keys, global installs, profile edits,
or execution-policy bypass are used. This targets the installed desktop framework,
not a claim of net461/downlevel portability. Reference/compiler hashes, source pin,
patch hashes, manifest/DLL paths and hashes are recorded in build-provenance.json.
Source, response file, resource and archive remain in the unique build directory.

The only upstream source difference between variants is the exact single-match
width-before.txt -> width-after.txt replacement in Render.cs. Both get the same
generated build version attributes. NonSpacingMark and EnclosingMark return zero
before existing wide/control classification. Existing code already permits zero
string width (empty/escape-only strings); cell-slicing/rendering consumers need
interactive validation. This is not grapheme clustering: surrogate pairs, ZWJ,
spacing marks, orphan combining marks, wrapping and terminal-specific ambiguous
width remain outside the correction. It changes neither ConPTY nor host defaults.

The build runs test-width.ps1 separately in fresh owned -NoProfile -NonInteractive
processes, with private history path and SaveNothing. Reflection invokes the actual
compiled private char-width function for ASCII/control/CJK, Thai base/marks,
accent/enclosing mark, and the Thai prefix sum. To demonstrate the regression,
run that test with the original manifest and `-Variant patched` (must fail).
These checks do not substitute for the parent's same-host/provider interactive
cursor/buffer tests. No claim of an interactive fix is made here.
