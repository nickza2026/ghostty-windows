# Mouse / selection / scrollback — native Win32

## ปัญหาและขอบเขต

19 ตุลาคม 2026 เวลา10:14 ผู้ใช้ยืนยันpasteปกติ แต่คลุมข้อความ/copyและล้อเมาส์ไม่ได้ Candidate50มีkeyboardcopybindingแต่ไม่มีmousehooksส่งเข้าCore จึงแก้backendโดยไม่เขียนselection/scrollback engineแยก ไม่เปลี่ยนCtrl+Cสำหรับinterruptหรือผ่อนresourcegate

## เส้นทาง input

- `window.zig` ส่ง WM_MOUSEMOVE/button/double-click/XBUTTON/wheel/horizontalwheel/capture-changed/cancel/leave ให้App
- `mouse_input.zig` decode signed16-bitcoordinates/buttonและsignedwheeldelta ไม่เปลี่ยนnegativecoordinatesเป็นunsignedขนาดใหญ่
- Button/moveเป็นclientphysicalpixelsอยู่แล้ว ส่วนwheelใช้screencoordinatesจึงScreenToClientก่อน ส่งCore.cursorPosCallbackและcacheNativeSurface.cursorให้getCursorPosตรงกัน ไม่คูณDPIซ้ำ
- Core.mouseButtonCallbackดูแลgesture/selectionและmouse-reportingของTUIตามเดิม Core.scrollCallbackรับwheelเป็นticks(delta/120),แนวบวกverticalขึ้น/horizontalขวา Partialverticalให้Coreสะสม; horizontalสะสมจนเต็มtickก่อนเพราะCoreปัดnonprecisionhorizontalเป็นinteger
- Interactivebuttondownใช้SetFocus/SetCapture;ปล่อยcaptureเมื่อbuttonสุดท้ายup/WM_CANCELMODE/focusหาย เมื่อWM_CAPTURECHANGEDหรือfocusหายส่งreleaseให้Coreและล้างcachedpressedbuttons ป้องกันลากค้าง
- TrackMouseEventขอWM_MOUSELEAVEและclearhoverนอกviewport HWNDถูกทำลายตามlifecycleเดิม
- Automatedoffscreen/no-activate **ไม่เรียกSetFocus/SetCapture** ไม่injectglobalinput และnativeclipboardcapabilityปิดในsmokemode จึงไม่อ่าน/เขียนOSclipboardหรือเปิดpermissiondialogจากtest

## หลักฐาน automated

Decoder3testsผ่าน:negativeclient/monitorcoordinates,buttons/double/Xbuttons,wheelsign/partialdelta

```powershell
zig test src/apprt/win32/mouse_input.zig
.\tools\windows\runtime-smoke.ps1 -Mode terminal -MouseSmoke -Executable .\zig-out\copy-input\bin\localterm-dev.exe
```

Mousefixtureสร้างscrollbackผ่านownedPowerShell ส่งmousemessagesเฉพาะownedoffscreenHWND ตรวจCore.selectionStringไม่ว่าง,viewportออกจากbottomด้วยwheelupและกลับbottomด้วยwheeldown,จำลองcapture-lossแล้วไม่มีbuttonค้าง คงrender/paint/terminalThai/deadlineเดิม ไม่ใช้testนี้claimphysicalcaptureหรือclipboardcopyจริง

Build51compilefailเพราะlocalreadyชนcallback;เก็บfailureไว้ แก้ชื่อแล้วbuild52ผ่าน123/123 Mousefixtures `terminal-native-20261019-102627-050`/`102640-691`ผ่านทั้งสองรอบ Keyboard/burst-title/exit/imageE2Enormal+portableผ่านเช่นกัน

Candidate52path `zig-out/mouse-input/bin/localterm-dev.exe` SHA256:

```text
19B1667DFD3CA1D145D9D82D17C5E8F254DD8A294F5452220AC912DFD7291966
```

