# Sandbox: ปิด terminal เมื่อ USB หลุด

อัปเดต 20 พฤศจิกายน 2569

## ขอบเขตที่อนุมัติ

เมื่อ USB ที่เก็บแพ็กและ Data หลุด ให้หน้าต่าง terminal ของ Sandbox หายไปเอง ไม่ค้างกล่อง error/confirmation และไม่ fallback ไป host shell งานนี้ไม่อนุญาตให้ force-stop VM อัตโนมัติหรือทำให้การถอดดิสก์ระหว่างเขียนข้อมูลกลายเป็นปลอดภัย

ผู้ใช้ให้แก้ปัญหาเปิด Sandbox ไม่ได้ก่อน งานนั้นกู้สำเร็จแล้ว: VM เดิมค้าง `stopping`; หลังได้รับอนุมัติ force-stop ครั้งเดียว ได้ทดสอบเปิด EXE จริงจากสถานะหยุด/มี state ค้าง ผ่าน launcher ของจริงโดยไม่ใช้ helper boot ล่วงหน้า เข้า guest ผ่าน ConPTY วาดข้อความไทย และปิดเฉพาะหน้าต่างทดสอบแล้ว VM ยัง ready การอนุมัติ force-stop ครั้งนั้นใช้ไปแล้ว ไม่ใช่สิทธิ์หยุด VM รอบใหม่เพื่อ build/test

## สถานะ USB auto-close

**ส่งมอบแล้วที่ `A:\sandbox\Sandbox.exe`** เปลี่ยนเฉพาะ EXE และเก็บไฟล์เดิมเป็น rollback โดยไม่ reset Data, เปลี่ยน keys หรือหยุด VM เพื่ออัปเดต

SHA256 ของ EXE ที่ติดตั้ง: `8430094d8345c59520efaac1d1840c7760758196637cda36d4b00fabec833288`

เมื่อ Windows ส่ง completed volume-removal ของไดรฟ์ที่เก็บแพ็ก หน้าต่างจะซ่อนทันทีแล้ว cleanup session โดยไม่ถามยืนยัน กรณีไม่มี notification มีการตรวจ drive-letter map สำรองทุก 1 วินาที หน้าต่างที่เปิดก่อนอัปเดตยังใช้โค้ดเก่าจนผู้ใช้เปิดใหม่ ไม่ได้ปิดหน้าต่างงานของผู้ใช้ให้อัตโนมัติระหว่างส่งมอบ

Source ที่เพิ่ม/ปรับ:

- `src/apprt/win32/sandbox_storage.zig`: pure policy จาก drive letter ของ executable root ที่ผ่าน validation แล้ว ไม่อิง cwd หรือ DRIVE_REMOVABLE เพราะ USB enclosure อาจรายงานเป็น fixed drive
- `src/apprt/win32/window.zig`: รับ completed volume removal ที่ตรงไดรฟ์เท่านั้น ซ่อนหน้าต่างก่อน cleanup ข้าม confirmation เฉพาะ storage-loss และป้องกัน closing callback ซ้ำ รวม timer สำรอง GetLogicalDrives ทุก 1 วินาที
- `src/apprt/win32/App.zig`: เปิด guard เฉพาะ Sandbox flavor แยก diagnostic ว่า storage-loss ไม่ใช่ natural child exit
- `src/win32_storage_loss_probe.zig`: ทดสอบ HWND ของตัวเองนอกจอ ส่ง message ใน process เดียวกัน รวม nested confirmation pump โดยไม่เปิด dialog มารบกวนผู้ใช้
- `tools/windows/sandbox/storage-message-probe.c` และ `verify-storage-loss.cjs`: shipping ConPTY regression แบบ synthetic ไม่มี backend/VM/USB จริง

ไม่ปิดจาก query-remove, arrival, ไดรฟ์อื่น, network-volume event, payload ไม่ครบ หรือ GetLogicalDrives ที่คืน 0 ซึ่งหมายถึง probe error ไม่ใช่หลักฐานว่าไดรฟ์หาย ไม่ใช้ error จากไฟล์ใน Data หรือ SSH เป็นเงื่อนไขปิด

## หลักฐานที่เสร็จแล้ว

