# Post-fix resource attribution — 26 ตุลาคม 2026

## สถานะ

**`WIN-RUNTIME-004` ยัง failed/open และไม่มี app-owned resource fix ใหม่ที่พิสูจน์แล้ว** สอง fix ก่อนหน้าเป็น inheritance isolation และ attribute-list API lifetime ไม่ใช่หลักฐานว่าแก้ +1 handle/+1 thread

ไม่ commit/push ไม่เปลี่ยน driver/global settings/GPU default/threshold/warmup/deadline และไม่ปิด handle หรือ thread ของโปรแกรมอื่น

## Normal strict lifecycle หลังสอง fix

รันครั้งเดียว `lifecycle-native-20261026-203702-064` โดยใช้ production ReleaseSafe SHA-256 `10ADEFA20075AC921A47CCF63DA56D11467E6E6D769A7916184EEDB197BA2741` จาก `zig-out/attributes-build-20261026-202012-333/bin/localterm-dev.exe`

- normal build `windows-portable-default=false`, ไม่มี `portable-data` ก่อน/หลัง ไม่มี font/background override
- app-local Microsoft ConPTY `1.25.260930003` จาก pinned bundle เดิม ตรวจ hashes/ลายเซ็นใหม่ คัดลอกเฉพาะ runtime/license/receipt เข้า private candidate ไม่ดาวน์โหลดหรือทับ portable เดิม
- PSS enabled, warmup 1 +20 cycles, strict comparison และ default lifecycle deadline 120s เดิม
- offscreen x=1984 y=0, no-activate, ยังต้องผ่าน render/paint; ไม่ใช่ on-screen acceptance
- exit 1 / `ResourceGrowth`, **handles 242→243, threads 6→7, GDI 3→3, USER 3→3** ไม่ timeout, `cleaned_descendants=[]`, source inputs ไม่เปลี่ยน
- artifact ใช้ provider diagnostic จึง `readiness_evidence=false` แม้ว่าจะคง strict resource predicate เดิม ไม่ใช้ absolute counts เทียบกับ process/run เก่าแล้วกล่าวว่า leak เพิ่มหรือลด

หลักฐาน `%LOCALAPPDATA%/Letta/build-logs/ghostty-windows/phase3b-runtime/`:

- `lifecycle-native-20261026-203702-064.stderr.log` และ row ชื่อเดียวกันใน `results.jsonl`
- `postfix-attribution-20261026-203701-992.json`: source/executable hashes, signed runtime pins, marker absence และ wrapper failure

### Numeric metadata ภายใน run เดียวกัน

| Type count | Baseline | Final | Delta |
|---|---:|---:|---:|
| ALPC Port | 4 | 2 | −2 |
| Event | 42 | 43 | +1 |
| Thread | 3 | 5 | +2 |

ประเภทอื่น count เท่าเดิม รวม net +1 handle ตารางนี้ไม่ใช่ object identity และไม่พิสูจน์ creator/closed owner

Final retained thread slots `0x4e4`→TID27720 (entry module `amdihk64.dll`) และ `0x6f8`→TID23304 (`ntdll.dll`) มาจาก **run นี้เท่านั้น** entry module ไม่ใช่ allocation caller ห้ามยืม TID/handle/creator stack ของรอบเก่ามาแทน

## ช่องว่างที่ไม่ทำซ้ำ

อ่าน `windows-runtime-attribution.md` และ entry-trace scripts เดิมแล้ว การขยาย NtCreate/NtDuplicate entry sweep เคยไม่พบ live caller ของ Event/IOCP บางรายการ แถม debugger counts ต่างจาก normal การพิมพ์ out-pointer ที่ API entry ไม่ใช่ค่าของ returned handle จึงไม่ยกระดับเป็น exact object correlation

Astra เห็นด้วยกับหนึ่ง close-side control เพื่อเติมช่องว่าง **ผู้เรียกปิด baseline ALPC handles ใน diagnostic run นั้น** เท่านั้น ไม่ใช่ creator/owner/leak cause และไม่แก้ normal gate โดยตรง

