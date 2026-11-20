# M1 GraphicsAPI inventory / CPU preparation seam

20 ตุลาคม 2026 ผู้ใช้10:20ตอบ “งั้นแก้ต่อเลย” ต่อแผนintegration เริ่มimplementationM1 ไม่เปลี่ยนdefault/promotion/driver/gates ไม่ทับaccepted62

## M1a ที่ลงโค้ดแล้ว (กำลังทดสอบ)

- เพิ่ม`src/renderer/CpuPreparation.zig` รับallocator/shaperoptions/metricsแบบvalueเท่านั้น ไม่มีDevice/GraphicsAPI/HWND/Surface/Thread argument
- ถือoptionalshaperเป็นownerจนrendererinitสำเร็จ `takeShaper`โอนownershipครั้งเดียวและdeferredcleanupหลังtransferไม่doublefree
- ใน`generic.zig`แยกfontgridmetricssnapshotภายใต้lockแล้วออกจากlockก่อนallocation/initต่อ WindowsเตรียมCPUก่อนWGLinitเพื่อให้CPUfailureไม่ต้องสร้างGPUก่อน ระบบอื่นคงGPU→CPUinitorderเดิม
- `Self`ยืมshaperระหว่างfallibleinit หลังprepBackgroundImageสำเร็จจึงtakeownership;abortปล่อยผ่านCpuPreparationdeferและAPIerrdefer ไม่อ้างแก้backgroundimageerrorpathอื่นที่มีอยู่ก่อน
- เพิ่ม3tests:metricsvaluecopyไม่มีdevice,ownershiptransfer/emptycleanup,checkAllAllocationFailuresของCPUpreparation รวมtestdiscoveryที่rendererroot
- ยังไม่แยกhostbinary/RemoteGraphicsAPIหรือส่งterminalframeจริง ยังไม่M1complete/ไม่GPUprocessintegrated

## API ที่ต้องเป็น remote-compatible ก่อน M2

| Contract/source | สิ่งที่พบจริง | งานถัดไป |
| --- | --- | --- |
| generic Renderer type aliases | Target,Buffer(T),Sampler,Texture,RenderPass,shaders,ExportedFrame และcustomshadercoordinate/target/swapchaincount | ใหม่ต้องมีtypedcontractครบ ไม่borrowOpenGLtypesที่ดึงGLเข้าhost |
| init/deinit/threadEnter/threadExit | initเตรียมAPI;thread hooksบนrendererworkerthread | remoteinitสร้างsession/jobไม่สร้างparentWGL;explicitownedteardown |
| optional loopEnter/Exit/displayRealized | genericตรวจhasDecl | รักษาunrealize/re-realize/minimize semanticsไม่สร้างWGLในparent |
| surfaceSize/setViewport | sizeจากbackendและviewportตามresize | ใช้parent-approvedsize/epoch ไม่childอ่านparentHWND |
| api.blending field | genericแก้fieldตรงจากconfig | proxyเป็นCPUvalueที่encodeในpacket ไม่เรียกGPUทันทีในparent |
| initShaders/shaders | shaderassets/config/customtarget | childมีshader/pipelineIDs;version/compileerrors/allowedcustomshadercontractต้องกำหนด |
| Buffer(T).init/initFill/sync/syncFromArrayLists/deinit | typedCPUarrays→GPUbuffers | explicitportablevertex/uniformwireencoding+IDs;ห้ามnativeusize/padding memcpy |
| Texture.init/replaceRegion/deinit;syncAtlasTexture | bitmapatlasresizeและupload | generation/create-update-destroyacks;copystablebytesก่อนปล่อยfontlock |
| Target.init/deinit/readPixelsAlloc | FBO/CPUreadback | GPUallocationchild,frameboundsparent,CPUframeownerมีdeinit |
| Sampler.init/deinit | filter/wrapstate | boundedresourceIDs/generation |
| Frame.begin/renderPass/complete | เก็บrenderer/targetpointersในlocalAPI | remoteframebuilderเก็บparent-localIDs ห้ามserializepointers |
| RenderPass.Options.Attachments/Step | Pipeline/gl.Buffer/Texture/Sampler slices;Drawใช้usize | drawpacketต้องprimitive/vertex/instancecountsแบบfixedwidthและoverflowchecked |

### Completion/backpressure ที่ห้ามพลาด

`opengl/Frame.zig:complete`ปัจจุบันgl.finish→pushFrame→surface_mailbox.push(.redraw,.forever) แล้วframeCompletedhealth เป็นเหตุให้closeต้องdrainmailboxตามfixเดิม Remotecompletionต้องไม่รอackจากUIกลับขณะUIรอjoinCPUrendererหรือถือdraw_mutex ห้ามcopyแบบเดิมเป็นblockingcrossprocessroundtrip

แยกresource/controlackจากlatestcompletedframequeue:dropframeได้ตามpolicyแต่ห้ามdropupload/destroy/closeack deadlineต้องabsoluteและbounded ไม่resetต่อmessageจนไม่มีวันtimeout

## M1b dependency/build boundary

ตรวจ`renderer.zig`เลือกGenericRenderer(GraphicsAPI)ตอนcompile และSharedDepswin32ลิงก์opengl32เสมอในปัจจุบัน จึงต้องแยกremote-onlyhostbuildgraph/childworkergraph ไม่ใช่เพิ่มruntimeflagในlegacyexeแล้วยังlinkGLอยู่

ยังไม่เพิ่มglobalBackendenum/เปลี่ยนpublicABIโดยอัตโนมัติ ต้องทำAPItypesและinternalexperimentalbuildselectionที่ไม่เปลี่ยนMetal/OpenGLdefaultก่อนตรวจhoststaticimports/runtimeknownmodulesจริง อาจพบcouplingผ่านshaders/Frame/Optionsที่ต้องแก้เพิ่ม ให้รายงานscopeจริงไม่ใส่stubที่pretenddrawสำเร็จ

Sourceanchors: `renderer/generic.zig`, `renderer/Options.zig`, `renderer/OpenGL.zig`, `renderer/opengl/{buffer,Texture,Target,Sampler,Frame,RenderPass}.zig`, `build/SharedDeps.zig` ภายใต้src

## Validation status

กำลังรันfullCoreDebug/-j1/unfilteredแยกprefix`zig-out/render-worker-m1` sourcefreezeจนจบ ยังไม่claim3testsหรือfullsuiteผ่าน ยังไม่บิลด์ทับ62/รันnativeGUIหรืออ่านclipboard/user-session แผนหลังผลจริงคือทวนnativelegacyและเดินM1bต่อในscopeapproved ไม่ขออนุมัติซ้ำทุกbuild แต่ไม่ขยายไปwhole-terminalchildโดยไม่ขอscope

### Full Core ผ่าน — 20 ตุลาคม เวลา10:37

FullCore89/89steps,3929/3990testsผ่าน61skip,exit0/ไม่timeout Debug-j1/no filter รวม3testsใหม่ ไม่เพิ่มskipเพื่อให้ผ่าน จากนั้นเริ่มnativeReleaseSafe-j1แยกprefixเดียวกันโดยprovisionapp-localConPTYที่pin/signatureเดิม แล้วstrictThaiTUI/background/mouseแบบoffscreenตามhelpersเดิม Sourcefreezeระหว่างnativebuild/tests ไม่ถือCorepassว่าnativepassล่วงหน้า

APIinventoryเพิ่มเติม:OpenGLFrame.completeเรียกgl.finish/pushFrameแล้วmailbox.redrawแบบforever มีGenericrenderer/Targetpointersเป็นlocalstateและRenderPass.Stepใช้GLobjects/slices/usize ตามsource จึงต้องencodefixed-widthresourceIDs/bytesก่อนremoteAPI ยังไม่เขียนremotehostที่แกล้งreturnsuccessแทนdrawจริง

### M1a nativeผ่าน / M1b data split เริ่ม — เวลา10:41–10:44

NativeReleaseSafe123/123stepsผ่านกับCpuPreparation StrictThaiTUI`terminal-native-20261020-104115-052`different_cells0(default_gc=true),cursor45/11ตรงเดิม;backgroundhelper`104127-137`และmouse`104137-525`exit0/remaining_surfaces0 SourceยังlegacyOpenGLทั้งสาม ไม่ใช่remotehost ResourceGrowthเดิมไม่ได้ประกาศหาย Backgroundhelperpassไม่ใช่humanvisualacceptanceใหม่

เพิ่ม`renderer/remote/Protocol.zig`draftv2CPU-onlyenvelope48bytes,explicitlittleendian,fixedwidthsurface/generation/sequence/epochและResourceIdslot+generation ไม่มีpointerหรือGLtypes Passed7/7standaloneDebugtests:roundtrip/truncated-trailing/unknownversion-kind-flags/oversizedlength/session-seq-epoch/invalididentity/resourcegeneration No payloadschema/transport/GPUexecutionหรือregistrylookupimplemented ห้ามอ้างcodecpassว่าdrawpass Hardpayloadguard64MiBเป็นเพดานparserไม่ใช่negotiatedproductionperformancebudget

แยกactuallegacyGLSLUniforms/CellText/CellBg/Image/BgImageไป`renderer/GlslData.zig`ที่ไม่importPipeline/GL,oldshadersre-exportaliasคงlayoutทุกfieldalignment ไม่ใช้nativeGPUlayoutเป็นwireABI เพิ่ม2testsขนาด/alignment/offsetและpackedflags/atlasenum และCPU-onlytestroot`src/render_worker_contract_tests.zig`

เริ่มexec20ทวนCPUcontract/layout10testsและstaticimportsไม่GL → nativebuild123stepsคาดตามgraph → strictThai/backgroundcapture/mouse ขณะนี้ยังไม่อ้างผ่านรอบหลังShaderDataextract Sourcefreezeระหว่างbuild/tests FullCore3929ผลก่อนextractต้องแยกtimestamp ไม่อ้างเป็นfullsuiteหลังsourceใหม่ M1bhostdependency/APIproxyยังinprogress

### M1b ผลจริง/codecต่อ — หลังเวลา10:49

