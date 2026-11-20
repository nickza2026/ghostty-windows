# Owned-resource audit — 4 พฤศจิกายน 2026

**ยังไม่ปิด `WIN-RUNTIME-004` และยังไม่ยืนยัน owner ของ normal +1 handle/+1 thread ครบชุด** งานนี้ไม่เปลี่ยน driver/default/warmup/deadline/เกณฑ์ ไม่ปิด unknown handles/threads ไม่แตะ `A:` บัญชีหรือ agent และไม่ commit/push

## หลักฐานใหม่ก่อนรันแอป

อ่าน source ownership ของ core worker, reader, libxev Windows และ stdlib ที่ build ใช้จริง ไม่ถือว่าชื่อ `Dynamic` แปลว่าต้องมี union เสมอ: libxev ยุบเป็น static backend เมื่อมี backend เดียว

- renderer/IO มี IOCP loop อย่างละหนึ่ง; libxev ปิดใน loop deinit
- Windows `xev.Async`/Timer ไม่ได้สร้าง Event ของ OS จึงไม่ควรนับทุก Async เป็น Event
- reader/renderer/IO worker เก็บ native thread handle; stdlib join รอ thread แล้วเรียก NtClose แต่ wrapper ไม่ส่ง native-close result กลับมา
- พบแยกต่างหากว่า pinned `ProcessIocp.init` ไม่มี duplicate-process-handle cleanup หาก CreateJobObject/AssignProcessToJobObject ล้มเหลว เป็น **error-path Process-handle finding** ไม่ใช่หลักฐานอธิบาย normal Event/Thread growth และไม่ได้แก้ dependency

`tools/windows/handle-tracing-control.c`: private self-only x64/PE subsystem2/no-console control สร้าง Event, Thread และ duplicate ผ่าน non-inline creator functions ทวน ABI160bytes/offset16 และจับคู่ returned HANDLE/PID/creator TID ได้จริงทั้งสาม API tracing enable/query/disableสำเร็จ แต่ **raw caller PC ทั้ง16ช่องเป็น0ทั้งสามประเภท** ผล `qualified=false`, native exit20, cleanupสำเร็จ ไม่มีtimeout/target app launch ไม่ลองเพิ่มbuffer/deadline/globalflagsหรือทำ broad debugger sweepซ้ำ

หลักฐานราก `zig-out/ownership-20261104-095534-477/`: `control-run.json`, `handle-tracing.stdout.jsonl`, `read-dependency-implementations.json`

## Surface-only ledger

เพิ่ม `src/os/windows_resource_ledger.zig` เปิดเฉพาะ `LOCALTERM_LIFECYCLE_LEDGER=1` ร่วมกับ controlled lifecycle fixture; terminalปกติไม่เปิด เก็บ fixed-capacity512 entries/no kernel resource/no logging thread/no per-acquisition file I/O

recordจริง: sequence/generation/role/HANDLE/creator TID/target TID/thread creation FILETIME/end sequence แยก `join_returned`/`deinit_returned` ออกจาก **native-close-success ซึ่งยังไม่ได้สังเกต** ตรวจ overflow/overlap/unmatched release ไม่ทับหลักฐาน และไม่รวมคนละgenerationเมื่อ Windows ใช้ slotซ้ำ

ขอบเขตเพียง5 roles: renderer/IO/reader worker + renderer/IO IOCP ไม่ครอบคลุม global std IO, process/job watcher หรือ indirect DLL allocations **unmatched ไม่ได้แปลว่า foreign หรือไม่มี app leak**

data/metadata tests เดิม6/6ทั้งDebug/ReleaseSafeผ่าน; native build attemptแรกไม่ผ่านเพราะเข้าใจ DynamicLoop shape ผิด ไม่มีnative launchจากfailedbuild เก็บreceiptเดิมไว้และเพิ่ม static/dynamic extraction regression ก่อนทวน ไม่เรียกcompiler failureว่าsemantic RED หรือ resource failure

## Native capture

revision ที่รองรับ instantiated loop type ผ่าน **7/7 ทั้ง Debug และ ReleaseSafe** แล้ว รอบ10:25 fresh legacy build จบ **LLVM out of memory / Buffer allocation failed / compiler exit9** ขณะนั้นยังไม่มี native acquisition ไม่ใช้unit passแทนnativepass

