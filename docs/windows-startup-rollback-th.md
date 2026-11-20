# Windows surface startup rollback — 30 ตุลาคม 2026

## ขอบเขตและสถานะ

แก้เส้นทางเริ่ม surface ไม่สำเร็จของ native Win32 โดยเฉพาะ ไม่ใช่การแก้ normal `WIN-RUNTIME-004` ทั้งหมด และยังไม่รับรองพร้อมใช้งานจริง

**strict lifecycle ยัง failed/open:** candidate หลังแก้ครบ warmup 1 + 20 cycles ยัง handles **233→234**, threads **6→7**, GDI **3→3**, USER **3→3** ไม่มี timeout มีการวาด/paint จริง ไม่มี owned descendants ที่ต้อง cleanup ห้ามตีความ absolute count ที่ต่างจาก process เก่าว่าแก้ leak ลดไปหลาย handles

ไม่เปลี่ยน threshold/warmup/deadline, GPU default, driver/global settings ไม่ปิด foreign handles/threads ไม่แตะ `A:` บัญชีหรือ agent ที่ใช้งาน และไม่ commit/push แพ็กส่งมอบเดิมไม่ได้ถูกแทนด้วย candidate นี้

## ปัญหาที่ทำซ้ำและสิ่งที่แก้

- ลำดับเดิมเริ่ม renderer แล้วจึงสร้าง IO worker: ถ้า IO spawn ล้มเหลว renderer ยังใช้ dependency ที่ error cleanup กำลังคืน
- Native surface ถูกติดตั้งเป็น routing target/สมาชิก registry ตั้งแต่ก่อน core init สำเร็จ จึงต้อง quarantine ก่อน join ที่มีการ drain mailbox ไม่ใช่แค่ลบ assertion
- owner ถูก copy เข้า `self` แล้ว แต่ errdefers เดิมยังทำลาย temporary copies ซึ่งอาจไม่ตรงกับ state ที่ workers แก้แล้ว
- font-grid reference ที่เพิ่ง acquire ขาด error-path dereference
- initial-title actions ยัง throw ได้หลังเริ่ม workers ทั้งคู่

ทางแก้จำกัด Windows: ใช้ startup transaction หยุด/join renderer เมื่อ IO start ล้มเหลว, ถอด routing/registry แบบ idempotent ก่อน join และ drain pending messages หลัง join ก่อนคืน address, ทำลาย authoritative owners ตามลำดับ teardown, คืน font reference เมื่อ init ล้มเหลว และเริ่ม Windows workers หลัง fallible initial-title actions ทั้งหมด ไม่ย้าย startup ของแพลตฟอร์มอื่น

## หลักฐานทดสอบ

รากหลักฐาน local: `zig-out/lifecycle-review-20261030-010851-497/`

