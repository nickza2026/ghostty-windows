/* Approved disposable ETW qualification only. Never attaches to the terminal.
 * SystemObject GUID/keyword: SDK26100 evntrace.h + Microsoft System Providers.
 * Classic class/opcodes: microsoft/perfview KernelTraceEventParser.cs,
 * SHA256 2245CCC62B0D933190068A18344BC64749A2893BD9740A79706BA7FE5E86C778.
 * Session is unique, capped, file-only, and owned by the caller's supplied GUID.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <evntrace.h>
#include <shellapi.h>
#include <objbase.h>
#include <psapi.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <wchar.h>

static const GUID object_provider = {0xfebd7460,0x3d1d,0x47eb,{0xaf,0x49,0xc9,0xee,0xb1,0xe1,0x46,0xf2}};
static const GUID object_class = {0x89497f50,0xeffe,0x4440,{0x8c,0xf2,0xce,0x6b,0x1c,0xdc,0xac,0xa7}};
typedef struct {
    EVENT_TRACE_PROPERTIES p;
    wchar_t name[160];
    wchar_t file[MAX_PATH];
} Properties;
typedef struct { uintptr_t begin, end; } Range;
_Static_assert(sizeof(CLASSIC_EVENT_ID)==24,"Unexpected ETW stack selector ABI");
static FILE *report;

static int path(wchar_t *out, const wchar_t *dir, const wchar_t *leaf) {
    return _snwprintf_s(out, MAX_PATH, _TRUNCATE, L"%s\\%s", dir, leaf) >= 0;
}
static void status(const char *operation, ULONG code) {
    fprintf(report,"{\"kind\":\"status\",\"operation\":\"%s\",\"code\":%lu}\n",operation,code);
    fflush(report);
}
static Range range(void *function) {
    DWORD64 image=0;
    PRUNTIME_FUNCTION f=RtlLookupFunctionEntry((DWORD64)(uintptr_t)function,&image,NULL);
    Range r={0,0};
    if(f){r.begin=(uintptr_t)image+f->BeginAddress;r.end=(uintptr_t)image+f->EndAddress;}
    return r;
}
__declspec(noinline) static HANDLE create_a(void) {
    volatile HANDLE h=CreateEventW(NULL,TRUE,FALSE,NULL);return h;
}
__declspec(noinline) static HANDLE create_b(void) {
    volatile HANDLE h=CreateEventW(NULL,TRUE,FALSE,NULL);return h;
}
__declspec(noinline) static HANDLE duplicate_to(HANDLE source,HANDLE target) {
    HANDLE h=NULL;
    if(!DuplicateHandle(GetCurrentProcess(),source,target,&h,0,FALSE,DUPLICATE_SAME_ACCESS))return NULL;
    return h;
}
__declspec(noinline) static BOOL close_owned(HANDLE h) {
    volatile BOOL result=CloseHandle(h);return result;
}
static void record(const char *operation,HANDLE h,void *caller,DWORD source,DWORD target,HANDLE other) {
    Range r=range(caller);
    fprintf(report,"{\"kind\":\"expected\",\"operation\":\"%s\",\"pid\":%lu,\"tid\":%lu,\"handle\":\"%llx\",\"other_handle\":\"%llx\",\"source_pid\":%lu,\"target_pid\":%lu,\"caller_begin\":\"%llx\",\"caller_end\":\"%llx\"}\n",
        operation,GetCurrentProcessId(),GetCurrentThreadId(),(unsigned long long)(uintptr_t)h,
        (unsigned long long)(uintptr_t)other,source,target,(unsigned long long)r.begin,(unsigned long long)r.end);
    fflush(report);
}
static int child(const wchar_t *dir) {
    wchar_t output[MAX_PATH],gate[MAX_PATH];
    if(!path(output,dir,L"child.jsonl")||!path(gate,dir,L"child-handle.txt"))return 40;
    if(_wfopen_s(&report,output,L"wb"))return 41;
    FILE *input=NULL;unsigned long long raw=0;
    if(_wfopen_s(&input,gate,L"rb")){fclose(report);return 42;}
    int read=fscanf(input,"%llx",&raw);fclose(input);
    if(read!=1||!raw){fclose(report);return 43;}
    HANDLE remote=(HANDLE)(uintptr_t)raw;
    HANDLE own=create_b();
    if(!own){fclose(report);return 44;}
    record("create_child",own,(void*)create_b,0,GetCurrentProcessId(),NULL);
    int ok=SetEvent(remote)!=0;
    record("close_remote",remote,(void*)close_owned,0,GetCurrentProcessId(),NULL);
    ok=close_owned(remote)&&ok;
    record("close_child",own,(void*)close_owned,0,GetCurrentProcessId(),NULL);
    ok=close_owned(own)&&ok;
    fprintf(report,"{\"kind\":\"child_result\",\"ok\":%s,\"pid\":%lu}\n",ok?"true":"false",GetCurrentProcessId());
    fclose(report);return ok?0:45;
}
static void properties(Properties *p,const wchar_t *name,const wchar_t *file,const GUID *guid) {
    ZeroMemory(p,sizeof(*p));
    p->p.Wnode.BufferSize=sizeof(*p);p->p.Wnode.Flags=WNODE_FLAG_TRACED_GUID;
    p->p.Wnode.ClientContext=1;p->p.Wnode.Guid=*guid;
    p->p.BufferSize=64;p->p.MinimumBuffers=4;p->p.MaximumBuffers=64;
    p->p.MaximumFileSize=32;p->p.FlushTimer=1;
    p->p.LogFileMode=EVENT_TRACE_SYSTEM_LOGGER_MODE|EVENT_TRACE_FILE_MODE_SEQUENTIAL;
    p->p.LoggerNameOffset=offsetof(Properties,name);p->p.LogFileNameOffset=offsetof(Properties,file);
    wcscpy_s(p->name,160,name);if(file)wcscpy_s(p->file,MAX_PATH,file);
}
static int stop_own(const wchar_t *name,const GUID *guid) {
    HANDLE token=NULL;TOKEN_PRIVILEGES wanted={0},previous={0};DWORD size=sizeof(previous);int changed=0;
    if(OpenProcessToken(GetCurrentProcess(),TOKEN_ADJUST_PRIVILEGES|TOKEN_QUERY,&token)) {
        wanted.PrivilegeCount=1;
        if(LookupPrivilegeValueW(NULL,L"SeSystemProfilePrivilege",&wanted.Privileges[0].Luid)) {
            wanted.Privileges[0].Attributes=SE_PRIVILEGE_ENABLED;SetLastError(ERROR_SUCCESS);
            changed=AdjustTokenPrivileges(token,FALSE,&wanted,sizeof(previous),&previous,&size)&&GetLastError()==ERROR_SUCCESS;
        }
    }
    Properties p;properties(&p,name,NULL,guid);
    ULONG rc=ControlTraceW(0,name,&p.p,EVENT_TRACE_CONTROL_QUERY);
    int result=0;
    if(rc!=ERROR_WMI_INSTANCE_NOT_FOUND) {
        if(rc||memcmp(&p.p.Wnode.Guid,guid,sizeof(GUID)))result=51;
        else {rc=ControlTraceW(0,name,&p.p,EVENT_TRACE_CONTROL_STOP);if(rc!=ERROR_SUCCESS&&rc!=ERROR_WMI_INSTANCE_NOT_FOUND)result=52;}
    }
    if(changed&&!AdjustTokenPrivileges(token,FALSE,&previous,0,NULL,NULL))result=53;
    if(token&&!CloseHandle(token))result=54;
    return result;
}
static int control(const wchar_t *dir,const wchar_t *name,const GUID *guid) {
    wchar_t output[MAX_PATH],etl[MAX_PATH],self[MAX_PATH],command[3*MAX_PATH],gate[MAX_PATH];
    if(wcslen(name)>=160||!path(output,dir,L"control.jsonl")||!path(etl,dir,L"handles.etl")||!path(gate,dir,L"child-handle.txt"))return 10;
    if(_wfopen_s(&report,output,L"wb"))return 11;
    HANDLE token=NULL;TOKEN_PRIVILEGES previous={0},wanted={0};DWORD previous_size=sizeof(previous);
    int privilege_changed=0,started=0,ok=0,child_ok=0;TRACEHANDLE session=0;
    HANDLE a=NULL,b=NULL,dup=NULL;PROCESS_INFORMATION pi={0};Properties p;
    ULONGLONG began=GetTickCount64();ULONG stop_code=ERROR_WMI_INSTANCE_NOT_FOUND;
    fprintf(report,"{\"kind\":\"control\",\"pid\":%lu,\"tid\":%lu,\"console\":%s,\"max_seconds\":30,\"buffer_cap_mib\":4,\"file_cap_mib\":32,\"system_wide_collection\":true}\n",GetCurrentProcessId(),GetCurrentThreadId(),GetConsoleWindow()?"true":"false");
    if(GetConsoleWindow())goto cleanup;
    /* Own-token privilege only, restored at exit. No ACL/group/global changes. */
    if(!OpenProcessToken(GetCurrentProcess(),TOKEN_ADJUST_PRIVILEGES|TOKEN_QUERY,&token))goto cleanup;
    wanted.PrivilegeCount=1;
    if(!LookupPrivilegeValueW(NULL,L"SeSystemProfilePrivilege",&wanted.Privileges[0].Luid))goto cleanup;
    wanted.Privileges[0].Attributes=SE_PRIVILEGE_ENABLED;
    SetLastError(ERROR_SUCCESS);
    if(!AdjustTokenPrivileges(token,FALSE,&wanted,sizeof(previous),&previous,&previous_size)||GetLastError()!=ERROR_SUCCESS){status("enable_own_token_privilege",GetLastError());goto cleanup;}
    privilege_changed=1;
    properties(&p,name,etl,guid);
    ULONG rc=StartTraceW(&session,name,&p.p);status("start",rc);
    if(rc!=ERROR_SUCCESS)goto cleanup;started=1;
    ENABLE_TRACE_PARAMETERS enable={0};enable.Version=ENABLE_TRACE_PARAMETERS_VERSION_2;
    rc=EnableTraceEx2(session,&object_provider,EVENT_CONTROL_CODE_ENABLE_PROVIDER,TRACE_LEVEL_VERBOSE,2,0,1000,&enable);status("enable_handle_only",rc);
    if(rc)goto cleanup;
    CLASSIC_EVENT_ID ids[3]={0};
    for(unsigned i=0;i<3;i++){ids[i].EventGuid=object_class;ids[i].Type=(UCHAR)(32+i);}
    rc=TraceSetInformation(session,TraceStackTracingInfo,ids,sizeof(ids));status("stack_create_close_duplicate",rc);
    if(rc)goto cleanup;
    a=create_a();if(!a)goto cleanup;
    record("create_a",a,(void*)create_a,0,GetCurrentProcessId(),NULL);
    dup=duplicate_to(a,GetCurrentProcess());if(!dup)goto cleanup;
    record("duplicate_self",a,(void*)duplicate_to,GetCurrentProcessId(),GetCurrentProcessId(),dup);
    if(!GetModuleFileNameW(NULL,self,MAX_PATH))goto cleanup;
    if(_snwprintf_s(command,3*MAX_PATH,_TRUNCATE,L"\"%s\" --child \"%s\"",self,dir)<0)goto cleanup;
    STARTUPINFOW si={0};si.cb=sizeof(si);
    if(!CreateProcessW(self,command,NULL,NULL,FALSE,CREATE_SUSPENDED|CREATE_NO_WINDOW,NULL,dir,&si,&pi))goto cleanup;
    HANDLE remote=duplicate_to(a,pi.hProcess);if(!remote)goto cleanup;
    record("duplicate_child",a,(void*)duplicate_to,GetCurrentProcessId(),pi.dwProcessId,remote);
    FILE *out=NULL;if(_wfopen_s(&out,gate,L"wb"))goto cleanup;
    int written=fprintf(out,"%llx",(unsigned long long)(uintptr_t)remote);int closed=fclose(out);
    if(written<=0||closed||ResumeThread(pi.hThread)==(DWORD)-1)goto cleanup;
    if(!CloseHandle(pi.hThread))goto cleanup;pi.hThread=NULL;
    if(WaitForSingleObject(pi.hProcess,5000)!=WAIT_OBJECT_0)goto cleanup;
    DWORD child_exit=1;if(!GetExitCodeProcess(pi.hProcess,&child_exit)||child_exit)goto cleanup;
    child_ok=1;
    if(WaitForSingleObject(a,0)!=WAIT_OBJECT_0)goto cleanup;
    record("close_a",a,(void*)close_owned,0,GetCurrentProcessId(),NULL);
    if(!close_owned(a))goto cleanup;
    HANDLE old=a;a=NULL;b=create_b();if(!b)goto cleanup;
    record("create_b",b,(void*)create_b,0,GetCurrentProcessId(),NULL);
    fprintf(report,"{\"kind\":\"slot_reuse\",\"observed\":%s}\n",b==old?"true":"false");
    record("close_b",b,(void*)close_owned,0,GetCurrentProcessId(),NULL);
    if(!close_owned(b))goto cleanup;b=NULL;
    record("close_duplicate",dup,(void*)close_owned,0,GetCurrentProcessId(),NULL);
    if(!close_owned(dup))goto cleanup;dup=NULL;ok=1;
