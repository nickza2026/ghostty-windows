# สำรวจข้อจำกัดด้านข้อมูล: Sandbox บน MacBook Pro M2 Pro

สำรวจวันที่ 20 พฤศจิกายน 2569 ก่อนเริ่ม implementation บน Mac

## ข้อสรุปและขอบเขต

ทำระบบเก็บข้อมูลที่เสถียรบน Mac ได้ แต่ **APFS, VM และคำว่า portable ไม่ได้ทำให้ข้อมูลทน crash, backup ได้ครบ หรือไม่ออกจากเครื่องโดยอัตโนมัติ**

baseline ที่เสนอคือ **Data บน APFS ภายใน Mac, Linux ARM64 ใหม่, หนึ่ง VM ต่อหนึ่ง Data root และ backup ขณะ VM หยุดจริง** ยังไม่เริ่มจาก USB ข้าม Windows/Mac, live migration หรือ live backup

รายงานนี้มีหลักฐานสามประเภท:

- **เอกสารต้นทาง:** Apple, QEMU และ Cursor ที่เปิดอ่านจากเว็บสาธารณะ
- **source ปัจจุบัน:** โค้ด Windows ใน checkout นี้ ใช้หา requirement และจุดที่ต้องออกแบบใหม่ ไม่ใช่หลักฐานว่า macOS ทำงานแล้ว
- **ข้อเสนอ/เงื่อนไขทดสอบ:** ยังไม่ได้ implement หรือรันบน M2 Pro จริง

ไม่ได้อ่านบัญชี/keys ของผู้ใช้ ไม่เชื่อม Mac หรือ guest จริง ไม่เปลี่ยน filesystem/permissions และไม่เริ่ม port ในการสำรวจนี้ branch ส่งมอบรวมเอกสารกับ Windows experimental development baseline สำหรับศึกษา/port ต่อ ไม่รวมข้อมูลบัญชี runtime ที่ดาวน์โหลดหรือ build caches และไม่ใช่หลักฐานว่า Mac implementation พร้อมแล้ว

## 1. ต้องนับข้อมูลมากกว่าดิสก์ VM

| กลุ่มข้อมูล | ตำแหน่ง/พฤติกรรมเป้าหมาย | สิ่งที่ต้องรักษาหรือควบคุม |
| --- | --- | --- |
| Linux boot/data disk | Data root บน APFS ที่เลือกชัดเจน | guest home, source code, Git work, databases, Node packages และบัญชีที่ติดตั้งใน guest |
| Firmware variables/instance configuration | Data root ของ instance | ARM UEFI state และข้อมูลที่ทำให้ boot/ระบุ instance เดิมได้ ถ้า backend ใช้ไฟล์เหล่านี้ |
| Immutable runtime/base image | runtime manifest ที่ pin รุ่นและ hash | ต้องกู้หาได้ตรงเวอร์ชัน ห้าม updater เขียนทับ base ที่ดิสก์เก่ายังอ้างอยู่ |
| Host SSH/authentication material | private profile ที่ออกแบบสำหรับ Mac | encryption/unlock, permissions, agent lifetime และ host-key verification |
| IDE profile และ remote server | แยก host กับ guest | Cursor UI/profile อยู่ฝั่ง Mac; server/tools อยู่ใน guest ไม่ถือว่าทุกอย่างอยู่ใน VM |
| Logs, screenshots, pasted images, cache และ temporary files | app-owned storage ที่กำหนดขอบเขต | อาจมีเนื้อหาโครงการ/คำสั่ง/ข้อมูลลับ ต้องกำหนด retention และไม่ใส่ทั้งหมดในรายงานโดยอัตโนมัติ |
| Backup/export | ปลายทางที่ผู้ใช้อนุมัติแยกจาก working data | ต้องครอบคลุมข้อมูลและ dependencies ที่ restore ต้องใช้ พร้อมป้องกัน secrets ใน backup |