## Close-side controller: qualification จาก private control ก่อน Native

เพิ่ม `tools/windows/native-close-attribution.ps1` และ private `close-attribution-control.c` เพื่อทดสอบ protocol ก่อนใช้กับแอป ไม่ใช้ private-control failure อนุญาต native launch

สัญญาของ collector และขอบเขตการตรวจ:

- type-only `!handle 0 1` ตอน baseline stop; ไม่มี object names/memory dumps
- selected slots จาก run ปัจจุบันเท่านั้น, จำกัด 16 slots/16 stops/output cap/outer deadline
- attempted close ต้องมี exact input handle + TID + basic stack
- `gu` ไม่ระบุ thread จึงไม่ freeze threads อื่น ตรวจ return ด้วย TID/return address/expected RSP และ low32 NTSTATUS
- ช่วง disable breakpoint ระหว่าง `gu` เป็น blind interval ต้องเก็บ full per-slot history และยอมรับได้เพียง partial attribution; snapshot diff อย่างเดียวไม่พอ

### ผล private control ที่ล้ม — ไม่ใช่หลักฐาน resource bug ของแอป

1. `close-attribution-control-20261026-205857-625`: ไม่รับ baseline marker เพราะ nested printf output มี symbol text ต่อท้าย; deadline60s/forced owned-tree cleanup ต้องเก็บเป็น infrastructure failure พบเพิ่มว่า `zig cc -mwindows` ถูก ignore และ PE subsystem=3 จึงห้ามเรียกว่าเป็น no-console control ที่ยืนยันแล้ว
2. clean recovery เพียงครั้งเดียว `close-attribution-control-20261026-210312-324`: ใช้ documented `zig build-exe ... -lc --subsystem windows`, PE preflight=2; ถึง baseline/เลือก private Event `0xac` ใน run นี้ได้ แต่ค้างที่ framing ของ `0:000> LC_QUERY_END` จึง **ยังไม่ตั้ง NtClose breakpointหรือเริ่ม return validation** deadline60s/forced cleanup, retained root/debuggee exit confirmed, observed remaining descendants=[] และ exact-owned-control liveness check หลังจบ=0

ทั้งสองรอบ `readiness_evidence=false`, ไม่มี final/history completion/validated returns; ไม่ใช้เป็น allocation attribution หลังพบ specific parser defect จึงทำ offline regression/fix ก่อนทวน control บน revision ใหม่ ไม่เพิ่ม deadline หรือใช้ failure เหล่านี้เป็นข้ออ้างให้รัน native

### แก้ parser แบบ offline แล้ว แต่ยังไม่ใช่ controller runtime pass

เพิ่ม normalization เฉพาะ CDB thread-prompt prefix โดยเก็บ raw logs เดิมและไม่รับ `.echo ...` command echo เป็น receipt:

- offline regression original-red: `0:000> LC_QUERY_END` ไม่เท่ากับ `LC_QUERY_END`
- หลังแก้ครั้งแรก ผ่าน **5 synthetic framing cases** และ replay exact recovery transcript แบบ data-only
- `tools/windows/close-attribution-parser-test.ps1` โหลดเฉพาะ function AST ที่เราเขียน ไม่ execute controller body/CDB/process/window
- `Mode=native` มี early qualification guard `NOT QUALIFIED`: ต้องส่ง completed-control receipt จาก **controller SHA เดียวกัน** ซึ่งมี verified successful return/full phase protocol/no timeout/no forced cleanup/root+target exit/ไม่มี remaining descendants ก่อน offline parser pass อย่างเดียวไม่พอ

### ทวน revision ที่แก้ parser และไม่ซ่อน failure

