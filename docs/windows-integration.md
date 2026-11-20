# แบบเชื่อมต่อ Win32 กับคอร์ Ghostty

วันที่: 16 ตุลาคม 2026<br>
Baseline upstream: `b3dc3d794513c11633e7c3347935693957744e83`<br>
ขอบเขต: เฟส 2 ออกแบบ integration ก่อนเขียน runtime และก่อนสร้างหน้าต่าง<br>
สถานะ: design proposal ที่ตรวจเทียบ local source และเอกสารทางการแล้ว ไม่ใช่ผล implement/GPU/IME ผ่าน

อัปเดตหลัง design: ผู้ใช้ยืนยันชื่อ `localterm-dev` และทิศทาง WGL adapter + CPU DIB เวลา 12:46 GMT+7 แล้ว เริ่มเฟส3Aเป็น window-only prototype ใน `src/apprt/win32/window_main.zig`/`window.zig` ผ่าน opt-in build target `windows-window` ไม่ใช่ runtime `win32` ที่ต่อคอร์ครบ ยังไม่มีcontext/shell/config loading และไม่ถือว่า3Bหรือgraphics gatesผ่าน ดูผลจริงใน `windows-validation.md`

## 1. จุดเริ่มและสิ่งที่ห้ามตีความเกินหลักฐาน

- อยู่บนสาขา `windows-terminal-baseline` ไม่สร้าง worktree เพิ่ม
- มี compatibility diff ที่อนุมัติแล้วใน `src/build/SharedDeps.zig` และ `src/renderer/OpenGL.zig`; การอ้าง source ด้านล่างหมายถึง baseline **พร้อม diff สองไฟล์นี้**
- Full-core ผ่าน 3,917 tests ข้าม 61; VT retry ผ่าน 6,722 tests ข้าม 64; library build ผ่านแล้ว ดู `windows-validation.md` สำหรับ commands, logs และเหตุ runner timeout รอบก่อนที่ยังไม่ทราบ root cause
- ยังไม่มี `win32` ใน `src/apprt/runtime.zig` หรือ runtime switch ของ executable, ยังไม่มีหน้าต่าง/renderer context/shell session ของแอปเรา
- ไม่มีการนำเข้า Noctty หรือ dependency EGL/WGL เพิ่มในเฟสออกแบบนี้ ไม่ได้อ้างว่าทดสอบ GPU จากผล unit tests
- ชื่อแอปยังต้องให้ผู้ใช้ยืนยันก่อนเฟส 3: เสนอชื่อชั่วคราว `localterm-dev` และ application/config ID เดียวกัน ชื่อนี้ยังไม่ใช่ชื่อที่นำไปใช้จริงใน build

## 2. คำตัดสินทางสถาปัตยกรรมที่เสนอ

| ID | ข้อเสนอ | เหตุผลและขอบเขต |
|---|---|---|
| R1 | เพิ่ม Zig runtime `win32` ใน process เดียวกับคอร์ | ใช้ `CoreApp`/`CoreSurface` และ encoder/thread model เดิม ไม่ใช้ C embedding API ที่ยังมีส่วนเฉพาะ macOS เป็นทางลัด |
| R2 | เริ่มเพียงหนึ่ง visible HWND และหนึ่ง terminal surface | ไม่ทำแท็บ/สปลิต/session restore/IPC server ในช่วงแรก; ไม่เปลี่ยน core collection ให้รองรับได้แค่หนึ่ง surface |
| G1 | เสนอ WGL backend สำหรับบริบท OpenGL บน Windows; เก็บ EGL เดิมบน non-Windows | EGL ปัจจุบันเลือก `EGL_PLATFORM_SURFACELESS_MESA`; ไม่มีหลักฐานว่าเครื่องมี EGL provider ที่ตรงกับ desktop GL 4.3 และบิลด์ผูก `egl` เฉพาะ GTK |
| G2 | เก็บ FBO renderer และ CPU-frame presentation เดิมในรุ่นแรก | Context backend ไม่เท่ากับ presentation backend ไม่เขียน renderer ใหม่หรือเปลี่ยนเป็น DirectX; UI วาด DIB จาก frame ที่คอร์ส่งมา |
| P1 | ใช้ WindowsPty/Command/termio เดิมก่อน | มี ConPTY spawn/I/O/resize/cleanup แล้ว ต้องทดสอบ lifecycle จริง ไม่เขียน PTY implementation คู่ขนาน |
| I1 | Win32 UI thread เป็นเจ้าของ event/input/IME/clipboard | Worker ส่ง mailbox/wakeup เท่านั้น ไม่เรียก UI API จาก renderer/IO thread โดยตรง |
| S1 | เฟส 3 เปิดหน้าต่างได้โดยยังไม่เรียก `CoreSurface.init` | `CoreSurface.init` เริ่ม renderer/IO threads และเตรียม shell จึงไม่ควรสร้างเพื่อให้ได้หน้าต่างเปล่าหรือใช้ dummy renderer/PTY |

G1/G2 เป็นทิศทางที่แนะนำ ไม่ใช่หลักฐานว่าบนเครื่องทำได้แล้ว ก่อนเฟส 4 ต้องผ่าน capability spike และการยืนยันแนวทางนี้ หาก WGL ไม่มี desktop GL 4.3 หรือ readback ช้าเกินรับได้ ให้หยุดเสนอทางเลือก ไม่แอบรับ Mesa/ANGLE หรือเปลี่ยน renderer ทั้งชุด

## 3. จุดจริงในซอร์สและ contract ที่ runtime ต้องทำ

### 3.1 Entry point, App และ build graph