layout เช่น `~/Sandbox-Mac/Data/macos-arm64` เป็นเพียงข้อเสนอให้เห็นขอบเขตง่าย ยังไม่มีการสร้างโฟลเดอร์นี้บน Mac ไม่ย้าย mutable Data เข้า signed `.app` และไม่ fallback ไปสร้าง Data ใหม่ใน home/temporary directory เมื่อ root เดิมเข้าไม่ได้

## 2. ข้อจำกัดที่กระทบความถูกต้องของข้อมูลโดยตรง

### 2.1 Backup เฉพาะ Data อาจไม่ครบ

source ปัจจุบัน `tools/windows/sandbox/prototype.cjs` สร้าง `Data/guest.qcow2` โดยมี backing file `../Runtime/base/debian.qcow2` ดังนั้น overlay ไม่ใช่สำเนาดิสก์เต็มที่พกไฟล์เดียวแล้วใช้แทนกันได้ [Q1]

ถ้า backup เฉพาะ overlay หรือ updater แทนที่ base ด้วยไฟล์ใหม่ชื่อเดิม อาจเปิดไม่ได้หรืออ่านชุดข้อมูลที่ไม่ตรงกัน แม้ไฟล์ overlay ยังอยู่ครบ การ rollback เฉพาะ EXE ก็ไม่ย้อนการเปลี่ยนแปลงใน guest disk

**ข้อเสนอสำหรับ Mac รุ่นแรก:** พิจารณา standalone guest disk ที่ไม่มี backing chain เพื่อลดความซับซ้อนของ backup/restore แลกกับพื้นที่สร้าง/เก็บเพิ่ม ถ้ายังคง overlay ต้องมี immutable versioned base และ export ที่ครอบคลุม chain, firmware state และ metadata จริง การเลือกนี้ต้องตกลงก่อน implement ไม่แอบเปลี่ยน Data Windows

### 2.2 Backup ระหว่างรันไม่เท่ากับ backup ที่กู้แอปได้แน่นอน

QEMU เตือนว่าอย่าใช้ `qemu-img` แก้ image ที่โปรเซสอื่นใช้อยู่ เพราะอาจทำลาย image และแม้แต่ query ก็อาจพบสถานะไม่สอดคล้อง [Q1]

การคัดลอกไฟล์ VM ขณะทำงาน, APFS clone หรือ filesystem snapshot ไม่ได้ยืนยันว่า buffers ใน guest/application ถูก flush แล้ว Database หรือไฟล์หลายชุดอาจต้องทำ recovery หลัง restore

**baseline:** normal shutdown ของ guest, ตรวจ QEMU ออกและ disk ownership/lock ถูกปล่อยจริง แล้วจึง export พร้อม manifest/hash ไปปลายทางใหม่ การปิดหน้าต่าง terminal ไม่ใช่หลักฐานว่า VM หยุด

หาก normal stop ค้าง ให้แสดงว่า backup ยังไม่พร้อม ไม่ force-stop เพื่อทำให้ปุ่ม backup สำเร็จ การเพิ่ม live backup ต้องมี quiesce/transaction protocol และ restore tests แยกต่างหาก

### 2.3 Snapshot บน SSD เดิมไม่ใช่สำเนาแยกเครื่อง

Apple ระบุว่า Time Machine local snapshots อยู่บน Mac และใช้กู้เมื่อ backup disk ไม่อยู่ Snapshots ใช้พื้นที่ตามเงื่อนไขและอาจถูกเอาออกเมื่อระบบต้องการพื้นที่ [A2]

จึงไม่ใช้ local snapshot เป็น backup เพียงชุดเดียว หาก SSD/เครื่องเสีย สำเนาที่อยู่บนอุปกรณ์เดียวกันก็ไม่ใช่การป้องกันอุปกรณ์สูญหาย ต้องมี backup แยกปลายทางและทดลอง restore

