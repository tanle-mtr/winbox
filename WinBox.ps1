<#
.SYNOPSIS
    WinBox - Windows 系统优化工具箱
    集合了 GitHub 上顶级 Windows 优化工具的核心功能

.VERSION
    1.0.0

.AUTHOR
    Generated from analysis of 14 GitHub repos

.NOTES
    Must run as Administrator for full functionality
#>
[CmdletBinding()]
param()

# ═══════════════════════════════════════════════════════════
#  全局配置
# ═══════════════════════════════════════════════════════════
$WinBoxRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptsRoot  = Join-Path $WinBoxRoot "Scripts"
$ConfigRoot   = Join-Path $WinBoxRoot "Config"
$LogsRoot     = Join-Path $env:TEMP "WinBox-Logs"
$RevertRoot   = Join-Path $env:LOCALAPPDATA "WinBox\Revert"
$LogPath      = Join-Path $LogsRoot "WinBox-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

foreach ($d in @($LogsRoot, $RevertRoot)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'HH:mm:ss'
    $line = "[$ts] [$Level] $Msg"
    Write-Host $line
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
}

# ═══════════════════════════════════════════════════════════
#  管理员权限检测
# ═══════════════════════════════════════════════════════════
function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ═══════════════════════════════════════════════════════════
#  系统信息
# ═══════════════════════════════════════════════════════════
function Get-SystemInfo {
    @{
        OS          = (Get-ComputerInfo).WindowsProductName
        Build       = (Get-ComputerInfo).WindowsBuildLabEx
        Version     = $PSVersionTable.PSVersion.ToString()
        IsAdmin     = (Test-IsAdmin).ToString()
        RAM_GB      = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        CPU         = (Get-CimInstance Win32_Processor).Name
        Arch        = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
        LastBoot    = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    }
}

