# Native Sandbox Preview สำหรับ Windows

## ไฟล์ที่จะเปิด

แพ็กคือ `zig-out/Sandbox-Native-Preview.zip` แตก ZIP ลงโฟลเดอร์ใหม่บน NTFS
แล้วเปิด **`Sandbox.exe` ที่อยู่ข้างโฟลเดอร์ `App` และ `Runtime`**
อย่าแตกทับ `A:\sandbox` หรือโฟลเดอร์ที่มี Data/บัญชีใช้งานอยู่แล้ว
ต้องเก็บ EXE, App, Runtime และ share ไว้ด้วยกัน ไม่ย้ายเฉพาะ EXE

SHA256 ของ ZIP แต่ละรุ่นอยู่ใน `native-package.json` ของชุด build และข้อความส่งมอบ
ไม่ใช้ checksum ของ preview รุ่นก่อนแทนไฟล์รุ่นใหม่

แอปหลักเป็น native Win32 terminal ไม่ได้เปิด CMD เป็นหน้าต่างหลัก
backend ใช้ private Windows Node/QEMU ของแพ็ก ส่วน shell ที่ได้เป็น Linux ใน VM
เครื่องต้องผ่าน WHPX/CPU/memory preflight ของแพ็ก ไม่มีการเปิด Windows feature,
ติดตั้ง driver หรือเปลี่ยน global environment ให้อัตโนมัติ

## เปิดครั้งแรก

1. เปิด `Sandbox.exe`
2. ตั้ง **Linux sudo password ใหม่** แล้วกรอกยืนยันใน terminal ของแอป
   ช่องกรอกแสดง `*` ไม่ใช่รหัสผ่าน Windows และไม่ต้องส่งรหัสผ่านในแชต
3. รอ guest เริ่มทำงาน ครั้งแรกต้องใช้อินเทอร์เน็ตดาวน์โหลด Node จากแหล่งที่ pin ไว้
4. เมื่อเห็น `sandbox@portable-sandbox:~/workspaces$` ใช้ shell ได้

guest เป็นผู้ใช้ `sandbox` UID 1000, HOME `/home/sandbox`, พื้นที่งานเริ่มที่
`/home/sandbox/workspaces` และ Node รุ่น `v24.22.1`
นี่คือ Node-only guest ไม่ได้ติดตั้งหรือล็อกอิน Letta, Herdr หรือ provider CLI ให้แล้ว

แพ็กส่งมอบไม่มี Data ที่เคยเปิดใช้ รหัสผ่านที่ตั้งไว้ บัญชี provider หรือ private SSH key
ข้อมูลของชุดนี้จะเกิดใน `Data` ข้าง EXE หลังเริ่มใช้ ไม่ใช่การนำบัญชีจากเครื่อง Windows
หรือจากแพ็กเดิมเข้ามา Windows เองยังอาจใช้ system DLL/font/cache/pagefile บน C:
จึงไม่ใช่การรับรองว่าไม่มีร่องรอยระบบปฏิบัติการบน C:

## คัดลอกและวางข้อความ

- ลากเลือกข้อความแล้วกด `Ctrl+C` เพื่อคัดลอก เมื่อไม่มีข้อความที่เลือก
  ปุ่มเดิมส่ง interrupt เข้าโปรแกรมใน terminal ไม่ได้คัดลอกข้อความทั้งหน้าจอ
- `Ctrl+V` วางข้อความจาก Windows เข้า terminal; `Ctrl+Shift+C` และ
  `Ctrl+Shift+V` ยังใช้ได้ คลิกขวาคัดลอกข้อความที่เลือก ไม่ใช่ปุ่มวาง
- เป็นการสั่งคัดลอก/วางด้วยผู้ใช้ ไม่เปิด clipboard sync อัตโนมัติหรือเปลี่ยน
  สิทธิ์อ่าน/เขียน clipboard ของโปรแกรมใน guest

ชุดทดสอบคีย์ลัดใช้ native handler, Core และ ConPTY จริงกับ clipboard จำลอง
ผ่านข้อความไทย/อีโมจิ โดยไม่อ่านหรือเขียน clipboard จริงของผู้ใช้

## ปิดหน้าต่างกับหยุด VM เป็นคนละอย่าง

**ปิด terminal หรือพิมพ์ `exit` เป็นการ disconnect เท่านั้น VM ยังรันอยู่**
เปิด EXE อีกครั้งเพื่อเชื่อมต่อกลับ ไม่ต้องล้าง Data

เมื่อต้องการตรวจสถานะหรือหยุด VM ให้เปิด PowerShell ในโฟลเดอร์แพ็กแล้วใช้:

```powershell
.\Sandbox-Status.cmd
.\Stop-Sandbox.cmd
```

`Stop-Sandbox.cmd` ขอ normal shutdown ของชุดนั้น ไม่ใช่หยุด VM อื่น
รอให้หยุดสำเร็จก่อนย้ายโฟลเดอร์แพ็ก ถอดไดรฟ์ หรือสำรอง/ย้าย Data
อย่าลบ Data/manager state หรือใช้ Task Manager ฆ่าตาม PID เก่าเพื่อแก้ error

ถ้า first boot ดาวน์โหลด Node หมดเวลา ให้เก็บ Data และข้อความผิดพลาดไว้
อย่ารีเซ็ตดิสก์เพื่อแก้ network error รุ่นนี้มีการทดสอบเริ่มต่อจาก owned fixture
หลัง download timeout โดยไม่ล้าง Data แล้ว แต่ไม่ได้รับประกันเครือข่ายทุกสภาพแวดล้อม

## ผลทดสอบและขอบเขต preview

ผล Linux ด้านล่างเป็น baseline ก่อนปรับคีย์ลัด clipboard ส่วน EXE รุ่นคีย์ลัดใหม่
ผ่าน native Core/ConPTY กับ clipboard จำลองตามหัวข้อคัดลอกและวางข้อความ
ยังไม่ใช้ผลนั้นแทนการตรวจ clipboard จริงของผู้ใช้หรือ Linux SIGINT ใน EXE ใหม่

- EXE→ConPTY→private Node→Linux PTY รับคำสั่งจริง พร้อม stdin/stdout TTY 103×31 ผ่าน
- output ภาษาไทย/สีถูก parse และวาดเป็นภาพจริงผ่าน offscreen native window
- terminal จบเอง, manager เดิมยังอยู่, normal stop/restart และข้อมูลทดสอบคงอยู่ผ่าน
- ตั้งรหัสผ่านภาษาไทยในหน้าต่าง native, masking, hash และ raw-mode restoration ผ่าน
  ใน setup-only fixture ที่ไม่มี VM
- factory เดิมยังไม่เคย boot และไม่มี Data หลังทดสอบ โดยใช้สำเนาแยกทั้งหมด

การตั้งรหัสผ่านและ VM boot ทดสอบแยกกัน ยังไม่ถือเป็นผล combined first-use→boot
หรือ physical keyboard/IME/numpad, GPU/DPI/multi-monitor, native exFAT และ human acceptance
ไม่มีการทดสอบ login provider หรือย้ายบัญชีจริงในงานนี้

รายละเอียดวิศวกรรมและไฟล์หลักฐานอยู่ใน `windows-native-sandbox-exe-plan-th.md`
