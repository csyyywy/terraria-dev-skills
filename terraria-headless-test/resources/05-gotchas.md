# 05. 排错：症状 → 原因 → 处理

| 症状 | 原因 | 处理 |
|---|---|---|
| 服务器起来了但什么都没发生，tick 恒 0 | 空服务器不 tick | 装假连接（`HeadlessLink`）；确认日志有 `headless link installed` |
| 客户端"卡在加载模组"，等几分钟不动 | ① 客户端没拿到模组（`-modpath` 无效）② stdout 管道写满 | 把模组复制到 `saves/Mods`；去掉 stdio 重定向 |
| 客户端连上就被踢 / 一直连不上 | 服务器还在生成世界，端口没在听 | 起客户端前探一次 TCP 端口 |
| `Mod name X does not match assembly name Y` | tModLoader 内部名 = **源码目录名** | 目录名改成与 `AssemblyName` 一致 |
| 构建报 `TML003: Please close tModLoader…` | 玩家开着游戏，`.tmod` 被独占 | 打包目录指到独立目录（`-p:ExtraBuildModFlags=-tmlsavedirectory <dir>`），不要写玩家 `Mods` |
| `wait 150` 立刻返回 | 等待计数被非帧的轮询（`Load` / `OnWorldLoad`）递减 | 只在 `PostUpdateEverything` 推进计数 |
| 两张截图只剩一张 | 单槽 pending 互相覆盖 | 改成队列 |
| `hurt` 没反应 | 无敌帧未过 | 两次伤害之间 `wait 90–120` |
| 生成的敌怪很快消失 | 服务器上没有玩家，引擎判为"离玩家太远" | L1 里只验"生成成功"；行为验证上 L2 |
| 客户端日志里 `Did not find enabled.json file` | 模组放在 `-modpath` 而不是 `saves/Mods` | 复制过去 |
| 副本里启动就卡 | 副本不在 `...\steamapps\common\tModLoader` 下 | 挪回去 |
| 客户端 300 秒没有心跳，日志停在 `Hook …AssemblyLoadContext…` | 沙盒缺完整 `config.json`，tML 走首次运行流程停在 **Select Language** | 用 `resources/config/client-config.json` 模板（驱动会自动写入）；别用手写的精简 JSON |
| 服务端起一下就没了，`-Action Run` 说进程不存在 | 端口被别的 lab 占着，tML bind 失败后**静默退出** | 现在驱动会自动换空闲端口；老日志里搜 `只允许使用一次` 可确诊 |
| 客户端弹 `Please ensure Steam is logged in and running.` 并卡住 | Steam 没运行 | 先开 Steam；`preflight-client.ps1` 会提前判掉 |
| 下一轮客户端一启动就退出 | 上一轮收尾写进 `in/cmd-client.txt` 的 `exit` 残留 | 驱动收尾已清空 `in/`；手工复现时先删 `in/*` |
| 等不到客户端心跳 | ① 缺 config.json 停在 Select Language ② 没 Steam ③ 端口被占服务端静默退出 ④ 桥没 arm | 依次看 `client.log` 有没有 `Finding Mods`、`preflight-client.ps1`、`session.ps1 -Action Status` |
| 桥始终起不来但窗口是真的 | 模组没加载 / 客户端只有菜单 | 用 `win-ui.ps1 -Action Shot/Click/Key` 走桌面级操作兜底 |
| 想知道启动卡在哪一步，但模组没加载、桥没 arm | 没有桥日志 | 看 `<lab>/out/boot-*.log`（OS 级重定向，从第一行就有）；`boot-log.ps1 -Only milestones` 直接给里程碑 |
| `ModSortingException: Missing mod: X required by Y` | 依赖没进沙盒 | 驱动现在会自动从 modReferences/玩家 Mods/工坊补齐；缺了会在数秒内报错并列出查过的地方 |
| 客户端弹 `Unable to access Steam Workshop` / `Select Language` / `Fatal Error` 卡住 | 模态框挡住了加载 | 驱动会在 90 秒内识别这些字样并失败，同时自动截一张 `client-failure.png` |
| 改完代码但用例说 `no such test registered` | `.tmod` 仍被上一轮进程占用，打包时间戳没变 | `session.ps1 -Action Stop` 现在会校验 lab 内 `.tmod` 句柄，仍占用会打印 WARN |
| 命令一直不返回 / job 永远等不到结束 | 用管道接驱动命令，未退出的子进程顶住管道，永不 EOF | 别用 `| tail`；驱动已用 Start-Process 脱离 stdio，手写命令同样遵守 |
| 重建包后没生效：`-Detach` 秒返回、截图还是老样子 | 同 lab 旧会话仍持有旧 `.tmod`（复制不进去/不生效） | 先 `session.ps1 -Action Stop`；驱动现在也会自动停旧会话并等句柄释放，`-Reuse` 才复用 |
| `click` 日志说 pressed，但 UI 控件没反应 | UI 读的是 `Main.mouseLeft + mouseLeftRelease` 边沿，不是 `PlayerInput` | 桥 1.4.0 起两套都写；仍不行用 `wheel`/`key` 或让模组注册 `ui` 打开器 |
| 模组里 vendored 的桥报 `FormatException`（如 `wait 1s`） | 桥版本旧 | `ping` 看 `bridge=<版本>`；把 `resources/bridge/*.cs` 重新覆盖进模组 |
| `c:wheel` / `c:click` 对自绘 UI 无效（日志说 queued 但界面不动） | 自绘 UI 读 `Mouse.GetState()`，只读系统状态，注入到不了 | 让模组 `DevBridge.RegisterUiAction("zoom", …)`，测试用 `c:uiact zoom +1` |
| 连续 `-Detach` 都 16-18s 秒返回，但包没换 | 旧会话复用 + `.tmod` 被占用导致构建没落盘 | 驱动会先停旧会话；日志里看 `tmod: mtime=… sha12=… age=…min`——年龄大就说明构建没成功 |
| 世界打不开 / 存档损坏 | 强杀进程 | 用 `exit save` 优雅退出；lab 本就是一次性的 |