cleanup:
    if(pi.hProcess){
        if(WaitForSingleObject(pi.hProcess,0)!=WAIT_OBJECT_0){TerminateProcess(pi.hProcess,90);if(WaitForSingleObject(pi.hProcess,2000)!=WAIT_OBJECT_0)ok=0;}
        if(!CloseHandle(pi.hProcess))ok=0;
    }
    if(pi.hThread&&!CloseHandle(pi.hThread))ok=0;
    if(a&&!CloseHandle(a))ok=0;if(b&&!CloseHandle(b))ok=0;if(dup&&!CloseHandle(dup))ok=0;
    if(started){
        ULONG disabled=EnableTraceEx2(session,&object_provider,EVENT_CONTROL_CODE_DISABLE_PROVIDER,0,0,0,1000,NULL);status("disable_provider",disabled);
        stop_code=ControlTraceW(session,name,&p.p,EVENT_TRACE_CONTROL_STOP);status("stop_owned_session",stop_code);
        if(stop_code!=ERROR_SUCCESS||disabled!=ERROR_SUCCESS)ok=0;
        fprintf(report,"{\"kind\":\"loss\",\"events\":%lu,\"log_buffers\":%lu,\"realtime_buffers\":%lu,\"buffers_written\":%lu}\n",p.p.EventsLost,p.p.LogBuffersLost,p.p.RealTimeBuffersLost,p.p.BuffersWritten);
        if(p.p.EventsLost||p.p.LogBuffersLost||p.p.RealTimeBuffersLost)ok=0;
    }
    if(privilege_changed&&!AdjustTokenPrivileges(token,FALSE,&previous,0,NULL,NULL))ok=0;
    if(token&&!CloseHandle(token))ok=0;
    ULONGLONG elapsed=GetTickCount64()-began;
    if(elapsed>30000)ok=0;
    WIN32_FILE_ATTRIBUTE_DATA info={0};
    if(started&&(!GetFileAttributesExW(etl,GetFileExInfoStandard,&info)||info.nFileSizeHigh||info.nFileSizeLow>32*1024*1024))ok=0;
    fprintf(report,"{\"kind\":\"result\",\"fixture_ok\":%s,\"child_ok\":%s,\"session_started\":%s,\"session_stopped\":%s,\"elapsed_ms\":%llu,\"stack_qualified\":false,\"terminal_launched\":false}\n",ok?"true":"false",child_ok?"true":"false",started?"true":"false",started&&stop_code==ERROR_SUCCESS?"true":"false",(unsigned long long)elapsed);
    fclose(report);return ok?0:20;
}
/* External capture only: no emitter, target lookup, or process creation. */
static int collect(const wchar_t *dir,const wchar_t *name,const GUID *guid) {
    wchar_t output[MAX_PATH],etl[MAX_PATH],ready[MAX_PATH],stop[MAX_PATH];
    if(wcslen(name)>=160||!path(output,dir,L"collection.jsonl")||!path(etl,dir,L"handles.etl")||
       !path(ready,dir,L"ready.json")||!path(stop,dir,L"stop.request"))return 60;
    /* Refuse stale signals/evidence rather than treating them as this run. */
    if(GetFileAttributesW(stop)!=INVALID_FILE_ATTRIBUTES||GetLastError()!=ERROR_FILE_NOT_FOUND)return 61;
    if(GetFileAttributesW(ready)!=INVALID_FILE_ATTRIBUTES||GetLastError()!=ERROR_FILE_NOT_FOUND)return 61;
    if(GetFileAttributesW(etl)!=INVALID_FILE_ATTRIBUTES||GetLastError()!=ERROR_FILE_NOT_FOUND)return 61;
    if(_wfopen_s(&report,output,L"wb"))return 62;
    HANDLE token=NULL;TOKEN_PRIVILEGES previous={0},wanted={0};DWORD previous_size=sizeof(previous);
    int changed=0,started=0,complete=0,clean=1,file_ok=0;TRACEHANDLE session=0;
    Properties p;ULONG rc=0,stop_code=ERROR_WMI_INSTANCE_NOT_FOUND;
    const char *cause="setup_failure";ULONGLONG began=GetTickCount64(),next_query=0,file_bytes=0;
    LARGE_INTEGER qpc={0},frequency={0};FILETIME epoch={0};
    fprintf(report,"{\"kind\":\"collection\",\"mode\":\"collect\",\"pid\":%lu,\"max_seconds\":110,\"buffer_cap_mib\":4,\"file_cap_mib\":32,\"system_wide_collection\":true,\"terminal_launched\":false}\n",GetCurrentProcessId());
    if(GetConsoleWindow())goto cleanup_collect;
    if(!OpenProcessToken(GetCurrentProcess(),TOKEN_ADJUST_PRIVILEGES|TOKEN_QUERY,&token))goto cleanup_collect;
    wanted.PrivilegeCount=1;
    if(!LookupPrivilegeValueW(NULL,L"SeSystemProfilePrivilege",&wanted.Privileges[0].Luid))goto cleanup_collect;
    wanted.Privileges[0].Attributes=SE_PRIVILEGE_ENABLED;SetLastError(ERROR_SUCCESS);
    if(!AdjustTokenPrivileges(token,FALSE,&wanted,sizeof(previous),&previous,&previous_size)||GetLastError()!=ERROR_SUCCESS)goto cleanup_collect;
    changed=1;properties(&p,name,etl,guid);
    rc=StartTraceW(&session,name,&p.p);status("start",rc);
    /* In particular, ERROR_ALREADY_EXISTS confers no ownership. */
    if(rc)goto cleanup_collect;
    started=1;
    ENABLE_TRACE_PARAMETERS enable={0};enable.Version=ENABLE_TRACE_PARAMETERS_VERSION_2;
    rc=EnableTraceEx2(session,&object_provider,EVENT_CONTROL_CODE_ENABLE_PROVIDER,TRACE_LEVEL_VERBOSE,2,0,1000,&enable);status("enable_handle_only",rc);
    if(rc)goto cleanup_collect;
    CLASSIC_EVENT_ID ids[3]={0};
    for(unsigned i=0;i<3;i++){ids[i].EventGuid=object_class;ids[i].Type=(UCHAR)(32+i);}
    rc=TraceSetInformation(session,TraceStackTracingInfo,ids,sizeof(ids));status("stack_create_close_duplicate",rc);
    if(rc)goto cleanup_collect;
    rc=ControlTraceW(session,name,&p.p,EVENT_TRACE_CONTROL_FLUSH);status("flush_before_ready",rc);
    if(rc||p.p.EventsLost||p.p.LogBuffersLost||p.p.RealTimeBuffersLost)goto cleanup_collect;
    if(!QueryPerformanceFrequency(&frequency)||!QueryPerformanceCounter(&qpc))goto cleanup_collect;
    GetSystemTimeAsFileTime(&epoch);
    char metadata[512];
    int length=sprintf_s(metadata,sizeof(metadata),"{\"mode\":\"collect\",\"pid\":%lu,\"qpc\":%lld,\"qpc_frequency\":%lld,\"epoch_filetime_100ns\":%llu,\"terminal_launched\":false}\n",GetCurrentProcessId(),qpc.QuadPart,frequency.QuadPart,((unsigned long long)epoch.dwHighDateTime<<32)|epoch.dwLowDateTime);
    if(length<=0||fflush(report))goto cleanup_collect;
    HANDLE signal=CreateFileW(ready,GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);
    if(signal==INVALID_HANDLE_VALUE)goto cleanup_collect;
    DWORD written=0;int ready_ok=WriteFile(signal,metadata,(DWORD)length,&written,NULL)&&written==(DWORD)length&&FlushFileBuffers(signal);
    if(!CloseHandle(signal))ready_ok=0;
    if(!ready_ok)goto cleanup_collect;
    for(;;){
        ULONGLONG now=GetTickCount64();
        if(now-began>=110000){cause="deadline";break;}
        if(now>=next_query){
            next_query=now+200;
            rc=ControlTraceW(session,name,&p.p,EVENT_TRACE_CONTROL_QUERY);
            if(rc){cause="session_failure";break;}
            if(p.p.EventsLost||p.p.LogBuffersLost||p.p.RealTimeBuffersLost){cause="loss";break;}
            WIN32_FILE_ATTRIBUTE_DATA info={0};
            if(!GetFileAttributesExW(etl,GetFileExInfoStandard,&info)){cause="file_failure";break;}
            file_bytes=((ULONGLONG)info.nFileSizeHigh<<32)|info.nFileSizeLow;
            if(file_bytes>=32ULL*1024*1024||p.p.NumberOfBuffers>64){cause="cap";break;}
        }
        WIN32_FILE_ATTRIBUTE_DATA request={0};
        if(GetFileAttributesExW(stop,GetFileExInfoStandard,&request)){
            if(!(request.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT))&&CompareFileTime(&request.ftLastWriteTime,&epoch)>=0){complete=1;cause="stop_request";break;}
            cause="invalid_stop_request";break;
        }
        if(GetLastError()!=ERROR_FILE_NOT_FOUND){cause="stop_request_failure";break;}
        Sleep(50);
    }
