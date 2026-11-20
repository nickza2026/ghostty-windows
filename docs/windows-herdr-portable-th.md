# Herdr แบบกดเปิดครั้งเดียวในแพ็ก portable

## Ready build: เปิด launcher แล้วใช้ Letta

`package-portable.ps1 -PortableTools -NodeSource <verified-node> -ReadyHerdrSource <prepared-program-package>` สร้างแพ็กพร้อม Node, full Git/Bash, pinned Herdr และ public Letta 0.34.23 โดยตรง คัดลอกเฉพาะ program trees ที่กำหนด ไม่อ่านหรือคัดลอก HOME, profiles, accounts, provider settings, caches หรือประวัติจากแพ็กต้นทาง ตรวจ provenance/entry hash ของ Letta และตรวจ pinned runtimes หลังคัดลอก ไม่รัน npm dependency lifecycle scripts

ขั้นตอน build สร้าง private shell และ config ล่วงหน้า ตั้ง default backend เป็น local ผ่านคำสั่ง `letta backend local` ของรุ่นที่ตรวจจริง เปิด long paths เฉพาะ Git config ของ HOME ใหม่ ปิด upstream update checks สำหรับ pinned/manual payload และให้ restore workspace กลับเป็น shell ไม่ auto-run คำสั่ง AI ที่บันทึกค้างไว้ ทุกโปรไฟล์เป็นของใหม่ จึงยังต้องเชื่อม provider ของตนเองก่อนใช้โมเดล ไม่ได้แปลว่า LLM รัน offline หรือย้ายบัญชีให้โดยอัตโนมัติ

ใช้งานปกติ: เปิด `Run-Herdr.cmd` แล้วใช้ `letta --new` ใน pane โดยไม่ต้องเรียก `herdr-private-shell.exe` เอง ตัว launcher ส่ง `--session` ชัดเจนและใช้ชื่อคงที่ต่อ package root/รุ่น shell เช่น `portable-<root-hash>-shell-v3` จึงไม่ reattach ไป daemon รุ่นก่อนที่ยังมี PATH ของเครื่อง การเปิดซ้ำในรุ่นเดิมยังใช้ session เดิม ไม่สร้าง daemon ใหม่ทุกครั้ง เมื่อเปลี่ยนรุ่น shell หรือย้ายแพ็กจะเปิด namespace ใหม่; session/workspace เก่ายังเก็บไว้ใน profile เดิมและไม่มีการ kill pane หรือล้างข้อมูลเพื่อแก้ปัญหา

การแพ็กพร้อมโปรแกรมใช้ bundled Node สำหรับ copy/hash เพราะ npm dependency tree มี path ยาวเกินข้อจำกัดของ `System.IO.File.Copy` ใน PowerShell 5.1 มี regression สำหรับ path เกิน 300 ตัวอักษร, ไม่ตาม private-profile junction, ปฏิเสธ reparse ใน program tree, ไม่ merge ทับปลายทาง และไม่ไล่อ่าน mutable profiles เพื่อสร้าง immutable manifest

Factory JSON เขียนจาก Node โดยตรงให้ `files` เป็น array ปกติ ไม่ round-trip array ขนาดใหญ่ผ่าน PowerShell 5.1 ซึ่งห่อเป็น `{value, Count}` ได้ มี unit test เทียบรายการ/hash แบบ semantic equivalence และห้ามเขียนทับ catalog เดิม การตรวจแพ็กต้องเทียบทุก immutable file กับ snapshot ไม่ใช่เพียงดูว่า launcher เปิดได้

เกณฑ์ทดสอบ ready build ต้องผ่าน **CMD → Herdr TUI/ConPTY → default pane → `letta --new`** จริง รวมเริ่มใหม่/restore และมี legacy daemon ค้างอยู่ โดยใช้ข้อมูลสังเคราะห์และ transport guard ไม่มีหลักฐาน provider/chat จริงจากการทดสอบนี้ เพียงเรียก Node/Git ผ่าน absolute path หรือเรียก v3 เองไม่พอสำหรับยืนยันว่า launcher พร้อม

## ขอบเขต

เพิ่ม `Run-Herdr.cmd` ข้าง `Run.cmd` โดยไม่ fork Herdr และไม่ build Zig ใหม่ ตัวเปิดใช้ official Windows ZIP ที่ pin เวอร์ชัน/URL/SHA256 ไว้ ไม่เรียกสคริปต์ `install.ps1` เพราะตัวติดตั้งปกติแก้ `HKCU\Environment\Path`

