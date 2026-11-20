# ทดลอง native Windows preview — ยังไม่ใช่ release

## Human check ล่าสุด — 27 ตุลาคม 2026 เวลา 12:41

**อัปเดต12:43:ยังไม่ผ่านeditingกลางบรรทัด** ผู้ใช้แนบ `paste-20261027-054223-13ba0086.png` และรายงาน **“ไม่ปกติละ ตอนเลือกตัวหนังสือกลางๆแล้วพิมพ์ aaaaa ยาวๆมันไม่อยู่หลัง a”** ภาพแสดงcaretอยู่ในข้อความsuffixด้านขวาแทนติดท้ายrunของaที่แทรก ยังต้องแยกวิธีย้ายcursor/selectionและสาเหตุจากcontrolledrepro ไม่เดาเป็นfontหรือแก้cursoroffsetเอง พักmixed-DPIและคงacceptanceรวมpending/failedตามcaseนี้ ข้อสรุป12:41ด้านล่างจำกัดเฉพาะbasiccaseไม่ใช่midlineeditingpass

ผู้ใช้ตอบ **“ปกตินะ”** พร้อมภาพ `paste-20261027-054150-5ae45b1b.png` หลังขั้นพิมพ์ไทย/สลับTH–EN/ลองBackspaceและลูกศร รับเป็น **user-reported pass ของการพิมพ์ไทยพื้นฐานในpreviewนี้** Agentเปิดภาพได้ เห็นข้อความไทยและABC123พร้อมcursorท้ายบรรทัด แต่ภาพนิ่งไม่พิสูจน์เหตุการณ์กดแต่ละปุ่ม/IMEcompositionหรือcandidatepopup

Artifact: `zig-out/app-build-20261026-193028-701/bin/localterm-dev.exe`, SHA256 `E0AA1AC887FBD29C30B143CEDAF85FA16EEA7A721E9C10570DB7FD370CC5C3D0`, system-defaultConPTY/ไม่opt-inremoteGPU หน้าต่างปกติที่ผู้ใช้อนุมัติ ค่าเริ่มต้นที่ตรวจจากownedHWNDคือDPI96/100% ไม่โอนผลนี้ไปหาbinaryอื่น

หลักฐานเก็บใต้ `%LOCALAPPDATA%\Letta\build-logs\ghostty-windows\manual-ime-dpi\20261027-122127-767` ยังไม่มีrecordedDPItransitionในตอนรับผลนี้ ขั้นถัดไปลากข้ามจอที่มีScaleต่างกันด้วยมือ โดยไม่เปลี่ยนdisplaysettingsแทนผู้ใช้ หากทุกจอScaleเท่ากันให้คงphysicalmixed-DPIเป็นยังไม่ทดสอบ ไม่ใช้ภาพ/WM_CHAR/syntheticDPIปิดcomposition/mixed-DPIหรือWIN-RUNTIME-004

เปิดเฉพาะ executable ที่บิลด์จาก checkout นี้ ชื่อ `localterm-dev.exe` เป็น prototype ของเรา ไม่ใช่ Noctty ยังไม่ใช่ ZIP portable/installer และยังไม่ผ่าน strict lifecycle, physical mixed-DPI และ human IME/clipboard acceptance ครบ ห้ามใช้ทดสอบกับรหัสผ่าน, token หรือข้อมูลลับ

## เปิด session ด้วยมือ

ใช้ PowerShell จาก repo root หลัง agent แจ้งว่า artifact ล่าสุดบิลด์และ smoke ผ่านแล้ว คำสั่งนี้เปิดหน้าต่าง **ให้คุณใช้งานจริง** ไม่ใช่ smoke ที่ปิดเอง และคืน environment เดิมของ PowerShell ผู้เรียกเมื่อจบ:

คำสั่งสั้นจาก repo root: `.\tools\windows\preview.ps1` wrapper นี้เปิด interactive window และคืน environment เดิม ไม่แก้ execution policy ถ้าเครื่องบล็อก ให้ใช้ชุดคำสั่งข้างล่างแทน ไม่ใช้ bypass policy อัตโนมัติ

เลือก artifact แยกด้วย `-Executable .\zig-out\image-paste\bin\localterm-dev.exe` ได้ รายละเอียด image paste, permission, portable image-cache และข้อจำกัดอยู่ใน [windows-image-paste.md](windows-image-paste.md) อย่าใช้ผลทดสอบ artifact ใหม่ไปรับรองexeเก่าที่defaultwrapperเลือก

