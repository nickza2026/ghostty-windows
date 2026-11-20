# เป้าหมาย: Native Windows sandbox EXE

ผู้ใช้อนุมัติทิศทางวันที่ 17 พฤศจิกายน 2026: “งั้นตั้งเป้าทำให้เป็น exe เลย”

สถานะล่าสุด 18 พฤศจิกายน 2026: รุ่น **Sandbox** บิลด์และ owned offscreen
name/password checks ผ่านแล้ว มีเครื่องมือซ่อม public payload พร้อม hash/backup/rollback
ไม่ใช้ syntax check อย่างเดียวแทน module closure/import และไม่ถือว่าเป็น VM boot
หรือ human acceptance ของเครื่องเป้าหมาย

สถานะเริ่มต้น: มี Ghostty Win32 prototype และ Node-only Linux VM backend อยู่แล้ว
แต่ยังไม่มี native EXE ที่เชื่อมสองส่วนนี้ครบ การ build ได้ไม่ใช่การรับรองใช้งานจริง
WIN-RUNTIME-004/cycle12 และข้อจำกัด native editing/GPU/DPI เดิมยังเปิดอยู่

## ผลลัพธ์ที่ต้องได้

เปิด EXE แล้วได้หน้าต่าง terminal ของแอปเอง ใช้ Ghostty Win32 ที่มีอยู่เป็นฐาน
คง Linux VM เบื้องหลัง ไม่เปิด CMD เป็นหน้าต่างหลัก ไม่ห่อ CMD ให้เปลี่ยนนามสกุลเท่านั้น
backend Node/QEMU ที่ยังจำเป็นใช้เฉพาะ runtime ของแพ็ก

Runtime, VM Data และข้อมูลที่แอปเป็นเจ้าของผูกกับตำแหน่ง EXE ปัจจุบัน
ไม่ผูก cwd หรืออาศัยบัญชี/Node/npm/config ของ Windows โดยเงียบ ๆ
กำหนด environment ของ child ก่อน CreateProcess ตัวแรก ไม่ใช่หลัง Node เริ่มแล้ว
สิ่งนี้ไม่ใช่การรับประกัน Windows ไม่ใช้ pagefile, Prefetch, driver/font/cache บน C:

## Milestones

1. **Native launch contract / environment** — แยกทางเปิด sandbox จาก native portable
   shell เดิม เลือก executable/argv/cwd จาก exe root และสร้าง private child environment
   พร้อม synthetic regressions: root ย้ายตำแหน่ง, path ไทย/space, inherited injection,
   dependency หาย, ไม่มี host-shell fallback หรือ global environment mutation
2. **Native terminal integration** — เชื่อม CoreSurface/ConPTY กับ framed SSH → Linux PTY
   ของ backend เดิม เปิด native window จริง ทดสอบ paint/input/resize/Ctrl-C/exit โดยแยก
   offscreen automation ออกจาก human preview และตรวจ numpad ทั้ง numeric/navigation/Enter
3. **Owned VM lifecycle** — start/status/normal stop/restart และ recovery ของ stale state
   ต้องผูก instance และตรวจ process/disk usage ไม่ kill ตาม PID เก่า ไม่เปิด QEMU ซ้อนดิสก์
   ไม่ล้าง Data เพื่อทำให้ error หาย
4. **Factory / relocation qualification** — ส่ง fresh unbooted public package ไม่มีบัญชี,
   key, password hash หรือ Data ทดสอบ ใช้ fixtures ของเรา ไม่ใช้แพ็กที่ผู้ใช้ใช้งานจริง
   ตรวจ backing chain ภายในสำเนา, user-global npm persistence, NTFS strict และ exFAT
   explicit reduced protection แยกผลตาม filesystem/สิทธิ์ที่ได้รับจริง
5. **Human acceptance** — ผู้ใช้ยืนยันการเปิด EXE, หน้าต่าง/terminal/input และขั้นเริ่ม-หยุด
   จากแพ็ก preview แยก Human-owned criteria ห้าม agent ปิดเองจาก unit test หรือ screenshot

## เกณฑ์ตรวจรับโดย agent

