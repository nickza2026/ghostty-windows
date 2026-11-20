# GPU-only owned-child lifecycle PoC

## ขอบเขตที่อนุมัติ

19 ตุลาคม 2026 เวลา18:07 ผู้ใช้ตอบ “ได้” ให้ทดลองGPU-onlyเป็นprocessลูก **ยังไม่ใช่อนุมัติย้ายrendererหลัก** ไม่เปลี่ยนdriver/settings/threshold/warmupของnativegate ไม่ปิดforeignhandles/threads Acceptedcandidate62และCore/VTbaseline62คงเดิม

เป้าหมายคือทดสอบprocess-boundarycleanupบนเครื่องนี้โดยไม่อ้างว่าprocess-globaldriverstateเป็นapp-ownedhandleที่ควรปิดเอง หรือย้ายleakไปอยู่นอกcounterแล้วเรียกว่าผ่าน

## Producer/consumer และ ownership

- Parent `tools/windows/gpu-child-parent.c` ไม่มีOpenGLimports ตรวจknownOpenGL/AMDmodulesไม่อยู่ในparent ใช้GetProcessHandleCount/GetGuiResources/own-threadcount
- Child `src/win32_gl_probe.zig` โหมดLOCALTERM_GL_CHILD_CONTROL=1 สร้างจริงGL4.3contextและRGBAFBO2×2 ตรวจ16bytesครบ3drawsแบบUI→worker→UI มีatomicdrawcoverage ไม่ใช่แค่processexit0
- Hostwindowของprobeซ่อนไว้และSetWindowPosเลยขอบvirtualdesktopรวมทุกmonitorด้วยNOACTIVATE ไม่มีpreview/foreground activation
- Parentสร้างchildแบบSUSPENDEDแล้วassignprivateJobก่อนResume จำกัดinheritedhandlesด้วยSTARTUPINFOEX/HANDLE_LISTเฉพาะstdioที่เป็นfixture ตั้งJOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE ไม่อนุญาตbreakaway
- ปิดสำเนาstdioฝั่งparentเมื่อส่งให้childแล้ว receiptตรวจPIDจริง/3draws/pixelmarker/hold-time/exit0 และjobActiveProcesses=0 ก่อนปิดprocess/thread/job handles ไม่ใช้childexit0เพียงอย่างเดียว
- Parentเก็บbaselineหลังchildแรกหนึ่งครั้ง จากนั้น20cyclesต้องhandles/GDI/USER/threadsไม่เกินbaselineทุกครั้ง ไม่มีextraGPUwarmup มีlongchildถือGLcontextที่ยังไม่destroy15วินาทีเพิ่ม **หลัง**20cyclesและเทียบbaselineเดิม ไม่resetbaseline นี่คือcontextlifetimeไม่ใช่15วินาทีcontinuousredraw
- Childรายงานhandles/GDI/USERก่อนและหลังGLเพื่อแสดงstateที่ยังอยู่ในchildก่อนexit ไม่ใช้ค่าพวกนี้เป็นnativegatepass การออกจากprocessและjobไม่มีdescendantsคือboundaryที่ทดสอบ

นี่คือ**GPU FBO/readback component proof** ไม่ใช่nativeWM_PAINT/terminal/ConPTY/IPCpixeltransport/Thai/clipboard/performanceacceptance และไม่รับรองdriverglobalserviceนอกownedprocess

## Fail-closed controls

Parentนับelapsedจากก่อนCreateProcess/assignjobแล้วใช้เวลาที่เหลือใน30วินาที ถ้าOSCreateProcessค้างในAPIเองต้องพึ่งouterrunner300วินาที ไม่อ้างว่าหยุดAPIนั้นได้ทันที Runnerหลังtaskkillต้องรอexitไม่เกิน5วินาที/บันทึกkillresultและterminationconfirmed ไม่waitต่อแบบunbounded เมื่อผิดพลาดterminateได้เฉพาะnewownedchild/privatejob ต้องยืนยันOWNED_CLEANUP_OK **จากparentoutputเท่านั้น** กรณีnegativeก่อนrunnerรับผลว่าnegativeทำงานถูก ไม่มีการkillแอปผู้ใช้

