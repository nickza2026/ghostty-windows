# Windows image paste — experimental

สถานะ: implementation และ synthetic tests มีแล้ว แต่ **ยังไม่รับรอง human clipboard/CLI integration หรือ portable ทั้งแอป** ไม่มีการอ่าน/เขียน clipboard จริงระหว่าง automated tests และไม่ได้ส่งรูปเข้า cloud CLI เพื่อทำให้ดูเหมือนทดสอบผ่าน

## สองเส้นทาง

1. **Ctrl+V / Ctrl+Shift+V ปกติ**: ถ้า clipboard มีรูป จะขออนุญาตอ่านและเซฟ PNG ชั่วคราว แล้วส่ง **path ที่ quote สำหรับ PowerShell** เข้า core paste เช่น `'D:\portable\portable-data\cache\clipboard\localterm-image-<random>.png' ` ไม่มี Enter/newline ไม่ execute คำสั่ง และไม่รับรองว่า CLI ทุกตัวจะตีความ path เป็น attachment เอง
2. **โปรแกรมที่รองรับ Kitty clipboard / paste events**: list MIME ได้ `text/plain` / `image/png` ตาม format ที่มีจริง จากนั้นโปรแกรมขออ่าน representation ได้ตาม permission/session-grant ของ core เส้นทาง PNG นี้อยู่ใน RAM ไม่จำเป็นต้องสร้างไฟล์ โปรแกรมต้องรองรับ protocol เอง ไม่ใช่การส่ง binary image เป็นข้อความธรรมดาผ่าน PTY

OSC 52 ยังอ่านข้อความเท่านั้น; binary clipboard write/การ copy รูปกลับเข้า Windows ยังไม่รองรับ หากรูปกับข้อความอยู่พร้อมกัน ordinary paste เลือกรูปก่อน และแสดง permission ก่อนอ่าน payload ผู้ใช้ปฏิเสธแล้วไม่ paste ข้อความอื่นแทนโดยเงียบ ๆ

## Portable storage และอายุไฟล์

- ก่อนเปิด terminal ให้สร้าง **directory** `portable-data` ข้าง `localterm-dev.exe` ที่เลือกใช้ โหมดนี้ snapshot ตอนสร้าง surface ไม่ใช้ cwd เป็นฐาน และสร้าง image cache ใต้ `<exe-dir>\portable-data\cache\clipboard`
- ถ้าเพิ่ม marker หลังเปิด ต้องเปิด terminal ใหม่; ถ้า marker/ไดรฟ์หายหรือ cache เขียนไม่ได้หลังเลือก portable แล้ว จะล้มเหลวและแจ้งปัญหา **ไม่ fallback ไป host TEMP/AppData** ไม่ขอ admin หรือแก้ ACL อัตโนมัติ
- เมื่อไม่เลือก portable ใช้ `%TEMP%` ของ process โดยชื่อไฟล์เป็น `localterm-image-<128-bit-random>.png` สร้างแบบ exclusive ไม่ overwrite ไฟล์เดิม รองรับเฉพาะ local drive-qualified path ไม่รองรับ UNC staging
- เก็บไฟล์ไว้ตลอดอายุ surface เพื่อให้ CLI อ่านหลัง paste ได้ จากนั้นปิด core/child ก่อน cleanup เฉพาะรายการที่ surface สร้างเองและ identity/size ยังตรง ไม่ wildcard sweep หรือ recursive delete temp ของเครื่อง
- cleanup เป็น best effort; crash, ไฟล์ถูกเปลี่ยน, permission หรือ reader ที่ล็อกไฟล์อาจทำให้เหลือไฟล์ ต้องตรวจ owned cache ก่อนส่ง portable folder ให้คนอื่น ห้ามถือว่าไม่มีข้อมูลส่วนตัวเพียงเพราะ session ปิดแล้ว
- โควตาต่อ surface: **16 ไฟล์ / รวม 128 MiB** ไม่รวม clipboard ของ Windows; ไม่ทำ quota eviction ที่ลบไฟล์ซึ่ง CLI อาจกำลังใช้อยู่

นี่เป็น portable foundation **เฉพาะ image cache** ไม่ใช่การรับรอง config/log/resource isolation ทั้งแอป ZIP, CPU baseline, update/rollback, clean-machine และ acceptance ของเฟส6ยังต้องทำตาม `PLAN.md`

## รูปที่รองรับและข้อจำกัด

