# Windows worker functional reproduction — 27 ตุลาคม 2026

## ขอบเขตและข้อสรุป

ผู้ใช้อนุมัติทำต่อจาก CPU-only milestone เพื่อทวน functional failures ของ181/244ด้วย GPU worker จริงแบบจำกัด ไม่ใช่ GPU-busy/driver-hang/performance qualification ไม่เปลี่ยน driver/global settings/default renderer/budgets/warmup/gates ไม่ commit/push

**รอบนี้ทั้ง private functional suite และ remote-host lifecycle ผ่าน** จึงจัดว่า **historical181/244 ยังทำซ้ำไม่ได้ใน cases นี้** ไม่ใช่ root-cause fix ไม่ใช้ passหนึ่งรอบลบ failures เดิมหรือประกาศreleaseพร้อมใช้ และไม่เปิดGPU qualificationทั้งหมดเอง

## Test-only offscreen และ production separation

- `src/win32_render_offscreen_test_worker.zig` เป็น private wrapper ของworkerจริง เพิ่มเพียง compile-time `gpu_worker_offscreen_context=true` ไม่เปิดfault fixture
- Late-reply test rootเดิมมีoffscreen flagด้วย; CPU delay200msยังเฉพาะthird-frame publicationหลังGPU draw/readback/finish ไม่ใช่GPU-busy/hang injection
- `wgl.zig` เมื่อflagมีเฉพาะtest root วางhidden1x1contextที่ virtual-desktop minimum−256 ทั้งx/y ตรวจactualGetWindowRectอยู่นอกทุกmonitorและIsWindowVisible=0ก่อนเริ่มGPUงาน พร้อมPID marker ไม่มีShowWindow/activation
- Production rootไม่มีflag จึงคงhidden(0,0)เดิม; namedcheckstepติดตั้งprivateoffscreenclone ส่วนappinstallยังใช้originalproductionworker ไม่ส่งfault/offscreen testrootเข้าdefaultapp dependencies
- **ใช้prefixแยกเสมอ** อย่าเรียกcheckstepร่วมกับappinstallในcandidateprefixเดียวกัน: privatecloneมีfilenameเดียวกับproductionworkerเพื่อรักษาprotocol/path pinning
- `render_worker_client_check.c` routestderrของworkerเข้าสู่supervisorlogเฉพาะprivatecheck translation unitผ่านduplicated allowlisted HANDLE Productiondiagnosticsยังopt-inเดิม ช่วยเก็บoffscreen/teardown evidence แต่มีobserver effect จึงไม่ใช่unchanged-normal-run proof
- `tools/windows/worker-functional-repro.ps1` buildprivateMSVC/baselineReleaseSafe-j2 แล้วรันexisting suiteหนึ่งครั้งด้วยCreateNoWindow/redirected streamsและruntime deadline180s ถือroot HANDLEจริง childjobsเดิมkill-on-parent-close ตรวจเฉพาะ3exe pathsใต้uniqueprivateprefix ไม่มีkill-by-name/PIDจากผู้ใช้/source mutationระหว่างrun
- Successต้องexit0/no timeout/no outer forced cleanup/no observed private-prefix processเหลือ/no sourcechanges/offscreen evidence/finallate-renderedPASS Buildก่อนruntimeไม่ได้อยู่ใน180s execution deadline

## 244 — existing functional suite หนึ่งรอบ

