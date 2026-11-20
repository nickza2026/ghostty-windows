// Test-only: explicit lpApplicationName mirrors the Windows ConPTY launch path.
// Unlike ProcessStartInfo's null application name, this must not search PATH.
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
internal static class HerdrShellCreateProcessProbe
{
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct StartupInfo {
        public int cb; public string reserved, desktop, title;
        public int x,y,xSize,ySize,xChars,yChars,fill,flags;
        public short showWindow,reservedSize; public IntPtr reservedPointer,input,output,error;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInfo { public IntPtr process,thread; public int processId,threadId; }
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    static extern bool CreateProcessW(string application, StringBuilder command,
        IntPtr processAttributes,IntPtr threadAttributes,bool inherit,int flags,
        IntPtr environment,string directory,ref StartupInfo startup,out ProcessInfo info);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h,uint ms);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h,out uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h,uint code);
    public static int Main(string[] args) {
        if(args.Length!=4) return 90;
        Environment.CurrentDirectory=args[1];
        var command=new StringBuilder("\""+args[0]+"\" -NoLogo -NoProfile -NonInteractive -EncodedCommand "+args[2]);
        var startup=new StartupInfo();startup.cb=Marshal.SizeOf(typeof(StartupInfo));
        ProcessInfo info;
        if(!CreateProcessW(args[0],command,IntPtr.Zero,IntPtr.Zero,false,
            0x08000400,IntPtr.Zero,args[1],ref startup,out info)) {
            int error=Marshal.GetLastWin32Error();Console.WriteLine("CREATEPROCESS_WIN32_ERROR="+error);
            return args[3]=="expect-missing" && error==2 ? 0 : 1;
        }
        try {
            if(args[3]=="expect-missing") return 91;
            if(WaitForSingleObject(info.process,20000)!=0) {TerminateProcess(info.process,92);return 92;}
            uint code;GetExitCodeProcess(info.process,out code);
            Console.WriteLine("CREATEPROCESS_CHILD_EXIT="+code);return (int)code;
        } finally { CloseHandle(info.thread);CloseHandle(info.process); }
    }
}
