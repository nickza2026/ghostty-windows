/* Real-time, selected-metadata-only collector. No ETL is created.
 * Parser and fixture attribution reside in the included qualification sources.
 * Do not substitute the offline callback: it has a ten-second deadline. */
#define WinMain offline_decode_main
#include "etw-handle-decode.c"
#undef WinMain
#define WinMain offline_control_main
#include "etw-handle-control.c"
#undef WinMain

static char arena[BYTE_CAP];
static size_t arena_used;
static volatile LONG live_error, bound_count;
static SRWLOCK scope_lock=SRWLOCK_INIT;
static TRACEHANDLE consumer=INVALID_PROCESSTRACE_HANDLE;
static ULONG consumer_result;
static BOOL live_append(const char *s) {
    size_t n=strlen(s);
    if(n>BYTE_CAP-2048-arena_used){InterlockedExchange(&live_error,ERROR_BUFFER_OVERFLOW);return FALSE;}
    memcpy(arena+arena_used,s,n);arena_used+=n;return TRUE;
}
static BOOL scoped(EVENT_RECORD *e) {
    ULONG a=0,b=0;const BYTE *p=e->UserData;size_t n=e->UserDataLength;
    if(!InterlockedCompareExchange(&bound_count,0,0))return FALSE;
    if(!memcmp(&e->EventHeader.ProviderId,&stack_guid,sizeof(GUID)))
        return get(p,n,8,&a,4)&&wanted(a);
    if(memcmp(&e->EventHeader.ProviderId,&handle_guid,sizeof(GUID)))return FALSE;
    if(e->EventHeader.EventDescriptor.Opcode==34){
        size_t x=(e->EventHeader.Flags&EVENT_HEADER_FLAG_32_BIT_HEADER)?12:16;
        size_t y=x==12?18:22;
        return wanted(e->EventHeader.ProcessId)||(get(p,n,x,&a,4)&&wanted(a))||(get(p,n,y,&b,4)&&wanted(b));
    }
    return wanted(e->EventHeader.ProcessId);
}
static void WINAPI live_callback(EVENT_RECORD *e) {
    Record r;int used,result;
    AcquireSRWLockShared(&scope_lock);
    if(!scoped(e)){ReleaseSRWLockShared(&scope_lock);other++;return;}
    if(InterlockedCompareExchange(&live_error,0,0)){ReleaseSRWLockShared(&scope_lock);return;}
    result=decode(e,&r);
    ReleaseSRWLockShared(&scope_lock);
    if(!result)return;
    if(result<0){if(result==-2)unsupported++;else malformed++;InterlockedExchange(&live_error,ERROR_INVALID_DATA);return;}
    if(selected>=RECORD_CAP){InterlockedExchange(&live_error,ERROR_BUFFER_OVERFLOW);return;}
    selected++;if(!version_supported(&r))versions++;
    used=snprintf(line,sizeof(line),"{\"kind\":\"%s\",\"sequence\":%llu,\"qpc\":\"0x%016llx\",\"executingPID\":%lu,\"executingTID\":%lu,\"opcode\":%u,\"version\":%u,\"unsupportedVersion\":%s",r.kind==2?"stack":"handle",selected,r.qpc,e->EventHeader.ProcessId,e->EventHeader.ThreadId,r.opcode,r.version,version_supported(&r)?"false":"true");
    if(r.kind==2){
        used+=snprintf(line+used,sizeof(line)-used,",\"eventQPC\":\"0x%016llx\",\"pid\":%lu,\"tid\":%lu,\"frames\":[",r.event_qpc,r.pid,r.tid);
        for(unsigned i=0;i<r.frames;i++)used+=snprintf(line+used,sizeof(line)-used,"%s\"0x%016llx\"",i?",":"",r.pcs[i]);
        used+=snprintf(line+used,sizeof(line)-used,"]}\n");
    }else{
        used+=snprintf(line+used,sizeof(line)-used,",\"ownerPID\":%lu,\"object\":\"0x%016llx\",\"handle\":%lu,\"objectType\":%u",r.pid,r.object,r.handle,r.type);
        if(r.opcode==34)used+=snprintf(line+used,sizeof(line)-used,",\"sourceHandle\":%lu,\"targetHandle\":%lu,\"sourceProcessId\":%lu,\"targetProcessId\":%lu,\"duplicateSemanticsQualified\":false",r.handle,r.target_handle,r.source_pid,r.target_pid);
        used+=snprintf(line+used,sizeof(line)-used,"}\n");
    }
    if(used<0||(size_t)used>=sizeof(line))InterlockedExchange(&live_error,ERROR_BUFFER_OVERFLOW);
    else live_append(line);
}
static DWORD WINAPI consume(void *unused){(void)unused;consumer_result=ProcessTrace(&consumer,1,NULL,NULL);return 0;}
static int new_file(const wchar_t *dir,const wchar_t *leaf,const char *text){
    wchar_t p[MAX_PATH];DWORD n=0;size_t len=strlen(text);
    if(!path(p,dir,leaf))return 0;
    HANDLE f=CreateFileW(p,GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);
    if(f==INVALID_HANDLE_VALUE)return 0;
    int ok=WriteFile(f,text,(DWORD)len,&n,NULL)&&n==len&&FlushFileBuffers(f);
    if(!CloseHandle(f))ok=0;return ok;
}
/* The root is pinned against rename/delete and must have the same narrow ACL
 * as secure_input. OPEN_REPARSE_POINT rejects substitution at the final node. */
