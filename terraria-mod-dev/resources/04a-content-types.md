# 04a. API 速查 · 内容类型（ModItem / ModNPC / ModProjectile / ModTile / ModBuff）

> §4.1–4.6。索引与通用原则见 `04-api-cheatsheet.md`。

## 4.1 类型获取（注册是隐式的，只需拿到类型 ID / 实例）

```csharp
using Terraria.ModLoader;

ModContent.ItemType<MyItem>()          // 物品类型 int
ModContent.NPCType<MyNPC>()            // NPC 类型 int
ModContent.TileType<MyTile>()          // 方块类型 int
ModContent.ProjectileType<MyProj>()    // 弹幕类型 int
ModContent.BuffType<MyBuff>()          // 增益类型 int
ModContent.GetInstance<MySystem>()     // ModSystem / ModPlayer 等单例实例
ModContent.Find<ModItem>("MyItem")     // 按名查找（跨模组）
```

## 4.2 ModItem（物品/武器/饰品/护甲）

`SetDefaults()` 常用属性：

| 属性 | 说明 | 例子 |
|---|---|---|
| `Item.width / height` | 碰撞盒（像素） | 20 / 20 |
| `Item.maxStack` | 最大堆叠 | 999 |
| `Item.value` | 价值（铜币） | 100 |
| `Item.rare` | 稀有度颜色 | `ItemRarityID.Blue` |
| `Item.useStyle` | 使用动作 | `ItemUseStyleID.Swing` / `.Shoot` |
| `Item.useTime / useAnimation` | 使用间隔/动画（tick） | 20 / 20 |
| `Item.autoReuse` | 按住连用 | true |
| `Item.consumable` | 消耗品 | true |
| `Item.useTurn` | 使用时可转身 | true |
| `Item.shoot` | 发射的弹幕类型 | `ModContent.ProjectileType<MyProj>()` |
| `Item.shootSpeed` | 弹幕初速 | 10f |
| `Item.damage` | 武器伤害 | 50 |
| `Item.knockBack` | 击退 | 5f |
| `Item.DamageType` | 伤害类型 | `DamageClass.Melee` / `.Ranged` / `.Magic` / `.Summon` |
| `Item.noMelee` | 近战挥击不打到实体（远程武器用） | true |
| `Item.UseSound` | 使用音效 | `SoundID.Item1` |
| `Item.createTile` | 放置成的方块 | `ModContent.TileType<MyTile>()` |
| `Item.placeStyle` | 放置变体 | 0 |
| `Item.defense` | 护甲防御 | 5 |
| `Item.accessory` | 是否饰品 | true |
| `Item.crit` | 暴击率加成% | 4 |

常用钩子：`SetStaticDefaults()`（静态设置）、`AddRecipes()`（配方）、`UpdateAccessory(Player, bool hideVisual)`（饰品效果）、`HoldItem(Player)`、`OnHitNPC(Player, NPC, NPC.HitInfo, int damageDone)`。

```csharp
public override void SetDefaults()
{
    Item.width = 20; Item.height = 20;
    Item.useStyle = ItemUseStyleID.Swing;
    Item.useTime = 20; Item.useAnimation = 20;
    Item.autoReuse = true;
    Item.maxStack = 999; Item.value = 100;
    Item.rare = ItemRarityID.Blue;
}
```

## 4.3 ModNPC（怪物/城镇 NPC/Boss）

`SetDefaults()` 常用属性：`NPC.width/height`、`NPC.damage`、`NPC.defense`、`NPC.lifeMax`、`NPC.knockBackResist`、`NPC.aiStyle`（或手写 AI）、`NPC.value`、`NPC.boss`（Boss 掉落条）、`NPC.friendly`（城镇 NPC）、`NPC.townNPC`、`NPC.HitSound`、`NPC.DeathSound`、`NPC.lavaImmune` 等。

