//! Synthetic text clipboard diagnostic only. No OS clipboard or VM access.
const std = @import("std");

pub const unicode_text = "paste ไทย 😀";
pub const etx_marker = "CLIPBOARD_TEXT_ETX";
pub const selected_copy_marker = "controlled CtrlC selected copy + CtrlShiftC + right-click copy match selected text; in-memory sink only";
pub const etx_verified_marker = "controlled CtrlC without selection reached ConPTY child as ETX; sink unchanged";
pub const paste_verified_marker = "controlled CtrlV + CtrlShiftV UTF8 paste roundtrip through ConPTY verified; synthetic clipboard only";

pub fn acknowledgement(alloc: std.mem.Allocator, phase: u8, text: []const u8) ![]u8 {
    if (phase != 1 and phase != 2) return error.InvalidClipboardFixturePhase;
    const encoder = std.base64.standard.Encoder;
    const encoded = try alloc.alloc(u8, encoder.calcSize(text.len));
    defer alloc.free(encoded);
    _ = encoder.encode(encoded, text);
    return std.fmt.allocPrint(alloc, "CLIPBOARD_TEXT_V{d}:{s}", .{ phase, encoded });
}

// Read actual ConPTY input; do not use PowerShell clipboard cmdlets. Ctrl+C
// is intentionally read as ETX so the fixture survives to test both pastes.
// This is transport evidence, not a test of Linux SIGINT handling.
pub const command =
    \\for($n=0;$n -lt 200;$n++){[Console]::WriteLine('SCROLL_LINE_'+$n)}
    \\[Console]::WriteLine('LOCALTERM_RENDER_SMOKE')
    \\$e=[string][char]27; [Console]::WriteLine($e+'[31mRED'+$e+'[0m ไทย')
    // ConPTY emits characters outside the active keyboard layout as text on
    // VK_MENU key-up (Alt-numpad commits), including UTF-16 surrogate pairs.
    // Normal key-ups mirror key-downs and must not be appended a second time.
    \\Add-Type -ErrorAction Stop -TypeDefinition @'
    \\using System; using System.ComponentModel; using System.Runtime.InteropServices; using System.Text; using System.Threading;
    \\public static class ClipboardFixtureInput {
    \\ [StructLayout(LayoutKind.Explicit, Size=20)] public struct Record {
    \\  [FieldOffset(0)] public ushort EventType; [FieldOffset(4)] public int KeyDown;
    \\  [FieldOffset(8)] public ushort Repeat; [FieldOffset(10)] public ushort VirtualKey;
    \\  [FieldOffset(12)] public ushort Scan; [FieldOffset(14)] public ushort Unicode;
    \\  [FieldOffset(16)] public uint Control;
    \\ }
    \\ [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr GetStdHandle(int n);
    \\ [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetConsoleMode(IntPtr h,out uint mode);
    \\ [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetConsoleMode(IntPtr h,uint mode);
    \\ [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetNumberOfConsoleInputEvents(IntPtr h,out uint count);
    \\ [DllImport("kernel32.dll",SetLastError=true,ExactSpelling=true)] static extern bool ReadConsoleInputW(IntPtr h,[Out] Record[] records,uint count,out uint read);
    \\ static void Check(bool ok) { if(!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    \\ public static bool IsTextCommit(Record key) { return key.EventType==1 && key.Unicode!=0 && (key.KeyDown!=0 || key.VirtualKey==0x12); }
    \\ public static void Run() {
    \\  if(Marshal.SizeOf(typeof(Record))!=20 || Marshal.OffsetOf(typeof(Record),"KeyDown").ToInt32()!=4 || Marshal.OffsetOf(typeof(Record),"Repeat").ToInt32()!=8 || Marshal.OffsetOf(typeof(Record),"Unicode").ToInt32()!=14 || Marshal.OffsetOf(typeof(Record),"Control").ToInt32()!=16) throw new Exception("INPUT_RECORD ABI mismatch");
    \\  IntPtr input=GetStdHandle(-10); uint original; Check(GetConsoleMode(input,out original));
    \\  Check(SetConsoleMode(input,original & ~0x207u));
    \\  try {
    \\   var buffer=new StringBuilder(); var records=new Record[32]; int lines=0,interrupts=0;
    \\   var deadline=DateTime.UtcNow.AddSeconds(8); Console.WriteLine("MOUSE_READY");
    \\   while(lines<2 && DateTime.UtcNow<deadline) {
    \\    uint count; Check(GetNumberOfConsoleInputEvents(input,out count)); if(count==0){Thread.Sleep(5);continue;}
    \\    uint read; Check(ReadConsoleInputW(input,records,Math.Min(count,(uint)records.Length),out read));
    \\    for(int n=0;n<read;n++) {
    \\     var key=records[n];
    \\     if(!IsTextCommit(key)) continue;
    \\     if(key.Repeat==0 || key.Repeat>4096) throw new Exception("Invalid synthetic key repeat");
    \\     for(int repeat=0;repeat<key.Repeat;repeat++) {
    \\      char value=(char)key.Unicode;
    \\      if(value==3){if(++interrupts!=1)throw new Exception("Unexpected synthetic ETX count");buffer.Clear();Console.WriteLine("CLIPBOARD_TEXT_ETX");continue;}
    \\      if(interrupts!=1)throw new Exception("Unexpected input before synthetic ETX");
    \\      if(value==13){if(++lines>2)throw new Exception("Unexpected synthetic line count");Console.WriteLine("CLIPBOARD_TEXT_V"+lines+":"+Convert.ToBase64String(Encoding.UTF8.GetBytes(buffer.ToString())));buffer.Clear();continue;}
    \\      if(value==10)continue;
    \\      if(buffer.Length>=4096)throw new Exception("Synthetic clipboard input limit");buffer.Append(value);
    \\     }
    \\    }
    \\   }
    \\   if(lines!=2 || interrupts!=1)throw new Exception("Synthetic clipboard input deadline/incomplete");
    \\   Console.WriteLine("CLIPBOARD_TEXT_CHILD_COMPLETE");
    \\  } finally { Check(SetConsoleMode(input,original)); }
    \\ }
    \\}
    \\'@
    \\[ClipboardFixtureInput]::Run()
    \\[Threading.Thread]::Sleep(60000)
;

test "clipboard fixture acknowledgements compare exact UTF8 without interpreting text" {
    const ascii = try acknowledgement(std.testing.allocator, 1, "hello");
    defer std.testing.allocator.free(ascii);
    try std.testing.expectEqualStrings("CLIPBOARD_TEXT_V1:aGVsbG8=", ascii);
    const unicode = try acknowledgement(std.testing.allocator, 2, unicode_text);
    defer std.testing.allocator.free(unicode);
    try std.testing.expect(std.mem.startsWith(u8, unicode, "CLIPBOARD_TEXT_V2:"));
    const encoded = unicode["CLIPBOARD_TEXT_V2:".len..];
    const decoder = std.base64.standard.Decoder;
    const bytes = try std.testing.allocator.alloc(u8, try decoder.calcSizeForSlice(encoded));
    defer std.testing.allocator.free(bytes);
    try decoder.decode(bytes, encoded);
    try std.testing.expectEqualStrings(unicode_text, bytes);
    try std.testing.expectError(error.InvalidClipboardFixturePhase, acknowledgement(std.testing.allocator, 0, "no"));
}
