# Linux VM แบบเก็บข้อมูลถาวรบน Windows — ต้นแบบ

> ยังเป็นต้นแบบระหว่างการตรวจรับ ไม่ใช่แพ็กที่รับรองพร้อมใช้งานหรือแก้ WIN-RUNTIME-004 แล้ว
> โฟลเดอร์ทดสอบ: `zig-out/sandbox-prototype-20261112-1450`
> ไม่มีการ commit/push, ย้ายบัญชีเดิม, แก้แพ็กบน `A:`, เปิด Windows feature หรือติดตั้ง driver

## ขอบเขตที่ตกลงกัน

- Windows เป็นเครื่องแสดงผล terminal/IDE; คำสั่งงานพัฒนาให้รันใน Linux guest
- Node, Herdr, Letta, โปรเจค และข้อมูลบัญชีของ **guest** อยู่ใน virtual disk ถาวร
- ไม่ mount `C:`, `D:`, Windows HOME/Desktop, clipboard หรือ SSH agent เข้า guest
- ไม่ใช้ Windows shell เป็นทางสำรองเมื่อ VM/SSH เปิดไม่ได้
- IDE ภายนอกเชื่อมด้วย Remote SSH; ไม่ต้องมีสำเนาโปรเจคบน host เพื่อแก้ไฟล์ใน guest
- ไม่ย้ายบัญชี/agent/memory/provider จากเครื่องเดิมอัตโนมัติ การเชื่อม provider ใหม่ต้องทำใน guest ภายหลัง

Windows 11 Home เครื่องนี้ตอบ `WHvGetCapability(HypervisorPresent)` สำเร็จ (`0x00000000`, present=true)
โดยไม่ต้องเปลี่ยน Windows จึงเลือก WHPX ไม่เปิด Windows Sandbox/WSL/Hyper-V feature เพิ่ม
เครื่องอื่นต้องผ่าน preflight ของตัวเอง ไม่มีการรับรองว่า Windows Home ทุกเครื่องพร้อมเหมือนกัน

## ผังข้อมูล

```text
Open-Terminal.cmd ── private launcher ── Windows OpenSSH ── Linux guest shell
Open-IDE.cmd ─────── private VS Code profile ── Remote SSH ── guest workspace
                                    │
                              QEMU + WHPX
                                    │
                         Data/guest.qcow2 (persistent)
                         /home/sandbox/workspaces
                         /home/sandbox/.letta
                         /home/sandbox/.local
```

`HOME` ปกติของผู้ใช้ Linux คือ `/home/sandbox` จึงไม่ต้องชี้ Herdr ไปหา Windows portable folder
เพราะ Herdr และลูก process อยู่ใน guest อยู่แล้ว ไม่มี Windows Desktop profile ให้ fallback ไปใช้

ไฟล์บน host แบ่งเป็น:

| ที่เก็บ | หน้าที่ |
|---|---|
| `Runtime/qemu` | โปรแกรม QEMU ที่ถอดจาก archive ไม่รัน installer |
| `Runtime/node` | Node ของตัวควบคุม VM บน Windows ไม่ใช่ Node ที่รันโปรเจคใน guest |
| `Runtime/base/debian.qcow2` | base image ที่ตรวจ hash แล้ว ใช้เป็น backing image |
| `App` | snapshot ของ launcher/bootstrap source พร้อม SHA256 |
| `Data/guest.qcow2` | overlay เก็บ Linux, โปรแกรมและข้อมูลใช้งานของ guest |
| `Data/seed.img` | NoCloud seed แบบ readonly; ไม่มี private SSH key/provider token |
| `Data/ssh` | คู่กุญแจใหม่เฉพาะ VM, host-key pin และ SSH config เฉพาะแพ็ก |
| `Data/ide` | profile/extensions ของ IDE client ภายนอก แยกจาก IDE profile เดิม |
| `Build` | archive/checksum/provenance และ partial download ของต้นแบบ |