- `close-attribution-control-20261026-211733-707`: baseline/type-selection ผ่านและ raw log มี actual NtClose entry/basic stack ของ private Event แล้ว แต่ output มี **สอง prompts ต่อกัน** (`0:000> 0:000> LC_CLOSE_ENTER...`) ทำให้ parser แบบ strip หนึ่ง prompt ไม่เห็น event ยังไม่มี return/final/history completion; timeout60s/forced cleanup, root+target exit confirmed, remaining=[] ไม่อ้างว่า matching_stops=0 แปลว่า breakpoint ไม่เคย hit เพราะค่าดังกล่าวคือจำนวนที่ parser อ่านได้
- เพิ่ม offline case จาก exact log ให้แดงก่อนแก้ แล้ว normalize consecutive prompt prefixes ผ่าน **6 cases + exact close-entry transcript replay**
- หยุดติดตาม numeric slot หลัง observed successful close แรกเพื่อไม่อ้างว่าการใช้ slot ซ้ำภายหลังยังเป็น baseline object; full history review ยังคงจำเป็น
- independent verifier ให้ conditional safety pass จากซอร์สเท่านั้น ไม่ใช่ runtime qualification ของ controller
- **runtime control ผ่าน** `close-attribution-control-20261026-212231-273`: exit0, baseline/final/history completion ครบ, exact private Event `0xac` มี verified close หนึ่งครั้ง TID31248/return addressตรงกัน, return RSP=entry+8, low32 NTSTATUS=0; raw histories OPEN ก่อน baseline และ CLOSE→OPEN แบบ reverse chronology ตอน final ไม่มีการ reuse ใน private control
- controller SHA-256 `8564F79455BFC0DBA1D156603CB247B41DC5FD0A71CE6BC3EF6C9D0F11F746C2`, source ไม่เปลี่ยนระหว่างรัน, ไม่ timeout/forced cleanup, root+target exit confirmed และ observed remaining descendants=[]
- `close-attribution-native-20261026-212508-317` ใช้ receipt/revision ตรงกัน แต่ **incomplete / timeout240s / forced cleanup**: baseline เลือก ALPC4 slots ได้ ก่อน CDB หยุดด้วย `Numeric expression missing` จาก predicate ที่ใช้ C-style `||` ใน MASM จึงไม่มี verified close return/final/history ไม่ใช่ ResourceGrowth result ใหม่หรือ allocation proof ของแอป root+target exit confirmed, remaining=[]
- ช่องโหว่ coverage คือ single-Event control ไม่ได้รัน predicate หลาย slots ไม่ลบผลผ่าน single-control แต่ไม่ใช้ยืนยัน multi-slot path ย้อนหลัง
- ตรวจ Microsoft MASM docs แล้ว comparisons ให้0/1 และต้องรวมด้วย `or` (หรือ `|`) ไม่ใช่ `||`; เพิ่ม offline condition regression ให้แดงก่อนแก้ แล้ว green พร้อม framing6cases
- ขยาย private control เป็น **4 Events** เพื่อทดสอบการสร้าง/ลด predicate 4→3→2→1 และต้องได้ successful returns ครบ4ก่อน native qualification; เพิ่ม fail-fast เมื่อ CDB รายงาน numeric/syntax error แทนรอdeadline
- **four-slot control ผ่านจริง** `close-attribution-control-20261026-213517-731`: exit0/ครบbaseline/final/history, four distinct Event slots, verified successful returns4 (ทุกอัน TID/RIP/RSP=entry+8ตรง, NTSTATUS0), full historiesแต่ละslotOPEN→CLOSE, no timeout/forced cleanup/remaining descendants, root+target exit confirmed
- controller SHA `FBC3F1147EEC1A06FB810EA7C3755F34DB8C75FFE38A54A87BD813E4918E447B`; private control exe SHA `0A6F48F77395BD4E3EFB636597D0F6F6B06EF5F75A22EF1D430223DCF82DEB82` Native guard require four successful returnsจากrevisionนี้ ไม่ใช้single-slot receiptเก่าหรือofflinepassอนุญาตlaunch
- native close-side บน MASM-correct revision จบแล้วตามหัวข้อถัดไป ไม่เปลี่ยน workload/deadline

## หลักฐานใหม่: observed close caller ของ baseline ALPC สอง generations

รอบ **`close-attribution-native-20261026-213658-329`**, PID28516 (`0x6f64`), executable/controller SHAs ตามข้างต้น:

