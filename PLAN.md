# แผนพัฒนาเทอร์มินัล Windows ของเรา

วันที่สำรวจ: 16 ตุลาคม 2026<br>
ปรับปรุง: 16 ตุลาคม 2026 หลังตรวจ checkout, ซอร์ส และเครื่องมือจริง โดยยังไม่บิลด์<br>
เครื่องที่ใช้สำรวจ: Windows build 10.0.26200, สถาปัตยกรรม AMD64, Git 2.52.0.windows.1<br>
โฟลเดอร์งาน: `D:\works\ghostty-windows` เป็นรากรีโปและมีซอร์ส Ghostty แล้ว ไม่ใช่โฟลเดอร์ว่าง

เอกสารนี้คือแผนสำหรับแอปที่เราใช้เองและพัฒนาเอง ไม่ใช่พอร์ตที่จะส่งกลับเข้า Ghostty และไม่ใช้ชื่อ Ghostty เป็นชื่อผลิตภัณฑ์

## สถานะจริงและขอบเขตหลักฐาน

### 30 ตุลาคม 2026 — แก้ native startup rollback; normal resource gate ยังเปิด

ทำซ้ำ IO-worker startup failure แบบ fault injection แล้วแก้การหยุด/joinก่อนคืนdependency, quarantine routing/registry, authoritative-owner cleanup, font reference และลำดับ initial-title ก่อนเริ่ม Windows workers Native renderer/IO/title failure ทั้งสามและ terminal ปกติผ่านจริงหลังแก้ (มี panic ใน attempt แรกซึ่งเก็บหลักฐานไว้) แต่ strict21cyclesยัง handles233→234/threads6→7/GDIUSERคงที่ จึงไม่ปิด `WIN-RUNTIME-004` ไม่ยกเกณฑ์หรือแตะ driver/default/A:/บัญชี/agent ไม่ commit/push ดู [startup rollback](docs/windows-startup-rollback-th.md)

full-core แบบ build runner **ยังไม่ผ่าน: timeout900s** โดยไม่มีtestsummary แต่ same compiled binary แบบ direct ภายใต้900sเดิมรันครบ **3994ผ่าน/61skipped/0failed (4055ทั้งหมด), exit0/source/binaryunchanged** ตัวอ่านผลเดิมไม่รองรับskippedจึงfalse-negative แก้และตรวจoffline9casesจากactualreceiptแล้วโดยไม่rerunชุดเต็ม ดูเอกสารข้างต้นสำหรับขอบเขตที่ยังไม่ผ่าน

ทวนexistingGPUworkeropt-in: negativeทั้ง3+positiveผ่าน แต่strictครั้งแรกfailed `TerminalMarkerMissing` cycle12แม้close21/21healthyและhandles123→123 จึงไม่ล้างoldclosefault ต่อมาobserverและV3failure-onlysnapshotcaptureแบบboundedไม่ทำซ้ำfailure ไม่ถือว่าแก้แล้ว เพิ่มsnapshotจำกัด96bytesเฉพาะcontrolledlifecyclefailure (normal/previewไม่logtext), unit3/3ทั้ง2mode และV3positiveสองbackendผ่าน รักษาlegacy+1handle/+1threadและopt-inmarkerfailureเป็นblockersจนได้causeproof ไม่เพิ่มdeadline/warmup/stressซ้ำ/defaultpromotion ไม่แตะA:/บัญชี/agent ไม่commit/push

4พ.ย. owned-resource audit: [หลักฐาน/ขอบเขต](docs/windows-owned-resource-ledger-th.md) ledger7/7testsทั้ง2mode; หลังLLVMOOMและheadroomคืน oneunchangedretrybuild123/123+positiveผ่าน Actual21cycles105lifetimes(returned63workers/42IOCP) active0/fault0 ไม่มีtrackedworkerlive/retainedtargetหรือIOCPslotmatchท้ายrun แต่strictยัง233→234/6→7 Event39→40,Threadhandles3→5,ALPC4→2,IOCP5→5 Livegroupsเพิ่มentryamdihk64จาก0เป็น1; ntdll3→3โดยเปลี่ยน3TIDs ไม่ใช่allocationcallerproof/driverleakproof Eventcallerยังไม่ทราบ ต้องขอhumanapprovalก่อนmachine-levelETW/ยกสิทธิ์/อาจเก็บmetadataprocessอื่น ไม่เปิดsessionหรือpatchDLLเอง ไม่ใช้oldCDBidentitiesข้ามrunและยังไม่closeWIN-RUNTIME-004

### 27 ตุลาคม 2026 — isolated Node/npm portable candidate ส่งมอบ local แล้ว

ผู้ใช้อนุมัติ15:49ให้Node/npm/การติดตั้งLettaภายหลังอยู่ในexe-relativeportable-data ใช้freshprofileไม่ย้ายบัญชี/agentmemoryเดิม ไม่globalinstall/เปลี่ยนWindowsenv/profile/commit/push เตรียมofficialNodev24.22.1Krypton/npm11.19.1pin/archiveSHA/license+fullimmutablefilemanifest และactualchildEnviron.Mapsanitizerก่อนprivateoverrides HOME/USERPROFILE/AppData/npmconfig/cache/temp/LettaLocalBackend; exactNodeentrypoints/privatePShistory/strictPATH(ไม่inheritGit/CLIเครื่อง) และdistribution-onlycompiledefaultเปิดEXEตรงก็ไม่fallbackhost Node/PSmoduleขาดหรือเสีย/พื้นที่เขียนไม่ได้errorก่อนchildspawn ไม่อ้างว่าเป็นsandboxหรือWindowsOSไม่แตะC:เลย

NativeMSVC/ReleaseSafeทั้งisolatedและnormalcompat123/123สำเร็จ; productionmessagepump priorityWMQUITใช้staleordinarywparamเดิม2/4red→คืนactualquitmessage4/4green; EnvMap2/path1ผ่าน พบCMDquotedbare`"node"`ทำให้%~dp0กลายเป็นcwdจริง จับ127redก่อนแก้wrapperหาknownCMDผ่านexplicitPATHแล้วsameE2Egreen Nativepositive8casesผ่าน(2providerfulltools+poisonedenv/midline2provider/keyboard/naturalexit/directEXEdefault/relocationไทยspacepreserveprofile), ASCII51/Thai49cells0/bufferตรง; native8negativeผ่านก่อนspawnและrestoreACL/ทุกmutation+postcleanupgreen ไม่ใช้readonlydirectoryattributeแทนwriteprobe ไม่อ่านuserterminal/clipboard/historyหรือใช้provider/accountsจริง Normalbuildไม่บังคับNode/ไม่สร้างportablemarkerและnoninteractiveexit0ผ่าน

Freshnever-runpackage `zig-out/portable-packages/localterm-portable-tools-20261027/Run.cmd` มีNode/npm/PSReadLineครบ ตรวจmanifest2,765files NativeSHA`5190F82B…2E0577` ไม่ติดตั้งLetta/profilehomeยังว่าง ผู้ใช้ติดตั้งภายหลังตามเลือก ไม่เหมารวมhumanacceptancecandidateเดิมว่าเป็นการยอมรับUIbinaryใหม่นี้ ยังไม่ปิดWIN-RUNTIME-004/physicalmixedDPIและไม่promoteprovider ดู [windows-portable-tools-th.md](docs/windows-portable-tools-th.md) พร้อมหลักฐาน `zig-out/portable-tools-evidence/build-20261027-162422-825/final-handoff.json`

### 27 ตุลาคม 2026 — app-owned PSReadLine correction ผ่านอัตโนมัติและผู้ใช้ยืนยันเคสลูกศรแล้ว

ผู้ใช้อนุมัติ14:28แล้ว: officialsourcepin/MIT/license-preservingapp-ownedPSReadLineMn/Me0 correction ไม่globalinstall/profile/defaultpromotion ด้านcausal8runold→patched→old→patchedสองproviderครบ: oldThai52แทน49/native1 vs patchedThai49/native0/ASCI51/cells0/bufferexact/hashจริงตรง Productcommonbootstrap/exe-relativechildenvทั้ง2provider+keyboard/naturalexitและrelocationpathไทย/spaceผ่าน; badhash/missingassetcloneถูกrejectและrestoreครบ Candidate`zig-out/app-readline-20261027-150014-546` nativeSHA1950B659…EBAE3 พร้อมopt-in`preview.ps1 -AppReadLine` NormalhumanpreviewPID11104เปิดแล้ว/nativelogverifiedmoduleB1BE…847B และ**ผู้ใช้ยืนยัน15:26:58ว่า “ไม่บัคแล้ว” สำหรับเคสลูกศรย้อนแล้วพิมพ์แทรก** ไม่ใช่fullUnicode/IME/GPU/DPIacceptance ไม่แตะoriginalpreview11164 ไม่ปิดWIN-RUNTIME-004/physicalmixedDPI ไม่commit/push ดู [windows-thai-midline-cursor-th.md](docs/windows-thai-midline-cursor-th.md)

### 27 ตุลาคม 2026 เวลา 12:43 — manualmidlineeditingcounterexample / พักDPI

ผู้ใช้แทรกaaaaยาวกลางบรรทัดที่มีไทยแล้วรายงานcursorไม่อยู่หลังaพร้อมภาพcounterexample ยกเลิกการเหมารวมeditingผ่านจากbasic12:41 PreviewเดิมsystemConPTY/binaryE0AA…C3D0 ยังเป็นuser-ownedlivewindow ไม่อ่านbuffer/clipboard/ส่งinputหรือเปิดแทนเอง ตรวจknownThaiwidth/providerและcontrollededitcaseก่อนpatch ไม่วินิจฉัยfontจากภาพเดียว ดู [windows-preview.md](docs/windows-preview.md)

Samebinaryrelated**output-only**A/Bรันจริง: systemstrictConptyUnicodeModelMismatch38cells/exit1 เทียบapp-local0cells/exit0 ทั้งคู่finalcursor45/11 ไม่timeout จึงยังไม่พิสูจน์interactivecause/fix รอวิธีย้ายกลางบรรทัดarrowหรือmouseก่อนmatchingregression ไม่เปลี่ยนdefaultหรือcursoroffset รายละเอียด [windows-thai-midline-cursor-th.md](docs/windows-thai-midline-cursor-th.md)

### 27 ตุลาคม 2026 เวลา 12:41 — userยืนยันพิมพ์ไทยพื้นฐานปกติ / physicalmixed-DPIยังรอ

หลังเปิดmanualpreviewdefaultcandidate`app-build-20261026-193028-701` DPI96/100% ผู้ใช้ตอบ **“ปกตินะ”** พร้อมภาพ รับเป็นuserreportedpassของพื้นฐานไทยตามขั้นนี้ Agentดูภาพเห็นไทย/ABC123/cursorท้ายบรรทัด ไม่เหมารวมIMMcomposition/candidate/ทุกkeyeventหรือmixed-DPI ปัจจุบันยังไม่มีrecordedDPItransition ขั้นต่อไปลากข้ามจอScaleต่างกัน ไม่ปรับWindowssettings/อ่านclipboard/เปิดหน้าต่างซ้ำ ดู [windows-preview.md](docs/windows-preview.md) ยังไม่ปิดWIN-RUNTIME-004หรือpromotedefault/commit/push

### 27 ตุลาคม 2026 — bounded functional GPU reproผ่านทั้ง181/244-style แต่ยังไม่rootcause/qualified

Privateoffscreenfunctionalsuiteหนึ่งรอบ32/32build+exit0:28actualhiddencontextsอยู่พ้นทุกmonitor, lateGPUreadback+0ms/publish+203ms/identical128RGBAถูกreject cleanupACK0/exited1/child1/jobempty1/forced1/handles69→69 noouterkill/remnants/sourcechange ไม่ถือว่าแก้244แล้ว

ActualremotehostMSVC/ReleaseSafebuild125/125 ใช้app-localproviderเดิม+qualifiednonfaultoffscreenworkerเฉพาะprivateprefix lifecycle21sessions/21healthycloses/21childcontexts passedexit0/frames165paints165/handles129→129/GDI2USER1stable/threads4→1/cleaneddescendants[] ไม่timeout ไม่ถือว่า181rootcauseหรือnormalWIN004resolved ไม่เปิดGPUbusy/perfqualification/defaultเอง ไม่มีcommit/push รายละเอียด [windows-worker-functional-repro-th.md](docs/windows-worker-functional-repro-th.md)

### 27 ตุลาคม 2026 — CPU reap budget defect แก้แล้ว / original shutdown faults ยังเปิด

พบและทำMSVC/baseline same16case red→greenจริง: productionreapเดิมprocesswait49ms+Sleep10เริ่มjobpollที่59msแล้วรับlateemptyเป็นsuccess แก้เฉพาะclampSleepremaining/ไม่เริ่มsubsequentpollหลังdeadline คงinitialnonblockingprobe/ACK/exit0/jobempty/forced/budgetsเดิม Original3/16failed→fixed16/16DebugและReleaseSafe; relatedCPUcontracts39/39ทั้งสองmode; compile-onlyclient/worker32/32ผ่านในprefixใหม่ ไม่runGPU/defaultไม่เปลี่ยน

RealCPUjobfixturefinish/destroy/observerexitผ่านแต่strictglobalhandles61→66failed; coldplainWin32controlข้ามproductionfinish/destroyก็+5ระหว่างCreateProcessก่อนreap ไม่warmup/waive/เรียกbenign อธิบายoriginalexec181/244ไม่ได้และไม่อ้างแก้แล้ว GPUqualificationยังpause ไม่มีcommit/push รายละเอียด [windows-worker-reap-audit-th.md](docs/windows-worker-reap-audit-th.md)

### 26 ตุลาคม 2026 — post-fix normal strict ยัง +1/+1 / close-side controller ยังไม่ qualified

หนึ่ง matched normal/no-marker/app-local/PSS-enabled case หลังสอง fix `lifecycle-native-20261026-203702-064` ยัง **242→243 handles / 6→7 threads / GDI USER3คงที่**, exit1/ResourceGrowth ไม่ timeout ไม่มี cleaned descendants/source/marker change ภายใน run เดียว ALPC4→2/Event42→43/Thread3→5 ไม่เทียบ numeric identities ข้าม run และไม่ปิด `WIN-RUNTIME-004`

ไม่ทำ old entry API sweep ซ้ำ เก็บinfra failuresครบแล้วแก้exactframing+MASMpredicateด้วยofflineแดง→เขียว/4Eventcontrolจริง **native213658ได้ใหม่: baselineALPC0xbc8/0xbd0ถูกRPCGCpathปิดสำเร็จ TID5832/NTSTATUS0/sameRIP/RSPentry+8** fullhistoryauditแยกbaselinegenerationจากlaterreuse32records/slotได้ sourcefreeze/no forcedcleanup/no descendants แต่แอปunderdebuggerยังResourceGrowth235→236/6→10 ไม่แทนnormalstrictpass/ไม่creator-ownerproof กำลังทำfilteredreturned-HANDLEcontrolแยกโดยไม่แตะproductionsource No driver/global/default/gate/commit/push change รายละเอียด `docs/windows-postfix-attribution-th.md`

ต่อมา **creator-native220653 actualAPIreturns3รายการjoinfullhistory/finalPSSได้**: AMDtimer→CreateThreadhandle0x71c/target10368; RPCThreadSelf→Event0xf58+self-threadduplicate0xe00/targetcreator24780(returnBOOL1+actualoutputhandle,ไม่ใช่OSthreadใหม่) sameTID/RIP/RSPentry+8ทุกAPI latestOPENไม่ถูกclose/reopenภายหลัง oldreuseexcluded ไม่มีforcedcleanup/descendants แต่underdebugger235→238/USER3→4/threads6→10ยังResourceGrowthและextraEvent0x750/IOCP0x75cไม่มีcreatorPC normal+1ยังไม่attributedครบ **WIN-RUNTIME-004เปิด** ไม่ปิดhandlesของDLLruntimeเอง ไม่เปลี่ยนapp/default/gates

### 26 ตุลาคม 2026 — attribute-list cleanup API contract ผ่าน regression แยกจาก resource attribution

ทำงาน cleanup ที่ผู้ใช้อนุมัติต่อจาก inheritance audit: original-red พิสูจน์ว่า native initialized lists ไม่ถูก Delete ใน success/post-init/post-update/real CreateProcess failure (77 passed/4 failed) แล้วเพิ่ม owner/defer ระดับ `startWindows` ซึ่งถือ list จน CreateProcess ใช้เสร็จและ Delete ก่อน caller ปล่อย arena

same-test green **81/81**, Command adjacent **116 passed / 12 skipped**, ไม่มี timeout/forced cleanup/input mutation; test-only TLS receipts นับ actual SDK calls และจับ premature delete ที่ create boundary มี pre-init control 0 deletes Verifier ให้ focused pass แล้ว Win32 ReleaseSafe build **123/123** ผ่านใน prefix ใหม่ `zig-out/attributes-build-20261026-202012-333` ไม่มี private test helper ติดไป ไม่มี build/test ค้าง ไม่เปิด GUI ไม่เปลี่ยน inheritance/stdio/worker/default/gates ไม่ commit/push และไม่อ้าง OS leak หรือปิด `WIN-RUNTIME-004` รายละเอียด `docs/windows-attribute-list-cleanup-th.md`

### 26 ตุลาคม 2026 — ปิดบั๊ก ConPTY broad inheritance เฉพาะจุด ไม่ล้าง WIN-RUNTIME-004

ทำ bounded source audit ตามคำแนะนำ Astra แล้วพบว่า `Command.startWindows` เปิด inheritance ทั้ง process แม้ใช้ ConPTY; worker มีช่วงที่ handle ของตนสืบทอดได้ แต่ยังไม่พิสูจน์ overlap จริงหรือความเชื่อมโยงกับ +1 handle/+1 thread

เพิ่ม private headless regression ผ่าน production `Command.start`: original-red ได้ READY/ACK/exit0/healthy cleanup แต่ `inherited_canary=1` แล้วล้มเฉพาะ isolation assertion จากนั้นแก้ให้ ConPTY ใช้ `bInheritHandles=FALSE` และคง non-ConPTY `TRUE`; same test green `inherited_canary=0`, **76/76 ผ่าน** และชุด Command **111 ผ่าน / 12 skipped**, exit0 ทั้งสองรอบ ไม่มี timeout/forced cleanup/source mutation Independent verifier ทวน logs และ source hashes แล้วให้ focused pass

Win32 ReleaseSafe build ผ่าน **123/123 steps**, prefix ใหม่ `zig-out/app-build-20261026-193028-701`, ตรวจไม่มี test helper ติดไปกับแอป ไม่มี build/test ค้าง ไม่เปลี่ยน GPU default, ไม่เปิด GUI, ไม่แตะ portable เดิม และไม่ commit/push ผลนี้ไม่ใช่การรัน/รับรองแอปจริง `WIN-RUNTIME-004`, exec181, exec244, actual GPU-busy/performance และ physical IME/mixed-DPI ยังเปิดเหมือนเดิม รายละเอียด ผล red/green และข้อสังเกต attribute-list cleanup ที่ยังไม่แก้: `docs/windows-launch-inheritance-audit-th.md`

### Auto featurelocalส่งมอบ / no-portableก็repro resource blocker / ไม่มีtestค้าง — 20ตุลาคม2026เวลา23:52

exec321normalno-marker/defaultfont12/app-local strictfailed233→234handles/6→7threads normal+marker samebinary/defaults failed242→243/6→7 GDIUSER3stableทั้งคู่ noTimeout/21samples/normalไม่สร้างmarker จึงportableไม่จำเป็นต่อrepro ไม่claimsharedcodeทุกอย่างไม่มีผลหรือallocationownerพิสูจน์แล้ว WIN-RUNTIME-004ยังopen no gatewaiver/OSsettings/foreignhandleclose/no speculativecodefix

Autofirst-runfeaturefulfilled helper7x2/auto-normalbuild123x2/native4/ZIPD→C/hash/preserve/Png318ผ่าน มีcleanlocalexperimental `zig-out/portable-auto-candidate-20261020.zip` userเปิดbin/localterm-dev.exeตรงได้ dataautoสร้างข้างexe ยังต้องbin/shareคู่กัน ไม่มีcommitpushpublish/credentials/copieduserdata/clipboardaccess No furtherbackgroundjobsafter321; nexthumanIME/interactiveacceptance ยังไม่ยืนยัน GPUqualificationยังpause/ไม่เปลี่ยนdefault FullCoreVT305ก่อนflagผลscopeเดิม

### Matched317ทั้งคู่failed / จัดเป็นblocker patternเดิม WIN-RUNTIME-004 รอno-markercontrol — 20ตุลาคม2026เวลา23:49

exec317normal-marker-font19 handles242→243/threads6→7 auto-existing-font19 233→234/6→7 GDIUSERstable ทั้งคู่failed จึงautoFlagไม่จำเป็นต่อrepro แต่ทั้งคู่portable modeยังไม่ตัดsharedportablepath

exec321same-normalbinary/no-marker/defaultfont12 vs marker/commentconfig(defaultfont12), app-local/gatesเดิม caseละ1 active No speculativepatches/environmentsettings/no foreignhandleclose. 318PNGผ่านไม่ปิด314/317failures

ExactsearcholdDocsพบWIN-RUNTIME-004ก่อนportable/normal62:233→234/6→7 AMDhook+NTDLLthreadchurn และlivecreatortraceบางobjectsอยู่ในwindows-runtime-attribution.md(103-129)/windows-validation.md(296,331,355)แล้ว ไม่ทำdebuggerauditเก่าซ้ำ/ไม่กล่าวว่าautoสร้างleakใหม่/ไม่equateTIDhandle跨run Moduleentryในnewinventoryสอดคล้องไม่ใช่newallocationcreatorproof

Auto-create feature/package/ZIP proofครบแล้ว มีlocalทดลอง `portable-auto-candidate-20261020.zip` qualificationgeneralยังblockedWIN-RUNTIME-004และhumanacceptance/cleanVMetc ไม่เปลี่ยนGPUdefaultเพื่อหลบgate

### Auto lifecycle strict failed / matched control active / PNGแยกผ่าน — 20 ตุลาคม2026 เวลา23:47

exec314ResourceGrowth: warmup+20cycleshandles236→237 threads6→7 GDI3→3 USER3→3 sample1handles237คงที่/threads8→10→7 ยังไม่พร้อมgeneralqualification PNGที่ต่อท้ายไม่executed

อ่านownedthreadinventoryแล้ว finalเพิ่มtid23232startAMD`amdihk64.dll`พร้อมNTDLLpoolthreadsเปลี่ยน ชื่อmoduleไม่พิสูจน์ผู้จอง/เหตุroot ไม่guessdriver/เพิ่มwarmup/disablePSS/เปลี่ยนOSsettingsให้ผ่าน

exec317matchedstrict normal-newbuild(false)+freshmarker/font19/app-local กับ auto-existingmarker/font19/app-local caseละ1 activeเก็บfailure314ไว้ exec318PNGautoportableแยกรันผ่านquotedpathparser/GDI+pixels/root/cleanup(noOSclipboard) ไม่ใช้PNGหรือZIPผ่านเป็นwaiver Sourcebinaryไม่เปลี่ยน/ไม่มีpatch speculative

### Autoportablebuild/native/ZIPD→Cผ่าน localcandidateใหม่ / extra lifecycle PNG active — 20 ตุลาคม2026 เวลา23:44

exec312helper7/7สองmodes auto=true/normal=falsebaselinebuild123/123ทั้งคู่ผ่าน directexeabsentdata/existingconfigdatahash/movedUnicode/invalidfilemarker4casesผ่าน normalcontrolterminalผ่านไม่มีmarkerสร้างใหม่ โปรไฟล์/provider/GPUdefaultไม่เปลี่ยน

exec313cleanauto package+ZIP`zig-out/portable-auto-candidate-20261020.zip`ไม่มีinitialdata→extractDไปCไทย/space/ทุกmanifesthash/CWDWindows/no terminal-providerenv/directexeสร้างrootเองผ่าน AutoEXESHA2566FA36F53DAD965E6AB5A2D5680AD26060D4D8AE785555ACCC7094CDB104819BA ZIP9763AB3A40A87C2F967AEA7BBE5332FCEA3BF62F1E54846E5D445F92309C29B3 OldZIPไม่ทับ/userauthnochanges

exec314extra lifecycle+portablePNGบนownedmovedfixture active notcleanpackageไม่clipboardจริง ไม่claimphysicalExplorerdoubleclick/IME/cleanVM/realreadonlyfullvolume FullCoreVT305ผ่านก่อนauto flagอย่าอ้างว่าเป็นfullsuiteหลังflag Newguideupdatedlocalautocandidateเปิดbin/localterm-dev.exeตรงได้ Run.cmdoptionalแค่providerbundled ไม่พกexeเดี่ยวต้องbin/shareอยู่คู่กัน

### FullCoreVTผ่านก่อนauto flag / auto-normalbuild+first-run active — 20 ตุลาคม2026 เวลา23:32

exec305Core3988/4049(61skip)89/89steps VT6722/6786(64skip)45/45steps passed Sourcefreezeปลดแล้วจึงwire Config.windows_portable_default/defaultfalse+CLIwindows-portable-default/Win32targetguard/addOptions/fromOptions/build_config export/globalstartupautohelperwhenflagtrueelseexistingLayout.init

exec312unit7x2→explicitx64MSVCbaseline auto=true prefixportable-auto-dev และ normal=false prefixportable-normal-dev→reuse6signedConPTYfilesจากportable-devไม่download→portable-auto-smoke no seededdata/no terminalproviderenv first-run/existinghash/movedUnicode/badmarker→normalcontrolmustnotcreateportable-data active Sourcefreeze ไม่มีGPU/profile/providerdefaultchanges/no commits ZIPเก่ายังไม่auto

NEXTหลังผ่าน312:pack cleanautoใหม่ด้วยpackage-portable -OmitInitialDataจากportable-auto-dev (อย่าเรียกimage-paste normal/portableharnessกับautoexeเพราะnormalcaseจะกลายportableตามrequirement) ZIP/extractcrossdrive/directexe no data proof updateThai guideพร้อมnewartifactpathและSHA ไม่อ้างliteralExplorerGUI/cleanVM/physicalreadonlyfullvolume/IMEหรือaccountsisolation

### Userขอdoubleclickautoportableไม่มีmarker / helperผ่านรอVTจบก่อนwireflag — 20 ตุลาคม2026 เวลา23:25

ผู้ใช้23:22ขอหากไม่มีportable-dataข้างexeให้สร้าง/อยู่ตรงexeได้เลย ตกลงทำเฉพาะportablebuildไม่เปลี่ยนnormaldefault/childHOME/accounts/providerDefault/GPU ไม่fallbackถ้าเขียนไม่ได้ OldZIPยังrequiresmarkerไม่อ้างautoแล้ว

exec305Coreexit0ผ่านแล้ว VTtest-lib-vtยังactiveจึงไม่แก้sharedbuildConfig/globalจนjobจบ เพิ่มnewunreferenced `src/apprt/win32/portable_auto.zig` first-runhelper independentmodule exec3097/7DebugReleaseSafeผ่าน

เพิ่มpackageOmitInitialData switch + portable-auto-smoke.ps1 syntaxผ่าน เตรียมnativeabsent-data/existingconfigdatahash/movedUnicode/invalidfilemarkerโดยไม่seeddata/provider/terminalenv มีterminal-smokeแค่offscreenautoclose ยังไม่runtimeexecuted

NEXTเมื่อexec305VTจบ:เพิ่มConfig.windows_portable_default=false/CLIwindows-portable-default,addOptions/fromOptions/build_configexport;globalWin32startupเลือกportable_auto.initเมื่อflagtrueelseLayout.initเดิม;buildexplicitx64CPUbaselineflagtrueในprefixใหม่เช่นzig-out/portable-auto-dev (ไม่ทับpreview/oldcandidate) คัดลอกsignedConPTY6filesจากportable-dev/bin แล้วรันportable-auto-smoke ก่อนpackใหม่ No source edits while active build/tests consume them.No commits/pushes/credentials/clipboard/OSsettings.

### Portable localcandidate + ZIPข้ามdriveผ่าน / fullregressionactive — 20 ตุลาคม 2026 เวลา22:48

exec303layout5/clipboard23DebugReleaseSafe/baselinebuild123ผ่าน original/normaloverlap/moved/missingresources/invalidconfig/invalidstorage6casesผ่าน และPNGnormalportableparserGDI+rootcleanupผ่าน2sessions แก้themecommandarenaแล้วจริงไม่dropgates

exec304cleanfolder`zig-out/portable-candidate-20261020` exec306ZIPคู่กัน→DไปCชื่อไทย/ช่องว่าง/CWDWindows/hashทุกmanifestfile/เลือกextractedresourcesไม่ตามenvbuildroot ผ่าน executableSHA256 ADA7F0996B1DDBA04AC7E3ED891453EC01726EFAD4978D708DF17263E57202E4 ยังไม่publish/userdata/authchanges publicguide[docs/windows-portable.md](docs/windows-portable.md)เปิดRun.cmdด้วยมือเพื่อbundledprovider

exec305fullCore/VTDebugexplicitCPUbaselineactive Sourcefreeze ยังไม่claimfullsuitepass, cleanVM, physicalIME/readonly/fullvolume,fullfiletrace หรือGPUqualification แยกบัญชีHerdrLettaยังไม่ทำ

### Portabletheme-finalizebugพบจากruntime / baseline+regression active — 20 ตุลาคม 2026 เวลา22:33

exec279layout4/clipboard22สองmodes/build123ผ่าน exec283theme/cache/writeprobe4สองmodes/build123/ThaiModel/PNGnormalportableCorePTyparser+GDI+rootcleanupผ่าน ไม่มีOSclipboardaccess

exec285harnesswindow/terminalflagsชนแก้เฉพาะharness exec290normalผ่าน packageThemeทำWin32programmaticPowerShellหายเป็นcmd/MarkerMissing พบConfig.finalize.theme replayเปลี่ยนarena แก้independentcommand/policysnapshotแล้วcloneเข้าnewarena ไม่restorepointerเก่า/ไม่dropmarkercheck

