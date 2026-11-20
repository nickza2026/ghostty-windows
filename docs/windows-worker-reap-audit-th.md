# Windows worker reap — CPU-only audit 27 ตุลาคม 2026

## ขอบเขตและสถานะ

ผู้ใช้อนุมัติเริ่มจาก shutdown/cleanup evidence และ CPU fixtures ก่อน โดย GPU qualification ยัง pause ไม่เปลี่ยน renderer default, RPC/cleanup budgets, warmup หรือ acceptance gates ไม่ commit/push และรักษา dirty work เดิมบน `windows-terminal-baseline`

**แก้และพิสูจน์ได้หนึ่ง defect แยก:** production `reap()` อาจเริ่ม job-empty poll หลัง budget เพราะใช้ `Sleep(10)` แม้เหลือเวลาเพียง1ms แล้ว query readiness ก่อนตรวจ deadline จึงรับสถานะ job-empty ที่เพิ่งมาช้ากว่า budget เป็น success ได้

**ไม่ได้พิสูจน์ว่าแก้ historical exec181/exec244:** สองเคสเดิมเป็น close/cleanup failure ไม่ใช่หลักฐาน late-success defect นี้ และยังไม่รัน original GPU reproduction ในรอบ CPU-only นี้ การทวน functional failure ด้วย GPU worker จริงต้องแยกจาก GPU-busy/performance qualification ที่ยัง pause ไม่เหมารวมว่าเป็นการรับรองเฟส GPU แล้ว

## หลักฐานเดิมที่อ่านตรง