- exec20CPUcontract/layout10/10และnoGLimportsผ่าน แต่nativecompilefailedเพราะalias`data`ชนparameterเดิม ไม่ลดcompilergate แก้aliasเป็นcpu_data แล้วexec21native123/123/strictThai`105346-090`diff0 cursor45/11/background`105358-358`/mouse`105408-769`ผ่านactualexit0/surfaces0
- ภาพ`render-worker-m1-data-fix-20261020-105003.background.bmp`เปิดตรวจแล้วDEFAULT/RESET49/RESET0และRGB/ELสีตรงfixture,top-leftRGB12/12/12 เป็นbackbuffer1034×661 ไม่ใช่desktopscreenshot/humanacceptance
- ตัวช่วยnewcodecเริ่มไม่ได้provideropenaiไม่configured ตรวจไม่มีpartialfilesแล้วทำตรงเอง ไม่มีprovider/harnesssettingschanges
- RegistryCPU-only:reserve→creating→validatedcreateACK→live→destroying→validateddestroyACK→vacant/generationใหม่ ห้ามreuseก่อนACK,ตรวจkind/worker/session,duplicate/staleACK,rejectedcreate,exhaustionไม่wrap,OOMcleanup Passedรวมwire/layout17/17
- CommandsCPU-only:explicitLEbuffer/texturedescriptorและgrayscale/BGRA/RGBAatlasupload,typedformats/targets/filters/wrap,region subtractionหลีกเลี่ยงoverflow,cap/dimension/stride/exactlength/ResourceIdchecks Passedรวม23/23 ยังไม่มีcompletebufferwrite/pipeline/target/sampler/drawpayloadexecutor อย่าเรียกว่าfullRemoteGraphicsAPI
- ShaderPayloadCPU-only:Uniforms124bytes(ไม่copy144-byteGPUstruct),CellText30(ไม่32),Image40(ไม่48),BgImage5(ไม่8),float/packedflags/atlasenum/lengthchecks Explicitmatrix4lanesใช้inlineforหลังcompilerจับdynamicvectorindex Passedรวม27/27 ไม่มีwirepadding/nativepointer
- Limitsเป็นboundedparser/negotiatedinputcontract ไม่ใช่performancebudgetหรือcapabilityรับรองGPUจริง Decodeคืนborrowedbytes ต้องtransportถือownershipfenceก่อนcopy/consumeและreceiverregistryตรวจlivenessต่อ

### Catalog split / finalbatch active

แยกbuiltinGLSLsources/names/vertexlayout/step/blendingไป`renderer/GlslCatalog.zig`ที่ไม่importGPU Pipeline LegacyshadersแปลงcatalogกลับPipelineDescriptionเดิม บันทึกค่าตรงbuiltin5pipelines/customfullscreenvertex ไม่เปลี่ยนshadercode/flip/alpha semantics

exec27กำลังทวนCPU29tests+noGLimports→nativeReleaseSafe+Thai/backgroundcapture/mouse→**fullCoreล่าสุด**ตามลำดับSourcesfreeze FullCore3929ก่อนหน้ายังแยกผล ไม่อ้างเป็นpost-catalogsuite M1bremotehost/dependencyselection/workerexecutionยังไม่เสร็จ ต้องทำrealterminalCPUframe/resourcepacketต่อไม่ใช้unitcodecpassแทนhostreadiness

### Catalog batch ผ่าน / ต่อ real CPU text-frame seam — เวลา11:21 เป็นต้นมา

exec27exit0:CPU29/29,noGLimports,native123/123,Thai`110718-017`diff0cursor45/11/background`110730-934`/mouse`110741-300`ผ่าน,fullCore89/89steps3957/4018pass61skip ไม่ลดgates/เพิ่มskip/no defaultchange

เพิ่มTextFrame(CRF1bodyในv2envelope):immutablefulluniforms/bg/fgตามroworderรวมcursorต้น/ท้าย,grayscale+BGRAatlases,explicitLE/nopointers/no padding,screen/grid/glyph/byte/atlasboundsและOOMcleanup PassedCPU33/33 แยกtext-onlyschema ไม่silentdropimages/customshaders

ต่อ`GenericRenderer.captureTextFrameLocked`:callerถือdraw_mutex,copyatlasภายใต้fontreadlockแล้วคืนownedbytes ไม่มีGPU/IPC/UIwaitหรือfileoutput เปิดencode/decodecheckผ่านOptionsเฉพาะcontrollednativeThaiTUIfixtureและatomiccheckedcounter UIตรวจcounterไม่จับdrawmutex ภาพ/sessionผู้ใช้ไม่ถูกcaptureโดยdefault Win32App/SurfaceและCoreSurfaceส่งflagแบบWindows/@hasDeclguard ระบบอื่นคงdefaultfalse

exec36กำลังnative+strictThai(ต้องCPUframechecked)/background/mouse→fullCorepost-seam Sourcesfreezeไม่แก้consumedfilesจนจบ **ก่อนclaimfixtureครบต้องเพิ่มfailurelatchด้วย** เพราะrenderer.Thread.drawFrameใช้log.warnเมื่อdrawerror และcounterเคยสำเร็จหนึ่งครั้งไม่พิสูจน์ทุกframeต่อมา ต้องตรวจทุกcontrolledsnapshotfailure ไม่ใช้warmup/thresholdskipแก้

### เตรียม GPU side (ยังไม่build/run / ตรวจสถานะเวลา11:39)

- `renderer/remote/TextGpuExecutor.zig`:new/unimported GPU-onlyexecutor ใช้legacyPipeline/Target/Buffer/Texture/layout,validateCPU+outputbytes+actualGLtexturelimitsก่อนGPUalloc,UNPACK/PACKalignment1สำหรับodd-widthatlas,checkedbind/drawทุกcallไม่ใช้RenderPass.stepที่catchreturn,readbackRGBA bottom-uppremul มีdefercleanupครบ per-frame ไม่ใช่performanceproof
- `src/win32_render_text_worker.zig`:new/unbuilt privateinheritedrequest/responsemaps+events,16-byteatomicpublicationprefix+v2header/session/generation/sequence/epoch,hello/text-frame/close,readonlyrequestmap,caps/outputbudget,ownedrequestcopy/recheckcommit,GLonlychild ไม่มีPTY/windowinput/fontshapingในworker ใช้WGLDevice.init(allocator,.{})/deinit(allocator)ตามAPIจริง
- ผ่านzig fmt --checkเท่านั้น ยังไม่มีnewbuildtarget/parentclient/remote-onlyhostmode/workerexecutionหรือexit/jobemptyproof ต้องทำต่อหลังexec36จบ sourcefreeze ไม่มีruntime/default/driverchangesจากสองไฟล์ใหม่

### Live CPU / GPU worker compile / transport ต่อ — เวลา11:49–11:58

exec36passednative123+Thai/background/mouse/fullCore3961/4022pass61skip89steps แต่firstreceiptglyphs0ยังไม่พอ จึงเพิ่มCPUfailurelatchและnonemptyglyphframecounter UIต้องทั้งglyph>0และfailures0 ไม่ใช้Thread.warnเป็นsuccess

เพิ่มadditivewindows-render-text-worker buildtarget exe`localterm-render-text-worker.exe` explicitGPU-onlygraph ไม่defaultinstall/ไม่hostgraph Workerexec45compilefailedเพราะentrymainหาย/Win32BOOLtypedwrapper แก้pubfnmainและCABIi32BOOLตามWindowsAPI exec48worker28/28/native123/123ผ่าน Thai`115720-090`glyphs1packet1323690bytes/noFailure+strictVTdiff0,background`115732-118`,mouse`115742-516`ผ่าน—all exit0/surfaces0 ยังไม่พิสูจน์workerวาดpixelsหรือGPU-freehost

เพิ่ม`render_worker_client.c/.h` CPUWin32transport:exe-relativepinnedchild,privateenvblockไม่SetParentEnv,explicitinheritedhandlelist/suspended→assignedkill-on-closejob→resume,dualmap/3events/atomicseq/recheckownedcopy,singleoutstanding,boundedwait/cancel/closeexit/jobempty/forcedcleanupแยกstatus ParentOpenต้องserializeกับotherinheritinglaunches—remoteDeviceinitควรอยู่ก่อนPTYspawn ไม่มีGL/userGUI/clipboardในlibrary MSVCcl C11W4/WXcompileผ่าน ไม่ใช่runtimeproof

เพิ่มCPU-only`remote/Client.zig`typedv2hello/capability/frame/closevalidator,request/replyownedbytes,status/fail-poison/cancel;`render_worker_client_check.zig`+buildtarget **exec51กำลังbuild/runจริง** positivehello/close6cycles(1explicitwarmup,5measuredhandlesdelta0),exit0+jobempty,negativecancelต้องไม่healthy,parentไม่มีGL/AMD modules ไม่ส่งtoycolorframeและไม่อ้างpixel/renderproof ผลยังpending

ถัดไปใช้Clientส่งrealcontrolledThaiCPUframeและเทียบworkerRGBAกับlegacyreference **หลังปล่อยdraw/fontlocksเท่านั้น** ต้องcaptureownedpacket/referenceระหว่างframeแล้วconsumeนอกlock Close/abortบนrendererexitนอกdrawlockด้วย Nativeproductionflagdefaultfalse ไม่มีsessiondump Hostremote-onlydependency/backendยังpending จึงยังไม่ปิดM1bหรือResourceGrowth

### Private client ผ่าน / real pixel parity batch active — เวลา12:03 เป็นต้นมา

exec51build/runexit0:GPUchildhello→closed→naturalexit0/jobempty6cycles(1explicitinitialwarmup+5measured),handlesทุกmeasuredรอบdelta0,negativecancelไม่healthyและcleanup/jobemptyจริง,parentไม่มีopengl32/atio6axx/amdihk64 ไม่ใช่thread/GDI/performance/terminal-hostqualification และยังไม่ส่งdrawpacketในcheckนี้

เพิ่มTextParitycontrolledcomponentต่อactualGenericRenderer:ownedpacketกับlegacyTarget.readPixelsAlloc referenceถูกcaptureภายใต้drawlockก่อนframecomplete;drawFrameเรียกClient.processหลังlockscopeสิ้นสุด รับRGBAownedcopyและexactmemcmpทุกbyte ไม่ตั้งtolerance/fallback Firstnonemptyglyphframechecks+allfailuresatomiclatch UIต้องchecks>0/failures0 ThreadExitปิดclientก่อนเข้าdrawlock/resourcecleanup ต้องmatchingclosed+exit0+jobempty/forced0;closeerrorlog.errทำhelperfail

เปิดเฉพาะLOCALTERM_GPU_TEXT_FRAME_CHECK+controlledstrictThaiTUI ผ่านruntime-smoke.ps1 -GpuTextFrameCheck -ThaiTuiSmoke -RequireThaiModel flagdefaultfalse/save-restoreenv/removeจากPTYenv,helperต้องทั้งexactpixelparityและhealthyclose receipts ไม่เขียนsnapshot/sessionดิสก์ SharedDepswin32เพิ่มCtransport(noGLในC) LegacyhostยังGLอยู่จึงไม่อ้างแก้parentisolationแล้ว

multifilepatchครั้งแรกหยุดที่Surface.envanchor ตรวจทุกhunkที่applyแล้วก่อนเติมWin32Surface/App/SharedDeps/PShelperที่ขาด **exec56กำลังnativecompile→GPUparityfixture→baselineThai/background/mouse** Sourcesfreezeไม่แก้consumedfiles จนได้ผล ยังไม่อ้างworkerpixelsผ่าน M1bremote-onlyhostselection/buildgraphยังต้องทำต่อ