| ตำแหน่ง | Contract จริง | สิ่งที่ Win32 ต้องทำ |
|---|---|---|
| `src/main.zig`, `src/main_ghostty.zig:26–115` | global init → `App.create` → runtime `init(app, .{})` → `run`; defer runtime `terminate` ก่อน core `destroy` | ใช้ flow นี้ต่อ ตรวจ errors/exit path ของ exe ใหม่ ไม่ถือว่าทาง executable ถูกทดสอบด้วย `app-runtime=none` แล้ว |
| `src/apprt/runtime.zig`, `src/apprt.zig:43–49` | enum และ compile-time selection มี `none`, `gtk` | เพิ่ม `win32` และ module exports `App`, `Surface`, `resourcesDir`; default Windows คง `none` ในช่วงทดลอง ใช้ explicit opt-in หลัง implement |
| `src/App.zig:164`, `:595` | `tick(rt_app)` drain mailbox; `Mailbox.push` enqueue แล้วเรียก runtime `wakeup()` | `wakeup` thread-safe และไม่บล็อก worker; UI message handler เรียก `tick` โดยไม่ถือ queue lock ขณะ dispatch |
| `src/App.zig:202–247` | `addSurface` ลงทะเบียน; `deleteSurface` เอาออกแต่ **ไม่** destruct/free | native runtime เป็นเจ้าของ surface allocation และเรียก lifecycle ให้ครบ ห้าม delete แล้วคิดว่า core threads หยุดแล้ว |
| `src/App.zig:136–150` | core app deinit ทำลาย surfaces, font cache แล้วค่อย `device.deinit` | ตอน runtime terminate ต้องปิด surface ให้ถูกและไม่ปล่อย render device/context host ก่อนผู้ยืมหยุด |
| `src/build/GhosttyExe.zig`, `dist/windows/ghostty.rc` | มี `.Windows` subsystem และ resource เดิม แต่ชื่อ/ไอคอนเป็น Ghostty | เปลี่ยนเฉพาะ product artifact ของเรา; คง attribution และไม่ใช้ไอคอนเดิมเป็นแบรนด์ |

`App` interface ใช้ `src/apprt/gtk/App.zig` เป็นตัวอย่าง signature: `init`, `run`, `terminate`, `wakeup`, `performAction`, static `performIpc`, `redrawInspector` การ compile runtime ใหม่อาจทำให้พบ optional hook/contract เพิ่ม ต้องไล่ call sites ไม่ประกาศว่าเพียงเท่านี้ครบทุก path ที่ core อาจ instantiate

`performIpc` รุ่นแรกคืน `false` อย่างตรงไปตรงมาเพราะไม่มี IPC server ไม่ตอบสำเร็จทั้งที่ไม่ได้ส่ง ห้ามใช้รูปแบบนี้เป็น stub ของ operation ที่เฟส acceptance ต้องรองรับจริง

### 3.2 Surface interface

อ้างอิง signatures: `src/apprt/gtk/Surface.zig` และ `src/apprt/embedded.zig:634–715,1213–1256` ไม่ดึง GTK/ObjC มาเป็น dependency ของ runtime ใหม่

| กลุ่มเมธอด | ค่า/ความหมายที่ต้องคง |
|---|---|
| `core()`, `rtApp()` | stable pointer หลัง initialization สำเร็จ; window userdata ต้องไม่ชี้ไปยัง stack/local ที่ย้ายตำแหน่ง |
| `getSize()` | `apprt.SurfaceSize` หน่วย **client pixels** ไม่ใช่ window outer rect, DIP หรือจำนวน cell |
| `getContentScale()` | `apprt.ContentScale{x,y}`; Windows core ใช้ default DPI 96 (`src/font/face.zig`), ดังนั้น scale = DPI/96 |
| `getCursorPos()` | client pixel coordinates ตาม `apprt.CursorPos`; อย่า scale ซ้ำเมื่อ Win32 ส่ง physical pixels อยู่แล้ว |
| `getTitle()`, `close(process_active)` | title เป็น owned UTF-8 ของ runtime; close request ต้องเข้า state machine ไม่ free object ทันทีใน callback ที่ยังใช้มัน |
| `renderDeviceOptions()` | คืน options ของ backend ที่เลือก ไม่ส่ง HDC ให้ EGL display ผ่าน pointer cast |
| `defaultTermioEnv()` | owned environment map ตามคอร์คาด; เริ่มจาก global environment เดิม ไม่ dump ค่า secrets ลง log |
| clipboard methods | `supportsClipboard`, `clipboardRequest`, `setClipboard` ตาม contracts ในส่วน 8 ไม่จำลอง Linux selections |

`CoreSurface.init(alloc, config, app, rt_app, rt_surface)` ที่ `src/Surface.zig:475` อ่าน size/DPI ก่อนสร้าง font/device/renderer และเริ่ม renderer/IO threads ภายในฟังก์ชันเดียว (`:562` และ `:736` เป็นต้นไป) จึงต้องมี native state และ context-host ที่พร้อมก่อนเรียก ไม่สร้าง thread/PTY ซ้ำจาก runtime

ใน `CoreSurface.close` ค่าที่ส่งให้ runtime close คือ `needsConfirmQuit()` แม้บาง wrapper ใช้ชื่อพารามิเตอร์ `process_active` ห้ามตีความว่าเป็นผล query ว่า process ยังมีชีวิตหรือใช้เป็นเหตุ force-kill โดยตรง และใน embedded example มี `addSurface` ก่อน core init พร้อม rollback `deleteSurface` เมื่อ init fail: runtime ใหม่ต้องกำหนด registered/core_initialized flags แยกกันและ gate callbacks ระหว่าง initializing ไม่เรียก `core()` บน undefined state

### 3.3 ชื่อผลิตภัณฑ์, config และ resources

- `src/config/file_load.zig` ปัจจุบันมี `ghostty/config.ghostty` และ legacy `ghostty/config`; ห้ามใช้ default เหล่านี้เป็น config ของผลิตภัณฑ์เราโดยไม่ตั้งใจ
- เสนอ Windows config path `%LOCALAPPDATA%\<app-id>\config.ghostty` โดยคง syntax/core parser เดิม; path นี้ยังไม่ implement และ `<app-id>` รอยืนยันชื่อ ถ้า LOCALAPPDATA ไม่มี ให้แจ้งเหตุ/ใช้ policy ที่ออกแบบชัด ไม่เดา path จาก current working directory
- ยังคง explicit config/CLI override semantics ของ core แต่ไม่ migrate/copy config Ghostty เดิมอัตโนมัติ ไม่อ่าน secrets หรือเขียน user profileระหว่าง design
- resourcesDir ต้อง resolve จาก package/executable layout ของเรา ไม่อาศัยโฟลเดอร์ build/cwd และไม่สมมติว่าเปลี่ยน exe name แล้ว lookup paths จะเปลี่ยนเอง
- เปลี่ยน Windows executable/version resource/window title/application class IDs ในขอบเขตผลิตภัณฑ์ ไม่แทนที่คำ Ghostty ทั้งรีโปซึ่งอาจเป็น attribution/API/escape compatibility ที่ต้องเก็บ

### 3.4 Runtime enum มีผลมากกว่าสองไฟล์