เก็บfailedcompileแรกกับsource snapshotเป็น `first-compile-failure-*`; รอบOOMเป็น `llvm-oom-build.json`/`llvm-oom-source-before.json` sourceไม่เปลี่ยนระหว่างbuild ไม่launch stalecandidate

หลังOOM WMIรายงานว่าง physical8.49GiB/freevirtual2.81GiB จากphysical31.92/virtual47.92GiB; C:ว่าง21.28GiB,D:48.20GiB เป็น **ค่าหลังล้ม ไม่ใช่compiler peakหรือหลักฐานชี้เหตุเดียว** nativebuildเดิมที่สำเร็จเคยรายงานMaxRSS1G แต่ไม่ใช่commit/virtualpeak ไม่เปลี่ยนpagefile/optimization/driverหรือปิดโปรแกรมผู้ใช้เพื่อให้ผ่าน

ตั้งpassivewaitจำกัด20นาที ไม่เปลี่ยนmemorysettings/ปิดโปรแกรม เวลา10:32พบphysicalfree11.17GiB/virtualfree8.31GiBคงที่สองsamples จึงทวน-j1/ReleaseSafeเดิมหนึ่งครั้งหลังตรวจsourceguard ไม่ถือว่า8GiBเป็นข้อกำหนดRAMขั้นต่ำ

### ผล native ที่อ่านแล้ว — 10:36–10:46

**Build123/123ผ่าน**, SHA-256 `931FB90C4F3664D90D8CDF143D6CE756AD0FB469655804AFA900AA033B47C5CC`; positive ledger-off exit0/marker+Thai/frameจริงผ่าน และledger-on21cyclesครบโดยไม่มีtimeout/owned-tree forcedcleanup source701inputsไม่เปลี่ยน

แต่ **strictยังexit1/ResourceGrowth**: handles233→234,threads6→7,GDI3→3,USER3→3 ไม่ยกผลcollectorexit0หรือunitpassมาล้างgate

| same-run inventory type | Baseline | Final | Delta |
| --- | ---: | ---: | ---: |
| Event | 39 | 40 | +1 |
| Thread handle | 3 | 5 | +2 |
| ALPC Port | 4 | 2 | −2 |
| IoCompletion | 5 | 5 | 0 |

ledger105entries:63workers (renderer/IO/readerอย่างละ21) +42IOCP (renderer/IOอย่างละ21),ครบ21generations,active0/fault0 ทุกrecordมีjoin/deinitreturned ไม่ใช่observedNtCloseresult การเทียบfinal liveTID+creationtimeไม่พบtrackedworkerที่ยังlive และfinalThreadtarget/IOCPnumeric slotsไม่พบcandidateตรงกับtrackedentries **ไม่ใช้unmatchedสรุปว่าappทุกpathปลอดleak**

liveThreadมี4added/3retired ไม่ใช่มีthreadใหม่เพียงตัวเดียวเมื่อเห็นnet+1:

| Entry module group | Baseline | Final |
| --- | ---: | ---: |
| localterm executable | 1 | 1 |
| atio6axx.dll | 2 | 2 |
| ntdll.dll | 3 | 3 |
| amdihk64.dll | 0 | 1 |

ตัวAMDhookเพิ่มในrunนี้คือTID8004/creation134382369146459853 และมีfinalThreadhandle0x3d0 ส่วนอีกfinalThreadhandleที่เพิ่ม0x470target26848(entryntdll) Eventที่เพิ่งสังเกตเป็นfinalslot0x4dc **ยืนยันได้เฉพาะthread entry/groupและsame-run identities ไม่ใช่creatorAPI/driverleak/cacheharmlessness** ไม่โอนRPC/AMDcreatorstackจากCDBรอบเก่ามาแทนEventนี้

ดู `build.json`, `positive.json`, `owned-ledger-run.json`, `owned-ledger-analysis.json`, `headroom-wait.json`; currentownedoutputsประมาณ150MiB ไม่มีcloneใหม่หรือแพ็กเดิมถูกแทน

## จุดหยุดด้าน scope และงานต่อ