Time Machine ช่วย backup ไฟล์ของ Mac แต่เอกสารนั้นไม่ได้รับรอง guest/application-consistent snapshot ของ QEMU การเลือก Time Machine ไม่ยกเลิกเงื่อนไข cold backup ของ baseline นี้ [A1, Q1]

### 2.4 พื้นที่ว่างมีหลายความหมาย

ต้องแยกอย่างน้อย:

- virtual capacity ของ guest disk
- filesystem free space ภายใน guest
- physical allocation ของ image บน host
- host volume/container space ที่จัดสรรได้จริง รวมผลของ snapshots/quotas
- พื้นที่ชั่วคราวสำหรับดาวน์โหลด, แตกไฟล์, upgrade, export และ restore

source Windows เรียก resize ของ virtual disk เป็น `8G` นี่ไม่ใช่พื้นที่ host ที่จองไว้แน่นอน และไม่ใช่ข้อกำหนดความจุของ Mac ที่ตกลงแล้ว ต้องตรวจ partition/filesystem ภายใน guest ด้วย

การลบ `node_modules` ใน guest ไม่รับรองว่า qcow2/host allocation จะหดเท่ากันทันที ต้องทดสอบ discard/trim และ format/backend ที่เลือกจริง ไม่รัน compact/repair ตอน VM ยังใช้งานอยู่ [Q1, Q2]

Apple นับพื้นที่ local snapshots บางส่วนเป็น available และมี API แยก available capacity ตามประเภทการใช้ ดังนั้นค่าในหน้าจอ Storage ไม่ใช่ reservation ที่รับรองว่าจะเขียน VM/backup ได้จบ [A2, A3]

**ข้อเสนอ:** preflight จากงานที่จะทำจริง ไม่ตั้งเลขพื้นที่ขั้นต่ำโดยเดาเผื่อทุกเครื่อง กำหนด budget/ขอบเขตขนาด guest และ runtime caches และมี test กรณี host/guest เต็มระหว่างเขียนด้วย ข้อเสนอ quota ต้องได้รับอนุมัติก่อนสร้าง/ปรับ APFS volume

มีความเสี่ยงที่แอปจะรายงานผิดว่า VM ค้าง: QEMU documentation ที่ตรวจระบุ `werror=enospc` เป็น default และอาจ pause VM เมื่อ host disk เต็ม ขณะที่ source `policy.cjs` ไม่กำหนด error policy เอง ต้อง pin และทดสอบ QEMU รุ่น Mac จริง แล้วแยก paused-for-I/O/full-disk จาก crashed/stale ไม่แก้ด้วย auto restart หรือ force-stop [Q3]

manager/console logs ใน source เปิด append และหมุนชื่อเก็บตามการ boot ยังไม่พบ retention/capacity policy ในส่วนที่ตรวจ จึงต้องรวม logs/cache/backup ใน data budget ไม่คิดเฉพาะ guest disk

### 2.5 Atomic rename ไม่ใช่หลักฐานว่า power loss ปลอดภัย

`runtime-cli.cjs` มีการเขียน temporary manager state แล้ว rename เป็นไฟล์ปัจจุบัน ซึ่งลดปัญหาผู้อ่านเห็น JSON ครึ่งไฟล์ แต่จากโค้ดส่วนนี้อย่างเดียวไม่พิสูจน์ durability หลัง host crash/power loss

Mac adapter ต้องกำหนด durable-save/flush protocol, recovery จากการเขียนไม่จบ และ owner-generation checks ของตัวเอง โดยไม่ลบ state/lock ของ VM ที่ยังมีชีวิตหรือไม่ทราบสถานะเพื่อให้ startup ผ่าน

ห้ามใช้ image cache mode ที่ละเลย flush เพื่อทำให้ benchmark ดูเร็ว แล้วอ้างว่าทน crash เท่าเดิม ต้องตรวจ semantics ของ QEMU รุ่น/backend จริง [Q2]

