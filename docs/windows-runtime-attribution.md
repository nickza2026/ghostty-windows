# Windows runtime: หลักฐาน handle attribution และ shutdown

## ผลต่อเนื่อง 26 ตุลาคม 2026

ดู [post-fix attribution](windows-postfix-attribution-th.md): normal strict หลังสอง launch/API-lifetime fixes ยัง +1/+1; เพิ่ม same-run verified RPC ALPC close callers และ exact returned-HANDLE creator joins ของAMD/RPCในowneddebuggercases ไม่ใช้identityข้ามrun ไม่อ้างว่าnormalgrowthถูกattributedครบและไม่ปิด `WIN-RUNTIME-004` เนื้อหาด้านล่างเป็นหลักฐานตามวันเวลาประวัติเดิม

## สถานะ 18 ตุลาคม 2026 เวลา 23:34

**ยังไม่รับรองพร้อมใช้งาน และไม่ได้เปลี่ยน strict lifecycle gate** ข้อมูล debugger เป็น attribution control ไม่ใช่ผลผ่าน performance/resource acceptance

## เครื่องมือที่ติดตั้งโดยผู้ใช้อนุมัติ

- Microsoft Debugging Tools for Windows, CDB `10.0.26100.9457`; ตรวจ Authenticode ของ installer และ `cdb.exe` เป็น Valid / Microsoft Corporation
- เลือกเฉพาะ `OptionId.WindowsDesktopDebuggers`; installer log จบ `0x0`, ไม่ต้อง restart ไม่เลือก WDK/driver/header/library components อื่น
- ติดตั้งเสร็จ 23:16:54; debugger directory รวม x86/x64/arm64 **363,351,326 bytes / 346.5 MiB** ไม่รวม symbol cache และ installer cache
- CDB x64 อยู่ `C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe`; ไม่แก้ PATH, global GFlags, driver หรือ setting ของ validation

## วิธีเก็บหลักฐาน

`tools/windows/wgl-htrace.ps1` เปิดเฉพาะ GPU-only probe ของงานนี้ ไม่ attach โปรแกรมอื่น ไม่มี Core/ConPTY/clipboard ใช้ normal heap (`-hd`), hidden/no-activate HWND, หนึ่ง warmup และ 20 cycles เดิมของ paced control เก็บ RGBA FBO readback ตามเดิม

- `!htrace -enable` / snapshot / diff ทำเฉพาะ process นี้ บน OS นี้ extension แสดงประวัติและ creator TID แต่ไม่แสดง stack PCs แม้ขอ full history จึง **ไม่อ้างว่ามี PC จาก htrace**
- exported marker แยก baseline/final โดยไม่เพิ่ม warmup; live breakpoints ที่ `NtCreateEvent`, `NtCreateThreadEx`, `NtDuplicateObject` เปิดเฉพาะหลัง baseline
- ใช้ basic stack (`k`) และเฉพาะ duplicate ของ current-thread pseudohandle สำหรับรายการสุดท้าย ไม่เขียน memory/heap dump ไม่อ่าน environment payload หรือ clipboard
- เทียบ handle/type จาก own-process PSS inventory กับ creator TID จาก htrace และ live stack ภายใน process เดียวกัน **ห้ามใช้ handle/TID ข้าม run เป็น identity**

## ผลที่พิสูจน์ได้

รอบ `cdb-wgl-htrace-20261018-232845-948`, PID `0x2a5c`:

| Handle ในรอบนี้ | ชนิด/target | Creator TID | หลักฐาน |
| --- | --- | --- | --- |
| `0x628` | Event | `0x7d7c` | มี Event-create stack หนึ่งรายการจาก TID นี้: `NtCreateEvent ← CreateEventW ← RPCRT4!ThreadSelf ← RpcpSetThreadpoolCallbackInstance ← PerformGarbageCollection ← TppTimerpExecuteCallback` |
| `0x62c` | Thread / target `32124` (`0x7d7c`) | `0x7d7c` | `NtDuplicateObject ← DuplicateHandle ← RPCRT4!ThreadSelf ← RpcpSetThreadpoolCallbackInstance ← PerformGarbageCollection` เป็น duplicate handle ของ thread ตัวเอง ไม่ใช่หลักฐานว่ามี OS thread ใหม่จากรายการนี้ |
| `0x1b8` | Thread / target `26068` | `0x2994` | retained target เริ่มใน `amdihk64.dll`; live thread-create stack มาจาก `amdihk64+0x4edd` ผ่าน NTDLL timer callback และ `CreateThread` |

