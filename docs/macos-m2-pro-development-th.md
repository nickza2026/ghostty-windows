# พัฒนา Sandbox บน MacBook Pro ชิป M2 Pro

คู่มือเริ่มงานบน Mac เครื่องจริง จาก source repo เดียวกับงาน Windows

ก่อนเริ่ม port ให้อ่าน [ข้อจำกัดและแผนรักษาข้อมูลบน M2 Pro](macos-m2-pro-data-constraints-th.md) ด้วย เป้าหมายเริ่มต้นคือ APFS ภายในเครื่องและพิสูจน์ backup/restore ก่อน USB portability

branch `feat/windows-sandbox-baseline` รวม Windows Sandbox development baseline และคู่มือนี้เพื่อใช้ศึกษาหรือ port ต่อ โดยไม่รวม Data/accounts, downloaded runtimes หรือ build caches ส่วน Windows ยังมี experimental/default-off paths และ qualification gaps ตามเอกสาร ไม่ใช่การรับรอง production readiness หรือผลทดสอบ Mac

## 1. สิ่งที่จะได้ในแต่ละช่วง

**ขณะเขียนเอกสารนี้ยังไม่มี Sandbox.app สำหรับ macOS ที่ผ่านการ build หรือทดสอบจริง** คำสั่ง build ในช่วงแรกสร้าง Ghostty macOS เดิม ไม่ได้สร้าง Linux sandbox โดยอัตโนมัติ

แยกผลลัพธ์เป็นสามระดับ:

1. **Mac development baseline**: clone repo, เตรียม Xcode/Zig และ build Ghostty บน M2 Pro ได้
2. **Mac Sandbox prototype**: เพิ่ม host backend ให้เริ่ม Linux ARM64 VM แล้วต่อ terminal ผ่าน SSH ได้ พร้อมเก็บข้อมูลข้ามการเปิดใหม่
3. **แพ็กสำหรับใช้งานจริง**: รวม runtime, profile isolation, first-use, recovery, USB-loss, packaging และการทดสอบครบ ก่อนเรียกว่า portable Sandbox พร้อมใช้

การผ่านระดับแรกไม่ใช่หลักฐานว่าระดับสองหรือสามเสร็จแล้ว และคู่มือนี้ไม่ได้อนุญาตให้ลบ Data เดิม ปิด VM ที่ใช้อยู่ ย้ายบัญชี หรือเรียก AI provider เพื่อทดสอบ

## 2. เหตุผลที่ไม่สร้าง repo ใหม่

repo นี้มี Zig terminal core ใน `src/` และแอป macOS แบบ SwiftUI/Metal ใน `macos/` อยู่แล้ว ใช้ทั้งสองส่วนเป็นฐาน แล้วเพิ่ม platform adapter สำหรับ Sandbox บน Darwin แทนการย้าย Win32 ทั้งชุด

| ส่วน | แนวทางบน M2 Pro |
| --- | --- |
| Terminal core, parser, rendering contracts | ใช้ core เดิมและรักษาการ build ของแพลตฟอร์มอื่น |
| หน้าต่างและ renderer | ใช้ SwiftUI/AppKit/Metal เดิม ไม่ port HWND/WGL มาใช้บน Mac |
| Host terminal transport | ใช้ Unix PTY/SSH แทน ConPTY และ Windows handle inheritance |
| VM acceleration | ใช้ backend ที่รองรับ Apple Silicon เช่น QEMU/HVF โดยออกแบบ lifecycle adapter ให้ชัดเจน |
| Guest | Linux ARM64/aarch64 image และเครื่องมือ Linux ARM64 |
| SSH agent | Unix-domain socket/กลไก macOS ที่แยกตามแพ็ก ไม่ใช้ Windows named pipe/DPAPI |
| USB loss | ใช้ volume identity และ unmount/removal notification ของ macOS ไม่ใช้ drive letter |
| Distribution | `.app` พร้อม runtime manifest และการตรวจ signing ตามช่องทางแจกจริง |

เลือก QEMU/HVF เป็น PoC แรกได้เพราะใกล้รูปแบบ QEMU/QMP ของ Windows แต่ยังต้องตรวจ runtime, firmware, entitlement และ lifecycle บน Mac จริงก่อนตัดสินเป็น backend สุดท้าย การใช้ Virtualization.framework เป็นอีก backend ต้องมี boot/storage adapter ของตัวเอง ไม่ใช่แค่เปลี่ยนชื่อ executable