### Real worker pixels ผ่าน / qualified summary+Core active — เวลา12:12 เป็นต้นมา

exec56exit0native123/123 GPUfixture`121145-189`CPUframe→privateGPUworkerRGBAexactdifferent_bytes0,closedACK/exit0/jobempty/forced0 frames25/surfaces0;baselineThai`121157-388`/background`121207-821`/mouse`121218-206`ผ่าน Driverยังอยู่legacyparentจึงไม่ใช่hostisolationหรือResourceGrowthqualification

receiptแรกglyphs1อาจเป็นcursor จึงเพิ่มmax_glyphs/maxforegroundsummaryจาก**ทุกsuccessfulmemcmp**;Appต้องmax>1/helperต้องcompletedchecks+failures0+healthyclose และlatchedfailureทุกframe ไม่ผ่อนpixelthreshold **exec60native→qualifiedGPUfixture→fullCoreunfilteredpost-parityกำลังรัน** sourcefreeze

ระหว่างfreezeเตรียมnew/unimported`CpuExportedFrame.zig`(CPU-onlymemoryownership+Windowsdmabufnoreturn) standalone1/1pass,และ`remote/Session.zig`(GPU-freeClient→ownedRGBAexport,resizeepoch,close/abort)fmtผ่านยังunwired/ไม่runtime-tested ไม่แก้OpenGLaliasหรือsourceที่Coreกำลังconsume

Next remote-onlyhost:เพิ่มdefault-falseWindowsbuildoption/selectorจริงและตัดhostopengl32/GLAD graph;Genericใช้CPUdata/shapingเดิมแต่conditionalizeGPU-onlyFrameState/SwapChain/shadersและdraw/init/resourcehooks ไม่ปล่อยdummyGPUmethodreturnsuccess;surfaceAPI.initเปิดprivateSessionก่อนPTYlaunch(serializeinheritlaunch),captureunderlock→RPC/publishOwnedFrameafterunlock,notifyUIแบบไม่foreverwait ชัดเจนว่าunsupportedimages/overlay/customshadersต้องfailไม่silentdrop Gateต่อไปdumpbin+runtimeparentnoGL/AMD+realrender/paint+ownedworkerexit/jobempty+strictlifecycleก่อนpromote

### Qualified parity/Core ผ่าน / first remote-onlyhost build active — หลัง12:31

exec60exit0native123/123,qualifiedThai`121750-201`checks29/maxglyphs655/failures0/exactmemcmp+closedACKexit0jobemptyforced0,fullCore89/89steps3961/4022pass61skip ไม่ใช่Coreหลังhosteditsด้านล่าง

เพิ่ม`-Dwindows-remote-renderer=true`defaultfalse/configcopy/options/selector เฉพาะWin32+OpenGLtarget;hostตัดGLAD C/opengl32/ImGuiOpenGLbackend แต่workerexplicitGLgraphแยกและauto-installในprefixhost ใหม่`renderer/Remote.zig`ใช้CPUData+Session+CpuExportedFrame,appDeviceเป็นCPUallocationไม่WGL,SessionเปิดAPI.initหลังCPUprepก่อนPTYเริ่ม,LocalGPUtexturedeinitpanicfailclosed(ไม่มีcreate API/ไม่มีGPUACKปลอม),initrejectbackground/customshader/legacyparityflag

GenericconditionalizeSwapChain/FrameState/CustomShaderStateเป็นvoidในremote,releaseGPUbranchตัดcomptime,drawRemoteFramecaptureownedunderlock→SessionRPC/pushFrame/notifyหลังunlock Cpucheckedcounters+errorlatch/log.err ไม่ใช้Frame.completeที่releaseGPUsemaphoreหรือmailboxforever;UIremoteatomicpending+directwindow.wakeโดยไม่window_mutex(ตัวHWND/generationยังaliveจนrendererjoin),tickpresenterเดิมรับownedRGBA,threadExitcloseอยู่นอกdrawlockที่APIhookท้ายfunc Runtimeverifyparentไม่มี3GL/AMDmodulesก่อน/หลังframe+ตอนclose

**exec78 firstopt-inhostcompile+dumpbinimportsกำลังรัน** prefix`zig-out/render-worker-host` แยกจากM1/accepted62 ยังไม่มีcompile/runtimequalification Sourcesfreeze App-localassetsเดิมที่ต้องdeploypairคือ`conpty.dll`119608bytes/`OpenConsole.exe`1089376bytesจากM1bin ไม่ใช้systemfallback HostchangeConfig feature rejection/health/failure/cancel/resize/resourcegatesยังต้องทวน ไม่claimM1bหรือResourceGrowthเสร็จ

### Opt-inhost compile/imports ผ่าน / first runtime active — เวลา12:39

exec78exit0:125/125steps remotehost+helper buildผ่าน dumpbinhostไม่พบopengl32.dll/wglCreateContext/wglMakeCurrent/gladLoad ไม่ใช่runtimeDLL/paint/lifecycleproof

exec80copyเฉพาะapprovedM1bin`conpty.dll`+`OpenConsole.exe`ไปhostbin ถ้ามีไฟล์เดิมhashไม่ตรงfailไม่ทับ ตรวจSHA256source/destinationทั้งคู่ แล้วเริ่มcontrolledstrictThaiTUIจริงoffscreennoactivateด้วยapp-localprovider ต้องhelperผ่านและมีremotehostrealframe/noGLAMDparent+healthyworkerclose receipts เพิ่มหลังจบ Sources/runtimehelperfreezeขณะทวน ผลยังpending ไม่claimResourceGrowth/defaultพร้อม

### Positivehost/defaultregressionผ่าน / M3negativeactive — เวลา13:09 เป็นต้นมา

exec80passedremoteThai33render/paint+VTdiff0+parentnoGLAMD+closeexit0jobemptyforced0;exec82background/mouse/strictlifecycle20afterwarmupผ่าน123→123handles/GDI2→2/USER1→1/threads4→1/21workerhealthyclose ต่อremotechangeConfigrejectunsupportedก่อนmutate แล้วexec88remote125/125/Thai+**repeatstrictlifecycle125040-182ตัวเลขเท่าเดิม**,legacy123/123+Thai125455/background125507/mouse125517,fullCorepost-host3961/4022pass61skip89stepsทุกstageexit0 ไม่อ้างlegacyleakหาย

ตรวจbackgroundBMPviewerunsupported→convertPNGไม่มีGUI ดูจริงและsample8pixelsเทียบlegacy121207:default12,12,12/RGB30,30,30/index29,31,33/RGB18,52,86/reset+ELตรง ไม่ใช้parserreceiptแทนpixels

M3เพิ่ม`render_worker_client_check.c`เฉพาะchecktarget includecommonclientและtest-onlykillowned:verifyIsProcessInJob/GetProcessId!=self/TerminateProcessownhandle77/boundedwait ไม่มีPIDinput/ค้นหาkillภายนอก ไม่มีfaultsymbolในproductionCvariant ZigcheckrawABIทดสอบ5badheadersparentreject13แล้วvalidclose,submitก่อนhello+unsupportedcreate_bufferต้องworkerexit1/ERROR_PROCESS_ABORTEDไม่timeoutและไม่มีhealthyclose;killowned77ต้องdetect/reapjobempty ทุกcasecompareparenthandlesbaseline/noGPU **exec92build/run active** Sourcesfreeze ไม่อ้างnegativeผ่านก่อนผล;hang/lateframe/resizeDPI/resourceimagesยังpending

### M3 negative ผ่าน / deterministic idle timeout active — เวลา13:14 เป็นต้นมา

exec92build/runexit0:5bad/replayedheadersreject13แล้วvalidclose,submitก่อนhello+unsupportedopcodeworkerexit1/process-abortedไม่ACK,ownedkill77detectedไม่healthy,ทุกcasejobempty/parenthandledelta0/noGPUparent รวมpositive6cycles/cancelเดิมผ่าน ไม่ใช่GPUbusyhang/UIresizeproof

เพิ่มCclientopaqueinternalprimary_thread_idจากPROCESS_INFORMATION(ไม่ใช่PIDinput/faultAPI) เพื่อcheckvariantOpenThreadเฉพาะownedprimarythread/GetProcessIdOfThreadตรงownprocess/IsInJob หลังhelloก่อนGPUdraw SuspendThreadต้องprevious0,ไม่พักdriverthreads ตัวnormalhostยังไม่มีpause/kill APIs Test50msRPCต้องERROR_TIMEOUT/received0/ไม่เกิน2000msoutertestbudget แล้วResumeOwnedThreadและ**รอcommittedlateclosedจริง**ก่อนยืนยันrw_finishยังreject clientที่poisoned จากนั้นabort/reapjobempty/handledelta0 ทั้งหมด **exec94build/run active** ยังไม่claimtimeoutผ่านก่อนผล

Next M3:actualterminalresize/DPI/minimize และ staleviewportfence ต้องเพิ่มparentviewportgenerationที่captureunderlock/echoส่งworker แล้วcheckcurrentgeneration/displayrealizedก่อนpushFrameหลังRPC (ปัจจุบันClientตรวจepochของsnapshotได้แต่ยังไม่มีparentcurrent-generationrecheckระหว่างUIresize) ไม่ใช้dimensionsอย่างเดียวเพราะA→B→Aได้ Future testsต้องทั้งCPUfenceunitและrealoffscreenwindowresize ไม่ใช้toycolorsแทน

### Idle timeout ผ่าน / parent viewport fence ลงแล้ว integration active — หลัง13:18

exec94build/runexit0:budget50msobserved47ms(GetTickCountgranularity),ERROR_TIMEOUT/received0,Resumeเฉพาะownedprimarythread→actualcommittedlateclosedพบจริงแต่rw_finishยังreject,abort/process/jobempty/parenthandledelta0/noGPUparent ผ่านnegativeเดิมทั้งหมด ไม่อ้างGPUbusyhangหรือUIhangqualification

เพิ่ม`ViewportEpoch.zig`pureCPUcaller-held-drawlock acceptsเฉพาะcurrentnonzero+realized/advancecheckednoreuse ทดสอบ3/3current-hidden-zero,A→B→A,overflowผ่าน(ครั้งแรกPSunquoted-femit-binแยก.exe แก้quoteแล้วรันจริง ไม่ใช่testcodefailure)

Generic remoteviewportepochcaptureพร้อมownedpacketunderlock→Remote/Sessionส่งepochนี้ไปClientแทนdimensioncounter→replyvalidateเดิม→reacquire drawlockcheckcurrentepoch/realizedก่อนpushFrame mismatchfreeownedRGBA+staledropcounter;resize/realize/unrealizeadvanceepochและdropqueuedlatestCPUframeด้วย ไม่ถือdraw/font/UIlocksระหว่างRPC/notify สะพานSessionrejectepochย้อนหลัง/epochเดิมแต่dimensionsเปลี่ยน ภาพหลังA→B→Aไม่คืนชีพตามขนาด

