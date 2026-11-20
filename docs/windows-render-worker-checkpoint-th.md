# GPU worker บน Windows: checkpoint การทดสอบ

อัปเดต 20 ตุลาคม 2026 เวลา 20:35 น. (Asia/Bangkok)

## ผลต่อเนื่อง 27 ตุลาคม 2026 เวลา 11:44 — bounded functional GPU repro

Privateoffscreenfunctionalsuiteผ่านหนึ่งรอบ รวม244-stylelateframe+203msrejected/cleanuphandles69→69; actualremotehost181-stylelifecycleผ่าน21/21healthycloses/handles129→129/frames165paints165 ไม่timeout/no cleanupdescendants/sourceunchanged ไม่promotedefault ไม่ปิดold181/244ด้วยpassเดี่ยว ไม่ใช่GPU-busy/performancequalification ดู [windows-worker-functional-repro-th.md](windows-worker-functional-repro-th.md)

## ผลต่อเนื่อง 27 ตุลาคม 2026 — CPU reap เท่านั้น

แก้แยกหนึ่ง polling-budget defect ที่พิสูจน์ด้วย same16case MSVC red→green: subsequent job poll เดิมอาจเริ่มหลังdeadlineและรับlateemptyเป็นsuccess ตอนนี้clampSleepremainingและไม่เริ่มpollหลังdeadline คงinitialzero-waitprobe/ACK/exit0/jobempty/budgetsเดิม Final16/16Debug+ReleaseSafe, relatedCPUcontracts39/39ทั้งสองmode, compile-onlyclient/worker32/32ผ่าน ไม่executeGPU

**ไม่ถือว่าแก้exec181/244แล้ว** RealCPUjobfixturestrictglobalcountยังfailed61→66; coldWin32controlข้ามproductionfinish/destroyก็+5ก่อนreap ไม่waiveหรือเพิ่มwarmup GPUqualification/defaultคงเดิม รายละเอียด [windows-worker-reap-audit-th.md](windows-worker-reap-audit-th.md) เนื้อหาด้านล่างเป็นcheckpointเดิมตามวันที่

## ข้อสรุปตอนนี้

**ยังไม่ประกาศพร้อมใช้งาน และยังไม่เปิดเป็น default** การทดสอบอัตโนมัติยืนยันเส้นทาง terminal จริงและภาพบางกรณีได้แล้ว แต่ยังมี close fault ที่ไม่ทราบต้นเหตุ รวมถึง performance, GPU-busy failure และการยอมรับจากการใช้งานจริงที่ยังไม่ครบ

ทำงานต่อบน branch `windows-terminal-baseline` เดิม ไม่มี commit/push ไม่ทับ accepted62 และไม่เปลี่ยน driver/system settings

## ขอบเขตและตัวเลือก

- Parent ยังเป็นเจ้าของ Core, ConPTY, keyboard/mouse และ IME; GPU อยู่ใน child ของ owned Job Object
- `-Dwindows-remote-renderer=true` เปิด remote renderer แบบ opt-in
- `-Dwindows-remote-images=true` เปิด inline images เพิ่ม และต้องใช้ร่วมกับ remote renderer; ค่าเริ่มต้นยังปิด
- Binary ที่ทดสอบแยกอยู่ใน `zig-out/render-worker-images/bin`, `zig-out/render-worker-host/bin` และ `zig-out/render-worker-legacy/bin`
- เมื่อใช้ `-ConptyProvider app-local` ต้อง provision runtime ใน **แต่ละ executable directory** ด้วย `tools/windows/provision-conpty-experiment.ps1 -OutputDirectory <prefix>/bin` สคริปต์ตรวจ package hash และ Microsoft signature; ไม่ fallback ไป system ConPTY

## หลักฐานที่ผ่าน