- registered `PNG`, `CF_DIBV5`, `CF_DIB`; ไม่รองรับ `CF_BITMAP` อย่างเดียว
- DIB header 40/108/124 bytes, 24/32-bit BI_RGB, canonical 32-bit BI_BITFIELDS, top-down/bottom-up และ row padding แปลง BGR เป็น RGBA PNG
- BI_RGB byte alpha ที่ reserved ถือว่า opaque; explicit alpha mask เก็บ straight alpha ยังไม่แก้ premultiplied alpha
- ไม่รองรับ palette/compressed DIB, noncanonical masks, linked/embedded/calibrated color profiles
- input ไม่เกิน **64 MiB**, **8,388,608 pixels**, แต่ละ dimension ไม่เกิน **16,384**; PNG encoder ใช้ stored DEFLATE จึงอาจใหญ่ เช่นรูป4Kประมาณ32 MiB
- PNG passthrough ตรวจโครงสร้าง/chunk CRC/order/dimensions ไม่ได้ inflate IDAT เพื่อตรวจ pixel data หรืออ้างว่าถอดรหัส untrusted PNG ครบ รับ HGLOBAL zero-padding หลัง IEND ไม่เกิน4096 bytes และไม่ส่ง padding ต่อ

## วิธีเปิด artifact ที่ถูกต้องด้วยมือ

หลังตรวจสถานะ validation ของ build ที่จะใช้เท่านั้น:

```powershell
.\tools\windows\preview.ps1 -Executable .\zig-out\image-paste\bin\localterm-dev.exe
```

Preview helper resolve relative path จากตำแหน่ง PowerShell จริง ไม่ใช่.NET process cwd (ซึ่งอาจไม่ตาม `cd`) และยังปฏิเสธ executable นอกworkspace/ผิดชื่อ ทวนด้วย `tools/windows/preview-path-test.ps1` แบบ intercept process creation ไม่เปิดGUI; ผลนี้ยืนยันเฉพาะhelper ไม่แทนhumanvisual/IMEacceptance

wrapper เดิมที่ไม่ส่ง `-Executable` ยังเลือก `zig-out\bin\localterm-dev.exe` ซึ่งอาจเป็น build เก่า **ไม่ใช่ image-paste artifact** wrapper ไม่แก้ execution policy/PATH/registry ไม่เปิดทดสอบอัตโนมัติ

สำหรับ image-cache portable ทดลอง สร้าง marker ข้าง artifact ก่อนเปิด:

```powershell
New-Item -ItemType Directory -Path .\zig-out\image-paste\bin\portable-data -Force
.\tools\windows\preview.ps1 -Executable .\zig-out\image-paste\bin\localterm-dev.exe
```

ใช้รูปจำลองที่ไม่มีข้อมูลส่วนตัวเท่านั้น: copy screenshot ทดสอบ, paste แล้วลอง Deny ก่อน ต้องไม่เกิดไฟล์/path; รอบ Allow ต้องได้ PNG/path ที่อ่านได้และอยู่ใต้ artifact ที่เลือก จากนั้นปิด surface และตรวจ cleanup ทดสอบ CLI แต่ละตัวแยกว่ารับเป็น attachment หรือเพียงข้อความ path อย่ากดส่งรูปเข้า external service เพื่อทดสอบโดยไม่มีการอนุญาต

## Automated evidence

```powershell
zig test src/apprt/win32/clipboard_integration.zig
zig test src/apprt/win32/clipboard_integration.zig -O ReleaseSafe
```

ผ่าน **18/18 ทั้งสองโหมด** วันที่18ตุลาคม2026 ครอบคลุม DIB→PNG→portable disk→readback byte equality→cleanup, pathไทย/ช่องว่าง, markerหายหลังstartup, invalid marker/cache, quota16ไฟล์, เก็บไฟล์ที่ไม่เกี่ยวข้อง, PNG padding/checksum และ allocator failures ของ codec ทั้งหมดไม่แตะ clipboard จริง

Native build34 ผ่าน123/123 แต่ window-only smokeพบResourceGrowth; เก็บfailureไว้ ไม่เดาสาเหตุหรือผ่อนgate Build35หลังportable latchผ่าน123/123และwindow/input smoke; window rerunทั้งbaseline28และbuild35 handles125→125,GDI2→2,USER1→1 ยังไม่ใช้rerunนี้ลบfailure34หรือปิดstrict lifecycle/ฟอนต์ไทย/IME/physicalDPI ดูผลล่าสุดใน `windows-validation.md`

หลักฐาน **build36 เดิม** SHA256 `42796AF02CDC26AF59E54726A3795C9F55968BB9D7AA4CA126F495F851772636` ผ่าน123/123และoffscreenwindow/inputsmokeพร้อม22frames/22paints/freshBMPcapture ไม่ใช่ artifact ล่าสุดแล้ว

### Candidate build42 — 18 ตุลาคม 2026 เวลา 19:56