รอบก่อน `cdb-wgl-htrace-20261018-232501-939` ให้ผล Event/RPC และ AMD timer สอดคล้องกัน เช่น Event `0x630` และ Thread `0x634` creator TID `0x7bdc`; ห้ามใช้เลขเหล่านี้แทน identity ของรอบข้างบน

GPU-only count ยังเป็น **224→225 handles**, GDI 1→1, USER 3→3 เช่นเดิม; history เห็น outstanding opens +3 รายการ ขณะที่ inventory เดิมเห็น ALPC Port −2 รวม net +1 **ยังไม่ได้เก็บ live close stack ของ ALPC สองรายการ จึงไม่ระบุ close owner โดยเดา**

ข้อสรุปจำกัด: มีหลักฐานของ retained opens ฝั่ง AMD hook และ RPC per-thread state ใน process ที่ไม่มี Core/PTY ไม่ใช่หลักฐานว่า handle ทั้งสามเป็น app-owned leak หรือเป็นสิ่งที่แอปควรปิดเอง ห้าม `CloseHandle`/terminate foreign threads ตาม inventory เพื่อทำให้ counter ผ่าน ทั้งหมดนี้ **ไม่รับ exception และไม่ยกเลิก failure ของ strict lifecycle**

## Burst shutdown: ยังเปิด issue

- Build43 `burst-native-20261018-201704-221` ค้างหลังตรวจ marker/Thai และ timeout 60s; เก็บ failure ไว้
- Build44 เพิ่ม info checkpoints แล้วผ่าน 3 รอบ แต่ไม่ได้เปลี่ยน shutdown logic จึงไม่ถือว่าแก้แล้ว
- Build46 เอา info checkpoints กลับเป็น debug เพื่อลด timing perturbation; บิลด์ 123/123 และ plain burst ผ่าน 10 รอบ ไม่มี debugger เกาะก่อน failure **ยังไม่ถือว่าหา root cause หรือแก้ failure เดิมได้**
- `-CaptureOwnedStacksOnTimeout` เป็น diagnostic-only: ตัดสิน timeout ด้วย 60s เดิมก่อน จากนั้น noninvasive attach เฉพาะ root process ที่ wrapper สร้างและยังถือ handle อยู่ ตรวจ executable identity/basic stacks/lock ownership แล้ว cleanup แม้ process จะออกระหว่าง capture ก็ยัง failed ไม่คืนค่า timed-out ให้ผ่าน
- กำลังทวน `burst-title` control เพื่อบังคับ bounded UI mailbox เต็มขณะ reader ส่ง OSC title และ UI เริ่ม teardown เป็นกรณีทดสอบใหม่ ไม่ใช้แทน original burst/lifecycle acceptance และยังไม่อ้างผลก่อนรันจบ

### ผล deterministic control และ candidate fix — 23:48

Build47 ผ่าน123/123; control ค้างสามรอบด้วย deadline60s เดิม (`23:36:23`, `23:38:05`, `23:40:12`) มีสองรอบที่ queue เต็มจาก OSC titles เองก่อนเติม fixture (`inserted=0`) ภาพ/Thai/child-active/title checks ถึงก่อนเริ่ม teardown ทั้งหมด

ครั้งแรก CDB ปฏิเสธ `-pd` ว่าไม่รองรับ detach-on-exit จึง **ยังไม่มี stack จากรอบแรก** แก้ collector ใช้เพียง noninvasive `-pv`; initial capture ได้ offsets แล้วเพิ่ม local PDB directory ก่อน Microsoft symbol cache จึงได้ named stacks ในรอบ23:40:

- UI: `lockUncancelable → displayUnrealized → Native Surface.deinit → closing`
- renderer: bounded-queue `push → Frame.complete → drawFrameLocked → drawFrame`; source `renderer/opengl/Frame.zig` ส่ง `.redraw` แบบ forever ขณะ draw mutex ยังถูกถือ
- reader: bounded-queue `push → surfaceMessageWriter → windowTitle`
- IO ยังรอ completion loop ไม่ได้ถึง threadExit จึง **ไม่ใช่หลักฐานว่า main รอ IO join อยู่แล้ว** การแก้เพียง join โดยไม่จัด unrealize order ยังไม่พอ