เพิ่ม case ที่เกี่ยวข้องและคง semantics ของ GTK/none ใน:

- `src/build/SharedDeps.zig` — dependency switch, system libraries และ EGL linkage
- `src/apprt/action.zig`, `src/apprt/structs.zig`, `src/apprt/surface.zig` — `getGObjectType` และ backing types
- `src/config/Config.zig`, `src/datastruct/split_tree.zig`, `src/font/face.zig`, `src/input/Binding.zig`, `src/terminal/mouse.zig` — runtime-specific switch ที่ค้นพบ
- ตรวจ `src/build/Config.zig` และ generated build options ให้สะท้อน enum เดียวกัน

รายการนี้มาจาก exact search ในทรี ไม่ใช่หลักฐานว่าเพิ่ม runtime แล้ว compile ผ่าน ต้อง build explicit runtime target เพื่อจับ exhaustive switches/instantiation เพิ่ม ห้ามแก้โดยเปลี่ยนทุก switch เป็น `else` แล้วกลบ platform behavior

## 4. เหตุใด EGL เดิมยังเสียบกับ HWND ไม่ได้ทันที

1. `src/renderer/opengl/Device.zig:39–68` เรียก `egl.load`, สร้าง surfaceless Mesa display และเลือก OpenGL RGBA8 config แบบไม่มี window surface
2. `OpenGL.init` สร้าง EGL context 4.3 core, bind/release บน thread ที่ init; `threadEnter/threadExit` bind/release อีกครั้งและโหลด GLAD แบบ thread-local
3. `pkg/opengl/egl.zig` ใช้ raw EGL symbols; `vendor/glad/src/glad_egl.c` โหลด extension ผ่าน `eglGetProcAddress` **ไม่ใช่**ตัวที่จัดหา EGL DLL หรือแปลง WGL เป็น EGL
4. `src/build/SharedDeps.zig` compile `glad_egl.c` และ link `egl` เฉพาะ `.gtk`; unit tests `.none` ที่ผ่านไม่ได้พิสูจน์ว่า EGL functions ที่ยังไม่ถูกใช้จะ resolve ได้ใน Win32 executable
5. `OpenGL.present` ใช้ CPU readback บน Windows หลัง compatibility patch; `Frame.complete` เรียก `gl.finish`, `pushFrame` และส่ง `.redraw` ให้ UI ไม่ได้เรียก `SwapBuffers(HWND)`

### ทางเลือกที่ประเมิน

| ทาง | ข้อดี | งาน/ความเสี่ยง | ข้อสรุปเฟสนี้ |
|---|---|---|---|
| EGL บน Windows | ใกล้ device/context API เดิม | ต้องเลือก provider, desktop OpenGL 4.3, surfaceless/pbuffer/window extensions, DLL source/version/license/packaging; ยังไม่มีหลักฐานพร้อม | ไม่เลือกเป็นค่าเริ่มต้น และไม่ติดตั้ง provider โดยอัตโนมัติ |
| WGL context adapter + CPU DIB | ใช้ Win32/OpenGL driver path; แยก platform glue โดยรักษา renderer/FBO/input core | ต้องเขียน context/device dispatch adapter และ pixel presenter; มี readback bandwidth/latency | **แนะนำสำหรับ single-window MVP หลัง spike ผ่าน** |
| WGL direct window swap | ลด CPU readback ระยะยาว | ต้องเปลี่ยน presentation/FBO/thread ownership มากกว่า adapter; ไม่ตรง latest-frame UI contract เดิมโดยตรง | งานภายหลัง ไม่ใช้เป็นทางลัดในเฟส 3 |
| ANGLE/OpenGL ES หรือ DirectX renderer | อาจเหมาะกับการแจกบางเครื่องในอนาคต | ไม่ใช่ desktop GL 4.3 API เดิม และเป็น dependency/renderer scope ใหม่ | นอกขอบเขต ต้องเสนอและขออนุมัติแยก |

## 5. WGL adapter ที่เสนอ — ยังไม่มี implementation

### 5.1 ขอบเขต module และ ABI

- เพิ่ม context backend ภายใน `src/renderer/opengl/` แยก EGL/WGL ด้วย compile-time target OS; ชื่อไฟล์ในเอกสารเป็น **ข้อเสนอ** ไม่ใช่ path ที่มีแล้ว
- `Device` ที่ core มองเห็นยังเป็น app-scoped ใช้สำหรับ config/dispatch initialization; per-surface context ยังเป็นเจ้าของโดย OpenGL API instance เดิม
- ย้ายการสร้าง context, make/release current, proc lookup และ destroy ผ่าน adapter contract; ไม่ปลอม HGLRC ให้เป็น `*egl.Context` และไม่คง EGL call ที่ต้อง link บน Windows แล้วหวังว่าจะไม่ถูกเรียก
- รักษา init/threadEnter/threadExit/deinit ของ GraphicsAPI ที่ generic renderer เรียก; non-Windows เลือก implementation EGL เดิม
- เพิ่ม Windows libraries เฉพาะ build ที่ใช้จริง เช่น `user32`, `gdi32`, `opengl32`, `imm32`; ตรวจ kernel32/bindings เดิมก่อนเพิ่ม ไม่รับ script/build flags จากฟอร์ก

### 5.2 Context host แยกจาก visible window

เพื่อไม่ผสม GDI painting กับ pixel format ของ OpenGL บน HWND เดียวกัน เสนอ hidden context-host HWND/HDC แยกต่อ surface ส่วน visible HWND ใช้ DIB presenter ปกติ ไม่สร้างหน้าต่าง visible เพิ่ม

