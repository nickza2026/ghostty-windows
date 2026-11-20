# Thai midline editing cursor — 27 ตุลาคม 2026

## รายงานที่ต้องแก้ — ยังไม่verified fix

ผู้ใช้ทดลองmanualpreviewdefaultcandidate `app-build-20261026-193028-701/bin/localterm-dev.exe` (SHA256 `E0AA1AC887FBD29C30B143CEDAF85FA16EEA7A721E9C10570DB7FD370CC5C3D0`), systemConPTY, defaultlegacyrenderer, observedDPI96/100%

หลังinitialbasiccaseตอบ“ปกตินะ” ผู้ใช้รายงาน12:43:55ว่า **“ไม่ปกติละ ตอนเลือกตัวหนังสือกลางๆแล้วพิมพ์ aaaaa ยาวๆมันไม่อยู่หลัง a”** ภาพcounterexampleมีข้อความไทยก่อนLatinrunและcaretอยู่ในexistingrightsuffix ไม่ติดท้ายrunของaตามที่ผู้ใช้คาด

เก็บภาพ/คำพูด/identityใน `%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\manual-ime-dpi\20261027-122127-767\human-typing-report.json` พร้อม `midline-edit-user-counterexample.png` ไม่อ่านlivebuffer/clipboardหรือส่งinputเข้าpreviewของผู้ใช้ ไม่เปลี่ยนWindowsscale/driver/defaultproviderหรือปิดหน้าต่างเอง

**ยืนยัน13:34:36:** ผู้ใช้ตอบ **“ลูกศร”** จึงกำหนดregressionเป็นkeyboardnavigation/แทรกกลางบรรทัด ไม่ใช่terminalmouse-selection

## Related controlled A/B ที่รันแล้ว — ไม่ใช่interactive reproduction

ใช้copyของ**samebinary**จากpreviewในprivateprefix `zig-out/thai-midline-provider-20261027-124820-674` ทั้งสองprovider โดยเปลี่ยนเพียงexplicitprovider ไม่แก้font/width/gatesหรือเพิ่มwarmup มีapprovedapp-localDLL/EXEจากexistinghash-pinnedcache ไม่download/installระบบ ไม่แตะhumanwindow

คำสั่งต่อprovider:

```powershell
& .\tools\windows\runtime-smoke.ps1 -Mode terminal -TimeoutSeconds 45 -ThaiTuiSmoke -RequireThaiModel -ConptyProvider <system|app-local> -Executable <same-private-binary>
```

| Provider | Actual result | Unicode-reference differences | Final cursor |
|---|---|---|---|
| System | exit1 / `ConptyUnicodeModelMismatch`, no timeout | 38 cells | expected(45,11), actual(45,11) |
| App-local | exit0 / strictmodelpassed, no timeout | 0 cells | expected(45,11), actual(45,11) |

Artifacts: `%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\thai-midline\20261027-124820-674`; exactnativecases `terminal-native-20261027-124821-650` และ `terminal-native-20261027-124832-433`

นี่confirmknownproviderdependentThai**output**modelmismatchบนbinaryปัจจุบัน และย้ำว่าcursor-onlycheckอาจผ่านแม้cellsผิด ไม่พิสูจน์ว่าเป็นสาเหตุของuser'sinteractivePSReadLinecaseหรือว่าapp-localแก้caseนั้นแล้ว

## ช่องว่างและการทวนถัดไป

Existing `thai_tui_fixture.zig` เป็นpredeterminedstdout/pacedCUP/EL/relativeoverwrite/wrap ไม่interactive ไม่มีPSReadLine ไม่ตรวจcaretหลังการinsertแต่ละครั้ง `thai_tui_model.zig` เปรียบเทียบfirst20rowsและfinalcursor ไม่ใช้ผลนี้ปิดmidlinebug