exec303unitmockAccessDeniedNoSpaceLeft+clipboard2modes→explicitx86_64-msvc/cpu=baselinebuild→newcleanpackageThai/spacerelocation+cowd/theme/negativefailclosed/normaloverlap→PNGactive Sourcefreeze ไม่อ้างVM/จริงdiskfull/physicalIME/useraccountisolation GPUqualificationpause/defaultunchanged รายละเอียดdocs/windows-portable.md

### Portablelayoutผ่าน / startup-config-tmp-resourcesintegration active — 20 ตุลาคม 2026 เวลา22:06

exec270layout3/3DebugReleaseSafeผ่าน ต่อglobalstartuplatch/app-onlytmp/portableconfig/no inheritedresourcedir-or-ancestorfallback/clipboardsharedlatchโดยไม่เปลี่ยนHOMEAPPDATAของchild oldnormalbehaviorคงไว้ Doubleclickportableเข้าterminalโดยไม่มีsmokefixture flag

exec279layout+resourceboundary/clipboard2modes→newportable-devprefixReleaseSafe(defaultGPUเดิม)active Sourcefreeze ยังไม่claimintegrationpass/portableทั้งแอป ต้องauditremainingthemes/cache/writesและpackaging-relocation-failures/docs ไม่แตะHerdrLettaaccounts/GPUqualificationยังpause

### Userpriority portableก่อน / implementationเริ่ม — 20 ตุลาคม 2026 เวลา22:00

ผู้ใช้ถามHerdr+Lettaแล้วขอterminalportableก่อน GPUqualificationpauseไม่ทิ้งsource/default/accepted62 ไม่แตะบัญชี/profileของHerdrLetta สำรวจพบportableมีเฉพาะimagecache Win32Config.default/resourcesenv+ancestorยังไม่isolate เพิ่มportable_pathscommonroot/config-data-cache-logs-tmpและfailuretests exec270CPU2modesactive ยังไม่bootstrap/config/resourcesintegrationหรือreadyclaim รายละเอียด[windows-portable.md](docs/windows-portable.md) buildทดสอบจะใช้prefixใหม่เพื่อไม่ทับpreviewที่ผู้ใช้อาจยังเปิดอยู่

### Production/testseparationและnativeผ่าน / manualpreviewต้องขออนุญาต — 20 ตุลาคม 2026 เวลา20:35

exec250images127/legacy126/no faultartifactในappinstall/wholeSHA3phases/viewport4/21healthycloses handles123→123 GDI2→2 USER1→1 threads4→1/legacyThaiGPU28checks655glyphs0fail/directVTgc0diffผ่าน ไม่มีdefaultpromotionหรือqualificationครบclaim

ขั้นถัดไปphysicalIMEต้องhumanและvisibleinteractiveGUI permission กำลังขออนุญาตไม่เปิดเอง ไม่ใช้manualtestล้างold181close/244cleanup/perf/GPUbusyblockersและไม่stresspassกลบfail source/candidateคงไว้ไม่มีcommitpush

### Late-rendered8runsผ่านแต่244ยังunexplained / productionseparationactive — 20 ตุลาคม 2026 เวลา20:26

exec2498/8 ACK0/exited1/child1/jobempty1/forced1/handles62→62ทุกrun realreadbackก่อน50ms/latepub203–219ms/exactRGBA/rejectผ่าน ไม่ถือแก้244cleanupflake ไม่stressวนต่อเพื่อกลบfailure และไม่driver-busyproof

exec250productionimages+legacybuild/testartifactnotappinstall→nativewholeSHA/viewport/strict21life/legacyThaiRGBAactive Sourcefreeze ไม่เปลี่ยนdefault/accepted62/foreground/driver old181closeและ244cleanupยังopen รวมphysicalIME/perfqualification/GPUbusy

### Latefixtureครั้งแรกcleanupfailยังไม่rootcause / boundeddiagnostic active — 20 ตุลาคม 2026 เวลา20:23

exec244MSVC/build32ผ่าน timing/pixels/rejectผ่านก่อนLateRenderedCleanupFailed combinedassert ไม่มีค่าแยก ห้ามอ้างgateclosed exec247เพิ่มdiagnosticno semanticschangeแล้วผ่านrendered+0ms/published+219ms exact128RGBA/reject/reap/handles0 ไม่ใช่fix244

exec249receiptทุกrun ACK/exit/job/forced/handles/bounded8runsstopfirstfailureactive no warmup/timeout/waivechanges Sourcefreeze exec244cleanupflakeยังunexplainedและแยกจากexec181postACKWorkerCloseFailed GPUbusy/manual/perfยังpending

### 3variantintegrationผ่าน/no perfwinclaim / safe real-late-rendered-reply gate active — 20 ตุลาคม 2026 เวลา20:11

exec238images/textonly/legacybuild+wholeSHA/Thai/viewport/strict42life/legacyRGBA/profile4ผ่าน remoteCPU25297/18406msframes893/720 vslegacy20578/7078frames1186/575 ปริมาณงานและframesต่างมากไม่claimperfimproved/qualified หยุดmicrooptimizationก่อนปิดfailuregate

exec244MSVCprod/test+separatetestworkerroot→warm2actualGPUframes→thirdGPUreadback/finishก่อน50ms→test-onlyCPUdelay200mspublishlateexact128RGBA/neveracceptedhealthy/ownedreap2runsactive Sourcefreeze defaultprodbranchcompiledout/testworkerไม่appinstall/no driverpause/GPUhangclaim cleanup5s/postfailureobservation1sแยกจากRPC50msเดิม oldpostACKclosefault/GPUbusy/manualยังpending

### ScratchCPU+nativeClientOOMผ่าน / 3variantintegrationactive — 20 ตุลาคม 2026 เวลา19:54

exec23739/39Debug+ReleaseSafe/client32/32+actualinitrequest/helloreply/closereplyOOMbalancedbytes/repeatedaborthandles0+oldnegative/race/privateRetainedframeผ่าน ไม่borrow/reuseResponse exec238nativeimages/text-only/legacybuild→wholeSHA/Thai/viewport/strict42closes/legacyRGBA→profile4casesactive sourcefreeze ไม่มีdefaultpromotion/wire/cadence/timeout/gateschanges ผลperfยังไม่claim

### FullpostownerCoreVTผ่าน / approvedboundedrequestscratch active — 20 ตุลาคม 2026 เวลา19:50

exec235Core89/89steps3981/4042pass61skip VT45/45steps6722/6786pass64skip exit0 ผู้ใช้19:15ตอบได้เรื่องscratch หลังSourcefreezeจบเพิ่มRequestBufferboundedgeometric<=header+requestlimit/exactencodedlength/growreplacementfirstOOMretain/closeabortfreeevenrepeated ไม่reuseFrameResponse/no wire/validation/cadence/budgetchanges

exec237CPU2modesreuse/growth/cap/OOM/deinit→actualClientinitrequest/helloreply/closereplyOOM+balancedbytes/repeatedabort/handles0+oldnegative/retainedframes/raceactive Sourcefreeze ยังไม่native/perfpassclaim originalclosefault/GPUbusy/manual/perfqualifiedยังpending

### Read-onlyownershipauditจบ/no newbugในpathsที่อ่าน — 20 ตุลาคม 2026 เวลา19:14

task6ตรวจbasefree/allocator/exactresponse/singleownerlatestframe/stalerelease/UIconvert-beforefree/legacyseparatememoryแล้วไม่พบownershipbugใหม่ ไม่ได้รันทดสอบ แนะนำboundedClientrequestserializationreuse onecandidate ไม่แตะliveResponseOwnedFrame ยังไม่measuredbottleneck/perfguarantee รอexec235CoreVTจบก่อนแก้Sourcefreeze

### Privateownershipcheckpointผ่าน / fullpostpatchregression+read-onlyaudit active — 20 ตุลาคม 2026 เวลา19:08

exec233CPU37/37สองmodes/retainedredaftergreen+5natural-failure reaps/remotelegacybuild/nativewholeSHA/viewport/21lifeผ่าน remotepacedparent9562.5+worker7515=17077.5ms/952frames vslegacy7953.125/965 ไม่มีoverallperfwinclaim SourceCPUไม่borrowmapping/interiorfree

exec235fullCore/VTDebugpostpatchactive Sourcefreeze task5generalpurpose拒งานOlufyonlyไม่ได้review→singlecleanrecoveryforktask6read-onlyownership/copy/validationauditactive ห้ามcountrefusalเป็นreview/no templateconfigedits originalclosefault/GPUbusy/manual/perfยังpending ไม่มีdefaultpromote/commit/push

### CPUphaseพบRPC82% / privateReplyownershiptransfer active — 20 ตุลาคม 2026 เวลา18:51

exec226remote127/legacy126/profile2casesผ่าน Capture16.98/17.14% RPC82.59/82.42% publish0.43/0.44% renderer-threadcyclesเฉพาะช่วงวัดไม่wholeparent/wall/shaping/free ห้ามเดาว่าGPUtargetแก้หลักแล้ว

พบSession.copyRgbaalloc/copyซ้ำหลังCprivateResponseแล้ว เพิ่มCpuFrame.takeRgbaโอนprivatebaseเข้าพร้อมpixelsviewoffset64/deinitfreebackingเดิม callerbytesemptyเมื่อsuccess/errorretain original ไม่sharedborrow/no decoder/wire/module/cadence/budgetchange exec233CPU2modes/Clientretained5failure-naturallifetimes→nativeboth→wholeSHA/viewport/21life/profile4casesactive Sourcefreeze ไม่claimperfimproved/ready/oldclosefixed

### Targetreusecorrectnessผ่านแต่pacedcostยังสูง / CPUphaseattribution active — 20 ตุลาคม 2026 เวลา18:39

exec221targetstable10/resize9x5return8x4created3/2textures2FBOold+finaldestroy/pixelreturnexact+image3band/clientfault+nativewholeSHA/viewport/strict21lifeผ่าน Profile remoteCPU29046/19406ms frames1076/946 vslegacy33422/7500 frames2253/991 ไม่อ้างpacedperfimproved

exec226profile-fixture-onlyQueryThreadCycleTime4pointsบนrendererthreadเพื่อแยกcapture/RPC/publish/packetbytes buildremote+legacyแล้วprofile2casesactive ยังไม่optimizationwire/ownership/decoder/modulegate ไม่ลดcadence/budget Sourcefreeze ไม่แปลงcyclesเป็นwallms/wholeparentCPU originalclosefault/GPUbusy/manualยังpending

### Ownedmetricsผ่านเผยpacedoverhead / workerFBOreuse active — 20 ตุลาคม 2026 เวลา18:31

exec215MSVC/client/native21+4profilesผ่าน remote sumCPU29593ms/18578ms frames1106/945 vslegacy33203/7969 frames2102/981 sumpeakWSupper273.6/226.2vs236.7/181.6MiB mixedCPUwindows/nonuniquepeakไม่อ้างoverallwin pacedoverheadยังต้องลด

พบTextGpuExecutorสร้างTarget2textures/FBOทุกframe เปลี่ยนworkercontext-ownedcachebydimensions/fullcleareveryframe/replacementก่อนdestroyresize/deinitonce ไม่แตะsharedlegacyTarget/protocol/cadence/budget exec221component12frameidentity+9x5return8x4+alltextures/FBOdeletion→image3band/clientfault→nativewholeSHA/viewport21life→remotelegacyprofilesactive Sourcefreeze ยังไม่claimperfimprovedหรือoriginalclosefixed

### Profile4closebudgetผ่าน แต่ยังไม่overallperfqualified / ownedmetrics active — 20 ตุลาคม 2026 เวลา18:23

exec212remote/legacyprofile+paced4cases25scloseผ่าน Parentonly(remoteCPU20609/11219ms vslegacy32781/7234ms;frames961/897vs1947/983) ไม่อ้างremoteรวมเบากว่า/เร็วกว่า เพราะworkerCPU/RAMexcludedและpacedparentCPUสูงกว่า

เพิ่มdiagnostic-onlyCmetrics250msผ่านexistingownedprocessHANDLE/K32meminfo/CPUtimesหลังexit ไม่มีPIDdiscovery/newhandles/ABI/protocol/budgetchanges exec215MSVCprod/test/clientneg+race→native21strictlife+metrics→remote/legacyprofile4casesหลังbuildactive Sourcefreeze รวมpeakเป็นupperboundไม่ใช่unique/simultaneousRAM/VRAM/ConPTY/shell ยังoriginalclosefault/GPUbusy/manualpending

### libVTDebugผ่าน / M5performanceisolated active — 20 ตุลาคม 2026 เวลา18:21

exec21145/45steps6722/6786pass64skip exit0 requiredDebugslow-runtime-safetyโดยไม่แก้assert/Core ต่างจากReleaseSafeinvokefailที่เก็บไว้ exec212remote/legacyprofile+profile-paced sequentialหลังbuildจบ/PSSเดิม/25sclosegateactive Sourcefreeze hostsamplesไม่ใช่totalparent+GPUworkerfootprint ยังoriginalpostACKfault/realGPUbusy/manualIMEunverified ไม่มีdefaultpromote/commit/push

สรุปที่อ่านแยกจาก chronology: [GPU worker checkpoint](docs/windows-render-worker-checkpoint-th.md)

### Core/codecผ่าน / libVTต้องDebugตามtestcontract — 20 ตุลาคม 2026 เวลา17:55

exec207codec36/36ทั้งDebug+ReleaseSafe;fullCore89/89,3981/4042pass61skip exit0 **CoretestexeบังคับDebugในbuild.zigแม้CLIส่งReleaseSafe** แก้คำเรียกstageก่อนหน้าให้ตรง ไม่อ้างCoreReleaseSafecoverage

libVTReleaseSafecompilefailPageList5754comptimeassertslow_runtime_safety→quirks54:Config736เปิดsafetyเฉพาะDebug/test-lib-vtใช้modeตามCLI ไม่แก้PageList/quirks/assert/เพิ่มskip exec211ทวนlibVTDebugตามrequiredconfigurationactive Sourcefreeze เก็บReleaseSafeinvokefailureไว้ M5ยังไม่ครบ/performanceยังไม่เริ่มเพราะไม่ปนbuildload

### M4automated5casesผ่าน / M5CoreVTcheckpoint active — 20 ตุลาคม 2026 เวลา17:39

exec204input173850ASCII/Thai/surrogate/Enter/repeat2;mouse173900selection/copyinmemory/wheelscroll/captureloss;exit173911;burst1739121688frames;title1739231644frames/backpressure4ผ่านทุกcaseoffscreenparentnoGL/healthyteardown/surfaces0 ไม่มีOSclipboard/globalinput ไม่ใช่physicalIME/manualacceptance

exec207M5CPUimagecodecDebug/ReleaseSafe→fullCoreReleaseSafe→libVTReleaseSafeactive sequential/sourcefreeze finiteeventmonitorแต่ละstage Performanceจะรันหลังbuildloadจบไม่ปนกัน OriginalpostACKWorkerCloseFailed/realGPU-busyhang/manualIME/performanceยังopen ไม่defaultpromote/commit/push

### Whole-frameKittylegacyparityผ่าน / M4controlledinteraction active — 20 ตุลาคม 2026 เวลา17:36

exec199images127/legacy126+actualConPTY/GDIremote2runs/legacy2runsผ่าน ทั้ง3phasewholeBGRA2733896bytes SHA256ตรงทุกrun:red6796d25b…/greenb39e832d…/delete779abb75… ไม่มีthresholdwaiver ไม่ใช่ทุกimageformat/crop/zorder/manualacceptance;originalpostACKWorkerCloseFailedยังopen

exec204M4currentimageoptinbinary inputASCII/Thai/surrogate/Enter→mouseownedHWNDselection/scroll/captureloss(inmemoryclipboardเท่านั้น)→naturalchildexit/outputburst/titlebackpressureactive ไม่มีOSclipboard/globalinput/foregroundGUI/sourcechanges physicalIME/manualยังต้องมนุษย์verify ไม่มีdefaultpromote/commit/push

### Native3variantsผ่าน / whole-frameKittylegacyreference active — 20 ตุลาคม 2026 เวลา17:24 เป็นต้นมา

exec197exit0images127/defaulttext127/legacy126:Kitty2+viewport4+Thai+strict21healthyteardownทั้ง2remoteผ่าน;legacytextRGBA29checks/max655glyph/fail0/diffbytes0ผ่าน monitorENDPASSจบ ยังไม่historicalpostACKfaultfixed

เพิ่มfixture-only-KittyImageLegacyReference/envreference(ต้องKitty/legacybuildจริง) remoteยังต้องimageflag/noGL/healthyworker;หลังGDIแต่ละ3phasehashENTIREBGRAbytecount+SHA256 ไม่ใช่แค่นับสี/defaultทั้งคู่false exec199buildimages2runs→legacyreference2runs/ทุกphasehashต้องตรงactive Sourcefreeze ไม่ปรับthreshold/ไม่Core/PTY/driver/accepted62promote/commit/push

### Separaterace red→green2ผ่าน / native3variants active — 20 ตุลาคม 2026 เวลา17:12

exec196MSVCC11W4WXprod/test+build30+green1/2ผ่าน realclosed+naturalexitพร้อมhealthynatural/job0/handles0 และstop+exit+closedพร้อมcancelwins/nohealthy/forcedcleanup0handles เดิมnegative/lateclose/text-imageSessionผ่าน OriginalpostACKWorkerCloseFailedไม่ยกเป็นfixed

exec197native3variantsimageKitty2/viewport4/Thai/21healthyteardown→text-onlyviewport/Thai/21→legacyexactRGBAactive มีfiniteeventsmonitorต่อvariant/stoponfailure Sourcefreezeไม่มีdefaultpromotion/driver/CorePTYinput/commit/push

### Separatereplyrace redพิสูจน์แล้ว / scopedgreen+cancelcontrol active — 20 ตุลาคม 2026 เวลา17:08

exec195build30ผ่าน/newregressionexit1EXPECTEDREDตรงWorkerCommunicationFailedหลังactualclosed+naturalexitพร้อม/ownedcleanuphandles0 เก่าnormalneg/imagechecksผ่าน ไม่ใช่suitepassหรือoriginalWorkerCloseFailedcause

แก้Cclosekind10ONLYเมื่อWaitได้process1ให้เช็คstopก่อนแล้วconsumealready-signaledresponse0ms→commonpacketvalidation→Client.finishยังต้องexit0/jobempty/ไม่forced ไม่promote timeout/render ไม่เพิ่มbudget เพิ่มtest-onlystopพร้อมทั้งprocess+closedcontrolต้องcancelwins exec196MSVCW4WXprod/test+green2normalneg/imageSessions/lateclosecontrolsactive Sourcefreeze originalcycle15ยังopen

### Teardownevidenceผ่าน / deterministicseparateclose-replyrace redtest active — 20 ตุลาคม 2026 เวลา17:04 เป็นต้นมา

exec192MSVCC11W4WXproduction+test/client30/native127ผ่าน;native170320ครบ21executor/context/device/runend+naturalACK/handles123→123/GDI2→2/USER1→1;Kitty1704313postGDIphases+healthycloseผ่าน originalcycle15causeยังunknown

เลิกสุ่มstressต่อ เพิ่มtest-onlymacrohookรอownedworkerexitจริง+ตรวจpublishedclosed/eventเดิมก่อนparentwait ใช้budgetที่เหลือไม่ขยาย/ไม่pause thread/driver productionmacro=1no-op/priorityยังเดิม exec195build→EXPECTEDREDreproWorkerCommunicationFailed(handles0)active หลังnormalnegative/imagechecks ไม่มีอ้างredtestเป็นsuitepassหรือแก้historicalWorkerCloseFailed Sourcefreeze

### Bounded105sessionsผ่าน/no originalfaultrepro / teardownevidence active — 20 ตุลาคม 2026 เวลา16:58 เป็นต้นมา

exec1895/5sets105healthyclosescounters123→123/GDI2→2/USER1→1/threads4→1ผ่าน monitorEND+exit0หยุดเอง ยังไม่แก้cycle15cause/ไม่rerunstressเพิ่มไม่จำกัด

เพิ่มdiagnostic-onlyCprocesswaitresult+underlyingWinerror/exitcodequery/jobactive/queryerror/elapsedbudgetบนreapfailure ไม่มีABI/order/deadline/returnsเปลี่ยน Workerclosemarkersหลังpublish→executor/context/device begin/end→GPUcleanup→run-complete ไม่เปลี่ยนdeferorder Loggingอาจperturbtimingจึงไม่ใช้absenceoffaultเป็นfixproof

exec192MSVCC11W4WXทั้งproduction/test→clientnegative/imageSession→native21strictlifeพร้อม21teardownchains+KittyGDIactive Sourcefreeze originalclosefaultและseparateresponse/processrace/launchriskยังopen ไม่promote/default/driver/CorePTYinput/commit/push

### Read-onlycloseaudit / originalfaultยังไม่มีfixที่มีหลักฐาน — 20 ตุลาคม 2026 เวลา16:55

task4ยืนยันworkerdefer/Sessionpoison/reapjobpollถูก ไม่justifyfixcycle15จากstressผ่าน Findingsแยก: C.rw_callwaitpriorityprocessก่อนresponseอาจrejectclosedที่publishก่อนexitเป็นWorkerCommunicationFailed(ไม่ใช่observedWorkerCloseFailed);C.reapรวมAPIerrors/deadlineเป็นERROR_TIMEOUT;temporaryinheritablelaunchhandles+CommandinheritTRUE/sharedserializationไม่พบเป็นriskยังไม่พิสูจน์cause ห้ามเปลี่ยนCoreCommand/PTYเงียบๆ

exec189monitor2/5=42healthyclosesผ่าน/stressยังactive Sourcefreeze หากfaultreproอ่านoriginalstatus+childstderrก่อน จากนั้นค่อยboundedreapAPI/workerexecutor-WGLteardownmarkersถ้า1460ยังคลุมเครือ

### Diagnostics42healthyclose+Kittyผ่าน / originalclosefaultยังunresolved — 20 ตุลาคม 2026 เวลา16:51

exec188client30/nativebuild+clientneg/imageSessionผ่าน;strictlifecycle2sets42healthyworkers/nohandleGDIUSERgrowth และKitty165051/165102red6624→green6624→removed0หลังGDIผ่าน ไม่reproclosefault ไม่ใช่rootcausefix

exec189bounded5×21=105sessionsบนbinaryเดิมactive/stopfirstfault/strict21ACKทุกset/เดิมbudgetและcriticalgate;finiteeventmonitorแจ้งแต่ละsetและจบเอง ไม่rerununtilgreen task4forkread-onlyreviewcloseownership/status/teardown ไม่มีtests/edits Sourcefreeze ฝากclosefaultเป็นblockerต่อแม้stresspassจนมีcausalproof

### ActualKittyGDIสองรอบผ่าน / cycle15naturalclosefault ต้องหาสาเหตุ — 20 ตุลาคม 2026 เวลา16:36

exec181127stepsผ่าน;actualConPTYKitty163422+163434 red6624→green6624→removed0หลังGDIpaint/parentnoGL/healthycloseผ่านทั้ง2 viewport163444ครบ4+staledrop/Thai163451diff0ผ่าน

แต่lifecycle163502criticalerrorcycle15WorkerCloseFailed (20healthyACKไม่ครบ21);exit0/handles123→123/GDI2→2/USER1→1/threads4→1ไม่ลบล้างfault gateจับถูก ไม่ใช่wrapperfalsepositive ต้นเหตุยังไม่ทราบC.reapมีboundedjobpollอยู่แล้ว ไม่guessfix

เพิ่มClient.logoriginalrw_finish/statusก่อนSession.failabortทับstatus และsmoke-onlychildstderrผ่านexistingCdiagnosticsallowlist (normalhostยังNUL) ไม่มีtimeout/reap/gateเปลี่ยน exec188clientregression/nativebuild/strictlifecycle2sets+Kitty2runsactive Sourcefreeze หากทวนผ่านก็ยังไม่แปลว่าcycle15ต้นเหตุแก้แล้ว

### Native3variantsผ่าน / actualConPTYKittyGDIphase fixture active — 20 ตุลาคม 2026 เวลา16:24 เป็นต้นมา

exec178images127steps/viewport2runsA-B-C-A+stale2/Thai/strictlife123→123;defaulttext127steps/viewport4/Thai/strictlife128→128;ทั้งคู่GDI2→2/USER1→1/threads4→1/21healthyworkers Legacy126steps/newsourceRGBA18checks655glyphfail0ผ่าน No actualKittypayloadใน178

เพิ่ม-KittyImageSmoke standaloneapp-localเฉพาะimagebuildflag:publicsyntheticRGBAส่งจริงผ่านchildConPTYAPCa=T i77 red→sameIDgreenreplacement→deleteI(no file/clipboard/parser bypass) AppobserveAFTERGDIpaintต้องred>=1024→green>=1024→clearedก่อนclosing;receiptstrictphases/parentnoGL/healthyworker โหมดเก่าค่าfalseเหมือนเดิม viewportscriptreceiptตามApp4minimumแล้ว

exec181buildexperimentalimageprefix→actualKitty2runs→viewport4/Thai/strictlifeactive Sourcefreeze ยังไม่legacyimageRGBAparity/qualification/performance/defaultpromotion CorePTYinput/driver/settingsไม่แก้

### Viewportfixture initialpresentationrace / stronger4sizegate active — 20 ตุลาคม 2026 เวลา16:05

exec174provisionpin+MSsignatureผ่าน/PTYmarkerกลับมา แต่viewportมีB/C/A3sizes ไม่มีinitialAเพราะtimerเริ่มresizeก่อนUIรับframeแรก กลับoriginalถูกเทียบกับfirstBจึงfailcoverage ไม่waive/no retryunchanged

แก้fixtureONLYhookviewport_presentedให้WM_TIMERไม่advanceจนUIconsumecurrentexpectedA/B/C/Aจริง;nonblocking/no sleeps/auto-close10sเดิม และstrengthenAppminimum3→4 matchingexisting4sizeintent/stale-dropยังต้องผ่าน Productionresize/renderer/PTYไม่เปลี่ยน exec1783variantsbuild+imagesviewport2runs/defaulttextviewport/Thai/strictlife2variants/legacyRGBAactive Sourcefreeze

### NewprefixmissingConPTY dependency / verifiedprovisionretest active — 20 ตุลาคม 2026 เวลา16:02

exec165imagesbuild127stepsผ่าน แต่viewportmarkerfailเพราะstderrชัดapp-localConPTY.MOD_NOT_FOUND→PTYinitfail/IOabrupt ไม่ใช่renderererror/ไม่waivemarker ขนาด4sizes+staledrop2ผ่านเป็นpartialเท่านั้น text/legacyยังไม่ได้run

exec174unchangedsourceretest3variantsactive ใช้repo provision-conpty-experiment.ps1ก่อนsmokeแต่ละprefix(pinNuGetSHA+Microsoftsignature/no overwrite mismatch/workspace-only),sameapp-localprovider/no systemfallback/timeout unchanged ไม่แก้PTY/Core/driver/settings No actualKittyfixtureclaim Sourcefreeze

### CPUStatecaptureCoreผ่าน / experimentalparentimageflag build active — หลัง20 ตุลาคม 2026 เวลา15:54

exec160unfilteredCore89steps3981/4042pass61skipผ่าน realKittycompletedpendingcapture/retain-copy/pruneCPUunloads/GPUstateguard/allallocationfailures

เพิ่ม-Dwindows-remote-images=false(default) requiresremote=true;เปิดเฉพาะflagใหม่นี้จึงClienthello3/captureImageFrameLocked→StateCPU+textshared→combinedownedpacket→Session.image;normalremoteยังhello1/textguardเดิมและlegacyเดิม Background/customshader/overlayยังreject Captureใต้draw/fontsharedlock/RPCหลังunlock/dimensionepoch/dropเหมือนเดิม

exec165activebuildnewimagesprefix→defaulttextprefix→legacyprefix+worker แล้วoffscreenTEXTONLYviewport/Thai/strictlifecycle2remotevariantsและlegacyexactRGBA ยังไม่actualConPTYKittyimagefixture/nativeimageparity Sourcefreeze ไม่promoteaccepted62/default/driver/CorePTYinput/commit/push

### ProductionimageSessionผ่าน / realimageStateCPUcapture fullCore active — หลัง20 ตุลาคม 2026 เวลา15:33

exec154CPU36/36ทั้งmodes/check2runs/oldlegacy152308exact31checks655glyphfail0/remotenative125/viewport152713staledrop2/Thai152721diff0/lifecycle152731strict123→123/GDI2→2/USER1→1/threads4→1/21healthyworkersผ่าน

exec15630steps+2runs productionSession.renderImageFrameผ่าน2actualimageframesก่อนkill77/cancel/localstaleepoch/peerstalegen:poison/autoreap/jobempty/noIPC/nohealthyclose/percasehandles0/nogpuparent+healthycontrol Sessiontext/imageใช้viewportvalidatorเดียวกัน

เพิ่มrenderer/image.State.captureCpuSnapshot(ยังไม่ต่อGeneric/Remote):retainactualpendingRGBA/no.ready,preflightrejectGPUstates+overlay,pruneonlyunload_pendingCPU,sortedIDs+actualplacementgen→ownedSnapshot;3newStateunits+realKittypendingfixturecapture+allallocationfailures **exec160fullCoreunfilteredactive** Sourcefreeze No runtimeinlineguard/default/accepted62/driver/CorePTYinput/commit/pushchange

### GPU3bandcompositeผ่าน+oldtextparity0 / opt-inimageIPC active — 20 ตุลาคม 2026 เวลา15:17 เป็นต้นมา

exec15134steps+2composite10frame-runsผ่านthresholds/crop/negativeclip/reuse/delete;oldtextcache10frames/negativecachedkill-cancelผ่าน;legacyoldbinary151651exact30checks/max655glyph/fail0/healthyclose

เพิ่มoptionalhello4Bflags3+kind17(ต้องepoch),emptyhello/flags1+kind8เดิมคงเดิม ClientOpts.inline_images=falsedefault,non-opt-localrejectก่อนIPC;workeracceptkind17เฉพาะnegotiated,returnsRGBAABIเดิม ไม่มีParentSession/adapter/guardเปิดimage

