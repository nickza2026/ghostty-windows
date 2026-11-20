# แผน integration: opt-in GPU render worker

## 1. ขอบเขต/สถานะ — 20 ตุลาคม 2026

เริ่มจากผู้ใช้09:47ตอบ “ได้เริ่มเลย” ต่อข้อเสนอ **ทำแผน integration/ownership/opt-in/rollback ก่อนแก้ renderer หลัก** ซึ่งช่วงแรกเป็นdocs-only ต่อมาได้รับอนุมัติให้เริ่มimplementationตามboundaryและทำต่อเนื่อง สถานะปัจจุบันมีopt-intext-onlyGPUworkerhostจริงแล้ว ไม่ย้ายCore/PTY/input/IME/clipboardไปchild ไม่สร้างPoCสีเพิ่ม ไม่เปลี่ยนdriver/systemsettings/gates/defaultbackendหรือcandidate62 ไม่commit/push ผลล่าสุดและข้อที่ยังpendingอยู่ในข้อ9และ[API inventory](windows-render-worker-api-inventory.md)

หลักฐานเดิมแยกชัด:

- Accepted62:humanThai/Herdrappearanceผ่าน;fullCore3926pass61skip/VT6722pass64skip Native strict lifecycleยัง233→234handles/6→7threads failed
- GPU-child66:process-boundarylifetimeผ่าน22childrenพร้อมnegativecontrols แต่ไม่ได้รวมterminal
- FrameIPCหลังreview:17cases/84frames/21childrenexit/jobempty,parent100handles/GDI0/USER1/threads4ไม่เพิ่ม มีGDI/WM_PAINTจริงและprogrammaticHWNDresize ไม่ใช่terminal/input/IME/performanceproof
- ข้อจำกัดและartifactreferencesอยู่ใน[GPU-child](windows-gpu-child-poc.md),[FrameIPC](windows-gpu-frame-ipc-poc.md),[attribution](windows-runtime-attribution.md) ไม่ใช้ผลcomponentลบnativefailure

## 2. จุดเชื่อมที่ตรวจจากโค้ด