static HANDLE secure_root(const wchar_t *dir){
    wchar_t full[MAX_PATH],drive[4];BYTE sd[65536],tu[4096];DWORD need;
    HANDLE token=NULL,f=INVALID_HANDLE_VALUE;PSID owner;PACL acl;BOOL present,def;
    BY_HANDLE_FILE_INFORMATION info;
    if(!GetFullPathNameW(dir,MAX_PATH,full,NULL)||full[1]!=L':'||full[2]!=L'\\')return f;
    drive[0]=full[0];drive[1]=L':';drive[2]=L'\\';drive[3]=0;
    if(GetDriveTypeW(drive)!=DRIVE_FIXED)return f;
    f=CreateFileW(full,READ_CONTROL|FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE,NULL,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,NULL);
    if(f==INVALID_HANDLE_VALUE)return f;
    if(!GetFileInformationByHandle(f,&info)||!(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)||(info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT))goto bad_root;
    if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)||!GetTokenInformation(token,TokenUser,tu,sizeof(tu),&need)||!GetKernelObjectSecurity(f,OWNER_SECURITY_INFORMATION|DACL_SECURITY_INFORMATION,sd,sizeof(sd),&need)||!GetSecurityDescriptorOwner(sd,&owner,&def)||!EqualSid(owner,((TOKEN_USER*)tu)->User.Sid)||!GetSecurityDescriptorDacl(sd,&present,&acl,&def)||!present||!acl)goto bad_root;
    for(DWORD i=0;i<acl->AceCount;i++){
        ACE_HEADER *a=NULL;if(!GetAce(acl,i,(void**)&a))goto bad_root;
        if(a->AceType==ACCESS_DENIED_ACE_TYPE)continue;
        if(a->AceType!=ACCESS_ALLOWED_ACE_TYPE||(!EqualSid(&((ACCESS_ALLOWED_ACE*)a)->SidStart,owner)&&!IsWellKnownSid(&((ACCESS_ALLOWED_ACE*)a)->SidStart,WinLocalSystemSid)))goto bad_root;
    }
    CloseHandle(token);return f;
