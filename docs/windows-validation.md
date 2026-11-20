# บันทึกการตรวจ Windows baseline

## Human report ล่าสุด — 19 ตุลาคม 2026 เวลา 10:12

ผู้ใช้ลองmanualpreviewcandidate50ตามchecklistbasicThai/English/สระวรรณยุกต์/การแก้ข้อความ/Enterแล้วตอบ “ปกตินะ” พร้อมภาพ ถือเป็นuser-reportednormalสำหรับชุดพื้นฐานนี้ ไม่ใช่agentตรวจภาพ: เครื่องมือViewImageล้มเพราะimageworkerหาย จึงไม่อ้างvisualinspectionหรือรายละเอียดที่ไม่ได้เห็น ไม่เหมารวมว่าIMEcomposition/candidateทุกภาษา,physicalDPI,OSclipboard/CLIหรือการใช้จริงสองสัปดาห์ผ่าน Strictlifecycleยังfailedตามเดิม ไม่มีการเปลี่ยนgate

เวลา10:14ผู้ใช้ยืนยันmanualtextpasteปกติ แต่เลือกข้อความ/copy/ล้อเมาส์ไม่ได้ จึงเปิดmouse/selection/copyblocker ไม่เหมารวมว่าclipboardทั้งหมดผ่าน พบnativeWndProcยังไม่ส่งmouseเข้าCore กำลังเพิ่มhooksและoffscreenregressionบนcandidate51แยกprefixเดิม โดยยังไม่เปิดGUI/อ่านclipboardแทนผู้ใช้ และcopywritepermission/pathยังต้องhumanทวนเมื่อเลือกข้อความได้แล้ว

> สถานะล่าสุดของ CDB/handle ownership และ shutdown deadlock ดู
> [Windows runtime attribution](windows-runtime-attribution.md) และหัวข้อ “ล่าสุด” ใน `PLAN.md`;
> วันที่/ข้อความ baseline ด้านล่างเป็นหลักฐานตามช่วงเวลา ไม่ใช่คำรับรอง artifact ปัจจุบัน

วันที่ตรวจ: 16 ตุลาคม 2026<br>
ขอบเขต: เตรียมเครื่องและตรวจ baseline ก่อนเริ่ม implementation แอป Win32<br>
เครื่องมือช่วยตรวจ: Letta Code; ยังไม่มีผล independent review จาก subagent

## สรุปล่าสุด ณ 12:14 GMT+7 — เฟส 0/1 ผ่านตามขอบเขต baseline

- Compatibility diff มี 2 ไฟล์: `src/build/SharedDeps.zig`, `src/renderer/OpenGL.zig`
- Full-core หลัง patch ทั้งสองผ่าน: exit 0, `89/89 steps succeeded; 3917/3978 tests passed (61 skipped)` เวลา 11:59:52 GMT+7
- Targeted platform-payload/memory-cleanup ผ่านก่อนหน้า: 76/76 tests
- VT regression รอบ concurrent ล้มเพราะ test runner timeout แม้อีกชุดผ่าน 3,596/3,628 (32 skipped); ยังไม่ยืนยันสาเหตุ
- VT retry แบบ `-j1` โดยไม่ซ้อนกับ full-core ผ่านเวลา 12:13:16: exit 0, `45/45 steps succeeded; 6722/6786 tests passed (64 skipped)` ไม่มี test filter/skip/timeout override
- Library build หลัง patch ผ่านเวลา 12:14:08: exit 0, `48/48 steps succeeded`; `zig fmt --check` ของ source 2 ไฟล์และ `git diff --check` ผ่าน
- ปิดเฟส 0/1 ในขอบเขตเครื่องมือ/provenance/VT baseline/full-core หลัง compatibility patch ที่อนุมัติแล้ว เหตุ runner timeout ก่อนหน้าคงเป็น follow-up ที่ยังไม่ยืนยัน root cause ไม่ลบหรือเปลี่ยนผลเก่า
- ยังไม่ทดสอบ Linux/GPU/หน้าต่าง Win32/IME จริง และยังไม่ commit/push

## Checkout

- โฟลเดอร์: `D:\works\ghostty-windows`
- สาขางาน: `windows-terminal-baseline` สร้างจาก `main`
- Baseline ที่ตรวจพบ: `b3dc3d794513c11633e7c3347935693957744e83`
- ซอร์สระบุรุ่น `1.3.2-dev` และ Zig ขั้นต่ำ `0.16.0`
- ก่อนเริ่มมี `PLAN.md` และ `.letta/` เป็น untracked; เก็บไว้ ไม่ลบหรือ stage
- การตรวจ official provenance: passed — fetch สำเร็จ, baseline ตรงกับ `upstream/main` และ tracked tree ไม่มี diff; รายละเอียดและขอบเขตการรับรองอยู่ใน `sources.md`

## เฟส 0 — Toolchain

| รายการ | สถานะ | หลักฐาน/ข้อจำกัด |
|---|---|---|
| VS 2022 Community | passed (discovery) | `vswhere` พบรุ่น `17.14.24` และ component `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` |
| VS 2022 Build Tools | passed (discovery) | พบแยกอีก installation; เลือก Community สำหรับ baseline นี้ ไม่ติดตั้งเพิ่ม |
| Developer Shell x64 | passed | โหลด `Microsoft.VisualStudio.DevShell.dll` และเรียก `Enter-VsDevShell` ด้วย `-arch=x64 -host_arch=x64` ได้ |
| MSVC | passed (discovery) | `Get-Command cl,link` พบใน toolset `14.44.35207`; ยังไม่ทดสอบ compile/link |
| Windows SDK | passed (discovery) | Developer Shell เลือก `WindowsSDKVersion=10.0.26100.0\`; พบ `rc.exe` แบบ x64 |
| Zig | passed | ติดตั้ง portable หลังผู้ใช้อนุมัติ ตรวจ archive SHA-256 ตรง official index และ `zig version` ได้ `0.16.0`, exit code 0 |
| Zig official release | passed (metadata) | อ่าน `https://ziglang.org/download/index.json` ได้ พบ Windows x86_64 รุ่น `0.16.0` |

คำว่า discovery/metadata หมายถึงตรวจพบเครื่องมือหรือข้อมูลเท่านั้น ไม่ใช่หลักฐานว่าบิลด์ผ่าน การตั้ง Developer Shell มีผลเฉพาะ process ที่รันคำสั่ง ต้อง initialize ใหม่ใน process ที่จะบิลด์จริง

### Zig portable ที่ติดตั้งแล้ว

- URL: `https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip`
- ขนาดจาก official index: `97217739` ไบต์
- SHA-256 จาก official index: `68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e`
- ดาวน์โหลดแล้ว ขนาดไฟล์จริง `97217739` ไบต์ และ SHA-256 ตรงค่าข้างต้น
- Executable: `C:\Users\nickl\AppData\Local\Programs\Zig\zig-x86_64-windows-0.16.0\zig.exe`
- ใช้แบบ portable นอกรีโป และเพิ่ม PATH เฉพาะ process ของ build ไม่เปลี่ยน system/user PATH
- ผู้ใช้อนุมัติวันที่ 16 ตุลาคม 2026 เวลา 10:50 GMT+7; ตรวจ hash/extract/`zig version` สำเร็จเวลาใกล้ 10:54 GMT+7

## เฟส 1 — Test matrix

| รายการ | Working directory | สถานะ |
|---|---|---|
| `zig build test-lib-vt --summary all` | รากรีโป | passed — exit 0; รวม 6,722 passed, 64 skipped, 6,786 total จาก 2 runners; 10:54:34–11:08:59 GMT+7 |
| `zig build -Demit-lib-vt --summary all` | รากรีโป | passed — exit 0; 11:08:59–11:09:32 GMT+7 |
| Static linking example | `example/c-vt-static` | build passed — exit 0; 11:09:32–11:11:47 GMT+7; runtime recheck passed — native exit 0 และ output `Extracted title: hello` |
| Dynamic linking example | `example/c-vt-effects` | build passed — exit 0; 11:11:47–11:13:12 GMT+7; copy DLL ตาม workflow และ runtime passed — native exit 0, output `Total bells: 2` |
| `zig build -Dapp-runtime=none test --summary all` | รากรีโป | failed — exit 1; 11:13:41–11:15:25 GMT+7; 87/91 build steps succeeded, 1 failed; compile ติด `pwd.h` จึงยังไม่ได้รัน full-core tests |

เมื่อรันจริงให้เพิ่ม command, timestamp, exit code, test counts รวม skipped/failed และ log reference ที่ไม่มีข้อมูลลับ ห้ามเปลี่ยน not run เป็น passed จากการอ่าน workflow

Log ของรอบนี้อยู่ที่ `C:\Users\nickl\AppData\Local\Letta\build-logs\ghostty-windows\20261016-105434` มี `results.jsonl` และ stdout/stderr แยกตามขั้น สรุปที่แจ้งช่วงแรก 3,596 passed/32 skipped เป็นเพียง runner ที่อ่านท้าย log; ตรวจ summary ครบภายหลังพบอีก runner 3,126 passed/32 skipped รวม 6,722 passed/64 skipped ผล skipped ไม่ถือว่าผ่าน และยังไม่ได้ audit สาเหตุเป็นรายเทสต์ ผลดังกล่าวไม่รับรอง GUI/PTY/renderer

ตรวจเวลา 11:10 GMT+7 พบโปรเซส Zig ของ static example ยัง compile จริง ไม่ได้หยุดรอ input ผลเทสต์รอบแรกใช้เวลาประมาณ 14 นาที รวม compile/dependency preparation และ test run (test run ประมาณ 9 นาทีตาม summary)

Static runtime ครั้งแรกแสดง output ถูกต้อง แต่ตัวตรวจ `Start-Process`/`WaitForExit` อ่าน `ExitCode` เป็น null จึงเกิด false failure ของ harness ไม่ใช่หลักฐานว่าแอป exit nonzero รันซ้ำด้วย native invocation และอ่าน `$LASTEXITCODE` ทันทีได้ 0 พร้อม output ที่คาดไว้ ผลครั้งแรกยังเก็บใน `runtime-results.jsonl`; ผลยืนยันอยู่ในรายการ `static-runtime-recheck` และ `static-runtime-recheck.stdout.log` ไม่ลบหรือเปลี่ยนผลเก่าให้ดูผ่าน