1. App-scoped WGL device สร้างและเป็นเจ้าของ bootstrap context host แยกสำหรับโหลด WGL extensions; ต้องไม่ยืม HWND/HDC ของ surface แรกแล้วทำให้ surface ปิดไม่ได้
2. สร้าง host window ด้วย class/private-DC policy ที่บันทึกชัด เลือก pixel format และ `SetPixelFormat` ได้ **ครั้งเดียวต่อ window** ก่อนสร้าง context
3. สร้าง legacy bootstrap context ชั่วคราวเพื่อเรียก `wglGetProcAddress` แล้วตรวจ `WGL_ARB_create_context`/profile และ attributes ที่ต้องใช้ ไม่รับ OpenGL 1.1 เป็นการผ่าน requirement 4.3
4. Runtime surface เตรียม hidden host ของตนก่อน `CoreSurface.init`; OpenGL adapter รับ native target ผ่าน contract ที่ typed ชัดเจน ต้องเพิ่มเมธอด/options จริงภายหลัง ไม่สมมติว่ามีอยู่แล้ว
5. สร้าง per-surface 4.3 core context กับ HDC ของ surface; ตรวจ actual GL version และ features ที่ renderer ใช้ ไม่พึ่งว่า request 4.3 แล้วจะสำเร็จเสมอ
6. Proc resolver ใช้ current WGL context กับ `wglGetProcAddress`; core symbols ใช้ `GetProcAddress` จาก trusted system `opengl32.dll` ตามความจำเป็น ตรวจ return/calling convention ให้ตรง GLAD โดยเฉพาะไม่ปน WinAPI กับ C callback ABI
7. Release current หลัง init ก่อนส่งงานให้ renderer thread; renderer `threadEnter` make current และโหลด `pkg/opengl/glad.zig` threadlocal; `threadExit` unbind/unload ก่อน UI thread destroy context

Context เดียวห้าม current สอง threads และห้ามลบ context ที่อีก thread ยังใช้อยู่ ไม่ใช้ `SwapBuffers` เป็นเกณฑ์ว่า renderer ถูกต่อแล้ว เพราะข้อเสนอ MVP ยัง export CPU frames จาก FBO

### 5.3 Capability spike ก่อนเปิด shell

แยก spike ที่ไม่มี PTY/`CoreSurface.init`: create/bootstrap → 4.3 core context → โหลด GLAD → draw FBO รูปทดสอบกำหนดสี/มุม → readback → ทำลายครบ ทดสอบ handoff UI→worker→UI และเปิด/ปิดอย่างน้อย 20 รอบ

บันทึก driver, GL vendor/renderer/version, extension ที่ต้องใช้จริง, create/makeCurrent/readback/destroy errors และจำนวน handles/threads ก่อนหลัง ไม่ log environment ทั้งชุด ถ้าไม่ผ่าน ให้หยุดก่อน surface/shell startup ไม่ fallback เป็น GL 1.1/software/EGL โดยไม่แจ้งและไม่ดาวน์โหลด driver

## 6. Frame presentation และ UI scheduling

```text
ConPTY output → termio/VT → renderer thread / FBO
                               |
                         CPU RGBA8 frame
                               |
                     latest-frame slot (คอร์)
                               |
                  mailbox .redraw → App.wakeup
                               |
                  UI tick → runtime redraw handler
                               |
              takeFrame → owned DIB → WM_PAINT
```

หลักฐาน: `src/renderer/opengl/Frame.zig:57–86`, `src/renderer/generic.zig:1015–1070`, `OpenGL.ExportedFrame.Memory` และ `opengl/Target.zig:223` เป็นต้นไป

- ใช้ `takeFrame` **เฉพาะ UI thread** ผู้รับเป็นเจ้าของ frame และต้อง deinit ครั้งเดียว; slot เก็บ latest-only และ deinit ภาพเก่าที่ถูกแทนอยู่แล้ว ห้าม runtime เก็บ pointer ยืมไปใช้หลัง deinit
- ทางที่ยืนยันจากซอร์ส: Surface mailbox `.redraw` → `Surface.handleMessage` → private `Surface.redraw` (`src/Surface.zig:1759`) → runtime `performAction(..., .render, {})`; runtime `.render` ดึง latest frame/invalidate บน UI ไม่เรียก core draw ซ้ำจาก `WM_PAINT`
- `WM_APP` wakeup ใช้ stable app/surface identity กับ generation; ไม่ post pointer ของ stack, borrowed frame หรือ surface ที่อาจถูก free ก่อนรับ message
- อาจ coalesce wakeups ได้ แต่ clear pending flag และ drain protocol ต้องไม่ทำ lost wakeup; ทดสอบ worker push ระหว่าง UI drain และหลัง close
- UI ดึง frame มาแปลงเป็น owned DIB บน UI หรือ buffer ที่ ownership ระบุชัด แล้วปล่อย RGBA frame; `WM_PAINT` ใช้ latest DIB ที่ยังอยู่ ไม่อ่าน mutable renderer state โดยข้าม mutex
- Source เป็น tightly packed **RGBA8 premultiplied**, stride `width*4`, sRGB-encoded จาก `glReadPixels` ไม่ใช่ BGRA ของ DIB; ต้องตรวจ integer overflow/ขนาดก่อน allocate และแปลง channels/row orientation อย่างตั้งใจ
- กำหนด top-down DIB และตรวจภาพมุมซ้ายบน/ขวาล่างจาก spike เพื่อยืนยัน row flip ไม่เดาจาก screenshot ว่า orientation ถูก
- MVP เป็น opaque window; transparent-background config ต้องแจ้ง unsupported/validate ให้ชัด ไม่เอา premultiplied alpha ไปแสดงเป็น opaque โดยไม่ flatten หรือรองรับ alpha blending จริง
- เมื่อ minimize/hidden ให้หยุด paint/render ตาม visibility callback และไม่สร้าง framebuffer ขนาดศูนย์; restore ต้อง redraw โดยใช้ size/DPI ใหม่

### ข้อยกเว้น main-thread draw ที่ต้องป้องกัน

`CoreSurface.draw()` เรียก `renderer.drawFrame(true)` โดยตรงบน caller thread ได้ตาม contract ขณะที่ OpenGL context ปัจจุบันถูก bind ที่ render thread และ `OpenGL.drawFrameStart/End` ยังเป็น no-op จึงห้าม runtime ใหม่เรียกทางนี้บน UI แล้วคิดว่า mutex ทำให้ context current ถูก thread

ข้อเสนอ MVP: UI scheduling ใช้ `CoreSurface.refreshCallback()` เพื่อ queue render ส่วน `.render`/paint ใช้ frame ที่เสร็จแล้วเท่านั้น ไม่เรียก synchronous core draw เมื่อ resize หากภายหลังจำเป็นต้องรองรับ synchronous GL draw บน UI ต้องเพิ่ม context handoff/dispatch protocol พร้อม test แยกก่อน ไม่ใช้เพียง `wglMakeCurrent` ข้าม thread หรืออาศัย draw mutex อย่างเดียว เช่นเดียวกับ viewport/`surfaceSize` ต้อง sync จาก core screen pixelsบน render thread ไม่ใช้ขนาด hidden context-host เป็น terminal size

### Performance gate

