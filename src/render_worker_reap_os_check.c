/* Private CPU-only real Windows process/job integration. No HWND/WGL/driver,
 * transport packets, arbitrary PID input, profile execution or shell launch.
 * close_ack is synthetic: this is reap/cleanup coverage, NOT ACK wire proof. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <wchar.h>
#include "render_worker_client.c"

typedef struct CheckChild {
    RwClient *client;
    HANDLE ready, release, observer;
} CheckChild;
static void checkpoint(const char *phase) {
    DWORD handles = 0;
    if (GetProcessHandleCount(GetCurrentProcess(), &handles))
        fprintf(stderr, "CPU_OS_STAGE phase=%s handles=%lu\n", phase, (unsigned long)handles);
}
static int is_raw_control(const char *args) {
    static const char flag[] = "--raw-close-control";
    while (isspace((unsigned char)*args)) ++args;
    if (strncmp(args, flag, sizeof(flag)-1) != 0) return 0;
    args += sizeof(flag)-1;
    while (isspace((unsigned char)*args)) ++args;
    return *args == 0;
}
static int start_child(CheckChild *out, DWORD code) {
    SECURITY_ATTRIBUTES sa = { sizeof(sa), NULL, TRUE };
    STARTUPINFOEXW si = {0}; PROCESS_INFORMATION pi = {0};
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limit = {0};
    wchar_t exe[32768], command[33000]; SIZE_T bytes = 0;
    HANDLE allowed[2]; int initialized = 0, ok = 0;
    memset(out, 0, sizeof(*out));
    out->client = (RwClient *)calloc(1, sizeof(RwClient));
    if (!out->client) goto done;
    out->ready = CreateEventW(&sa, TRUE, FALSE, NULL);
    out->release = CreateEventW(&sa, TRUE, FALSE, NULL);
    out->client->job = CreateJobObjectW(NULL, NULL);
    limit.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!out->ready || !out->release || !out->client->job ||
        !SetInformationJobObject(out->client->job, JobObjectExtendedLimitInformation,
                                 &limit, sizeof(limit))) goto done;
    checkpoint("created-events-and-job");
    allowed[0] = out->ready; allowed[1] = out->release;
    si.StartupInfo.cb = sizeof(si);
    InitializeProcThreadAttributeList(NULL, 1, 0, &bytes);
    si.lpAttributeList = (LPPROC_THREAD_ATTRIBUTE_LIST)calloc(1, bytes);
    if (!si.lpAttributeList || !InitializeProcThreadAttributeList(si.lpAttributeList, 1, 0, &bytes)) goto done;
    initialized = 1;
    if (!UpdateProcThreadAttribute(si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                   allowed, sizeof(allowed), NULL, NULL)) goto done;
    DWORD length = GetModuleFileNameW(NULL, exe, _countof(exe));
    if (!length || length >= _countof(exe)) goto done;
    if (_snwprintf_s(command, _countof(command), _TRUNCATE,
                    L"\"%ls\" --reap-child %llx %llx %lu", exe,
                    (unsigned long long)(uintptr_t)out->ready,
                    (unsigned long long)(uintptr_t)out->release, (unsigned long)code) < 0) goto done;
    if (!CreateProcessW(exe, command, NULL, NULL, TRUE,
                        CREATE_SUSPENDED | CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT,
                        NULL, NULL, &si.StartupInfo, &pi)) goto done;
    out->client->process = pi.hProcess;
    checkpoint("created-suspended-child");
    if (!DuplicateHandle(GetCurrentProcess(), pi.hProcess, GetCurrentProcess(),
                         &out->observer, SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, 0)) goto done;
    checkpoint("duplicated-owned-observer");
    if (!AssignProcessToJobObject(out->client->job, pi.hProcess)) goto done;
    out->client->assigned = 1;
    checkpoint("assigned-private-job");
    if (ResumeThread(pi.hThread) != 1) goto done;
    if (WaitForSingleObject(out->ready, 5000) != WAIT_OBJECT_0) goto done;
    checkpoint("child-ready");
    out->client->close_ack = 1; /* Synthetic precondition, no transport claim. */
    ok = 1;
