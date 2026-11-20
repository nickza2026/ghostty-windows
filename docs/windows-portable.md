# Windows terminal portable

สถานะ 20 ตุลาคม 2026 เวลา 23:47: **auto-portable functionality/ZIP ผ่าน แต่ native strict lifecycle ยังมี failure จึงยังไม่พร้อมใช้งานทั่วไปหรือ qualified public release** รุ่นนี้สร้าง storage ข้าง exe เองเมื่อไม่มี marker native first-run/preserve/move/negative/ZIP ข้าม drive ผ่าน รุ่นปกติคงค่าเดิม; full Core/VT ผ่านก่อนเพิ่ม auto build flag ไม่อ้างว่าเป็น full suite หลัง flag ผู้ใช้ให้ทำ portable ก่อน qualification ของ GPU worker งาน GPU เดิมคงไว้และยังไม่เปลี่ยน default

## เปิดทดลอง

**รุ่นปัจจุบันตามคำขอเวลา 23:22:** ใช้ `D:\works\ghostty-windows\zig-out\portable-auto-candidate-20261020.zip` หรือ folder ชื่อเดียวกัน แตก ZIP แล้วเปิด **`bin\localterm-dev.exe` ตรง ๆ ได้** มันจะสร้าง `bin\portable-data` พร้อม config/data/cache/logs/tmp ข้าง exe เอง ไม่ต้องสร้าง marker หรือใช้ Run.cmd เพื่อเปิด portable โหมดนี้

ZIP สะอาดไม่มี `portable-data` เตรียมมาให้ และไม่มี config/profile/cache ส่วนตัว เมื่อเปิดครั้งแรกสร้าง directories เท่านั้น ถ้าต้องการตั้งค่าให้สร้างไฟล์ UTF-8 `bin\portable-data\config\config.ghostty` เช่น `font-size = 14` ไม่มีการคัดลอก config จาก AppData/HOME หรือ credentials มาเอง รุ่นเดิม `portable-candidate-20261020.zip` ยังเป็น marker-opt-in อย่าสับสนกับชื่อใหม่ที่มี **auto**

exec309 helper unit 7/7 ทั้ง Debug/ReleaseSafe ผ่าน รวมสร้าง root ชื่อไทย/ช่องว่าง, เก็บ config เดิม, ไม่แทนที่ file marker, และ fault checks ของ layout เดิม หลัง exec305 จบแล้วผูก `-Dwindows-portable-default=true` เข้ากับ global Win32 startup เรียบร้อย **ค่า default รุ่นปกติยัง false** และห้ามใช้ flag นี้กับ target/runtime อื่น

exec312 ผ่าน helper7/7ทั้งDebug/ReleaseSafe และ auto (`zig-out/portable-auto-dev`)/normal-default-false (`zig-out/portable-normal-dev`) build123/123ทั้งคู่แบบx64CPUbaseline ทวน direct-exe first-run/no seeded data, config/data hashes, move และ invalid file marker ผ่าน4cases พร้อม normal control ผ่านและไม่สร้าง data root ไม่ทับ artifact รุ่นก่อน

`package-portable.ps1 -OmitInitialData` กับ `portable-auto-smoke.ps1 -SourcePrefix <new-auto-prefix>` ใช้จริงในexec312แล้ว harness ไม่ seed marker/ใช้Run.cmd/ตั้ง terminal-or-provider env โดยใช้เฉพาะ terminal-smoke เพื่อ offscreen/ปิดเอง ไม่อ้างว่าเป็น Explorer double-click จริงหรือ physical keyboard acceptance

เก็บ `bin` และ `share` ของรุ่น auto ไว้ด้วยกัน ไม่ย้ายเฉพาะ exe; portable-data ตามตำแหน่ง exe จริง ไม่ใช่ cwd, shortcut working directory หรือ folder ของHerdr