ตัว terminal/IDE/SSH client และตัวควบคุม VM ยังเป็น Windows process นอก VM ไม่ใช่การย้าย Windows ทั้งระบบลง guest
การไม่ mount host drive ไม่ใช่การรับรองว่า client/driver/hypervisor ไม่มีช่องโหว่

## ปุ่มเข้าใช้งานที่จัดเตรียมไว้

ต้องผ่านการทดสอบ boot/SSH จริงก่อนถือว่าปุ่มเหล่านี้พร้อมใช้งาน:

- `Open-Terminal.cmd`: ตรวจ WHPX, เตรียม guest ถ้ายังไม่มี, เริ่ม VM และเชื่อม Linux shell
- `Open-IDE.cmd`: รอ VM พร้อม แล้วใช้ VS Code profile และ Remote SSH extension เฉพาะแพ็ก
- `Sandbox-Status.cmd`: ดูสถานะ manager ที่พิสูจน์ตัวตนได้
- `Stop-Sandbox.cmd`: ขอ shutdown ตามปกติ ไม่ตัดไฟ guest ที่มีข้อมูลผู้ใช้เงียบ ๆ
- `Force-Stop-Sandbox.cmd`: คำสั่งตัดไฟที่ต้องเลือกเอง อาจทำข้อมูลที่ยังไม่เขียนลงดิสก์เสียหาย

ปิด terminal ไม่ได้แปลว่าปิด VM เพื่อให้ IDE ที่เชื่อมอยู่ทำงานต่อได้
ใช้ Stop ก่อนถอด drive, ย้ายโฟลเดอร์ หรือสำรอง virtual disk
Windows OpenSSH client และ VS Code เป็น prerequisite ที่ตรวจพบในเครื่องนี้ ไม่ติดตั้งโปรแกรม/feature ระบบให้อัตโนมัติ
ไม่ใช้ Microsoft Remote SSH extension กับ Cursor โดยเดาว่าเข้ากันได้

ไฟล์โปรเจคเริ่มต้นอยู่ที่ `/home/sandbox/workspaces` เปิดผ่าน Remote SSH URI ไม่ใช่ Windows folder mount
ยังไม่ได้นำโปรเจคจริงของผู้ใช้เข้า guest และไม่ auto-copy checkout ปัจจุบันหรือไฟล์บัญชีใด ๆ

## ขอบเขตเครือข่ายและสิทธิ์

1. bootstrap แรกใช้ QEMU `restrict=on` ไม่เปิดทางออกอินเทอร์เน็ต/บริการ host ให้ guest
2. root bootstrap ลง firewall และบังคับให้ networking/SSH service ต้องรอ firewall สำเร็จ
3. seed เป็น readonly; policy โหลดใหม่ทุก boot และผู้ใช้ `sandbox` ไม่มี sudo/admin/docker socket
4. โหมดปกติอนุญาต DNS/DHCP ที่จำเป็น และ HTTP(S) ออกอินเทอร์เน็ต
5. ปฏิเสธการเริ่ม connection ไป private/local/reserved IPv4 และ IPv4 interface ของ host ที่ตรวจพบ; IPv6 ภายนอกปิด
6. SSH เปิดรับบน **host loopback เท่านั้น**; ไม่เปิด monitor/QMP ผ่าน TCP
7. ไม่ forward SSH agent/X11 และไม่ใช้ SSH config/known_hosts ของบัญชีเดิม

Firewall นี้ป้องกัน application ที่เป็นผู้ใช้ธรรมดาใน guest ไม่ใช่การรับรองเมื่อ guest root/kernel ถูกยึด
Internet proxy/บริการที่เปิดสาธารณะและช่องโหว่ hypervisor/SSH/IDE เป็นข้อจำกัดที่ต้องพิจารณาแยก
ไม่ probe บริการบัญชีจริงหรืออุปกรณ์ LAN เพื่อพิสูจน์ isolation ให้ใช้ listener สังเคราะห์ที่เราเป็นเจ้าของเท่านั้น

