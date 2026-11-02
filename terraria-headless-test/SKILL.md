---
name: terraria-headless-test
description: 给 tModLoader 模组做自动化自测：热会话一次启动反复下发（单条约 1 秒），无窗口跑真实世界，真帧截图与 UI 操作（免焦点按键/鼠标），文件桥下发指令并收 [TEST] 断言，支持批量 suite、并行 lab、命名 recipe。
whenToUse: 写完或改完模组要自己验证行为、复现 bug、看真实画面、跑回归，或要给模组接一套脚本化测试桥时加载。
---

# tModLoader 模组自测

改完代码，用一条命令拿到**可判定的结果**：世界真的跑了、断言 PASS/FAIL、需要时还有真实画面。

## 硬规则（违反就会白烧一整个 5–10 分钟）

0. **等待是最后手段，不是默认动作。** 先问：能不能直接查状态？
1. **任何阻塞等待上限 30 秒**。需要更久就拆成短轮询或走事件通知。
   - 反例：`job_output(wait=true, timeout_ms=420000)` —— 一轮直接挂 7 分钟。
   - 正例：`job_output(wait=false)` 每做一步查一次；或 `wait=true, timeout_ms<=3000` 当“让出一下”。
2. **启动一律 `-Detach`，之后用 `session.ps1 -Action Run/Suite`。** 不要为了等就绪而 sleep。
   - `-Detach` 自带硬预算 `-MaxWaitSec`（默认 **30s**）：超时就返回“正在启动”，会话仍然在后台继续起；
     冷启动 260s 的 L2 也因此不会堵住调用方（实测 21s 返回）。
   - 就绪探测用 `session.ps1 -Action Poll`（**永不阻塞**，0=就绪 1=未就绪，实测 0.4s）；
     确实要等才用 `-Action Wait -TimeoutSec 30`（自带进度、有上限）。
3. **不要用管道接驱动命令**（`pwsh ... | tail`、`| head` 这类）。子进程会继承管道句柄，
   只要它活得比命令久，管道就永不 EOF，命令永远不返回——看起来像“卡死”，其实是等不到结束符。
   驱动内部已改成 `Start-Process`/`cmd >> file`，但你手写的命令同样要遵守。
4. **失败必须快，不许靠睡。** 启动期盯 `<lab>/out/boot-*.log`（`boot-log.ps1 -Only errors`），
   命中 `Missing mod` / `ModSortingException` / 模态框字样就立即判失败；驱动已内置（数秒级）。
5. **长任务跑后台 job，不要前台堵。** 起 job 后继续做别的；job 结束会有会话通知。
6. **每次等待都要打印进度**（`[12s] waiting ...`）。没有进度输出又没有上限的等待，一律视为 bug。

判断自己是不是在“硬等”：如果这一分钟里你做不了任何别的事，那就是任务设计错了，不是等待姿势不对。

**脚本侧不变量**：`tml.ps1` / `session.ps1` 里不存在不受预算约束的等待——所有 `AddSeconds` / `Wait-Beat` / `Wait-Port`
都从 `-MaxWaitSec`（或 `-TimeoutSec`，且被上限截断）取值；无命令、无期望时干脆跳过等待。
如果以后要加新的等待，必须同样受预算约束，否则就是回归。

## 先看这张表：能测什么、多快

| 级别 | 组成 | 能验证 | 不能验证 | 冷启动 | 热会话单条 |
|---|---|---|---|---|---|
| **L1 无窗口** | 单个 `-server` + 模组侧假连接 | 世界 tick、AI、物理、生成、存档、掉落、发包端 | 渲染、UI、贴图、特效 | 10–15s | **0.4–0.6s** |
| **L2 有像素** | `-server` + 一个真客户端 | L1 全部 + 真帧截图、UI、特效、双端差异 | —— | 20s（小世界/暖缓存）～270s（大世界+首次模组加载+工坊查询） | **1.3–3.4s** |

两级共用同一套文件桥与断言格式，只差一个 `-Client`。