Dynamic runtime ใช้ DLL จาก `example/c-vt-effects/.zig-cache/o/333cabb39763c648a2499d679fc2e68a/ghostty-vt.dll` คัดลอกเข้า `zig-out/bin` และเรียก exe โดยตรงตามแนวทาง Windows CI ได้ callbacks สำหรับ bell, title, write_pty, clipboard และ unknown APC/OSC ตัวอย่าง clipboard เป็น mock callback ของตัวอย่าง ไม่ได้พิสูจน์ clipboard ของแอป Win32 หรือเข้าถึงคลิปบอร์ดจริง ผลอยู่ใน `dynamic-runtime.stdout.log` และ `runtime-results.jsonl`

VT baseline ผ่านตามขอบเขต tests/library/static/dynamic linking แล้ว ส่วน full-core probe บันทึกแยกเป็น `full-core.stdout.log`, `full-core.stderr.log` และ `full-core-result.json` เฟส 1 ยัง blocked ที่ full-core compatibility ไม่เริ่มเฟส 3 จนกว่าตัดสินใจขอบเขต patch ตามแผน

เวลาใกล้ 11:14 GMT+7 พบ full-core compile error ที่ยืนยันแล้ว: generated `posix_c.h` include `pwd.h` ซึ่งไม่พบใน native MSVC target ต้นทางคือ `src/build/SharedDeps.zig:219–229` ยังรอ runner จบทั้ง graph จึงยังไม่ระบุ final exit code รายละเอียดและแนวทางที่ยังไม่ลงมืออยู่ใน `gaps.md` รายการ `WIN-BUILD-001` ส่วนข้อความของ `hb_c.h` ที่พบเป็น warnings ยังไม่รับรองว่าเป็น fatal failure

ผลสุดท้ายเวลา 11:15:25 GMT+7: runner จบ exit 1, summary `87/91 steps succeeded (1 failed)` โดยขั้นที่ล้มคือ `translate-c posix_c.h`; downstream compile/run ของ full-core จึงไม่สำเร็จ ส่วน `translate-c hb_c.h success 4s` ยืนยันแล้วว่า warnings ที่พบไม่ใช่ fatal blocker ในรอบนี้ ไม่ถือว่าจำนวน build steps เป็นจำนวน tests และไม่รับรองว่าแก้ `pwd.h` จุดเดียวแล้วจะผ่านทั้งหมด เพราะ compiler อาจยังไม่ถึงข้อผิดพลาดถัดไป

### Recheck หลังผู้ใช้อนุมัติ POSIX compatibility patch

- Patch แรก: `src/build/SharedDeps.zig` สร้าง `posix_c` เฉพาะ non-Windows โดยไม่เปลี่ยน test filters หรือสร้าง stub
- `zig fmt --check src/build/SharedDeps.zig` ผ่าน และ `git diff --check` ผ่าน
- Full-core command เดิม: 11:42:01–11:43:23 GMT+7, exit 1, `86/89 steps succeeded (1 failed)`
- ปัญหา `pwd.h` ไม่เกิดแล้ว; error ถัดไปคือ `src/renderer/Dmabuf.zig:44` ใช้ `@splat(-1)` กับ Windows HANDLE type รายละเอียด WIN-BUILD-002 ใน `gaps.md`
- Full-core tests ยังไม่ได้รัน ไม่อ้างว่าผ่านจากการข้าม compile blocker แรก
- VT test regression หลัง patch: exit 1 เวลา 11:55:52 GMT+7, command `zig build test-lib-vt --summary all`; ชุดหนึ่งผ่าน 3,596 และ skipped 32 แต่อีก test runner `test.exe` ไม่ตอบ `--listen=-` เป็นเวลา `1m2.442ms`; ไม่ถือว่ารอบนี้ผ่าน ส่วน library build regression ยังไม่ได้รัน เพราะ runner หยุดเมื่อขั้นแรก exit 1; metadata `posix-regression-results.jsonl`
- ต่อมาผู้ใช้อนุมัติขยาย DMA-BUF compatibility เวลา 11:44 GMT+7 เพิ่ม Windows compile-time guard ใน `OpenGL.zig` และ platform-payload/memory-cleanup test โดยคง `Dmabuf.zig`/Linux ownership เดิม ขณะนี้รัน targeted test แล้วจึง full-core เดิมเมื่อ targeted ผ่าน; metadata `dmabuf-results.jsonl` ยังไม่รับรองผลล่วงหน้า และยังไม่เริ่ม runtime Win32

Targeted check `zig build -Dapp-runtime=none test --summary all -Dtest-filter=ExportedFrame` ผ่านเวลา 11:46:49 GMT+7: exit 0, `89/89 steps succeeded; 76/76 tests passed` (รวม test blocks ที่ build runner เลือก ไม่ใช่ผล full suite) ขณะนี้ full-core แบบไม่ filter กำลังรันต่อ ผล Linux/GPU/การวาดภาพยังไม่ได้ตรวจ

ผล full-core แบบไม่ filter หลัง patch ทั้งสอง: 11:46:49–11:59:52 GMT+7, exit 0, `89/89 steps succeeded; 3917/3978 tests passed (61 skipped)` โดย compile ประมาณ 2 นาทีและ run tests ประมาณ 10 นาที ตาม summary ผลอยู่ใน `full-core-dmabuf.stderr.log` และรายการ `full-core-dmabuf` ของ `dmabuf-results.jsonl` ไม่ถือว่า 61 skipped ผ่าน และยังไม่ได้ audit สาเหตุรายเทสต์

VT regression รอบที่มี runner timeout รันซ้อนเวลากับ full-core compile/test จึงต้องตรวจซ้ำแบบแยก workload ก่อนสรุปว่าเป็น code regression หรือ runtime/test-runner instability ยังไม่มีหลักฐานให้ฟันธงว่าความซ้อนเป็นสาเหตุ ไม่เพิ่ม timeout หรือปิดเทสต์เพื่อกลบปัญหา เก็บ log เดิมไว้ และจะ retry full VT suite แบบจำกัด concurrency หลัง full-core ปัจจุบันจบ ไม่เริ่ม VT runner ซ้ำขณะชุดเดิมยังรัน

หลัง full-core จบ เริ่ม retry `zig build test-lib-vt -j1 --summary all` ตามด้วย `zig build -Demit-lib-vt -j1 --summary all` เมื่อ tests ผ่าน ตรวจ `zig build --help` ก่อนใช้ concurrency flag แล้ว ไม่มี test filter/skip/timeout override ผลจะอยู่ใน `vt-serial-results.jsonl`, `vt-serial-recheck.*`, `vt-build-final.*` ยังรอผล

ผล retry VT: 12:00:16–12:13:16 GMT+7, exit 0, `45/45 steps succeeded; 6722/6786 tests passed (64 skipped)` แยกเป็น 3,126 passed/32 skipped และ 3,596 passed/32 skipped ตรงกับ baseline เดิมทั้งหมด ข้อสังเกต: `-j1` จำกัด concurrency ของ build แต่ตรวจ process จริงยังพบ test runners 2 ตัวภายใน command นี้ จึงไม่อ้างว่ารันทีละ test process หรือพิสูจน์สาเหตุ timeout ได้ เพียงยืนยันว่ารอบไม่ซ้อน full-core นี้ผ่านด้วย source ปัจจุบัน

ผล library build หลัง tests: `zig build -Demit-lib-vt -j1 --summary all`, 12:13:16–12:14:08 GMT+7, exit 0, `48/48 steps succeeded` ตาม `vt-build-final.stderr.log` และ `vt-serial-results.jsonl` จากนั้นตรวจ format/diff ผ่าน ผล static/dynamic examples เป็นผล baseline ก่อน source patches; ไม่อ้างว่ารัน linking examples ซ้ำหลัง patch แต่ VT library/test regression ของ source ปัจจุบันผ่านแล้ว

## สิ่งที่ยังไม่ตรวจ

- Standalone smoke test ด้วย `cl.exe`/`link.exe` โดยตรง (build ที่ตรวจผ่านใช้ Zig กับ native MSVC target และ SDK ใน Developer Shell ไม่ใช่การทดสอบ standalone compiler ทุกตัว)
- GPU/driver, WGL/OpenGL version และ extension
- HWND/runtime ใหม่, renderer integration และ DPI
- ConPTY spawn/I/O/resize/cleanup บนเครื่องนี้
- IME ไทย, clipboard และ visual acceptance จากผู้ใช้
- การเปิด/ปิดซ้ำและ orphan process/handle/thread leak

เฟส 0/1 ผ่านตาม baseline ที่ระบุพร้อม compatibility patch ที่อนุมัติแล้ว 2 ไฟล์ ยังไม่มีการทำ runtime Win32, commit หรือ push ขั้นถัดไปคือเฟส 2 ออกแบบ integration ให้ตรง contracts และ EGL ของ renderer ปัจจุบัน ก่อนสร้างหน้าต่างหรือเลือกเส้นทาง WGL/EGL จริง

## ผลตรวจเอกสารเฟส 2

หลังผู้ใช้อนุมัติเริ่มเฟส2 เวลา 12:31 GMT+7 เพิ่ม `docs/windows-integration.md` และ `docs/reference-notes.md` พร้อมอัปเดต PLAN/provenance โดยไม่แก้sourceเพิ่มจากcompatibility diffเดิม

- อ่านเอกสาร Microsoft/Khronos ที่อ้างใน reference notesจริง HTTP200; endpointเก่า wglMakeCurrentได้404จึงแก้เป็นAPI endpointที่เปิดได้ บันทึกข้อจำกัดไว้
- ตรวจ source paths หลักที่อ้างมีจริง และทวน `.redraw → .render`, `textCallback` paste semantics, `refreshCallback` queue rendering, clipboard enum `started/unavailable/unsupported` กับโค้ดจริง
- อ่าน startup/core surface init/deinit/device lifetime, blocking ReadFile และ CancelIoEx pathก่อนกำหนดownership/gates ไม่สรุปว่าไม่มีcancellation
- เอกสารทั้ง6ไฟล์อ่านเป็นUTF-8แบบstrictได้และcode fencesสมดุล; `git diff --check` ผ่าน
- ไม่มี `reference/noctty` checkout; exact-textตรวจ `noctty`/reference-noctty ใน root build files, `src/build` และ `pkg` ไม่พบ dependencyข้อความดังกล่าว การตรวจนี้มีขอบเขต ไม่ใช่การรับรองทุกdynamic pathของ buildที่ยังไม่implement
- Tracked source diffยังมีเพียง2ไฟล์เดิม 45 insertions/20 deletions ไม่มีruntime/graphics codeใหม่จึงไม่ได้รันbuild/testซ้ำเพื่ออ้างผลimplementationที่ยังไม่มี
- ยังไม่มีindependent review, native GPU/IME/window acceptance หรือการอนุมัติชื่อ/graphics directionจากผู้ใช้ รอการตัดสินใจก่อนเฟส3/4ตามgate