แม้ไม่แชร์ clipboard ระดับ VM, terminal escape sequence ก็เป็นอีกช่องทางหนึ่ง
ตัวส่งผ่าน terminal จึงกรอง OSC clipboard/link/file channel และ APC/DCS passthrough ก่อนแสดงผล
ภาพ Kitty แบบอ่านไฟล์ host และ passthrough บางชนิดจึงไม่รองรับในโหมดนี้
CPU tests ของ byte filter ไม่ใช่หลักฐานรับรอง parser ทุกแบบของ GUI terminal จริง
IDE ต้องเปิด Workspace Trust ไว้; อย่าติดตั้ง extension ที่ไม่เชื่อถือบน host โดยคิดว่า VM ครอบคลุมมันด้วย

## Runtime และความถูกต้องของไฟล์

- QEMU Windows: official download page ชี้ไป Stefan Weil distribution, archive วันที่ `20260811`
- Debian: generic amd64 13, SHA512 pin ของ image ที่รับมาครั้งนี้
- Guest Node: `24.22.1`, official Linux x64 tarball + SHA256 pin
- Guest Herdr: `0.9.5`, Linux x86_64 **raw ELF** + SHA256 pin ไม่ใช่ tar archive
- Guest Letta: npm `@letta-ai/letta-code@0.34.23`; ติดตั้ง/รัน npm lifecycle เป็น `sandbox` ไม่ใช่ root

checksum จาก HTTPS/release metadata เป็นการตรวจความถูกต้องตาม pin ไม่ใช่ independent publisher authentication/Authenticode assertion
7-Zip extractor ตรวจ hash ก่อนใช้; installer ของ 7-Zip/QEMU ถูกอ่านเป็น archive ไม่ได้ถูกรัน
การ download ต่อใช้ HTTP Range ที่ตรวจ `206`/`Content-Range` และตรวจ **hash ทั้งไฟล์** ก่อน publish
partial ไม่ใช่ runtime ที่ใช้ได้ และการ parse metadata ได้ไม่ได้แปลว่า acquisition สำเร็จ
base URL ที่เป็น `latest` ยังถูกบังคับ digest เดิม ถ้า upstream เปลี่ยนไฟล์ต้องหยุด ไม่เปลี่ยน pin เงียบ ๆ

## ข้อมูลถาวร การย้าย และความลับ

- overlay อ้าง backing image ด้วย path แบบ relative; ต้องเก็บ base image คู่กับ Data
- ก่อนย้าย/สำรอง: Stop VM และตรวจว่าหยุดจริง แล้วคัดลอก **ทั้งแพ็ก** ไม่ใช่เพียงไฟล์ overlay
- การย้าย path, restart, persistence และ Remote SSH reconnect ต้องมีผลทดสอบจริงแยกจาก source/CPU tests
- ข้อมูลใน virtual disk ยังเป็นไฟล์บน host; ACL ไม่ใช่ encryption
- ผู้ได้ทั้งแพ็กอาจเข้าถึงข้อมูลภายในได้ถ้าไม่มีการเข้ารหัสเพิ่มเติม อย่าเผยแพร่แพ็กที่ login แล้ว
- private Data บน NTFS ใช้ ACL เฉพาะผู้ใช้ปัจจุบันและ SYSTEM; การย้ายข้าม Windows SID/เครื่องยังไม่ผ่าน qualification
- exFAT เปิด reduced protection เฉพาะแพ็กผ่าน `Enable-ExFAT.cmd` และ `portable-storage.json`; ค่าเริ่มต้นไม่เปิด ผู้เข้าถึงไดรฟ์อาจแก้โปรแกรม, VM, คีย์, trust records และ manager token ได้
- NTFS ยังคง owner/ACL/native key checks แม้คัดลอกไฟล์ยอมรับเดิมมา การย้ายกลับ NTFS ไม่เพิกถอนสำเนาคีย์/ข้อมูลที่อาจถูกคัดลอกแล้ว
- exFAT ใช้คีย์ Ed25519 เดิมผ่าน agent ส่วนตัวตลอดอายุ manager แทน native private-file loader ที่ปฏิเสธคีย์บน filesystem นี้ ตรวจคู่คีย์และ native sign/verify ก่อนเปิด VM ไม่ใช้ global Windows agent/host profile/C: fallback
- agent ใช้ protected local pipe เฉพาะ user ปัจจุบันกับ SYSTEM, reject remote clients, ไม่ forward เข้า guest; ไม่ใช่การแยกจากโปรแกรมอื่นของ user เดียวกัน และไม่เพิ่ม encryption ให้คีย์บนไดรฟ์
- cold start บน exFAT ใช้ restricted bootstrap ใหม่ภายใต้ exclusive manager ทุกครั้ง ไม่มี automatic force-stop ระหว่าง bootstrap หรือ runtime
- ไม่แก้ ownership/permission ของแพ็กบน `A:` และไม่ทดสอบย้ายข้อมูลจริงโดยอัตโนมัติ

