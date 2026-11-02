# 02. 文件协议与接入

## 接入（三步）

1. 把 `bridge/*.cs` 链进工程（不要复制粘贴，改一处即同步）：

```xml
<ItemGroup>
  <Compile Include="..\<KIT>\resources\bridge\*.cs" Link="DevBridge\%(Filename)%(Extension)" />
</ItemGroup>
```

2. 模组里写断言：

```csharp
TmlKit.Bridge.DevBridge.Report("my_case", ok, "detail");
```

3. 用 `scripts/tml.ps1` 指定 `-Commands` 与 `-Expect` 跑一轮。

桥自带 `ModSystem` 与 `ModPlayer`，无需注册；`Main.dedServ` 为真时自动跳过客户端专用部分。

## 扩展点（不要 fork 桥）

```csharp
// 自定义动词：返回一行结果，参数是空格切分后的数组
DevBridge.RegisterVerb("grid", args => "count=" + InventoryGrid.Count);

// 界面打开器：配合 ui <名字>
DevBridge.RegisterUi("gems", () => TalentTree.Open());
```

两行都写在模组的 `ModSystem.Load()` 里。未注册的名字会被拒绝并列出全部可用项，不会静默失败。

## 与环境变量的约定

- 桥只读 `TMLKIT_ROOT`（技能默认设置它）。
- 兼容旧桥：`-LegacyEnv`（默认开）额外导出 `MOD_TESTDIR` 与 `<ModName>_TESTDIR`；模组迁移到新桥后可用 `-LegacyEnv:$false` 关掉。
- 旧桥若用 `in/commands.txt` / `out/results.txt` 命名，加 `-LegacyBridge` 让驱动再写一份 `commands.txt`，并自动读取 `results*.txt`。

## 目录布局

```
labs/<lab>/
├── in/     cmd-server.txt  cmd-client.txt      # 驱动写，模组读完即删
├── out/    log-*.txt  result-*.txt  heartbeat-*.txt  diag-*.txt  *.png  hurt-*.txt
├── mods/                 # 服务端 -modpath 指向这里
├── saves/                # -tmlsavedirectory
│   ├── Mods/             # 客户端专用：模组与 enabled.json 必须在这
│   └── Worlds/
└── serverconfig.txt
```

## 热会话下的读取语义

`session.ps1 -Action Run/Suite` 用**文件偏移**只读本次新增的 `[TEST]` 行；suite 里每个用例开始还会清空 `result-*.txt`，
所以历史结果不会串到当前用例。`-ExpectLog` 则匹配 `log-<side>.txt` 的新增行（动词、界面动作都靠它断言）。

## 心跳

`out/heartbeat-<side>.txt` 每 250ms 重写一次：

```
ms=1730000000000
tick=7615
side=server
net=2
world=myworld
player=(none)
fps=0
```

驱动只认 `ms`：**存在**不算就绪，`ms` 在 3 秒内才算。菜单期的客户端也会写心跳，
所以"起来了但还没进世界"和"起不来"能区分开。

## 命令与等待

- 每次轮询把整个 `cmd-<side>.txt` 读入队列并删除文件；每帧只推进一条。
- `wait <n>`：接下来 n 帧不执行后续命令（**只在真正的帧里递减**，菜单里的额外轮询不算）。
- `waitfor inworld|menu`：条件不满足就原地阻塞重试，用于"进世界后再改血 / 受伤"。
- `exit [save]`：`SaveWorld()` 后 `Environment.Exit(0)`，测试专用，不要进生产代码。

## 结果格式

```
[TEST] world_loaded PASS world=myworld
[TEST] check_hpgte40 PASS hp=57/100 want >=40
```

驱动用 `^\[TEST\] (\S+) (PASS|FAIL)\s*(.*)$` 解析；`-Expect` 里的用例名缺失也算失败。

## 为什么用文件而不是 socket

所有读写都发生在游戏主线程，不存在跨线程访问 `Main.*` 的崩溃；一次往返几十毫秒，
远小于模型或构建的耗时。需要进程内更快时可以换成 socket，协议层不用改。
