# GPU frame IPC / offscreen presentation PoC

## ขอบเขตที่อนุมัติ — 19 ตุลาคม 2026 เวลา23:22

ผู้ใช้ตอบ “ได้” หลังข้อเสนอ **ส่งframeจากGPUchildผ่านsharedmemoryให้parentวาดจริงแบบoffscreen** นี่เป็นPoCแยกขั้นถัดจากGPU-childlifetime66 ไม่ใช่อนุมัติย้ายproductionrenderer/terminal/ConPTY/input/focus/IME/clipboardหรือทำdriver/settingschanges

ไฟล์implementationและbinaryต้องแยกจากacceptedcandidate62และgpu-child-poc66 ใช้prefix`zig-out/gpu-frame-ipc` ชื่อexeใหม่ ไม่เปลี่ยนresourcegate/warmup/thresholdของnativeappและไม่ใช้PoCpassยกเว้นResourceGrowthเดิม

## Planned contract (ยังไม่ใช่ผลทดสอบ)

### Producer: GPU child

- สร้างจริงdesktopGL4.3context/FBO อ่านRGBAที่ตรวจpatternได้ ไม่ใช้bufferสีสำเร็จรูปแล้วอ้างว่าGLrender
- ส่งผ่านmappingที่parentสร้างและให้handleเฉพาะexplicitrestrictedinheritance ไม่ใช้globalnamedchannelที่processอื่นเข้ามาส่งโดยปริยาย
- ข้อมูลwireต้องมีversion/magic,ขนาดheader/capacity,width/height/stride/payloadlength,request/response sequence,resizeepochและcommit/synchronizationboundaryชัดเจน
- มีsinglewriterและoneoutstandingrequest หรือprotocolที่ให้หลักฐานเทียบเท่า ห้ามreusebufferก่อนparentอ่านเสร็จ Childต้องตรวจขอบเขตก่อนGLallocation/readbackด้วย

### Consumer: CPU/GDI parent

- ไม่มีOpenGLimport/context;ตรวจknownGPUmodulesพร้อมยอมรับข้อจำกัดว่าsnapshotสามชื่อไม่พิสูจน์ทุกtransientvendorload
- ไม่เชื่อheaderจากsharedmemory:ตรวจversion/size/stride/overflow/capacity/epoch/sequence/commitก่อนcopy/paint เก่าหรือผิดต้องfailไม่แสดงเป็นframeใหม่
- แปลงbottom-upRGBAเป็นtop-downBGRAอย่างชัดเจน ใช้GDIbackbufferและWM_PAINTจริง ตรวจpixelsของparentbackbufferหลังpathนี้ ไม่ใช้childstdoutแทนparentpresentationproof
- Windowต้องอยู่นอกvirtualdesktopรวมทุกmonitorด้วยNOACTIVATE/SW_SHOWNOACTIVATE ไม่แย่งfocusหรือบังงานผู้ใช้ Savedimageคือoffscreenartifactไม่ใช่onscreenhumanacceptance
- Resizeหลายขนาดรวมodddimensionsต้องเปลี่ยนepochและไม่ใช้frameเก่าหลังresize

### Ownership/lifetime

- CREATE_SUSPENDED→assignprivateJob→resume,JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,จำกัดhandleinheritanceเฉพาะstdio+IPCที่จำเป็น
- Close/ack/deadline/childcrashต้องมีข้อกำหนดชัดเจน Parentต้องยืนยันchildexitและjobไม่มีowneddescendantsก่อนรับcleanup ห้ามปิดforeignhandles/threads
- Parentเก็บhandles/GDI/USER/ownthreadsหลังหนึ่งwarmup จากนั้น20cyclesต้องไม่เพิ่ม ไม่resetcounter/เพิ่มwarmupเพื่อกลบผล ต้องปิดtemporarymeasurement/IPC/GDIhandlesก่อนอ่านcounts
- GUImeasurementzero/errorต้องแยกกัน ทุกwait/kill/cleanupต้องboundedและรายงานunconfirmedถ้าหยุดไม่ได้
- Markerแบ่งproducer:parentpass/paint/cleanupรับเฉพาะparentoutput Childpixelmarkerรับเฉพาะchildoutput Binaryhashบันทึกprovenance/identityไม่ใช่hardwareattestationหรือsignedallowlist

## Planned test matrix (ยังไม่รัน)

| กรณี | เกณฑ์ |
| --- | --- |
| Positive/resize | จริงGPUframe→sharedmemory→verifiedGDIbackbuffer→WM_PAINTหลายขนาด ไม่มีstaleepoch |
| Parentlifecycle | หนึ่งwarmup+20cycles,childออก/jobempty,parentresourceไม่เพิ่ม |
| Stalesequence | rejectก่อนpaint ไม่ใช้frameเก่าเป็นใหม่ |
| Staleresizeepoch | rejectหลังresize ไม่ข้ามepoch |
| Badstride/size/overflow | rejectก่อนcopy/allocationout-of-bounds |
| Childcrash | failclosed ไม่มีparentpassหรือownedchildค้าง |
| Childhang | deadlinefail/cleanupเฉพาะprivatejobพร้อมconfirmedexit |
| Close/ackfailure | ไม่รับchildalive/noackเป็นcleanupผ่าน |

