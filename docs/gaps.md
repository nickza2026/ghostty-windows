# ช่องว่างและตัวบล็อก Windows

วันที่เริ่มบันทึก: 16 ตุลาคม 2026<br>
Baseline: `b3dc3d794513c11633e7c3347935693957744e83`<br>
ผลจาก Letta Code โดยยังไม่แก้ implementation

## WIN-BUILD-001 — Full-core ดึง POSIX headers บน MSVC

- สถานะ: resolved สำหรับ Windows full-core build/test หลัง patch — full-core exit 0 เวลา 11:59:52 GMT+7; baseline เดิม exit 1 ยังเก็บเป็นหลักฐาน ผู้ใช้อนุมัติ patch เวลา 11:41 GMT+7; VT regression runner issue ติดตามแยก WIN-TEST-003
- ผลกระทบ: ไม่สามารถใช้ผล VT ที่ผ่านแทนการรับรอง full application core หรือผ่านเกณฑ์เริ่ม runtime Win32 ได้
- เครื่องมือ: Windows x64, Zig `0.16.0`, VS Community 2022, MSVC `14.44.35207`, SDK `10.0.26100.0`
- Working directory: `D:\works\ghostty-windows`

### วิธีทำซ้ำ

ใน Developer PowerShell x64 ที่เพิ่ม Zig portable เข้า PATH เฉพาะ process:

```powershell
zig build -Dapp-runtime=none test --summary all
```

### Expected / actual

- Expected: build graph สำหรับ native Windows ไม่บังคับ translate headers ของ POSIX ที่ Windows SDK ไม่มี
- Actual: `compile test ghostty-test Debug native-native-msvc` → `translate-c posix_c.h` ล้มด้วย `fatal error: 'pwd.h' not found`
- ต้นทางที่ยืนยัน: `src/build/SharedDeps.zig:219–229` เพิ่ม import `posix_c` รวม `errno.h`, `pwd.h`, `signal.h`, `sys/types.h`, `unistd.h` สำหรับ target ที่กำลัง build
- Generated header ใน cache ยืนยันว่ารวม `pwd.h` จริง ไม่ใช่การเดาว่า SDK ขาดการติดตั้ง
- Log แสดง warning จาก `translate-c hb_c.h` ว่าไม่รู้จัก `-fno-sanitize=undefined` และ `-fno-sanitize-trap=undefined`; final graph ยืนยัน `translate-c hb_c.h success 4s` จึงไม่ใช่ fatal blocker ของรอบนี้
- Full-core tests ยังไม่ได้รัน เพราะ build ล้มก่อน ไม่สามารถรายงานจำนวน failed test หรือรับรองว่ามี source incompatibility เพียงจุดเดียว

### หลักฐาน

Log root: `C:\Users\nickl\AppData\Local\Letta\build-logs\ghostty-windows\20261016-105434`

- `full-core.stderr.log` — compiler diagnostics
- `full-core-result.json` — final exit/timestamps เมื่อ runner จบ
- `results.jsonl` — VT tests/library และ C example builds ผ่านก่อนหน้า

### แนวทางแก้ที่เสนอ (ยังไม่ลงมือ)

1. ตรวจผู้ใช้ import `posix_c` และแยก dependency ที่จำเป็นจริงบน Windows ก่อนเลือก guard ที่ build level; exact search พบ `src/config/Config.zig:60`, `src/os/desktop.zig:6`, `src/os/passwd.zig:20` และ `src/termio/Exec.zig:584` โดย `passwd.zig` มี Windows guard แล้ว ต้องตรวจการใช้ symbol ในอีกสามจุด ไม่ใช่ลบ import ทั้งก้อนโดยไม่ตรวจ
2. ใช้ OS-specific binding เดิมใน official baseline ก่อนเขียนใหม่ ไม่เพิ่ม POSIX compatibility layer เพียงเพื่อให้ include ผ่าน
3. Patch เฉพาะ source/build ที่พิสูจน์ว่าจำเป็น ทดสอบ VT regression และ full-core ใหม่; ห้ามปิดเทสต์หรือทำ empty stub เพื่อให้ดูผ่าน
4. ขอผู้ใช้ตัดสินใจขอบเขต baseline compatibility patch ก่อนเริ่มเฟส 3 ตาม `PLAN.md`

### Patch รอบแรกหลังอนุมัติ