| รายการ | หลักฐานและข้อจำกัด |
| --- | --- |
| Build แยกสามรุ่น | exec197: image opt-in 127 steps, text-only 127 steps, legacy 126 steps |
| แยก GPU จาก parent | Remote fixtures ตรวจ parent ไม่มี GL/AMD modules และ child close ACK/exit0/job empty; ไม่ใช่หลักฐานว่า driver ทุก failure mode ถูกทดสอบแล้ว |
| Resize/epoch | Offscreen A→B→C→A ครบ 4 presentations, odd sizes/minimize/restore/synthetic DPI และ discard stale returned frames; ไม่ใช่ physical mixed-DPI acceptance |
| Thai text | Direct VT model comparison ต่าง 0 cells; legacy text GPU parity exec197 มี 29 checks สูงสุด 655 glyphs และไม่มี different bytes |
| Kitty ผ่าน ConPTY ถึง UI | exec199 ส่ง RGBA แดง→เขียว replacement ID เดิม→delete ผ่าน child stdout/ConPTY/parser/CPU snapshot/IPC/worker/GDI จริง ไม่ inject เข้า parser และไม่ใช้ clipboard |
| Whole-frame image parity | Remote 2 runs และ legacy reference 2 runs: BGRA ทั้งเฟรม 2,733,896 bytes มี SHA-256 ตรงกันครบทั้งสาม phase; เฉพาะ fixture 1×1 RGBA ขยาย 8×4 cells ไม่ใช่ทุก format/crop/z-order |
| Input/mouse/close-under-load | exec204: ASCII/Thai/surrogate/Enter/repeat, selection/capture-loss/scrollback, natural child exit, burst และ OSC title backpressure ผ่าน; mouse ใช้ in-memory clipboard sink และ owned HWND เท่านั้น |
| Image codec | exec207: Debug 36/36 และ ReleaseSafe 36/36 |
| Full Core | exec207: 89/89 build steps, 3,981/4,042 tests ผ่าน, skip 61; **test executable เป็น Debug ตาม build.zig** ไม่ใช่ ReleaseSafe แม้ invocation ส่ง option ดังกล่าว |
| lib-VT | exec211: Debug 45/45 steps, 6,722/6,786 tests ผ่าน, skip 64; ใช้ configuration ที่เปิด slow runtime safety ตาม test contract ไม่มีการแก้ assert |
| Profile close budget | exec212: remote/legacy ทั้ง profile และ profile-paced ปิดภายในเกณฑ์ 25 วินาทีครบสี่กรณี ไม่ใช่หลักฐานว่า remote เร็วกว่า |

### Performance รอบแรก: นับเฉพาะ parent

fixture 1920×1080 แต่ละ run ประมาณ 15 วินาที ไม่มี build load ร่วม:

| รุ่น/fixture | CPU time ที่ sample ได้ (ms) | OS peak working set (bytes) | Frames/paints |
| --- | ---: | ---: | ---: |
| Remote profile | 20,609.375 | 115,576,832 | 961 |
| Remote paced | 11,218.750 | 66,215,936 | 897 |
| Legacy profile | 32,781.250 | 247,996,416 | 1,947 |
| Legacy paced | 7,234.375 | 190,418,944 | 983 |

**ห้ามใช้ตารางนี้สรุปว่า remote เบาหรือเร็วกว่าโดยรวม:** ไม่รวม worker CPU/RAM/VRAM และ throughput/ปริมาณ output ไม่เท่ากัน paced parent CPU ของ remote สูงกว่า legacy ด้วย

### รอบวัด owned worker เพิ่ม (exec215)

MSVC C11 `/W4 /WX`, client negative/race tests และ native lifecycle 21 workers ผ่านโดย counters ไม่โต แล้วจึงวัด profile แยกจาก build load:

| รุ่น/fixture | Parent CPU sample (ms) | Worker CPU หลัง exit (ms) | ผลรวม CPU ต่าง observation windows (ms) | ผลรวม peak WS upper bound (MiB) | Frames |
| --- | ---: | ---: | ---: | ---: | ---: |
| Remote profile | 21,453.125 | 8,140 | 29,593.125 | 273.6 | 1,106 |
| Remote paced | 10,671.875 | 7,906 | 18,577.875 | 226.2 | 945 |
| Legacy profile | 33,203.125 | — | 33,203.125 | 236.7 | 2,102 |
| Legacy paced | 7,968.750 | — | 7,968.750 | 181.6 | 981 |

Worker memory มี 61/60 samples ตามลำดับ ผ่าน existing owned handle ไม่ค้น PID ใหม่ ผลรวม peak นับ shared pages ซ้ำได้และไม่ใช่ simultaneous peak/VRAM ส่วน CPU สองฝั่งมี observation windows ต่างกัน จึงไม่ใช่ benchmark ควบคุมงานเท่ากันทั้งหมด แต่ผล paced ยังแสดงค่าใช้จ่ายที่ต้องตรวจเพิ่ม ไม่ประกาศ performance superiority

### Render-target reuse ผ่าน correctness แต่ยังไม่พิสูจน์ performance win

exec221 ผ่าน GPU component: stable-size 10 frames ใช้ target เดียว, resize 9×5→8×4 สร้างรวม 3 targets, texture/FBO ทั้งคู่ของของเก่าและของสุดท้ายถูกลบ และ pixels เมื่อกลับขนาดเดิมตรง reference; image three-band/client failures, native whole-frame Kitty hashes, viewport และ lifecycle 21 sessions ผ่านด้วย

หลัง reuse: remote profile รวม CPU 29,046 ms/1,076 frames และ paced 19,406 ms/946 frames; legacy 33,422 ms/2,253 และ paced 7,500 ms/991 ตามลำดับ (ข้อจำกัดการวัดเหมือนข้างต้น) **ยังไม่เห็น paced overhead ลดลงจากรอบวัดนี้** จึงคง target reuse ในฐานะลด allocation churn ที่ตรวจ lifecycle ได้ ไม่อ้างแก้ performance qualification สำเร็จ

exec226 build remote/legacy ผ่านและวัด renderer-thread CPU phases ได้: profile capture 16.98%, RPC 82.59%, publish 0.43%; paced 17.14%, 82.42%, 0.44% ตามลำดับ เฉพาะช่วงที่วัด ไม่ใช่ whole-parent CPU/wall time และไม่รวม shaping/updateFrame/thread อื่น/free หลัง publish ไม่มีการตัด decoder/module checks

### Private reply ownership transfer ผ่าน checkpoint

exec233 ผ่าน CPU contracts 37/37 ทั้ง Debug/ReleaseSafe รวม take/failure-retain/base-free tests; actual Session เก็บ frame แรกไว้ข้าม green reply และทั้งห้า natural/failure reaps ได้โดย bytes ไม่เปลี่ยน พร้อม native whole-frame hashes/viewport/lifecycle 21 sessions ผ่าน ไม่ยืม shared mapping

รอบวัดหลังโอน ownership: remote profile parent 20,984.375 + worker 9,796 = 30,780.375 ms/1,230 frames และ paced 9,562.5 + 7,515 = 17,077.5 ms/952 frames; legacy profile 33,609.375 ms/2,088 frames และ paced 7,953.125 ms/965 frames ข้อจำกัดการวัดเหมือนข้างต้น ยังไม่ประกาศ overall performance parity/superiority แม้ parent paced CPU รอบนี้ลดลงจากรอบก่อน

## Close race ที่แก้ กับ fault ที่ยังไม่แก้

