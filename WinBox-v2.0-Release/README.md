# WinBox - Windows 系统工具箱

> 集合了 GitHub 上 14 个顶级 Windows 优化工具的核心功能，一键直达。

![Version](https://img.shields.io/badge/version-2.0.0-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-green)
![Windows](https://img.shields.io/badge/Windows-10%20%2F%2011-0078d6)

---

## 📦 来源项目

本工具箱整合了以下 GitHub 项目的核心思路和脚本：

| # | 项目 | ⭐ Stars | 类型 | 贡献的功能 |
|---|------|---------|------|-----------|
| 1 | [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat) | 55,859 | PowerShell | 应用移除逻辑、注册表调整 |
| 2 | [Atlas-OS/Atlas](https://github.com/Atlas-OS/Atlas) | 21,341 | Playbook | 服务优化、启动项管理 |
| 3 | [BCUninstaller/Bulk-Crap-Uninstaller](https://github.com/BCUninstaller/Bulk-Crap-Uninstaller) | 20,894 | C# | 应用卸载引擎 |
| 4 | [memstechtips/Winhance](https://github.com/memstechtips/Winhance) | 12,636 | C# | autounattend 生成逻辑 |
| 5 | [zoicware/RemoveWindowsAI](https://github.com/zoicware/RemoveWindowsAI) | 12,842 | PowerShell | Copilot/Recall 移除 |
| 6 | [farag2/Sophia-Script-for-Windows](https://github.com/farag2/Sophia-Script-for-Windows) | 9,666 | PowerShell | 150+ 函数体系 |
| 7 | [itsfatduck/optimizerDuck](https://github.com/itsfatduck/optimizerDuck) | 8,522 | C# WPF | 优化分类体系设计 |
| 8 | [RayTuneX](https://github.com/rayenghanmi/RyTuneX) | 5,367 | C# WinUI | UI/UX 参考 |
| 9 | [LeDragoX/Win-Debloat-Tools](https://github.com/LeDragoX/Win-Debloat-Tools) | 6,373 | PowerShell | 深度清理脚本 |
| 10 | [semazurek/ET-Optimizer](https://github.com/semazurek/ET-Optimizer) | 611 | C# | 性能调优策略 |
| 11 | [simeononsecurity/Windows-Optimize-Harden-Debloat](https://github.com/simeononsecurity/Windows-Optimize-Harden-Debloat) | 1,386 | PowerShell | 安全加固策略 |
| 12 | [W4RH4WK/Debloat-Windows-10](https://github.com/W4RH4WK/Debloat-Windows-10) | 6,144 | PowerShell | 早期 debloat 思路 |
| 13 | [Sycnex/Windows10Debloater](https://github.com/Sycnex/Windows10Debloater) | 18,839 | PowerShell | AppX 卸载逻辑 |
| 14 | [BoringBoredom/PC-Optimization-Hub](https://github.com/BoringBoredom/PC-Optimization-Hub) | 1,234 | 资源集合 | 优化参考资料 |

---

### 方式零：双击 EXE（最简单）

```
双击 WinBox.exe
```
> PyInstaller 打包的单文件程序，无需安装 Python 或 PowerShell 额外依赖，静默启动无控制台窗口。

---

## 🚀 快速开始

### 方式一：双击启动（推荐）

```
双击 WinBox\启动工具箱.bat
```

### 方式二：PowerShell 手动启动

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
cd E:\编程作品\作品\DeepSeek\winbox\WinBox
.\WinBox.ps1
```

### 前置要求

- Windows 10 (1809+) / Windows 11
- PowerShell 5.1 或 PowerShell 7
- **必须以管理员身份运行**（否则部分功能受限）

---

## 🗂️ 工具分类

### 🔒 隐私保护
| 工具 | 说明 |
|------|------|
| 禁用 Windows 遥测 | 关闭诊断数据收集、活动历史记录 |
| 禁用 Copilot | 关闭 Windows Copilot AI 助手 |
| 禁用广告与建议 | 关闭开始菜单、设置中的推广内容 |
| 禁用位置服务 | 关闭 GPS/定位传感器 |
| 禁用活动历史记录 | 停止 Windows 跟踪您的使用习惯 |
| 禁用个性化体验 | 阻止 Microsoft 基于使用数据推送建议 |
| 禁用锁屏相机 | 防止锁屏时调用摄像头 |
| 禁用零售演示模式 | 关闭 OEM 预装的零售体验 |

### ⚡ 性能优化
| 工具 | 说明 |
|------|------|
| 启用游戏模式 | 优化游戏时 CPU/GPU 资源分配 |
| 关闭鼠标加速 | 禁用增强指针精确度 |
| 禁用休眠 & 快速启动 | 释放磁盘空间，确保完整关机 |
| 高性能电源计划 | 保持 CPU 最高频率运行 |
| 禁用后台应用 | 阻止应用在后台消耗资源 |
| 优化视觉效果 | 关闭动画和透明效果提升响应速度 |
| 优化网络延迟 | 调整 TCP/IP 参数降低延迟 |
| DNS-over-HTTPS | 使用 Cloudflare DNS 提升解析速度和隐私 |

### ⚙️ 服务管理
| 工具 | 说明 |
|------|------|
| 禁用 Xbox 相关服务 | 关闭游戏栏、录制等服务 |
| 禁用遥测服务 | 关闭 Diagnostics Tracking 等 |
| 禁用 Modern Standby 睡眠学习 | 减少待机时后台活动 |

### 📅 计划任务
| 工具 | 说明 |
|------|------|
| 禁用遥测计划任务 | 关闭 Windows 遥测后台任务 |

### 🎨 外观定制
| 工具 | 说明 |
|------|------|
| 恢复经典右键菜单 | Win11 中返回传统右键菜单 |
| 任务栏图标居中/左对齐 | 切换 Win10/Win11 风格 |
| 禁用任务栏小组件 | 隐藏天气/新闻小组件 |
| 显示文件扩展名 | 始终显示文件后缀 |
| 禁用透明效果 | 关闭毛玻璃效果提升性能 |
| 任务栏添加"结束任务" | 右键任务栏可强制关闭应用 |

### 🤖 AI 功能管理 (新增)\n| 工具 | 说明 |\n|------|------|\n| 禁用 Windows Recall | 完全关闭截图回忆功能 |\n| 禁用剪贴板历史 | 关闭剪贴板记录和云端同步 |\n\n### 💾 C 盘深度清理 (新增)\n| 工具 | 说明 |\n|------|------|\n| 一键深度清理 | 清理临时文件、更新缓存、日志、缩略图、DNS、minidump |\n| 分析 C 盘空间 | 扫描 C 盘主文件夹并生成空间报告 |\n| 清理临时文件 | 清理用户和系统临时文件 |\n| 清理 Windows 更新缓存 | 停止 Windows Update 并清空下载缓存 |\n| 刷新 DNS 缓存 | 清除 DNS 客户端缓存 |\n| 清理内存转储文件 | 删除 MEMORY.DMP 和 Minidump 文件 |\n| 清理 Windows 升级残留 | 移除 Windows 升级遗留文件夹 |\n\n### 📦 软件卸载管理 (新增)\n| 工具 | 说明 |\n|------|------|\n| 扫描已安装软件 | 从注册表和 WinGet 列出所有程序 |\n| 卸载 Microsoft Edge | 移除 Edge 浏览器 |\n| 卸载 OneDrive | 彻底移除 OneDrive |\n| 卸载 Microsoft Teams | 移除 Teams 聊天应用 |\n\n### 🛡️ 安全加固 (增强)\n| 工具 | 说明 |\n|------|------|\n| 最大化 UAC 安全 | 设置 UAC 为最高级别 |\n| 确保 Defender 运行 | 保持 Windows 安全中心激活 |\n| 优化防火墙规则 | 启用防火墙并阻止匿名枚举 |\n\n### 🚀 一键操作 (增强)\n| 工具 | 说明 |\n|------|------|\n| 一键游戏优化 | Game Mode + 全屏优化 + GPU 调度 |\n| 深度隐私保护 | 隐私类所有选项一键应用 |\n| 性能 Boost 全套 | 性能类所有选项一键应用 |
| 工具 | 说明 |
|------|------|
| 禁用 Windows Recall | 完全关闭截图回忆功能 |
| 禁用剪贴板历史 | 关闭剪贴板记录和云端同步 |

### 🧹 系统清理
| 工具 | 说明 |
|------|------|
| 深度系统清理 | 清理临时文件、缓存、日志 |
| 清理 WinSxS | 移除旧版组件节省磁盘空间 |
| 清理浏览器缓存 | Edge/Chrome/Firefox 缓存 |

### 🛡️ 安全加固
| 工具 | 说明 |
|------|------|
| 调整 UAC 级别 | 提高用户账户控制安全级别 |
| 保持 Defender 开启 | 确保 Windows 安全中心正常 |
| 优化防火墙规则 | 启用防火墙并阻止匿名枚举 |

### 🚀 一键操作
| 工具 | 说明 |
|------|------|
| 一键游戏优化 | 游戏模式 + 全屏优化 + GPU 调度 |
| 深度隐私保护 | 隐私类所有选项一键应用 |
| 性能 Boost 全套 | 性能类所有选项一键应用 |

---

## 📁 项目结构

```
WinBox/
├── WinBox.ps1              # 主程序（PowerShell + WinForms GUI）
├── 启动工具箱.bat           # 启动脚本
├── README.md               # 本文档
├── Config/                 # 配置文件
│   ├── Atlas-tweaks.yml    # Atlas 配置参考
│   ├── ET-Features.txt     # ET-Optimizer 功能列表
│   └── autounattend.xml    # Winhance 无人值守安装模板
├── Scripts/                # 各仓库脚本集合
│   ├── AI/                 # AI 功能移除
│   ├── Bloatware/          # 垃圾软件处理
│   ├── Cleanup/            # 清理脚本
│   ├── Customize/          # 外观定制
│   ├── Performance/        # 性能优化（含 Atlas 脚本）
│   ├── Privacy/            # 隐私相关（含 Win11Debloat .reg 文件）
│   ├── ScheduleTasks/      # 计划任务
│   ├── Services/           # 服务管理
│   ├── Sophia-Private/     # Sophia 脚本函数
│   └── Uninstaller/        # 卸载工具
└── Assets/                 # 图标资源
```

---

## ⚠️ 注意事项

1. **必须管理员权限**：部分优化需要修改注册表和系统设置，请以管理员身份运行
2. **创建还原点**：建议在首次使用前创建系统还原点
3. **风险等级说明**：
   - 🟢 **Safe（安全）**：可逆，不影响系统稳定性
   - 🟡 **Moderate（中等）**：可能影响某些功能，需谨慎
   - 🔴 **Risky（高风险）**：可能破坏系统功能，不建议普通用户使用
4. **还原功能**：每个已实现的工具有对应的还原按钮，可以撤销修改
5. **日志记录**：所有操作记录在 `%TEMP%\WinBox-Logs\` 目录下

---

## 🔧 如何添加新工具

编辑 `WinBox.ps1`，在 `$Optimizations` 字典中添加新的条目：

```powershell
'Your-Tool-Key' = @{
    Name        = '工具显示名称'
    Category    = '分类名'
    Description = '工具描述'
    Script      = {
        # 你的优化代码
        Set-WinBoxReg 'HKCU:\...' 'Name' 'Value' 'DWord'
    }
    Revert      = {
        # 还原代码（可选）
    }
    Risk        = 'Safe'  # Safe / Moderate / Risky
}
```

---

## 📝 版本历史

### v2.0.0 (2026-08-22)
- 初始版本
- 整合 14 个 GitHub 项目精华
- 57+ 优化工具
- 分类导航 + 执行日志

---

## 📄 License

本项目基于所整合的各项目许可证（MIT / GPLv3 / PolyForm Shield）组合使用，仅供学习和个人使用。
