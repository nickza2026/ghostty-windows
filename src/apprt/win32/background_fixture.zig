//! Controlled default/RGB/indexed background + erase-to-end diagnostic.
const std = @import("std");
const output = "\x1b[2J\x1b[HLOCALTERM_RENDER_SMOKE - background BCE\r\n" ++
    "\x1b[31mRED\x1b[0m ไทย\r\n" ++
    "\x1b[49mDEFAULT+EL\x1b[K\r\n" ++
    "\x1b[48;2;30;30;30mRGB1E+EL\x1b[K\r\n" ++
    "RGB1E+SPACES " ++ " " ** 64 ++ "\x1b[0m\r\n" ++
    "\x1b[40mINDEX0+EL\x1b[K\r\n" ++
    "\x1b[49mRESET49+EL\x1b[K\r\n" ++
    "\x1b[48;2;18;52;86mRGB123456+EL\x1b[K\r\n" ++
    "\x1b[0mRESET0+EL\x1b[K\r\nBACKGROUND_READY";
const encoded = encoded: {
    @setEvalBranchQuota(100_000);
    var bytes: [std.base64.standard.Encoder.calcSize(output.len)]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&bytes, output);
    break :encoded bytes;
};
pub const command = "$b=[Convert]::FromBase64String('" ++ encoded ++ "');$o=[Console]::OpenStandardOutput();$o.Write($b,0,$b.Length);$o.Flush();[Threading.Thread]::Sleep(60000)";