`writeback` ไม่เท่ากับ `unsafe`: เอกสาร QEMU อธิบาย flush/error policy ต่างกัน ต้องรักษาความแตกต่างนี้ ไม่สรุปว่า cache ทุกชนิดปลอดภัยเท่ากันหรือปิด flush ทั้งหมด [Q3]

### 2.6 Sleep, crash, unplug และ permission denial คนละเหตุการณ์

เมื่อปิดฝา/เครื่อง sleep อาจเกิด pause/resume และ transport timeout ต้องตรวจ owner/VM จริงหลัง resume ไม่ใช้เวลาของไฟล์หรือ SSH timeout เป็นหลักฐานว่า VM ตาย

ถ้าเข้า Data ไม่ได้เพราะ permission หรือ volume ไม่พร้อม ให้คง Data และหยุด operation ไม่สร้าง profile เปล่าทับ ไม่ reset known hosts และไม่ถือเป็นการติดตั้งใหม่

USB-loss ในอนาคตต้องอ้าง volume identity ของ Data/package จริง ไม่ปิดเมื่อไดรฟ์อื่นถูกถอด และไม่ force-stop VM อัตโนมัติ การซ่อน terminal ไม่ป้องกันการเสียหายของ storage ที่ถูกดึงออก

## 3. ข้อจำกัด APFS และตำแหน่งเก็บ

### APFS-first ไม่ได้แปลว่าไม่มีข้อจำกัด

ใช้ APFS ภายใน Mac เป็น baseline ลดความเสี่ยงจากสาย/USB power และแยกปัญหาออกจาก exFAT แต่ยังมีกรณี disk full, host crash, controller failure, permission และ backup ที่ต้องทดสอบ

ก่อนเลือก volume ต้องตรวจ case sensitivity, space sharing และ quota/reserve ของ volume จริง ไม่อนุมานจากคำว่า APFS อย่างเดียว

Apple ระบุว่า volumes ใน APFS container ใช้ free space ร่วมกัน; Reserve Size และ Quota Size เป็นคุณสมบัติของ volume ที่กำหนดแยกได้ การสร้างโฟลเดอร์ Data จึงยังไม่ได้สร้าง quota หรือรับรองพื้นที่ให้แอป [A5, A6]

Linux guest แยกชื่อ `Name` กับ `name` ได้ การ export กลับ host volume ที่ไม่แยกตัวพิมพ์ต้องตรวจชื่อชนกันก่อน copy ไม่เขียนทับโดยเงียบ เช่นเดียวกับ file permissions, symlinks และ extended metadata ที่ข้าม filesystem

### ไม่วาง active VM disk ใน cloud-sync folder เป็น baseline

Apple อธิบายว่า optimized storage อาจเก็บไฟล์ใน iCloud และดาวน์โหลดต้นฉบับเมื่อจำเป็น [A4] Active VM ยังต้องการ local, predictable storage และ exclusive ownership

ดังนั้น baseline ที่เสนอตัด iCloud Drive, Desktop/Documents ที่ sync และ live-sync folder อื่นออกจาก working Data root เพื่อไม่เพิ่มความเสี่ยงจาก offload, conflict copy หรือเปิด image ชุดเดียวจากหลายเครื่อง นี่เป็นนโยบายความเสถียรที่เสนอ ไม่ใช่ข้อกล่าวอ้างว่า Apple ห้าม VM บนทุก cloud folder

backup/export ที่ปิดจบและตรวจแล้วอาจส่งไปปลายทาง sync ได้ภายใต้นโยบาย encryption/retention ที่อนุมัติ ไม่ใช้การ sync image ที่ยังเขียนอยู่เป็น backup protocol

### หนึ่ง writer ต่อหนึ่ง Data root

สอง app instances หรือสอง Mac ห้ามเปิดดิสก์เดียวกัน read-write พร้อมกัน ต้องมี exclusive ownership/locking และตรวจ reference chain ไม่เลือก force-share หรือข้าม lock เพราะคิดว่าเป็นไฟล์ค้าง [Q2]

