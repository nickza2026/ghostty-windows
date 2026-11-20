# ConPTY app-local experiment สำหรับ Thai TUI

## ขอบเขตและสถานะ

19 ตุลาคม 2026 ผู้ใช้เทียบ Herdr 0.9.3 ใน candidate53 กับ Windows Terminal แล้วรายงานว่า Windows Terminal ชัดปกติ ภาพที่ส่งทั้งสองเปิดตรวจได้ จึงตรวจ integration ฝั่งเรา ไม่แก้ repository/ไฟล์ของ Herdr และไม่ใช้ basic Thai typing ที่ผ่านก่อนหน้ารับรอง formatted TUI ทั้งหมด

ผู้ใช้อนุมัติ app-local experiment เวลา13:49 (“ได้ทำเลย”) การอนุมัตินี้ไม่ใช่ human acceptance ว่า Herdr หายแล้ว ไม่เปลี่ยน default terminal, driver, Windows settings หรือ production backend อัตโนมัติ และไม่มี commit/push

## หลักฐาน A/B build58

Build ผ่าน123/123 steps ใช้ ReleaseSafe/-j1, fixture byte stream ชุดเดียวส่งตรงเข้า Core Terminal reference และผ่าน owned PowerShell/ConPTY แล้วเทียบ codepoint/attached grapheme ทุกช่องรวมตำแหน่ง cursor ก่อนวินิจฉัยฟอนต์

| Provider | Width flags | Unicode-reference cell differences | Cursor expected/actual |
| --- | --- | --- | --- |
| System | 0 | 38 | 45 / 52 |
| App-local Microsoft | 0 | 0 | 45 / 45 |
| App-local Microsoft | 0x10 wcswidth | 0 | 45 / 45 |
| App-local Microsoft | 0x08 graphemes | 0 | 45 / 45 |

Receipts อยู่ใต้ `%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\phase3b-runtime`:

- `terminal-native-20261019-135836-107` system
- `terminal-native-20261019-135848-170` app-local default
- `terminal-native-20261019-135858-591` app-local wcswidth
- `terminal-native-20261019-135909-062` app-local graphemes

GetEnvironmentVariable/width flags ถูกตรวจจาก raw log จริง ไม่อาศัยชื่อ test อย่างเดียว System flags0x10/0x08 เคยได้ HRESULT0 แต่ cursor ยัง52 จึงไม่ใช้ S_OK รับรอง width semantics

Tail fixture ยาว52 UTF-16 units มี7 combining marks ขณะที่ direct reference cursor45 ภาพ static style fixture และ modern PNG ตรวจได้ แต่ **ยังไม่ใช่ Herdr dynamic rendering acceptance** ตัวเลข different cells ของ legacy reference อาจเป็น representation ของ SARA AM/ช่อง wide ไม่ใช่ทุก difference คือข้อความเสีย

## Runtime ที่ pin และขอบเขตความเชื่อถือ

- Official NuGet: `Microsoft.Windows.Console.ConPTY` เวอร์ชัน `1.25.260930003`
- Package SHA256: `02B07B349AF66D801159BDF9E440D4A1CE78BB951F37FC8609731665AFDAE7EE`
- `conpty.dll`: `FEEEF341D891643C62D30B6B07800BC70F0BC148F44CB8C3BEE84AA557AE805A`
- `OpenConsole.exe`: `3D66B23D0A71BB8EED2B77EDC8B9DF9BF54CE6C8FB74C863A30E760997F80586`
- ทั้งสองไฟล์ผ่าน Authenticode `Valid`, signer `Microsoft Corporation`
- SPDX MIT ตาม nuspec; provision เก็บ copyright/license, nuspec, API header และ manifest ร่วมกับ binaries

```powershell
.\tools\windows\provision-conpty-experiment.ps1
```

