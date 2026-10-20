# 01. 环境要求与验证

占位符：`<TML_DIR>` = tModLoader 安装目录，`<WORKSPACE>` = 工作区根目录，`<ModName>` = 模组工程名，`%USERPROFILE%` = 当前用户目录（PowerShell 写 `$env:USERPROFILE`）。

## 1.1 需要的东西

| 组件 | 要求 |
|---|---|
| Terraria | 正版（Steam / GOG） |
| tModLoader | 1.4.4 stable（免费 Steam app 1281930，或 GitHub release） |
| .NET SDK | 官方要求 8.0 起；含 SilkyUI 等使用新语法依赖的工程需 **9.0.x**（见 §1.2） |
| 编辑器 / git | VS Code、VS2022+、Rider（可选）；git 可选（版本管理、拉 ExampleMod） |

## 1.2 PATH 陷阱（重要）

机器上可能并存多个 dotnet 安装点：`C:\Program Files\dotnet`（.NET 默认的 64 位安装点，通常带 SDK，**构建 mod 用它**）、`%USERPROFILE%\.dotnet`（用户级，可能只有旧 SDK）、`C:\Program Files (x86)\dotnet`（旧 32 位副本，不要用于构建）。

**多个 SDK 安装点并存时，务必确认 `dotnet --list-sdks` 中有 9.x。**

版本不足的典型症状：依赖 SilkyUI 的工程构建失败。`SilkyUIAnalyzer` 使用 C# 14 `extension(...)` 扩展成员语法，旧版 Roslyn 把它解析成"名为 `extension` 的方法"，块内成员被当作本地函数，报 `error CS0106: 修饰符"public"对该项无效`（报在 `ITypeSymbolExtensions.cs`，不在你的模组代码里）。换 9.x SDK 即通过，不要改业务代码。

**推荐做法**：命令用带 SDK 的 dotnet，或把它的安装目录放到系统环境变量 Path 最前并重开终端；同时设 `DOTNET_ROOT` 指向该目录。

## 1.3 验证命令

```powershell
dotnet --list-sdks                     # 必须能看到 9.0.x；只有 8.0.x 时依赖 SilkyUI 的工程会编译失败
Test-Path "<TML_DIR>\tModLoader.dll"   # tML 安装存在
Get-Content "<TML_DIR>\tMLMod.targets" # 关键构建入口文件
Get-ChildItem "$env:USERPROFILE\Documents\My Games\Terraria\tModLoader"  # tML 用户目录（首次运行游戏后生成）
```

## 1.4 关键路径速查

| 用途 | 路径 |
|---|---|
| tML 安装（tMLMod.targets、Libraries 引用） | `<TML_DIR>` |
| tML 用户数据（Mods、ModSources、Logs） | `%USERPROFILE%\Documents\My Games\Terraria\tModLoader` |
| 打包产物 `.tmod` | `<tML 用户数据>\Mods\<ModName>.tmod` |
| 游戏日志 | `<tML 用户数据>\Logs\client.log`（游戏内 Mods 菜单或报错时看这里） |
| 工作区源码 / ModSources 链接 | `<WORKSPACE>\<ModName>`；junction 在 `<tML 用户数据>\ModSources\<ModName>` |
| tML 官方 API 文档 | https://docs.tmodloader.net/docs/stable/ |

## 1.5 tML 构建入口说明（tMLMod.targets）

- `TargetFramework = net8.0`、`LangVersion = 12.0`、`PlatformTarget = AnyCPU`。
- 引用：`tModLoader.dll` + `Libraries/**/*.dll`（全部官方引用集）；分析器 `Libraries/tModCodeAssist/1.0.0/tModCodeAssist.dll`（IDE 提示用）。
- `BuildMod` 目标：`dotnet tModLoader.dll -build <ProjectDir> -eac <TargetPath> ...` → 编译后打包 `.tmod` 到 tML `Mods\` 目录。
- 预定义宏：`TML_2026_06`（随版本变化，用于条件编译）。

## 1.6 首次运行 tML

1. 从 Steam 库启动 **tModLoader**（不是 Terraria）；首次会创建 `%USERPROFILE%\Documents\My Games\Terraria\tModLoader\`（Mods / ModSources / Logs）。
2. 若报缺 .NET 运行时，按 `LaunchUtils\InstallDotNet.sh` 的逻辑装运行时（或装 8.0.20 运行时）。

## 1.7 网络/下载注意事项（证书拦截）

- 加速工具或代理可能把 github / huggingface / docker 域名指向 127.0.0.1 并做 TLS 拦截（hosts 条目）。
- git（OpenSSL 后端）访问这些域名会报 `UNABLE_TO_VERIFY_LEAF_SIGNATURE`：指定合并信任包 `$env:GIT_SSL_CAINFO="<CA_BUNDLE>"`（`<CA_BUNDLE>` = 合并后的 CA 证书包路径），或用系统证书 / 浏览器下载。不要关闭证书校验。