Testsต้องเก็บactualexit/expectedexit/timeout/parentcounts/childexit/paintcount/binaryhash/artifactและreadiness_evidence=false มีภาพให้parentagentเปิดตรวจ ไม่ใช้sourceinspectionแทนผลรัน

## สถานะเริ่มต้น

กำลังimplementationในfilesใหม่และadditivebuildtargetโดยwriterหนึ่งราย อีกฝั่งดูcontract/docs/review ไม่มีใครแก้fileเดียวกันซ้อน เมื่อbuild/testเริ่มต้องfreezeconsumedsourceจนจบ ผลจริง/ชื่อcommand/รูป/ข้อจำกัดจะบันทึกหลังทดสอบ **ยังไม่มีIPCpass**

PoCนี้ไม่รับรองterminalstate/fontatlas/images/ConPTY/clipboard/IME/input/focus/crashrecoveryในแอปจริงหรือperformanceที่ใช้งานได้ ต้องแยกscopeก่อนmainintegration Accepted62และCore/VT62/manualacceptanceเดิมคงเดิม

## Implementation / ผลรุ่นแรก — เวลา23:41

ไฟล์ใหม่`src/gpu_frame_protocol.h`,`src/win32_gpu_frame_probe.zig`,`tools/windows/gpu-frame-parent.c`,`tools/windows/gpu-frame-ipc.ps1` และadditivebuildtarget`windows-gpu-frame-probe`เท่านั้น Runtime/renderer/ConPTYหลักไม่เปลี่ยน

Wirev1มี80-byteheader+boundedRGBApayloadสูงสุด256×128(131072bytes),fixed-widthu32ไม่มีpointerข้ามprocess Childmapผ่านrestrictedinheritedhandle,request/responseauto-resetEvents,releasecommitและparentInterlockedacquire มีoneoutstandingrequest Parentcopyขนาดจากboundedlocalrequestเท่านั้นไม่ใช้sharedlengthซ้ำหลังvalidate แล้วตรวจheader/commitซ้ำหลังcopy

`gpu-frame-ipc-20261019-233828-586`ผ่าน14cases(positive+13negative),childReleaseSafe28/28,parentC17/O2/MT/W4/WX,ไม่มีwrappertimeout Positive1warmup+20cycles/21childrenexit+jobempty/84verifiedframesและWM_PAINTs Parent100handles/GDI0/USER1/threads3คงเดิม Sizes32×24→127×65→127×65→64×48,epochs101/102/102/103,sequences1/2/3/4

Parentagentเปิด`positive/frame-odd.png`ตรวจแล้ว:blue/whiteด้านบนred/greenด้านล่างตรงodd-sizefixture ภาพมาจากverifiedGDIbackbuffer ไม่ใช่desktopscreenshotหรือonscreenhumanacceptance ProducerตรวจทุกRGBApixel,consumerตรวจทุกpixelและแปลงbottomupRGBA→topdownBGRAก่อนStretchDIBits/GdiFlushและWM_PAINTBitBlt

Negativesรุ่นแรกครอบคลุมstale-sequence/stale-epoch/bad-stride/bad-size/bad-dimensions/bad-version/truncated/bad-pixel/crash/hang/close-hang/bad-close/launch-failure ต้องparent-onlyreject/ownedjobcleanup/GUIcleanup SourceimportsparentUSER32/GDI32/KERNEL32 ไม่มีOpenGL

## Parent review / กำลังทวนหลังเสริม

รุ่นแรกresizeเฉพาะframe/backbufferแต่HWNDคง256×128 ParentเสริมprogrammaticHWNDclientresizeตามframeจริง+ตรวจGetClientRect/offscreenทุกครั้ง เพื่อไม่เหลือพื้นที่frameเก่าหลังย่อ ไม่อ้างinteractiveuserresize/WM_SIZEครบทุกสถานการณ์

เสริมprocess-localper-monitor-v2DPIawarenessก่อนสร้างHWNDทั้งparent/childเพื่อให้offscreengeometryใช้physicalcoordinates ไม่แก้systemDPIsettings ต้องWindowsที่รองรับAPIนี้ ไม่silentfallback เสริมSelectObject/DeleteObject/StretchDIBits/Begin-EndPaintfailurechecks และเพิ่มbad-commit/bad-header/bad-capacitynegativecontrolsโดยตรง