exec154activeCPU2modes/checkbuild+2runs(imageIPCexactred-green16pixels/raw-nooptreject/handles0/noGPUparent)/oldlegacybinaryparity/defaultremote-build→viewport/Thai/strictlifecycle Sourcefreeze ไม่claimterminalKittylegacyparity/default/driver/accepted62/commit/push

### GPUimageupload-cacheผ่าน / composited3bands active — 20 ตุลาคม 2026 เวลา15:11 เป็นต้นมา

exec14928steps+2GPUrunsผ่านactual2DsRGBAreadback/reuse/genreplace/resize/stale-contentreject/IDmissing-emptydelete/IDreuse/GLcleanup ไม่ใช่image drawหรือIPCproof

เพิ่มcandidateExecutor.renderImageFrame→validatedtext+imageview/sharedrenderDecoded ใช้ImageGpuCache+legacyimagepipeline/vertexlayout/order3bands(z<minInt/2,negative,nonnegative),ทุกdrawerrorpropagate และplainText/emptyลบimagecache Rawworkerhandlerยังtext-only/parentguardคงเดิม

exec151activebuildcomponent+rawworker→GPUcomposite10frames2runs exactzthreshold/red-whitecounts/crop-negativeclip/placementreuse/remove/plaincleanup→oldtext10framecache→transportnegative→legacyThaiRGBAparity Sourcefreeze ไม่claimIPC/terminalKittyparity/default/driver/accepted62/commit/push

### GPUimagecache compile correction — 20 ตุลาคม 2026 เวลา15:09

exec148compilefail25/28เพราะZig0.16ArrayListไม่มีdefaultitems(`.{}`) ไม่มีGPUrun แก้เป็น`.empty`เฉพาะจุด exec149build→run2active คงpixel/gen/content/deletiongatesทั้งหมด Sourcefreeze ไม่เปิดruntime/inlineguard/default/driver/accepted62/commit/push

### CPUtext+image35/35ผ่าน / GPUupload-cachecomponent active — หลัง20 ตุลาคม 2026 เวลา15:03

exec146correct-root35/35Debug/ReleaseSafeผ่าน เพิ่มunwiredworker-onlyImageGpuCachefullsnapshotsync(ID/gen/dims/noncryptofingerprintpreflight,CPUreserveก่อนGPUalloc,create-before-delete/evictmissing/empty/contextcleanup) Texture2DsRGBAlinearตรงlegacy

exec148build/newhiddenGPUcomponentrun2active exactRGBAuploadreadback/reuse/replace/resize/stale-contentreject/GLdelete ไม่ใช่image rendering/IPC/runtime/terminalparity No guard/default/accepted62/driver/commit/pushchanges Sourcefreezeชุดที่รัน

### Aggregate13/13สองmodesผ่าน / outertext+imagecodecกำลังทวน — หลัง20 ตุลาคม 2026 เวลา14:59

exec14413/13ทั้งDebug/ReleaseSafe เพิ่มunwiredImageFramecombinedheader24+text+imagespayloadbudget/sharedcellsize/ownedcopy/flagslengthguard รันremote-rootตรงติดoutside-modulepathก่อนtests แก้testentrypointsrc/render_worker_image_codec_tests.zigแทน ไม่หลบcompilerguard

exec146correct-rootDebug/ReleaseSafeactive ยังไม่peernegotiation/workerupload/GPUKittycache/drawband/parentCPUadapter/parity ไม่ปลดinlineguard/default/accepted62/driver/commit/push Sourcefreezecandidate suite

### Placementcodec8/8สองmodesผ่าน / aggregateimagecandidate active — 20 ตุลาคม 2026 เวลา14:55

exec143Debug/ReleaseSafe8/8(4placement4resource)ผ่าน เพิ่มunwiredImageSnapshotIMS1header/offsettable/fullownedresource+placements codec sortedIDs/zorder/idgen/crop/celloffset/aggregatebytes-count checkedก่อนsinglealloc+binarylookup/emptydelete Resource.encodeIntoไม่tempallocateซ้ำ

exec144Debug/ReleaseSafeunitsactive ยังไม่outertext+imagebudget/wire/upload/drawbands/ACK/cacheintegration ไม่ปลดguard/default/accepted62/driver/commit/push Sourcefreezeเฉพาะcandidatecodecที่ทดสอบ

### Pre-imageCorecheckpointผ่าน / signedplacementcodec active — 20 ตุลาคม 2026 เวลา14:50

exec136ReleaseSafeimage4/4+Core3964/4025pass61skip89steps/exit0 ยืนยันfailed-commandบรรทัดเป็นZig0.16stderrdiagnosticprinterจากlocalstd/Buildและcompiler/build_runner(no-matter-result)ไม่ใช่testfail เก็บหลักฐานไม่ลบlog

เพิ่มunwiredImagePlacement56B LE Id/gen64/signedxyz/dest/celloffset/cropตรวจstaleresource/cropoverflow/destcaps exec143Debug/ReleaseSafeunitsactive ยังไม่มีaggregatecount/bytebudget/sort/cellsizevalidateครบ ไม่ต่อwire/workerimages/ไม่ปลดguard/default/driver/accepted62/commit/push

### Colorcache10frames/Cstrictผ่าน / candidateimagecodec4unitsผ่าน — หลัง20 ตุลาคม 2026 เวลา14:31

exec13228steps+2runsผ่านgraymask/BGRAred-green-white/counters1,5,15/GLdelete;MSVCC11W4WXproduction/testCผ่าน Forktask_3read-onlyimagemapสำเร็จ CPUgeneration/pixelsกับplacementsdirtyแยก,3Kittybands/order/2DsRGBAlinearfilter ห้ามparent.readyfake/GPUupload/ACKdropเมื่อviewportstale

เพิ่มunwiredCPUcandidateImageResource32BheaderownedRGBA/id/gen64LE/caps/length4Debugunitsผ่าน ยังไม่เปิดinlineimages/ไม่แก้textschema/ไม่มีplacementsหรือaggregatebudgetครบ exec136activeReleaseSafe4+fullCoreล่าสุด4standaloneไม่บวกในCorecount Sourcefreezeไฟล์ที่consume ไม่มีdefault/accepted62/driver/commit/pushchanges

### Cached-rendered-resourcefailureผ่าน / coloratlascheck+imagemap active — 20 ตุลาคม 2026 เวลา14:29

exec13130steps+2runsผ่านkill77/cancelหลังreal2GPUframes/cachedresources:autoreap/jobempty/per-casehandles0/noGPUparent/poison/noIPC/noACK;idle-timeout50msactual47/62ms ไม่ใช่busyGPUhang/globalVRAMproof

exec132activeGPUcache10frames graymask+BGRAcolorglyphred/green/white/counters1,5,15/deletedTextureสองรอบ ไม่เปลี่ยนproductionfrom128 Forktask_3read-onlyKittyimagemap activeแทนOlufyscopeagenttask_2ที่ปฏิเสธและไม่inspect/edit ไม่มีdefault/driver/accepted62/commit/pushchanges

### CachedGPUresourceผ่าน+terminalexactparity / post-drawfailuretests active — 20 ตุลาคม 2026 เวลา14:26

exec128cache7GPUframes/counters1programSet5atlasCreates9updates/visible+maskchange-revert/GLdeleted,legacyexact16checks/max655glyph/fail0,remoteviewport142457/Thai142503diff0/lifecycle142514strict123→123handles/GDI2→2/USER1→1/threads4→1/21healthyworkersผ่าน ยังไม่performance/image/restartqualification

exec131activeSessionnegative4caseรวมkill77/cancel**หลัง2realvisible-glyphframesและcachedresourcesอยู่** ต้องauto-reapก่อนcallerabort/noACK/noIPCต่อ/per-casehandles0/noGPUparentสองรอบ Sourcefreeze Read-onlyagenttask_2สำรวจKittyCPUimage/placement/wire/draworderขอบเขตM3ถัดไปเท่านั้น ไม่แก้Core/PTY/input/default/driver/accepted62/commit/push

### GPUcachefixtureพบtransparentcursor / แก้fixtureกำลังทวน — 20 ตุลาคม 2026 เวลา14:22

exec12431stepsผ่านแต่GlyphNotDrawn จึงไม่รันlegacyparity/remoteตามหลัง อ่านactualvertexshaderยืนยันcursor0,0overrideglyphด้วยtransparentcursorcolor แก้fixturehiddenu16maxไม่เปลี่ยนshader/glyphthreshold แล้วเพิ่มmask0→255same-sizeupdateต้องpixelsเปลี่ยนและคืนglyph

exec128active7GPUframes(shaderSet1/atlascreates5/updates9/visiblepixels+mutation+GLdelete)→legacyexactThaiRGBAparity→remotebuild/viewport/Thai/lifecycle Sourcefreezeไม่performance/default/driver/accepted62/commit/pushclaim

### Sessionauto-cleanupผ่าน / context-ownedGPUcacheกำลังทวน — 20 ตุลาคม 2026 เวลา14:14 เป็นต้นมา

exec117check30/30+Sessioninvalidframe/ownedexit77poison-autoabort/noIPC/handles0+negativeidleTimeout47ms/lateclosedผ่าน remote125/viewport141255/Thai141303diff0/lifecycle141314strict123→123handles/GDI2→2/USER1→1/threads4→1/21healthyworkersผ่าน ไม่ใช่UIcrashinjection/autorestartproof

exec124active Workercontext-ownedExecutor:lazyprogramset1,atlasfullupdateเมื่อdimsเดิม/create-before-deleteเมื่อเปลี่ยน(ยังfullsnapshot/noimages),GPUcachecheck5visible-glyphframes/pixel-identical/odd1,3,5/counters1,5,5/GLIsTexturedeleted/invalid0→newGPUworkerlegacyexactThaiRGBAparity→remotebuild/viewport/Thai/strictlifecycle Sourcefreeze ไม่มีperformanceclaimหรือdefault/driver/accepted62/commit/pushchanges

### UI/mailboxepochgapแก้ผ่าน+post-M3Coreผ่าน / failurecleanupactive — 20 ตุลาคม 2026 เวลา14:06 เป็นต้นมา

exec113exit0 remote125/actualstaledropviewport2รอบ+4correctpairs/odd1117+Areturn/Thai diff0,legacy123/window135209handles125→125no-terminal+Thai135223,latestCore3964/4025pass61skip89steps ไม่ลดgate ไม่claimwindow-onlyแก้legacyterminalleak

exec117active productionSessionpoison/errorautoabort+reap/noIPCต่อ/ไม่มีhealthyclose,Remote/Genericcatch failoutsideLocksและhealthunhealthyinstantnotify. TestSessioninvalidframe+ownedkill77ต้องcleanupก่อนcallerabortและเรียกซ้ำไม่ส่งIPC รวมnegative/timeoutเดิม→remotebuild→viewport/Thai/strictlifecycle Sourcefreeze ไม่มีautoRestart/defaultfallback/accepted62/driver/commit/pushchanges M3resource/images/perf/nativecrash/restartยังpending

### Deterministicstale-frameพบUI→mailboxgap / fixกำลังทวน — 20 ตุลาคม 2026 เวลา13:42

exec110failedViewportFixtureResizeTimeout/StaleFrameNotRejectedหลังatomicunits3/3+native125;workerexit0jobemptyแต่parenttestfail ไม่รันThai/Coreตามหลัง จึงไม่claimM3stale-safe

ตรวจCore.sizeCallbackส่งrendererresizeผ่านmailbox/Thread404setScreenSizeจึงepochadvanceช้าและfixtureรอเธรดตัวเอง แก้RuntimeSurface.resize/DPIremoteUIinvalidateก่อนCoreenqueue:dropqueued/advanceepoch/targetpendingunderdrawlockสั้นๆ แล้วrendererSkipcapture+commitจนsetScreenSizeappliedตรงlatestUItarget ไม่แก้Core/PTY/inputlogic ไม่ผ่อนgate/timeout/warmup

exec113active remotecompile→deterministicviewport2→Thai→legacycompile/window+Thai→Coreล่าสุด Sourcefreeze LastCoreexec88ก่อนM3/110Coreไม่ได้รัน ยังไม่defaultpromote/accepted62/driver/commit/pushchanges

### Realviewportpositiveผ่าน / deterministiclate-rendered-frame+Core active — หลัง20 ตุลาคม 2026 เวลา13:34

exec107passednative125,viewport133350 current-size4presentations 1034x661→1117x709→884x561→1034x661/20paints/minrestore/syntheticDPI144/healthyclose/surfaces0 ต่อThai133401diff0/35paints ไม่ใช่physicalDPIacceptance

exec110active AtomicViewportEpoch3units→native→viewport2รอบที่หน่วง**realreceivedframe2หลังRPCนอกlocks**เฉพาะprivatefixtureจนUIepochadvanced(<=5s) แล้วต้องactualstaledrop>0/odd1117framepresent/returnedA/allcurrent-size/healthyclose ต่อThai/fullCorepost-M3 Sourcefreezeไม่claimก่อนผล ไม่หน่วงGPUdriverthreads ไม่มีdefault/accepted62/driver/commit/pushchanges M3images/resource/autorestart/performanceยังpending

### ViewportfenceThai/lifecycleผ่าน / realterminalresizefixture active — หลัง20 ตุลาคม 2026 เวลา13:25

exec101native125/125,Thai132423diff0/35paints,strictlifecycle132436(123→123handles/GDI2→2/USER1→1/threads4→1/21healthyworker)ผ่าน หลังviewportepochfence ไม่ใช้แทนrealresizeproof

exec107active standalone-ViewportSmoke privateenvstrip/save-restore/remote-only,ownedoffscreenclient1117x709→minimize→restore→synthetic144DPI→originalA→close6steps1s โนactivate Surface.presentต้องcurrent-sizeทุกframe/Appdistinct>=3+returnedfirst+Windowdispatchcoverage/paint/healthyclose แล้วstrictThai ไม่แก้oldwindowfixture/gates/systemDPI ไม่มีuserclipboard/foreground/default/accepted62/commit/pushchanges Sourcefreezeไม่claimผลก่อนรันจบ

### Idletimeout/latecloseผ่าน / viewportgenerationfenceบิลด์active — หลัง20 ตุลาคม 2026 เวลา13:18

exec94exit0 50msbudgetobserved47ms/ERROR_TIMEOUT0bytes→resumeownedprimary→actualcommittedlateclosedแต่clientไม่healthy→abortexit/jobempty/handles0/noGPUparent negativeเดิมผ่าน ไม่ใช่GPUbusy/UIhangproof

ลงViewportEpoch3/3CPUunitsผ่าน A→B→Aไม่reaccept;Genericcaptureepochunderlock→Session/clientheaderใช้parentepoch→หลังRPCrecheckcurrentepoch+realizedก่อนpublish/freeStaleOwned เพิ่มadvance+dropqueuedlatestในresize/realize/unrealize ไม่ถือlockรอIPC **exec101remotebuild/Thai/strictlifecycleactive** sourcefreeze realterminalownedresize/DPI/minimizefixtureยังpending ห้ามอ้างunitsเป็นUIproof ไม่มีdefault/driver/accepted62/commit/pushchanges

### M3negativeชุดแรกผ่าน / ownedidle-timeout+latecloseactive — 20 ตุลาคม 2026 เวลา13:14 เป็นต้นมา

exec92exit0 badheaders/replay5case/nohello/unsupportedopcode/ownedkill77ทุกcaseไม่มีfakeACK/healthyclose,exit/jobempty/handledelta0/noGLparentผ่าน positive6cycle/cancelยังผ่าน ไม่ใช่resizeหรือGPUbusyhangproof

exec94active deterministicpauseเฉพาะownedprimarythreadหลังhelloก่อนGPUdraw(ไม่พักdriverthreads),50msRPCtimeoutต้องreturned1460/0bytes,Resumeแล้วรอactualcommittedlateclosedแต่clientpoisonedต้องยังไม่healthy,abortexit/jobempty/handles0 ไม่มีfaultAPIsproduction มีเพียงopaqueCclientเก็บprimaryThreadIdจากPROCESS_INFORMATION ต้องรวมmetadatachangeนี้ในregressionรอบถัดไป

M3ถัดไปparentcurrentviewportepochfence+realterminalresize/DPI/minimize ปัจจุบันsnapshotresponseepochmatchแล้วแต่UIresizeระหว่างRPCยังไม่มีcurrent-generationrecheckก่อนpublish ต้องแก้ก่อนอ้างstaleFrameปลอดภัย ไม่ใช้ขนาดอย่างเดียวA→B→A sourcefreeze94เฉพาะชุดที่consume ไม่มีdefault/driver/accepted62/commit/pushchanges

### Post-hostfullregressionผ่าน / M3negativeกำลังรัน — 20 ตุลาคม 2026 เวลา13:09 เป็นต้นมา

exec88exit0 remote125+Thai+repeatstrictlifecycle125040(123→123handles/GDI2→2/USER1→1/threads4→1/21healthyworker),legacy123+Thai125455/bg125507/mouse125517,post-hostCore3961/4022pass61skip89steps defaultไม่promote/legacyResourceGrowthยังแยกรายงาน

exec92active test-onlyCwrapper+RawZigprotocolnegative5headers/nohello/unsupportedresourcecommand/ownedworkerTerminate77 ต้องไม่มีfakeACK/healthycloseและexit/jobempty/handles0 ไม่เพิ่มfaultAPIในproduction ไม่killuserPID ไม่อ้างhang/lateframe/resizeDPI/images/performance/humanacceptanceครบ Sourcefreezeต่อจนผล ไม่commit/push/default/accepted62/driverchanges

### Opt-inrealrender+strictResourceGrowthรอบแรกผ่าน / regressionซ้ำactive — 20 ตุลาคม 2026 เวลา12:44

exec80Thai123955remote33paints/diff0/parentnoGLAMD/workercloseexit0jobemptyforced0ผ่าน exec82background124155/mouse124205/lifecycle124216ผ่าน:20cyclesหลังwarmup handles123→123/GDI2→2/USER1→1/threads4→1,21workerhealthyclose ไม่มีการลดgate แต่legacy/defaultleakยังรายงานแยกไม่claimหาย

BMPviewerไม่รองรับ แปลงownedartifactPNGแล้วดู+samplepixels8จุดเทียบlegacy121207ตรงทั้งหมด รวมRGB123456=18,52,86/default12,12,12/SGR49EL ไม่ใช้parsedreceiptแทนภาพ

เพิ่มremotechangeConfigrejectunsupportedbg/customก่อนmutateCPU/configowner exec88remoteRebuild→Thai/lifecycleซ้ำ→legacybuild+Thai/bg/mouse→fullCorepost-host active sourcefreeze Mainintegrationplanแก้หัวdocs-onlyเก่าเป็นสถานะจริงโดยคงM3–M5pending/no defaultpromote/no commits/push

### Opt-inhost125steps+noGLimportsผ่าน / firstrealterminalruntime active — 20 ตุลาคม 2026 เวลา12:39

exec78passed125/125host+GPUchildและdumpbinhostnoGLimports ตัดparentGLgraphสำเร็จระดับbuild ไม่ใช่runtime/ResourceGrowthproof exec80กำลังstrictThaiapp-localoffscreenหลังcopyConPTYคู่approvedจากM1binโดยhashตรงและไม่ทับconflicts ต้องrealframe/paint+parentnoGLAMD+workerclosedexit0jobemptyforced0ก่อนนับผ่าน แล้วlifecycle20cycles/background/mouse/legacyregressionต่อ ไม่เปลี่ยนdefault/accepted62/driver/no commits

### Qualifiedparity/Coreผ่านแล้ว / firstrealremotehostcompile active — หลัง20 ตุลาคม 2026 เวลา12:31

exec60ผ่านnative123,Thai29checks/maxglyphs655/failures0/exit0jobemptyforced0,fullCore3961/4022pass61skip จากนั้นลงhostpathจริงไม่รอผู้ใช้ตาม:windows-remote-renderer defaultfalse flag/selector/copy,hostGLAD/opengl32/ImGuiGLlinkcut,workerแยกgraph auto-installในprefixใหม่;RemoteCPUDevice/Session/ownedCpuFrame verifyparentnoGLruntime,Generic GPUstatesconditionalvoid/remoteDraw capturelocked→IPC+publishunlocked/nonblockingnativewake,APIexitcloseนอกlock

exec78firstcompile→dumpbinimportsactive prefixzig-out/render-worker-host sourcefreeze ยังไม่claimcompile/runtime/ResourceGrowthผ่าน Assets app-localที่อนุมัติอยู่M1binconpty.dll+OpenConsole.exe ต้องcopyคู่ก่อนruntimetestในprefixhost ไม่fallbacksystem Backendunsupportedfeatures/resize/cancel/health/lifecycleยังต้องทวน ไม่มีdefault/accepted62/driverchanges/commit/push

### Real GPUworker RGBAparityผ่าน / latestCore active / parentremoteonlyยังpending — 20 ตุลาคม 2026 เวลา12:12 เป็นต้นมา

exec56native123+GpuThai121145exactbyte0/healthycloseexit0jobemptyforced0/25frames+baselineThai/background/mouseผ่าน Receiptแรกglyph1อาจcursor เพิ่มsuccessfulmaxglyphsummary/Appmax>1/helpercompletedfails0 **exec60native→qualifiedGpuThai→post-parityfullCore active** sourcefreeze ไม่อ้างcountsCoreเก่าเป็นล่าสุด

newunimportedCpuExportedFrame standalone1testpass/remoteSessionfmtpreparedยังunwired คู่มือนำทางApiinventoryNext remote-onlyhostbuildflagdefaultfalse/selector+GLAD/opengl32linkcut,conditionalizeGenericGPUresources/drawแต่คงCPUCore/fontshape,Sessioninitก่อนPTY,IPC/publishoutsideLocks ไม่ใช้dummyGPUsuccess ไม่silentdropunsupportedfeatures ยังไม่ปิดM1b/ResourceGrowth/no parentGL claim ไม่มีcommit/push/default/accepted62/driverchanges

### Private client runtimeผ่าน / actualThaiGPUparityกำลังทวน — 20 ตุลาคม 2026 เวลา12:03 เป็นต้นมา

exec51exit0 hello/closed+exit0/jobempty6cycles,5measuredhandleDelta0,cancelneverhealthy,parentnoGL/AMD Sourceก่อนหน้าCPUfullCore3961/4022/61skip;post-latchnative+workerbuild48ผ่าน ไม่มีthread/GDI/performance/productionhostclaim

ต่อTextParityactualownedCPUframe+legacyRGBAreferenceในdrawlock แล้วRPC/exactmemcmp**หลังunlock**;failurelatch+checks/healthycloseoutsideDrawLockก่อนThreadExitGPUcleanup flagcontrolledstrictThaiTUI-only/privateenv/nosessiondump/defaultfalse Ctransportlinkwin32 ไม่มีGLในCแต่legacyhostยังGL

ตรวจpartialpatchที่Surfaceenvanchorfailedครบทุกhunkแล้วแก้ส่วนApp/SharedDeps/Surface/helperที่ขาด exec56native→GpuTextFrameCheckstrictThai→baselineThai/background/mouse active sourcefreeze ยังไม่claimGPUdrawpassed ยังไม่ปิดM1bremote-onlyhost/backendgraphหรือResourceGrowth

### GPUworkerบิลด์ผ่าน / CPUglyphcheckเข้มขึ้น / privateclient runtime active — 20 ตุลาคม 2026

exec36post-seamfullCore3961/4022pass61skip/native3smokesผ่าน จากนั้นอุดblank-first-receiptด้วยnonemptyglyphcounter+failurelatch Appต้องfailures0และglyph>0 exec48worker28/28/native123/123+Thai115720(diff0,glyph1)/background/mouseผ่าน ไม่อ้างfullCoreหลังlatchหรือworkerpixelsผ่าน

GPUworkerentry/BOOLcompilefailแก้แล้ว เพิ่มnamedbuildtargetเฉพาะhelperไม่defaultinstall เพิ่มprivateCtransport/pinnedchild/envblock/handlelist/suspendedassignjob/dualmap/events/atomicownedreply/boundedcloseexitjobempty C11W4WXcompileผ่าน APIopenต้องserializeotherinheritlaunches ClientZigtypedheaders/ownedreply/errorcancelและclientchecktargetCPU-onlyกำลังexec51build/run6hello-closecycles+cancel+handles0/noGPUmodulesในparent ไม่ส่งtoyframe/ยังpendingresult

ถัดไปrealcontrolledThaiCPUframe→workerRGBAcompareoutsideallrenderer/fontlocks แล้วremote-onlyhostbackend/buildgraphจริง ยังไม่อ้างGPUintegrated/ResourceGrowthหาย No commits/push/default/accepted62/driverchanges

### CPUcatalog fullbatchผ่าน / realtextseam active / GPUsideยังunbuilt — 20 ตุลาคม 2026 เวลา11:39

exec27passed29contracts/noGLimports/native123+Thai/background/mouse/fullCore3957/4018pass61skip(all exit0) จากนั้นTextFrame immutableCRF1bodyCPU33testsผ่าน กลั่นrealrenderer uniforms/bg/fgroworder/2atlasesเป็นownedbytes

เพิ่มcaptureTextFrameLockedและcontrolledThaiTUI-onlyencode/decodecheck/atomiccounter ไม่captureproductionuser/no disk/IPCwaitภายใต้lock exec36กำลังnative3smokes→fullCorepostseam Sourcesfreeze **TODOหลังจบ: latch controlledCPUframefailures เพราะThread.drawFramecatchใช้warn counter>0อย่างเดียวไม่พอพิสูจน์subsequentframes** ก่อนclaimครบต้องปิดช่องนี้

เตรียมnew/unimportedTextGpuExecutor(checkedlegacy-compatibleGLdraw/limits/oddunpackalignment)และwin32_render_text_worker(privateinheritedmaps/events,atomicprefix,v2hello/frame/close) fmtcheckผ่านแต่ยังunbuilt/unrun ไม่มีbuildtarget/parentclient/remotehost proof ต้องทำต่อหลังfreeze ไม่claimGPUprocessintegratedหรือResourceGrowthหาย Accepted62ไม่ทับ/defaultยังlegacy

### M1b CPUcatalog/resourcewireต่อ / latestfullbatch active — 20 ตุลาคม 2026

CPUshaderextract10tests/noGLimportsผ่าน แต่nativeเจอaliasdataชนparameter แก้cpu_data exec21native123/123+strictThai diff0cursor45/11/background/mouseผ่าน ภาพbackgroundเปิดตรวจdefaulttop-leftRGB12/12/12และRGB/EL/resetfixture ไม่อ้างhumanacceptance

เพิ่มRegistry7tests+wire/layoutรวม17pass (reserve/createACK/live/destroyACK/reusegeneration/workerrestart/type/exhaustion/OOM);Commandsbuffer/texture/atlasupload6testsรวม23pass;ShaderPayloadUniforms/cells/images explicitLE/no padding4testsรวม27pass แก้vectorindexเป็นinlinecomptimeตามcompiler ไม่มีGPUdraw/RemoteAPIreadyclaim

ตัวช่วยcodecprovideropenaiไม่configured failก่อนเขียนfiles ตรวจpartialnoneแล้วทำตรงต่อไม่แก้harness จากนั้นแยกCPU-onlyGlslCatalog builtin5pipeline metadata/sourceจากactualGLshadersอีกจุด เริ่มexec27CPU29+importcheck→native+3smokes→fullCorepost-catalog sourcefreezeทั้งชุด ยังไม่ใช้ผลเดิมอ้างใหม่passed

M1bremote-onlyhostbuild/API/actualworkerยังpending งานactiveไม่รอผู้ใช้ตาม NativelegacyยังGL ResourceGrowthเดิมยังไม่ปิดและM1candidateไม่ได้qualifystrictlifecycle ไม่ทับaccepted62 ไม่เปลี่ยนCore/VT/ConPTY/input/clipboard/portableStore ownership

### M1a nativeผ่าน / M1b codeต่อ / data regression active — 20 ตุลาคม 2026 เวลา10:44

exec15native123/123+strictThaiTUI(default_gc=true diff0 cursor45/11)/backgroundhelper/mouseexit0 ทั้ง3offscreen/remaining_surfaces0 ยังlegacyGLไม่ใช่remotehost ไม่claimResourceGrowthหาย FullCoreก่อนหน้าผ่าน3929/3990/61skip

M1bเพิ่มCPU-onlywireProtocolv2draft48byteLE/fixedwidthidentity-resourceIDs Passed7/7standaloneDebug(exec17) แล้วextractactualCPUshaderUniforms/cells/imagesเข้าGlslDataไม่มีPipeline/OpenGLimports oldGLshadersใช้aliaseslayoutเดิม เพิ่ม2layout/flagtestsและtestroot รวมProtocol+Data10tests เริ่มexec20CPUtests/importcheck→nativebuild+Thai/backgroundcapture/mouse Sourcesfreeze ยังไม่claimรอบนี้passหรือremotehostAPIเสร็จ

ไม่เพิ่มGPUสีPoC ไม่เปลี่ยนdefault/ConPTY/input/clipboard/portablePaths/driver/accepted62 งานยังactiveM1bหลังnativebaselineผ่านแล้ว APIpacket/resourcepipelinecouplingต้องทำต่อจริงไม่ใส่successstub รายละเอียดAPIinventorydoc

### M1a fullCoreผ่าน / nativelegacy regression active — 20 ตุลาคม 2026 เวลา10:37

FullCore89/89steps,3929/3990testsผ่าน61skip(exit0/no timeout/Debug-j1/no filter) รวม3newCPUpreparationtests จากนั้นเริ่มexec15connectionนี้ nativeReleaseSafe-j1 prefixrender-worker-m1 +app-localConPTY → strictThaiTUI/RequireThaiModel → background0c0c0c → mouse smokeoffscreen Sourcefreezeไม่แก้backend/buildconfigระหว่างcompile/tests ไม่ใช้Corepassอ้างnativepass ไม่ทับ62หรืออ่านclipboard/session

M1aยังรอnativeผลจริง ส่วนM1bAPIinventoryเสร็จแต่remote-onlyhostdependency/buildยังpending ต้องแก้typedresource/frame/mailboxcouplingจริง ไม่สรุปว่าGPUprocessintegratedหรือnativeResourceGrowthหาย แผนแก้ต่อยังactiveไม่รอapprovalซ้ำสำหรับmilestonesที่อนุมัติ