- มี native Windows PE EXE จาก source ไม่ใช่ console wrapper เป็นตัวแอปหลัก
- app-owned files/env ผูก current executable root; ไม่ fallback ไป host runtime/profile
- lifecycle/recovery ไม่กระทบ instance อื่นหรือดิสก์ที่กำลังใช้งาน
- มี red/green regression ตามข้อบกพร่องที่พบ และผล native integration ที่รันจบจริง
- วิธี OpenAI login ตรวจที่ CLI surface จริง เช่น device-code ไม่สั่งให้วาง OAuth URL
  ในช่องแชตจากการเห็นเพียงความสามารถของ auth helper
- รายงาน build, executed tests, blocked checks, GPU/DPI และ human acceptance แยกกัน

## ขอบเขตที่ไม่อนุมัติ

- ไม่ใช้ `A:\sandbox`/แพ็กเดิมเป็น test fixture และไม่สั่งเริ่ม/หยุด VM;
  ข้อยกเว้นเฉพาะงาน 18 พฤศจิกายนที่อนุมัติด้านล่างคือซ่อม public program files
  โดยเก็บ Data/บัญชี/ตัวระบุแพ็กเดิมทั้งหมด
- ไม่รีเซ็ตบัญชี/ดิสก์ เปลี่ยนเป็น full SDK หรือย้าย host/provider credentials
- ไม่ commit/push/deploy ติดตั้ง feature/driver/service หรือแก้ global environment
- ไม่เปลี่ยน failure เป็น silent host-shell fallback และไม่อ้าง portable ว่าไร้ร่องรอย OS
- ไม่สร้าง worktree/reset/rebase เพื่อทิ้ง dirty checkout เดิม งานนี้ต่อใน primary checkout

## ขอบเขตแก้แพ็กและชื่อที่อนุมัติ 18 พฤศจิกายน 2026

- ผู้ใช้ยืนยันชื่อ **Sandbox** สำหรับ native sandbox distribution:
  executable, initial/dynamic window title, VERSIONINFO/manifest และ launch-error label
  ไม่ใช่แค่เปลี่ยนชื่อไฟล์; ordinary localterm-dev build และ attribution เดิมคงอยู่
- อนุมัติคืน public App/Runtime/share/launcher ที่ขาดพร้อม backup ไฟล์ที่จะเปลี่ยน
  แต่ไม่คัดลอก owner marker ของ factory ทับตัวระบุแพ็กเดิม ไม่ลบไฟล์นอก manifest
  และไม่แทน guest disk/backing file ที่มีเนื้อหาต่างโดยเงียบ ๆ
- อนุมัติ exFAT reduced-protection เฉพาะแพ็กเป้าหมายแยกแล้ว;
  ไม่ใช่สิทธิ์เปลี่ยน NTFS policy, driver, Windows feature หรือ global environment
- เกณฑ์ก่อนส่งกลับให้ลอง: public inventory/hash/dependency closure ครบ,
  อ่าน metadata ชื่อจาก PE จริง และตรวจ HWND ของ owned offscreen fixture ว่าเป็น Sandbox
  การ import/check โค้ดแบบไม่ boot ต้องไม่ใช้ผล syntax-only แทน module resolution

## การตัดสินใจที่ต้องปิดก่อน milestone ที่เกี่ยวข้อง

- การปิดหน้าต่างสุดท้ายจะหยุด VM หรือคง background: ยังไม่เปลี่ยน semantics เดิมเอง
  ต้องทำสถานะและทาง normal stop ให้ผู้ใช้เห็นชัด แล้วตกลงก่อนเปลี่ยน default
- adoption ของ Data เดิมต้องเป็นงานแยกที่อนุมัติหลัง fresh factory ผ่าน ไม่ copy/reset
  หรือทดสอบ login จริงเพื่อทำให้ดูเหมือน native milestone ผ่าน
- การใช้ disposable exFAT VHD/UAC หรือ human on-screen preview ต้องขอสิทธิ์เฉพาะเมื่อจำเป็น

## จุดเริ่มต้นที่ตรวจแล้ว

- `src/apprt/win32/{App,Surface,window,portable_paths,portable_tools}.zig`
- `src/Command.zig`: Windows child environment block ส่งก่อน CreateProcessW ได้
- `src/os/windows_portable_env.zig`: มี helper sanitize ของ fresh portable child เดิม
- `tools/windows/sandbox/{entry,runtime-cli,terminal-protocol,policy}.cjs`
- ผล Node-only เดิมอยู่ใน `windows-node-sandbox-verification-th.md` ไม่โอนเป็น native GUI pass

