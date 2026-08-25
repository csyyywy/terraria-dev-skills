# 13. 无头服务器自动化测试（Headless Testing）

> 让 AI 在设计/实现之后，**直接通过无头服务器验证逻辑**：免交互拉起专用服务器 → 经"指令文件桥"下发测试指令 → 解析结果断言。
> 本分册所有机制均经 2026-02 本机 spike 实测（参数、就绪标记、耗时、已知噪音见 §13.2）。

## 13.1 能测什么 / 不能测什么

**能测（服务端权威面）**：加载期崩溃、本地化缺键警告、配方注册、世界生成与持久化（SaveWorldData/LoadData 往返）、NPC 生成/清除、货币与命令处理、词缀掷点幂等、HandlePacket 直调逻辑。
**不能测**：渲染/UI/贴图缺失（`_Highlight`/`_Head` 等客户端专属校验无头测不出）、纯客户端钩子、真实双端同步（无头客户端不受支持——只能测到"单服务器端"粒度）。

## 13.2 已验证事实（spike 实测，2026-02）

| 事项 | 结论 |
|---|---|
| 免交互启动 | `-config <file>` + 配置内 `world=/autocreate=1/worldname/maxplayers/port` → 自动建小世界并就绪；**小型世界生成约 10 秒** |
| 就绪标记 | stdout 依次出现 `Listening on port <port>` → `Type 'help' for a list of commands.` → **`Server started`**（以此为准） |
| 启动噪音 | 重定向环境下会出现两次"**句柄无效**。(see server.log for full trace)"——无害，可忽略；它是 §13.3 所述输入限制的症状 |
| **stdin 喂命令不可行** | Windows 版服务器用 Console API（按键级）读输入而非标准输入流，重定向 stdin 后命令不被消费（发出 help/exit 均无效，直至超时）。**不要尝试管道喂命令**；官方 DedicatedServerUtils 靠 tmux/docker attach 真 TTY |
| 进程管理 | 优雅退出需靠指令桥（见 §13.4 `#exit`）；超时兜底 `Process.Kill()`（EXITCODE=-1，世界可能未保存） |
| 隔离 | `-tmlsavedirectory <sandbox>` 使 Worlds/Mods/Logs 全部派生到沙盒，不污染真实存档 |

## 13.3 核心机制：指令文件桥（Command File Bridge）

被测模组内置一个 **SelfTestSystem : ModSystem**（模板见 `examples/SelfTestCommand.cs`），约定：

```
<workRoot>/
├── in/commands.txt        # AI 侧追加行 = 下发指令（每行一条；# 开头为注释；'#exit' = 存档退出）
├── out/results.txt        # 模组侧追加 "[TEST] <用例名> PASS|FAIL <详情>"
├── mods/                  # -modpath 指向这里（.tmod + enabled.json）
├── saves/                 # -tmlsavedirectory 指向这里
│   ├── Worlds/spike.wld
│   └── Logs/
└── serverconfig.txt       # 脚本自动生成
```

- 模组侧 `PostUpdateWorld` 每 30~60 tick 读一次 `in/commands.txt`，维护"已消费行数"游标，逐行分发到注册的测试处理器；
- 每个处理器执行断言后向 `out/results.txt` 追加一行结果；**只追加、不重写**（脚本侧 tail 解析）；
- `#exit` 特殊指令：`WorldFile.SaveWorld(); Environment.Exit(0);`（测试场景专用，非生产代码）。

## 13.4 标准流程（scripts/headless-test.ps1 已封装）

```powershell
.\resources\scripts\headless-test.ps1 `
  -ProjectPath '<WORKSPACE>\<ModName>\<ModName>.csproj' `
  -ModName '<ModName>' `
  -Commands @('selftest currency', 'selftest rift level1') `
  -ExpectCases @('currency', 'rift level1')
```

内部八步：① 可选 `dotnet build` → ② 双位置定位 `.tmod`（安装目录 Mods 与默认存档 Mods）拷入沙盒 `mods/` + 写 `enabled.json` → ③ 生成 `serverconfig.txt` 与空指令/结果文件 → ④ `dotnet tModLoader.dll -server -config … -tmlsavedirectory … -modpath …` 后台启动（stdout/stderr 异步落盘，避免死锁）→ ⑤ 轮询 stdout 直到 `Server started` → ⑥ 轮询 `results.txt` 直到期望用例齐活或超时 → ⑦ 追加 `#exit`，20 秒不退则 Kill → ⑧ 汇总 `{Pass, Fail, Elapsed, 日志路径}`，Fail 非零则脚本退出码 1。

## 13.5 给被测模组的规范

1. 提供 **Console 型自检命令**或 SelfTestSystem（二选一，推荐后者，见 examples）；
2. 所有断言输出必须走统一格式 `[TEST] <case> PASS|FAIL <detail>`；
3. 断言尽量**服务端语义**：不要依赖 `Main.LocalPlayer`/`Main.MouseWorld`/渲染；
4. 需要确定性随机时在测试处理器内固定种子，别用 `Main.rand` 裸值。

## 13.6 排错速查

| 症状 | 原因 | 处理 |
|---|---|---|
| 卡住不动且 stdout 出现"句柄无效" | 正常启动噪音 | 忽略；以 `Server started` 为准 |
| 永远等不到 `Server started` | 端口占用 / 世界损坏 / 模组加载红字 | 看 `<sandbox>/saves/Logs/server.log` 尾部；换端口重试 |
| `results.txt` 无输出 | 指令桥没装 / commands.txt 编码不对（须 UTF-8）/ 游标文件错位 | 先发 `ping` 用例验证桥；检查 File.AppendAllText 的编码参数 |
| 强杀后世界打不开 | 未走 `#exit` 就 Kill | 删沙盒重来（沙盒本就是一次性的） |
