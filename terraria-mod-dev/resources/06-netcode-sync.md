# 06. 多人同步（Netcode）要点

## 6.1 铁律

只有**服务端**应该直接修改世界状态（NPC/方块/世界数据）；客户端想改世界必须先发请求，服务端广播结果。纯客户端表现（特效、音效、HUD）随意。

## 6.2 四种同步手段

| 手段 | 场景 |
|---|---|
| `ModSystem.NetSend/NetReceive` | 世界级数据：新玩家加入时同步全量（每局状态） |
| `ModPlayer` + `SendClientChanges`/`SyncPlayer` | 玩家级数据 |
| `ModPacket`（自定义消息） | 任意即时事件：伤害、开关、计数 |
| `ModSystem.SaveWorldData/LoadWorldData` | 世界持久化（跨会话），与网络同步是两回事 |

## 6.3 自定义消息（ModPacket）

```csharp
// 发送（任意端，服务端可广播）
if (Main.netMode == NetmodeID.MultiplayerClient)
{
    ModPacket p = Mod.GetPacket();   // 在 Mod 子类或 ModSystem 里
    p.Write((byte)MyMessageType.DoSomething);
    p.Write(targetIndex);
    p.Write(amount);
    p.Send();                        // 客户端 → 服务端；服务端转发用 p.Send(ignoreClient: -1)
}

// 接收（在 Mod 类里）
public override void HandlePacket(BinaryReader reader, int whoAmI)
{
    var type = reader.ReadByte();
    switch (type)
    {
        case (byte)MyMessageType.DoSomething:
            int i = reader.ReadInt32();
            int amt = reader.ReadInt32();
            // 服务端验证后改世界，并广播
            break;
    }
}
```

> `HandlePacket` 收包方向与 whoAmI 陷阱见 §6.6。

## 6.4 常用 NetmodeID / NetMessage

- `Main.netMode`：`NetmodeID.Server`（-2，服务端）、`NetmodeID.SinglePlayer`（0）、`NetmodeID.MultiplayerClient`（1）。
- 服务端专属逻辑：`if (Main.netMode == NetmodeID.Server) { ... }`。
- 客户端发送：`if (Main.netMode == NetmodeID.MultiplayerClient) { ... }`。
- `NetMessage.SendData(...)`：复用原版消息通道（如 `MessageID.DamageNPC`）。

## 6.5 陷阱

- 忘写 `if (Main.netMode == NetmodeID.Server)` 保护 → 客户端也执行服务端逻辑，造成双写。
- 自定义字段没同步（如 ModPlayer 计数值只本地改）→ 别人看不到。
- 用 `BinaryWriter/BinaryReader` 读写顺序必须严格一致。
- `HandlePacket` 里别信任客户端输入，先校验。
- `GlobalItem/GlobalNPC` 的 `SaveData/LoadData` 与 `NetSend/NetReceive` **字段集必须对称**——漏字段会让对端拿到默认值（如基础价值缓存归零后再套倍率就错账）。
- ⚠️ 1.4.4 起 `OnHitNPC` 类命中钩子在**服务端与所属玩家的客户端**都会触发（经验结论，以实测为准）：产生真实伤害/生成弹幕/上 buff 的逻辑要加 `if (Main.netMode == NetmodeID.MultiplayerClient) return;` 或收归服务端执行。

## 6.6 HandlePacket 的 whoAmI 方向（高频翻车点）

- 服务端收到"玩家发来"的包：`whoAmI` = 发送者玩家下标（0..maxPlayers-1）。
- 客户端收到"服务端下发"的包：`whoAmI` = 哨兵值 **256**（官方注释原文："For clients it will always be 256, the server"；合法玩家下标只有 0..254，`Main.maxPlayers = 255`）。
- 推论：
  - 下行广播要把目标玩家写进包体，接收端从包体读 target，不要用 whoAmI 定位；
  - `if (whoAmI < 0 || whoAmI >= Main.maxPlayers) return;` 这类守卫会把全部服务端下行包拦掉（256 ≥ 255 必中）——典型症状："命令改了货币/状态，客户端永远不刷新"。
- 方向速记：上行包（客户端→服务端）用 whoAmI；下行包（服务端→客户端）用包体 target。

## 6.7 ModPlayer 玩家数据三件套（客户端权威模式）

- `SyncPlayer(toWho, fromWho, newPlayer)`：玩家加入时全量上报；
- `CopyClientState(targetCopy)`：生成当前值快照；
- `SendClientChanges(clientPlayer)`：每 tick 与快照比对，有变化才发包；
- 注意：此模式默认**客户端权威**——服务端改的值若不回推，会被客户端旧快照反向覆盖；服务端权威数值（货币等）需要额外的下行广播通道（见 §6.6）。