## ความคืบหน้าเริ่มต้น

- เพิ่ม `src/apprt/win32/sandbox_environment.zig`: สร้าง allowlist environment ใหม่ก่อน
  child spawn ไม่คัดลอก inherited runtime/provider settings, profile/temp ผูก package root
- Zig 0.16.0: format check และ unit tests **4/4 ผ่านจริง** รวม path ไทย/space/apostrophe,
  invalid root/system metadata และ exhaustive allocation-failure cleanup
- หลักฐาน: `zig-out/native-sandbox-contract-f5b4063dc3314a779d3a0ab2f90a3f18/result.json`
- helper นี้ยังไม่ต่อเข้า CreateProcess ของ native app จึงยังไม่แก้ environment ของแพ็ก
  ที่ใช้อยู่ และยังไม่ใช่หลักฐานว่า native EXE integration เสร็จ
- งานถัดไปใน milestone 1 คือ fixed direct-Node launch contract กับ package/dependency
  validation ก่อนเชื่อม native App/global/Exec โดยไม่เปลี่ยน ordinary portable shell

### Launch contract — ทวนผลโดย parent แล้ว

- `src/apprt/win32/sandbox_launch.zig` ผูก root จาก dirname ของ full executable path
  ตรวจ marker ตาม backend เดิม, dependency และ reparse ancestors ก่อนคืน fixed argv/cwd/env
- parent รัน format check และ combined suite **7/7 ผ่าน ไม่มี skip**; จำนวนนี้รวม
  environment tests เดิม 4 ข้อ ไม่ใช่ 7 บวก 4 เป็น tests ใหม่ทั้งหมด
- หลักฐาน: `zig-out/native-sandbox-launch-review-fe8f4b8547c645dca9d9fa169cdb29ca/result.json`
- validation ยังเป็น snapshot มี TOCTOU; ไม่ใช่ secure-spawn/GUI acceptance
  ไม่รองรับ UNC/device namespace และ JSON lone-surrogate ของ marker ถูกปฏิเสธ
- milestone ถัดไปกำลังเชื่อม explicit `windows-sandbox-default` flavor เข้ากับ native
  global storage/config/Exec: ใช้ `Data/native`, private Node โดยตรง และ fail closed
  หาก allocation/dependency/policy ผิด ไม่ใช้ emergency `cmd.exe` fallback
- ช่วงนี้คง close semantics แบบ disconnect-only เดิม ไม่เพิ่มการหยุด VM อัตโนมัติ
  ปุ่ม/คำสั่ง normal stop และ cooperative session cleanup ยังเป็นงานแยกก่อนส่ง preview

### Explicit native flavor — source integration แล้ว แต่ยังไม่ compile รับรอง

- มี `windows-sandbox-default` แบบ default-off และตรวจขัดแย้งกับ portable flavor เดิม
- ต่อ global executable-root selection → `Data/native`, native terminal default,
  finalized-config adapter และ Exec fixed argv/cwd/fresh environment โดยไม่ผ่าน CMD
- worker รัน standalone suites: launch 7/7, portable_auto 15/15, adapter 8/8 ผ่าน
  suites เหล่านี้มี imported tests ซ้ำกัน จึงไม่รวมเป็นจำนวน tests ใหม่
- รอบ compile ของ worker ใช้ `--system` และติด missing `uucode`/`translate_c`
  ไม่ใช่หลักฐานว่า native integration compile ผ่าน; parent เริ่ม compile-only รอบใหม่
  โดยใช้ pinned manifest dependencies และแยก cache/output ใต้ `zig-out`
- ยังไม่รัน EXE, GUI, VM, provider หรือแพ็กข้อมูลจริง ไม่มี preview พร้อมส่ง ณ ขั้นนี้

### Native compile ผ่าน — ยังไม่ใช่ผล GUI/VM integration

- บิลด์แบบ parallel เคย OOM จึงเปลี่ยนเป็น `-j1` ใช้ cache เดิมและไม่แก้ pagefile/ปิด VM
- compile พบ error contract ของ `global.environMap` กระทบ CLI/theme เดิม แก้ที่ adapter
  ให้ clone validated allowlist และคง `error{OutOfMemory,Unexpected}` โดยไม่ fallback host env