ครั้งแรกที่ผู้ใช้เปิดจึงดาวน์โหลด ตรวจ checksum แตกแพ็กให้ครบและเก็บ manifest รายไฟล์ ครั้งถัดไปตรวจแล้วใช้ไฟล์เดิมโดยไม่ดาวน์โหลดใหม่ ไม่ลบ/ซ่อมทับ payload ที่ผิดปกติเงียบ ๆ และไม่ fallback ไป Herdr ที่ติดตั้งในเครื่อง

## วิธีใช้

เปิด `Run-Herdr.cmd` ในโฟลเดอร์แพ็ก เก็บ `support/`, `bin/`, `share/` ไว้ด้วยกัน ครั้งแรกต้องใช้อินเทอร์เน็ตเพื่อดาวน์โหลด official release หากเกิด error ตัวเปิดจะแสดงข้อความและไม่ไปใช้โฟลเดอร์ของเครื่องแทน

Herdr มี profile ใหม่ของตัวเองใต้ `bin/portable-data/profiles/herdr` ไม่คัดลอกบัญชี Herdr, Codex หรือ Letta ของตัวหลัก หรือย้ายข้อมูล Letta ที่ผู้ใช้ลงใน portable ไว้ก่อนหน้า ต้องล็อกอินบัญชีที่ต้องการใช้งานเอง ไม่มีการรัน login/logout ให้

เรียก EXE ที่ pin ไว้แบบ absolute และใช้ config/state/session เฉพาะชุดนี้ ไม่เปลี่ยน User PATH, Machine PATH หรือ Registry ของ Windows การเปลี่ยน environment มีผลแค่ตัวเปิดและ process ลูก

## เหตุผลที่ไม่ตั้งแค่ HERDR_HOME

ใน source v0.9.5 `HERDR_HOME` ใน installer เป็น distribution root ส่วน runtime config/state เลือกผ่าน `XDG_CONFIG_HOME`, `XDG_STATE_HOME` และ `HERDR_CONFIG_PATH` ต้องล้าง inherited `HERDR_*` โดยเฉพาะ `HERDR_SOCKET_PATH` และ `HERDR_CLIENT_SOCKET_PATH` ก่อนกำหนด session ส่วนตัว เพื่อไม่ต่อไปยัง server ของตัวหลัก

Windows ใช้ชื่อ IPC ที่ derive จาก path ของ session ไม่ใช่เพียง EXE คนละโฟลเดอร์ การย้ายทั้งแพ็กทำให้ตัวเปิดคำนวณ root ใหม่ ไม่อ้างอิง path ต้นทางแบบ hardcode

## Shell และ history ส่วนตัว

Herdr v0.9.5 เปิด pane ของ PowerShell ด้วย `-NoExit -Command` แต่ไม่ได้ใส่ `-NoProfile` จึงไม่ใช้เพียง HOME environment เป็นหลักฐานว่า profile ของ Windows ไม่ถูกโหลด ตัวเปิดนี้สร้าง console shim ขนาดเล็กจาก `support/herdr-private-shell.cs` ด้วย .NET Framework compiler ที่มากับ Windows และเก็บ source/EXE/hash manifest ใต้ `portable-data/apps/herdr-shell/v3` ไม่ build Zig หรือสร้าง compiler cache ของ Zig รุ่น v3 แยกจาก v1/v2 ไม่เขียนทับ binary เดิมที่ process อาจใช้อยู่

shim กำหนด `PSModulePath` และ package root ให้ PowerShell child โดยตรงจากตำแหน่ง EXE ปัจจุบันก่อน interactive ConsoleHost autoload ไม่พึ่งเฉพาะ environment ที่ Herdr server ส่งมา เพราะใน pane จริงพบ module path ถูกสร้างใหม่จน inbox PSReadLine โหลดก่อน private module การ import private moduleซ้ำจึงชนชื่อ cmdlet แม้ redirected-stdin test ผ่าน ใช้ import แบบไม่ force และให้ private DLL ผูกตั้งแต่เริ่ม process ทดสอบต้องตรวจ assembly location ใน **interactive Herdr ConPTY พร้อม bundled moduleจริง** รวม `-NoProfile`, private HOME/history ไม่ถือว่า fallback inbox หรือการรัน shimแบบredirectedstdioเป็นหลักฐานเทียบเท่า