**exec101remotebuild→strictThai→strictlifecycle21healthyworkeractive** ยังไม่claimintegrationผ่าน sourcefreeze Realoffscreenwindowresize/DPI/minimizefixtureถัดไป ยังไม่ใช้CPUunitsแทนUIproof Nativewindowมีtimer1fixtureSetWindowPos/DPI/minimizeอยู่แล้วแต่terminalmodeยังไม่ได้เปิดseriesนั้น ต้องทำcontrolledownedterminaltestแยก ไม่foreground/OSclipboard/systemsettings

### Viewportfencebaselineผ่าน / realownedwindowfixture active — หลัง13:25

exec101exit0native125/125,Thai132423-732diff0/35paint+healthyclose,strictlifecycle132436-334handles123→123/GDI2→2/USER1→1/threads4→1/21healthyworkerผ่าน ไม่ใช่realresizeproof

เพิ่มstandalone`-ViewportSmoke`/LOCALTERM_VIEWPORT_SMOKEเฉพาะremoteterminalsmoke ไม่mixThai/mouse/bg/GPUparity/input/lifecycle Envsave-restore+stripPTY ใช้nativeownedwindowtimer1แต่1วินาที6stepเฉพาะfixture:exactclient1117x709(ปรับจากnonclientrect,NOMOVE/NOZORDER/NOACTIVATEรักษาoffscreen)→minimize→restorenoactivate→syntheticWM_DPICHANGED144→กลับoriginalclientA→close ค่าเดิมwindow-only5step100ms/gatesไม่เปลี่ยน

Surface.presentfixtureต้องmemoryW/H==currentSurface.sizeทุกframe,Appเก็บdistinctpresentationpairsต้อง>=3และกลับfirstpairจริง,windowต้อง6ticks/>=3resize+DPIdispatch+redtext/paintตามhelperเดิม+healthyworkerclose SyntheticDPIเฉพาะpayload/lifetimeไม่ใช่physicalmixedmonitor/humanvisualacceptance Overflowfenceclearqueuedก่อนadvanceแม้fail

patchรอบแรกถูกtoolปฏิเสธเพราะFileOpsซ้ำ ตรวจทุกไฟล์ยืนยันไม่applyก่อนรวมhunksใหม่ครบทั้ง6ไฟล์ Zigfmt/PSparseผ่าน **exec107nativebuild→realviewportfixture→strictThaibaselineactive** Sourcesfreeze ผลยังpendingต้องไม่อ้างresizeผ่านจากการเขียนfixture

### Realwindowresizeผ่าน / deterministicstalerenderedframe active — หลัง13:34

exec107exit0native125,viewport133350-235จริง20render/paint/current-sizeทุกpresent 1034x661→1117x709→884x561→1034x661,6stepsminimize/restore/syntheticDPI144+returnedoriginal+healthyexit0jobemptyforced0+surfaces0 ต่อstrictThai133401-030diff0/35paintsผ่าน ไม่ใช่physicalmixedDPI/humanacceptance

ทำviewportepochatomicobservation(captureacquire/advancerelease ยังdrawlockป้องกันstatecapture/commit)เพื่อcontrolledtestรอepochโดยไม่ถือdrawmutex หลังRPCรับ**realownedRGBAครบแล้ว**หน่วงreplyที่2เฉพาะ-ViewportSmokeไม่เกิน5sจนUIrealresizeadvanceepoch แล้วปล่อยเข้าGenericcurrent-generationcheckซึ่งต้องfree/discardสักframe Appต้องatomicstaledrops>0/1117x709ต้องpresentจริง/กลับA และhelperต้องdelayedreceipt+actualdrop+current-size+closedครบ ไม่หน่วงchild/driverthread/ไม่แก้productionbudget/APIไม่มีwirepointer

**exec110atomicunits→native→deterministicviewport2รอบ→strictThai→fullCorepost-M3active** Sourcefreeze ยังไม่claimdelayedframeproofก่อนผล ชุดนี้ยังไม่ครอบคลุมGPUbusyhang,fullresource/imageupload,autorestartหรือperformancequalification

### Deterministic fixture เปิดเผย UI/mailbox gap / fix กำลังทวน — เวลา13:42

exec110 **failedจริง**:atomicCPU3/3/native125ผ่าน แต่viewport134208-970 timeoutViewportFixtureResizeTimeout แล้วStaleFrameNotRejected/PresentationCoverageFailed,workerยังปิดexit0jobemptyforced0 ไม่มีการนับfailเป็นผ่าน ไม่มีThai/Corestageรันหลังจากนั้น

SourceยืนยันCore.sizeCallback→Core.resizeส่งrenderer.resizeผ่านmailbox,Thread.zig404ค่อยsetScreenSize:epochเดิมจึงadvanceบนrendererthread ไม่ใช่ตอนUIรับresize การรอepochบนrendererthreadตัวเดิมไม่ก้าวและยังเผยช่องว่างin-flightimageระหว่างUIsizeเปลี่ยนกับrendererdrainmailbox ไม่ใช่ข้ออ้างwaivefixture

แก้เฉพาะparentWin32Surface.resize/setDpiเมื่อchanged+initializedในremote flag:callGeneric.invalidateRemoteViewportFromUIก่อนCorecallback (Core/PTY/inputalgorithmไม่แก้) methodlockdrawสั้นๆ→dropqueued/advanceatomicepoch→storetargetscreen+pendingถ้าgeometryยังไม่applyหรือfontchange แล้วunlockก่อนCoremailbox/UIงานต่อ Rendercapture/commitปฏิเสธpendingด้วย Thread.setScreenSizeยังinvalidate+เทียบappliedscreenกับlatestUItargetก่อนclearpending กันqueuedoldsizeแซงUIlatest;same-sizecallbackไม่สร้างpendingที่Coreจะไม่ส่งต่อ FontDPIchangedCoreบังคับresizeตามsource3796–3798

**exec113remotebuild→deterministicviewport2รอบ→Thai→legacybuild/window-only+Thai→fullCoreactive** Sourcesfreeze ยังไม่claimfixผ่าน ไม่ผ่อนgate/increase5sfixturebudget/เปลี่ยนwarmup/defaultหรือdriver LastfullCoreยังexec88ก่อนM3 ไม่ใช่ชุด110

### UIepochgapแก้ผ่าน / failed-sessioncleanup active — เวลา14:06 เป็นต้นมา

exec113exit0 remote125,deterministicviewport134810-228+รอบถัดไปผ่านactualstaleRGBA discard/current-size4pairs/odd1117x709/returnedA/healthyclose+surfaces0,remoteThai134826diff0,legacy123/window135209(window-only20cyclehandles125→125GDI2→2USER1→1)+Thai135223diff0,**latestCore3964/4025pass61skip89steps** (เพิ่มviewportCPU3tests) ไม่อ้างwindow-onlyเป็นterminalleakproof

M3ต่อproductionSession:poisonedlatch,render/closeerrorerrdeferfail→abort/reapownedchildทันทีนอกdraw/font/UIlocks,poisonedrender/closeต้องWorkerSessionPoisoned/noIPCใหม่/ไม่มีhealthyACK ภายนอกRemote.render/Genericdrawcatchก็failsessionครอบsnapshotencode/notifyfailureและhealthatomicunhealthy+instantmailbox(ไม่frameCompletedซึ่งreleaseGPU semaphore/foreverpush) ไม่มีauto-relaunch/fallbackparentGL

Testcheck executableเพิ่มproductionSessionจริง2case invalidemptyframeและownedworkerexit77 duringclose ต้องhandleNULL/processExited/jobEmpty/forced1/noACK **ก่อนcallerabort** แล้วเรียกrender/closeซ้ำต้องpoisonedและsequenceไม่เพิ่ม/handledelta0 รวมprotocol/timeout/lateclosed/cancelpositiveเดิม **exec117checkbuild/run→remote-build→viewport/Thai/strictlifecycleactive** ยังไม่claimcleanuptestsหรือUIhealthnotificationruntimeผ่านก่อนผล ไม่ใช้sessioncomponentแทนnativecrash/hang/restartqualification M3resource/images/restart/performanceยังpending

### Sessionfailcleanupผ่าน / worker shader+atlas cache active — เวลา14:14 เป็นต้นมา

exec117exit0check30/30+productionSessioninvalidframe/ownedexit77autoabortก่อนcallercleanup/poisonlatched/noIPC/handles0+protocol/cancel/50msidle-timeoutactual47ms/lateclosedทั้งหมดผ่าน remote125/viewport141255(staledrop2,current4pairs)/Thai141303diff0/lifecycle141314strict123→123handles/GDI2→2/USER1→1/threads4→1/21healthyworkerผ่าน UIhealthunhealthybranchcompiledแต่ยังไม่อ้างruntimeUIcrash-injectionproof

พบExecutorเดิมสร้าง5builtinprograms+สองatlasesทุกframe จึงเพิ่มcontext-ownedExecutorที่workerสร้างหนึ่งตัวหลังGLload/deinitก่อนGLunload/contextrelease ValidateCPU/outputbudget/driverlimitsก่อนGPUallocationเหมือนเดิม programsetlazyinitครั้งแรก;สองatlasแยกgray/BGRA:ขนาดเดิมreplaceRegionfullupload ขนาดเปลี่ยนcreateใหม่สำเร็จก่อนdeleteold ไม่มีresourceACKหรือwireGLuintเพิ่ม FrameACKยังหลังdraw/finish/readbackvalid ตัวTarget/3buffersยังperframe ไม่อ้างว่าincrementalresourcewire/image/performanceครบ

GPU-only`windows-render-text-cache-check`ใหม่ ownhiddenWGLcontext ไม่ใช่noGPUparent:invalidframeต้องallocated0,5realtextpacketsพร้อมvisiblewhiteglyph/pixel-identicalข้ามatlas1/3/5oddresize/reuse,programsets1/atlascreates5/updates5/completed5,deinitต้องownednull+glIsTexturecurrentIDsfalse ไม่มีวาดquadrantแทนterminalproof **exec124cachebuild/run+newworker→existinglegacybinaryexactThaiRGBAparity→remotebuild/viewport/Thai/strictlifecycleactive** Sourcesfreeze ไม่claimcacheผ่านหรือperformanceเร็วขึ้นก่อนผล

### Cachefixturecursorผิด / แก้แล้วกำลังทวนโดยไม่ลดglyphassertion — เวลา14:22