## สถานะหลักฐาน

| รายการ | สถานะ |
|---|---|
| WHPX capability บนเครื่องนี้ | ผ่าน API read-only |
| download/whole digest/extraction ของ QEMU+Debian | ผ่าน มี acquisition-complete receipt |
| pure CPU seed/policy/acquisition/CLI/escape filter tests | มี executed tests; ดูผลรันล่าสุด รวม regression FAILED ติด login prompt และ C1 control |
| boot/NoCloud/firewall/host key บน guest จริง | ผ่าน restricted bootstrap และ fresh runtime boot พร้อม graceful shutdown |
| Node/Herdr/Letta ใน guest จริง | SSH uid=1000, HOME=/home/sandbox, Node 24.22.1 / Herdr 0.9.5 / Letta 0.34.23 ผ่าน |
| Herdr pane command discovery | ผ่าน normal names ของ node/npm/git/herdr/letta ผ่าน pane run/read API จริง พร้อม TUI attached และ nonce/SHA256 รอบใหม่; ไม่ใช่ keyboard-focus/native GUI acceptance |
| persistent reboot/host-listener denial | ผ่านเขียน UTF-8 แล้วปิด/เปิด VM อ่าน SHA256 เดิม; guest เข้า owned listener ทาง 10.0.2.2 ไม่ได้ทั้งสองรอบ |
| manager start/stop/restart | ผ่าน private Node manager สองรอบที่ path เดิม และสองรอบหลังย้าย; graceful stop และ QEMU exit 0 |
| ย้าย path | ผ่านย้ายทั้งแพ็กไปภาษาไทย+ช่องว่าง+apostrophe บน NTFS volume เดิม อ่าน SHA256 เดิมและเปิด manager ได้ แล้วคืน path เดิม; ยังไม่รับรองข้ามเครื่อง/volume/exFAT |
| exFAT CLI บน VHDX จริง (14 พ.ย. 2026) | ผ่าน native SSH + UTF-8 SHA256 persistence สองรอบและย้ายชื่อไทย/space/apostrophe; packaged CMD เข้า Linux/uid 1000/HOME/cwd จริงด้วย prompt-paced redirected stdin; 3 cold starts, restricted bootstrap/runtime 6 receipts exit 0; ไม่ใช่ GUI, ข้ามเครื่อง/volume หรือ USB power-loss qualification |
| packaged terminal entry | ผ่าน Open-Terminal.cmd → private Node → SSH → Linux Bash ด้วย prompt-paced redirected stdin; platform=linux, uid=1000, HOME และ cwd ถูกต้อง แล้ว normal stop; ไม่ใช่ native interactive GUI proof |
| private IDE CLI preparation | ติดตั้ง ms-vscode-remote.remote-ssh 0.124.0 ใน private profile และ guest workspace URI ผ่าน CLI จริง; ไม่ได้เปิด/เชื่อมผ่าน IDE GUI |
| interactive terminal/IDE GUI | keyboard focus, native rendering และ IDE GUI connection ยังไม่รับรอง |
| provider chat/บัญชีจริง | ไม่ได้ทดสอบ/ไม่ได้ย้าย |

ผลนี้เป็นต้นแบบ headless/CLI ไม่ใช่ production หรือผลรับรอง malware isolation ทุกกรณี
เริ่มกับโปรเจกต์ทดสอบก่อน บัญชีจริง/provider chat ยังไม่ได้ทดสอบ และไม่ได้นำบัญชีเดิมเข้า VM
WIN-RUNTIME-004, remote cycle12 และงาน ETW เดิมยังแยกอยู่ ไม่ได้ปิดด้วยงานนี้

