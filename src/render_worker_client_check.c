/* Controlled check executable ONLY. Never compiled into the terminal host.
 * Fault operations use the client's own process handle + verified owned job;
 * no PID argument, process discovery, system/driver changes or external kill. */
#include "render_worker_client.h"
#include <wchar.h>
static const wchar_t *rw_check_worker_name(void);
#define RW_WORKER_NAME rw_check_worker_name()
static int rw_check_before_reply_wait(RwClient *c,uint32_t *timeout);
#define RW_BEFORE_REPLY_WAIT(c,t) rw_check_before_reply_wait(c,t)
#define rw_open rw_check_open_impl
#include "render_worker_client.c"
#undef rw_open
/* Private diagnostic only: preserve real worker teardown/offscreen evidence in
 * the supervisor's existing stderr file. Production diagnostics stay opt-in. */
int rw_open(uint64_t surface,uint64_t generation,uint32_t rc,uint32_t sc,uint32_t timeout,uintptr_t diagnostics,RwClient **out,RwStatus *s){
    HANDLE log=GetStdHandle(STD_ERROR_HANDLE);
    if(!diagnostics&&log&&log!=INVALID_HANDLE_VALUE)diagnostics=(uintptr_t)log;
    return rw_check_open_impl(surface,generation,rc,sc,timeout,diagnostics,out,s);
}
static int rw_check_fault_worker=0;
static const wchar_t *rw_check_worker_name(void){return rw_check_fault_worker?L"localterm-render-late-reply-test-worker.exe":L"localterm-render-text-worker.exe";}
void rw_check_select_late_reply_worker(int enabled){rw_check_fault_worker=enabled;}
int rw_check_late_rendered_owned(RwClient *c,uint64_t *rendered,uint64_t *published,uint64_t *sequence,uint8_t *rgba){
    BOOL inside=FALSE;
    DWORD exit_code=STILL_ACTIVE;
    ULONGLONG end=GetTickCount64()+1000;
    volatile LONG64 *marker;
    if(!c||!c->assigned||!c->process||c->response_capacity<256||!GetExitCodeProcess(c->process,&exit_code))return 0;
    if(exit_code==STILL_ACTIVE&&(!IsProcessInJob(c->process,c->job,&inside)||!inside))return 0;
    marker=(volatile LONG64 *)(c->response+c->response_capacity-32);
    while(InterlockedCompareExchange64(marker+1,0,0)==0){if(GetTickCount64()>=end)return 0;Sleep(1);}
    *published=(uint64_t)InterlockedCompareExchange64(marker+1,0,0);
    *rendered=(uint64_t)InterlockedCompareExchange64(marker,0,0);
    *sequence=(uint64_t)InterlockedCompareExchange64(marker+2,0,0);
    if(*sequence!=c->sequence||(uint64_t)InterlockedCompareExchange64((volatile LONG64 *)c->response,0,0)!=c->sequence||u16le(c->response+RW_PREFIX+8)!=9||u32le(c->response+RW_PREFIX+12)!=144)return 0;
    if(u32le(c->response+RW_PREFIX+RW_HEADER)!=8||u32le(c->response+RW_PREFIX+RW_HEADER+4)!=4||u32le(c->response+RW_PREFIX+RW_HEADER+8)!=32||u32le(c->response+RW_PREFIX+RW_HEADER+12)!=1)return 0;
    memcpy(rgba,c->response+RW_PREFIX+RW_HEADER+16,128);
    return 1;
}
static int rw_check_close_exit_armed=0,rw_check_close_exit_observed=0;
int rw_check_arm_close_exit_before_wait(RwClient *c) {
    BOOL inside=FALSE;
    if(!c||!c->assigned||!c->process||c->finished||!IsProcessInJob(c->process,c->job,&inside)||!inside)return 0;
    rw_check_close_exit_armed=1;rw_check_close_exit_observed=0;return 1;
}
int rw_check_close_exit_was_observed(void){return rw_check_close_exit_observed;}
int rw_check_arm_cancel_close_exit_before_wait(RwClient *c){
    if(!rw_check_arm_close_exit_before_wait(c))return 0;
    rw_check_close_exit_armed=2;return 1;
}
static int rw_check_before_reply_wait(RwClient *c,uint32_t *timeout) {
    ULONGLONG started,elapsed;
    int mode=rw_check_close_exit_armed;
    if(!rw_check_close_exit_armed)return 1;
    rw_check_close_exit_armed=0;
    if(u16le(c->request+RW_PREFIX+8)!=10)return 0;
    started=GetTickCount64();
    if(WaitForSingleObject(c->process,*timeout)!=WAIT_OBJECT_0)return 0;
    elapsed=GetTickCount64()-started;
    if(elapsed>=*timeout)return 0;
    *timeout-=(uint32_t)elapsed; /* Test wait shares, never extends, call budget. */
    if((uint64_t)InterlockedCompareExchange64((volatile LONG64 *)c->response,0,0)!=c->sequence||u16le(c->response+RW_PREFIX+8)!=11)return 0;
    /* Observe and restore the real auto-reset notification, not an invented ACK. */
    if(WaitForSingleObject(c->response_event,0)!=WAIT_OBJECT_0||!SetEvent(c->response_event))return 0;
    rw_check_close_exit_observed=1;
    if(mode==2)rw_cancel(c); /* All three signals ready: stop must still win. */
    return 1;
}
_Static_assert(sizeof(RwStatus)==28,"Zig/C status ABI");
int rw_check_kill_owned(RwClient *c) {
    BOOL inside=FALSE;
    if(!c||!c->assigned||!c->process||!c->job||c->finished)return 0;
    if(!IsProcessInJob(c->process,c->job,&inside)||!inside)return 0;
    if(GetProcessId(c->process)==GetCurrentProcessId())return 0;
    return TerminateProcess(c->process,77)&&WaitForSingleObject(c->process,5000)==WAIT_OBJECT_0;
}
/* The test calls this only after a validated hello, before any GPU draw. The
 * primary thread is idle in the protocol loop; driver threads are NOT paused. */