| กรณี | ผลที่ต้องได้ |
| --- | --- |
| positive | parentexit0,1warmup+20cycles+1longcontrol,22childrenออกและjobempty,parentcountsไม่เพิ่ม |
| missing-receipt | childrender/exit0แต่ไม่มีreceipt,parentต้องexit1 |
| bad-pixels | ฉีดผิด1byteในreadbackfixture ต้องPixelReadbackMismatchและparentexit1 |
| hang | childค้าง60วินาที,parentdeadline30วินาทีต้องfail/cleanupownjob |
| launch-failure | pathfixtureไม่มีจริง,parentต้องfailโดยไม่มีchildcreated |
| counter-error | ฉีดcounterAPIerrorในparent ต้องfailไม่รับzeroเป็นmeasurementpass ไม่มีchildcreated |

Negativeexpectedfailureไม่ใช่nativegatepass ทุกreceiptตั้งreadiness_evidence=false Native62strictresourcefailureยังเปิดอยู่ Childdiagnosticmarkerตรวจเฉพาะchildlogs,parentpass/cleanupmarkerตรวจเฉพาะparentlogs ไม่รวมทุกproducerแล้วค้นtoken GetGuiResourcesแยกzeroที่LastErrorSUCCESSกับzero/error ไม่รับfaultเป็นmeasurement

Receiptเป็น**trustedinstrumentedchildself-report** ที่ตรวจsourceRGBAจริง/PID/drawcount/hashคงเดิม ไม่ใช่GPUhardwareattestationหรือproofจากผู้ผลิตอิสระ Runnerบันทึกhashของbinaryที่callerส่ง ไม่ใช่signedallowlist;ไม่ใช้รันuntrustedproducersแล้วอ้างป้องกันforgedsamePIDreceipt Checksสามmoduleชื่อเจาะเครื่องAMDนี้กับsourceparentไม่มีGLcalls ไม่รับรองทุกvendor/transientDLLloads

## Build/run

ใช้VS2022x64DeveloperShellและZig0.16ที่โครงการใช้ ไม่ติดตั้งdependenciesใหม่:

```powershell
zig build windows-gl-probe -j1 -Dapp-runtime=win32 -Demit-docs=false -Doptimize=ReleaseSafe -p zig-out/gpu-child-poc --summary all
cl.exe /nologo /TC /O2 /MT /W4 /WX /D_WIN32_WINNT=0x0602 /DUNICODE /D_UNICODE /Fozig-out/gpu-child-poc/bin/gpu-child-parent.obj /Fezig-out/gpu-child-poc/bin/gpu-child-parent.exe tools/windows/gpu-child-parent.c /link user32.lib
.\tools\windows\gpu-child-poc.ps1
```

Runnerเก็บhashparent/childและตรวจคงเดิมหลังทุกcase Artifactsอยู่`%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\phase3b-runtime\gpu-child-poc-*` มีparentstdout/stderrและchildlogsแยกcase ใช้CREATE_NEWไม่เขียนทับlogเก่า

## สถานะระหว่างพัฒนา

- Build64parentหยุด/WXจากC4701baselinepotentiallyuninitialized ยังไม่รันchild แก้initializedbaselineพร้อมbaseline_readyguard ไม่ปิดwarning
- Build65parentผ่าน/W4/WX และchild28/28steps แต่positiveหยุดcycle0เพราะCRTreceiptreaderเจอsharingviolationwinerr32 Writerhandleของparentยังเปิดอยู่ ChildlogมีจริงGPU_CHILD_OK/AMD RX7600/3draws/16bytes/exit0 และcleanupสำเร็จ **ไม่รับเป็นPoCpass**
- แก้ปิดparentstdioหลังrestrictedinheritance/assignjobก่อนResume โดยchildมีcopiesของตัวเองอยู่แล้ว แล้วกำลังทวนใหม่ด้วยchild65เดิม ยังไม่สรุปผลล่วงหน้า
- รอบ`gpu-child-poc-20261019-181635-626`positiveและ4negativecontrolsผ่าน Parentbaselinehandles71/GDI0/USER1/threads4;หลัง20cyclesและpost-teardownlongcontrolhandles71/GDI0/USER1/threads1,22childrenexit/jobempty นี่คือผลรุ่นแรก **ยังไม่ปิดreviewข้อจำกัด** longcontrolรุ่นนี้holdหลังcontextdestroy
- Reviewพบproducerfencing/cleanupwait/GUIcountererror/longcontextgap แก้แล้วกำลังbuild66และทวนใหม่พร้อมcounter-errornegativeเพิ่มเติม ย้ายhold15วินาทีเข้าcontextlifetimeจริง ไม่แก้baselineหรือthreshold ยังไม่ใช้ผล65อ้าง66ผ่าน