ไฟล์ `zig-out\image-paste\bin\localterm-dev.exe` SHA256 ของ **build42 ในบันทึกส่วนนี้ (ไม่ใช่ artifact ปัจจุบัน)**:

```text
AD15F986EBD48508762EB0CAB6E3604C8DBCC22A9AB26D2315411FCCB4DB28CD
```

- บิลด์ ReleaseSafe ผ่าน **123/123 steps**; ค่า preview ปัจจุบันใช้ Consolas + Leelawadee UI สำหรับไทย, native TrueType hinting และแถว 23px ที่ 96 DPI ขนาด 12pt ยังต้อง human visual acceptance ไม่ใช่การรับรองว่าตรงกับ Windows ClearType ทุก pixel
- `image-paste-smoke.ps1` ผ่านทั้ง normal และ portable: สร้างภาพ DIB จำลอง 2×1 สีแดง/เขียว, ใช้ staging/core paste ของ production จริง, ส่ง quoted path ผ่าน ConPTY ให้ PowerShell tokenizer อ่านเป็น **หนึ่ง StringLiteral โดยไม่ execute** จากนั้น GDI+ ถอดรหัส PNG และตรวจ format/dimensions/RGBA
- normal TEMP มีช่องว่าง อัญประกาศเดี่ยว และภาษาไทย; portable ตรวจ path ใต้ executable root และยืนยันไม่เขียน host TEMP; หลังปิดทั้งสอง session ตรวจ cleanup และลบได้เฉพาะ directory ว่างที่ harness สร้างเอง ไม่มี recursive deletion
- Build41 รอบแรกยังไม่ผ่าน expected-root assertion; เก็บ failure ไว้ แก้ literal ใน harness ให้ใช้ Unicode codepoints เพื่อไม่ให้ PowerShell 5.1 อ่าน UTF-8-without-BOM เป็น ANSI แล้วทวนด้วย root assertion เดิม พร้อม diagnostic เฉพาะเมื่อ mismatch ทั้งสอง session ของ build42 จึงผ่าน
- ทั้งหมด **ไม่อ่าน/เขียน Windows clipboard ของผู้ใช้**, ไม่แสดง permission dialog, ไม่ทดสอบ hotkey/permission/Kitty ด้วย clipboard จริง และไม่ส่งภาพเข้า AI service จึงยังไม่แทน manual integration acceptance
- Full-core และ native regression ชุดล่าสุดกำลังทวนแยก; strict lifecycle ยังมี WIN-RUNTIME-004 และไม่มีการผ่อนเกณฑ์/รับ exception อัตโนมัติ ดูสถานะจริงใน `windows-validation.md`

รัน E2E แบบปลอดภัยจาก workspace ที่ตั้งค่า Zig/MSVC แล้ว:

```powershell
.\tools\windows\image-paste-smoke.ps1 -Executable .\zig-out\image-paste\bin\localterm-dev.exe
```

คำสั่งนี้ต้องไม่มี `portable-data` อยู่ก่อน เพื่อไม่เปลี่ยน directory ของผู้ใช้ หากมีอยู่จะหยุด ไม่ลบหรือย้ายให้เอง automated HWND อยู่ offscreen/no-activate **ไม่ใช่ manual preview** หากผู้ใช้จะเปิดดูแบบ interactive ให้เรียกแยกด้วยคำสั่งนี้ซึ่งแสดงหน้าต่างตามปกติ (ไม่ถือว่า artifact พร้อมใช้งานแล้ว):

```powershell
.\tools\windows\preview.ps1 -Executable .\zig-out\image-paste\bin\localterm-dev.exe
```

## Artifact ล่าสุด — build50, 19 ตุลาคม 2026

Executable path เดิมถูกแทนด้วย build50 แล้ว SHA256 ปัจจุบัน:

```text
8674943AB93F3372ADCCAB3654B513279513D4372F6E5CA8FEF0446DC3B82EF3
```