## เฟส3A — localterm-dev native window prototype

ผู้ใช้ยืนยันชื่อ/ทิศทางgraphicsเวลา12:46 GMT+7 จากนั้นเพิ่ม `windows-window` และ `run-windows-window` เป็นtargetเฉพาะWindows ไม่เปลี่ยนdefault build และยังไม่เพิ่ม enum/runtime `win32` หรือCoreSurfaceเชื่อมคอร์ ไม่มีshell/GPU/config loadingในexeนี้

### วิธี build/run บน Windows x64

จาก `D:\works\ghostty-windows` ใน VS2022 Developer PowerShell x64 ตามtoolchainเดิม (Zigportableต้องอยู่ในprocess PATH):

```powershell
zig build windows-window --summary all
.\zig-out\bin\localterm-dev.exe
```

หน้าต่างปกติแสดงชื่อ `localterm-dev — window prototype (no terminal)` เป็นclientareaดำ รับ native resize/minimize/restore/close แต่ยังไม่ใช่terminalหรือที่พิมพ์shellได้ ปิดผ่านปุ่มXตามปกติ

Automated lifecycle check (มีหน้าต่างแสดงแบบไม่activateและปิดเอง):

```powershell
zig build run-windows-window -- --smoke-test
```

smokeทำwarmup1รอบแล้วทดสอบ20รอบ: resizeclient, native minimize/restore, synchronous syntheticWM_DPICHANGEDพร้อมborrowedRECT, postedWM_CLOSE, destroyและdrainWM_QUITในUIloop ไม่เรียกCoreSurfaceหรือspawnprocessใด ตรวจkernel handles/GDI/USER countsหลังwarmupกับหลังรอบสุดท้าย ไม่แทนการตรวจทุกชนิดของmemory/threadleak

### ผลที่ตรวจแล้ว

- Window build exit0, 3/3 stepsสำเร็จ รวมnativeWindows subsystem executable และresource
- Smoke recheck exit0: 20รอบหลังwarmup, handles `96→96`, GDI `2→2`, USER `1→1`
- Unknown argumentและextra argument exit1ตามคาด โดยจบก่อนสร้างหน้าต่าง (`UnknownArgument`, `UnexpectedArgument`)
- VT compile regression (`zig build test-lib-vt-build --summary all`) exit0, 43/43 steps; **ไม่ใช่**การรันVTsuiteใหม่
- Core targeted regression (`zig build -Dapp-runtime=none test -Dtest-filter=ExportedFrame --summary all`) exit0, 76/76 tests; ยังไม่อ้างfullsuiteหลังwindow-only patch
- ตอนตรวจbrandingพบVERSIONINFO/metadataที่ยังไม่สมบูรณ์ แก้resourceให้ใช้numericID1และเติมFileVersion/ProductVersionstringsมาตรฐานแล้วตรวจใหม่ ไม่คัดลอกGhosttyiconหรือเปลี่ยนattribution
- Final artifactหลังแก้ครบ: buildexit0, ProductName `localterm-dev`, OriginalFilename `localterm-dev.exe`, FileVersion `0.0.0.0` อ่านผ่านทั้งWin32APIและ.NET; `mt.exe` extractmanifestID1สำเร็จ ยืนยันPerMonitorV2/asInvokerและไม่มีGhosttybranding
- Final smokeเวลา12:56:59 GMT+7 exit0, handles `96→96`, GDI `2→2`, USER `1→1` หลัง20รอบและwarmupอีก1รอบ หลักฐาน `window-final-smoke.stderr.log`, `window-resource-final-build.stderr.log`, `embedded-final.manifest` กับรายการ`window-final-smoke`ในresults.jsonl(รวมSHA256ของexe)
- `zig fmt --check` ของ build/window sources, `git diff --check`, strictUTF-8/fencesของdocsผ่าน ยังไม่commit/push

Logroot: `C:\Users\nickl\AppData\Local\Letta\build-logs\ghostty-windows\phase3-window` มี `results.jsonl`, stdout/stderrแยกชื่อchecksและfinalbuild/smoke

Smokeครั้งแรกใช้Start-Process+WaitForExitอ่านExitCodeเป็นnullแม้outputครบ จัดเป็นharness failureและไม่ถือว่าผ่าน รันยืนยันด้วยStart-Process **-Wait** -PassThruได้exit0 เก็บรายการnullและlogเดิมไว้ ไม่เปลี่ยนให้ดูผ่าน

ระหว่างแก้metadata: Win32 VerQueryValueWอ่านProductName/OriginalFilenameได้ก่อนแต่.NETยังอ่านค่าว่าง จึงไม่สรุปว่าทั้งresourceหาย หลังเติมversionstringsและใช้resourceID1แล้วmetadatareaderที่ใช้ตรวจผ่านครบ เก็บbuildlogsแต่ละรอบไว้ แยกจากnativewindowlifecycleที่ผ่านก่อนหน้า

### ขอบเขตที่ยังไม่ผ่าน

- เฟส3B: runtime enum/buildselection/App/Surface contractsกับคอร์ยังไม่implement ไม่ใช้window-onlytargetมาอ้างว่าต่อคอร์ครบ และ `-Dapp-runtime=win32` ยังใช้ไม่ได้
- ไม่มีGLcontext, actualGPU/readback, realCoreSurface, PTY, inputencoder, IMEหรือclipboard
- DPI checkเป็นsyntheticmessageเท่านั้น ยังไม่ใช่mixed-DPImonitortransition/visualacceptanceจากผู้ใช้
- NativeAPI failure injectionทุกขั้นและframe/mailboxgenerationtestsยังรอruntimeจริง ไม่อ้างว่าCLInegativecasesแทนทั้งหมดได้
- Windowsx86_64เท่านั้น ยังไม่รับรองARM64/32bit/Windowsรุ่นอื่น; ยังไม่มีinstaller/defaultterminal

## เฟส3B — core App runtime integration

หลังคำสั่งให้ทำต่อเนื่องเวลา13:19 ทำงานต่อในเซสชันนี้ ยกเลิกWakeเดิมที่ไม่มีlistenerและไม่ใช้เป็นคำรับรองว่างานกำลังรัน

- เพิ่ม `.win32` enum/runtime selection และ `src/apprt/win32.zig`, `App.zig`, `Surface.zig` เป็นtypedcontracts
- ผ่านexisting `main_ghostty` → globalinit → `CoreApp.create` → nativeApp init/run/terminate → coreApp destroy จริง ไม่ใช่เปลี่ยนธงให้เรียก3Astandaloneentrypoint
- nativeAppใช้งานcoremailbox/tickและWindowswakeผ่านUIthread พร้อมmutexสำหรับhandle/generationและdropstalegeneration; ยังไม่มีregisteredCoreSurface
- typedSurfaceมีownership/deinitของoptionalCoreSurfaceจริง แต่ยังไม่เปิดcreationpath ไม่มีdummyCoreSurface/PTY; optionalfeaturesยังunsupportedและคืนfalse/errorตามจริง ไม่ถือว่าterminalfeaturesผ่าน
- แยกWindows WGLcontext lifecycleจากEGLเพื่อให้ลิงก์coredestructorได้โดยไม่รับEGLprovider; WindowsDeviceเก็บownerthread ส่วนcontextมีhiddenhost/DC/temporarybootstrapของตนเอง และGLADreloadตามthread บนnon-WindowsคงEGLpathเดิม
- nativeexecutableเลือกresource/ชื่อlocalterm-dev และGUI subsystem; เมื่อlinkMSVCCRTต้องใช้mainCRTStartupให้เรียกZig-exported mainผ่านCRTinit ไม่ใช่ข้ามCRTด้วยcustomrawentry

### ผลจริง ณ13:31

| Check | ผล |
|---|---|
| `zig build -Dapp-runtime=win32 -Demit-exe=true -Demit-docs=false --summary all` รอบแรก | ลิงก์ล้ม `undefined symbol WinMain`; เก็บruntime-build-01logไว้ |
| คำสั่งเดียวกันหลังแก้CRTentry รอบ2 | exit0, 123/123stepsสำเร็จ |
| runtime smokeผ่าน `LOCALTERM_WINDOW_SMOKE=1` | exit0, nativewindow21cyclesรวมwarmup; handles107→107,GDI2→2,USER1→1 |
| cross-thread mailbox/wakeup | 210validcoreticks,21new-windowrequestsจากworkerdrainครบ;21stalegenerationwakesถูกละเลยตามexactcount; new-windowactionคืนfalseเพราะterminalcreationยังไม่เปิด |
| terminal/shell/GPUขณะruntime smoke | terminalsurfaces0; ไม่มีCoreSurface.init/PTY/contextcreationในรอบนี้ |

Logroot: `C:\Users\nickl\AppData\Local\Letta\build-logs\ghostty-windows\phase3b-runtime` มีresults.jsonlและruntime-build-01/02,runtime-smoke-01แยกstdout/stderr+SHA256

`LOCALTERM_WINDOW_SMOKE`เป็นtestenvironmentoptionเฉพาะแอป ตั้งค่า1ชั่วคราวเพื่อให้เปิด/ปิดเองและทดสอบworkerqueue ไม่ใช่CLIflagของGhostty และต้องrestore/removeหลังทดสอบ; หากไม่ตั้งค่าexeเปิดหน้าต่างปกติ ไม่อ่านconfigGhosttyของผู้ใช้ในnativeApp runนี้ (global/coreinitializationยังทำตามupstream)

### Graphics gate ที่กำลังตรวจต่อ

เพิ่ม `windows-gl-probe`/`run-windows-gl-probe` กับ `src/win32_gl_probe.zig`: standaloneWGL4.3core→FBO2×2สีสี่มุม→RGBAreadback→release→workerbind/draw/release→ownerbind/draw/release/destroy ทำ20รอบหลังwarmup ไม่มีterminal/PTY

