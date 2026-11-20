# Linux + Node/npm — portable sandbox ต้นแบบ

แพ็กนี้เป็นแพ็กใหม่ แยกจาก SDK เดิม ไม่ใช่แพตช์ให้แตกทับแพ็กที่มี Data อยู่แล้ว
ไม่มีบัญชี SSH key รหัสผ่าน หรือข้อมูลโปรเจกต์สำเร็จรูปในไฟล์ดาวน์โหลด

host ต้องมี WHPX และ CPU ที่รองรับ SSSE3/SSE4.1/SSE4.2 รุ่นโค้ดปัจจุบันเปิด flags
เหล่านี้ให้ guest โดยตรงและหยุดหาก host ไม่รองรับ ไม่ใช้ `-cpu host` ของ KVM/HVF
และไม่สลับไป software emulation ให้อัตโนมัติ ค่า CPU ใหม่มีผลเมื่อหยุดและเปิด VM ใหม่
การอัปเดตแพ็กเดิมไม่ต้องรีเซ็ต Data แต่ต้องบันทึกงานและหยุด VM ตามปกติก่อน

## เริ่มใช้

1. แตก ZIP ลงโฟลเดอร์ใหม่และเก็บทั้งโฟลเดอร์ไว้ด้วยกัน หากใช้ exFAT ให้เปิด `Enable-ExFAT.cmd` และตอบ Y หลังอ่านข้อจำกัด
2. เปิด `Open-Terminal.cmd` ครั้งแรกจะให้ตั้งรหัสผ่าน Linux สำหรับ sudo ในหน้าต่างนั้น ไม่ใช่รหัส Windows และไม่ต้องส่งรหัสผ่านในแชต
3. รอเตรียม Linux/Node ครั้งแรก เมื่อเห็น `sandbox@portable-sandbox` จึงเป็น shell ใน guest
4. หยุด VM ด้วย `Stop-Sandbox.cmd` ก่อนย้ายแพ็กหรือถอดไดรฟ์ ปิดหน้าต่าง terminal อย่างเดียวไม่ได้ปิด VM

ภายใน guest มี Node 24.22.1 พร้อม npm/npx ไม่มี Letta, Herdr, Git, make หรือ g++ ติดตั้งล่วงหน้า
ยังมีระบบปฏิบัติการ, SSH, Python 3, sudo, firewall, CA certificates และเครื่องมือระบบที่จำเป็น
Node ฝั่ง Windows เป็นตัวควบคุม VM ไม่ใช่ Node สำหรับงานพัฒนา และไม่ใช้ global Node/npm หรือบัญชีเดิมของเครื่อง
แพ็กบางลงโดยไม่รวม QEMU executable ของสถาปัตยกรรมอื่น แต่ยังเก็บ DLL และ firmware ของชุด runtime

## ติดตั้งโปรแกรมเอง

ทำภายใน Linux prompt:

```sh
node --version
npm --version
sudo apt update
sudo apt install git
# เมื่อแพ็กเกจ npm ต้อง compile native addon:
sudo apt install build-essential python3
# เมื่อต้องการ Letta Code:
npm install -g @letta-ai/letta-code
```

npm global ของผู้ใช้เก็บใน `~/.local` และอยู่ใน PATH ข้อมูลใน guest รวมโปรแกรมที่คุณลงเองคงอยู่เมื่อหยุด/เปิดใหม่
ไม่มีการติดตั้ง Letta/Herdr/Git กลับให้อัตโนมัติหรือถอนโปรแกรมที่คุณลงเองในรอบถัดไป
บัญชีปกติคือ sandbox UID 1000; sudo ขอรหัสผ่าน Linux, ไม่ใช่ NOPASSWD ไม่เปิด root SSH หรือ SSH password login

## เปิดเว็บใน guest จากเครื่องแม่

