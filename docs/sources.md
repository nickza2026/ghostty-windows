# ที่มาของซอร์สและ baseline

วันที่ตรวจ: 16 ตุลาคม 2026<br>
ขอบเขต: ตรวจประวัติ Git จาก official remote และ tracked tree ก่อนเริ่ม implementation

## Upstream ที่ยืนยันแล้ว

| รายการ | ค่า |
|---|---|
| Official repository | `https://github.com/ghostty-org/ghostty.git` |
| Local baseline commit | `b3dc3d794513c11633e7c3347935693957744e83` |
| `upstream/main` หลัง fetch | `b3dc3d794513c11633e7c3347935693957744e83` |
| Baseline tree | `26f08d48bb6a0174dc5a6bc982099fee05e62749` |
| รุ่น | `1.3.2-dev` ตาม `build.zig.zon` |
| Zig ขั้นต่ำ | `0.16.0` ตาม `build.zig.zon` |
| สาขางาน | `windows-terminal-baseline` จาก local `main` ที่ baseline เดียวกัน |

วิธีตรวจและผล:

1. เพิ่ม remote `upstream` ชี้ official repository และ fetch สำเร็จ โดยไม่เปลี่ยน `origin`
2. `git merge-base --is-ancestor b3dc3d794513c11633e7c3347935693957744e83 upstream/main` ได้ exit code 0
3. `git rev-parse upstream/main` ตรงกับ baseline ทุกตัวอักษร ไม่ได้เลื่อน HEAD หรือ merge ซอร์สใหม่
4. `git diff --quiet <baseline> --` ได้ exit code 0: tracked working tree ไม่มี diff จาก baseline ขณะตรวจ
5. `git diff --cached --quiet` ได้ exit code 0: ไม่มี staged diff

ข้อจำกัด: การตรวจนี้ยืนยัน Git provenance ของ tracked tree เทียบกับ commit ที่ official remote ประกาศ ไม่ใช่การ audit authorship ทุกบรรทัดหรือการรับรอง license ของ dependency ทั้งหมด ไฟล์ untracked ของเราไม่รวมอยู่ในคำรับรอง tracked tree นี้

## Path ของ upstream ที่ใช้เป็นฐาน

รายการต่อไปนี้มาจาก baseline SHA ข้างต้นและคง path เดิม ส่วน tracked path อื่นในทรีอ้าง baseline เดียวกันจนกว่าจะมี diff ที่บันทึกแยก:

| กลุ่ม | Path เดิม |
|---|---|
| Build | `build.zig`, `build.zig.zon`, `src/build/**`, `pkg/**` |
| Terminal/VT | `src/terminal/**`, `src/lib_vt.zig`, `include/ghostty/vt/**` |
| App/runtime | `src/App.zig`, `src/Surface.zig`, `src/apprt.zig`, `src/apprt/**` |
| Renderer | `src/renderer.zig`, `src/renderer/**` |
| Font/input/config | `src/font/**`, `src/input/**`, `src/config/**` |
| PTY/process/I/O | `src/pty.zig`, `src/Command.zig`, `src/termio/**`, `src/os/**` |
| Windows resources | `dist/windows/**` |
| Tests/examples | `.github/workflows/test.yml`, `test/**`, `example/**` |
| นโยบาย/ลิขสิทธิ์ | `AGENTS.md`, `AI_POLICY.md`, `LICENSE` |

Windows PTY ที่พบเป็นโค้ดใน official baseline ไม่ใช่โค้ดที่นำเข้าจาก Noctty ในงานนี้ การมี implementation ยังไม่ใช่หลักฐานว่าทดสอบผ่าน ดูผล runtime ใน `windows-validation.md`

## ไฟล์ local ที่ไม่ใช่ upstream baseline