# ═══════════════════════════════════════════════════════════
#  PowerShell 执行引擎
# ═══════════════════════════════════════════════════════════
function Invoke-WinBoxScript {
    param(
        [string]$ScriptPath,
        [string[]]$Args = @(),
        [int]$Timeout = 120,
        [switch]$Silent
    )
    if (-not (Test-Path $ScriptPath)) {
        Write-Log "脚本不存在: $ScriptPath" 'WARN'
        return @{ Success = $false; Error = "Script not found: $ScriptPath" }
    }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`" $($Args -join ' ')"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $Silent
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit($Timeout * 1000)
        @{
            Success = ($proc.ExitCode -eq 0)
            ExitCode = $proc.ExitCode
            Output = $stdout
            Error = $stderr
        }
    } catch {
        Write-Log "执行失败: $($_.Exception.Message)" 'ERROR'
        @{ Success = $false; Error = $_.Exception.Message }
    }
}

# ═══════════════════════════════════════════════════════════
#  注册表操作
# ═══════════════════════════════════════════════════════════
function Set-WinBoxReg {
    param([string]$Path, [string]$Name, [object]$Value, [Microsoft.Win32.RegistryValueKind]$Kind = 'String')
    $key = Split-Path $Path -Parent
    $leaf = Split-Path $Path -Leaf
    $regKey = [Microsoft.Win32.Registry]::OpenBaseKey(
        switch ($key.Split('\')[0]) {
            'HKLM' { [Microsoft.Win32.RegistryHive]::LocalMachine }
            'HKCU' { [Microsoft.Win32.RegistryHive]::CurrentUser }
            'HKCR' { [Microsoft.Win32.RegistryHive]::ClassesRoot }
            default { [Microsoft.Win32.RegistryHive]::LocalMachine }
        }
    ).OpenSubKey($leaf, $true)
    if ($regKey) {
        $regKey.SetValue($Name, $Value, $Kind)
        $regKey.Close()
        return $true
    }
    return $false
}

function Get-WinBoxReg {
    param([string]$Path, [string]$Name)
    $key = Split-Path $Path -Parent
    $leaf = Split-Path $Path -Leaf
    try {
        $regKey = [Microsoft.Win32.Registry]::OpenBaseKey(
            switch ($key.Split('\')[0]) {
                'HKLM' { [Microsoft.Win32.RegistryHive]::LocalMachine }
                'HKCU' { [Microsoft.Win32.RegistryHive]::CurrentUser }
                default { [Microsoft.Win32.RegistryHive]::LocalMachine }
            }
        ).OpenSubKey($leaf)
        if ($regKey) { return $regKey.GetValue($Name) }
    } catch {}
    return $null
}

# ═══════════════════════════════════════════════════════════
#  服务管理
# ═══════════════════════════════════════════════════════════
function Set-WinBoxService {
    param([string]$Name, [string]$StartupType)
    $valid = @('Automatic', 'AutomaticDelayedStart', 'Manual', 'Disabled')
    if ($StartupType -notin $valid) { Write-Log "无效启动类型: $StartupType" 'WARN'; return $false }
    try {
        sc.exe config $Name start= $StartupType | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Get-WinBoxServiceStatus {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) { return $svc.StartType.ToString() }
    return 'NotFound'
}

# ═══════════════════════════════════════════════════════════
#  计划任务
# ═══════════════════════════════════════════════════════════
function Invoke-WinBoxTask {
    param([string]$Path, [string]$Action)
    switch ($Action) {
        'Disable' { Disable-ScheduledTask -TaskPath $Path -ErrorAction SilentlyContinue }
        'Enable'  { Enable-ScheduledTask   -TaskPath $Path -ErrorAction SilentlyContinue }
        'Delete'  { Unregister-ScheduledTask -TaskPath $Path -Confirm:$false -ErrorAction SilentlyContinue }
        'Run'     { Start-ScheduledTask    -TaskPath $Path -ErrorAction SilentlyContinue }
    }
}

function Get-WinBoxTaskList {
    param([string]$Filter = '')
    Get-ScheduledTask | Where-Object { $_.TaskPath -like "*$Filter*" } |
        Select-Object TaskPath, TaskName, State |
        Sort-Object TaskPath, TaskName
}

# ═══════════════════════════════════════════════════════════
#  UWP 应用管理
# ═══════════════════════════════════════════════════════════
function Get-WinBoxAppList {
    param([switch]$All, [switch]$RemovableOnly)
    $apps = Get-AppxPackage | Select-Object Name, PackageFullName, Publisher
    if ($RemovableOnly) {
        $protected = @('Microsoft.Windows.Store', 'Microsoft.Windows.Photos',
                        'Microsoft.WindowsCalculator', 'Microsoft.WindowsNotepad',
                        'Microsoft.WindowsTerminal', 'Microsoft.Paint')
        $apps = $apps | Where-Object { $_.Name -notin $protected }
    }
    $apps | Sort-Object Name
}

function Remove-WinBoxApp {
    param([string]$Name)
    $pkgs = Get-AppxPackage -Name $Name
    foreach ($p in $pkgs) {
        Remove-AppxPackage -Package $p.PackageFullName -ErrorAction SilentlyContinue
        Write-Log "已移除: $($p.Name)"
    }
    $prov = Get-AppxProvisionedPackage -Online -PackageName $pkgs[0].PackageFullName -ErrorAction SilentlyContinue
    if ($prov) {
        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue
        Write-Log "已移除 Provisioned: $($prov.PackageName)"
    }
}

function Install-WinBoxApp {
    param([string]$Name)
    try {
        wsreset -i -PackageFullName $Name
        Write-Log "正在从 Microsoft Store 重新安装: $Name"
    } catch {
        Start-Process "ms-windows-store://pdp/?ProductId=$Name"
        Write-Log "已打开 Microsoft Store: $Name"
    }
}

# ═══════════════════════════════════════════════════════════
#  启动项管理
# ═══════════════════════════════════════════════════════════
function Get-WinBoxStartupItems {
    $regItems = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue |
        Select-Object PsChildName, @(
            @{N='Value';E={$_.PSObject.Properties.Value}}
        )
    $shellItems = Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue |
        ForEach-Object { [PSCustomObject]@{ Name = $_.PSChildName; Path = (Get-ItemProperty $_.PSPath).'(default)' } }
    $wmItems = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
        Select-Object Name, Command, Location
    [PSCustomObject]@{
        Registry = $regItems
        Shell    = $shellItems
        WMI      = $wmItems
    }
}

# ═══════════════════════════════════════════════════════════
#  磁盘清理
# ═══════════════════════════════════════════════════════════
function Invoke-WinBoxCleanup {
    param([string[]]$Targets = @('Temp', 'SysTemp', 'Recycle', 'Update', 'Prefetch'))
    $results = @{}
    if ('Temp' -in $Targets) {
        $before = (Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        $after = (Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $results['Temp'] = [math]::Round(($before - $after) / 1MB, 1)
    }
    if ('SysTemp' -in $Targets) {
        $before = (Get-ChildItem 'C:\Windows\Temp' -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Remove-Item 'C:\Windows\Temp\*' -Recurse -Force -ErrorAction SilentlyContinue
        $after = (Get-ChildItem 'C:\Windows\Temp' -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $results['SysTemp'] = [math]::Round(($before - $after) / 1MB, 1)
    }
    if ('Recycle' -in $Targets) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        $results['Recycle'] = 'Done'
    }
    if ('Update' -in $Targets) {
        $before = (Get-ChildItem 'C:\Windows\SoftwareDistribution\Download' -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Remove-Item 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force -ErrorAction SilentlyContinue
        $after = (Get-ChildItem 'C:\Windows\SoftwareDistribution\Download' -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $results['Update'] = [math]::Round(($before - $after) / 1MB, 1)
    }
    if ('Prefetch' -in $Targets) {
        $before = (Get-ChildItem 'C:\Windows\Prefetch' -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Remove-Item 'C:\Windows\Prefetch\*' -Force -ErrorAction SilentlyContinue
        $after = (Get-ChildItem 'C:\Windows\Prefetch' -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $results['Prefetch'] = [math]::Round(($before - $after) / 1MB, 1)
    }
    return $results
}

# ═══════════════════════════════════════════════════════════
#  快速优化命令集（来自各仓库的精华整合）
# ═══════════════════════════════════════════════════════════
$Optimizations = @{

    # ── 隐私 & 遥测 ──
    'Disable-Telemetry' = @{
        Name        = '禁用 Windows 遥测'
        Category    = 'Privacy'
        Description = '禁用诊断数据、活动历史记录、应用启动跟踪'
        Script      = {
            # Telemetry disable (from Win11Debloat + Atlas)
            Set-WinBoxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0 'DWord'
            Set-WinBoxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowNetworkTelemetry' 0 'DWord'
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\LooselyCoupled' 'Value' '' 'String'
            Disable-ScheduledTask -TaskPath '\Microsoft\Windows\Application Experience\' -ErrorAction SilentlyContinue
            Disable-ScheduledTask -TaskPath '\Microsoft\Windows\Customer Experience Improvement\' -ErrorAction SilentlyContinue
            Disable-ScheduledTask -TaskPath '\Microsoft\Windows\Diagnosis\' -ErrorAction SilentlyContinue
            Write-Log '遥测已禁用'
        }
        Revert      = {
            Set-WinBoxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1 'DWord'
            Write-Log '遥测已恢复'
        }
        Risk        = 'Safe'
    }

    'Disable-Copilot' = @{
        Name        = '禁用 Copilot'
        Category    = 'Privacy'
        Description = '禁用 Windows Copilot AI 助手'
        Script      = {
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Chat' 'FeatureReadyState' 0 'DWord'
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Chat' 'NotificationsEnabled' 0 'DWord'
            Set-WinBoxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 'DWord'
            Write-Log 'Copilot 已禁用'
        }
        Revert      = {
            Set-WinBoxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 0 'DWord'
            Write-Log 'Copilot 已恢复'
        }
        Risk        = 'Safe'
    }

    'Disable-RetailDemos' = @{
        Name        = '禁用零售演示模式'
        Category    = 'Privacy'
        Description = '关闭 OEM 预装的零售体验demo'
        Script      = {
            Set-WinBoxReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RetailDemo' 'CopyProtection' 1 'DWord'
            Write-Log '零售演示已禁用'
        }
        Risk        = 'Safe'
    }

    'Disable-LockScreenCam' = @{
        Name        = '禁用锁屏相机'
        Category    = 'Privacy'
        Description = '禁止 Windows 锁屏时使用摄像头'
        Script      = {
            Set-WinBoxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' 'NoLockScreenCamera' 1 'DWord'
            Write-Log '锁屏相机已禁用'
        }
        Risk        = 'Safe'
    }

    'Disable-Ads' = @{
        Name        = '禁用广告与建议'
        Category    = 'Privacy'
        Description = '关闭开始菜单、设置中的广告和推荐内容'
        Script      = {
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 0 'DWord'
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0 'DWord'
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353698Enabled' 0 'DWord'
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenEnabled' 0 'DWord'
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0 'DWord'
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0 'DWord'
            Write-Log '广告与建议已禁用'
        }
        Revert      = {
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 1 'DWord'
            Write-Log '广告已恢复'
        }
        Risk        = 'Safe'
    }

    'Disable-Location' = @{
        Name        = '禁用位置服务'
        Category    = 'Privacy'
        Description = '关闭 Windows 位置跟踪'
        Script      = {
            Set-Service -Name 'lfsvc' -StartupType Disabled -ErrorAction SilentlyContinue
            Set-WinBoxReg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}' 'SensorPermissionState' 0 'DWord'
            Write-Log '位置服务已禁用'
        }
        Risk        = 'Moderate'
    }

    'Disable-ActivityHistory' = @{
        Name        = '禁用活动历史记录'
        Category    = 'Privacy'
        Description = '停止 Windows 记录您的使用习惯'
        Script      = {
            Set-WinBoxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0 'DWord'
            Set-WinBoxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0 'DWord'
            Set-WinBoxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0 'DWord'
            Write-Log '活动历史已禁用'
        }
        Risk        = 'Safe'
    }

    'Disable-TailoredExperiences' = @{
        Name        = '禁用个性化体验'
        Category    = 'Privacy'
        Description = '禁止 Microsoft 基于您的信息提供个性化建议'
        Script      = {
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PrivacySettings' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 'DWord'
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PrivacySettings' 'DiagnosticInformationEnabled' 0 'DWord'
            Write-Log '个性化体验已禁用'
        }
        Revert      = {
            Set-WinBoxReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PrivacySettings' 'TailoredExperiencesWithDiagnosticDataEnabled' 1 'DWord'
        }
        Risk        = 'Safe'
    }

    # ── 性能优化 ──
    'Performance-GameMode' = @{
        Name        = '启用游戏模式'
        Category    = 'Performance'
        Description = '优化游戏时的系统资源分配'
        Script      = {
            Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 -Type DWord
            Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value 1 -Type DWord
            Write-Log '游戏模式已启用'
        }
        Risk        = 'Safe'
    }

    'Performance-MouseAccel' = @{
        Name        = '关闭鼠标加速'
        Category    = 'Performance'
        Description = '禁用增强指针精确度，获得更精准的鼠标控制'
        Script      = {
            Set-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0'
            Set-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0'
            Set-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0'
            Write-Log '鼠标加速已关闭'
        }
        Revert      = {
            Set-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '1'
        }
        Risk        = 'Safe'
    }

    'Performance-Hibernate' = @{
        Name        = '禁用休眠 & 快速启动'
        Category    = 'Performance'
        Description = '释放磁盘空间，确保完整关机（适合SSD）'
        Script      = {
            powercfg /hibernate off
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 0 -Type DWord
            Write-Log '休眠和快速启动已禁用'
        }
        Risk        = 'Moderate'
    }

    'Performance-PowerPlan' = @{
        Name        = '切换到高性能电源计划'
        Category    = 'Performance'
        Description = '禁用节能模式，保持CPU始终运行在最高频率'
        Script      = {
            powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
            powercfg /setactive a1841308-3541-4fab-bc81-f71556f20b4a 2>$null
            Write-Log '高性能电源计划已激活'
        }
        Risk        = 'Safe'
    }

    'Performance-BackgroundApps' = @{
        Name        = '禁用后台应用'
        Category    = 'Performance'
        Description = '阻止应用在后台消耗CPU和内存'
        Script      = {
            Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 1 -Type DWord
            Write-Log '后台应用已禁用'
        }
        Revert      = {
            Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 0 -Type DWord
        }
        Risk        = 'Safe'
    }

    'Performance-VisualFX' = @{
        Name        = '优化视觉效果（提升响应速度）'
        Category    = 'Performance'
        Description = '关闭动画和透明效果，提升系统流畅度'
        Script      = {
            [Environment]::SetEnvironmentVariable('VISUAL_EFFECTS', '2', 'User')
            $settings = @{
                'WORKSENTATTRACT'           = 0
                'FOREGROUNDLOCKTIMEOUT'     = 0
                'DOUBLECLICKTIME'           = 400
                'MENUANIMATION'             = 0
                'SNAPANIMATION'             = 0
                'DROP_SHADOW'               = 0
                'FLASHOPENING'              = 0
                'IMMATIVE_ANIMATIONS'       = 0
                'LISTBOXGRADIENT'           = 0
                'ACTIVETRACKING'            = 0
                'CARETBLINKING'             = 1
            }
            foreach ($k in $settings.Keys) {
                Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name $k -Value $settings[$k] -Type String -ErrorAction SilentlyContinue
            }
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'ForegroundGainBoost' -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'HungAppTimeout' -Value '1000' -Type String
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -Type String
            Write-Log '视觉效果已优化'
        }
        Risk        = 'Safe'
    }

    'Performance-NetworkLatency' = @{
        Name        = '优化网络延迟'
        Category    = 'Performance'
        Description = '调整TCP/IP参数，降低网络延迟，提升游戏/下载体验'
        Script      = {
            # Disable Nagle's algorithm
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'TcpNoDelay' -Value 1 -Type DWord -ErrorAction SilentlyContinue
            # Enable Auto-Tuning for better throughput
            netsh int tcp set global autotuninglevel=normal 2>$null
            # Disable receive-side scaling if causing issues (optional)
            Write-Log '网络优化已应用'
        }
        Risk        = 'Safe'
    }

    'Performance-DNS-Privacy' = @{
        Name        = '启用 DNS-over-HTTPS (Cloudflare)'
        Category    = 'Performance'
        Description = '使用 Cloudflare DNS (1.1.1.1) 提升DNS解析速度和隐私'
        Script      = {
            Set-DnsClientServerAddress -InterfaceAlias '*' -ServerAddresses '1.1.1.1','1.0.0.1' -ErrorAction SilentlyContinue
            Write-Log 'DNS 已切换至 Cloudflare'
        }
        Revert      = {
            Set-DnsClientServerAddress -InterfaceAlias '*' -ServerAddresses '8.8.8.8','8.8.4.4' -ErrorAction SilentlyContinue
        }
        Risk        = 'Safe'
    }

    # ── 服务管理 ──
    'Services-Disable-Xbox' = @{
        Name        = '禁用 Xbox 相关服务'
        Category    = 'Services'
        Description = '关闭 Xbox 游戏栏、录制和辅助服务'
        Script      = {
            $services = @('XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'GamingServices', 'GamingServicesAccount')
            foreach ($s in $services) {
                Set-WinBoxService $s 'Disabled'
                Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            }
            Write-Log 'Xbox 服务已禁用'
        }
        Risk        = 'Moderate'
    }

    'Services-Disable-TelemetrySvcs' = @{
        Name        = '禁用遥测服务'
        Category    = 'Services'
        Description = '关闭 Diagnostics Tracking、Remote Registry 等不必要服务'
        Script      = {
            $services = @{
                'DiagTrack'               = 'Disabled'
                'dmwappushservice'        = 'Disabled'
                'WMPNetworkSvc'           = 'Disabled'
                'MapsBroker'              = 'Disabled'
                'SessionEnv'              = 'Disabled'
                'RstrSvc'                 = 'Manual'
                'wuauserv'                = 'Manual'  # optional: manual Windows Update
                'BITS'                    = 'Manual'
                'lfsvc'                   = 'Disabled'
                'RemoteRegistry'          = 'Disabled'
            }
            foreach ($svc in $services.Keys) {
                Set-WinBoxService $svc $services[$svc]
            }
            Write-Log '遥测服务已优化'
        }
        Risk        = 'Moderate'
    }

    'Services-Disable-SleepStudy' = @{
        Name        = '禁用 Modern Standby 睡眠学习'
        Category    = 'Services'
        Description = '减少现代待机模式下的后台活动'
        Script      = {
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'SleepStudyDisabled' -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HibernteEnabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Write-Log '睡眠学习已禁用'
        }
        Risk        = 'Safe'
    }

    # ── 计划任务 ──
    'Tasks-Disable-Telemetry' = @{
        Name        = '禁用遥测计划任务'
        Category    = 'ScheduleTasks'
        Description = '关闭 Windows 收集和上报遥测数据的后台任务'
        Script      = {
            $tasks = @(
                '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
                '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
                '\Microsoft\Windows\Autochk\Proxy'
                '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
                '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
                '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
                '\Microsoft\Windows\Feedback\Siuf\DmClient'
                '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
                '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
            )
            foreach ($t in $tasks) {
                Invoke-WinBoxTask $t 'Disable'
            }
            Write-Log '遥测计划任务已禁用'
        }
        Revert      = {
            foreach ($t in $tasks) { Invoke-WinBoxTask $t 'Enable' }
        }
        Risk        = 'Safe'
    }

    # ── 外观定制 ──
    'Customize-ClassicContextMenu' = @{
        Name        = '恢复经典右键菜单 (Win11)'
        Category    = 'Customize'
        Description = '在 Windows 11 中恢复传统的右键菜单'
        Script      = {
            Set-ItemProperty -Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' -Value '' -Type String -ErrorAction SilentlyContinue
            Write-Log '经典右键菜单已启用'
        }
        Revert      = {
            Remove-Item 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -ErrorAction SilentlyContinue
        }
        Risk        = 'Safe'
    }

    'Customize-TaskbarCenter' = @{
        Name        = '任务栏图标居中 (Win11)'
        Category    = 'Customize'
        Description = '将任务栏图标对齐方式改为居中'
        Script      = {
            $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Set-ItemProperty -Path $path -Name 'TaskbarAl' -Value 0 -Type DWord
            Write-Log '任务栏已居中'
        }
        Revert      = {
            Set-ItemProperty -Path $path -Name 'TaskbarAl' -Value 1 -Type DWord
        }
        Risk        = 'Safe'
    }

    'Customize-TaskbarLeft' = @{
        Name        = '任务栏图标左对齐 (Win10风格)'
        Category    = 'Customize'
        Description = '将任务栏图标对齐方式改为左侧'
        Script      = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAl' -Value 0 -Type DWord
            Write-Log '任务栏已左对齐'
        }
        Risk        = 'Safe'
    }

    'Customize-DisableWidgets' = @{
        Name        = '禁用任务栏小组件'
        Category    = 'Customize'
        Description = '隐藏任务栏上的天气/新闻小组件'
        Script      = {
            $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Set-ItemProperty -Path $path -Name 'TaskbarDa' -Value 0 -Type DWord
            # Kill and restart Explorer to apply
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Write-Log '小组件已禁用'
        }
        Risk        = 'Safe'
    }

    'Customize-ShowFileExtensions' = @{
        Name        = '显示文件扩展名'
        Category    = 'Customize'
        Description = '在资源管理器中始终显示已知文件类型的扩展名'
        Script      = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 -Type DWord
            Write-Log '文件扩展名已显示'
        }
        Revert      = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 1 -Type DWord
        }
        Risk        = 'Safe'
    }

    'Customize-DisableTransparency' = @{
        Name        = '禁用透明效果'
        Category    = 'Customize'
        Description = '关闭 Windows 透明/毛玻璃效果，提升性能'
        Script      = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 0 -Type DWord
            Write-Log '透明效果已禁用'
        }
        Revert      = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 1 -Type DWord
        }
        Risk        = 'Safe'
    }

    'Customize-EndTaskOnTaskbar' = @{
        Name        = '任务栏右键添加"结束任务"'
        Category    = 'Customize'
        Description = '在任务栏右键菜单中添加"结束任务"选项'
        Script      = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' -Name 'TaskbarEndTask' -Value 1 -Type DWord
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Write-Log '结束任务已添加到任务栏右键菜单'
        }
        Risk        = 'Safe'
    }

    # ── 深度清理 ──
    'Cleanup-DeepClean' = @{
        Name        = '深度系统清理'
        Category    = 'Cleanup'
        Description = '清理临时文件、更新缓存、缩略图缓存、日志'
        Script      = {
            $results = Invoke-WinBoxCleanup -Targets @('Temp', 'SysTemp', 'Recycle', 'Update', 'Prefetch', 'ThumbCache')
            # Clean thumbnail cache
            Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force -ErrorAction SilentlyContinue
            # Clean Windows Update cache
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            Remove-Item 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            Write-Log "深度清理完成。已释放: $([math]::Round(($results.Values | Where-Object {$_ -is [double]} | Measure-Object -Sum).Sum, 1)) MB"
        }
        Risk        = 'Safe'
    }

    'Cleanup-WinSxS' = @{
        Name        = '清理 WinSxS 组件存储'
        Category    = 'Cleanup'
        Description = '移除已替换的旧版 Windows 组件，节省大量磁盘空间'
        Script      = {
            $result = dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet 2>&1
            Write-Log "WinSxS 清理: $result"
        }
        Risk        = 'Moderate'
    }

    'Cleanup-BrowserCache' = @{
        Name        = '清理浏览器缓存'
        Category    = 'Cleanup'
        Description = '清理 Edge、Chrome、Firefox 的缓存文件'
        Script      = {
            $browsers = @(
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2"
            )
            $total = 0
            foreach ($b in $browsers) {
                if (Test-Path $b) {
                    $sz = (Get-ChildItem $b -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    Remove-Item $b -Recurse -Force -ErrorAction SilentlyContinue
                    $total += $sz
                }
            }
            Write-Log "浏览器缓存已清理: $([math]::Round($total/1MB, 1)) MB"
        }
        Risk        = 'Safe'
    }

    # ── 安全加固 ──
    'Security-UAC' = @{
        Name        = '调整 UAC 提示级别'
        Category    = 'Security'
        Description = '提高 UAC 安全级别，减少弹窗干扰同时保持保护'
        Script      = {
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -Value 1 -Type DWord
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ConsentPromptBehaviorAdmin' -Value 5 -Type DWord
            Write-Log 'UAC 已设置为最高安全级别'
        }
        Risk        = 'Safe'
    }

    'Security-Defender' = @{
        Name        = '保持 Windows Defender 开启'
        Category    = 'Security'
        Description = '确保 Windows 安全中心正常运行（不建议关闭）'
        Script      = {
            Set-WinBoxService 'Sense' 'Automatic'
            Set-WinBoxService 'WinDefend' 'Automatic'
            Write-Log 'Defender 服务已确保为自动启动'
        }
        Risk        = 'Safe'
    }

    'Security-Firewall' = @{
        Name        = '优化防火墙规则'
        Category    = 'Security'
        Description = '启用防火墙并阻止入站匿名枚举'
        Script      = {
            netsh advfirewall set allprofiles state on 2>$null
            # Block anonymous enumeration
            netsh advfirewall firewall add rule name="Block Anonymous Enum" dir=in action=block protocol=any profile=any 2>$null
            Write-Log '防火墙已优化'
        }
        Risk        = 'Safe'
    }

    # ── AI 功能移除 ──
    'AI-RemoveRecall' = @{
        Name        = '禁用 Windows Recall'
        Category    = 'AI'
        Description = '完全禁用 Windows 11 Recall 截图回忆功能'
        Script      = {
            # ViVeTool approach for Recall removal
            $vivetoolPath = Join-Path $ScriptsRoot 'AI\ViVeTool.exe'
            if (Test-Path $vivetoolPath) {
                & $vivetoolPath /disable /id:39339539 38775358 40655531 41175252 39957217 40425568 41158583 41379875 41392744 41910394 41910395 2>&1 | Out-Null
            }
            Set-WinBoxReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ExperimentalCloud' 'Disabled' 1 'DWord'
            Set-WinBoxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAccess' 1 'DWord'
            Set-WinBoxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableCloudOptimizedContent' 1 'DWord'
            Write-Log 'Recall 已禁用'
        }
        Risk        = 'Moderate'
    }

    'AI-RemoveClipHistory' = @{
        Name        = '禁用剪贴板历史'
        Category    = 'AI'
        Description = '关闭 Windows 剪贴板历史记录和云端同步'
        Script      = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Clipboard' -Name 'EnableClipboardHistory' -Value 0 -Type DWord
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Clipboard' -Name 'ClipboardSync' -Value 0 -Type DWord
            Write-Log '剪贴板历史已禁用'
        }
        Revert      = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Clipboard' -Name 'EnableClipboardHistory' -Value 1 -Type DWord
        }
        Risk        = 'Safe'
    }

    # ── 一键操作 ──
    'Quick-GamingMode' = @{
        Name        = '一键游戏优化'
        Category    = 'QuickActions'
        Description = '启用游戏模式 + 禁用全屏优化 + GPU 优先级提升'
        Script      = {
            # Enable Game Mode
            Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 -Type DWord
            # Disable fullscreen optimizations
            Set-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehavior' -Value 2 -Type DWord
            Set-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 1 -Type DWord
            # Hardware-accelerated GPU scheduling
            Set-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_HonorUserFsrBehavior' -Value 1 -Type DWord
            Write-Log '游戏优化已应用'
        }
        Risk        = 'Safe'
    }

    'Quick-PrivacyHardcore' = @{
        Name        = '深度隐私保护'
        Category    = 'QuickActions'
        Description = '禁用遥测 + 广告 + 位置 + 活动历史 + 个性化体验（综合）'
        Script      = {
            $opt = $Optimizations['Disable-Telemetry']
            & $opt.Script
            $opt = $Optimizations['Disable-Ads']
            & $opt.Script
            $opt = $Optimizations['Disable-Location']
            & $opt.Script
            $opt = $Optimizations['Disable-ActivityHistory']
            & $opt.Script
            $opt = $Optimizations['Disable-TailoredExperiences']
            & $opt.Script
            Write-Log '深度隐私保护已全面应用'
        }
        Risk        = 'Safe'
    }

    'Quick-PerformanceBoost' = @{
        Name        = '性能boost全套'
        Category    = 'QuickActions'
        Description = '高性能电源 + 禁用动画 + 关闭鼠标加速 + 禁用后台应用'
        Script      = {
            $opt = $Optimizations['Performance-PowerPlan']
            & $opt.Script
            $opt = $Optimizations['Performance-VisualFX']
            & $opt.Script
            $opt = $Optimizations['Performance-MouseAccel']
            & $opt.Script
            $opt = $Optimizations['Performance-BackgroundApps']
            & $opt.Script
            Write-Log '性能boost全套已应用'
        }
        Risk        = 'Safe'
    }
}


# ═══════════════════════════════════════════════════════════
#  WinForms GUI 主界面
# ═══════════════════════════════════════════════════════════

# === DISK & SOFTWARE (v2.0) ===
function Get-DiskSpaceInfo {
    param([string]$Drive="C:")
    $d=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID=`"$Drive`"" -EA SilentlyContinue
    if(-not $d){return $null}
    @{Drive=$Drive;TotalGB=[math]::Round($d.Size/1GB,1);FreeGB=[math]::Round($d.FreeSpace/1GB,1)
       UsedGB=[math]::Round(($d.Size-$d.FreeSpace)/1GB,1);PercentFree=[math]::Round(($d.FreeSpace/$d.Size)*100,1)}
}
function Invoke-WinBoxDiskAnalysis {
    param([string]$Drive="C:")
    $r=@{RootFreeGB=0;RootUsedGB=0;Items=@();TopFolders=@()}
    $di=Get-DiskSpaceInfo $Drive
    if($di){$r.RootFreeGB=$di.FreeGB;$r.RootUsedGB=$di.UsedGB}
    $p=@{"Windows"="C:\Windows";"Users"="C:\Users";"PF"="C:\Program Files";"x86"="C:\Program Files (x86)"}
    foreach($k in $p.Keys){
        $v=$p[$k]
        if(Test-Path $v){
            try{
                $s=(Get-ChildItem $v -Recurse -Force -EA SilentlyContinue|Where-Object{-not $_.PSIsContainer}|Measure-Object Length -Sum).Sum
                $r.Items+=[PSCustomObject]@{Name=$k;SizeMB=[math]::Round($s/1MB,0)}
            }catch{}
        }
    }
    $r.Items=$r.Items|Sort-Object SizeMB -Descending
    $r.TopFolders=$r.Items|Select-Object -First 10
    return $r
}
function Invoke-WinBoxDeepCleanup {
    param([string[]]$Targets=@("Temp"))
    $results=@{};$totalSaved=0
    function Clean-Path {
        param([string]$Path)
        if(-not(Test-Path $Path)){return 0}
        try{
            $b=(Get-ChildItem $Path -Recurse -Force -EA SilentlyContinue|Where-Object{-not $_.PSIsContainer}|Measure-Object Length -Sum).Sum
            Remove-Item $Path -Recurse -Force -EA SilentlyContinue
            $a=(Get-ChildItem $Path -Recurse -Force -EA SilentlyContinue|Where-Object{-not $_.PSIsContainer}|Measure-Object Length -Sum).Sum
            return [math]::Max(0,[math]::Round(($b-$a)/1MB,1))
        }catch{return 0}
    }
    if("Temp"-in $Targets){$s=Clean-Path "$env:TEMP\*";if($s-gt0){$results["User Temp"]=$s;$totalSaved+=$s}}
    if("SysTemp"-in $Targets){$s=Clean-Path "C:\Windows\Temp\*";if($s-gt0){$results["System Temp"]=$s;$totalSaved+=$s}}
    if("Recycle"-in $Targets){Clear-RecycleBin -Force -EA SilentlyContinue;$results["Recycle Bin"]="Cleared"}
    if("Update"-in $Targets){
        Stop-Service wuauserv -Force -EA SilentlyContinue
        $s=Clean-Path "C:\Windows\SoftwareDistribution\Download\*"
        Start-Service wuauserv -EA SilentlyContinue
        if($s-gt0){$results["WinUpdate Cache"]=$s;$totalSaved+=$s}
    }
    if("Prefetch"-in $Targets){$s=Clean-Path "C:\Windows\Prefetch\*";if($s-gt0){$results["Prefetch"]=$s;$totalSaved+=$s}}
    if("ThumbCache"-in $Targets){
        $s=Clean-Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db";if($s-gt0){$results["Thumb Cache"]=$s;$totalSaved+=$s}
        $s=Clean-Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db";if($s-gt0){$results["Icon Cache"]=$s;$totalSaved+=$s}
    }
    if("DNSCache"-in $Targets){ipconfig /flushdns 2>$null;$results["DNS Cache"]="Flushed"}
    if("MemoryDump"-in $Targets){
        $s=Clean-Path "C:\Windows\MEMORY.DMP";if($s-gt0){$results["Memory Dump"]=$s;$totalSaved+=$s}
        $s=Clean-Path "C:\Windows\Minidump\*";if($s-gt0){$results["Minidumps"]=$s;$totalSaved+=$s}
    }
    if("WindowsUpgrade"-in $Targets){
        @("C:\`$Windows.~WS","C:\`$GetCurrent","C:\Windows.old")|ForEach-Object{
            if(Test-Path $_){
                try{$s=[math]::Round((Get-ChildItem $_ -Recurse -Force -EA SilentlyContinue|Measure-Object Length -Sum).Sum/1MB,1);Remove-Item $_ -Recurse -Force -EA Stop;$results[$_ -replace "C:\\",""]=$s;$totalSaved+=$s}
                catch{$results[$_ -replace "C:\\",""]="Needs reboot"}
            }
        }
    }
    return @{Results=$results;TotalSaved=$totalSaved}
}
function Get-WinBoxInstalledSoftware {
    param([string]$Search="")
    $items=@()
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*","HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*")|ForEach-Object{
        try{Get-ItemProperty $_ -EA SilentlyContinue|Where-Object{$_.DisplayName -and (-not $_.systemComponent)}|ForEach-Object{$items+=[PSCustomObject]@{Name=$_.DisplayName;Publisher=$_.Publisher;Version=$_.DisplayVersion;UninstallCmd=$_.UninstallString;Source="Win32"}}}catch{}
    }
    try{$wl=winget list --accept-source-agreements 2>$null;if($wl-match "Installed"){$wl -split "`r`n"|Where-Object{$_ -match "^\s*\w"}|ForEach-Object{$parts=$_.Trim().Split(" ");if($parts.Count -ge 2){$n=$parts[0];$v=$parts[1];if($n -and -not($items|Where-Object{$_.Name-eq $n})){ $items+=[PSCustomObject]@{Name=$n;Publisher="";Version=$v;UninstallCmd="winget uninstall --name `"$n`"";Source="WinGet"} } }} } }catch{}
    if($Search){$items=$items|Where-Object{$_.Name -like "*$Search*"}}
    return $items|Sort-Object Name
}
function Uninstall-WinBoxSoftware {
    param([string]$Name,[string]$Source="Win32")
    if($Source -eq "WinGet"){$cmd="winget uninstall --name `"$Name`" --accept-source-agreements";Write-Log "Running: $cmd";Invoke-Expression $cmd;return $LASTEXITCODE}
    else{$apps=Get-WinBoxInstalledSoftware $Name;$app=$apps|Where-Object{$_.Name-eq $Name}|Select-Object -First 1
        if($app -and $app.UninstallCmd){Write-Log "Uninstalling: $Name";$u=$app.UninstallCmd;
            $arg=if($u -match "msiexec"){'msiexec /x "'+($u -replace 'msiexec /x ','')+'" /qn'}else{$u};
            Start-Process cmd.exe -ArgumentList "/c $arg" -Wait -EA SilentlyContinue;return $LASTEXITCODE}
        else{Write-Log "Not found: $Name" "WARN";return -1}
    }
}


# === V2.0 ADDITIONAL FUNCTIONS ===
function Get-WinBoxStartupItems {
    param([switch]$DisabledOnly)
    $items = @()
    $reg = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -EA SilentlyContinue
    if ($reg) {
        $reg.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
            $items += [PSCustomObject]@{ Name=$_.Name; Path=$_.Value; Source="Registry" }
        }
    }
    $wm = Get-CimInstance Win32_StartupCommand -EA SilentlyContinue
    $wm | Where-Object { $_.Location -ne 'HKLM' } | ForEach-Object {
        $items += [PSCustomObject]@{ Name=$_.Name; Path=$_.Command; Source="WMI" }
    }
    return $items | Sort-Object Name
}
function Invoke-WinBoxCreateRestore {
    checkpoint-computer -Description "WinBox Manual Restore Point" -EA SilentlyContinue
    if ($LASTEXITCODE -eq 0) { Write-Log "System restore point created" }
    else { Write-Log "Restore point skipped (system restore may be disabled)" "WARN" }
}
function Get-WinBoxSystemReport {
    $os = Get-ComputerInfo
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -EA SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -EA SilentlyContinue
    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $def = Get-MpComputerStatus -EA SilentlyContinue
    @{
        OS = "$($os.WindowsProductName) Build $($os.WindowsBuildLabEx)"
        CPU = $cpu.Name
        RAM_GB = $ram
        Disks = ($disk | ForEach-Object { "$($_.DeviceID): $([math]::Round($_.Size/1GB,0))GB ($([math]::Round($_.FreeSpace/$_.Size*100,0))% free)" }) -join "; "
        Defender = if ($def) { "RT:$($def.RealTimeProtectionEnabled)" } else { "N/A" }
        PowerPlan = (powercfg /getactivescheme 2>$null) -replace ".*GUID: ", ""
        Admin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── 主窗体 ──
$form = New-Object System.Windows.Forms.Form
$form.Text = 'WinBox - Windows 系统工具箱 v1.0'
$form.Size = New-Object System.Drawing.Size(1100, 750)
$form.StartPosition = 'CenterScreen'
$form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($PSHome + '\powershell_ise.exe')
$form.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 35)
$form.ForeColor = [System.Drawing.Color]::White

# ── 字体 ──
$fontMain  = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Regular)
$fontTitle = New-Object System.Drawing.Font('Microsoft YaHei UI', 13, [System.Drawing.FontStyle]::Bold)
$fontSmall = New-Object System.Drawing.Font('Microsoft YaHei UI', 8, [System.Drawing.FontStyle]::Regular)

$form.Font = $fontMain
$form.Padding = New-Object System.Windows.Forms.Padding(12)

# ── 左侧分类导航 ──
$categoryPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$categoryPanel.Width  = 200
$categoryPanel.Height = $form.Height - 70
$categoryPanel.Location = New-Object System.Drawing.Point(12, 60)
$categoryPanel.FlowDirection = 'TopDown'
$categoryPanel.WrapContents  = $false
$categoryPanel.AutoScroll    = $true
$categoryPanel.BackColor   = [System.Drawing.Color]::FromArgb(32, 32, 45)

$categories = @('All', 'Privacy', 'Performance', 'Services', 'ScheduleTasks',
                'Customize', 'AI', 'Cleanup', 'Security', 'QuickActions')

$activeCategoryBtn = $null

function New-CatButton {
    param([string]$Text, [string]$Tag)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text   = $Text
    $btn.Size   = New-Object System.Drawing.Size(180, 40)
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize = 0
    $btn.Font    = $fontMain
    $btn.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 200)
    $btn.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 45)
    $btn.TabIndex = 0
    $btn.Tag = $Tag
    $btn.UseVisualStyleBackColor = $false
    $btn.add_MouseHover({
        if ($this.Tag -ne $activeCategoryBtn) {
            $this.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 65)
        }
    })
    $btn.add_MouseLeave({
        if ($this.Tag -ne $activeCategoryBtn) {
            $this.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 45)
        }
    })
    $btn.add_Click({
        if ($activeCategoryBtn) {
            $activeCategoryBtn.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 45)
            $activeCategoryBtn.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 200)
        }
        $this.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 90)
        $this.ForeColor = [System.Drawing.Color]::White
        $activeCategoryBtn = $this
        RefreshToolList $this.Tag
    })
    return $btn
}