ดาวน์โหลดลง LocalAppData build cache ตรวจ pinned package hash ก่อน extract เฉพาะ fixed entries ของ x64 ลง `zig-out/conpty-ab/bin` ไม่ extract arbitrary paths ไม่ overwrite ไฟล์ต่าง hash ไม่เขียนผ่าน reparse-point ancestors และไม่ติดตั้งระบบ หาก hash/signature/path ไม่ผ่านให้หยุด ไม่ใช้ runtime ที่ไม่ผ่านแทน

## Provider lifetime และ fail-closed

`src/conpty_windows.zig` เลือก app-local ต่อเมื่อ explicit process env `LOCALTERM_CONPTY_PROVIDER=app-local` และ `LOCALTERM_CONPTY_EXPERIMENT=1` เท่านั้น Default ยังเป็น system

โหลด `conpty.dll` จาก directory ของ executable ปัจจุบันด้วย absolute path และ DLL-directory/System32 search flags ไม่ค้น cwd/PATH ไม่ยืม DLL/EXE จาก Herdr หรือ Windows Terminal และไม่ silently fallback เมื่อ explicit app-local โหลดไม่ได้

Resolve `ConptyCreatePseudoConsole`, `ConptyResizePseudoConsole`, `ConptyClosePseudoConsole` จาก DLL เดียวกัน เก็บ DLL reference ใน Pty นั้น ใช้ provider เดียวตลอดอายุ HPCON และ FreeLibrary หลัง ClosePseudoConsole กลับแล้วเท่านั้น Error path ก่อนสร้าง HPCON คืน DLL/pipe resources ตามลำดับเดิม

## Regression และ manual handoff

Build59 ผ่าน123/123 เพิ่ม16 paced repaints, CUP/EL, relative cursor rewrite และ Thai ใกล้ขอบ wrap ส่ง bytes เดียวกับ direct reference เปรียบเทียบ20แถว ไม่รับรองด้วย parse marker/red-pixels เพียงอย่างเดียว App-local harness บังคับ strict cell/grapheme/cursor equality ผ่านสองรอบ `terminal-native-20261019-140630-169` และ `terminal-native-20261019-140642-191`:0differentcells/cursor45ตรงreference,35frames/35paintsต่อรอบ ViewImageเปิดภาพรอบสองตรวจได้

System negative control ถูก reject ด้วย `ConptyUnicodeModelMismatch` จริง:38differentcells ไม่ใช่เพียงreceiptmissing รอบpacedนี้finalcursorของsystemเป็น45แล้ว ไม่ใช่52แบบfixtureแรก **จึงต้องคงcell/graphemeequalityไว้ ห้ามลดtestเหลือcursor-only** Negativecontrolเป็นexpectedfailureไม่ใช่แก้thresholdให้systemผ่าน

Candidate59 `zig-out/conpty-ab/bin/localterm-dev.exe` SHA256 `123F6E375BFC3F00322335DB3419D8321916348A5578FE62FAFC6C10EF239BF6` ยังexperimentalopt-in ไม่promoteproductionเอง เวลา14:09keyboardASCII/Thai/surrogate/Enter+repeat2,mouse/copy/wheel/releaseแบบin-memorysink,naturalchildexitผ่านเพิ่มเติมด้วยmodernproviderจริง ไม่แตะOSclipboard/UIfocus กำลังทวนstrictlifecycleโดยคงgatesเดิม ไม่บิลด์ทับmanualbinary

ใช้ preview แบบ opt-in นี้เพื่อรับ Herdrhumanacceptanceแยกจากsyntheticregression:

```powershell
.\tools\windows\preview.ps1 -Executable .\zig-out\conpty-ab\bin\localterm-dev.exe -AppLocalConpty
```

คำสั่งนี้เป็น human interactive preview ไม่ใช่ automated GUI acceptance ให้รัน Herdr เดิมและตรวจ/scroll ข้อความไทยเดิม ไม่ต้องสั่งแก้โปรเจกต์ใหม่เพื่อสร้าง output ไม่เปิด GUI แทนผู้ใช้ ไม่อ่าน clipboard/session ของผู้ใช้ และไม่ claim Herdr หายก่อนผู้ใช้ยืนยัน