| Path | ที่มา/สถานะ |
|---|---|
| `PLAN.md` | มีอยู่ก่อนเริ่มงานแบบ untracked; ปรับจากการอ่าน local source และตรวจเครื่องด้วย Letta Code ห้ามอ้างว่าเป็นเอกสาร upstream |
| `.letta/**` | มีอยู่ก่อนเริ่มงานแบบ untracked เป็น local agent/settings ไม่แก้ ไม่รวม commit อัตโนมัติ และยังไม่ได้ audit ที่มาของโปรไฟล์ |
| `docs/sources.md` | สร้างใหม่ในงานนี้จากคำสั่ง Git ที่บันทึกข้างต้น เป็นเอกสาร local ที่ AI ช่วยเขียน |
| `docs/windows-validation.md` | สร้างใหม่ในงานนี้จากผลตรวจเครื่องมือและ official Zig index เป็นเอกสาร local ที่ AI ช่วยเขียน |
| `docs/gaps.md` | สร้างใหม่ในงานนี้จาก full-core compiler diagnostics, build/import graph และผล compatibility patch/rechecks เป็นเอกสาร local ที่ AI ช่วยเขียน |
| `docs/windows-integration.md` | สร้างในเฟส 2 จาก baselineพร้อม compatibility diff และ docs Microsoft/Khronos; design proposalเท่านั้น ยังไม่มี Win32/WGL implementation |
| `docs/reference-notes.md` | สรุปเอกสารทางการที่เปิดอ่าน HTTP200จริงกับ upstream source paths ครอบคลุม HWND/WGL/ConPTY/input/IME/core surface; บันทึกหน้า404ที่แก้endpointแล้ว ไม่ใช้Noctty |

### Local compatibility changes ที่กำลังตรวจ

ผู้ใช้อนุมัติแก้ compatibility ของ `posix_c` วันที่ 16 ตุลาคม 2026 เวลา 11:41 GMT+7:

| Path | การเปลี่ยนจาก baseline | ที่มาของเหตุผล |
|---|---|---|
| `src/build/SharedDeps.zig` | เพิ่ม guard ไม่สร้าง/translate import `posix_c` เมื่อ target เป็น Windows; รายการ POSIX headers และพฤติกรรม non-Windows คงเดิม | Full-core log `pwd.h not found`, OS guards ของ `pty-c` ในไฟล์เดียวกัน, Windows bindings/process path เดิม และการตรวจ consumers ใน `src/os/passwd.zig`, `src/os/desktop.zig`, `src/config/Config.zig`, `src/termio/Exec.zig` |
| `src/renderer/OpenGL.zig` | หลังอนุมัติขยายขอบเขต DMA-BUF เวลา 11:44 GMT+7 เพิ่ม Windows-only compile-time exclusion ของ DMA-BUF export/payload ใช้ CPU-buffer path เดิม และเพิ่ม platform-payload/memory-cleanup test | Compiler reference chain จาก `Dmabuf.zig:44` ผ่าน `ExportedFrame`; export/cleanup และ fallback code เดิมของ official baseline ไม่เปลี่ยน `Dmabuf.zig` หรือ Linux export |
| `build.zig` | เพิ่ม explicit Windows window-only build/run targetsโดยไม่เปลี่ยนdefault build/runtime | เฟส3Aตามdesignที่ผู้ใช้ยืนยันชื่อและทิศทางเวลา12:46; std.Build APIในbaseline |
| `src/apprt/win32/window_main.zig`, `src/apprt/win32/window.zig` | โค้ดใหม่ของเรา: nativeWin32 window/message pump/paint/client size/DPI/teardown และsmoke mode ไม่ใช่coreApp/Surfaceimplementationเต็ม | Microsoft API contractsใน `reference-notes.md`, std.os.windows ABIและprocess argsของZig0.16ที่ติดตั้ง ไม่รับโค้ดฟอร์ก |
| `dist/windows/localterm-dev.rc`, `dist/windows/localterm-dev.manifest` | resource/manifestใหม่ ProductName/filenameเป็นlocalterm-dev, PerMonitorV2/asInvoker, ไม่มีGhostty icon | รูปแบบWin32 VERSIONINFO/manifestสำหรับproductใหม่ ไม่แก้LICENSE/attributionของupstream |