รุ่น v3 กำหนด **PATH ของ PowerShell child โดยตรง** ด้วย เพราะ HOME ที่ถูกต้องไม่ได้แปลว่า PATH ถูกต้อง: pane จริงเคยเรียก host Git ที่ D: และ host Letta/Node ที่ C: แม้ความจำอยู่ใน private HOME แล้ว ค่า PATH ใหม่เริ่มด้วย Node, npm ของ Herdr และ shims ภายในแพ็ก ตามด้วย pinned Herdr 0.9.5 และ OS directories ที่จำเป็นเท่านั้น ไม่ต่อ PATH ของเครื่อง กำหนด PATHEXT/ComSpec และไม่ให้ค้น current directory เป็น executable fallback ด้วย ไม่มีการแก้ User/Machine PATH

การตรวจต้องส่งคำสั่งเข้า **pane สังเคราะห์ของ Herdr จริง** แล้วตรวจ `Get-Command git,node,letta` และรัน version ของ payload จริง ไม่ใช่เพียงเรียก Node/Git ผ่าน absolute path ใน test driver ทดสอบ host-PATH trap และกรณี payload ไม่มีว่าต้องไม่ fallback ไปเครื่อง รวมหลังย้าย runtime fixture เมื่อ reload config แล้วต้องสร้าง **pane ใหม่**: environment ของ PowerShell ใน pane เก่าไม่เปลี่ยนตามเอง ห้ามแก้ปัญหาโดยเพิ่ม trust ทั้งไดรฟ์หรือเปลี่ยน Git/PATH ของเครื่อง และอย่าใช้ Git จาก host กับค่า trust `%(prefix)` ที่ออกแบบสำหรับ bundled Git

ตัวเปิดกำหนด `terminal.default_shell` เป็น **absolute path ของ private shim ในแพ็กที่กำลังเปิด** และ refresh ค่าที่ตัวเปิดจัดการทุกครั้งหลังย้ายแพ็ก ไม่ใช่เก็บ absolute path ต้นทางถาวร เขียนเป็น TOML basic string ที่ escape backslash รองรับชื่อไทย ช่องว่าง และ apostrophe การใช้ชื่อสั้นเดิม `herdr-private-shell.exe` ไม่เพียงพอ: upstream มี PATH resolver แต่หากหาไม่พบจะส่งชื่อสั้นต่อให้ `CreateProcessW` ที่ระบุ `lpApplicationName` ซึ่งไม่ค้น PATH ให้อีกชั้น จึงอาจขึ้น Action rejected แม้มีไฟล์ shim ในแพ็ก

shim เรียก Windows PowerShell แบบ absolute พร้อม `-NoProfile` ตั้ง `$HOME` และ PSReadLine history ไปที่โปรไฟล์ส่วนตัว และคง console handles ของ pane ไม่เปิดหน้าต่าง shell เพิ่ม ตัวเปิด migrate เฉพาะชื่อ private shim เดิมหรือพาธรูปแบบ private shim ที่เคยสร้างไว้ ไม่เปลี่ยน shell อื่นที่ผู้ใช้เลือกเอง แก้เฉพาะค่าใน section `[terminal]` รักษาค่าอื่น/inline comments/line endings และสำรอง config เดิมข้างไฟล์ส่วนตัวก่อน atomic replace ไม่ส่งสำเนา config ไป evidence หรือ memory

ไม่ล้าง config หรือบัญชีเดิม การ refresh managed shell path ข้างต้นเป็นการซ่อม routing เฉพาะแพ็ก ไม่ใช่การย้าย account หากผู้ใช้เปลี่ยน default shell เองหรือเอา config เก่ามาใช้ ขอบเขต NoProfile/history นี้ไม่รับรอง shell ที่ผู้ใช้เลือกแทน การแก้ config เองไม่ใช่ sandbox restriction

สำหรับตรวจแบบไม่เปิด UI มี `Run-Herdr.cmd --install-only` และ `Run-Herdr.cmd --version` โดยไม่ส่ง arbitrary arguments จาก CMD ไปยัง PowerShell

## ข้อจำกัด

- ไม่ใช่ filesystem sandbox: Windows DLL/fonts/browser/OS caches และโปรแกรมภายนอกยังอาจใช้ C: ได้ ไฟล์งานยังอยู่ใน workspace ที่ผู้ใช้เลือก
- ยังไม่ได้ยืนยันบัญชี, provider, model หรือการใช้ Herdr interactive ของผู้ใช้จริงจากการตรวจ source หรือ syntax อย่างเดียว
- อย่าเรียก `herdr update`, `herdr channel set ...` หรือตัวติดตั้งปกติกับ payload นี้ เพราะอาจกลับไปแก้ User PATH ต้องอัปเดต pin ผ่านขั้นตอน portable ที่ตรวจใหม่
- รักษา profile ทุกครั้งที่อัปเดต ห้ามลบ `portable-data` เพื่อแก้ error หรือแจกสำเนาที่มีบัญชี/ข้อมูลส่วนตัว
- ตัวเปิดนี้ไม่ได้เพิ่ม Git ให้ Letta คำเตือน `Memory git sync failed: spawn git ENOENT` เป็นงาน dependency อีกส่วนหนึ่ง ไม่อ้างว่าแก้จากการเพิ่ม Herdr
- ชุดส่งมอบนี้เป็น local candidate ไม่ใช่การรับรอง GPU/DPI หรือ public release ของเทอร์มินัล