bad_root:if(token)CloseHandle(token);CloseHandle(f);return INVALID_HANDLE_VALUE;
}
static int fixture(const wchar_t *dir){
    wchar_t self[MAX_PATH],command[3*MAX_PATH],gate[MAX_PATH];PROCESS_INFORMATION pi={0};STARTUPINFOW si={0};
    HANDLE a=NULL,b=NULL,d=NULL,remote=NULL;int ok=0;DWORD code=1;si.cb=sizeof(si);
    a=create_a();if(!a)goto done_fixture;record("create_a",a,(void*)create_a,0,GetCurrentProcessId(),NULL);
    d=duplicate_to(a,GetCurrentProcess());if(!d)goto done_fixture;record("duplicate_self",a,(void*)duplicate_to,GetCurrentProcessId(),GetCurrentProcessId(),d);
    if(!GetModuleFileNameW(NULL,self,MAX_PATH)||!path(gate,dir,L"child-handle.txt")||_snwprintf_s(command,3*MAX_PATH,_TRUNCATE,L"\"%s\" --child \"%s\"",self,dir)<0)goto done_fixture;
    if(!CreateProcessW(self,command,NULL,NULL,FALSE,CREATE_SUSPENDED|CREATE_NO_WINDOW,NULL,dir,&si,&pi))goto done_fixture;
    AcquireSRWLockExclusive(&scope_lock);pids[1]=pi.dwProcessId;InterlockedExchange(&bound_count,2);ReleaseSRWLockExclusive(&scope_lock);
    remote=duplicate_to(a,pi.hProcess);if(!remote)goto done_fixture;record("duplicate_child",a,(void*)duplicate_to,GetCurrentProcessId(),pi.dwProcessId,remote);
    char value[32];sprintf_s(value,sizeof(value),"%llx",(unsigned long long)(uintptr_t)remote);
    if(!new_file(dir,L"child-handle.txt",value)||ResumeThread(pi.hThread)==(DWORD)-1)goto done_fixture;
    if(WaitForSingleObject(pi.hProcess,5000)!=WAIT_OBJECT_0||!GetExitCodeProcess(pi.hProcess,&code)||code||WaitForSingleObject(a,0)!=WAIT_OBJECT_0)goto done_fixture;
    record("close_a",a,(void*)close_owned,0,GetCurrentProcessId(),NULL);if(!close_owned(a))goto done_fixture;
    HANDLE old=a;a=NULL;b=create_b();if(!b)goto done_fixture;record("create_b",b,(void*)create_b,0,GetCurrentProcessId(),NULL);
    fprintf(report,"{\"kind\":\"slot_reuse\",\"observed\":%s}\n",b==old?"true":"false");
    record("close_b",b,(void*)close_owned,0,GetCurrentProcessId(),NULL);if(!close_owned(b))goto done_fixture;b=NULL;
    record("close_duplicate",d,(void*)close_owned,0,GetCurrentProcessId(),NULL);if(!close_owned(d))goto done_fixture;d=NULL;ok=1;
done_fixture:
    if(pi.hProcess){if(WaitForSingleObject(pi.hProcess,0)!=WAIT_OBJECT_0){TerminateProcess(pi.hProcess,90);if(WaitForSingleObject(pi.hProcess,2000)!=WAIT_OBJECT_0)ok=0;}CloseHandle(pi.hProcess);}
    if(pi.hThread)CloseHandle(pi.hThread);if(a)CloseHandle(a);if(b)CloseHandle(b);if(d)CloseHandle(d);return ok;
}
static int stream_run(const wchar_t *dir,const wchar_t *name,const GUID *guid,int control_mode){
    HANDLE root=secure_root(dir),token=NULL,thread=NULL;TOKEN_PRIVILEGES want={0},prev={0};DWORD size=sizeof(prev);
    Properties prop;TRACEHANDLE session=0;EVENT_TRACE_LOGFILEW log={0};int changed=0,owned=0,ok=0,clean=1,drained=1,child_ok=0;
    ULONG rc=ERROR_INVALID_PARAMETER,stoprc=ERROR_WMI_INSTANCE_NOT_FOUND;ULONGLONG begin=GetTickCount64();FILETIME epoch;wchar_t file[MAX_PATH];
    if(root==INVALID_HANDLE_VALUE||wcslen(name)>=160)return 70;
    const wchar_t *fresh[]={L"decoded.jsonl",L"ready.json",L"stop.request",L"binding.txt",L"binding-ack.json",L"stream.jsonl",L"control.jsonl",L"child.jsonl",L"child-handle.txt"};
    for(unsigned i=0;i<sizeof(fresh)/sizeof(fresh[0]);i++)if(!path(file,dir,fresh[i])||GetFileAttributesW(file)!=INVALID_FILE_ATTRIBUTES||GetLastError()!=ERROR_FILE_NOT_FOUND){CloseHandle(root);return 71;}
    if(!path(file,dir,control_mode?L"control.jsonl":L"stream.jsonl")||_wfopen_s(&report,file,L"wb")){CloseHandle(root);return 72;}
    GetSystemTimeAsFileTime(&epoch);
    if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY|TOKEN_ADJUST_PRIVILEGES,&token))goto finish;
    want.PrivilegeCount=1;if(!LookupPrivilegeValueW(NULL,L"SeSystemProfilePrivilege",&want.Privileges[0].Luid))goto finish;
    want.Privileges[0].Attributes=SE_PRIVILEGE_ENABLED;SetLastError(0);
    if(!AdjustTokenPrivileges(token,FALSE,&want,sizeof(prev),&prev,&size)||GetLastError())goto finish;changed=1;
    properties(&prop,name,NULL,guid);prop.p.MaximumFileSize=0;prop.p.LogFileNameOffset=0;prop.p.LogFileMode=EVENT_TRACE_SYSTEM_LOGGER_MODE|EVENT_TRACE_REAL_TIME_MODE;
    rc=StartTraceW(&session,name,&prop.p);status("start",rc);if(rc)goto finish;owned=1;
    log.LoggerName=(LPWSTR)name;log.ProcessTraceMode=PROCESS_TRACE_MODE_REAL_TIME|PROCESS_TRACE_MODE_EVENT_RECORD|PROCESS_TRACE_MODE_RAW_TIMESTAMP;log.EventRecordCallback=live_callback;
    consumer=OpenTraceW(&log);if(consumer==INVALID_PROCESSTRACE_HANDLE)goto finish;
    thread=CreateThread(NULL,0,consume,NULL,0,NULL);if(!thread)goto finish;
    ENABLE_TRACE_PARAMETERS enable={0};enable.Version=ENABLE_TRACE_PARAMETERS_VERSION_2;
    rc=EnableTraceEx2(session,&object_provider,EVENT_CONTROL_CODE_ENABLE_PROVIDER,TRACE_LEVEL_VERBOSE,2,0,1000,&enable);status("enable_handle_only",rc);if(rc)goto finish;
    CLASSIC_EVENT_ID ids[3]={0};for(unsigned i=0;i<3;i++){ids[i].EventGuid=object_class;ids[i].Type=(UCHAR)(32+i);}
    rc=TraceSetInformation(session,TraceStackTracingInfo,ids,sizeof(ids));status("stack_create_close_duplicate",rc);if(rc)goto finish;
    if(control_mode){AcquireSRWLockExclusive(&scope_lock);pids[0]=GetCurrentProcessId();InterlockedExchange(&bound_count,1);ReleaseSRWLockExclusive(&scope_lock);}
    LARGE_INTEGER qpc,freq;QueryPerformanceCounter(&qpc);QueryPerformanceFrequency(&freq);
    char ready[512];sprintf_s(ready,sizeof(ready),"{\"mode\":\"%s\",\"pid\":%lu,\"qpc\":%lld,\"qpc_frequency\":%lld,\"epoch_filetime_100ns\":%llu,\"terminal_launched\":false}\n",control_mode?"control":"collect",GetCurrentProcessId(),qpc.QuadPart,freq.QuadPart,((ULONGLONG)epoch.dwHighDateTime<<32)|epoch.dwLowDateTime);
    if(!new_file(dir,L"ready.json",ready))goto finish;
    if(control_mode){ok=fixture(dir);child_ok=ok;goto finish;}
    while(GetTickCount64()-begin<108000&&!InterlockedCompareExchange(&live_error,0,0)){
        if(!bound_count){
            path(file,dir,L"binding.txt");HANDLE f=secure_input(file);
            if(f!=INVALID_HANDLE_VALUE){char raw[32]={0};DWORD n=0;BY_HANDLE_FILE_INFORMATION info;ULONG pid=0;wchar_t text[32]={0};
                int valid=GetFileInformationByHandle(f,&info)&&CompareFileTime(&info.ftLastWriteTime,&epoch)>=0&&ReadFile(f,raw,31,&n,NULL)&&n>0&&n<31;
                CloseHandle(f);for(DWORD i=0;i<n&&i<31;i++){if(raw[i]<'0'||raw[i]>'9')valid=0;text[i]=(wchar_t)raw[i];}
                if(!valid||!parse_pid(text,&pid)||pid==GetCurrentProcessId())goto finish;
                AcquireSRWLockExclusive(&scope_lock);pids[0]=pid;pids[1]=pid;InterlockedExchange(&bound_count,1);ReleaseSRWLockExclusive(&scope_lock);
                char ack[80];sprintf_s(ack,sizeof(ack),"{\"pid\":%lu,\"bound\":true}\n",pid);if(!new_file(dir,L"binding-ack.json",ack))goto finish;
            }
        }
        path(file,dir,L"stop.request");HANDLE f=secure_input(file);
        if(f!=INVALID_HANDLE_VALUE){BY_HANDLE_FILE_INFORMATION info;ok=bound_count&&GetFileInformationByHandle(f,&info)&&CompareFileTime(&info.ftLastWriteTime,&epoch)>=0;CloseHandle(f);break;}
        rc=ControlTraceW(session,name,&prop.p,EVENT_TRACE_CONTROL_QUERY);if(rc||prop.p.EventsLost||prop.p.LogBuffersLost||prop.p.RealTimeBuffersLost||prop.p.NumberOfBuffers>64)break;
        Sleep(50);
    }
