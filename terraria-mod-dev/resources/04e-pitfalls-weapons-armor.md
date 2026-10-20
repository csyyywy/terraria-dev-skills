# 04e. 实战踩坑 · 武器 / 弹幕 / 护甲套装

> 属 04 分册家族，§4.17–4.21；索引见 `04-api-cheatsheet.md`。

## 4.17 武器与弹幕

**鞭子**
- `Item.DefaultToWhip(proj, dmg, kb, shootSpeed, animationTotalTime)`：第 5 参是**动画总时长，不是射程**；长度只由 `shootSpeed` 决定（T1=4 → T2=5 → T3=6，每阶 +1）。该调用还会置 `autoReuse = false`，T2 起要自动攻击须逐把手写 `Item.autoReuse = true`。
- 弹幕侧：`SetStaticDefaults` 置 `ProjectileID.Sets.IsAWhip[Type] = true`，`SetDefaults` 调 `Projectile.DefaultToWhip()`。后者已设 `aiStyle = 165`、`usesLocalNPCImmunity = true`、`localNPCHitCooldown = -1`，且 `AI_165_Whip` 命中时自动执行 `Main.player[owner].MinionAttackTargetNPC = i`——标记目标、仆从集火、同一目标只结算一次都是自动的（反编译 `Terraria.Projectile` 实证），勿重复实现。
- ❌ 自我衰减：`OnHitNPC` 里 `Projectile.damage = (int)(Projectile.damage * 0.8f)` 每次命中永久降伤，群怪时伤害迅速归底。多目标递减用 `usesLocalNPCImmunity` 或自建冷却，不要动 `Projectile.damage`。
- 多把鞭子差异化：`WhipBase : ModProjectile` 暴露 `DebuffType / DebuffTime / TipDamageMultiplier / ApplySummonCurse` 等虚属性，子类只填数值。鞭梢判定用 `Projectile.WhipPointsForCollision` + `Projectile.FillWhipControlPoints(proj, list)` 取真实控制点，看命中点是否落在后 1/3，不要用 `ai[0]` / `timeLeft` 估。

**段身虫**
基准实现 = 原版毁灭者：`realLife` + `ai[0]` / `ai[1]` 双向链。引擎行为（反编译 `Terraria.NPC` 实证）：

| 引擎行为 | 源码位置 |
|---|---|
| 伤害汇聚到 `Main.npc[realLife]`，回写本段 life / lifeMax | `npc.cs` Hitting 分支 `Main.npc[realLife].life -= (int)num` |
| `realLife != -1` 时 `GetLifeStats()` 读头部 → 顶部血条显示总血池 | `npc.GetLifeStats` |
| `checkDead()` 首行 `if (realLife >= 0 && realLife != whoAmI) return;` → 段位永不自行判死 | `npc.checkDead` |

- 搭法：头部 `realLife` = 自身 `whoAmI`、`lifeMax` = 总血池；体 / 尾 `realLife` = 头部 `whoAmI`、`ai[0]` = 后继、`ai[1]` = 前驱；段 AI 只跟 `ai[1]`，不要各自 `TargetClosest`；前驱死亡照原版写 `NPC.life = 0; NPC.checkDead();`；身 / 尾置 `NPC.dontCountMe = true`，全段消失后再置击杀旗标。
- ❌ 手动镜像伤害（`HitEffect` 里 `head.life -= hit.Damage`）绕过原版伤害系统 → 不吃暴击 / 减伤，`playerInteraction`、`GetWereThereAnyInteractions()` 失真，客户端血条不同步。
- 「头死全死」是期望行为，弃用 `realLife` 换来的正是上面这串问题。

**命中附加减益**
- `GlobalItem.OnHitNPC` 只覆盖直接武器命中；远程 / 魔法 / 召唤 / 剑气等弹幕须另写 `GlobalProjectile.OnHitNPC`。用 `item.ModItem?.Mod == Mod` / `projectile.ModProjectile?.Mod == Mod` 限定本模组，避免波及原版。
- 减益里不要 `npc.defense -= X`：`ModBuff.Update` 每帧执行会无限叠加 → 防御转负 → 伤害爆炸。DoT 只做 `npc.life -= X` + 微粒，降防改走命中时一次性扣等其它机制。

**范围爆炸**
Projectile 没有 `ExpandHitboxBy`（CS1061）。记 `center`，放大 `width` / `height`（如 56），`position = center - new Vector2(28, 28)`，再 `maxPenetrate = -1; penetrate = -1;` 调 `Projectile.Damage()`；配 `SoundEngine.PlaySound(SoundID.Item14, Center)` 与粒子。