ตั้งค่าไว้หนึ่งคู่: **เครื่องแม่ `127.0.0.1:18787` → guest TCP `8787`**
เมื่อคุณติดตั้ง Herdr Web หรือ web app ให้ฟัง `0.0.0.0:8787` **ภายใน guest** แล้วเปิด
`http://127.0.0.1:18787` บนเครื่องแม่ การฟังเฉพาะ `127.0.0.1` ใน guest จะไม่รับการ forward นี้
แพ็กไม่ได้ติดตั้งหรือรัน Herdr Web ให้เอง และไม่ใช้ service เดิมที่ port 8787 บนเครื่องแม่

host listener ผูกเฉพาะ loopback ไม่เปิด LAN/อินเทอร์เน็ตหรือแก้ Tailscale/Windows firewall ให้อัตโนมัติ
localhost ไม่ได้จำกัดเฉพาะ Windows user เดียว แอปเว็บต้องมี authentication ของตัวเองเมื่อต้องการป้องกันผู้ใช้อื่นในเครื่อง
คู่ port อยู่ใน `guest-profile.json`; เปลี่ยนได้เฉพาะตอน VM หยุดและต้องไม่ชน port ของโปรแกรมอื่น ไม่มีการปิดโปรแกรมอื่นเพื่อแย่ง port

## ขอบเขต sandbox และข้อมูล

ไม่มี shared folder/clipboard หรือ SSH agent forwarding เข้าสู่ guest และไม่คัดลอกบัญชี/agent/memory ของ Windows
การ paste ข้อความเป็นการส่งข้อมูลเข้า guest โดยเจตนา ข้อมูลทั้งหมดใน VM อยู่ใน `Data` ของแพ็ก ไม่ใช่การรับประกันว่า Windows/OS จะไม่สร้าง cache ใด ๆ บน C:
sudo ให้สิทธิ์ root **ภายใน guest** เท่านั้น แต่ root แก้ firewall ภายใน guest ได้ จึงไม่ใช่ sandbox สำหรับมัลแวร์ที่มี root
เก็บทั้ง `Runtime/base` และ `Data/*.qcow2` ทุกไฟล์ backing chain อย่าคัดลอกเฉพาะ guest.qcow2

## Copy ข้อความออกไป Windows

เลือกข้อความที่แสดงในหน้าต่าง terminal ฝั่ง Windows แล้วสั่ง Copy ของหน้าต่างนั้น
Windows Terminal ใช้ `Ctrl+Shift+C`; Console/CMD แบบเดิมใช้เมนูแถบชื่อ Edit → Mark
เลือกข้อความแล้วกด Enter จากนั้นวางในโปรแกรมบน host ด้วย `Ctrl+V`
อย่ากด `Ctrl+C` โดยไม่มีข้อความที่เลือกหากไม่ต้องการส่งคำสั่งหยุดไปยังโปรแกรมใน guest

การ Copy ข้อความที่ผู้ใช้เลือกเองไม่ใช่ clipboard sync: guest ยังอ่าน/เขียน clipboard
ของ Windows อัตโนมัติผ่าน OSC 52 ไม่ได้

NTFS ตรวจ owner/ACL ตามเดิม; exFAT ต้องยอมรับ reduced protection และทุก cold start ผ่าน restricted bootstrap ใหม่
exFAT ไม่มี ACL แยกผู้ใช้ ผู้เข้าถึงไดรฟ์อาจอ่าน/แก้โปรแกรม, VM, private key, trust records, manager token และ hash รหัสผ่าน Linux
agent ส่วนตัวไม่เพิ่ม encryption ให้คีย์ และไม่ป้องกันโปรแกรมอื่นของ Windows user เดียวกัน
ไม่เผยแพร่ `Data` หรือแพ็กที่ตั้งบัญชี/รหัสผ่านแล้ว รหัสผ่านถูกเก็บเป็น salted hash ไม่ใช่การเข้ารหัสดิสก์

ต้นแบบนี้ไม่ใช่ WIN-RUNTIME-004/cycle12 fix หรือการรับรอง native GUI/GPU/DPI, ข้ามเครื่อง, USB hot-unplug/ไฟดับ หรือ provider chat จริง
ดูสถานะผลทดสอบที่มากับการส่งแพ็ก ไม่ตีความการมีไฟล์หรือ version probe ว่า GUI ผ่านแล้ว
