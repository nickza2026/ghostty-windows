# Linux VM sandbox — ต้นแบบ

1. เปิด `Open-Terminal.cmd` แล้วรอ Linux prompt ประมาณ 20–30 วินาทีเมื่อเตรียม SDK แล้ว
2. คำสั่งและโปรเจกต์ทำงานใน Linux ที่ `/home/sandbox/workspaces` ไม่ใช่ Windows shell
3. `Open-IDE.cmd` เปิด VS Code ฝั่ง Windows ด้วย private profile เพื่อทำงานผ่าน Remote SSH
4. ปิดหน้าต่าง terminal ไม่ได้ปิด VM; ใช้ `Stop-Sandbox.cmd` เพื่อปิดตามปกติ
   `Force-Stop-Sandbox.cmd` เป็นการตัดไฟที่ต้องสั่งเองและอาจทำข้อมูลเสียหาย
5. ดูสถานะด้วย `Sandbox-Status.cmd`

ติดตั้งใน guest: Node 24.22.1, Herdr 0.9.5, Letta Code 0.34.23 และ Git
บัญชี/agent/memory เดิมบน Windows ไม่ได้ถูกนำเข้า ต้องตั้งค่าบัญชีใหม่ภายใน guest เมื่อต้องการใช้จริง
ไม่มี shared drive, shared clipboard, Windows SSH agent forwarding หรือ host-shell fallback
การ paste ข้อความโดยผู้ใช้ยังเป็นการส่งข้อมูลเข้า guest โดยเจตนา

เก็บและย้าย **ทั้งโฟลเดอร์แพ็ก** รวม `Runtime/base` และ `Data/*.qcow2` ทุกไฟล์
guest disk อาจอ้าง backing image; ห้ามย้ายเฉพาะไฟล์ `guest.qcow2` หรือถอน backing files ออกจากแพ็ก
อย่า commit/อัปโหลด `Data` ที่มี private keys, บัญชี หรือข้อมูลจริง

ต้นแบบนี้ผ่าน headless guest/SSH, Herdr pane API, persistence และ NTFS same-volume relocation
ไม่ใช่ผลรับรอง native keyboard/GUI, VS Code GUI connection, provider chat จริง หรือความปลอดภัยจากช่องโหว่ทุกชนิด
ยังไม่รับรองการย้ายข้ามเครื่อง/volume; ผล CLI บน exFAT อยู่ในหัวข้อด้านล่าง
WHPX และ Windows OpenSSH client ต้องมีอยู่ก่อน
ไม่มีการเปิด Windows feature, ติดตั้ง driver หรือย้ายบัญชีให้อัตโนมัติ

## โหมด exFAT — reduced protection แบบเลือกเปิด

ค่าเริ่มต้นใช้ NTFS และตรวจเจ้าของ/ACL ตามเดิม โหมด exFAT เปิดโดย `Enable-ExFAT.cmd`
และตอบ Y เพื่อยอมรับข้อจำกัดของแพ็กนี้เท่านั้น ไม่เปลี่ยน policy หรือสิทธิ์ของทั้งไดรฟ์
การยอมรับเก็บใน `portable-storage.json` ที่ portable root; ไม่ย้ายข้อมูลแอปไป C: หรือ host AppData

exFAT ไม่มี ACL แยกผู้ใช้ ผู้ที่เข้าถึงไดรฟ์ได้อาจอ่านหรือแก้โปรแกรมในแพ็ก, ดิสก์ VM, SSH keys,
trust records และ manager token จึงอาจคัดลอกข้อมูลหรือควบคุม VM ได้ โหมดนี้ไม่เหมาะกับ
การฝากข้อมูลลับบนไดรฟ์ที่ผู้อื่นเข้าถึงได้ การกลับไปใช้ NTFS ไม่เพิกถอนสำเนาคีย์/ข้อมูลที่อาจถูกคัดลอกแล้ว