Readback 1920×1080 RGBA8 = 8,294,400 bytes/frame หรือประมาณ 475 MiB/s ที่ 60 FPS **ก่อน** conversion/copy; 4K = 33,177,600 bytes/frame ประมาณ 1.85 GiB/s ที่ 60 FPS เป็นค่าคำนวณ ไม่ใช่ benchmark เครื่องนี้

บันทึก frame latency/readback/conversion/paint และ CPU/memory เมื่อ scroll/output burst ไม่รับรอง 60 FPS และไม่เร่ง idle ให้ redraw ตลอด หากทางนี้เป็น blocker ให้เสนอ direct presentation แยกจากงาน renderer core ไม่เปลี่ยนไปเอง

## 7. Window/input/DPI/IME contracts

| Win32 event/API | ทางเชื่อมที่เสนอ | ข้อกำหนด |
|---|---|---|
| `WM_NCCREATE`/window userdata | ผูก stable runtime surface/app state | เก็บ initializing/live/closing generation; messages ระหว่าง `CreateWindowExW` ต้องไม่เรียก core ที่ยัง init ไม่ครบ |
| message loop | `GetMessageW`/Translate/Dispatch + app wake message | แยก return -1, 0, positive; ไม่ busy-loop เมื่อไม่มีงาน; `PostQuitMessage` เฉพาะ UI thread ตาม lifecycle |
| `WM_SIZE` | `CoreSurface.sizeCallback` | เก็บ client pixels; core คำนวณ cells/padding และส่ง PTY resize เอง ห้ามหาร font size แล้วเรียก ConPTY ซ้ำจาก runtime |
| `WM_DPICHANGED` | update runtime scale → `contentScaleCallback` → size sync | DPI/96 สำหรับ Windows, ใช้ suggested rect ตาม Microsoft; callback อาจ resize เองด้วย ต้อง coalesce โดยไม่ยกเลิก event สุดท้าย |
| focus/visibility | `CoreApp.focusEvent`, `CoreSurface.focusCallback/occlusionCallback` | ล้าง key/preedit ที่ค้างเมื่อ focus หายตาม policy ไม่ปล่อย modifiers ติด |
| key down/up/syskey | สร้าง `input.KeyEvent` → `keyCallback` | physical `key`, action, mods, consumed_mods, utf8, composing, unshifted_codepoint; ตรวจ `.consumed` เพื่อไม่ส่งซ้ำผ่าน character path |
| character/dead key | UTF-16 decode และ event association | เก็บ surrogate state ต่อ surface, ไม่แปลงทีละ WCHAR; ไม่ใช้ `ToUnicodeEx` จนไป consume dead-key state ซ้ำกับ `TranslateMessage` โดยไม่ออกแบบ |
| IME composition/result | `preeditCallback` และ committed key/text encoding ตามคอร์ | preedit ต้อง UTF-8 และ reset ด้วย null เมื่อจบ/ยกเลิก; `GCS_RESULTSTR` commit ครั้งเดียว ไม่ส่งซ้ำจาก `WM_CHAR` |
| IME cursor/candidate | `CoreSurface.imePoint()` → client position → Imm API | ตรวจหน่วย/offset/DPI อีกครั้ง และ balance `ImmGetContext/ImmReleaseContext` |
| mouse/button/wheel | core cursor/button/scroll callbacks | client pixels, capture/release, scroll units และ modifier policy; ใช้ core mouse reporting ไม่เขียน VT escape เอง |

**ข้อควรระวังสำคัญ:** `CoreSurface.textCallback` ใน `src/Surface.zig:3400` ใช้ paste semantics (`completeClipboardPaste(..., true)`) รวม bracketed paste/newline normalization ไม่ใช่ generic API สำหรับส่งทุก key/IME result ต้องออกแบบ committed-input ให้เข้า `KeyEvent.utf8`/encoder ที่ถูกและทดสอบ protocol; ห้ามใช้ textCallback เป็นทางลัดจนพิมพ์ปกติกลายเป็น paste

IME MVP เสนอ IMM32 bridge ก่อน แต่ยังไม่รับรองว่าครอบคลุมทุก TSF/Windows IME ต้องทดสอบภาษาไทยที่เครื่องนี้ใช้จริง รวมเปลี่ยนภาษา/cancel/focus loss/repeat และบันทึกชื่อ input method โดยไม่เก็บข้อความงานส่วนตัว

กำหนด DPI awareness/manifest policy ก่อนสร้าง HWND แรก; `ImmGetCompositionStringW` รับและคืนขนาดเป็น **bytes** แม้เป็น Unicode และความยาวไม่รวม NUL อย่าใช้เป็นจำนวน WCHAR โดยตรง ตรวจ negative result, byte parity/ขนาด และ allocateตามที่ตรวจได้ก่อน UTF-16 decode

## 8. Clipboard และ action handling

### Clipboard

- `supportsClipboard`: `.standard` เท่านั้นใน MVP; `.selection`/`.primary` ตอบไม่รองรับ ไม่ map เงียบ ๆ ไป clipboard เดียวกัน
- Native text ใช้ `CF_UNICODETEXT` ↔ UTF-8; lock/copy/unlock/close ให้ครบ ไม่ถือ native clipboard lock ระหว่างรอ confirmation หรือคุยกับ PTY
- ขาเขียน: native memory ต้องใช้ allocation/flagsตาม `SetClipboardData` contract เมื่อสำเร็จ ownershipย้ายให้ระบบ ห้าม GlobalFree/เขียนทับต่อ; ถ้าล้ม callerยังต้องคืน allocationที่ตนถือ แยก ownershipนี้ออกจาก UTF-8 request buffersของ core
- `clipboardRequest` คืน `started` (เริ่มแล้ว), `unavailable`, `unsupported` ตาม enum จริงใน `src/apprt/structs.zig` ไม่ใช้ bool แทนโดยพลการ
- สำหรับ request ที่เริ่มแล้ว เก็บ owned request state ตาม variant และ complete/deny ครั้งเดียว; clipboard content ที่ส่งกลับเป็น borrowed ระหว่าง call ต้องไม่ free ก่อน core ใช้เสร็จ
- `completeClipboardRequest` อาจคืน `UnsafePaste`/`UnauthorizedPaste` โดย request ยัง alive ให้ runtimeถามยืนยันหรือ deny ไม่ complete ซ้ำแล้ว free ผิดลำดับ; cancel/close ต้องจัดการ pending request ให้จบก่อน surface หาย
- แยก user Ctrl+V ออกจาก OSC52/Kitty remote clipboard; คง core permissions/confirmation ไม่ถือว่า child shell มีสิทธิอ่าน clipboard อัตโนมัติ
- นโยบาย plain text อย่างเดียวต้องตอบ unsupported MIME/list ตาม protocol ที่ coreรองรับจริง ไม่อ้างว่ารองรับ binary/image หากยังไม่มี native mapping

