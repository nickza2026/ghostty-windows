# Node/npm และ profile เครื่องมือแบบ portable

สถานะ: 27 ตุลาคม 2026 ทวน local native integration และสร้างแพ็กทดลองแล้ว ไม่ใช่ qualified public release และไม่ได้ปิด WIN-RUNTIME-004 / physical mixed-DPI

## ขอบเขตที่ผู้ใช้อนุมัติ

27 ตุลาคม 2026 เวลา 15:49 ผู้ใช้อนุมัติให้ Node/npm อยู่ในแพ็ก และให้การติดตั้ง Letta ภายหลังเก็บข้อมูลของ CLI ใน portable-data โดยไม่พึ่ง Node/npm ที่ติดตั้งบน Windows เริ่ม profile ใหม่ ไม่ย้ายบัญชี/credentials/agent memory เดิม ไม่แก้ machine environment หรือ profile ของเครื่อง และไม่ commit/push

นี่ไม่ใช่ sandbox: Windows DLL/fonts/driver/browser/OS caches ยังใช้ระบบปฏิบัติการได้ โปรแกรมที่ผู้ใช้สั่งหรือ lifecycle scripts อาจเขียนไฟล์นอกแพ็ก ไฟล์โปรเจกต์และ `.letta` / `.npmrc` เฉพาะโปรเจกต์ยังเป็นของ workspace ตามปกติ ไม่รับรองว่าไม่มีการแตะ C: ทั้งระบบ

## โครงสร้าง

```text
Run.cmd
bin/localterm-dev.exe
bin/powershell/PSReadLine/                  module แก้ Thai Mn/Me พร้อม license/provenance
bin/portable-data/
  runtimes/node/                          Node + npm + license + complete hash manifest
  shims/{node,npm,npx,letta}.cmd            เรียก private Node/CLI แบบ absolute
  npm/                                    global npm prefix ของแพ็กนี้
  home/.letta/                            Letta CLI home
  home/.letta/lc-local-backend/            local backend เมื่อผู้ใช้เลือก local mode
  home/AppData/{Roaming,Local}/            AppData ของ child tools
  home/PowerShell/PSReadLine/              ประวัติ shell ในโหมดแยก
  config/{npm-user,npm-global}.npmrc        สร้างเปล่าเฉพาะครั้งแรก ไม่ทับของเดิม
  cache/npm/                              npm cache
  tmp/                                    TEMP/TMP/TMPDIR ของ child tools
```

Node pin: **v24.22.1 (Krypton LTS), Windows x64**, npm **11.19.1** จาก official Node archive พร้อม SHA256 ใน `third_party/node/source-pin.json` ต้นทาง/ข้อกำหนดดู `third_party/node/README.md` ไม่ใช้ Node ของเครื่องมาติดตั้งแทน ไม่มี runtime download ตอนเปิดโปรแกรม

## การใช้หลังได้แพ็กทดลอง

เก็บ `bin` และ `share` ไว้ด้วยกัน เปิดผ่าน `Run.cmd` เพื่อใช้ bundled app-local ConPTY ตาม launcher ที่ระบุ ชื่อ provider ไม่ใช่การ promote default ใน normal build ตัวแจกโหมดนี้ build ด้วย isolated default เพื่อให้เปิด executable โดยตรงแล้วยังตรวจ runtime/private profile แต่ direct EXE อาจเลือก system ConPTY ตาม runtime policy เดิม

จาก shell ในแพ็ก:

```powershell
node --version
npm --version
npm install -g @letta-ai/letta-code
letta
```

