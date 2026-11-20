# Git สำหรับ Letta ใน portable-data

## ปัญหาที่จำลองได้

Letta ต้องเรียก executable `git` ระหว่างเริ่มต้น แต่ strict PATH ของแพ็กมีเฉพาะ shims/Node/npm/Windows จึงได้ `spawn git ENOENT` แม้เครื่องจะมี Git ที่อื่น การเพิ่ม Herdr อย่างเดียวไม่ได้แก้ dependency นี้

จำลองด้วย Node ตัว bundled และ `child_process.spawnSync('git', ['--version'])` บน strict PATH ได้ `error=ENOENT`, `status=null` โดยไม่ต้องเปิด Letta, สร้าง agent, ล็อกอิน หรือเรียก provider จริง

## ตำแหน่งและขอบเขต

- เก็บ **full PortableGit พร้อม Bash** ทั้งแพ็กใต้ `bin/portable-data/runtimes/git` รวม DLL, Git helpers และ notices/licenses ไม่ย้ายแค่ EXE; MinGit ไม่พอสำหรับ memory hooks ของ Letta
- เก็บ native-entry proxy ที่ `bin/portable-data/shims/git.exe` ซึ่งอยู่ใน strict PATH เดิมแล้ว ไม่ต้อง build Zig ใหม่
- proxy คำนวณ runtime จากตำแหน่งตัวเอง ไม่อ้างอิง path ของเครื่อง จึงตามการย้ายทั้งแพ็กได้
- ไม่ใช้ `.cmd` แทน executable เพราะ Node ที่ spawn โดยไม่ผ่าน shell ต้องเรียก EXE ได้จริง
- ไม่ใช้ host Git เป็น fallback ไม่แก้ Registry, User/Machine PATH, Git config เครื่อง หรือบัญชีเดิม
- ตัวติดตั้งเพิ่ม runtime/proxy/metadata และค่า trust แบบจำกัดใน `.gitconfig` ของ private HOME สองชุดเท่านั้น ไม่คัดลอก home, auth, provider หรือประวัติของ Letta และไม่แก้ Git config ของบัญชี Windows
- ไม่อ้างว่า Git ผ่านแล้วเท่ากับ Letta/provider ใช้งานครบ ต้องแยก Git boundary, isolated startup และบัญชีจริงออกจากกัน

ใช้ official PortableGit 2.56.0.windows.4 แบบ pin URL/version/SHA256 ไม่รัน SFX หรือ post-install command ของ archive ตรวจชื่อ/type/size ด้วย Windows tar แล้วแตกด้วย official standalone 7zr 26.05 ที่ตรวจ SHA256 และเก็บใน `bin/portable-data/runtimes/git-bootstrap` ด้วย Windows tar อ่านรายการได้แต่แตก LZMA lc=8 ของรุ่นนี้ไม่ได้ ไฟล์ที่มีอยู่แต่ผิดปกติต้อง fail closed ไม่ซ่อมทับข้อมูลเงียบ ๆ

## exFAT และ ownership ของความจำ Letta

exFAT ไม่บันทึกเจ้าของไฟล์ Git จึงอาจปฏิเสธ memory repo ด้วย `detected dubious ownership` หลังย้ายไป A: ไม่ใช่หลักฐานว่า repo เสียหาย ตัวติดตั้งเพิ่ม `safe.directory` เฉพาะ `.letta/local/memfs/*` ใน private HOME ของ native terminal และ Herdr แยกกัน ไม่ใช้ `safe.directory=*` ไม่อนุญาตทั้งไดรฟ์หรือ workspace และไม่แก้ host global config

ค่าที่เก็บเริ่มด้วย `%(prefix)` อ้างอิง prefix ของ bundled Git แล้วตามตำแหน่งแพ็กใหม่อัตโนมัติ จึงไม่ hardcode A:/D: ก่อนเขียนจะให้ Git expand ค่าแล้วตรวจว่าตรงกับ memfs ใน private HOME ที่กำหนดเท่านั้น ค่าอื่นของ config คงอยู่และมี backup ข้างไฟล์ private เดิมถ้าไฟล์มีอยู่แล้ว เรียกซ้ำไม่เพิ่มค่าซ้ำ การเปลี่ยน layout/pin ของ Git ต้องทดสอบ prefix นี้ใหม่