## ผล reviewed66 — 19 ตุลาคม 2026 เวลา18:23

Buildchild28/28steps,ReleaseSafe/-j1;parentCL/O2/MT/W4/WXผ่าน Runner`gpu-child-poc-20261019-182157-467`ผ่าน6cases:positiveและ5negative(missing-receipt,bad-pixels,hang,launch-failure,counter-error) ไม่มีoutertimeout ทุกnegativeได้expectedexit1และcleanupmarkerจากparent ไม่ใช่จากchild

- Baselineหลังchildแรก:handles71/GDI0/USER1/threads4
- หลัง20cycles:handles71/GDI0/USER1/threads1;หลังlongactivecontextcontrolเท่ากัน ยังไม่resetbaseline
- 22childrenexit0/jobActiveProcesses=0ก่อนparentปิดhandles ทั้งหมดมีPIDreceipt/3verifieddraws/16RGBAbytes และlongchildhold15000msขณะcontextยังalive
- Longchildก่อนexitรายงานhandles87→211/GDI0→1/USER1→3 ชี้ว่ามีstateภายในchildก่อนออก ไม่ได้อ้างว่าการdestroycontextคืนทุกอย่างแล้ว OSprocess-exit/privatejobboundaryคือสิ่งที่PoCทดสอบ
- Parent`dumpbin /imports`มีUSER32.dll/KERNEL32.dllเท่านั้น ไม่มีOpenGLimport;knownmodulechecksผ่าน ไม่รับรองทุกtransientvendorDLLโดยเหมารวม
- Hashparent `AE7B6746C2BFECE146A435B1F0E7DE46429E05A05EF0A8011F9DDAB35743CC9C`
- Hashchild `E0702D84CAF6EB797E996EFE55F1A3BEC171BAA9A29A10A86641D0C905B0909B`
- Accepted62hashยัง `2589A9B770D5930E1F00C654D4D89116C78B522A94A0E4EEB1D9AAE9829327CC` ไม่ถูกทับ

นี่คือ**componentPoCผ่านบนเครื่องนี้** ไม่ใช่nativeResourceGrowthผ่าน/rendererreplacement/WM_PAINT/terminalacceptance/IPCtransportหรือperformanceproof Rootwrapper300s-timeout/kill-failurepathแก้boundedโดยsourceinspection แต่ไม่ได้forceoutertimeoutใน6casesนี้;hangnegativeทดสอบchild30sdeadlineภายในparentเท่านั้น ไม่อ้างdynamiccoverageเกินจริง

## ข้อเสนอขั้นต่อไป (ยังไม่อนุมัติ/ไม่implement)

ก่อนintegrationหลัก แนะนำPoCแยกเพื่อส่งRGBAframeจากGPUchildผ่านsharedmemoryให้parentตรวจขนาด/stride/sequence/epochและวาดจริงแบบoffscreen พร้อมresize/close/crash/staleframecontrols ต้องวัดparentresourceและownedchildexitต่อ ไม่เปลี่ยนrendererหลัก/ConPTY/clipboardหรือdriverในขั้นนี้

การintegrationจริงยังต้องออกแบบownershipของGL/fontatlas/terminalstate,input/focus/IME/clipboard,IPCdeadline+crashrecovery,resourcegateที่รวมownedchildrenและrollback/opt-in ไม่ถือว่าคำอนุมัติGPU-onlylifetimePoCครอบคลุมสิ่งเหล่านี้ หยุดรอscopeapprovalใหม่ก่อนเขียนIPCหรือmainintegration ไม่มีjobรันหลังสรุปผลนี้