exec124build31/31ผ่านแต่GPUcomponentfailGlyphNotDrawn จึงไม่มีlegacyparity/remote/Coreตามหลัง Sourcecell_text.v.glslยืนยันzeroedcursor_pos0,0overrideforegroundglyph0,0ด้วยzeroedtransparentcursor_color(ท้ายshader) ไม่ใช่เหตุให้ลดvisibleglyphthresholdหรือแก้legacyshader

แก้fixtureเท่านั้นเป็นhidden-cursoru16maxเหมือนrendererจริง แล้วเพิ่มsame-sizeatlascontentupdate/revert:7frames ทุกnormalframeต้องwhiteglyphvisible+pixelsตรงreference,frame6mask0ต้องglyphหายและpixelsเปลี่ยน,frame7mask255ต้องกลับreference shaderSets1/atlasCreates5/updates9/completed7/invalidallocated0/GLIsTexturedeleted **exec128cachecheck→legacyexactThaiRGBA→remotebuild/viewport/Thai/strictlifecycleactive** Sourcefreeze ไม่claimผ่านหรือspeedupก่อนผล Cachelogic/legacyshaderไม่เปลี่ยนจาก124

### Cacheผ่านทั้งcomponent/terminalparity / rendered-resourcefailure active — เวลา14:26

exec128exit0cache31/31+7realGPUframes/visible+maskmutationrevert/counters1,5,9/GLtexturedeleteผ่าน,legacy-workerexactRGBA **16checks/max655glyph/failures0**(ไม่สวมจำนวน29ของรอบเก่า),remoteviewport142457staledrop2/current4pairs/Thai142503diff0/lifecycle142514handles123→123/GDI2→2/USER1→1/threads4→1/21healthyworkersผ่าน ไม่ใช่performanceหรือfullimagesqualification

เสริมclient-checkproductionSession4cases:invalidCPUframe/idlekill77/kill77หลัง2realvisible-glyphframes/cancelหลัง2realvisible-glyphframes (cachedshader+atlasesต้องมีแล้ว) ต้องauto-reapก่อนcallerabort/poison/noIPCต่อ/noACK/handlesเท่าก่อนทุกcaseและCPUparentnoGLAMD **exec131build→runสองรอบactive** Sourcefreezeยังไม่claimpassed/gpu-busyhang/globaldriverVRAMzero;ownedkillหลังfinishไม่ใช่hangmid-draw

ส่งread-onlyagentสำรวจinlineKittyimageCPUdata/upload/draw-order/ownershipboundaryสำหรับM3ถัดไป ไม่edit/build/GUI/clipboard/system/branch/commit/push Parentdefault/legacy/accepted62คงเดิม

### Rendered-resource kill/cancelผ่าน / coloratlascheck active — เวลา14:29

exec13130/30+run1/run2exit0:kill77/cancelหลัง2realvisible-glyphGPUframesและcachedresources auto-reap/jobempty/poison/noIPC/noACK/per-casehandles0/noGLAMDparentผ่าน timeout50msobserved47/62msตามWindowsgranularity ไม่อ้างGPUbusyhangหรือglobalVRAMmeasurement

agenttask_2ปฏิเสธงานเพราะtemplateจำกัดOlufy ไม่ได้สำรวจ/เปลี่ยนไฟล์;ใช้forktask_3read-onlyGhosttyscopeแทน ยังpendingreport ไม่อ้างได้mapแล้ว

เสริมGPU-onlycachecheckจาก7เป็น10frames:หลังgraymaskhide/restoreให้color-glyphใช้BGRAatlasopaqueแดง→เขียว→ขาว ต้องได้RGBred/green/กลับreferenceจริง ใช้textureเดิม/programset1/atlascreates5/updates15/GLdeleted **exec132build/runสองรอบactive** Sourcefreeze ไม่มีproductionshader/worker/parentruntimeเปลี่ยนจาก128 Colorfontatlasไม่ใช่KittyimageTex2Dsupport

### Colorcache/Cstrictผ่าน / candidateinline-imagecodec — หลัง14:31

exec13228steps+สองrunsผ่าน10realGPUframes/graymask+BGRAred-green-white/programSets1/atlasCreates5/updates15/GLdelete;MSVCC11/W4/WXproductionCและtest-onlyCwrapperผ่าน+scopeddiffcheckผ่าน

forktask_3read-onlymapสำเร็จ:generickittyUpdate1557/upload1992/captureguard3823;image.zig pendinggeneration696–786/placement790–818/CPUownedpending866–913/normalize936–990/upload1072–1108. Kittycontentgenerationกับplacementdirtyแยกกัน,Image.renderDataเลือกanimationframe,draworderต้องbg→kittybelowbg→cellbg→kittybelowtext→text→kittyabove;RGBA sRGBA2D+linearfilterต่างจากrectanglefontatlas ห้ามparentupload/ปลอม.ready/ทำuploadACKหายเพราะstaleviewportdrop Background/customshader/overlay/clipboardfilepasteคนละscope

เริ่ม`ImageResource.zig` **candidateCPU-onlyยังไม่importต่อwire/runtime**:IMG1fixed32B LEheader(id,width,height,pixelLen,u64generation),straightRGBA8ownedcopy/borroweddecode;dimension<=32768,total<=64MiB,checkedu64budget/length/id+generationก่อนallocate,decodeexactversion/truncation/lengthguards ID0ถูกCorekittyassignก่อนstorageตามgraphics_exec1036/graphics_storage259 ไม่มีGLhandles/pointers serialize

StandaloneDebug4/4ผ่านownership/high-u64LE/truncated-version-length-identity/overflow-budget/allallocationfailures ไม่รวมในCorecount **exec136ReleaseSafe4→fullCorecurrentcheckpointactive** guardinlineimagesยังไม่ปลด/workeruploaddrawยังไม่เชื่อม/placements+aggregateframebudgetยังpending ไม่claimKittysupportจากcodeccomponent

### Pre-imagecheckpointผ่าน / placementcandidateกำลังทวน — เวลา14:50

exec136exit0ImageResourceReleaseSafe4/4และCore89/89steps3964/4025pass61skipผ่าน มีบรรทัดfailed-commandหลังThaiinkdiagnostic ตรวจlocalZig0.16sourceBuild/Step/Run2721เก็บstderrเป็นdiagnostic,compiler/build_runner1381พิมพ์messages**no matter result**แล้ว1515พิมพ์result_failed_commandตามverbosecontext แม้step.success จึงไม่ใช่เหตุอ้างtestfail/ลบdiagnostics;run-testขั้นจริงระบุ3964pass61skipและexit0ชัด

เพิ่มunwired`ImagePlacement.zig`fixed56B LE:Id+gen64(refresource) / signedx,y,z / destW,H / cell offsets / sourcecrop;gen/idต้องตรงresolvedresource,cropnonzeroและu64additionไม่wrap,dimension/dest/offsetcaps,decodeexactlength ไม่ใช้nativepadding/pointers ไม่clampnegativex/yทิ้งและไม่เปลี่ยนz bands Candidateaggregateยังต้องตรวจactualcelloffsets/counts/totalbudget/resource lookup+sort orderก่อนเปิดwire **exec143Debug/ReleaseSafeunitsactive** (includesreferencedImageResource testsตามrunner) ไม่มีruntime/shader/inlineguardเปลี่ยน

### Placement8/8ผ่าน / aggregatecandidateกำลังทวน — เวลา14:55

exec143Debug+ReleaseSafe8/8ทั้งคู่ (4placement+4resource)ผ่าน ไม่บวกเป็นCore8ใหม่เพราะยังunwired

เพิ่มCPU-onlyImageSnapshotIMS1candidateheader32+u32offsettable+IMG1records+56Bplacements:sorteduniqueimageIDsกับz/ID-orderedplacementsแยก,checkedcounts/totalimage-snapshotbudget/u64ก่อนsingleallocation,cellsizefinitepositive+celloffset<=cellsize,resourceidentity/gen/cropครบ;offsettablecanonicalเริ่ม0/monotonic/noholesตามexactresource-length,lookupbinaryไม่copyPixel Temp Resource.encodeIntoใหม่รับdisjointdestination ไม่allocateภาพซ้ำ Emptybundleแทนremove-allได้

**exec144Debug/ReleaseSafeaggregate+referencedunitsactive** ตรวจvalidlookup/negativeclip/order/missing-stale-duplicate/crop-cell/count/offset/truncated/budget/emptydelete/allallocationfailure Sourcefreeze ไม่มีtextframewire/workerupload/GPUimagecache/drawband/ACKintegration และoutertext+imagecombinedbudgetยังpending จึงยังไม่ปลดinlineimageguard/default/accepted62หรือclaimKittysupport

### Aggregate13/13ผ่าน / outercandidateและmodule-root correction — เวลา14:59 เป็นต้นมา

exec144Debug/ReleaseSafe13/13ผ่าน (5aggregate+4resource+4placement) เพิ่มunwiredImageFrameKIB1header24ซ้อนTextFrame+ImageSnapshot:header+สองcomponentsต้องอยู่ในpayloadbudgetเดียวก่อนcopy/allocate,cell_sizeตรงtextuniforms,exactlength/version/flags0 ไม่มีpeernegotiationหรือworkerselectorเปิดใช้

รันImageFrameตรงจากremoteโฟลเดอร์compilefailoutside-module-path(GlslData) ก่อนtests จึงแก้entrypointใหม่`src/render_worker_image_codec_tests.zig` ให้moduleRootsrcถูกต้อง ไม่แก้importguard/codecเพื่อหลบ compiler **exec146Debug/ReleaseSafecorrect-root suiteactive** ผลก่อนหน้าไม่ใช่unitpass/ไม่รันReleaseSafe Sourcefreeze ยังไม่runtime/Kittyupload/drawsupport

### CPUcombined35/35ผ่าน / GPUimagecachecandidate active — หลัง15:03

exec146correctsrc-rootDebug/ReleaseSafe35/35ทั้งคู่ผ่าน(รวมprotocol/shaderpayload/text/imagecomponentrefs ไม่ใช่Corecountเพิ่ม35)

เพิ่มworker-onlycandidateImageGpuCache/hiddenGPUcomponenttarget`windows-render-image-cache-check` ยังไม่importในworkerหรือparent.SyncรับfullImageSnapshotbytes/decodeก่อนGLallocation,querydriverlimit/preflightallIDs+gen+dims,noncryptoWyhashfingerprintตรวจsamegenแต่bytesต่าง(ไม่authentication),reserveCPUmap(old+incoming)+removalidsก่อนGPUcreate,genใหม่createก่อนdeleteold,genเก่าปฏิเสธ,resourceที่ไม่มีในfullsnapshotถูกevict,emptyclearall และcontext-owneddeinit callerต้องfatalcloseเมื่อsyncerrorเพราะlateGLfailureอาจpartialupdate ไม่มีACKส่งจากcache