Candidate fix ถอด blocking pre-unrealize เฉพาะ Win32 final teardown ซึ่ง WM_CLOSE เรียกก่อน DestroyWindow อยู่แล้ว; Core ยัง stop/join/deinit renderer ให้เสร็จในขณะที่ HWND/DC ยัง valid เพิ่ม optional Win32 `joinWorkerDuringClose` เพื่อ drain UI mailbox ระหว่างรอ IO/renderer หลัง surface deregister แล้ว ป้องกัน producer ค้างและ late message แตะ GPU ที่กำลังถูกทำลาย Runtime อื่นใช้ `thread.join()` เดิม ไม่มีการ drop notification เปลี่ยน timeout หรือ terminate workers เพื่อปิด test

Build48 ยังไม่ผ่าน compile เพราะอ้าง `std.os.windows.exp` ผิด namespace แก้เป็น explicit kernel32 `WaitForSingleObject`; build49/regression กำลังทวน **ยังไม่มีผลรับรองจนรันจบ**

### ผลหลัง patch — 19 ตุลาคม 2026

- Build49 ผ่าน123/123; queue-full reproผ่าน3/3 (23:50:23/35/45), plainburst3/3 และ window/input/exit/missing-shell ผ่าน โดยไม่ยืดdeadlineหรือdrop .redraw/health messages; imageE2E normal ไม่ตอบconsumerจึงหยุดpipelineก่อนportable/lifecycle เก็บfailureไว้
- Build50 เพิ่ม synthetic Enter modifier isolation/dispatch receipt เฉพาะimagefixture แล้วnormal/portableE2Eผ่าน พร้อมqueue-full/burst/inputผ่านซ้ำ ไม่อ้างยืนยันย้อนหลังว่าfailure49มาจากmodifierแน่นอน
- Strict lifecycle `lifecycle-native-20261018-235936-910` ยังคง233→234handles,3→3GDI,3→3USER,6→7threads จบResourceGrowthไม่ใช่timeout ยังไม่ผ่านและไม่ยอมรับexception
- Artifact SHA256 `8674943AB93F3372ADCCAB3654B513279513D4372F6E5CA8FEF0446DC3B82EF3`; full-coreไม่filterหลังpatchกำลังรันแยก ยังไม่ใช้core/native/syntheticผ่านแทนhuman-ownedacceptance

### Full-core หลัง patch: blocked ที่ LLVM compile

รอบ `post-shutdown-full-core-50` และ retry `post-shutdown-full-core-50-j1` จบ exit1 จาก compiler exit9/LLVM out-of-memory,86/89steps ทั้งสองรอบ **test executable ยังไม่ได้รัน** ไม่มี post-patch full-core pass ที่จะนำมาแทนด้วย baseline3926/3987ก่อนหน้า

Retryลดเฉพาะ build parallelism (`-j1`),คงDebugและไม่filter tests ก่อนเริ่มWMIรายงานfree physical11,973MiB/free virtual4,706MiB ไม่ใช่ค่าpeakและไม่ใช่หลักฐานการตั้งpagefile หยุดretryหลังครั้งนี้ ไม่เปลี่ยนmemorysettings/ปิดโปรแกรมผู้ใช้/ลดtestmodeเพื่อให้ผ่าน ต้องคืนทรัพยากรก่อนทวนคำสั่งเดิม ไม่มีtestรันค้างหลังretryจบ

### ทวนหลังผู้ใช้คืนทรัพยากร — รอบเช้า 19 ตุลาคม

ผู้ใช้สั่งลองใหม่08:51: full-coreเดิมแบบ-j1/Debug/ไม่filterผ่าน **3926/3987tests,61skip,89/89steps,exit0** ในรอบ `post-shutdown-full-core-50-j1-20261019-085233` เริ่มfreeRAM20.6GiB/freevirtual25.2GiB จึงปิดOOMblockerของvalidationรอบนี้ได้ ไม่ถือว่าresource lifecycleหรือhumanacceptanceผ่านตามไปด้วย

Zig summaryระบุcompile MaxRSS9G/run MaxRSS331M; **ไม่ใช่ข้อกำหนดRAMขั้นต่ำหรือsystemcommit peak** ส่วนmemorysamplerของwrapperเก็บ178samplesแต่เห็นเพียงlauncherPID14552 ไม่ตามintermediate build processไปถึงcompiler/test จึงรายงานrounded0GiBผิดscope บันทึกcorrectionแยกในresults.jsonlและเก็บrawlogsไว้ ไม่ใช้ตัวเลขนี้อ้างว่าcompilerไม่ใช้RAM รายงานstderrยังมีข้อความ`failed command`ประกอบteststderr แต่finalsummaryระบุtest success/3926pass61skipและprocessexit0 ตรวจจากsummary/exitจริง ไม่ลบข้อความเดิม