ยังระบุ **callerของEventที่เหลือไม่ได้** ไม่ทำspeculative appfix/closeunknown/DLLhook/NTDLLtrampoline/driverexception/defaultpromotion และไม่รันlifecycleวนซ้ำโดยไม่มีข้อมูลใหม่

ตรวจETWproviderเฉพาะmetadata: wevtutilไม่พบpublisher และlogmanไม่พบชื่อMicrosoft-Windows-Kernel-Object; ไม่ได้เปิดsession/elevate/installหรือถือว่าชื่อไม่พบพิสูจน์ว่าETWทุกแบบใช้ไม่ได้

เอกสาร [EVENT_FILTER_DESCRIPTOR](https://learn.microsoft.com/en-us/windows/win32/api/evntprov/ns-evntprov-event_filter_descriptor) ระบุPIDscopefilterสำหรับuser-modeproviders ไม่ใช่หลักประกันkernelproviderถูกจำกัดPID จึงห้ามโฆษณาว่าkerneltraceเป็นown-PID-onlyจากการตั้งfilterเฉยๆ [System Object Provider](https://learn.microsoft.com/en-us/windows/win32/etw/system-providers) ต้องแยกschema/sessionและสิทธิ์จากproviderชื่อข้างต้น

หากไปต่อด้วยETW ต้องขอhumanapprovalก่อนสร้างmachine-levelsession/ยกสิทธิ์หรืออาจเก็บmetadataprocessอื่น เก็บlocalไม่upload ไม่หยุดsessionอื่น ไม่เปลี่ยนpersistent/globalsettings และต้องqualifyกับownedcontrolsก่อนterminalrun พร้อมvalidatehandle/PID/generation/userPC/loss/caps ไม่fallbackunfilteredหรือเพิ่มlimitเอง ขณะนี้ไม่มีsession/test/buildรันค้าง และnormalgate/markerfailureยังเปิด

## ETW qualification — 11 พฤศจิกายน 2026

ผู้ใช้อนุมัติเมื่อ8พ.ย.และให้ต่อ11พ.ย.: controlสูงสุด30s/conditionalterminalสูงสุด120s รวมอาจต้องadminและmachine-levelmetadata ไม่มีdriver/default/globalpersistentsettingchange

ยืนยันSDK26100/OS26200และMicrosoft System Providers: enableGUID `febd7460-3d1d-47eb-af49-c9eeb1e146f2` HANDLEkeyword2,systemloggermode; emittedclassicObjectGUID `89497f50-effe-4440-8cf2-ce6b1cdcaca7`,op32create/33close/34duplicate ไม่ใช้enableGUIDแทนemittedclass Stackใช้`TraceSetInformation(TraceStackTracingInfo)`/CLASSIC_EVENT_ID24bytes ไม่ถือว่าAPIstatus0พิสูจน์stack

สร้าง`tools/windows/etw-handle-control.c`/decoder/supervisor/qualification scriptsและรันheadlesscontrolจริงผ่านUACหนึ่งครั้ง: **2,328ms**,Eventcreate/selfduplicate/cross-PIDduplicate/close/slotreuseสำเร็จ **zeroevent/bufferloss**,stop0และGUID-verifiedowncleanup0 ไม่attachterminalหรือใช้debugger

NativecontrolETL18MiBอยู่เฉพาะuser+SYSTEMrestrictedlocaldirectoryใต้`%LOCALAPPDATA%/Letta/private-traces/` ไม่copyrawETLเข้าrepo/memory/upload traceอาจมีชื่อ/pathmetadataในopaquepayload ห้ามกล่าวว่าPID-onlyหรือไม่มีnamesจากการไม่decode tail

decoderแรกไม่รองรับobservedversions/tail แก้**offlineETLเดิม/SHAไม่เปลี่ยน ไม่captureซ้ำ**: handlecreate/close/StackWalkv2,duplicatev3 บนเครื่องนี้ อ่านเฉพาะfixedprefixตามMicrosoft PerfViewและdiscardopaque tail ไม่เดาversionถัดไป 17data-onlycasesผ่าน ต้องแยกparse-only successจากcallerqualification

ผลcallerqualificationจริง **10/10operations** มีreturnedhandle/PID/type/object/lifetime/knownfunctionPCตรงกัน รวมparentA/Bใช้slotเดียวแต่คนละobjectและcross-PIDdupที่childยืนยันใช้งาน/closeได้ MicrosoftdecoderมีTODOเรื่องPIDของduplicate จึงทวนกับknowncross-PIDAPIจริง ไม่ใช้TODOเป็นข้อยืนยัน

พบและแก้first-same-slot false-negative: childใช้numeric handleเดิมกับbootstrapnon-Event(type42)ก่อนEvent(type21) ต้องจับคู่ด้วยindependentcreatorPC/type/object/generation ไม่เลือกแถวแรกตามเลขhandle

verifierทวนstablequalification/sourceกับpositivecopyผ่าน และnegative5แบบrejectครบ: ไม่มีstack,สลับcross-PIDtarget,parsefailedแต่มีoldvalidrows,ลบclose_a,และใส่creatorPCให้bootstrapnon-Eventแต่ลบEventจริง ไม่ถือผลนี้เป็นterminal/resourcegatepass

รอบterminalใช้sameprovider/keywords/stackmechanism/caps4MiBbuffers+32MiBfile ใช้collectoradminแยกจากnonadminnativeactorและexistingoffscreen21-cyclefixture ไม่เปลี่ยน701nativeinputs/candidatehash รอผลfreshnative/collectionreceiptก่อนอ้างEventcaller หากcap/loss/earlystopต้องคงunqualified ไม่เพิ่มlimitหรือtraceซ้ำเอง

### ผล terminal capture — 11 พ.ย. 12:09

ใช้สิทธิ์conditionalterminalหนึ่งรอบแล้ว โดยnativeactorยังnonadmin/offscreen/defaultlegacy,120sเดิม ไม่มีdebugger/ใหม่driver/cadencechange candidateSHAเดิม sourceguardผ่าน เก็บmodulemap31modulesโดยไม่มีqueryfailure

**ETW captureไม่qualified:** fileถึง32MiB (33,554,432bytes) ใน3,546ms,eventsLost71,849/logBuffersLost1; collectorหยุดทันทีไม่รอจน110s/ไม่ขยายcap APIdisable/stopรายงาน4201(instanceไม่มีแล้ว) ต่อมาsupervisorตรวจownedGUIDcleanupexit0/controllerexitconfirmed และยืนยันrecordednative/controllerPIDไม่live ไม่กล่าวว่าnativeStopAPIสำเร็จ0หรือมีzero-loss

nativefixture21cyclesจบเองexit1/ResourceGrowth,ไม่timeout/forcecleanup: handles239→240,GDI3→3,USER3→3,threads6→7; ledger105/active0/fault0 ยังไม่ใช่native-close-success ไม่มีการแก้appownedbug/driverexception/defaultpromotion

**ห้ามใช้partialETLหรือcontrolcallerมาแทนEventcallerท้ายnativeรอบนี้** ไม่decodepartialเพื่ออ้างsame-runownerและไม่ทำterminalcaptureซ้ำ auto Currentprivateoutputsประมาณcontrol49.03MiB+terminal45.8MiB ไม่มีworktree/cloneใหม่ไม่เปลี่ยนแพ็กใช้อยู่และไม่commit/push

## งานต่อที่ต้องอนุมัติก่อน capture เพิ่ม

แนวทางแนะนำเป็นreal-time consumer: ยังรับmachine-levelETWตามข้อจำกัดเดิม แต่discardnon-targetmetadataก่อนเขียนดิสก์ ไม่เก็บrawglobalETLให้ชน32MiB ห้ามโฆษณาว่าkernel-sidePID-only การกรองปลายทางลดretentionไม่ใช่ลดcollectionscope

ต้องมีtarget-PID bindingที่ตรวจcreationidentityได้ก่อนปล่อยworkload หรือboundedpre-bindbufferที่พิสูจน์ไม่overflow/ไม่มีmissingepoch ต้องทวนcontrolแบบใหม่กับknownPC/crossPID/reusedslot/closehistory/loss/capsก่อนterminalอีกหนึ่งรอบ ไม่เปลี่ยนprovider/เพิ่มlimit/ย้ายข้อมูลหรือเปิดsessionใหม่เองจากผลรอบนี้ ขณะจบงาน12:09ไม่มีownedcapture/session/testรันค้าง ยังไม่ระบุEventcallerและไม่closeWIN-RUNTIME-004/markerfailure