`Run.cmd` ยังใช้ได้เพื่อเลือก bundled Microsoft app-local ConPTY เฉพาะ process นี้ ไม่เปลี่ยน system/user environment หรือ registry แต่ไม่ใช่สิ่งจำเป็นสำหรับ auto-portable เปิด exe ตรงจะใช้ provider default ของระบบตามเดิมทั้ง storage ยังportable หากเปิด exe แล้วปิดทันที ให้เปิดผ่านRun.cmdเพื่ออ่านข้อความ/exit code; ไม่มีการขอadmin/แก้ACLหรือเลือก host storage แทนเมื่อเขียนไม่ได้

นี่เป็น Windows x64 / MSVC CPU-baseline build ไม่ใช่ ARM64/x86 และยังต้องมี Windows/ConPTY, system fonts และ OpenGL 4.3/driver ที่รองรับ CPU DIB frame ไม่ใช่ software-renderer fallback สำหรับเครื่องไม่มี OpenGL ส่วน GPU worker isolation ไม่ได้ถูกเปิดเป็น default ใน package นี้

config ที่แก้ได้อยู่ `bin\portable-data\config\config.ghostty` โหลดตอนเริ่ม terminal; ตัวอย่าง `font-size = 14` ส่วน theme ส่วนตัวอยู่ `bin\portable-data\config\themes` การ reload/conditional-theme runtime ไม่ได้ถูกรับรองจาก startup tests ชุดนี้ หลีกเลี่ยง absolute path/`config-file` ที่ชี้เครื่องเดิมหากจะย้ายเครื่อง และห้ามใส่ token/password เป็น command ใน config เพราะ diagnostics อาจบันทึก command

shell/Herdr/Letta **ยังใช้บัญชีและ profile ตามการตั้งค่าของโปรแกรมเหล่านั้นเอง** portable terminal ไม่ทำให้สองบัญชีแยกหรือพก login ข้ามเครื่องอัตโนมัติ ขั้นนี้ไม่มีการอ่าน/คัดลอก credentials หรือส่ง request เข้าบัญชีจริง

## ข้อมูลและการอัปเดตด้วยมือ

ข้อมูลที่ terminal ควบคุมอยู่ใต้ `bin\portable-data` ภาพ paste อยู่ `cache\clipboard` ผูกกับ exe ที่รัน ไม่ใช่ cwd `logs` ยังเป็น directory ที่สงวนไว้ แอปส่ง diagnostics ไป stderr ไม่ได้เพิ่ม disk-log collector อัตโนมัติ ไฟล์ BMP/JSON ของ automated smoke อยู่ใน log folder ของ **test harness** ไม่ใช่ app storage ในการใช้งานปกติ

ปิด terminal และ process ลูกก่อนย้ายหรืออัปเดต รักษา `portable-data` เดิมไว้ สำรองก่อนเปลี่ยน version; อย่า copy config template จาก ZIP ทับ config ของตัวเอง และอย่าลบ folder เดิมทั้งชุดเพื่ออัปเดต ยังไม่มี migration/auto-updater หรือการรับรอง rollback schema

package manifest เก็บ SHA-256 ของ initial payload; config ใน manifest เป็น template เริ่มต้นที่ผู้ใช้แก้ได้ ไม่ใช่เหตุให้ restore/overwrite config อัตโนมัติ ใช้ ZIP สะอาดสำหรับส่งต่อ ไม่ zip folder ที่ใช้งานแล้ว เพราะอาจมี config/paths/ภาพส่วนตัว/ไฟล์ค้างจาก crash

## ขอบเขต

- รุ่นปกติใช้ directory `portable-data` ข้าง executable เป็นตัวเลือกตามเดิม รุ่น distribution ที่buildด้วย `-Dwindows-portable-default=true` สร้าง directory นี้เองเมื่อไม่มี ไม่ยึด cwd และไม่ตรวจจากตำแหน่ง `herdr` ใน PATH
- แยกไฟล์ที่ terminal เป็นเจ้าของ ได้แก่ config, data/cache, logs และ temporary staging ตาม portable root
- ไม่เปลี่ยน `HOME`, `USERPROFILE`, `APPDATA`, บัญชีหรือ credentials ของ Herdr/Letta/โปรแกรมลูกโดยอัตโนมัติ การแยกบัญชีเป็นอีกงานหลัง terminal portable
- ไม่รับรองว่า Windows, GPU driver, shell history และโปรแกรมลูกจะไม่เขียนนอก portable folder
- ไม่มี installer, registry/PATH modifications, admin elevation, network updater หรือการย้าย config เดิมโดยเงียบ ๆ

