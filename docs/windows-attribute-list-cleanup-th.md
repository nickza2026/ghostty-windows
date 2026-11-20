# อายุและ cleanup ของ Windows process attribute list

วันที่: 26 ตุลาคม 2026 — งานต่อจาก `windows-launch-inheritance-audit-th.md` ใน primary checkout เดิม ไม่ใช้ worktree ไม่ commit/push และไม่เปลี่ยน GPU default

## ประเด็นที่ตรวจ

`Command.startWindows` สร้าง attribute list สำหรับ `PSEUDOCONSOLE` ด้วย `InitializeProcThreadAttributeList` และ `UpdateProcThreadAttribute` แล้วใช้ใน `CreateProcessW` แต่เดิมไม่มี `DeleteProcThreadAttributeList` ก่อน caller ปล่อย arena buffer ส่วน worker C มี flag ownership และ delete ของตนเองอยู่แล้ว จึงไม่แก้ worker ปนในงานนี้

การคืน buffer ของ arena ไม่ใช่การเรียก destructor ของ opaque Windows attribute list ต้องแยก lifetime ของ native list ออกจาก backing storage และห้าม delete ก่อน `CreateProcessW` ใช้งานเสร็จ

ตรวจเอกสาร Microsoft ของ Initialize แล้ว: “When you have finished using the list, call the DeleteProcThreadAttributeList function.”

**ยังไม่อ้างว่าเป็นสาเหตุของ `WIN-RUNTIME-004` หรือพิสูจน์ OS memory/handle leak แล้ว** งานนี้ตรวจสัญญา API และ control flow เท่านั้น ไม่วัด resource counts ซ้ำเพื่อกลบ failure เดิม

## Regression บน actual Command

ใช้ private headless ConPTY/helper และ watchdog เดิม เพิ่ม receipts เฉพาะ `builtin.is_test` แบบ thread-local:

- นับ initialize เฉพาะ native call ที่สำเร็จ ไม่รวม sizing query
- นับ update หลัง native call สำเร็จ และ create attempt ก่อนเรียก native `CreateProcessW`
- นับ delete เฉพาะหลัง native `DeleteProcThreadAttributeList` คืนกลับ ไม่ใช้ mock/no-op delete
- snapshot จำนวน delete ตรง create boundary ต้องเป็น 0 เพื่อไม่ให้ total count ที่ถูกต้องซ่อนการลบเร็วเกินไป
- reset state/injection ก่อนแต่ละเคสและหลังจบ ตรวจและเรียก start ใน thread เดียวกัน ไม่มี storage หรือ injection behavior นี้ใน production

| เคส | init | update | create attempt | delete ที่ต้องได้ |
|---|---:|---:|---:|---:|
| Success: READY/ACK/exit0/healthy teardown | 1 | 1 | 1 | 1 |
| Inject ก่อน real initialization | 0 | 0 | 0 | 0 |
| Inject หลัง real initialization | 1 | 0 | 0 | 1 |
| Inject หลัง real update | 1 | 1 | 0 | 1 |
| Real CreateProcess failure ด้วย path/args[0] absolute ที่ syntax ไม่ถูกต้อง | 1 | 1 | 1 | 1 |

เคส injection พิสูจน์ unwind หลังขั้น native ที่ระบุ ไม่เรียกว่าได้ทำให้ Windows API เอง fail จริง ทุก failure case ต้องคืน error ที่กำหนดและ `pid == null`; ไม่รอ READY/ACK จาก process ที่ไม่ได้สร้าง Success-case assertions เกิดหลัง child exit/teardown เพื่อไม่ให้ expected original-red บังคับฆ่าลูกแทน healthy close

## ลำดับ ownership ที่เสนอ

1. owner pointer ระดับฟังก์ชันเริ่ม `null` และมี defer ระดับฟังก์ชัน
2. sizing query และ initialization ที่ยังไม่สำเร็จไม่เป็นเจ้าของ list
3. ตั้ง owner ทันทีหลัง real initialization สำเร็จ ก่อน update/error injection
4. ใช้ list ต่อจน CreateProcess สำเร็จหรือ fail แล้ว defer เรียก delete หนึ่งครั้ง ก่อน arena ถูกปล่อย

ไม่วาง defer ไว้ใน branch สร้าง pseudoconsole attributes เพราะ branch จบก่อน CreateProcess และจะลบ list เร็วเกินไป ไม่เปลี่ยน inheritance/stdio ที่แก้และทดสอบแล้ว

## ผลการตรวจ

