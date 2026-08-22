using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;

class WinBoxLauncher
{
    [DllImport("kernel32.dll")] static extern bool FreeConsole();
    [DllImport("kernel32.dll")] static extern uint AllocConsole();
    
    static void Main(string[] args)
    {
        FreeConsole();
        string exeDir = AppDomain.CurrentDomain.BaseDirectory;
        string ps1Path = Path.Combine(exeDir, "WinBox.ps1");
        if (!File.Exists(ps1Path))
        {
            AllocConsole();
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("??? WinBox.ps1");
            Console.ReadKey();
            return;
        }
        try
        {
            var psi = new ProcessStartInfo("powershell.exe",
                "-ExecutionPolicy Bypass -NoProfile -File \"" + ps1Path + "\"");
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            using (var p = Process.Start(psi))
            {
                p.WaitForExit();
                Environment.Exit(p.ExitCode);
            }
        }
        catch (Exception ex)
        {
            AllocConsole();
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("????: " + ex.Message);
            Console.ReadKey();
        }
    }
}