- adapter suite ปัจจุบัน **9/9 ผ่าน**; full opt-in native compile **exit 0**
- หลักฐาน: `zig-out/native-sandbox-build-9ed7622e15044791a25ea60debb45ed5/build-global-error-contract-result.json`
- binary ของ compile รอบนี้ 44,400,640 bytes, SHA256
  `196FEFD24F5B97D492847C9F3F4E832CB2C5D683F0070634387998294070B156`
  เป็น baseline ก่อนเพิ่ม diagnostic offscreen ไม่ใช่ SHA ของ preview ที่ยังไม่ได้ส่ง
- กำลังทำ native controlled fixture แบบไม่ใช้ VM: EXE → ConPTY → private Node
  ต้องพิสูจน์ offscreen/no-focus ตั้งแต่สร้างหน้าต่าง และแยกผล paint/TTY ออกจาก human acceptance

### Controlled native fixture ผ่าน — ขั้นถัดไป real backend/VM

- parent ทวน receipt สำเร็จ: EXE → ConPTY → private Node, genuine TTY **103×31**,
  root/cwd/argv และ private environment ถูกต้องแม้เริ่มจาก cwd อื่น
- native parse marker/ไทย และวาดภาพจริง **16 frames/16 paints**, child จบเอง;
  missing Node/missing EXE และ stale-artifact negative cases ผ่าน
- offscreen opt-in มีผลเฉพาะ diagnostic: no-activate, เลื่อนพ้น virtual desktop
  ก่อนแสดงหน้าต่าง และไม่เปิด close-confirm dialog ใน diagnostic เท่านั้น
- หลักฐาน `zig-out/native-conpty-fixture-716cc5e6-6ebe-438e-b7b0-8e0ca7819896/receipt.json`
  และ `Data/native/logs/sandbox-native-frame.bmp` ภายใน relocated fixture
- parent ตรวจ SHA ของ BMP และแปลงเป็น PNG เพื่อดูภาพจริงแล้ว:
  เห็น marker สีแดงและคำว่าไทยบน terminal ไม่ใช่ OCR/physical keyboard/IME acceptance
- source checks: option/helper tests **2/2**, native build และ fixture runner exit **0**
- EXE SHA256 รุ่นนี้ `594097ee235653fa709ebe097633bd2588c91cf7285d517550470f0e24baf358`
- เริ่มงาน fresh unbooted native factory + distinct disposable VM test copy;
  ใช้ production backend จริง ไม่แทน App/entry ด้วยสคริปต์จำลอง และไม่ทดสอบกับ Data จริง

### Bun CPU และ Copy — งานเพิ่มที่ยังไม่แก้แพ็กใช้งานจริง

- เตรียม explicit SSE flags ใน backend และ host capability preflight; regression **113/113 ผ่าน**
  และ paused diskless WHPX fixture เปิด flags ที่ร้องขอสำเร็จ ไม่ใช่ผลรัน Bun ใน guest จริง
- ผู้ใช้อนุมัติ “ยืนยัน restart เลย” วันที่ 18 พฤศจิกายน 2026 เวลา 01:00 BKK
  สำหรับ CPU patch สองไฟล์และ normal stop/start ของ `A:\sandbox` เท่านั้น
  ไม่ใช่อนุญาตนำ native EXE ที่กำลังทดสอบไปแทนแพ็กนี้หรือรีเซ็ต Data
- manual selected-text Copy ฝั่ง host แยกจาก automatic guest clipboard sync;
  guest OSC 52 ยังคงถูกบล็อก และไม่ได้แก้หรืออ่าน system clipboard ระหว่างการทดสอบ

## ผล native → VM ที่ตรวจจบจริง (18 พฤศจิกายน 2026)

- แพ็ก public ที่ยังไม่เคยเปิด: `zig-out/native-preview-5a909091-d660-4282-9d93-aeb03647292f/Sandbox-Native-Preview`
  และ `sandbox-native-preview.zip` ในโฟลเดอร์เดียวกัน ไม่มี `Data`/บัญชี/SSH key/password hash
- ZIP SHA256 `467df0950200fec1f10ba31c037604c805705f746080d679eaf9716f5557554d`
- ผลจริง: `native-guest-fccc05bc-0aa4-46c8-910e-71ca4be1ee35.json` ในโฟลเดอร์แพ็ก
  ผ่านทั้ง `cold-start` และ `restart` โดย native EXE เป็นผู้เริ่ม manager/VM