### M1 implementation เริ่ม / fullCore active — 20 ตุลาคม 2026 เวลา10:20

ผู้ใช้“งั้นแก้ต่อเลย”อนุมัติแก้ต่อตามintegrationplan เริ่มM1aจริง:CpuPreparationCPU-onlymodule+metrics/shaperownershiptransfer+3unittests GenericWindowsเตรียมCPUก่อนWGL ระบบอื่นรักษาinitorderเดิม ไม่มีremoteGL/hostcompilemode/defaultเปลี่ยน และไม่claimnativeResourceGrowthหาย

เริ่มfullCoreDebug-j1/no filter prefixrender-worker-m1(exec11connectionปัจจุบัน) sourcefreezeก่อนเดินต่อ ตรวจfreecommit13783MiB ไม่killแอปผู้ใช้ ไม่บิลด์ทับ62 ระหว่างรันทำread-onlyAPIinventoryเสร็จใน[APIinventory](docs/windows-render-worker-api-inventory.md) รวมBuffer/Texture/Target/shaders/Frame.completeที่mailbox.forever ต้องหลีกเลี่ยงremoteUI/joinwaitdeadlock

M1ยังinprogress CPUunit/fulltestsยังไม่ประกาศpass ต้องอ่านexit/countsจริงแล้วทวนnativelegacyและทำM1bremote-onlybuilddependencyต่อ ไม่เพิ่มPoCสีหรือย้ายConPTY/input/clipboard/portableStoreไปchildโดยเดา ไม่หยุดขออนุมัติซ้ำสำหรับapprovedmilestones แต่scope/riskใหม่ต้องแจ้ง

### Integration plan อิงcode / 20 ตุลาคม 2026 เวลา09:47

ผู้ใช้“ได้เริ่มเลย”ต่อข้อเสนอทำแผนก่อนแก้rendererหลัก เริ่มตรวจจริงCoreSurface/Options/State/GenericRenderer/OpenGL/Win32AppSurface/SharedDeps พบcomptimebackend+win32opengl32staticlink และpointer/mutex/fontgrid/mailboxข้ามprocessไม่ได้ จึงไม่เสนอแค่runtimeflagหรือย้ายpresentแล้วอ้างGPUออกจากparent

เขียน[opt-in render-worker integration plan](docs/windows-render-worker-integration-plan.md):แนะนำGPU-onlyexecutionผ่านboundedrender/resourcepackets,Core/VT/ConPTY/input/IME/clipboard/portableStoreอยู่parent;remote-onlyhostแยกbinary/buildgraph,workerเท่านั้นมีGL Legacy62ไม่ถูกทับ/ไม่silentfallback/ไม่auto-relaunchshell Rollbackต้องแจ้งsessioncontinuityไม่อ้างย้ายHPCONไปlegacyseamless

M1API/dependency split→M2realterminaltext/atlasframe→M3resource/lifecycle→M4interaction→M5fullqualification เสนอimplementationยังไม่เริ่ม รอบนี้docs/sourceinspectionเท่านั้น ไม่มีruntime/build/sourcechangesหรือjobsactive Nativegateยังfailedตามเดิม ต้องอนุมัติM1boundaryก่อนแก้mainrenderer ไม่ใช้“ได้”ของplanningอ้างอนุมัติrewriteทั้งหมด

### FrameIPC/presentationหลังreviewผ่าน — 19 ตุลาคม 2026 เวลา23:46

`gpu-frame-ipc-20261019-234450-167`17/17casesผ่าน(no wrappertimeouts),child28/28,parent/W4/WX Parentagentตรวจreceiptsซ้ำ84FRAME_OK/21childexit+jobempty/parentbaselineและfinal100handles/GDI0/USER1/threads4ไม่เพิ่ม เปิดBMP→PNGรอบใหม่สีblue-white/red-greenถูกต้อง ไม่ใช่desktopcapture

actualHWNDresize/clientdimensionassert+physicaloffscreenNOACTIVATEผ่านพร้อม16negativecontrolsรวมbadcommit/header/capacityหลังreview Byteprotocol256×128cap/80byteheader/event+release-acquire checksคงเดิม Hashparent3B8452954462C8B0BA0D829392890C480E354D7C7B0422CE8F72269D7D65015B;child73256D5C0CF8B36BE9C70AA7077D3A31195AD441CD23FA45C2C40F8ABCEFDE1A Accepted62และGPU-child66hashตรวจซ้ำคงเดิม

รายละเอียด/negativeผล/limitsในFrameIPCdoc PoCscope23:22เสร็จ **ไม่มีjobรันต่อ** ไม่claimnativeResourceGrowthfix/terminaltext/input/IME/clipboard/performance/mainintegrationหรือonscreenhumanacceptance ไม่มีcommit/push/worktree/driver/globalsettingschanges แนะนำขั้นถัดไปเป็นopt-inintegrationdesign+rollback/ownership/regressionplanก่อนแตะmainrenderer ต้องขอscopeใหม่ไม่ทำrewriteโดยคำว่า“ได้”ของIPCdemo

### FrameIPCรุ่นแรกผ่าน / parentreviewทวน17cases active — 19 ตุลาคม 2026 เวลา23:41

Workerรายงาน`gpu-frame-ipc-20261019-233828-586`ผ่าน14cases,child28/28,parent/W4/WX:1warmup20cycles21childexit/jobempty84frames/WM_PAINT Parent100handles/GDI0/USER1/threads3คงเดิม Parentอ่านprotocol/consumer/producer/runnerเองและเปิดภาพPNGblue-whiteเหนือred-greenยืนยันGDIbackbuffer ไม่ใช่desktop/humanacceptance

เสริมเฉพาะIPCfiles:HWNDresizeจริงตามframe+GetClientRect/offscreenassert(เดิมเฉพาะbackbuffer),GDIreturnchecks,process-localper-monitor-v2DPIawarenessparent/childเพื่อphysicalgeometryไม่แก้systemsettings เพิ่มbadcommit/header/capacitynegative3cases แล้วเริ่มexec34`gpu-frame-ipc.ps1 -Build`17cases Sourcesfreeze ไม่ใช้ผลก่อนreviewอ้างsourceใหม่ผ่าน ไม่มีruntime/renderer/ConPTYหลักหรือ62/gpu-child66changes

Wire80bytefixedwidthheader+256×128RGBAcap/Eventrelease-acquire/commitและdoubleheadercheckcopyfromparentknownbounds;fielddetail/results/limitsในFrameIPCdoc Fixturestaticcontentmetadatafreshnessไม่ใช่freshcontentnonce/hardwareattestation/no maliciousproducer claim ไม่nativegatepassหรือterminal/input/IME/performanceintegration

### FrameIPC/presentation PoC อนุมัติ / implementation active — 19 ตุลาคม 2026 เวลา23:22

ผู้ใช้ตอบ “ได้” ให้ขั้นส่งframeผ่านsharedmemoryและparentoffscreenpresentation เริ่มwriterเฉพาะnewIPCfiles+smalladditivebuildtarget prefix`zig-out/gpu-frame-ipc` ไม่แก้mainrenderer/ConPTY/windowruntimeหรือaccepted62/previousgpu-child66 ไม่สร้างworktree/commit/push/driverchanges

PlannedGLactualRGBA→boundedversionedheader/epoch/seq/stride/capacity/commit→verifiedparentGDIbackbuffer+WM_PAINTนอกทุกmonitor/noactivate,resizeodddimensions,childjobexit/closeack/1warmup20parentcycles และstale/badmetadata/crash/hang/closefailurecontrols Scopecontractใน[frameIPC PoC](docs/windows-gpu-frame-ipc-poc.md) ทั้งหมดตอนนี้plannedยังไม่claimผ่าน

Implementationworkerownsnewsourceและbuildtarget ParentownsPLAN/docsแล้วreviewภาพ/ผลหลังรายงาน ไม่editwriterfilesซ้อน ไม่รันtestซ้อนconsumingsourcesที่กำลังเปลี่ยน งานกำลังทำจริงมีcompletionnotification ไม่รอผู้ใช้ตาม ยังไม่อนุมัติproductionintegrationจากคำว่า“ได้”รอบนี้

### Reviewed GPU-child PoC66 ผ่าน / รอscopeถัดไป — 19 ตุลาคม 2026 เวลา18:23

`gpu-child-poc-20261019-182157-467`ผ่านpositive+5negativecontrolsหลังreviewfix (exec28exit0,childbuild28/28,parent/W4/WX) Parentbaseline71handles/GDI0/USER1/threads4 หลัง20cyclesและlongactiveGLcontext15sเป็น71/0/1/1 ไม่เพิ่มทุกcycle 22childexit0/jobempty/actual3draws/16RGBAbytes ไม่มีparentOpenGLimport(dumpbinมีUSER32/KERNEL32) ไม่มีextraGPUwarmup/resetbaseline

HashparentAE7B6746C2BFECE146A435B1F0E7DE46429E05A05EF0A8011F9DDAB35743CC9C;childE0702D84CAF6EB797E996EFE55F1A3BEC171BAA9A29A10A86641D0C905B0909B;accepted62hashเดิมยืนยันไม่ถูกทับ Childlongก่อนexitยังมี211handles/GDI1/USER3 แยกprocessช่วยcleanupboundaryไม่ใช่contextdestroyคืนหมด ไม่claimnativegateผ่านหรือmainintegration

Result/limitationsครบในGPU-childPoCdoc รวมtrustedselfreport/knownmodulelimit/outertimeoutkillpathsource-onlyไม่ได้forceใน6cases ทุกnegativeactualexit1+parentcleanupไม่ใช่positivegatepass ตอนนี้ไม่มีbuild/testรัน Scope18:07สำเร็จเฉพาะcomponentPoC

แนะนำขออนุมัติPoCframeIPCsharedmemory+parentoffscreenpresentation/resize-close-crash-stalecontrolsก่อนmainrenderer ไม่เริ่มIPC/ConPTY/input/IME/clipboardintegrationโดยคำว่า“ได้”ของlifetimePoC Native62strictresourceยังfailedคงเดิมและCore/VT62+humanThai/appearancepassคงเดิม

### PoCรุ่นแรกผ่าน / reviewed66กำลังทวน — 19 ตุลาคม 2026 เวลา18:19

`gpu-child-poc-20261019-181635-626`ผ่านpositiveและmissingreceipt/badpixels/hang/launchfailure4negative (exec27exit0) Parentbaseline71handles/GDI0/USER1/threads4 หลัง20cyclesและpost-teardownlongcontrol71/0/1/1,22childrenexit/jobempty แต่ไม่ใช้ผลรุ่นแรกปิดreviewข้อจำกัดหรือนativegate

แก้parent-onlyproducerchecks/outerkillwait5sพร้อมterminationconfirmed/GetGuiResourceszeroerroraware/30selapsedรวมcreate+assignเมื่อAPIreturn/hold15sขณะcontextยังalive และเพิ่มcounter-errorinjectionnegative เริ่มbuild66→6casesSourcesfreeze ไม่ปรับwarnings/warmup/thresholdหรือaccepted62

ระบุlimitationsชัด:childpixelเป็นtrustedinstrumentedselfreportไม่hardwareattestation/hashrecordไม่signedallowlist/modulechecksเฉพาะknownAMDสามชื่อไม่ทุกvendor/transientloads ไม่มีnativeWM_PAINT/terminal/IPC/performanceproof CounterAPIOSblockingพึ่งouter300s ไม่อ้างhardcancel30sระหว่างOSCreateProcessค้าง ดูPoCdoc ไม่มีmainintegrationอนุมัติจากคำว่า“ได้”รอบก่อน

### Read-only PoC review / ยังไม่รับ pass — 19 ตุลาคม 2026 เวลา18:17

Forkreviewอ่านsourceเท่านั้นพบproducerfencingcleanupmarkersปนparent/childlogs,wrapperkill-failureตามด้วยunboundedwait,GetGuiResourceszero/errorไม่แยก และlongcontrolปัจจุบันholdหลังcontextdestroyไม่ใช่longactivecontext ต้องแก้หลังexec27จบไม่เปลี่ยนsourcesกลางtest พร้อมจำกัดclaim:receiptเป็นtrustedinstrumentedchildselfreport+PID/hash ไม่ใช่hardwareattestation;knownmodulechecksสามชื่อไม่รับรองทุกvendor/transientloadหรือnativeintegration

Containmentหลักsuspended→assignjob→resume/restrictedhandleinheritance/exit+zerojobchildrenมีจริงและnegativecontrolsตั้งreadinessfalse ถูกต้อง แต่ยังไม่ใช้ผลรอบแรกหรือfutureexit0ปิดnativegate Planหลังชุดปัจจุบันคือparent-onlymarkerchecks/boundedkillwait/error-awareGUIcounts/absolutechilddeadlineและlongactivecontextแล้วทวนใหม่ ไม่ปิดwarningsหรือเปลี่ยนparentthreshold/warmup/native62

### อนุมัติGPU-child PoC / ทวนsharingfix active — 19 ตุลาคม 2026 เวลา18:16

ผู้ใช้18:07ตอบ “ได้” ให้GPU-onlyownedchildPoC ไม่ใช่rendererintegration เริ่มparentCไม่มีOpenGL+restrictedstdioinheritance/privatejobkill-on-close/1warmup20cyclesparentresourcegate+15slongcontrolแยก พร้อมmissingreceipt/badpixel/hang/launchfailure negativecontrols ทั้งหมดoffscreenhidden/noactivate ไม่compileทับ62/ไม่เปลี่ยนmainrendererหรือdriver

Build64parent/WXจับuninitializedbaseline แก้zero-init+readyguardไม่ลดwarning Build65parentผ่าน/W4/WX child28/28 แต่positivecycle0failedsharingviolationReaderwinerr32;childมีactualGL4.3/RX7600/verified3draws/16RGBAbytes/exit0/cleanupสำเร็จ ไม่claimPoCผ่าน แก้ปิดparentwriter/stdinสำเนาหลังassignjobก่อนResumeแล้วทวนใหม่child65เดิม Jobexec27กำลังรันsourcesfreeze มีforkread-onlyauditparentcleanup/harnessแยก ไม่edit/build/GUIซ้อน

ดู[GPU-childPoC](docs/windows-gpu-child-poc.md) สำหรับcontract/controls/ข้อจำกัด นี่ไม่ใช่nativeWM_PAINT/IPC/terminalproofหรือnativeResourceGrowthfix Native62strictfailureยังเปิดแม้PoCผ่านในอนาคต ไม่มีintegrationหรือscopeอื่นอนุมัติล่วงหน้า

### ปิด bounded attribution / รอ scope decision — 19 ตุลาคม 2026 เวลา17:48

`cdb-native-htrace-20261019-174618-084`Native63เดิมmarkerครบ/no timeout DuplicateObjectunfilteredจับ1029calls แต่0callsจากhtracecreator0x7640ของสองgap ไม่พิสูจน์duplicatehypothesis จึงหยุดtraceไม่ขยายNtAPIเดาไปเรื่อย

ภายในrunนี้3รายการจับคู่PSS/htrace/livekได้:758Threadtarget15228 creator28112(0x6dd0),stackamdihk64+0x4edd←NTDLLtimer;5f4Event/608Threadtarget33312creator33312(0x8220)stackRPCRT4!ThreadSelf/PerformGarbageCollectionและself-threadDuplicateHandle ส่วน790Event/794IoCompletioncreator30272(0x7640)startatio6axxยังunknownliveallocation/openstack ไม่เหมารวมว่าเป็นRPC/app-ownedleakหรือปิดเอง

เปรียบเฉพาะtype-countnormal62:Event39→40,Thread3→5,IOCPไม่เปลี่ยน;underCDBรอบล่าสุดEvent39→41,Thread3→5,IOCP5→6 ผลmeasurementต่างกัน ไม่ตีความcountเป็นobjectidentity/closeownerหรือยืนยันว่าสองgapคือสาเหตุnormal+1 Strictnormal62ยังfailed ไม่มีsafeapp-ownedfixพิสูจน์แล้ว และไม่ผ่อนthreshold/warmup/driverchecks

**ตอนนี้ไม่มีbuild/test/traceรันต่อ** FullCore/VT62และhumanThai/appearanceผ่านตามเดิม เสนอขออนุมัติแค่GPU-onlyowned-child lifecycle isolationPoCเพื่อทดสอบขอบเขตcleanup ไม่ใช่rewrite/ย้ายrendererหลักทันที ต้องรักษาparentresourcegateเดิม+ยืนยันchildexit/noowneddescendants/จริงGLrenderpaint ไม่ย้ายleakออกนอกcounterแล้วclaimpass ไม่ทำก่อนscopeapproval/ไม่แตะaccepted62/driver/settings/foreignhandles

### เติมAPIรอบ2ยังมีgap / ทดสอบduplicatehypothesis — 19 ตุลาคม 2026 เวลา17:44

`cdb-native-htrace-20261019-174306-723`markerครบ/no timeout Native63เดิม มี5retainedopensอีกครั้ง แต่handle/TIDคนละrunห้ามยืมidentity:3dcThread/31892และ3d0Eventcreator31892(0x7c94);7b0Thread/27636creator29220(0x7224);7e8IoCompletionและ7f4Eventcreator25752(0x6498),threadstartatio6axx Underdebugcounts234→237handles/USER3→4/threads6→10 ไม่แทนnormalstrict62

NtCreateIoCompletionBPจับ40callsได้(เช่นmainCorelibxevIOCP)แต่ไม่มีdirectcreate/openEvent/IoCompletionliveAPIhitของcreator0x6498ที่retained จึงยังไม่อ้างownerจากthreadentryอย่างเดียว พบcoveragegapเดิมNtDuplicateObjectจับเฉพาะcurrent-threadpseudohandle จึงอาจพลาดEvent/IOCPที่duplicateไม่ใช่createใหม่ นี่เป็นhypothesisไม่ใช่ผลพิสูจน์

ขยายเฉพาะDuplicateObjectBPให้logsourcehandleและbasicstackทุกแบบ แล้วรันownedNative63เดิมหนึ่งรอบ ไม่compile/ตั้งค่าdriver/ผ่อนgate ถ้ายังตามสองรายการไม่ได้ให้รายงานunknownไม่เดาปิด;ตัวaccepted62/normalprofileไม่ถูกแก้

### Native63 creator trace partial proof / เติม2API — 19 ตุลาคม 2026 เวลา17:40

Build63ผ่าน123/123;`cdb-native-htrace-20261019-173901-579`baseline/finalmarkerครบ/no timeout เป็นdiagnosticไม่ใช่strictpass Underdebuggercounts247→250,USER3→4,threads6→10ต่างจากnormal62 ห้ามใช้tracecountsแทนnormal233→234/6→7หรือเปรียบabsoluteเป็นleakเพิ่ม

จับคู่htrace+PSS+livekภายในrunนี้ได้:handle82c Threadtarget30504 creator6556(0x199c)stackNtCreateThreadEx←CreateThread←amdihk64+0x4edd←NTDLLtimer;85c Eventและ8b0 Threadtarget22960 creator22960(0x59b0)stackRPCRT4!ThreadSelf←RpcpSetThreadpoolCallbackInstance←PerformGarbageCollection และself-threadDuplicateHandle ไม่ใช่สร้างOSthreadใหม่สำหรับ8b0

ยังมี858 Event/860 IoCompletioncreator3292(0xcdc),threadstartatio6axx แต่ไม่มีlivecallstackตรงAPI ห้ามเหมาว่าRPC/driverจัดสรรทุกอันเพราะthreadentrypointเท่านั้น Htrace5retainedopensกับnet+3ไม่ได้พิสูจน์closedowner ไม่ยืมoldALPCcloseข้อสรุปข้ามrun

เพิ่มเฉพาะCDBbreakpointsNtOpenEvent/NtCreateIoCompletionแล้วรันownedtraceอีกรอบด้วย63binaryเดิม ไม่compile/แก้counter/warmup/deadline/driver/ปิดforeignobjects ต้องตาม2gapนี้หรือแจ้งยังไม่ทราบ ไม่repeatbaselineยาวหรือเริ่มarchitecture rewriteโดยยังไม่ขอscope

### Fresh62 resource ยัง failed / native creator trace63 active — 19 ตุลาคม 2026 เวลา17:33

`lifecycle-native-20261019-173158-832`candidate62hashเดิม/modernprovider/bg0c0c0cยังResourceGrowthexit1ไม่timeout:handles233→234,threads6→7,GDI/USER3→3 Saved`.thread-delta.json`:4added/3removedในprocessเดียว Added3828startamdihk64กับ1732/21788/28084startntdll;removed7304/19344/25132startntdll ไม่ใช่creatorstackและห้ามใช้TIDsข้ามrunเป็นidentity Wrapperexec10สำเร็จหมายถึงเก็บdiagnosticfactsได้ ไม่ใช่strictgateผ่าน

เพิ่มnative-onlylifecyclemarkerแบบno-opไม่allocate/เพิ่มwarmup/แก้counts/deadline และCDBhelperเฉพาะowneddummy-shellfixture แยกbuild63prefix`zig-out/native-attribution`ไม่ทับaccepted62 Htraceprocess-local/normalheap(-hd)และlivekstackที่NtCreateEvent/NtCreateThreadEx/current-threadDuplicateหลังbaselineจนfinal ไม่มีheapdump/session/clipboard/driver/globalGFlagschanges และsignedMicrosoftCDB/ownedtree240secdeadline

Build63→traceกำลังรันsourcesfreeze หลังfullCore/VT62ผ่านแล้ว เปลี่ยนเฉพาะdiagnosticwindowmarkerหลังbaseline จึงไม่ใช้62fulltestpassอ้าง63fullbaselineใหม่หรือรับรองhuman63 ไม่promote63เป็นpreview ไม่ปิดforeignobjects/ผ่อนgateแม้traceเก็บสำเร็จ ต้องจับคู่currentrunretainedhandle/TIDกับcreatorstackจริงก่อนตัดสินใจapp-ownedfixหรือถามscopearchitecture

### Full baseline62 ผ่าน / fresh resource inventories active — 19 ตุลาคม 2026 เวลา17:28

FullCore`baseline62-test-20261019-164732`ผ่าน3926/3987tests,61skip,89/89steps;VT`baseline62-test-lib-vt-20261019-170213`ผ่าน6722/6786tests,64skip,45/45steps ทั้งคู่exit0/ไม่timeout/Debug-j1/no filter/sourceคงเดิมจนจบ เป็นผลsourceหลังConPTY+backgroundจริง ไม่ใช้candidate53baselineแทน

อ่านmodern59rawlogพบbaseline6/final7TIDs มีadded4/removed3:added29576startamdihk64และ15232/22572/22876startntdll ส่วนremoved14192/24452/29936startntdll **นี่คือsnapshotdifferencesในprocessเดียว ไม่ใช่creatorstack และห้ามอ้างnet+1คือมีใหม่แค่1thread** ไม่ใช้เลขTIDsนี้ข้ามrun

เริ่มfreshstrictlifecycle62แยกownedprocessด้วย-AppLocalConptyและpreviewbackground0c0c0cที่humanรับ บันทึกbaseline/finalTID+startmoduleเป็นJSONคู่กับrawlogs ไม่compile/เปลี่ยนsource/threshold/warmup/deadline ไม่ปิดforeignthreads/handles หากgatefailคงfailed แม้inventorydiagnosticสำเร็จ ยังไม่มีcodefixresourceที่พิสูจน์แล้ว

### Resource review กู้เอง / baselines ยัง active — 19 ตุลาคม 2026 เวลา16:48

Read-onlyworkerปฏิเสธเพราะtemplateจำกัดOlufy ไม่ได้อ่านไฟล์ ไม่รับผลว่าreviewผ่าน Parentตรวจเองแทน:WGLContextdeinitเรียกdeletecontextบนownerthreadก่อนReleaseDC/DestroyWindow/unregister;PtyปิดproviderHPCONก่อนFreeLibraryและiniterrdeferคืนmodule Sourceinspectionยังไม่ใช่proofว่าทุกAPIสำเร็จ/ไม่มีleak

Rawmodern59lifecyclelogมีthreadinventorymoduleจริงรวมatio6axx.dll/amdihk64.dll/ntdll.dll เช่นTID29576เริ่มในamdihk64 แต่ยังไม่จับคู่baseline/finalidentityกับcreatorstackรอบนี้ จึงไม่ใช้net+1หรือoldCDBproofระบุretainedownerทั้งหมด ขั้นต่อไปหลังfulltestsคือfreshownedfixturebaseline/finalTID+creatorprovenanceด้วยthreshold/warmupเดิม ไม่ปิดforeignobjects/ปรับdriver/อนุมัติarchitecture rewriteโดยเดา Sourcesคงเดิมระหว่างCore→VT ไม่มีprobeหรือGUIรันซ้อนกับbaselines

### Human appearance ผ่าน / full baselines active — 19 ตุลาคม 2026 เวลา16:46

ผู้ใช้ตอบ **“ok แล้ว”** หลังpreview62-AppLocalConpty-Background0c0c0c รับเป็นhumanacceptanceของHerdrคำถาม/พื้นหลังรอบนี้ คู่กับThaiqualifiedreportก่อนหน้า ไม่เหมารวมCtrlShiftC/IME/DPI/CLIimageconsumerหรือระยะยาวผ่าน ไม่promoteproductionbackend/themeเองและไม่เปลี่ยนsettingsถาวร

ตรวจfreecommit5140MiB/physical11144MiB เริ่มfullCore→VT -j1/Debug/no filter/app-runtime=none แยกprefixzig-out/baseline62 ไม่บิลด์ทับ62sourcesfreezeจนจบ เก็บcounts/exit/timeoutlogจริง ไม่ใช้native123/123buildแทนtestpass Testdeadline40นาทีต่อstep ถ้าtimeoutหยุดเฉพาะownedcompilerprocess-tree ไม่มีGUI/clipboard/session/driverchanges

ควบคู่มีread-onlyreviewresourceattribution/ownedWGL/ConPTYlifetime ไม่แก้codeหรือรันprobeซ้อน Strictresource+1handle/+1threadยังfailed ต้องแยกoldAMD/RPCproofจากmodernrunและไม่waive/ปิดforeignhandles ขั้นต่อไปหลังbaselineผลจริงคือเลือกboundeddiagnosticที่มีหลักฐาน ไม่อนุมัติarchitecture rewriteล่วงหน้า ตอนนี้build/testและreviewกำลังทำงาน ไม่รอผู้ใช้ตาม

### WT-contrast preview ทวนผ่าน — 19 ตุลาคม 2026 เวลา16:08

Candidate62เดิม/hashคงเดิม ทวนprocess-localdefault0c0c0cผ่าน7pixelchecks`terminal-native-20261019-160729-260`:default/outside/SGR49/SGR0=0c0c0c,blockEL/paddedblock=1e1e1e,RGBอื่น123456ไม่เปลี่ยน ViewImageเปิดตรวจได้ มีcontrastเหมือนสีWTreference ไม่อ้างว่าfullquestionpaddingในHerdrผ่านแล้ว ส่งmanualpreview62-AppLocalConpty-Background0c0c0cแทน1e1e1e รอhumanดูคำถามหน้าเดิม ไม่เปลี่ยนdefaultถาวร/palette/Herdr และยังไม่มีresource/fullCoreVTpassใหม่ ไม่มีbuild/testรันหลังชุดนี้จบ

### Windows Terminal appearance reference — 19 ตุลาคม 2026 เวลา16:06

ผู้ใช้ส่งWTภาพอ้างอิง ViewImageเปิดตรวจได้:คำถามเป็นบล็อกทึบต่อเนื่องรวมpadding โดยวัดpixelmain/sidebar=#0C0C0C และquestion/padding=#1E1E1E **บล็อกสว่างกว่าพื้นหลัก** ไม่ใช่ทำสองสีเท่ากัน รับผิดทิศทางpreview1e1e1eก่อนหน้า ไม่เปลี่ยนpaletteหรือทาสีทับเอง

กำลังทวนcontrast0c0c0cบนcandidate62เดิมผ่านprocess-localflag ไม่compile/ทับbinary62หรือ59 และไม่ตั้งถาวร ต้องให้7pixelchecksแสดงdefault0c0c0c/block1e1e1e/SGR49/EL/RGBอื่นคงเดิม แล้วส่งhumanดูHerdrว่าคลุมคำถามครบหรือยัง Controlledcontrastไม่เท่ากับพิสูจน์fullnestedHerdrpaddingผ่าน และdefaultsourceเดิม282c34ยังไม่promoteเป็นthemeอื่น

### Background preview ไม่ผ่าน human — 19 ตุลาคม 2026 เวลา15:57

ผู้ใช้รายงานคำถามของLettaที่อยู่ในHerdrไม่มีพื้นดำคลุมจึงอ่านยาก เกณฑ์appearanceที่ต้องรักษาคือ **บล็อกคำถามดำต่อเนื่องและตัดกับพื้นหลัก** ไม่ใช่ทำdefaultbgเท่ากับblockRGBแล้วลบรอยต่อ Preview1e1e1eทำให้contrastหาย จึงไม่รับเป็นfix/ไม่ตั้งถาวร แม้controlledSGR/BCEpixeltestsผ่านก็ตาม Defaultsourceยัง282c34และcandidate59ไม่ถูกแก้

ขอภาพคำถามเดียวกันในWindowsTerminalเพื่อแยกintent/outputของHerdr/Lettaกับbackgroundที่สูญหายระหว่างConPTY/renderer ก่อนแก้codeใหม่ ไม่เดาทาสีช่องว่าง/แปลงSGRหรือแก้Herdrจากภาพอย่างเดียว ไม่มีbuild/testรันตอนขอreferenceนี้ ขอบเขตThaiuserreportยังคงเดิม ไม่มีappearancehumanpass

### Build62/background pixels ผ่าน / ส่ง human appearance preview — 19 ตุลาคม 2026 เวลา15:33