## 3. เตรียม Mac และ source

### 3.1 ตรวจว่า terminal เป็น ARM64

เปิด Terminal บน Mac แล้วรัน:

```sh
uname -m
sw_vers
```

M2 Pro ใน native session ควรแสดง `arm64` ถ้าเห็น `x86_64` ให้ตรวจว่ากำลังเปิด Terminal ผ่าน Rosetta หรือใช้ shell จาก environment ที่จำลอง Intel อยู่ อย่าเริ่ม build แล้วถือว่าผลนั้นเป็น native M2 โดยไม่ตรวจ architecture ของ artifact

ใช้ workspace บน APFS ภายในเครื่องสำหรับ source/build รอบแรก เพื่อแยกปัญหา compiler ออกจาก filesystem ของ USB ยังไม่ต้องคัดลอกดิสก์ VM หรือบัญชีจาก Windows

### 3.2 Clone delivery branch

```sh
mkdir -p "$HOME/Developer"
cd "$HOME/Developer"
git clone --branch feat/windows-sandbox-baseline --single-branch \
  https://github.com/nickza2026/ghostty-windows.git
cd ghostty-windows
git status --short
git log -1 --oneline
```

ถ้ามีโฟลเดอร์ชื่อนี้อยู่แล้ว ให้ตรวจ branch และงานค้างก่อนใช้ checkout นั้น ไม่ลบหรือ reset เพื่อให้คำสั่ง clone ผ่าน บันทึก commit ที่ใช้ทดสอบไว้ เพื่อไม่ปะปนผลกับ branch รุ่นใหม่ในภายหลัง

เริ่มอ่าน `AGENTS.md`, `HACKING.md`, `build.zig.zon` และคู่มือนี้ก่อนสั่ง agent ทำงาน ห้ามถือว่า source Windows ที่มีอยู่เท่ากับ Mac backend ที่พร้อมใช้งาน

## 4. Toolchain ตาม source revision นี้

### Xcode

`HACKING.md` ของ revision นี้ระบุ **Xcode 26, macOS 26 SDK และ Metal Toolchain** การลงแค่ Command Line Tools ไม่เท่ากับมี toolchain สำหรับ build แอปนี้ครบ และเลข deployment target ของแอปไม่ใช่เวอร์ชัน SDK ที่ใช้ compile

ติดตั้ง Xcode จากช่องทาง Apple ที่ผู้ใช้เลือก เปิด Xcode ให้จบ first launch/license และติดตั้ง component/Metal Toolchain ที่ Xcode ต้องการก่อน แล้วตรวจ:

```sh
xcode-select -p
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
xcrun --find metal
```

ถ้าเครื่องมีหลาย Xcode ให้เลือกเวอร์ชันที่ตรงข้อกำหนดก่อน build อย่าเปลี่ยน system-wide `xcode-select` โดยไม่ตั้งใจ โดยเฉพาะเครื่องที่มีงานอื่นใช้ Xcode คนละเวอร์ชันอยู่ ดูข้อควรระวังเรื่อง environment ที่หัวข้อ 5 ด้วย

### Zig

`build.zig.zon` ของ revision นี้กำหนด `minimum_zig_version = "0.16.0"` และ baseline Windows ใช้ Zig 0.16.0 ให้เริ่มทดสอบ Mac ด้วยเวอร์ชันเดียวกัน ไม่แทนด้วย nightly/latest โดยอัตโนมัติ