- startup/recovery/HWND input/clipboard delivery Node tests: 48/48 ผ่าน
- pure storage policy Zig tests: 4/4 ผ่าน
- native window probe: removal, nested_confirmation, disabled, fallback ผ่านครบ ทั้ง genuine paint, hide และ closing callback ครั้งเดียว
- logs/probe/build receipt: `zig-out/usb-loss-20261120/`
- startup EXE proof: `zig-out/a-launch-recovery-91adc27a-8862-40ec-bd00-401be621deb7/recovered-native-stopping-rescue-20261120-1115.json`
- shipping build แบบ serial ผ่าน พร้อม source-hash stability และ resource guard
- shipping ConPTY original-vs-candidate: EXE เดิมยังเปิดหลัง matching removal; candidate ซ่อนและปิดจริง พร้อม owned child exit, fresh marker/paint และ negative events ผ่าน หลักฐาน `zig-out/storage-loss-fixture-4eec1d51-c897-4b8f-a5e5-fb4e4b6f4942/receipt.json`
- ตรวจ PE identity เป็น Sandbox และ clipboard shortcut contract เดิมผ่าน
- delivery/rollback receipt: `zig-out/usb-loss-20261120/delivery.json`
- EXE ใหม่ที่ลงจริงเปิด guest ConPTY และวาดข้อความไทยผ่าน ปิดเฉพาะหน้าต่างทดสอบแล้ว VM ยัง ready: `zig-out/a-launch-recovery-91adc27a-8862-40ec-bd00-401be621deb7/recovered-native-usb-close-installed-20261120-1155.json`

probe รอบแรกไม่ผ่านเพราะ bare GDI window ที่อยู่นอกจอไม่ได้รับ paint อัตโนมัติ และพบ closing hook เดิมถูกเรียกซ้ำจาก defer หลัง WM_CLOSE แก้ harness ให้ invalidate/UpdateWindow จริง และแก้ fallback cleanup ไม่เรียกซ้ำแล้ว ไม่ลด assertion หรือถือว่าผลเก่าผ่าน

นี่เป็น synthetic USB-loss proof กับ shipping EXE และ actual-installed normal-open proof ไม่ใช่ physical USB qualification ไม่ได้ถอด USB จริงขณะ VM ทำงาน

## วิธีทดสอบซ้ำและขอบเขตการดูแลต่อ

1. รอ free Windows commit ให้พอ ไม่ปิดแอป/VM ผู้ใช้เอง เริ่ม build เต็มเมื่อ preflight เหลืออย่างน้อย 4 GiB หลัง setup และหยุดเฉพาะ compiler ที่เปิดเองหากต่ำกว่า 1 GiB
2. ตรวจ source/build receipts และ hashes ก่อน build ซ้ำ ถ้ามี source เปลี่ยนจาก snapshot ให้ตรวจ diff และทดสอบใหม่ ไม่เขียนทับงานคนอื่น
3. รัน `zig-out/usb-loss-20261120/build.ps1` ใช้ recipe และ D: caches เดียวกับ shipping baseline เดิม แบบ `-j1` ไม่เพิ่ม renderer/images/optimization flags โดยเดา
4. รัน `node tools/windows/sandbox/verify-storage-loss.cjs` หลังมี shipping prefix ครบ ต้องยืนยันว่า original artifact ไม่หายหลัง matching event และ candidate หาย รวม native paint, negative events และ owned child cleanup
5. ถ้า harness ล้ม ให้แยกปัญหาการส่ง system message/fixture ออกจาก product ก่อน อย่าทดสอบโดยถอด USB จริงหรือปิด VM ผู้ใช้
6. ตรวจ PE metadata/clipboard contract และ SHA256 แล้วเปลี่ยนเฉพาะ executable ที่เป็นเจ้าของงานนี้ในแพ็กจริง เก็บ rollback ห้ามวาง factory archive ทับ Data หรืออัปเดต App ทั้งชุดโดยไม่จำเป็น
7. ตรวจไฟล์ EXE ที่ติดตั้งจริงกับ build และทดสอบเปิดผ่าน entrypoint จริงแบบนอกจอโดยไม่หยุด VM ที่ใช้อยู่ หน้าต่างเก่าที่ยังเปิดอยู่ใช้โค้ดเก่าจนผู้ใช้เปิดใหม่ อย่าปิดงานผู้ใช้เองเพื่ออัปเดต

ข้อจำกัดคงเดิม: Windows ต้องยังประมวลผล notification/timer ได้ การถอดดิสก์อาจทำให้ VM/data เสียหายได้ และ feature นี้ไม่ได้เพิ่ม desktop sandbox, browser IDE, Tailscale mapping, global configuration หรือสิทธิ์ commit/push
