# 04e. 实战踩坑 · 武器/弹幕/护甲套装

> 属 04 分册家族（原 §4.17–4.18）；索引与通用原则见 `04-api-cheatsheet.md`。以下均为实测验证条目。

## 4.17 实战踩坑（2026-08 反馈轮验证）

**鞭子（Whip）**
- `Item.DefaultToWhip(proj, dmg, kb, shootSpeed, animationTotalTime)`：第 5 参是**动画总时长，不是射程**！鞭子长度由 `shootSpeed` 决定（T1=4 → T2=5 → T3=6 逐阶 +1 即可）。
- `DefaultToWhip` 会设 `autoReuse=false`：想让 T2+ 鞭子自动攻击，必须**手动 `Item.autoReuse = true`**。
- 鞭子弹幕：SetStaticDefaults 设 `ProjectileID.Sets.IsAWhip[Type]=true` + `Projectile.DefaultToWhip()`；OnHitNPC 里 `target.AddBuff(BuffID.ShadowFlame, 240)` 标记 + 伤害递减 `Projectile.damage = (int)(Projectile.damage * 0.8f)`。

**命中附加减益（OnHit）**
- `GlobalItem.OnHitNPC` **只覆盖直接武器命中（近战挥击）**；远程/魔法/召唤/剑气等弹幕要**另写 `GlobalProjectile.OnHitNPC`** 才会触发。
- 用 `item.ModItem?.Mod == Mod` / `projectile.ModProjectile?.Mod == Mod` 限定本模组物品，避免影响原版。
- ⚠️ 减益里**不要** `npc.defense -= X`（ModBuff.Update 每帧跑，会无限叠加 → 防御负数 → 伤害爆炸）。要做 DoT 就只 `npc.life -= X` + 微粒特效；要降防请另想办法（如命中时一次性扣或其它机制）。

**段身虫（Worm）**
- 千万别给各段设 `NPC.realLife=head`：打掉头部会连带杀死全部段 → 整条 Boss 瞬间死亡。
- 正确做法：段间只用 `NPC.ai[3]` 链（每段 ai[3]=上一段 whoAmI）；段 AI 沿 ai[3] 向上找最近**存活**段跟随，链到头就自己当领头追玩家；击杀旗标=「所有段都不存在」才置位。
- 每段独立 HP、各自被击杀；身/尾设 `NPC.dontCountMe=true`（不计入清场）。

**范围爆炸（AoE）**
- Projectile 没有 `ExpandHitboxBy`（编译报 CS1061）。做法：记录 `center`，把 `width/height` 调大（如 56），`position = center - new Vector2(28,28)`，再 `maxPenetrate=-1; penetrate=-1; Projectile.Damage()` 结算范围内敌人；配 `SoundEngine.PlaySound(SoundID.Item14, Center)` 与粒子。

## 4.18 护甲套装与实战补遗（2026-08 M7/M8 反馈轮验证）

**护甲套装（头/胸/腿）**
- 头盔类：`IsArmorSet(Item head, Item body, Item legs)` 判定成套；`UpdateArmorSet(Player)` 给加成；`player.setBonus = Language.GetTextValue("Mods.<Mod>.SetBonus.<Name>")` 设套装 Tooltip。
- ⚠️ **setBonus 文案必须与 UpdateArmorSet 数值同步**：改了数值忘了改 hjson，玩家看到旧数值以为没生效。
- 职业头饰：同一胸甲+护腿 + 4 个职业头饰（近战/远程/魔法/召唤）各成一套，防御 召唤<魔法<远程<近战。
- 装备贴图（_Head/_Body/_Legs）尺寸规范见 `11-armor-textures.md`。

**类名 = 命名空间陷阱**：模组主类与命名空间同名（如类 Voidfall + 命名空间 Voidfall）时，子命名空间写 `Voidfall.Content.X` 解析到类 → CS0426。写 `Content.X` 或 `global::Voidfall.Content.X`。

**ModItem.Shoot 覆写 + return false 时 Item.shoot 必须保留**：去掉 `Item.shoot` 后 Shoot 钩子可能不触发（远程/近战发射类必须保留 shoot 指向一个弹幕类型）。

**引导弹落点随鼠标**：`ModItem.Shoot` 里读 `Main.MouseWorld`，经 `NewProjectile` 的 ai0/ai1（绝对世界坐标）传给弹幕；弹幕读 `ai[0]/ai[1]` 作目标。单机/多人通用（避免服务端无鼠标）。

**全屏 AoE 大招**：巨大 friendly 命中盒（如 1600×1600）+ `usesLocalNPCImmunity=true` + `localNPCHitCooldown` 大值（> 弹幕存活时长）→ 每敌只结算一次。

**敌对弹幕可被打掉**：AI 里遍历 `Main.ActiveProjectiles`，与玩家友方弹幕重叠则 `Projectile.Kill()`。

**友方弹幕「穿透 + 命中即爆炸」**：`penetrate=-1`（不被消耗）+ `OnHitNPC` 里 `Projectile.Kill()`（触发 OnKill 爆炸）。

**useAmmo + 自订弹（弹药武器强制发射指定弹幕）**：
- ⚠️ 枪设 useAmmo 时，**弹药弹幕会覆盖 `Item.shoot`**（尤其弹药是 mod 弹幕如虚空子弹时），可能发射弹药弹幕、吃不到本模组 GlobalProjectile 减益。
- ⚠️ **`PickAmmo` 钩子挂在【弹药】而非武器上**：`ItemLoader.PickAmmo` 源码调 `ammo.ModItem?.PickAmmo(...)`（遍历的是弹药）——给武器类加 `PickAmmo` 覆写**不会生效**（实测踩坑）。
- ✅ 武器侧强制弹幕类型用 **`ModItem.ModifyShootStats(Player, ref Vector2 position, ref Vector2 velocity, ref int type, ref int damage, ref float knockback)`**（`type` 是 ref）：`type = ModContent.ProjectileType<自订弹>()` → 「消耗弹药 + 永远发射自订弹」两全。
- 注意 tML 1.4.4 的 `ModItem.Shoot(Player, EntitySource_ItemUse_WithAmmo, Vector2, Vector2, int, int, float)` 参数**非 ref**，不能改 type；要改 type 用 `ModifyShootStats`。
- 若无需消耗弹药，直接去掉 useAmmo（自产弹）最简单。

**ModConfig 默认值会被玩家配置文件覆盖**：想「默认开启」某个运行时功能，需移除运行时闸门（而非只改属性默认值）——玩家旧配置文件里已有 false 会覆盖新默认。
