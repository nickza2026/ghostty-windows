'use strict';
const assert = require('node:assert/strict');

/** Diagnostic input to the current owned terminal HWND only; no global input. */
function inputScript(pid, line, expectedTitle) {
  assert(Number.isSafeInteger(pid) && pid > 0 && pid <= 0xffffffff);
  assert(typeof line === 'string' && line.length < 3000 && line.isWellFormed() && !/[\x00-\x1f\x7f-\x9f]/.test(line));
  assert(expectedTitle === undefined || expectedTitle === 'Sandbox');
  const encoded = Buffer.from(line, 'utf8').toString('base64');
  return `Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class OwnedNativeInput {
 public delegate bool Callback(IntPtr h, IntPtr p);
 [DllImport("user32.dll")] public static extern bool EnumWindows(Callback f,IntPtr p);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode,ExactSpelling=true)] public static extern int GetClassNameW(IntPtr h,System.Text.StringBuilder name,int count);
 [DllImport("user32.dll",CharSet=CharSet.Unicode,ExactSpelling=true)] public static extern int GetWindowTextW(IntPtr h,System.Text.StringBuilder name,int count);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtrW(IntPtr h,int i);
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public int left,top,right,bottom;}
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
}
'@;
$script:found=[IntPtr]::Zero; [OwnedNativeInput]::EnumWindows({param($h,$p) $id=[uint32]0; [void][OwnedNativeInput]::GetWindowThreadProcessId($h,[ref]$id); if($id -eq ${pid}){$name=New-Object Text.StringBuilder 256;[void][OwnedNativeInput]::GetClassNameW($h,$name,256);if($name.ToString() -eq 'localterm-dev.window-prototype' -and [OwnedNativeInput]::IsWindowVisible($h)){$script:found=$h;return $false}}; return $true},[IntPtr]::Zero)|Out-Null;
$h=$script:found; if($h -eq [IntPtr]::Zero){throw 'No owned terminal HWND'};
$titleText=New-Object Text.StringBuilder 512;[void][OwnedNativeInput]::GetWindowTextW($h,$titleText,512);
${expectedTitle ? "if($titleText.ToString() -ne 'Sandbox'){throw 'Owned native title is not Sandbox'};" : ''}
$r=New-Object OwnedNativeInput+Rect; if(-not [OwnedNativeInput]::GetWindowRect($h,[ref]$r)){throw 'No owned rect'};
$right=[OwnedNativeInput]::GetSystemMetrics(76)+[OwnedNativeInput]::GetSystemMetrics(78);
if($r.left -lt ($right+64) -or ([OwnedNativeInput]::GetWindowLongPtrW($h,-20).ToInt64() -band 0x08000000) -eq 0 -or [OwnedNativeInput]::GetForegroundWindow() -eq $h){throw 'Unsafe native position/focus'};
$line=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${encoded}'));
foreach($c in $line.ToCharArray()){$id=[uint32]0;[void][OwnedNativeInput]::GetWindowThreadProcessId($h,[ref]$id);if($id -ne ${pid}){throw 'HWND ownership changed'};[void][OwnedNativeInput]::SendMessageW($h,0x0102,[IntPtr][int]$c,[IntPtr]::Zero)};
[void][OwnedNativeInput]::SendMessageW($h,0x0100,[IntPtr]13,[IntPtr]0x001c0001);
[void][OwnedNativeInput]::SendMessageW($h,0x0101,[IntPtr]13,[IntPtr](-1071906815));
@{offscreen=$true;noActivate=$true;ownedPid=${pid};characters=$line.Length;globalInput=$false;terminalClass='localterm-dev.window-prototype';verifiedSandboxTitle=${expectedTitle ? '$titleText.ToString()' : '$null'}}|ConvertTo-Json -Compress
`;
}
module.exports = { inputScript };