เพิ่ม guard `target.result.os.tag != .windows` ครอบการสร้าง import `posix_c` ใน `SharedDeps.zig` โดยไม่เปลี่ยน headers หรือ test filters บน non-Windows และไม่เพิ่ม empty module/stub บน Windows ตรวจ `zig fmt --check src/build/SharedDeps.zig` และรัน full-core เดิมซ้ำ ผลอยู่ใน `full-core-posix-guard.*` กับ `full-core-posix-guard-result.json` เมื่อจบ ยังไม่ถือว่า blocker resolved จากการแก้ไฟล์เพียงอย่างเดียว

ผลรอบแรก: exit 1 เวลา 11:43:23 GMT+7, `86/89 steps succeeded (1 failed)` ไม่มีขั้น translate `posix_c.h` หรือข้อผิดพลาด `pwd.h` แล้ว แต่ compile ไปติด `Dmabuf.zig` ตาม WIN-BUILD-002 จึงยืนยันได้ว่า guard ตัด dependency ที่ผิดแพลตฟอร์มออก ไม่ใช่ full-core ผ่าน ยังรอ VT regression และยังไม่ปิดการตรวจ compatibility ทั้งหมด

## WIN-BUILD-002 — Linux DMA-BUF ใช้ Windows handle type

- สถานะ: resolved สำหรับ Windows full-core compile/test หลัง OpenGL guard — exit 0 เวลา 11:59:52 GMT+7; ผู้ใช้อนุมัติขยายขอบเขตเวลา 11:44 GMT+7 ยังไม่รับรอง Linux/GPU/runtime ของแอป
- วิธีทำซ้ำ: full-core command เดิมบน baseline พร้อม patch `SharedDeps.zig`
- Actual: `src/renderer/Dmabuf.zig:44:46: error: expected type '*anyopaque', found 'comptime_int'` จาก `fds: [max_planes]std.posix.fd_t = @splat(-1)`
- Reference chain: `renderer.Dmabuf` → `renderer.OpenGL.ExportedFrame` ที่ `src/renderer/OpenGL.zig:302` ทำให้ต้องวิเคราะห์ DMA-BUF แม้กำลัง build Windows
- สาเหตุชนิดข้อมูล: บน Windows `std.posix.fd_t` เป็น HANDLE แต่ DMA-BUF planes ใช้ Unix integer descriptors และ sentinel -1 โครงสร้างยังมี `close`/comparison ที่ต้องตรวจร่วมกัน ไม่เปลี่ยน -1 เป็น pointer เพื่อให้ compile ผ่านอย่างเดียว
- ขอบเขตที่ต้องประเมินก่อนแก้: `src/renderer/Dmabuf.zig`, union/export/cleanup ของ `src/renderer/OpenGL.zig` และผู้ใช้ planes ที่จำเป็น
- แนวทางที่เสนอ: แยก Linux-only DMA-BUF จากชนิด/เส้นทางที่ Windows ต้อง compile โดยรักษา ownership/close จริงของ Linux ไม่ทำ no-op cleanup หรือปิด renderer tests และไม่เพิ่ม DMA-BUF implementation สำหรับ Windows
- หลักฐาน: `full-core-posix-guard.stderr.log` และ `full-core-posix-guard-result.json` ใน log root เดิม
- ข้อจำกัด: ยังไม่ยืนยันว่าจุดนี้เป็น incompatibility สุดท้าย และยังไม่ทดสอบ Linux regression

### Patch หลังอนุมัติขยายขอบเขต

- แก้ `src/renderer/OpenGL.zig` เท่านั้น ไม่เปลี่ยน Linux DMA-BUF descriptor/validate/close ใน `Dmabuf.zig`
- Windows ไม่ instantiate เส้น `target.exportDmabuf`; `ExportedFrame.dmabuf` มี payload เป็น `noreturn` ซึ่งสร้างค่าไม่ได้ แทนการทำ dummy descriptor หรือ no-op cleanup
- `present` ใช้ memory readback path เดิมบน Windows; non-Windows ยังลอง DMA-BUF ตาม presentation health และ fallback แบบเดิม
- เพิ่มเทสต์ `ExportedFrame platform payload and memory cleanup` ตรวจ platform-specific payload type และปล่อย CPU buffer ด้วย testing allocator ไม่ต้องสร้าง GPU context
- รัน targeted full-core filter ก่อน แล้วจึง full-core ไม่ filter เมื่อ targeted ผ่าน; logs `dmabuf-targeted.*`, `full-core-dmabuf.*`, metadata `dmabuf-results.jsonl`
- ยังไม่ได้ทดสอบภาพ/GPU, Linux runtime หรือ WGL และไม่รับรองว่าทาง OpenGL ปัจจุบันพร้อมสร้างแอป Windows จากการแก้ compile type นี้