ยังต้องทวน input/copy/scroll/image/shutdown และ strict lifecycle ของ provider ใหม่ ผล strict resource gate เดิมยัง failed ไม่ถูกยกเว้นเพราะ Thai fixture ผ่าน เช่นเดียวกับ CtrlShiftC/IME/DPI/portable consumer acceptance ที่ต้องคงขอบเขตหลักฐานแยกกัน

เวลา14:11 strictlifecyclemodernจบ `lifecycle-native-20261019-141007-062`:exit1/ResourceGrowth,timeoutFalse,20cyclesหลังwarmup handles233→234,threads6→7,GDI/USER3→3 ไม่waivegate ไม่เทียบabsolutehandlecountsคนละprocessเป็นimprovement และไม่claimcreatorของรอบนี้จากpatternเดิม Keyboard/mouse/copy/exit syntheticผ่านตามบันทึกข้างบน แต่Herdrmanual/image/fullCore/VTยังไม่รับรองใหม่ ไม่มีtestรันหลังรอบนี้จบ Binary59ยังfrozenรอmanual

## Background appearance preview62 (ยังไม่ใช่ human acceptance)

ผู้ใช้รายงานเวลา14:43ว่า “ภาษาไม่น่ามีปัญหาแล้วนะ” แต่block/backgroundยังดูไม่สวย วัดภาพdefault#282C34กับblock#1E1E1E จึงไม่แก้font/Herdrหรือบังคับpaletteแทนแอป

Build60หยุดเพราะOOMและrecovery61ยังไม่เริ่มcompileเนื่องจากcommitไม่พอ ไม่ใช่pixeltestfail หลังผู้ใช้ขอretry15:28commitfree~5.9GiB Build62ผ่าน123/123 ตามflagsเดิม ผ่าน14pixelchecksในสองสีdefault282c34/1e1e1eครอบคลุมdefault/truecolor/SGR49/SGR0/erase-to-end/paddedspaces ภาพก่อนและหลังเปิดตรวจจริง ไม่พบrenderผิดในcontrolledcasesนี้ ไม่ใช่การพิสูจน์nestedHerdrทุกกรณี

`terminal-native-20261019-153231-543` และ `terminal-native-20261019-153244-603` คือcolorreceipts; `terminal-native-20261019-153255-078` strictThairedrawผ่านหลังpreview1e1e1e(0cellsdifferent/cursor45/35framespaints) Binary62SHA256 `2589A9B770D5930E1F00C654D4D89116C78B522A94A0E4EEB1D9AAE9829327CC`

```powershell
.\tools\windows\preview.ps1 -Executable .\zig-out\background-probe\bin\localterm-dev.exe -AppLocalConpty -Background 1e1e1e
```

Backgroundเป็น6hexvalidatedprocess-localdefaultเท่านั้น ไม่เขียนconfig/themeถาวร ไม่เปลี่ยนexplicitSGR/palette ล้างและrestoreenvของhelperตามปกติ เปิดmanualเฉพาะผู้ใช้รัน ไม่เปิดแทนโดยautomation Candidate59และprofileเดิมไม่ถูกทับ รอhumanดูHerdrหน้าเดิม ไม่claim“สวย/แก้แล้ว”จากfixture ตลอดจนstrictresource/fullCoreVTยังคงแยกสถานะ

## แหล่ง API และแพ็กเกจ

- [Microsoft NuGet package](https://www.nuget.org/packages/Microsoft.Windows.Console.ConPTY)
- `inc/conpty.h` จาก pinned package เป็น contract ของ Conpty* exports
- [Microsoft winconpty source](https://github.com/microsoft/terminal/tree/main/src/winconpty) อธิบาย width flags และ textMeasurement; ไม่ใช้แค่ Windows API HRESULT เป็น feature proof