Probebuildครั้งแรกเกิดtranslate-cWindowsSDK`DECLSPEC_NOINITALL`errorในmodulevariantที่ส่งtarget/optimizeเพิ่ม ขณะcoreใช้opengldependency `.{} ` ได้ จึงแก้probeให้reuseconfigurationเดียวกับSharedDepsก่อน ไม่แก้SDK/ปิดdiagnostics และยังไม่สรุปrootcauseเกินการเปรียบเทียบนี้ รอผลprobeก่อนอ้างGLcapability

Full-core/VT regressionหลังcontext/runtimepatchชุดนี้ยังรอรันแยกจากGPUgateตามลำดับไม่ซ้อนfullcoreกับVTsuite

### ผลgraphics gate / GLAD fix เวลา13:39

- Probeหลังreuseupstreammoduleoptions buildผ่าน28/28steps แต่nativeครั้งแรกcrashที่`gladLoaderUnloadGLContext`→FreeLibraryเมื่อUIreloadหลังworkerjoin ไม่อ้างรอบcrashว่าผ่าน
- ตรวจgeneratedCพบcustomresolver loaderไม่เขียน`glad_loader_handle` ขณะที่Zigwrapperตั้งTLScontextและresetหลังunloadเป็นundefined จึงใช้garbagehandleในcleanupรอบถัดไป แก้`pkg/opengl/glad.zig`ให้contextเริ่ม/จบzeroและcleanupเมื่อloadล้ม ไม่แก้generatedvendorC
- Nativeprobeหลังfix exit0: ATI Technologies Inc./AMD Radeon RX7600, GL`4.3.0 Core Profile Context 26.6.4.260624`; FBO2×2สีสี่มุมRGBAตรงexpected, UI→worker→UIhandoffครบ20cyclesหลังwarmup; handles223→223,GDI1→1,USER3→3
- `zig build -Dapp-runtime=none test -Dtest-filter=GLAD --summary all` exit0,76/76tests รวมemptyresolver/reload/unloadกรณีไม่มีGPU
- Nativeprobeยังไม่ใช่การวาดglyphจากGenericRenderer, latency/performance1920×1080, DPIจริง หรือLinuxregression ไม่ประกาศgraphicsทั้งหมดพร้อมจากFBO2×2นี้

### Full-coreผลหลัง3B/context/GLADpatch

`zig build -Dapp-runtime=none test --summary all` exit0เวลา13:53:44 GMT+7:89/89steps, **3918 passed/61 skipped (3979total)** ใช้เวลารันtest10m หลังcompileประมาณ3m ไม่เพิ่มtimeout/ตัดtests โดยจำนวนผ่านเพิ่ม1จากGLADregressiontest

VTsuite/libเริ่มหลังfullcoreจบจากscriptเดียวกัน ผลแยกในregression-results.jsonl ขณะนั้นยังรันอยู่ ไม่ใช้ผลVTbaselineมาอ้างหลังpatchใหม่

### งานต่อ4A/4Bที่ยังไม่รับรอง

ระหว่างVTกำลังรัน เพิ่มsourceของopaqueCPU DIBpresenter,CoreSurfaceownership/resize/DPI/frameconsumptionและcontrolledterminalpathแบบexplicitenvironmentopt-inเท่านั้น ยังไม่build/runrealterminalpathและยังไม่อ้างผ่าน เส้นทางdefaultยังwindow/coreAppโดยไม่สร้างterminalsurface

`presenter.zig`แปลงGLreadbackbottom-upRGBAเป็นtop-downBGRAตรงBITMAPINFOnegativeheight (Target.readPixelsAllocยังไม่flip),checkedlength/dimensionsและownedUIbuffer มีpuretestsสำหรับswizzle/rows/invalidinput/OOM/BMPheaderรอรัน ไม่ทำGLในWM_PAINT

Nativecontrolledtestที่เตรียมไว้ต้องใช้shellของtestเองNoProfile,ตรวจVTmarker/ไทย/redpixels+BMPframeเฉพาะแอป และclose/join/deinitสำเร็จ ไม่ถือว่าจำนวนframesอย่างเดียวแทนtext/cleanupgateได้ ต้องมีdeadlineและยุติเฉพาะownedtestPIDsหากshutdownไม่ผ่าน

### ผลครบ VT/library เวลา14:19

- VT `zig build test-lib-vt -j1 --summary all`: exit0,45/45steps, **6722passed/64skipped(6786total)** ประกอบด้วย3126pass/32skipและ3596pass/32skip ใช้เวลารัน11mและ9mตามลำดับ ไม่เพิ่มtimeout/ไม่ตัดtests
- `zig build -Demit-lib-vt -j1 --summary all`: exit0,48/48steps ไม่ดึงopenglprobedepsในlib-vt-onlymode

### ผล real CoreSurface/output/teardown เวลา14:31

รอบruntime-build-03ผ่านtypecheckingแต่ลิงก์ล้มclose/writeในExec.quit-pipe: ตรงนี้เป็นWindowsHANDLEไม่ใช่CRTfd จึงไม่aliasไป`_close`/`_write` แก้เฉพาะpipeownershipในExecให้CloseHandle/WriteFileบนWindowsและคงPOSIXbranchเดิม เพิ่มWriteFiledeclarationในWindowsbridge

WindowsReadFileEOF (`BROKEN_PIPE`/`PIPE_NOT_CONNECTED`/`NO_DATA`หรือread0) ไม่ใช่unreachable; cancellationยังตรวจquitpipeก่อนออก errorอื่นlogและออกreader ไม่panicทั้งแอป ไม่มีการเพิ่มtimeoutเพื่อข้ามhang

| Gate | ผลจริง |
|---|---|
| targeted`Windows reader`หลังpipe/EOFpatch | exit0,77/77 รวมnativequit-piperoundtrip+EOF |
| runtime-build-04 | exit0,123/123steps |
| `tools/windows/runtime-smoke.ps1 -Mode window` | passed:true,exit0,210ticks/21mailboxrequests,20cycles+warmup; handles125→125,GDI2→2,USER1→1 |
| helperเดียวกัน`-Mode terminal` | passed:true,exit0,deadlineไม่เกิด,ไม่มีcriticalstderr/childprocessเหลือ;17frames/17paints,remaining_surfaces0 |
| terminaloutput | VTplainStringพบLOCALTERM_RENDER_SMOKEและไทย;115redpixels;renderer/IOthreadsออกและreaderรับquitจริง |
| frameartifact | terminal-frame.bmpSHA256`160FA13B630CE3F717F1782FC663E580FB0CD8ED96EE581DA340B9EE1B0FBB0E`;1034×661;แปลงเป็นPNGและagentเปิดดูแล้วmarker/RED/ไทยอ่านได้ไม่กลับหัว |

ExecutableSHA256ของรอบนี้`C210A394BD34B691A3239D3E0AD1537EAF614B1F37016661FE21D18F5B9BA479` เป็นหลักฐานเฉพาะartifactขณะนั้น ไม่ใช่sourceที่กำลังแก้keyboardต่อ Resultreceiptเก็บSHA256แยกต่อรอบ

Harnessมีmodewindow/terminalและกำลังเพิ่มinput:ตั้ง/restoretestenvเฉพาะprocess เปิดtestwindowแบบไม่activate มีdeadline60s ตรวจlog/receipt/frameใหม่ไม่ใช้ภาพเก่า และตรวจลูกด้วยparentPID+creationidentity เก็บroothandleกันPIDreuse ไม่มีkillตามprocessnameหรือglobalkeyboardinjection หากต้องcleanupถือว่ารอบนั้นfailedแม้ภายหลังexit0

นี่เป็นoutput/closegateของcontrolledsessionหนึ่งรอบ ยังไม่ใช่20รอบของrealCoreSurface,childexitธรรมชาติ,heavyoutputshutdown,recovery,clipboard,IME,WSLหรือperformance1080p60fps Full-core3918passข้างบนเกิดก่อนpipe/EOFpatchชุด4B;หลังpatchนี้มีtargeted77passกับnativeE2E ต้องรันfull-coreอีกครั้งก่อนอ้างbaselineล่าสุดครบ

### Input/IMM/clipboard และ full-core หลัง4B (14:47–15:23)

- **passed:** full-core `zig build -Dapp-runtime=none test --summary all`, exit0,89/89 steps, **3920 passed /61 skipped (3981 total)** จบ15:02 หลัง pipe/EOF patch; ผลนี้เกิดก่อน process-handle lifecycle patch ถัดไป จึงไม่ใช้รับรอง patch ล่าสุดแทนการทดสอบใหม่
- **passed:** runtime-build-08/09/12,123/123 steps; controlled input เข้า KeyEvent/encoder จริง ไม่ผ่าน paste API: ASCII + `สวัสดี` (รวม combining vowels) + emoji surrogate pair + Enter ไปกลับ PowerShell ครบ ล่าสุด input-native-20261016-152145-966,exit0,18frames/17paints,ไม่มี timeout/orphan/critical log
- รอบวิเคราะห์ก่อนแก้ fixture พบ viewport echo `aไทย😀` แต่ `Console.ReadLine()` คืน `aไทย??` จึงตั้ง `[Console]::InputEncoding/OutputEncoding` และ PowerShell `$global:OutputEncoding` เป็น UTF-8 ภายใน ConPTY session ของแอปเท่านั้น ไม่เปลี่ยน locale/registry/profile หรือ console ของผู้ใช้ที่อื่น โหมด interactive ใช้ NoProfile/NoExit พร้อม initializer เดียวกัน
- Agent เปิดดู PNG จาก input gate ที่ผ่านและตรวจ SHA256 ตรง receipt แล้ว เห็นสระบน/emoji สีและภาพไม่กลับหัว **ไม่ใช่ human acceptance ของ typography หรือ IME**
- **passed (unit only):** `zig build test-windows-ime --summary all`,2/2 tests ตรวจ logical→physical client rectangle และ bounds; native replay ผ่านทั้ง WM_IME_CHAR ของไทยและ WM_CHAR/surrogate แต่ไม่ใช่การพิมพ์ผ่าน IME จริง
- IMM adapter แสดง preedit ผ่าน core, clear เมื่อ commit/cancel/focus/layout change, ส่ง candidate/composition geometry และไม่ส่ง GCS_RESULTSTR เองซ้ำกับ default IMM committed-character route ต้องตรวจ candidate/preedit/cancel กับ IME จริงโดยผู้ใช้ก่อนปิด4C
- **passed (pure unit only):** `zig build test-windows-clipboard --summary all`,5/5 tests ครอบคลุม UTF-16/Thai/supplementary, NUL/invalid surrogate, native length bounds, CR/LF policy และ allocation failure ไม่มีการอ่านหรือเปลี่ยน system clipboard ใน tests; ทุก native smoke ปิด OS clipboard support ไว้
- Clipboard implementation จำกัด standard/CF_UNICODETEXT,16MiB native block; unsupported selection/primary/binary Kitty transactions ไม่อ้างรองรับ ค่าเริ่มต้น app clipboard-read/write=ask; Ctrl+V/Ctrl+Shift+V ผ่าน core paste, Ctrl+Shift+C ผ่าน core copy, Ctrl+C ยังคง encoder ไปยัง shell
- Multiline paste ขออนุญาตแม้ shell เปิด bracketed paste; core ยังเป็นผู้ encode/bracket ตาม mode จริง Dialog default No และไม่แสดงเนื้อหา clipboard ใน log; app-initiated read ขออนุญาตก่อนอ่านข้อมูลจริง Busy/invalid data ไม่ปิด terminal และไม่มี automated native clipboard acceptance แฝง