## 4.18 护甲套装与武器补遗

**护甲套装**
- `IsArmorSet(Item head, Item body, Item legs)` 判成套，`UpdateArmorSet(Player)` 给加成，`player.setBonus = Language.GetTextValue("Mods.<Mod>.SetBonus.<Name>")` 设 Tooltip；文案须与 `UpdateArmorSet` 数值同步（改数值忘改 hjson 即不同步）。
- 职业头饰：同一胸甲 + 护腿配 4 个职业头饰（近战 / 远程 / 魔法 / 召唤），防御 召唤 < 魔法 < 远程 < 近战；`_Head` / `_Body` / `_Legs` 尺寸见 `11-armor-textures.md`。

**类名 = 命名空间陷阱**：主类与命名空间同名时，`<ModName>.Content.X` 解析到类 → CS0426；改写 `Content.X` 或 `global::<ModName>.Content.X`。

**`ModItem.Shoot` + `return false`**：`Item.shoot` 必须保留，去掉后 Shoot 钩子可能不触发；远程 / 近战发射类须让 shoot 指向弹幕类型。

**引导弹落点随鼠标**：`ModItem.Shoot` 读 `Main.MouseWorld`，经 `NewProjectile` 的 ai0 / ai1（绝对世界坐标）传给弹幕，弹幕读 `ai[0]` / `ai[1]`；单机 / 多人通用，避免服务端无鼠标。

**全屏 AoE**：巨大友方命中盒（如 1600×1600）+ `usesLocalNPCImmunity = true` + 大于弹幕存活时长的 `localNPCHitCooldown` → 每敌只结算一次。

**其它弹幕技巧**：敌对弹幕可打掉——AI 里遍历 `Main.ActiveProjectiles`，与友方弹幕重叠则 `Projectile.Kill()`；友方弹幕「穿透 + 命中即爆炸」用 `penetrate = -1` + `OnHitNPC` 里 `Projectile.Kill()`（触发 OnKill 爆炸）。

**useAmmo + 自订弹**
- useAmmo 会让**弹药弹幕覆盖 `Item.shoot`**，可能打出弹药弹幕、吃不到本模组 `GlobalProjectile` 减益；无需消耗弹药就直接去掉 useAmmo。
- `PickAmmo` 挂在**弹药**上而非武器上（`ItemLoader.PickAmmo` 调 `ammo.ModItem?.PickAmmo(...)`），武器侧覆写不生效。
- ✅ 武器侧改用 `ModItem.ModifyShootStats(Player, ref Vector2 position, ref Vector2 velocity, ref int type, ref int damage, ref float knockback)`（`type` 是 ref）：`type = ModContent.ProjectileType<自订弹>()` → 消耗弹药 + 永远发射自订弹。tML 1.4.4 的 `ModItem.Shoot(Player, EntitySource_ItemUse_WithAmmo, Vector2, Vector2, int, int, float)` 参数非 ref，改不了 type。

**ModConfig 默认值被玩家配置覆盖**：要「默认开启」须移除运行时闸门，只改默认值无效（旧配置里的 false 会盖掉）。也别做死配置：有 `[Range]` / `[Slider]` 与 hjson `Label` / `Tooltip` 却无人读取（只在 `/cmd` 打印里出现）即假开关；自检 `grep -rn "配置属性名"` 必须搜到读取点。

## 4.20 Boss 朝向：贴图形态决定 AI

**症状**：玩家站到 Boss 左侧，整只 Boss 倒转贴地飞。

**根因**：AI 末尾的 `NPC.rotation = dir.ToRotation();` 只适用于旋转对称贴图（悬浮球体 / 眼球 / 陨石）；直立人形 / 兽形（有腿、有臂、面朝一侧）按速度方向转就整个翻过来。判定：有明确「上下」→ 直立型，圆 / 球 / 无方向性 → 对称型，拿不准把 PNG 放大 3–8 倍用 `NearestNeighbor` 看。

