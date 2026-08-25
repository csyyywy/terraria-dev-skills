# 04c. API 速查 · ID 枚举 / DamageClass / 常用辅助

> 属 04 分册家族（原 §4.11–4.14）；索引与通用原则见 `04-api-cheatsheet.md`。

## 4.11 常用 ID 枚举（Terraria.ID）

| 枚举 | 用途 | 例子 |
|---|---|---|
| `ItemUseStyleID` | 使用动作 | `Swing, Shoot, Eating, HoldUp` |
| `ItemRarityID` | 稀有度 | `White, Blue, Green, Orange, Red, Pink, Cyan, Purple` |
| `TileID` | 方块 ID | `WorkBenches, Furnaces, Anvils, DemonAltar` |
| `ProjectileID` | 弹幕 ID | `Bullet, Fireball, ...` |
| `NPCID` | NPC ID | `Zombie, Guide, ...` |
| `BuffID` | 增益 ID | `Poisoned, OnFire, ...` |
| `SoundID` | 音效 | `Item1, Item2, NPCHit1, NPCDeath1, Tink` |
| `DustID` | 粒子 | `Stone, Wood, Fire, Gold` |
| `ItemID` | 物品 ID | `Wood, StoneBlock, IronBar, PlatinumCoin` |
| `DamageClass` | 伤害类型 | `Melee, Ranged, Magic, Summon, Generic` |

## 4.12 伤害类型（DamageClass）

⚠️ **本版本（1.4.4 / 2026.x）自定义 DamageClass 是自动注册的**，`DamageClassLoader.AddDamageClass` 已移除（仅剩 GetDamageClass）。子类即注册，无需 SetStaticDefaults 手动注册。

```csharp
public class ExampleDamageClass : DamageClass
{
    // 不继承任何原版伤害类型的修饰符；也可按需覆盖 GetEffectInheritance / GetPrefixInheritance / SetDefaultStats
    public override StatInheritanceData GetModifierInheritance(DamageClass damageClass)
        => new StatInheritanceData();
}
// 使用：Item.DamageType = ModContent.GetInstance<ExampleDamageClass>();
```

## 4.13 常用辅助

- `Main.rand`：随机数（`Main.rand.Next(min, max)`）。
- `Main.LocalPlayer`：本地玩家。
- `Dust.NewDust(pos, w, h, DustID.X)` / `Dust.NewDustPerfect(pos, DustID.X, velocity)`：粒子。
- `Gore.NewGore(...)`、`CombatText.NewText(...)`：战斗文字。
- `Projectile.NewProjectile(source, pos, vel, type, damage, knockBack, owner)`：发射弹幕。
- `NPC.NewNPC(...)`：生成 NPC。
- `TileEntity`：方块实体（复杂逻辑用）。
- `ModCommand`：聊天命令（`[Autoload] public class X : ModCommand { ... }`）。

- `Player.QuickSpawnItem` 双重载，语义不同：
  - `(source, int type, int stack = 1)`：按类型**新建**物品（不带实例上的全局数据）；
  - `(source, Item item, int stack = 1)`：**克隆**传入实例（保留 GlobalItem 词缀等实例数据，官方注释 "clones it… retain item infos"），但 `stack` 参数会**覆盖**克隆出的堆叠；
  - `*Direct` 变体返回生成的 `Main.item[index]`。给带词缀/mod 数据的装备发物品务必用 Item 重载并传对 stack。

`Player.armor` 槽位布局（扫描装备效果/套装计数时跳过社交槽；染料存于独立的 `Player.dye[]` 数组）：

| 下标 | 含义 |
|---|---|
| 0-2 | 头/胸/腿 |
| 3-8 | 饰品（8 = 恶魔之心扩展位） |
| 9 | 大师模式第 6 饰品位 |
| 10-19 | 时装（社交）槽 |

> 边界数值建议落码前对照本机源码/wiki 复核（尤其扩展位的开启条件）。

## 4.14 终局/月亮领主材料 ID 对照（本机编译验证，2026-08）

| 易记错的名字（不存在） | 正确的常量 |
|---|---|
| ~~LuminiteBar~~ | `ItemID.LunarBar`（夜明锭） |
| ~~SolarFragment / VortexFragment / NebulaFragment / StardustFragment~~ | `ItemID.FragmentSolar` / `FragmentVortex` / `FragmentNebula` / `FragmentStardust` |
| BrokenHeroSword | `ItemID.BrokenHeroSword`（存在） |
| ~~TileID.AncientManipulator~~ | `TileID.LunarCraftingStation`（远古操纵机） |
| 其它可用 | `ItemID.LunarTabletFragment`、`ItemID.CelestialSigil` |

稀有度：**不存在 `ItemRarityID.Rainbow`**；终局用 `ItemRarityID.Purple`(10)。`LightPurple/Pink/Cyan/Orange/Lime/Yellow/Expert` 均存在。
合成站：远古操纵机 = `TileID.LunarCraftingStation`；秘银/山铜砧 = `TileID.MythrilAnvil`；铁/铅砧 = `TileID.Anvils`。
