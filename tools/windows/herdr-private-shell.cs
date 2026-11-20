// Small Windows console shim: never load the host PowerShell profile.
// Herdr v0.9.5 accepts a shell executable, not an executable-plus-arguments.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

internal static class HerdrPrivateShell
{
    private static string Quote(string value)
    {
        // CommandLineToArgvW-compatible quoting, including trailing backslashes.
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { result.Append('\\', slashes * 2 + 1); result.Append(c); }
            else { result.Append('\\', slashes); result.Append(c); }
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        return result.Append('"').ToString();
    }

    public static int Main(string[] args)
    {
        string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        string powershell = Path.Combine(windows, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        if (!File.Exists(powershell)) { Console.Error.WriteLine("Windows PowerShell is missing; no shell fallback."); return 127; }
        string arguments = "-NoLogo -NoProfile ";
        if (args.Length == 0)
        {
            string bootstrap = @"
try {
    $ErrorActionPreference = 'Stop'
    Set-Variable -Name HOME -Scope Global -Value $env:HOME -Force
    $history = Join-Path $env:HOME '.powershell-history.txt'
    $module = Join-Path $env:LOCALTERM_HERDR_PACKAGE_ROOT 'bin\powershell\PSReadLine\PSReadLine.psd1'
    # Interactive ConsoleHost may already have imported this module. Forcing a
    # second import re-registers its nested DLL cmdlets and fails in real ConPTY.
    if (Test-Path -LiteralPath $module -PathType Leaf) { Import-Module -Name $module }
    else { Import-Module -Name PSReadLine }
    Set-PSReadLineOption -HistorySavePath $history
    $global:__HerdrPrivateOriginalPrompt = $function:prompt
    function global:prompt {
        $out = @(& $global:__HerdrPrivateOriginalPrompt) -join ' '
        $loc = $ExecutionContext.SessionState.Path.CurrentLocation
        if ($loc.Provider.Name -eq 'FileSystem') {
            [Environment]::CurrentDirectory = $loc.ProviderPath
            $out += [string][char]27 + ']9;9;' + $loc.ProviderPath + [char]27 + '\'
        }
        $out
    }
} catch { [Console]::Error.WriteLine('Private shell initialization failed; no host profile fallback.'); exit 1 }
";
            arguments += "-NoExit -ExecutionPolicy Bypass -EncodedCommand " + Convert.ToBase64String(Encoding.Unicode.GetBytes(bootstrap));
        }
        else
        {
            foreach (string arg in args) arguments += Quote(arg) + " ";
        }
        var start = new ProcessStartInfo(powershell, arguments);
        start.UseShellExecute = false;
        start.WorkingDirectory = Environment.CurrentDirectory;
        // Herdr may rebuild a pane's environment from its shell environment.
        // Bind module discovery in this immediate child before ConsoleHost's
        // interactive autoload, rather than relying on server-inherited values.
        string bin = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", ".."));
        string package = Directory.GetParent(bin).FullName;
        if (!File.Exists(Path.Combine(bin, "localterm-dev.exe"))) {
            Console.Error.WriteLine("Private shell package sentinel missing; no host fallback.");
            return 127;
        }
        string modules = Path.Combine(bin, "powershell");
        string systemModules = Path.Combine(Path.GetDirectoryName(powershell), "Modules");
        start.EnvironmentVariables["PSModulePath"] = Directory.Exists(modules) ? modules + ";" + systemModules : systemModules;
        start.EnvironmentVariables["LOCALTERM_HERDR_PACKAGE_ROOT"] = package;
        // Pane creation can replace the server PATH with the Windows account
        // PATH. Rebind the executable search in this immediate child as well.
        // Do not append the inherited PATH: missing private tools must not fall
        // through to host Node, Git or globally installed npm CLIs.
        string data = Path.Combine(bin, "portable-data");
        start.EnvironmentVariables["PATH"] = String.Join(";", new string[] {
            Path.Combine(data, "runtimes", "node"),
            Path.Combine(data, "profiles", "herdr", "npm"),
            Path.Combine(data, "shims"),
            Path.Combine(data, "apps", "herdr", "0.9.5"),
            Path.Combine(windows, "System32"), windows,
            Path.GetDirectoryName(powershell)
        });
        start.EnvironmentVariables["PATHEXT"] = ".COM;.EXE;.BAT;.CMD";
        start.EnvironmentVariables["NoDefaultCurrentDirectoryInExePath"] = "1";
        start.EnvironmentVariables["ComSpec"] = Path.Combine(windows, "System32", "cmd.exe");
        // Keep the inherited console/ConPTY handles; no extra console window.
        if (!Console.IsInputRedirected)
            Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e) { e.Cancel = true; };
        using (var process = Process.Start(start))
        {
            process.WaitForExit();
            return process.ExitCode;
        }
    }
}