Retryตามผู้ใช้ผ่าน123/123steps Fullflagsเดิม-j1/ReleaseSafe ทั้งสองสี282c34/1e1e1eผ่าน14pixelchecks:default+EL,RGB+EL,paddedinside/outside,SGR49reset,truecolor123456+EL,SGR0reset ไม่เปลี่ยนpaletteหรือสีexplicitที่TUIส่ง ViewImageตรวจPNGทั้งสองได้ จึงไม่พบBCE/SGR49renderผิดในcontrolledcasesนี้ ไม่เหมารวมnestedHerdrทุกกรณีว่าถูกแล้ว แถบต่างสีในfixtureมาจากexplicitRGBกับdefaultคนละสี และหายเมื่อpreviewdefaultตรงกัน โดยtruecolorอื่นยังคงค่าเดิม

Receipts`terminal-native-20261019-153231-543`(282c34),`terminal-native-20261019-153244-603`(1e1e1e);strictpacedThaiหลังเปลี่ยนpreviewbgผ่าน`terminal-native-20261019-153255-078`,0cellsdifferent/cursor45ตรงreference/35framespaints

Candidate62`zig-out/background-probe/bin/localterm-dev.exe` SHA256`2589A9B770D5930E1F00C654D4D89116C78B522A94A0E4EEB1D9AAE9829327CC` frozen แยกจาก59 คำสั่งmanual`preview.ps1 -Executable .\zig-out\background-probe\bin\localterm-dev.exe -AppLocalConpty -Background 1e1e1e` เปลี่ยนแค่defaultbgprocess-localไม่เขียนthemefile/ปรับHerdr/ตั้งถาวร รอhumanดูหน้าHerdrเดิมและacceptappearance ไม่มีtestรันหลังชุดนี้จบ Strictresource+1handle/+1threadและfullCore/VTยังเปิด ไม่ใช้123/123buildอ้างfulltestpass

### ผู้ใช้ขอ retry ใหม่ / build62 active — 19 ตุลาคม 2026 เวลา15:28

ผู้ใช้ถาม “ลองใหม่ได้ไหม” ตรวจreadonlyfreecommit6032MiB(~5.9GiB),physical12231MiB เพิ่มจากรอบก่อน จึงเริ่มretryตามอนุมัติใหม่หนึ่งครั้ง (6GiBเป็นresourceestimateไม่ใช่validationgate) ใช้flagsเดิม-j1/ReleaseSafe/fullgraph prefixbackground-probeไม่ทับcandidate59 ตามด้วยpixelสองสี/SGR49/EL/paddedcellsและstrictThaiหากbuildผ่าน Jobexec100กำลังรันsourcesfreeze ไม่เปลี่ยนsystemsettings/ปิดโปรแกรมผู้ใช้ ไม่อ้างผลผ่านล่วงหน้า

### Recovery61 รอครบแล้วยัง blocked — 19 ตุลาคม 2026 เวลา15:11

Jobexec97รอ15นาทีครบโดยfreecommitไม่ถึง6GiB จบblocked **ยังไม่ได้เริ่มcompile61หรือpixel/Thaiหลังปรับพื้นหลัง** ไม่ใช่compiler61fail ไม่มีโปรแกรมถูกปิดหรือsystemsettingsเปลี่ยน และไม่มีbackgroundtest/buildรันต่อหลังรอบนี้ ไม่สรุปว่าrenderer/BCEถูกหรือผิดจากภาพอย่างเดียว

หยุดretryตามขอบเขตonecleanrecovery Candidate59เดิมยังใช้ได้ Backgroundpreviewcode/fixtureยังunverifiedและไม่ส่งให้humanเปิด ต้องรอทรัพยากรพอหรือผู้ใช้อนุมัติแนวทางอื่นก่อนเริ่มใหม่ ไม่เปลี่ยนpagefileหรือkillBun/agentbackendแทนผู้ใช้ ResourceGrowth+1handle/+1threadและfullCore/VTยังเปิดคงเดิม

### Background60 OOM / bounded recovery61 — 19 ตุลาคม 2026 เวลา14:52

Build60หยุด92/123steps:helpgenและlibghostty-vtLLVMOutOfMemory ไม่ใช่pixel/assertionfailure และ **pixel/BCE/Thaiชุดนี้ยังไม่รัน** candidate59ของผู้ใช้ไม่ถูกทับ ตรวจOSreadonlyphysicalfree~10.5GiBแต่freecommit~2GiB ไม่พบZigค้างของownedprobe ไม่ปิดBun/Java/โปรแกรมผู้ใช้หรือเปลี่ยนpagefile/driver/settings

เริ่มbackgroundrecovery61หนึ่งครั้ง:ตรวจทุก60วินาทีรอfreecommit>=6GiBและphysical>=5GiBไม่เกิน15นาที แล้วใช้buildflagsเดิม-j1/ReleaseSafe/fullinstallgraph ไม่ข้ามlibVT/helpgen/ลดoptimizerหรือgates หากไม่พอหรือOOMซ้ำให้หยุดรายงาน ไม่retryวนไปเรื่อย sourcesfreezeระหว่างรอ/รัน เมื่อbuildผ่านจึงรันpixelสองสีและstrictThaiตามแผน ไม่ส่งตัวpreviewที่ยังไม่ผ่านให้human

### Herdr Thai รับผลแล้ว / background appearance probe60 — 19 ตุลาคม 2026 เวลา14:43

ผู้ใช้กล่าว **“ภาษาไม่น่ามีปัญหาแล้วนะ แต่ตัว block หรือพื้นหลังต่างๆมันยังดูไม่สวยอ่ะ”** พร้อมภาพ รับbasicHerdrThaiบนcandidate59เป็นqualifieduserreportว่ารอบนี้ไม่พบปัญหาภาษา ไม่เหมารวมIMEทุกภาษา/DPI/ใช้งานยาวผ่าน ก่อนหน้า14:40ผู้ใช้บอกสัญลักษณ์ขอบขวาอยู่หลังslide/copyไม่ได้และน่าจะเป็นHerdr จึงพักglyphประเด็นนั้น ไม่แก้font/encodingจากการเดา ไม่claimพิสูจน์ownerแล้ว

ViewImageภาพล่าสุดเห็นblockพื้นดำเป็นแถบสลับช่องพื้นหลัก วัดpixelจริง default=#282C34 ตรงConfigdefault,block=#1E1E1E จึงยังแยกว่าเป็นสีintentของTUIหรือSGR49/EL/BCEผิด NativeCoreมีOSCcolorqueryreportอยู่และBundledfontไม่เกี่ยว ไม่แก้Herdrหรือบังคับpalette/เขียนconfigถาวร

เพิ่มcontrolledbackground_fixture RGB/default/index0/SGR49/EL/paddedspaces และprocess-localpreview_background6hexเท่านั้น Defaultไม่เปลี่ยน กำลังbuild60prefix`zig-out/background-probe`แยกจาก59ที่ผู้ใช้เปิดอยู่ ทวนpixelค่าที่คาดสองpreviewbackground282c34/1e1e1eและThai strictregression ไม่ใช้matchingbackgroundกลบrenderbugหากpixelไม่ตรง คงpinnedMicrosoftapp-localruntime/signaturesเดิม sourcesfreezeระหว่างjob และhumanappearanceacceptanceยังเปิด

### Herdr candidate59 screenshot — 19 ตุลาคม 2026 เวลา14:35

ผู้ใช้ส่งภาพHerdrในlocaltermโดยไม่เพิ่มverbalacceptance ViewImageตรวจได้:formattedThaiอ่านเป็นบรรทัด ไม่เห็นfloatingข้ามบรรทัดแบบภาพแรก แต่มีสัญลักษณ์คล้ายreplacementdiamondที่ขอบขวาหลายตำแหน่ง ยังไม่ระบุcodepoint/ว่าเป็นintentionalwrapmarker,missingglyphfallbackหรือFFFDในข้อมูล และไม่claimทุกscroll/redrawผ่านจากภาพเดียว

ตรวจreadonlyprocessmetadataยืนยันpreviewPID19120exe`zig-out/conpty-ab/bin/localterm-dev.exe`โหลดconpty.dllจากbinเดียวกันversion1.25.2609.30003จริง ไม่อ่านprocessmemory/session/clipboardหรือเปลี่ยนหน้าต่าง จึงรับเป็นagent-observedscreenshotของmoderncandidate ไม่ใช่humanverbalpass ยังต้องได้originalsymbol/codepointก่อนแก้glyphโดยเดา พบshaper/run.zigมีpathแทนunsupportedglyphเป็นFFFD จึงภาพอย่างเดียวแยกencodingไม่ได้ BundledNerdsymbolfontมีอยู่ในSharedGridSet ไม่เพิ่มfontcodepointmap/ติดตั้งfontล่วงหน้า

### Candidate59 modern strict lifecycle ยัง failed — 19 ตุลาคม 2026 เวลา14:11

`lifecycle-native-20261019-141007-062` modernprovider20cyclesหลังwarmupจบexit1/ResourceGrowth/timeoutFalse:handles233→234,threads6→7,GDI3→3,USER3→3 คงthreshold/deadline/PSSเดิม **ไม่ปิดblockerเพราะThai regressionผ่าน** และไม่เทียบabsolute235จากcandidate53คนละprocessเป็นleakที่ดีขึ้น ไม่ระบุcreatorรอบใหม่จากแค่netpattern

ยังไม่พร้อมใช้งานตามstrictgate ผลThai/keyboard/mouse/naturalexitและuserHerdrmanualต้องแยกกัน Binary59frozenไม่บิลด์ทับ ตอนนี้ไม่มีtestรันหลังlifecycleจบ รอผู้ใช้ทดสอบHerdrในcandidate59ด้วย-AppLocalConptyตามคำสั่งที่ส่งแล้ว ไม่เปิดGUI/Herdrแทนผู้ใช้ และไม่promotebackendเป็นdefault

### Candidate59 modern functional smoke ผ่าน — 19 ตุลาคม 2026 เวลา14:09

App-localinput(`input-native-20261019-140844-035`)ผ่านASCII/Thai/surrogate/Enter+WM_CHARrepeat2;MouseSmoke(`terminal-native-20261019-140854-638`)ผ่านdrag/rightcopy/CtrlShiftC/wheel/releaseในin-memorysinkไม่แตะOSclipboard;naturalexit(`exit-native-20261019-140905-053`)ผ่าน ทุกตัวexit0offscreen/noactivateและตรวจproviderloadedจริง ไม่ใช้เป็นhumanCtrlShiftC/IME/Herdrpass

ส่งmanualcandidate59ด้วยpreview-AppLocalConptyและต้องดูHerdrThai/scrollจริง ก่อนclaimHerdrแก้สำเร็จ กำลังทวนstrictlifecyclemodern20cyclesในbackgroundโดยคงthreshold/PSS/deadlineเดิม source/binary59frozen ไม่บิลด์ทับpreviewและไม่สร้างportablemarkerในexe-rootขณะhumanใช้ Normal+portableimage/fullCore/VTบนsourceใหม่นี้ยังไม่ผ่านรับรองเพิ่มเติม Defaultbackendยังไม่promote

### Candidate59 strict regression ผ่าน / manual Herdr พร้อมทดสอบ — 19 ตุลาคม 2026 เวลา14:07

Build59ผ่าน123/123,app-localstrictpacedredrawผ่านสองรอบ0cellsdifferent/cursor45ตรงdirectref,35frames/paintsทั้งคู่ มี16pacedrepaints/relativecursor/near-edgewrap ภาพPNGตรวจViewImageได้ SystemnegativecontrolfailConptyUnicodeModelMismatchจริง38cellsdifferent **รอบนี้cursorของsystem45เหมือนกันแล้ว** จึงไม่ลดregressionเป็นcursor-onlyและไม่เหมารวมclassiccursor52เกิดทุกรูปแบบ

Binary`zig-out/conpty-ab/bin/localterm-dev.exe` SHA256`123F6E375BFC3F00322335DB3419D8321916348A5578FE62FAFC6C10EF239BF6` frozen ส่งmanualด้วย`tools/windows/preview.ps1 -Executable .\zig-out\conpty-ab\bin\localterm-dev.exe -AppLocalConpty` ไม่ใช่candidate53เดิม Defaultbackendยังsystemหากไม่opt-in Userต้องทวนHerdrformattedThai/scrollจริงก่อนclaimแก้Herdrแล้ว

กำลังทวนinput/MouseSmoke/naturalexitบนmodernproviderแบบoffscreenในbackground ไม่แตะOSclipboard/เปิดHerdr/modelแทนผู้ใช้ ไม่บิลด์ทับ59ขณะรับmanual Helperเปิดmodernproviderได้กับterminalmodesแต่ยังlabelreadinessfalseสำหรับexperimentalbackendและไม่waivestrictresourcegate ยังไม่ทวนfullCore/VTบนsourceใหม่นี้

### Build58 A/B ชี้ modern provider / strict59 กำลังทวน — 19 ตุลาคม 2026 เวลา13:59

Build58ผ่าน123/123 และ4offscreenA/Bเสร็จแล้ว Systemยังunicode-reference38cellsdifferent/cursor52แทน45 แต่app-localdefault/wcswidth/graphemesทั้ง3แบบ **0cellsdifferent/cursor45ตรงreference** Rawlogยืนยันโหลดproviderจากexe-dirจริง ViewImageตรวจmodernPNGได้ ไม่เปลี่ยนfont/defaultlegacyเพื่อกลบอาการ ยังไม่ใช่Herdrhumanpass รายละเอียดhash/license/API/lifetime/commandsอยู่[ConPTY experiment](docs/windows-conpty-experiment.md)

กำลังbuild59เพิ่ม16pacedredraw/relativecursor/near-edgewrapและstrictmodelregression20แถว App-localต้องmatchdirectUnicodecell/grapheme/cursorทุกจุด sourceไม่เปลี่ยนระหว่างรัน ต้องให้systemnegativecontrolถูกrejectด้วยModelMismatchไม่ใช่timeout/crashก่อนส่งmanualPreviewใหม่ `preview.ps1 -AppLocalConpty`เป็นexplicitopt-inเท่านั้น ตัวเดิมยังsystemและไม่มีการเปิดHerdr/ส่งmodelแทนผู้ใช้ ไม่promoteproductionอัตโนมัติ

### App-local experiment อนุมัติ / build58 กำลังทวน — 19 ตุลาคม 2026 เวลา13:49

ผู้ใช้ตอบ **“ได้ทำเลย”** อนุมัติMicrosoftConPTY/OpenConsoleแบบapp-localA/B ไม่ใช่ยืนยันว่าแก้แล้วหรืออนุมัติเปลี่ยนdriver/OSsettings ดาวน์โหลดofficialNuGet1.25.260930003 SHA256`02B07B349AF66D801159BDF9E440D4A1CE78BB951F37FC8609731665AFDAE7EE`ลงcacheแล้ว `provision-conpty-experiment.ps1`ตรวจpin/signatures/เส้นทางและไม่ทับไฟล์ต่างhash วางDLL+EXEและMITnotice/nuspec/header/manifestเฉพาะ`zig-out/conpty-ab/bin` ทั้งสองbinaryลายเซ็นValid/Microsoft Corporation ไม่มีการinstallระบบหรือใช้ไฟล์Herdr/WT

เพิ่ม`conpty_windows.zig`experimentalproviderเฉพาะenvapp-local+experiment1 โหลดconpty.dllด้วยabsoluteexe-dir/LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|SYSTEM32 ไม่ค้นcwd/PATH ไม่มีfallbacksilent จับCreate/Resize/CloseจากmoduleเดียวและFreeLibraryหลังCloseHPCON/errorcleanupเท่านั้น Defaultsystemเดิม และnormalpreviewล้างexperimentenvทั้งหมด

Build58/A/B4casesกำลังรันsourcesfreeze:system0,app-local0,app-localwcswidth,app-localgraphemes ตรวจreceiptต้องเห็นloadedproviderจริงแล้วเทียบcells/cursorและPNG ไม่claimS_OK/load/parsepassคือHerdrvisualpass และstrictresourcegateยังไม่ถูกwaive ไม่มีการเปิดHerdrจริง/ส่งภาพขึ้นmodelแทนผู้ใช้

### Probe57: flags ไม่เปลี่ยนผล / ขอ scope decision — 19 ตุลาคม 2026 เวลา13:11

Build57ผ่าน123/123;system/wcswidth/graphemesownedoffscreenfixturesรันจบโดยยังเป็นdiagnostic ไม่visualpass ตรวจrawstderrยืนยันส่งflags0x10และ0x08จริงและHRESULT0 แต่ทั้ง3แบบยังcursor52แทน45/diff6และ38ตามreferenceเดิม **จึงไม่อ้างว่าflagแก้แล้วหรือสรุปsupportจากS_OK** ไม่เปลี่ยนproductionflags/defaults ไม่เพิ่มpaddingหรือrewriteANSIกลบอาการ

ขั้นถัดไปที่แนะนำคือA/BMicrosoftConPTY/OpenConsole redistributableแบบapp-local (คนละbackendจากsystemConPTY) เพื่อวัดmodel/redrawก่อนยอมรับเป็นproductiondependency ขอบเขตเพิ่มruntime/provider/packagingจึงต้องผู้ใช้อนุมัติก่อน ไม่copyไฟล์จากHerdr/WTหรือเปลี่ยนdefaultterminal/driver/OSsettings ตรวจเฉพาะmetadataNuGetofficialพบpackageMicrosoft.Windows.Console.ConPTY stableล่าสุด1.25.260930003 ยังไม่download/install/vendor runtime ไม่มีtestกำลังรันหลังprobe57จบ รอscopeapprovalนี้

หากอนุมัติ ต้องpinversion/hash/license,ใช้Create/Resize/CloseจากproviderเดียวกันและคงlibrarylifetimeจนHPCON/childcleanupจบ โหลดจากabsoluteapp-localpathเท่านั้น ทวนcursor/glyph/capture/keyboard/image/shutdown/resourcegate ไม่ถือว่าmodernruntimeจะแก้Herdrก่อนA/Bจริง

### Thai model56 พบ cursor-width discrepancy / probe57 — 19 ตุลาคม 2026 เวลา13:02

Build55compilefailเพราะreferenceTerminalไม่มีfieldio แก้ใช้global.ioแล้วbuild56ผ่าน123/123 พร้อมoffscreencontrolsUnicode/legacyทั้งคู่ ข้อมูลcellต่างreferencelegacy6cellsเฉพาะGCrow (representationSARAAM),referenceunicode38cells จึงไม่เหมารวมdifferentcells=ข้อความเสียทั้งหมด แต่finalcursorทั้งสองcontrolเป็น52แทนreference45 คำนวณอิสระtailstringยาว52UTF16unitsและมี7combiningmarks ตรงกับclassicconsolemeasurement ไม่ใช่หลักฐานfontinkผิด

ตรวจreadonlyWTใช้OpenConsole1.24ที่มากับแพ็กเกจ,เราใช้systemCreatePseudoConsole/conhost10.0.26100.1บนOS26200 แม้HerdrมีOpenConsole1.24.2607.10001ของตัวเองก็ไม่copy/loadเป็นdependencyของเรา MicrosoftCreatePseudoConsoleAPIpageบอกinherit-cursorเท่านั้น ขณะที่officialsrc/winconpty/winconpty.h/.cppกำหนดglyph-widthmask0x18,wcswidth0x10,graphemes0x08→--textMeasurement จึงกำลังbuild57 **diagnostic-only** widthflags0/0x10/0x08บนownedfixture เพื่อดูHRESULTและcursor/cellsจริง ไม่อ้างS_OKหมายความว่าAPIรองรับ/แก้แล้วและไม่เปลี่ยนproductiondefault/APIprovider/OSsettings/driver

ยังไม่ยืนยันHerdrdynamicredrawหายหรือmodernhostdependencyจำเป็น Sourcefreezeระหว่างprobe57 มีbackgroundjobทำงาน ไม่ขอผู้ใช้ทดสอบตัวที่ยังไม่แก้

### Thai TUI diagnostic54 / model55 — 19 ตุลาคม 2026 เวลา12:49

Build54ผ่าน123/123,offscreenfixture`terminal-native-20261019-124906-594`parse/render/paintผ่าน เก็บPNGและViewImageตรวจจริง:staticThaiหลายstyle/SARAAM/CUPดูเรียงเป็นบรรทัด ไม่เห็นอาการfloatingข้ามบรรทัดแบบHerdr จึง **ยังไม่reproduceHerdrเต็มและไม่อ้างแก้แล้ว**

กำลังbuild55เพิ่มexactUTF8/ANSIbytesชุดเดียว (base64ผ่านownedPowerShellstdoutเพื่อไม่แปลnewline)เทียบdirectTerminalmodelกับConPTYterminalmodelทีละcell/codepoint/attachedgrapheme+cursor และdiagnosticcontrollegacyvsunicodeเฉพาะfixture ไม่เปลี่ยนproductiondefault ไม่แก้HarfBuzz/driverโดยไม่มีหลักฐาน Modeldifferenceเป็นdiagnosticcountsไม่ใช่passรับรองlayout ไม่มีherdr/clipboard/modelnetworkcalls Sourcefreezeระหว่างbuild55

### Herdr A/B ยืนยัน WT ปกติ — 19 ตุลาคม 2026 เวลา12:40

ผู้ใช้ตอบ **“windows terminal ชัดปกติ”** พร้อมภาพเทียบ ViewImageเปิดได้จริง ThaiformattedTUIในWTชัดกว่าภาพcandidate53 จึงรับเป็นterminal-sidecompatibilityblockerก่อน ไม่แก้herdr ไม่เหมารวมว่าbyte-streamหรือterminalcapabilityสองฝั่งเหมือนกันทุกอย่าง

กำลังbuild54diagnostic`zig-out/thai-tui`เพิ่มcontrollednon-privateThaiANSIregular/bold/italic/dim/strike,mixedLatin,SARAAM,2027on/off,CUP/ELrenderแบบoffscreen/noactivate คงdefaultsก่อนแก้; parse/renderpassเป็นdiagnosticไม่ใช่visualacceptance/readiness และไม่launchHerdrจริง/อ่านsessionหรือclipboard Reviewagentreadonlyชี้ให้เทียบterminalmodelกับdirectVTก่อนblamefont เพราะConPTYflags0และTERM_PROGRAM=ghosttyอาจทำให้producer/cellwidthต่างจากWT อีกจุดThai-codepointoverrideตั้งregularfaceแม้styledตามresolversemantics จึงไม่แก้styledfontmatchingโดยเดา Existingstackedmarktestเฉพาะกี้ไม่ครอบคลุมSARAAM/longTUI

Configgrapheme-width-methoddefaultunicodeมีdocumentedcursor-desyncกับlegacywcswidthapps แต่ยังไม่เปลี่ยนproductiondefaultหรือปิด2027เพื่อให้ผ่าน ต้องวัดmodel/layoutก่อน Sourceคงเดิมระหว่างbuild54 ไม่มีdriver/settings/gatechanges

### Herdr Thai/TUI rendering report — 19 ตุลาคม 2026 เวลา12:02

ผู้ใช้รายงานเรียกherdrแล้วตัวหนังสือเพี้ยนพร้อมภาพ คราวนี้ViewImageเปิดภาพได้จริง เห็นThaiช่องไฟ/combiningmarks/ตำแหน่งบางส่วนผิดในformattedTUI ขณะที่Latinส่วนมากอ่านได้ **ยังไม่พิสูจน์ว่าเป็นUTF8/fontshaping/widthmeasurementหรือANSIcursorlayout** และไม่ใช้basicThaihumanpassปิดกรณีนี้

ตรวจreadonlyGet-Commandพบherdr.exeจากstandalone0.9.3-x86_64-pc-windows-msvcและPEconsole subsystem3 ไม่launchHerdr/เรียกmodelหรือแก้herdrrepoเอง ต้องA/Bherdrrelease/ข้อความเดียวกันในWindowsTerminalเทียบcandidate53ก่อนระบุfaultowner ถ้าWTปกติให้เจาะterminal/rendering/widthcompatibilityของเราก่อน ถ้าทั้งคู่ผิดให้ตรวจHerdroutput/TUImeasurementต่อ ไม่claimownerจากภาพเดียว ยังไม่มีAI-CLIimageconsumerpass

### AI-CLI เป้าหมายระบุแล้ว — 19 ตุลาคม 2026 เวลา 11:53

ผู้ใช้ระบุ **Letta Code** ตรวจreadonlyพบlauncher`C:\nvm4w\nodejs\letta.ps1`,เรียกletta.cmd--versionได้0.34.17 และletta.js/image-resize-worker.jsที่เคยขาดตอนนี้มีแล้ว **ไม่ได้ติดตั้ง/แก้harnessเอง** ยืนยันคำสั่งletta,/newและCtrl+VจากCLIreferenceทางofficialdochelper (local+CLI) ก่อนแนะนำmanualintegration ใช้ภาพไม่มีข้อมูลสำคัญและpromptอ่านเฉพาะภาพ/ไม่แก้ไฟล์ ไม่เรียกmodelหรืออัปโหลดแทนผู้ใช้ ยังไม่claimAI-CLIimageconsumeผ่านก่อนผู้ใช้ส่งทดสอบ

### Candidate53 baseline จบ — 19 ตุลาคม 2026 เวลา 11:43

Full-core `copy53-test-20261019-110056`ผ่าน3926/3987tests/61skip,89/89steps,exit0; VT `copy53-test-lib-vt-20261019-111609`ผ่าน6722/6786tests/64skip,45/45steps,exit0 แบบ-j1/Debug/ไม่filter sourceคงเดิมจนจบ ทั้งสองเป็นผลหลังmouse/copyจริง ไม่ใช้candidate50แทน

Strictlifecycle `lifecycle-native-20261019-114247-673`ยังfailedResourceGrowth/exit1/ไม่timeout:20cyclesหลังwarmup handles235→236,GDI3→3,USER3→3,threads6→7 **ไม่ใช้233vs235จากคนละprocessสรุปว่าเพิ่มleak2** และไม่ยืนยันcreatorของรอบใหม่นี้จากแค่deltaเดิม หลักฐานAMD/RPCก่อนหน้าอยู่ในattributiondoc ไม่ใช่สิทธิ์ปิดforeignhandlesหรือผ่อนgate

ตอนนี้ไม่มีtestกำลังรัน ManualbasicThai/textpaste/rightclickcopy/wheel/release/normalimagepathผ่านจากuserreportตามscopeเดิม ยังไม่พร้อม:strictresourcegate,CtrlShiftCmanualที่เคยfailยังไม่รับรองใหม่,AI-CLIconsumeimageต้องทราบCLIเป้าหมาย,portablehuman/DPI/IMEcompositionและเกณฑ์ใช้จริงยังเปิดอยู่ รอชื่อAI CLIที่ถามผู้ใช้ไว้ ไม่เริ่มส่งภาพขึ้นserviceหรือแก้driver/OSsettingsเอง

### Human clipboard image normal ผ่านถึง path insertion — 19 ตุลาคม 2026 เวลา 11:34

ผู้ใช้ตอบ **“ได้ปกติ”** หลังขั้นPaintภาพไม่มีข้อมูลสำคัญ→Ctrl+A/Ctrl+C→terminalCtrl+V/อนุญาต→เห็นquotedPNGpathโดยยังไม่Enter รับเป็นuserreportedpassของnormal-modeOSclipboardimage→pathinsertion ไม่อ้างagentอ่านclipboard/เห็นภาพ/ตรวจไฟล์นั้นเอง หรือAI-CLIconsumeimage/portablehumanผ่าน ขั้นถัดไปต้องระบุCLIที่ใช้จริงก่อนintegrationacceptance ไม่เดาว่าLetta/Claude/Codexตัวใด

Baselineล่าสุด`copy53-test-20261019-110056`จบexit0เมื่อ11:16:09แล้ว pipelineยังทวนVT→strictlifecycleต่อ ไม่แก้sourcesระหว่างรัน ไม่ใช้fullcorepassปิดresourcefailure

### Human focus-loss release ผ่าน — 19 ตุลาคม 2026 เวลา 11:06

ผู้ใช้ตอบ **“ไม่ค้างตาม”** หลังdragselectionค้าง→Alt+Tab→ปล่อย→กลับมา รับเป็นuserreportedpassของfocus-lossreleasecandidate53 ชุดmanualmouseที่ส่งให้ผ่านrightclickcopy/verticalwheelscrollback/ปล่อยนอกขอบ/focus-lossไม่ค้างแล้ว ไม่เหมารวมCtrl+Shift+Cที่เคยรายงานไม่สำเร็จ,ทุกDPI/ทุกTUIหรือclipboardimage/CLI Full-core→VT→strictlifecyclejobเดิมยังทวนแยก sourceไม่เปลี่ยน ขั้นmanualถัดไปภาพclipboardที่ไม่มีข้อมูลสำคัญจากPaint→Ctrl+Vเพื่อดูquotedPNGpath/permissionโดยยังไม่กดEnter ไม่ใช่agentอ่านclipboard

### Human physical capture ผ่าน — 19 ตุลาคม 2026 เวลา 11:04

ผู้ใช้ตอบ **“ได้”** หลังทดสอบdragselectionออกนอกขอบ→ปล่อยเมาส์→กลับเข้ามาโดยไม่กดปุ่ม รับเป็นuserreportedpassว่าphysicalcapture/releaseไม่ลากค้างสำหรับกรณีนี้ รวมmanualrightclickcopyและverticalwheelscrollbackผ่านแล้ว ไม่เหมารวมfocus-lossระหว่างลาก/ทุกจอDPI/ทุกTUI Full-core→VT→strictlifecyclecandidate53ยังเป็นงานทวนเดิม ห้ามอ้างcandidate50baselineแทนผลใหม่ ขั้นmanualต่อไปfocus-lossระหว่างdragเพื่อตรวจอีกreleasepath

### Human wheel ผ่าน — 19 ตุลาคม 2026 เวลา 11:01

หลังให้สร้างhistory100บรรทัดและเลื่อนขึ้น/ลงกลับprompt ผู้ใช้ตอบ **“ได้ปกติ”** รับเป็นuserreportedpassของbasicverticalwheelscrollbackcandidate53 ไม่เหมารวมhorizontalwheel/touchpad/TUImousereportingทุกแบบ ขั้นถัดไปตรวจphysicaldragออกขอบแล้วปล่อยว่าไม่ค้างcaptureซึ่งoffscreenไม่ได้จับเมาส์จริง Full-core/VT/lifecyclejobเดิมกำลังรัน sourceไม่เปลี่ยน

