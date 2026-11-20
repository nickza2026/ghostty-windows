#define UNICODE
#define _UNICODE
#include <windows.h>
#include <evntrace.h>
#include <evntcons.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>

/* Offline, schema-specific parser. No TDH inference or wall-clock conversion.
 * Schema: Microsoft/perfview KernelTraceEventParser.cs, SHA256
 * 2245CCC62B0D933190068A18344BC64749A2893BD9740A79706BA7FE5E86C778
 * lines 2654,3030,9253,11022,11098 (StackWalk/ObjectHandle/Duplicate).
 * The controller must qualify duplicate source/target semantics separately.
 */
#define RECORD_CAP 16384u
#define BYTE_CAP (8u * 1024u * 1024u)
#define FRAME_CAP 192u
static const GUID stack_guid = {0xdef2fe46,0x7bd6,0x4b80,{0xbd,0x94,0xf5,0x7f,0xe2,0x0d,0x0c,0xe3}};
static const GUID handle_guid = {0x89497f50,0xeffe,0x4440,{0x8c,0xf2,0xce,0x6b,0x1c,0xdc,0xac,0xa7}};
typedef struct {
    unsigned kind, opcode, version, frames;
    ULONG pid, tid, source_pid, target_pid, handle, target_handle;
    USHORT type;
    ULONGLONG qpc, event_qpc, object, pcs[FRAME_CAP];
} Record;
static ULONG pids[2];
static HANDLE output = INVALID_HANDLE_VALUE;
static ULONGLONG started, bytes, selected, other, unsupported, malformed, versions;
static ULONG stop_error;
static BOOL stopped;
static char line[16384];
static BOOL version_supported(const Record *r) {
    if(r->version==0)return TRUE; /* legacy Microsoft fixed-prefix schema */
    return r->kind==1&&r->opcode==34?r->version==3:r->version==2;
}
static BOOL wanted(ULONG p) { return p == pids[0] || p == pids[1]; }
static BOOL get(const BYTE *p, size_t n, size_t at, void *out, size_t len) {
    if (!p || at > n || len > n-at) return FALSE;
    memcpy(out,p+at,len); return TRUE;
}
#define GET(at,field) do { if (!get(p,n,at,&r->field,sizeof(r->field))) return -1; } while(0)
/* 0 = unrelated; 1 = selected; -1 = malformed; -2 = unsupported.
 * Owner selection precedes emission; no unrelated payload is ever emitted. */