### Actions

Runtime `performAction` ต้องแยก target app/surface และ action value ตาม `apprt.Action` โดยไม่เก็บ borrowed payload ข้าม event loop ถ้าต้อง async ให้ copy/own ตาม variant

| ลำดับ | Actions/หน้าที่ | Policy MVP |
|---|---|---|
| จำเป็นช่วง init | config_change, cell_size, size_limit, initial_size, set_title, quit_timer | ไล่ชื่อ/value จาก `action.zig` และ callsites ก่อน implement; window constraints และ owned title ต้องทำจริง |
| จำเป็นช่วงใช้งาน | `.render` หลัง mailbox redraw, close/quit/focus, mouse shape/visibility, clipboard confirmation | มาถึง UI thread และเคารพ state machine; ไม่ตอบ true หากยังไม่ทำ |
| ยังไม่ทำ | tab/split, global hotkeys, inspector UI, desktop notification และ IPC features | คืน false/unsupported ตาม contract พร้อม log แบบจำกัดครั้ง ไม่สร้าง dummy UI หรือ throw จนการเริ่ม app ล้มโดยไม่จำเป็น |

ตารางนี้เป็น mapping ของหน้าที่ ไม่ใช่รายชื่อ Zig enum ที่คัดลอกตรงทั้งหมด คำสั่ง/แท็กจริงต้องยึด `src/apprt/action.zig` และผล compile runtime ใหม่

## 9. PTY และ teardown — ใช้ core lifecycle ไม่เขียนคู่ขนาน

Existing path: `CoreSurface.init` → `termio.Exec/Subprocess` → `WindowsPty.open` → `Command.startWindows` (`src/Command.zig:305`) พร้อม pseudo-console attribute → core IO/reader threads

- Runtime กำหนด shell เป็น `powershell.exe` อย่างชัดเจน; default Windows path ใน `Exec.zig` มี `cmd.exe` อยู่ ไม่สมมติว่าจะเปิด PowerShell เองหรือเครื่องมี `pwsh.exe`
- ไม่เปิด stdin/stdout pipes จาก runtime อีกชุด และไม่เรียก `CreatePseudoConsole`/`ResizePseudoConsole` นอก core ซ้ำ
- Core ส่ง renderer/IO mailboxes ภายใน resize callback; Runtime ส่งแค่ pixel size/DPI events ตาม contract
- `Exec.Subprocess.deinit` เรียก stop แล้ว PTY deinit; Windows kill path ใช้ `TerminateProcess` และ wait อยู่แล้ว นี่ไม่ใช่หลักฐานว่า process tree/interactive close สมบูรณ์
- `WindowsPty.deinit` ปิด pipe handles และ `ClosePseudoConsole`; Windows read thread ใช้ blocking `ReadFile` และมี handling `OPERATION_ABORTED` ต้องทดสอบ idle EOF/cancel/broken pipe จริงก่อนรับรอง close ไม่ค้าง

`Exec.threadExit` ปัจจุบัน stop subprocess → เขียน quit pipe → บน Windows `CancelIoEx(read_thread_fd, null)` → join reader (`src/termio/Exec.zig:194–229`) จึงไม่ใช่ว่าไม่มี cancellation เลย แต่ผลต่อ synchronous `ReadFile` และ race ช่วง shell exit/broken pipe ยังต้องพิสูจน์จาก native test ไม่เปลี่ยนเป็น API อื่นจากการเดาในเฟสเอกสาร

### State machine ที่ต้อง implement

```text
allocated → native_ready → core_initializing → live
                |                 |             |
                +---- failure ----+---- close --+
                                  v
                             closing
                                  v
                         core_stopped/joined
                                  v
                         native_destroyed → freed
```

Baseline `CoreSurface.deinit` หยุดและ join renderer ก่อน IO แล้วจึง deinit shared state เดิมห้าม runtime สลับเองจากการคาดเดา หลังพบ native burst-close timeout จริงจึงแก้ **core เฉพาะ Windows** ให้หยุด/join IO producer และ reader ก่อน renderer consumer พร้อม sticky quit check และ CancelSynchronousIo retry ระหว่าง join; แพลตฟอร์มอื่นคงลำดับเดิม ไม่ให้ runtime double-stop/join หรือปิด borrowed handles ดูผลผ่าน burst/exit/input และ full-core หลังแก้ใน `windows-validation.md` ทั้งนี้ยังไม่รับรอง shutdown ของ OSC/UI-message flood ทุกแบบจาก fixture plain-output นี้

1. UI mark closing, disable input/new requests, invalidate generation และจบ/deny pending clipboard/IME ตาม ownership
2. ถ้า need-confirm-quit ให้ถามก่อนเข้า destruction ไม่ถามจาก worker หรือขณะถือ mutex
3. เอา runtime surface ออกจาก core app registryตาม contract แล้วทำ core deinit บน thread ที่ contractกำหนด โดยให้ native context hosts และ callback targets ยังอยู่
4. Core renderer thread unbind current และ join ก่อน context destroy; core IO stop/join ต้องปลด blocking reader ได้ หากทำให้ UI ค้างต้องแก้ lifecycle แบบมีเหตุผลและ test ไม่ย้าย destructor ไป background แล้วเรียก UI API ผิด thread
5. หลัง core surface หยุดแล้ว ปล่อย runtime-owned frames/DIBs, per-surface native context host/DC/HWND และ surface allocation; posted messages หลัง close ต้องกลายเป็น no-op ด้วย identity/generation ไม่ dereference pointer ที่ free แล้ว
6. Runtime `terminate` ต้องไม่ double-destruct surface ที่ core app destroy จะเห็นอีก ส่วน app-scoped WGL device/independent bootstrap host ให้ core app device deinit เป็นเจ้าของและทำหลังทุก surface gone ตาม flow จริงใน `main_ghostty.zig`