## 三步上手

```powershell
# 0) L2 前先体检（40 秒，缺 Steam / 配置不对会立刻说清楚）
pwsh -File resources/scripts/preflight-client.ps1 -TmlDir <TML_DIR>

# 1) 起一个常驻会话（就绪即返回；之后每条用例只发命令）
pwsh -File resources/scripts/tml.ps1 -Lab gems -ModName <Mod> -Tmod <tmod> -TmlDir <TML_DIR> `
  -Client -Player <角色> -MinimizeClient -Detach

# 2) 反复下发（单条约 1 秒）
pwsh -File resources/scripts/session.ps1 -Action Run -Lab gems -Commands 'c:ui gems;c:wait 20;c:shot gems'
pwsh -File resources/scripts/session.ps1 -Action Run -Lab gems -Recipe open-ui -Args 'page=gems'

# 3) 标准循环（顺序不能变）
#    Stop → 重新打包 → Detach
#    漏掉 Stop，或打包因句柄占用没落盘，都会让你拿旧包下结论
pwsh -File resources/scripts/session.ps1 -Action Stop -Lab gems

# 3) 批量 / 并行 / 收工
pwsh -File resources/scripts/session.ps1 -Action Suite -Lab gems -Suite resources/suites/l2-interaction.json
pwsh -File resources/scripts/suites.ps1 -Suite a.json,b.json -Parallel 2 -ModName <Mod> -Tmod <tmod> -TmlDir <TML_DIR>
pwsh -File resources/scripts/session.ps1 -Action Stop -Lab gems
```

不用热会话也可以一条命令跑完整轮：

```powershell
pwsh -File resources/scripts/tml.ps1 -Lab one -ModName <Mod> -Tmod <tmod> -TmlDir <TML_DIR> `
  -Commands 'ping;diag;spawn 1 5;wait 60;count npc' -Expect ping
```

## 产物与目录

工作目录默认 `~/.tmlkit`（`labs/` `_build/` `_inst/` `logs/`，环境变量 `TMLKIT_HOME` 可改），不写技能目录。

`labs/<lab>/` 下：`in/`（命令）、`out/`（结果）、`mods/`、`saves/`、`workshop/`、`.session.json`。
`out/` 里：`result-<side>.txt`（断言）、`log-<side>.txt`（命令与结果）、`diag-<side>.txt`（世界快照）、`heartbeat-<side>.txt`、`*.png`（截图）。

## 协议速览

| 文件 | 方向 | 内容 |
|---|---|---|
| `in/cmd-server.txt`、`in/cmd-client.txt` | 驱动 → 模组 | 一行一条，读完即删 |
| `out/log-<side>.txt` | 模组 → 驱动 | `[时间] [tick] 请求 → 结果` |
| `out/result-<side>.txt` | 模组 → 驱动 | 只有 `[TEST] <名字> PASS|FAIL <细节>` |
| `out/heartbeat-<side>.txt` | 模组 → 驱动 | `ms/tick/side/net/world/player/fps` |
| `out/<名字>.png` | 客户端 → 人 | 后缓冲截帧，先写 `.partial` 再改名 |

行首 `s:` 只给服务端，`c:` 只给客户端（无前缀默认服务端）。断言在模组里一行：`DevBridge.Report("case", ok, "detail")`。

## 动词与扩展点

| 类别 | 命令 |
|---|---|
| 读取 | `ping` `diag` `tick` `state` `count` `find` `tile` |
| 世界 | `spawn` `give` `tp` `time` `weather` `save` `hurt` `buff` `clearbuffs` `playerreset` |
| 控制 | `wait <ticks>`（也支持 `20t` / `1s`）`waitfor <条件>` `shot <名字>` `exit` `link on|off` `mute on|off` `speed on|off` |
| 界面/输入 | `ui <名字>` `key <触发器>` `key vk:<键>` `mouse <x> <y>` `click [left|right] [x y]` |
| 断言 | `assert hp>=60` `assert npc<=3` `assert inventory==true` `check hp>=40` |
| 测试角色 | `god` `kb` `lockhp` `keepalive` `hp` `hpmax` `defense` `immune` |