### Human right-click copy ผ่าน — 19 ตุลาคม 2026 เวลา 11:00

หลังส่งcandidate53ให้ผู้ใช้ลองลากเลือก→คลิกขวา→วางNotepad ผู้ใช้ตอบ **“ได้แล้วทำอะไรต่อ”** รับเป็นuserreportedpassของright-clickcopy/OSclipboardintegrationตามขั้นนี้ ไม่ใช่agentอ่านclipboardและไม่เหมารวมCtrl+Shift+CหรือCtrl+C/clipboardimage/CLIผ่าน ขั้นต่อไปmanualwheelup/downในhistory100บรรทัด ขณะนี้เริ่มfull-core→VT-j1ไม่filter→strictlifecycleบนcandidate53อีกครั้งเป็นbackgroundjob หลังmanualcopyblockerคลี่คลาย คงsourcesจนจบ ไม่เปลี่ยนgatesและยังไม่declareพร้อมใช้งาน

### Candidate53 ผ่าน targeted regression — 19 ตุลาคม 2026 เวลา 10:41

Build53ผ่าน123/123; keyboardCtrlShiftCและrightclickcopy→Core→in-memorysink bytesตรงกับselectionทั้งสองรอบ; rightclickไม่มีselectionไม่เพิ่มwriteและไม่paste ตามด้วยmouseviewport/cancel,keyboard,boundedqueueburst-title,naturalexit,imageE2Enormal/portableผ่าน Candidateล่าสุด`zig-out/copy-input/bin/localterm-dev.exe` SHA256 `0EF93F4DAA02094578CBAFA6FB47D131655CC7026F8A6092FCC152B2FD235C56`

**ยังไม่พิสูจน์Windowsclipboardwriteหรือสาเหตุmanualshortcutfailure** ไม่ใช้sinkpassปิดcopyblocker ส่งผู้ใช้ปิดตัวเก่าเปิดprefixcopy-inputใหม่แล้วลากเลือก→คลิกขวา→วางNotepad ตอนนี้ไม่มีtestกำลังรัน รอmanualOSboundaryนี้ก่อนทวนfull-core/VTของsourcefinalอีกครั้ง (ชุดmouse52ถูกcancelไปแล้ว ไม่ใช่baselinepass) ไม่วนbaselineยาวระหว่างกำลังแก้copyblockerและไม่อ่าน/เขียนclipboardแทนผู้ใช้ Strictresourcegateยังfailedตามเดิม

### Copy blocker / right-click copy — 19 ตุลาคม 2026 เวลา 10:32

ผู้ใช้รายงานCtrl+Shift+Cยังไม่ได้เหมือนเดิม และขอ **“ทำให้คลุมข้อความแล้วคลิกขวาคือ copy ด้วย”** ยังไม่ปิดcopyblockerหรือโยนว่าใช้shortcutผิด หยุดbaselineownedPID22964พร้อมverifieddescendantsก่อนแก้source (ตรวจpathและstarttime;ไม่แตะpreviewผู้ใช้) ดังนั้นmouse52-fullcoreexit255เป็นintentionalcancellation ไม่ใช่assertionfailureและVT/lifecycleชุดนั้นยังไม่รัน

ตั้งWin32right-click-action=.copyตามCoreเดิม:คัดลอกselectionปัจจุบัน ไม่แทนด้วยwordใต้เมาส์ ไม่pasteเมื่อไม่มีselection เพิ่มmousefixtureผ่านnativeCtrlShiftCkeyhandlerและrightclick→Corecopy→in-memoryclipboard sink ตรวจbytesเท่ากับselection และไม่มีselectionต้องไม่เขียนเพิ่ม ทั้งหมดไม่อ่าน/เขียนOSclipboard Fixtureเปิดwritecapabilityเฉพาะsinkแต่บล็อกclipboardRequestจริงทุกsmoke ไม่เปลี่ยนproductionclipboardpermissions/Windowswriter ขณะนี้build53/regressionsกำลังรันใน`zig-out/copy-input` ไม่แก้sourcesจนจบ ยังไม่ยืนยันrootcauseของmanualcopyfailureหรือOSclipboardwriteสำเร็จ

### Mouse candidate52 — 19 ตุลาคม 2026 เวลา 10:27

Build51ติดcompileชื่อlocalreadyชนcallbackreadyก่อนsmoke แก้ชื่อfixture_readyแล้ว **build52ผ่าน123/123**; mouseoffscreen2รอบผ่านselectionStringไม่ว่าง/viewportเลื่อนขึ้นแล้วกลับbottom/capture-lossreleasesทุกbutton พร้อมkeyboard/burst-title/naturalexit/imageE2Enormal+portableผ่าน Artifactใหม่`zig-out/mouse-input/bin/localterm-dev.exe` SHA256 `19B1667DFD3CA1D145D9D82D17C5E8F254DD8A294F5452220AC912DFD7291966` ไม่แทนcandidate50ที่อาจเปิดอยู่

ขณะนี้รันfull-core→VTแบบ-j1ไม่filterตามด้วยstrictlifecycleบนcandidate52เป็นbackgroundjob ไม่แก้sourcesจนจบ ส่งผู้ใช้ปิดpreviewเก่าแล้วเปิดprefixใหม่เพื่อmanualdrag/copyด้วยCtrl+Shift+Cและwheel ไม่ใช้syntheticWM_CAPTURECHANGEDแทนphysicalSetCaptureacceptance และไม่อ้างclipboardwriteผ่านจากselectiontest ดู[windows-mouse-input.md](docs/windows-mouse-input.md)

### Mouse/selection blocker จาก human report — 19 ตุลาคม 2026 เวลา 10:14

ผู้ใช้ยืนยัน **“วางได้ปกติ แต่ copy ไม่ได้ คลุมตัวหนังสือไม่ได้ และสกอเมาส์ไม่ได้”** รับmanualtextpasteเป็นuserreportedpassเท่านั้น ไม่อ้างcopyหรือmouseผ่าน พบWin32มีkeyboardhookและcopybindingแต่ไม่มีmousehooksเข้าCoreเลย จึงเพิ่มclientphysical-pixelposition/dragbuttons/wheel→Corecallbacks, HWNDcaptureเฉพาะrealinteractiveinput, capture/focus-lossrelease, wheelScreenToClientและsignedcoords ไม่ทำselectionหรือscrollbackจำลองแยกจากCore

Mousepayloaddecoder3testsผ่าน ได้แก่negativecoordinates/buttondouble-X/wheelsignedpartialdelta กำลังbuild51ไว้`zig-out/mouse-input`แยกจากcandidate50ที่ผู้ใช้อาจเปิดอยู่ แล้วทวนoffscreenselectionString/viewportup-down/cancelสองรอบ +keyboard/shutdown/image regressions Nativeautomatedsmokeไม่เรียกSetCapture/SetFocusและnativeclipboardcapabilityปิดในsmokemode ไม่อ่าน/เขียนclipboardหรืออ้างmanualdrag/copyผ่านก่อนผู้ใช้ลอง ตัวsubagentรันไม่ได้เพราะCLIไฟล์หายจึงตรวจเอง ไม่แก้harnessinstallation

### Human basic Thai/input report — 19 ตุลาคม 2026 เวลา 10:12

หลังผู้ใช้เปิดmanualpreviewตามคำสั่งcandidate50และได้รับchecklistพิมพ์ไทย/อังกฤษ/สระวรรณยุกต์/Backspace/ลูกศร/Enter ผู้ใช้ตอบ **“ปกตินะ”** พร้อมแนบภาพ บันทึกเป็นhumanรายงานว่าการตรวจพื้นฐานชุดนี้ปกติ ไม่ใช่agentvisualverification: ViewImageเปิดภาพไม่สำเร็จเพราะimageworkerของharnessหาย ไม่ติดตั้ง/ซ่อมharnessเองและไม่อ้างเห็นภาพแล้ว ยังไม่ครอบคลุมIMEcandidate/compositionทุกภาษา/physicalDPI/clipboard/CLIจริง/การใช้จริงสองสัปดาห์ และไม่ลบstrictresourcefailure ขั้นต่อไปmanualpasteข้อความที่ไม่สำคัญด้วยCtrl+Shift+Vตามkeybindingจริง โดยagentไม่อ่าน/เขียนclipboardแทนผู้ใช้

### Preview helper path fix — 19 ตุลาคม 2026 หลังผู้ใช้ลองเปิดจริง

ผู้ใช้พบ`Preview executable must be ... inside this workspace`จากrelativepathที่คู่มือให้ สาเหตุhelperใช้.NET GetFullPathซึ่งอิงprocesscwdที่ไม่จำเป็นต้องตรงPowerShell Set-Location แก้preview.ps1ให้resolveผ่านPowerShellproviderโดยคงworkspace/filenameguardเดิม `preview-path-test.ps1`ผ่านrelative/absolute/normalized paths ขณะ.NETcwdอยู่Windowsแต่PSอยู่workspace,ยังrejectsibling/wrongfilenameและrestoreenvironment ทดสอบด้วยinterceptStart-Processไม่เปิดGUI ไม่เปลี่ยนcandidate50binary/strictgateหรือclaimhumanacceptance

### ล่าสุด 19 ตุลาคม 2026 เวลา 09:27 — regression จบ รอ human acceptance/ข้อจำกัด resource

Full-coreหลังpatchผ่าน3926/3987tests/61skip,89/89steps,exit0 ตามด้วยVTเต็ม `post-shutdown-vt-50-20261019-090857` ผ่าน6722/6786tests/64skip,45/45steps,exit0 ไม่ซ้อนcore ImageE2E normal/portableเพิ่มอีกสองชุดผ่านทั้ง4sessions (09:26:34/44/55และ09:27:05) รวมbuild50ผ่านสามชุดnormal+portable ตรวจcleanupสำเร็จไม่มีportable-datafixtureค้าง SHA256ยัง `8674943AB93F3372ADCCAB3654B513279513D4372F6E5CA8FEF0446DC3B82EF3`;gitdiffcheckผ่าน ไม่มีtestกำลังรันหลังชุดนี้จบ

**ยังไม่พร้อมใช้งานและไม่รับexception:** strictlifecycle233→234handles/6→7threadsยังfailed แม้พิสูจน์retainedopensในGPU-onlyว่าเป็นAMD/RPC ไม่ใช่สิทธิ์ให้ปิดforeignhandles/แก้driver/เปลี่ยนthresholdเอง ขั้นถัดไปที่ต้องมนุษย์ช่วยคือเปิดcandidate50ด้วยpreview.ps1แบบmanualตรวจภาษาไทย/IMEก่อน แล้วจึงclipboard/CLIจริงตามความยินยอม ไม่มีการเปิดGUIหรืออ่านclipboardอัตโนมัติแทนhuman criterion และไม่ข้ามไปแพ็กportableเฟส6

### ล่าสุด 19 ตุลาคม 2026 หลัง full-core retry รอบเช้า

ผู้ใช้สั่งลองใหม่เมื่อ08:51; เริ่มด้วยfreeRAM20.6GiB/freevirtual25.2GiB **full-coreหลังpatchผ่านแล้ว**: `post-shutdown-full-core-50-j1-20261019-085233`, exit0,89/89steps,3926/3987testsผ่าน/61skip คงDebug/ไม่filter/-j1 ใช้เวลารวมประมาณ15นาที ไม่ใช้OOMสองรอบก่อนหน้าแทนtestfailureและไม่ลบhistory

Zig summaryรายงานcompile test MaxRSS9G และrun test MaxRSS331M ไม่ใช่RAMขั้นต่ำทั้งเครื่อง ตัวsampler178จุดเห็นแค่launcherPID14552เพราะตามancestryผ่านintermediate build processไม่ครบ จึง**ใช้peak0GiBที่ปัดจากlauncherไม่ได้** บันทึกmemory-correctionในresults.jsonlแล้ว ไม่rerun15นาทีเพียงเพื่อแต่งmemoryreport ไม่มีการเปลี่ยนpagefile/ปิดโปรแกรมผู้ใช้

ตอนนี้ทวนVTbaselineเต็ม-j1ต่อแล้วจะimageE2Enormal/portableเพิ่มสองชุดแบบไม่อ่านclipboard; freeze sourcesจนjobจบ ยังคงstrictlifecycle233→234/6→7failedและhumanacceptanceเปิดอยู่ จึงยังไม่พร้อมใช้งาน เฟส6ยังเป็นแผนไม่ข้ามไปimplementเอง

### ล่าสุด 19 ตุลาคม 2026 เวลา 00:05 GMT+7 — blocked ด้านหน่วยความจำ

**ไม่มี build/test กำลังรันหลัง retry จบ** Full-core หลัง patch สองรอบ (`post-shutdown-full-core-50` และ `post-shutdown-full-core-50-j1`) ล้มระหว่าง LLVM compile ด้วย out-of-memory/exit9,86/89steps ยังไม่ได้รัน test executable จึงไม่ใช่ assertion failure และ **ยังไม่มี full-core pass หลัง patch** รอบ-j1คงDebug/ไม่filter/ไม่เปลี่ยน tests ก่อนเริ่มมี free physical11,973MiB,free virtual4,706MiBจากWMI (ไม่ใช้ค่านี้อ้างวัดpeakหรือพิสูจน์pagefile configuration) ไม่ retry ต่อ/เปลี่ยนpagefile/ปิดโปรแกรมผู้ใช้เอง

Agent-actionable shutdown fix/native regressions และ synthetic image normal/portable ผ่านตามbuild49/50 แต่ยังไม่พร้อม: รอทรัพยากรพอสำหรับfull-core, strict lifecycle233→234/6→7ยังfailed, human Thai/IME/OSclipboard/CLI/physicalDPIและเกณฑ์ใช้จริงเฟส5ยังเปิดอยู่ เฟส6เป็นแผนเท่านั้นยังไม่อนุมัติให้ข้ามblockerไปimplementแพ็กเกจ ไม่ใช้portableimagecacheที่ผ่านแทนportableทั้งแอป

### ล่าสุด 19 ตุลาคม 2026 เวลา 00:03 GMT+7

Build50 ผ่าน123/123 และ synthetic image E2E ทั้ง normal/portable, queue-full shutdown repro, plain burst, input ผ่านบน artifact เดียวกัน SHA256 `8674943AB93F3372ADCCAB3654B513279513D4372F6E5CA8FEF0446DC3B82EF3` ขณะนี้รัน **full-core ไม่ filter หลัง shutdown patch** อยู่ ห้ามแก้ sources ที่ validation ใช้จนเสร็จ

Build49 ยืนยัน queue-full repro3/3 และ plainburst3/3 รวม window/input/exit/missing-shell ผ่าน แต่ image consumer ไม่ตอบก่อนปิด จึงไม่ได้รัน portable/lifecycle ใน pipeline นั้น; เก็บ failure ไว้ Build50 แก้ synthetic image Enter ที่ยังรับ global modifier จากผู้ใช้ในโปรแกรมอื่น (ให้แยกเหมือน input smoke) และเพิ่ม receipt ว่า Enter dispatch แล้ว จากนั้นทั้งสองโหมดผ่าน **ไม่อ้างว่าพิสูจน์ root cause ของ failure49 ได้จากการผ่านรอบเดียว** และไม่ใช้แทน OSclipboard/AI-CLI acceptance

**strict lifecycle ล่าสุดยัง failed จริง** `lifecycle-native-20261018-235936-910`: handles233→234, GDI3→3,USER3→3,threads6→7 ไม่มี timeout และไม่ได้ผ่อนเกณฑ์ ยังไม่พร้อมใช้งาน/humanThai-IME/clipboard/CLI/physicalDPI ยังเปิดอยู่

### ล่าสุด 18 ตุลาคม 2026 เวลา 23:48 GMT+7

ยังทำงานต่อ ไม่ได้รออนุมัติ debugger แล้ว: ผู้ใช้อนุมัติติดตั้งและติดตั้ง Microsoft Debugging Tools สำเร็จ 23:16:54 (CDB signed/รันได้, 346.5 MiB) รายละเอียดและหลักฐานอยู่ [windows-runtime-attribution.md](docs/windows-runtime-attribution.md)

- Retained opens ใน GPU-only control พิสูจน์ได้จาก creator TID + live stacks: AMD hook Thread หนึ่ง handle, RPC `ThreadSelf` Event และ duplicate current-thread handle อีกสองรายการ ยังไม่ปิด strict lifecycle gate/net +1 และไม่ปิด foreign handles เอง ไม่อ้าง close owner ของ ALPC −2 ที่ไม่มี live close stack
- Plain burst build46 ผ่าน 10 รอบโดยไม่มี debugger ก่อน failure แต่ยังเก็บ timeout build43 ไว้ ไม่สรุปแก้จาก rerun ผ่าน
- `burst-title` control ทำให้ปิดค้างได้ 3 รอบตาม 60s เดิม; มีรอบ queue เต็มจาก title stream เอง (`inserted=0`) ก่อนการเติมข้อความจำลอง PDB จากรอบ 23:40 ยืนยัน **UI รอ draw mutex ใน displayUnrealized / renderer ถือ mutex และรอ .redraw ใน UI mailbox / reader รอ title ใน mailbox**
- แก้เฉพาะ Win32 ให้ Surface ไม่เข้า blocking unrealize ก่อนหยุด workers (WM_CLOSE ยังเก็บ HWND/DC ไว้จน deinit เสร็จก่อน DestroyWindow) และ UI drain Core mailbox ระหว่าง join IO/renderer หลัง deregister surface ไม่ drop redraw/health ให้ดูเหมือนผ่าน runtime อื่นใช้ join เดิม
- Build48 พบ compile error namespace Win32 wait ก่อน smoke จึงแก้ใช้ explicit kernel32 import ตามรูปแบบโปรเจกต์ **ขณะนี้ build49 + queue-full3 / originalburst3 / window,input,exit,missing-shell / image normal+portable / strictlifecycle กำลังรัน** ยังไม่อ้าง fix ผ่านหรือพร้อมใช้งาน รักษา freeze ของ sources ที่ build/test กำลังใช้

### คำสั่งทำงานต่อเนื่อง — 18ตุลาคม2026 18:54 GMT+7

ผู้ใช้สั่ง **“ทำจนกว่าจะพร้อมใช้งานหากพร้อมใช้งานให้บอกฉัน”** ให้ทำ approved milestones ต่อโดยไม่รอให้ตาม ไม่ใช้ buildผ่านแทนพร้อมใช้งาน คงห้ามcommit/push/แก้driver/ผ่อนresource threshold,warmup,deadline Automatedwindowsต้องพ้นvirtualdesktopทุกจอ/noactivateและคงrender/paintchecks ส่วนmanualpreviewแสดงปกติ

ยังไม่พร้อม: WIN-RUNTIME-004 handles233→234/threads6→7,ภาพไทยยังไม่ผ่านhumanacceptance,clipboard/CLIจริงและIME/physicalDPIยังต้องยืนยันพร้อมเกณฑ์ใช้งานในเฟส5–6 ห้ามagentclaimhuman-ownedcriteriaเอง ระหว่างรอhumanให้ทำส่วนที่ทดสอบเองได้ต่อ

งานที่กำลังทำ: (1)PSSown-processno-GPUcontrolพบแต่ละprocesscountsคงที่ ไม่ใช้63vs57ข้ามprocessสรุปdelta;กำลังเทียบPSSon/offในreal-surfacelifecycleโดยcountergateเดิมและlabelcontrolว่าไม่เป็นreadinessevidence (2)nativeclipboardharnessใช้newprivatewindowstation/desktopในhelperprocessที่ไม่แสดงwindowและfailclosed เพื่อไม่แตะWinSta0clipboardของผู้ใช้ แล้วทำimage/portable/error/permission/CLIintegrationที่ยังเหลือต่อ (3)ไล่ฟอนต์ไทยและgateอื่นในแผนเดิมจนปิดจริง ไม่เรียกexperimentalimagecacheว่าfullportable

อัปเดต19:56:PSScauseถูกตัดออกแล้ว; pacedGPU-onlyreproducepattern**+2Thread(AMDhook/NTDLL)+1Event−2ALPCPort=+1**เหมือนterminal ไม่มีCore/ConPTY ยังไม่ปิดWIN-RUNTIME-004/ไม่รับexceptionเอง PrivatewindowstationถูกAccessDeniedแม้least rightsจึงblockedOSclipboardtest ไม่fallbackหรือยกสิทธิ์ NativeTT/ThaiUIfixture4แบบผ่านและHarfBuzz94/101pass(7skip) Candidateใช้Consolas+ThaiUI/nativeTT/23pxrows ยังไม่ผ่านhumanvisual

Build42ผ่าน123/123; syntheticimageE2Eผ่านจริงทั้งnormalและportableผ่านproductionstaging→Core→PTY→PowerShellliteralparser→independentGDI+PNGdimensions/pixels พร้อมexpectedroot/cleanup/ไม่แตะOSclipboardและไม่executeข้อความ รูทnormalมีspace/quote/Thai;พบPS5.1อ่านUTF8noBOMliteralผิด จึงใช้codepointsในharnessและคงrootassertion ทั้งสองsessionexit0/ownedpathsไม่เหลือ **ยังไม่แทนCtrlV OSclipboard permissionหรือAI-CLIacceptance** ขณะนี้ทวนfull-coreและnativewindow/input/exit/burst/bad-shell/lifecycleบนcandidate42ผ่านbackgroundjob ไม่แก้sourceที่testกำลังใช้ และไม่ประกาศพร้อมจนปิดเกณฑ์จริง

อัปเดต20:26:full-core **3926/3987ผ่าน/61skip**,89/89steps; native42window/input/exit/burst/missing-shellผ่าน แต่strictlifecycle233→234/6→7ยังfailed Native43ปรับnon-fontfixturesให้ใช้configเดียวกับpreview;HarfBuzzbounds94/101ผ่าน/7skip รวมrow19/23,light/nativeTT,UI/Consolas+UI,graphemeเปิด/ปิด ตรวจinkไม่ล้นแนวตั้งเมื่อ+4rowsและConsolaswidth9px Native43imageE2Enormal/portable,input,exitผ่าน แต่**burst-native-20261018-201704-221 timeout60sหลังterminalmarkercheck** จึงเป็นshutdownblockerใหม่ ไม่อ้างว่าชุดก่อนผ่านแล้วปิดได้

Build44เพิ่มcheckpointnotifyIO/stopcallback/childstop/readercancel/join ผ่าน123/123;burst3รอบผ่าน4907/4775/5022framesพร้อมcheckpointครบ แต่**ไม่ได้แก้shutdownlogicและยังreproducehangพร้อมcheckpointไม่ได้** ไม่ปิดissueจาก3passes และไม่เพิ่มtimeout Nativeartifactprefixถูกเขียนทับด้วยbuild44แล้ว SHAของbuild42ในdocsเป็นhistoricalเท่านั้น ยังไม่มีhuman acceptance ไม่พบCDB/WinDbgในSDK/PATH/packageที่ตรวจ ขออนุมัติติดตั้งเฉพาะMicrosoftDebuggingToolsแล้วเมื่อ20:17 ยังไม่อนุมัติจึงไม่ติดตั้ง/แก้driver/settings/gate;ถ้างานพักตรงนี้คือรออนุมัติdebugger ไม่ใช่มีtestbackgroundรันอยู่

| รายการ | ผลตรวจ ณ วันที่ปรับแผน |
|---|---|
| Checkout | สาขา `main`, HEAD `b3dc3d794513c11633e7c3347935693957744e83` |
| รุ่นในซอร์ส | `1.3.2-dev`, `minimum_zig_version = "0.16.0"` ใน `build.zig.zon` |
| Remote | `origin` fetch/push เป็น `https://github.com/nickza2026/ghostty-windows`; ยังไม่มี `upstream` |
| ไฟล์ที่ไม่ติดตาม | `PLAN.md` และ `.letta/`; ไม่ถือว่าเป็นของทิ้งและไม่ stage รวมอัตโนมัติ |
| เอกสารที่ยังไม่มี | `docs/sources.md`, `docs/reference-notes.md`, `docs/gaps.md` |
| Windows PTY | มี implementation และจุดเชื่อม termio อยู่แล้ว แต่ยังไม่ทดสอบ runtime |
| แอป Windows | ไม่มี runtime Win32 ให้เลือกใน enum และ switch ของ executable |
| เครื่องมือ | ไม่พบ `zig` ใน PATH; พบ VS 2022 และ MSVC แต่ `cl` ไม่อยู่ใน PATH ของเชลล์ที่สำรวจ |
| ผลบิลด์/เทสต์/GPU | ยังไม่ได้รัน จึงไม่มีหลักฐานว่าผ่าน |

HEAD นี้เป็น **baseline ที่ตรวจพบในเครื่อง** ยังไม่ใช่หลักฐานยืนยัน provenance ว่าทั้งทรีตรงกับ official Ghostty ที่ SHA เดียวกัน ต้องตรวจจาก official remote ในเฟส 1 ก่อนรับรองที่มา ห้ามเลื่อน baseline ไปตาม `main` โดยไม่บันทึก

สถานะ discussion, PR, รุ่นล่าสุด และความสามารถของ Noctty ที่แผนเก่าอ้างถึงยังไม่ได้ตรวจออนไลน์รอบนี้ จึงไม่ใช้เป็นหลักฐานผ่านเฟสหรือเหตุผลให้รับโค้ดเข้าทรี

### ความคืบหน้าหลังเริ่มงาน

16 ตุลาคม 2026: สถานะในตารางข้างบนเป็น snapshot ก่อนเริ่มงาน ปัจจุบันสร้างสาขา `windows-terminal-baseline` จาก `main`, เพิ่ม `upstream` และตั้ง push URL เป็น `DISABLED` แล้ว ผล fetch ยืนยันว่า `upstream/main` ตรงกับ baseline และ tracked tree ไม่มี diff สร้าง `docs/sources.md` กับ `docs/windows-validation.md` แล้ว

MSVC/SDK discovery ผ่านใน Developer Shell x64: toolset `14.44.35207`, SDK `10.0.26100.0` ไม่ต้องติดตั้ง VS เพิ่ม ต่อมาติดตั้ง Zig portable `0.16.0` หลังผู้ใช้อนุมัติ ตรวจ SHA-256 และ `zig version` ผ่านแล้ว เฟส 0 ผ่านเกณฑ์เครื่องมือพร้อม

เวลาใกล้ 11:13 GMT+7: VT tests ผ่าน 3,596 และ skipped 32, library build และตัวอย่าง C static/dynamic build/runtime ผ่าน exit 0 ทั้งหมดตามขอบเขตที่ตรวจแล้ว

เวลา 11:15:25 GMT+7: full-core probe จบ exit 1; `87/91 steps succeeded (1 failed)` ขั้น `translate-c posix_c.h` ล้มเพราะ `pwd.h` ไม่พบบน MSVC ต้นทางคือ `src/build/SharedDeps.zig:219–229` ส่วน `hb_c.h` แปลงสำเร็จแม้มี warnings เฟส 1 จึง blocked ที่ full-core compatibility ยังไม่เริ่มแก้ implementation หรือเฟส 3 รอผู้ใช้ตัดสินใจขอบเขต patch ดู `docs/gaps.md` และ `docs/windows-validation.md` ผลนี้ยังไม่รับรอง GUI/renderer/PTY runtime

เวลา 11:41 ผู้ใช้อนุมัติ patch `posix_c`; เพิ่ม non-Windows guard ใน `SharedDeps.zig` แล้ว Full-core recheck จบเวลา 11:43:23 exit 1 โดยข้ามปัญหา `pwd.h` ได้ แต่ติด Linux DMA-BUF ใช้ Windows HANDLE type ใน `src/renderer/Dmabuf.zig:44` ยังไม่แก้ renderer เพราะเกินขอบเขต build/import ที่อนุมัติ กำลังรัน VT regression ของ patch ปัจจุบัน และรออนุมัติขยายขอบเขตตาม WIN-BUILD-002 ก่อนเดินต่อ

เวลา 11:44 ผู้ใช้อนุมัติขยาย DMA-BUF compatibility แล้ว: แก้เฉพาะ `OpenGL.zig` ให้ Windows ไม่ instantiate DMA-BUF export/payload ใช้ CPU-buffer fallback เดิม โดยไม่เปลี่ยน `Dmabuf.zig` และ Linux cleanup เพิ่ม platform-payload/memory-cleanup test; targeted check ผ่านเวลา 11:46:49 (`76/76 tests passed`, exit 0) กำลังรอ full-core ไม่ filter และ VT regression ยังไม่ประกาศว่า compatibility ทั้งหมดหรือแอป Windows พร้อมใช้

เวลา 11:59:52: full-core ไม่ filter ผ่านแล้ว (`3917/3978 tests passed`, skipped 61, exit 0) หลัง patch 2 ไฟล์ ส่วน VT regression ก่อนหน้ามี runner timeout จึงยังไม่ปิดเฟส 1 เริ่ม retry VT full suite แบบ `-j1` หลัง full-core จบโดยไม่ปิดเทสต์ ดู WIN-TEST-003 และผล retry ในเอกสาร validation

เวลา 12:14:08: VT retry ผ่าน (`6722/6786 tests passed`, skipped 64, exit 0) ตรงกับผลรวม baseline เดิมทั้ง 2 runners และ library build ผ่าน 48/48 steps; format/diff checks ผ่าน จึงปิดเฟส 0/1 ตามขอบเขต baseline พร้อม compatibility patch ที่อนุมัติแล้ว เก็บ runner timeout รอบก่อนไว้เป็น follow-up ที่ยังไม่ทราบ root cause ยังไม่มี runtime Win32 หรือผล Linux/GPU/IME และยังไม่ commit/push

เฟส 2 หลังผู้ใช้สั่งดำเนินการเวลา 12:31: จัดทำ `docs/windows-integration.md` กับ `docs/reference-notes.md` จาก source/เอกสาร MicrosoftและKhronosครบหัวข้อที่กำหนด เสนอ WGL context adapter+CPU DIB โดยแยก hidden context hostจากvisible HWND ไม่ยัด WGLเข้า EGL type; ยังไม่ implementหรือเลือก dependencyเพิ่ม รอยืนยันชื่อชั่วคราว `localterm-dev` ก่อนเฟส3 และยืนยันทิศทาง graphicsก่อนเฟส4 ดู open questions/gatesในเอกสาร

