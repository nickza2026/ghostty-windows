// GPU-frame component experiment; parent intentionally has no OpenGL imports.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "../../src/gpu_frame_protocol.h"
_Static_assert(offsetof(GpuFrameMap, pixels) == GF_HEADER_BYTES, "wire ABI");
typedef struct { DWORD handles,gdi,user,threads; } Counts;
typedef struct { HWND hwnd; HDC dc; HBITMAP bitmap; HGDIOBJ old; unsigned char *bits; int w,h,painted,failed,registered; } View;
static const wchar_t *cls = L"LocaltermGpuFrameIpcPoc";
static int physical_coordinates(void){
    typedef BOOL (WINAPI *SetDpi)(HANDLE);
    FARPROC raw=GetProcAddress(GetModuleHandleW(L"user32.dll"),"SetProcessDpiAwarenessContext");
    SetDpi set=NULL;
    if(!raw||sizeof(set)!=sizeof(raw))return 0;
    memcpy(&set,&raw,sizeof(set));
    return set((HANDLE)(intptr_t)-4)!=0; // Process-local per-monitor-v2, no system setting.
}
static int gui(DWORD kind,DWORD *out) { SetLastError(0); *out=GetGuiResources(GetCurrentProcess(),kind); return *out || GetLastError()==0; }
static int counts(Counts *c) {
    THREADENTRY32 t={0}; HANDLE s; DWORD e;
    if (!gui(0,&c->gdi)||!gui(1,&c->user)) return 0;
    c->threads=0; s=CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD,0);
    if(s==INVALID_HANDLE_VALUE) return 0;
    t.dwSize=sizeof(t);
    if(!Thread32First(s,&t)){CloseHandle(s);return 0;}
    do{if(t.th32OwnerProcessID==GetCurrentProcessId())++c->threads;t.dwSize=sizeof(t);}while(Thread32Next(s,&t));
    e=GetLastError();CloseHandle(s);
    return e==ERROR_NO_MORE_FILES && GetProcessHandleCount(GetCurrentProcess(),&c->handles);
}
static int no_gpu(void){return !GetModuleHandleW(L"opengl32.dll")&&!GetModuleHandleW(L"atio6axx.dll")&&!GetModuleHandleW(L"amdihk64.dll");}
static LRESULT CALLBACK wnd(HWND h,UINT msg,WPARAM wp,LPARAM lp){
    View *v=(View *)GetWindowLongPtrW(h,GWLP_USERDATA);
    if(msg==WM_NCCREATE){v=(View *)((CREATESTRUCTW *)lp)->lpCreateParams;SetWindowLongPtrW(h,GWLP_USERDATA,(LONG_PTR)v);}
    if(msg==WM_MOUSEACTIVATE)return MA_NOACTIVATE;
    if(msg==WM_ERASEBKGND)return 1;
    if(msg==WM_PAINT){PAINTSTRUCT p;HDC dc=BeginPaint(h,&p);if(!dc){if(v)v->failed=1;return 0;}
        if(v&&v->bitmap){if(!BitBlt(dc,0,0,v->w,v->h,v->dc,0,0,SRCCOPY))v->failed=1;else ++v->painted;}
        if(!EndPaint(h,&p)&&v)v->failed=1;return 0;}
    return DefWindowProcW(h,msg,wp,lp);
}
static int drop_view(View *v){
    int ok=1;
    if(v->bitmap){HGDIOBJ old=SelectObject(v->dc,v->old);if(!old||old==HGDI_ERROR)ok=0;if(!DeleteObject(v->bitmap))ok=0;v->bitmap=NULL;}
    if(v->dc){if(!DeleteDC(v->dc))ok=0;v->dc=NULL;}
    if(v->hwnd){if(!DestroyWindow(v->hwnd))ok=0;v->hwnd=NULL;}
    if(v->registered){if(!UnregisterClassW(cls,GetModuleHandleW(NULL)))ok=0;v->registered=0;}
    return ok;
}
static int view_init(View *v){
    WNDCLASSEXW c={0};RECT r;
    c.cbSize=sizeof(c);c.lpfnWndProc=wnd;c.hInstance=GetModuleHandleW(NULL);c.lpszClassName=cls;
    if(!RegisterClassExW(&c))return 0;
    v->registered=1;
    int x=GetSystemMetrics(SM_XVIRTUALSCREEN)+GetSystemMetrics(SM_CXVIRTUALSCREEN)+64;
    int y=GetSystemMetrics(SM_YVIRTUALSCREEN);
    v->hwnd=CreateWindowExW(WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW,cls,L"GPU IPC owned offscreen fixture",WS_POPUP,x,y,256,128,NULL,NULL,c.hInstance,v);
    if(!v->hwnd || !GetWindowRect(v->hwnd,&r) || r.left<GetSystemMetrics(SM_XVIRTUALSCREEN)+GetSystemMetrics(SM_CXVIRTUALSCREEN))return 0;
    v->dc=CreateCompatibleDC(NULL);if(!v->dc)return 0;
    ShowWindow(v->hwnd,SW_SHOWNOACTIVATE);
    // The launcher's STARTF_USESHOWWINDOW may override the first ShowWindow.
    // Enforce a real visible-but-offscreen window without ever activating it.
    if(!SetWindowPos(v->hwnd,NULL,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE|SWP_SHOWWINDOW)||!IsWindowVisible(v->hwnd))return 0;
    if(!GetWindowRect(v->hwnd,&r)||r.left<GetSystemMetrics(SM_XVIRTUALSCREEN)+GetSystemMetrics(SM_CXVIRTUALSCREEN))return 0;
    printf("OFFSCREEN x=%d y=%d noactivate=1 visible=1\n",x,y);
    return 1;
}
static int save_bmp(const wchar_t *dir,const View *v){
    wchar_t path[4096];FILE *f=NULL;BITMAPFILEHEADER file={0};BITMAPINFOHEADER info={0};
    _snwprintf_s(path,_countof(path),_TRUNCATE,L"%s\\frame-odd.bmp",dir);
    if(_wfopen_s(&f,path,L"wbx")||!f)return 0;
    DWORD size=(DWORD)(v->w*v->h*4);
    file.bfType=0x4d42;file.bfOffBits=sizeof(file)+sizeof(info);file.bfSize=file.bfOffBits+size;
    info.biSize=sizeof(info);info.biWidth=v->w;info.biHeight=-v->h;info.biPlanes=1;info.biBitCount=32;info.biSizeImage=size;
    int ok=fwrite(&file,1,sizeof(file),f)==sizeof(file)&&fwrite(&info,1,sizeof(info),f)==sizeof(info)&&fwrite(v->bits,1,size,f)==size;
    if(fclose(f))ok=0;return ok;
}
static int frame_valid(GpuFrameMap *m,uint32_t seq,uint32_t epoch,uint32_t w,uint32_t h){
    LONG committed=InterlockedCompareExchange((volatile LONG *)&m->commit,0,0);
    if(committed!=(LONG)seq||m->status!=GF_FRAME||m->response_magic!=GF_MAGIC||m->response_version!=GF_VERSION||m->header_bytes!=GF_HEADER_BYTES||
       m->frame_sequence!=seq||m->frame_epoch!=epoch||m->frame_width!=w||m->frame_height!=h||w<2||h<2||w>GF_MAX_W||h>GF_MAX_H||
       m->stride!=w*4u||m->payload_bytes!=w*h*4u||m->payload_bytes>GF_CAPACITY||m->capacity!=GF_CAPACITY||m->mapping_bytes!=sizeof(*m))return 0;
    return 1;
}
static int present(View *v,GpuFrameMap *m,uint32_t seq,uint32_t epoch,uint32_t w,uint32_t h){
    unsigned char rgba[GF_CAPACITY],bgra[GF_CAPACITY];BITMAPINFO info={0};
    if(!frame_valid(m,seq,epoch,w,h))return 0;
    // Copy size derives ONLY from the bounded parent request, never a second
    // untrusted shared-header read (even a misbehaving producer cannot expand it).
    memcpy(rgba,m->pixels,(size_t)w*h*4u);MemoryBarrier();
    if(!frame_valid(m,seq,epoch,w,h))return 0;
    static const unsigned char color[4][4]={{255,0,0,255},{0,255,0,255},{0,0,255,255},{255,255,255,255}};
    for(uint32_t y=0;y<h;++y)for(uint32_t x=0;x<w;++x){
        uint32_t from=((h-1-y)*w+x)*4;uint32_t to=(y*w+x)*4;
        uint32_t q=((h-1-y)<h/2?0u:2u)+(x<w/2?0u:1u);
        if(memcmp(rgba+from,color[q],4))return 0;
        bgra[to]=rgba[from+2];bgra[to+1]=rgba[from+1];bgra[to+2]=rgba[from];bgra[to+3]=255;
    }
    if(v->bitmap){HGDIOBJ old=SelectObject(v->dc,v->old);if(!old||old==HGDI_ERROR||!DeleteObject(v->bitmap))return 0;v->bitmap=NULL;}
    info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=(LONG)w;info.bmiHeader.biHeight=-(LONG)h;
    info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
    v->bitmap=CreateDIBSection(v->dc,&info,DIB_RGB_COLORS,(void **)&v->bits,NULL,0);
    if(!v->bitmap)return 0;
    v->old=SelectObject(v->dc,v->bitmap);if(!v->old||v->old==HGDI_ERROR)return 0;
    v->w=(int)w;v->h=(int)h;
    int lines=StretchDIBits(v->dc,0,0,(int)w,(int)h,0,0,(int)w,(int)h,bgra,&info,DIB_RGB_COLORS,SRCCOPY);
    if(lines<=0)return 0;
    if(!GdiFlush())return 0;
    for(uint32_t p=0;p<w*h;++p)if(memcmp(v->bits+p*4,bgra+p*4,3))return 0;
    RECT client,physical;
    if(!SetWindowPos(v->hwnd,NULL,0,0,(int)w,(int)h,SWP_NOMOVE|SWP_NOZORDER|SWP_NOACTIVATE|SWP_NOREDRAW)||
       !GetClientRect(v->hwnd,&client)||client.right-client.left!=(LONG)w||client.bottom-client.top!=(LONG)h||
       !GetWindowRect(v->hwnd,&physical)||physical.left<GetSystemMetrics(SM_XVIRTUALSCREEN)+GetSystemMetrics(SM_CXVIRTUALSCREEN))return 0;
    int before=v->painted;
    if(!InvalidateRect(v->hwnd,NULL,FALSE)||!UpdateWindow(v->hwnd)||v->painted!=before+1||v->failed)return 0;
    return 1;
}
static int wait_response(HANDLE response,HANDLE process){HANDLE h[2]={response,process};return WaitForMultipleObjects(2,h,FALSE,5000)==WAIT_OBJECT_0;}
static int set_handle_env(const wchar_t *name,HANDLE h){wchar_t b[40];_snwprintf_s(b,_countof(b),_TRUNCATE,L"%llx",(unsigned long long)(uintptr_t)h);return SetEnvironmentVariableW(name,b)!=0;}
static int cycle(const wchar_t *exe,const wchar_t *dir,const wchar_t *mode,int index){
    HANDLE job=NULL,map=NULL,request=NULL,response=NULL,out=INVALID_HANDLE_VALUE,in=INVALID_HANDLE_VALUE;
    PROCESS_INFORMATION pi={0};STARTUPINFOEXW si={0};SECURITY_ATTRIBUTES sa={sizeof(sa),NULL,TRUE};
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION lim={0};JOBOBJECT_BASIC_ACCOUNTING_INFORMATION acct={0};
    GpuFrameMap *m=NULL;View view={0};SIZE_T bytes=0;int attrs=0,assigned=0,ok=0;DWORD exit=~0u;
    wchar_t command[4096],log[4096];
    _snwprintf_s(command,_countof(command),_TRUNCATE,L"\"%s\"",exe);
    _snwprintf_s(log,_countof(log),_TRUNCATE,L"%s\\child-%02d.log",dir,index);
    job=CreateJobObjectW(NULL,NULL);lim.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if(!job||!SetInformationJobObject(job,JobObjectExtendedLimitInformation,&lim,sizeof(lim)))goto end;
    map=CreateFileMappingW(INVALID_HANDLE_VALUE,&sa,PAGE_READWRITE,0,sizeof(GpuFrameMap),NULL);
    request=CreateEventW(&sa,FALSE,FALSE,NULL);response=CreateEventW(&sa,FALSE,FALSE,NULL);
    if(!map||!request||!response)goto end;
    m=(GpuFrameMap *)MapViewOfFile(map,FILE_MAP_ALL_ACCESS,0,0,sizeof(*m));if(!m)goto end;
    memset(m,0,sizeof(*m));m->magic=GF_MAGIC;m->version=GF_VERSION;m->capacity=GF_CAPACITY;m->mapping_bytes=sizeof(*m);
    if(!set_handle_env(L"LOCALTERM_FRAME_MAP",map)||!set_handle_env(L"LOCALTERM_FRAME_REQUEST",request)||!set_handle_env(L"LOCALTERM_FRAME_RESPONSE",response)||!SetEnvironmentVariableW(L"LOCALTERM_FRAME_MODE",mode))goto end;
    out=CreateFileW(log,GENERIC_WRITE,FILE_SHARE_READ,&sa,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);
    in=CreateFileW(L"NUL",GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,&sa,OPEN_EXISTING,0,NULL);
    if(out==INVALID_HANDLE_VALUE||in==INVALID_HANDLE_VALUE)goto end;
    InitializeProcThreadAttributeList(NULL,1,0,&bytes);if(!bytes)goto end;
    si.lpAttributeList=(LPPROC_THREAD_ATTRIBUTE_LIST)HeapAlloc(GetProcessHeap(),0,bytes);
    if(!si.lpAttributeList||!InitializeProcThreadAttributeList(si.lpAttributeList,1,0,&bytes))goto end;attrs=1;
    HANDLE allowed[5]={out,in,map,request,response};
    if(!UpdateProcThreadAttribute(si.lpAttributeList,0,PROC_THREAD_ATTRIBUTE_HANDLE_LIST,allowed,sizeof(allowed),NULL,NULL))goto end;
    si.StartupInfo.cb=sizeof(si);si.StartupInfo.dwFlags=STARTF_USESHOWWINDOW|STARTF_USESTDHANDLES;si.StartupInfo.wShowWindow=SW_HIDE;
    si.StartupInfo.hStdOutput=out;si.StartupInfo.hStdError=out;si.StartupInfo.hStdInput=in;
    if(!CreateProcessW(exe,command,NULL,NULL,TRUE,CREATE_SUSPENDED|CREATE_NO_WINDOW|EXTENDED_STARTUPINFO_PRESENT,NULL,NULL,&si.StartupInfo,&pi)){fprintf(stderr,"FAIL launch\n");goto end;}
    if(!AssignProcessToJobObject(job,pi.hProcess))goto end;assigned=1;
    CloseHandle(out);out=INVALID_HANDLE_VALUE;CloseHandle(in);in=INVALID_HANDLE_VALUE;
    if(!view_init(&view)||ResumeThread(pi.hThread)==(DWORD)-1)goto end;
    static const uint32_t sizes[4][2]={{32,24},{127,65},{127,65},{64,48}};
    static const uint32_t epochs[4]={101,102,102,103};
    for(uint32_t f=0;f<4;++f){
        m->command=GF_RENDER;m->epoch=epochs[f];m->sequence=f+1;m->width=sizes[f][0];m->height=sizes[f][1];
        InterlockedExchange((volatile LONG *)&m->commit,0);
        if(!SetEvent(request)||!wait_response(response,pi.hProcess)){fprintf(stderr,"FAIL response deadline/crash frame=%u\n",f);goto end;}
        int before=view.painted;
        if(!present(&view,m,f+1,epochs[f],sizes[f][0],sizes[f][1])){fprintf(stderr,"REJECT frame=%u paint_unchanged=%d\n",f,view.painted==before);goto end;}
        if(index==0&&f==1&&!save_bmp(dir,&view))goto end;
        printf("FRAME_OK cycle=%d epoch=%u sequence=%u size=%ux%u WM_PAINT=1 pixels=verified\n",index,epochs[f],f+1,sizes[f][0],sizes[f][1]);
    }
    m->command=GF_CLOSE;m->sequence=5;InterlockedExchange((volatile LONG *)&m->commit,0);
    if(!SetEvent(request)||!wait_response(response,pi.hProcess)||InterlockedCompareExchange((volatile LONG *)&m->commit,0,0)!=5||m->status!=GF_CLOSED||m->frame_sequence!=5||m->frame_epoch!=103||m->response_magic!=GF_MAGIC||m->response_version!=GF_VERSION||m->header_bytes!=GF_HEADER_BYTES||m->payload_bytes!=0){fprintf(stderr,"FAIL close acknowledgement\n");goto end;}
    if(WaitForSingleObject(pi.hProcess,5000)!=WAIT_OBJECT_0||!GetExitCodeProcess(pi.hProcess,&exit)||exit!=0||
       !QueryInformationJobObject(job,JobObjectBasicAccountingInformation,&acct,sizeof(acct),NULL)||acct.ActiveProcesses!=0)goto end;
    printf("IPC_CHILD_OK cycle=%d pid=%lu frames=4 resize_epochs=3 closed=1 job_empty=1\n",index,pi.dwProcessId);ok=1;
end:
    if(!ok){
        fprintf(stderr,"IPC_FAIL cycle=%d winerr=%lu\n",index,GetLastError());
        if(pi.hProcess){
            if(assigned)TerminateJobObject(job,99);else TerminateProcess(pi.hProcess,99);
            if(WaitForSingleObject(pi.hProcess,5000)==WAIT_OBJECT_0&&(!assigned||(QueryInformationJobObject(job,JobObjectBasicAccountingInformation,&acct,sizeof(acct),NULL)&&acct.ActiveProcesses==0)))fprintf(stderr,"OWNED_CLEANUP_OK\n");
        }else fprintf(stderr,"OWNED_CLEANUP_OK no_child_created=1\n");
    }
    if(!drop_view(&view)){fprintf(stderr,"FAIL parent view cleanup\n");ok=0;}
    else printf("PARENT_VIEW_CLEANUP_OK cycle=%d\n",index);
    if(pi.hThread)CloseHandle(pi.hThread);if(pi.hProcess)CloseHandle(pi.hProcess);
    if(attrs)DeleteProcThreadAttributeList(si.lpAttributeList);if(si.lpAttributeList)HeapFree(GetProcessHeap(),0,si.lpAttributeList);
    if(out!=INVALID_HANDLE_VALUE)CloseHandle(out);if(in!=INVALID_HANDLE_VALUE)CloseHandle(in);
    if(m)UnmapViewOfFile(m);if(map)CloseHandle(map);if(request)CloseHandle(request);if(response)CloseHandle(response);if(job)CloseHandle(job);
    return ok;
}
int wmain(int argc,wchar_t **argv){
    Counts base={0},f={0};int ready=0;
    if(argc!=4||!no_gpu()||!physical_coordinates())return 2;
    if(wcscmp(argv[3],L"positive"))return cycle(argv[1],argv[2],argv[3],0)?0:1;
    for(int i=0;i<21;++i){
        if(!cycle(argv[1],argv[2],L"positive",i)||!counts(&f)||!no_gpu())return 1;
        if(i==0){base=f;ready=1;printf("BASELINE handles=%lu GDI=%lu USER=%lu threads=%lu\n",base.handles,base.gdi,base.user,base.threads);}
        else if(!ready||f.handles>base.handles||f.gdi>base.gdi||f.user>base.user||f.threads>base.threads){fprintf(stderr,"FAIL parent resource growth\n");return 1;}
        printf("PARENT cycle=%d handles=%lu GDI=%lu USER=%lu threads=%lu\n",i,f.handles,f.gdi,f.user,f.threads);
    }
    printf("GPU_FRAME_IPC_PASS warmup=1 cycles=20 frames=84 closed_children=21 no_parent_gl=1\n");return 0;
}
