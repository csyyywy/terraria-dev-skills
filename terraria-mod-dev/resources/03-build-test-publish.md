# 03. 构建 / 测试 / 调试 / 发布流水线

## 3.1 构建（推荐：命令行）

```powershell
# 全量构建：C# 编译 + tML 打包 .tmod（实测 ~5s，0 警告 0 错误）
& "%USERPROFILE%\.dotnet\dotnet.exe" build "<WORKSPACE>\MyMod\MyMod.csproj" -c Debug

# 只编译不打包（快速检查语法）。注意：tMLMod.targets 里 TargetFramework 由 BuildMod 门控，
# 只给 -p:BuildMod=false 会导致 TargetFramework 为空（NETSDK1013），必须同时显式给 TargetFramework
& "%USERPROFILE%\.dotnet\dotnet.exe" build "<WORKSPACE>\MyMod\MyMod.csproj" -c Debug -p:BuildMod=false -p:TargetFramework=net8.0

# Release 构建
& "%USERPROFILE%\.dotnet\dotnet.exe" build "<WORKSPACE>\MyMod\MyMod.csproj" -c Release
```

⚠️ **发布构建（Publish / ModSources 路径）不应用 csproj 的 `<ImplicitUsings>enable</ImplicitUsings>`**：tML 发布编译不读该设置，`List<>`/`Math`/`Enumerable` 等未显式 using 的类型报 CS0246（本地 build 能过、发布才炸）。两个办法：
- 显式 `using System; using System.Collections.Generic; ...`，或
- 加 `GlobalUsings.cs`：`global using System; System.Collections.Generic; System.IO; System.Linq; System.Threading; System.Threading.Tasks;`
- **本地模拟发布构建**：`build -c Debug -p:BuildMod=false -p:TargetFramework=net8.0 -p:ImplicitUsings=disable`，0 错 0 警才放心发布。

**打包/进程区分（TML003 文件锁）**：
- tML 客户端进程 = `dotnet.exe`，命令行含 `-terrariasteamclient` → **玩家在玩，绝不杀**。
- 裸 `dotnet tModLoader.dll`（命令行无 terrariasteamclient）→ 残留 headless server，可杀。
- 客户端开着时打包一般也能成功（tML 写临时文件再替换）；若报 TML003/文件锁，退出客户端/残留 server 再打包。

产物：

| 路径 | 内容 |
|---|---|
| `MyMod\bin\Debug\net8.0\MyMod.dll` | 编译出的程序集 |
| `...\tModLoader\Mods\MyMod.tmod` | 打包好的模组（tML 自动写到这里） |
| `...\tModLoader\Mods\enabled.json` | 已启用模组列表（构建后 tML 自动加入 MyMod） |

**等价游戏内操作**：Developer Mode 下 Mods 菜单 → "Build & Reload"（或 `F10` 重载构建）。两者都用本地 .NET SDK。

## 3.2 游戏内测试（核心循环）

1. 启动 tML（Steam 库 → tModLoader）。
2. 主菜单 → **Mods** → 在 **Mod Sources** 标签下看到 `MyMod`（经 junction 同步）。
3. 启用它（点一次），若已启用则点 **Reload**（`Reload Mods` 按钮或 F10）。
4. 进世界后，给测试物品最稳的方式是写一个 `ModCommand`（参照 `examples/ExampleCommand.cs` 与 ExampleMod 的 ExampleItemCommand），或直接用合成/掉落验证。
5. 改动代码 → 重复 3.1 构建 → 游戏内 Reload。

> 实用指令（在聊天框输入）：`/MyMod`（若实现）或使用 tML 自带的 `-debug` 启动参数；直接给测试物品最稳的方式是写一个 `ModCommand`（见 examples/ExampleCommand）。

## 3.3 无头测试：专用服务器

```powershell
# 方式一：游戏目录脚本
& "<STEAM_LIB>\steamapps\common\tModLoader\start-tModLoaderServer.bat"

# 方式二：tML server 直接跑（会加载 Mods 目录里已启用的模组）
# ⚠️ 必须在 tModLoader 安装目录下运行（workdir），否则 deps.json 找不到 Libraries\ReLogic → FileNotFoundException: ReLogic
Set-Location "<STEAM_LIB>\steamapps\common\tModLoader"
& "%USERPROFILE%\.dotnet\dotnet.exe" "tModLoader.dll" -server
```

服务器日志：`...\tModLoader\Logs\server.log`。适合验证"加载不炸、世界正常生成"。

## 3.4 调试

**日志**：

| 日志 | 路径 |
|---|---|
| 客户端 | `...\tModLoader\Logs\client.log` |
| 服务器 | `...\tModLoader\Logs\server.log` |
| 崩溃 | `...\tModLoader\Logs\Launch.log` |

**断点调试**：

- VS Code：安装 C# 扩展；`Properties\launchSettings.json` 指向 `start-tModLoader.bat`，F5 启动 tML 并附加调试器。
- 也可先启动 tML，再用 `dotnet-attach`/VS "附加到进程"（选 tModLoader 进程）。
- tML 会加载 `bin\Debug\net8.0\MyMod.dll` 的 PDB，断点可用（Edit and Continue 已开启：构建日志有 "Edit and continue path"）。

## 3.5 发布（Steam 创意工坊）

1. 构建 **Release**：`& "%USERPROFILE%\.dotnet\dotnet.exe" build ... -c Release`。
2. 游戏内 → **Mods → Publish**（对 MyMod 点发布按钮）。
3. 填工坊信息：`description.txt` 自动作为简介，`icon.png` 作图标，`build.txt` 的 version 作版本。
4. 满足发布门槛（tML 要求账号有相应条件，详见 tModLoader.app 文档）。
5. 更新：再次构建后重新发布（版本号 +1，工坊会提示更新）。
6. **版本号三处同步**：`build.txt` 的 `version`、`Mod.Call GetVersion` 的返回值（`Voidfall.cs` 里 `if (name == "GetVersion") return "x.y.z"`）、README/description 里的「当前版本」说明——改版本号一起改，否则跨模组调用方/玩家看到的版本不一致。

**本地分发**：直接拷贝 `Mods\MyMod.tmod` 给别人，对方放进自己的 `Mods\` 目录并启用。

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
改代码 → dotnet build（有错修到 0 错误）→ 游戏内 Reload → 测试 → 改 … → 发布前 Release build → Publish
```