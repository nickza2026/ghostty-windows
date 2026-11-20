# Node-only portable Linux sandbox — ผลตรวจ 15 พฤศจิกายน 2026

แพ็กที่ตรวจ: `zig-out/sandbox-node-candidate-20261115-ebdfc56b/sandbox-node-portable-20261115.zip`

- ZIP 555,241,887 bytes; หลังแตก public factory 1,061,369,185 bytes ก่อนสร้าง Data
- SHA256: `532beebff9f7cf412a9bce9673bee63e98d6d65ae98e4ccf13c9a370fcacfcf3`
- ใช้ App snapshot 21 ไฟล์ตาม `factory.json` และ `native-proof.json` ในไดเรกทอรีเดียวกัน
- factory ไม่เคย boot/ตั้งรหัส/ลงบัญชี; ZIP ไม่มี Data, key, hash รหัสผ่าน หรือบัญชีสำเร็จรูป
- การทดสอบใช้สำเนาที่แตกจาก ZIP ไม่ใช่ส่ง guest ที่ผ่านการตั้งค่าแล้ว

## ผลที่รันจริง

1. regression suite 112/112 ผ่าน ไม่มี skip: `node --test tools/windows/sandbox/*.test.cjs` (บน PowerShell ส่งรายการไฟล์จาก Get-ChildItem)
2. native Windows ConPTY แบบ headless ไม่เปิด/แย่ง focus ของหน้าต่าง: stdin/stdout เป็น TTY จริง
3. Windows ConPTY → SSH framed stream → Linux PTY: 129×41 → 91×33, ส่ง resize, Ctrl-C, exit code 7 และคืน raw mode ของ host สำเร็จ
4. guest shell UID 1000, HOME `/home/sandbox`, Node `v24.22.1`; ก่อนติดตั้งเครื่องมือทดสอบไม่พบ Git, Herdr, Letta, g++ หรือ make
5. wizard รหัสผ่านภาษาไทยผ่าน native console: ไม่ echo plaintext, ไฟล์ตั้งค่าไม่มี plaintext และคืน raw mode
6. SHA512crypt 100,000 rounds เทียบกับ libcrypt ใน Linux ตรงกัน; sudo แบบไม่มีรหัสไม่ผ่าน และส่งรหัสสังเคราะห์ที่ตั้งไว้แล้วผ่านจริง
7. npm global prefix `/home/sandbox/.local`; ติดตั้งและเรียกแพ็ก local สังเคราะห์ด้วยผู้ใช้ธรรมดาแบบ offline โดยไม่ใช้ sudo และยังเรียกได้หลังหยุด/เปิด VM ใหม่
8. HTTP จาก host `127.0.0.1:18787` ไป Node server ใน guest `0.0.0.0:8787` ตอบ nonce ของรอบนี้จริง ไม่ใช่ response เก่า
9. ทั้งสอง cold starts จบด้วย normal stop; รอบตรวจ TUI เพิ่มเติมก็ normal stop ไม่ใช้ force-stop
10. Letta Code `0.34.23` initial TUI จริงในสำเนา guest แสดงเป็นหลายคอลัมน์ที่ความกว้าง 129 ไม่ใช่ทีละตัวลงบรรทัด มีหัวข้อ `No model selected`, เมนู `/model`, `/connect` และ input prompt; ออกด้วย Ctrl-C exit 0

Letta/Git/build-essential ถูกติดตั้งเฉพาะใน guest ทดสอบเพิ่มเติม ไม่ได้อยู่ใน ZIP/factory การตรวจ TUI ใช้ HOME ใหม่ ไม่มี key/provider จริง และปิด TCP ขาออกที่ไม่ใช่ loopback ก่อนเปิด UI ไม่มีการส่งข้อความให้โมเดลหรือใช้เครดิต provider

หลักฐาน TUI รอบแรกเป็น false-negative ของ harness เพราะ command echo มีข้อความ `printf REAL_LETTA_RETURN_%s` ไม่ใช่ layout ล้มเหลว เก็บ screen ก่อนแก้ไว้แล้ว ทวนใหม่โดยเริ่มวัดหลัง execution marker แยกตัวเลข exit จริงออกจาก printf echo และตรวจ process exit สำเร็จ กรณี parser หนึ่งคอลัมน์มี regression test แยก

## สิ่งที่ยังไม่รับรอง

- ผล native ของ snapshot Node-only นี้เป็น **NTFS**; ยังไม่ทดสอบ snapshot นี้บน exFAT VHD รอบใหม่ กำลังรออนุญาต UAC สำหรับ VHD ชั่วคราว ไม่ได้ใช้ผล exFAT CLI ของ snapshot เก่าแทน
- ไม่ใช่การรับรอง native Ghostty/Herdr renderer, GPU, DPI, on-screen human acceptance, ข้ามเครื่อง, power loss หรือ hot-unplug
- ไม่ใช่ provider chat/login จริง และไม่มีการย้ายบัญชี/agent/memory ของ host
- WIN-RUNTIME-004 และ cycle12 ยังไม่ถูกปิดด้วยงานนี้

## ดาวน์โหลดและเริ่มใช้

API บนเครื่องนี้ `http://127.0.0.1:8787/api/fs/file` ส่ง ZIP ครบและ SHA ตรง แต่ HTTPS `nick.tailbd0a76.ts.net` จากเครื่องตรวจ timeout ทั้ง Node และ Windows curl จึงยังไม่อ้างว่าลิงก์ระยะไกลพร้อมใช้งาน ไม่มีการเปลี่ยน auth, TLS หรือ Tailscale เพื่อฝืนให้ผ่าน

คู่มือใน ZIP คือ `START-HERE-TH.md` แตกลงโฟลเดอร์ใหม่ ไม่ทับแพ็ก/Data เดิม ใช้ `Open-Terminal.cmd` ตั้งรหัส Linux ของตนเอง หากต้องใช้ exFAT ให้แยกผลทดสอบที่ยังรออนุญาตข้างต้นออกจากการยอมรับ reduced protection ด้วย `Enable-ExFAT.cmd`