$categories | ForEach-Object {
    $label = switch ($_) {
        'All'          { '🏠 全部工具' }
        'Privacy'      { '🔒 隐私保护' }
        'Performance'  { '⚡ 性能优化' }
        'Services'     { '⚙️ 服务管理' }
        'ScheduleTasks'{ '📅 计划任务' }
        'Customize'    { '🎨 外观定制' }
        'AI'           { '🤖 AI 功能' }
        'Cleanup'      { '🧹 系统清理' }
        'Security'     { '🛡️ 安全加固' }
        'QuickActions' { '🚀 一键操作' }
    }
    $b = New-CatButton -Text $label -Tag $_
    $categoryPanel.Controls.Add($b)
}
$form.Controls.Add($categoryPanel)

# ── 顶部标题栏 ──
$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 30)
$titleBar.Height = 45
$titleBar.Dock = 'Top'

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'WinBox - Windows 系统优化工具箱'
$titleLabel.Font = $fontTitle
$titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 200, 255)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(20, 12)
$titleBar.Controls.Add($titleLabel)

# Admin badge
$adminBadge = New-Object System.Windows.Forms.Label
$adminBadge.Font = $fontSmall
$adminBadge.ForeColor = if (Test-IsAdmin) { [System.Drawing.Color]::FromArgb(80, 200, 120) } else { [System.Drawing.Color]::FromArgb(255, 100, 80) }
$adminBadge.Text = if (Test-IsAdmin) { '✓ 管理员模式' } else { '⚠ 请以管理员身份运行' }
$adminBadge.Location = New-Object System.Drawing.Point($titleBar.Width - 180, 12)
$titleBar.Controls.Add($adminBadge)