- เส้นทาง input จริงผ่าน HWND ของ terminal → ConPTY → private Node → Linux PTY;
  guest UID 1000, Node `v24.22.1`, stdin/stdout เป็น TTY ขนาด 103×31
- marker สีแดงและคำว่าไทยถูก parse และวาดจริง; parent ตรวจภาพ
  `native-tty-verified.png` (1034×661) แล้ว ไม่ใช่ใช้ข้อความ echo ของคำสั่งเป็นหลักฐาน
- guest `exit` ทำให้ terminal จบเอง; manager เดิมยัง ready หลังหน้าต่างปิด
  จากนั้น authenticated normal stop ปิด VM และปล่อย manager state ได้จริง
  เปิดใหม่แล้วตรวจ synthetic persistence ผ่าน ก่อน normal stop รอบที่สอง
- ทดสอบนอก virtual desktop, no-activate และไม่ใช้ global keyboard/clipboard
  ชุดนี้ไม่เปิดแพ็กใช้งานจริงหรือย้ายข้อมูล/บัญชีเข้าแพ็กใหม่
- ข้อจำกัดของผลนี้: เคยเจอ official Node download timeout ใน first boot;
  รอบที่สำเร็จเริ่มต่อจาก fixture ของเราเดิมโดย **ไม่รีเซ็ต Data** หลังตรวจ public hashes,
  ownership และไม่มี process/disk ใช้งานค้าง ไม่ใช่ผล first-use password wizard
- หลังจบ parent ตรวจว่าไม่มี process ของชุด VM นี้, ไม่มี manager state ค้าง
  และ factory ต้นฉบับยังไม่มี `Data` พร้อมตรวจ public inventory/ZIP hash ซ้ำใน runner

### ข้อบกพร่องในตัวทดสอบที่แก้แล้ว

- `EnumWindows` ตัวแรกของ PID อาจเป็น hidden WGL/IME helper ไม่ใช่ terminal;
  เลือกเฉพาะ visible `localterm-dev.window-prototype` ของ child ที่เพิ่งเปิด
  โดยคง guard นอกจอ 64 pixels/no-activate/not-foreground เดิม ไม่ลดเกณฑ์เพื่อให้ผ่าน
- เปลี่ยน PowerShell HWND calls เป็น async เพื่อให้ controller ระบาย native debug pipes
  ระหว่าง `SendMessage` ไม่ค้างเพราะ event loop ถูก block
- คำตอบ control API ที่ timeout ไม่ได้แปลว่า manager ตาย; retry แบบมี deadline
  และตรวจ root/manager identity ทุกครั้งก่อน normal stop ไม่ลบ state หรือ kill PID จากไฟล์
- sandbox CJS suite สุดท้ายหลังรวม shared input/first-use/resume guards ผ่าน **137/137**
  หลักฐาน `sandbox-unit-final.log` ในโฟลเดอร์แพ็ก

### Native first-use password ผ่านแยกแล้ว

- `verify-native-first-use.cjs` เปิด EXE จริงนอกจอ ผ่าน private Node/ConPTY
  เรียก production `entry.main(['setup-guest', root])` กับ fixture ใหม่ ไม่มี VM/network
- ผ่านสอง fixture ใหม่: กรอกรหัสผ่านภาษาไทยทั้ง first/confirm ผ่าน HWND ของ terminal,
  ค่า hash ตรงกับข้อความทดสอบ, แสดงดาวแทนรหัสผ่าน และคืน raw mode หลังตั้งค่าสำเร็จ
- ทดสอบไม่บันทึกรหัสผ่านหรือ hash ลง stdout/report; negative cases ปฏิเสธ stale proof
  และ unexpected plaintext/hash writes ก่อนเก็บ capture — unit **11/11 ผ่าน**
- หลักฐานล่าสุด `zig-out/native-first-use-6bfdd028-ba5f-40be-bdd3-628c042077d9/first-use.json`
  พร้อม `native-first-use.png`; parent เปิดภาพตรวจแล้ว เห็นดาวทั้งสองบรรทัด ไม่มี plaintext
- เป็น real native setup-only verification, ไม่ใช่การทดสอบ first-use→VM boot ต่อกัน
  ใน process เดียว และไม่ใช่ human acceptance; factory เดิมยังไม่มี Data และไม่เปลี่ยน hashes