1. **แก้แล้วเฉพาะ race ที่พิสูจน์ได้:** exec195 สร้างจังหวะให้ real `.closed` และ process exit พร้อมก่อน parent wait แล้วพบ `WorkerCommunicationFailed` แบบ deterministic; exec196 หลังแก้ผ่านสองรอบ พร้อม control ว่า stop/cancel ต้องชนะเมื่อทั้งสาม signals พร้อมกัน
2. Fix จำกัดเฉพาะ CLOSE ที่พบ process exit และมี reply event พร้อมอยู่แล้ว ตรวจ packet ตามเดิม และยังต้อง exit0/job empty/no forced cleanup จึงถือว่า healthy ไม่ส่งเสริม timeout หรือ render replies เป็น success
3. **ยังไม่ทราบสาเหตุ:** exec181 lifecycle cycle 15 เกิด `WorkerCloseFailed` หลัง exchange สำเร็จ แม้ท้ายที่สุดเก็บ handles คืนได้ จึงไม่ใช่ fault เดียวกับข้อ 1 และไม่ได้ถือว่าแก้แล้วเพราะ stress ภายหลังผ่าน
4. เพิ่ม original finish status ก่อน abort, process-wait/exit-code/job-query diagnostics และ executor/WGL/device/run completion markers แล้ว ไม่มีการเพิ่ม timeout หรือผ่อน critical-log/resource gates

## รายการที่ยังเปิด