| Source anchor | ข้อเท็จจริง | ผลต่อแผน |
| --- | --- | --- |
| `src/renderer.zig`, `Renderer = GenericRenderer(GraphicsAPI)` | backendเลือกcomptimeจากbuildconfig มีDeviceตามGraphicsAPI | เพิ่มแค่runtimeflagไม่พอ ต้องแยกbuildgraphของhost/worker |
| `src/build/SharedDeps.zig` win32linkblock | ลิงก์user32/gdi32/**opengl32** | hostทดลองต้องไม่ลิงก์OpenGLหรือglad/WGLpath ตรวจimportsจริง ไม่ถือว่าไม่เรียกGLก็พอ |
| `src/Surface.zig: Renderer.init`, `renderer_state` | ผูกdevice/fontgrid/surface/thread/mailbox และterminal=`&self.io.terminal` | pointerพวกนี้ห้ามส่งข้ามprocess |
| `src/renderer/Options.zig` | `*Device`, `*SharedGrid`, `*Surface`, `*Thread`, Mailbox | ต้องเปลี่ยนขอบเขตเป็นownedbytes/IDs ไม่serializeOptionsดิบ |
| `src/renderer/State.zig` | terminal/preedit/mouseอ่านภายใต้`*std.Io.Mutex` | mutexยังอยู่parent CPU snapshotต้องจบก่อนรอIPC |
| `src/renderer/generic.zig: init/updateFrame/drawFrameLocked` | initเรียกGraphicsAPI.initก่อนสร้างfontshaper;updateอ่านterminal/font/mouse/preedit | ต้องแยกCPU preparationออกจากGPUsideeffectsจริง ไม่เปลี่ยนแค่present |
| `generic.zig: syncAtlasTexture` | fontatlasbytesผูกtexture resize/replaceRegion | ต้องมีatlasgeneration/resourceupload/ack ไม่ส่งAtlas pointer |
| `src/renderer/OpenGL.zig: init/threadEnter/present` | Windowsสร้างWGLcontextตั้งแต่init;presentส่งallocatedRGBA | ย้ายpresentอย่างเดียวจะยังเหลือGL/AMDในparent |
| `src/apprt/win32/Surface.zig: present` | takeFrame→presenter.Image.fromRGBA→invalidate | จุดรับRGBAใหม่ฝั่งUIที่ควรรักษาinterface/ownershipเดิม |
| `win32/Surface.zig: resize/setDpi/deinit` | CorecallbacksและCoredeinitก่อนคืนclipboardfiles | รักษาDPI/resizeและportablepathlifetime ไม่ผูกกับworkerexit |
| `win32/App.zig: ready/closing/paint/resized/focusChanged/mouseEvent` | HWND,input,closeconfirmationและCorecallbackอยู่UIparent | ไม่ย้ายrawWindowsinput/clipboardไปGPUworker |

บรรทัดเปลี่ยนได้ ให้ค้นsymbolanchorsข้างบน ไม่ใช้line-numberเก่าแทนverification

## 3. แนวทางที่แนะนำ

**รักษาCore/PTY/input/fontshapingไว้parent ย้ายเฉพาะGPUexecutionไปworker ผ่านserializable render packets** ใช้GenericRenderer/GraphicsAPI abstractionเท่าที่ตรวจแล้วรองรับ ต้องทำAPIinventoryก่อนสรุปว่าRemoteGraphicsAPIเป็นdrop-inได้

อีกทางคือย้ายทั้งCoreSurface/PTYไปchild ซึ่งลดpointerboundaryฝั่งrenderer แต่จะขยายinput/IME/clipboard/session/ConPTYownershipมาก จึง **ไม่เลือกในแผนนี้** และห้ามสลับไปทำเองเมื่อGPU-onlyยาก

### Binary/opt-in

- เสนอhostทดลองแยกexecutable/buildtargetและworkerเฉพาะ แยกprefixจากaccepted62 ชื่อtarget/flagยังเป็นข้อเสนอ **ยังไม่มีcommandให้รัน**
- Legacy/defaultbuildยังใช้เส้นเดิม Hostทดลองcomptimeเลือกremote-onlybackendและdependencygraphไม่มีOpenGL imports;childเท่านั้นลิงก์OpenGL/WGL
- Selectorที่launcherเลือกartifactก่อนเปิดsession ไม่persistglobalenvironment/registry/userconfigเอง และไม่ทำsilentfallback
- ตรวจstaticimports+runtimeknownmodulesทุกcycle:hostไม่มีOpenGL/knownAMDmodules ข้อจำกัดเรื่องtransientvendorinjectionต้องระบุ ไม่อ้างว่าprocessisolationเป็นsecuritysandbox

## 4. Ownership ที่ต้องรักษา

| Parent (UI + CPU) | GPU worker |
| --- | --- |
| VisibleHWND,paint/backbuffer,focus/DPI/resize/cursorposition | HiddenoffscreenWGLhost/context,GLthread |
| CoreSurface,terminalstate,VTparser,selection,search,scrollback | Shader/pipeline/target/texture/bufferที่สร้างจากpacket |
| ConPTYprovider/HPCON,IOthread,shellprocess,lifecycleและexitstatus | ไม่เปิดshell/PTY ไม่รับrawkeystrokesหรือclipboard |
| Fontdiscovery/shaping/grid/CPUatlas/cache/derivedconfig | GPUatlastextures/resourcegenerationตามupload |
| IME/preedit,key/mouse callbacks,title/notifications/permissions | รับdrawstateที่parentจัดเตรียมแล้วเท่านั้น |
| Clipboardtext/image/permission,portableimageStore | ไม่เลือกTEMP/portablepathหรือเขียนpastedimage |
| ImmutableCPUrenderpacket,IPCsession/privatejob,frameacceptance | อ่านpacket,validate/executeGL,readback/publishRGBA |

GPUjobห้ามครอบshell/ConPTYchildren การkillGPUjobต้องไม่ปิดsessionจริง Workercrashไม่ใช่เหตุให้ลบportableimages/ส่งinputซ้ำ/เปิดshellใหม่

## 5. Packet/transport contract (ออกแบบก่อนimplement)

FrameIPC v1จากPoCไม่พอสำหรับrealrenderer ต้องversionใหม่ ไม่ขยายmeaningของ80-bytefixtureheaderเงียบๆ

### Command side

- Handshake:protocol/buildcompatibility,sessionnonce,supportedformats/limits/status ไม่ใช่permissionให้ใช้globalchannel
- Frame identity:surfaceID,workergeneration,resizeepoch,monotonicsequence และresourcegeneration ไม่มีrawpointer/allocator/mutex/HWNDaddress
- CPUfrontendsnapshotterminal/preedit/mouseภายใต้existingmutex แล้วcopyออก immutablepacketก่อนปล่อยlock ไม่waitIPC/UI/mailboxในcriticalsection
- Render packetประกอบด้วยdimensions/scales,opaque/premultipliedalphacontract,uniforms,draw/cell/overlaydataและresourceIDs ต้องinventoryจริงก่อนfreezewirelayout
- Atlas/image/buffer/shaderdataส่งownedboundedbytes พร้อมIDs/generation/create-update-destroy acknowledgements ใช้explicitportablewiretypesไม่memcpyZig/Cnativevertexstructดิบ
- IDsห้ามreuseจนworkerackreleaseหรือgenerationเปลี่ยน ห้ามdropresourceuploadsเพียงเพราะdropoldframeได้
- ที่minimize/zero-sizeส่งsuspend ไม่allocatezeroFBO เมื่อคืนขนาดต้องepochใหม่และfullframe

### Frame side

- RGBAformat/alpha/roworientationต้องเทียบ`OpenGL.ExportedFrame.Memory`และ`presenter.Image.fromRGBA`จริง PoCopaquequadrantsยังไม่พิสูจน์alphablendingของterminal
- แยกcommand/responseownership ใช้events+release/acquirecommitและvalidateheaderก่อน/หลังcopyตามPoC แต่header/session/generation/resourceacksต้องเพิ่ม
- ตรวจversion/header/capacity/overflow/dimension/stride/payload/epoch/sequence/generationก่อนallocate/copy/paint ใช้parentrequestboundsไม่re-readsharedlengthเพื่อขยายcopy
- Latest-framepolicyทำได้เฉพาะcompletedframes ไม่dropcontrol/resource/closeack มีboundedqueueและbackpressure ไม่allocateเรื่อยๆเมื่อworkerช้าหรือUIค้าง
- ห้ามใช้256×128fixturecapเป็นproductionlimitเงียบๆ ต้องnegotiatedhardcapsและerrorUIเมื่อเกิน ไม่มีsilentcrop/downscale/fallback ขนาด/slotcount/memorybudgetต้องวัดก่อนเลือกจริง
- ภาพ/terminalcontentถือเป็นข้อมูลsession ไม่dumprawtext/pixels/environmentในdefaultdiagnosticlogs ใช้metadataเท่าที่จำเป็น

### Input/IME/clipboard

ไม่สร้างkeyboardIPCอีกชุดในGPU-onlyarchitecture:inputไปCore/PTYparentเส้นเดิม ส่งเฉพาะผลCPUdrawstate ส่วนIMEcandidate/caretgeometry/focus/selectionเป็นUIparent ต้องทวนว่าความหน่วงframeไม่ทำให้caretcoordinateเก่า

Clipboardpermissionsยังขอบเขตเดิม ไม่auto-approve ตอนworkerrestartไม่ลบimageStore Portableimageยังrootตาม**parent executableที่รัน**ไม่ใช่cwd/helperexe/TEMP fallback

## 6. Close/crash/restart และ rollback

### Normal close

1. ผ่านcloseconfirmationเดิมก่อน ไม่ส่งcloseเพียงเพราะworkerขัดข้อง
2. หยุดรับrenderworkใหม่/ยกเลิกpendingwaits ให้CPUproducerหยุดโดยคงCoredeinit/join/mailbox-drainorderที่มีอยู่ ต้องตรวจorderจริงในimplementation ไม่จับdraw_mutexแล้วรอUI
3. ส่งGPUcloseด้วยgeneration/sequenceที่กำหนด รอack **และ** processexit0/jobemptyภายในabsolutebudget UIต้องresponsive ไม่บล็อกWndProcรอไม่จำกัด
4. หลังไม่มีCPUcopy/childaccessจึงunmapและcloseIPC/GDIhandlesแล้วDestroyWindowตามlifetime ปิดIO/PTYและลบclipboardfilesด้วยexistingSurfaceclosepolicy ไม่ทำworkercleanupไปเปลี่ยนPTYorderเอง

### Worker fail

- Markrendererunhealthy,แสดงlast-goodframe/errorชัดเจน ไม่เรียกframeเก่าว่าlive ไม่ปิดหรือrelaunchshellและไม่replaykeystrokes
- ไม่มีsilentin-processGLfallback เพราะhostremote-onlyต้องไม่โหลดOpenGL
- Restartเสนอให้explicit/bounded:childใหม่generationใหม่,discardoldframes/resourcesและreplayfullCPUresources+fullframe ไม่จำลองPTYsessionใหม่;policyจำนวนretry/timeoutต้องตัดสินใจก่อนimplement
- Forcekillได้เฉพาะownedGPUjobเมื่อdeadlinefail บันทึกforcedexitแยก ไม่รับว่าhealthyclose แม้OSคืนresourceแล้ว
- CPUworker/mailboxห้ามอยู่ในlockขณะwaitIPC ห้ามloopresetdeadlineทีละmessageจนไม่มีวันtimeout

### Rollback

- ก่อนเปิดsession:เลือกlegacyartifact/launcherเดิม Accepted62ไม่ถูกทับ
- ระหว่างsession:ปิดทดลองผ่านnormalcloseก่อนเปิดlegacyใหม่ แจ้งsessioncontinuityให้ชัด **ไม่อ้างseamlessย้ายHPCON/VTstate/PTYไปlegacy** และไม่แอบเปิดshellที่สอง
- แยกprefix/config/versionedprotocol ไม่deployhelperทับคนละversion ชื่อhelperต้องresolveจากapprovedparentexedir ไม่searchcwd/PATH

## 7. Implementation milestones (กำลังดำเนินการ ไม่ใช่ผ่านครบทุกข้อ)

| Milestone | งานที่แตะrealterminal ไม่เพิ่มfixtureสีใหม่ | Exit criterion |
| --- | --- | --- |
| M1: API/dependency split | inventoryGraphicsAPI/Texture/Target/Frame/Pipelinecalls;แยกCPUinitออกจากGPUsideeffects,remote-onlybuildgraph;legacypathคงเดิม | legacy/nativebaselineไม่ถอย;hostทดลองไม่importGL;ไม่มีwirepointer;patchscopeและAPIinventoryreviewก่อนM2 |
| M2: First terminal frame | actualCoreterminalCPUcells+fontatlas→packet→GPUworker→existingparentpresenter | deterministicASCII/Thai/textcursorจริงเทียบlegacypixel/grid ไม่ใช้quadrantPoCแทน |
| M3: Resource/surface lifecycle | atlasresize/generation,images,resize/DPI,minimize,backpressure/close/crash/restart | odd/maxbounds/lateframes/timeout/exit/jobempty+parentcountsผ่าน ไม่dropuploadack |
| M4: Interaction parity | key/mouse/selection/wheel/focusloss/IME/preedit/clipboard/portableimages/titlemailbox | automatedsyntheticcontrolsและhumanmanualเฉพาะที่จำเป็น ไม่แอบเปิดGUIforeground/อ่านclipboardผู้ใช้ตอนautomated |
| M5: Qualification | fullCore/VT/unfilterednative/gpuworker+negativecases/performance+packaging/rollback | worker-modeผ่านเกณฑ์เดิมจริง+childcleanup พร้อมbudget/humanacceptance;legacyResourceGrowthรายงานแยกไม่อ้างว่าหาย ไม่เปลี่ยนthreshold/warmup/defaultเพื่อรับผ่าน |

M1–M5เป็นแผน ไม่ใช่คำอนุมัติทำmainrewriteทั้งหมด ต้องอนุมัติimplementationboundaryก่อนเริ่มM1 เมื่ออนุมัติแล้วให้ทำmilestonesในขอบเขตต่อเนื่อง ไม่ถามซ้ำทุกcompile/test หยุดเฉพาะscope/riskจริง

## 8. Validation/acceptance matrix

- Agent-owned:legacyfullCore/VTและnativesyntheticregressionsตามคำสั่งเดิม,sourcefreezeระหว่างbuild/test,hashaccepted62,staticimportsของhost,actualworkerGL+realterminalframe+parentWM_PAINT/readback
- Agent-owned:หนึ่งwarmup20surfacecyclesและgateshandles/GDI/USER/threadsเดิม รวมchildexit/jobempty/closeack ไม่มีorphanหรือlateframeintoDestroyedsurface ทุกforcednegativeต้องexpectedfailure+parent-onlycleanup ไม่ใช้wrapperexit0แทนnativepass
- Agent-owned:malformedwire/overflow/truncation/staleepoch-seq-generation/missingresourceack/childcrash/hang/blockedmailbox/closebeforefirstframe/resizewhileinflight/minimize/atlasreallocation/memorypressure
- Agent-owned:normal/portableimagefixtureใช้diskrootตามexecutable,cleanupหลังsessionclose ไม่อ่านOSclipboard/sessionผู้ใช้ในautomatedcases
- Human-owned:HerdrThai/กล่องคำถาม/สีพื้น,cursor,IMEcomposition/deadkeys/clipboardconsumerจริง,mixed-DPIinteractivefeel/resizeและความลื่นของworkerhost ต้องขอvisiblepreviewชัดเจน ไม่อ้างoffscreenแทนonscreenacceptance
- Performanceยังไม่มีbudgetที่วัด:เก็บframe/resizep50-p95,queueoccupancy/droppedframes,CPU/RSS/commit/bytescopied/idle ไม่อ้างCPUcopy256×128พิสูจน์1080p/4K60fps ตัวอย่าง1080pRGBAหนึ่งcopyประมาณ8.3MB/frame ต้องวัดหลายcopyจริงก่อนpromote
- หลักฐานทุกphaseต้องbinaryhash/command/exit/skip/failure/timeout/artifact/knownlimits ไม่มีrawsessiondumpหรือglobaldriverGFlagschanges
- การqualifyworker-modeไม่เปลี่ยนผลlegacy-modeที่failed การpromote/default/releaseต้องตัดสินใจlegacyblockerและขอบเขตsupportแยก ไม่ประกาศว่าแอปทั้งหมดผ่านเพราะmodeเดียวผ่าน

## 9. ผลงานรอบนี้/จุดตัดสินใจ

สถานะ20ตุลาคม2026หลัง12:44:

- M1 dependency/CPU split: `-Dwindows-remote-renderer=true` defaultfalse,artifactแยก`zig-out/render-worker-host`;build125/125,dumpbinhostnoGLimports,actualterminalruntimeparentไม่พบGL/AMDmodules Workerใช้GLgraphของตนเอง/hello/session/epoch/ownedbytes ไม่มีwirepointer
- M2 text subset: realterminalCPUcells/uniforms/fontatlases→worker→ownedRGBA→parentpresenterเดิม;legacy/workerexactmemcmp29frames,max655glyph,failures0;strictThaiVTdiff0และremotehost33paintframesผ่าน ไม่ใช่images/customshader/overlayหรือhumanvisualacceptance
- Positive lifecycle opt-inครั้งแรกผ่านstrictgateเดิม20cyclesหลังwarmup:handles123→123/GDI2→2/USER1→1/threads4→1 และworkerclosedACK+exit0+jobempty/forced0ครบ21ตัว ไม่ใช้ผลนี้อ้างว่าlegacy/defaultResourceGrowthถูกแก้แล้ว
- Background screenshotดูผ่านPNGconversionและsamplepixelsเทียบlegacyจริง:default12/12/12,RGB30/30/30,index29/31/33,RGB18/52/86,reset/ELตรง;mouse/selection/wheel/capturelossใช้in-memorysinkผ่าน ไม่อ่านclipboardผู้ใช้
- เพิ่มremoteconfigupdatefail-closedก่อนmutateownerstate **exec88ผ่าน** remote125/125+Thai+strictlifecycleซ้ำ`125040-182`(handles123→123/GDI2→2/USER1→1/threads4→1/21healthyworkers),legacy123/123+Thai`125455-314`/background`125507-043`/mouse`125517-445`,fullCorepost-host89/89steps3961/4022pass61skip ทุกstageexit0 ไม่ใช่legacyResourceGrowthผ่าน
- เริ่มM3negativeจริงในcheck executableเท่านั้น:badreserved/version/surface/truncated/replayedheadersต้องrejectก่อนpublishและworkerยังcloseได้,submitก่อนhello/unsupportedresourcecommandต้องexit1ไม่ACK,forcedownedworkerexit77ต้องไม่healthycloseและreap/jobempty/parenthandles0 **exec92build/run active** ไม่มีfaultentrypointในproduction ไม่ใช้ผลนี้อ้างhang/lateframe/resizeครบ
- M3–M5 resource/image/resize/DPI/minimize/backpressure/crash/restart/negativecases/interactionเต็ม/performance/packaging/humanacceptanceยังไม่ครบ ไม่promoteopt-inเป็นdefault และไม่มีข้อยกเว้นResourceGrowth

ขั้นต่อไปปิดpositiveM1/textM2regressionbatchให้จบ แล้วทำresource/failure/surface lifecycleตามM3ก่อนqualification ไม่ย้ายทั้งterminal/ConPTYไปchildหรือเปลี่ยนdriverเพื่อรับผ่าน