模组侧两行注册，不必 fork 桥：

```csharp
public override void Load()
{
    DevBridge.RegisterVerb("gems", _ => { TalentTree.Open(); return "gems opened"; });
    DevBridge.RegisterUi("gems", () => TalentTree.Open());
}
```

未注册的名字会被拒绝并列出全部可用项，不会静默失败。

`ping` 会回报桥版本：`pong tick=… bridge=1.4.0`。模组里 vendored 的 `bridge/*.cs` 版本不一致时，
新旧动词行为会不同（例如旧版 `wait` 不认 `1s` 后缀，会抛 FormatException）——出怪事第一件事就是看这个版本号。

## 界面、输入与无人值守

- `ui <名字>`：调模组注册的打开器；内置 `inventory` / `close`。
- `key <触发器>`：进程内写 `PlayerInput.Triggers.JustPressed`，**不依赖窗口焦点**；`key vk:E` 才是 Win32 兜底。
- `mouse` / `click`：进程内改 `Main.mouseX/Y`；`click` **同时**写 `PlayerInput.Triggers.MouseLeft` 与
  `Main.mouseLeft/mouseLeftRelease`——UI 与第三方框架（SilkyUI 等）读的是后者，只写前者打不到控件。
- `wheel <delta>`：滚轮，写 `PlayerInput.ScrollWheelValue` 与 `ScrollWheelDeltaForUI`（正=上滚）。
- `-MinimizeClient`：客户端心跳后最小化窗口；配合上面的注入，全程不抢焦点。
- 静音默认开（`SDL_AUDIODRIVER=dummy` + 音量归零），`-Mute:$false` 关闭。
- UI 有开启动画，截图前必须等帧：`c:ui gems; c:wait 20; c:shot gems`。

### .tmod 指纹：先确认跑的是哪个包

启动时打印 `tmod: mtime=… size=… sha12=… age=…min`。
`age>30min` 默认**直接失败**（多数情况是打包被句柄占用、只打印 Packaging 却没落盘），
确认无误要跑旧包时加 `-AllowStaleTmod`。

## 自绘 UI：输入注到不了，必须走 `uiact`

`key` / `click` / `wheel` 注入的是**原版输入管线**（`PlayerInput` + `Main.mouseLeft/mouseLeftRelease`）。
原版 UI 和读这两个字段的框架能收到；但**自绘 UI 如果自己调 `Mouse.GetState()` 读滚轮/坐标，注入永远到不了**——
`Mouse.GetState()` 是只读的系统状态，模组侧也无法伪造。

所以给模组一个统一出口：注册 UI 动作，测试用 `uiact` 调它。

```csharp
public override void Load()
{
    DevBridge.RegisterUiAction("zoom", args => TreeView.Zoom(args.Length > 0 ? int.Parse(args[0]) : 1));
    DevBridge.RegisterUiAction("gems.page", args => GemPage.Select(args[0]));
}
```

```
c:uiact zoom +1          -> [Zoom] step=+1 applied
c:uiact gems.page sigil  -> 切到印记页
c:uiact nope             -> REFUSED ... 已注册: zoom,gems.page
```

判断标准很简单：**这个控件是不是读 `Mouse.GetState()`**？是 → 必须 `uiact`；否（原版控件、读 `Main.mouseLeft` 的框架）→ `click` 可行。

## 测试角色

| 开关 | 命令 | 效果 |
|---|---|---|
| `-God` | `god on` | 伤害被 `ModifyHurt → Cancel()` 取消，连特效都不触发 |
| `-NoKb` | `kb on` | 免疫击退 |
| `-LockHp 25` | `lockhp 25` | 锁血，`PreKill` 兜底不死 |
| `-KeepAlive` | `keepalive on` | 受伤流程照跑，事后还原血量（测受伤特效） |

## 批量 suite