static int decode(const EVENT_RECORD *e, Record *r) {
    const BYTE *p = (const BYTE *)e->UserData;
    size_t n = e->UserDataLength;
    BOOL stack = !memcmp(&e->EventHeader.ProviderId,&stack_guid,sizeof(GUID));
    BOOL handle = !memcmp(&e->EventHeader.ProviderId,&handle_guid,sizeof(GUID));
    unsigned op = e->EventHeader.EventDescriptor.Opcode;
    memset(r,0,sizeof(*r));
    if ((!stack && !handle) || (stack && op != 32) || (handle && (op < 32 || op > 34))) return 0;
    r->pid=e->EventHeader.ProcessId; r->tid=e->EventHeader.ThreadId;
    r->qpc=(ULONGLONG)e->EventHeader.TimeStamp.QuadPart;
    r->opcode=op; r->version=e->EventHeader.EventDescriptor.Version;
    if (stack) {
        r->kind=2;
        GET(0,event_qpc); GET(8,pid); GET(12,tid);
        if (!wanted(r->pid)) return 0;
        if (!(e->EventHeader.Flags & EVENT_HEADER_FLAG_64_BIT_HEADER) ||
            (e->EventHeader.Flags & EVENT_HEADER_FLAG_32_BIT_HEADER)) return -2;
        if (n < 16 || (n-16)%8 || (n-16)/8 > FRAME_CAP) return -1;
        r->frames=(unsigned)((n-16)/8);
        if (!r->frames) return -1;
        for (unsigned i=0;i<r->frames;i++)
            if (!get(p,n,16+8*i,&r->pcs[i],8)) return -1;
    } else {
        r->kind=1;
        if (op == 34) {
            /* PID offsets follow the kernel pointer size; select owners before
             * rejecting a selected 32-bit event. Other processes are counts only. */
            if (e->EventHeader.Flags & EVENT_HEADER_FLAG_32_BIT_HEADER) {
                GET(12,target_pid); GET(18,source_pid);
                return wanted(r->pid)||wanted(r->source_pid)||wanted(r->target_pid)?-2:0;
            }
            GET(16,target_pid); GET(22,source_pid);
            if (!wanted(r->pid) && !wanted(r->source_pid) && !wanted(r->target_pid)) return 0;
            if (!(e->EventHeader.Flags & EVENT_HEADER_FLAG_64_BIT_HEADER)) return -2;
            /* Microsoft decoder consumes this prefix even when an opaque
             * name/extra tail is present. Never inspect or emit that tail. */
            if (n < 26) return -1;
            GET(0,object); GET(8,handle); GET(12,target_handle); GET(20,type);
        } else {
            if (!wanted(r->pid)) return 0;
            if (!(e->EventHeader.Flags & EVENT_HEADER_FLAG_64_BIT_HEADER) ||
                (e->EventHeader.Flags & EVENT_HEADER_FLAG_32_BIT_HEADER)) return -2;
            if (n < 14) return -1; /* fixed prefix only; object names discarded */
            GET(0,object); GET(8,handle); GET(12,type);
        }
    }
    return 1;
}
#undef GET
static void fail(ULONG error) { stopped=TRUE; if (!stop_error) stop_error=error; }
static BOOL emit(const char *s, BOOL final) {
    size_t n=strlen(s); DWORD written=0;
    /* Reserve a bounded final result even on a cap failure. */
    if (bytes+n > BYTE_CAP-(final ? 0 : 2048)) { fail(ERROR_BUFFER_OVERFLOW); return FALSE; }
    if (!WriteFile(output,s,(DWORD)n,&written,NULL) || written != n) {
        fail(ERROR_WRITE_FAULT); return FALSE;
    }
    bytes+=n; return TRUE;
}
static BOOL deadline(void) {
    if (GetTickCount64()-started >= 10000) fail(ERROR_TIMEOUT);
    return !stopped;
}
static ULONG WINAPI buffer_callback(EVENT_TRACE_LOGFILEW *log) {
    (void)log; return deadline() ? TRUE : FALSE;
}
static void WINAPI event_callback(EVENT_RECORD *e) {
    Record r; int result; int used;
    if (!deadline()) return;
    result=decode(e,&r);
    if (!result) { other++; return; }
    if (result < 0) {
        if(wanted(r.pid)||wanted(r.source_pid)||wanted(r.target_pid)) {
            snprintf(line,sizeof(line),"{\"kind\":\"schema_error\",\"pid\":%lu,\"opcode\":%u,\"flags\":%u,\"version\":%u,\"bytes\":%u,\"decode_status\":%d}\n",
                r.pid,e->EventHeader.EventDescriptor.Opcode,e->EventHeader.Flags,e->EventHeader.EventDescriptor.Version,e->UserDataLength,result);
            emit(line,FALSE);
        }
        if (result == -2) unsupported++; else malformed++;
        fail(ERROR_INVALID_DATA); return;
    }
    if (selected >= RECORD_CAP) { fail(ERROR_BUFFER_OVERFLOW); return; }
    selected++;
    /* OS26200: create/close/stack v2, duplicate v3. Fixed prefixes are
     * independently checked by cross-PID API results and known caller PCs. */
    if (!version_supported(&r)) versions++;
    used=snprintf(line,sizeof(line),
        "{\"kind\":\"%s\",\"sequence\":%llu,\"qpc\":\"0x%016llx\",\"executingPID\":%lu,\"executingTID\":%lu,\"opcode\":%u,\"version\":%u,\"unsupportedVersion\":%s",
        r.kind==2?"stack":"handle",selected,r.qpc,e->EventHeader.ProcessId,
        e->EventHeader.ThreadId,r.opcode,r.version,version_supported(&r)?"false":"true");
    if (r.kind==2) {
        used+=snprintf(line+used,sizeof(line)-used,
            ",\"eventQPC\":\"0x%016llx\",\"pid\":%lu,\"tid\":%lu,\"frames\":[",r.event_qpc,r.pid,r.tid);
        for (unsigned i=0;i<r.frames;i++)
            used+=snprintf(line+used,sizeof(line)-used,"%s\"0x%016llx\"",i?",":"",r.pcs[i]);
        used+=snprintf(line+used,sizeof(line)-used,"]}\n");
    } else {
        used+=snprintf(line+used,sizeof(line)-used,
            ",\"ownerPID\":%lu,\"object\":\"0x%016llx\",\"handle\":%lu,\"objectType\":%u",r.pid,r.object,r.handle,r.type);
        if (r.opcode==34) used+=snprintf(line+used,sizeof(line)-used,
            ",\"sourceHandle\":%lu,\"targetHandle\":%lu,\"sourceProcessId\":%lu,\"targetProcessId\":%lu,\"duplicateSemanticsQualified\":false",
            r.handle,r.target_handle,r.source_pid,r.target_pid);
        used+=snprintf(line+used,sizeof(line)-used,"}\n");
    }
    if (used < 0 || (size_t)used >= sizeof(line)) { fail(ERROR_BUFFER_OVERFLOW); return; }
    emit(line,FALSE);
}

