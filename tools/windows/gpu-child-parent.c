// Component PoC only. No OpenGL imports and no production renderer integration.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

typedef struct { DWORD handles, gdi, user, threads; } Counts;
static int counter_negative = 0;
static int gui_count(DWORD flag, DWORD *value) {
    SetLastError(ERROR_SUCCESS);
    if (counter_negative) { *value = 0; SetLastError(ERROR_INVALID_HANDLE); }
    else *value = GetGuiResources(GetCurrentProcess(), flag);
    if (*value == 0 && GetLastError() != ERROR_SUCCESS) {
        fprintf(stderr, "FAIL GUI counter error=%lu\n", GetLastError()); return 0;
    }
    return 1;
}
static int counts(Counts *c) {
    HANDLE s; THREADENTRY32 t = {0}; DWORD own = GetCurrentProcessId();
    if (!gui_count(0, &c->gdi) || !gui_count(1, &c->user)) return 0;
    c->threads = 0;
    s = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (s == INVALID_HANDLE_VALUE) return 0;
    t.dwSize = sizeof(t);
    if (!Thread32First(s, &t)) { CloseHandle(s); return 0; }
    do { if (t.th32OwnerProcessID == own) ++c->threads; t.dwSize = sizeof(t); }
    while (Thread32Next(s, &t));
    DWORD e = GetLastError(); CloseHandle(s);
    return e == ERROR_NO_MORE_FILES && GetProcessHandleCount(GetCurrentProcess(), &c->handles);
}
static int no_gpu_modules(void) {
    return !GetModuleHandleW(L"opengl32.dll") && !GetModuleHandleW(L"atio6axx.dll") &&
           !GetModuleHandleW(L"amdihk64.dll");
}
static int gate(Counts b, int cycle) {
    Counts f;
    if (!counts(&f) || !no_gpu_modules()) return 0;
    printf("PARENT cycle=%d handles=%lu GDI=%lu USER=%lu threads=%lu\n",
           cycle, f.handles, f.gdi, f.user, f.threads);
    return f.handles <= b.handles && f.gdi <= b.gdi && f.user <= b.user && f.threads <= b.threads;
}
static int receipt(const wchar_t *path, DWORD pid, DWORD hold) {
    FILE *f = NULL; char *data = NULL; long size; char token[160]; int ok = 0;
    if (_wfopen_s(&f, path, L"rb") || !f) return 0;
    if (fseek(f, 0, SEEK_END) || (size = ftell(f)) < 0 || size > 1024*1024 ||
        fseek(f, 0, SEEK_SET)) goto end;
    data = (char *)calloc((size_t)size+1, 1);
    if (!data || fread(data, 1, (size_t)size, f) != (size_t)size) goto end;
    sprintf_s(token, sizeof(token), "GPU_CHILD_OK pid=%lu draws=3 rgba=16/16 hidden_noactivate=1 hold_ms=%lu", pid, hold);
    ok = strstr(data, token) != NULL;
end:
    free(data); fclose(f); return ok;
}
static int child(const wchar_t *exe, const wchar_t *logs, int index, const wchar_t *mode) {
    HANDLE job = NULL, out = INVALID_HANDLE_VALUE, in = INVALID_HANDLE_VALUE;
    STARTUPINFOEXW si = {0}; PROCESS_INFORMATION pi = {0};
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION lim = {0};
    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION acct = {0};
    SECURITY_ATTRIBUTES sa = {sizeof(sa), NULL, TRUE};
    wchar_t path[4096], cmd[4096]; SIZE_T bytes = 0; DWORD exit = ~0u; int ok = 0, assigned = 0, attrs = 0;
    _snwprintf_s(path, _countof(path), _TRUNCATE, L"%s\\child-%02d.log", logs, index);
    _snwprintf_s(cmd, _countof(cmd), _TRUNCATE, L"\"%s\"", exe);
    if (!SetEnvironmentVariableW(L"LOCALTERM_GL_CHILD_CONTROL", L"1")) goto done;
    if (mode) {
        if (!SetEnvironmentVariableW(L"LOCALTERM_GL_CHILD_NEGATIVE", mode)) goto done;
    } else {
        SetEnvironmentVariableW(L"LOCALTERM_GL_CHILD_NEGATIVE", NULL);
    }
    SetEnvironmentVariableW(L"LOCALTERM_GL_PACED_CONTROL", NULL);
    SetEnvironmentVariableW(L"LOCALTERM_GL_HTRACE_CONTROL", NULL);
    job = CreateJobObjectW(NULL, NULL);
    lim.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &lim, sizeof(lim))) goto done;
    out = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, &sa, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    in = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ|FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
    if (out == INVALID_HANDLE_VALUE || in == INVALID_HANDLE_VALUE) goto done;
    InitializeProcThreadAttributeList(NULL, 1, 0, &bytes);
    if (!bytes) goto done;
    si.lpAttributeList = (LPPROC_THREAD_ATTRIBUTE_LIST)HeapAlloc(GetProcessHeap(), 0, bytes);
    if (!si.lpAttributeList || !InitializeProcThreadAttributeList(si.lpAttributeList, 1, 0, &bytes)) goto done;
    attrs = 1;
    HANDLE allowed[2] = {out, in};
    if (!UpdateProcThreadAttribute(si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                  allowed, sizeof(allowed), NULL, NULL)) goto done;
    si.StartupInfo.cb = sizeof(si); si.StartupInfo.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.StartupInfo.wShowWindow = SW_HIDE; si.StartupInfo.hStdOutput = out;
    si.StartupInfo.hStdError = out; si.StartupInfo.hStdInput = in;
    ULONGLONG started = GetTickCount64();
    if (!CreateProcessW(exe, cmd, NULL, NULL, TRUE,
                        CREATE_SUSPENDED|CREATE_NO_WINDOW|EXTENDED_STARTUPINFO_PRESENT,
                        NULL, NULL, &si.StartupInfo, &pi)) {
        fprintf(stderr, "FAIL child launch winerr=%lu\n", GetLastError()); goto done;
    }
    if (!AssignProcessToJobObject(job, pi.hProcess)) goto done;
    assigned = 1;
    // The suspended child already inherited its own copies. Do not retain a
    // parent writer while the receipt reader uses CRT secure sharing rules.
    CloseHandle(out); out = INVALID_HANDLE_VALUE;
    CloseHandle(in); in = INVALID_HANDLE_VALUE;
    if (ResumeThread(pi.hThread) == (DWORD)-1) goto done;
    ULONGLONG elapsed = GetTickCount64()-started;
    if (elapsed >= 30000 || WaitForSingleObject(pi.hProcess, (DWORD)(30000-elapsed)) != WAIT_OBJECT_0) {
        fprintf(stderr, "FAIL owned child deadline index=%d pid=%lu\n", index, pi.dwProcessId); goto done;
    }
    if (!GetExitCodeProcess(pi.hProcess, &exit) || exit != 0) goto done;
    if (!QueryInformationJobObject(job, JobObjectBasicAccountingInformation, &acct, sizeof(acct), NULL) ||
        acct.ActiveProcesses != 0) { fprintf(stderr, "FAIL owned descendants remain\n"); goto done; }
    DWORD hold = mode && !wcscmp(mode, L"long") ? 15000 : 3000;
    if (GetTickCount64()-started < hold || !receipt(path, pi.dwProcessId, hold)) { fprintf(stderr, "FAIL child receipt missing/invalid\n"); goto done; }
    printf("CHILD_OK index=%d pid=%lu exit=0 active_job_processes=0\n", index, pi.dwProcessId); ok = 1;
