/* Own-process control experiment: does the existing PSS diagnostic itself
 * retain a worker/handle? No windows, clipboard, GPU or foreign-process access.
 * Link with src/apprt/win32/diagnostics.c. This does not change any smoke gate.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

DWORD localterm_win32_thread_handles(void (*emit)(uintptr_t, DWORD));

static void discard_handle(uintptr_t handle, DWORD id) {
    (void)handle;
    (void)id;
}

static int counts(const char *label, unsigned cycle) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;
    THREADENTRY32 entry = {0};
    entry.dwSize = sizeof(entry);
    DWORD count = 0;
    BOOL more = Thread32First(snapshot, &entry);
    while (more) {
        if (entry.th32OwnerProcessID == GetCurrentProcessId()) ++count;
        entry.dwSize = sizeof(entry);
        more = Thread32Next(snapshot, &entry);
    }
    DWORD status = GetLastError();
    CloseHandle(snapshot);
    if (status != ERROR_NO_MORE_FILES) return 0;
    DWORD handles = 0;
    if (!GetProcessHandleCount(GetCurrentProcess(), &handles)) return 0;
    printf("%s cycle=%u handles=%lu threads=%lu\n", label, cycle,
           (unsigned long)handles, (unsigned long)count);
    fflush(stdout);
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1], "control") && strcmp(argv[1], "snapshot"))) return 2;
    const int capture = !strcmp(argv[1], "snapshot");
    printf("own-process PSS probe mode=%s; no GUI/GPU; thresholds untouched\n", argv[1]);
    fflush(stdout);
    if (!counts("baseline", 0)) return 3;
    for (unsigned i = 0; i < 21; ++i) {
        if (capture) {
            DWORD status = localterm_win32_thread_handles(discard_handle);
            if (status != ERROR_SUCCESS) {
                fprintf(stderr, "PSS failed=%lu\n", (unsigned long)status);
                return 4;
            }
        }
        Sleep(250);
        if (!counts("sample", i)) return 3;
    }
    return counts("final", 21) ? 0 : 3;
}