เวลา12:46ผู้ใช้ยืนยันชื่อ `localterm-dev` และทิศทาง WGL+CPU DIBแล้ว เริ่มเฟส3A: เพิ่ม opt-in target `windows-window`/`run-windows-window` ใน build.zig พร้อมหน้าต่างZigเดี่ยวและresource/manifestของเรา ไม่สร้างCoreSurface/renderer/PTY ไม่แก้default runtime selection ผลบิลด์ผ่านและnative lifecycle smoke20รอบหลังwarmupผ่าน (resize/minimize/restore/close, resource countsไม่เพิ่ม, syntheticDPIเท่านั้น) กำลังตรวจartifactสุดท้ายและบันทึกหลักฐาน ยังไม่ประกาศเฟส3B/runtime integrationครบ

เวลา12:56:59 finalartifactเฟส3Aผ่าน: ProductName/OriginalFilenameอ่านตรงชื่อเรา, manifestPerMonitorV2/asInvokerextractยืนยันแล้ว; smokeexit0หลัง20รอบ+warmup handles96→96,GDI2→2,USER1→1 พร้อมnegativeCLIcasesexit1ตามคาด; VTcompile43/43stepsและcoretargeted76/76testsผ่าน ไม่มีfullsuiteใหม่หลังwindow-onlypatch เฟส3Aผ่านตามขอบเขต แต่เฟส3Bยังต้องต่อruntime enum/App/Surfaceจริง ไม่ใช้prototypeมาแทนการรับรองคอร์

แก้ไขยอด VT ที่รายงานตอนแรก: 3,596 passed/32 skipped เป็นเพียง runner หนึ่ง ผลรวมเดิมจริงคือ 6,722 passed/64 skipped จาก 2 runners รายละเอียดอยู่ในเอกสาร validation

อัปเดต16:13 GMT+7: เฟส3Bต่อ runtime/CoreSurface/mailbox จริงแล้ว และ4A/4Bแสดง output/ANSIสี/ไทย/emojiผ่าน WGL→CPU DIB ได้ Full-core หลังpipe/EOFpatchผ่าน3920/3981(61skip); input KeyEvent ไปกลับ PowerShellผ่านรวมWM_CHAR repeat=2,ไทย combining vowels,surrogate pairและEnter เพิ่มIMM preedit/candidate adapterกับpure geometry2tests และCF_UNICODETEXT permission/multiline policyกับpure5testsแล้ว แต่ยังไม่รับรอง native IME/clipboard หรือ human typography

4Dพบและแก้ original CreateProcessW hThread/hProcessรั่ว2/session (targeted ownership76pass), และ burst-closeค้างจาก Windows reader cancellation race; หลังแก้ IO-before-renderer shutdown, sticky quit checkทุกreadและCancelSynchronousIo retry ระหว่างjoin รอบruntime-build-21ผ่าน123/123 และburst/exit/inputE2Eผ่านทั้งหมด ไม่มีtimeout/ownedorphans ส่วน strict real-surface21session gateยังfailedที่handle233→234,threads6→7; threadใหม่มาจากAMDdriver hookแต่handleยังอยู่ระหว่าง attribution ไม่เพิ่มthreshold/ไม่เปลี่ยนdriver setting ยังไม่ปิดเฟส4/ไม่เลื่อนเป็นdefaultterminalและยังไม่commit/push

คำขอportableเวลา15:16เพิ่มเป็นเฟส6ด้านล่างแล้ว เป็นแผนZIP/config-data isolation/update-rollback/clean-machine validation ไม่ใช่portable implementationหรือrelease artifactที่ตรวจผ่าน

อัปเดต16:39 GMT+7: full-core หลัง Command handle/shutdown/cancellation patches ผ่าน **3922/3983 tests (61 skipped),89/89steps**; native artifactล่าสุดทวนburstสองรอบ/exit/input+repeat/missing-shell/windowผ่านครบ และกำลังรันVTต่อแบบไม่ซ้อนcore Snapshotจับคู่ retained handleกับAMDhookได้แล้ว แต่ยังมีNTDLL worker handleและnetdelta233→234จึงไม่ปิดstrictlifecycle gate ยังเหลือperformance/IME/clipboard/human acceptanceตามเดิม

อัปเดต17:01 GMT+7: VT regression ผ่าน **6722/6786 tests,64 skipped,45/45steps** ตรงbaseline ไม่ซ้อนfull-core จึงปิดรอบregressionหลังshutdownpatchได้ เริ่มแยกวัด1080pWGLreadback→RGBA/BGRAconversion→memory-DCDIBเป็นcomponentcostเท่านั้น ไม่ใช้แทนwhole-appFPS,window/compositorlatencyหรือCPU/memoryของshell workload และไม่เพิ่มidle redrawเพื่อทำตัวเลขให้ดีขึ้น

อัปเดต17:23 GMT+7: 1080pcomponentbenchmarkReleaseSafeรวมmean5.175ms/p95 6.508ms; exact-clientwholehostprofileและburst/exit/input/startup/windowทวนผ่านบนReleaseSafeartifactล่าสุด ได้observedparentCPU25.82%ของหนึ่งcore,peakworking-set~204MiB แต่present25frames/15sจึงไม่รับรอง60FPS กำลังแยกตรวจframeจริง/wakeup/dirty semantics ส่วนstrictlifecycleReleaseSafeยัง233→234handles,6→7threadsเหมือนDebug ไม่เปลี่ยนเกณฑ์หรือปิดdriver feature คู่มือhumanpreviewอยู่docs/windows-preview.md ยังไม่มีhumanacceptance/ยังไม่ปิดเฟส4

อัปเดต18:06 GMT+7: พิสูจน์IOCPAsyncvalue-copy lostwakeและแก้sharedborrowedinstanceแล้ว ตามด้วยnativewakecoalescing/latest-frameconsume/input-paint-timerfairness ไม่มีidleredrawtimerใหม่ Burst1080pสองรอบและpacedผ่านพร้อมautoclose~15.4s,window/input/exit/startup/burstcloseผ่านครบ **full-coreหลังแก้3923/3984pass,61skip,89/89steps** ผลVTล่าสุด6722pass/64skipยังเป็นรอบ17:01 ไม่อ้างรันใหม่ กำลังทวนstrictlifecycleartifactล่าสุด;ยังเหลือhumanIME/clipboard/physicalDPIและไม่ปิดเฟส4หรือpromotedefaultterminal

อัปเดต18:08 GMT+7: strictlifecycleartifact28ยังfailed233→234handles,6→7threads(GDI/USERคงที่)หลัง21sessions ไม่timeout/ไม่เหลือownedorphans จึงคงWIN-RUNTIME-004 ไม่อนุมัติข้อยกเว้นdriverstateเอง ขั้นhumanpreviewมีwrapper `tools/windows/preview.ps1` (เปิดด้วยมือเท่านั้น) และคู่มือตรวจไทย/IME/clipboard/DPIในdocs/windows-preview.md;sourceยังไม่commit/push,portableยังเป็นแผนเฟส6

## คำตัดสิน

ซอร์สที่เข้าทรีของเรามาจาก [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) ที่คอมมิตซึ่งบันทึก SHA ไว้เท่านั้น งาน Windows ที่ Ghostty ยังไม่มี เราเขียนเอง