Full-core→VT→strictlifecycleหลังpatchกำลังรันแยก ไม่มีการนำcore/VTผลcandidate50มาอ้างเป็นผลใหม่ strictlifecycleก่อนหน้าที่ยังfailed233→234handles/6→7threadsยังไม่ถูกปิด

## Manual acceptance ที่ต้องผู้ใช้ยืนยัน

ปิดpreviewตัวเก่าก่อน แล้วเปิดcandidateล่าสุด53แบบเห็นหน้าต่างตามปกติ:

```powershell
cd D:\works\ghostty-windows
.\tools\windows\preview.ps1 -Executable .\zig-out\copy-input\bin\localterm-dev.exe
```

1. ลากเลือกข้อความธรรมดาในหน้าต่าง ดูhighlightและขอบเขตตรงกับข้อความ
2. คลิกขวาหลังมีselection แล้ววางในNotepadด้วยตัวเอง; เมื่อไม่มีselectionต้องไม่paste Ctrl+Shift+Cเป็นอีกcopybindingที่ตรวจแยกจากคลิกขวา Ctrl+Cยังมีความหมายinterruptของshellตามbindingเดิม ไม่ใช้agentอ่านclipboard
3. สร้างhistoryด้วย`1..100 | ForEach-Object { "บรรทัด $_ ABC ไทย" }` แล้วหมุนwheelขึ้น/ลง ดูhistoryจริงและกลับpromptได้
4. ทวนลากออกขอบหน้าต่างแล้วปล่อย/สลับหน้าต่างระหว่างลากว่าไม่ค้างcapture รายงานแยกจากoffscreenซึ่งไม่แตะphysicalcapture

ยังไม่claimhumanmouse/copyผ่านจนผู้ใช้ยืนยัน และไม่แทนIMEcomposition/DPIทุกจอ/AI-CLIหรือเกณฑ์ใช้จริงเฟส5

## Copy report และ candidate53 ที่กำลังตรวจ

เวลา10:30ผู้ใช้รายงานCtrl+Cไปpromptบรรทัดใหม่ (อธิบายว่าเป็นinterruptและให้ลองCtrl+Shift+C) เวลา10:32ผู้ใช้ยืนยันว่ายังเหมือนเดิมและขอselection+right-click copy **จึงยังไม่ถือว่าcopyผ่านหรือสรุปว่าผู้ใช้กดผิด**

หยุดfull-coremouse52ที่ownedprocessก่อนแก้sources ไม่ปิดpreviewหรือโปรแกรมของผู้ใช้ รายงานexit255ของbaselineรอบนั้นเป็นcancelled-by-agentเพื่อแก้blocker ไม่ใช่testassertionfailure VT/lifecycleในpipelineนั้นยังไม่รัน

Candidate53ตั้งCore `right-click-action=copy`ในWin32config (ไม่ใช่copy-or-paste/context-menu):เมื่อมีselectionคัดลอกselectionเดิมไม่ว่าคลิกที่wordไหน เมื่อไม่มีselectionไม่paste/ไม่ส่งshellcommand ใช้productionCorecopyrouteเดียวกับshortcut

เพิ่มfixtureผ่านnativekeyhandlerด้วยsyntheticCtrlShiftCmodsที่จำกัดเฉพาะmousefixture และrightclickmessagesเฉพาะownedoffscreenHWND แล้วเทียบCorecopyMIMEtextกับselectionStringผ่านin-memorysink ตรวจrightclickไม่มีselectionไม่เขียนclipboardเพิ่ม ProductionWindowsclipboardwriter/permissionsไม่ถูกแทนที่ Fixtureปิดrealreadsและwriteเฉพาะsink จึงไม่แตะclipboardของผู้ใช้ ไม่ใช้ผลนี้อ้างว่าWindowsclipboardwriteจริงผ่าน

ขณะนี้build53และregressionsกำลังรัน ยังไม่ยืนยันสาเหตุmanualshortcutfailureหรือผลcopyจริงก่อนทวนจบ

### ผล candidate53 — 10:41