- Build50 ผ่าน123/123; E2E normal `image-paste-native-20261018-235842-391` และ portable `image-paste-native-20261018-235854-982` exit0 พร้อม expected-root, single-literal parser, independent GDI+ pixels และ cleanup assertions เดิม
- Build49 normal consumer ไม่ตอบก่อนปิด เก็บ failure `image-paste-native-20261018-235152-111` ไว้ ไม่อ้างว่า E2E ไม่เคยพลาด พบ harness รับ global keyboard modifier ของผู้ใช้ระหว่าง synthetic Enter จึงแยกเฉพาะ image fixture ให้เหมือน input smoke และเพิ่ม `controlled image synthetic Enter dispatched` receipt; การทวนผ่านไม่ได้พิสูจน์ย้อนหลังว่า modifier เป็นสาเหตุของ failure49
- Production physical keyboard และ manual preview ยังคงอ่าน modifier จริง ไม่ inject global input ไม่เปลี่ยน focus/clipboard ของผู้ใช้ ไม่เพิ่ม deadline หรือปิด consumer assertion
- Shutdown UI mailbox deadlock มี pre-fix queue-full repro ที่ค้าง และหลัง patch ผ่าน3/3ในbuild49 +ผ่านซ้ำbuild50 ดู [runtime attribution](windows-runtime-attribution.md)
- ยังไม่พร้อมใช้งาน: strict lifecycle build50 ยังคง233→234handles/6→7threads; full-coreหลังpatchเคยOOMสองรอบ แต่รอบเช้า19ตุลาคมเมื่อผู้ใช้ให้ลองใหม่ผ่าน3926/3987tests/61skip,89/89steps,exit0แล้ว VTตามด้วย6722/6786tests/64skip,45/45steps,exit0 ส่วนhumanvisual/IME/OSclipboard/AI-CLIacceptanceยังไม่ได้รับรอง
- 09:27ทวนsyntheticimageE2Eเพิ่มสองชุดผ่านnormal/portableครบ4sessions ใช้hashcandidate50เดิม ตรวจPNG/quoting/root/cleanupเดิม ไม่มีportable-datafixtureค้าง รวมbuild50ผ่านnormal+portableสามชุด แต่ยังไม่ใช้แทนhotkey/permission/OSclipboardหรือAI-CLIจริง ไม่มีtestรันค้างหลังชุดนี้จบ

## Human normal-image paste — candidate53, 19 ตุลาคม 2026 เวลา 11:34

หลังผู้ใช้เปิดcandidate53และทดสอบPaintภาพที่ไม่มีข้อมูลสำคัญ→Ctrl+A/Ctrl+C→Ctrl+Vในterminal/อนุญาตตามprompt→เห็นquotedPNGpath ผู้ใช้ตอบ “ได้ปกติ” รับเป็นuserreportedpassของnormal-modeOSclipboardimageถึงpathinsertionเท่านั้น ไม่อ้างagentอ่านclipboard/ตรวจpixelsของไฟล์จริงหรือเห็นภาพแนบเอง ยังไม่ได้ยืนยันAI-CLIอ่านภาพ,portablemodeจริง/ย้ายrootหรือcleanupของsessionmanualนี้ ต้องระบุCLIเป้าหมายจริงก่อนทดสอบconsumer ไม่ส่งภาพขึ้นserviceหรือรันAI-CLIแทนผู้ใช้โดยอัตโนมัติ

Candidate53คือ`zig-out/copy-input/bin/localterm-dev.exe` SHA256 `0EF93F4DAA02094578CBAFA6FB47D131655CC7026F8A6092FCC152B2FD235C56` ไม่ใช่candidate50ในบันทึกด้านบน

## Letta Code consumer — เตรียม manual integration

ผู้ใช้ระบุLetta Codeเวลา11:53 ตรวจlauncher/versionแบบreadonlyได้0.34.17 (ไม่ใช่การเปลี่ยนversionของsessionที่กำลังคุยโดยagent) entryและimage-resize-workerที่เคยmissingมีแล้ว ไม่ซ่อมinstallationเอง Official[CLIreference](https://docs.letta.com/platform/cli/reference/index.md)ระบุlettaเริ่มinteractive,/newแยกconversation,Ctrl+Vวางcontent/image ใช้docsผ่านETaghelperและตรวจlocal/CLIapplicability

ให้ผู้ใช้รันlettaในnativecandidate53เอง แยกconversationทดสอบด้วย/new แล้วส่งpromptให้อ่านเฉพาะภาพที่ไม่มีข้อมูลสำคัญไม่แก้ไฟล์ โดยpasteจากclipboardเข้าprompt ต้องดูว่าLettaรับquotedPNGpath/attachmentและอธิบายเนื้อหาจริงได้ก่อนclaimconsumerpass ขั้นส่งpromptอาจส่งภาพให้modelตามconfigurationของผู้ใช้ agentไม่เรียกmodel/อัปโหลดหรืออ่านOSclipboardแทนผู้ใช้ และอย่าปิดnativewindowก่อนconsumerอ่านไฟล์เสร็จเพราะappownedPNGถูกcleanupตอนปิด

ยังไม่ยืนยันLettaimageintegrationผ่านจากversion/docsหรือnormalpathinsertionเพียงอย่างเดียว และไม่ใช้ผ่านconsumerในอนาคตปิดstrictresourcegateที่ยังfailed