กำลังทวนVTbaselineแล้วimageE2Eเพิ่มสองชุดต่อแยก ไม่ซ้อนfull-coreและไม่เปลี่ยนsources/gates

### ปิดรอบ automated regression — 09:27

VT `post-shutdown-vt-50-20261019-090857` ผ่าน6722/6786tests,64skip,45/45steps,exit0 หลังfull-coreจบแล้ว ImageE2Eเพิ่มสองชุด normal/portableผ่าน4sessions (`image-paste-native-20261019-092634-226`, `092644-840`, `092655-200`, `092705-543`) ทุกsessionใช้SHA256candidate50เดิมและcleanupผ่าน ไม่มีportable-datafixtureค้าง

ตอนนี้ไม่มีtestรัน ไม่ใช้การผ่านเหล่านี้ลบstrictlifecycle233→234/6→7หรือclaimhuman visual/IME/clipboard/CLI/DPIเอง ขั้นต่อไปคือmanual Thai/IME acceptance บนcandidate50ตามคำสั่งpreviewในเอกสารimage-paste และต้องคงresourcefailureไว้จนมีการตัดสินใจขอบเขตที่ชัดเจน ไม่closeforeignhandlesหรือผ่อนgateโดยอัตโนมัติ

### Candidate53 หลัง mouse/copy — 19 ตุลาคม เวลา11:43

Full-core `copy53-test-20261019-110056`ผ่าน3926/3987tests/61skip,89/89steps,exit0; VT `copy53-test-lib-vt-20261019-111609`ผ่าน6722/6786tests/64skip,45/45steps,exit0 คงDebug/-j1/ไม่filterและไม่แก้sourceจนจบ

Lifecycle `lifecycle-native-20261019-114247-673`หลัง20cycles/warmupยังResourceGrowth/exit1ไม่timeout:handles235→236,GDI3→3,USER3→3,threads6→7 Net+1/+1patternเดิมไม่ใช่หลักฐานระบุcreatorของobjectsรอบใหม่นี้ ไม่เทียบabsolute233vs235คนละprocessแล้วอ้างleakเพิ่ม2 ไม่เปลี่ยนthreshold/warmup/deadlineหรือปิดforeignhandles ยังคงfailed

Candidate53manualuserreportsผ่านrightclickcopy,wheel,dragrelease/focusloss,normalclipboardimageถึงpathตามdocsอื่น ไม่ใช้humanpassesปิดresourcegate ไม่มีtestกำลังรันหลังรอบนี้จบ

Artifact logs อยู่ `%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\phase3b-runtime`; ดู `results.jsonl` ประกอบ stdout/stderr/debugger logs ของแต่ละชื่อรอบ

### Candidate62 หลัง ConPTY และ human appearance — 19 ตุลาคม เวลา17:28

ผู้ใช้รับHerdrThaiและpreviewbackground0c0c0cแล้วตามPLAN ไม่ใช่resourcewaiver FullCore `baseline62-test-20261019-164732`:3926/3987pass61skip89/89steps และVT `baseline62-test-lib-vt-20261019-170213`:6722/6786pass64skip45/45steps ทั้งคู่exit0/ไม่timeout/-j1/Debug/no filter/sourceไม่เปลี่ยนระหว่างรัน

Parentทวนrawmodern59`lifecycle-native-20261019-141007-062`โดยแยกphaseก่อน/หลังPSSinventory พบ6→7threadsแต่มี4added/3removed ไม่ใช่แค่มีthreadใหม่1ตัว AddedTID29576startamdihk64และ15232/22572/22876startntdll;removed14192/24452/29936startntdll ข้อเท็จจริงนี้ยังไม่ระบุcreatorstackหรืออนุญาตปิดforeignobject และไม่ใช้TIDข้ามrunเป็นidentity

กำลังเก็บfreshcandidate62strictlifecycle/phasepairedTID-startmoduleJSONในownedfixtureเท่านั้น ไม่รันHerdr/อ่านsession/clipboard ไม่แก้sourceหรือgates ไม่เปลี่ยนdriver และไม่อ้างinventoryสำเร็จคือstrictgateผ่าน

### Fresh modern/native attribution — 19 ตุลาคม เวลา17:40