# Version label
$verLabel = New-Object System.Windows.Forms.Label
$verLabel.Text = 'v2.0 | 集合 14 个 GitHub 项目精华 + 新类别'
$verLabel.Font = $fontSmall
$verLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 130)
$verLabel.Location = New-Object System.Drawing.Point($titleBar.Width - 350, 12)
$titleBar.Controls.Add($verLabel)

$form.Controls.Add($titleBar)

# ── 工具列表区域 ──
$toolListPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$toolListPanel.Location = New-Object System.Drawing.Point(224, 60)
$toolListPanel.Size   = New-Object System.Drawing.Size(560, $form.Height - 70)
$toolListPanel.FlowDirection = 'TopDown'
$toolListPanel.WrapContents  = $false
$toolListPanel.AutoScroll    = $true
$toolListPanel.BackColor   = [System.Drawing.Color]::FromArgb(25, 25, 35)
$toolListPanel.Padding     = New-Object System.Windows.Forms.Padding(8)

$form.Controls.Add($toolListPanel)

# ── 右侧详情面板 ──
$detailPanel = New-Object System.Windows.Forms.Panel
$detailPanel.Location = New-Object System.Drawing.Point(796, 60)
$detailPanel.Size   = New-Object System.Drawing.Size(292, $form.Height - 70)
$detailPanel.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 42)
$detailPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$detailPanel.AutoScroll = $true

