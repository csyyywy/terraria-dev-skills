> **这份分册只讲「构建校验 + 最小服务端自检」。**
> 需要真帧截图、UI 操作、受伤特效、双端对比，一律用技能 **terraria-headless-test**
> （热会话单条 1.3-3.4 秒；带客户端的一次冷启动实测 **250-270 秒**，不是几十秒）。
> 本页不再给固定秒数：小世界生成 1 个模组约 15s、3 个模组约 57s，首次冷启动含客户端加载会再翻几倍。

# 13. 无头服务器自动化测试

> 用专用服务器验证服务端逻辑：免交互拉起 → 经指令文件桥下发用例 → 解析 `[TEST]` 行并断言。
> 需要真实画面、UI、受伤特效或双端对比时，改用技能 `terraria-headless-test`。

## 13.1 能测什么

**能测（服务端权威面）**：加载期崩溃、本地化缺键、配方注册、`SaveWorldData` / `LoadData` 往返、NPC 生成与清除、货币与命令处理、随机逻辑幂等、`HandlePacket` 直调逻辑。

**测不了**：渲染、UI、贴图缺失（`_Highlight` / `_Head` 等客户端专属校验）、纯客户端钩子、双端同步。

## 13.2 两条必须先知道的事实

1. **没有客户端时世界不更新。** `Main.DedServ_PostModLoad` 里是 `if (Netplay.HasClients) Game.Update(...)`；
   零客户端时 `PostUpdateWorld` / `PostUpdateEverything` 永不进入。所以用例必须在 **世界载入时** 跑
   （`ModSystem.OnWorldLoad`），不能只放在每帧钩子里——否则 `results.txt` 永远是空的。

   这条已做对照实验：同一模组、同一份世界，分别在 **无控制台** 与 **真实控制台窗口**（`cmd /c start` + 继承环境变量）
   下启动，两边的都是 `Listening on port` → `Server started`，而 `results.txt` 始终只有 2 字节。
   控制台只影响 `startDedInput`，动不了 `HasClients` 这个门，所以**不要**为此改启动方式。
2. **`world=` 与 `autocreate` 要一起给。** 只写 `worldpath=` 不会设置内部的世界路径，服务器照旧打印世界列表
   并停在 `Choose World:`；而 `world=` 指向不存在的文件又**没有** `autocreate` 时，会打印
   `Load failed! No backup found.` 然后卡在 `Console.ReadKey()`，永远不会 `Listening`。

## 13.3 世界配置的正确写法

```ini
world=<沙盒>\saves\Worlds\world.wld   # 允许此刻不存在
worldname=headless_<hash>
autocreate=1                          # 第一次生成；文件已存在时被忽略，不会重建
maxplayers=1
port=<空闲端口>
upnp=0
```

- 小世界（4200×1200）实测 **15–60 秒**生成完（1 个模组约 15s，3 个模组约 57s，随机器变化）；别按固定秒数硬编码超时。
- 端口避开 **7491–7990**（Windows 常保留给 Hyper-V / WSL）。
- 世界缓存按"启用模组集合"分目录，别全局共用一个 `.wld`；被 kill 的运行会留下截断的世界，
  校验时要看文件头（前 4 字节的版本号），只看大小会放行清零文件。

## 13.4 就绪判据：让桥自证

**不要**用 stdout 里的 `Server started` 判就绪——重定向环境下这行不可靠，也不代表世界可用。
唯一可靠的信号是：**先下发 `ping`，在 `results.txt` 里读到 `[TEST] ping PASS`**。

脚本同时监控失败信号，命中即退出并打印诊断（配置、世界文件、`results.txt` 全文、`server.log` 尾部 20 行、stdout 尾部 25 行）：

| 信号 | 含义 |
|---|---|
| `Load failed` / `Choose World` | 世界配置或文件不可用 |
| `Missing mod` / `An error occurred` | 模组或依赖缺失 |
| 进程提前退出 | 启动即失败，看 stderr 与 server.log |
| 已监听但 N 秒无 ping | 桥没启用：环境变量名不对、模组没加载、`IsLoadingEnabled` 返回 false |

## 13.5 指令文件桥

被测模组内置一个 `SelfTestSystem : ModSystem`（模板见 `examples/SelfTestCommand.cs`）：

```
<workRoot>/
├── in/commands.txt     # 一行一条；# 开头为注释；#exit = 存档退出
├── out/results.txt     # 模组追加 "[TEST] <case> PASS|FAIL <detail>"
├── mods/               # -modpath：.tmod + enabled.json（含 modReferences 依赖）
├── saves/              # -tmlsavedirectory：Worlds / Mods / Logs
└── serverconfig.txt
```