[Noctty](https://github.com/amanthanvi/noctty) เป็นตัวอย่างให้อ่าน เพื่อรู้ว่าแอป Win32 ต้องแก้ปัญหาใดบ้างและเรียก API ใดของ Windows ห้าม copy โค้ดจาก Noctty เข้าทรี เมื่อชี้ไม่ได้ว่าบรรทัดนั้นมาจากไฟล์ใด คอมมิตใด ของ Ghostty

บิลด์ใช้ `build.zig` ของ Ghostty ในคอมมิตที่ปัก ถ้าขั้นตอนที่ต้องการยังไม่มีในไฟล์นั้น ให้เขียนเพิ่มเอง ห้ามยก `build.zig`, สคริปต์ดาวน์โหลด หรือสคริปต์แพ็กเกจของ Noctty มาใช้

ทางนี้ช้ากว่าการรับฟอร์ก Noctty ทั้งก้อน แอปใช้ได้ช้ากว่า เพราะ Ghostty บน `main` ยังไม่มี runtime ของแอป Windows ใน `src/apprt.zig` มีแค่ `none` กับ `gtk` สิ่งที่ได้แทนคือทุกไฟล์ในทรีมีที่มาที่บันทึกได้

## กฎที่มาของโค้ด

ทุกไฟล์ที่ commit ในรีโปนี้ต้องเข้าได้ข้อใดข้อหนึ่ง

1. มาจาก `ghostty-org/ghostty` ที่ SHA ซึ่งบันทึกใน `docs/sources.md` พร้อม path เดิม
2. เราเขียนเองในรีโปนี้ โดยคอมมิตบอกว่าเขียนจากเอกสารใด เช่น เอกสาร Win32 ของ Microsoft หรือเอกสาร Zig

ห้ามนำเข้าโค้ดในกรณีเหล่านี้

- Copy จาก Noctty, Wintty, GhosttyWin32, polter หรือฟอร์กอื่น ทั้งไฟล์หรือบางฟังก์ชัน เมื่อไฟล์นั้นปนโค้ด Ghostty กับโค้ดที่ฟอร์กเขียนเอง จนชี้ที่มาทีละบรรทัดไม่ได้
- Copy จาก pull request ที่ Ghostty ไม่ได้ merge รวม [#12167](https://github.com/ghostty-org/ghostty/pull/12167)
- Copy สคริปต์บิลด์ ธง `-Demit-exe` ขั้นตอนดาวน์โหลด ConPTY ตัวติดตั้ง หรือตัวอัปเดต ของ Noctty
- วางไฟล์จาก Noctty แล้วแก้ชื่อ แล้วถือว่าเป็นโค้ดที่เราเขียน

การอ่าน Noctty ทำได้ และจำกัดอยู่ที่นี้

- Clone ไว้ที่ `reference/noctty` ซึ่งถูก `gitignore` ไม่ถูก `zig build` อ้างถึง และไม่ถูก commit
- บันทึกสิ่งที่เรียนได้ลง `docs/reference-notes.md` เป็นชื่อ API, ลำดับงาน และลิงก์เอกสาร Microsoft หรือไฟล์ Ghostty
- โน้ตห้ามแปะตัวฟังก์ชันจาก Noctty ถ้าต้องยกตัวอย่างโค้ด ให้ยกจากเอกสาร Microsoft หรือจากไฟล์ Ghostty ที่ SHA ตรงกับ `docs/sources.md`

ก่อนเขียนไฟล์บิลด์หรือไฟล์ระบบ ให้ค้นในคอมมิต Ghostty ที่ปักก่อน ตามลำดับนี้

1. `build.zig`, `build.zig.zon`, `src/build/Config.zig`
2. `pkg/*/build.zig` โดยเฉพาะ `pkg/freetype/build.zig` ที่มีทางคอมไพล์บน Windows ด้วย MSVC อยู่แล้ว
3. `.github/workflows/test.yml` แยก job Windows จริงออกจาก job บนระบบอื่น: Windows มี `zig build test-lib-vt` และ `zig build -Demit-lib-vt`; คำสั่ง `zig build -Dapp-runtime=none test` อยู่ใน job `test` ที่ใช้ Nix ไม่ใช่หลักฐานว่า full suite ผ่าน Windows
4. `src/pty.zig`, `src/termio/**`, `src/font/backend.zig`, `src/renderer.zig`

ถ้าพบในคอมมิตนั้น ให้ใช้ไฟล์นั้นและบันทึก path กับ SHA ถ้าไม่พบ ให้เขียนเอง แล้วค่อยเปิด `reference/noctty` เพื่อดูว่าเขาเรียก API ชื่ออะไร จากนั้นไปอ่านเอกสารของ API นั้นแล้วลงมือเอง

## ฐาน Ghostty ที่มีอยู่และส่วนที่ใช้ต่อ

ใช้ checkout ที่มีอยู่ โดยปัก baseline ข้างต้นและตรวจที่มาจาก official Ghostty ในเฟส 1 ไม่ clone ทับ `src/` และไม่เลือกเวอร์ชัน Zig ตาม Noctty หรือคำว่า latest

เก็บทรีปัจจุบันเป็นฐานสำหรับตรวจสอบและใช้ส่วนต่อไปนี้ โดยสถานะ “มีโค้ด” ไม่เท่ากับ “ทำงานบนเครื่องนี้แล้ว”

| ส่วน | path ใน Ghostty | บทบาทบน Windows |
|---|---|---|
| ตัวแปล VT และสถานะจอ | `src/terminal/**`, `src/lib_vt.zig` | ใช้ได้ใน `libghostty-vt` ซึ่ง upstream รองรับ Windows |
| บิลด์ | `build.zig`, `build.zig.zon`, `src/build/**`, `pkg/**` | คำสั่งแรกคือเทสต์แบบไม่มีแอป |
| ฟอนต์ | `src/font/**` | ค่าเริ่มบน Windows คือ `freetype_windows` ตาม `src/font/backend.zig` |
| renderer | `src/renderer/**` | คอมไพล์ไทม์มี Metal กับ OpenGL บน Windows ใช้ OpenGL |
| input, config | `src/input/**`, `src/config/**` | ใช้ของ Ghostty |
| PTY และ process | `src/pty.zig`, `src/termio/Exec.zig`, `src/Command.zig` | มี WindowsPty, ConPTY และทางเปิด process ให้ตรวจใช้ต่อ |
| เทสต์ Windows | `.github/workflows/test.yml`, job `build-libghostty-vt-windows` | `zig build test-lib-vt`, `zig build -Demit-lib-vt` และตัวอย่าง C |
| เทสต์คอร์วงกว้าง | job `test` ที่ใช้ Nix | ทดลอง `zig build -Dapp-runtime=none test` บนเครื่องนี้แยกต่างหาก ยังไม่รับรองว่าผ่าน |

สิ่งที่ Ghostty ยังไม่มี และเป็นงานที่เราเขียนเอง

- runtime ของแอปใน `src/apprt.zig` ตอนนี้เลือกได้แค่ `none` กับ `gtk` สำหรับ exe
- หน้าต่าง Win32, แท็บ, สปลิต, เมนู, หน้าตั้งค่า
- การเชื่อม runtime ใหม่เข้ากับ Windows PTY และ termio ที่มีอยู่ รวมถึงพิสูจน์ spawn, I/O, resize และ cleanup; ไม่เริ่มเขียน ConPTY ใหม่ทั้งชุด
- การสร้างบริบท OpenGL บนหน้าต่าง Win32 แล้วส่งให้ renderer ของ Ghostty
- IME, clipboard และ DPI ในชั้นหน้าต่าง

GTK บน Windows ไม่ใช่ทางที่เราจะเดิน นี่เป็นการตัดสินใจของโปรเจกต์ว่าจะใช้ Win32 ไม่ใช่ข้อสรุปจากสถานะ discussion ที่ยังไม่ได้ตรวจรอบนี้ จึงไม่เปิด `-Dapp-runtime=gtk` เพื่อให้ได้หน้าต่างเร็ว

## Noctty ใช้ดูอะไร

อ่านเพื่อทำเช็คลิสต์ ไม่ได้เพื่อเอางานที่เขาทำเสร็จมาเป็นฐาน ข้อมูลรุ่น วันที่ ขนาดไฟล์ และฟีเจอร์ของ Noctty จากแผนเก่าถือว่ายังไม่ยืนยัน จนกว่าจะบันทึก URL, path, SHA และวันที่ตรวจจริง การอ่าน Noctty เป็นตัวเลือก ไม่ใช่ prerequisite ของการเริ่ม Win32 จากเอกสาร Microsoft

เช็คลิสต์สำหรับตรวจงาน โดยยังไม่ถือว่าเราหรือ Noctty ทำผ่านแล้ว

- หน้าต่างเปล่าที่รับคีย์บอร์ดได้
- เปิด `powershell.exe` ผ่าน ConPTY แล้วไบต์วิ่งเข้าตัวแปล VT ของ Ghostty
- วาดช่องตัวอักษรด้วย OpenGL ของ Ghostty บน HWND
- พิมพ์ไทยผ่าน IME
- วางจากคลิปบอร์ด
- เปิด WSL หนึ่งดิสโทร ถ้าเครื่องมี

รายการที่เขาทำเพิ่ม เช่น session restore, command palette, ตัวอัปเดต, ตัวติดตั้ง และ default terminal อยู่นอกช่วงแรก

## สถาปัตยกรรมเป้าหมาย

```text
แอป Win32 ที่เราเขียน
  หน้าต่าง, input, IME, clipboard
  ไฟล์ใหม่ใต้ src/apprt/ ที่เราเป็นผู้เขียน
        |
        v
คอร์ที่ดึงจาก Ghostty ที่ SHA เดิม
  src/terminal/**     ตัวแปล VT
  src/renderer/**     OpenGL
  src/font/**         freetype_windows
  src/config/**       คอนฟิก
  src/input/**        การเข้ารหัสคีย์
  src/termio/**       ใช้ทาง Windows ที่มีอยู่และตรวจจุดเชื่อม
  src/pty.zig        WindowsPty / ConPTY / resize / cleanup
  src/Command.zig    เปิด process และผูก pseudo console
```

เธรดอ่าน เขียน และวาดยังเป็นแบบ Ghostty เราไม่เขียนตัวแปล VT ใหม่

### ขอบเขตการเชื่อมต่อที่ต้องออกแบบก่อนลงมือ

| ชั้น | ใช้ของเดิม | งานที่ต้องออกแบบ/พิสูจน์ |
|---|---|---|
| Build/runtime | `build.zig`, `src/build/Config.zig`, `src/build/GhosttyExe.zig`, `src/apprt/runtime.zig`, `src/apprt.zig` | เพิ่ม runtime Win32 และ selection ให้ครบ ไม่ใช่แก้ `build.zig` จุดเดียว; ธงใหม่ยังไม่มีจนกว่าจะ implement |
| App/surface | `src/App.zig`, `src/Surface.zig`, `src/apprt/surface.zig`, runtime เดิมเป็นตัวอย่าง interface | App/Surface contract, callbacks, redraw/wakeup, focus, content scale, close, lifetime |
| Win32 | ไฟล์ใหม่ใต้ `src/apprt/` แยก window/input/graphics ตามหน้าที่ | HWND, message loop, UI thread, DPI awareness, client size, minimize/restore |
| Graphics | `src/renderer.zig`, `src/renderer/OpenGL.zig`, `src/renderer/Thread.zig`, `src/renderer/generic.zig` | WGL context และ extension loading, pixel format, GL version/limits ที่ renderer ใช้จริง, context ownership และ swap |
| PTY/process | `src/pty.zig:326` เป็นต้นไป, `src/termio/Exec.zig`, `src/Command.zig` | ตรวจเส้นทางเดิมตั้งแต่ spawn ถึง exit; `CreatePseudoConsole`, `ResizePseudoConsole`, `ClosePseudoConsole` มีแล้ว ต้องไม่สร้าง owner ซ้ำ |
| Input | `src/input/**` และ input API ของ Surface | แยก key event กับ text commit, UTF-16 เป็น UTF-8, repeat/modifiers, IME และไม่ส่งข้อความซ้ำ |
| Font/config | `src/font/**`, `src/config/**` | ใช้ `freetype_windows`; ตรวจ fallback ไทย/emoji, config defaults และ path ของชื่อแอปใหม่ |

ต้องบันทึก ownership ของ HWND, HDC/HGLRC, surface, thread, timer/event, pipe, HPCON, process และ memory allocator ว่าใครสร้าง ใครปิด และปิดลำดับใด ไม่เรียก OpenGL จากเธรดที่ไม่มี current context และไม่แก้สถานะ terminal ข้ามเธรดโดยข้ามกลไกของคอร์

ข้อจำกัดที่ยืนยันเพิ่มจากการทำ compatibility: `OpenGL.zig` ปัจจุบันใช้ EGL context/device โดยตรง และกำหนด OpenGL ขั้นต่ำ 4.3 จึงห้ามสมมติว่า WGL context ที่สร้างเองจะเสียบกับ renderer ได้ทันที ในเฟส 2 ต้องตรวจ `opengl/Device.zig` และ presentation contracts แล้วเสนอทางเชื่อม WGL หรือ EGL บน Windows พร้อม trade-off/driver requirements ให้ชัดก่อน implement ชื่อเฟส 4A ด้านล่างเป็นเป้าหมาย graphics integration ไม่ใช่ข้อยืนยันว่าเลือก WGL ได้โดยไม่แก้ adapter

## ลิขสิทธิ์และชื่อ

Ghostty เป็น MIT ต้องคง `LICENSE` และข้อความลิขสิทธิ์ของ Mitchell Hashimoto กับผู้ร่วม Ghostty ไว้กับไฟล์ที่ดึงมา

ตามนโยบายโปรเจกต์นี้ ไม่ใช้ชื่อและไอคอน Ghostty เป็นแบรนด์แอปของเรา ไม่ใช่ข้อวินิจฉัยทางกฎหมายจาก MIT ชื่อผลิตภัณฑ์ยังไม่กำหนด ก่อนสร้าง exe ต้องให้ผู้ใช้ยืนยันชื่อชั่วคราวที่ไม่มีคำว่า ghostty หรือ noctty และไม่สื่อว่าเป็นแอปทางการ โฟลเดอร์คอนฟิกอยู่ใต้ `%LOCALAPPDATA%` ของชื่อนั้น

ตรวจ branding มากกว่าชื่อไฟล์: `src/build/GhosttyExe.zig` ตั้งชื่อ executable เป็น `ghostty` และใช้ `dist/windows/ghostty.rc` ซึ่งยังอ้าง `ghostty.ico`, `OriginalFilename` และ `ProductName` เดิม ต้องปรับเฉพาะ artifact ของเราและเก็บ attribution แยกจาก branding ไม่ลบข้อความลิขสิทธิ์หรือเปลี่ยนชื่อ API ของ upstream ทั้งทรี

Noctty ก็เป็น MIT แต่การไม่ copy โค้ดเขาเป็นกฎของโปรเจกต์นี้ แม้สัญญาอนุญาตจะอนุญาตให้ copy ได้ การ copy ไฟล์ที่ปนที่มาจะทำให้เราชี้ไม่ได้ว่าบรรทัดใดเป็นของ Ghostty

## เครื่องมือ

| เครื่องมือ | สถานะบนเครื่องนี้เมื่อ 16 ตุลาคม 2026 | รุ่นที่ใช้ |
|---|---|---|
| Git for Windows | มีแล้ว 2.52.0 | รุ่นนี้ใช้ได้ |
| Zig | ยังไม่มีใน `PATH` | รุ่นที่ตรง `minimum_zig_version` ของ SHA ที่ clone ณ วันที่สำรวจ `main` ระบุ `0.16.0` อย่าติดตั้ง 0.15.2 เพราะนั่นเป็นรุ่นของ Noctty |
| Visual Studio 2022 | พบ Build Tools และ Community รุ่น 17.14.24; Community มี component `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` และ `cl.exe` รุ่นโฟลเดอร์ 14.44.35207 | ใช้ Developer PowerShell x64; ตรวจ Windows SDK, linker และ resource compiler ก่อนตัดสินใจติดตั้งเพิ่ม |

หน้าดาวน์โหลด Zig: https://ziglang.org/download/ เลือกไฟล์ Windows x86_64 ของรุ่นที่ `build.zig.zon` ระบุ อย่าใช้ `winget install zig` หรือ `scoop install zig` ถ้าคำสั่งนั้นได้รุ่นคนละเลขกับไฟล์นี้

บิลด์ดึง dependency ตาม URL/แฮชใน `build.zig.zon` ครั้งแรกจึงต้องมีเน็ตเวิร์ก ไม่เปลี่ยนแฮชเพื่อข้าม integrity check และไม่เพิ่มตัวดาวน์โหลด ConPTY จากฟอร์ก ใช้ binding และ kernel32 ของทางเดิมก่อน เครื่อง build 26200 ใหม่กว่า Windows 10 1809 ที่มี ConPTY แต่ minimum Windows version ของผลิตภัณฑ์ยังไม่ประกาศ จนกว่าจะทดสอบจริง

ยังไม่ได้ตรวจว่า GPU ของเครื่องนี้ทำ OpenGL ได้หรือไม่ และการบิลด์ Ghostty ผ่านบนเครื่องนี้หรือไม่

## ระยะงาน

แต่ละเฟสจบเมื่อเกณฑ์ผ่าน

### เฟส 0 — เครื่องมือ

1. ใช้ VS 2022 Community ที่มีอยู่ก่อน ไม่ติดตั้ง VS ซ้ำจากข้อมูลแผนเก่า
2. เปิด Developer PowerShell x64 for VS 2022 แล้วตรวจ `Get-Command cl`, `Get-Command link`, `Get-Command rc`; ตรวจ SDK path ของ session ด้วย
3. ตรวจว่ามี Zig นอก PATH หรือไม่ก่อนดาวน์โหลด ถ้าต้องติดตั้งให้ขออนุมัติ แล้วใช้รุ่น 0.16.0 ตาม baseline พร้อมตรวจ checksum จากแหล่งทางการ
4. ตรวจ `zig version`, บันทึก executable path, MSVC/SDK versions และสถาปัตยกรรมจริงลง build log; ถ้า Zig ปฏิเสธรุ่น ให้หยุดตรวจข้อกำหนดในซอร์ส ไม่เปลี่ยน baseline เอง

เกณฑ์ผ่าน: `zig version` ตรงไฟล์ `build.zig.zon` และ `cl` ใช้ได้ในเชลล์ที่จะบิลด์

### เฟส 1 — ยืนยันฐานซอร์สและบิลด์โดยไม่เปลี่ยนคอร์

ทำงานใน `d:\works\ghostty-windows`

```powershell
Set-Location D:\works\ghostty-windows
git status --short
git rev-parse HEAD
git remote -v
```

ห้าม clone ลง `src/`, ห้าม `cd src` เพื่อบิลด์ และห้าม rename `origin` เพราะตอนนี้เป็นรีโปของผู้ใช้แล้ว ก่อนแก้ implementation ให้สร้าง branch จาก `main` ใน checkout หลักหลังตรวจไฟล์ค้าง ไม่สร้าง worktree เพิ่มโดยไม่จำเป็น ไม่ reset/clean งานเดิม และไม่ commit/push เว้นแต่ผู้ใช้สั่ง

หลังได้รับอนุมัติการตั้ง remote/เข้าถึงเครือข่าย และตรวจว่ายังไม่มีชื่อ `upstream` จึงใช้:

```powershell
git remote add upstream https://github.com/ghostty-org/ghostty.git
git remote set-url --push upstream DISABLED
git fetch upstream
```

ตรวจ baseline SHA ว่าอยู่ในประวัติที่ fetch จาก official remote และเทียบ tracked tree หากมี commit เฉพาะฟอร์ก ต้องแยก upstream base, commit ของเรา และ provenance ของ diff ห้ามรับรองทั้งทรีเพียงเพราะ `git rev-parse HEAD` แสดง SHA ได้ จดผลใน `docs/sources.md` พร้อม repository, baseline/upstream SHA, path เดิม, ไฟล์ที่แก้, วันที่และวิธีตรวจ โดยไม่สร้าง network operation ระหว่างการแก้แผนครั้งนี้

เริ่มด้วยคำสั่งจาก job Windows `build-libghostty-vt-windows` ที่ตรวจพบจริง:

```powershell
zig build test-lib-vt
zig build -Demit-lib-vt
```

จากนั้น build ตัวอย่าง `example/c-vt-static` และ `example/c-vt-effects` ตาม workflow เดิม และทดสอบการโหลด DLL ตามขั้นตอนใน job นั้น ไม่เดา DLL path หรือถือว่า build ผ่านเท่ากับ runtime ผ่าน

ตรวจความพร้อมของคอร์วงกว้างแยกด้วยคำสั่งต่อไปนี้ ซึ่งพบใน job Nix ไม่ใช่ Windows job:

```powershell
zig build -Dapp-runtime=none test
```

เกณฑ์ผ่านส่วน Windows VT: unit tests, library build และตัวอย่าง linking ที่กำหนดผ่านบนเครื่องนี้ พร้อมบันทึก command, working directory, exit code, passed/skipped/failed counts และ log ส่วน full-core ต้องรายงานผลแยก ไม่ใช้ผล VT แทนการรับรอง renderer หรือ GUI

ถ้า full-core ล้มเพราะเครื่องมือให้แก้สภาพเครื่องก่อน ถ้าล้มในซอร์สให้บันทึกชื่อเทสต์/compile error และหยุดตัดสินใจขอบเขต patch ก่อนเฟส 3 ห้ามปิดเทสต์หรือใช้แพตช์ Noctty เพื่อฝืนผ่าน ต้องมี baseline failure list ที่อนุมัติก่อนเดินต่อ และไม่เพิ่ม regression จากรายการนั้น

ผลของเฟสนี้คือมีหลักฐานผล VT build/test/linking และรายการผล full-core ที่แยกชัดเจน ยังไม่มีหน้าต่าง และยังไม่รับรอง GUI/renderer/PTY runtime

### เฟส 2 — ออกแบบ integration จากซอร์สและเอกสาร

สร้าง `docs/windows-integration.md` ระบุ contract ตามตารางสถาปัตยกรรมข้างต้น, ownership/thread model, startup/shutdown, error path และรายการไฟล์ที่จะเปลี่ยน ตรวจ WindowsPty และ Command เดิมก่อนสรุปว่าขาดอะไร และเลือกชื่อชั่วคราวกับผู้ใช้ก่อนเฟส 3

การอ่าน Noctty เป็นตัวเลือก ถ้าต้อง clone ต้องเพิ่ม `/reference/` ใน `.gitignore` **ก่อน** clone และขออนุมัติ network operation ตรวจว่าไม่มี nested repository เดิมอยู่แล้ว:

```powershell
git clone --depth 1 https://github.com/amanthanvi/noctty.git reference/noctty
```

ตรวจด้วย `git check-ignore reference/noctty` และตรวจ build graph ว่าไม่อ้าง reference; การไม่มีไฟล์ใน `git status` อย่างเดียวไม่พิสูจน์ว่า build ไม่ใช้มัน บันทึก SHA ของ reference ที่อ่านไว้ด้วย

อ่านแล้วเขียน `docs/reference-notes.md` ให้ครบห้าข้อนี้ โดยแต่ละข้อมีลิงก์เอกสาร Microsoft หรือ path ใน Ghostty ที่ SHA ของเรา

- สร้าง HWND และลูปข้อความ
- สร้างบริบท OpenGL บน HWND
- เปิด ConPTY และผูก stdin stdout ของเชลล์
- รับคีย์บอร์ดกับ IME แล้วส่งเป็นไบต์ที่คอร์ Ghostty รับอยู่แล้ว
- จุดใน Ghostty ที่แอปต้องเรียก เพื่อสร้าง surface และส่งขนาดจอ เริ่มค้นที่ `src/apprt.zig`, `src/apprt/surface.zig`, `src/renderer.zig`

เกณฑ์ผ่าน: integration design และโน้ตห้าข้อครบพร้อม path/API evidence, ระบุของเดิม/ของใหม่ชัดเจน, ไม่มี dependency จาก reference ใน build; ถ้าไม่อ่าน Noctty ให้ระบุว่าไม่ได้ใช้และอ้าง Microsoft/Ghostty แทน ไม่ต้อง clone เพื่อให้ผ่านเฟส

ผลปัจจุบัน: design/research deliverablesครบตาม `docs/windows-integration.md` และ `docs/reference-notes.md`; ชื่อและ graphics directionเป็นข้อเสนอรอผู้ใช้ยืนยัน ไม่ใช่การอนุมัติหรือผลGPU/native acceptance ไม่มีการแก้sourceเพิ่มนอก compatibility diffเดิม2ไฟล์ในเฟสนี้

### เฟส 3 — ต่อบิลด์เองให้ได้หน้าต่างเปล่า

เพิ่ม runtime Win32 ใน enum/switch และ implementation ของ App/Surface ให้สอดคล้องกับคอร์ ตรวจ `build.zig`, `src/build/Config.zig`, `src/build/GhosttyExe.zig` และ resource/manifest ไม่ถือว่าเพิ่มไฟล์หน้าต่างอย่างเดียวแล้วคอร์จะเชื่อมได้เอง ทุก diff ต้องระบุเหตุผลและ baseline SHA

คำสั่ง runtime ใหม่จะกำหนดเมื่อ implement และตรวจ `zig build --help` แล้วเท่านั้น ตัวเลือก `-Dapp-runtime=win32` ยังใช้ไม่ได้ในซอร์สปัจจุบัน ห้ามเขียนเป็นคำสั่งพร้อมรันหรือยกธงจากฟอร์ก ส่วน `emit-exe` ของต้นทางให้ตรวจ `Config.zig` ตาม SHA ไม่ถือว่าชื่อธงทุกตัวเป็นของ Noctty

โปรแกรมแรกสร้างหน้าต่าง Win32 ว่าง ๆ แล้วปิดได้ ยังไม่ต้องวาดเทอร์มินัล

เกณฑ์ผ่าน: exe ของเราเปิด/ปิดหน้าต่างซ้ำได้, resize/minimize/restore ไม่ค้าง, UI thread ไม่บล็อกกับ I/O, resource และชื่อไม่แสดงแบรนด์ทางการ, baseline tests ไม่มี regression และมีคำสั่ง build/run ที่ทำซ้ำได้ในเอกสาร ยังไม่ต้องเปิด shell

### เฟส 4 — เชลล์เส้นเดียว

ใช้ WindowsPty/termio/Command ของ baseline ก่อน เขียนเพิ่มเฉพาะจุดที่พิสูจน์ว่าขาด แบ่งทำตามลำดับ ไม่รวมทุกอย่างเป็นการทดสอบเดียว:

#### 4A — WGL, renderer และฟอนต์

ข้อกำหนดจาก designเฟส2: ทำ standalone context/FBO/readback spikeก่อนเปิดshell การเรียก production `CoreSurface.init` เริ่มrenderer/IO/PTYในflowเดียว จึงเริ่มreal surfaceเพียงครั้งเดียวที่รอยต่อ4A/4Bแล้วแยกตรวจgraphicsกับPTY ไม่สร้างdummy backendเพื่อแสร้งว่าterminal surfaceไม่เริ่มIO รุ่นแรกเสนอ CPU-frame/DIB presentation ไม่ถือว่า WGL direct window swapทำเสร็จแล้ว

- ตรวจ driver, GL version/extension และข้อกำหนดจาก renderer จริงก่อนเริ่มเชื่อม ไม่รับรองจากชื่อ GPU
- สร้าง context บน HWND, กำหนดผู้ถือ context และส่งงานตาม renderer thread เดิม
- วาดข้อความทดสอบผ่าน terminal/surface และ renderer จริง ตรวจ ASCII, ไทย, combining marks และ fallback ที่ฟอนต์รองรับ
- Resize/DPI change ต้องอัปเดต framebuffer pixels, content scale และ grid แยกหน่วยกัน; minimize ต้องไม่วาดขนาดศูนย์หรือ busy-loop
- ผ่านเมื่อวาดและ resize ได้ซ้ำโดยไม่มี GL error/ค้าง พร้อมบันทึก driver/GL capabilities; ถ้าไม่ผ่านให้หยุด ไม่เปลี่ยนเป็น DirectX หรือเขียน renderer ใหม่โดยอัตโนมัติ

#### 4B — PowerShell ผ่านเส้นทาง PTY เดิม

- เริ่มจาก `powershell.exe` ของระบบ ตรวจ path จริง; ไม่บังคับว่ามี `pwsh.exe`
- ตรวจ spawn, cwd, environment และ Unicode path; default ใน `Exec.zig` มีทาง `cmd.exe` จึงต้องกำหนด PowerShell อย่างตั้งใจ
- ต่อ output เข้าตัวแปล VT และ input ผ่าน encoder ของคอร์ ตรวจสี, cursor movement, scrollback และ output ปริมาณมากไม่ทำ UI ค้าง
- Resize ส่งจำนวนแถว/คอลัมน์ที่ถูกต้องถึง PTY; ตรวจอ่าน EOF, shell exit และ startup failure
- ผ่านเมื่อพิมพ์คำสั่ง, แสดงผล และ resize ได้โดยไม่เขียน PTY ซ้ำหรือข้าม synchronization เดิม

#### 4C — Input, IME และ clipboard

- ทดสอบ key down/up, modifiers, repeat, Enter/Backspace/arrows, Ctrl+C และ Ctrl+V ตามนโยบาย shortcut ที่บันทึกไว้
- แยก IME preedit กับ committed text, รองรับ UTF-16 surrogate pair, วาง candidate window ตามตำแหน่ง cursor และไม่ส่ง commit ซ้ำ
- ทดสอบพิมพ์ไทยอย่างน้อยหนึ่งคำที่มีสระ/วรรณยุกต์, เปลี่ยนภาษา, ยกเลิก composition และ paste ข้อความไทยหลายบรรทัด
- กำหนด multiline paste/bracketed paste อย่างชัดเจนก่อนเปิดใช้ clipboard ไม่ execute ข้อความพิเศษเงียบ ๆ
- ผ่านเมื่อ input ไม่หาย/ซ้ำและ shell ได้ไบต์ UTF-8 ตามที่คอร์คาด; ผลที่เห็นบนจอให้ผู้ใช้ยืนยัน ไม่รับรอง IME จาก unit test อย่างเดียว

#### 4D — Shutdown และ failure recovery

- บันทึกลำดับหยุด I/O, ยกเลิก pending operation, จบ/รอ process ตามนโยบาย, ปิด PTY, หยุด renderer และทำลาย window/context โดยเคารพ ownership จริง
- ไม่บล็อก message loop กับการปิด ConPTY หรือการรอเธรดที่ยังต้องให้ UI ระบาย output
- ทดสอบปิดขณะ shell idle/กำลังเขียน output, shell exit เอง, เปิด shell ไม่สำเร็จ และเปิด/ปิดซ้ำอย่างน้อย 20 รอบ
- ผ่านเมื่อไม่มี orphan shell ของ session, ไม่มี crash/deadlock และไม่มี handle/thread เพิ่มสะสมโดยไร้คำอธิบาย; process ลูกทดสอบต้องจบตามนโยบาย โดยไม่ฆ่า shell อื่นของผู้ใช้

เส้นทางยอมรับรวมหลัง 4A–4D ใช้ PowerShell เส้นเดียว:

- เปิด PowerShell
- พิมพ์คำสั่งแล้วเห็นผลบนหน้าต่าง
- พิมพ์ไทยผ่าน IME ได้อย่างน้อยหนึ่งคำ
- ปิดหน้าต่างแล้วโปรเซสเชลล์จบตาม

เกณฑ์ผ่าน: สี่ข้อนี้และเกณฑ์ 4A–4D ผ่านบนเครื่องนี้ โดยไม่มีไฟล์ที่ copy จาก `reference/noctty`, baseline ไม่มี regression และผู้ใช้ยืนยันภาพ/IME ที่ทดสอบจริง

แท็บ, สปลิต, หน้าตั้งค่า, ตัวติดตั้ง และตัวอัปเดตยังไม่ทำในเฟสนี้ การอนุมัติแผนไม่เท่ากับอนุมัติ human acceptance ของแอป

### เฟส 5 — ใช้เอง แล้วค่อยเพิ่มทีละอย่าง

ใช้เส้น PowerShell นี้กับงานจริงอย่างน้อยสองสัปดาห์ บันทึกตัวบล็อกลง `docs/gaps.md` แต่ละข้อมีวิธีทำให้เกิดซ้ำ

ลำดับหลังเฟส 4 ถ้าข้อนั้นเกิดจริง

1. เชลล์ไม่เปิด หรือหน้าต่างค้าง
2. IME, clipboard, คีย์ลัดที่ใช้พิมพ์งาน
3. WSL ดิสโทรที่เครื่องนี้มี
4. ฟอนต์และภาพกระตุก
5. แท็บหรือสปลิต

ยังไม่ทำจนกว่าข้อ 1 ถึง 3 จะเงียบ: DirectX ทั้งก้อน, WinUI, C#, ตัวติดตั้ง, Authenticode, การเป็น default terminal

ทุกการเพิ่มต้องบอกที่มาตามกฎด้านบน รัน targeted tests ของส่วนที่แตะก่อน แล้วรันชุด baseline ที่ผ่านในเฟส 1 รวม full-core ตามขอบเขตที่ตกลง ผลต้องไม่แย่ลงจากรายการ failure ที่อนุมัติ

เกณฑ์ผ่านเฟส 5: มีบันทึกการใช้จริงอย่างน้อยสองสัปดาห์ ไม่อ้างเพียงเวลาที่ผ่านไป, ปัญหาบล็อกงานทุกข้อมีสถานะ/วิธีทำซ้ำ, ผู้ใช้ยอมรับ PowerShell/IME/clipboard ก่อนขยายฟีเจอร์ WSL ให้ทดสอบเฉพาะดิสโทรที่พบจริง และระบุ not applicable ถ้าไม่มี ไม่ติดตั้งดิสโทรเอง

### เฟส 6 — Portable app สำหรับ Windows

เพิ่มตามคำขอผู้ใช้วันที่16ตุลาคม2026 เวลา15:16 GMT+7: **วางแผนไว้ก่อน ยังไม่ implement หรือรับรอง portable ใน artifact ปัจจุบัน** ให้ทำช่วงท้ายหลัง4A–4Dผ่านและจัดการ blocker การใช้จริงช่วงเฟส5ก่อน ไม่แทรกงานแพ็กเกจจนทำให้ shell/input/shutdown ค้าง การทำ ZIP ทดลองไม่แทนเกณฑ์ใช้จริงสองสัปดาห์หรือ human acceptance ของเฟส5

#### เป้าหมายและรูปแบบแพ็กเกจ

- แจกเป็น ZIP แยกตาม architecture ที่บิลด์และทดสอบจริง เริ่ม Windows x64 ไม่อ้างรองรับ ARM64/x86 จากการแพ็ก ZIP
- กำหนด CPU baseline สำหรับ artifact แจกโดยชัดเจน ไม่ใช้ build แบบ `-mcpu native` ของเครื่องพัฒนาเป็น portable release โดยอัตโนมัติ ตรวจ SIMD/runtime dispatch และ dependency ด้วย ทดสอบบน CPU/feature set ต่ำสุดที่ประกาศเพื่อไม่ให้เกิด illegal instruction บนเครื่องอื่น
- แตกไฟล์แล้วเปิด executable ของเราได้ด้วยสิทธิ์ผู้ใช้ปกติ ไม่ต้องติดตั้ง Zig, Visual Studio, Windows SDK หรือตัวแอปลงระบบ ไม่ต้องเปิด Developer Shell
- มี executable, resources ที่ runtime ใช้จริง, dependency ที่จำเป็นและมีสิทธิ์แจก, LICENSE/third-party notices, คู่มือไทย และ manifest รายการไฟล์/เวอร์ชัน/SHA256 ไม่ใส่ซอร์ส/cache ของ build, logs ทดสอบ, config ของผู้พัฒนา หรือ secrets
- ตรวจ dependency/imports จาก release artifact บนเครื่องสะอาดก่อนเลือกรูปแบบ CRT/DLL ไม่ถือว่า exe เดี่ยวพอเพราะรันผ่านบนเครื่องที่ติดตั้ง VS; ไม่ copy DLL ระบบ, OpenGL driver, PowerShell หรือฟอนต์ Windows มาแจก หากต้องเพิ่มฟอนต์ bundled ต้องตรวจ license และขนาดแพ็กเกจก่อน
- Portable ไม่เท่ากับทำงานได้ทุกเครื่อง: บันทึก Windows minimum/ConPTY, GPU/OpenGL4.3 และ driver ตาม gate ที่พิสูจน์จริง CPU DIB ยังใช้ OpenGL renderer ไม่ใช่ software-renderer fallback

#### Config/data isolation และการย้ายโฟลเดอร์

- สำหรับ portable ทั้งแอปยังต้องออกแบบ marker/explicit option และ precedence ให้ครบ ยึดตำแหน่ง executable ไม่ใช่ current working directory; **ข้อยกเว้นที่เริ่ม implement แล้ว18ตุลาคม2026:** image-paste cache เลือกจาก directory `portable-data` ข้างexeและsnapshotตอนสร้างsurface เก็บที่ `portable-data/cache/clipboard` ไม่มีCLIportableflag และไม่ใช่การรับรองconfig/resource/log isolationทั้งแอป ดู `docs/windows-image-paste.md`
- โครงเป้าหมาย เช่น `localterm-dev.exe`, `resources/`, `portable-data/config/`, `portable-data/data/`, `portable-data/cache/`, `portable-data/logs/`; ตรวจ resource lookup, path resolver และฟีเจอร์ที่เขียนไฟล์จริงก่อนยืนยัน layout
- ใน portable mode ให้ข้อมูลที่แอปเป็นเจ้าของอยู่ใต้ `portable-data/` ไม่อ่าน/ทับ config Ghostty เดิมหรือ config ของแอปแบบติดตั้งโดยเงียบ ๆ โหมดปกติยังแยกใช้ per-user location ของเราอย่างชัดเจน
- หากพื้นที่ข้าง executable เขียนไม่ได้/ดิสก์เต็ม/ไดรฟ์หลุด ต้องแจ้งข้อผิดพลาดหรือเสนอ read-only mode ที่ระบุชัด ไม่ fallback ไปเขียน AppData โดยไม่บอก ไม่ขอ admin เพื่อแก้ permission อัตโนมัติ
- ใช้ relative path กับข้อมูลภายในแพ็กเกจ ไม่ฝัง drive letter/checkout path; ทดสอบย้ายและเปลี่ยนชื่อโฟลเดอร์ เปลี่ยน drive letter, path ไทย/ช่องว่าง, เปิดจาก cwd อื่น และรันโหมดปกติกับ portable พร้อมกันโดยไม่ชน config/cache/session identity
- ไม่ทำ PATH modification, file association, startup registration, registry install keys หรือ default-terminal registration การรองรับ installer/default terminal เป็นคนละขอบเขต
- ขอบเขต isolation คือไฟล์ที่แอปควบคุม ไม่รับรองว่า Windows/GPU driver/เชลล์/โปรแกรมลูกจะไม่เขียนภายนอกโฟลเดอร์เลย ต้องระบุข้อยกเว้น เช่น OS temp, shader cache และ shell history ไม่ย้าย/ปิด history หรือเปลี่ยน profile ของผู้ใช้โดยเงียบ ๆ

#### Update, rollback และข้อมูลส่วนตัว

- เริ่มจากอัปเดตด้วยมือเมื่อปิดแอปและ process ลูกของ session แล้ว เปลี่ยนเฉพาะ executable/resources ที่อยู่ใน manifest รักษา `portable-data/` ไม่ล้างทั้งโฟลเดอร์หรือ overwrite config ด้วยค่าเริ่มต้น
- สำรอง config ก่อน migration, ระบุ schema/version และวิธีย้อนกลับหาก downgrade อ่านข้อมูลไม่ได้ ไม่อ้างว่าเปลี่ยน exe กลับแล้ว rollback ข้อมูลได้เสมอ
- ไม่เพิ่ม auto-updater, network download หรือ telemetry ในงาน portable นี้ การส่งโฟลเดอร์/ZIP ต่ออาจพาข้อมูลส่วนตัวติดไป ต้องมีคู่มือแยก package สะอาดจาก user data และไม่รวม user data ใน release ZIP

#### Validation และเกณฑ์รับงาน

1. ตรวจ release build/dependencies/resources/license inventory และ checksum ของ ZIP; รันทดสอบ baseline ที่เกี่ยวข้องโดยไม่ลด tests หรือซ่อน skipped
2. ทดสอบแตกและเปิดจาก fresh user/VM ที่ไม่มี dev toolchain พร้อม PowerShell/output/input/ไทย/IME/clipboard/resize/shutdown ตามเฟส4 ใช้ clipboard/IME จริงเฉพาะการทดสอบที่ผู้ใช้รับทราบ ไม่เขียนทับ clipboard หรือ profile เพื่อทดสอบแพ็กเกจโดยอัตโนมัติ
3. ตรวจ app-owned writes ด้วยรายการ path/file-access evidence ไม่อ้าง isolation เพียงเพราะเห็นโฟลเดอร์ `portable-data/`; ทดสอบ read-only, disk-full และ resource หาย แล้วไม่เกิด silent fallback/data loss
4. ทดสอบย้ายโฟลเดอร์และ drive, upgrade/downgrade/rollback, config เดิมไม่ถูกแก้ และไม่มี orphan process; บันทึก machine-specific absolute paths ที่ไม่สามารถพกพาได้และวิธีแจ้งผู้ใช้
5. บันทึก commands, artifact hashes, expected/actual และสถานะ passed/failed/blocked/not run ใน `docs/windows-validation.md`; จัดทำ `docs/windows-portable.md` คู่มือภาษาไทยเมื่อเริ่ม implement ไม่ใช้แผนนี้แทนคู่มือที่ทดสอบแล้ว

ผ่านเมื่อแตก ZIP และใช้งานบน environment ที่ประกาศรองรับได้โดยไม่มี dev tools/admin/installer, ย้ายโฟลเดอร์แล้ว config/data ของแอปยังอยู่ครบ, update ไม่ลบข้อมูล และ **ผู้ใช้ยืนยันการใช้งาน portable จริง** ก่อนประกาศพร้อมแจก การวางแผนครั้งนี้ไม่อนุมัติ publish/upload artifact, installer, signing หรือ auto-update

## หลักฐานและวิธีตรวจงานทุกเฟส

| เอกสารเป้าหมาย (ยังไม่สร้างในงานแก้แผนนี้) | เนื้อหาขั้นต่ำ |
|---|---|
| `docs/sources.md` | upstream URL/SHA, local baseline, provenance ของ diff/ไฟล์ใหม่, เอกสารอ้างอิง, ประวัติเลื่อน SHA |
| `docs/windows-integration.md` | contracts, thread/handle ownership, startup/shutdown, errors, config/branding และคำสั่ง runtime ใหม่หลัง implement |
| `docs/reference-notes.md` | API/ลิงก์/path/SHA ที่อ่าน, ไม่แปะโค้ดฟอร์ก; ระบุไม่ได้ใช้ Noctty ได้ |
| `docs/windows-validation.md` | เครื่องมือ/SDK/GPU/OS, ขั้นทดสอบ, expected/actual, exit code, log reference, counts ของ skipped/failed, baseline exceptions และ human acceptance |
| `docs/gaps.md` | อาการ/ผลกระทบ, วิธีทำซ้ำ, shell/font/config ที่ใช้, log ที่ลบข้อมูลลับแล้ว, สถานะ/ทางแก้ |

สถานะผลตรวจต้องใช้ passed / failed / blocked / not run / not applicable อย่างตรงไปตรงมา ห้ามถือว่า skipped หรือไม่มีเครื่องมือเป็น passed บันทึก `$LASTEXITCODE` ทันทีหลัง native command ก่อนคำสั่งอื่น ไม่เก็บ environment ทั้งชุดหรือข้อมูลลับใน log

การ rollback ให้แยก diff ของแต่ละเฟสและรักษา provenance ใช้ revert ของ commit ที่ระบุเมื่อได้รับอนุมัติ ไม่ `reset --hard`, `clean` หรือทับไฟล์ผู้ใช้เพื่อให้ทดสอบผ่าน ก่อน commit ตรวจเฉพาะไฟล์ที่เกี่ยวข้อง และไม่รวม `.letta/` หรือ reference โดยอัตโนมัติ

### การใช้ agent

โปรไฟล์ `.letta/agents/*.md` ที่ตรวจพบยังจำกัดงานเฉพาะ Olufy-API และ runtime ปัจจุบันไม่รับ custom type `repo-scout`/`advisor`; general-purpose สองตัวที่ลองปฏิเสธงาน จึงยังไม่มี independent review จาก subagent ห้ามนับว่ารีวิวแล้ว ก่อนใช้ต่อให้ผู้ใช้อนุมัติการปรับโปรไฟล์ให้ตรง Ghostty รวมชื่อโมเดลที่ใช้จริงก่อน ไม่เปลี่ยนโมเดลหรือข้อจำกัดเงียบ ๆ งานแก้แผนครั้งนี้ไม่แก้โปรไฟล์เหล่านั้น

## การเลื่อน SHA ของ Ghostty

เลื่อนทีละคอมมิตหรือทีละช่วงที่อ่าน diff ได้ บันทึก SHA เก่าและใหม่ใน `docs/sources.md` ไฟล์ที่เราเขียนเองให้เราเป็นฝ่ายปรับให้เข้ากับคอร์ อย่ารับไฟล์ `src/apprt` จากที่อื่นมาทับ

รีโมต

- `upstream` ที่ต้องตั้งในเฟส 1 คือ `https://github.com/ghostty-org/ghostty.git` ใช้ fetch และตั้ง push URL เป็น `DISABLED`; ปัจจุบันยังไม่มี และค่านี้เป็นเพียงตัวกันพลาด ไม่ใช่กลไกควบคุมสิทธิ์
- ไม่มีรีโมต Noctty ในรีโปซอร์ส โคลนอ้างอิงอยู่นอก git
- `origin` มีอยู่แล้วคือ `https://github.com/nickza2026/ghostty-windows` ให้คงไว้ ไม่ rename และไม่ push โดยไม่มีคำสั่งผู้ใช้

## ความเสี่ยง

| ความเสี่ยง | ผล | การรับมือ |
|---|---|---|
| Ghostty ไม่มีแอป Windows | เฟส 1 จบแล้วยังใช้เป็นเทอร์มินัลไม่ได้ | เฟส 3 และ 4 คือกำแพงนี้ เขียนเองเป็นชิ้นเล็ก |
| ไฟล์ Noctty ปนที่มา | copy แล้วชี้ SHA ของ Ghostty ไม่ได้ | กฎที่มาของโค้ด และ `reference/` ไม่อยู่ใน git |
| บิลด์ของ Noctty ดูพร้อมใช้ | ธงและสคริปต์ดาวน์โหลดกลายเป็นทางลัด | ใช้คำสั่งจาก workflow ของ Ghostty ถ้าไม่มีให้เขียนเอง |
| Zig คนละรุ่นกับ `build.zig.zon` | บิลด์ไม่เริ่ม | ติดตั้งรุ่นที่ไฟล์นั้นระบุ วันที่สำรวจคือ 0.16.0 |
| OpenGL บนเครื่องนี้ยังไม่รู้ | เฟส 4 วาดไม่ได้แม้หน้าต่างขึ้น | ตรวจตอนเฟส 4 ก่อนเขียน renderer ใหม่ |
| คอร์เดินหน้าบน `main` | SHA ที่ปักเก่ากว่า `main` ในอีกไม่กี่สัปดาห์ | เลื่อน SHA เป็นงานเฉพาะ ไม่ปนกับฟีเจอร์ |
| ConPTY มีโค้ดแต่ยังไม่ทดสอบ | เข้าใจผิดว่า shell integration เสร็จแล้ว | ทดสอบ 4B/4D และแก้เฉพาะ gap ของเส้นทางเดิม |
| full-core Windows ไม่ตรง job Nix | คิดว่า upstream รับรองทุกเทสต์แล้ว | แยก VT baseline กับ full-core และอนุมัติ blocker ก่อนเฟส 3 |
| WGL/thread/teardown ผิดลำดับ | จอดำ ค้าง หรือ handle รั่ว | ownership document และ stress test ก่อนใช้งานจริง |
| ข้อมูลที่มาไม่ยืนยัน | รับรองโค้ดที่ตรวจจาก official ไม่ได้ | ตรวจ upstream ancestry/tree และ provenance ของ local diff |
| config/ไอคอนยังใช้แบรนด์เดิม | แอปดูเหมือนทางการหรือทับ config เดิม | ตรวจ exe, resource, manifest และ config isolation ก่อนเปิดให้ใช้ |

## สิ่งที่แผนนี้ไม่ทำ

- ไม่ clone Noctty มาเป็นฐานซอร์ส และไม่บิลด์ Noctty เพื่อใช้เป็นแอปของเรา
- ไม่ copy โค้ดที่ชี้ repo, path และ commit ไม่ได้
- ไม่ส่งพอร์ต Windows ทั้งก้อนกลับ `ghostty-org/ghostty`
- ไม่ใช้ GTK เป็นแอป Windows
- ไม่เขียนตัวแปล VT ใหม่ทับ `src/terminal/**`
- ไม่ใส่เทเลเมทรี และไม่เปิดทางอัปโหลดแครช

## แหล่งอ้างอิงและสิ่งที่ต้องตรวจเพิ่ม

- หลักฐานที่อ่านจาก local baseline: `AGENTS.md`, `AI_POLICY.md`, `README.md`, `build.zig.zon`, `build.zig`, `src/build/Config.zig`, `src/build/GhosttyExe.zig`, `src/apprt.zig`, `src/apprt/runtime.zig`, `src/apprt/surface.zig`, `src/renderer.zig`, `src/renderer/backend.zig`, `src/font/backend.zig`, `src/pty.zig`, `src/termio/Exec.zig`, `dist/windows/ghostty.rc` และ `.github/workflows/test.yml`
- Windows CI ที่อ่านจริง: job `build-libghostty-vt-windows` ประมาณบรรทัด 936; full-core command อยู่ใน job `test` ประมาณบรรทัด 1474 ซึ่งใช้ Nix
- official source สำหรับยืนยัน provenance ในเฟส 1: https://github.com/ghostty-org/ghostty
- Microsoft สำหรับอ่านและบันทึกเวอร์ชัน/วันที่ก่อน implement: https://learn.microsoft.com/en-us/windows/console/creating-a-pseudoconsole-session , https://learn.microsoft.com/en-us/windows/win32/opengl/rendering-contexts , https://learn.microsoft.com/en-us/windows/win32/intl/input-method-manager , https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows
- ลิงก์จากแผนเก่าที่ยังไม่ตรวจสถานะออนไลน์: Ghostty discussions #2563/#12371, PR #12167/#11839 และ https://github.com/amanthanvi/noctty ; ไม่ใช้ยืนยันสถานะ merge, ฟีเจอร์ หรือความเข้ากันได้ของ SHA ปัจจุบัน
- ตรวจเครื่องจริง: `Get-Command`, `vswhere -products '*'` และ component query พบ VS Community พร้อม MSVC; ไม่พบ Zig ใน PATH แต่ยังไม่ได้สแกนทั้งดิสก์ และยังไม่ทดสอบ Windows SDK/OpenGL/runtime

## ลำดับเริ่มงานหลังอนุมัติแผน

1. แก้ขอบเขต agent เฉพาะเมื่อผู้ใช้อนุมัติ แล้วจึงขอ independent review; ไม่ถือว่าเป็นเงื่อนไขให้แอบแก้ settings
2. เปิด Developer PowerShell ของ VS ที่มีอยู่ ตรวจ toolchain และขออนุมัติติดตั้ง Zig ถ้าจำเป็น
3. ตรวจ official provenance และบันทึก `docs/sources.md` โดยรักษา `origin` และไฟล์ค้าง
4. รัน Windows VT baseline และ full-core probe แยกผล ก่อนเริ่ม branch implementation/ออกแบบ integration
5. ดำเนินเฟส 2 → 3 → 4A–4D → 5 ตามเกณฑ์ ไม่เพิ่มแท็บหรือเปลี่ยน renderer เพื่อข้าม blocker

งานปัจจุบันเป็นการปรับแผนด้วย Letta Code จากการอ่านซอร์สและตรวจเครื่อง ไม่ใช่การ implement หรือหลักฐาน build ผ่าน หากจะนำงานไปสื่อสารกับ upstream ต้องทำตาม `AI_POLICY.md` เรื่องการเปิดเผย AI assistance และการตรวจโดยมนุษย์; แผนนี้ไม่อนุมัติการสร้าง issue/PR หรือส่ง contribution อัตโนมัติ
