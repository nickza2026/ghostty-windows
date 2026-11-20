#define UNICODE
#define _UNICODE
#define _WIN32_WINNT 0x0601
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

/* Diagnostic only. Parent must create a private, empty gate directory and
 * validate the candidate hash before invoking this helper. No ETW APIs here. */
static BOOL plain_absolute(const wchar_t *p) {
    wchar_t b[32768]; DWORD a;
    if (!p || wcslen(p) >= 32760 || !((p[0] >= L'A' && p[0] <= L'Z') ||
        (p[0] >= L'a' && p[0] <= L'z')) || p[1] != L':' || p[2] != L'\\') return FALSE;
    if (wcschr(p + 2, L':') || wcschr(p, L'/') || wcschr(p, L'"') ||
        p[wcslen(p)-1] == L'\\') return FALSE;
    if (!GetFullPathNameW(p, 32768, b, NULL) || _wcsicmp(p, b)) return FALSE;
    for (size_t i = 3; ; ++i) {
        if (!b[i] || b[i] == L'\\') {
            wchar_t c = b[i]; b[i] = 0; a = GetFileAttributesW(b); b[i] = c;
            if (a == INVALID_FILE_ATTRIBUTES || (a & FILE_ATTRIBUTE_REPARSE_POINT)) return FALSE;
            if (!c) break;
        }
    }
    return TRUE;
}
static BOOL fresh_write(const wchar_t *p, const char *s) {
    HANDLE h = CreateFileW(p, GENERIC_WRITE, 0, NULL, CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    DWORD n = 0; BOOL ok;
    if (h == INVALID_HANDLE_VALUE) return FALSE;
    ok = WriteFile(h, s, (DWORD)strlen(s), &n, NULL) && n == strlen(s);
    if (!FlushFileBuffers(h)) ok = FALSE;
    if (!CloseHandle(h)) ok = FALSE;
    return ok;
}
static BOOL json_path(const wchar_t *p, char *out, int cap) {
    char u[32768]; int n = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, p, -1, u, sizeof(u), NULL, NULL), j = 0;
    if (!n) return FALSE;
    for (int i = 0; u[i]; ++i) {
        unsigned char c = (unsigned char)u[i];
        if (c < 32 || j + 3 >= cap) return FALSE;
        if (c == '\\' || c == '"') out[j++] = '\\';
        out[j++] = (char)c;
    }
    out[j] = 0; return TRUE;
}
int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show) {
    int argc = 0; wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if(argv&&argc==2&&!wcscmp(argv[1],L"--selftest")) {
        char escaped[128];int result=0;
        if(!json_path(L"C:\\owned\\a.exe",escaped,sizeof(escaped))||strcmp(escaped,"C:\\\\owned\\\\a.exe"))result=1;
        if(json_path(L"invalid\npath",escaped,sizeof(escaped)))result=2;
        if(json_path(L"C:\\owned\\a.exe",escaped,3))result=3;
        LocalFree(argv);return result;
    }
    HANDLE token = NULL, io[3] = {0}; TOKEN_ELEVATION elevation; DWORD size;
    STARTUPINFOEXW si = {0}; PROCESS_INFORMATION pi = {0}; SIZE_T bytes = 0;
    wchar_t identity[32768], request[32768], receipt[32768], image[32768], command[32768];
    char image_json[65536], exe_json[65536], record[140000];
    FILETIME created, exited, kernel, user, published;
    BOOL started = FALSE, resumed = FALSE, child_exited = FALSE, cleanup = FALSE;
    DWORD result = 125, error = 0; ULONGLONG begin = GetTickCount64();
    (void)inst; (void)prev; (void)cmd; (void)show;
    if (!argv || argc != 4 || wcscmp(argv[1], L"--launch")) goto done;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token) ||
        !GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation), &size) || elevation.TokenIsElevated) goto done;
    if (!plain_absolute(argv[2]) || !plain_absolute(argv[3]) ||
        (GetFileAttributesW(argv[2]) & FILE_ATTRIBUTE_DIRECTORY) ||
        !(GetFileAttributesW(argv[3]) & FILE_ATTRIBUTE_DIRECTORY)) goto done;
    if (wcslen(argv[3]) > 32600 || wcslen(argv[2]) > 32600 || wcschr(argv[2], L'"')) goto done;
    swprintf(identity, 32768, L"%ls\\native-identity.json", argv[3]);
    swprintf(request, 32768, L"%ls\\resume.request", argv[3]);
    swprintf(receipt, 32768, L"%ls\\launcher.json", argv[3]);
    { wchar_t pattern[32768]; WIN32_FIND_DATAW fd; HANDLE f;
      swprintf(pattern, 32768, L"%ls\\*", argv[3]);
      f = FindFirstFileW(pattern, &fd);
      if (f == INVALID_HANDLE_VALUE) goto done;
      BOOL empty = TRUE;
      do { if (wcscmp(fd.cFileName,L".") && wcscmp(fd.cFileName,L"..")) empty = FALSE; } while (FindNextFileW(f,&fd));
      FindClose(f); if (!empty) goto done;
    }
    size = 32768;
    if (!QueryFullProcessImageNameW(GetCurrentProcess(), 0, image, &size) ||
        !json_path(image,image_json,sizeof(image_json)) || !json_path(argv[2],exe_json,sizeof(exe_json))) goto done;
    for (int i = 0; i < 3; ++i) {
        HANDLE source = GetStdHandle(i == 0 ? STD_INPUT_HANDLE : i == 1 ? STD_OUTPUT_HANDLE : STD_ERROR_HANDLE);
        if (!source || source == INVALID_HANDLE_VALUE) {
            if (i != 0) goto done;
            source = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
            if (source == INVALID_HANDLE_VALUE) goto done;
            BOOL ok = DuplicateHandle(GetCurrentProcess(), source, GetCurrentProcess(), &io[i], 0, TRUE, DUPLICATE_SAME_ACCESS);
            CloseHandle(source); if (!ok) goto done;
        } else if (!DuplicateHandle(GetCurrentProcess(), source, GetCurrentProcess(), &io[i], 0, TRUE, DUPLICATE_SAME_ACCESS)) goto done;
    }
    InitializeProcThreadAttributeList(NULL,1,0,&bytes);
    si.lpAttributeList = HeapAlloc(GetProcessHeap(),0,bytes);
    if (!si.lpAttributeList) goto done;
    if (!InitializeProcThreadAttributeList(si.lpAttributeList,1,0,&bytes)) { HeapFree(GetProcessHeap(),0,si.lpAttributeList); si.lpAttributeList=NULL; goto done; }
    if (!UpdateProcThreadAttribute(si.lpAttributeList,0,PROC_THREAD_ATTRIBUTE_HANDLE_LIST,io,sizeof(io),NULL,NULL)) goto done;
    si.StartupInfo.cb = sizeof(si); si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    si.StartupInfo.hStdInput=io[0]; si.StartupInfo.hStdOutput=io[1]; si.StartupInfo.hStdError=io[2];
    swprintf(command,32768,L"\"%ls\"",argv[2]);
    if (!CreateProcessW(argv[2],command,NULL,NULL,TRUE,CREATE_SUSPENDED | CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT,NULL,NULL,&si.StartupInfo,&pi)) goto done;
    started=TRUE;
    if (!GetProcessTimes(pi.hProcess,&created,&exited,&kernel,&user)) goto finish;
    snprintf(record,sizeof(record),"{\"native_pid\":%lu,\"native_creation_filetime\":%llu,\"launcher_pid\":%lu,\"launcher_image\":\"%s\",\"native_image\":\"%s\",\"resumed\":false}",pi.dwProcessId,((unsigned long long)created.dwHighDateTime<<32)|created.dwLowDateTime,GetCurrentProcessId(),image_json,exe_json);
    if (!fresh_write(identity,record)) goto finish;
    GetSystemTimeAsFileTime(&published);
    { ULONGLONG gate_start=GetTickCount64(); BOOL ack=FALSE;
      while (GetTickCount64()-gate_start < 5000) {
        HANDLE h=CreateFileW(request,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,NULL);
        if(h!=INVALID_HANDLE_VALUE) {
            BY_HANDLE_FILE_INFORMATION info;
            ack=GetFileInformationByHandle(h,&info) && !(info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY)) && CompareFileTime(&info.ftCreationTime,&published)>=0;
            CloseHandle(h); break;
        }
        Sleep(10);
      }
      if(!ack) goto finish;
    }
    if (ResumeThread(pi.hThread) != 1) goto finish;
    resumed=TRUE; CloseHandle(pi.hThread); pi.hThread=NULL;
    { ULONGLONG elapsed=GetTickCount64()-begin;
      if(WaitForSingleObject(pi.hProcess,elapsed<120000 ? (DWORD)(120000-elapsed):0)!=WAIT_OBJECT_0) goto finish;
    }
    child_exited=TRUE;
    if(!GetExitCodeProcess(pi.hProcess,&result)) result=125;
finish:
    error=GetLastError();
    if(started && !child_exited) {
        cleanup=TerminateProcess(pi.hProcess,125) && WaitForSingleObject(pi.hProcess,5000)==WAIT_OBJECT_0;
        child_exited=WaitForSingleObject(pi.hProcess,0)==WAIT_OBJECT_0;
    }
    snprintf(record,sizeof(record),"{\"started\":%s,\"resumed\":%s,\"child_exited\":%s,\"cleanup\":%s,\"exit_code\":%lu,\"last_error\":%lu,\"readiness_evidence\":false}",started?"true":"false",resumed?"true":"false",child_exited?"true":"false",cleanup?"true":"false",result,error);
    if(!fresh_write(receipt,record)) result=125;
done:
    if(pi.hThread) CloseHandle(pi.hThread);
    if(pi.hProcess) CloseHandle(pi.hProcess);
    if(si.lpAttributeList) { DeleteProcThreadAttributeList(si.lpAttributeList); HeapFree(GetProcessHeap(),0,si.lpAttributeList); }
    for(int i=0;i<3;++i) if(io[i]) CloseHandle(io[i]);
    if(token) CloseHandle(token);
    if(argv) LocalFree(argv);
    return (int)result;
}