```json
{ "name": "gems-ui", "cases": [
  { "name": "open",  "recipe": "open-ui", "args": { "page": "gems" }, "expectLog": ["ui gems -> opened"] },
  { "name": "check", "commands": ["s:assert inventory==true"], "expect": ["assert_inventoryeq1"] },
  { "name": "shot",  "recipe": "shot-ui", "args": { "name": "gems" }, "shot": "gems" }
] }
```

- `expect` 等 `[TEST] <名字>`；`expectLog` 等桥日志子串（动词/界面动作用它）。
- `shot` 自动追加 `c:shot <名字>` 并**校验 PNG 真的生成**，缺失判 FAIL。
- 每个用例开始会清空结果文件，用例之间不串味。

## Recipe

`resources/recipes/*.json` 命名动作序列，`{param}` 单层替换。内置 `open-ui` / `shot-ui` / `reset-player` / `hurt-check`；未知名字会报错并列出可用项。

## 并行

`suites.ps1 -Parallel N`：每个 suite 独立 lab + 独立端口，子进程里完成「起会话 → 跑 suite → 停会话」。L1 可任意并行；带 `-Client` 时自动降为串行（Steam / 显卡 / 焦点会打架）。

## 参数速查

| 脚本 | 关键参数 |
|---|---|
| `tml.ps1` | `-Lab` `-ModName` `-Tmod`/`-ProjectPath`/`-ModDir` `-TmlDir` `-Client` `-Player` `-MinimizeClient` `-Detach` `-Port` `-Commands` `-Expect` `-TimeoutSec` `-Mute` `-IsolatedWorkshop` `-LegacyEnv` `-LegacyBridge` `-PlanOnly` |
| `session.ps1` | `-Action Run|Suite|Status|Stop` `-Lab` `-Commands` `-Expect` `-ExpectLog` `-Recipe` `-Args` `-Suite` `-TimeoutSec` `-SettleSec` `-CaseTimeoutSec` `-StopOnFail` |
| `suites.ps1` | `-Suite` `-Parallel` `-ModName` `-Tmod` `-TmlDir` `-Port` `-Client` `-Player` `-Keep` |
| `preflight-client.ps1` | `-TmlDir` `-WaitSec` |
| `boot-log.ps1` | `-Lab` `-Side server\|client` `-Only all\|errors\|milestones` `-Tail` `-Follow` |
| `win-ui.ps1` | `-Action List|Shot|Click|Key` `-Title` `-Out` `-X` `-Y` `-Keys` `-Button` `-NoFocus` |

## 必须先知道的六个坑

1. **空服务器不 tick**：`DedServ_PostModLoad` 里 `if (Netplay.HasClients) Game.Update(...)`。L1 靠给 `RemoteClient` 塞假 `ISocket` 解决；L2 有真客户端，必须 `link off`，否则假连接会把真客户端挤掉。
2. **缺 `config.json` 会停在 Select Language**：模组枚举永不开始，表现为「客户端 300 秒不响应」。沙盒模板见 `resources/config/client-config.json`，驱动会自动写入。
3. **`-modpath` 只对服务端生效**：客户端只从 `<存档目录>\Mods` 加载。L2 必须把 `.tmod` 与 `enabled.json` 复制过去（驱动会同时镜像到 `saves` 与 `saves-client`）。
4. **别给游戏进程接 stdout 管道**：日志写满后主线程卡在 `Console.Write`，现象酷似「卡在加载模组」；常驻会话更必须用 `Start-Process` 脱离句柄。
5. **端口会被占用**：tML bind 失败时静默退出。驱动会从 `-Port` 起自动找空闲端口并写进 `serverconfig.txt`，失败会直接告诉你「端口被占用」。
6. **L2 需要 Steam 在跑**：缺 Steam 时客户端弹 Fatal Error 并卡住对话框；`preflight-client.ps1` 会先判这一条。

## 启动期可见性：不依赖模组也能看（boot 日志）

驱动给 server/client 都做了 **OS 级文件重定向**（`cmd /c ... >> file 2>&1`，不经过管道），
所以进程从**第一行输出**开始就落盘，模组桥有没有起来都能看：