### Real-surface lifecycle — พบ handle growth ยังไม่ผ่าน

`tools/windows/runtime-smoke.ps1 -Mode lifecycle` ใช้21 sessionsใน process เดียว (warmup1+ทดสอบ20), auto-close3sหลัง ready ต่อ session, deadline120sที่ตั้งไว้สำหรับ target ใหม่นี้ก่อนเริ่มทดสอบ ตรวจ marker/frame ทุก session และ handle/GDI/USER/thread count หลังปิด

รอบ `lifecycle-native-20261016-152156-421` **failed**,exit1,ไม่ timeout,ไม่เหลือ owned descendants: handles235→276 เพิ่มต่อเนื่องประมาณ2/session, GDI3→3,USER3→3,threads6→7 จึง **ไม่ผ่าน4D** แม้ worker shutdown/frames ทำงาน ไม่เพิ่ม threshold/warmup/timeout เพื่อเปลี่ยนผลเป็นผ่าน

อ่าน source พบ `CreateProcessW` คืน owned primary-thread/process handles แต่เดิมไม่มี CloseHandle; pinned libxev IOCP watcher DuplicateHandle และปิด duplicate/job ของตนเอง ไม่ได้เป็น owner ของ originals แก้ Windows Command/Exec ownership และกำลัง recheck target/lifecycle คง gate เดิม Thread growth ยังไม่สรุปว่าเป็น cache หรือ leak จนมีหลักฐานหลังแก้

ยังไม่ทดสอบครบ: shell exitเอง, closeขณะ output burst, startup failure, modifier/deadkey ทุกชุด, native IME/clipboard จริง, Unicode cwd/physical mixed-DPI, performance1080p60fps และ Linux runner ไม่มีผลเหล่านี้จาก byte-roundtrip หรือ window-only20cycles

### 4D เพิ่มเติม — negative startup / natural exit / output-burst shutdown

- `runtime-build-17`123/123ผ่าน; bad-shell-native-20261016-155245-315 **passed expected exit1**: preflight FileNotFound ก่อนสร้างCoreSurface/renderer/IO ไม่ fallback shell ไม่เหลือownedprocess อนุญาตเฉพาะerrorบรรทัดFileNotFoundในnegativefixtureนี้เท่านั้น ไม่ปิดcritical-log checksของmodeอื่น ไม่ใช่การรับรองทุกCreateProcess failureหรือauto-recovery
- exit-native-20261016-155247-625 **passed exit0**,child-exited status0/runtime1202ms ถูกส่งถึงCoreSurfaceจริงและสั่งปิดตามnormal policy ไม่ใช้timerมาปลอมเป็นexit;3frames/2paints,115redpixels,remaining_surfaces0
- burst-native-20261016-155249-285 **failed timeout60s** หลังเริ่มIOshutdown; เปลี่ยนWindowscoredeinitให้หยุดIOก่อนrendererแล้วรอบ...155753-788ยังtimeout จึงยังไม่ถือว่าการสลับลำดับอย่างเดียวแก้ปัญหา ไม่มีการเพิ่มdeadlineหรือdetachworkerกลบ
- ReaderWindowsเดิมตรวจquitpipeเฉพาะหลังReadFileถูกcancel หนึ่งครั้งของCancelIoExอาจมาถึงระหว่างparse(ไม่มีpendingread)แล้วreadครั้งถัดไปค้าง เพิ่มstickyquitcheckทุกiteration และใช้CancelSynchronousIoบนownedreaderthreadพร้อมretryขณะwait/join; process/threadhandlesยังreleaseตามowner ไม่ปิดborrowedFDจากruntime
- **passedหลังแก้:** runtime-build-21,123/123; burst-native-20261016-161146-977 exit0,17frames/17paints,1955redpixels; logยืนยันchild stopped→reader quit/completed→IO exited→renderer exited;ไม่มีtimeout/critical/orphan และใช้deadline60sเดิม
- **passed regression artifactเดียวกัน:** exit-native-20261016-161201-159 (3frames/2paints) และ input-native-20261016-161202-815 (18frames/17paints,`aaสวัสดี😀`ยืนยันWM_CHARrepeat2) เก็บhash/receiptแยกในresults.jsonl
- เพิ่มunitแบบdelayed read30msเพื่อครอบคลุมcancel/joinข้ามช่วงที่ยังไม่มีpendingIO และตรวจOPERATION_ABORTED: `windows-reader-cancel-race-unit` **passed78/78**,89/89steps ส่วนnative window/C bridge typecheckผ่าน3/3และruntime-build-22ผ่าน123/123

ผลข้างบนไม่ปิดstrictlifecycle/driver-handle attributionในWIN-RUNTIME-004,ไม่ใช่nativeIME/clipboard acceptance,ไม่ได้ทดสอบOSC/clipboard-message floodทุกชนิดหรือgrandchild/detached-process policy และไม่ใช่performancebenchmark 60fps การรันno-activateและจำนวนdirty framesไม่ใช้แทนmeasurementนั้น

Own-process PSS metadata รอบ `lifecycle-native-20261016-162122-566`: baseline retained thread handlesคือmain`0x2cc→26296`และสองAMDOpenGL`0x388→24316`,`0x3a8→34972`; finalเพิ่ม`0x488→21244`ซึ่งstartใน`amdihk64.dll`และ`0x658→12856`ซึ่งstartใน`ntdll.dll` ยืนยันhandleที่อ้างถึงAMDhookได้แล้ว แต่threadhandlesเพิ่ม2ขณะที่totalเพิ่ม1 จึงไม่เหมารวมnetdeltaทั้งหมดเป็นAMDhandleเดียว Strictgateยังfailed/ไม่timeout/ไม่เหลือowneddescendants ต้องเก็บobject-level attributionหรือข้อตกลงknownprocess-globalstateก่อนเปลี่ยนสถานะ ไม่ปิดhandleของdriverหรือเปลี่ยนsettingเครื่อง

### Regression ล่าสุดหลัง shutdown patch — 16:39 GMT+7

Native artifact SHA256 `54BD5584E0D85FCCE24ADEB1242C54E96411298D2EC8FFF7CCF7A7621D59E97A` (runtime-build-22) ทวนซ้ำแล้วผ่าน: burst สองรอบ16:25:45/16:25:56, natural exit16:26:06, input+repeat16:26:08, negative missing-shell16:26:18 (expected exit1) และ window-only21cycles16:26:19 ทุก receipt `passed:true` ไม่มี timeout/critical log/owned orphan ไม่ใช่ผลของ executable เก่าหรือ screenshot เก่า

`full-core-post-shutdown`: `zig build -Dapp-runtime=none test --summary all`, เริ่ม16:26:33 จบ16:39:02,exit0, **89/89 steps,3922/3983 tests passed,61 skipped** รวม Command handle ownership และ delayed-read cancellation regression ใหม่แล้ว

`vt-post-shutdown`: `zig build test-lib-vt -j1 --summary all` รันต่อใน job เดียวกัน ไม่ซ้อน full-core; จบ17:01,exit0, **45/45 steps,6722/6786 tests passed,64 skipped** (3126+3596 passed,32+32 skipped) ตรง baseline เดิม ไม่ใช้ core/VT มาแทน native lifecycle/performance/human acceptance และยังเก็บ runner timeout รอบเก่าใน WIN-TEST-003 ไม่ลบประวัติ failed run

### 1080p component cost — 17:05 GMT+7

`zig build windows-frame-bench -Doptimize=ReleaseSafe --summary all` ผ่าน28/28steps; `frame-bench-1080p` exit0 ไม่timeout บน AMD Radeon RX7600,OpenGL4.3 Core26.6.4.260624;30warmup+240samples ขนาด1920×1080RGBA8 มีpixelcheckหลังGDIflushไม่ใช่จับเวลาemptyloop:

| ช่วง | mean ms | p50 ms | p95 ms | max ms |
| --- | ---: | ---: | ---: | ---: |
| clear+readback+glFinish | 1.350 | 1.304 | 1.605 | 2.159 |
| allocation+RGBA→BGRA+vertical flip | 2.898 | 2.791 | 3.435 | 5.181 |
| memory-DC StretchDIBits+GdiFlush | 0.373 | 0.345 | 0.594 | 1.100 |
| รวมและ image free | 5.175 | 5.047 | 6.508 | 8.745 |

ใช้page allocator,preallocated RGBAreadback buffer,offscreenFBOและmemoryDC ไม่รวมproductionfontshaping/terminalupdate/actualwindowpaint/compositor/inputlatency ไม่ใช้ค่านี้อ้างwhole-app60FPSหรือรับรองCPU/working-setbudget กำลังเพิ่มcontrolledchanging-outputบนclient1920×1080และsamplingเฉพาะnativeparent โดยไม่อ่านclipboard/ผู้ใช้,ไม่activatewindow,ไม่เพิ่มidleredraw ชุดรัน/ผลกับartifactใหม่จะเก็บแยก ไม่ใช้DebugartifactเดิมแทนReleaseSafe

