# 04b. API 速查 · ModSystem / ModPlayer / Global* / 合成配方

> §4.7–4.10。索引与通用原则见 `04-api-cheatsheet.md`。

## 4.7 ModSystem（游戏系统）

```csharp
public class MySystem : ModSystem
{
    public override void Load() { }                    // 模组加载（注册事件/静态初始化）
    public override void Unload() { }                  // 卸载（清静态字段）
    public override void PostUpdateWorld() { }         // 每 tick 世界更新后
    public override void PostUpdatePlayers() { }       // 每 tick 玩家更新后
    public override void PostUpdateEverything() { }
    public override void PreWorldGen() { }             // 世界生成前
    public override void PostWorldGen() { }            // 世界生成后
    public override void NetSend(BinaryWriter writer) { }   // 世界数据同步到新玩家
    public override void NetReceive(BinaryReader reader) { }

    // —— 世界持久化（跨会话，写入世界档案）——
    public override void SaveWorldData(TagCompound tag) { }
    public override void LoadWorldData(TagCompound tag) { }   // 与 SaveWorldData 成对覆写（MustOverrideTogether）
    public override void SaveWorldHeader(TagCompound tag) { } // 世界列表 UI 可读的小数据量头信息

    // 注意：NetSend/NetReceive ≠ 存档。NetSend 仅服务端在 WorldData 消息时调用
    //（Boss 击败/新一天/玩家加入），不是持续同步通道；跨会话保存必须走 SaveWorldData/LoadWorldData。
}
```

## 4.8 ModPlayer（玩家扩展）

```csharp
public class MyPlayer : ModPlayer
{
    public int Charges;                               // 玩家状态字段
    public override void UpdateEquips() { }           // 每 tick 装备/饰品效果
    public override void ModifyHitNPC(NPC target, ref NPC.HitModifiers modifiers) { }
    public override void OnHitNPC(NPC target, NPC.HitInfo hit, int damageDone) { }
    public override void ModifyHitByNPC(NPC npc, ref Player.HurtModifiers modifiers) { }
    public override void OnHurt(Player.HurtInfo info) { }
    public override void UpdateDead() { }             // 死亡状态重置字段
}
// 使用：player.GetModPlayer<MyPlayer>().Charges += 1;
```

## 4.9 Global*（对所有对象全局挂钩）

| 类 | 作用 | 例 |
|---|---|---|
| `GlobalItem` | 所有物品 | `AppliesToEntity(Item, bool lateInstantiation)`、`UpdateInventory(Item, Player)`、`ModifyTooltips(Item, List<TooltipLine>)` |
| `GlobalNPC` | 所有 NPC | `OnHitByItem/OnHitByProjectile`、`ModifyNPCLoot(NPC, NPCLoot)`、`OnKill` |
| `GlobalProjectile` | 所有弹幕 | `OnHitNPC(Projectile, NPC, ...)` |
| `GlobalTile` | 所有方块 | `RightClick(int i, int j)`、`ModifyLight` |
| `GlobalBuff` | 所有增益 | `Update(Player, ref int buffIndex)` |

多人相关：`SaveData/LoadData` 与 `NetSend/NetReceive` 字段集必须对称；命中类钩子的双端触发语义见 `06-netcode-sync.md` §6.5/§6.6。

## 4.10 合成配方（Recipe）

> 注意：`Recipe.Create` 只能在配方相关方法里调用 —— `ModItem.AddRecipes()`、`ModSystem.AddRecipes()`、`GlobalItem.AddRecipes()`。放进 `Load()` / `Update` 等会抛 `RecipeException: A Recipe can only be created inside recipe related methods` 并禁用模组。

```csharp
// 写在 ModItem.AddRecipes() 或 ModSystem（静态）里
Recipe.Create(ModContent.ItemType<MyItem>())
    .AddIngredient(ItemID.Wood, 10)
    .AddIngredient(ModContent.ItemType<OtherItem>(), 2)
    .AddIngredient(ItemID.IronBar, 3)
    .AddTile(TileID.WorkBenches)
    .AddCondition(Condition.InGraveyardBiome()) // 可选条件
    .Register();
```