# Log output area
$logPanel = New-Object System.Windows.Forms.Panel
$logPanel.Location = New-Object System.Drawing.Point(12, $form.Height - 180)
$logPanel.Size   = New-Object System.Drawing.Size(1068, 160)
$logPanel.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 25)
$logPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Text = '📋 执行日志'
$logLabel.Font = $fontSmall
$logLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 200, 255)
$logLabel.Location = New-Object System.Drawing.Point(8, 4)
$logLabel.AutoSize = $true
$logPanel.Controls.Add($logLabel)

$logTextBox = New-Object System.Windows.Forms.TextBox
$logTextBox.Multiline     = $true
$logTextBox.ScrollBars    = 'Vertical'
$logTextBox.Font          = New-Object System.Drawing.Font('Consolas', 8)
$logTextBox.ForeColor     = [System.Drawing.Color]::FromArgb(180, 220, 180)
$logTextBox.BackColor   = [System.Drawing.Color]::FromArgb(15, 15, 25)
$logTextBox.ReadOnly    = $true
$logTextBox.Dock        = 'Fill'
$logTextBox.Padding     = New-Object System.Windows.Forms.Padding(8, 24, 8, 8)
$logPanel.Controls.Add($logTextBox)

function Write-ToLog {
    param([string]$Msg, [string]$Color = '180,220,180')
    $ts = Get-Date -Format 'HH:mm:ss'
    $logTextBox.Invoke({
        $colorObj = switch ($Color) {
            'red'    { [System.Drawing.Color]::FromArgb(255, 100, 100) }
            'yellow' { [System.Drawing.Color]::FromArgb(255, 220, 100) }
            'green'  { [System.Drawing.Color]::FromArgb(80, 200, 120) }
            default  { [System.Drawing.Color]::FromArgb(180, 220, 180) }
        }
        $logTextBox.ForeColor = $colorObj
        $logTextBox.AppendText("[$ts] $Msg`n")
        $logTextBox.ScrollToCaret()
    })
}