Actualpreviewใช้ownedWindowsPowerShell `-NoLogo -NoProfile -NoExit -Command <UTF8-init>` การอ้างPSReadLinecause/versionยังต้องตรวจในcontrolledfreshshell ไม่อ่านhistory/profile/sessionของผู้ใช้

เพิ่มopt-infixture `LOCALTERM_MIDLINE_SMOKE` ผ่าน `tools/windows/midline-arrow-check.ps1` เพื่อทวนfreshowneddisposableshellกับinstalledMicrosoftPSReadLine2.0.0จริง: fixedprompt, ASCIIcontrolแล้วThaiprefix+ASCIIrightsuffix, left12ครั้ง, insert32a, F12orderedOSCbarrierพร้อมGetBufferState logicalindex/base64text และConsoleX เก็บcompleteactualrowcells/graphemes+caretเทียบreference จากนั้นF11RevertLineตรวจemptybufferและส่งexplicitreadinessbarrier ไม่Enterexecute ข้อมูลsynthetic ไม่มีOSSendInput/clipboard/humanpreviewinput

ChildAPPDATAเป็นuniqueprivateartifactก่อนimportPSReadLine และhistorySaveNothing/privatepath ไม่อ่านprofile/historyเดิม เมื่อจบต้องครบทั้งสองcaseและไม่มีfailures ไม่มีการเปลี่ยนfont/renderer/providerdefaultหรือoffsetcompensationเพื่อให้testผ่าน

Attemptแรกbuildไม่ผ่านเพราะZiginferred-error-setcycleจากtest-onlytitle→keycallbackhook เก็บrawfailedtranscript/qualificationแยก ไม่ใช่productredและไม่มีruntime แก้เฉพาะbarrierให้ใช้expliciterror-setก่อนทวนใหม่ ต้องได้intendedruntimefailureก่อนproductpatch ไม่รับcompileerrorเป็นreproduction

Attemptถัดมา `arrow-20261027-134724-534` build123/123จริง และASCIIcontrolผ่านทั้งsystem/app-local: buffer_oktrue/logicalcursor47/consoleX51/terminalX51/referenceX51/cells0 แต่Thaiยังไม่ถึงเพราะCtrl+Cไม่ออกreadinessรอบถัดไป จึงเป็น**incompleteharness ไม่ใช่productredหรือfixproof** เก็บrawtranscript/qualificationแยก แก้testtransitionเป็นF11RevertLine+verifiedempty+explicitbarrier ไม่เพิ่มsleep/deadline ไม่ลดassertionsและไม่เปลี่ยนproductbehavior

พักphysicalmixed-DPI; aggregateeditingacceptanceยังไม่ผ่าน No commit/push และไม่มีการแก้productlogicแบบเดาสาเหตุจากrelatedA/B

## Interactive runtime red ที่ครบจริง — ยังไม่แก้ product

`arrow-20261027-135531-807` build123/123/MSVC-baseline-ReleaseSafe/sourceunchangedระหว่างbuild+cases ใช้F11verifiedemptybarrierแล้วครบASCIIและThaiจริง ไม่ใช่incompleteattemptก่อนหน้า:

| Provider / case | Buffer/suffix | Logical UTF-16 offset | Console X | Terminal X | Expected X | Row cell differences |
|---|---|---:|---:|---:|---:|---:|
| system / ASCII | exact | 47 | 51 | 51 | 51 | 0 |
| system / Thai | exact | 48 | **52** | **52** | **49** | 0 |
| app-local / ASCII | exact | 47 | 51 | 51 | 51 | 0 |
| app-local / Thai | exact | 48 | **52** | **52** | **49** | 0 |

Exactnativecases `terminal-native-20261027-135809-948`, `terminal-native-20261027-135823-960` ทั้งคู่exit1/`MidlineCursorOrCellMismatch`/no timeout/cleaned_descendants[] expectedred ไม่ใช้exit0ของexperimentrunnerเป็นproducttestpass BothConPTYprovidersไม่แก้interactivecaseนี้