| ชุดตรวจ | ผลที่ตรวจแล้ว |
| --- | --- |
| helper fault injection ก่อนเพิ่ม rollback | **2 ผ่าน / 1 ล้มจริง** ที่ IO failure คืน dependency ขณะ renderer ยัง live; ไม่ใช้ compiler/argument failure เป็น RED |
| helper หลังเพิ่ม rollback | **3/3 ทั้ง Debug และ ReleaseSafe**; fake operations ไม่ทำเครื่อง OOM จริง |
| supervisor classification | **10 cases ผ่าน** แบบ data-only; missing join/quarantine, panic, error อื่น, shell launch และ title failure หลัง worker start ต้องไม่ผ่าน |
| native attempt แรกก่อนแก้ quarantine/owner/font ครบ | renderer failure เกิด **panic / exit 3** จริง เก็บ receipt/log เดิมไว้ ไม่ถือว่าชุด helper ผ่านแล้วเท่ากับ native ผ่าน |
| native renderer-start failure หลังแก้ครบ | expected exit **1**, ไม่มี panic/timeout, ไม่เริ่ม shell, ไม่อ้างว่า join worker ที่ยังไม่ถูกสร้าง |
| native IO-start failure หลังแก้ครบ | renderer ถูกสร้างจริง → quarantine → join receipt → expected exit **1**, ไม่มี panic/timeout/owned-tree cleanup |
| native initial-title failure | expected exit **1**, ไม่มี worker-start/join หรือ shell launch |
| native terminal ปกติ | exit **0**, UTF-8/Thai marker และ actual frame/paint ผ่าน ไม่มี owned-tree cleanup |
| existing GPU-worker opt-in: startup failures + terminal ปกติ | fresh build125/125 และ negative renderer/IO/title ทั้งสาม + positive terminal ผ่านจริง; close ACK/exit/job-empty ครบ ไม่ใช่ default promotion |
| GPU-worker opt-in: strict lifecycle | **ยัง failed `TerminalPresentationFailed`**: cycle12 (surface13) เกิด `TerminalMarkerMissing`; worker close **21/21 ACK1/exit0/jobempty1/forced0**, frames/paints166, handles123→123/GDI2→2/USER1→1/threads4→1; resourceไม่โตแต่ไม่ใช่ผลผ่าน และไม่ใช่หลักฐานล้างoldclosefault |
| normal strict lifecycle หลังแก้ | **ยัง ResourceGrowth** ตามตัวเลขด้านบน ไม่ยกเว้น failure |
| full-core ไม่มี filter ผ่าน build runner | **timeout 900s / forced owned-tree cleanup / root exit confirmed**, source unchanged, stdout/stderr ว่าง ไม่มี executed-test summary จึงไม่ผ่าน; ยังไม่ระบุว่า test ใดล้มเหลว |
| same full-suite binary แบบ direct runner | **3,994 ผ่าน / 61 skipped / 0 failed**, ครบ4055/4055, exit0, ไม่timeout/forcedcleanup, source/binary unchanged; แยก verdict จาก build runner ที่ timeout |
| ตัวอ่าน footer ของ direct supervisor | เดิม false-negative เมื่อมี skipped; RED จาก actualfooter แล้วแก้predicate, offline regression **9/9** รวม timeout/forcedcleanup/failed acquisitionกับoldsuccess ไม่รันทดสอบ4055ข้อซ้ำ และเก็บrawreceipt/logไว้ |

Native ReleaseSafe candidate: `fixed/bin/localterm-dev.exe` ภายในรากหลักฐาน SHA-256 `46CF3E40A197A05B12735251DC97A616C33FC12F62AE06A321DC177A959291F5` มี source snapshot/hash ก่อน–หลังและ fresh receipt แยกแต่ละ case

Full-core direct test binary SHA-256 `A6914AA1CBFFD599655A00BC669C6EBB65208C4954F92FB6D38B30C202717E94`; ดู `full-core-direct-verified.json` และ `verify-core-direct.ps1` สำหรับการตรวจ exit/coverage/source/binary/log provenance จากหลักฐานเดิม การผ่านแบบ direct ไม่ได้ทำให้ build-runner timeout กลายเป็นผ่าน และยังไม่สรุปว่า runner มีบั๊กหรือเคสทดสอบค้าง

Negative fixtures เปิดด้วย `runtime-smoke.ps1 -Mode terminal -WorkerStartupFailure renderer|io|title` เท่านั้น ไม่ใช่โหมดใช้งานปกติ ตรวจเฉพาะ expected error แบบ exact และติดป้าย `readiness_evidence=false` การไม่มี frame ใน negative fixtureไม่ใช่หลักฐานการ render; positive terminal/strict run แยกต่างหากยังต้องมี frame จริง

ผล opt-in ล่าสุดอยู่ `remote-startup-*.json` / `strict-run-remote.json` และไม่เขียนทับ legacy receipts มี diagnostic จำกัดหนึ่งรอบเพื่อเก็บเวลา log และ CPU/working-set ของ owned PowerShell child โดยไม่เปลี่ยน source,3sclose cadence,120sdeadline,PSS หรือwarmup (`marker-observer*`) ผล diagnosticไม่ล้าง original failureแม้รอบถัดไปผ่าน ยังไม่สรุปว่าCLRstartupช้าหรือConPTY/VTทำข้อมูลหายจากคำว่าmarker missingเพียงอย่างเดียว