## Layout ที่กำลังผูกเข้ารันไทม์

```text
<exe-dir>/
  localterm-dev.exe
  portable-data/
    config/config.ghostty
    data/
    cache/clipboard/
    logs/
    tmp/
```

นี่เป็น layout ของ app-owned state ไม่ใช่ package manifest ที่ครบแล้ว ตำแหน่ง bundled resources/DLLs ต้องตรวจจาก build output และทดสอบ relocation ก่อนยืนยันคู่มือเปิดใช้งาน

เมื่อเลือก portable แล้ว marker/storage หาย, ถูกแทนด้วยไฟล์/link หรือเขียนไม่ได้ ต้องแสดงข้อผิดพลาด ไม่ fallback ไป host TEMP/AppData และไม่แก้สิทธิ์ให้เอง โหมดปกติที่ไม่มี marker ต้องไม่ถูกเปลี่ยนไปอ่าน portable หรือทับ Ghostty config เดิม

## งานที่กำลังทำและหลักฐาน

- พบว่า Win32 runtime ปัจจุบันใช้ `Config.default` แล้วเติม candidate defaults ไม่ได้โหลด portable config
- resource discovery ปัจจุบันยังรับ `GHOSTTY_RESOURCES_DIR` และค้น ancestor ต้องปิด host fallback ใน portable mode
- image cache เดิมมี executable-relative marker latch/no-host-fallback อยู่แล้ว ดู [image paste](windows-image-paste.md)
- exec270 ผ่าน common layout foundation 3/3 ทั้ง Debug/ReleaseSafe: independent roots, path ไทย/ช่องว่าง, invalid marker/child และ selected storage loss
- เพิ่ม startup snapshot ใน global state แล้ว เลือก app-only tmp ใต้ portable root โดยไม่เปลี่ยน environment ของ shell; clipboard ใช้ snapshot เดียวกัน ไม่กลับไปเลือกใหม่เมื่อสร้าง surface
- portable runtime โหลด `portable-data/config/config.ghostty` แทนการอ่าน host config; config ผิด/อ่านไม่ได้ต้อง fail ไม่สลับไป host config โหมดปกติยังคงพฤติกรรมเดิม explicit `config-file`/absolute paths ที่ผู้ใช้ใส่เองยังต้องพิจารณาเรื่องการย้ายเครื่อง
- resource lookup ของ portable จำกัดเฉพาะ `<exe-dir>/share/ghostty` หรือ layout เดิม `<package>/bin` + `<package>/share/ghostty`; sentinel อยู่ที่ `share/terminfo/ghostty.terminfo` ไม่ใช้ inherited `GHOSTTY_RESOURCES_DIR` หรือไต่ ancestor นอก package ถ้าไม่พบให้ error
- exec279 ผ่าน layout/resource-boundary 4/4, clipboard 22/22 ทั้ง Debug/ReleaseSafe และ app build 123/123 ใน prefix ใหม่ ไม่ทับ preview เดิม
- เพิ่ม portable theme path `config/themes`, SSH metadata cache ใต้ `data/<program>/ssh_cache`, และไม่ initialize Sentry ใน portable mode ไม่มีการเพิ่ม network/telemetry; startup ทำ exclusive write+delete probes ใน directory ของตัวเองโดยไม่แก้ ACL
- exec283 ผ่าน layout 4/4 สอง modes/build123/Thai direct VT model และ synthetic PNG E2E normal+portable ทั้งสอง session: quoted path เป็นหนึ่ง literal, independent GDI+ RGBA, expected-root และ cleanup ผ่าน ไม่อ่าน OS clipboard
- exec285 harness ล้มเพราะตั้ง window-only smoke กับ terminal smoke คู่กัน แก้เฉพาะ harness; exec290 normal control ผ่านแต่ package ใช้ theme แล้ว PowerShell หายเป็น cmd จึงไม่พบ fixture marker เป็น **runtime integration bug** ไม่ใช่ missing DLL
- สาเหตุ: theme finalize สร้าง Config/arena ใหม่และ replay เฉพาะ parsed inputs ค่า Win32 runtime ที่ตั้งโดยตรงจึงหาย เพิ่ม independently-owned command/policy snapshot และ clone กลับเข้า arena ใหม่หลัง finalize ไม่ใช้ pointer เก่า ตรวจ diagnostics หลัง finalize ด้วย
- exec303 ผ่าน layout/write-fault 5/5 และ clipboard 23/23 ทั้ง Debug/ReleaseSafe, build 123/123 ด้วย **explicit `x86_64-windows-msvc` / `cpu=baseline`** จากนั้น original/normal-overlap/moved/missing-resources/invalid-config/invalid-storage ผ่านทั้ง 6 cases พร้อม PNG E2E normal+portable/cleanup ผ่านอีกครั้ง แก้ theme command/arena แล้วไม่ drop marker check; AccessDenied/NoSpaceLeft เป็น simulation ไม่แทน physical read-only/full-volume acceptance
- `package-portable.ps1` สร้าง local candidate จาก clean install prefix เท่านั้น ตรวจ Microsoft signatures, ไม่ copy portable user data/PDB/test executables และไม่ overwrite output เดิม; `portable-smoke.ps1` ใช้ owned offscreen fixtures และย้าย directory ที่ตรวจขอบเขตแล้ว ไม่มี recursive deletion หรือ login changes
- exec304 สร้าง clean candidate ไม่รวม test config/cache/user data/PDB/worker fixture และ exec306 ZIP→แตกจาก D: ไป C: ในชื่อไทย/ช่องว่าง ตรวจ hashes ทุกไฟล์ตาม manifest แล้วรันจาก `C:\WINDOWS` ผ่านจริง เลือก resources ที่แตกใหม่ ไม่ใช้ inherited resources จาก build folder ทั้งหมด offscreen/no-activate ไม่ใช่ human on-screen acceptance
- executable SHA-256: `ADA7F0996B1DDBA04AC7E3ED891453EC01726EFAD4978D708DF17263E57202E4` หลักฐานคำสั่ง/exit/path/ZIP hash อยู่ `%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\portable\results.jsonl`
- exec305 ผ่าน full Core Debug 3988/4049 (61 skipped), 89/89 steps และ VT 6722/6786 (64 skipped), 45/45 steps ด้วย CPU baseline **ก่อนเพิ่ม auto-create build flag** ผลนี้ไม่แทนการทวน flag ใหม่ใน exec312
- exec313 pack ZIPautoไม่มีseededdata→แตกDไปCชื่อไทย/ช่องว่าง→ตรวจทุกmanifesthash→เรียกexeตรงจากCWDWindowsโดยไม่มีterminal/providerenv ผ่าน สร้างdataข้างexeและเลือกextractedresourcesไม่ใช้buildfolderที่แอบใส่ในenv ZIP SHA256 `9763AB3A40A87C2F967AEA7BBE5332FCEA3BF62F1E54846E5D445F92309C29B3`, auto executable SHA256 `6FA36F53DAD965E6AB5A2D5680AD26060D4D8AE785555ACCC7094CDB104819BA`
- exec314 strict lifecycle **failed ResourceGrowth** หลัง warmup+20 cycles: handles236→237, threads6→7, GDI3→3, USER3→3 ทำให้ PNG ที่ต่อท้าย job นี้ไม่ได้รัน เก็บ failure ไว้ ไม่ใช้ startup/ZIP success เป็น waiver
- sample1เริ่มhandles237คงที่ถึงsample20 ขณะที่thread6→8→10→7; inventory final พบ thread23232เริ่มใน `amdihk64.dll` และมีNTDLL pool threads เปลี่ยน แต่ข้อมูลนี้ไม่พิสูจน์ root cause/ผู้จองhandle จึงยังไม่เดาว่าเป็นdriver leakหรือแก้settings/เพิ่มwarmupให้ผ่าน
- exec317 matched lifecycle normal/default-false build+marker กับ auto build+existing marker ใช้font19/providerเดียวกัน caseละหนึ่งครั้ง **failedทั้งคู่**: normal handles242→243/threads6→7, auto233→234/6→7, GDI/USERคงเดิม จึงแสดงว่าauto flagไม่จำเป็นต่อการrepro แต่ยังไม่ใช้ผลนี้ตัด shared portable path ทิ้ง เพราะทั้งสองcaseเข้าportable
- exec321 เทียบ normal binary เดียวกัน/no-marker กับ normal+marker โดยใช้candidatefont defaults ไม่มีoverrideและapp-local providerเหมือนกัน **failedทั้งคู่**: no-marker233→234handles/6→7threads, marker242→243/6→7, GDI3→3/USER3→3 ทั้งคู่ มี21samples/no timeout ตัวnormalไม่ได้สร้างportable-dataเอง ผลนี้พิสูจน์ว่าไม่จำเป็นต้องเปิดportableก็reproได้ ไม่ใช่หลักฐานว่าshared portable changesไม่มีผลใด ๆ หรือพิสูจน์allocationcallerของทุกobject
- ตรวจเอกสารเดิมพบอาการและthread-inventory pattern สอดคล้องกับ **WIN-RUNTIME-004 ก่อน auto-portable**: [runtime attribution](windows-runtime-attribution.md) และ [validation](windows-validation.md) มีทั้งoldcandidate62 strictfailureและown-processcreatorstackบางรายการแล้ว ไม่ใช้TID/handleข้ามrunเป็นidentity ไม่กล่าวว่าเป็นleakใหม่จากauto และไม่ใช้ข้อมูลเก่าพิสูจน์allocationcallerของรอบใหม่
- exec318 PNGautoportableรันแยกแล้ว **ผ่าน**: quoted pathหนึ่งliteral, independent GDI+pixel decoder, expectedportable root, close/cleanup ไม่มีOSclipboardaccess ผลนี้ไม่ปิดlifecyclefailure

