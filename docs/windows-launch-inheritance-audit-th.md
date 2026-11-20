# ตรวจ handle inheritance ของ worker / ConPTY

วันที่: 26 ตุลาคม 2026 — ตรวจบน working tree สาขา `windows-terminal-baseline` โดยเก็บงานเดิมไว้ ไม่ commit/push และไม่เปลี่ยน GPU default

## ขอบเขตและสิ่งที่ยังอ้างไม่ได้

ตรวจการสร้าง process, ช่วงที่ handle ตั้งให้สืบทอดได้, allowlist, thread/caller และ ownership ของเส้นทาง `Command.start` กับ render-worker เท่านั้น ไม่ใช่การรับรองทั้งแอปหรือทุก process launcher

**ยังไม่พบหลักฐานว่าประเด็นนี้เป็นต้นเหตุของ `WIN-RUNTIME-004`** ตัวเลข handles +1 / threads +1 จาก exec321 ยังไม่ระบุ allocation owner และเกิดได้แม้ไม่ใช้ portable marker จึงไม่เรียกว่า app-owned leak และไม่ล้าง failure เก่า

## หลักฐานจากซอร์ส

- `src/Command.zig` เส้นทาง Windows สร้าง attribute `PSEUDOCONSOLE` แต่ไม่มี `HANDLE_LIST` สำหรับ ConPTY; เดิมเรียก `CreateProcessW` ด้วย `bInheritHandles=TRUE` ทั้งกรณี ConPTY และกรณี redirect stdio ปกติ
- `src/pty.zig` สร้าง pipe โดยไม่ให้สืบทอด และ clear `HANDLE_FLAG_INHERIT` ทั้งสี่ปลาย การป้องกันนี้ครอบคลุม pipe ของ PTY เอง ไม่ได้ห้ามสืบทอด handle อื่นใน process
- `src/render_worker_client.c:134–188` สร้าง mappings/events ที่ให้สืบทอดได้ รวมถึง NUL/diagnostic duplicate ชั่วคราว ใช้ allowlist สำหรับลูก worker ของตนเอง แล้วจึง clear flags ของ parent และปิด temporary handles
- Allowlist ของ worker ไม่ได้จำกัด incoming handles ของ process อื่นที่เปิดพร้อมกัน `src/render_worker_client.h` ระบุให้ caller serialize กับ launch อื่นที่เปิด inheritance แต่ไม่พบ lock ร่วมในเส้นทาง launch โดยตรงที่ตรวจ
- `src/Surface.zig` สร้าง renderer ระหว่าง init และเปิด IO thread แยก; `src/termio/Thread.zig` → `Exec.threadEnter` → `Subprocess.start` → `Command.start` เป็นทางเปิด shell จึงยังต้องแยกการพิสูจน์ overlap จริงจากข้อบกพร่องทั่วไปของ broad inheritance

ข้อสรุปเชิงซอร์ส: handle อื่นที่สืบทอดได้ระหว่าง ConPTY launch เป็น candidate ที่ต้องทดสอบ ไม่ใช่หลักฐานว่า worker overlap หรือ failure เก่าเกิดจากเส้นทางนี้จริง

## Regression ที่ใช้โค้ดจริง

ไฟล์:

- `src/windows_command_inheritance_test.zig`
- `tools/windows/command-inheritance-child.c`
- `tools/windows/command-inheritance-check.ps1`
- core-test wiring ใน `build.zig` และ test block ของ `src/Command.zig`

ชุดเทสสร้าง system ConPTY แบบ headless และ event ที่เป็นของเทสเอง **หลัง** สร้าง ConPTY แล้ว เรียก production `Command.start` เพื่อเปิด C helper ส่วนตัว ไม่ใช้ shell, clipboard, user files, renderer หรือ session จริง