ขั้นตอน human-owned acceptance แยกไว้ใน [windows-preview.md](windows-preview.md) ยังไม่ถือว่าผู้ใช้ได้ทำหรืออนุมัติข้อใดจากการเขียนคู่มือนี้

Host profile รอบแรก `runtime-build-23-releasesafe` บิลด์ผ่าน123/123 แต่ `profile-native-20261016-171221-348` **failed** ก่อนเริ่มCoreSurface เพราะclientไม่ตรง1920×1080 ไม่ได้เอาขนาดเล็กกว่ามาแทน Leaf `--profile-size-probe` (ไม่มีGPU/PTY) พบclient1920×1061,outer1936×1100,DPI96 จึงเพิ่ม WM_GETMINMAXINFO override เฉพาะcontrolledprofileให้captionedclient1080pเกินmonitortracklimitได้ โดยไม่แก้normal-windowหรือsettingเครื่อง ต้องให้leafและfullruntimeพิสูจน์sizeซ้ำก่อนใช้ผลprofile; actualwindowpaintยังขึ้นกับvisibility/clippingของจอ ไม่ใช้เป็นforeground/compositorbenchmark

### ReleaseSafe exact-client host profile และ regression — 17:20 GMT+7

Leaf retryผ่านclient1920×1080จริงแล้ว และ `runtime-build-24-releasesafe`ผ่าน123/123 Artifact SHA256 `58200489A7FBB850172DCC63DA1E2569B279C930D4DC2419124E9D091EBE7D7D` ทวนprofile/burst/naturalexit/input+repeat/missing-shell/windowผ่านทั้งหมด ชื่อreceiptเริ่ม17:19:58/17:20:16/17:20:27/17:20:28/17:20:38/17:20:39 ตามลำดับ

Profileเพิ่มตัวเลขcounterต่อแถวเพื่อไม่ใช้ภาพpatternซ้ำมารับรองrendering ใหม่ เป็นNoProfile controlledchild,client1920×1080,no-activate,closeหลัง15s ไม่มีactualclipboard;57resource samplesทุก250msถึง14945.71ms ได้parentCPU3859.375ms (**25.8226%เทียบหนึ่งcore** ไม่หารเป็นmachineutilization),OSpeakworkingsetที่สังเกต213942272bytes(~204.03MiB),sampledworking-setpeak207720448bytes(~198.10MiB) ไม่รวมPowerShell/ConHost/GPU/compositorและไม่รวมช่วงท้ายที่พ้นlastsample ไม่ใช่steady-stateidle/budgetpass

ตัวนับpresent/paint **25/25** จึงยังไม่รับรอง60FPSหรือlatency;ต้องแยกproducer/wake/dirty/coalescing/visibilityและตรวจframeจริงก่อนสรุปคอขวด ไม่เสนอเปลี่ยนrendererจากตัวเลขนี้อย่างเดียว เพิ่มarchiveBMPแยกชื่อreceipt+hashเพื่อไม่ให้ภาพprofileถูกโหมดถัดไปเขียนทับ

ReleaseSafe strictlifecycleรอบ `lifecycle-native-20261016-172106-616` **ยังfailed ResourceGrowth** ไม่timeout/noownedorphans:handles233→234,GDI3→3,USER3→3,threads6→7 เหมือนDebug PSSพบretainedAMDhookthreadhandleและNTDLLworkerhandleเพิ่ม ยังไม่อนุมัติknownexceptionเอง ผลprofile/functionalผ่านไม่ปิดWIN-RUNTIME-004

Profile rerun `profile-native-20261016-172550-841` ผ่านบนSHAเดียวกันและarchiveBMPตามreceiptแล้ว (hashตรวจหลังcopy) CPUobserved32.60%ของหนึ่งcore/peakworking-set213831680bytes แต่ยังpresent25/paint25 จึงเก็บทั้งสองรอบ ไม่เลือกเฉพาะCPUต่ำสุด ภาพที่ตรวจผ่านPNGซึ่งแปลงจากcontrolledBMPแสดงcounterประมาณ242158–242185และANSIred/ไทย แสดงว่าpayloadมีการเปลี่ยนจริง แต่ภาพเดียวไม่บอกframepacing/latencyหรือยืนยันhuman typography

ขั้นวิเคราะห์ต่อ: controlled `profile-paced` ใช้payloadเดียวกันแต่producerพัก16ms เทียบunboundedprofileบนartifactเดียวกัน แยกpressureจากoutputกับwake/dirty/present semantics **ไม่ใช่**เพิ่มrenderer/idle timer ไม่ใช้componentbenchmarkแทนframecounter และยังไม่แก้pinnedlibxev (อ่านIOCPAsync/dispatchจากcachedarchiveเพื่อวิเคราะห์เท่านั้น)

### Shared Async, wake coalescing และ message-pump fairness — 17:53 GMT+7

ก่อนแก้ pacedและburstได้25frames/15sเท่ากัน สาเหตุคือcopyIOCPAsyncก่อนrendererregisterwaiter แก้เป็นborrowedpointerจากstable`self.renderer_thread.wakeup`ผ่านTermio.Options/Termio/StreamHandler ไม่มีownership/deinitใหม่ regression`renderer-wakeup-borrow-unit-02`ผ่าน76/76 โดยทดลองdetachedcopyแล้วcallbackต้องไม่มา ก่อนnotifyborrowedinstanceแล้วcallbackต้องมา ใช้nonblockingdispatchไม่มีtimer หลังแก้pacedเพิ่ม1411presents/951paints แต่burstเกิดWakeFailed/paintstarvation จึงเก็บเป็นfailedในWIN-RUNTIME-005 ไม่อ้างแก้ครบจากunit

Facadeเพิ่มmutex-protectedone-pendingwake,clearก่อนmailboxdrain,coalescerenderrequestsแล้วconsume latestframeหลังdrain และUpdateWindowเฉพาะpendinginvalidregion ไม่มีGLในWM_PAINT Window-onlytestยัง21cycles/21mailboxrequests/stalegenerationignored แต่10notificationsต่อcycleต้องcoalesceเหลือ1dispatch (รวม21แทน210 ไม่เปลี่ยนlifecyclethreshold) รอบ27burstไม่มีwakeerrorและpaint6440ครั้ง แต่profile15sกลับยาว~48s จึง **ไม่รับรองtimerfairness** แม้receiptfunctionalเดิมจะpassed

รอบ28เพิ่มboundedinput/paintและWM_TIMERfilteredPeekMessageหนึ่งturnต่อordinarydispatch;idleยังblockGetMessage ไม่มีtimer/rendererpollingใหม่ และtightenprofileให้จบภายใน25sรวมstartup/teardown ไม่เพิ่ม60swatchdogเดิม ReleaseSafe123/123,artifactSHA256`34FB4AB2E04A348A96C01777CBD700244D63AEAB396EE7B5E7E608F8CDD14E0A`:

| controlled profile | wall seconds | presents/paints | observed parent CPU (%หนึ่งcore) | observed OS peak bytes |
| --- | ---: | ---: | ---: | ---: |
| unbounded17:52:44 | 15.442 | 2107/2107 | 214.33 | 248537088 |
| unbounded17:53:00 | 15.439 | 2085/2085 | 215.55 | 248823808 |
| paced16ms17:53:15 | 15.374 | 1420/1420 | 74.67 | 191012864 |

ทั้งสามpassedและclose_within_25s:true ไม่มีcritical/timeout/ownedorphan เป็นno-activatehostmeasurementไม่ใช่DWM/displayFPSหรือrealkeyboardlatency ไม่หารpresentsด้วย15แล้วรับรอง60Hzdisplay CPUเพิ่มตามจำนวนเฟรมที่เคยหาย จึงยังไม่รับรองenergy/idlebudgetจากข้อมูลนี้ Full-coreหลังเปลี่ยนcommonborrowed-pointerกำลังทวน ไม่ใช้3922passก่อนแก้pointerมารับรองsourceใหม่

อัปเดต18:06: `full-core-post-wakeup` จบexit0, **89/89steps,3923/3984 tests passed,61 skipped** รวมshared-instancecounterfactual regressionใหม่แล้ว Nativeบนartifact28เดียวกันทวนwindow/burst1080pสองรอบ/paced1080p/burstclose/naturalexit/input+repeat/missing-shellผ่านครบ ไม่มีwakeerrorหรือownedorphan คู่ผลVTล่าสุดยัง6722pass/64skipจาก17:01 (ไม่ได้รันVTใหม่หลังpointerpatch; แก้เฉพาะtermio/core/runtime ไม่อ้างเป็นผลVTรอบใหม่) กำลังทวนstrictreal-surfacelifecycleบนartifact28 ไม่ใช้ผลwindow-only125→125มาปิดgateนั้น

อัปเดต18:08: strictlifecycleบนartifact28 `lifecycle-native-20261016-180631-757` จบexit1,**ResourceGrowthยังfailed** ไม่มีtimeout/ownedorphan:233→234handles,6→7threads,GDI3→3,USER3→3 PSSยังพบAMDhookthreadhandle`0x3d8→2484`และNTDLLworker`0x6f8→11224`เพิ่ม ไม่มีหลักฐานใหม่ให้ปิดnetdeltaเป็นAMDhandleเดียว จึงคงWIN-RUNTIME-004และเฟส4เปิดอยู่ ไม่เปลี่ยนwarmup/threshold/driver settings Artifactนี้พร้อมเฉพาะ**controlled human preview**ตามwindows-preview.md ไม่ใช่release/defaultterminal และยังไม่มีผู้ใช้ยืนยันIME/clipboard/physicalDPI

### Thai font comparison — 19:26 GMT+7

ตามhumanreviewว่ารูปไทยผิดสัดส่วน เพิ่มเฉพาะcontrolled`font-angsana`/`font-leelawadee`fixtures ใช้`font-codepoint-map=U+0E00-U+0E7F=Angsana New`เทียบ`Leelawadee UI`,Consolas/ขนาด/cell/ข้อความเหมือนกัน ไม่แก้defaultdiscovery/baselineหรือfontระบบ `font-compare-build-29`123/123ผ่าน ติดตั้งprefixแยก`zig-out/font-compare`ไม่ทับartifact28ที่ให้humanpreview ทั้งสองnativecasesผ่าน/ไม่มีmapped-fontlookupwarning;receipts`font-angsana-native-20261016-192605-572`และ`font-leelawadee-native-20261016-192619-170`มีarchivedBMP+hash