การติดตั้ง Letta เป็นการใช้งานภายหลัง **ยังไม่ได้ทำในแพ็กส่งให้ผู้ใช้** ไม่ได้ยืนยัน login/provider หรือ first-run Letta จากตัวอย่างคำสั่งนี้ แพ็กใช้ Node ที่รองรับขั้นต่ำ Node22.19+ ตาม CLI0.34.23 ที่ตรวจ และใช้ private home กับ `LETTA_LOCAL_BACKEND_DIR` ตาม [Letta configuration](https://docs.letta.com/reference/settings/index.md) การติดตั้ง CLI ไม่ได้เปลี่ยน cloud/local backend ให้เอง

## Isolation และ fail-closed

- Native เพิ่มค่าเฉพาะ `Config.env` ของ child: HOME/USERPROFILE, AppData, TEMP, npm prefix/cache/config และ Letta directories ไม่เปลี่ยน environment ของโปรแกรมผู้เรียกหรือ Windows
- ก่อน merge ค่า private จะลบ Node/npm/Letta injections และ known inherited auth/harness variables จาก **actual child environment map** ไม่ใช่ใส่ empty overrides แล้วปล่อยค่าของเครื่องค้าง ไม่อ่านหรือ log ค่าลับ
- PATH ในโหมดใหม่นี้ประกอบด้วย private shims/Node/npm และ Windows system paths เท่านั้น **ไม่ดึง Git/CLI ของเครื่องผ่าน inherited PATH** ต้องจัดหาเครื่องมือเพิ่มภายหลังหรือเลือกใช้ explicit host path โดยตั้งใจ โหมดปกติที่ไม่เลือก isolated build/flag ไม่เปลี่ยน
- PowerShell ใช้ absolute Windows executable + `-NoProfile` และ private module search path ตั้ง HOME/history ก่อน prompt แรก ฟังก์ชัน `node/npm/npx/letta` ใช้ absolute Node/entrypoint เพื่อไม่เลือกโปรแกรมจาก current directory
- ตั้ง `NoDefaultCurrentDirectoryInExePath` ให้ child CMD ด้วย การทดสอบควบคุมพบ cwd poison exit91 เมื่อไม่มี flag และ private Node v24.22.1 exit0 เมื่อมี flag ทั้งนี้ไม่ใช่การ sandbox arbitrary Node subprocess
- ตรวจทุกไฟล์ใน immutable runtime/module manifest ก่อน execute พร้อม reject missing/hash mismatch/unlisted/unsafe relative paths และ reparse ancestors/entries ใช้ directory write probes กับพื้นที่ mutable ไม่บังคับให้ runtime binaries เขียนได้
- พื้นที่ขาด/เขียนไม่ได้/runtime ขาด ให้ error ไม่เลือก host Node หรือ host storage เงียบๆ อาจมี terminal-owned directories ที่สร้างก่อนตรวจครบ แต่ไม่ spill ไป host profile
- manifest/provenance เป็น unsigned local-package consistency ไม่ใช่การรับรอง authenticity ของ Microsoft/Node แบบ cryptographic signing chain อย่าใช้ package ที่ไม่น่าเชื่อถือ
- npm CLI flags, workspace `.npmrc` และ lifecycle scripts ของแพ็กเกจที่ติดตั้งเองยังมีผล การทดสอบสังเคราะห์จึงใช้ local tarball, `--offline --ignore-scripts --no-audit --no-fund` เท่านั้น

## ความปลอดภัยของข้อมูลและการย้ายแพ็ก

เมื่อใช้ไปแล้ว portable-data อาจมี login/API keys/agent state/history อย่าแจกทั้งโฟลเดอร์ที่ใช้จริงต่อผู้อื่น แพ็กส่งให้ผู้ใช้ต้องสร้างใหม่และไม่เคยรัน ไม่คัดลอกข้อมูลจาก test clone หรือ profile เดิม ปิดแอปและ child tools ก่อนย้าย/อัปเดต เก็บข้อมูลเดิมไว้และไม่ลบ portable-data เพื่ออัปเดต executable

## Build และแพ็ก

```powershell
zig build -j2 -Dapp-runtime=win32 -Dtarget=x86_64-windows-msvc -Dcpu=baseline -Doptimize=ReleaseSafe -Demit-docs=false -Dwindows-portable-default=true -Dwindows-portable-tools-default=true -p <fresh-prefix>
.\tools\windows\stage-portable-node.ps1
.\tools\windows\build-app-psreadline.ps1
# เตรียม verified ConPTY/package evidence และ patched PSReadLine ลง source prefix ก่อน
.\tools\windows\package-portable.ps1 -SourcePrefix <fresh-prefix> -PortableTools -NodeSource <verified-node-payload>
```

Node stager/package helper ไม่ทับ output เดิม ไม่คัดลอก user profile ตัวเลือก NodeSource ใช้ร่วมกับ PortableTools เท่านั้น และไม่ใช้ OmitInitialData สำหรับโหมดนี้ `windows-portable-tools-default` ต้องใช้พร้อม `windows-portable-default` จึงไม่เปลี่ยน default ของ normal builds

## หลักฐานที่มีแล้วและสิ่งที่ยังรอ

- Structural package negatives: missing-listed/bad digest/unlisted/traversal/duplicate JSON keys/output exists ผ่าน รวม space/Thai relocation และ private offline npm global fixture โดยไม่ได้รัน native executable เก่าเป็นหลักฐาน integration
- Shared production message pump: original algorithm ผิด2/4 tests เพราะ PeekMessage รับ WM_QUIT แล้วคืน ordinary message เก่า หลังแก้คืน actual quit message ผ่าน4/4 รวม nonzero quit error ที่ต้องไม่หาย
- Child Environ.Map sanitizer ผ่าน2/2; metadata relative-path guard ผ่าน1/1 ไม่มี GUI/provider/auth execution
- Native isolated MSVC/ReleaseSafe build123/123 สำเร็จพร้อม source hashes frozen; private PSReadLine compiled-width10 checksทั้ง original/patched ผ่าน
- Native positive suite ผ่าน8กรณีจริง: system ConPTY พร้อม synthetic inherited Node/npm/API-key poisons, app-local ConPTY full-tools, midlineทั้งสอง provider, keyboard, natural exit, direct EXE defaultโดยไม่ใส่tools/readline flags และย้ายทั้งแพ็กไปชื่อไทย/ช่องว่างพร้อมรักษาexisting profile sentinel
- Actual child proof ตรวจ `process.execPath`, `os.homedir()`, `os.tmpdir()` และ HOME/USERPROFILE/AppData/npm/Letta paths ว่าอยู่ใน root ใหม่จริง รวม private PSReadLine history option ติดตั้ง synthetic CLI tarballแบบofflineในprivateglobalprefixแล้วรันผ่านnpm-generated CMD ได้ ไม่ได้ใช้ mock environment แทน native child
- Native midlineหลังเชื่อมprofileใหม่: ASCIIcaret51/Thaicaret49 bufferถูกต้อง/cell differences0 ทั้งsystemและapp-local ตัวDLLโหลดจริงSHA256 `FFB5E54D4DB8E7A93B8502988943076ABA35C7ED51D9040AF45208E06E1C25BF` ไม่เหมารวมว่าhumanacceptanceของcandidateเก่าเป็นการยอมรับbinaryใหม่นี้
- Normal buildที่ปิดportable defaultทั้งสองoption build123/123และnoninteractive natural exit0 ผ่าน โดยไม่มีNodepayloadหรือportable-data ไม่เปิดpromptเพื่ออ่านhosthistoryในการทวนนี้
- พบpackagingregressionจริงระหว่างintegration: npm-generated CMD เรียกquoted bare `"node"` ทำให้ `%~dp0` ของNodewrapperกลายเป็นcwd ส่งผลexit127 แม้directabsolute/unquotedbareผ่าน เพิ่ม `portable-quoted-shim-test.ps1` จับred127ก่อนแก้ แล้วแก้การหาknownCMDfilenameผ่านexplicitPATH ได้greenและsameNativeE2Eผ่าน ไม่แก้ด้วยการยอมfallbackNodeของเครื่อง
- Native fail-closed8กรณีผ่านจริงก่อน `started subcommand` (Node/npm/module missing/hash/unlisted/home file/junction/cache write ACL) restoreไฟล์/junction/ACLครบและpost-cleanupfulltoolsE2Eexit0 ตัวassertของtestdriverเคยชนreadonly`HOME` และเคยเทียบrawSDDLผิดเพราะWindowsเพิ่มD:AIเมื่อลงACL หลักฐานแยกแสดงACEทั้ง8,owner,group,protectedเหมือนเดิม จึงเปลี่ยนcleanuporacleให้ตรวจทุกrule/owner/group/inheritanceและexclusivewrite+deleteprobe ไม่ผ่อนnativeerror/child-spawn assertions ผลสุดท้าย `zig-out/portable-tools-evidence/negative-fca8ef1a24e147798a19d68b16985333/results.json`
- Latest structural package regressions และ quoted-bare shim ผ่านซ้ำหลังแก้ทั้งหมด ไม่มีการติดตั้งLetta/login/providerหรือย้ายstateจริง

## แพ็กส่งมอบที่ตรวจแล้ว

เปิด `D:\works\ghostty-windows\zig-out\portable-packages\localterm-portable-tools-20261027\Run.cmd`

- EXE: `bin/localterm-dev.exe` SHA256 `5190F82B1DF6512D8494F24C421775A922473417254457D324919EEA452E0577`
- ตรวจhashตามpackage manifestครบ **2,765ไฟล์** และsource hashesของnative targetsตรงกับbinaryที่ทดสอบ
- แพ็กส่งมอบ **ไม่เคยรัน** และ `home/npm/cache/tmp` ไม่มีไฟล์จากผู้ใช้หรือการทดสอบ การทดสอบทั้งหมดใช้cloneแยก ไม่ติดตั้งLetta ไม่ย้ายบัญชี/agent memory และไม่commit/push
- หลักฐานหลัก: `zig-out/portable-tools-evidence/build-20261027-162422-825/{candidate,positive-suite,normal-compat,final-handoff}.json`
- `zig fmt --check`, PowerShell AST parsingของhelperทั้ง8 และ whitespace checksของtracked changed targets ผ่าน

การทวนนี้ไม่ใช่ clean-user/VM, real IME, mixed-DPI, GPU stability/performance หรือ Windows/third-party filesystem-confinement qualification