ต้องได้ READY, ส่ง `CANARY-PING`, ได้ ACK ตรงข้อความ, child exit 0 และ teardown สำเร็จก่อนตรวจ isolation ทดสอบเฉพาะ numeric handle slot ของ canary ใน process ลูกที่เทสเป็นเจ้าของ โดย duplicate กลับเข้า parent และเปรียบเทียบ object identity ป้องกันการสรุปผิดจาก handle value ถูกใช้ซ้ำ ไม่ enumerate handles และไม่ใช้ `CLOSE_SOURCE`

มี transcript/wait bounds และ drainer ทำงานตลอด `ClosePseudoConsole` ทั้งนี้ Win32 API นี้เป็น synchronous และไม่มี deadline/cancellation ในตัว จึงยอมรับเป็น API assumption พร้อม watchdog ภายนอกทั้ง invocation: timeout หรือ forced cleanup คือ **failure** เสมอ ไม่ใช่ผ่าน และไม่ผ่อน runtime gates เดิม

supervisor ยืนยันการ exit ของ Zig root ผ่าน retained process handle เท่านั้น ไม่อ้างว่าได้ยืนยัน descendants ทุกตัวหลัง timeout ส่วนผลปกติต้องผ่าน assertion ของ private child ใน native fixture

## ผลการตรวจและการรัน

- parse/format ของไฟล์ที่เปลี่ยนผ่าน; static verifier ให้ limited pass สำหรับโครงสร้างเทส ยังไม่ใช่ runtime qualification
- original attempt แรก: build/link failed เพราะเทสประกาศ `CompareObjectHandles` กับ Kernel32 ทั้งที่ Microsoft ระบุ Kernelbase — **ไม่นับเป็น original-red ของบั๊ก**
- แก้เฉพาะ binding ของเทสให้หา API จาก Kernelbase ที่โหลดอยู่แล้ว ไม่ค้น/โหลด DLL จาก cwd/PATH และไม่ถือ missing API ว่าเป็น canary absence
- attempt หลังแก้ binding: build ผ่านแต่ assertion ของ helper path ล้มก่อนสร้าง ConPTY เพราะ `addOptionPath` ส่ง cache-relative path — **ยังไม่นับเป็น original-red ของบั๊ก**
- แก้เทสให้ resolve generated dependency เป็น absolute path ด้วย Windows UTF-16 API ก่อนเปิด helper ไม่ใช้ PATH lookup
- **original-red ยืนยันแล้ว** `red-20261026-191828-036-2eb83e16`: 75/76 tests ผ่าน, เคส canary ล้มเฉพาะ final isolation assertion พร้อม `COMMAND_INHERITANCE ready=1 ack=1 child_exit=0 cleanup=healthy inherited_canary=1`; ไม่ timeout, ไม่ forced cleanup, hash ของไฟล์ที่เฝ้าดูไม่เปลี่ยนระหว่างรัน
- แก้ production เฉพาะการเลือก `bInheritHandles`: ConPTY ใช้ `FALSE`; non-ConPTY ยังคง `TRUE` เพื่อรักษา redirect stdio เดิม ไม่เปลี่ยน worker protocol, deadlines, GPU default หรือ failure gates
- **green ผ่าน** `green-20261026-192043-388-9e5d8f95`: exit 0, 91/91 build steps, 76/76 tests; receipt เดิมครบและ `inherited_canary=0`
- **adjacent ผ่าน** `adjacent-20261026-192125-113-1d62fa75`: exit 0, 91/91 steps, 111 passed / 12 skipped จาก 123 tests รวมเส้นทาง Command เดิม; ไม่เรียก skip ว่าผ่าน
- ทั้ง green/adjacent ไม่ timeout, ไม่ forced cleanup และ hash ของไฟล์ที่เฝ้าดูไม่เปลี่ยนระหว่างรัน; SHA ของ test/helper/build/supervisor ตรงกับ original-red ที่ยืนยันแล้ว เปลี่ยนเฉพาะ `Command.zig`
- independent verifier ตรวจ logs, assertions และ current source hashes ซ้ำแบบอ่านอย่างเดียวแล้ว ให้ focused pass ไม่ใช่ app-wide qualification
- successful runner มีข้อความ `failed command` ข้าง diagnostic stderr ของ receipt ด้วย แต่ exit code และ test summaries เป็น success จึงไม่ใช้ข้อความนั้นโดด ๆ มาตัดสินว่าเทสล้ม
- **Win32 ReleaseSafe compile/install ผ่าน** `app-build-20261026-193028-701`: exit 0, 123/123 steps, ไม่มี timeout/forced cleanup/source mutation; prefix ใหม่ `zig-out/app-build-20261026-193028-701`, executable `bin/localterm-dev.exe` SHA-256 `E0AA1AC887FBD29C30B143CEDAF85FA16EEA7A721E9C10570DB7FD370CC5C3D0`
- ตรวจ install prefix แล้วไม่มี `command-inheritance-child` ติดไป (0 files) ไม่เปิดแอปหรือแก้ portable เดิม ผลนี้เป็น compile/install ไม่ใช่ native UI/app-local ConPTY acceptance หรือการรัน full Core/VT suite
- งาน bounded investigation/fix นี้จบแล้ว ไม่มี build/test ค้าง แต่ gate ของแอปทั้งหมดด้านล่างยังไม่ถูกปิดโดยผลรอบนี้

