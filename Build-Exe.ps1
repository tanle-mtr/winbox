param(
    [string]$WorkDir = "E:\编程作品\作品\DeepSeek\winbox\WinBox",
    [string]$CscPath = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
)

$mainB64 = (Get-Content "$WorkDir\scripts_b64.txt" -Raw).Trim()
$zipB64  = (Get-Content "$WorkDir\scripts_archive_b64.txt" -Raw).Trim()

function Get-ByteLiteral($b64) {
    $bytes = [Convert]::FromBase64String($b64)
    $rows = @()
    for ($i = 0; $i -lt $bytes.Length; $i += 16) {
        $row = "            "
        $end = [Math]::Min($i + 16, $bytes.Length)
        $vals = @()
        for ($j = $i; $j -lt $end; $j++) {
            $vals += "0x{0:X2}" -f $bytes[$j]
        }
        $row += ($vals -join ", ")
        $rows += $row
    }
    return "{ " + ($rows -join ",`n") + " }"
}

$csPath = "$WorkDir\WinBoxLauncher.cs"
$sw = [System.IO.StreamWriter]::new($csPath, $false, [System.Text.Encoding]::ASCII)
try {
    $sw.WriteLine('using System;')
    $sw.WriteLine('using System.IO;')
    $sw.WriteLine('using System.IO.Compression;')
    $sw.WriteLine('using System.Diagnostics;')
    $sw.WriteLine('using System.Runtime.InteropServices;')
    $sw.WriteLine('class WinBoxLauncher')
    $sw.WriteLine('{')
    $sw.WriteLine('    [DllImport("kernel32.dll")] static extern bool FreeConsole();')
    $sw.WriteLine('    [DllImport("kernel32.dll")] static extern uint AllocConsole();')
    $sw.WriteLine('    static void Main(string[] args)')
    $sw.WriteLine('    {')
    $sw.WriteLine('        FreeConsole();')
    $sw.WriteLine('        string td = Path.Combine(Path.GetTempPath(), "WinBox");')
    $sw.WriteLine('        if (!Directory.Exists(td)) Directory.CreateDirectory(td);')
    $sw.WriteLine('        try')
    $sw.WriteLine('        {')
    $sw.WriteLine('            string ms = Path.Combine(td, "WinBox.ps1");')
    $sw.WriteLine('            File.WriteAllBytes(ms, MainScriptBytes);')
    $sw.WriteLine('            string sd = Path.Combine(td, "Scripts");')
    $sw.WriteLine('            if (Directory.Exists(sd)) Directory.Delete(sd, true);')
    $sw.WriteLine('            byte[] zb = ScriptsArchiveBytes;')
    $sw.WriteLine('            using (var ms2 = new MemoryStream(zb))')
    $sw.WriteLine('            using (var za = new ZipArchive(ms2, ZipArchiveMode.Read))')
    $sw.WriteLine('                za.ExtractToDirectory(sd);')
    $sw.WriteLine('            string cs = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Config");')
    $sw.WriteLine('            string cd = Path.Combine(td, "Config");')
    $sw.WriteLine('            if (Directory.Exists(cs) && !Directory.Exists(cd)) Directory.CreateDirectory(cd);')
    $sw.WriteLine('            foreach (var f in Directory.GetFiles(cs, "*.*"))')
    $sw.WriteLine('                File.Copy(f, Path.Combine(cd, Path.GetFileName(f)), true);')
    $sw.WriteLine('            var psi = new ProcessStartInfo("powershell.exe",')
    $sw.WriteLine('                "-ExecutionPolicy Bypass -NoProfile -File \"" + ms + "\"");')
    $sw.WriteLine('            psi.UseShellExecute = false; psi.CreateNoWindow = true;')
    $sw.WriteLine('            using (var p = Process.Start(psi))')
    $sw.WriteLine('            { p.WaitForExit(); Environment.Exit(p.ExitCode); }')
    $sw.WriteLine('        }')
    $sw.WriteLine('        catch (Exception ex)')
    $sw.WriteLine('        {')
    $sw.WriteLine('            AllocConsole();')
    $sw.WriteLine('            Console.ForegroundColor = ConsoleColor.Red;')
    $sw.WriteLine('            Console.WriteLine("启动失败: " + ex.Message);')
    $sw.WriteLine('            Console.ReadKey();')
    $sw.WriteLine('        }')
    $sw.WriteLine('    }')

    $mainLit = Get-ByteLiteral $mainB64
    $zipLit  = Get-ByteLiteral $zipB64

    $sw.WriteLine('    private static readonly byte[] MainScriptBytes = ')
    $sw.WriteLine($mainLit)
    $sw.WriteLine(';')
    $sw.WriteLine('    private static readonly byte[] ScriptsArchiveBytes = ')
    $sw.WriteLine($zipLit)
    $sw.WriteLine(';')
    $sw.WriteLine('}')
    Write-Output "C# source written."
} finally {
    $sw.Close()
}

Write-Output "Compiling..."
$exePath = "$WorkDir\WinBox.exe"
$argList = '/target:winexe /out:"' + $exePath + '" /platform:x64 /optimize "' + $csPath + '"'
$proc = Start-Process $CscPath -ArgumentList $argList -Wait -PassThru -NoNewWindow
Write-Output "Exit code: $($proc.ExitCode)"
if ($proc.ExitCode -eq 0 -and (Test-Path $exePath)) {
    $fs = (Get-Item $exePath).Length
    Write-Output "OK: WinBox.exe = $([math]::Round($fs/1MB, 2)) MB"
} else {
    Write-Output "FAILED"
}
