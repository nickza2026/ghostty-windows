using System;
using System.IO;
using System.IO.Pipes;
using System.Collections.Concurrent;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

// Transport only. Private keys never enter this process or its IPC.
public static class GhosttyPrivateAgentBridge {
    const int Maximum = 65536;
    [StructLayout(LayoutKind.Sequential)] struct Attributes {
        public int Length; public IntPtr Descriptor;
        [MarshalAs(UnmanagedType.Bool)] public bool Inherit;
    }
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string s, uint revision, out IntPtr descriptor, out uint size);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafePipeHandle CreateNamedPipe(string name, uint access, uint mode, uint instances, uint output, uint input, uint timeout, ref Attributes attributes);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CancelIoEx(SafePipeHandle handle, IntPtr overlap);
    static Stream output;
    static readonly object outputLock = new object();
    static readonly ConcurrentDictionary<int, Pending> pending = new ConcurrentDictionary<int, Pending>();
    static NamedPipeServerStream[] pipes;
    static volatile bool stopping;
    static int nextRequest;
    sealed class Pending { public readonly ManualResetEventSlim Ready = new ManualResetEventSlim(); public byte[] Response; }
    static int Integer(byte[] b, int o) { return checked((int)(((uint)b[o]<<24)|((uint)b[o+1]<<16)|((uint)b[o+2]<<8)|b[o+3])); }
    static void Integer(byte[] b, int o, int n) { b[o]=(byte)(n>>24);b[o+1]=(byte)(n>>16);b[o+2]=(byte)(n>>8);b[o+3]=(byte)n; }
    static byte[] Read(Stream stream, int count) {
        byte[] b=new byte[count];int at=0;
        while(at<count){int n=stream.Read(b,at,count-at);if(n==0)throw new EndOfStreamException();at+=n;}
        return b;
    }
    static byte[] ReadPipe(NamedPipeServerStream pipe, int count) {
        byte[] b=new byte[count];int at=0;
        while(at<count){
            Task<int> read=pipe.ReadAsync(b,at,count-at);
            if(!read.Wait(5000)){
                CancelIoEx(pipe.SafePipeHandle,IntPtr.Zero);
                try { if(!read.Wait(2000)) Stop(); } catch {}
                throw new TimeoutException();
            }
            if(read.Result==0)throw new EndOfStreamException();at+=read.Result;
        }
        return b;
    }
    static void Emit(byte[] body) {
        lock(outputLock){byte[] header=new byte[4];Integer(header,0,body.Length);output.Write(header,0,4);output.Write(body,0,body.Length);output.Flush();}
    }
    static void Stop() {
        stopping=true;
        if(pipes!=null)foreach(var p in pipes)if(p!=null)try{p.Dispose();}catch{}
        foreach(var item in pending.Values)try{item.Ready.Set();}catch(ObjectDisposedException){}
    }
    static void Serve(object value) {
        var pipe=(NamedPipeServerStream)value;
        while(!stopping){
            try {
                pipe.WaitForConnection();
                for(int packets=0;packets<256&&!stopping;packets++){
                    int length=Integer(ReadPipe(pipe,4),0);if(length<1||length>Maximum)throw new InvalidDataException();
                    byte[] request=ReadPipe(pipe,length);int id=Interlocked.Increment(ref nextRequest);if(id<=0)throw new InvalidDataException();
                    var slot=new Pending();if(!pending.TryAdd(id,slot))throw new InvalidDataException();
                    try {
                        byte[] message=new byte[length+5];message[0]=2;Integer(message,1,id);Buffer.BlockCopy(request,0,message,5,length);Emit(message);
                        if(!slot.Ready.Wait(10000)||slot.Response==null||stopping)throw new TimeoutException();
                        byte[] header=new byte[4];Integer(header,0,slot.Response.Length);pipe.Write(header,0,4);pipe.Write(slot.Response,0,slot.Response.Length);pipe.Flush();
                    } finally { Pending removed;pending.TryRemove(id,out removed);slot.Ready.Dispose(); }
                }
            } catch { /* A malformed/idle client only loses its own connection. */ }
            finally { if(!stopping)try{pipe.Disconnect();}catch{Stop();} }
        }
    }
    static void VerifySecurity(NamedPipeServerStream pipe, SecurityIdentifier user) {
        PipeSecurity security=pipe.GetAccessControl();
        var descriptor=new RawSecurityDescriptor(security.GetSecurityDescriptorBinaryForm(),0);
        if(!descriptor.Owner.Equals(user)||(descriptor.ControlFlags&ControlFlags.DiscretionaryAclProtected)==0||descriptor.DiscretionaryAcl==null||descriptor.DiscretionaryAcl.Count!=2)throw new InvalidDataException();
        bool own=false,system=false;
        var sidSystem=new SecurityIdentifier(WellKnownSidType.LocalSystemSid,null);
        foreach(GenericAce raw in descriptor.DiscretionaryAcl){
            CommonAce ace=raw as CommonAce;
            if(ace==null||ace.AceQualifier!=AceQualifier.AccessAllowed||ace.AceFlags!=AceFlags.None)throw new InvalidDataException();
            // Kernel may map GENERIC_ALL to concrete file/pipe rights.
            if((ace.AccessMask&0x10000000)==0&&(ace.AccessMask&0x60003)!=0x60003)throw new InvalidDataException();
            if(ace.SecurityIdentifier.Equals(user))own=true;else if(ace.SecurityIdentifier.Equals(sidSystem))system=true;else throw new InvalidDataException();
        }
        if(!own||!system)throw new InvalidDataException();
    }
    public static void Run(string name) {
        if(!Regex.IsMatch(name,@"^\\\\\.\\pipe\\ghostty-sbx-[a-f0-9]{64}$"))throw new InvalidDataException();
        output=Console.OpenStandardOutput();IntPtr descriptor=IntPtr.Zero;
        try {
            var user=WindowsIdentity.GetCurrent().User;
            string sddl="O:"+user.Value+"D:P(A;;GA;;;SY)(A;;GA;;;"+user.Value+")";
            uint size;if(!ConvertStringSecurityDescriptorToSecurityDescriptor(sddl,1,out descriptor,out size))throw new Win32Exception();
            var attributes=new Attributes{Length=Marshal.SizeOf(typeof(Attributes)),Descriptor=descriptor,Inherit=false};
            pipes=new NamedPipeServerStream[4];
            for(int i=0;i<pipes.Length;i++){
                // FIRST_PIPE_INSTANCE only on the first handle; retain all handles for
                // the entire manager lifetime, including between client connections.
                uint access=3|0x40000000u|(i==0?0x80000u:0u);
                var handle=CreateNamedPipe(name,access,8,4,Maximum+4,Maximum+4,0,ref attributes);
                if(handle.IsInvalid){handle.Dispose();throw new Win32Exception();}
                try{pipes[i]=new NamedPipeServerStream(PipeDirection.InOut,true,false,handle);}catch{handle.Dispose();throw;}
                VerifySecurity(pipes[i],user);
            }
            foreach(var pipe in pipes){var thread=new Thread(Serve);thread.IsBackground=true;thread.Start(pipe);}
            Emit(new byte[]{1}); // Only after every pipe passed the native DACL check.
            Stream input=Console.OpenStandardInput();
            while(!stopping){
                int length=Integer(Read(input,4),0);if(length<6||length>Maximum+5)throw new InvalidDataException();
                byte[] body=Read(input,length);if(body[0]!=2)throw new InvalidDataException();
                Pending slot;if(!pending.TryGetValue(Integer(body,1),out slot))throw new InvalidDataException();
                byte[] response=new byte[length-5];Buffer.BlockCopy(body,5,response,0,response.Length);slot.Response=response;try{slot.Ready.Set();}catch(ObjectDisposedException){}
            }
        } catch(EndOfStreamException) {} finally {Stop();if(descriptor!=IntPtr.Zero)LocalFree(descriptor);}
    }
}
