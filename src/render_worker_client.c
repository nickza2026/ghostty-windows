#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include "render_worker_client.h"

#define RW_PREFIX 16u
#define RW_HEADER 48u
#define RW_MAX_BODY (64u * 1024u * 1024u)
#ifndef RW_WORKER_NAME
#define RW_WORKER_NAME L"localterm-render-text-worker.exe"
#endif
#ifndef RW_BEFORE_REPLY_WAIT
#define RW_BEFORE_REPLY_WAIT(c,t) (1)
#endif
struct RwClient {
    HANDLE job, process, request_map, response_map, request_event, response_event, stop_event;
    uint8_t *request, *response;
    uint32_t request_capacity, response_capacity;
    DWORD primary_thread_id; /* Owned child identity, not a caller-supplied PID. */
    uint64_t surface, generation, sequence;
    int assigned, close_ack, finished, broken;
    int diagnostics;
    ULONGLONG metrics_next_ms;
    SIZE_T metrics_peak_working_set;
    DWORD metrics_samples,metrics_errors;
};
/* Read only the already-owned process HANDLE, never discover/open by PID.
 * Diagnostic fixtures only. Working-set peaks are NOT private memory or VRAM. */
static void sample_owned_resources(RwClient *c) {
    PROCESS_MEMORY_COUNTERS memory;
    ULONGLONG now;
    if(!c->diagnostics||!c->process)return;
    now=GetTickCount64();if(now<c->metrics_next_ms)return;
    c->metrics_next_ms=now+250;
    memset(&memory,0,sizeof(memory));memory.cb=sizeof(memory);
    if(K32GetProcessMemoryInfo(c->process,&memory,sizeof(memory))){
        if(memory.PeakWorkingSetSize>c->metrics_peak_working_set)c->metrics_peak_working_set=memory.PeakWorkingSetSize;
        c->metrics_samples++;
    }else c->metrics_errors++;
}
static void report_owned_resources(RwClient *c) {
    FILETIME created,exited,kernel,user;
    ULONGLONG cpu=0;
    DWORD error=0;
    int complete;
    if(!c->diagnostics)return;
    complete=GetProcessTimes(c->process,&created,&exited,&kernel,&user)!=0;
    if(complete)cpu=((((ULONGLONG)kernel.dwHighDateTime<<32)|kernel.dwLowDateTime)+(((ULONGLONG)user.dwHighDateTime<<32)|user.dwLowDateTime))/10000;
    else error=GetLastError();
    fprintf(stderr,"worker resources surface=%llu cpu_ms=%llu cpu_complete=%d peak_working_set_bytes=%llu samples=%lu sample_errors=%lu interval_ms=250 win_error=%lu\n",(unsigned long long)c->surface,(unsigned long long)cpu,complete,(unsigned long long)c->metrics_peak_working_set,(unsigned long)c->metrics_samples,(unsigned long)c->metrics_errors,(unsigned long)error);
}
static uint16_t u16le(const uint8_t *p) { return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8)); }
static uint32_t u32le(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1]<<8) | ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24); }
static uint64_t u64le(const uint8_t *p) { return u32le(p) | ((uint64_t)u32le(p+4)<<32); }
static int failure(RwStatus *s, uint32_t stage, DWORD error) {
    if (s) { s->stage=stage; s->win_error=error?error:ERROR_GEN_FAILURE; }
    return 0;
}
static void drop(HANDLE *h) { if (*h && *h!=INVALID_HANDLE_VALUE) CloseHandle(*h); *h=NULL; }
static int env_order(const void *a, const void *b) { return _wcsicmp(*(const wchar_t *const *)a, *(const wchar_t *const *)b); }
static wchar_t *environment(HANDLE *handles, uint32_t rc, uint32_t sc, uint64_t surface, uint64_t generation) {
    static const wchar_t *names[]={L"LOCALTERM_RENDER_REQUEST_MAP",L"LOCALTERM_RENDER_RESPONSE_MAP",L"LOCALTERM_RENDER_REQUEST_EVENT",L"LOCALTERM_RENDER_RESPONSE_EVENT",L"LOCALTERM_RENDER_STOP_EVENT",L"LOCALTERM_RENDER_REQUEST_CAPACITY",L"LOCALTERM_RENDER_RESPONSE_CAPACITY",L"LOCALTERM_RENDER_SURFACE",L"LOCALTERM_RENDER_GENERATION"};
    static const wchar_t control_prefix[]=L"LOCALTERM_RENDER_";
    wchar_t values[9][96], *source=GetEnvironmentStringsW(), *result=NULL;
    const wchar_t **entries=NULL; size_t count=0, chars=1;
    if (!source) return NULL;
    entries=(const wchar_t **)calloc(4096,sizeof(*entries));
    if (!entries) goto done;
    for (const wchar_t *p=source; *p; p+=wcslen(p)+1) {
        if (!_wcsnicmp(p,control_prefix,_countof(control_prefix)-1)) continue;
        if (count>=4087) goto done;
        entries[count++]=p;
    }
    for (size_t i=0;i<9;++i) {
        uint64_t value=i<5?(uint64_t)(uintptr_t)handles[i]:i==5?rc:i==6?sc:i==7?surface:generation;
        if (_snwprintf_s(values[i],_countof(values[i]),_TRUNCATE,L"%ls=%llx",names[i],(unsigned long long)value)<0) goto done;
        entries[count++]=values[i];
    }
    qsort(entries,count,sizeof(*entries),env_order);
    for (size_t i=0;i<count;++i) { size_t n=wcslen(entries[i])+1; if(n>32767-chars) goto done; chars+=n; }
    result=(wchar_t *)calloc(chars,sizeof(wchar_t));
    if (result) { size_t at=0; for(size_t i=0;i<count;++i){size_t n=wcslen(entries[i])+1;memcpy(result+at,entries[i],n*sizeof(wchar_t));at+=n;} }
done:
    free(entries); FreeEnvironmentStringsW(source); return result;
}
static int job_empty(RwClient *c, DWORD *active, DWORD *error) {
    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION info;
    *active=0;*error=0;
    if(!c->job)return 1;
    if(!QueryInformationJobObject(c->job,JobObjectBasicAccountingInformation,&info,sizeof(info),NULL)){
        *active=MAXDWORD;*error=GetLastError();return 0;
    }
    *active=info.ActiveProcesses;return *active==0;
}
static int reap(RwClient *c, uint32_t timeout, RwStatus *s) {
    ULONGLONG started=GetTickCount64(),end=started+timeout;
    DWORD active=MAXDWORD,query_error=0;
    if(c->process){
        DWORD code=STILL_ACTIVE,wait_result=WaitForSingleObject(c->process,timeout);
        if(wait_result!=WAIT_OBJECT_0){
            DWORD error=wait_result==WAIT_FAILED?GetLastError():0;
            fprintf(stderr,"rw reap failure phase=process_wait result=%lu win_error=%lu budget_ms=%lu elapsed_ms=%llu\n",(unsigned long)wait_result,(unsigned long)error,(unsigned long)timeout,(unsigned long long)(GetTickCount64()-started));return 0;
        }
        if(!GetExitCodeProcess(c->process,&code)){
            DWORD error=GetLastError();
            fprintf(stderr,"rw reap failure phase=exit_code win_error=%lu\n",(unsigned long)error);return 0;
        }
        if(s){s->process_exited=1;s->child_exit=code;}
    }
    /* Keep the initial nonblocking readiness probe after a signalled process:
     * the waiting thread may be scheduled late, even for a timely OS signal.
     * Subsequent polls must not start past the original budget, including
     * after an overslept Sleep. Never request more than the remaining time. */
    int first_probe=1;
    for(;;){
        ULONGLONG now=GetTickCount64();
        if(!first_probe&&now>end)break;
        first_probe=0;
        if(job_empty(c,&active,&query_error)){if(s)s->job_empty=1;return 1;}
        now=GetTickCount64();if(now>=end)break;
        Sleep((DWORD)((end-now)<10?(end-now):10));
    }
    fprintf(stderr,"rw reap failure phase=job_empty active=%lu query_error=%lu budget_ms=%lu elapsed_ms=%llu\n",(unsigned long)active,(unsigned long)query_error,(unsigned long)timeout,(unsigned long long)(GetTickCount64()-started));
    return 0;
}
int rw_destroy(RwClient *c, uint32_t timeout, RwStatus *s) {
    int ok=1;
    if(!c)return 1;
    if(c->process && !c->finished){
        if(s)s->forced=1;
        if(c->assigned){if(!TerminateJobObject(c->job,1))ok=0;}
        else if(!TerminateProcess(c->process,1))ok=0;
    }
    if(!reap(c,timeout,s))ok=0;
    if(c->request && !UnmapViewOfFile(c->request))ok=0;
    if(c->response && !UnmapViewOfFile(c->response))ok=0;
    drop(&c->request_event);drop(&c->response_event);drop(&c->stop_event);
    drop(&c->request_map);drop(&c->response_map);drop(&c->process);drop(&c->job);
    free(c);return ok;
}
int rw_open(uint64_t surface,uint64_t generation,uint32_t rc,uint32_t sc,uint32_t timeout,uintptr_t diagnostics,RwClient **out,RwStatus *s){
    SECURITY_ATTRIBUTES sa={sizeof(sa),NULL,TRUE}; STARTUPINFOEXW si; PROCESS_INFORMATION pi;
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limit; SIZE_T attr_bytes=0;
    RwClient *c=NULL; HANDLE io=NULL,log=NULL,allowed[7]; wchar_t *env=NULL,*exe=NULL;
    int attrs=0,ok=0; DWORD error=ERROR_INVALID_PARAMETER; uint32_t stage=1;
    if(s){memset(s,0,sizeof(*s));s->child_exit=STILL_ACTIVE;}
    if(!out)return failure(s,1,error);*out=NULL;
    if(!surface||!generation||!timeout||timeout>60000||rc<RW_PREFIX+RW_HEADER+181||sc<RW_PREFIX+RW_HEADER+20||rc>RW_PREFIX+RW_HEADER+RW_MAX_BODY||sc>RW_PREFIX+RW_HEADER+RW_MAX_BODY)return failure(s,1,error);
    memset(&si,0,sizeof(si));memset(&pi,0,sizeof(pi));memset(&limit,0,sizeof(limit));
    c=(RwClient *)calloc(1,sizeof(*c));exe=(wchar_t *)calloc(32768,sizeof(wchar_t));
    if(!c||!exe){error=ERROR_NOT_ENOUGH_MEMORY;goto end;}
    c->surface=surface;c->generation=generation;c->request_capacity=rc;c->response_capacity=sc;
    c->diagnostics=diagnostics!=0;
    {
        DWORD n=GetModuleFileNameW(NULL,exe,32768);wchar_t *slash;
        if(!n||n>=32768){error=ERROR_BAD_PATHNAME;goto end;}
        slash=wcsrchr(exe,L'\\');if(!slash){error=ERROR_BAD_PATHNAME;goto end;}
        const wchar_t *worker_name=RW_WORKER_NAME;
        if((size_t)(slash-exe)+1+wcslen(worker_name)>=32768){error=ERROR_BAD_PATHNAME;goto end;}
        memcpy(slash+1,worker_name,(wcslen(worker_name)+1)*sizeof(wchar_t));
    }
    stage=2;c->job=CreateJobObjectW(NULL,NULL);limit.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if(!c->job||!SetInformationJobObject(c->job,JobObjectExtendedLimitInformation,&limit,sizeof(limit)))goto os_error;
    stage=3;c->request_map=CreateFileMappingW(INVALID_HANDLE_VALUE,&sa,PAGE_READWRITE,0,rc,NULL);
    c->response_map=CreateFileMappingW(INVALID_HANDLE_VALUE,&sa,PAGE_READWRITE,0,sc,NULL);
    c->request_event=CreateEventW(&sa,FALSE,FALSE,NULL);c->response_event=CreateEventW(&sa,FALSE,FALSE,NULL);c->stop_event=CreateEventW(&sa,TRUE,FALSE,NULL);
    if(!c->request_map||!c->response_map||!c->request_event||!c->response_event||!c->stop_event)goto os_error;
    c->request=(uint8_t *)MapViewOfFile(c->request_map,FILE_MAP_ALL_ACCESS,0,0,rc);
    c->response=(uint8_t *)MapViewOfFile(c->response_map,FILE_MAP_ALL_ACCESS,0,0,sc);
    if(!c->request||!c->response)goto os_error;
    io=CreateFileW(L"NUL",GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,&sa,OPEN_EXISTING,0,NULL);
    if(io==INVALID_HANDLE_VALUE){io=NULL;goto os_error;}
    if(diagnostics){if(!DuplicateHandle(GetCurrentProcess(),(HANDLE)diagnostics,GetCurrentProcess(),&log,0,TRUE,DUPLICATE_SAME_ACCESS))goto os_error;}
    allowed[0]=c->request_map;allowed[1]=c->response_map;allowed[2]=c->request_event;allowed[3]=c->response_event;allowed[4]=c->stop_event;allowed[5]=io;allowed[6]=log;
    env=environment(allowed,rc,sc,surface,generation);if(!env){error=ERROR_NOT_ENOUGH_MEMORY;goto end;}
    stage=4;InitializeProcThreadAttributeList(NULL,1,0,&attr_bytes);
    if(!attr_bytes)goto os_error;
    si.lpAttributeList=(LPPROC_THREAD_ATTRIBUTE_LIST)malloc(attr_bytes);
    if(!si.lpAttributeList){error=ERROR_NOT_ENOUGH_MEMORY;goto end;}
    if(!InitializeProcThreadAttributeList(si.lpAttributeList,1,0,&attr_bytes))goto os_error;attrs=1;
    if(!UpdateProcThreadAttribute(si.lpAttributeList,0,PROC_THREAD_ATTRIBUTE_HANDLE_LIST,allowed,(log?7:6)*sizeof(HANDLE),NULL,NULL))goto os_error;
    si.StartupInfo.cb=sizeof(si);si.StartupInfo.dwFlags=STARTF_USESHOWWINDOW|STARTF_USESTDHANDLES;si.StartupInfo.wShowWindow=SW_HIDE;
    si.StartupInfo.hStdInput=io;si.StartupInfo.hStdOutput=log?log:io;si.StartupInfo.hStdError=log?log:io;
    stage=5;if(!CreateProcessW(exe,NULL,NULL,NULL,TRUE,CREATE_SUSPENDED|CREATE_NO_WINDOW|CREATE_UNICODE_ENVIRONMENT|EXTENDED_STARTUPINFO_PRESENT,env,NULL,&si.StartupInfo,&pi))goto os_error;
    c->process=pi.hProcess;c->primary_thread_id=pi.dwThreadId;
    if(!AssignProcessToJobObject(c->job,c->process))goto os_error;c->assigned=1;
    for(size_t i=0;i<5;++i)if(!SetHandleInformation(allowed[i],HANDLE_FLAG_INHERIT,0))goto os_error;
    if(ResumeThread(pi.hThread)==(DWORD)-1)goto os_error;
    *out=c;c=NULL;ok=1;goto end;
os_error:error=GetLastError();
end:
    if(pi.hThread)CloseHandle(pi.hThread);
    if(attrs)DeleteProcThreadAttributeList(si.lpAttributeList);
    free(si.lpAttributeList);free(env);free(exe);drop(&io);drop(&log);
    if(c)rw_destroy(c,timeout,s);
    if(!ok)return failure(s,stage,error);
    if(s)s->win_error=0;return 1;
}
int rw_call(RwClient *c,const uint8_t *request,size_t n,uint8_t *response,size_t cap,size_t *result,uint32_t timeout,RwStatus *s){
    uint64_t sequence,epoch;DWORD which;HANDLE events[3];size_t length;uint8_t header[RW_HEADER];
    if(result)*result=0;
    if(!c||!request||!response||!result||!timeout||timeout>60000||c->broken||c->finished||c->close_ack||n<RW_HEADER||n>c->request_capacity-RW_PREFIX)return failure(s,6,ERROR_INVALID_PARAMETER);
    sequence=u64le(request+32);epoch=u64le(request+40);
    if(u32le(request)!=0x32525747u||u16le(request+4)!=2||u16le(request+6)!=RW_HEADER||u16le(request+10)!=0||u32le(request+12)!=n-RW_HEADER||u64le(request+16)!=c->surface||u64le(request+24)!=c->generation||sequence<=c->sequence)return failure(s,6,ERROR_INVALID_DATA);
    c->sequence=sequence;c->broken=1;
    if(!ResetEvent(c->response_event))return failure(s,6,GetLastError());
    InterlockedExchange64((volatile LONG64 *)c->request,0);memset(c->request+8,0,8);
    memcpy(c->request+RW_PREFIX,request,n);InterlockedExchange64((volatile LONG64 *)c->request,(LONG64)sequence);
    if(!SetEvent(c->request_event))return failure(s,6,GetLastError());
    if(!RW_BEFORE_REPLY_WAIT(c,&timeout))return failure(s,6,ERROR_TIMEOUT);
    events[0]=c->stop_event;events[1]=c->process;events[2]=c->response_event;
    which=WaitForMultipleObjects(3,events,FALSE,timeout);
    /* Natural close may publish .closed and exit before this thread runs.
     * Only a CLOSE request may consume an already-signaled reply after exit.
     * Never promote timeout/render replies; cancellation retains priority.
     * Full packet validation below and rw_finish(exit0+empty job) still apply. */
    if(which==WAIT_OBJECT_0+1 && u16le(request+8)==10){
        if(WaitForSingleObject(c->stop_event,0)==WAIT_OBJECT_0)return failure(s,6,ERROR_CANCELLED);
        if(WaitForSingleObject(c->response_event,0)==WAIT_OBJECT_0)which=WAIT_OBJECT_0+2;
    }
    if(which!=WAIT_OBJECT_0+2)return failure(s,6,which==WAIT_TIMEOUT?ERROR_TIMEOUT:which==WAIT_OBJECT_0?ERROR_CANCELLED:ERROR_PROCESS_ABORTED);
    if((uint64_t)InterlockedCompareExchange64((volatile LONG64 *)c->response,0,0)!=sequence||u64le(c->response+8)!=0)return failure(s,6,ERROR_INVALID_DATA);
    memcpy(header,c->response+RW_PREFIX,RW_HEADER);
    if(u32le(header+12)>c->response_capacity-RW_PREFIX-RW_HEADER)return failure(s,6,ERROR_INVALID_DATA);
    length=(size_t)u32le(header+12)+RW_HEADER;
    if(length>c->response_capacity-RW_PREFIX||length>cap||u32le(header)!=0x32525747u||u16le(header+4)!=2||u16le(header+6)!=RW_HEADER||u16le(header+10)!=0||u64le(header+16)!=c->surface||u64le(header+24)!=c->generation||u64le(header+32)!=sequence||u64le(header+40)!=epoch)return failure(s,6,ERROR_INVALID_DATA);
    memcpy(response,c->response+RW_PREFIX,length);
    if((uint64_t)InterlockedCompareExchange64((volatile LONG64 *)c->response,0,0)!=sequence||memcmp(header,c->response+RW_PREFIX,RW_HEADER)||memcmp(header,response,RW_HEADER))return failure(s,6,ERROR_INVALID_DATA);
    c->close_ack=u16le(request+8)==10&&u16le(header+8)==11&&length==RW_HEADER;
    sample_owned_resources(c);
    if(s){s->close_ack=c->close_ack;s->win_error=0;}c->broken=0;*result=length;return 1;
}
void rw_cancel(RwClient *c){if(c&&c->stop_event)SetEvent(c->stop_event);}
int rw_finish(RwClient *c,uint32_t timeout,RwStatus *s){
    DWORD code=STILL_ACTIVE;
    if(!c||c->broken||!c->close_ack||!timeout||timeout>60000)return failure(s,7,ERROR_INVALID_STATE);
    if(!reap(c,timeout,s))return failure(s,7,ERROR_TIMEOUT);
    if(!GetExitCodeProcess(c->process,&code)||code!=0)return failure(s,7,ERROR_PROCESS_ABORTED);
    report_owned_resources(c); /* CPU complete after exit; memory peak sampled live. */
    c->finished=1;if(s){s->close_ack=1;s->win_error=0;}return 1;
}
