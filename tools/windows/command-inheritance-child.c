#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>

/* Private console protocol peer. No shell, files, descendants, or handle probes. */
static int output(const char *text) {
    DWORD written = 0;
    DWORD size = (DWORD)strlen(text);
    return WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), text, size, &written, NULL)
        && written == size;
}

int main(void) {
    HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    DWORD mode;
    if (!GetConsoleMode(input, &mode)) return 10;
    if (!SetConsoleMode(input, mode & ~(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT))) return 11;
    if (!output("READY\r\n")) return 12;
    const ULONGLONG deadline = GetTickCount64() + 5000;
    char line[32];
    unsigned used = 0;
    for (;;) {
        ULONGLONG now = GetTickCount64();
        if (now >= deadline) return 13;
        if (WaitForSingleObject(input, (DWORD)(deadline - now)) != WAIT_OBJECT_0) return 14;
        INPUT_RECORD record;
        DWORD count;
        if (!ReadConsoleInputW(input, &record, 1, &count) || count != 1) return 15;
        if (record.EventType != KEY_EVENT || !record.Event.KeyEvent.bKeyDown) continue;
        WCHAR ch = record.Event.KeyEvent.uChar.UnicodeChar;
        if (!ch) continue;
        if (ch == L'\r' || ch == L'\n') break;
        if (ch > 127 || used == sizeof(line) - 1) return 16;
        line[used++] = (char)ch;
    }
    line[used] = 0;
    if (strcmp(line, "CANARY-PING")) return 17;
    return output("ACK:CANARY-PING\r\n") ? 0 : 18;
}