done:
    if (initialized) DeleteProcThreadAttributeList(si.lpAttributeList);
    free(si.lpAttributeList); drop(&pi.hThread);
    checkpoint("startup-attributes-and-thread-closed");
    if (!ok && out->client) {
        RwStatus status = {0};
        int destroyed = rw_destroy(out->client, 5000, &status); out->client = NULL;
        int observed = out->observer ? WaitForSingleObject(out->observer, 5000) == WAIT_OBJECT_0 : status.process_exited;
        fprintf(stderr, "CPU_OS_STARTUP_FAILURE destroy=%d observer_exit=%d process_exited=%d job_empty=%d forced=%d\n",
                destroyed, observed, status.process_exited, status.job_empty, status.forced);
        drop(&out->ready); drop(&out->release); drop(&out->observer);
    }
    return ok;
}
static int run_case(int kind) {
    CheckChild child; RwStatus status = {0}; DWORD before = 0, after = 0;
    int finish, destroyed, observed, correct; ULONGLONG started;
    if (!GetProcessHandleCount(GetCurrentProcess(), &before) || !start_child(&child, kind == 1 ? 77 : 0)) return 0;
    status.close_ack = 1;
    if (kind != 2 && !SetEvent(child.release)) {
        int destroyed = rw_destroy(child.client, 5000, &status);
        int observed = WaitForSingleObject(child.observer, 5000) == WAIT_OBJECT_0;
        fprintf(stderr, "CPU_OS_RELEASE_FAILURE destroy=%d observer_exit=%d process_exited=%d job_empty=%d forced=%d\n",
                destroyed, observed, status.process_exited, status.job_empty, status.forced);
        drop(&child.ready); drop(&child.release); drop(&child.observer); return 0;
    }
    started = GetTickCount64();
    if (kind == 3) {
        /* Cold Win32 control: neither production finish nor destroy is called.
         * This isolates launch-time global growth without warming it away. */
        DWORD code = STILL_ACTIVE;
        finish = WaitForSingleObject(child.client->process, 5000) == WAIT_OBJECT_0 &&
            GetExitCodeProcess(child.client->process, &code);
        status.process_exited = finish; status.child_exit = code;
        JOBOBJECT_BASIC_ACCOUNTING_INFORMATION info = {0};
        status.job_empty = QueryInformationJobObject(child.client->job,
            JobObjectBasicAccountingInformation, &info, sizeof(info), NULL) && info.ActiveProcesses == 0;
    } else finish = rw_finish(child.client, 50, &status);
    checkpoint(kind == 3 ? "manual-wait-returned" : "production-finish-returned");
    ULONGLONG elapsed = GetTickCount64() - started;
    if (kind == 0 || kind == 3) correct = finish && status.process_exited && status.child_exit == 0 && status.job_empty && !status.forced;
    else if (kind == 1) correct = !finish && status.process_exited && status.child_exit == 77 && status.job_empty;
    else correct = !finish && status.close_ack && !status.process_exited && !status.job_empty && !status.forced;
    if (kind == 3) {
        destroyed = 1;
        if (!status.process_exited) {
            status.forced = 1;
            destroyed = TerminateJobObject(child.client->job, 1) &&
                WaitForSingleObject(child.client->process, 5000) == WAIT_OBJECT_0;
        }
        destroyed = CloseHandle(child.client->process) && destroyed;
        destroyed = CloseHandle(child.client->job) && destroyed;
        free(child.client);
    } else destroyed = rw_destroy(child.client, 5000, &status);
    child.client = NULL;
    checkpoint(kind == 3 ? "manual-handles-closed" : "production-destroy-returned");
    observed = WaitForSingleObject(child.observer, 5000) == WAIT_OBJECT_0;
    drop(&child.ready); drop(&child.release); drop(&child.observer);
    checkpoint("fixture-handles-closed");
    if (!GetProcessHandleCount(GetCurrentProcess(), &after)) return 0;
    correct = correct && destroyed && observed && status.process_exited && status.job_empty &&
        status.forced == (kind == 1 || kind == 2) && before == after;
    printf("%s real-cpu-job kind=%d finish=%d elapsed_ms=%llu ack=%d exited=%d child=%lu job_empty=%d forced=%d destroy=%d observer_exit=%d handles=%lu->%lu synthetic_ack=1\n",
           correct ? "PASS" : "FAIL", kind, finish, (unsigned long long)elapsed,
           status.close_ack, status.process_exited, (unsigned long)status.child_exit,
           status.job_empty, status.forced, destroyed, observed, (unsigned long)before, (unsigned long)after);
    return correct;
}
int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR args, int show) {
    (void)instance; (void)previous; (void)show;
    unsigned long long ready_value, release_value; unsigned long code;
    if (sscanf(args, "--reap-child %llx %llx %lu", &ready_value, &release_value, &code) == 3) {
        HANDLE ready = (HANDLE)(uintptr_t)ready_value, release = (HANDLE)(uintptr_t)release_value;
        if (!SetEvent(ready)) return 90;
        DWORD wait = WaitForSingleObject(release, 5000);
        CloseHandle(ready); CloseHandle(release);
        return wait == WAIT_OBJECT_0 ? (int)code : 91;
    }
    printf("CPU-only process/job cleanup integration begin; no GPU/transport readiness claim\n");
    fflush(stdout);
    if (is_raw_control(args)) {
        printf("COLD_WIN32_CONTROL production_finish_destroy_not_called=1 global_count_gate_retained=1\n");
        return run_case(3) ? 0 : 1;
    }
    int passed = 0;
    for (int i = 0; i < 3; ++i) { if (!run_case(i)) return 1; ++passed; }
    printf("CPU_OS_REAP_RESULT cases=%d failed=0 historical_gpu_failures_resolved=0\n", passed);
    return 0;
}
