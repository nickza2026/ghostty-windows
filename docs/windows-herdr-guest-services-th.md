# Herdr และ Web เป็น service ภายใน Linux guest

คู่มือนี้ใช้กับ guest ที่ติดตั้งชุด `sandbox-herdr-*` แล้ว ไม่ได้หมายความว่า
ZIP Sandbox ทุกชุดมี Herdr หรือ service เหล่านี้ติดตั้งมาให้

## ขอบเขต

- `sandbox-herdr-native.service` รัน native Herdr ด้วยบัญชีและ HOME เดิม
- `sandbox-herdr-web.service` รัน source checkout เดิมผ่าน
  `bun start --runtime=herdr --vm-forward=18787`
- ทั้งคู่เป็น **systemd user services ใน guest** ไม่ใช่บริการ Windows
  ไม่เปิด VM เองตอน Windows เริ่มทำงาน
- เมื่อเปิด VM แล้ว user manager ที่เปิด linger สามารถเริ่ม service ที่ enable
  ไว้ได้โดยไม่ต้องเปิด terminal ค้าง เมื่อปิด VM บริการก็หยุดตาม
- Web ใช้ `http://127.0.0.1:18787` บน Windows ผ่าน mapping ของแพ็ก
  ไม่ใช่ guest loopback `127.0.0.1:8787` และไม่ได้เปิดให้ LAN เข้าถึง

## บัญชีและ AI

service ไม่เปลี่ยน HOME ไม่สร้างบัญชีใหม่ และไม่ย้ายประวัติหรือข้อมูล provider
native service สร้าง config แยกที่ตั้ง
`session.resume_agents_on_restore = false` โดยตรวจความหมาย TOML ว่าคีย์อื่น
ตรงกับ config หลักเดิมทั้งหมด ไม่เขียนทับ config หลัก

การเริ่ม native service ไม่ใช่คำสั่งให้ resume AI pane อัตโนมัติ
การสั่งเริ่ม AI ใหม่ด้วยตนเองในภายหลังยังเป็นการกระทำของผู้ใช้

## ดูสถานะและจัดการ

รันคำสั่งต่อไปนี้ **ใน Linux guest** ไม่ใช่ PowerShell ของ Windows:

```sh
systemctl --user status sandbox-herdr-native.service sandbox-herdr-web.service
systemctl --user is-enabled sandbox-herdr-native.service sandbox-herdr-web.service
loginctl show-user "$USER" -p Linger
```

หยุดหรือเปิดเฉพาะ Web โดยไม่หยุด native:

```sh
systemctl --user stop sandbox-herdr-web.service
systemctl --user start sandbox-herdr-web.service
```

การ restart native กระทบ Web ที่ผูก dependency ไว้ด้วย ควรทำเมื่อไม่มีงาน
ใน native ที่กำลังใช้งานอยู่:

```sh
systemctl --user restart sandbox-herdr-native.service
```

ดู log ของบริการใน guest:

```sh
journalctl --user -u sandbox-herdr-native.service -u sandbox-herdr-web.service -n 80
```

log อาจมีข้อมูลส่วนตัวของแอป ไม่ควรคัดลอกทั้งไฟล์เพื่อเผยแพร่

## การป้องกัน state ค้าง

runner ตรวจ native RPC ก่อนแจ้งพร้อม และรอ readiness banner จาก Web
process ที่เพิ่งเริ่มจริง ไม่ใช้ไฟล์ log เก่าเป็นหลักฐาน
การ restart มีขอบเขต retry ของ systemd ไม่ใช่การเริ่มซ้ำไม่จำกัด

Web control socket ที่ไม่ทราบที่มายังคงทำให้เริ่มไม่ผ่าน ไม่มีการลบทิ้งหรือ
kill process จาก PID ที่พบ ส่วน socket ที่มี receipt ระบุ inode/owner/เวลา
ตรงกับ invocation เก่าของ service เอง จะย้ายเก็บได้เฉพาะเมื่อการเชื่อมต่อ
ยืนยันว่าไม่มี listener และตรวจ identity ซ้ำแล้วยังตรง

ไฟล์ config, marker หรือ receipt ที่เป็น symlink รวมถึง dangling symlink
ถือเป็น collision และเก็บไว้ ไม่เขียนทับเพื่อฝืนให้เริ่มได้

ก่อนถอดไดรฟ์ ให้หยุด VM ตามปกติด้วย `Stop-Sandbox.cmd` ของแพ็กและรอให้หยุด
บริการภายใน guest ไม่ได้ทำให้การถอดไดรฟ์ขณะ VM ใช้งานดิสก์ปลอดภัย