เฟส3Aตรวจfinalartifactเวลา12:56:59 GMT+7: windowbuild+smokeexit0,20รอบหลังwarmupresourcecountsคงที่, metadataและembeddedmanifestตรวจผ่าน; sourceเดิมVTcompileและcoretargetedregressionผ่าน ดูcommands/logs/ขอบเขตที่ยังไม่implementในvalidation ยังไม่มีCoreSurface/PTY/WGLcontextหรือfullWin32runtimeในprototype

Patch นี้เขียนในรีโปโดย Letta Code จาก local baseline/build diagnostics ไม่รับโค้ดจาก Noctty หรือฟอร์ก ไม่สร้าง POSIX stub หรือปิดเทสต์ ยังไม่ commit การยืนยัน provenance เดิมครอบคลุม baseline ก่อน patch ส่วน tracked diff ปัจจุบันต้องอ้างรายการนี้แยก

ผลตรวจล่าสุด: targeted 76/76 tests ผ่าน และ full-core หลัง patch ทั้งสองผ่าน exit 0 เวลา 11:59:52 GMT+7 (3,917 passed, 61 skipped); VT retry หลัง runner timeout ผ่านเวลา 12:13:16 (6,722 passed, 64 skipped) ตรง baseline เดิม และ library build หลัง patch ผ่านเวลา 12:14:08 (48/48 build steps, exit 0) พร้อม format/diff checks ดูหลักฐานและข้อจำกัดใน `windows-validation.md` ยังไม่มีการทดสอบ Linux/GPU หรือ independent agent review และยังไม่ยืนยัน root cause ของ timeout รอบก่อน

ยังไม่มี `reference/noctty` ใน checkout และงานนี้ไม่ได้ clone Noctty หากเพิ่มไฟล์ใหม่หรือแก้ upstream path ในอนาคต ต้องเพิ่มรายการ path, เหตุผล, เอกสารอ้างอิง และ commit ของเราเมื่อผู้ใช้อนุมัติให้ commit

## Remote และการเลื่อน baseline

- `origin`: `https://github.com/nickza2026/ghostty-windows` สำหรับรีโปผู้ใช้ ไม่ได้ rename หรือ push
- `upstream`: fetch จาก official Ghostty; push URL ตั้งเป็น `DISABLED` เพื่อกันพลาด ไม่ใช่ authorization boundary
- ไม่ reset/clean/rebase/merge และไม่เลื่อน baseline ระหว่างการเตรียมเครื่อง
- เมื่อจะเลื่อน SHA ต้องบันทึก SHA เก่า/ใหม่, diff ของ upstream, ผลทดสอบ และ local integration ที่ต้องปรับก่อนดำเนินการ

## ประวัติ

| วันที่ | Baseline เดิม | Baseline ใหม่ | เหตุผล |
|---|---|---|---|
| 16 ตุลาคม 2026 | ไม่มีรายการในเอกสาร | `b3dc3d794513c11633e7c3347935693957744e83` | บันทึก checkout ที่มีอยู่และยืนยันตรงกับ official `upstream/main`; ไม่ได้เปลี่ยนซอร์ส |
## เพิ่มเติม: original Win32 implementation หลังเฟส3A

งานบนbranchเดิมไม่มีprojectcommit/push เพิ่มruntimeenum/typecontractsในsrc/apprt/runtime.zig,apprt.zigและswitchesที่ต้องexhaustive;ไฟล์ใหม่src/apprt/win32.zig,win32/App.zig,Surface.zig,window.zig,presenter.zig,text_input.zigเป็นโค้ดที่เขียนในงานนี้จากcontractsของbaselineและAPIอ้างอิงในreference-notes ไม่รับไฟล์จากNoctty

