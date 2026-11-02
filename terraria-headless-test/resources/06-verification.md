# 06. 实测数据与验收

环境：Windows 11 x64、tModLoader 1.4.4（2026.08 stable）、.NET 8/9、单机。

## L1

```
[    2s] build
[    5s] server heartbeat alive
[   11s] RESULT: PASS=6 FAIL=0
        world_loaded / tick_advancing(tick=31) / tile_write / npc_spawn
        world_time_advancing(time 13601 -> 13641) / heartbeat_file
```

无客户端时 `diag` 仍报 `hasClients: True`，心跳 `tick` 连续增长到数千——世界确实在跑。

## L2

```
[    7s] server port listening
[    8s] client started
[   23s] client heartbeat alive
[   31s] RESULT: PASS=12 FAIL=0  SHOTS=2
```

截图 800×720，玩家站在正午地表，HUD / 小地图 / 聊天都在，`Welcome to <world>! Current players: <name>.`

## 测试角色

```
c:god on;c:hurt 40;c:check hp>=60        -> check_hpgte60 PASS  hp=60/260   （血没掉）
c:lockhp 25;c:hurt 999;c:check alive     -> check_alive PASS   hp=25       （没被打死）
c:lockhp off;c:hurt 12;c:check hp<25     -> check_hplt25 PASS  hp=20       （正常掉血）
```

## 热会话（2026-11-02 实测）

| 场景 | 用时 |
|---|---|
| L1 `s:ping`（热会话） | 0.6s（连续三次稳定） |
| L1 4 条 suite（ping / 自定义动词 / diag / ping） | 2.7s |
| L1 4 条 assert suite | 1.8s |
| L2 5 条交互 suite（waitfor → key → mouse → click → shot） | 3.4s |
| L2 4 条 recipe suite（reset → open-ui → assert → shot） | 2.7s |
| 3 个 L1 suite 并行 | 14s（含各自 ~11s 启动） |
| Stop 会话 | 3.1s |

对照冷启动：L1 10–15s、L2 20–35s。**热会话把单条成本压到 1 秒级**。
## 2026-11-02 补充实测

| 场景 | 结果 |
|---|---|
| 缺依赖（modReferences 里有、沙盒没有） | **6.8s** 失败，输出 `Missing mod: SilkyUIFramework required by DepMod` |
| 依赖自动补齐 | `dep: SilkyUIFramework <- …\Mods\…tmod`，`enable: DepMod,SilkyUIFramework,SubworldLibrary` |
| `wait 1s` | 60 tick（log 里 `wait 60 tick(s) (1s)`） |
| 冷启动 L1 | 9–15s |
| 冷启动 L2 | 20s（暖缓存）～270s（大世界 + 首次模组加载 + 工坊查询） |

## 2026-11-02 第三批实测

| 场景 | 结果 |
|---|---|
| 同 lab 二次 `-Detach` | 日志 `found running session → stopping it → previous session stopped; .tmod handles released`，5s 起好 |
| 桥版本回报 | `[PASS] ping :: tick=80 side=server world=lab bridge=1.4.0` |
| `-Detach -MaxWaitSec 20` 冷启动 L2 | 21.3s 返回（此前 240s） |
| `-Action Poll` | 0.4s，`server=ready client=ready tick=…` |

## 2026-11-02 第四批实测

| 场景 | 结果 |
|---|---|
| `uiact zoom +1` | 桥日志 `[Zoom] step=+1 -> applied` / `uiact zoom -> done` |
| `uiact nope` | `REFUSED ... 已注册: zoom` |
| `.tmod` 指纹 | `mtime=2026-11-02 18:53:27 size=43320 sha12=3cf36d4418fa age=0.1min` |

## 2026-11-02 第五批实测（A/B/C 对照 + 像素断言）

| 场景 | 结果 |
|---|---|
| 同一帧画 `TextureAssets.Item[Heart]` / `MagicPixel` / `InventoryBack9` | 三者**全部出像素**（截图可见；`assertpix` 取到 f71318 / ffffff / 3f5297） |
| 区域截图 `c:shot crop 90 90 260 70` | 产出 260x70 PNG，同帧日志 `shotframe … rect=90,90,260,70` |
| `assertpix 110 110 #ff0000 60` | PASS，`got=f71318 d=8,19,24` |
| `.tmod` age>30min | 默认 FAIL（`-AllowStaleTmod` 放行） |

## 验收清单

- [ ] **等待纪律**：全程没有超过 30s 的无进度阻塞；长任务用 job + 短轮询
- [ ] 没有任何命令用管道接驱动（`| tail` 一类）
## 验收清单（原）

- [ ] `preflight-client.ps1` PASS（L2 前）
- [ ] `tml.ps1 -Detach` 起会话 → `session.ps1 -Action Status` 显示 pid/端口/心跳
- [ ] `session.ps1 -Action Run -Commands 's:ping' -Expect ping` ≤2.5s
- [ ] suite 4 条全 PASS，输出矩阵含每条耗时
- [ ] `suites.ps1 -Parallel 2` 两个 L1 suite 并行、端口不冲突
- [ ] `-Client` 时 `suites.ps1` 打印串行告警
- [ ] recipe 未知名字 → 退出码 1 且列出可用项
- [ ] 回归：demo-l1 / assert-demo / l2-interaction 三个 suite 全 PASS
## 验收清单（旧）

- [ ] L1 一轮通过，`result-*.txt` 无 FAIL、无缺失用例
- [ ] `diag` 里 tick 在增长（证明世界真的在跑，不是"进程活着"）
- [ ] 需要画面时 L2 出图，且图里能看到本次改动
- [ ] 测试角色配置生效：god 不许掉血、锁血不许死
- [ ] 没有残留进程（驱动按 PID 收尸）、没有写玩家自己的 `Mods` 与存档