### งานที่ยังไม่ใช้ผลข้างบนแทนการตรวจรับ

- การตั้งรหัสผ่านครั้งแรกและ VM boot ถูกทดสอบแยก; combined first-use→boot ยังไม่ถือว่าผ่าน
- physical keyboard/IME, numpad บนเครื่องผู้ใช้, GPU/DPI/multi-monitor และ native exFAT
  ยังไม่ถือว่าตรวจรับจาก offscreen test นี้
- human acceptance ยังเป็นของผู้ใช้; ไม่มีการเปิดหน้าต่าง preview บนจอให้เอง
- Herdr Web opt-in VM-forward เป็นงานแยก; ผล unit/typecheck ไม่ใช่ browser/WS live acceptance

ไฟล์นี้เป็นแผนที่บันทึกสำเร็จแทน Goal tool ซึ่งคืน `EPERM: fsync` และตรวจซ้ำยังไม่มี Goal
ผลที่ผ่านข้างบนเป็น owned synthetic integration ไม่ใช่การรับรอง physical input
หรือความพร้อม production และไม่มีการ commit/push งานใน project

### 18 พฤศจิกายน: clipboard candidate และ Herdr host→guest บน D:

- clipboard ผ่าน native handler→Core→ConPTY กับ sink จำลอง รวม selection-copy,
  no-selection ETX, ไทย/อีโมจิ และ Ctrl+Shift/right-click เดิม ไม่แตะ clipboard ผู้ใช้
- reader ของ fixture ต้องรับ UTF-16 ที่ ConPTY ส่งเป็น VK_MENU key-up commits;
  ไม่แก้ production paste เพื่อหลบข้อจำกัดของ `.NET ReadKey`
- shipping build 123/123; factory `zig-out/native-clipboard-preview-20261118`
  ZIP roundtrip ผ่าน และ first-use EXE ใหม่นอกจอผ่านใน
  `zig-out/native-first-use-1b6f0d3c-2e67-457f-84e5-164f82108990/first-use.json`
- `zig-out/Sandbox-Native-Preview.zip` ชี้ ZIP ใหม่ SHA256
  `f80c1019cbc58665b1b9b891da92f50c0118a665b5521c3440a4c1be96bb27de`
  เก็บ branded factory รุ่นก่อนไว้ ไม่เปลี่ยน A: และไม่รวม Data
- Herdr ตัวเต็ม default guest loopback ตอบ HTML 200 ภายใน guest แต่ Windows
  เข้าไม่ได้; `bun start --vm-forward=54351` ผ่าน QEMU forward ของ fixture D:
  ทั้งหน้า UI, same-site origin-less document, WS 101 และ frames จริง
- Host/Origin/proxy และ origin-less API/POST/WS ผิดถูกปฏิเสธ 6 กรณี; real
  non-NAT peer ถูกปฏิเสธ และ host listener เป็น 127.0.0.1 เท่านั้น
- unit Herdr 34/34 และ typecheck app/tools ผ่าน; public-source patch แปดไฟล์
  อยู่ `zig-out/Herdr-VM-Forward.zip` ตรวจ apply byte-exact, conflict ไม่เขียน
  บางส่วน และ ZIP roundtrip แล้ว ไม่แก้ checkout C: หรือย้าย profiles
- หลักฐาน Herdr อยู่ `zig-out/herdr-host-live-d85e3f2a-0d31-49f0-82ac-87b15bb55d10`
  หน้า UI ใช้ Edge headless โปรไฟล์ใหม่ ไม่มี provider/native input acceptance
  ปิด QA Web, native Herdr และ VM D: ตามปกติทั้งหมดแล้ว ไม่หยุด VM ใน A:

OS clipboard จริง, Linux SIGINT ใน EXE ใหม่นี้, physical keyboard และ human
acceptance ยังไม่ถูกแทนด้วยผล controlled fixture หรือ first-use ข้างต้น

### ส่งมอบและพื้นที่ทดสอบ

- `zig-out/Sandbox-Native-Preview.zip` เป็น hardlink ของ ZIP ที่ตรวจ SHA แล้ว
  ไม่ใช่แพ็กใหม่/สำเนา ZIP กินพื้นที่อีกชุด; คู่มือข้างไฟล์ `zig-out/Native-Sandbox-TH.md`