TextureoptsตรงlegacyOpenGL.imageTextureOptions:straightRGBA input/sRGBA2D/linearfilter/clamp. ComponentGetTexImageexactRGBAตรวจred→green/resizeblue+white,ID/genreuse,changed-contentrejectไม่mutate,stale-genreject,oldGLIsTexturefalse,removeID/empty/IDfreshreuse/deinit **exec148build→runสองรอบactive** Sourcefreeze ยังไม่มีimage drawbands/IPC/parentadapter/terminalKittyparity ไม่ใช้uploadreadbackแทนrenderproof

15:09 correction:exec148compilefail25/28ตรงArrayListmissingitems ไม่มีGPUcaseรัน แก้initializer`.empty`ตามZig0.16 ไม่ลดgates **exec149build/run2active** ยังไม่claimuploadcacheผ่าน

15:11 exec14928/28+run1/run2ผ่านactualGPUresourceupload/readback/reuse/generationreplace/resize/stale+changedcontentreject/delete/IDreuse/GLcleanup

Candidatecompositingเพิ่มExecutor.image_cacheและrenderImageFrame→ImageFrame.decode→renderDecoded(input,images) oldrender(rawtext)ยังTextFrame.decodeก่อนentryเดียวกัน;drawImageBandsตรงlegacythreshold `<minInt(i32)/2`, `<0`, `>=0` ระหว่างglobalBG/cellBG/text,vertexdataImageชนิดCPUsharedไม่serializepadding,bind2Dtextureunit0+premultblend/allGLerrorspropagate.Genที่placementอ้างต้องมีcacheตรง ทุกempty/plaintextsnapshotลบimagesresource ไม่ปลอมparentready

**exec151build image-frame-check+text-cache-check+rawtextworker→imagecomposite10framesสองรอบ→textcache10frames→transportfailure/cancel/kill→legacyThaiexactRGBAactive** NewGPUcomponentcountsred/whiteเชิงตัวเลขที่zmin/bgLimit-1/bgLimit/-1/0/1,placement-only6framescachecreated1,replacedcrop2x1greennegativeclip8pixels,empty/plaincleanup,programset1/completed10 Sourcefreeze ยังไม่มีworkerimagewireselector/peernegotiation/parentadapter/actualterminalKittylegacyparity ไม่ใช้syntheticGPUcomponentแทนacceptance

15:17 exec151exit0/34steps/composite10frames2runs/textcache10/transportnegativeผ่าน legacy151651oldbinaryexactRGBA30checks655glyphfail0,healthyclose+surfaces0

OptionalimageIPCเพิ่มแบบbackcompat:Protocolv2headerเดิม+newkind17submit_image_frameต้องepoch>0;emptyhelloเดิมตอบ16BcapsbodyCRF1schema1/flags1เป๊ะ ส่วน4BrequestedLEflags3 opt-inตอบflags3(รู้จักเฉพาะ1/3),Client.Options.inline_imagesdefaultfalse/clientเก่าทำงานเดิม ไม่แอบadvertise3ให้emptyhello Kind17workerต้องready+image_modeถึงdecodeKIB1/wholebudgetและdrawผ่านCandidate ใช้frame_readyเดิมกับwidth/height/stride/format16B+premulbottomupRGBA ไม่ACKก่อนrenderfinish/readback

Client.renderImageFrame non-optinต้องrejectก่อนdecode/consumeSeq,explicitoptinClientเท่านั้นส่งkind17;replymetadata/epoch/session/sequence/outputbudgetเหมือนrendertext NewCPUtesthello/capsbits/epoch plusCcheckplainno-send/rawtexthellokind17rejectไม่healthy/optin2imageframesgen1red→gen2greenexpected16pixels/noGLparent/healthyclose/handles0 **exec154CPUdebug-safe/check2runs/oldLegacybinaryparity/remotedefaultviewportThai21workerlifeactive** ยังไม่ParentSessionimageAPI/CPUimageadapter/guardเปิด/realterminalKittyparity Sourcefreeze

15:28 exec154ผ่านCPU36/36Debug/ReleaseSafe/check30steps+2runs;oldlegacy152308exact31checks655glyphfail0;remote125steps/viewport152713staledrop2และ4sizes/Thai152721diff0/lifecycle152731handles123→123/GDI2→2/USER1→1/threads4→1/21healthyworkers

15:33 exec156Session.renderImageFrame+commonuseViewportกับtextผ่าน30steps+2runs:หลัง2actualRGBAred-green16pixels/frameในแต่ละSessionจึงkill77/cancel/localstaleviewport(epochไม่consumeSeq)/peerstaleimagegen(workerexit1/1067/noACK),ต้องautoreapก่อนcallerabort+poison/noIPCต่อ/nohealthyclose/percasehandles0/noGLparent มีhealthySessionnaturalclosecontrolแยก ไม่ใช่terminalKitty/nativeimageparity

เริ่มrealrendererStateCPUadapter`image.State.captureCpuSnapshot`(ยังไม่ต่อGeneric/Remote):callerdrawlock+ownerallocator,validatecaps/finitecell/preflightalltagkittyและpending/unload_pendingเท่านั้น reject.ready/.replace/GPUstatesโดยไม่read/destroytexture,pruneunload_pendingCPUตามremoveByPtrpatternเดิม,retainsRGBApendingpixelsข้ามACK/staleviewportdrop,ตรวจu64pixelbudgetก่อนPending.len/dataSlice,sortIDmetadata/refplacementgeneration/negativexyz/crop→ownedSnapshot ไม่ปลอม.ready ไม่เรียกupload No legacydefaultpathเปลี่ยน

3newStateunitsretain-copy/pruneCPUunload/rejectGPU-sentinel-restored-beforedeinit/allallocationfailuresและเสริมexistingrealTerminal.Kittycompletedpendingfixturecapture(ตรวจgen/bytesและยัง.pending) **exec160fullCoreunfilteredactive** Sourcefreeze ไม่มีgenericguard/parentadapterเปิดimages ไม่claimruntimeKittyจากCPUcapture

15:54 exec160exit0Core89/89steps3981/4042pass61skipผ่าน sourceconsumedrealimageStateadapterfixtures ไม่รวมstandaloneentrypointเป็นCoreเพิ่มเอง

Experimentalparentwiringเพิ่มbuildoption`windows-remote-images`defaultfalse/requireswindows-remote-renderer=true;exportfromConfig/generatedbuild_configครบ RuntimeLegacy+ordinaryremoteไม่มีbehavior/capabilityเปลี่ยน เฉพาะnewflagtrueจึงRemote.session.inline_images/hello3/renderImageFrameและGeneric.remoteLockedCaptureเลือกcaptureImageFrameLocked:retainStateCPUresources→snapshot、sharedtextcellencoderใต้fontlock→ImageFramebudget/metrics→ownedbytes;ทุกRPC/childwaitหลังdraw/fontlockscopeจบเหมือนเดิม,viewportgeneration/latest-size/staledropคงเดิม PlaincaptureTextFrameLockedยังrejectimages/BG/custom/overlay;privatecellencoderไม่มีexternallycallbypass Background/custom/overlayยังrejectแม้newflag

**exec165nativebuild3variants(imagesnewprefix/defaultremotetext/legacynewprefix+worker)และoffscreenTEXTONLYviewport/Thai/strictlifecycle2remotevariants/legacyexactRGBAactive** Sourcefreeze รุ่นนี้ยังไม่actualKittyConPTY→UIหรือlegacyimageparity จึงไม่claimimagefeaturequalifiedหรือpromotedefault/accepted62 GUItestsนอกจอ/noactivate ไม่มีclipboard/driver/settings/CorePTYinputchanges

16:02 exec165images127/127buildผ่าน viewport4sizes/staledrop2ผ่านแต่terminalmarkerfail จับrootcauseจากstderr`app-local ConPTY load failed MOD_NOT_FOUND`→ConptyLoadFailed→ioThreadUnexpected/abrupt เพราะprefixใหม่ยังไม่provisionruntime ไม่อ้างfailedrenderer/ไม่ตัดmarkerrequirement text-only/legacy stagesยังไม่run

Recoveryใช้tools/windows/provision-conpty-experiment.ps1 -OutputDirectory <workspace>/zig-out/<prefix>/bin หลังbuildก่อนsmokeทุกprefix:repoพินNuGetpackageSHA256+MicrosoftAuthenticode/workspace-only/refuse mismatching existingfiles ไม่มีsystemfallback/noPTYsourcefix **exec174เดิม3variantbuild+viewport/Thai/strictlife/legacyRGBAactive** Sourcefreeze runtimepackageเท่านั้นไม่ใช่driver/systeminstall ห้ามลืมprovisionเมื่อเพิ่มprefixใหม่ที่ใช้-ConptyProvider app-local

16:05 exec174pin+signatureprovision/PTYmarkerผ่าน แต่3presentationsB/C/A(no initialA)→ViewportPresentationCoverageFailed;sourcewindow.WM_TIMERtick1resizeblindก่อนUIรับinitialA,App.noteViewportFrameใช้firstobservedsizeเป็นoriginalจึงกลายเป็นB ไม่blindretryหรือยอม3size

Fixture-onlyแก้Hooks.viewport_presented(UIlastcurrent-size metadata)ก่อนadvancephase0/1/4/5 ต้องรับA/B/C/Aจริง ไม่มีsleep/blockUI/เพิ่มdeadline(auto-close10sเดิม)/รอdriver/หยุดthread ขณะรอยังdispatchwakes/paintตามปกติ Appcoverageเพิ่มขั้นต่ำ3→4โดยยังreturn_original+odd+staledropเหมือนเดิม Productionresizeไม่มีbehaviorเปลี่ยน **exec178build/provision3variants/imagesviewport2runs+textviewport/Thai/21workerstrictlifeทั้งคู่/legacyRGBAactive** ยังTEXTONLYfixturesไม่claimnativeKittyimageparity Sourcefreeze

16:24 exec178exit0images127steps/viewport2runsครบ4sizes/stale2/Thai0diff/lifecyclehandles123→123;defaulttext127steps/viewportครบ4/Thai0diff/handles128→128(ไม่นำ123รอบอื่นมาสวม) ทั้งคู่GDI2→2/USER1→1/threads4→1/21healthyworkers;newsourcelegacy126steps/exactRGBA18checks655glyphfail0/healthycloseผ่าน TEXTONLYไม่ยกเป็นKittyproof

NativeKittyfixtureใหม่`-KittyImageSmoke` requiresstandaloneterminal/app-local+experimentalimagebuild;envsave-clear-restoreครบ/providerห้ามfallback;Appbooleanfalseไม่เปลี่ยนโหมดเดิม PublicRGBA1x1red/greenส่งAPCผ่านactualPowerShellchildstdout/ConPTY/Kittyparser/State.pending/capture/IPC/workerGPU ไม่injectintoCore/ข้ามparser ไม่file/clipboard `a=T,t=d,f=32,i=77,p=1,c=8,r=4,z=1,C=1,q=2`→sameIDreplacement→`a=d,d=I,i=77,q=2` paced800ms(no deadline extension)