/* Reject remote paths, reparse files, foreign owners, and broad allow ACLs.
 * Keep this handle open without write/delete sharing for the entire decode. */
static HANDLE secure_input(const WCHAR *path) {
    WCHAR full[32768], root[4]; HANDLE file=INVALID_HANDLE_VALUE, token=NULL;
    BYTE token_data[4096], security[65536]; DWORD need=0; PSID owner=NULL;
    PACL acl=NULL; BOOL present=FALSE, defaulted=FALSE; BY_HANDLE_FILE_INFORMATION info;
    if (!GetFullPathNameW(path,32768,full,NULL) || full[1]!=L':' || full[2]!=L'\\') return file;
    root[0]=full[0]; root[1]=L':'; root[2]=L'\\'; root[3]=0;
    if (GetDriveTypeW(root)!=DRIVE_FIXED) return file;
    file=CreateFileW(full,READ_CONTROL|GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,
        FILE_FLAG_OPEN_REPARSE_POINT,NULL);
    if (file==INVALID_HANDLE_VALUE) return file;
    if (!GetFileInformationByHandle(file,&info) || (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY))) goto bad;
    if (!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)) goto bad;
    if (!GetTokenInformation(token,TokenUser,token_data,sizeof(token_data),&need)) goto bad;
    if (!GetKernelObjectSecurity(file,OWNER_SECURITY_INFORMATION|DACL_SECURITY_INFORMATION,
            security,sizeof(security),&need) ||
        !GetSecurityDescriptorOwner(security,&owner,&defaulted) ||
        !EqualSid(owner,((TOKEN_USER *)token_data)->User.Sid) ||
        !GetSecurityDescriptorDacl(security,&present,&acl,&defaulted) || !present || !acl) goto bad;
    for (DWORD i=0;i<acl->AceCount;i++) {
        ACE_HEADER *ace=NULL;
        if (!GetAce(acl,i,(void **)&ace)) goto bad;
        if (ace->AceType==ACCESS_DENIED_ACE_TYPE) continue;
        if (ace->AceType!=ACCESS_ALLOWED_ACE_TYPE) goto bad;
        if (!EqualSid(&((ACCESS_ALLOWED_ACE *)ace)->SidStart,owner) &&
            !IsWellKnownSid(&((ACCESS_ALLOWED_ACE *)ace)->SidStart,WinLocalSystemSid)) goto bad;
    }
    CloseHandle(token); return file;