- เก็บผล lib-VT invocation ReleaseSafe ของ exec207 ว่า compile ไม่ผ่าน เพราะ `PageList.pinIsValid` ต้องเปิด `slow_runtime_safety`; Config เปิดเฉพาะ Debug ผล Debug ที่ผ่านไม่ได้แปลว่า ReleaseSafe invocation ผ่านด้วย
- exec235 ผ่าน full post-ownership Core Debug 89/89 steps, 3,981/4,042 tests (skip 61) และ VT Debug 45/45 steps, 6,722/6,786 (skip 64) ส่วน ownership contracts อยู่ใน standalone CPU suite 37/37 ไม่ใช่การเพิ่มจำนวน Core tests ใน default backend
- Fork read-only audit task6 จบแล้ว: ไม่พบบั๊ก ownership/lifetime ใหม่ใน paths ที่อ่าน ตรวจ allocator identity, base-free, exact response tail, single-owner latest-frame transfer, stale release และ UI conversion-before-release; **ไม่ได้รันทดสอบ** ส่วน task5 template ปฏิเสธเพราะจำกัด Olufy จึงไม่ได้ review
- ผู้ใช้อนุมัติ bounded request-buffer reuse เวลา 19:15 หลัง exec235 จบจึงเพิ่ม Client-owned scratch: ใช้ exact encoded slice แต่ retain capacity แบบ geometric **ไม่เกิน protocol header + request_limit**; growth alloc replacement ก่อน free เพื่อคงของเดิมเมื่อ OOM; close/abort ปล่อย scratch แม้ repeated cleanup ไม่ reuse response ที่ frame ยังถืออยู่ การ retain capacity ถึงสิ้น session เป็น memory trade-off ที่มี bound ไม่ใช่ลด memory ได้เสมอ
- exec237 ผ่าน CPU contracts 39/39 ทั้ง Debug/ReleaseSafe, client build 32/32 พร้อม actual init request/hello-reply/close-reply OOM, balanced allocations/repeated abort/handles0 และ negative/race/retained-frame tests เดิม ไม่มีการ reuse live response
- exec238 ผ่าน native ทั้ง image opt-in/text-only/legacy, whole-frame Kitty hashes/Thai/viewport/strict lifecycle 42 closes และ profile สี่กรณี แต่จำนวน frames ต่างจากรอบก่อนมาก: remote profile 893/CPU รวม 25,296.875 ms, paced 720/18,405.5 ms; legacy 1,186/20,578.125 และ paced 575/7,078.125 ไม่ใช่งานเท่ากัน จึงไม่สรุป performance gain/parity จากรอบนี้
- หยุดไล่ optimization จุดย่อยชั่วคราวเพื่อปิด failure gate ที่ยังขาด: exec244 **ยังไม่ผ่าน** late-rendered fixture แม้ MSVC/build ผ่าน และผ่าน timing/pixel/reject checks ก่อนถึง `LateRenderedCleanupFailed` ซึ่งเป็น combined assertion ยังไม่ทราบว่าข้อใด fail; exec247 เพิ่มเฉพาะค่า ACK/exit/job/forced/handles/ticks เพื่อวินิจฉัยหนึ่งรอบ ไม่ผ่อนเงื่อนไขหรือเพิ่ม warmup
- Late fixture ใช้ executable test root แยก build เฉพาะ client-check ไม่ติดตั้งผ่าน app install; production compile delay branch ทิ้ง ใช้ production render/readback/finish จริงสองเฟรมก่อน frame ที่สามเสร็จแล้ว CPU sleep 200 ms จึง publish โดยบันทึก ticks ใน test-only tail นอก actual tiny reply RPC deadline 50 ms เดิม ส่วน post-failure observation/reap เป็นคนละ budget ไม่ pause driver และยังไม่ถือว่าปิด gate จน cleanup ผ่านด้วย
- exec247 รอบ diagnostic ผ่าน: readback ที่ +0 ms ตาม resolution ของ GetTickCount64, publish ที่ +219 ms, exact RGBA/reject/cleanup/handles ผ่าน แต่ไม่ใช่คำอธิบายหรือ fix ของ exec244; exec249 เก็บ cleanup receipt ทุกครั้งใน bounded repro 8 runs หยุด first failure โดยไม่มี threshold/warmup/deadline changes ยังเก็บ failure เดิมเป็นรายการเปิด แยกจาก close fault exec181
- exec249 ผ่านทั้ง 8 runs: ACK=0, exited=1, child exit1, jobempty=1, forced=1 และ handles 62→62 ทุกครั้ง late publication +203–219 ms; ยังไม่อ้างแก้ cleanup failure ของ exec244 ซึ่งไม่ทำซ้ำในชุดนี้ และไม่รัน stress เพิ่มเรื่อย ๆ เพื่อกลบ failure
- exec250 ผ่าน production image 127/127 และ legacy 126/126 steps, test worker artifact ไม่อยู่ใน app prefixes ทั้งสอง; Kitty whole-frame hashes ตรง reference ครบสาม phases, viewport 4 presentations และ production 21 healthy closes ผ่าน: handles 123→123, GDI 2→2, USER 1→1, threads 4→1; legacy Thai GPU parity 28 checks/max 655 glyphs/failures 0 และ direct VT grapheme comparison ต่าง 0 cells
- ยังไม่มีหลักฐาน actual GPU-busy hang ครบตาม qualification; late-rendered test ที่กำลังทวนเป็น CPU delay **หลัง GPU finish** ไม่ใช่ GPU-busy/driver-hang proof และห้าม pause driver threads
- Physical keyboard/IME, on-screen/mixed-DPI และ workflow จริงยังต้องการ human acceptance; synthetic messages ไม่แทนเกณฑ์เหล่านี้
- Read-only review พบประเด็น launch inheritance/serialization ที่ต้องตรวจเพิ่ม ยังไม่พิสูจน์ว่าเป็นต้นเหตุและไม่ได้แก้ ConPTY/Command นอก scope โดยเงียบ ๆ

## ที่เก็บหลักฐาน

`%LOCALAPPDATA%/Letta/build-logs/ghostty-windows/phase3b-runtime/results.jsonl` อ้าง stdout/stderr, executable SHA-256 และ frame artifacts ของแต่ละ run ส่วน chronology อยู่ใน `PLAN.md` และ `windows-render-worker-api-inventory.md`

ขั้นถัดไป: ขออนุญาตเปิด interactive candidate แบบเห็นได้เพื่อทดสอบ physical IME/keyboard กับผู้ใช้ ยังไม่เปิดหน้าต่างจนได้รับอนุญาต ไม่ถือ manual acceptance ว่าผ่านเอง และไม่ใช้ผลนี้ล้าง blocker ของ exec181 close fault, exec244 cleanup failure, performance หรือ GPU-busy qualification ไม่มี default promotion/commit/push
