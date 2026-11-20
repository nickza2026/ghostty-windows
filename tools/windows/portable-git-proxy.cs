using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;

internal static class PortableGitProxy {
    [StructLayout(LayoutKind.Sequential)] struct Startup {
        public uint cb; public IntPtr reserved, desktop, title;
        public uint x, y, xs, ys, xc, yc, fill, flags;
        public ushort show, reservedSize; public IntPtr reservedBytes, input, output, error;
    }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr process, thread; public uint pid, tid; }
    [StructLayout(LayoutKind.Sequential)] struct BasicLimit {
        public long processTime, jobTime; public uint flags;
        public UIntPtr minWorking, maxWorking; public uint active;
        public UIntPtr affinity; public uint priority, scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong a,b,c,d,e,f; }
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimit {
        public BasicLimit basic; public IoCounters io;
        public UIntPtr processMemory, jobMemory, peakProcess, peakJob;
    }
    delegate bool Handler(uint signal);
    static readonly Handler Control = delegate(uint signal) { return signal == 0 || signal == 1; };
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref Startup startup, out ProcessInfo info);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateJobObjectW(IntPtr security, string name);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimit limits, uint size);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle, uint timeout);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int kind);
    [DllImport("kernel32.dll")] static extern uint GetConsoleCP();
    [DllImport("kernel32.dll")] static extern bool SetConsoleCtrlHandler(Handler handler, bool add);
    // Quote every argument using the CommandLineToArgvW/MS CRT convention.
    static string Quote(string value) {
        StringBuilder b = new StringBuilder("\""); int slashes = 0;
        foreach (char c in value) {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { b.Append('\\', slashes * 2 + 1); b.Append(c); }
            else { b.Append('\\', slashes); b.Append(c); }
            slashes = 0;
        }
        b.Append('\\', slashes * 2); return b.Append('"').ToString();
    }
    static void CheckLocalPath(string path) {
        string current = Path.GetFullPath(path);
        if (current.Length < 3 || current[1] != ':' || current[2] != '\\') throw new IOException();
        while (!String.IsNullOrEmpty(current)) {
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) throw new IOException();
            current = Path.GetDirectoryName(current);
        }
    }
    static int Main(string[] args) {
        IntPtr job = IntPtr.Zero; ProcessInfo child = new ProcessInfo(); bool started = false;
        try {
            string self = System.Reflection.Assembly.GetExecutingAssembly().Location;
            CheckLocalPath(self);
            string data = Directory.GetParent(Path.GetDirectoryName(self)).FullName;
            string git = Path.Combine(data, "runtimes", "git", "cmd", "git.exe");
            if (!File.Exists(git)) {
                Console.Error.WriteLine("Private Git runtime is missing; no host Git fallback.");
                return 127;
            }
            CheckLocalPath(git);
            StringBuilder command = new StringBuilder(Quote(git));
            foreach (string arg in args) command.Append(' ').Append(Quote(arg));
            job = CreateJobObjectW(IntPtr.Zero, null);
            if (job == IntPtr.Zero) throw new IOException();
            ExtendedLimit limit = new ExtendedLimit(); limit.basic.flags = 0x2000;
            if (!SetInformationJobObject(job, 9, ref limit, (uint)Marshal.SizeOf(typeof(ExtendedLimit)))) throw new IOException();
            Startup startup = new Startup(); startup.cb = (uint)Marshal.SizeOf(typeof(Startup));
            startup.flags = 0x100; startup.input = GetStdHandle(-10);
            startup.output = GetStdHandle(-11); startup.error = GetStdHandle(-12);
            // No new console/window; attached Ctrl-C reaches Git while broker waits.
            SetConsoleCtrlHandler(Control, true);
            uint flags = 4;
            if (GetConsoleCP() == 0) flags |= 0x08000000; // CREATE_NO_WINDOW when broker has no console.
            if (!CreateProcessW(git, command, IntPtr.Zero, IntPtr.Zero, true, flags, IntPtr.Zero, null, ref startup, out child)) throw new IOException();
            if (!AssignProcessToJobObject(job, child.process)) throw new IOException();
            if (ResumeThread(child.thread) == UInt32.MaxValue) throw new IOException();
            started = true;
            if (WaitForSingleObject(child.process, UInt32.MaxValue) != 0) throw new IOException();
            uint exit; if (!GetExitCodeProcess(child.process, out exit)) throw new IOException();
            return unchecked((int)exit);
        } catch {
            if (!started && child.process != IntPtr.Zero) TerminateProcess(child.process, 126);
            Console.Error.WriteLine("Portable Git could not start or supervise its private runtime.");
            return 126;
        } finally {
            if (child.thread != IntPtr.Zero) CloseHandle(child.thread);
            if (child.process != IntPtr.Zero) CloseHandle(child.process);
            if (job != IntPtr.Zero) CloseHandle(job);
        }
    }
}
