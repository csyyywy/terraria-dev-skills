# 03. 构建 / 测试 / 调试 / 发布流水线

占位符：`<ModName>` = 模组工程名，`<WORKSPACE>` = 工作区根目录，`<TML_DIR>` = tModLoader 安装目录，`<tML 用户数据>` = `%USERPROFILE%\Documents\My Games\Terraria\tModLoader`。

## 3.1 构建（推荐：命令行）

```powershell
# 全量构建：C# 编译 + tML 打包 .tmod
dotnet build "<WORKSPACE>\<ModName>\<ModName>.csproj" -c Debug

# 只编译不打包（快速检查语法）。注意：tMLMod.targets 里 TargetFramework 由 BuildMod 门控，
# 只给 -p:BuildMod=false 会导致 TargetFramework 为空（NETSDK1013），必须同时显式给 TargetFramework
dotnet build "<WORKSPACE>\<ModName>\<ModName>.csproj" -c Debug -p:BuildMod=false -p:TargetFramework=net8.0

# Release 构建
dotnet build "<WORKSPACE>\<ModName>\<ModName>.csproj" -c Release
```

**csproj 用属性导入 targets 时（模板写法）**：`templates/MyMod.csproj` 写的是 `<Import Project="$(TMLDir)\tMLMod.targets" />`，构建命令需补 `-p:TMLDir="<TML_DIR>"`，否则导入路径为空、报 `MSB4019`。也可以在 csproj 里直接写死绝对路径，代价是换机器要改。工程放在 `ModSources` 下时可用相对导入 `..\tModLoader.targets`，无需传参。

**发布构建（Publish / ModSources 路径）不应用 csproj 的 `<ImplicitUsings>enable</ImplicitUsings>`**：tML 发布编译不读该设置，`List<>` / `Math` / `Enumerable` 等未显式 using 的类型报 CS0246（本地 build 能过、发布才炸）。对策：显式写 `using System;`、`using System.Collections.Generic;` 等，或加一个 `GlobalUsings.cs`（为 `System`、`System.Collections.Generic`、`System.IO`、`System.Linq`、`System.Threading`、`System.Threading.Tasks` 各写一条 `global using`）。发布前先用上面"只编译"命令追加 `-p:ImplicitUsings=disable` 本地模拟一次，0 错 0 警再发布。

**打包 / 进程区分（TML003 文件锁）**：

- tML 客户端进程是 `dotnet.exe`，命令行含 `-terrariasteamclient` → **玩家在玩，不要杀**。
- 裸 `dotnet tModLoader.dll`（命令行无 `-terrariasteamclient`）→ 残留 headless server，可杀。
- 客户端开着时打包一般也能成功（tML 写临时文件再替换）；若报 TML003 / 文件锁，退出客户端或残留 server 再打包。

**游戏开着时，ModSources 的源文件也可能被锁**：模组从 `ModSources/<ModName>` 加载且处于启用状态时，tML 会持有部分 `.cs`，表现为**只有个别源文件**拒绝写入（`PermissionError 13`，`rm` 也失败），而同目录其它文件、目录本身都正常 —— 容易误判成"编辑器占用"或沙箱故障。此时 `dotnet build` 报 **TML003**（不是 CS 错误），报错原文：

`tModLoader : Mod Build error TML003: Please close tModLoader or disable the mod in-game to build mods directly.`

**判据**：先 grep `error CS`。为 0 说明 C# 编译已通过，只是打包被游戏挡住 —— 退出游戏或在游戏内禁用该模组即可，不要改代码。

**产物**：

- 编译产物：`<ModName>\bin\Debug\net8.0\<ModName>.dll`
- 打包产物：`<tML 用户数据>\Mods\<ModName>.tmod`（tML 自动写到这里）
- 启用列表：`<tML 用户数据>\Mods\enabled.json`（构建后 tML 自动加入 `<ModName>`）

**等价游戏内操作**：Developer Mode 下 Mods 菜单 → "Build & Reload"（或 `F10` 重载构建）。两者都用本地 .NET SDK。

## 3.2 游戏内测试（核心循环）

1. 启动 tML（见 01 §1.6）→ 主菜单 **Mods** → **Mod Sources** 标签下看到 `<ModName>`（经 junction 同步）。
2. 启用它；已启用则点 **Reload**（`Reload Mods` 按钮或 F10）。
3. 进世界验证：最稳的是写一个 `ModCommand`（参照 `examples/ExampleCommand.cs` 与 ExampleMod 的 ExampleItemCommand），或直接用合成 / 掉落。
4. 改代码 → 重复 3.1 构建 → 游戏内 Reload。聊天框可用 `/<ModName>`（若已实现该类命令）。

## 3.3 无头测试：专用服务器

```powershell
& "<TML_DIR>\start-tModLoaderServer.bat"   # 方式一：游戏目录脚本

# 方式二：直接跑 tML server（加载 Mods 目录里已启用的模组）
# 注意：workdir 必须是 tModLoader 安装目录，否则 deps.json 找不到 Libraries\ReLogic，报 FileNotFoundException: ReLogic
Set-Location "<TML_DIR>"
dotnet "tModLoader.dll" -server
```

日志：`<tML 用户数据>\Logs\server.log`。适合验证"加载不炸、世界正常生成"。

## 3.4 调试

日志都在 `<tML 用户数据>\Logs\` 下：客户端 `client.log`、服务器 `server.log`、崩溃 `Launch.log`。

**断点调试**：

- VS Code：安装 C# 扩展；`Properties\launchSettings.json` 指向 `start-tModLoader.bat`，F5 启动 tML 并附加调试器。
- 也可先启动 tML，再用 `dotnet-attach` / VS"附加到进程"（选 tModLoader 进程）。
- tML 会加载 `bin\Debug\net8.0\<ModName>.dll` 的 PDB，断点可用（构建日志出现 "Edit and continue path" 即 Edit and Continue 已开启）。

## 3.5 发布（Steam 创意工坊）

1. 构建 **Release**：`dotnet build "<WORKSPACE>\<ModName>\<ModName>.csproj" -c Release`。
2. 游戏内 **Mods → Publish**（对 `<ModName>` 点发布）；工坊信息取自 `description.txt`（简介）、`icon.png`（图标）、`build.txt` 的 `version`（版本），账号还需满足发布门槛（见 tModLoader 官方文档）。
3. 更新：重新构建后再发布（`version` +1，工坊会提示更新）。
4. **版本号三处同步**：`build.txt` 的 `version`、`Mod.Call` 里 `GetVersion` 的返回值（主类中 `if (name == "GetVersion") return "x.y.z"`）、README / `description.txt` 的当前版本说明。改一处要全改，否则跨模组调用方与玩家看到的版本不一致。

**本地分发**：拷贝 `<tML 用户数据>\Mods\<ModName>.tmod` 给别人，对方放进自己的 `Mods\` 目录并启用。

## 3.6 常用命令行参数（tModLoader.exe / tModLoader.dll）

| 参数 | 作用 |
|---|---|
| `-build <ProjectDir>` | 构建模组（打包 .tmod） |
| `-server` | 以专用服务器模式运行 |
| `-eac <path>` | 使用预编译的程序集（配合构建） |
| `-debug` | 调试模式（更多日志） |
| `-tmlsavedirectory <path>` | 指定 tML 用户数据目录（原版另有 `-savedirectory`） |

## 3.7 常见流程速查

```text
改代码 → dotnet build（修到 0 错误）→ 游戏内 Reload → 测试 → 改 … → 发布前 Release build → Publish
```