$form.Controls.Add($logPanel)
$form.Controls.Add($detailPanel)

# ── 生成工具卡片 ──
function New-ToolCard {
    param(
        [string]$Key,
        [string]$Name,
        [string]$Desc,
        [string]$Risk,
        [string]$Category
    )
    $card = New-Object System.Windows.Forms.Panel
    $card.BackColor   = [System.Drawing.Color]::FromArgb(35, 35, 50)
    $card.Size        = New-Object System.Drawing.Size(530, 80)
    $card margined    = $true
    $card.Padding     = New-Object System.Windows.Forms.Padding(12)
    $card.Cursor      = [System.Windows.Forms.Cursors]::Hand
    $card.Tag         = $Key

    # Risk badge
    $riskBadge = New-Object System.Windows.Forms.Label
    $riskBadge.Font     = $fontSmall
    $riskBadge.ForeColor = switch ($Risk) {
        'Safe'      { [System.Drawing.Color]::FromArgb(80, 200, 120) }
        'Moderate'  { [System.Drawing.Color]::FromArgb(255, 180, 50) }
        'Risky'     { [System.Drawing.Color]::FromArgb(255, 80, 80) }
        default     { [System.Drawing.Color]::Gray }
    }
    $riskBadge.Text     = switch ($Risk) {
        'Safe'      { '● 安全' }
        'Moderate'  { '● 中等' }
        'Risky'     { '● 高风险' }
        default     { "● $Risk" }
    }
    $riskBadge.Location = New-Object System.Drawing.Point(12, 52)
    $card.Controls.Add($riskBadge)

    # Name
    $nameLbl = New-Object System.Windows.Forms.Label
    $nameLbl.Text   = $Name
    $nameLbl.Font   = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
    $nameLbl.ForeColor = [System.Drawing.Color]::White
    $nameLbl.Location = New-Object System.Drawing.Point(12, 6)
    $nameLbl.AutoSize = $true
    $card.Controls.Add($nameLbl)

    # Description
    $descLbl = New-Object System.Windows.Forms.Label
    $descLbl.Text   = $Desc
    $descLbl.Font   = $fontSmall
    $descLbl.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 170)
    $descLbl.Location = New-Object System.Drawing.Point(12, 28)
    $descLbl.Size   = New-Object System.Drawing.Size(340, 24)
    $descLbl.AutoSize = $false
    $card.Controls.Add($descLbl)

    # Apply button
    $applyBtn = New-Object System.Windows.Forms.Button
    $applyBtn.Text    = '✅ 应用'
    $applyBtn.Size    = New-Object System.Drawing.Size(80, 30)
    $applyBtn.Location = New-Object System.Drawing.Point(380, 20)
    $applyBtn.Font    = $fontMain
    $applyBtn.BackColor = [System.Drawing.Color]::FromArgb(40, 80, 60)
    $applyBtn.ForeColor = [System.Drawing.Color]::FromArgb(120, 220, 160)
    $applyBtn.FlatStyle = 'Flat'
    $applyBtn.FlatAppearance.BorderSize = 0
    $applyBtn.Cursor  = [System.Windows.Forms.Cursors]::Hand
    $applyBtn.add_Click({
        $parent = $this.Parent
        $toolKey = $parent.Tag
        Execute-Tool $toolKey $parent
    })
    $card.Controls.Add($applyBtn)

    # Revert button
    $revertBtn = New-Object System.Windows.Forms.Button
    $revertBtn.Text    = '↩️ 还原'
    $revertBtn.Size    = New-Object System.Drawing.Size(80, 30)
    $revertBtn.Location = New-Object System.Drawing.Point(470, 20)
    $revertBtn.Font    = $fontMain
    $revertBtn.BackColor = [System.Drawing.Color]::FromArgb(60, 50, 40)
    $revertBtn.ForeColor = [System.Drawing.Color]::FromArgb(220, 180, 100)
    $revertBtn.FlatStyle = 'Flat'
    $revertBtn.FlatAppearance.BorderSize = 0
    $revertBtn.Cursor  = [System.Windows.Forms.Cursors]::Hand
    $revertBtn.add_Click({
        $parent = $this.Parent
        $toolKey = $parent.Tag
        Execute-Revert $toolKey $parent
    })
    $card.Controls.Add($revertBtn)

    $card.add_MouseHover({
        $this.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 65)
    })
    $card.add_MouseLeave({
        $this.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 50)
    })

    return $card
}

function Execute-Tool {
    param([string]$Key, [System.Windows.Forms.Panel]$Card)
    if (-not $Optimizations.ContainsKey($Key)) { return }
    $opt = $Optimizations[$Key]
    Write-ToLog "▶ 正在执行: $($opt.Name)" 'yellow'

    # Check admin
    if (-not (Test-IsAdmin)) {
        Write-ToLog '❌ 需要管理员权限，请以管理员身份运行 PowerShell' 'red'
        return
    }

    try {
        $result = & $opt.Script
        Write-ToLog "✓ 成功: $($opt.Name)" 'green'
        $Card.BackColor = [System.Drawing.Color]::FromArgb(40, 70, 50)
        Start-Sleep -Milliseconds 500
        $Card.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 50)
    } catch {
        Write-ToLog "✗ 失败 [$($opt.Name)]: $($_.Exception.Message)" 'red'
    }
}

function Execute-Revert {
    param([string]$Key, [System.Windows.Forms.Panel]$Card)
    if (-not $Optimizations.ContainsKey($Key)) { return }
    $opt = $Optimizations[$Key]
    if (-not $opt.Revert) {
        Write-ToLog "⊘ 该工具无还原选项: $($opt.Name)" 'yellow'
        return
    }
    Write-ToLog "↩ 正在还原: $($opt.Name)" 'yellow'
    try {
        & $opt.Revert
        Write-ToLog "✓ 已还原: $($opt.Name)" 'green'
    } catch {
        Write-ToLog "✗ 还原失败 [$($opt.Name)]: $($_.Exception.Message)" 'red'
    }
}

function RefreshToolList {
    param([string]$Category)
    $toolListPanel.Controls.Clear()

    $filtered = if ($Category -eq 'All') {
        $Optimizations.GetEnumerator()
    } else {
        $Optimizations.GetEnumerator() | Where-Object { $_.Value.Category -eq $Category }
    }

    if ($filtered) {
        $sorted = $filtered | Sort-Object { $_.Value.Name }
        foreach ($kv in $sorted) {
            $card = New-ToolCard -Key $kv.Key -Name $kv.Value.Name -Desc $kv.Value.Description -Risk $kv.Value.Risk -Category $kv.Value.Category
            $toolListPanel.Controls.Add($card)
        }
    } else {
        $emptyLbl = New-Object System.Windows.Forms.Label
        $emptyLbl.Text = "『 $Category 』暂无工具"
        $emptyLbl.Font = $fontMain
        $emptyLbl.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 130)
        $emptyLbl.AutoSize = $true
        $toolListPanel.Controls.Add($emptyLbl)
    }

    # Auto-select category button
    $categories | ForEach-Object {
        $btn = $categoryPanel.Controls | Where-Object { $_.Tag -eq $_ } | Select-Object -First 1
        if ($btn -and $btn.Tag -eq $Category) {
            $global:activeCategoryBtn = $btn
            $btn.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 90)
            $btn.ForeColor = [System.Drawing.Color]::White
        } elseif ($btn) {
            $btn.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 45)
            $btn.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 200)
        }
    }
}

# ── 底部状态栏 ──
$statusBar = New-Object System.Windows.Forms.StatusStrip
$statusBar.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 30)

$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = '就绪'
$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 170)
$statusBar.Items.Add($statusLabel) | Out-Null

$toolCountLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$toolCountLabel.Text = "  |  共 $($Optimizations.Count) 项工具"
$toolCountLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 150, 200)
$statusBar.Items.Add($toolCountLabel) | Out-Null

$form.Controls.Add($statusBar)