HANDLE rw_check_pause_owned(RwClient *c) {
    BOOL inside=FALSE;HANDLE thread;DWORD previous;
    if(!c||!c->assigned||!c->process||!c->job||!c->primary_thread_id||c->finished||c->broken)return NULL;
    if(!IsProcessInJob(c->process,c->job,&inside)||!inside)return NULL;
    thread=OpenThread(THREAD_SUSPEND_RESUME|THREAD_QUERY_LIMITED_INFORMATION,FALSE,c->primary_thread_id);
    if(!thread)return NULL;
    if(GetProcessIdOfThread(thread)!=GetProcessId(c->process)){CloseHandle(thread);return NULL;}
    previous=SuspendThread(thread);
    if(previous!=(DWORD)0){if(previous!=(DWORD)-1)ResumeThread(thread);CloseHandle(thread);return NULL;}
    return thread;
}
int rw_check_resume_owned(HANDLE thread) {
    DWORD previous=ResumeThread(thread);BOOL closed=CloseHandle(thread);
    return previous==1&&closed;
}
int rw_check_late_close_owned(RwClient *c) {
    HANDLE events[2];const uint8_t *header;
    if(!c||!c->assigned||!c->broken)return 0;
    events[0]=c->response_event;events[1]=c->process;
    if(WaitForMultipleObjects(2,events,FALSE,5000)!=WAIT_OBJECT_0)return 0;
    if((uint64_t)InterlockedCompareExchange64((volatile LONG64 *)c->response,0,0)!=c->sequence)return 0;
    header=c->response+RW_PREFIX;
    return u32le(header)==0x32525747u&&u16le(header+8)==11&&u32le(header+12)==0&&
        u64le(header+16)==c->surface&&u64le(header+24)==c->generation&&u64le(header+32)==c->sequence;
}
