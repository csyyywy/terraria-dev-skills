# 06. 多人同步（Netcode）要点

## 6.1 基本原则

世界状态（NPC/方块/世界数据）只由服务端直接修改：客户端要改世界必须先发请求，服务端执行后广播结果。纯客户端表现（特效、音效、HUD）不受此限。

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

> `HandlePacket` 的收包方向与 whoAmI 见 §6.6。

## 6.4 常用 NetmodeID / NetMessage

- `Main.netMode`：`NetmodeID.Server`（-2，服务端）、`NetmodeID.SinglePlayer`（0）、`NetmodeID.MultiplayerClient`（1）；服务端专属逻辑用 `if (Main.netMode == NetmodeID.Server)`，客户端发送用 `if (Main.netMode == NetmodeID.MultiplayerClient)`。
- `NetMessage.SendData(...)`：复用原版消息通道（如 `MessageID.DamageNPC`）。

## 6.5 陷阱

- 缺 `if (Main.netMode == NetmodeID.Server)` 保护 → 客户端也执行服务端逻辑造成双写；自定义字段未同步（如 ModPlayer 计数值只本地改）→ 别人看不到。
- `BinaryWriter/BinaryReader` 的读写顺序必须严格一致；`HandlePacket` 里先校验，不信任客户端输入。
- `GlobalItem/GlobalNPC` 的 `SaveData/LoadData` 与 `NetSend/NetReceive` 字段集必须对称——漏字段会让对端拿到默认值（如基础价值缓存归零后再套倍率就错账）。
- 1.4.4 起 `OnHitNPC` 类命中钩子在服务端与所属玩家的客户端都会触发：产生真实伤害/生成弹幕/上 buff 的逻辑要加 `if (Main.netMode == NetmodeID.MultiplayerClient) return;` 或收归服务端执行。

## 6.6 HandlePacket 的 whoAmI 方向

- 服务端收到玩家发来的包：`whoAmI` = 发送者玩家下标（0..maxPlayers-1）。客户端收到服务端下发的包：`whoAmI` = 哨兵值 **256**（官方注释："For clients it will always be 256, the server"；合法下标只有 0..254，`Main.maxPlayers = 255`）。
- 下行广播（服务端→客户端）把目标玩家写进包体，接收端从包体读 target，不要用 whoAmI 定位；上行包（客户端→服务端）才用 whoAmI。
- `if (whoAmI < 0 || whoAmI >= Main.maxPlayers) return;` 这类守卫会拦掉全部下行包（256 ≥ 255 必中），症状是"命令改了货币/状态，客户端永不刷新"。

## 6.7 NetSend 不是存档

注意：`NetSend/NetReceive` 只在世界数据消息触发时调用（Boss 死、新玩家加入、新的一天），不跨会话；玩家重进后 `static` 字段已被 `Unload()` 清空，进度全丢。

```csharp
// 只写了这一对 → 打完 Boss 退出重进，旗标归零、城镇 NPC 不再入住、配方条件失效
public override void NetSend(BinaryWriter w) { ... }
public override void NetReceive(BinaryReader r) { ... }

// 必须补这一对（跨会话持久化）
public override void SaveWorldData(TagCompound tag) { ... }
public override void LoadWorldData(TagCompound tag) { ... }
```

- 多值用 `List<string>` 记旗标名，比一排 bool 好扩展：

  ```csharp
  var downed = new List<string>();
  if (DownedA) downed.Add("a");
  tag["downedX"] = downed;
  // 读：tag.TryGet("downedX", out List<string> downed)
  ```

- `TagCompound.TryGet<T>(key, out T)` 缺键时不造默认对象，适合"缺失即视为未击败"；`Get<T>` 会抛或造默认值。
- 自检：每个「跨会话应记住」的 static 字段都要在 `SaveWorldData`/`LoadWorldData` 里出现。`Unload()` 只清运行时状态——把 `Completed` 转发给持久化字段又在 `Unload()` 里置 false，等于退出时抹掉存档。

## 6.8 进度旗标被"复用 Boss"污染

借用真 Boss NPC 做事件/入侵的强化版时留意：那些 Boss 的 `OnKill` 会无条件点亮进度旗标；事件没有前置门槛，玩家就能靠事件白送进度。

```csharp
// GlobalNPC 上打标记
public class MyInvasionNPC : GlobalNPC {
    public override bool InstancePerEntity => true;
    public bool InInvasion;
    public static bool IsInvasionSpawn(NPC npc) =>
        npc.active && npc.TryGetGlobalNPC(out MyInvasionNPC g) && g.InInvasion;
}

// Boss 的 OnKill 首行拦截（只拦进度，掉落照常）
if (MyInvasionNPC.IsInvasionSpawn(NPC)) return;
```

## 6.9 ModPlayer 玩家数据三件套（客户端权威模式）

- 三件套：`SyncPlayer(toWho, fromWho, newPlayer)` 加入时全量上报；`CopyClientState(targetCopy)` 生成当前值快照；`SendClientChanges(clientPlayer)` 每 tick 与快照比对，有变化才发包。
- 默认客户端权威：服务端改的值不回推会被客户端旧快照反向覆盖；服务端权威数值（货币等）需要额外的下行广播通道（见 §6.6）。