ภาพคู่`%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\phase3b-runtime\thai-font-comparison-20261016.png`ครอป620×170pixelsบนซ้ายจากframebufferแต่ละรูป แล้วขยายnearest-neighbor2เท่าเท่ากันและติดlabelภายนอก ไม่วาดThaiใหม่ด้วยSystem.Drawing ตัวอย่างมีไทย/อังกฤษ/emoji/สระบนล่าง/วรรณยุกต์ซ้อน จากการดูBสัดส่วนและbaselineเข้ากับLatinมากกว่าA แต่การยอมรับvisualเป็นของผู้ใช้ ยังไม่ได้เปลี่ยนdefaultmappingหรืออ้างfull-coreรอบใหม่จากfixture-onlypatchนี้

Human review19:31ยังเห็นBเพี้ยน จึงไม่รับรองterminalThaiจากcomparisonนี้ ตรวจSystemFonts.MessageBoxFont/CaptionFontของเครื่องจริงได้Leelawadee UI9pt ทำreferenceด้วยWindowsGDITextRendererที่12pt(เท่าnominalterminaldefault)และnaturalspacing/25pxrowsเพื่อเทียบ ไม่อ้างเป็นframebufferterminal ภาพ`thai-terminal-vs-windows-reference.png`ผู้ใช้ยืนยัน19:43ว่า **ภาพล่างWindowsreferenceดีสำหรับไทย** นี่เป็นvisualtarget ไม่ใช่การapproveภาพบนหรือปิดIME/clipboardgate

ขั้นdiagnosticต่อ`font-system`:Leelawadee UIเป็นprimaryทั้งterminal ไม่มีThai-codepointoverride เพื่อเทียบกับmappedfallbackและreference ต้องระวังว่าการเปลี่ยนprimaryเปลี่ยนcellmetricsและอาจเปลี่ยนshapingrunด้วย ผลเดียวจึงยังไม่พิสูจน์สาเหตุscalingโดยลำพัง บิลด์แยกfont-compareprefix ไม่แก้defaultfontหรือsettingระบบ

ผล19:53:primarysystemfontรอบ30ยังหนา/ช่องไฟกว้าง พบWindows.DiscoverIterator.matchesกรองเฉพาะfamily/codepointและไม่กรองstyletraits จึงแก้ตรวจFreeTypeBOLD/ITALIC flags;explicitstyleชื่อยังได้รับการเคารพ `windows-font-style-unit`76/76pass(ครอบคลุมConsolas4stylesและLeelawadee UIregular/bold),ReleaseSafe31ผ่าน123/123 และmapped/primarynativecasesผ่านlog/cleanup แต่**ภาพยังไม่ผ่านhumanvisualtarget** ไม่อ้างว่าการแก้styleทำให้ไทยเสร็จแล้ว

ภาพ`thai-style-fixed-vs-windows.png`แสดงmappedterminal/primaryterminal/Windowsreference2xเหมือนกัน Primaryproportionalfontทำfixedcellกว้างมากจึงไม่promote การไล่ต่อใช้unit-onlyselectedstyle/fileprobeเพื่อแยกRegularจากSemilightที่อาจมีstyleflagsเดียวกัน อีกทั้งWindowsreferenceเป็นnaturalspacingและClearType ส่วนterminalเป็นfixedcell+FreeTypecoverage จึงไม่ควรยกproportionalpositionsมาแทนgridแล้วทำcursor/selectionคลาด เป้าหมายคือglyph/marksอ่านถูกต้องโดยคงterminalsemantics Full-core3923passก่อนstylepatchไม่ใช้รับรองstylepatchนี้ ยังต้องทวนเมื่อแก้ลงตัว

### Thai measurements และ full-coreหลังstylefix — 20:22

- `windows-font-style-probe`:ConsolasRegular=`consola.ttf`,Bold=`consolab.ttf`,Italic=`consolai.ttf`,BoldItalic=`consolaz.ttf`;LeelawadeeUIRegular=`LeelawUI.ttf`,Bold=`LeelaUIb.ttf` จึงตัดSemilightออกสำหรับผลหลังแก้ ไม่อ้างว่าregularflagsอย่างเดียวพิสูจน์ชื่อstyleได้
- `windows-thai-metrics`:12pt/96DPIได้16px/emทั้งConsolasและLeelawadeeUI ทั้งThai`.none`และruntime`.ic_width` adjustment ดังนั้น **ไม่พบfallbackshrink** ในกรณีนี้ ไม่แก้sizeadjustโดยเดา PrimaryUIcell15pxขณะที่Consolas9pxจึงอธิบายช่องไฟprimaryUIที่กว้าง
- Thai`กี้`testผ่านทั้งgraphemeเปิด/ปิดและทั้งUI-primaryกับConsolas+Thai ทั้ง3glyphไม่missingและanchorcell0;GPOS offsetsอย่างเดียว(9/10px)ไม่ใช่หลักฐานว่าmarkหลุดcell เพราะbearing-8/-5pxชดเชยอยู่ SharedGridactualinkxได้0/1/5px
- บนConsolasgrid9×19:baseglyphtopbearing13px,vowel17px,tone20px หลังรวมHarfBuzzoffset;offset_yคือระยะจากbottomcellถึง **top**glyph ไม่ใช่bottom จึงห้ามบวกbitmapheightซ้ำเพื่อคำนวณtop วรรณยุกต์มีoverhangเหนือแถว1px แต่ยังไม่พิสูจน์ว่าGPUclipเสมอ เพราะอาจoverdrawแถวก่อนหน้า ต้องดูactualframe
- พบallocationค้าง2รายการใน**test helper**ที่ใช้discoveredface.loadแล้วerrdefermetadatafaceเฉพาะerror แก้เป็นdeferคืนpeek/pathทุกกรณี เพราะloadedfaceเป็นindependentowner รันซ้ำ`windows-thai-regressions-02`และ`windows-thai-real-grids`ผ่าน77/77/noallocationleak ไม่เอาhelperleakไปปะปนกับWIN-RUNTIME-004
- `full-core-post-font-style`:exit0,**89/89steps,3926/3987tests passed,61skipped** ตรวจproductionstylematchingfixและสามtestsใหม่แล้ว ยังไม่ใช่humanvisualacceptanceและไม่ได้รันVTใหม่

ขั้นต่อไปcontrolled`font-roomy`คงConsolas+LeelawadeeUI/12pt/ข้อความเดิม เปลี่ยนเฉพาะ`adjust-cell-height=4`(19→23px)ด้วยmetricmodifierที่มีอยู่ เพื่อเทียบพื้นที่สระ/วรรณยุกต์ ไม่ย้ายGPOSเอง/ไม่เปลี่ยนความกว้างcursorและไม่แก้defaultของterminal การเพิ่มheightทำให้fontcenterแนวตั้งตามmodifiercontract ไม่ใช่manualbaselinepatch

### Image paste + portable image cache — 18ตุลาคม2026

รอบ33ไม่ผ่านcompileเพราะ`clipboard.zig`local`formats`shadowฟังก์ชันชื่อเดียวกัน แก้ชื่อเป็นnative_formats;ไม่อ้างpuretestsเดิมว่าพิสูจน์integrationผ่าน Build34ReleaseSafeผ่าน123/123แต่`window-native-20261018-182349-268`failed ResourceGrowth handles131→174,GDI2→10,USER1→4 ไม่timeoutและยังไม่ระบุสาเหตุ

พบportablemodeต้องsnapshotตอนสร้างsurface ไม่ใช่ตรวจmarkerใหม่ทุกpaste มิฉะนั้นลบportable-data/ถอดdriveอาจสลับไปhostTEMP เพิ่มportable latchและregressionที่markerหายแล้วได้PortableDataMissingโดยไม่มีfallback ตรวจcacheแต่ละระดับแบบno-followและปฏิเสธสิ่งที่ไม่ใช่directory รายละเอียดstorage/limits/ownershipอยู่ `windows-image-paste.md` ยังไม่เป็นportableทั้งแอป

`zig test src/apprt/win32/clipboard_integration.zig` และ`-O ReleaseSafe`ผ่าน**18/18ทั้งคู่**,noallocationleak มีDIB→PNG→portablecache→readbackbyteequality→cleanup,pathไทย/ช่องว่าง,markerหาย/invalid,cacheเป็นไฟล์,quota16ไฟล์และpreserveไฟล์อื่น ไม่มีOSclipboardaccessหรือexternalCLIrequest Previewwrapperเพิ่มoptional-Executableและตรวจparserแล้ว ไม่ได้เปิดinteractivewindowเอง

Build35ReleaseSafeผ่าน**123/123** SHA256`D2B9427A0FB8E565D4F0AA979B289DE2C04A22060E20FD40695E826C96283803` ที่`zig-out/image-paste/bin/localterm-dev.exe` เทียบbaseline28ที่hashตรง`34FB4AB2...`ในenvironmentเดียวกัน:baseline`window-native-20261018-182921-396`และnew`window-native-20261018-182934-407`ผ่าน handles125→125,GDI2→2,USER1→1;new`input-native-20261018-182947-464`ผ่านASCII/Thai/surrogate/WM_CHARrepeatและcleanup20frames/20paints/0surfaces แต่ไม่ใช้ผลrerunลบfailure34หรืออ้างว่ารูปจากclipboardจริง/CLIattachmentผ่าน

`clipboard-vt-20261018`:**45/45steps,324/324tests passed** สำหรับVTclipboardfilter;build35strictlifecycle`lifecycle-native-20261018-183203-215`ยังfailed **handles233→234,threads6→7,GDI3→3,USER3→3** ไม่มีtimeout คงWIN-RUNTIME-004 ไม่ปรับthresholdหรือdriver ผู้ใช้แจ้งว่าtestwindowsบังงาน จึงหยุดรันartifactเก่าที่แสดงบนจออัตโนมัติ รอบต่อไปต้องเป็นoffscreen/noactivateและแยกevidenceจากon-screenacceptance

