// TEST ONLY. A real headless Windows ConPTY, never a visible/focused window.
// It launches only a supplied owned Node console probe, in a kill-on-close job;
// that probe must reuse a ready external manager and must NOT start any VM.
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;
public static class SandboxConPtyTest {
 [StructLayout(LayoutKind.Sequential)] struct Coord{public short X,Y;public Coord(int x,int y){X=(short)x;Y=(short)y;}}
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct SI{public int cb;public string reserved,desktop,title;public int x,y,xSize,ySize,xChars,yChars,fill,flags;public short show,reservedSize;public IntPtr reservedPtr,input,output,error;}
 [StructLayout(LayoutKind.Sequential)] struct SX{public SI info;public IntPtr attributes;}
 [StructLayout(LayoutKind.Sequential)] struct PI{public IntPtr process,thread;public int pid,tid;}
 [StructLayout(LayoutKind.Sequential)] struct Basic{public long perProcess,perJob;public uint flags;public UIntPtr minimum,maximum;public uint active;public UIntPtr affinity;public uint priority,scheduling;}
 [StructLayout(LayoutKind.Sequential)] struct IO{public ulong a,b,c,d,e,f;}
 [StructLayout(LayoutKind.Sequential)] struct Limits{public Basic basic;public IO io;public UIntPtr pm,jm,peakp,peakj;}
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool CreatePipe(out IntPtr r,out IntPtr w,IntPtr security,uint size);
 [DllImport("kernel32.dll")] static extern int CreatePseudoConsole(Coord size,IntPtr input,IntPtr output,uint flags,out IntPtr pc);
 [DllImport("kernel32.dll")] static extern int ResizePseudoConsole(IntPtr pc,Coord size);
 [DllImport("kernel32.dll")] static extern void ClosePseudoConsole(IntPtr pc);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,int flags,ref IntPtr bytes);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,IntPtr attribute,IntPtr value,IntPtr size,IntPtr previous,IntPtr returned);
 [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcessW(string app,StringBuilder command,IntPtr a,IntPtr b,bool inherit,int flags,IntPtr env,string cwd,ref SX startup,out PI process);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadFile(IntPtr h,byte[] bytes,uint n,out uint read,IntPtr overlap);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool WriteFile(IntPtr h,byte[] bytes,uint n,out uint written,IntPtr overlap);
 [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h,uint ms);
 [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h,out uint code);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h,uint code);
 [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int id);
 [DllImport("kernel32.dll")] static extern bool SetStdHandle(int id,IntPtr handle);
 [DllImport("kernel32.dll",SetLastError=true)] static extern uint ResumeThread(IntPtr h);
 [DllImport("kernel32.dll")] static extern IntPtr CreateJobObject(IntPtr a,string name);
 [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job,int cls,ref Limits limits,int bytes);
 [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
 static byte[] Exact(Stream input,int n){byte[] b=new byte[n];for(int at=0;at<n;){int got=input.Read(b,at,n-at);if(got==0)throw new EndOfStreamException();at+=got;}return b;}
 static byte[] Frame(Stream input){byte[] h=Exact(input,4);int n=(h[0]<<24)|(h[1]<<16)|(h[2]<<8)|h[3];if(n<1||n>32769)throw new InvalidDataException();return Exact(input,n);}
 static Coord Size(byte[] b){if(b.Length!=5||b[0]!=2)throw new InvalidDataException();int x=(b[1]<<8)|b[2],y=(b[3]<<8)|b[4];if(x<1||x>2000||y<1||y>1000)throw new InvalidDataException();return new Coord(x,y);}
 static string Quote(string value){return "\""+value.Replace("\"","\\\"")+"\"";}
 public static int Run(string node,string cwd,string probe){
  IntPtr ir=IntPtr.Zero,iw=IntPtr.Zero,orr=IntPtr.Zero,ow=IntPtr.Zero,pc=IntPtr.Zero,attributes=IntPtr.Zero,job=IntPtr.Zero;PI pi=new PI();Thread reader=null;
  try{
   Console.Error.WriteLine("CONPTY_TEST read-size");
   Stream input=Console.OpenStandardInput(),output=Console.OpenStandardOutput();Coord size=Size(Frame(input));
   Console.Error.WriteLine("CONPTY_TEST create-console");
   if(!CreatePipe(out ir,out iw,IntPtr.Zero,65536)||!CreatePipe(out orr,out ow,IntPtr.Zero,65536)||CreatePseudoConsole(size,ir,ow,0,out pc)!=0)throw new IOException("create console");
   CloseHandle(ir);ir=IntPtr.Zero;CloseHandle(ow);ow=IntPtr.Zero;
   reader=new Thread(()=>{try{byte[] b=new byte[32768];uint n;while(ReadFile(orr,b,(uint)b.Length,out n,IntPtr.Zero)&&n>0){output.Write(b,0,(int)n);output.Flush();}}catch{}});reader.IsBackground=true;reader.Start();
   Console.Error.WriteLine("CONPTY_TEST console-created");
   IntPtr bytes=IntPtr.Zero;InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref bytes);attributes=Marshal.AllocHGlobal(bytes);
   if(!InitializeProcThreadAttributeList(attributes,1,0,ref bytes)||!UpdateProcThreadAttribute(attributes,0,(IntPtr)0x20016,pc,(IntPtr)IntPtr.Size,IntPtr.Zero,IntPtr.Zero))throw new IOException("console attribute");
   SX startup=new SX();startup.info.cb=Marshal.SizeOf(typeof(SX));startup.attributes=attributes;
   job=CreateJobObject(IntPtr.Zero,null);Limits limits=new Limits();limits.basic.flags=0x2000;
   if(job==IntPtr.Zero||!SetInformationJobObject(job,9,ref limits,Marshal.SizeOf(typeof(Limits))))throw new IOException("owned job");
   // The PowerShell host has redirected std handles. Do not pass those pipes
   // into the console child: a real console must provision its own fd 0/1/2.
   // Existing reader/writer streams retain their original handles throughout.
   IntPtr oldIn=GetStdHandle(-10),oldOut=GetStdHandle(-11),oldErr=GetStdHandle(-12);
   try{
    SetStdHandle(-10,IntPtr.Zero);SetStdHandle(-11,IntPtr.Zero);SetStdHandle(-12,IntPtr.Zero);
    if(!CreateProcessW(node,new StringBuilder(Quote(node)+" "+Quote(probe)),IntPtr.Zero,IntPtr.Zero,false,0x80004,IntPtr.Zero,cwd,ref startup,out pi))throw new IOException("owned console process");
   }finally{SetStdHandle(-10,oldIn);SetStdHandle(-11,oldOut);SetStdHandle(-12,oldErr);}
   if(!AssignProcessToJobObject(job,pi.process))throw new IOException("owned job assignment");
   Console.Error.WriteLine("CONPTY_TEST child-assigned");
   Thread writer=new Thread(()=>{try{while(true){byte[] f=Frame(input);if(f[0]==2){if(ResizePseudoConsole(pc,Size(f))!=0)throw new IOException();}else if(f[0]==1){int at=1;while(at<f.Length){byte[] b=new byte[f.Length-at];Buffer.BlockCopy(f,at,b,0,b.Length);uint n;if(!WriteFile(iw,b,(uint)b.Length,out n,IntPtr.Zero)||n==0)throw new IOException();at+=(int)n;}}else throw new InvalidDataException();}}catch{}});writer.IsBackground=true;writer.Start();
   uint suspended=ResumeThread(pi.thread);Console.Error.WriteLine("CONPTY_TEST resume previous="+suspended+" error="+Marshal.GetLastWin32Error());if(suspended==0xffffffff)throw new IOException("resume owned process");uint wait=WaitForSingleObject(pi.process,20000);uint code;GetExitCodeProcess(pi.process,out code);Console.Error.WriteLine("CONPTY_TEST wait="+wait+" exit="+code);if(wait!=0)return 124;return (int)code;
  }finally{
   if(pi.process!=IntPtr.Zero&&WaitForSingleObject(pi.process,0)!=0)TerminateProcess(pi.process,125);
   if(job!=IntPtr.Zero)CloseHandle(job);if(pc!=IntPtr.Zero)ClosePseudoConsole(pc);
   if(reader!=null)reader.Join(2000);if(pi.thread!=IntPtr.Zero)CloseHandle(pi.thread);if(pi.process!=IntPtr.Zero)CloseHandle(pi.process);
   if(attributes!=IntPtr.Zero){DeleteProcThreadAttributeList(attributes);Marshal.FreeHGlobal(attributes);}foreach(IntPtr h in new[]{ir,iw,orr,ow})if(h!=IntPtr.Zero)CloseHandle(h);
  }
 }
}