App.paintobserverอ่านpresenterBGRAเฉพาะหลังimage.paintGDIสำเร็จ UI-onlystage0→red>=1024→green>=1024/red<1024→green<64/red<1024หลังdelete;closingstage!=3ต้องfail Scriptต้องครบ3phase/pinning/parentnoGL+healthyclose ไม่ใช้RPCreceipts/metadataแทนUIpixels Boundsimage8x4cells/markersplainThai+redtextไม่ถึงimagepixelthreshold **exec181experimentalbuild/actualKitty2runs/viewport4/Thai/strictlifeactive** Sourcefreeze ยังไม่legacyimageexactRGBAหรือphysicalonscreenacceptance/featurequalification

16:36 exec181127stepsผ่าน actualConPTYKitty163422และ163434ทั้งคู่UIpostGDIred6624/green6624/removedgreen0/healthyclose/noGLparentผ่าน viewport163444ครบ4/staledropและThai163451diff0ผ่าน แต่lifecycle163502failcriticalจริงที่cycle15`remote host worker close failed WorkerCloseFailed`;มี20healthycloseไม่ใช่21 แม้exit0+handles123→123/GDI2→2/USER1→1/threads4→1+cleanupจบก็ห้ามถือpass ไม่ใช่wrapperfalsepositive

ต้นเหตุcloseยังunknown:statusเดิมอาจถูกSession.fail→abortทับ จึงClient.closeบันทึกoriginalrw_finish return/stage/winerror/ack/exited/childexit/jobempty/forced/budgetก่อนcleanup พร้อมsmoke-onlyRemote.initส่งGetStdHandle(stderr)ผ่านexistingCexplicitduplicate+allowlistเพื่อเก็บworkererror;normalhostยังNUL ไม่ให้IO/handleอื่นC codeไม่เปลี่ยน `reap`เดิมpolljobempty10msในbudgetอยู่แล้ว ห้ามguessเพิ่มpoll/timeout/relaxcritical หรืออ้างdriverhangจากข้อมูลไม่พอ **exec188clientnegative+imageSessionregression/nativebuild/strictlife2sets+KittyGDI2runsactive** Sourcefreeze ทวนผ่านอย่างเดียวไม่ใช่rootcausefixed

16:51 exec188exit0client30steps+nativebuild/clientnegative+imageSessionผ่าน;2strictlife42healthyworkers/countersไม่โตและKitty165051/165102ทั้งคู่red6624/green6624/remove0หลังGDIpaint/healthycloseผ่าน ไม่พบoriginalclosefaultซ้ำ ยังไม่rootcausefixed

Boundedreproเพิ่มexec1895sets×21=105sessionsบนunchangedbinary/stopfirstfault/แต่ละsetstrict21naturalhealthyACK+counts/no criticalตามเดิม ไม่มีrerun-failed-until-green finiteeventmonitorส่งsetresultและstoponEND มีread-onlyforktask4reviewC/Client/Session/workerteardown ไม่ให้แก้sourceหรือรันทับ Nativeclosefaultcycle15ยังคงunresolvedqualificationblockerแม้stressครั้งต่อไปผ่าน

16:55 task4read-onlyaudit:workerexecutor→GLloaderunload→releasecurrent→context→device deferถูก;Sessionpoison+abortถูก;reapเดิมboundedpolljobถูก จึงยังไม่มีjustifiedfixสำหรับcycle15 Separatestaticrace C.rw_call152–154waitstop/process/response:process+replyพร้อมกันอาจlostvalidclosed→WorkerCommunicationFailed ไม่ใช่observedWorkerCloseFailedหลังexchangeสำเร็จ แยกไว้ไม่อ้างแก้ต้นเหตุ

Diagnosticgap C.reap63–68/finish169รวมprocesswait/GetExitCode/queryjob failures+deadlineเป็นERROR_TIMEOUT ถ้าพบ1460ใหม่ใช้originalexited/jobempty+childstderrแยกก่อน อาจเพิ่มboundedteardownmarkers/underlyingWin32resultsโดยไม่เปลี่ยนbudget อีกrisktemporaryinheritableworkerlaunchhandles(106–129)+Command.CreateProcessinheritTRUE(421–434)ไม่มีsharedserializationที่auditพบ ยังไม่ยืนยันleak/cause ไม่แอบแก้Command/ConPTYนอกscope **exec189ยังactive2/5healthy42** Sourcefreeze

16:58 exec189ครบ105sessions5/5setsทุกset21healthyACK+handles123→123/GDI2→2/USER1→1/threads4→1/criticalfreeผ่าน มีENDPASS+monitorจบexit0 ไม่rerunต่อไม่จำกัด ไม่ถือoriginalcycle15fixed ยังบันทึกunresolvedblocker

Diagnosticextension:reapfailureเท่านั้นบันทึกWaitForSingleObject result/WAIT_FAILEDLastError/GetExitCodefailure/jobactive/queryLastError/budgetelapsed;statusABI28B/returnmapping/5sbudget/jobpoll10ms/orderไม่เปลี่ยน Workercloseบันทึกclosed-published→executorbegin/end→contextbegin/end→devicebegin/end→gpu-teardown-complete→run-completeหลังmaps/handlesdeferจบจริง preserveเดิมallcleanuporder NormalhoststderrNUL/smokeexistingdiagnosticallowlist Loggingอาจเปลี่ยนtimingได้ จึงpasswithloggingไม่ใช่causalfix

**exec192MSVCstdc11W4WXproduction+testvariants/clientnegative+imageSessionregression/native21completeexecutor-context-device-runendchains/strictcounts+KittyGDIactive** Sourcefreeze ไม่แก้separateWaitMultiplepriorityrace/Commandinheritanceจากreviewเอง ยังไม่legacyimageexactparity/perf/M1bqualificationหรือdefaultpromotion

17:04 exec192exit0MSVCC11W4WXสองvariants/client30steps/native127+negative/imageSessionsผ่าน;native170320strict21healthyclose+21executor/context/device/runcompletionchains/handles123→123/GDI2→2/USER1→1/threads4→1;Kitty170431postGDIred6624/green6624/remove0และfullteardown/healthycloseผ่าน ไม่มีcycle15reproหรือcausalfix

Nextboundedexperimentแยกstaticclose-responsepriorityraceจากunknownWorkerCloseFailed:RW_BEFORE_REPLY_WAIT productiondefaultconstant1(no-op);testvariantownedhookหลังrequestpublicationก่อนWaitรอprocessExitในremainingcallbudget(หักelapsed),ตรวจactualresponsecommit/closedkind11+observe/restoreexistingauto-resetevent ไม่เขียนfakeACK/body ไม่stop/pausethreadหรือdriver Maintestเพิ่มท้ายnormalnegative/imagechecks ต้องhealthycloseเมื่อทั้งrealprocessและrealclosedพร้อมกัน ถ้าoldpriorityrejectจะcleanupวัดhandles0+REPRODUCEDแล้วreturnerror **exec195build/EXPECTEDREDactive** productionwaitpriorityยังไม่แก้ ห้ามนับexpectedredexit1เป็นsuitepassหรือoriginalfaultfixed Sourcefreeze

17:08 exec195build30stepsผ่าน normalnegative/imageSessionchecksผ่านแต่newtestจริงexit1/WorkerCommunicationFailed+REPRODUCED+handles0ตามEXPECTEDRED พิสูจน์separateprocess-before-responseprioritybug ไม่ใช่ยกscriptoverall0มาอ้างtestgreenหรืออ้างrootcausecycle15

ScopedfixC.rw_call:เฉพาะrequestkind10 CLOSE และWaitresultprocess1เท่านั้น เช็คstopmanualeventก่อน(cancelpriority)→nonblocking0msconsumealready-signaledresponse→commonprefix/header/session/seq/epoch/sizevalidationเดิม→Client.closedexpectedkind/bodyและrw_finishnaturalexit0/jobempty/no-forcedเดิม ไม่promoteWAIT_TIMEOUT/WAIT_FAILED/submit_frame ไม่เพิ่มwaitbudget ไม่ยอมlate/invalidACK เพิ่มtest-onlycancelmodeหลังactualworkerclosed+exitพร้อมก่อนwaitต้องERROR_CANCELLED/nohealthy/forcedcleanuphandles0 **exec196MSVCC11W4WXทั้งvariants/build+green2fullnegative/imageSession/lateclose+newcancelcontrolsactive** Sourcefreeze เดิมWorkerCloseFailedcycle15ยังunresolved

17:12 exec196exit0MSVCC11W4WXprod/test/build30+green1/green2ผ่านทั้งdeterministicactualclosed+processExitและstop+exit+closed3signals;healthyrequiresvalidatedACK+exit0/job0/noforced/handles0,stopwins1223/nohealthyACK/ownedforcedreap/handles0;existingnegative/lateclosed/text-imageSessionsผ่าน แก้เฉพาะraceที่red195พิสูจน์ ไม่ยกเป็นhistoricalWorkerCloseFailedcause/fix

**exec197rebuild/provision/native3variantsactive** imagesKittypostGDI2/viewport4/Thai/strict21teardown+counts→defaulttextviewport4/Thai/strict21→legacyThaiRGBAexact;finitepervariantmonitor/endstopติดตามผล ไม่แก้sourcesระหว่างbuild ไม่promoteexperimentalflagเป็นdefault/accepted62 และoriginalpostACKfault/legacyimageparity/M1b/performanceยังpending

17:24 exec197exit0images127/defaulttext127/legacy126ผ่าน Kitty2/viewport4/Thai/strict21naturalhealthyACK+runendteardown/countsทั้งremote;legacytextRGBA29checks/maxglyph655/fail0/differentbytes0ผ่าน finiteeventENDPASS+monitorจบ OriginalpostACKfaultไม่อ้างfixed

NextM3actualimageparityเพิ่มdiagnostic-only`-KittyImageLegacyReference`ต้องKittyfixtureจริง+legacybuild(ห้ามremote) envsaveclearrestoreครบ/normalfalse;remoteKittyยังต้องexperimentalimageflag+parentnoGL+healthyclose LegacyreferenceexplicitlyparentGLexpectedไม่ใช่isolation ส่วนobservepostGDIเมื่อphaseadvance hashWHOLEUIownedBGRAทุกbyteด้วยSHA256+bytecountทั้งred/green/delete ไม่ได้hashsource1pixel/แค่นับสี RPC หรือGPUmetadata ไม่แตะCore/PTY/imagependingready

