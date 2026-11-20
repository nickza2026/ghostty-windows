/* Own, noninteractive window station. Never read, empty, save or restore the
 * user's WinSta0 clipboard; no SwitchDesktop, ShowWindow or SendInput calls.
 * Isolation failure is fatal, with NO fallback to the interactive station.
 */
#define _WIN32_WINNT 0x0A00
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

size_t localterm_probe_png(unsigned char *, size_t);
DWORD localterm_probe_read(HWND, DWORD);

static int put(HWND owner, UINT format, const void *bytes, SIZE_T length) {
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, length);
    if (!memory) return 0;
    void *data = GlobalLock(memory);
    if (!data) { GlobalFree(memory); return 0; }
    memcpy(data, bytes, length);
    GlobalUnlock(memory);
    if (!OpenClipboard(owner)) { GlobalFree(memory); return 0; }
    int ok = EmptyClipboard() && SetClipboardData(format, memory) != NULL;
    CloseClipboard();
    if (!ok) GlobalFree(memory);
    return ok;
}

static int check(HWND hwnd, DWORD kind, const char *label) {
    DWORD status = localterm_probe_read(hwnd, kind);
    printf("private clipboard %s status=%lu\n", label, (unsigned long)status);
    fflush(stdout);
    return status == 0;
}

int localterm_private_clipboard_fixture(void) {
    HWINSTA original = GetProcessWindowStation(); // borrowed
    HDESK original_desktop = GetThreadDesktop(GetCurrentThreadId()); // borrowed
    wchar_t name[96];
    if (swprintf_s(name, 96, L"LocaltermClipboardProbe-%lu-%llu",
                   (unsigned long)GetCurrentProcessId(), GetTickCount64()) < 0) return 1;
    const ACCESS_MASK access = WINSTA_READATTRIBUTES | WINSTA_ACCESSCLIPBOARD |
        WINSTA_CREATEDESKTOP | WINSTA_ACCESSGLOBALATOMS;
    HWINSTA station = CreateWindowStationW(name, CWF_CREATE_ONLY, access, NULL);
    if (!station) { fprintf(stderr, "private station unavailable=%lu; no fallback\n", GetLastError()); return 2; }
    HDESK desktop = NULL;
    HWND hwnd = NULL;
    int result = 3;
    if (!SetProcessWindowStation(station)) goto cleanup;
    desktop = CreateDesktopW(L"Fixture", NULL, NULL, 0,
        DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS | DESKTOP_CREATEWINDOW, NULL);
    if (!desktop || !SetThreadDesktop(desktop)) goto cleanup;
    if (GetProcessWindowStation() != station || GetThreadDesktop(GetCurrentThreadId()) != desktop) goto cleanup;
    hwnd = CreateWindowExW(WS_EX_NOACTIVATE, L"STATIC", L"private clipboard fixture",
        0, 0, 0, 1, 1, HWND_MESSAGE, NULL, GetModuleHandleW(NULL), NULL);
    if (!hwnd) goto cleanup;
    puts("private noninteractive clipboard isolation established; WinSta0 untouched");
    {
        unsigned char dib[48] = {0};
        BITMAPINFOHEADER header = {0};
        header.biSize = sizeof(header); header.biWidth = 2; header.biHeight = -1;
        header.biPlanes = 1; header.biBitCount = 24;
        memcpy(dib, &header, sizeof(header));
        dib[42] = 255; dib[44] = 255;
        if (!put(hwnd, CF_DIB, dib, sizeof(dib)) || !check(hwnd, 1, "CF_DIB to PNG")) goto cleanup;
        unsigned char png[1024] = {0};
        size_t length = localterm_probe_png(png, sizeof(png) - 8);
        UINT format = RegisterClipboardFormatW(L"PNG");
        if (!length || !format || !put(hwnd, format, png, length + 8) ||
            !check(hwnd, 2, "registered PNG with HGLOBAL padding")) goto cleanup;
        const wchar_t text[] = L"test \x0E44\x0E17\x0E22";
        if (!put(hwnd, CF_UNICODETEXT, text, sizeof(text)) || !check(hwnd, 3, "Unicode text")) goto cleanup;
        if (!check(hwnd, 5, "production Unicode text write/read roundtrip")) goto cleanup;
        dib[12] = 0; // Invalid biPlanes, still bounded native HGLOBAL.
        if (!put(hwnd, CF_DIB, dib, sizeof(dib)) || !check(hwnd, 4, "malformed image rejection")) goto cleanup;
    }
    result = 0;
cleanup:
    if (hwnd) {
        if (OpenClipboard(hwnd)) { EmptyClipboard(); CloseClipboard(); }
        DestroyWindow(hwnd);
    }
    if (original && !SetProcessWindowStation(original)) result = 5;
    if (original_desktop && !SetThreadDesktop(original_desktop)) result = 4;
    if (desktop) CloseDesktop(desktop);
    CloseWindowStation(station);
    if (result) fprintf(stderr, "private clipboard fixture failed=%d win32=%lu\n", result, GetLastError());
    return result;
}