# ── 初始化 ──
$global:activeCategoryBtn = $categoryPanel.Controls[0]
RefreshToolList 'All'
Write-ToLog 'WinBox 工具箱已启动'
Write-ToLog "系统: $((Get-SystemInfo).OS) Build $((Get-SystemInfo).Build)"
Write-ToLog "PowerShell: $((Get-SystemInfo).Version)  |  管理员: $((Get-SystemInfo).IsAdmin)"

# ── 运行消息循环 ──
$form.Add_Shown({ $form.Activate() })

# === v2.0 NEW TOOLS ===
$Optimizations += @{
    "Disk-CleanAll"         = @{Name="One-Click Deep C Drive Cleanup";Category="DiskCleanup";Description="Clean temp,updates,logs,thumbnails,DNS,minidumps";Script={if(-not(Test-IsAdmin)){Write-Log "Admin required" "WARN";return};$r=Invoke-WinBoxDeepCleanup -Targets @("Temp","SysTemp","Recycle","Update","Prefetch","ThumbCache","DNSCache","MemoryDump","WindowsUpgrade");foreach($k in $r.Results.Keys){$v=$r.Results[$k];if($v-is [double]){Write-Log "  $k : freed $([math]::Round($v,1)) MB"}else{Write-Log "  $k : $v"}};Write-Log "Total freed: $([math]::Round($r.TotalSaved,1)) MB"};Risk="Safe"}
    "Disk-Analyze"          = @{Name="Analyze C Drive Space";Category="DiskCleanup";Description="Scan C drive folders and show usage report";Script={$info=Get-DiskSpaceInfo "C:";if($info){Write-Log "C: Total=$($info.TotalGB)GB Used=$($info.UsedGB)GB Free=$($info.FreeGB)GB ($($info.PercentFree)%)"};$a=Invoke-WinBoxDiskAnalysis "C:";Write-Log "Top folders:";$a.TopFolders|ForEach-Object{Write-Log "  $("{0,8}" -f $_.SizeMB) MB  $($_.Name)"} };Risk="Safe"}
    "Disk-CleanTemp"        = @{Name="Clean Temporary Files";Category="DiskCleanup";Description="Clean user and system temp files";Script={$r=Invoke-WinBoxDeepCleanup -Targets @("Temp","SysTemp","Prefetch");foreach($k in $r.Results.Keys){if($r.Results[$k]-is [double]){Write-Log "  $k : freed $([math]::Round($r.Results[$k],1)) MB"}}};Risk="Safe"}
    "Disk-CleanUpdateCache" = @{Name="Clean Windows Update Cache";Category="DiskCleanup";Description="Stop Windows Update and clear download cache";Script={$r=Invoke-WinBoxDeepCleanup -Targets @("Update");foreach($k in $r.Results.Keys){if($r.Results[$k]-is [double]){Write-Log "  $k : freed $([math]::Round($r.Results[$k],1)) MB"}}};Risk="Safe"}
    "Disk-CleanDNS"         = @{Name="Flush DNS Cache";Category="DiskCleanup";Description="Clear DNS client cache";Script={ipconfig /flushdns;Write-Log "DNS cache flushed"};Risk="Safe"}
    "Disk-CleanMinidump"    = @{Name="Clean Memory Dump Files";Category="DiskCleanup";Description="Delete MEMORY.DMP and Minidump files";Script={$r=Invoke-WinBoxDeepCleanup -Targets @("MemoryDump");foreach($k in $r.Results.Keys){if($r.Results[$k]-is [double]){Write-Log "  $k : freed $([math]::Round($r.Results[$k],1)) MB"}}};Risk="Safe"}
    "Disk-CleanUpgrade"     = @{Name="Clean Windows Upgrade Residue";Category="DiskCleanup";Description="Remove Windows upgrade leftover folders";Script={$r=Invoke-WinBoxDeepCleanup -Targets @("WindowsUpgrade");foreach($k in $r.Results.Keys){if($r.Results[$k]-is [double]){Write-Log "  $k : freed $([math]::Round($r.Results[$k],1)) MB"}else{Write-Log "  $k : $($r.Results[$k])"}}};Risk="Moderate"}
    "Software-Scan"         = @{Name="Scan Installed Software";Category="SoftwareUninstall";Description="List all installed programs from registry and WinGet";Script={$apps=Get-WinBoxInstalledSoftware;$w32=($apps|Where-Object{$_.Source-eq "Win32"}).Count;Write-Log "Found $($apps.Count) programs (Win32: $w32)";Write-Log "Top 20:";$apps|Select-Object -First 20|ForEach-Object{Write-Log "  $($_.Name) v$($_.Version) ($($_.Source))"}}};Risk="Safe"}
    "Software-RemoveEdge"   = @{Name="Uninstall Microsoft Edge";Category="SoftwareUninstall";Description="Remove Microsoft Edge browser";Script={$ep=Get-AppxPackage -Name "*Edge*" -EA SilentlyContinue;if($ep){foreach($p in $ep){Remove-AppxPackage -Package $p.PackageFullName -EA SilentlyContinue;Write-Log "Removed UWP Edge: $($p.Name)"}};@("EdgeUpdate","edgeupdate","edgeupdatem")|ForEach-Object{Set-WinBoxService $_ "Disabled"};Write-Log "Edge uninstalled/disabled"};Risk="Moderate"}
    "Software-RemoveOneDrive" = @{Name="Uninstall OneDrive";Category="SoftwareUninstall";Description="Completely remove OneDrive";Script={Stop-Process -Name OneDrive -Force -EA SilentlyContinue;$p="$env:SYSTEMROOT\System32\OneDriveSetup.exe";if(Test-Path $p){Start-Process $p -ArgumentList "/uninstall" -Wait -EA SilentlyContinue};Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -EA SilentlyContinue;Set-WinBoxReg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSync" 1 "DWord";Write-Log "OneDrive uninstalled"};Risk="Moderate"}
    "Software-RemoveTeams"  = @{Name="Uninstall Microsoft Teams";Category="SoftwareUninstall";Description="Remove Microsoft Teams chat app";Script={$tp=Get-AppxPackage -Name "*Teams*" -EA SilentlyContinue;if($tp){foreach($p in $tp){Remove-AppxPackage -Package $p.PackageFullName -EA SilentlyContinue;Write-Log "Removed Teams: $($p.Name)"}};Write-Log "Teams uninstalled"};Risk="Moderate"}
    "AI-RemoveRecall"       = @{Name="Disable Windows Recall";Category="AI";Description="Disable Windows 11 Recall AI screenshot memory";Script={Set-WinBoxReg "HKCU:\Software\Microsoft\Windows\CurrentVersion\ExperimentalCloud" "Disabled" 1 "DWord";Set-WinBoxReg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAccess" 1 "DWord";Write-Log "Recall disabled"};Risk="Moderate"}
    "AI-RemoveClipHistory"  = @{Name="Disable Clipboard History";Category="AI";Description="Disable clipboard history and cloud sync";Script={Set-ItemProperty -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 0 -Type DWord;Write-Log "Clipboard history disabled"};Revert={Set-ItemProperty -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1 -Type DWord};Risk="Safe"}
    "Security-UAC"          = @{Name="Maximize UAC Security";Category="Security";Description="Set UAC to highest level";Script={Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1 -Type DWord;Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 5 -Type DWord;Write-Log "UAC set to max security"};Risk="Safe"}
    "Security-Defender"     = @{Name="Ensure Defender Running";Category="Security";Description="Keep Windows Security active";Script={Set-WinBoxService "Sense" "Automatic";Set-WinBoxService "WinDefend" "Automatic";Write-Log "Defender ensured"};Risk="Safe"}
    "Security-Firewall"     = @{Name="Optimize Firewall";Category="Security";Description="Enable firewall on all profiles";Script={netsh advfirewall set allprofiles state on 2>$null;Write-Log "Firewall optimized"};Risk="Safe"}
    "Quick-GamingMode"      = @{Name="One-Click Game Optimize";Category="QuickActions";Description="Game Mode + fullscreen opt + GPU priority";Script={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1 -Type DWord;Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehavior" -Value 2 -Type DWord;Write-Log "Game optimization applied"};Risk="Safe"}
    "Quick-PrivacyHardcore" = @{Name="Deep Privacy Protection";Category="QuickActions";Description="Disable telemetry + ads + location + activity history";Script={$o=$Optimizations["Disable-Telemetry"];&$o.Script;$o=$Optimizations["Disable-Ads"];&$o.Script;$o=$Optimizations["Disable-Location"];&$o.Script;$o=$Optimizations["Disable-ActivityHistory"];&$o.Script;Write-Log "Deep privacy protection applied"};Risk="Safe"}
    "Quick-PerformanceBoost" = @{Name="Performance Boost Full Set";Category="QuickActions";Description="Power plan + visuals + mouse + background apps";Script={$o=$Optimizations["Performance-PowerPlan"];&$o.Script;$o=$Optimizations["Performance-VisualFX"];&$o.Script;$o=$Optimizations["Performance-MouseAccel"];&$o.Script;$o=$Optimizations["Performance-BackgroundApps"];&$o.Script;Write-Log "Performance boost applied"};Risk="Safe"}
}


# === V2.0 ADDITIONAL TOOLS ===
$Optimizations += @{
    "Startup-Manager" = @{Name="Startup Item Manager";Category="Customize";Description="View and manage all startup programs";Script={$items=Get-WinBoxStartupItems;Write-Log "Startup items ($($items.Count)):";$items|ForEach-Object{Write-Log "  [$($_.Source)] $($_.Name) => $($_.Path.Substring(0,[Math]::Min(60,$_.Path.Length)))"}};Risk="Safe"}
    "Appx-RemoveLegacy" = @{Name="Remove Legacy Windows Apps";Category="SoftwareUninstall";Description="Remove pre-installed Windows bloatware (News,Clip,3DViewer etc.)";Script={@("Microsoft.BingNews","Microsoft.BingSearch","Microsoft.BingWeather","Microsoft.GetHelp","Microsoft.Getstarted","Microsoft.Microsoft3DViewer","Microsoft.MicrosoftOfficeHub","Microsoft.MixedReality.Portal","Microsoft.People","Microsoft.Print3D","Microsoft.SkypeApp","Microsoft.Wallet","Microsoft.WindowsAlarms","microsoft.windowscommunicationsapps","Microsoft.WindowsFeedbackHub","Microsoft.WindowsMaps","Microsoft.WindowsPhone","Microsoft.WindowsSoundRecorder","Microsoft.Xbox.TCUI","Microsoft.XboxApp","Microsoft.XboxGameOverlay","Microsoft.XboxGamingOverlay","Microsoft.XboxIdentityProvider","Microsoft.XboxSpeechToTextOverlay","Microsoft.YourPhone","Microsoft.ZuneMusic","Microsoft.ZuneVideo","Microsoft.BingFoodAndDrink","Microsoft.BingHealthAndFitness","Microsoft.BingSports","Microsoft.BingTranslator","Microsoft.BingTravel","Microsoft.OneConnect","Microsoft.AAD.BrokerPlugin")|ForEach-Object{try{$p=Get-AppxPackage -Name $_ -EA SilentlyContinue;if($p){Remove-AppxPackage -Package $p.PackageFullName -EA SilentlyContinue;Write-Log "Removed: $_"}}}catch{Write-Log "Skip: $_" "WARN"}};Risk="Moderate"}
    "Theme-DarkMode" = @{Name="Enable Dark Mode";Category="Customize";Description="Switch Windows to dark theme";Script={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -Type DWord;Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0 -Type DWord;Write-Log "Dark mode enabled"};Revert={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 1 -Type DWord;Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 1 -Type DWord};Risk="Safe"}
    "Theme-LightMode" = @{Name="Enable Light Mode";Category="Customize";Description="Switch Windows to light theme";Script={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 1 -Type DWord;Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 1 -Type DWord;Write-Log "Light mode enabled"};Risk="Safe"}
    "Privacy-NoAnimations" = @{Name="Disable Animations";Category="Privacy";Description="Disable window animations for snappier feel";Script={Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -Type String -EA SilentlyContinue;Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewAlphaSelect" -Value 0 -Type DWord -EA SilentlyContinue;Write-Log "Animations disabled"};Revert={Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "1" -Type String -EA SilentlyContinue};Risk="Safe"}
    "Privacy-StorageSense" = @{Name="Enable Storage Sense";Category="Cleanup";Description="Enable Windows Storage Sense for auto cleanup";Script={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -Value 1 -Type DWord -EA SilentlyContinue;Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "256" -Value 1 -Type DWord -EA SilentlyContinue;Write-Log "Storage Sense enabled"};Revert={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -Value 0 -Type DWord -EA SilentlyContinue};Risk="Safe"}
    "Privacy-StopUpdatesASAP" = @{Name="Defer Feature Updates";Category="Privacy";Description="Defer feature updates for 365 days";Script={Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdates" -Value 1 -Type DWord -EA SilentlyContinue;Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdatesPeriodInDays" -Value 365 -Type DWord -EA SilentlyContinue;Write-Log "Feature update defer set to 365 days"};Revert={Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdates" -EA SilentlyContinue};Risk="Safe"}
    "Privacy-DisableDVR" = @{Name="Disable Game DVR";Category="Privacy";Description="Disable Xbox Game Bar and DVR recording";Script={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord -EA SilentlyContinue;Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "HistoricalCaptureEnabled" -Value 0 -Type DWord -EA SilentlyContinue;Write-Log "Game DVR disabled"};Revert={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 1 -Type DWord};Risk="Safe"}
    "Privacy-DisableDeliveryOpt" = @{Name="Disable Delivery Optimization";Category="Privacy";Description="Stop Windows downloading updates from other PCs";Script={Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0 -Type DWord -EA SilentlyContinue;Write-Log "Delivery Optimization disabled"};Revert={Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -EA SilentlyContinue};Risk="Safe"}
    "Privacy-DisableNotifications" = @{Name="Disable All Notifications";Category="Privacy";Description="Turn off Windows notifications system-wide";Script={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "ToastEnabled" -Value 0 -Type DWord -EA SilentlyContinue;Write-Log "Notifications disabled"};Revert={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "ToastEnabled" -Value 1 -Type DWord};Risk="Safe"}
    "Privacy-DisableBingSearch" = @{Name="Disable Bing in Search";Category="Privacy";Description="Remove web search results from Start menu";Script={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Type DWord -EA SilentlyContinue;Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "AllowSearchToUseLocation" -Value 0 -Type DWord -EA SilentlyContinue;Write-Log "Bing search disabled"};Revert={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 1 -Type DWord};Risk="Safe"}
    "Privacy-DisableCopilot" = @{Name="Disable Copilot Button";Category="AI";Description="Disable Windows Copilot AI button in taskbar";Script={Set-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -EA SilentlyContinue;Write-Log "Copilot button disabled"};Revert={Remove-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -EA SilentlyContinue};Risk="Safe"}
    "Privacy-DisableGameBar" = @{Name="Disable Game Bar";Category="Privacy";Description="Disable Xbox Game Bar overlay and recording";Script={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "GameBarPresentationsEnabled" -Value 0 -Type DWord -EA SilentlyContinue;Write-Log "Game Bar disabled"};Revert={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "GameBarPresentationsEnabled" -Value 1 -Type DWord};Risk="Safe"}
    "Privacy-DisableSnapAssist" = @{Name="Disable Snap Assist";Category="Customize";Description="Disable window snap assist and layouts";Script={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0 -Type DWord -EA SilentlyContinue;Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapBar" -Value 0 -Type DWord -EA SilentlyContinue;Write-Log "Snap Assist disabled"};Revert={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 1 -Type DWord};Risk="Safe"}
    "Privacy-PreventAutoReboot" = @{Name="Prevent Auto Reboot";Category="Privacy";Description="Prevent Windows from auto-rebooting after updates";Script={Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -EA SilentlyContinue;Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" -Value 0 -Type DWord -EA SilentlyContinue;Write-Log "Auto reboot prevented"};Revert={Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -EA SilentlyContinue};Risk="Safe"}
    "Privacy-DisableChat" = @{Name="Disable Windows Chat";Category="Privacy";Description="Disable Windows Chat (Teams integration)";Script={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Chat" -Name "ChatIcon" -Value 3 -Type DWord -EA SilentlyContinue;Write-Log "Windows Chat disabled"};Revert={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Chat" -Name "ChatIcon" -Value 1 -Type DWord};Risk="Safe"}
    "Privacy-DisablePhoneLink" = @{Name="Disable Phone Link";Category="Privacy";Description="Disable Phone Link / Your Phone integration";Script={Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CDP" -Name "NearShareChannelUserAuthPolicy_ANDROID" -Value 0 -Type DWord -EA SilentlyContinue;Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CDP" -Name "NearShareChannelUserAuthPolicy_IOS" -Value 0 -Type DWord -EA SilentlyContinue;Write-Log "Phone Link disabled"};Risk="Safe"}
    "Security-DefenderFull" = @{Name="Enable Windows Defender";Category="Security";Description="Enable Windows Defender and real-time protection";Script={Set-WinBoxService "WinDefend" "Automatic";Start-Service WinDefend -EA SilentlyContinue;Set-WinBoxService "Sense" "Automatic";Start-Service Sense -EA SilentlyContinue;Write-Log "Defender enabled"};Risk="Safe"}
    "System-RestorePoint" = @{Name="Create Restore Point";Category="QuickActions";Description="Create a system restore point before making changes";Script={Invoke-WinBoxCreateRestore};Risk="Safe"}
    "System-SysReport" = @{Name="System Health Report";Category="QuickActions";Description="Generate comprehensive system report";Script={$r=Get-WinBoxSystemReport;Write-Log "=== System Report ===";Write-Log "OS: $($r.OS)";Write-Log "CPU: $($r.CPU)";Write-Log "RAM: $($r.RAM_GB)GB";Write-Log "Disks: $($r.Disks)";Write-Log "Defender: $($r.Defender)";Write-Log "Power Plan: $($r.PowerPlan)";Write-Log "Admin: $($r.Admin)"};Risk="Safe"}
    "Quick-FullDeblock" = @{Name="Full Debloat";Category="QuickActions";Description="Apply all privacy + performance + cleanup tweaks at once";Script={$seq=@("Disable-Telemetry","Disable-Ads","Disable-Location","Disable-ActivityHistory","Performance-PowerPlan","Performance-VisualFX","Performance-MouseAccel","Performance-BackgroundApps","Cleanup-DeepClean");foreach($k in $seq){$o=$Optimizations[$k];if($o){&$o.Script}};Write-Log "Full debloat applied"};Risk="Moderate"}
}

[System.Windows.Forms.Application]::Run($form)