ถ้ามีการย้าย root หรือ restore ต้อง resolve root และ bindings ใหม่อย่างชัดเจน ไม่เดาว่า path เดิมที่กลับมามีไฟล์คือ instance เดิมเสมอ ส่วน transport/agent socket ของ Darwin มีข้อจำกัด path ที่ต้องทดสอบกับชื่อไทย, spaces และ path ยาวด้วย

### Signed app, path relocation และสิทธิ์ของ macOS

Apple ระบุว่า signed bundles ควรถูกถือเป็น read-only และ Gatekeeper อาจรันแอปที่ดาวน์โหลดมาจากตำแหน่ง read-only ที่ไม่ได้ระบุแน่นอน ดังนั้นการนำ path ของ executable มาต่อ `../Data` อย่างเดียวไม่ใช่การ resolve persistent root ที่เชื่อถือได้ทุกกรณี [A7]

ให้ใช้ Data root ที่ผู้ใช้เลือก/ยืนยันและตรวจ identity ได้ แยกจาก `.app` ที่อัปเดต เป้าหมาย APFS ภายในช่วยให้เริ่มจากกรณีง่าย แต่ยังต้องทดสอบ package ที่ดาวน์โหลดมาจริงและ signing identity ของรุ่นแจก

Apple แยก persistent Application Support จาก reproducible caches และมีสิทธิ์ Files & Folders รวมถึง policy สำหรับ removable/network volumes; path ที่มีอยู่ไม่ได้รับรองว่าโปรเซสเข้าถึงได้ [A8, A9, A10]

ชื่อผลิตภัณฑ์ Sandbox ไม่ได้เปิด Apple App Sandbox entitlement ให้อัตโนมัติ และไม่ใช่เหตุผลให้ขอ Full Disk Access ตั้งแต่แรก ถ้าถูกปฏิเสธสิทธิ์ ให้รายงานเหตุและรักษา Data ไม่เปลี่ยนไปเขียนที่อื่นเงียบ ๆ

หากใช้ disk-space API ที่อยู่ในกลุ่ม required-reason API ต้องตรวจ declaration/reason ใน `PrivacyInfo.xcprivacy` ตามแพลตฟอร์มและช่องทางแจกจริงด้วย Apple เตือนไม่ให้ใช้ API นี้เพื่อ fingerprint ผู้ใช้ [A3]

## 4. การเข้ารหัส บัญชี และข้อมูลที่ออกนอก VM

### FileVault ไม่ใช่ app isolation

แยกข้อกำหนดการป้องกันข้อมูลขณะเครื่องปิด/สูญหาย ออกจากสิทธิ์ของโปรเซสและผู้ใช้เมื่อ Mac ปลดล็อกแล้ว การอยู่บน encrypted startup volume ไม่ได้ป้องกันทุกโปรเซสที่ได้รับสิทธิ์เข้าถึงไฟล์

Apple ระบุว่า internal storage ของ Apple Silicon มีการเข้ารหัสอยู่แล้ว แต่เมื่อเปิด FileVault การป้องกัน key จะรวม user credentials กับ hardware UID ไม่ใช่ข้อพิสูจน์ว่าไฟล์ที่ copy ไป USB/NAS ถูกเข้ารหัสต่อให้ และรูปแบบการป้องกัน removable storage ไม่เหมือน internal Secure Enclave storage [A11]

qcow2 เป็น disk format ไม่ใช่คำรับรอง encryption: create flags ใน source Windows ที่ตรวจไม่ได้เปิด image encryption เอง ข้อนี้ไม่ใช่ผลตรวจสถานะ encryption ของดิสก์จริงของผู้ใช้ เพราะไม่ได้อ่านดิสก์/keys นั้น

หากสำเนาถูกส่งออกไป external disk/NAS/cloud ต้องตรวจ encryption ของปลายทางนั้นด้วย ไม่ถือว่า FileVault ของ SSD ภายในติดไปกับไฟล์ที่ copy ออกไปโดยอัตโนมัติ Time Machine มีตัวเลือก Encrypt Backup และต้องเก็บรหัสสำหรับ restore เอง [A1]