**exec199imagesbuild+2actualConPTY/GDIruns→legacybuild+2explicitreferenceactualrunsactive** ทุกrunต้อง3uniquephasehash+samebytecountครบ baselineimagesrun1 เทียบimagesrun2และlegacyrun1/2 mismatchfailทันทีไม่colourthresholdwaiver Sourcefreeze ยังไม่claimwholeframeparityจนผลออก originalclosefault/driverhang/performance/M1bqualified/defaultpromotionยังไม่ผ่าน

17:36 exec199exit0images127/legacy126+remote2runs/legacyreference2runs actualConPTY+postGDIทั้ง3phasewholeBGRA2733896bytes SHA256ตรงกันทุกrun:red6796d25b6724f6dfd4056ede23baa3228ee288621036ea42af126ca9941ac207/greenb39e832d3cd4370e258be7455d5a2d0c6e8a15734dcdc377b39864f088c79d7c/deleted779abb756e2cb11e1fa97372598b7de1e49a14ac771028ddadb3fe47ee36240e ไม่มีthresholdwaiver ผลนี้เฉพาะfixtureRGBA1x1scaled8x4/red-green-IDreplacement-delete ไม่ใช่ทุกformat/crop/zorder/manualacceptanceหรือoriginalclosefaultfixed

**M4exec204controlledinteractionactive** บนcurrentremoteimageoptinbinary:inputASCII/ThaiUTF16/surrogate/Enter→mousefixtureownedHWNDselection/scrollback/captureloss+in-memoryclipboard(existingSurface.fixture sinkไม่OSclipboard)→naturalexit/burst/OSCtitlebackpressure ไม่มีglobalinput/foreground/driver/CorePTYchanges sourcefreeze ผลsyntheticinputไม่แทนphysicalIME/keyboard/mouseacceptanceจากมนุษย์ ยังไม่defaultpromotion/M1bqualified

17:39 exec204exit0ครบ5cases input173850KeyEventASCII+Thai+surrogate+Enter/repeat2;mouse173900CtrlShiftC/right-clickselected/no-selection-no-copy-pasteใช้inmemorysink+drag/wheelscroll/captureloss;exit173911naturalchildexit;burst1739121688frames/paints;title1739231644frames/paints+queuefullinserted4 ทุกcaseparentnoGL/actualGDI/healthyworkercompletecleanup/surfaces0 ไม่มีOSclipboard/globalinput ไม่ใช่physicalIME/onscreenacceptance/CPUlatencybenchmark

**exec207M5automatedregressioncheckpointactive** CPUimagecodecstandaloneDebug/ReleaseSafe→fullCoretestReleaseSafeWin32→libVTReleaseSafeWin32 sequential+finiteperstageeventmonitor stopfirstfailure Sourcefreeze Performanceต้องแยกหลังbuildloadจบ ไม่ใช้M4fpsแทนqualifiedperformance ยังoriginalpostACKclosefault/GPU-busyhang/manualIME/defaultpromotionunverified ไม่commit/push/driver/threshold changes

17:55 exec207codec36/36Debug+ReleaseSafeผ่าน fullCore89/89steps3981/4042pass61skip exit0 **actualCoretestexeforcedDebug(build.zig608–620)** ถึงCLIoptimizeReleaseSafe จึงไม่อ้างCoreReleaseSafecoverage LibVTReleaseSafecompilefailPageList.pinIsValid5754comptimeassert(build_options.slow_runtime_safety)→quirks54;Config736เปิดเฉพาะDebug โมดูลVTtestใช้CLIoptimizeไม่เหมือนCore ความผิดพลาดของinvocationไม่ใช่หลักฐานWindows/rendererbug ไม่แตะCore/assertหรือskip **exec211requiredDebuglibVTactive** เก็บfailedReleaseSafeเป็นหลักฐานไม่ได้claimผ่าน Sourcefreeze/performanceรอbuildจบ

สรุปcurrentcheckpointแบบไม่ต้องไล่อ่านchronology: [windows-render-worker-checkpoint-th.md](windows-render-worker-checkpoint-th.md)

18:21 exec211requiredDebuglibVT45/45steps6722/6786pass64skip exit0 ไม่มีCore/assert/skipchanges ยังไม่claimReleaseSafeinvocationผ่าน **exec212M5performanceactive** remoteimageoptinและlegacyprofile/profile-paced4cases sequentialหลังbuildloadหมด defaultPSSdiagnostics/25sclosebudgetเดิม ข้อมูลhostresourcesไม่ใช่totalparent+GPUworker ไม่มีdefaultpromote/physicalIME/driverbusyhang/oldpostACKclosecauseclaim Sourcefreeze

18:23 exec2124/4closebudget25sผ่าน parentonlyremoteprofileCPU20609ms/WS115576832/frames961;remote-paced11219/66215936/897;legacy32781/247996416/1947;legacy-paced7234/190418944/983 ไม่อ้างoverallperfwinเพราะworkerexcludedและpacedremoteparentCPUสูงกว่า

Diagnostic-onlysample_owned_resourcesใช้existingc.processHANDLE/K32GetProcessMemoryInfoทุก>=250msระหว่างsuccessfulRPC,report_owned_resourcesCPUGetProcessTimesหลังnaturalexitเฉพาะc.diagnostics (เดิมprivate stderr handle) ไม่มีPIDdiscovery/OpenProcess/newHANDLE/protocol/statusABIเปลี่ยน normaldiagnostics0ไม่query CPUafterexitcomplete vsparentCPUobservedwindowsต่างกันต้องlabel;sumpeakWSไม่ใช่simultaneous/uniquepages/VRAM **exec215MSVCC11W4WXprod/test/clientnegative+race/native21strictlife+21metricsแล้วprofile4casesactive** Sourcefreeze originalpostACKclose/GPUbusy/manualยังpending

18:31 exec215exit0MSVC/clientnegative+race/native21strictcounters/21metrics/profile4casesผ่าน remoteprofileparentCPU21453+worker8140=29593ms/frames1106/sumpeakupper273.6MiB;remotepaced10672+7906=18578/945/226.2;legacy33203/2102/236.7และpaced7969/981/181.6 ไม่อ้างperfwin CPUmixedwindows+peaknonunique และworkloadoutputต่างกัน pacedoverheadชัดต้องตรวจ

WorkeronlyoptimizationพบTarget.init/deiniteveryframeในTextGpuExecutor(2textures+FBOs);เพิ่มcontext-ownedtargetcachematchdimensions/replacementallocatedfirstbeforeolddeinit/fullclearทุกframeตามเดิม no wire/cadence/budget/sharedlegacyTargetchanges เพิ่มcachecheckstable10frameidentity/invalidalloc0/resize9x5-return8x4created3/wholepixelsreturnexact/old+final2textures2FBOdestroy **exec221componentsGPUtext/imagecache/image3band/clientnegative→nativewholeSHA/viewport4/strict21life→profile4casesactive** Sourcefreeze ผลperformanceยังไม่claim originalpostACKclosefaultยังไม่fixed

18:39 exec221exit0componenttargetstable10resize9x5return8x4created3+deletedold/finaltextures/FBOs+exactpixels/image3band/clientfault/nativewholeSHA/viewport4/strict21ผ่าน remoteprofileCPU20906+8140=29046ms/1076frames/WSupper272MiB;paced11766+7640=19406/946/225.4;legacy33422/2253/236.5และpaced7500/991/181.8 ไม่claimpacedperfimproved ลดallocationchurnโดยมีlifecycleproofเท่านั้น

**exec226read-onlyprofilephaseinstrumentationactive** Remote.profile_enabledเฉพาะApp.fixtureprofile/profile-paced ใช้QueryThreadCycleTime(GetCurrentThread pseudoHANDLEไม่ต้องopen/close)ก่อนcapture/หลังcapture/หลังRPC/หลังpublish สะสมcycles+packetbytesแล้วlogonceตอนthreadExit normalfalseไม่sysquery ไม่ลบdecoder/verifyNoGpu/parentlocks/epochfences no wire/cadence/budgetchanges buildremote+legacy/profile2cases Sourcefreeze phasecyclesไม่ใช่walltime/wholeparentCPU(excludesblockedwait/updateFrame/shaping/otherthreads/packetfreeafterpublish) ยังไม่เดาแก้copiesจนอ่านattribution

18:51 exec226exit0remote127/legacy126/profile2cases CPUphasescapture16.98%/RPC82.59%/publish0.43%;paced17.14/82.42/0.44% เป็นsame-renderer-threadcyclesเฉพาะส่วนที่วัด ไม่ใช่wall/wholeparent/shaping/threadอื่น/packetfree ParentprofileCPU21922/paced12500msและworker7953/6453ms ไม่อ้างoverallperfwin

OwnershipoptimizationตรวจพบSession.copyRgbaalloc/copyทั้งRGBAซ้ำหลังC.rw_callcopyออกsharedmapเป็นprivateReplyแล้ว เพิ่มCpuFrame.RgbaMemory.backingoptionaldefaultnull/deinitfreebaseไม่ใช่interior และtakeRgba(owned *[]u8,pixeloffset) validatesdimensions/overflow/offset/exactremaininglengthก่อนconsume ไม่มีallocหลังconsume errorcallerownershipเดิม;SessionรับreplyprivatebaseoffsetProtocol.header_bytes+16แทนcopy deferReply.deinitfreeemptysafe ไม่ยืมsharedmap ไม่ข้ามProtocol/client/epoch/modulevalidation CPUtestsbase/view/emptyreplyfree/errorsretained;ClientimageSessionsเก็บredframeprivatebaseข้ามgreenreplyและ5kill/cancel/stale/naturalreapsแล้วexactcompare **exec233Debug/ReleaseSafeCPU/client/nativeboth/wholeSHA/viewport/21life/profilesactive** Sourcefreeze originalclosefault/GPUbusy/manualpending ยังไม่performancewinclaim

19:08 exec233exit0CPU37/37Debug+ReleaseSafe/clientprivatebase-retainedredexactaftergreen+5reaps/nativeboth/wholeSHA/viewport/strict21lifeผ่าน remoteprofile20984+9796=30780ms/1230frames/WSupper272.7MiB;paced9562.5+7515=17077.5/952/225.2;legacy33609/2088/236.4,paced7953/965/181.8 ยังไม่overallperfparity/superiority กรอบobservationwindows/workloadnonmatchเดิม

**exec235fullCore/VTDebugหลังpatchactive** Sourcefreeze ส่วนread-onlyreviewtask5generalpurposeปฏิเสธOlufyonlyไม่ได้inspectsource เปลี่ยนsinglecleanrecoveryforktask6ตรวจFramebaseownership/allconsumers+RPCcopy/validationmapและoneboundedrecommendation ไม่ถือtemplate refusalเป็นreview ไม่แตะtemplate/harnesssettings หรือscopeอื่น oldpostACKclose/GPUbusy/manual/perfqualifiedยังpending