โหมดนี้ยกเว้นเฉพาะ owner/DACL บน filesystem ที่ตรวจพบว่าเป็น exFAT จริง หลังยอมรับเท่านั้น
บน NTFS ยังคงตรวจเจ้าของ/ACL และให้ Windows OpenSSH โหลดคีย์ตามเดิม แม้มีไฟล์ยอมรับโหมด exFAT
reparse guard, host-key pin, firewall และ restricted bootstrap ยังทำงาน ไม่มีการยกระดับ Administrator ให้อัตโนมัติ

Windows OpenSSH บนเครื่องทดสอบปฏิเสธ private key ที่อยู่บน exFAT โปรแกรมจึงใช้ **agent ส่วนตัวของแพ็ก**
สำหรับโหมดนี้เท่านั้น คีย์ Ed25519 ตัวเดิมยังเก็บใน `Data/ssh/client_key` ไม่ถูกย้ายไป C:/AppData
โปรแกรมตรวจรูปแบบและคู่ public/private key แล้วทดสอบลายเซ็นกับ Windows OpenSSH ก่อนเปิด VM
agent ถือคีย์ในหน่วยความจำตลอดอายุ manager; ไม่ได้เปลี่ยนเป็นคีย์ใหม่ทุก boot และไม่ใช้ Windows agent เดิม
คีย์บนไดรฟ์ยังไม่ได้เข้ารหัสเพิ่มจากการใช้ agent

ช่องทาง agent เป็น local named pipe ที่กำหนดสิทธิ์เฉพาะ Windows user ปัจจุบันกับ SYSTEM
และปฏิเสธ remote clients ไม่ forward agent เข้า guest และไม่เพิ่มคีย์เข้า global agent
ไม่ได้ป้องกันโปรแกรมอื่นที่ทำงานด้วย Windows user เดียวกันหรือผู้ดูแลเครื่อง
ใช้ Windows PowerShell/.NET ที่มีอยู่ โดยเก็บไฟล์ชั่วคราวของ helper ใน `Data`; ไม่มีการติดตั้ง service หรือ driver เพิ่ม

ทุก cold start บน exFAT ต้องผ่าน restricted bootstrap ใหม่ภายใต้ manager เดียวก่อนเปิด runtime
จึงอาจรอนานกว่าโหมด NTFS ปิดด้วย `Stop-Sandbox.cmd` ให้เสร็จก่อนย้ายโฟลเดอร์/ถอดไดรฟ์
หากคู่คีย์ไม่ตรง, agent เริ่มไม่ได้ หรือ Windows client ทดสอบลายเซ็นไม่ผ่าน โปรแกรมหยุดก่อนเปิด VM
ไม่เปลี่ยนไปใช้คีย์/agent/profile เดิมของ Windows เครื่องนั้นแทน

ผลทดสอบ 14 พ.ย. 2026 บน Windows + exFAT จริงภายใน VHDX ที่สร้างทิ้งได้:
- native SSH สองรอบ อ่านข้อมูลภาษาไทย SHA256 เดิมหลังหยุด–เปิดใหม่และย้ายชื่อโฟลเดอร์ไทย+ช่องว่าง+apostrophe
- `Open-Terminal.cmd` บนโฟลเดอร์ที่ย้ายแล้ว เข้า Linux Bash ด้วย redirected stdin ที่รอ prompt ก่อนส่งคำสั่ง
- สาม cold starts ผ่าน restricted bootstrap ใหม่ทุกครั้ง; bootstrap/runtime รวม 6 ครั้งจบด้วย QEMU exit 0

ผลนี้ไม่ใช่ native keyboard/GUI หรือ VS Code GUI acceptance, provider chat, การย้ายข้ามเครื่อง/volume
หรือการทดสอบถอด USB/ไฟดับกะทันหัน ตัวแพ็กยังเป็นต้นแบบ ไม่ใช่การรับรอง exFAT ทุกอุปกรณ์