bad:
    if (token) CloseHandle(token);
    CloseHandle(file); return INVALID_HANDLE_VALUE;
}

static int selftest(void) {
    BYTE b[16+8*(FRAME_CAP+1)]={0}; EVENT_RECORD e; Record r;
    ULONG a=101, z=202, sh=0x1234, th=0x5678; USHORT type=0x9abc;
    ULONGLONG object=0x123456789abcdef0ULL;
    memset(&e,0,sizeof(e)); pids[0]=a; pids[1]=z;
    e.UserData=b; e.EventHeader.Flags=EVENT_HEADER_FLAG_64_BIT_HEADER;
    e.EventHeader.ProviderId=handle_guid; e.EventHeader.EventDescriptor.Opcode=34;
    e.EventHeader.ProcessId=999; e.UserDataLength=26;
    memcpy(b,&object,8); memcpy(b+8,&sh,4); memcpy(b+12,&th,4);
    memcpy(b+16,&a,4); memcpy(b+20,&type,2); memcpy(b+22,&z,4);
    if (decode(&e,&r)!=1 || r.object!=object || r.source_pid!=z || r.target_pid!=a ||
        r.handle!=sh || r.target_handle!=th || r.type!=type) return 1;
    e.UserDataLength=25; if (decode(&e,&r)!=-1) return 2;
    e.UserDataLength=26; e.EventHeader.Flags=EVENT_HEADER_FLAG_32_BIT_HEADER;
    e.EventHeader.ProcessId=a;
    if (decode(&e,&r)!=-2) return 3;
    e.EventHeader.Flags=EVENT_HEADER_FLAG_64_BIT_HEADER;
    e.EventHeader.EventDescriptor.Opcode=32; e.UserDataLength=14;
    memcpy(b+12,&type,2);
    e.EventHeader.ProcessId=a;
    if (decode(&e,&r)!=1 || r.handle!=sh || r.type!=type || r.object!=object) return 4;
    e.UserDataLength=13; if (decode(&e,&r)!=-1) return 5;
    e.EventHeader.ProviderId=stack_guid; e.UserDataLength=24;
    memcpy(b+8,&a,4); memcpy(b+12,&z,4); memcpy(b+16,&object,8);
    if (decode(&e,&r)!=1 || r.pid!=a || r.tid!=z || r.pcs[0]!=object || r.frames!=1) return 6;
    e.UserDataLength=23; if (decode(&e,&r)!=-1) return 7;
    e.UserDataLength=sizeof(b); if (decode(&e,&r)!=-1) return 8;
    e.UserDataLength=15; if (decode(&e,&r)!=-1) return 9;
    e.UserDataLength=24; memcpy(b+8,&e.EventHeader.ProcessId,4);
    e.EventHeader.ProcessId=999; memcpy(b+8,&e.EventHeader.ProcessId,4);
    if (decode(&e,&r)!=0) return 10;
    e.EventHeader.Flags=EVENT_HEADER_FLAG_32_BIT_HEADER;
    if (decode(&e,&r)!=0) return 11; /* unrelated 32-bit stack is not our data */
    memset(b,0,sizeof(b));
    e.EventHeader.ProviderId=handle_guid;e.EventHeader.EventDescriptor.Opcode=32;
    e.EventHeader.ProcessId=a;e.EventHeader.Flags=EVENT_HEADER_FLAG_64_BIT_HEADER;
    e.UserDataLength=16;memcpy(b,&object,8);memcpy(b+8,&sh,4);memcpy(b+12,&type,2);
    if(decode(&e,&r)!=1)return 12; /* empty UTF-16 name/zero padding */
    b[14]=1;if(decode(&e,&r)!=1)return 13; /* opaque tail is never decoded */
    e.EventHeader.EventDescriptor.Version=2;e.UserDataLength=156;
    if(decode(&e,&r)!=1||r.object!=object||r.handle!=sh||r.type!=type)return 14;
    if(!version_supported(&r))return 15;
    r.kind=1;r.opcode=34;r.version=3;
    if(!version_supported(&r))return 16;
    r.version=4;if(version_supported(&r))return 17;
    return 0;
}
static BOOL parse_pid(const WCHAR *s, ULONG *v) {
    unsigned long long n=0;
    if (!*s) return FALSE;
    for (;*s;s++) { if (*s<L'0'||*s>L'9') return FALSE; n=n*10+(*s-L'0'); if(n>0xffffffffULL) return FALSE; }
    *v=(ULONG)n; return n!=0;
}
int WINAPI WinMain(HINSTANCE instance,HINSTANCE previous,LPSTR command,int show) {
    int argc=0, exit_code=1; LPWSTR *argv=CommandLineToArgvW(GetCommandLineW(),&argc);
    EVENT_TRACE_LOGFILEW log; TRACEHANDLE trace=INVALID_PROCESSTRACE_HANDLE;
    HANDLE input=INVALID_HANDLE_VALUE; ULONG status=ERROR_INVALID_PARAMETER;
    (void)instance; (void)previous; (void)command; (void)show;
    if (!argv) return 2;
    if (argc==2 && !wcscmp(argv[1],L"--selftest")) { exit_code=selftest(); LocalFree(argv); return exit_code; }
    if (argc!=5 || !parse_pid(argv[3],&pids[0]) || !parse_pid(argv[4],&pids[1])) goto done;
    output=CreateFileW(argv[2],GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);
    if (output==INVALID_HANDLE_VALUE) goto done;
    input=secure_input(argv[1]);
    if(input==INVALID_HANDLE_VALUE) { status=ERROR_ACCESS_DENIED; goto result; }
    memset(&log,0,sizeof(log)); log.LogFileName=argv[1];
    log.ProcessTraceMode=PROCESS_TRACE_MODE_EVENT_RECORD|PROCESS_TRACE_MODE_RAW_TIMESTAMP;
    log.EventRecordCallback=event_callback; log.BufferCallback=buffer_callback;
    started=GetTickCount64(); trace=OpenTraceW(&log);
    if(trace==INVALID_PROCESSTRACE_HANDLE) { status=GetLastError(); goto result; }
    /* QPC framing only; no guessed interpretation of cycle/system clocks. */
    if(log.LogfileHeader.ReservedFlags!=1 || log.LogfileHeader.PointerSize!=8) {
        unsupported++; status=ERROR_NOT_SUPPORTED; goto result;
    }
    status=ProcessTrace(&trace,1,NULL,NULL);
    deadline();
    if (log.EventsLost || log.LogfileHeader.EventsLost || log.LogfileHeader.BuffersLost) fail(ERROR_INVALID_DATA);
result:
    if(trace!=INVALID_PROCESSTRACE_HANDLE) CloseTrace(trace);
    if(stop_error) status=stop_error;
    snprintf(line,sizeof(line),
        "{\"kind\":\"result\",\"qualification\":\"parse-only-not-callstack-gate\",\"ok\":%s,\"error\":%lu,\"selectedRecords\":%llu,\"otherEvents\":%llu,\"malformed\":%llu,\"unsupportedPayloads\":%llu,\"unsupportedVersions\":%llu,\"recordCap\":16384,\"byteCap\":8388608,\"frameCap\":192,\"deadlineMs\":10000,\"source\":\"Microsoft-PerfView-KernelTraceEventParser\",\"sourceSHA256\":\"2245CCC62B0D933190068A18344BC64749A2893BD9740A79706BA7FE5E86C778\",\"framing\":\"classic-provider-opcode-64bit-raw-QPC\",\"duplicateSemanticsQualified\":false}\n",
        status==ERROR_SUCCESS && !versions?"true":"false",status,selected,other,malformed,unsupported,versions);
    if(emit(line,TRUE) && status==ERROR_SUCCESS && !versions) exit_code=0;
done:
    if(input!=INVALID_HANDLE_VALUE) CloseHandle(input);
    if(output!=INVALID_HANDLE_VALUE) CloseHandle(output);
    LocalFree(argv); return exit_code;
}