การลบไฟล์ไม่ได้รับรองว่าไม่มีสำเนาใน backup, snapshots, cache หรือระบบปลายทาง อย่าแสดงข้อความ secure erase โดยไม่มี implementation/threat model ที่รองรับ

### Credentials และ Keychain ต้องมีแผน restore

ต้องเลือกก่อนว่าจะผูก secret กับกลไกของ Mac เครื่องนั้น หรือใช้ encrypted per-package store ที่ผู้ใช้ปลดล็อก การ copy Data ไม่ใช่หลักฐานว่าย้าย Keychain/สิทธิ์/secret มาได้ครบ และห้ามเลือก plaintext fallback เพื่อให้ย้ายเครื่องง่าย

ไม่เหมารวมว่า Keychain ทุกชนิดย้ายไม่ได้: Apple มีวิธีย้าย keychains บางประเภทพร้อมรหัสเดิม แต่ระบุว่า copy passwords จาก Local Items หรือ iCloud Keychain ด้วยวิธีคัดลอก keychain ไม่ได้ [A12] แผนกู้เครื่องใหม่ต้องระบุวิธีที่เลือกจริงและมี recovery test

backup อาจมี private keys, tokens, guest account state, history และ configuration ที่ยังใช้สิทธิ์ได้จริง ต้องจำกัดสิทธิ์/encrypt และไม่ใส่ใน factory package, Git, support logs หรือ screenshot โดยอัตโนมัติ

restore tests ใช้ fixture data ที่เป็นเจ้าของหรือได้รับอนุมัติ แยก network/provider access เพื่อไม่ให้บัญชี/งานอัตโนมัติที่คืนกลับมาทำงานจริงระหว่างทดสอบ

### Cursor Remote SSH ไม่ใช่คำรับรองว่าข้อมูลอยู่ใน VM เท่านั้น

remote workspace อยู่ใน guest ได้ แต่ Cursor UI/extensions/profile และข้อมูลบางชนิดอยู่ฝั่ง host ตามการตั้งค่า เมื่อใช้ AI จะมีข้อมูลส่งผ่านบริการที่เกี่ยวข้อง

หน้า Data Use ของ Cursor ระบุว่าแม้ใช้ API key ของตัวเอง requests ยังผ่าน backend ของ Cursor และ Privacy Mode เกี่ยวข้องกับการใช้/เก็บข้อมูล ไม่ใช่โหมด offline [C1]

จึงต้องแยกข้อตกลง host-local, guest-local และ cloud/provider ก่อนนำโครงการลับเข้าใช้งาน ไม่ทดลองเรียก AI เพื่อพิสูจน์ data isolation และไม่ถือว่า settings ของ Cursor Windows ได้ย้าย/ใช้กับ Mac แล้ว

## 5. รูปแบบ backup/restore ที่เสนอสำหรับรุ่นแรก

1. รับ normal-stop ของ instance ที่ถูกต้อง รอ VM ออกจริงและปล่อย disk lock ถ้าไม่จบให้รายงาน incomplete ไม่ force
2. สร้าง export ใหม่ข้างนอก working root ไม่เขียนทับ backup ที่ผ่านล่าสุดระหว่าง export
3. รวม writable disks, firmware variables, instance/profile/config และ immutable dependencies ที่ต้องใช้ หรือ manifest ที่ยืนยันว่ากู้ dependency รุ่นเดิมได้จริง
4. บันทึก format/schema, host/guest architecture, runtime versions, files/hashes และเวลา backup; hash ตรวจ integrity ไม่ใช่ encryption
5. ตรวจ completeness ก่อน publish ชุด backup ให้ผู้ใช้/backup service เห็นว่า complete เก็บ error ของ failed export ไม่ใช้ receipt เก่าตัดสินว่ารอบใหม่สำเร็จ
6. restore ลง root ใหม่ที่เป็น fixture ตรวจ boot, project/Git data, dependency binding และ normal stop โดยไม่เขียนทับต้นฉบับ
7. ทดสอบแผนกู้โดยไม่มีเครื่องเดิม/Keychain เดิมตามขอบเขตที่เลือก ก่อนบอกว่าย้ายเครื่องได้

