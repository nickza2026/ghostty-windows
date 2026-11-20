//! Controlled source/consumer only; no Windows clipboard API access.
const std = @import("std");

pub fn png(alloc: std.mem.Allocator) ![]u8 {
    var dib: [48]u8 = @splat(0);
    std.mem.writeInt(u32, dib[0..4], 40, .little);
    std.mem.writeInt(i32, dib[4..8], 2, .little);
    std.mem.writeInt(i32, dib[8..12], -1, .little);
    std.mem.writeInt(u16, dib[12..14], 1, .little);
    std.mem.writeInt(u16, dib[14..16], 24, .little);
    @memcpy(dib[40..46], &[_]u8{ 0, 0, 255, 0, 255, 0 });
    return @import("clipboard_image.zig").fromDib(alloc, &dib);
}

// Parse a single PowerShell string literal, never execute the pasted text.
// GDI+ independently decodes the staged PNG and verifies its dimensions/colors.
pub const command =
    "Add-Type -AssemblyName System.Drawing; " ++
    "[Console]::WriteLine('LOCALTERM_RENDER_SMOKE'); $e=[string][char]27; " ++
    "[Console]::WriteLine($e+'[31mRED'+$e+'[0m ไทย'); " ++
    "[Console]::WriteLine('LOCALTERM_IMAGE_READY'); $s=[Console]::ReadLine(); " ++
    "$tokens=$null; $errors=$null; " ++
    "$null=[Management.Automation.Language.Parser]::ParseInput($s,[ref]$tokens,[ref]$errors); " ++
    "$t=@($tokens|Where-Object{$_.Kind -notin @('EndOfInput','NewLine')}); " ++
    "if($errors.Count -ne 0 -or $t.Count -ne 1 -or $t[0].Kind -ne 'StringLiteral'){throw 'unsafe/nonliteral fixture paste'}; " ++
    "$path=$t[0].Value; if(-not [IO.Path]::IsPathRooted($path)){throw 'relative fixture path'}; " ++
    "$root=$env:LOCALTERM_EXPECT_IMAGE_ROOT; " ++
    "if([string]::IsNullOrEmpty($root)){throw 'fixture expected-root environment missing'}; " ++
    "$full=[IO.Path]::GetFullPath($path); $prefix=$root.TrimEnd('\\')+'\\'; " ++
    "if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){ " ++
    "$n=[Math]::Min($full.Length,$prefix.Length); $i=0; while($i -lt $n -and $full[$i] -eq $prefix[$i]){$i++}; " ++
    "throw ('image root mismatch index='+$i+' path-length='+$full.Length+' root-length='+$prefix.Length+' actual-code='+[int]$full[$i]+' expected-code='+[int]$prefix[$i]) }; " ++
    "$b=[Drawing.Bitmap]::new($path); try { " ++
    "if($b.Width -ne 2 -or $b.Height -ne 1 -or $b.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid){throw 'PNG dimensions/format'}; " ++
    "$r=$b.GetPixel(0,0); $g=$b.GetPixel(1,0); " ++
    "if($r.R -ne 255 -or $r.G -ne 0 -or $r.B -ne 0 -or $r.A -ne 255 -or $g.R -ne 0 -or $g.G -ne 255 -or $g.B -ne 0 -or $g.A -ne 255){throw 'PNG pixel mismatch'} " ++
    "} finally {$b.Dispose()}; [Console]::WriteLine('LOCALTERM_IMAGE_OK'); " ++
    "[Threading.Thread]::Sleep(60000)";