| Baseline ALPC slot ใน run นี้ | Observed close TID | Native return | Live basic stack |
|---|---:|---|---|
| `0xbc8` | 5832 (`0x16c8`) | NTSTATUS0, same TID/RIP, RSP=entry+8 | `NtClose ← RPCRT4!LRPC_CASSOCIATION::~LRPC_CASSOCIATION ← LrpcDeleteLingeringAssociations ← PerformGarbageCollection ← NTDLL timer callback` |
| `0xbd0` | 5832 (`0x16c8`) | เช่นเดียวกัน | stack เดียวกัน |

**พิสูจน์ได้ว่า RPC garbage-collection path เป็น observed successful close caller ของ baseline generations สองรายการนี้ใน diagnostic run นี้** ไม่ได้พิสูจน์ creator/ownership ของ retained opens, ไม่ใช่ app-owned cleanup patch และห้ามนำเลขเหล่านี้ไปจับคู่ normal run

### ป้องกันข้อสรุปผิดจาก handle-slot reuse

Raw full histories แสดงการ reuse slot ทั้งสองภายหลังจริง จึงไม่ได้เอา handle number อย่างเดียวเป็น identity:

- baseline per-slot history มี1 OPEN; final per-slot history มี34 records แบบ newest-first
- baseline history เป็น exact suffix ของ final history; chronological first record ที่เพิ่มคือ CLOSE จากTID5832 และมี CLOSE จากTIDนี้เพียงครั้งเดียวต่อslotหลังbaseline ตรง observed/verified return
- อีก32 records ต่อslotเป็น reuse ภายหลัง จงใจไม่นับเป็น object เดิมหรือ caller ของ baseline generation
- reported full trace database31833 records < configured65536; ไม่มี block count mismatch/truncation ที่พบ
- `tools/windows/close-attribution-history-audit.ps1` ทำเฉพาะ offline numeric suffix/sequence/TID/PID audit เขียน `history-audit.json` ใน artifact directory ไม่ launch/attach process

`result.json` ระบุ baseline/final/history completionครบ, source/controllerไม่เปลี่ยน, root+target exit confirmed, no timeout/forced cleanup/observed remaining descendants อย่างไรก็ดี **debugger exit1 มาจากแอปที่ยัง `ResourceGrowth`: handles235→236, GDI/USER3คงที่, threads6→10** ไม่ใช่ normal strict pass และห้ามเทียบ absolute counts กับ normal242→243/6→7 เป็น improvement

Snapshot diff พบ outstanding OPEN3รายการใน diagnostic run นี้; ใน collector นี้มีเพียง numeric creator TID ไม่มี live creator API-return evidence จึงยังไม่ระบุว่าเป็น retained allocation owner ครบแล้ว กำลังเพิ่ม filtered public-API returned-HANDLE control แยกจากclosecollector ไม่แก้ production source/defaultหรือแอบอ้างว่าปิดWIN004

## Creator-return collector แยก: ต้องจับ HANDLE จริง ไม่ใช่ out-pointer

ไฟล์ `native-open-attribution.ps1`, `open-attribution-control.c`, `open-attribution-parser-test.ps1` ไม่เปลี่ยน app/build/default ตั้งเพียงสาม API families หลังbaseline:

- `KERNELBASE!CreateEventW`: filter caller return PC อยู่ใน **RPCRT4 module bounds ของ process ปัจจุบัน**; HANDLE จากRAXหลัง verified return
- `KERNELBASE!DuplicateHandle`: filtercallerRPCRT4และsource current-thread pseudohandle−2; ต้อง verified BOOL success ก่อนอ่าน **HANDLEเพียงหนึ่งค่าจากpublicoutputpointerที่บันทึกตอนentry** ไม่อ่านชื่อ/ข้อมูลอื่น
- ordinary `CreateThread`: filter startR8 อยู่ใน **amdihk64 bounds ของ process ปัจจุบัน**; จับHANDLEจากRAX ตรวจactualcurrentpublicsymbolsพบชื่อ `KERNEL32!CreateThreadStub` จึง resolveชื่อนี้ในแต่ละprocess ไม่คัดลอกoffset/addressข้ามrun