Artifactsใต้ `%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\phase3b-runtime\worker-functional-20261027-113348-008\`

- Build32/32, explicitMSVC/baseline/ReleaseSafe; actualbuild+runtranscriptเก็บ `build-and-run-transcript.log`
- Suiteexit0, sourceunchanged, no timeout/outer forced cleanup, retainedrootexitconfirmed, exactprivate-prefix process observations empty
- **28contexts/28uniquePID markers**, actualhiddenrect `left=-2176 top=-256 right=-2175 bottom=-255 visible=0` ทุกmarkerอยู่นอกvirtualdesktopที่ตรวจในchildจริง Parentยังผ่านnoGL/AMD modulechecksตามfixture
- Prelude/negativecasesเดิมผ่าน รวมbadheaders, killed77, idle timeout/actual lateclosed rejection, poison/retainedframe, imageIPC, simultaneousclosed+process-exit, cancelpriority และOOM/repeatedabort มีexpectednegativeworkererrorsในstderr ไม่ใช่การลบerrorจากlog
- Late-renderedcase: originalreferencewarmframes2เหมือนเดิม, thirdGPUreadbackเสร็จที่+0ms (<50ms), identical128RGBA bytes published+203msแล้วถูกปฏิเสธ ไม่promotehealthyclose
- Exactcleanupreceipt: **ACK0 / exited1 / child1 / jobempty1 / forced1 / handles69→69** `forced1`เป็นexpectedfailure-cleanupflagภายในnegativecase ไม่ใช่naturalhealthyclose และไม่ใช่outertimeoutkill

นี่คือcurrentpassของ244-style fixture ไม่พิสูจน์ว่า original combined-assertion failureถูกแก้หรือเป็นfaultเดียวกับCPUreapbudgetdefect รอบก่อน

## 181 — remote host lifecycle หนึ่งรอบ

Build/provenance: `worker-host-repro-20261027-113900-766\` ภายใต้artifactrootข้างต้น Runtime: `lifecycle-native-20261027-114149-901`

- Build **125/125** explicitMSVC/baseline/ReleaseSafe, opt-inremote renderer+imagesเฉพาะprivatebinary ไม่มีdefaultpromotion
- Sourcehashed12inputsไม่เปลี่ยนระหว่างbuild/run; provenanceเก็บbinaryhashes/arguments/provider/source ของprivateapp
- ใช้approved app-localConPTYจากexisting`zig-out/conpty-ab/bin` ตรวจactualhashเทียบexistingproviderreceiptก่อนcopy ไม่มีprovision/downloadหรือcopyuserconfig
- เก็บoriginalinstalledproductionworkerในartifactก่อนแทนเฉพาะprivateprefixด้วยqualified**nonfault**offscreenworkerจากsuiteข้างต้น ผ่านsame-binary hash check มีPDBคู่กัน ไม่แก้oldpreview/portable/candidate
- ใช้existingruntime-smoke `-Mode lifecycle -TimeoutSeconds 120 -ConptyProvider app-local` คง1warmup+20cycles/NoProfile/syntheticUTF-8Thai output/PSS-enabled/resource/critical-log/actualrender-paintchecksเดิม Host windowoffscreenx1984/no-activate และchildcontextsassertoffscreenจริง
- **Exit0 / passed=true / no timeout / cleaned_descendants=[] / sourceunchanged** `readiness_evidence=false`เพราะapp-local diagnostic ไม่ใช้เป็นnormalshippingacceptance
- Rawlogsครบ **21cycles,21healthyworkercloses** (`ACK1 exit0 jobempty1 forced0`), **21offscreencontexts**, ไม่มีnaturalclose/reap/cleanupfailuremarkers
- Finalresources: **handles129→129, GDI2→2, USER1→1, threads4→1**; **frames165/paints165/remaining_surfaces0**

129→129ของremote diagnosticนี้ไม่ใช่การแก้ normaldefault242→243/6→7และไม่โอนnumericidentity/ownershipข้ามrun `WIN-RUNTIME-004`ยังเปิด

## Review และงานที่ยังเปิด

Independent read-only reviewของtestseparation/offscreen/supervisorไม่พบconcreteintroducedsafety/false-successissue; reviewไม่ใช่runtimeacceptance Markerchecksในsupervisorเป็นaggregateไม่ใช่fullper-childPIDidentityjoin และbuildไม่มี180s runtime deadline

Final independent verifierตรวจrawtranscripts/receiptsยืนยัน32/32และ125/125,28offscreenPIDs/latecleanup69→69,21healthyhostcloses/21contextsและfinalresource/framecountsตามรายงาน ไม่พบoverclaimในscopeที่อ่าน ไม่ได้เรียกtestsหรือรับรองproductionเอง

Parent final observationเก็บ `worker-host-repro-20261027-113900-766/final-owned-observation.json`: exactprivateexe paths6รายการไม่มีliveprocessที่สังเกตพบ, watchedsourcehashesยังตรงทั้งสองruns, hostprefixไม่มีclient-check/late-reply/reapcheckfaultartifacts ไม่มีruntime/buildค้าง ไม่ใช้missing/nullhostremainingfieldเป็นหลักฐานempty

ยังเปิด original181/244cause (ไม่มีper-stageข้อมูลย้อนหลังพอและรอบนี้not-reproduced), CPUOSfixturecold+5, normalWIN004, GPU-busy/performancequalification และhumanIME/mixed-DPI/interactiveacceptance ไม่มีspeculativeproductpatchเพิ่มเพราะสองreproductionpassesนี้

คำสั่งfunctional suiteที่ใช้:

```powershell
& .\tools\windows\worker-functional-repro.ps1 -TimeoutSeconds 180
```

อย่ารันวนเพื่อกลบfailureหรือเรียกผลนี้ว่าperformance/driver-hangqualification; รันต่อเมื่อมีhypothesis/เงื่อนไขที่ต้องทดสอบใหม่หรือscopeอนุมัติชัดเจน