常用钩子：`SetStaticDefaults()`（`NPCDebuffImmunityData`、`NPCID.Sets`）、`AI()`（每 tick 逻辑）、`FindFrame(int frameHeight)`、`OnSpawn`、`CanHitPlayer/CanBeHitByItem`、`ModifyNPCLoot(NPCLoot)`（掉落）、`Chat`（城镇对话）、`SpawnChance` + `OnSpawn`（自然生成）、`Bestiary`。

```csharp
public override void SetDefaults()
{
    NPC.width = 30; NPC.height = 30;
    NPC.damage = 20; NPC.defense = 5;
    NPC.lifeMax = 200; NPC.knockBackResist = 0.5f;
    NPC.HitSound = SoundID.NPCHit1;
    NPC.DeathSound = SoundID.NPCDeath1;
    NPC.value = 500f;
}

public override void AI()
{
    NPC.velocity.X = MathF.Cos(NPC.ai[0] += 0.05f) * 2f; // 简单左右摆动
}
```

> 城镇 NPC 商店用 §4.16 的 `AddShops` / `NPCShop`；`SetupShop` 已移除。

## 4.4 ModProjectile（弹幕）

`SetDefaults()`：`Projectile.width/height`、`Projectile.friendly`（友方）、`Projectile.hostile`（敌方）、`Projectile.damage`、`Projectile.penetrate`（穿透，-1 无限）、`Projectile.tileCollide`（撞墙）、`Projectile.ignoreWater`、`Projectile.light`、`Projectile.timeLeft`、`Projectile.aiStyle`（或用 `ai[0]/ai[1]` 手写状态）、`Projectile.DamageType`。

常用钩子：`AI()`（运动/碰撞逻辑）、`OnHitNPC(NPC, NPC.HitInfo, int damageDone)`、`Kill(int timeLeft)`（爆炸/生成特效）、`OnKill`、`DrawColor(Color, Color)`、`ShouldUpdatePosition`。

```csharp
public override void SetDefaults()
{
    Projectile.width = 12; Projectile.height = 12;
    Projectile.friendly = true;
    Projectile.penetrate = 3;
    Projectile.timeLeft = 300;
    Projectile.DamageType = DamageClass.Magic;
    Projectile.aiStyle = 1; // 标准直飞
}
```

## 4.5 ModTile（方块）

`SetStaticDefaults()`：`Main.tileSolid[Type] = true`、`Main.tileBlockLight[Type]`、`Main.tileLighted`、`TileID.Sets.*`、`AddMapEntry(new Color(...), CreateMapEntryName())`、`HitSound`、`DustType`、`MinPick`（挖掘力）、`MineResist`、`AdjTiles = new int[] { TileID.WorkBenches }`。

`SetDefaults()`：`TileObjectData.newTile.CopyFrom(TileObjectData.Style1x1)` 等（尺寸/锚点），然后 `TileObjectData.addTile(Type)`。

常用钩子：`ModifyLight(int i, int j, ref float r, ref float g, ref float b)`、`RandomUpdate(int i, int j)`、`KillTile(int i, int j, ref bool fail, ref bool effectOnly, ref bool noItem)`、`AnimateTile()`、`TileFrame(int i, int j, ref bool resetFrame, ref bool noBreak)`。

```csharp
public override void SetStaticDefaults()
{
    Main.tileSolid[Type] = true;
    Main.tileBlockLight[Type] = true;
    Main.tileLighted[Type] = true;
    AddMapEntry(new Color(100, 100, 200));
    DustType = DustID.Stone;
    HitSound = SoundID.Tink;
    MinPick = 65;
    MineResist = 2f;
    TileObjectData.newTile.CopyFrom(TileObjectData.Style1x1);
    TileObjectData.addTile(Type);
}
```

## 4.6 ModBuff（增益/减益）

`SetStaticDefaults()`：`Main.debuff[Type]`（是否减益）、`Main.buffNoTimeDisplay[Type]`、`Main.persistentBuff[Type]`、`Main.buffNoSave[Type]`、`BuffID.Sets.*`。名称/描述走 `Localization`（BuffName / BuffDescription）。

`Update(Player player, ref int buffIndex)`（对玩家）、`Update(NPC npc, ref int buffIndex)`（对 NPC）。