## แหล่งอ้างอิง

- [Official release manifest](https://herdr.dev/latest.json)
- [Manual Windows archive](https://herdr.dev/docs/install/#windows-archive)
- [CLI/environment reference](https://herdr.dev/docs/cli-reference/)
- [Tagged config/state source](https://github.com/herdrdev/herdr/blob/v0.9.5/src/config/io.rs)
- [Tagged session paths](https://github.com/herdrdev/herdr/blob/v0.9.5/src/session.rs)

## ผลทดสอบและแพ็กส่งมอบ

มีชุดทดสอบ `tools/windows/herdr-portable-test.ps1` สำหรับ ZIP/hash/manifest, reuse, secret/socket environment, private shell/bootstrap/history, npm shim precedence, Node integrity/reparse, lock, profile collision และ relocation ใช้ไฟล์/บัญชี sentinel สังเคราะห์ ไม่ใช้บัญชีจริง

เพิ่ม `tools/windows/herdr-shell-path-test.ps1` สำหรับข้อผิดพลาดที่ผู้ใช้พบเมื่อย้ายไป A: โดยเรียก Win32 `CreateProcessW` จริงแบบ explicit application name: ชื่อสั้น fail ด้วย error 2 แม้ PATH มีไฟล์ ขณะที่ค่าที่ launcher สร้างใหม่เปิด shell ได้ทั้งก่อน/หลังย้าย fixture ไปชื่อไทย มีช่องว่างและ apostrophe ตรวจ migration เฉพาะ managed value, custom-shell preservation, backup และไม่ rewrite ซ้ำ ผลนี้ไม่ใช่หลักฐานว่ารัน Herdr UI หรือว่าได้ระบุสาเหตุภายใน upstream PATH resolver ครบแล้ว

`tools/windows/herdr-real-shell-test.ps1` ใช้ pinned Herdr จริงกับ headless server, session และ profile สังเคราะห์สุ่ม บังคับเงื่อนไข builder PATH หา shim ไม่พบ แล้วตรวจ red/green และการย้ายด้วย workspace/pane จริงและ unique shell marker ไม่ใช่เชื่อ command echo ผลการรันจริงต้องแนบ evidence แยก ไม่ stop/reload server A: หรือ C: ของผู้ใช้เอง

`tools/windows/herdr-portable-integration-test.ps1` repackage retained clean baseline โดยไม่ build Zig แล้วดาวน์โหลด official pinned ZIP ผ่าน CMD install-only ตรวจ reuse/version และย้ายทั้งแพ็กไปโฟลเดอร์ชื่อไทย/มีช่องว่าง ผลรันจริงและหลักฐานแพ็กส่งมอบต้องแนบใน evidence ของรอบนั้น ไม่ถือว่า compilation หรือ source review เป็นการเปิด UI สำเร็จ

รอบ 28 ตุลาคม 2026 ผ่าน regression 31 กรณี รวมการเริ่ม shell ด้วย PSReadLine ที่ bundled จริง และตรวจว่า assembly ของ DLL มาจากแพ็ก ไม่ใช่แค่ manifest ดูเหมือนอยู่ในแพ็ก พบและแก้ลำดับ `PSModulePath`: `-NoExit` autoload module ก่อน startup command จึงต้องเลือก private module ตั้งแต่ครั้งแรก ไม่โหลด inbox แล้ว import DLL อีกชุดจน cmdlet ชื่อซ้ำ หลักฐาน red/green แยกจาก source review และการ compile

แพ็กส่งมอบ local candidate: `zig-out/portable-packages/localterm-herdr-portable-20261028/Run-Herdr.cmd` เตรียม payload Herdr 0.9.5 ไว้แล้ว จึงไม่ต้องดาวน์โหลดซ้ำบนชุดนี้ โปรไฟล์ยังใหม่ ไม่มีการล็อกอินหรือทดสอบ provider/บัญชีจริง และยังไม่อ้างการยอมรับ interactive UI โดยผู้ใช้