รอบ observer จบโดยไม่ทำซ้ำ failure: native exit0, handles128→128, GDI2→2,USER1→1,threads4→1,frames/paints168; sample shell60จุด/21PID/21cycles เป็น **diagnostic-only** ไม่ล้าง cycle12 ที่ล้ม

### Diagnostic-only delta หลัง source V2 ที่ผ่าน regression

เพิ่ม `terminal_marker_diagnostic.zig` และเรียกจาก Win32 App **เฉพาะเมื่อ marker check เดิมล้มและ `lifecycle_smoke=true`**: บอก byte count, ASCII-marker/Thai flags แยกกัน และ raw prefixสูงสุด96bytesในBase64 ไม่เพิ่มเวลา/เปลี่ยนcondition ไม่ log input จาก normal terminal/preview และไม่อ้างว่าแก้ markerหายแล้ว

โมดูล snapshot ผ่าน3/3ทั้งDebug/ReleaseSafe ครอบคลุมempty,flagsอิสระ,whole-text searchแม้sampleถูกcap และdecodeยืนยันprefix ส่วนdiagnostic-versionสองbackend **buildและpositive terminal/frameผ่านแล้ว** แยกจาก V2 receipts ข้างต้น Core startup/ownership code และhelperไม่เปลี่ยนจาก V2 ที่ผ่าน3994tests ไม่อ้างว่ารันfull-coreชุดเดิมซ้ำหลังเพิ่มdiagnostic

V3 legacy SHA-256 `A7666F948016F4177D4E98DD25788587F2B867AD86458D60973FE2B8A8C040D6`; V3 opt-in remote `DECEF6DDC74094C2C4A07F9B4299F189C76FF78583B812206E8571C4E344C9D5` ดู `diagnostic-*-build.json` / `diagnostic-*-smoke.json`

ทำ bounded capture ของ V3 **หนึ่งรอบเท่านั้น** พร้อมsame-runowned-shell timing/CPUและfailure-onlysnapshot ราก `diagnostic-marker-capture.json` / `marker-observer-v3*`: รอบนี้exit0,source unchanged,frames/paints168,handles128→128/GDI2→2/USER1→1/threads4→1 ไม่พบmarkerfailureจึงไม่มีsnapshotจริงให้วิเคราะห์ **ไม่ใช่หลักฐานว่าแก้cycle12แล้ว** และไม่ทำstressวนเพื่อให้ผ่าน ฟังก์ชันsnapshotมีunitcoverage แต่เส้นทางemitในnativeยังไม่ได้ถูกtriggerในการcaptureนี้

จบขอบเขตการทดลองรอบนี้โดยยังคงสองblockers: legacy `ResourceGrowth` และ opt-in `TerminalMarkerMissing` ที่ยังไม่ทราบสาเหตุ ต้องได้failure-traceใหม่ก่อนเลือกlogicfix ไม่เพิ่มbudget/ผ่อนmarkercheck/เปิดdefaultจากผลpassภายหลัง หลักฐานและcandidateที่สร้างในรากนี้รวมประมาณ666MiB ไม่มีcloneใหม่ ไม่ลบcache/โปรไฟล์/ข้อมูลจริง

## ข้อจำกัดและงานต่อ

ผลนี้พิสูจน์ scoped startup-error cleanup ไม่ได้พิสูจน์ว่า normal +1 handle/+1 thread เป็นของแอปทั้งหมดหรือเป็น cache ที่ไม่มีอันตราย รายการ/entry module จาก snapshot ไม่ใช่ live creator attribution จึงยังไม่ปิด `WIN-RUNTIME-004` หรือยกเกณฑ์ให้ผ่าน

ยังไม่รับรอง failure→retry/address reuse แบบ stress ใน process เดียว, remote-renderer production qualification, GPU-busy/long-duration, physical mixed-DPI, IME หรือ WSL จริง ผลนอกขอบจอไม่ใช่ human visual acceptance และไม่เปลี่ยนผล Thai-arrow case ที่ผู้ใช้ยืนยันผ่านไว้แล้ว
