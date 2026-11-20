# บันทึกอ่านอ้างอิงสำหรับ Windows integration

ตรวจวันที่ 16 ตุลาคม 2026 โดย Letta Code ในเฟส 2 อ่านเอกสารผ่าน HTTP และ source ใน checkout ไม่ได้ใช้ browser automation ไม่ได้ทดลอง native Win32/GPU/IME จากการอ่านนี้

Baseline: `b3dc3d794513c11633e7c3347935693957744e83` พร้อม compatibility diff ที่ระบุใน `sources.md` ไม่อ่าน/คัดลอก Noctty หรือฟอร์ก ใช้ตัวอย่าง upstream เพื่อทำความเข้าใจ contract ไม่ย้าย GTK/ObjC implementation มาเป็น Win32 stub

## 1. การสร้าง HWND และ message loop

อ่านจริง HTTP 200:

- [Microsoft: Creating a Window](https://learn.microsoft.com/en-us/windows/win32/learnwin32/creating-a-window)
- [Microsoft: Using Messages and Message Queues](https://learn.microsoft.com/en-us/windows/win32/winmsg/using-messages-and-message-queues)
- [Microsoft: PostMessageW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-postmessagew)

สิ่งที่ได้: CreateWindowEx คืน HWND หรือ failure; message pump ต้องแยก GetMessage = -1, 0, >0 และ TranslateMessage/DispatchMessage; PostMessage ส่งเข้า queue ของ thread ที่สร้าง HWND และคืนก่อน handler ทำงาน

ผลต่อ design: รักษา stable app/surface allocation และ initialization state ตั้งแต่ window creation, ไม่ post borrowed pointer ข้าม lifetime, UI drain core mailbox จาก wake message ไม่ใช้ workerเรียก UIโดยตรง รายละเอียดอยู่ใน integration ส่วน 3/6/7

ยังไม่พิสูจน์: native window/state/generation/coalescing/WM_NCCREATE implementation หรือจำนวน handles ที่เครื่องจริง ต้องตรวจตอนเฟส 3

## 2. WGL context creation/current/pixel format

อ่านจริง HTTP 200:

- [Microsoft: SetPixelFormat](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-setpixelformat)
- [Microsoft: wglMakeCurrent](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-wglmakecurrent)
- [Microsoft: wglGetProcAddress](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-wglgetprocaddress)
- [Microsoft: wglDeleteContext](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-wgldeletecontext)
- [Khronos: WGL_ARB_create_context / profile](https://registry.khronos.org/OpenGL/extensions/ARB/WGL_ARB_create_context.txt)

สิ่งที่ได้: pixel format ตั้งได้ครั้งเดียวต่อ window; current context ผูกกับ thread; proc lookup ต้องมี contextและสัมพันธ์กับ pixel format; ลบ context ที่ currentอยู่บนอีก threadเป็น error; extensionให้ wglCreateContextAttribsARB และ version/profile attributes

ผลต่อ design: bootstrap contextเพื่อโหลด extensionก่อนสร้าง 4.3 core, แยก hidden GL host จาก visible GDI-painted HWND, bind/releaseและโหลด GLADตาม thread ก่อน destroy ไม่ cast WGL เป็น EGL

ข้อจำกัดการอ่าน: URL เริ่มต้น `.../windows/win32/opengl/wglmakecurrent` ได้ 404 จึงแก้ไป endpoint `.../api/wingdi/nf-wingdi-wglmakecurrent` ที่สำเร็จ ไม่อ้างหน้า 404 เป็นหลักฐาน รายละเอียด cleanup HDC ต้องตาม acquisition ของเรา ไม่ใช้คำสั่ง DeleteDC เหมารวมกับ HDC จากหน้าต่าง

ยังไม่พิสูจน์: GPU/driver ของผู้ใช้รองรับ GL4.3, extensionsครบ, context/thread handoff หรือประสิทธิภาพจริง ไม่ดาวน์โหลด DLL/driver ในงานนี้

## 3. EGL/OpenGL และ core Surface lifecycle จาก upstream

อ่าน source จริง:

| Source | ข้อสังเกตที่ใช้ใน design |
|---|---|
| `src/main_ghostty.zig` | global/core app/runtime lifecycle; runtime terminate ก่อน core app destroy ตามลำดับ defers |
| `src/App.zig` | add/delete registry แยก destructor; device lifetime ยาวกว่าทุก surface; mailbox pushเรียก runtime wakeup |
| `src/apprt/gtk/App.zig`, `src/apprt/gtk/Surface.zig` | ตัวอย่าง typed App/Surface interface โดยไม่พา GObjectมารันบน Win32 |
| `src/apprt/embedded.zig` | registration/rollback, getSize/contentScale, clipboard surface methods; มี platform/APIเฉพาะ embedding ไม่ใช่ Win32 runtime สำเร็จรูป |
| `src/Surface.zig` | initเริ่ม renderer/IO threads, deinit join/cleanup; size/DPI routing; textCallback ใช้ paste semantics; redrawส่ง action `.render` |
| `src/renderer/opengl/Device.zig` | EGL surfaceless Mesa display/config, borrowed display lifetime |
| `src/renderer/OpenGL.zig` | EGL context, GL4.3 minimum, threadEnter/Exit, CPU exported frames และ Windows DMA-BUF exclusion จาก patch ของเรา |
| `pkg/opengl/glad.zig`, `pkg/opengl/egl.zig` | GLAD pointers เป็น threadlocal; EGL wrapperไม่ใช่ WGL adapter |
| `vendor/glad/src/glad_egl.c`, `src/build/SharedDeps.zig` | generated EGL extension loaderเรียก eglGetProcAddress; compile/link EGL เฉพาะ GTK ไม่ได้จัดหา EGL runtime ให้ Windows |
| `src/renderer/generic.zig`, `opengl/Frame.zig`, `opengl/Target.zig` | latest-frame slot/ownership, gl.finish, CPU readback RGBA; UI direct drawต้องมี context contractเพิ่มไม่ใช่เพียง mutex |
| `src/config/file_load.zig` | default/legacy config paths ยังใช้ Ghostty ID ต้องแยก Windows product path อย่างตั้งใจ |

ผลต่อ design: เพิ่ม typed context adapter ไม่เปลี่ยน core VT rendererใหม่; แยก context กับ presentation; ยืนยันว่า `app-runtime=none test` ผ่านไม่ได้พิสูจน์ executable/GPU paths ที่ยังไม่ instantiate จึงมี explicit runtime build/capability gates

## 4. ConPTY spawn/communication/shutdown

อ่านจริง HTTP 200: [Microsoft: Creating a Pseudoconsole Session](https://learn.microsoft.com/en-us/windows/console/creating-a-pseudoconsole-session)

สิ่งที่ได้: กำหนด pipes/console sizeและ pseudo-console attributeให้ child; read/write channelsต้องไม่บล็อกกันจน deadlock; Microsoftแนะนำ servicing channels บน threads แยกพร้อมbuffer/queue state

อ่าน source: `src/pty.zig` WindowsPty open/resize/deinit, `src/Command.zig:305` startWindows, `src/termio/Exec.zig` Subprocess/read thread/threadExit และ command defaults

ผลต่อ design: ใช้ existing ConPTY backendก่อน, runtimeส่ง size/inputเข้าคอร์ไม่เปิดpipesซ้ำ; stop/cancel/joinต้องพิสูจน์ idle/busy/EOF/native cancellation แม้มี CancelIoExอยู่แล้ว ค่าเริ่มต้นยังเป็น cmd.exeไม่ใช่ PowerShell ต้องกำหนด shellชัด

ยังไม่พิสูจน์: ผล ClosePseudoConsole/CancelIoExต่อ blockingReadFileเมื่อ idle, process-tree policy, Unicode cwdจริง หรือ native shell exit สิ่งเหล่านี้เป็น phase4 tests ไม่ใช่ข้อสรุปจาก source

## 5. DPI และ coordinate model

อ่านจริง HTTP 200: [Microsoft: WM_DPICHANGED](https://learn.microsoft.com/en-us/windows/win32/hidpi/wm-dpichanged)

สิ่งที่ได้: wParamเก็บ DPI x/y, lParamมี suggested rectและควรใช้ SetWindowPosตาม policy เพื่อให้หน้าต่างย้าย/resizeเหมาะกับ DPIใหม่

เทียบ source: `src/apprt/structs.zig` ระบุSurfaceSize/CursorPosเป็นpixels, `src/font/face.zig` Windows default96DPI, `Surface.contentScaleCallback/sizeCallback` คำนวณ font/padding/resizeแล้วส่งIO/render messages

ผลต่อ design: manifest/awarenessก่อน HWND, scale=DPI/96, clientpixelsไม่ใช่outerrect/cells, ไม่ scaleซ้ำหรือส่ง ConPTY resizeคู่ขนานจาก runtime

ยังไม่พิสูจน์: mixed-DPI monitors, Thai IME candidate placement, resize/minimizeจริง

## 6. IME, Unicode และ clipboard

อ่านจริง HTTP 200:

- [Microsoft: WM_IME_COMPOSITION](https://learn.microsoft.com/en-us/windows/win32/intl/wm-ime-composition)
- [Microsoft: ImmGetCompositionStringW](https://learn.microsoft.com/en-us/windows/win32/api/imm/nf-imm-immgetcompositionstringw)
- [Microsoft: Clipboard Formats](https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats)
- [Microsoft: SetClipboardData](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setclipboarddata)
- [Microsoft: Alpha Blending](https://learn.microsoft.com/en-us/windows/win32/gdi/alpha-blending) — อ่านประกอบทางเลือก presentation ไม่ใช่หลักฐานว่ารองรับ transparencyแล้ว

สิ่งที่ได้: IME composition/resultต้องแยกกัน; ImmGetCompositionStringWวัดbuffer/resultเป็นbytesแม้Unicodeและอาจคืนnegativeerror; Windows textclipboardมีCF_UNICODETEXT

SetClipboardDataย้ายnative object ownershipให้ระบบเมื่อสำเร็จ และ memory objectต้องจัดสรรแบบGMEM_MOVEABLEตามAPI; ห้ามแปลงเรื่องนี้เป็นการfreeUTF-8/core request bufferโดยพลการ เพราะเป็นownerคนละชั้น

เทียบ source: `src/input/key.zig` เก็บphysicalkey/mods/consumed_mods/composing/utf8; `Surface.preeditCallback` ต้องresetเอง; `textCallback` เป็นpaste; `ClipboardReadResult` ใช้ `started/unavailable/unsupported`; clipboard confirmอาจคืนunsafe/unauthorizedโดยstateยังalive

ผลต่อ design: UTF-16 surrogate-safe conversion, IME commit/WM_CHAR dedupe, clipboardrequest exactly-onceและคงcore security/confirmation ไม่ประกาศรองรับprimaryselection/MIMEอื่นโดยไม่ทำจริง; MVPแสดงopaque DIBก่อน ส่วนtransparencyต้องมีgateแยก

เพิ่มเติมวันที่16ตุลาคม2026 อ่าน HTTP200 ก่อน implementation: [WM_IME_CHAR](https://learn.microsoft.com/en-us/windows/win32/intl/wm-ime-char), [WM_IME_SETCONTEXT](https://learn.microsoft.com/en-us/windows/win32/intl/wm-ime-setcontext) และอ่าน WM_IME_COMPOSITION ซ้ำ Unicode WM_IME_CHAR มี payload แบบ WM_CHAR; เมื่อวาด preedit เองต้อง clear ISC_SHOWUICOMPOSITIONWINDOW ก่อนส่ง WM_IME_SETCONTEXT ให้ DefWindowProc แต่ยังคง candidate UI จึงไม่ส่ง GCS_RESULTSTR เข้า PTY เองและใช้ committed-character route เพียงทางเดียว

เพิ่มเติม ownership จาก [PROCESS_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/ns-processthreadsapi-process_information),HTTP200: ผู้เรียก CreateProcessW ต้องปิดทั้ง hProcess และ hThread เมื่อไม่ใช้แล้ว Process exit ไม่ปล่อย references ของ caller ให้เอง ตรวจประกอบ pinned libxev `src/watcher/process.zig` จาก local cached archive (ไม่แก้/ไม่รับโค้ดเข้าทรี): IOCP watcher DuplicateHandle และเป็น owner เฉพาะ duplicate/job ของตัวเอง

Shutdown race: อ่านHTTP200 [CancelSynchronousIo](https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-cancelsynchronousio) และ [Canceling Pending I/O Operations](https://learn.microsoft.com/en-us/windows/win32/fileio/canceling-pending-i-o-operations) ประกอบReadFile loopจริง การcancelที่ไม่มีpendingrequestไม่ครอบคลุมreadที่เริ่มภายหลัง จึงต้องมีstickyquitและประสานการจบthread ไม่ถือcancelrequestสำเร็จเท่ากับthreadจบแล้ว

Own-handle attribution bridge `src/apprt/win32/diagnostics.c` เขียนจากpublicProcessSnapshotAPI/`processsnapshot.h`ของMicrosoftWindowsSDK10.0.26100.0 ใช้PSS_CAPTURE_HANDLESเฉพาะGetCurrentProcess,ไม่captureVM/memory/namesหรือprocessอื่น คืนborrowedhandleที่เป็นthreadเพื่อจับคู่GetThreadIdกับstart-module diagnostic ปล่อยsnapshot/markerด้วยPssFreeSnapshot/PssWalkMarkerFree ไม่ปิดborrowedhandles ไม่ใช้privateSystemHandleInformationlayout

ยังไม่พิสูจน์: IMEภาษาไทยจริง, TSF coverage, keyboardlayout/AltGr/deadkey/kittykeyboard, clipboardpermissionsจริง หรือpixels/alphaบนจอ

## 7. สิ่งที่ยังต้องตัดสินใจ/ตรวจต่อ

- ชื่อชั่วคราว/app IDก่อนแก้ exe/config/resourceจริง
- อนุมัติทิศทาง WGL context adapter + CPU DIB และnative capability spike ไม่ถือว่าเอกสารเป็นการอนุมัติ dependency/APIใหม่นอกขอบเขต
- GPU readiness/error propagationจากrenderthread, blocking-reader shutdown และperformance ต้องพิสูจน์เมื่อimplement
- ไม่มีผล independent subagent review โปรไฟล์ agentsที่มีอยู่ถูกจำกัดOlufyในรอบก่อน ไม่ได้แก้scope/ฝืนใช้เพื่ออ้างว่ามีผู้รีวิว
- ไม่มีการตรวจชื่อ/trademark availabilityของ `localterm-dev` เป็นเพียงtechnical workingnameเสนอให้ผู้ใช้ยืนยัน

เอกสารนี้เป็นสรุปเหตุผลที่ได้จากแหล่งข้างต้น ไม่ใช่ใบรับรองว่าทุกAPIเหมาะกับWindowsทุกรุ่นหรือทุกdriver; การนำไปใช้ต้องอ้าง acceptance gates ใน `windows-integration.md`
