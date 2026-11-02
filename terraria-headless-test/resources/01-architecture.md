# 01. 为什么这样设计

## 两条硬约束

**泰拉瑞亚没有无头单人模式。** `-join -player -skipselect` 会停在主菜单；单人世界必须由界面流程进入。

**空专用服务器不运行世界。** tModLoader 的服务端主循环是：

```
Main.DedServ_PostModLoad:
  IL_0dbe  ldsfld  Terraria.Netplay::HasClients
  IL_0dc3  brfalse.s <跳过>
  IL_0dcb  callvirt Microsoft.Xna.Framework.Game::Update(GameTime)
  IL_0de8  ldsfld  Terraria.Main::OnTickForThirdPartySoftwareOnly
  IL_0def  callvirt Action::Invoke()          // 无论有没有客户端都每圈调用
```

`HasClients` 的来源：

```
Netplay.UpdateConnectedClients:  HasClients = Σ RemoteClient.IsConnected()
RemoteClient.IsConnected():      Socket != null && Socket.IsConnected()
```

结论：给任意一个 `RemoteClient` 槽位装上假的 `ISocket`（`IsConnected()` 恒真），
`HasClients` 即为真，服务端开始正常跑 `Main.Update` —— 无窗口、无 GPU、无第二个进程。
实现见 `bridge/HeadlessLink.cs`，安装时机用 `Main.OnTickForThirdPartySoftwareOnly`
（空服务器里唯一每圈必调的钩子）。

## 两级方案各自能证明什么

| 验证对象 | L1 服务端 | L2 +客户端 |
|---|---|---|
| 加载期崩溃、注册、配方 | ✅ | ✅ |
| 世界生成、存档往返、液体、生长 | ✅ | ✅ |
| NPC / 弹幕 / 掉落物的逻辑与数值 | ✅（需自行放置玩家或对象） | ✅ |
| 玩家行为（移动、受伤、死亡、buff） | ⚠️ 需合成玩家 | ✅ |
| 绘制、UI、特效、贴图 | ❌ | ✅ |
| 双端一致性（同步 bug） | ❌ | ✅（两侧各算各的，可对比） |

## 为什么不直接只用客户端

客户端启动要经过模组加载、Steam 检测与世界连接，单轮 25–35 秒，且会抢占前台窗口。
既然绝大多数逻辑 bug 在服务端就能暴露，默认走 L1；只有像素相关才升到 L2。

## 安全边界

桥是惰性的：没有环境变量 `TMLKIT_ROOT` 就完全不工作。发布版带着这些源码不会自己动。