```
<lab>/out/boot-server.log     tML 原始 stdout+stderr（Finding Mods / Sandboxing / 异常栈都在这里）
<lab>/out/boot-client.log
```

```powershell
# 看里程碑（进程到底走到哪一步）
pwsh -File resources/scripts/boot-log.ps1 -Lab gems -Side server -Only milestones
# 只看错误
pwsh -File resources/scripts/boot-log.ps1 -Lab gems -Side client -Only errors
# 实时跟踪
pwsh -File resources/scripts/boot-log.ps1 -Lab gems -Side client -Follow
# 原始尾部
pwsh -File resources/scripts/boot-log.ps1 -Lab gems -Side server -Tail 40
```

失败时驱动会自动把 `boot-*.log` 尾部 15 行打进诊断——**模组没加载、桥没 arm 也照样有证据**。

启动失败还被做成了**快失败**：命中 `Missing mod` / `ModSortingException` / `Disabling Mod` / 端口占用 / 模态框字样，
数秒内抛错并附原始行（实测缺依赖 6.8 秒），不再等到 240 秒超时。

实测：一次正常启动的 boot-server.log 里按顺序出现
`Finding Mods... → Sandboxing: MyMod → Constructing Mods... → Listening on port → Server started`；
绑定端口失败会直接出现 `通常每个套接字地址…只允许使用一次`，不用等 240 秒超时。

## 等不到客户端心跳：先分类，再决定走哪条路

`客户端心跳超时` 是最常见的失败，但原因完全不同。按下面顺序 30 秒内能定位：

| 现象 | 判据 | 处理 |
|---|---|---|
| 进程没起来 | `Get-Process dotnet` 里没有对应 lab 的进程 | 看 `-Detach` 输出；端口/Steam 前置检查会先报 |
| 进程在、日志停在 `Hook …AssemblyLoadContext…` | 客户端自己的 `client.log` 没有 `Finding Mods` | 缺完整 `config.json`（模板在 `resources/config/client-config.json`），或 Steam 没登录 |
| `Finding Mods` 有、桥 `log-client.txt` 没生成 | 环境变量没进子进程 | 用驱动启动（它设 `TMLKIT_ROOT`）；手工启动时自己 export |
| 桥 arm 了但没有 `[TEST]` | 用例没注册 / 名字不匹配 | `session.ps1 -Action Run -Commands 'ping'` 先验通道 |
| 客户端弹模态框（`Unable to access Steam Workshop` / `Select Language` / `Fatal Error`） | 模态框挡住加载，世界永远进不去 | 驱动会在 90s 内识别并失败，同时截 `out/client-failure.png`；按提示修 Steam/配置后重跑 |
| 心跳文件存在但很旧 | 进程已死或 tick 停了 | 用 `session.ps1 -Action Status` 看 alive 与 tick |

诊断命令：

```powershell
pwsh -File resources/scripts/session.ps1 -Action Status -Lab <lab>
tail $env:TMLKIT_HOME/labs/<lab>/out/log-client.txt | Select-Object -Last 10 # 桥
tail "<TML_DIR>/tModLoader-Logs/client.log" | Select-Object -Last 15          # tML 自己
pwsh -File resources/scripts/preflight-client.ps1 -TmlDir <TML_DIR>           # 40 秒体检
```

## 兜底：桥不可用时的桌面级 UI 操作（computer use）

当桥死活起不来（模组没加载、客户端只有菜单），但**窗口是真的**，可以用系统级截图/点击继续验证界面：

```powershell
# 列窗口（确认标题/进程）
pwsh -File resources/scripts/win-ui.ps1 -Action List

# 截窗口（PrintWindow，被遮挡也能拍；失败退回屏幕抓取）
pwsh -File resources/scripts/win-ui.ps1 -Action Shot -Out C:\temp\game.png

# 窗口内坐标点击 / 发键
pwsh -File resources/scripts/win-ui.ps1 -Action Click -X 400 -Y 300
pwsh -File resources/scripts/win-ui.ps1 -Action Key -Keys '{ESC}'
```