กำลังbuild/run17casesด้วยhelper`-Build` แยกprefixเดิม ไม่ใช้ผล14casesอ้างsourceหลังreviewผ่าน ผลและhashใหม่จะตามหลังรันจบ Sourcesfreezeระหว่างbuild/test Accepted62และgpu-child66คงเดิม

ข้อจำกัด:trustedGPUproducerไม่ใช่hardwareattestation ภาพfixtureคงที่ จึงพิสูจน์sequence/epochmetadatafreshnessและpixeltransport แต่ไม่พิสูจน์freshcontentnonceหรือmaliciousproducerที่สร้างexpectedpatternเอง Mappingbounded/CPUcopy/หลายขนาดfixtureยังไม่ใช่terminal/fullscreen/font/IME/clipboard/performanceหรือproductioncrashrestartproof NativeResourceGrowthเดิมยังfailed

## ผลหลัง parent review — เวลา23:46

Command `.\tools\windows\gpu-frame-ipc.ps1 -Build` ผ่านจริง17/17cases ไม่มีwrappertimeout Childbuild28/28steps/ReleaseSafe-j1,parentC17/O2/MT/W4/WX ไม่มีลดwarnings

Artifacts:`%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\phase3b-runtime\gpu-frame-ipc-20261019-234450-167` Receiptsอยู่sharedresults.jsonlผูกชื่อrunนี้ Parentagentนับซ้ำ17passed/0timeouts/84FRAME_OK/21IPC_CHILD_OKและเปิดPNGที่แปลงจากBMPรอบนี้ตรวจblue-whiteเหนือred-greenถูกต้อง

| ผล | ค่าจริง |
| --- | --- |
| Parentbaselineหลังหนึ่งwarmup | handles100/GDI0/USER1/threads4 |
| Parentหลัง20cycles | handles100/GDI0/USER1/threads4 ไม่มีcycleเกินbaseline |
| GPUframe/presentation | 84frames/WM_PAINTs/21childrenexit0/jobempty |
| Resize | 32×24→127×65→127×65→64×48 พร้อมactualHWNDclientdimensionsassertและoffscreenassertหลังresize |
| Offscreengeometry | physicalx1984,y0,NOACTIVATE,visibleoutsidevirtualdesktopบนเครื่องนี้ |
| Negativecontrols | 16กรณีexpectedexit1,rejectก่อนpaint/ownedjobcleanup/parentviewcleanupยืนยันจากparentoutput |
| Parenthash | 3B8452954462C8B0BA0D829392890C480E354D7C7B0422CE8F72269D7D65015B |
| Childhash | 73256D5C0CF8B36BE9C70AA7077D3A31195AD441CD23FA45C2C40F8ABCEFDE1A |

เพิ่มbadcommit/header/capacityจาก13negativeรุ่นแรกเป็น16negative:stale-sequence/stale-epoch/bad-stride/bad-size/bad-dimensions/bad-version/bad-commit/bad-header/bad-capacity/truncated/bad-pixel/crash/hang/close-hang/bad-close/launch-failure Errorsถูกยืนยันโดยexpectedmarker+exit+cleanupไม่ใช่แค่nonzero Childcrash/hangไม่ทำให้parentรับframeหรือcleanupปลอม

ตรวจhashaccepted62และGPU-child66ซ้ำ:ทั้งหมดตรงเดิม62=`2589A9B770D5930E1F00C654D4D89116C78B522A94A0E4EEB1D9AAE9829327CC`,parent66=`AE7B6746C2BFECE146A435B1F0E7DE46429E05A05EF0A8011F9DDAB35743CC9C`,child66=`E0702D84CAF6EB797E996EFE55F1A3BEC171BAA9A29A10A86641D0C905B0909B` ไม่ถูกทับ

### ข้อสรุป/ขอบเขตถัดไป

**Shared-memoryGPUframe→CPU/GDIparentpresentationPoCผ่านบนเครื่องนี้** ไม่ใช่nativeappResourceGrowthผ่านหรือproductionintegration ภาพคือbackbufferartifactไม่ใช่desktopscreenshot/onscreenhumanacceptance ProgrammaticHWNDresizeผ่าน ไม่ใช่interactiveWM_SIZE/monitorDPItransitionacceptance ไม่ทดสอบmaxmappingทุกdimension/continuousredraw/ประสิทธิภาพterminalจริง

ตอนนี้ไม่มีbuild/test/workerรันค้าง ไม่มีcommit/pushหรือdriver/systemsettingschanges ขั้นต่อไปแนะนำแผนintegrationแบบopt-inพร้อมownership/IPCversioning/input-IME-clipboard/timeout-restart/rollbackและfullregressionmatrixก่อนแตะmainrenderer ต้องขอscopeapprovalแยก ไม่ถือว่าคำอนุมัติPoCครอบคลุมmainrewrite
