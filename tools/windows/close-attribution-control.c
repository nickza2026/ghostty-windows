/* Private headless debugger-protocol control. No GPU, shell or user data. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdint.h>

__declspec(dllexport) __declspec(noinline)
void localterm_native_htrace_marker(unsigned phase) {
    volatile unsigned observed = phase;
    (void)observed;
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR args, int show) {
    (void)instance; (void)previous; (void)args; (void)show;
    HANDLE events[4] = {0};
    for (unsigned i = 0; i < 4; ++i) {
        events[i] = CreateEventW(NULL, TRUE, FALSE, NULL);
        if (!events[i]) return 10;
        char message[96];
        snprintf(message, sizeof(message), "LC_CONTROL_HANDLE=%llx\n",
                 (unsigned long long)(uintptr_t)events[i]);
        OutputDebugStringA(message);
    }
    localterm_native_htrace_marker(1);
    for (unsigned i = 0; i < 4; ++i) {
        if (!CloseHandle(events[i])) return 11;
    }
    localterm_native_htrace_marker(2);
    return 0;
}