```powershell
$names = @('LOCALTERM_WINDOW_SMOKE', 'LOCALTERM_TERMINAL_SMOKE', 'LOCALTERM_TERMINAL', 'LOCALTERM_INPUT_SMOKE', 'LOCALTERM_LIFECYCLE_SMOKE', 'LOCALTERM_TERMINAL_CASE')
$saved = @{}
try {
    foreach ($name in $names) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    $env:LOCALTERM_TERMINAL = '1'
    Start-Process -FilePath (Resolve-Path '.\zig-out\bin\localterm-dev.exe').Path -Wait
} finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
    }
}
```

ถ้าดับเบิลคลิกโดยไม่มี flag นี้ ยังเป็น window-only path โดยตั้งใจ ไม่ได้ promote terminal เป็น default ก่อนจบ gate Session ใช้ Windows PowerShell ของระบบ, `-NoProfile`, และ UTF-8 เฉพาะ process ไม่เปลี่ยน profile/locale/registry/PATH/config ของเครื่อง บิลด์ปัจจุบันยังเจาะจง CPU ของเครื่องนี้ อย่านำไปใช้รับรอง portable CPU baseline

ตามคำขอผู้ใช้18ตุลาคม2026 automated smoke ต้องอยู่นอกvirtual-desktop boundsทั้งหมดและไม่activate/แย่งfocus ไม่ใช่แค่พ้นprimarymonitor หรือเปิดแล้วค่อยย้ายภายหลัง Interactivepreviewที่เปิดด้วยมือยังแสดงตามปกติ ผลoffscreenต้องคงframebuffer capture/paint coverageและแยกจากการยืนยันภาพบนจอจริง ไม่ใช้การซ่อนwindow/ปิดpaint checksเพื่อให้ผลผ่าน

## ลำดับยืนยันผล

1. พิมพ์ `Write-Output 'ASCII สวัสดี กิ ก้ กิ้ 😀'` ตรวจตัวอักษร, สระ/วรรณยุกต์ซ้อน, emoji, baseline และไม่ตัดบน/ล่าง การได้ bytes ครบจาก smoke ไม่แทนการตรวจภาพนี้
2. สลับ English/Thai ด้วยวิธีปกติของคุณ พิมพ์เอง แก้ด้วย Backspace/arrows และลองกดค้าง ตรวจไม่หาย/ซ้ำ จากนั้น `Start-Sleep 30` แล้ว Ctrl+C ต้องกลับ prompt โดย session ยังอยู่
3. Clipboard ใช้ข้อมูลทดสอบที่คุณเตรียมเองเท่านั้น Ctrl+Shift+A เลือกทั้งหมด, Ctrl+Shift+C copy, Ctrl+V หรือ Ctrl+Shift+V paste มี permission prompt ตาม policy; ลอง deny แล้วต้องไม่ paste ข้อมูล ลองข้อความไทยสองบรรทัดแบบไม่เป็นคำสั่ง ตรวจ multiline confirmation ก่อนอนุญาต อย่าอนุญาต paste ข้อความที่ไม่รู้เนื้อหา
4. ถ้ามี IME ที่สร้าง composition/preedit อยู่แล้ว ลองเริ่ม composition, เลือก candidate, commit และ cancel ตรวจ candidate ตรง cursor, commit ไม่ซ้ำ และไม่ส่ง preedit เข้า shell Thai keyboard layout หลายแบบส่ง WM_CHAR ตรง ไม่ได้ทดสอบ IMM composition; ถ้าไม่มี IME แบบนี้ให้บันทึก **ยังไม่ทดสอบ** ไม่ติดตั้งภาษาเพิ่มเพื่อทำให้ดูเหมือนผ่าน
5. Resize/minimize/restore; ถ้ามีจอหลาย DPI ลากข้ามจอ ตรวจ glyph/grid/candidate ตรงตำแหน่ง หากมีจอเดียวให้บันทึก mixed-DPI ว่ายังไม่ทดสอบ ไม่ใช้ synthetic DPI มาแทน
6. ปิดหน้าต่างขณะ shell ทำงาน เลือก No ก่อน ต้องใช้ต่อได้ แล้วเลือก Yes เพื่อปิด session รอบถัดไปลองพิมพ์ `exit` ต้องปิดเอง ไม่มีหน้าต่าง/PowerShell ของ session ค้าง ไม่ทดสอบด้วยการฆ่า shell อื่นหรือ detached GUI ของคุณ

รายงานแยกแต่ละข้อว่า ผ่าน/ไม่ผ่าน/ยังไม่ทดสอบ พร้อมข้อผิดพลาดหรือภาพเฉพาะข้อมูลทดสอบ Agent จะไม่รับรองข้อ human-owned เองจาก unit tests หรือ screenshot ที่ตรวจ bytes เท่านั้น ขณะนี้ lifecycle ยังพบ process-global handle/thread ต่างจาก baseline ดู WIN-RUNTIME-004 ใน `gaps.md`; ไม่มีการเพิ่ม threshold/ปิด AMD driver feature เพื่อซ่อนผลนั้น