อย่าใช้ `DeleteDC` กับ HDC ทุกชนิดอย่างเหมารวม ต้องใช้ cleanup ตรงกับวิธี acquisition (`GetDC`/private DC/created DC) และทำลาย context ก่อนทำลาย window/DC ที่ยังใช้ ไม่ฆ่าโปรเซสอื่นของผู้ใช้เพื่อให้ shutdown test ผ่าน

## 10. Ownership/thread matrix

| Resource | ผู้สร้าง/เจ้าของ | ผู้ใช้ | จุดคืน |
|---|---|---|---|
| Runtime App / message target | UI runtime | UI; worker ถือเฉพาะ wake identity ที่ valid | หลังหยุด workers/surfaces และไม่รับ wake ใหม่ |
| CoreApp | `main_ghostty` | UI + core mailboxes | `App.destroy` หลัง runtime terminate ตาม existing entrypoint |
| Config | Runtime App | core derives/copies ตาม API | หลัง surface callbacks ไม่ใช้แล้ว; config refresh ไม่ให้ borrowed pointer ค้าง |
| Visible HWND + DIB | Runtime Surface/UI | UI paint/input | หลัง core stop และคืน frame/DIB เก่าแล้ว |
| App bootstrap WGL host/dispatch | Windows Device adapter | context factory; เธรดต้องระบุ | Device deinit หลังทุก surface/context gone |
| Per-surface hidden HWND/HDC | Runtime Surface/UI | WGL context บน init/render thread ตาม handoff | หลัง context destroy และ join; acquisition-specific cleanup |
| Per-surface HGLRC | OpenGL context adapter | ทีละ thread ที่ current | หลัง render threadExit และ join; ตรวจ not current |
| GLAD context pointers | `pkg/opengl/glad.zig` threadlocal | thread ที่โหลด | threadExit/unload บน thread เดิม |
| Latest RGBA frame | core queue → UI เมื่อ take | ผู้รับเพียง owner เดียว | deinit เมื่อแปลง/แทน/close; ห้าม free pixels ซ้ำกับ DIB owner |
| Clipboard request/native lock | runtime request owner/UI | core complete/deny API | ตาม variant; native lockปล่อยก่อน dialog/async |
| HPCON/pipes/process/read thread | core PTY/Command/termio | IO/reader core | core deinit/cancel path; runtime ไม่ปิด handle ยืมเอง |

## 11. Failure behavior และสิ่งที่ต้องมองเห็น

| Failure | พฤติกรรมที่ต้องการ |
|---|---|
| HWND/register/message loop error | log operation + Win32 code, unwindเฉพาะ resource ที่สร้างสำเร็จ; exit nonzero ไม่เปิด orphan shell |
| GL4.3/extension/context ไม่พร้อม | แสดงเหตุ unsupported ก่อนเปิด shell; ไม่ silent fallback เป็น API ต่ำกว่า requirement |
| renderer thread init fail | ต้องมี readiness/failure signal หรือ equivalent ที่ทำให้ runtime รู้; ปัจจุบัน threadMain log warning แล้วคืนได้ ต้องออกแบบเพิ่ม ไม่ปล่อยหน้าต่างดำแต่บอก ready |
| shell path/cwd/env invalid | รายงานที่ปลอดภัย ไม่ dump env; rollback surface/thread/PTY ให้ครบ |
| clipboard locked/denied | unavailable/deny ตาม API ไม่ retry busy-loopหรือถือ lockค้าง |
| resize ขนาดศูนย์/เก่า | gateด้วย visibility/generation; ไม่ allocateขนาด overflow และไม่ส่ง obsolete size หลัง close |
| close stuck/read cancellation fail | บันทึกขั้น/threads/handlesที่ค้างเป็น blocker; ไม่ซ่อนด้วย detached thread, forced app exit หรือ kill process wildcard |

## 12. ลำดับ implementation และ acceptance gates

### รายการไฟล์ที่คาดว่าจะเปลี่ยน

ชื่อไฟล์ใหม่ในตารางเป็นข้อเสนอ ยังไม่สร้างในเฟส 2 และอาจปรับเมื่อ compile gate พบcontractเพิ่ม:

| Path/กลุ่ม | เฟส | งาน |
|---|---|---|
| `src/apprt/runtime.zig`, `src/apprt.zig`, `src/build/Config.zig` | 3B | runtime selection/enum/build option consistency |
| `src/build/GhosttyExe.zig`, `dist/windows/ghostty.rc` หรือresourceของ productแยก | 3 | artifact name/version/manifest/branding ไม่เปลี่ยน attribution |
| `src/apprt/win32.zig`, `src/apprt/win32/App.zig`, `Surface.zig`, `window.zig` (ใหม่) | 3 | typed contract/message loop/state/ownership; zero core surfaceใน window smoke |
| `src/apprt/win32/input.zig`, `ime.zig`, `clipboard.zig`, `presenter.zig` (ใหม่) | 4 | input conversion/IME/request ownership/DIB presenter |
| `src/renderer/opengl/context.zig`, `wgl.zig` หรือ backend directory (ใหม่) | 4A | target-selected context/device interfaceและ Windows native implementation; ไม่มีdependencyกลับไป runtime Appเพียงเพื่อโหลด Win32 API |
| `src/renderer/OpenGL.zig`, `src/renderer/opengl/Device.zig` | 4A | delegate platform context lifecycle; คง draw/FBO/shadersเดิมและ non-Windows EGL |
| `src/build/SharedDeps.zig`, `pkg/opengl/**` ตามจุดที่พิสูจน์ว่าจำเป็น | 3B/4A | Windows link/proc resolver/type separation; ไม่ดึง EGL/GTKเข้าบิลด์ Windowsโดยเงียบ |
| `src/apprt/*` structs/action/surface และ runtime switchesในส่วน3.4 | 3B | enum exhaustivenessโดยคง semanticsเดิม |
| `src/config/file_load.zig` และ resource lookupที่ตรวจพบ | 3B/4 | new product Windows path/override policy ไม่อ่าน configแบรนด์อื่นอัตโนมัติ |
| `src/pty.zig`, `src/Command.zig`, `src/termio/Exec.zig` | 4 เฉพาะถ้าพบnativefailure | เริ่มจาก existing path; patchเฉพาะ defectที่ทำซ้ำได้ไม่เขียนbackendใหม่ |
| `docs/sources.md`, `windows-validation.md`, `gaps.md`, integration/reference notes | ทุกเฟส | บันทึก diff/ที่มา/commands/results/failuresและการเปลี่ยนdecision |