**直立型修法**：
```csharp
NPC.rotation = 0f;                                              // 保持直立，绝不跟速度转
NPC.spriteDirection = NPC.direction = target.Center.X > NPC.Center.X ? 1 : -1;  // 左右翻转
```
- 要飞就保留 `noGravity` / `noTileCollide`，只去掉旋转，二者不冲突；对称型（眼球、陨石、法球）保留 `rotation = dir.ToRotation()` 更好看。
- 排查：`grep -rn "NPC.rotation = " --include=*.cs Content/NPCs/` 逐个确认贴图无方向性，任何直立造型都要改。`NPC.spriteDirection` 常被整工程漏设（默认恒 1 → Boss 永远朝右），属「能跑但观感怪」，只能清单式自查。

## 4.21 Boss AI 骨架：朝向只是表面，结构才是病根

朝向修好后仍「不像样」，病因在结构：

| # | 病因 | 自查 |
|---|---|---|
| 1 | 滑冰式移动：`velocity += dir * f` + `ClampVelocity`，无摩擦 / 惯性 | `grep "velocity += dir"` |
| 2 | 技能无方位感，全从 `NPC.Center` 对称扇出 | `grep "NewProjectile.*NPC.Center"` |
| 3 | 零前摇，时间到直接吐弹，无法读招 | 查有无 `scale` / `alpha` / `AddLight` 蓄力表现 |
| 4 | 状态机割裂：技能是独立定时器，与移动脱钩 | 看 `case` 分支与攻击判定是否互相独立 |
| 5 | 多人不同步：随机判定写在双端都会跑的位置 | `grep "Main.rand.NextBool"`，看有没有包服务端守卫 |

### 飞行 Boss 基类

**飞行手感**（「不像在飞」的核心）：
```csharp
// 步进式加速：有重量、有惯性
Vector2 desiredVel = toPoint / dist * maxSpeed;
if (dist < 90f) desiredVel *= dist / 90f;         // 靠近自动减速，防抖
Vector2 delta = desiredVel - NPC.velocity;
if (delta.Length() > accel) delta = Vector2.Normalize(delta) * accel;
NPC.velocity += delta;

// 每帧阻尼 + 低速归零（否则永远有微小抖动）
NPC.velocity *= 0.95f;
if (MathF.Abs(NPC.velocity.X) < 0.02f) NPC.velocity.X = 0f;
```
- 只调 `MaxSpeed` / `Accel` / `Damping` 三个数即可拉开手感：重甲 Accel 0.26–0.34、猎手 0.5+、主宰 0.38 居中。
- 备好机动原语：`HoverAround()`（悬浮呼吸）、`RetreatFrom()`（后撤蓄力）、`Brake()`（出招钉住）。

**前摇（telegraph）——让招式可读可躲**：
```csharp
StartTelegraph(duration, aimDir);   // 膨胀到 1.18× + AddLight + 吸入式粒子
TelegraphProgress                   // 0→1 线性推进（分母必须是总时长，不是剩余值）
```
- 前摇期间跳过阻尼 = Boss「钉」在空中，形成明确读招窗口；出招方向存私有字段，别和子类 localAI 抢槽位（否则召唤标记会被蓄力方向覆盖）。
- 方位感：出弹用 `NPC.Center + dir * forward + 侧向偏移`，不要裸 `NPC.Center`；直立 Boss 这样才像「从手 / 胸 / 口发出」。

### 多人：选招只在服务端
```csharp
static bool IsServerAuthority => Main.netMode != NetmodeID.MultiplayerClient;

bool TickStateTimer(int cooldown) {       // 计时推进 + 掷骰都在服务端
    if (!IsServerAuthority) return false;
    if (++moveTimer < cooldown) return false;
    moveTimer = 0; return true;
}
// 子类：if (TickStateTimer(cd)) { 选招... }
```
让 `RandServer()` 参与选招却漏了计时守卫，客户端会因恒 false **永久停在 Idle**。正确做法：计时 + 掷骰一起只在服务端，客户端靠同步下来的 `ai[]` 跟随状态。

### 震屏（无 `Main.CameraShake`）
```csharp
Main.instance.CameraModifiers.Add(new PunchCameraModifier(
    position, direction, strength, vibrationCyclesPerSecond, frames, distanceFalloff, uniqueId));
```
需 `using Terraria.Graphics.CameraModifiers;`；`Main.netMode == Server` 时跳过（纯客户端表现）。

### 招式设计
- ❌ 多个 Boss 共用「环绕 + 定时扇形弹」模板、只改数字 → 一眼看穿。
- ✅ 按形象设计招牌招式：重甲 → 砸地冲击波；猎手 → 后撤扑击；主宰 → 传送 + 全向新星；且招式要有成本（前摇、僵直）与破绽（冲刺不修正方向 = 可躲）。