ดาวน์โหลด **macOS aarch64** ของ Zig 0.16.0 จาก [ziglang.org/download](https://ziglang.org/download/) และตรวจ archive ที่ใช้จริงตามข้อมูล integrity/signature ของ upstream ที่มีให้ ไม่เทียบ hash ของไฟล์คนละชื่อหรือคนละ architecture

ตัวอย่างกรณีแตก toolchain ไว้ใน workspace แล้ว:

```sh
export PATH="$PWD/zig-out/toolchains/zig-aarch64-macos-0.16.0:$PATH"
zig version
file "$(command -v zig)"
```

ปรับชื่อโฟลเดอร์ให้ตรง archive ที่แตกจริง บรรทัด `export` มีผลเฉพาะ shell นี้ ไม่ต้องเขียนลง `~/.zshrc` หรือเปลี่ยน Node/CLI ของเครื่องเพื่อเริ่ม build

### Dependencies อื่น

เริ่มจากข้อกำหนดใน `HACKING.md` และ build errors ของ revision ที่ clone จริง การ build อาจดาวน์โหลด dependencies ของ Zig, Swift หรือ resource จาก upstream จึงต้องมีอินเทอร์เน็ต อย่าตีความการดาวน์โหลด dependency เป็นการอนุญาตให้เรียก model, login หรือย้าย credentials

Homebrew/QEMU/Node ที่ติดตั้งบน host ใช้เป็นเครื่องมือพัฒนาได้เมื่อผู้ใช้เลือกติดตั้ง แต่ยังไม่ใช่ runtime แบบ self-contained ที่จะใส่ในแพ็กสำเร็จรูป

## 5. Build Ghostty บน Mac ให้ผ่านก่อน

ตรวจว่ารันอยู่ที่ root ของ repo และ `zig version` ถูกต้อง:

```sh
mkdir -p zig-out/dev-cache/zig-global zig-out/dev-cache/tmp
export ZIG_GLOBAL_CACHE_DIR="$PWD/zig-out/dev-cache/zig-global"
export TMPDIR="$PWD/zig-out/dev-cache/tmp/"
zig build -j1 -Dxcframework-target=native -Demit-docs=false
```

ใช้ `-j1` เป็นจุดเริ่มต้นเพื่อลดการแย่ง resource กับงานอื่นบน Mac ไม่ใช่คำรับรองว่า build ทุกเครื่องใช้หน่วยความจำเท่ากัน ประเมิน Memory Pressure และพื้นที่ดิสก์จริงก่อนเพิ่ม parallelism หรือเริ่ม VM พร้อม compile

ข้อเท็จจริงของ build graph:

- Debug เป็นค่าเริ่มต้นเมื่อไม่กำหนด optimize
- `zig build` ปกติบน Mac ใช้ macOS app/XCFramework build และค่าเริ่มต้นเป็น universal framework; คำสั่งด้านบนเลือก `-Dxcframework-target=native` เพื่อ build arm64 ของ M2 โดยตรง
- `zig build run` มีเส้นทาง native-only สำหรับ host architecture และส่ง arguments หลัง `--` ให้ executable
- `-Demit-macos-app=false` ข้าม app bundle จึงไม่ใช่การพิสูจน์ว่า SwiftUI app build ผ่าน
- ไม่มีเหตุผลให้ใส่ `-Dapp-runtime=win32`, `-Dwindows-sandbox-default=true` หรือ Windows renderer flags บน Mac

`src/build/GhosttyXcodebuild.zig` เลือก configuration `Debug` หรือ `ReleaseLocal` ตาม optimize โดย Debug bundle ของ Xcode อยู่ที่:

```text
macos/build/Debug/Ghostty.app
```

install step คัดลอก app bundle ไป prefix ของ Zig ด้วย ให้ตรวจ artifact ที่เกิดขึ้นจริง ไม่ใช้เพียงการพบ directory เก่าหรือ exit code ของคำสั่งอื่นเป็นผล build รอบนี้

prefix ปกติได้ `zig-out/Ghostty.app` ไม่ใช่ `zig-out/bin/Ghostty.app` ตรวจ architecture ของ executable ที่ build แล้วได้ด้วย:

```sh
file macos/build/Debug/Ghostty.app/Contents/MacOS/ghostty
```

**ข้อจำกัดการเลือก Xcode:** Zig build wrapper สร้าง environment ใหม่ให้ `xcodebuild` โดยส่ง `PATH` เป็นหลัก ดังนั้นตั้ง `DEVELOPER_DIR` ใน parent shell แล้วไม่ได้แปลว่าค่าจะไปถึงทุก child step ตรวจ Xcode ที่ถูกเรียกจริง ถ้า wrapper ใช้ Xcode ผิด ให้แก้การส่ง environment เฉพาะ build stepหรือให้ผู้ใช้เลือก active Xcodeอย่างชัดเจน ไม่อ้างว่า export อย่างเดียวแก้แล้ว

### เปิด baseline แบบไม่โหลด config เดิม

เมื่อต้องตรวจแค่ executable baseline ใช้คำสั่งที่ไม่เปิด login shell/CLI ของผู้ใช้:

```sh
zig build run -j1 -Demit-docs=false -- \
  --config-default-files=false \
  --command=/usr/bin/true
```

คำสั่งนี้อาจปิดหน้าต่างเร็ว เป็นเพียง baseline launch ไม่ใช่ render/TUI/VM acceptance และยังเป็นโปรเซสบน macOS ไม่ใช่ใน Linux sandbox อย่าทดสอบ provider/login เพื่อพิสูจน์การแยก environment

ถ้า command-line/config parsing ของ revision ที่ clone แตกต่าง ให้หยุดตรวจ source และ error ของรอบนั้นก่อนแก้ ห้าม fallback ไปเปิด host shell โดยเงียบ ๆ

## 6. งาน port ที่ต้องทำต่อหลัง baseline ผ่าน

### Milestone A — แยก host adapter

กำหนดขอบเขตร่วมสำหรับ prepare/start/status/terminal/normal stop โดยไม่เอา Win32 API ไปเรียกบน Darwin เก็บ proof of ownership ของ manager/VM, authenticated local control, disk lock และ recovery ที่ตรวจ process/port/disk จริง

ให้ implementation Windows เดิมยังทำงานเหมือนเดิมก่อนเพิ่ม Mac เลี่ยงการเปลี่ยน schema/path ของ Data Windows เพื่อรองรับ Macในรอบเดียวกัน ทุก draft API/path ในหัวข้อนี้เป็นแบบที่ต้อง implement ไม่ใช่ชื่อ flag หรือ backend ที่มีอยู่แล้ว

### Milestone B — Linux ARM64 VM ที่เป็นของ fixture

1. จัดหา QEMU **macOS arm64** และตรวจว่ามี HVF accelerator ด้วย `qemu-system-aarch64 -accel help`
2. ใช้ Linux **ARM64/aarch64 cloud image** จาก upstream ที่ pin รุ่น/URL/hash ของไฟล์เดียวกัน เตรียม UEFI/firmware และ writable variable store ที่เข้ากับ QEMU รุ่นนั้น
3. ทำ disk overlay และ seed ใหม่ใน fixture ที่เป็นเจ้าของ ไม่ใช้ guest disk ที่มีบัญชีจริงจาก Windows
4. แปลง machine/CPU/device/boot/network arguments สำหรับ ARM `virt` โดยตรง ไม่ค้นหาแล้วแทน `qemu-system-x86_64.exe` ด้วยชื่อใหม่ทั้งบรรทัด
5. เปิด host SSH forwarding เฉพาะ loopback และใช้ guest account ที่ไม่ใช่ root โดยมี host-key verification
6. ตรวจ guest architecture เป็น `aarch64`, Node/npm **Linux ARM64**, user-global npm install, restart persistence และ normal stop ที่ออกจริง

ยังไม่มีคำสั่ง QEMU ARM ที่ทดสอบกับแพ็กนี้ครบ จึงไม่ให้บรรทัด launch ที่เดา path firmware/seed/device ไว้เป็นคำสั่งพร้อมใช้ ถ้า HVF/firmware/entitlement ไม่ผ่าน ให้แก้ข้อจำกัดนั้น ไม่ปิด SIP, Gatekeeper หรือระบบความปลอดภัยทั้งเครื่องเพื่อให้ PoC ผ่าน

M2 Pro เร่ง Linux ARM64 ได้ แต่ดิสก์ boot Linux x86_64 เดิมไม่ได้กลายเป็น ARM64 ด้วยการเปลี่ยน extension การ emulate x86_64 เป็นอีกโหมดที่มีข้อจำกัดด้านความเร็ว ไม่ใช่ native baseline ที่เลือกไว้

### Milestone C — ต่อ terminal จากแอป

เปิด terminal ที่สั่งงานใน guest ผ่าน SSH/PTY เท่านั้นเมื่อเลือก Sandbox mode ถ้า VM, profile, agent, runtime หรือ package identity ไม่พร้อม ให้แสดงข้อผิดพลาด ไม่เปิด shell ของ macOS แทน

ทดสอบ input/output TTY, resize, Ctrl+C/SIGINT, Ctrl+D, Unicode ไทย/emoji และ TUI โดยดูผล paint จริง แยก keyboard input, terminal stream และ window lifecycle ไม่ถือว่า SSH connect สำเร็จเท่ากับ terminal ใช้งานครบ

### Milestone D — portable profile และบัญชี

เริ่มจาก profile ใหม่ของ Mac ไม่ import `.ssh`, Cursor, Letta, provider keys, browser session หรือ Keychain ของผู้ใช้โดยอัตโนมัติ การเลือกใช้ Keychain/รหัสผ่านปลดล็อกต้องเป็นข้อตกลงชัดเจน ไม่อ้างว่า keys ใน USB plaintext ปลอดภัยเพียงเพราะเรียก portable

จัด runtime/data ให้อิง root ของแพ็กที่กำลังรัน ไม่อิง cwd และไม่ fallback ไป host Node, host home หรือ host temporary directory เมื่อพื้นที่แพ็กใช้ไม่ได้ ตัวอย่าง layout เป้าหมาย:

```text
Sandbox-Mac/
  Sandbox.app
  Runtime/macos-arm64/
  Data/macos-arm64/
    vm/
    ssh/
    profile/
    logs/
    tmp/
```

layout นี้เป็นข้อเสนอสำหรับ implementation ใหม่ ไม่ใช่ directory ที่สร้างแล้ว ข้อมูล runtime ที่เปลี่ยนได้ไม่ควรเขียนเข้า signed `.app` bundle สำหรับ shared USB ต้องแยก Windows/macOS data และ guest architecture พร้อม platform/profile binding ที่ตรวจได้

การเก็บ app-owned runtime/profile ตามแพ็กไม่ใช่ filesystem sandbox ของ macOS ทั้งเครื่อง ระบบปฏิบัติการ, SDK, fonts และ system caches ยังอาจใช้พื้นที่ของเครื่องตามปกติ

ใช้ APFS สำหรับ baseline ก่อน ถ้าต้องพก USB เดียวข้าม Windows/Mac ต้องทดสอบ exFAT และข้อจำกัด permission/locking/encryption แยกต่างหาก อย่าทำเครื่องหมาย security เท่ากันเพราะ filesystem อ่านได้ทั้งสองเครื่อง

### Milestone E — USB-loss และ lifecycle

ใช้ volume identity ที่ผูกกับ package root และ notification ของ macOS; error จากไฟล์, permission denial หรือ SSH หลุด ไม่ใช่หลักฐานว่า USB หาย

เมื่อยืนยันว่า volume ที่เก็บแพ็กหาย ให้ซ่อน/ปิดเฉพาะ terminal ที่เป็นเจ้าของโดยไม่ติด confirmation ระหว่าง cleanup และไม่ force-stop VM อัตโนมัติ กรณีเกิดเหตุขณะมี dialog/nested event loop ต้องป้องกัน callback/deinit ซ้ำด้วย

ทดสอบด้วย owned fixture และ synthetic event ก่อน ไม่เริ่มด้วยการถอด USB ที่มี VM/account จริง การปิดหน้าต่างไม่ทำให้การถอดดิสก์ระหว่างเขียนข้อมูลปลอดภัย

### Milestone F — Cursor และแพ็กใช้งานจริง

Cursor UI อยู่บน Mac และ remote server อยู่ใน guest ใช้ remote workspace ใน Linux ผ่าน SSH แยก profile ของ IDE ตามที่ผู้ใช้เลือก ไม่เขียนทับ `~/.ssh/config` หรือ settings ของ Cursor เดิมอัตโนมัติ

การเชื่อมครั้งแรกอาจต้องดาวน์โหลด Cursor server ภายใน guest ต้องทดสอบ Anysphere Remote SSH/architecture/forwarding บน Macจริงก่อนแสดงปุ่มว่าเชื่อมพร้อมใช้ การ login และ consent เป็นของผู้ใช้ ไม่ย้าย Windows Cursor profile มาทั้งชุด

แพ็กสำเร็จรูปต้องมี runtime inventory/hash, architecture checks, first-use, startup recovery, normal shutdown และ signing/distribution policy ที่ทดสอบแล้ว Local development build ไม่เท่ากับ notarized release และการเปลี่ยน binary ใน signed bundle อาจทำให้ signature ไม่ตรง

## 7. วิธีตรวจงานและบันทึกหลักฐาน

เริ่ม targeted tests ของส่วนที่แก้ แทนการรันทุก suite แล้วไม่รู้ว่าอะไรผ่าน:

```sh
zig build test -j1 -Dtest-filter='ชื่อ test ที่มีจริง'
```

แทน filter ด้วยชื่อจาก source จริง ถ้าเลือก filter แล้วไม่เจอ test อย่านับเป็นผ่าน ดู `AGENTS.md` สำหรับคำสั่ง test/format และอย่ารัน formatter ทั้ง repoจนแก้งานเดิมที่ไม่เกี่ยวข้อง

เก็บ source commit, toolchain versions, architecture ของ host/guest, exact command, exit code และ artifact hash ของรอบนั้น ห้ามใช้ log/screenshot เก่าที่มีอยู่ก่อนมาแทนผล acquisition ที่ล้มเหลว

automated GUI smoke ต้องอยู่นอกขอบทุก monitor ไม่ activate/steal focus และยังตรวจ genuine render/paint; interactive preview ที่ผู้ใช้ขอดูเองเปิดตามปกติ ผล offscreen ไม่ใช่ human acceptance หรือ qualification ทุกจอ/DPI

ก่อนประกาศ Mac Sandbox พร้อม ต้องมีอย่างน้อย:

- native M2 build และ fresh first-use จากแพ็ก data-free
- เปิดจาก stopped state ด้วย entrypoint จริง ไม่ใช้ helper boot VM ให้ล่วงหน้า
- reopen, crash/stale-state recovery ที่ไม่ลบ lock/state ของ owner ที่ยังอยู่หรือไม่ทราบสถานะ
- guest-only commands, environment isolation, npm install และ persistence
- Thai/emoji/input/resize/SIGINT และ renderer/PTY cleanup ที่พิสูจน์ได้
- loopback-only network/SSH authentication และ negative tests
- USB-loss ที่ไม่ปิดผิด volume ไม่ค้าง dialog ไม่ double-cleanup และไม่ force VM
- แยกข้อมูล/บัญชี Windows กับ Mac และไม่ทำให้ build/runtime Windows เสีย

การทดสอบกับ Macจริงในรายการนี้ยังไม่ได้รันจากเครื่อง Windows ที่เขียนเอกสารนี้

## 8. ส่งงานให้ agent บน Mac ต่อ

ใช้ brief นี้ได้หลัง clone และตรวจ toolchain แล้ว:

> อ่าน AGENTS.md, HACKING.md และ docs/macos-m2-pro-development-th.md ใน repo นี้ก่อน เริ่มจากตรวจ native arm64/Xcode26 SDK/Metal/Zig0.16 และ build Ghostty macOS baseline ให้ผ่าน แยกหลักฐาน baseline ออกจาก Sandbox ที่ยังไม่ implement จากนั้นเสนอ host-adapter patch ขนาดเล็กสำหรับ Linux ARM64 VM โดยรักษา Windows implementation เดิม ห้ามอ่าน/ย้ายบัญชีหรือ credentials ห้ามใช้ดิสก์ VM จริงเป็น fixture ห้ามเปลี่ยน global settings, ปิดแอป/VM ผู้ใช้, commit/push, download runtime ใหม่หรือเรียก provider โดยอาศัย brief นี้เป็นการอนุมัติโดยอัตโนมัติ ถ้าต้องเพิ่ม dependency หรือเปลี่ยนสิทธิ์ ให้ระบุรายการและขออนุมัติก่อนทำ ทดสอบสิ่งที่ทำได้อย่างปลอดภัยให้จบและรายงานสิ่งที่ยังไม่ผ่านตามจริง

**ขั้นแรกบน M2 Pro: clone branch นี้ ตรวจ toolchain แล้ว build Ghostty baseline ก่อนเริ่ม port VM backend**

## อ้างอิงใน repo

- [แนวทางพัฒนา upstream](../HACKING.md)
- [ข้อกำหนด agent](../AGENTS.md)
- [Zig/dependencies](../build.zig.zon)
- [macOS build wrapper](../src/build/GhosttyXcodebuild.zig)
- [XCFramework build](../src/build/GhosttyXCFramework.zig)
- [macOS application source](../macos/)