finish:
    if(owned){rc=EnableTraceEx2(session,&object_provider,EVENT_CONTROL_CODE_DISABLE_PROVIDER,0,0,0,1000,NULL);status("disable_provider",rc);if(rc)clean=0;
        stoprc=ControlTraceW(session,name,&prop.p,EVENT_TRACE_CONTROL_STOP);status("stop_owned_session",stoprc);if(stoprc)clean=0;
        fprintf(report,"{\"kind\":\"loss\",\"events\":%lu,\"log_buffers\":%lu,\"realtime_buffers\":%lu}\n",prop.p.EventsLost,prop.p.LogBuffersLost,prop.p.RealTimeBuffersLost);
        if(prop.p.EventsLost||prop.p.LogBuffersLost||prop.p.RealTimeBuffersLost)clean=0;
    }
    if(thread&&WaitForSingleObject(thread,1500)!=WAIT_OBJECT_0){CloseTrace(consumer);consumer=INVALID_PROCESSTRACE_HANDLE;if(WaitForSingleObject(thread,500)!=WAIT_OBJECT_0)drained=0;}
    if(consumer!=INVALID_PROCESSTRACE_HANDLE)CloseTrace(consumer);
    if(thread)CloseHandle(thread);
    /* A non-drained callback must never race serialization or process teardown.
     * ExitProcess below ends only this collector, after owned-session stop. */
    if(!drained){
        if(changed)AdjustTokenPrivileges(token,FALSE,&prev,0,NULL,NULL);
        if(token)CloseHandle(token);
        CloseHandle(root);fclose(report);ExitProcess(79);
    }
    if(thread&&consumer_result!=ERROR_SUCCESS)clean=0;
    if(owned){Properties query;properties(&query,name,NULL,guid);rc=ControlTraceW(0,name,&query.p,EVENT_TRACE_CONTROL_QUERY);status("query_after_stop",rc);if(rc!=ERROR_WMI_INSTANCE_NOT_FOUND)clean=0;}
    if(changed&&!AdjustTokenPrivileges(token,FALSE,&prev,0,NULL,NULL))clean=0;if(token)CloseHandle(token);
    ok=ok&&clean&&owned&&stoprc==ERROR_SUCCESS&&!live_error&&!versions&&GetTickCount64()-begin<=(control_mode?24000:110000);
    snprintf(line,sizeof(line),"{\"kind\":\"result\",\"qualification\":\"parse-only-not-callstack-gate\",\"ok\":%s,\"error\":%ld,\"selectedRecords\":%llu,\"otherEvents\":%llu,\"malformed\":%llu,\"unsupportedPayloads\":%llu,\"unsupportedVersions\":%llu,\"recordCap\":16384,\"byteCap\":8388608,\"frameCap\":192,\"duplicateSemanticsQualified\":false}\n",ok?"true":"false",live_error,selected,other,malformed,unsupported,versions);
    size_t n=strlen(line);memcpy(arena+arena_used,line,n);arena_used+=n;
    if(!path(file,dir,L"decoded.jsonl"))ok=0;else{HANDLE f=CreateFileW(file,GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);DWORD wrote=0;if(f==INVALID_HANDLE_VALUE)ok=0;else{if(!WriteFile(f,arena,(DWORD)arena_used,&wrote,NULL)||wrote!=arena_used||!FlushFileBuffers(f))ok=0;if(!CloseHandle(f))ok=0;}}
    fprintf(report,"{\"kind\":\"result\",\"fixture_ok\":%s,\"child_ok\":%s,\"complete\":%s,\"session_stopped\":%s,\"elapsed_ms\":%llu}\n",control_mode&&ok?"true":"false",child_ok?"true":"false",ok?"true":"false",owned&&!stoprc?"true":"false",GetTickCount64()-begin);
    if(fclose(report))ok=0;CloseHandle(root);return ok?0:73;
}
static int stream_selftest(void){
    int result=selftest();if(result)return result;
    EVENT_RECORD e={0};BYTE data[32]={0};ULONG pid=101;
    e.UserData=data;e.UserDataLength=sizeof(data);e.EventHeader.ProviderId=handle_guid;
    e.EventHeader.ProcessId=999;e.EventHeader.EventDescriptor.Opcode=34;
    e.EventHeader.Flags=EVENT_HEADER_FLAG_64_BIT_HEADER;
    pids[0]=pid;pids[1]=pid;InterlockedExchange(&bound_count,0);
    memcpy(data+16,&pid,4);if(scoped(&e))return 18;
    InterlockedExchange(&bound_count,1);if(!scoped(&e))return 19;
    memset(data,0,sizeof(data));if(scoped(&e))return 20;
    memcpy(data+22,&pid,4);if(!scoped(&e))return 21;
    e.EventHeader.ProviderId=stack_guid;memset(data,0,sizeof(data));
    memcpy(data+8,&pid,4);if(!scoped(&e))return 22;
    e.UserDataLength=8;if(scoped(&e))return 23;
    return 0;
}
int WINAPI WinMain(HINSTANCE h,HINSTANCE p,LPSTR cmd,int show){
    (void)h;(void)p;(void)cmd;(void)show;int argc=0,result=2;GUID guid;wchar_t **argv=CommandLineToArgvW(GetCommandLineW(),&argc);if(!argv)return 1;
    if(argc==2&&!wcscmp(argv[1],L"--selftest"))result=stream_selftest();
    else if(argc==3&&!wcscmp(argv[1],L"--child"))result=child(argv[2]);
    else if(argc==4&&!wcscmp(argv[1],L"--stop-own")&&SUCCEEDED(CLSIDFromString(argv[3],&guid)))result=stop_own(argv[2],&guid);
    else if(argc==5&&SUCCEEDED(CLSIDFromString(argv[4],&guid))){if(!wcscmp(argv[1],L"--control"))result=stream_run(argv[2],argv[3],&guid,1);else if(!wcscmp(argv[1],L"--collect"))result=stream_run(argv[2],argv[3],&guid,0);}
    LocalFree(argv);return result;
}
