# 01. 环境要求与验证（本机实测）

## 1.1 需要的东西

| 组件 | 要求 | 本机状态（2026-08 实测） |
|---|---|---|
| Terraria | 正版（Steam/GOG） | ✅ `<STEAM_LIB>\steamapps\common\Terraria` |
| tModLoader | 1.4.4 stable（免费 Steam app 1281930，或 GitHub release） | ✅ `<STEAM_LIB>\steamapps\common\tModLoader`（2026.06 月更版） |
| .NET SDK | **8.0.x**（构建 mod 必需） | ✅ 8.0.423 于 `%USERPROFILE%\.dotnet` |
| 编辑器 | VS Code / VS2022+ / Rider（可选） | ✅ VS Code 1.134 + VS 2026 Build Tools 18.8 |
| git | 可选（版本管理/拉 ExampleMod） | ✅ 2.55.0 |

## 1.2 ⚠️ PATH 陷阱（重要）

本机同时存在多个 dotnet：

- `C:\Program Files\dotnet\dotnet.exe` → **纯运行时**（无 SDK），且在 PATH 首位
- `%USERPROFILE%\.dotnet\dotnet.exe` → 带 **SDK 8.0.423**（正确选择）
- `C:\Program Files (x86)\dotnet\dotnet.exe` → 带 **SDK 8.0.423**（备选）

直接敲 `dotnet build` 可能命中无 SDK 的副本，报 `No .NET SDKs were found` 或游戏内 ".NET SDK not recognised"。

**修复方案（任选）**：

1. 所有命令用完整路径：`%USERPROFILE%\.dotnet\dotnet.exe build ...`（本技能统一采用）。
2. 打开"系统环境变量 → Path"，把 `%USERPROFILE%\.dotnet` 移到 `C:\Program Files\dotnet` 之前，并重开终端。
3. 设 `DOTNET_ROOT=%USERPROFILE%\.dotnet`。

## 1.3 验证命令

```powershell
# .NET SDK 必须在列（应看到 8.0.x）
& "%USERPROFILE%\.dotnet\dotnet.exe" --list-sdks

# tML 安装存在
Test-Path "<STEAM_LIB>\steamapps\common\tModLoader\tModLoader.dll"

# tML 用户目录（首次运行游戏后生成）
Get-ChildItem "$env:USERPROFILE\Documents\My Games\Terraria\tModLoader"

# 关键构建入口文件
Get-Content "<STEAM_LIB>\steamapps\common\tModLoader\tMLMod.targets"
```

## 1.4 关键路径速查

| 用途 | 路径 |
|---|---|
| tML 安装（含 tMLMod.targets、Libraries 引用） | `<STEAM_LIB>\steamapps\common\tModLoader` |
| tML 用户数据（Mods、ModSources、Logs） | `%USERPROFILE%\Documents\My Games\Terraria\tModLoader` |
| 打包产物 `.tmod` | `...\tModLoader\Mods\<ModName>.tmod` |
| 游戏日志 | `...\tModLoader\Logs\client.log`（游戏内 Mods 菜单或报错时看这里） |
| 工作区源码 | `<WORKSPACE>\<ModName>` |
| ModSources 链接 | `%USERPROFILE%\Documents\My Games\Terraria\tModLoader\ModSources\<ModName>`（junction） |
| tML 官方 API 文档 | https://docs.tmodloader.net/docs/stable/ |

## 1.5 tML 构建入口说明（tMLMod.targets）

`tMLMod.targets`（tML 安装目录下）是官方构建规格，要点：

- `TargetFramework = net8.0`、`LangVersion = 12.0`、`PlatformTarget = AnyCPU`。
- 引用：`tModLoader.dll` + `Libraries/**/*.dll`（全部官方引用集）。
- 分析器：`Libraries/tModCodeAssist/1.0.0/tModCodeAssist.dll`（IDE 提示用）。
- `BuildMod` 目标：`dotnet tModLoader.dll -build <ProjectDir> -eac <TargetPath> ...` → 编译后打包 `.tmod` 到 tML `Mods\` 目录。
- 预定义宏：`TML_2026_06`（随版本变化，用于条件编译）。

## 1.6 首次运行 tML

1. 从 Steam 库启动 **tModLoader**（不是 Terraria）。
2. 首次会创建 `Documents\My Games\Terraria\tModLoader\`（Mods / ModSources / Logs）。
3. 若报缺 .NET 运行时，用 `LaunchUtils\InstallDotNet.sh` 逻辑（或已装 8.0.20 运行时即可）。