ข้อแก้ไขจากการรันจริง: NTFS private DACL ต้องเรียกซ้ำได้โดยแก้เฉพาะ Access ไม่ขอ SACL/SeSecurityPrivilege;
Debian cloud image ต้องมี `build-essential` สำหรับ native `node-pty` ของ Letta (ติดตั้งใน guest เท่านั้น)
ตัวอ่าน serial ต้องจับ FAILED ที่ต่อท้าย getty prompt แต่ยังไม่ยอมรับ embedded/stale READY
bootstrap proof ผูกกับ instance, host key และ file identity ของ overlay ไม่ใช่ตรวจแค่ชื่อไฟล์ receipt ว่ามีอยู่
QEMU build ที่ใช้เปิด absolute Unicode disk path ไม่สำเร็จ จึงส่งเฉพาะชื่อ disk/seed/serial/firmware
แบบ relative ภายในแพ็ก และกำหนด cwd เป็น root ที่ตรวจ ownership แล้ว ไม่เปลี่ยน system codepage หรือสร้าง global path alias
Windows IDE ใช้ dedicated profile/extensions และปิด telemetry/update ใน profile นี้เท่านั้น
ถ้า executable ของ IDE มี portable `data` ของตัวเองจะปฏิเสธ ไม่ยืม principal นั้นแทน profile ที่ระบุ
Windows OpenSSH ต้องมี `ProgramData` ใน environment แม้ใช้ private `-F` config:
พิสูจน์แล้วว่าขาดตัวนี้ได้ exit 255 โดยไม่มีข้อความ เพิ่มเฉพาะ OS metadata นี้จึงทำงาน
ไม่ได้ส่ง host HOME/USERPROFILE, API keys, username/domain หรือ SSH agent ไปแทน private principal
VS Code รุ่นที่ตรวจมี CLI ใน versioned directory จึงอ่านเฉพาะ hex version tag จาก public `bin/code.cmd`
ไม่ execute script นั้นและไม่เดา CLI path หรืออ่าน account profile

## ตรวจต่อสำหรับผู้พัฒนา

ผลรอบส่งมอบต้นแบบ: CPU tests 66/66 ผ่าน, packaged CMD และ private IDE CLI ผ่าน;
App 12 ไฟล์ตรง SHA256 กับ source ปัจจุบัน พร้อม `START-HERE-TH.md` ในแพ็ก
ตรวจหลังทดสอบแล้วไม่มี owned QEMU/private Node หรือ manager ค้าง
ขนาด logical รวม 6.681 GiB หรือ 6.080 GiB เมื่อนับ hardlink เพียงครั้งเดียว
ไม่ใช่ขนาด physical allocation; เก็บ original failed-guest baseline ที่ยังเป็น backing chain ไว้ ไม่ลบทิ้งเพื่อให้ตัวเลขเล็กลง

source อยู่ `tools/windows/sandbox/` ทดสอบ CPU โดยส่งรายการ `.test.cjs` ให้ Node เป็น argument array
ไม่ใช้ผล CPU test แทน boot/GUI test และไม่แก้ snapshot ใน App ระหว่างที่ VM/manager กำลังใช้
รีบูต/SSH smoke ของต้นแบบเก็บ receipt ด้วย boot nonce ใหม่และไม่รับ ready marker เก่าเป็นผลรอบใหม่

แหล่งอ้างอิง:

- <https://www.qemu.org/download/#windows>
- <https://www.qemu.org/docs/master/system/invocation.html>
- <https://qemu.weilnetz.de/w64/>
- <https://cloud.debian.org/images/cloud/trixie/latest/>
- <https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html>
- <https://github.com/herdrdev/herdr/releases/tag/v0.9.5>
- <https://nodejs.org/dist/v24.22.1/SHASUMS256.txt>
- <https://docs.letta.com/self-hosting/index.md>
