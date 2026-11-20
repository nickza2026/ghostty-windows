//! Non-private ANSI/Thai diagnostic. Process success is NOT visual acceptance.
const std = @import("std");

const initial =
    "\x1b[?1049h\x1b[2J\x1b[H" ++
    "LOCALTERM_RENDER_SMOKE - Thai TUI diagnostic\r\n" ++
    "\x1b[31mRED\x1b[0m ไทย\r\n" ++
    "REG  | กำลังอ่านข้อมูล ผู้ใช้ น้ำ กุ้ง ปรับความจำ ทดสอบ | END\r\n" ++
    "\x1b[1mBOLD | กำลังอ่านข้อมูล ผู้ใช้ น้ำ กุ้ง ปรับความจำ ทดสอบ | END\x1b[0m\r\n" ++
    "\x1b[3mITAL | กำลังอ่านข้อมูล ผู้ใช้ น้ำ กุ้ง ปรับความจำ ทดสอบ | END\x1b[0m\r\n" ++
    "\x1b[9mSTRK | กำลังอ่านข้อมูล ผู้ใช้ น้ำ กุ้ง ปรับความจำ ทดสอบ | END\x1b[0m\r\n" ++
    "\x1b[2mDIM  | กำลังอ่านข้อมูล ผู้ใช้ น้ำ กุ้ง ปรับความจำ ทดสอบ | END\x1b[0m\r\n" ++
    "MIX  | ผ่าน \x1b[1m123 tests\x1b[0m และ \x1b[3mภาษาไทย\x1b[0m | END\r\n" ++
    "SPLT | ก\x1b[32mี้\x1b[0m น้ำ ผู้ใช้ กุ้ง | END\r\n" ++
    "\x1b[?2027hGC   | กำลังอ่านข้อมูล ผู้ใช้ น้ำ กุ้ง ปรับความจำ ทดสอบ | END\r\n" ++
    "\x1b[?2027lLEG  | กำลังอ่านข้อมูล ผู้ใช้ น้ำ กุ้ง ปรับความจำ ทดสอบ | END\r\n" ++
    "CUP  | OLD TEXT\r\nTUI_READY\r\n";

const repaint =
    "\x1b[14;1H\x1b[2KREPAINT | สถานะเก่า น้ำ ผู้ใช้" ++
    "\x1b[15;1H\x1b[2KREL | ภาษาไทย น้ำ ผู้ใช้ tail\x1b[4DTAIL" ++
    "\x1b[16;112Hน้ำกุ้งAB" ++
    "\x1b[14;1H\x1b[2KREPAINT | สถานะใหม่ กุ้ง กำลังทำงาน";
const final = "\x1b[12;1H\x1b[2KCUP  | เขียนซ้ำด้วย cursor absolute น้ำ ผู้ใช้ | END";
pub const output = initial ++ repaint ** 16 ++ final;

fn encode(comptime input: []const u8) [std.base64.standard.Encoder.calcSize(input.len)]u8 {
    @setEvalBranchQuota(100_000);
    var bytes: [std.base64.standard.Encoder.calcSize(input.len)]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&bytes, input);
    return bytes;
}

// Same bytes as output, paced to exercise actual intermediate repaint frames.
pub const command = "$a=[Convert]::FromBase64String('" ++ encode(initial) ++ "'); $b=[Convert]::FromBase64String('" ++ encode(repaint) ++ "'); $c=[Convert]::FromBase64String('" ++ encode(final) ++ "'); $o=[Console]::OpenStandardOutput(); $o.Write($a,0,$a.Length); for($n=0;$n -lt 16;$n++){$o.Write($b,0,$b.Length);$o.Flush();[Threading.Thread]::Sleep(30)}; $o.Write($c,0,$c.Length); $o.Flush(); [Threading.Thread]::Sleep(60000)";