- 坐标是**窗口内相对坐标**（窗口左上角为 0,0），先用 `Shot` 量出目标位置。
- 默认会自动 `SetForegroundWindow`；窗口最小化时先 `ShowWindow(SW_RESTORE)`（脚本已做）。
- 这条路的代价：依赖窗口与前台焦点、拍不到纯离屏内容；能用桥就别用它。

## 依赖与工坊：缺一个就 ModSortingException

驱动会从 `build.txt` 的 `modReferences` 自动补齐依赖，依次在：

1. `-ExtraMods <路径或目录>`（可多次传）
2. 玩家 `Mods`：`%USERPROFILE%\Documents\My Games\Terraria\tModLoader\Mods`
3. 工坊：`<steamapps>\workshop\content\1281930`（可用 `-WorkshopContent` 指定）

找到就复制进 lab 并把 `enabled.json` 写成 `[被测模组, 依赖...]`；**找不到立刻抛错并列出查过的地方**。
只给 `.tmod` 时用 `-BuildTxt <项目 build.txt>` 指定依赖清单来源。

即使没有任何清单，启动期也会盯进程输出：出现 `Missing mod` / `ModSortingException` / `Disabling Mod`
就在**秒级**失败并打印原始行（实测 6.8 秒），不再等满心跳超时。

## 截图也要能断言：shot / shotstat / assertpix

- `shot <名字>`：全屏；`shot <名字> <x> <y> <w> <h>`：只拍这块（省得整屏裁）。
  每次都会同帧打印 `shotframe name=… tick=… rect=… mouse=…`，**用这一帧的坐标去核对**，
  不要拿几十 tick 前的日志坐标去裁图（fit/动画已经改了布局）。
- `assertpix <x> <y> <#rrggbb> [tol]`：**同帧读后缓冲**取一个像素做断言，直接产出 `[TEST]`。
  实测：`assertpix 110 110 #ff0000 60` → `PASS got=f71318 d=8,19,24`。
- suite 的 `shot` 会额外产 `shotstat`（`distinct` 颜色数 / `nonUniform` 非主导色占比）。

suite 用例里 `"shot": "gems"` 除了校验 PNG 是否生成，还会产出一行统计：

```
[PASS] shot:gems        170704 bytes, 800x720
[PASS] shotstat:gems    distinct=312 nonUniform=0.87
```

- `distinct`：采样到的颜色种类数；`nonUniform`：非主导色占比（0–1）。
- 面板“看起来是空的”通常表现为 `distinct` 很低、`nonUniform` 接近 0，可以直接写进断言。

## UI 问题的固定套路（先数据，后截图）

1. 在可疑位置加一行**结构化日志**（例：`[Grid] count=5 nonAir=59 filter=True`）；
2. 跑一轮 `expectLog` 断言这行，先判断“数据是不是空的”；
3. 数据没问题再截图，用 `shot` + `shotstat` 判断“是不是没画出来”；
4. 只有这两步都对不上，才去怀疑布局/尺寸/裁剪。

这条顺序能把“界面空白”从猜谜变成二分：数据 → 绘制 → 布局。

## 分册

- `01-architecture.md` 为什么这样设计、能力边界、IL 证据
- `02-protocol.md` 文件协议、心跳、`wait`/`waitfor`、桥接入与扩展点
- `03-verbs.md` 动词全表、`check`/`assert` 命名规则
- `04-client-mode.md` L2 客户端接入、截图套路、隔离安装副本
- `05-gotchas.md` 症状 → 原因 → 处理
- `06-verification.md` 实测数据与验收清单
- `docs/tier0-terrex-spike.md` 协议客户端（Tier 0）可行性结论
- 资产：`bridge/`（可 vendored 的 C# 桥）、`scripts/`（驱动 / 会话 / 体检 / 桌面兜底）、`suites/`、`recipes/`、`config/`