ผล targeted เวลา 11:46:49 GMT+7: exit 0, `89/89 steps succeeded; 76/76 tests passed` จึงมีหลักฐานว่า platform payload/memory-cleanup test compile และชุด filtered tests ผ่านบน Windows แล้ว ยังรอ full-core แบบไม่ filter และไม่รับรองผล Linux จาก Windows test

ผล full-core ที่ตามมาเวลา 11:59:52 GMT+7: exit 0, `89/89 steps succeeded; 3917/3978 tests passed (61 skipped)` ปิด compile blocker ได้ตามขอบเขต Windows build/test ไม่ใช่หลักฐานว่า renderer สร้าง context หรือแสดงภาพได้จริง

## WIN-TEST-003 — VT regression test runner ไม่ตอบกลับ

- สถานะ: confirmed runner failure รอบ 11:43:56–11:55:52 GMT+7, ยังไม่ยืนยันสาเหตุ
- Command: `zig build test-lib-vt --summary all`
- Result: exit 1, `43/45 steps succeeded (1 failed); 3596/3628 tests passed (32 skipped)` โดยชุดที่รายงานผลครบผ่าน แต่อีก runner ล้มด้วย `test runner failed to respond for 1m2.442ms`
- Failed runner: `.zig-cache/o/157e40d424d1dbef4dab8959c7caacfd/test.exe` พร้อม `--listen=-`; ไม่ใช่ assertion failure ที่ระบุชื่อเทสต์ใน log นี้
- Log: `vt-regression.stderr.log`, `posix-regression-results.jsonl` ใน log root เดิม
- ระหว่างรอบนี้ full-core compile/test รันซ้อนอยู่ แต่ยังไม่พิสูจน์ว่า CPU/resource contention เป็นสาเหตุ
- ขั้นถัดไป: รอ full-core ปัจจุบันจบ แล้ว rerun VT suite โดยลด concurrency และไม่ filter/skip tests จากนั้น library build regression; เปรียบเทียบ seed/runner/ผลจริงก่อนสรุป
- ยังไม่แก้ Zig/test runner ไม่เพิ่ม timeout ไม่ปิดเทสต์ และไม่อ้างว่า VT regression ผ่านจากผลเพียงชุดเดียว

หลัง full-core จบแล้วเริ่ม retry แบบ `zig build test-lib-vt -j1 --summary all` โดยไม่ซ้อน full-core และไม่ filter tests รอผลใน `vt-serial-results.jsonl` หากยัง timeout ต้องวิเคราะห์ failed runner/เทสต์ที่เกี่ยวข้องต่อ ไม่ถือว่าลด concurrency แล้วสาเหตุได้รับการพิสูจน์

ผล retry เวลา 12:13:16 GMT+7: exit 0, `6722/6786 tests passed (64 skipped)`, `45/45 steps succeeded` ตรง baseline เดิมทั้ง 2 runners จึงไม่พบ test regression ที่เกิดซ้ำในรอบนี้ สถานะเป็น **retry passed / root cause unconfirmed** เก็บเหตุ timeout ไว้สำหรับติดตาม ไม่เพิ่ม timeout หรือเปลี่ยน tests ทั้งนี้ `-j1` ไม่ได้ทำให้ test process เหลือหนึ่งตัวตามที่คาด มี 2 runners ภายใน command เดียวแต่ไม่มี full-core ซ้อน หาก timeout เกิดซ้ำให้เก็บ seed/runner/test diagnostics เพิ่ม ไม่สรุปว่าจบถาวรแล้ว

Library build หลัง retry ผ่านเวลา 12:14:08 GMT+7: exit 0, 48/48 build steps สำเร็จ ไม่เหลือ baseline compile/test blocker ที่เกิดซ้ำในรอบตรวจล่าสุด; timeout คงเป็น follow-up ด้าน test stability ไม่ใช่ผลล้มเหลวที่ถูกลบทิ้ง

## ข้อสังเกตสำหรับเฟส 2 — EGL/WGL integration ยังไม่ออกแบบ

ซอร์ส `src/renderer/OpenGL.zig` ที่ตรวจใช้ `gl.egl`, `egl.Context` และ `device.display` โดยตรง พร้อมกำหนด OpenGL ขั้นต่ำ 4.3 การสร้าง WGL context บน HWND อย่างเดียวจึงยังไม่พิสูจน์ว่าจะส่งเข้า renderer นี้ได้ ต้องออกแบบ context/device/presentation adapter หรือเส้นทาง EGL บน Windows จากเอกสารทางการก่อน implement ไม่รับโค้ดฟอร์กและไม่เริ่มเปลี่ยน renderer ทั้งชุดในงาน compatibility นี้ ยังไม่ตรวจ driver/extension/ภาพจริงบนเครื่อง