อย่าเริ่มแก้ทุกไฟล์พร้อมกัน: เฟส3Aต้องเล็กและยังไม่แตะgraphics/PTY; build/runtime contractเพิ่มใน3B แล้วแยกcontext spikeก่อนreal shell

### เฟส 3A — Native window อย่างเดียว

- ยืนยันชื่อชั่วคราวก่อนใช้ executable/resource/config ID
- Native message loop, visible HWND, empty opaque client area, resize/focus/DPI/close โดยยังไม่สร้าง CoreSurface/PTY/context
- ไม่สร้าง fake renderer/clipboard implementations เพื่ออ้างว่า runtime integration เสร็จ
- Gate: เปิด/ปิดซ้ำ 20 รอบ, ไม่มีหน้าต่างค้าง/handle เพิ่มสะสม, message errors ถูกแยกและ baseline tests ไม่มี regression

### เฟส 3B — Compile-time runtime integration

- enum/switches/build options/resources/branding และ App/Surface contracts เข้ากับคอร์
- Build explicit runtime ใหม่และบันทึกคำสั่งที่ตรวจ `zig build --help` แล้ว; `-Dapp-runtime=win32` ยังไม่ใช่คำสั่งใช้ได้ตอนนี้
- Gate: ไม่มี GTK/EGL provider dependency หลุดเข้าทาง WGL, ไม่มี dummy success ของ required methods; หน้าต่างเปล่ายังเปิดได้โดยไม่ spawn shell

### เฟส 4A — Graphics spike และ real core surface

- ผ่าน WGL capability/lifetime spike ก่อน; ต่อ ContextBackend → core Renderer → latest frame → DIB presenter
- หลัง graphics readiness เท่านั้นจึงต่อ CoreSurface/init ที่เริ่ม IO ด้วย ต้องมี rollback หาก worker init fail
- Gate: GL version ≥4.3 จริง, draw/readback/pixel orientation/channel ถูก, resize/minimize/DPI ไม่ค้าง, memory/handle/thread cleanup ผ่าน รวม targeted tests ของ adapter/queue/conversion

ข้อจำกัดลำดับเฟส: จาก sourceปัจจุบันไม่สามารถเรียก production `CoreSurface.init` เพื่อวาดterminalแล้วอ้างว่าไม่เริ่มPTY/IOได้ เฟส4Aส่วนstandalonegraphicsต้องเสร็จก่อน; การเริ่มreal surfaceเกิดที่รอยต่อ4A/4Bครั้งเดียวและเปิดshellด้วย จากนั้นตรวจgraphics/textกับPTYเป็นacceptanceคนละข้อ ไม่เพิ่มfakeIOเพื่อทำให้ชื่อเฟสดูแยกขาดจากกัน

### เฟส 4B–4D — PowerShell / input / shutdown

- PowerShell command และ UTF-8/Unicode cwd, resize, output burst, EOF, nonexistent shell path
- Key/modifier/deadkey/IMEไทย/clipboard permissionsตามส่วน 7–8 ผู้ใช้ยืนยันการพิมพ์/ภาพจริง ไม่รับรองจาก unit tests แทน
- Close idle/กำลังเขียน output/shell exitเอง/confirm cancel และ child process testที่ควบคุมได้ ไม่เหลือ processของ sessionตาม policy
- Gate: ทำตาม `PLAN.md` พร้อม log/checklist ใน `windows-validation.md`, ไม่มี baseline regression และไม่เปลี่ยน test filters/timeout เพื่อซ่อน failure

### Targeted tests ที่ควรเพิ่มเมื่อ implement

1. Runtime state transitions/failure injection หลัง register/window/DC/context/surface init แต่ละจุด
2. wake coalescing และ generation guard: closing/reallocated surface ไม่รับ stale pointer
3. RGBA→DIB channel/row/stride/overflow และ allocation failure; frame ownership deinit ครั้งเดียว
4. UTF-16 surrogate/invalid pair, consumed-keyกับWM_CHAR dedupe, IME result/preedit/cancel sequences
5. clipboard request complete/deny/unsafe-confirm/cancel exactly-once และ unsupported selection/MIME
6. WGL context current-thread contract/proc lookup failure/GL version reject; Linux compile/regressionบน runnerที่มีจริง ไม่อ้าง Windows testแทน

## 13. Open questions และความพร้อม

| ข้อ | ต้องตัดสินใจ/ตรวจ | บล็อกอะไร |
|---|---|---|
| Q1 | ผู้ใช้ยืนยัน `localterm-dev` เวลา12:46แล้ว | ปิดเรื่องชื่อสำหรับworking prototype; ไม่ใช่trademark clearance |
| Q2 | ผู้ใช้ยืนยันทิศทาง WGL adapter + CPU DIB เวลา12:46แล้ว | directionอนุมัติ แต่ capability/performanceยังต้องพิสูจน์ก่อนgraphics acceptance |
| Q3 | renderer readiness/error propagation และ core blocking-read shutdownบน Windows | real shell session/acceptance ห้ามถือว่าผ่านจาก full-core tests |
| Q4 | GPU/driver desktop GL4.3 และ pixel/copy performance จริง | graphics gate ยังไม่ได้วัด |
| Q5 | Windows minimum version/ConPTY support policy และ Linux regression runner | การแจก/อ้าง cross-platform support ยังไม่ประกาศ |
| Q6 | independent review โดย agent ที่ได้รับอนุญาตทำ Ghostty | โปรไฟล์ปัจจุบันยังจำกัด Olufy และไม่ได้แก้; ไม่มีผล subagent review ของ design นี้ |

ผลเฟส 2: มีแผน contracts/ownership/files/gates สำหรับ implementation แล้ว แต่ **ยังไม่พร้อมประกาศว่า Windows terminal ใช้งานได้** ก่อนเริ่มหน้าต่างให้ตอบ Q1; ก่อนเริ่ม graphics/shell ให้ยืนยัน Q2 และพิสูจน์ Q3/Q4 ตาม gate

## 14. แหล่งอ้างอิง

รายละเอียดเอกสาร Microsoft/Khronos ที่เปิดอ่านจริง วันที่ตรวจ และหัวข้อ HWND/WGL/ConPTY/input/core surface อยู่ใน `reference-notes.md` ทุก path ของ upstream อ้าง baseline ใน `sources.md`; ชื่อ module/API ที่เสนอใหม่ในเอกสารนี้ยังไม่ได้ implement และไม่ใช่ API ของ Ghostty ที่มีอยู่แล้ว
