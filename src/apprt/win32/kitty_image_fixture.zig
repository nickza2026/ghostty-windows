//! Public, synthetic RGBA bytes through the actual ConPTY child output path.
//! No file/clipboard access. Parser/storage/upload/paint are NOT bypassed.
const std = @import("std");
const initial = "\x1b[2J\x1b[H\x1b[?25lLOCALTERM_RENDER_SMOKE\r\n\x1b[31mRED\x1b[0m ไทย\r\n";
pub const red = "\x1b[5;1H\x1b_Ga=T,t=d,f=32,s=1,v=1,i=77,p=1,q=2,c=8,r=4,z=1,C=1;/wAA/w==\x1b\\";
pub const green = "\x1b[5;1H\x1b_Ga=T,t=d,f=32,s=1,v=1,i=77,p=1,q=2,c=8,r=4,z=1,C=1;AP8A/w==\x1b\\";
pub const remove = "\x1b_Ga=d,d=I,i=77,q=2\x1b\\";
fn encode(comptime input: []const u8) [std.base64.standard.Encoder.calcSize(input.len)]u8 {
    @setEvalBranchQuota(100_000);
    var bytes: [std.base64.standard.Encoder.calcSize(input.len)]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&bytes, input);
    return bytes;
}
pub const command = "$o=[Console]::OpenStandardOutput(); foreach($s in @('" ++ encode(initial) ++ "','" ++ encode(red) ++ "','" ++ encode(green) ++ "','" ++ encode(remove) ++ "')) { $a=[Convert]::FromBase64String($s); $o.Write($a,0,$a.Length); $o.Flush(); [Threading.Thread]::Sleep(800) }; [Threading.Thread]::Sleep(60000)";