## WIN-RUNTIME-004 — Real-surface stress พบ owned process handles และ process-global growth

- สถานะ: original process/thread handle leak **แก้และ targeted test ผ่านแล้ว**; strict lifecycle gate ยัง **failed/blocked** ที่ส่วนต่างหนึ่ง handle/หนึ่ง thread ไม่อนุมัติ exception เอง
- ทำซ้ำ: บิลด์ Win32 runtime แล้วใช้ `tools/windows/runtime-smoke.ps1 -Mode lifecycle` เป็น21 sessionsใน process เดียว NoProfile/UTF-8/ไม่ activate window ตรวจทุก session,deadline120s ไม่มีการฆ่า process ตามชื่อ
- ก่อนแก้: `lifecycle-native-20261016-152156-421`,handles235→276 (+2/session),GDI3→3,USER3→3,threads6→7; exit1,ไม่ timeout/ไม่มี owned orphan
- สาเหตุที่พิสูจน์จาก code: CreateProcessW คืน hThread/hProcess แต่ไม่มี release ของ originals; libxev IOCP watcher มี duplicate/job ของตัวเอง ไม่ได้ปิด originals ให้ แก้ Command spawn/deinit และ Exec stop/externalExit ฝั่ง Windows ไม่เปลี่ยน POSIX behaviour
- หลังแก้: ownership test76/76ผ่าน; `lifecycle-native-20261016-153205-059` และ `...154426-789` ไม่มี +2/session แล้ว แต่ยัง handles233→234,threads6→7; GDI/USERคงที่ จึงยังถือ failed ไม่เพิ่ม threshold/warmup/timeout ให้ผ่าน
- Thread diagnostic ในรอบ15:44: baselineมีmain executable,ntdll workersและสองthreadsจาก`atio6axx.dll`; หลัง20รอบมีmainเดิม/สองatio threadsเดิม/ntdll workersและthreadใหม่เริ่มจาก`amdihk64.dll`ใต้AMD DriverStore ไม่มี renderer/IO threadของเราเหลือในชุดที่ตรวจ Sourceใช้NtQueryInformationThread(start address)+GetModuleHandleExW(FROM_ADDRESS) เฉพาะ own process
- thread-start diagnostic เดิมระบุได้เพียง **entry module** ของ thread ไม่ใช่ live allocation caller/ownership และยังไม่พิสูจน์ว่า **handle** เพิ่มเป็นของ threadนั้น ห้ามเรียกทั้งหมดว่า cache หรืออ้าง strict gate ผ่านโดยอัตโนมัติ
- 26 ตุลาคม2026: หลังinheritance/attribute-list fixes normalno-marker/app-localยังfailed242→243handles/6→7threads ไม่timeout ในseparateowneddebuggercasesจับRPCGCปิดbaselineALPCสองgenerationsสำเร็จ และactualreturnedHANDLEของAMDCreateThread/RPCEvent/self-threadduplicateสามรายการjoinfullhistory/finalPSSได้แล้ว **เฉพาะinstrumentedPIDsนั้น** ยังมีextraEvent/IOCPไม่ทราบlivecreatorและไม่โอนidentitiesไปnormalrun ไม่ปิดWIN004หรือunknownDLLhandles ดู `windows-postfix-attribution-th.md`
- ขั้นถัดไป: attribution ของ handle และตรวจว่าการเพิ่มเป็น bounded process-global driver state จริง พร้อมบันทึก policy/approval ถ้าต้องยอมรับ known exception; ไม่ kill thread,ไม่ปิด unknown-owned handle,ไม่ disable AMD overlay/เปลี่ยน driver setting ของผู้ใช้เพื่อทำให้ test ผ่าน ขณะรอทำ EOF/burst/startup tests อื่นได้ แต่ไม่ปิดเฟส4D
- หลักฐานอยู่ `%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\phase3b-runtime\results.jsonl` และ stderrของแต่ละreceipt; เฉพาะ controlled output ไม่อ่าน clipboard/profile ของผู้ใช้

### Read-only attribution review — 18:10