Build36เพิ่มoffscreenเฉพาะautomatedsmoke: ใช้SM_X/Y/CX/CYVIRTUALSCREENวางxที่ขวาสุดทุกจอ+64px,WS_EX_NOACTIVATE,ShowWindowแบบnoactivateและกั้นWM_WINDOWPOSCHANGING/restore/DPIsuggestedrectไม่ให้พากลับเข้าscreen ไม่ใช้SW_HIDE/ปิดrender/ผ่อนpaintchecks Interactivemanualpreviewไม่มีoffscreenflagจึงยังเห็นตามปกติ แก้nativeKittycompletionerrorให้ไม่โยนerrorกลับไปให้callerทำลายrequestที่coreconsumeแล้วซ้ำ

ReleaseSafe**123/123steps** SHA256`42796AF02CDC26AF59E54726A3795C9F55968BB9D7AA4CA126F495F851772636` Prefix`zig-out/image-paste`;`window-native-20261018-184041-796`ผ่านhandles125→125,GDI2→2,USER1→1 และ`input-native-20261018-184055-088`ผ่าน**22frames/22paints/0surfaces** มีfreshBMPframe/red_pixels389 พร้อมASCII/Thai/surrogate/repeat/Enterroundtrip จริง ทั้งสองlogระบุ**offscreenx1984y0/noactivate** และตรวจGetWindowRectกับforegroundหลังShowWindowแล้ว ผลนี้ยืนยันrender/paint/captureนอกจอบนเครื่องปัจจุบัน ไม่ใช่humanon-screenquality/physicalmixed-DPI และไม่ลบfailureก่อนหน้า

Build36offscreenstrictlifecycle`lifecycle-native-20261018-184129-397`:ครบ21sessions/20หลังwarmup,exit1 ResourceGrowth,**handles233→234,threads6→7,GDI3→3,USER3→3** ไม่มีtimeout/owneddescendantsที่ต้องkillและมีfreshframeSHA`100242789941BDB5E115425B1313B06DC80C433EE01681A68E5A85BC44E7EC55` ผลยังตรงกับon-screenbuild35 จึงยืนยันว่าoffscreenไม่ได้ใช้ปิดrenderหรือซ่อนgateนี้ คงWIN-RUNTIME-004/ยังไม่release-ready ไม่เปลี่ยนdriver/threshold และยังไม่รับรองclipboardจริง/CLIattachmentหรือภาพไทย

### Readiness investigation — 18ตุลาคม2026 18:54เป็นต้นไป

- Userอนุมัติทำต่อจนพร้อมจริง บันทึกscopeในPLAN.md ไม่ประกาศพร้อมจากbuildอย่างเดียว
- Own-process C probe`tools/windows/lifecycle-snapshot-probe.c`ลิงก์diagnostics.cเดิม ไม่สร้างGUI/GPUหรืออ่านclipboard:controlcounts63→63/threads1→1;PSScounts57→57/threads1→1 ภายในแต่ละprocess21รอบ ทั้งคู่exit0 ไม่เทียบabsolute63vs57ข้ามprocess ไม่พบว่าPSSล้วนเพิ่มworker/handle
- Build37ผ่าน123/123 เพิ่มเฉพาะPSSattributioncontrol defaultเปิดเหมือนเดิม `-PssDiagnostics disabled`ใช้เฉพาะlifecycleและreceiptระบุ`readiness_evidence=false` ไม่แก้passedpredicate/resourcecounter/warmup/deadline;defaultgate`lifecycle-native-20261018-190111-644`และcontrol`lifecycle-pss-control-native-20261018-190219-502`ยังfailedเหมือนกัน233→234handles/6→7threads/GDI3/USER3 จึงตัดPSSเป็นสาเหตุเดียวออก ยังไม่ปิดWIN-RUNTIME-004
- Privateclipboardharness`src/win32_clipboard_probe.zig`+`tools/windows/private-clipboard-fixture.c`คอมไพล์ผ่าน แต่runtime`CreateWindowStationW`failed**AccessDenied5** ทั้งALL_ACCESSและleastrequiredrights ไม่มีwindow/clipboardAPIหลังfailure ไม่มีfallbackไปWinSta0 ไม่แก้ACL/ขอadmin ถือว่า**nativeclipboardvalidationblocked** ไม่ใช่ผ่าน18synthetictestsแล้วแทนได้
- ขั้นต่อไปnumericown-handleinventoryเปรียบเทียบkind/targetId/accessก่อนหลัง ไม่captureobjectnames/VM/stackหรือcloseborrowedhandles และตรวจcodeownershipควบคู่ไป ไม่รัน21cyclesซ้ำโดยไม่มีคำถามใหม่

Build38ผ่าน123/123;`lifecycle-native-20261018-191159-014`ยังfailed233→234/6→7 แต่PSSnumericinventoryได้233→234recordsพอดี:ลบunknown0x28c/0x2d8(access0x1f0001)สองตัว เพิ่มEvent0x684และThread0x480→31056(`amdihk64.dll`),Thread0x68c→31284(`ntdll.dll`) จึงแยกnet+1เป็น**+2threads+1event−2unknown**ได้ แต่ยังไม่ทราบชนิดunknownหรือcreatorของevent ไม่เหมารวมทุกnetdeltaเป็นdriverthreadตัวเดียว เพิ่มpublicObjectTypeInformation(class2)เพื่อระบุชนิดเท่านั้น ไม่queryObjectNameInformation/path/VM

Read-onlyownershipreviewไม่พบnormal-successleakโดยตรงในUI→IOjoin→rendererjoin→WGL/DC/HWNDteardown;พบlibxevprocesswatcherinitหลังDuplicateHandleไม่มีerrdeferหากCreateJobObject/AssignProcessToJobObjectล้มเหลว เป็นerror-pathdefectแยก ไม่อ้างว่าคือcurrentnormal+1 และไม่patchdependencycacheเงียบ ๆ

PacedWGL-onlycontrol`paced-wgl-20261018`:build28/28,21contexts/onewarmup,hold3000msต่อcontext,hiddenHWND/UI-worker-UIhandoff/RGBAreadback ไม่มีCoreSurface/ConPTY/parentwindowหรือPSS **failedGraphicsResourceGrowth229→230handles,GDI1→1,USER3→3**,noTimeout ผลนี้reproduce+1ได้ในGPU-onlypath จึงหักล้างการใช้fastWGL223→223เดิมตัดdelayedGPU/driverstateออก ไม่ปิดgate/เปลี่ยนwarmup/threshold/driver ผลcontrolไม่ใช่readinessevidence

Build39ผ่าน123/123;typedowninventory`lifecycle-native-20261018-191850-712`คง233→234/6→7;ObjectTypeInformation(class2เท่านั้น)ระบุสองตัวที่หายเป็น**ALPC Port**(0x2c4/0x2cc,access0x1f0001) ไม่ใช่timer/ownedfile;เพิ่มThread0x470→28868,Thread0x59c→27920และEvent0x654 จึงได้**+2Thread+1Event−2ALPCPort=+1**ครบตัวเลข แต่ยังไม่รู้creatorของEvent/ALPC จึงไม่claimnetdeltaเป็นdriverหนึ่งhandleโดยลำพัง ขั้นต่อไปทำtypedinventoryในpacedGPU-onlycontrolเพื่อตรวจว่ารูปแบบเดียวกันโดยไม่มีCore/ConPTYหรือไม่

Thai follow-upพบFreeTypeconfigdefault`light=true,autohint=true`เป็นdefaultที่เหมาะLinux/Fontconfig ขณะที่targetreferenceเป็นWindowsnative ทดลองเฉพาะfixtures`font-native`/`font-native-roomy`ใช้`no-light,no-autohint`(nativeTTnormal target)เทียบConsolas+LeelawadeeUI/12ptและ19/23pxrowsที่มีอยู่ ไม่เปลี่ยนdefaultหรือเอาproportionaltextpositionsแทนterminalgridก่อนดูผลจริง ไม่ใช้การเพิ่มrowheightเพียงอย่างเดียวอ้างแก้shape/AAสำเร็จ

TypedpacedGPU-only40ได้223→224recordsและ**รูปแบบเดียวกับterminalครบ**:ลบALPCPort0x2b8/0x2c0 เพิ่มEvent0x350,Thread0x3c0→30916(`amdihk64.dll`),Thread0x3cc→3356(`ntdll.dll`) โดยไม่มีCore/ConPTY ยืนยันGPU-onlyreproductionของnetobjectpattern ไม่ใช่แค่threadcountเท่ากัน ยังไม่ทราบcreatorของEvent/ALPC ไม่ปิดstrictgateเองหรือcloseborrowedhandles

Nativefontbuild40ผ่าน123/123/fourfixturesallpass;ภาพจากfreshframes`thai-hinting-4way-20261018.png`ใช้nearest2xไม่แต่งglyph ผลnativeTTเปลี่ยนshape/AAจริง ไม่ใช่แค่ย้ายbaseline HarfBuzzregressionแรกcompilefailedจากtesthelperขาด`comptime` ไม่เปลี่ยนproductionเพื่อกลบ;แก้แล้ว`native-tt-harfbuzz-02`**89/89steps,94/101testsผ่าน,7skip**(Debugตามroottesttarget) รวมUI-primary/Consolas+UI ×light/nativeTT ×graphemeเปิด/ปิด ทุกglyphไม่missing/anchorcell0/Consolaswidth9px

NativeTTtoneยังมีinktop21pxบนgrid19px(เดิมlight20px) และhorizontalovershoot1pxในstackedmark จึงไม่อ้างnativeflagsเพียงอย่างเดียวแก้verticaloverhang CandidatepreviewเลือกUIThai/nativeTTพร้อม+4rowheightเป็น23pxตามfixtureที่เห็นจริง ต้องตรวจmetricsmodifiers/actualframeต่อ และhumanvisualacceptanceยังไม่ผ่าน ไม่เปลี่ยนGPOS/cursorwidthเพื่อบังคับภาพให้เหมือนproportionalWindowsreference

กำลังเพิ่ม`image_paste_fixture.zig`/`image-paste-smoke.ps1`:syntheticDIB→productionstaging/corepaste→PTY→PowerShelltokenizer(หนึ่งStringLiteral,ไม่execute)→independentGDI+PNGdimensions/pixels ทดสอบnormalTEMPที่มีspace/quote/Thaiกับportableexpectedrootและempty-onlycleanup ไม่ใช่OSclipboardread/permission/AI-CLIattachmentacceptance มีguardfixture-onlyและไม่มีmodalในautomatedfailure ไม่แตะWinSta0 clipboard
