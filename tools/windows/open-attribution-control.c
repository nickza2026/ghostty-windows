/* Private no-HWND control; all published handles survive the final marker. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
__declspec(dllexport) __declspec(noinline)
void localterm_native_htrace_marker(unsigned phase) {
    volatile unsigned observed = phase; (void)observed;
}
static DWORD WINAPI private_thread(void *arg) { (void)arg; return 0; }
static void publish(const char *api, HANDLE handle) {
    char message[128];
    snprintf(message, sizeof(message), "LO_EXPECT api=%s handle=%llx\n",
             api, (unsigned long long)(uintptr_t)handle);
    OutputDebugStringA(message);
}
int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR args, int show) {
    (void)instance; (void)previous; (void)args; (void)show;
    localterm_native_htrace_marker(1);
    HANDLE event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!event) return 10;
    publish("CreateEventW", event);
    HANDLE duplicate = NULL;
    if (!DuplicateHandle(GetCurrentProcess(), GetCurrentThread(),
                         GetCurrentProcess(), &duplicate, 0, FALSE,
                         DUPLICATE_SAME_ACCESS)) { CloseHandle(event); return 11; }
    publish("DuplicateHandle", duplicate);
    HANDLE thread = CreateThread(NULL, 0, private_thread, NULL, 0, NULL);
    if (!thread) { CloseHandle(duplicate); CloseHandle(event); return 12; }
    publish("CreateThread", thread);
    if (WaitForSingleObject(thread, 5000) != WAIT_OBJECT_0) return 13;
    localterm_native_htrace_marker(2);
    BOOL ok = CloseHandle(thread);
    ok = CloseHandle(duplicate) && ok;
    ok = CloseHandle(event) && ok;
    return ok ? 0 : 14;
}