- SDK `processsnapshot.h` ให้ขยายmetadataได้ด้วย `PSS_CAPTURE_HANDLE_BASIC_INFORMATION` และตรวจ `PSS_HANDLE_HAVE_TYPE`/`PSS_HANDLE_HAVE_BASIC_INFORMATION` ก่อนใช้ObjectType/basicfields ต้องคงUNKNOWNเมื่อSDKไม่ให้type ไม่อ่านTypeName/ObjectName/VMหรือunionข้อมูลที่ไม่มีvaliditybit แผนถัดไปคือเปรียบเทียบcounts/handlevaluesตามชนิดเพื่ออธิบายthreadhandles+2แต่total+1;handlevalueอาจreuseจึงไม่ถือว่าเลขเท่ากันเป็นobjectเดิมแน่นอน
- พบลำดับsamplingไม่สมมาตร:baselineCountsก่อนthread/PSSdiagnostic แต่finalCountsหลังdiagnostic จึงควรแยกcanonicalrawgateที่อ่านก่อนdiagnosticทั้งสองฝั่งกับdiagnostic-onlypostcounts ไม่ย้ายbaselineหลังwarmupเพิ่มเพื่อทำให้ผ่าน และต้องเทียบdiagnostic-disabledrunแยกก่อนโทษobservereffect
- หลักฐานล่าสุดcycle0หลังsnapshotยัง233handles/6threads,cycle1–3เป็น234/8และfinal234/7 **ยังไม่พิสูจน์ว่าPSSทำให้เพิ่ม** หรือพิสูจน์ownerของnetdeltaทั้งหมด การขยายbridgeและcontrolledrunยังไม่ได้ทำในreviewนี้ ระหว่างhumanpreviewตรวจเฉพาะsource/SDK/log ไม่เปิดหน้าต่างหรืออ่านclipboardเพิ่มเติม

## WIN-RUNTIME-005 — IOCP renderer wake ถูกคัดลอก และ native message storm หลังแก้

- พิสูจน์อาการก่อนแก้ด้วย1080pchanging-outputทั้งpaced16msและunbounded:25presents/25paintsต่อ15s ทั้งคู่ แม้CPUparentต่างกันมาก ไม่ใช่หลักฐานว่าGPUช้าหรือควรเปลี่ยนrenderer
- `Termio.Options`, `Termio` และ `StreamHandler` เก็บ `xev.Async` by-value ก่อนrendererลงทะเบียนwaiter แต่pinnedIOCPAsyncเก็บguard/waiter/wakeupinline ไม่ใช่copyablefd NativeIOจึงnotifydetachedcopy ส่วนcursor-resetmailboxยังปลุกตัวจริงทุกประมาณ500ms
- แก้borrow `*xev.Async` จาก `&self.renderer_thread.wakeup` ที่อยู่stableในCoreSurface ไม่ชี้local`render_thread`ที่ถูกย้าย ไม่deinitborrowedhandle/ไม่แก้libxev/pinnedcache POSIXใช้instanceเดียวกันโดยไม่มีการเปลี่ยนownership
- `renderer-wakeup-borrow-unit-02` **76/76pass**:counterfactualcopyก่อนwaiterregistrationไม่ปลุกcallback;borrowedhandlerต้องปลุกผ่านboundednonblockingdispatch ไม่มีcursor/idletimerช่วยให้ผ่าน
- `runtime-build-26-releasesafe`123/123; pacedcase **1411presents/951paints** ผ่าน แต่unbounded **9437presents/2paints** และWin32WakeFailedหลายครั้ง แม้exit0/no-timeoutจึง **failed** ไม่ซ่อนcriticallogหรือประกาศperformancegateผ่าน
- กำลังแก้nativefacadeให้wakecoalescedภายใต้window_mutex,clearก่อนdrainเพื่อไม่lostwake,consumeเฉพาะlatestframeหลังdrain และdeliverpendinginvalidregionแบบevent-driven ไม่มีtimerเพิ่ม ต้องพิสูจน์burstpaint/input/timerfairnessและshutdownอีกครั้งก่อนปิดgapนี้ lifecyclethreshold/warmup/deadlineในWIN-RUNTIME-004ไม่เปลี่ยน
- ผล18:06: แก้facadeและboundedinput/paint/timerpumpแล้ว รอบ28burstสองรอบจบ15.44s/15.44s(present=paint2107/2085),paced15.37s(1420/1420),ครบ25sprofilebudgetที่tightenเพิ่ม ไม่เพิ่มwatchdogเดิม;windowcoalescing21dispatch/21mailboxrequests/stalegenerationignored,burstclose/exit/input+repeat/missing-shellผ่านครบ **full-core3923pass/61skip,89/89steps** ถือว่าlostwake/message-storm/timer-starvationถูกแก้และตรวจผ่านในcontrolledcasesนี้ แต่ยังไม่อ้างhardware-inputlatency/display/compositorFPS/humanIMEหรือใช้ปิดWIN-RUNTIME-004 ดูartifactSHA/receiptsในwindows-validation.md