cleanup_collect:
    if(started){
        rc=EnableTraceEx2(session,&object_provider,EVENT_CONTROL_CODE_DISABLE_PROVIDER,0,0,0,1000,NULL);status("disable_provider",rc);
        if(rc)clean=0;
        stop_code=ControlTraceW(session,name,&p.p,EVENT_TRACE_CONTROL_STOP);status("stop_owned_session",stop_code);
        if(stop_code!=ERROR_SUCCESS)clean=0;
        fprintf(report,"{\"kind\":\"loss\",\"events\":%lu,\"log_buffers\":%lu,\"realtime_buffers\":%lu,\"buffers_written\":%lu}\n",p.p.EventsLost,p.p.LogBuffersLost,p.p.RealTimeBuffersLost,p.p.BuffersWritten);
        if(p.p.EventsLost||p.p.LogBuffersLost||p.p.RealTimeBuffersLost)clean=0;
        WIN32_FILE_ATTRIBUTE_DATA info={0};
        if(GetFileAttributesExW(etl,GetFileExInfoStandard,&info)){
            file_bytes=((ULONGLONG)info.nFileSizeHigh<<32)|info.nFileSizeLow;
            file_ok=file_bytes<=32ULL*1024*1024;
        }
    }
    if(changed&&!AdjustTokenPrivileges(token,FALSE,&previous,0,NULL,NULL))clean=0;
    if(token&&!CloseHandle(token))clean=0;
    ULONGLONG elapsed=GetTickCount64()-began;
    complete=complete&&clean&&file_ok&&elapsed<=110000;
    fprintf(report,"{\"kind\":\"result\",\"mode\":\"collect\",\"complete\":%s,\"cause\":\"%s\",\"cleanup_ok\":%s,\"session_started\":%s,\"session_stopped\":%s,\"zero_loss\":%s,\"file_cap_ok\":%s,\"file_bytes\":%llu,\"elapsed_ms\":%llu,\"terminal_launched\":false}\n",complete?"true":"false",cause,clean?"true":"false",started?"true":"false",started&&stop_code==ERROR_SUCCESS?"true":"false",started&&stop_code==ERROR_SUCCESS&&!p.p.EventsLost&&!p.p.LogBuffersLost&&!p.p.RealTimeBuffersLost?"true":"false",file_ok?"true":"false",file_bytes,elapsed);
    if(fclose(report))complete=0;
    return complete?0:63;
}
int WINAPI WinMain(HINSTANCE h,HINSTANCE p,LPSTR cmd,int show) {
    (void)h;(void)p;(void)cmd;(void)show;
    int argc=0;wchar_t **argv=CommandLineToArgvW(GetCommandLineW(),&argc);if(!argv)return 1;
    int code=2;GUID guid={0};
    if(argc==3&&!wcscmp(argv[1],L"--child"))code=child(argv[2]);
    else if(argc==5&&!wcscmp(argv[1],L"--control")&&SUCCEEDED(CLSIDFromString(argv[4],&guid)))code=control(argv[2],argv[3],&guid);
    else if(argc==5&&!wcscmp(argv[1],L"--collect")&&SUCCEEDED(CLSIDFromString(argv[4],&guid)))code=collect(argv[2],argv[3],&guid);
    else if(argc==4&&!wcscmp(argv[1],L"--stop-own")&&SUCCEEDED(CLSIDFromString(argv[3],&guid)))code=stop_own(argv[2],&guid);
    LocalFree(argv);return code;
}