Thai prefixมี16UTF-16units และ3NonSpacingMarksคือU+0E49/U+0E48/U+0E31 จึงoccupy13gridcellsในcaseนี้: prompt4+prefix13+insert32=49; PSReadLineนับprefix16แล้วไป52 Fullrowcellsตรงreferenceรวมrightsuffix ดังนั้นcaret52อยู่ในsuffixจริง ไม่ใช่logicalinsertผิดหรือglyphdataหาย ตัวเลขนี้ไม่ใช่การเปลี่ยนexpectedให้ตามConsoleX

## หลักฐาน official PSReadLine width path

อ่านpublicsourceเท่านั้น ไม่execute/installโค้ดที่ดาวน์โหลด:

- [PSReadLine v2.0.0 Render.cs](https://github.com/PowerShell/PSReadLine/blob/v2.0.0/PSReadLine/Render.cs#L849-L897): `LengthInBufferCells(char)` คืน1ให้Thaiทั้งสามmarks เพราะไม่ใช่control<256และไม่เข้าช่วงwide>=0x1100
- `ConvertOffsetToPoint` บรรทัด1044–1080วนแต่ละUTF-16charบวกwidthดังกล่าว แล้วบรรทัด833เรียก `_console.SetCursorPosition(point.X, point.Y)` ตรงกับdelta3ที่วัดได้
- [PSReadLine v2.4.5 Render.Helper.cs](https://github.com/PowerShell/PSReadLine/blob/v2.4.5/PSReadLine/Render.Helper.cs#L94-L120): officiallateststableที่APIคืนในวันทดสอบยังมีwidthalgorithmเดียวกันสำหรับThai ไม่อ้างว่าอัปเกรดเฉยๆหาย และยังไม่ได้ติดตั้ง/รันv2.4.5
- Installedmodulemanifest2.0.0 assemblyidentity `Microsoft.PowerShell.PSReadLine, Version=3.0.0.0, PublicKeyToken=31bf3856ad364e35`, SHA256 `B336DE6471B361478AE78EA3D98D7D9112DF4974CAE500C7D80E31A76177DE60` metadataตรวจได้โดยไม่invokeprivatewidthmethod/อ่านuserhistory Assemblyversionไม่ใช่moduleversion

Astra read-onlyadvisoryเห็นตรงกันว่าอย่าoffsetrenderer/เปลี่ยนConPTYเป็นfixของcaseนี้ Consoleและterminalตามตำแหน่งเดียวกันที่ผิดจากline-layout จึงต้องแก้upstreamline-editorcompatibilityพร้อมtest ไม่ทำterminalเดาว่าapplicationต้องการcursorช่องไหน

ยังไม่มีgreenfix ไม่มีmoderncompatiblemoduleติดตั้งอยู่ในstandardPS7locationsหรือpwshบนPATH Read-onlySDKinventoryพบ.NETSDK9.0.203 แต่ยังไม่ได้buildmodulefork ทางเลือกapp-ownedPSReadLinesourcecorrectionเป็นruntime/maintenance/packagingdecisionใหม่ ต้องขออนุมัติก่อน ไม่globalinstall/แก้profile/เปลี่ยนdefaultหรือbundleforkอัตโนมัติ

Relatedchecksบนsamefixturebinaryผ่าน: `input-native-20261027-141320-102` actualASCII+Thai+surrogate+Enter/repeat2 และ `exit-native-20261027-141330-791` naturalchildexit; previewpathregressionเพิ่มinheritedMIDLINEenvclear+restoreผ่านโดยinterceptStartProcessไม่เปิดGUI ผลเหล่านี้ไม่ปิดmidlinebug

ทวนexactinteractivecasesซ้ำอีกครั้ง `terminal-native-20261027-141645-719`/`terminal-native-20261027-141656-453` ได้ASCII51ตรง/Thai52แทน49แบบเดิมทั้งคู่exit1/no timeout/cleaned_descendants[] บังคับ`midline_edit_diagnostic=true/readiness_evidence=false`ในmetadataใหม่ เก็บraw+qualifiedmatrixเป็น `repeat-qualified-red.json` ไม่เรียกเป็นgreen finalexactfixtureexe/OpenConsolepathsไม่พบliveprocess ไม่มีการปิดหรือส่งปุ่มเข้าhumanpreview

## ผู้ใช้อนุมัติ app-owned correction และ interactive module A/B

ผู้ใช้ยืนยัน **“ได้”** 14:28:33 อนุมัติทำPSReadLineฉบับแก้เฉพาะแอป ไม่ใช่globalinstall/profile/default-shell/ConPTYpromotionหรือGitpublication

Assetsอยู่ `third_party/psreadline/` และ `tools/windows/build-app-psreadline.ps1` เอกสารคือ `BUILD.md` ไม่ใช่README ไม่มีการสร้างworktree OfficialMITsourcev2.0.0 pincommit`6b5e9ff4bdfe15f67b3647e0d1ecdb6cf2e3bda6`, archiveSHA256`C9AFF6362CE22DB35EC400130C83C5120335BBC5B299953AF3F5D28E5F1BF67C` compileRoslynSDK9.0.203กับinstalleddesktopframework/SMArefs ไม่executeupstreambuildscripts ไม่NuGet/install/signing/profile/policybypass

OnlysourcechangeคือMn/Meคืน0ก่อนexistingcontrol/wideclassification Buildoriginal/patchedเหมือนกันและpreservelicense/provenance ทั้งคู่ผ่านactualcompiledwidthreflection10checks; originalภายใต้patchedexpectationต้องexit1`U+0E49: expected0 got1`; Thaiprefixold16/new13

Moduleartifactsสร้างใน `%LOCALAPPDATA%\Letta\app-psreadline-0efbcb87282b4f1382129ec3b77d3b7f` แล้วcopyเข้าprivatecandidate`zig-out/midline-module-20261027-143905-055/bin/{original,patched}-readline/PSReadLine` ไม่modifiedinstalledmodule

InitialintegrationมีstartupcmdletcollisionเพราะWindowsPowerShellpreloadPSReadLineก่อน-NoExit/-Command จึงไม่ใช่productred เพิ่มprivatefirstPSModulePathเฉพาะownedprocessก่อนspawn พร้อมrestorecallerค่าเดิม ไม่Remove-Moduleglobalหรือซ่อนfallback Childtypeactualassemblyต้องอยู่selecteddirectoryและhashตรงartifact Parentrunnerตรวจhashจริง ไม่ใช้แค่manifest/version

`tools/windows/midline-module-check.ps1` actual8runs **old→patched→old→patched** ทั้งsystemและapp-localบนsamebinary ครบ/qualifiedทุกrun:

- OriginalDLLSHA`BC979004209800C07C7369F485CE3902C8EF2AF6F579C29B6F2C0EEF5471DA42`: ASCII51ตรง/Thaibuffer/suffix/cellsถูกแต่ConsoleX=TerminalX52แทน49 nativeexit1
- PatchedDLLSHA`B1BE80EB70C8F4721C6D77112A9B3E9D84E8C74911B6F7B37A3C60E72BF2847B`: ASCII51ตรง/Thaibuffer/suffix/cellsถูกและConsoleX=TerminalX=expected49 nativeexit0
- no timeout/forceddescendantcleanup; originalredและpatchedgreenสลับกลับได้ในfreshprocess ไม่มีcacheassemblyค้าง NativeCPU/GDIrender/paintยังต้องผ่านตามsupervisor
- exactmatrix/rawlogs `%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\thai-midline\module-ab-20261027-144929-971\results.json`

นี่เป็นgreenของboundedinteractivecase ไม่ใช่IME/mixed-DPI/fullUnicode/ZWJ/orphanmarks/wrappingacceptanceหรือdownlevel.NET4.6.1portability

Peerreviewพบmodulecontentsreparseguardและemptyproviderfalsegreen จึงเพิ่มqueue-basedtreeguardไม่ตามlinks/nonemptyuniqueprovider+requiredmatrixcount และทดสอบnegativeทั้งสองจริงก่อนlaunch (emptyarray/nestedjunction) ผ่าน Nativefixtureเพิ่มConsoleXassertตรงreferenceด้วย ไม่ลดassertionsหรือoffsetrenderer

### การเชื่อมใช้งานเฉพาะแอป: ผ่านอัตโนมัติและผู้ใช้ยืนยันเคสลูกศรแล้ว

ตัวเลือก `-AppReadLine` / `LOCALTERM_APP_READLINE=1` ใช้ asset ที่ `powershell/PSReadLine` ข้าง executable ผ่าน **child Config.env เท่านั้น** ไม่เปลี่ยน process/machine PSModulePath ของผู้ใช้ ตัวเลือกปกติที่ไม่เปิด flag ยังไม่เปลี่ยน ไม่เลือก app-local ConPTY ให้อัตโนมัติ

Startup ตรวจ patched variant, ตำแหน่ง assembly ของ type ที่โหลดจริง และ DLL SHA256 ตาม provenance หากไม่ผ่านจะออกจาก PowerShell (bootstrap กำหนด exit125; native supervisor ของ negative test เห็น exit1 จึงไม่อ้างว่าได้วัด child125 แยก) ไม่มี silent fallback เป็น module ของเครื่อง Normal mode ไม่มี fixture prompt/history policy/F11/F12 handlers และไม่เขียนทับ custom portable command เงียบๆ

Candidate `zig-out/app-readline-20261027-150014-546/bin/localterm-dev.exe`, native SHA256 `1950B65953B14C12C7F264F6442801755F6A712EB4CD885D88A21F70D31EBAE3` build123/123 และ native source hash คงเดิมตลอด build/tests:

- `terminal-native-20261027-150634-168` system และ `terminal-native-20261027-150647-396` app-local: ใช้ **product common bootstrap** และ asset ตาม exe โดยไม่ส่ง test-module override ข้อความ/ท้ายบรรทัดครบ ASCII caret51, Thai logical48, ConsoleX=TerminalX=expected49, celldifferences0, actual loaded DLL hash ตรง B1BE…847B, nativeexit0
- `input-native-20261027-150657-959`: common bootstrap + ASCII/Thai/surrogate/Enter/repeat2 ผ่าน
- `exit-native-20261027-150708-364`: common bootstrap + natural child exit ผ่าน
- ทุก positive case no timeout, cleaned_descendants[], readiness_evidence=false; raw transcript และ qualified matrix อยู่ `%LOCALAPPDATA%/Letta/build-logs/ghostty-windows/thai-midline/app-build-20261027-150014-546`
- `terminal-native-20261027-151031-197`: thin relocation ไปโฟลเดอร์ `readline relocated ไทย ...` ที่มีช่องว่างและภาษาไทยใน path ผ่าน regression เดิมพร้อม loaded hash เดิม ยืนยัน lookup ตาม executable ไม่ใช่ cwd และ caller PSModulePath ไม่เปลี่ยน
- `terminal-native-20261027-151238-438`: เปลี่ยน expected hash ใน provenance ของ clone เท่านั้น ถูกปฏิเสธก่อน startup marker/fixture, nativeexit1/no timeout/no cleanupdescendants
- `terminal-native-20261027-151249-172`: นำ required license ออกจาก clone ชั่วคราว ถูกปฏิเสธ FileNotFound **ก่อน spawn child** nativeexit1 ไม่มีการทดสอบกับ package หลักหรือ global module และ finally คืนไฟล์/bytes ของ clone ครบแล้ว

Unsigned local package consistency ไม่ใช่ Microsoft signature/authenticity guarantee ทาง preview ตรวจ ancestor/module-content reparse points; direct env opt-in ของ native helper อาศัย executable-relative package ที่เชื่อถือได้ ไม่ใช่ sandbox สำหรับ module ที่ไม่น่าเชื่อถือ ไม่อ้าง full grapheme/ZWJ/orphan-mark/wrapping/IME/mixed-DPI หรือ downlevel .NET4.6.1 portability

เปิดด้วย PowerShell จาก repository:

```powershell
.\tools\windows\preview.ps1 -Executable .\zig-out\app-readline-20261027-150014-546\bin\localterm-dev.exe -AppReadLine
```

ต้องนำ **ทั้งโฟลเดอร์** patched/PSReadLine จากผล `build-app-psreadline.ps1` ไปไว้ `bin/powershell/PSReadLine` ใน build prefix ใหม่ รวม manifest/psm1/DLL/format/license/provenance ห้ามถือว่ามีไฟล์ source แล้ว module จะ active เอง Helper preflight ปฏิเสธไฟล์ขาด/hashไม่ตรงก่อนเปิด GUI ไม่ใช้ `Install-Module`, profile หรือ execution-policy bypass

เปิด human preview ใหม่ PID11104 เวลา15:15:40 ด้วย normal route และ system ConPTY; native startup log ยืนยันโหลด DLL B1BE…847B แล้ว ไม่แตะ PID11164 เดิม ไม่ส่ง input หรืออ่าน clipboard/terminal buffer ของหน้าต่างคนใช้ หลักฐาน `%LOCALAPPDATA%/Letta/build-logs/ghostty-windows/thai-midline/manual-fixed-20261027-151540-169` การยืนยันภาพ/caret จากผู้ใช้ยัง pending และ WIN-RUNTIME-004/physicalmixedDPI ยังไม่ปิด

หน้าต่างใหม่จริงชื่อ `localterm-dev — APP_READLINE_ACTIVE|B1BE...` (ยังไม่ได้ตั้ง friendly title) ตัวเก็บ ready.json ของ launcher อ่าน redirected log ที่ยังเขียนอยู่ด้วย File.ReadAllText แล้วติด file-sharing error จึง **ไม่ใช้ไฟล์ ready.json เป็นหลักฐาน** ตรวจแยกด้วย native startup log, alive HWND3870074 และ bounded WM_NULL health metadata ได้ responsive=true/10ms โดยไม่อ่าน terminal buffer; เก็บ `verified-observation.json` และรอ closure ด้วย process handle ที่ตรวจ exact executable identity แล้ว Closure ไม่ใช่ human caret acceptance ห้ามเรียกเหตุขัดข้องของ metadata wrapper นี้ว่า product hang/failure

### ผู้ใช้ยืนยันผล — 27 ตุลาคม 2026 เวลา 15:26:58 Asia/Bangkok

หลังให้ลองลูกศรย้อนกลับแล้วพิมพ์แทรกใน preview ใหม่ ผู้ใช้ตอบ **“ไม่บัคแล้ว”** จึงถือว่า bounded Thai arrow-midline regression นี้ผ่านทั้ง automatic red/green comparison และ human acceptance บน candidate ข้างต้น ไม่ได้อนุมานจากการปิดหน้าต่างหรือ metadata wrapper สถานะ pending ตอนเปิด preview ด้านบนเป็นบันทึกตามเวลาและถูกแทนด้วยคำยืนยันนี้

ไม่ขยายผลเป็นการรับรอง full Unicode/grapheme/ZWJ/orphan marks/wrapping/IME, GPU หรือ physical mixed-DPI; WIN-RUNTIME-004 ยังเปิดอยู่ ไม่เปลี่ยน default/provider หรือ global module/profile และไม่มี commit/push จากคำยืนยันนี้ ใช้ preview ตัวเดิมต่อผ่าน `-AppReadLine` ได้