- Astra review แบบอ่านอย่างเดียวเห็นด้วยกับ owner/defer ระดับฟังก์ชันและ safeguards ของ regression
- **original-red** `red-20261026-201215-934-73b5f368`: exit 1, 77 passed / 4 failed จาก 81 tests ล้ม final delete-count assertion ใน success/post-init/post-update/real-launch-failure ทุกเคสได้ `delete=0` หลัง native stages ที่คาดไว้และ healthy fixture teardown; pre-init control ได้ 0/0/0/0 และผ่าน inheritance regression เดิมยังผ่าน
- **fix** เพิ่ม owner/defer ระดับ `startWindows` ตามลำดับด้านบน และ API declaration ของ Delete ไม่เปลี่ยน worker, deadlines, inheritance หรือ stdio
- **green** `green-20261026-201708-548-c6461ca5`: exit 0, 91/91 steps, **81/81 tests passed** receipts ครบ matrix; ทุกเคสที่ init สำเร็จได้ delete=1, pre-init ได้ delete=0 และ delete ก่อน create=0
- **adjacent** `adjacent-20261026-201747-495-a7cd26c1`: exit 0, 91/91 steps, **116 passed / 12 skipped จาก 128 tests** ไม่ใช้ skipped แทน passed
- ทั้งสามรอบไม่ timeout/forced cleanup และ input ที่เฝ้าดูไม่เปลี่ยนระหว่างรัน test/helper/API-declaration/supervisor/build hashes เดียวกันระหว่าง red→green เปลี่ยนเฉพาะ `Command.zig` เพื่อใส่ owner/defer
- real-launch-failure ตั้งใจคืน `error.Unexpected` (`FILE_NOT_FOUND`) จึงมี diagnostic stack trace ใน stderr แม้ green ผ่าน ตัดสินจาก error assertion, receipts, exit และ summaries ไม่ใช้ข้อความ `failed command` ที่ runner แสดงข้าง stderr เพียงอย่างเดียว
- **independent verifier: focused pass** ตรวจ owner/defer, real native delete tracing, ordering snapshot, resets, failure semantics และ source hashes แล้ว ไม่พบ concrete issue ในขอบเขตนี้ ไม่รันเทสซ้ำหรือแก้ไฟล์
- **Win32 ReleaseSafe compile/install ผ่าน** `attributes-build-20261026-202012-333`: exit 0, **123/123 steps**, ไม่ timeout/forced cleanup/input mutation; prefix ใหม่ `zig-out/attributes-build-20261026-202012-333`, `bin/localterm-dev.exe` SHA-256 `10ADEFA20075AC921A47CCF63DA56D11467E6E6D769A7916184EEDB197BA2741`
- Production non-test compilation ผ่านโดย test tracing/injection ถูกปิดตาม `builtin.is_test`; ตรวจ install prefix แล้วไม่พบ private test helper (0 files) ไม่เปิดแอป ไม่ทับ portable เดิม ไม่ใช่ UI/app-local acceptance หรือ full Core/VT test run
- งาน cleanup เฉพาะจุดนี้เสร็จ ไม่มี task-owned build/test ค้าง ไม่มี commit/push และเก็บงานเดิมใน primary checkout ไว้

หลักฐานราย invocation ใช้ `%LOCALAPPDATA%/Letta/build-logs/ghostty-windows/launch-inheritance/` เดิม มี source/compiler hashes, arguments, exit/timeout และ logs สคริปต์บันทึก `src/os/windows.zig` เพิ่มด้วย หาก input ที่เฝ้าดูเปลี่ยนระหว่างรันต้อง invalidate ผล

## ขอบเขตความปลอดภัยและเกณฑ์ที่ยังเปิด

private handles/child เท่านั้น ไม่มี GUI, shell, user clipboard/files, foreign handle enumeration/closure หรือ driver pause `ClosePseudoConsole` ยังเป็น synchronous API assumption พร้อม continuous drain และ external process watchdog; timeout/forced cleanup คือ failure และ supervisor ยืนยันเพียง Zig root exit ไม่อ้าง whole-tree shutdown หลัง timeout

ไม่ใช้ผลนี้ปิด `WIN-RUNTIME-004`, exec181, exec244, actual GPU-busy, performance, physical IME หรือ mixed-DPI และ native fixture นี้ไม่ใช่ app-local ConPTY/UI acceptance

อ้างอิง: [InitializeProcThreadAttributeList](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-initializeprocthreadattributelist), [DeleteProcThreadAttributeList](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-deleteprocthreadattributelist)