- 桥根目录由环境变量传入。两种常见约定脚本都设置：`MOD_TESTDIR` 与 `<ModName>_TESTDIR`。
- 用例在世界载入时执行一次；需要"经过若干帧"的用例必须在有客户端的前提下再轮询（见 `terraria-headless-test`）。
- 断言只追加不重写，脚本按行解析。
- `-Commands` / `-ExpectCases` 支持逗号分隔（`'ping,talent_tree'`）；脚本会逐项拆成多行写入，不会写成一行。
- 世界缓存键 = `模组名_<每个 .tmod 文件名与大小的哈希>`，换模组、换依赖或重新打包都会换键。

## 13.6 标准用法

```powershell
# 只做构建 + hjson 校验（不启动服务器，几秒）
.\scripts\headless-test.ps1 -Mode Validate -ModName <Mod> -ProjectPath <csproj> -TmlDir <TML_DIR>

# 起服务器跑用例
.\scripts\headless-test.ps1 -Mode Server -ModName <Mod> -ProjectPath <csproj> -TmlDir <TML_DIR> `
  -ExpectCases ping,talent_tree

# 只打印将要执行的命令行与配置（排查配置问题最快）
.\scripts\headless-test.ps1 -Mode Server -ModName <Mod> -TmodPath <tmod> -TmlDir <TML_DIR> -PlanOnly
```

主要参数：`-Mode Validate|Server`、`-ModName`、`-ProjectPath`、`-TmodPath`、`-TmlDir`（或环境变量 `TML_DIR`）、
`-Commands`、`-ExpectCases`、`-TimeoutSec`、`-BridgeGraceSec`、`-SettleSec`、`-FailOnAnyFail`、
`-Port`（0 = 自动挑空闲端口）、`-WorkRoot`、`-PlanOnly`。

- `-SettleSec`（默认 3）：期望用例齐了之后再等几秒重读 `results.txt`——收尾阶段才写出的 FAIL 也算数。
- `-FailOnAnyFail`（默认 `$true`）：结果里**任何** FAIL 都会让退出码变 1，并在日志里标成 `UNEXPECTED FAIL`；
  只想校验点名的用例时传 `'-FailOnAnyFail:$false'`（bash 里必须加单引号，否则 `$false` 被 shell 吃掉）。
`-ValidateOnly` 仍可用但已弃用，会映射到 `-Mode`。

构建阶段会把打包目录指到临时目录（`-p:ExtraBuildModFlags=-tmlsavedirectory <temp>`），
因此**不需要先关游戏**，产物也直接给 Server 模式用。

## 13.7 排错速查

| 症状 | 原因 | 处理 |
|---|---|---|
| 停在世界列表 / `Choose World:` | 只给了 `worldpath=`，没有 `world=` | 按 13.3 写全 |
| `Load failed! No backup found.` 后卡住 | `world=` 指向不存在的文件且无 `autocreate` | 补 `autocreate=1`，或删掉坏缓存 |
| 服务器正常但 `results.txt` 一直空 | 用例放在 `PostUpdateWorld`（无客户端不跑） | 改到 `OnWorldLoad` |
| 桥不响应 | 环境变量名不匹配 / `IsLoadingEnabled` 判空 | 同时设 `MOD_TESTDIR` 与 `<ModName>_TESTDIR`；先跑 `ping` |
| 构建报 `TML003` | 游戏开着，`.tmod` 被占 | 用本脚本（打包到临时目录）或先关游戏 |
| 端口绑定失败 | 命中 7491–7990 保留段 | 让脚本自动挑端口 |
| `Device or resource busy` | 残留服务器进程占着文件 | 脚本会按沙盒路径清理残留；也可手动结束 |

## 13.7 验收标准（2026-11 修订）

「构建成功 + 能进世界」不足以判定通过——纯渲染/布局 bug 可以 100% 通过它
（实测：宝石页列表全空、天赋图标全空都能通过）。

- 逻辑改动：L1 断言 + `[TEST]` 覆盖改动点；
- **UI 改动：必须附一张 L2 截图**，并给出 `shotstat`（`distinct` / `nonUniform`）或 `assertpix` 像素断言；
- 依赖/打包改动：记录 `.tmod` 的 `mtime` 与 `sha12`，证明跑的是新包。