src/renderer/opengl/wgl.zigเป็นtypednativeWGLadapterของเรา;src/win32_gl_probe.zigเป็นcapability/lifetimeprobe ใช้GLADที่baselineมีอยู่แล้ว ไม่เพิ่มproviderหรือcastHGLRCเป็นEGLContext OpenGL.zigเลือกcontext/backendตามOSและใช้CPUframeบนWindows;non-WindowsคงEGLpath

pkg/opengl/glad.zigแก้zero-initialization/resetของTLScontextจากnativecrashที่generatedC.glLoaderUnloadใช้garbageloaderhandle โดยอ่านvendor/glad/src/gl.cและinclude/glad/gl.hในbaseline ไม่แก้generatedvendorcode เพิ่มemptyresolver/reloadtestและยืนยันnative20cycles

src/termio/Exec.zigกับsrc/os/windows.zigแก้WindowsquitpipeHANDLE close/writeและReadFileEOFตามnativepathจริง;ไม่เปลี่ยนPOSIXbranchหรือสร้างPTYใหม่ทับของbaseline tools/windows/runtime-smoke.ps1เป็นharnessของเราเฉพาะownedtestprocesses ไม่ใช้Nocttyscripts

การทดสอบหลัง3B:full-core3918pass/61skip,VT6722pass/64skip,lib48/48;หลัง4Bpipepatch:targeted77และnativeoutput/closegateผ่าน ดูเวลา/command/hash/ขอบเขตที่ยังไม่runในwindows-validation.md ข้อมูลนี้ไม่ใช่independentreviewหรือhumanvisualapproval

ส่วน input/IMM32/CF_UNICODETEXT ใน `src/apprt/win32/{App,Surface,window,text_input,ime,clipboard}.zig` เขียนเองจาก core contracts และ Microsoft API ใน `reference-notes.md` ไม่ได้ยก implementation จากฟอร์กอื่น การ decode/geometry tests แยกจากการยืนยัน native IME/clipboard จริง

ระหว่าง stress พบ `CreateProcessW` คืน `hThread`/`hProcess` แต่ `Command` เดิมไม่ release ทั้งสอง: เพิ่มการปิด primary-thread handle หลัง spawn และ `Command.deinit` สำหรับ owned process handle พร้อมเรียกใน `Exec.Subprocess.stop/externalExit` ฝั่ง Windows ไม่เปลี่ยน POSIX reaping semantics; libxev IOCP watcher ถือ duplicate ของตนเองตาม pinned archive SHA ใน `build.zig.zon` ไม่แก้ dependency นั้น ผล lifecycle หลัง patch ยังต้องวัด ไม่รับรองจาก code review อย่างเดียว

หลังburst fixtureพบhangจริง แก้เฉพาะWindowsใน`src/Surface.zig`ให้IOproducer/readerจบก่อนrendererconsumer และ`Exec.zig`ตรวจquitทุกread+CancelSynchronousIo retryจนthreadจบ มีdelayed-read regressionและnativeburst/exit/inputผ่าน ดูreceiptในvalidation ส่วน`diagnostics.c`เป็นoriginalmetadata-onlybridgeจากMicrosoftSDK/publicPSSAPI ใช้เฉพาะlifecycle smoke ไม่มีVM clone/อ่านmemory/name/processอื่นและไม่closeborrowedhandles

Performance tooling: `src/win32_frame_bench.zig` เขียนเอง ใช้WGLadapter/presenterของcheckoutนี้, QPC และMicrosoftGDI memoryDC/DIBsectionสำหรับcomponentcost ไม่รับโค้ดจากfork ไม่เปิดshell/อ่านข้อมูลผู้ใช้ ไม่เปลี่ยนrendererเพื่อทำbenchmark ขนาดprofilewindowใช้GetClientRect/GetWindowRect/AdjustWindowRectExForDpiและWM_GETMINMAXINFOเฉพาะfixtureเพื่อยืนยันclient1920×1080จริง ไม่แก้globalwindow/systemsettings; `window_main.zig --profile-size-probe`เป็นleafไม่มีCore/GPU/PTYและติดตั้งในlogprefixแยกไม่ทับfullruntime