### สรุปขอบเขตส่งมอบเวลา 23:52

งาน auto-create เสร็จและมี local candidate ให้ลองได้: เปิด `bin\localterm-dev.exe` แล้วสร้างapp-owneddataข้างexeเมื่อยังไม่มี เก็บconfig/dataเดิม, ย้ายpathไทย/ช่องว่าง/ข้ามdriveได้ตามtestsข้างต้น รุ่นปกติไม่auto-create และไม่เปลี่ยนบัญชีHerdr/Letta/provider/GPUdefault ไม่มีcommit/push/publish

strictnative lifecycleยัง **failed/blockerเปิด** ไม่ปิดWIN-RUNTIME-004หรือเรียกready-for-distribution เพราะstartup/ZIP/PNGผ่าน ไม่เพิ่มwarmup/threshold ไม่ปิดforeignhandle/driver/settings และไม่วนrerunเพื่อกลบfailure ผลownerของรอบเก่าไม่ใช่creatorstackของรอบใหม่

ขั้นถัดไปฝั่งผู้ใช้คือทดลองเปิดexeรุ่นautoและพิมพ์ไทย/IMEจริง เกณฑ์humanacceptance/cleanVM/physicalreadonly/fullvolume/fullfiletraceและGPUworkerqualificationยังไม่ผ่านจากงานนี้ ไม่มีbackground investigationที่อ้างว่ากำลังทำต่อหลังmatchedcontrolsจบ
- ยังไม่ทดสอบ VM/clean user, physical read-only/full-volume, full file-access trace หรือ real IME ของ portable candidate จึงไม่รับรอง ready-for-distribution

## เกณฑ์ก่อนเรียกว่าพร้อม

ต้องทวน startup/config/resource/cache integration, ย้าย/เปลี่ยนชื่อ folder และ cwd, failure/read-only/no silent fallback, package dependencies และ clean-machine acceptance แยกผลผ่าน/ไม่ผ่าน/ยังไม่ทดสอบชัดเจน ก่อนเปิด interactive portable ให้ผู้ใช้ยืนยัน

หน้าต่าง IME preview ที่เปิดก่อนหน้านี้เป็น candidate เดิม ไม่ใช่ portable build ที่กำลังทำ และผล GPU parity/Core tests ไม่ใช่หลักฐาน portable acceptance