ทดสอบกับ repo สังเคราะห์บน exFAT จริง: ก่อนตั้งค่าถูกปฏิเสธ หลังตั้งค่าสร้าง memory commit และ agent ID ใหม่ได้ ส่วน repo นอก memfs ยังถูกปฏิเสธ ทดสอบ config เดิมกับ Git อีก package root พร้อมบังคับ different-owner ใน **test เท่านั้น** เพื่อยืนยัน relocation แล้วรัน Letta จริงใน profile สังเคราะห์บน exFAT จนมี initial memory commit โดยไม่ใช้ provider/บัญชีจริง ดู `portable-git-ownership-test.cjs` และโหมด `--portable-ownership` ของ startup test

## การตรวจสอบ

ชุดทดสอบ `tools/windows/portable-git-integration-test.ps1` ผ่านกับ official ZIP ที่ตรวจ SHA256 แล้ว ใช้ Node bundled เรียก `git` โดยไม่ผ่าน shell: version, init/status, cwd, binary stdin, Unicode/quotes/backslashes, stderr/exit code, missing-runtime/no fallback, cancellation และย้ายทั้งแพ็กชื่อไทย/มีช่องว่าง ตรวจว่า Git ลูกถูก kill ตาม proxy เมื่อ Node ยกเลิกงาน รวม recovery ของ metadata-only install ที่ขาดช่วงและการรักษา unknown proxy ไม่ทับเงียบ ๆ

`tools/windows/portable-git-negative-test.ps1` ผ่าน 12 กลุ่ม synthetic ZIP/hash/reuse/tamper/reparse โดยไม่รัน binary ปลอม ไม่เรียก network/provider และไม่ใช้ repo หรือ credentials จริง Layout ของ pin นี้เป็น `ucrt64` ไม่ใช่ `mingw64`; ตรวจจาก ZIP จริงก่อนกำหนด required files และรักษา `LICENSE.txt` พร้อม notices/dependencies ทั้งหมด

source ของ packager แนบ `Install-Portable-Git.cmd` และ support โดย `Run.cmd`/normal `Run-Herdr.cmd` ทำ Git setup เมื่อ runtime/proxy ยังขาด Diagnostic `Run-Herdr.cmd --version`/`--install-only` ไม่ trigger Git download และหาก setup ล้มต้องหยุด ไม่เปิด app ด้วย host fallback

เพิ่มการทดสอบ full Git hook จริงใน repo สังเคราะห์: Bash array → private Node → nested Git → initial commit โดยไม่ skip hook และไม่มี remote ไม่ใช่ commit งานใน project

หลังผู้ใช้ให้ทำต่อ อัปเดตเฉพาะแพ็กส่งมอบที่ระบุชัดเจน `zig-out/portable-packages/localterm-herdr-portable-20261028` โดยตรวจ factory launcher hashes ก่อนเพิ่ม Git/CLI ไม่ถือว่าเป็นการแก้ Herdr ตัวหลักบน C: หรือย้ายบัญชีจากแพ็กอื่น ติดตั้ง Letta 0.34.23 ที่ `bin/portable-data/npm` ด้วย bundled Node, configs เปล่าและ cache ส่วนตัว ตรวจ published patcher ก่อนรันเฉพาะ patcher นี้ ไม่รัน lifecycle scripts ของ dependency

actual Letta ผ่าน startup ใน genuine headless ConPTY ด้วย profile/repo สังเคราะห์: สร้าง local agent และ memory `.git` พร้อม initial commit ผ่าน hookจริง เปิดถึง prompt `No model selected` แล้ว Ctrl-C ออกด้วย exit 0 ใช้ allowlisted env และ test-only Node transport/child-process guards บล็อก fetch/external DNS/connection และ browser; ไม่ใช่ OS sandbox และไม่ได้ส่งข้อความหรือใช้ credentials จริง API duration/usage เป็น 0 พบ warning `AttachConsole failed` จาก node-pty cleanup helper ของตัวทดสอบหลังปิด ConPTY แยกจาก app initialization ซึ่งผ่าน ไม่อ้างว่าได้ทดสอบ paint/GPU หรือบัญชี/providerจริง

เก็บผลที่ `zig-out/portable-tools-evidence/portable-git-20261028` ล้างเฉพาะ NPM cache ที่พิสูจน์ว่าเกิดใน install window นี้ 312,195,852 bytes เก็บ CLI และ small logs ไว้ การ install NPM ถัดไปจะดาวน์โหลดใหม่ ไม่ใช่การล้าง cache เครื่องหรือบัญชี
