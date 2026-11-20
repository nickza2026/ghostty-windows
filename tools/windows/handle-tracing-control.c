/* Private self-only capability test. No debugger, HWND, GPU, shell, or names. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

typedef LONG (NTAPI *SetProcessInfo)(HANDLE, ULONG, void *, ULONG);
typedef LONG (NTAPI *QueryProcessInfo)(HANDLE, ULONG, void *, ULONG, ULONG *);
enum { HandleTracing = 32, TraceOpen = 1, RecordCap = 16 };
typedef struct { HANDLE process, thread; } TraceClient;
typedef struct {
    HANDLE handle;
    TraceClient client;
    ULONG type;
    void *pc[16];
} TraceEntry;
typedef struct {
    HANDLE selected;
    ULONG count;
    TraceEntry entries[RecordCap];
} TraceQuery;
_Static_assert(sizeof(void *) == 8, "x64 control only");
_Static_assert(sizeof(TraceEntry) == 160, "unexpected trace entry ABI");
_Static_assert(offsetof(TraceQuery, entries) == 16, "unexpected trace query ABI");

typedef struct { uintptr_t begin, end; } CreatorRange;

__declspec(noinline) static HANDLE make_event(void) {
    volatile HANDLE result = CreateEventW(NULL, TRUE, FALSE, NULL);
    return result;
}
static DWORD WINAPI wait_for_stop(void *event) {
    return WaitForSingleObject((HANDLE)event, 5000) == WAIT_OBJECT_0 ? 0 : 1;
}
__declspec(noinline) static HANDLE make_thread(HANDLE event, DWORD *tid) {
    volatile HANDLE result = CreateThread(NULL, 0, wait_for_stop, event, 0, tid);
    return result;
}
__declspec(noinline) static HANDLE duplicate_current(void) {
    HANDLE result = NULL;
    if (!DuplicateHandle(GetCurrentProcess(), GetCurrentThread(),
                         GetCurrentProcess(), &result, 0, FALSE,
                         DUPLICATE_SAME_ACCESS)) return NULL;
    return result;
}
static CreatorRange creator_range(void *function) {
    DWORD64 image = 0;
    PRUNTIME_FUNCTION entry = RtlLookupFunctionEntry((DWORD64)(uintptr_t)function,
                                                    &image, NULL);
    CreatorRange result = {0, 0};
    if (entry) {
        result.begin = (uintptr_t)image + entry->BeginAddress;
        result.end = (uintptr_t)image + entry->EndAddress;
    }
    return result;
}
static int query_known(QueryProcessInfo query, HANDLE handle, const char *role,
                       CreatorRange creator, DWORD target) {
    TraceQuery data = {0};
    data.selected = handle;
    ULONG returned = 0;
    LONG status = query(GetCurrentProcess(), HandleTracing, &data,
                        (ULONG)sizeof(data), &returned);
    printf("{\"kind\":\"query\",\"role\":\"%s\",\"handle\":\"%p\","
           "\"status\":\"%08lx\",\"returned\":%lu,\"count\":%lu,"
           "\"target_tid\":%lu,\"creator_begin\":\"%llx\",\"creator_end\":\"%llx\"}\n",
           role, (void *)handle, (unsigned long)status, returned, data.count,
           target, (unsigned long long)creator.begin, (unsigned long long)creator.end);
    /* ReturnLength is optional/version-sensitive. Never infer record bounds
       from it: count must fit the actual fixed input buffer as well. */
    if (status < 0 || returned > sizeof(data) || data.count > RecordCap) return 0;
    int known_caller = 0, matching_open = 0;
    for (ULONG i = 0; i < data.count; ++i) {
        TraceEntry *entry = &data.entries[i];
        int match = entry->handle == handle && entry->type == TraceOpen &&
                    (uintptr_t)entry->client.process == GetCurrentProcessId() &&
                    (uintptr_t)entry->client.thread == GetCurrentThreadId();
        matching_open |= match;
        printf("{\"kind\":\"trace\",\"role\":\"%s\",\"handle\":\"%p\","
               "\"pid\":%llu,\"tid\":%llu,\"type\":%lu,\"pc\":[",
               role, (void *)entry->handle,
               (unsigned long long)(uintptr_t)entry->client.process,
               (unsigned long long)(uintptr_t)entry->client.thread, entry->type);
        for (unsigned j = 0; j < 16; ++j) {
            uintptr_t pc = (uintptr_t)entry->pc[j];
            printf("%s\"%llx\"", j ? "," : "", (unsigned long long)pc);
            if (match && pc >= creator.begin && pc < creator.end) known_caller = 1;
        }
        printf("]}\n");
    }
    printf("{\"kind\":\"qualification\",\"role\":\"%s\","
           "\"matching_open\":%s,\"known_creator_pc\":%s}\n", role,
           matching_open ? "true" : "false", known_caller ? "true" : "false");
    return matching_open && known_caller;
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR args, int show) {
    (void)instance; (void)previous; (void)args; (void)show;
    setvbuf(stdout, NULL, _IONBF, 0);
    HANDLE event = NULL, thread = NULL, duplicate = NULL;
    int qualified = 0, enabled = 0, cleanup_ok = 1;
    DWORD tid = 0;
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    SetProcessInfo set = (SetProcessInfo)(uintptr_t)GetProcAddress(ntdll, "NtSetInformationProcess");
    QueryProcessInfo query = (QueryProcessInfo)(uintptr_t)GetProcAddress(ntdll, "NtQueryInformationProcess");
    CreatorRange ranges[3] = {creator_range((void *)make_event),
        creator_range((void *)make_thread), creator_range((void *)duplicate_current)};
    MODULEINFO image = {0};
    if (!GetModuleInformation(GetCurrentProcess(), GetModuleHandleW(NULL), &image, sizeof(image))) return 10;
    printf("{\"kind\":\"control\",\"pid\":%lu,\"tid\":%lu,\"console\":%s,"
           "\"entry_size\":%u,\"entry_offset\":%u,\"record_cap\":%u,"
           "\"image_begin\":\"%llx\",\"image_size\":%lu}\n",
           GetCurrentProcessId(), GetCurrentThreadId(), GetConsoleWindow() ? "true" : "false",
           (unsigned)sizeof(TraceEntry), (unsigned)offsetof(TraceQuery, entries), RecordCap,
           (unsigned long long)(uintptr_t)image.lpBaseOfDll, image.SizeOfImage);
    if (!set || !query || GetConsoleWindow()) goto cleanup;
    for (unsigned i = 0; i < 3; ++i) if (!ranges[i].begin || ranges[i].end <= ranges[i].begin) goto cleanup;
    ULONG flags = 0;
    LONG status = set(GetCurrentProcess(), HandleTracing, &flags, sizeof(flags));
    printf("{\"kind\":\"enable\",\"status\":\"%08lx\"}\n", (unsigned long)status);
    if (status < 0) goto cleanup;
    enabled = 1;
    event = make_event();
    if (!event) goto cleanup;
    thread = make_thread(event, &tid);
    if (!thread) goto cleanup;
    duplicate = duplicate_current();
    if (!duplicate) goto cleanup;
    /* Query all three once even when one has no PCs. No retries or cap growth. */
    int a = query_known(query, event, "event", ranges[0], 0);
    int b = query_known(query, thread, "thread", ranges[1], tid);
    int c = query_known(query, duplicate, "duplicate", ranges[2], GetCurrentThreadId());
    qualified = a && b && c;
cleanup:
    if (thread) {
        if (!SetEvent(event) || WaitForSingleObject(thread, 5000) != WAIT_OBJECT_0) cleanup_ok = 0;
        DWORD exit_code = 1;
        if (!GetExitCodeThread(thread, &exit_code) || exit_code != 0) cleanup_ok = 0;
        if (!CloseHandle(thread)) cleanup_ok = 0;
    }
    if (duplicate && !CloseHandle(duplicate)) cleanup_ok = 0;
    if (event && !CloseHandle(event)) cleanup_ok = 0;
    LONG disabled = enabled ? set(GetCurrentProcess(), HandleTracing, NULL, 0) : 0;
    if (disabled < 0) cleanup_ok = 0;
    printf("{\"kind\":\"result\",\"qualified\":%s,\"cleanup_ok\":%s,"
           "\"disable_status\":\"%08lx\",\"application_gate_pass\":false}\n",
           qualified ? "true" : "false", cleanup_ok ? "true" : "false", (unsigned long)disabled);
    return qualified && cleanup_ok ? 0 : 20;
}