Artifacts อยู่ `%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\phase3b-runtime\`

- `lifecycle-native-20261020-163502-145.stderr.log`: UTF-8 มี NUL บางส่วน อ่านโดยตัด NUL เฉพาะ display (ไม่แก้ raw file) พบ `error: remote host worker close failed: error.WorkerCloseFailed` ก่อน cycle15 ไม่มี original per-stage finish/process-exit/job-empty/forced fields จึงเติมค่าเหล่านี้ย้อนหลังไม่ได้
- `render-worker-real-late-rendered-20261020-201951.run1.stderr.log`: exact `error: LateRenderedCleanupFailed`; original assertion รวมหลายเงื่อนไข ไม่มี component values
- Later diagnostic/stress passes ไม่อธิบายต้นเหตุ failures เก่า
- Worker publish `.closed` ก่อน executor/context/device teardown และ process exit ดังนั้น ACK ไม่ได้แปลว่า process/job จบแล้ว โค้ดยังต้องตรวจ natural exit0 + empty job + no forced cleanup ตามเดิม

## Defect และ minimal correction

ตัวอย่าง deterministic ที่ใช้ production implementation กับ private Win32 boundary stubs:

1. เริ่ม budget50ms, process wait คืนที่เวลา49ms
2. Job ยัง active; จะ empty ที่51ms
3. โค้ดเดิม sleep10ms แล้ว query ที่59ms พบemptyและคืนsuccess ทั้งที่เป็น **subsequent poll หลังdeadline**
4. กรณี scheduler oversleep: sleep10จาก40ms แต่ fake clock ไป61ms โค้ดเดิมก็ query/accept หลังdeadline

แก้เฉพาะ loop ใน `src/render_worker_client.c`:

- เก็บ initial nonblocking job probe หลัง process signal ไว้: OS waiting thread อาจถูก schedule ช้าทั้งที่ signal มาทันเวลา รวม direct reap budget0
- subsequent poll เริ่มได้ไม่เกิน original deadline; ตรวจ clock ก่อน poll ถัดไปหลัง Sleep
- ขอ Sleep ไม่เกิน `min(10, remaining)` ไม่มีการต่อ budget
- readiness ตรงdeadlineยังตรวจได้แบบไม่รอ; jobยังactiveที่deadlineไม่ได้เวลารอเพิ่ม
- ACK validation, exit code0, job-empty requirement, forced cleanup semantics และ status ABI ไม่เปลี่ยน

นี่เป็น **polling-budget correction ไม่ใช่ hard-wall return-time guarantee**: OS scheduling และ QueryInformationJobObject latency ไม่สามารถยกเลิกย้อนหลังด้วย loop นี้ได้ และ initial immediate probe ยังคง semantics เดิม

## Regression และ related checks ที่รันจริง

### Private deterministic CPU fixture

`src/render_worker_reap_check.c` include production implementation แล้ว substituteเฉพาะ clock/process-wait/exit-query/job-query/Sleep ใน test translation unit ไม่มี process/worker/GPU/HWND/real waits หรือ hooks ใน production

| Target / revision | ผลจริง | Artifact directory |
|---|---|---|
| Original source / default GNU Debug, initial11cases | exit1, 2 failed | `reap-cpu-original-20261027-103647-552` |
| Fixed / GNU Debug + ReleaseSafe, final16cases | ทั้งคู่ exit0, 16/16 | `reap-cpu-boundaries-Debug-20261027-105450-149`, `...ReleaseSafe-20261027-105452-101` |
| **Original saved source / explicit MSVC baseline, same final16cases** | **exit1, 3 failed** | `reap-cpu-msvc-original-Debug-20261027-110012-879` |
| **Fixed MSVC baseline Debug** | **exit0, 16/16** | `reap-cpu-msvc-fixed-Debug-20261027-110014-755` |
| **Fixed MSVC baseline ReleaseSafe** | **exit0, 16/16** | `reap-cpu-msvc-fixed-ReleaseSafe-20261027-110016-398` |

Final16cases ครอบคลุม within-budget success, late job-empty, oversleep, exact deadline, direct assertionว่า Sleep requestไม่เกินremaining, process timeout/wait failure, exit query failure, job query failure, nonzero child exit, missing ACK, zero-budget finish rejection และ initial nonblocking readiness preservation

Original source ถูกเก็บก่อนpatchแล้ว copyพร้อมcurrenttest/headerเข้า private artifact directory เพื่อรัน red ไม่ reset checkout หรือย้อน dirty files

### Related CPU contracts / compile-only integration

- `src/render_worker_contract_tests.zig`: **39/39 Debug และ39/39 ReleaseSafe**, explicit `x86_64-windows-msvc`, baseline CPU; compile `--test-no-exec` ก่อน launchผ่าน CreateNoWindow + redirected streams ไม่มี console/GUI
- Artifacts `reap-related-contracts-Debug-20261027-104851-248` และ `...ReleaseSafe-20261027-104903-274`
- **compile-only private client/worker graph32/32ผ่าน**, ReleaseSafe MSVC/baseline, source hashesไม่เปลี่ยนระหว่างbuild; artifact `reap-client-compile-20261027-105940-284`, prefixใหม่ `zig-out/reap-client-compile-20261027-105940-284`
- เก็บactualexecutedtooltranscriptเพิ่มเป็น `build-transcript.log` พร้อมSHA/summaryใน `compile-summary-evidence.json` เพราะoriginalreceiptมีเพียงexit0/sourcehashes ไม่ได้เก็บstepcount ห้ามใช้receiptเดิมอย่างเดียวอ้างindependent32/32 verification
- ไม่ execute client-check/GL workers ที่ได้จาก build นี้ และไม่ถือว่า GPU runtime ผ่าน
- แก้คำอธิบาย named build step `windows-render-client-check`: เดิมอ้างCPU-only แต่ executionจริง initializeWGLก่อนhelloและมีrealrenderedfixtures ตอนนี้แจ้งว่า executionมีWGL/GPU ชัดเจน ไม่เปลี่ยนbuild dependencies/default

ตัวอย่าง compile regression (ต้องตรวจ exit และใช้ bounded hidden runnerเหมือนreceipts):

```powershell
$zig = Join-Path $env:LOCALAPPDATA 'Programs\Zig\zig-x86_64-windows-0.16.0\zig.exe'
& $zig build-exe src/render_worker_reap_check.c -target x86_64-windows-msvc -mcpu baseline -lc -O Debug --subsystem windows '-femit-bin=<private-output>\cpu-reap.exe'
# No GPU/window/child processes in this executable. Run with redirected output,
# retained process handle and external 10-second deadline; require exit0.
```

## Real CPU process/job fixture — strict global count ยัง failed

`src/render_worker_reap_os_check.c` สร้างเฉพาะ self-executable CPU child ใน private kill-on-job-close job ผ่าน handle-list allowlist2events, suspended-before-job assignment และ retained observer process handle ไม่มี PIDinput/foreign process discovery/kill-by-name/WGL/window/driver settings

`close_ack` เป็น **synthetic precondition ไม่ใช่ wire ACK proof**; planned cases natural0/nonzero77/ACK-but-heldprocess แต่ **หยุดที่case0 failure จึงยังไม่อ้างว่าrealnegativecasesผ่าน**

- `reap-os-cpu-Debug-20261027-104219-096`: finish/destroy/observer exit/statusครบ แต่ global handles61→66 จึงfixture **exit1/failed** ไม่เพิ่มwarmupเพื่อให้ผ่าน
- `reap-os-stages-20261027-104643-351`: afterevents/job64 → afterCreateProcess71 (owned process/threadอธิบาย2 จาก+7) → observer72 → startupthreadclosed71 → productiondestroy69 → finalfixturehandlesclosed66 เทียบbaseline61 จึง+5เกิดก่อนreap
- defaultstandalonecompiler targetตรวจจริงเป็นGNU; explicitproductionMSVC control `reap-os-msvc-Debug-20261027-105647-069` ยังfailed61→66 จึงไม่ถือtargetmismatchเป็นสาเหตุหรือใช้เปลี่ยนtargetเพื่อซ่อนfailure
- Independent cold Win32 control **ข้าม production finish/destroy**, directwait/closeเท่านั้น, mode3มีactual markerยืนยัน: `reap-os-cold-verified-20261027-105408-526` ยัง **exit1 /61→66** ไม่warmupและคงglobalassertion
- Wrong-mode attempt `...cold-win32-control-20261027-105133-005` ไม่ได้เข้าcontrolจริง; เก็บqualification=falseพร้อมเหตุผลแยกไว้ ไม่ใช้wrapperintent fieldเป็นexecutionproof แก้privateflag whitespace parsingแล้วจึงได้verifiedmode3ข้างต้น
- Startup failure cleanup diagnosticsเพิ่มactualdestroy/observer outcomes ไม่ ignoreผลเงียบ และโอนprocessownershipก่อนcheckpoint

สิ่งที่สรุปได้คือ **production reap ไม่จำเป็นต่อการเกิด cold +5ในfixtureนี้** ยังไม่ทราบชนิด/ownerหรือพิสูจน์ว่าbenign/cache จึงไม่อ้างglobal zero-leak, realOSintegrationผ่าน, normalWIN004resolved หรือรับexceptionเอง

## Independent review / งานค้าง

Verifier read-onlyให้ conditional pass สำหรับnarrow loop correctionและตรวจraworiginal/fixed13case receipts/source hashes; ขอexact-deadline/clamped-Sleep coverageซึ่งเพิ่มและรันfinal16MSVCแล้ว รวมแก้privatefixturecleanupreportingตามที่พบ ไม่ได้ให้OSintegrationpass

Final verifierทวนsamefinalfixturehashในMSVC original/fixedreceiptsแล้ว: original3/16failed → 16/16ทั้งสองmode และrelated39/39ถูกต้อง; productionCไม่เปลี่ยนจากreviewก่อนหน้า ไม่พบscope/safety misstatementใหม่ Count32/32เก็บactualtranscriptเพิ่มตามข้อสังเกตข้างต้น ไม่อ้างว่าverifierได้ตรวจtranscriptนั้นก่อนเก็บ

Optional Astra advisory ไม่ได้ผล (`fetch failed`, own worker outputลงท้ายTask failed) ไม่นับเป็นreviewpass ไม่เปลี่ยนmodel/globalconfigหรือซ่อมauthenticationเพื่อฝืนใช้

ยังเปิด: historical181/244 root causes/reproduction, realOSfixture cold+5 attribution/strictcount, actual GPU-busy/performance, normal WIN-RUNTIME-004และhuman acceptance งานนี้ไม่ปิดfailureเก่าเพราะunit/buildผ่าน และไม่รับรองappพร้อมส่งมอบ