Normalcandidate62`lifecycle-native-20261019-173158-832`ยังstrictfailed233→234handles/6→7threads/GDIUSERstable ไม่มีtimeout เก็บthread-deltaJSON:4added/3removed หนึ่งaddedthreadentryamdihk64 อีก3ntdll ไม่ตีความnet+1เป็นOSthreadใหม่แค่หนึ่งตัว

เพิ่มเฉพาะno-op lifecycleexportmarkersในwindow.zigหลังbaseline/finalinventory ไม่มีallocation/เปลี่ยนwarmup/countthreshold แล้วbuilddiagnostic63แยกprefixnative-attribution(123/123) ไม่ส่ง63แทนaccepted62 CDBsignedMicrosoft,process-localhtrace/-hd/livebasicstacksเท่านั้น ไม่dumpheap/อ่านsession/globalGFlags/driverchanges

รอบ`cdb-native-htrace-20261019-173901-579`markerครบ/no timeout:debugcounts247→250handles/USER3→4/threads6→10 จึง**ไม่แทนnormalstrictผล** ภายในrunนี้htraceretained5opens:

| Handle | PSSชนิด/target | Htracecreator | Live-stackข้อสรุป |
| --- | --- | --- | --- |
| 82c | Thread/30504 | 6556(0x199c) | NtCreateThreadEx←CreateThread←amdihk64+0x4edd←NTDLLtimercallback |
| 85c | Event | 22960(0x59b0) | CreateEventW←RPCRT4!ThreadSelf←RpcpSetThreadpoolCallbackInstance←PerformGarbageCollection |
| 8b0 | Thread/22960 | 22960(0x59b0) | DuplicateHandlecurrent-thread pseudohandle←RPCRT4!ThreadSelf เป็นselfhandleไม่ใช่OSthreadใหม่ |
| 858 | Event | 3292(0xcdc) | ยังไม่มีตรงliveAPIstack;threadentryatio6axxไม่พอระบุallocationcaller |
| 860 | IoCompletion | 3292(0xcdc) | เช่นเดียวกัน ไม่ใช่Threadhandle |

5retainedopens/net+3ยังไม่พิสูจน์closedowner ห้ามยืมoldALPC−2มาอ้างrunนี้ เพิ่มNtOpenEvent/NtCreateIoCompletionbreakpointsเฉพาะ2gapsเพื่อรัน63เดิมอีกรอบ ไม่compile/ยกเว้นgate/closeforeignobjectsหรือทำarchitectureใหม่ก่อนscopeapproval

### Bounded trace conclusion / scope decision — 19 ตุลาคม เวลา17:48

รอบ174306-723NtOpenEvent/NtCreateIoCompletionจับAPIได้จริงแต่ไม่มีdirecthitของcreatorสองgap ต่อรอบ174618-084ขยายNtDuplicateObjectunfiltered(1029hits)ยังไม่มีhitcreator0x7640 จึงยังไม่พิสูจน์duplicatehypothesis ไม่ขยายtraceแบบเดาAPIไม่จำกัด

รอบ174618-084ภายในPID0x81c0:758Threadtarget15228creator28112(0x6dd0)มีliveamdihk64+0x4edd←NTDLLtimerstack;5f4Event/608Threadtarget33312creator33312(0x8220)มีRPCRT4!ThreadSelf←PerformGarbageCollectionstack/current-threadpseudohandleduplicate;790Event/794IoCompletioncreator30272(0x7640),threadstartatio6axxแต่ยังไม่มีตรงallocation/openstack ห้ามนำhandle/TIDรอบก่อนมาเป็นidentityหรือปิดforeignobjects

Normal62typeinventoriesEvent39→40,Thread3→5 เทียบunderCDBรอบนี้Event39→41,Thread3→5,IOCP5→6;normalIOCPcountไม่เปลี่ยน การเปรียบtype-countไม่พิสูจน์objectidentityหรือclosedowner แต่ยืนยันmeasurementมีความต่างและไม่ควรเอาCDBextraopensอ้างnormal+1ตรงๆ Normalstrictgateยังfailed ไม่มีapp-ownedfixพิสูจน์แล้ว

หยุดprobeและรอscopeapproval:ข้อเสนอแค่GPU-onlyowned-child lifecycle isolationPoCก่อนตัดสินใจrendererarchitecture ต้องคงparentresourcechecksและตรวจchildexit/noowneddescendants/จริงGLdrawpaint ไม่ย้ายปัญหาออกนอกcounterแล้วclaimpass ไม่ทำก่อนอนุมัติ ไม่เปลี่ยนdriver/globalsettings/accepted62 ไม่มีjobsรันต่อหลังสรุปนี้