done:
    if (!ok) {
        fprintf(stderr, "CHILD_FAIL index=%d exit=%lu winerr=%lu\n", index, exit, GetLastError());
        // Only our new suspended/job-owned child, never another application.
        if (pi.hProcess) {
            if (assigned) TerminateJobObject(job, 99); else TerminateProcess(pi.hProcess, 99);
            if (WaitForSingleObject(pi.hProcess, 5000) == WAIT_OBJECT_0 &&
                (!assigned || (QueryInformationJobObject(job, JobObjectBasicAccountingInformation, &acct, sizeof(acct), NULL) && acct.ActiveProcesses == 0)))
                fprintf(stderr, "OWNED_CLEANUP_OK index=%d\n", index);
        } else {
            fprintf(stderr, "OWNED_CLEANUP_OK index=%d no_child_created=1\n", index);
        }
    }
    if (pi.hThread) CloseHandle(pi.hThread);
    if (pi.hProcess) CloseHandle(pi.hProcess);
    if (attrs) DeleteProcThreadAttributeList(si.lpAttributeList);
    if (si.lpAttributeList) HeapFree(GetProcessHeap(), 0, si.lpAttributeList);
    if (in != INVALID_HANDLE_VALUE) CloseHandle(in);
    if (out != INVALID_HANDLE_VALUE) CloseHandle(out);
    if (job) CloseHandle(job);
    return ok;
}
int wmain(int argc, wchar_t **argv) {
    Counts baseline = {0};
    int baseline_ready = 0;
    if (argc != 4 || !no_gpu_modules()) return 2;
    if (!wcscmp(argv[3], L"counter-error")) {
        Counts invalid;
        counter_negative = 1; // Explicit counter-API failure injection, no child.
        if (counts(&invalid)) return 0;
        fprintf(stderr, "OWNED_CLEANUP_OK no_child_created=1\n"); return 1;
    }
    if (wcscmp(argv[3], L"positive")) {
        // Negative controls return a real failure; caller must not count it as a gate pass.
        if (wcscmp(argv[3], L"missing-receipt") && wcscmp(argv[3], L"bad-pixels") && wcscmp(argv[3], L"hang")) return 2;
        return child(argv[1], argv[2], 0, argv[3]) ? 0 : 1;
    }
    for (int i=0; i<21; ++i) {
        if (!child(argv[1], argv[2], i, NULL)) return 1;
        if (i == 0) {
            if (!counts(&baseline) || !no_gpu_modules()) return 1;
            baseline_ready = 1;
            printf("BASELINE handles=%lu GDI=%lu USER=%lu threads=%lu\n", baseline.handles, baseline.gdi, baseline.user, baseline.threads);
        } else if (!baseline_ready || !gate(baseline, i)) return 1;
    }
    // Long-lived child is separate coverage AFTER all 20 cycles, not a new baseline.
    if (!baseline_ready || !child(argv[1], argv[2], 21, L"long") || !gate(baseline, 21)) return 1;
    printf("GPU_CHILD_POC_PASS warmup=1 cycles=20 long_controls=1 parent_gpu_modules=0 children_exited=22\n");
    return 0;
}