Build53ผ่าน123/123; nativeCtrlShiftC/rightclick→Corecopy→sinkตรงกับselectionทั้ง2รอบ (`terminal-native-20261019-103957-530`/`104009-293`) และno-selectionrightclickไม่เพิ่มwrite Mouseviewport/cancel,keyboard/burst-title/exit/imageE2Enormal+portableผ่าน ไม่claimOSclipboardwriteสำเร็จจากsink

ล่าสุด `zig-out/copy-input/bin/localterm-dev.exe` SHA256:

```text
0EF93F4DAA02094578CBAFA6FB47D131655CC7026F8A6092FCC152B2FD235C56
```

ไม่มีtestรันอยู่หลังpipelineจบ รอผู้ใช้manualrightclickcopyบนprefixใหม่นี้เพื่อยืนยันOSboundary ก่อนbaselinefull-core/VTของsourcefinal; ผลcore/VTก่อนmousepatchและชุดmouse52ที่cancelไม่ใช่ผลbaselinecandidate53 Strictlifecycleเดิมยังfailed ไม่ผ่อนthresholdหรือdeclareพร้อมใช้งาน

### Human confirmation — 11:00

ผู้ใช้ตอบ “ได้แล้วทำอะไรต่อ” หลังได้รับขั้นตอนcandidate53ลากเลือก→คลิกขวา→วางNotepad จึงบันทึกright-clickcopyผ่านจากuserreport ไม่ใช่agentอ่านOSclipboard ไม่อ้างCtrl+Shift+CหรือCtrl+Ccopyผ่านตามไปด้วย และยังไม่รับรองclipboardimage/AI-CLI

ส่งทดสอบmanualwheelในhistory100บรรทัดต่อ พร้อมเริ่มfull-core→VTเต็ม-j1ไม่filter→strictlifecyclecandidate53แยก ไม่แก้sourcesระหว่างงานเหล่านี้และไม่ใช้humanrightcopypassลบresourcefailure

เวลา11:01ผู้ใช้ตอบ “ได้ปกติ” หลังขั้นสร้างhistory100บรรทัดและverticalwheelup/downกลับprompt รับbasicwheelscrollbackเป็นuserreportedpass ไม่เหมารวมhorizontal/touchpad/TUIทุกแบบ ส่งphysicaldragออกขอบแล้วปล่อยเพื่อตรวจcaptureไม่ค้างต่อ ไม่อ้างoffscreenได้ตรวจphysicalcaptureแล้ว

เวลา11:04ผู้ใช้ตอบ “ได้” หลังdragออกขอบ/ปล่อย/กลับเข้ามาโดยไม่กดปุ่ม รับphysicalcapture/releaseกรณีนี้เป็นuserreportedpass ยังไม่อ้างfocus-lossระหว่างลากหรือphysicalDPIทุกจอผ่าน ส่งfocus-lossระหว่างdragเป็นmanualreleasepathถัดไป

เวลา11:06ผู้ใช้ตอบ “ไม่ค้างตาม” หลังdrag→Alt+Tab→ปล่อย→กลับมา รับfocus-lossreleaseเป็นuserreportedpass รวมmanualrightclickcopy/verticalwheel/ปล่อยนอกขอบ/focus-lossตามchecklistผ่าน ไม่อ้างCtrlShiftCที่เคยรายงานfailหรือทุกDPI/TUIผ่าน และไม่เปลี่ยนstrictresourcegate Full-core/VT/lifecycleชุดcandidate53ยังทวนแยกโดยไม่แก้source

### Baseline candidate53 จบ — 11:43

Full-coreผ่าน3926/3987/61skip,89/89steps;VTผ่าน6722/6786/64skip,45/45steps ทั้งสองexit0/Debug/-j1/ไม่filter Lifecycleล่าสุด235→236handles,6→7threads,GDI/USER3→3ยังfailedResourceGrowthไม่timeout ไม่ใช้absolutehandlesต่างprocessเทียบเป็นleakเพิ่ม ไม่มีtestรันค้าง ยังไม่พร้อมและไม่claimshortcutCtrlShiftCหรือทุกDPIผ่านจากrightclickcopyที่ผู้ใช้ยืนยัน