ความถี่, จำนวนรุ่น, ปลายทาง, encryption และ RPO/RTO ยังไม่ได้ตกลง ห้ามอ้างว่าระบบ backup อัตโนมัติหรือกู้ย้อนหลังได้ตามเวลาหนึ่งจนกำหนดและทดสอบแล้ว

## 6. Gates ก่อนเรียกว่าเสถียรบน M2 Pro

| การทดสอบที่ต้องมี | ผลที่คาดหวัง |
| --- | --- |
| first-use/fresh root และเปิดใหม่ | instance/profile/disk เดิมยังถูกต้อง ไม่ reset เมื่อพบ error |
| write → normal stop → reopen | ไฟล์และ Git state คงอยู่ ตรวจด้วย marker/hash ของรอบนั้น |
| host/guest low-space และ write failure | ไม่อ้าง backup/save สำเร็จ ไม่เขียนทับชุดที่ผ่านล่าสุด ไม่ล้าง lock ของ live owner |
| duplicate launch | มี writer เดียว ไม่มี force-share และไม่มี VM ตัวที่สองแอบใช้ดิสก์เดียวกัน |
| owned fixture crash/recovery | แยก manager ตายจาก QEMU ยังอยู่ ไม่ repair image ที่กำลังใช้ |
| sleep/wake | resolve owner/agent/transport โดยไม่สร้าง instance ใหม่หรือหยุด VM ผิดตัว |
| backup แล้ว restore ลง root ใหม่ | boot และอ่านข้อมูลตัวอย่างได้ครบ รวม dependencies; ต้นฉบับไม่เปลี่ยน |
| runtime/app upgrade และ rollback | base/schema ไม่ถูกแทนที่โดยไม่เข้ากัน; rollback binary ไม่แสร้งย้อน data |
| root ไทย/spaces/ย้ายตำแหน่ง | path/socket/profile binding ถูกต้อง หรือปฏิเสธพร้อมเหตุผล ไม่ fallback ไป host profile |
| permission denial | ไม่สรุปว่า Data หาย ไม่ขอ Full Disk Access เหมาเพื่อแก้ปัญหา |
| data inventory/privacy | ระบุ host/guest/backup/provider data ที่เกิดขึ้นจริง และตรวจไม่มี credentials ใน logs/export สาธารณะ |
| USB/exFAT | เป็น qualification รอบถัดไป ไม่ใช้ผล APFS ภายในแทน |

ทั้งหมดนี้เป็นแผนทดสอบ ไม่ได้รันกับ APFS/M2 Pro ใน session Windows นี้ ไม่ทดสอบด้วยการเติม SSD จริงจนเต็มหรือถอดดิสก์ที่มี VM/account จริง

## 7. สิ่งที่ต้องยืนยันก่อน implementation

- macOS/Xcode ที่เครื่อง M2 Pro ใช้จริง, RAM และพื้นที่ว่าง/volume format ของ root ที่จะเลือก
- source code อย่างเดียวหรือรวมฐานข้อมูล/keys/บัญชีที่ต้องกู้ได้; threat model ที่ต้องป้องกัน
- ปลายทาง backup ที่ผู้ใช้มีและยอมรับ, encryption/unlock และเวลาย้อนหลัง/ข้อมูลสูญหายที่รับได้
- ขอบเขตข้อมูลที่ยอมให้ IDE/AI ส่งออก และจะใช้ host profile ใหม่หรือของเดิม

**ข้อเสนอเริ่มต้น:** ยังไม่ทำ USB portability, ย้ายบัญชี, live backup หรือ automatic data migration เริ่มจาก local APFS + explicit Data root + single writer + cold export/restore ที่ตรวจได้ก่อน

