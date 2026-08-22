<#
.SYNOPSIS
    WinBox 快速命令行工具
    提供无需 GUI 的批量优化工具执行能力

.EXAMPLE
    .\Quick-Execute.ps1 -Category Performance
    .\Quick-Execute.ps1 -Key "Privacy-Telemetry,Copilot"
    .\Quick-Execute.ps1 -All
#>
[CmdletBinding()]
param(
    [ValidateSet('Privacy', 'Performance', 'Services', 'ScheduleTasks', 'Customize', 'AI', 'Cleanup', 'Security', 'QuickActions', 'All')]
    [string]$Category = 'All',

    [string[]]$Key,

    [switch]$Revert,

    [switch]$DryRun,

    [switch]$ShowOnly
)

$WinBoxRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not ($WinBoxRoot -match 'WinBox$')) {
    $WinBoxRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'WinBox'
}
& "$WinBoxRoot\WinBox.ps1" -Category $Category -Key $Key -Revert:$Revert -DryRun:$DryRun -ShowOnly:$ShowOnly
exit $LASTEXITCODE
