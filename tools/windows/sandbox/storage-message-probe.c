/* Sends standard volume messages to one owned offscreen fixture HWND only.
 * No broadcast, device detach, process injection, clipboard, or VM control. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dbt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

static DWORD target_pid;
static HWND target;
static BOOL CALLBACK find_window(HWND hwnd, LPARAM unused) {
    DWORD pid = 0;
    wchar_t name[128];
    (void)unused;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == target_pid && GetClassNameW(hwnd, name, 128) &&
        wcscmp(name, L"localterm-dev.window-prototype") == 0 && IsWindowVisible(hwnd)) {
        target = hwnd;
        return FALSE;
    }
    return TRUE;
}
static int owned(void) {
    DWORD pid = 0;
    GetWindowThreadProcessId(target, &pid);
    return pid == target_pid;
}
static int send_volume(WPARAM event, DEV_BROADCAST_VOLUME *volume) {
    DWORD_PTR result = 0;
    if (!owned()) return 0;
    return SendMessageTimeoutW(target, WM_DEVICECHANGE, event, (LPARAM)volume,
        SMTO_ABORTIFHUNG | SMTO_BLOCK, 3000, &result) != 0;
}
int wmain(int argc, wchar_t **argv) {
    RECT rect;
    DEV_BROADCAST_VOLUME volume = {0};
    DWORD mask;
    if (argc != 3) return 10;
    target_pid = (DWORD)wcstoul(argv[1], NULL, 10);
    mask = (DWORD)wcstoul(argv[2], NULL, 10);
    if (!target_pid || !mask || (mask & (mask - 1)) || mask > (1UL << 25)) return 11;
    EnumWindows(find_window, 0);
    if (!target || !owned() || !GetWindowRect(target, &rect) ||
        rect.left < GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN) + 64 ||
        !(GetWindowLongPtrW(target, GWL_EXSTYLE) & WS_EX_NOACTIVATE) || GetForegroundWindow() == target) return 12;
    volume.dbcv_size = sizeof(volume);
    volume.dbcv_devicetype = DBT_DEVTYP_VOLUME;
    volume.dbcv_unitmask = mask;
    if (!send_volume(DBT_DEVICEQUERYREMOVE, &volume) || !send_volume(DBT_DEVICEARRIVAL, &volume)) return 13;
    volume.dbcv_unitmask = mask ^ 0x03ffffff;
    if (!send_volume(DBT_DEVICEREMOVECOMPLETE, &volume)) return 14;
    volume.dbcv_unitmask = mask;
    /* Malformed header cases run in-process in the window probe: system
     * message marshaling may reject them before reaching the target HWND. */
    if (!owned() || !IsWindowVisible(target)) return 16;
    if (!send_volume(DBT_DEVICEREMOVECOMPLETE, &volume)) return 17;
    /* HWND reuse cannot send a message to another process: after the final
     * event only ownership/visibility are observed, no further messages. */
    for (int i = 0; i < 100; ++i) {
        if (!owned() || !IsWindowVisible(target)) {
            puts("{\"matchedRemovalDisappeared\":true,\"negativeEventsPreservedWindow\":true,\"offscreen\":true}");
            return 0;
        }
        Sleep(10);
    }
    puts("{\"matchedRemovalDisappeared\":false,\"negativeEventsPreservedWindow\":true,\"offscreen\":true}");
    return 2; /* The original defect: completed removal leaves the window up. */
}