ข้อผิดพลาด/ข้อจำกัดที่เก็บไว้:

- controlเดิมที่บังคับKERNELBASECreateThreadผ่าน เป็นเพียงABI/site control ไม่ใช่ ordinary-import route proof จึงไม่ใช้อนุญาตnativeบนเส้นทางนั้น
- ordinary-route control `...215406-007` failเพราะPDBไม่ resolveชื่อ `KERNEL32!CreateThread` เก็บforcedcleanup/failedqualificationไว้; parentทำowned private `x kernel32!*CreateThread*` ก่อนentry พบactualpublicsymbolCreateThreadStubใน `thread-export-map-20261026-215721-581`
- control `...220117-415` และ `...220432-800` บนordinaryimportจับreturnedhandles3APIตรงกับcontrolledpublicationsจริง ทั้งหมดsameTID/RIP/RSPentry+8/no forcedcleanup/remnants พร้อมOPENhistories; labelmetadataแก้ให้ตรงactualStubsiteก่อนใช้native
- Native exit1ต้องมี exact `error: ResourceGrowth` เท่านั้นและไม่มีother/scoped errors/panic/critical/fatal เพื่อแยก **application_failure** ออกจาก **protocol_complete** ไม่แปลงเป็นnormal-gate pass มีofflineclassification regressionสำหรับscopedZigerrors
- source/controller/privateexe hashesต้องตรงqualifiedreceipt; PE2/signedCDB/retainedownedidentities/stop-output-deadlinecaps/cleanupเหมือนclosecollector; plain-gu blind intervalsยังมี ไม่กล่าวว่าไม่มีcreationเมื่อไม่มีcapture

Independent verifierให้conditionalsource-safety passสำหรับoneNativeattemptหลังsame-revisionordinary-routecontrolครบเท่านั้น `handle_histories.complete` เป็นเพียงcapture/delimiter check ไม่ใช่automaticgeneration/callerproof ต้องตรวจ full histories และ final numeric inventoryด้วยมือ

Final classification revision ผ่าน ordinary-route private control `open-attribution-control-20261026-220651-344` แล้วรัน native หนึ่ง case ต่อไปนี้ โดยไม่ใช้receiptคนละSHA ไม่บังคับGC/driverwarmup/เปลี่ยนworkloadเพื่อให้มีcapture

## หลักฐานใหม่: exact observed creator API returns ของสาม retained handles

**`open-attribution-native-20261026-220653-340`**, PID30276 (`0x7644`), controller SHA `ED4DCE9F7182576863535A0A5AE4FB3D3D02A27D61A0E26647619394EAC2EF5F`, executable SHAเดิม:

| Returned handle ใน run นี้เท่านั้น | Actual API/caller ที่จับตรง | Final PSS numeric metadata |
|---|---|---|
| `0x71c` | `KERNEL32!CreateThreadStub ← amdihk64+0x4edd ← NTDLL timer callback`, creatorTID28212 (`0x6e34`), actualHANDLEจากRAX | Thread target10368, threadentryอยู่ในcurrentAMDmodulebounds/`amdihk64.dll` |
| `0xf58` | `CreateEventW ← RPCRT4!ThreadSelf+0x16d ← RpcpSetThreadpoolCallbackInstance ← PerformGarbageCollection`, creatorTID24780 (`0x60cc`), actualHANDLEจากRAX | Event |
| `0xe00` | `DuplicateHandle ← RPCRT4!ThreadSelf+0x2a8 ← callback/GC pathเดียวกัน`, source current-thread pseudohandle, verifiedBOOL1แล้วอ่านactualoutputHANDLE | Thread target24780 เท่ากับcreatorTID จึงเป็น self-thread handle duplicate **ไม่ใช่ OS thread ใหม่** |

ทุกAPIยืนยันreturn TID/RIP และRSP=entry+8 ก่อนอ่านผล ไม่ใช้entry out-pointer/address เป็นhandle ไม่ใช้threadentrymoduleอย่างเดียวอนุมานcaller

`open-attribution-history-audit.ps1` ทำofflinejoinและเขียน `creator-history-audit.json`:

- fullhistorylatest recordเป็นOPENจากcapturedcreatorTIDที่ไม่ซ้ำในhistoryของslotนั้น/currentPID และfinalPSSมีhandle/type/targetตรง จึงไม่มีlaterCLOSE/reopenหลังgenerationที่จับได้
- จำนวนrecords5/17/17ตามลำดับ; older4/16/16recordsเป็นgenerationเก่าก่อนcapture จงใจไม่นับเป็นobjectเดียวกัน
- database31859 < configured65536, blockcountsครบและไม่มีtruncationที่ตรวจพบ
- ข้อสรุปจำกัด **observed creator API/caller ของ retained HANDLE generations ใน instrumented PID นี้** ไม่เท่ากับผู้สร้าง underlying kernel object ทุกกรณี/all-resource ownership หรือหลักฐาน app-owned leak

Protocolครบ, source/controllerไม่เปลี่ยน, no timeout/forcedcleanup/observedremainingdescendants, root+targetexitconfirmed แต่ **application exit1/ResourceGrowth ยังถูกเก็บแยกจากcollector success**: handles235→238, GDI3→3, USER3→4, threads6→10; `normal_gate_pass=false`, `readiness_evidence=false`

### สอง outstanding opens ที่ยังไม่ทราบ live creator ใน case นี้

| Handle | Final type | Htrace creator TID | ขอบเขตความรู้ |
|---|---|---:|---|
| `0x750` | Event | 2736 | threadentry `atio6axx.dll`; **ไม่มีlivecreatorAPIstack จึงไม่ระบุallocationcaller/owner** |
| `0x75c` | IoCompletion | 2736 | เช่นเดียวกัน |

Instrumentedtypecounts ALPC4→2/Event39→41/Thread3→5/IOCP5→6 รวม+3 ไม่ใช่normaltypecounts ALPC4→2/Event42→43/Thread3→5รวม+1 การเห็นextraคู่เฉพาะdiagnosticนี้ไม่พิสูจน์ว่าdebuggerสร้างมัน และไม่โอนidentities/creatorPCsไปnormalrun ห้ามใช้threecapturedreturnsหรือolderclose-run handlesเป็นคำตอบว่าnormal+1ถูกattributedครบแล้ว

Independent verifier ตรวจ raw entry/return stacks, full histories และfinalnumericinventoryแล้ว ให้ **verifiedสำหรับrestrictedสามcreator-returnclaims** รวมrawcounter235→238/6→10 และapplicationfailureตามที่รายงาน ส่วนclose-runสองbaseline ALPC claimsผ่านindependentraw-evidence verificationแยกกัน ไม่ยกระดับเป็นnormal-run ownership/leak/acceptance proof

## งานคงเหลือและข้อจำกัดจริง

ยังไม่มีหลักฐาน allocation owner ของ **normal +1ครบชุด** ที่พอให้ลงapp-owned fixเพิ่ม แม้ได้exactobservedcreatorsสามhandles/closecallersสองportsในinstrumentedcasesแล้ว ส่วนextraEvent/IOCPcreator, normal-to-instrumented correlation, exec181/exec244, actual GPU-busy/performance, physical IME/mixed-DPI และ human acceptance ยังเปิด

จบรอบbounded attributionที่หลักฐานนี้ ไม่มีการเก็บunfilteredAPItraceซ้ำ/คาดเดาcallerจากmodule/closeunknownDLLhandles/เปลี่ยนdriverหรือglobalinstrumentation/ทำspeculative app patch/รับdriver exception/ผ่อนgateเพื่อให้ผ่าน ไม่อ้างว่าแอปไม่มีleakทั้งหมดหรือพร้อมส่งมอบ `WIN-RUNTIME-004` ยังเป็นblocker ไม่มีruntime/build/testค้างหลังfinalchecks และไม่commit/push

เอกสาร Microsoft ที่ตรวจจริง: [!handle flags](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-handle), [gu return/stack semantics](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/gu--go-up-), [!htrace full history vs outstanding diff](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-htrace), [MASM numeric/boolean operators](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/masm-numbers-and-operators)