- retire เฉพาะ public files ที่ SHA ตรง factory จำนวน 12,291 ไฟล์จาก failed copies 3 ชุด
  ลดขนาด logical 1,874,843,022 bytes โดยตรวจ ownership/reparse/ไม่มี process ก่อน
  ไม่ลบ directory, Data, backing image, ไฟล์ที่แก้ต่างจากต้นฉบับ หรือ baseline ที่เก็บไว้
- ตรวจซ้ำว่า Data และ public backing image ของทั้ง 3 ชุดยังอยู่
  รายละเอียด `retired-public-duplicates.json`; failed copies ที่ retire แล้วต้อง restore
  public payload จาก ZIP SHA เดิมก่อนนำมารันใหม่ ไม่ถือว่าเป็น standalone package แล้ว
- factory ยังไม่เคย boot, ไม่มี process ของ VM candidate ค้าง และไม่เปิด preview บนจอเอง

## รุ่น Sandbox branding / complete-public-repair

- fresh factory ปัจจุบัน: `zig-out/sandbox-branded-factory-20261118-1311/native-package.json`
  พร้อม verified manifest/ZIP round-trip; ไม่มี Data
- Native build `sandbox-branded-build-a291913e-7135-43ca-b82b-82801bd237b7` ผ่าน
  **123/123 build steps**; PE ProductName/FileDescription `Sandbox`, OriginalFilename `Sandbox.exe`
- EXE SHA256 `a5906d4b1548a2301877f4978cc366e128c6e87e44ca5235010147a4e26b16ff`
- ZIP SHA256 `f09b80c6bfe85f26ed10d5c71472bdb7755efe0791eb4e5e07d27d7ab812aa62`
  friendly path `zig-out/Sandbox-Native-Preview.zip` อ้างรุ่นนี้แล้ว
  alias รุ่น unbranded เก็บแยก ไม่เขียนทับ inode ของ baseline
- Zig branding **3/3 ผ่าน** หลัง red regression ที่ชื่อเดิมเป็น localterm-dev;
  CJS suite หลังเพิ่ม public repair/generated metadata guards **153/153 ผ่าน**
- `native-first-use-8747b202-53c7-457a-adb5-e345a175de00/first-use.json`
  พิสูจน์ live owned HWND title เป็น **Sandbox ทั้งสอง password prompts** ก่อน input,
  offscreen/no-activate/not-foreground, masked UTF-8 setup และ natural exit 0
  parent เปิดภาพตรวจ masking/Thai/red paint แล้ว ไม่มี plaintext
- `repair-native-public.cjs` ตรวจ public manifest/hash และ literal relative-require closure,
  stage inode ใหม่, backup ที่ตรวจ hash, revalidate ก่อนติดตั้ง และ rollback เมื่อผิดพลาด
  เก็บ owner/profile/storage policy/Data/extras ไม่ทับ altered backing image
  อนุญาตแทน known old EXE/entry และ generated pkgconfig สองไฟล์ได้เฉพาะ explicit old hashes
- เกณฑ์ module import เป็นการโหลด exports โดยไม่เรียก entry main จึงไม่ start VM,
  ไม่ใช้ผล import/setup-only นี้แทน terminal→VM boot หรือ human acceptance

## Clipboard shortcuts — งานกำลังตรวจ 18 พฤศจิกายน

- ผู้ใช้ยืนยันว่าใช้ Ctrl+C/Ctrl+V; รุ่น branding เดิมไม่มี Ctrl+V binding
  ใน Sandbox early-return config และ Ctrl+C ยังเป็น terminal interrupt
- พฤติกรรมที่กำลังแก้: Ctrl+C คัดลอกเฉพาะ selection; ไม่มี selection ส่ง ETX
  ผ่าน terminal ตามเดิม, Ctrl+V วางข้อความ, Ctrl+Shift+C/V คงอยู่
- ทดสอบด้วย selection จริงของ core + in-memory clipboard sink/source และ child
  สังเคราะห์บน ConPTY; ไม่แตะ Windows clipboard ของผู้ใช้ ไม่ boot/stop VM
- ETX acknowledgement พิสูจน์ byte ผ่าน ConPTY ไม่ใช่ผล Linux SIGINT หรือ
  Get/SetClipboardData บน Windows จริง; คง guest OSC52 filter และไม่เปิด automatic sync
- ยังไม่ถือว่าส่งมอบจน actual Config regression, controlled fixture และ build ผ่าน