## แหล่งอ้างอิงที่เปิดอ่าน

เอกสาร Apple อาจเลือก macOS รุ่นล่าสุดเป็นค่าเริ่มต้น ต้องตรวจรายละเอียดกับ macOS ที่ติดตั้งบน M2 Pro จริง โดยไม่อนุมานเมนู/สิทธิ์จากคนละรุ่น

- **[A1]** [Apple: Back up your Mac with Time Machine](https://support.apple.com/en-us/104984) — external backup, Encrypt Backup และรหัสที่ใช้ restore
- **[A2]** [Apple: About Time Machine local snapshots](https://support.apple.com/en-us/102154) — local snapshot, available storage และการเก็บตามพื้นที่
- **[A3]** [Apple Foundation: volumeAvailableCapacityForImportantUsageKey](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey) — available-capacity API; อ่านเนื้อหาจาก structured documentation ไม่ถือว่า HTML shell ที่ HTTP200 เป็น discussion
- **[A4]** [Apple: Optimize storage space on your Mac](https://support.apple.com/guide/mac-help/optimize-storage-space-sysp4ee93ca4/mac) — cloud/on-demand storage
- **[A5]** [Apple: File system formats available in Disk Utility](https://support.apple.com/guide/disk-utility/file-system-formats-dsku19ed921c/mac) — APFS, case sensitivity และ space sharing
- **[A6]** [Apple: Add, delete, or erase APFS volumes](https://support.apple.com/guide/disk-utility/add-delete-or-erase-apfs-volumes-dskua9e6a110/mac) — Reserve Size และ Quota Size
- **[A7]** [Apple TN2206: macOS Code Signing In Depth](https://developer.apple.com/library/archive/technotes/tn2206/_index.html) — read-only signed bundles และ Gatekeeper path isolation
- **[A8]** [Apple: File System Basics](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html) — persistent app data กับ caches; ใช้ส่วน macOS ไม่ยกกฎ iOS backup มาปน
- **[A9]** [Apple: Control access to files and folders](https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac) — สิทธิ์เข้าถึงโฟลเดอร์
- **[A10]** [Apple: Privacy Preferences Policy Control payload](https://support.apple.com/guide/deployment/privacy-preferences-policy-control-payload-dep38df53c2a/web) — removable/network volumes และ All Files; อ้างอิงชนิดสิทธิ์ ไม่ได้เสนอให้ deploy MDM
- **[A11]** [Apple Platform Security: Volume encryption with FileVault](https://support.apple.com/guide/security/volume-encryption-with-filevault-sec4c6dc1b6e/web) — Apple Silicon, FileVault และ removable storage
- **[A12]** [Apple: Copy keychains](https://support.apple.com/guide/keychain-access/copy-keychains-kyca1121/mac) — ขอบเขตของการย้าย keychain
- **[Q1]** [QEMU: qemu-img](https://www.qemu.org/docs/master/tools/qemu-img.html) — live-image warning, backing files, convert/check/repair
- **[Q2]** [QEMU: Disk Images](https://www.qemu.org/docs/master/system/images.html) — disk formats, snapshots, cache/locking semantics; ต้องเทียบ QEMU รุ่นที่เลือกจริง
- **[Q3]** [QEMU: Invocation](https://www.qemu.org/docs/master/system/qemu-manpage.html) — `cache`, `werror` และ disk-full behavior
- **[C1]** [Cursor: Data Use & Privacy Overview](https://cursor.com/data-use) — backend dataflow และข้อจำกัดของ Privacy Mode

source ที่สำรวจ: `tools/windows/sandbox/prototype.cjs` (prepare/backing disk/profile/normal shutdown), `policy.cjs` (disk/network/SSH arguments), `runtime-cli.cjs` (state saves/manager lifecycle), `storage-policy.cjs` และ manager recovery helpers ผล Windows ไม่ยืนยัน Darwin implementation