หลักฐานราย invocation อยู่ที่ `%LOCALAPPDATA%/Letta/build-logs/ghostty-windows/launch-inheritance/` มี arguments, source SHA-256, compiler SHA-256, exit/timeout และ stdout/stderr; ผลจะถูก invalidate หากไฟล์ input ที่บันทึก hash เปลี่ยนระหว่างรัน

## ข้อจำกัดที่ต้องเก็บไว้

- กรณี non-ConPTY ที่ redirect stdio ยังเป็นอีกขอบเขตหนึ่ง การปิด inheritance เฉพาะ ConPTY ไม่ใช่การแก้ isolation ทั้ง process
- native fixture นี้ใช้ system ConPTY ไม่ใช่ app-local DLL หรือการรับรอง UI/portable ทั้งชุด
- `WIN-RUNTIME-004`, exec181 `WorkerCloseFailed`, exec244 `LateRenderedCleanupFailed`, actual GPU-busy, controlled performance และ physical keyboard/IME/mixed-DPI ยังเป็นเกณฑ์แยกกัน
- ไม่เปิด GUI, ไม่ pause driver, ไม่ปิด handle ของโปรแกรมอื่น และไม่แทน human acceptance ด้วย synthetic test

### ข้อสังเกต cleanup ที่ไม่รวมใน patch นี้

ณ snapshot ของ inheritance audit ยังไม่พบ `DeleteProcThreadAttributeList` หลังสร้าง attribute list ขณะที่ buffer ถูกปล่อยผ่าน arena จึงแยกออกจาก patch inheritance เดิม ต่อมาผู้ใช้อนุมัติงาน cleanup และทำ original-red→green ผ่านแล้ว รวม success/error matrix และ focused verifier pass ดู `windows-attribute-list-cleanup-th.md` ประเด็นนี้ยังไม่ใช่หลักฐานว่าเป็น allocation owner ของตัวเลข +1/+1 หรือเหตุผลให้ปิด `WIN-RUNTIME-004`

## เอกสาร Microsoft ที่ตรวจประกอบ

- [CreateProcessW: bInheritHandles และค่า handle ที่สืบทอด](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)
- [Creating a Pseudoconsole Session: ตัวอย่างใช้ bInheritHandles=FALSE และการสื่อสารผ่าน pipe](https://learn.microsoft.com/en-us/windows/console/creating-a-pseudoconsole-session)
- [CompareObjectHandles: Windows 10+, Kernelbase.dll](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-compareobjecthandles)
- [DeleteProcThreadAttributeList: อายุของ attribute list เป็นประเด็นติดตามแยก](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-deleteprocthreadattributelist)
