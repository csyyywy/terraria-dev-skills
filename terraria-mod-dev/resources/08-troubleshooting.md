# 08. 常见错误与排错

> 先看日志 `%USERPROFILE%\Documents\My Games\Terraria\tModLoader\Logs\client.log`（或 server.log / Launch.log）：报错一般带堆栈与模组名。

## 8.1 构建/环境类

| 症状 | 原因 | 修复 |
|---|---|---|
| `No .NET SDKs were found` / 游戏内 ".NET SDK not recognised" | `dotnet` 指向不含 SDK 的副本 | 用 9.x SDK 的 `dotnet` 或调 PATH（见 01 §1.2）；`dotnet --list-sdks` 确认有 9.x |
| `CS0106: 修饰符"public"对该项无效`（报在 SilkyUIAnalyzer\ITypeSymbolExtensions.cs） | C#14 `extension(...)` 块被旧 Roslyn 当普通方法 | 换 9.x SDK；**不是你的 bug**（见 01 §1.2） |
| `NETSDK1013: TargetFramework 值为空` | csproj 相对导入 `..\tModLoader.targets`，junction 工作区解析失败 | 改用属性导入 `$(TMLDir)` 并在构建时传 `-p:TMLDir=<TML_DIR>`，或写死绝对路径（见 02 §2.3、templates） |
| `error MSB4019`（找不到导入的 targets） | targets 路径错 | 确认 tML 已安装且路径正确；先让 tML 构建一次生成包装文件 |
| 报原版/旧版 API 错（如 `Item.useTime` 不存在） | 版本对不上，或用了 1.4.5 preview、旧教程 API | 对照 docs.tmodloader.net/docs/stable 的 1.4.4 签名 |
| 构建成功但 .tmod 没更新 | 游戏在跑，锁文件 | 退出 tML 再构建 |
| `NuGet.targets(745,5): error : Value cannot be null. (Parameter 'path1')`（restore 失败） | 受限环境剥离了 `PROGRAMFILES(X86)`/`PROGRAMDATA`/`APPDATA` 等特殊目录变量，NuGet 拼机器级配置路径时 path1 为 null；缓存失效（如 `--force`）才暴露 | 构建前补齐这些变量（见 scripts/build.ps1 顶部），再 restore + build；别用 `--force` 无谓失效缓存 |

## 8.2 加载/运行类（进游戏或 Reload 红字）

| 症状 | 原因 | 修复 |
|---|---|---|
| `Missing localization key: Mods.MyMod.ItemName.X` | 新内容没写 hjson 键 | 补 `Localization/en-US.hjson`（+zh-Hans）；新版报作用域键名（如 `Items.X.DisplayName`），键名=类名（见 05 §5.7） |
| `Missing ModItem.X` / 类未找到 | 没继承正确基类，或命名空间/类名与文件名不符 | 确认 `: ModItem/ModNPC/...`，类名唯一 |
| `Exception: System.TypeLoadException` | 引用了不存在或已改名的 API | 查 API 文档核对签名；必要时用 tModPorter |
| Reload 后旧数值残留 | `Unload()` 没清静态字段 | `Mod.Unload()` 里静态引用置 null、计数器归零 |
| 贴图花屏/错位 | 尺寸或命名与类不符；装备贴图（_Head/_Body/_Legs）按图标规格做了 | 文件名=类名，tile 尺寸见 02.5；装备贴图见 `11-armor-textures.md`（40x1120/360x224） |
| `MissingResourceException: 未找到预期的资源 Content/Items/X` | 内容类缺同名贴图 | 放 `Content/Items/X.png`（纯色占位即可），见 02 |
| `MissingResourceException: 未找到预期的资源 Content/Tiles/X_Highlight` | 设了 `TileID.Sets.HasOutlines[Type]=true` 但缺 `_Highlight` 轮廓图（客户端专属，无头服务器测不出） | 生成同尺寸白色轮廓 `X_Highlight.png`，用真机 Reload 验证 |
| `RecipeException: A Recipe can only be created inside recipe related methods` | 在 Load()/Update 等非配方方法里调 Recipe.Create | 移到 `ModItem.AddRecipes()` / `ModSystem.AddRecipes()` / `GlobalItem.AddRecipes()` |
| `icon.png` 报错 | 格式或尺寸不对 | 80×80 PNG（其它尺寸拒载）；发布工坊须非默认图标 |
| 模组不在 Mods 列表 | 没进 ModSources / junction 断 / 没启用 | 检查 `ModSources\MyMod` junction，在 Mods 菜单启用 |
| 游戏内点构建卡住 | tML 在等 SDK 或锁文件 | 用命令行构建定位错误，再 Reload |

## 8.3 逻辑/行为类

| 症状 | 原因 | 修复 |
|---|---|---|
| 武器没有伤害 | 忘设 `Item.damage` / `DamageType` / `useStyle` | 对照 04.2 |
| 弹幕不飞/穿透异常 | `Projectile.aiStyle` 与手写 AI 混用，或 `friendly` 未设 | 二选一；设 `friendly=true` |
| 物品不能合成 | `AddTile` 站没建 / 材料 ID 错 | 检查 Recipe 条件，先用原版材料验证 |
| NPC 不生成 | 没写生成条件（SpawnChance/OnSpawn/手动生成） | 加生成逻辑或手动 `NPC.NewNPC` |
| 只有主机看到效果 | 网络同步缺失 | 见 06：事件走 ModPacket，世界数据走 NetSend |
| 加载报 `Duplicate`（类型冲突） | 命名空间/类名与其它模组撞 | 模组名与命名空间尽量唯一 |

## 8.4 静默失效类（不报错、功能没效果）

> 判据以 tML 源码为准：`<TML_SRC>`（= tModLoader 源码检出目录）下的 `patches\` 与 `ExampleMod\`，别靠记忆，直接 grep。
> 查不到（原版逻辑，patch 只有 diff）就反编译：`~/.dotnet/tools/ilspycmd -t Terraria.NPC "<TML_DIR>/tModLoader.dll"`（`<TML_DIR>` = tModLoader 安装目录；tModLoader.dll 内嵌整个 Terraria，无须单独的 Terraria.dll）。⚠️ 输出重定向到工程目录之外，否则会被 SDK 当源码编译。

| 症状 | 原因 | 修复 |
|---|---|---|
| 饰品词缀/效果完全没用（护甲正常） | 只 override 了 `GlobalItem.UpdateEquip`，没 override `UpdateAccessory`：饰品槽 `armor[3..9]` 走 `ApplyEquipFunctional` → `ItemLoader.UpdateAccessory`（`Player.cs.patch:3292`），不经 `UpdateEquip`（在其末尾 `GrantArmorBenefits`，`Player.cs.patch:3099`，只服务 armor 槽） | 补 `public override void UpdateAccessory(Item item, Player player, bool hideVisual)`。`ModAccessorySlot.ApplyEquipEffects`（`ModAccessorySlot.cs:114-118`）同时调 `GrantArmorBenefits` + `ApplyEquipFunctional`，自定义饰品槽会双触发 → 每帧标记去重（`ResetEffects` 清） |
| 自定义饰品槽上的效果数值翻倍 | 同上，双路径触发 | 同上，每帧标记去重 |
| 服务端改了 `_xx` 字段，客户端读到的永远是 0 | `SendExtraAI`/`ReceiveExtraAI` 漏发该字段 | 补发；或让客户端按已同步字段惰性重算（该字段是它们的纯函数时更稳） |
| `ModPlayer.OnHurt` 的反伤在多人下翻倍 | `PlayerLoader.OnHurt`（`Player.cs.patch:6113`）在发包分支（`netMode==1 && whoAmI==myPlayer && !quiet`）之外 → 双端各跑一次 | 加归属守卫 `if (Main.netMode != NetmodeID.SinglePlayer && Player.whoAmI != Main.myPlayer) return;`。**不能**写成 `netMode == Server → return`：监听服自己就是本地玩家，会连 host 的效果一起干掉 |
| 缓存/候选池建成空列表后永不重建 | 重建判据 `if (_cache == null) Build();`，而 `Build()` 的异常路径把空集合赋给 `_cache`（空 ≠ null） | 异常路径保持 `null`，或加显式 `Invalidate()` |
| 扣费/扣材料在服务端"没生效" | 服务端路径只递减了局部影子变量，真实扣除写在客户端回执里 | 服务端也要真扣；或明确该路径为客户端权威并加限速 |

### 必记的 tML 语义

| 结论 | 出处 |
|---|---|
| `ModPlayer.OnHitNPC` / `ModifyHitNPC` 对弹幕命中同样触发（`*WithProj` 内部先调通用版）；近战专属逻辑必须放 `OnHitNPCWithItem` / `ModifyHitNPCWithItem`，否则双重触发（例：狂乱 1.25² = 1.5625） | `PlayerLoader.cs:1015-1020`、`:1025-1031` |
| `ModPlayer.SendClientChanges` 在客户端执行（`this` = 客户端自己的实例，`clientPlayer` = 上一帧快照） | `Main.cs.patch:2781` |
| `NPC.StrikeNPC(HitInfo)` 不自动发包，须手动 `NetMessage.SendStrikeNPC` | `NPC.cs.patch:2576`（原文明写） |
| 服务端收到客户端 StrikeNPC 包走 `StrikeNPC(hit, fromNet: true)`，不重跑 `ModifyIncomingHit` 等修饰链 → 只在服务端算的减伤/修饰字段必须下行 | `MessageBuffer.cs.patch:363` + `NPC.cs.patch:2513` |
| `NPC.StrikeNPC(HitInfo)` 不触发任何 `OnHitNPC` 钩子（唯一调用点 `CombinedHooks.cs:119` / `:168`）：命中处理器内手动补打击不会递归，但其它 mod 的 `OnHitNPC` 也看不到 | `NPC.cs.patch:2582` 体内无 `Loader.OnHit`；对照 `StrikeOtherNPC` 才有 `NPCLoader.OnHitNPC` |
| 弹幕改伤害用 `GlobalProjectile.ModifyHitNPC(Projectile, NPC, ref NPC.HitModifiers)`（走 `FinalDamage`）；别在 `OnHitNPC` 里补额外打击 —— 会被敌方防御再削一次，还多一条飘字和同步包 | `GlobalProjectile.cs:237`；`CombinedHooks.ModifyHitNPCWithProj`（`:155`） |
| 抽象 `ModBuff` 基类不会被自动加载（不会缺贴图报错），可作公共基类 | `Mod.Internals.cs:73` 过滤 `!t.IsAbstract` |
| `Player.maxBuffs` 基础 44（`44 + BuffLoader.extraPlayerBuffCount`），"每件装备挂一条 buff"按此估上限 | `Player.cs.patch:395-398` |
| `moveSpeed` 是 `maxRunSpeed` 和 `runAcceleration` 的*共同*乘数 —— 原版速度药水 `moveSpeed += 0.25f` 本就同时抬高加速度；玩家说"只加速度、上限没变"时该改的是上限 | `Player.cs.patch:856`（官方注释原文） |
| `maxRunSpeed` / `accRunSpeed` 只能在 `ModPlayer.PostUpdateRunSpeeds` 改（其它时机被覆盖）；`runAcceleration` 只定多快达到上限 | `Player.cs.patch:921` / `:933` |
| `GlobalItem.OnHitNPC` 的 `if (!HasAffix) return;` 连带挡掉"装备被动"：写在门控之后的 `ModPlayer` 被动字段（命中回血/回蓝/爆伤…）手持无词缀武器时永不生效 | 移到 `ModPlayer.OnHitNPCWithItem`，见下节骨架 |

### 被动/套装效果骨架：位掩码 + 标记 Buff

反模式：`ModPlayer` 上放 `int EquipLegendaryPowerId`，`PostUpdateEquips` 里遍历 `armor[0..9]` 只取**第一件**带效果的装备 → 后者全失效，体感"只有手持武器的效果生效"。

```
ResetEffects:        _collected.Clear();  Mask = 0;
UpdateEquip/         _collected.Add(itemEffectId);        ← 逐件登记
UpdateAccessory:       （同一 tick 双触发需去重，见上表）
PostUpdateEquips:    Mask = BitOf(weaponId) | CollectMask(_collected, exclude: weaponId);
                     if (isLocal) ApplyBuffs(player, Mask);   ← 只为"已激活"显示，服务端不需要
命中/周期触发点:      if ((Mask & BitOf(X)) != 0) ...
```

- 位或幂等 → 多件同 id 只占一个 bit，无需去重代码。
- `exclude: weaponId` 一行实现"武器优先"，不必逐触发点写分支。
- 收集走 `UpdateEquip`/`UpdateAccessory`，别遍历 `armor[0..9]`，否则 `ModAccessorySlot` 自定义槽的装备统计不到。
- 掩码对**所有**玩家都算（服务端要给远端玩家的弹幕加成），buff 只给本地玩家挂，否则每 tick 向全体广播 AddBuff 包。
- 归属判断统一用 `Main.netMode == SinglePlayer || Player.whoAmI == Main.myPlayer`。

### SilkyUI：`FitHeight` + 绝对定位子元素 = 元素被裁掉且点不中

症状：网格/格子看不见或看得见点不动，父容器只剩一条极窄边框。

```csharp
panel.FitHeight = true;                 // ← 自适应高度
foreach (...) {
    slot.Positioning = Positioning.Absolute;   // ← 绝对定位子元素
    slot.SetLeft(...); slot.SetTop(...);
    slot.Join(panel);
}
SUITheme.StyleSubPanel(panel);          // ← 内部设了 OverflowHidden = true
```

根因：绝对定位子元素不参与父容器自适应尺寸 → 面板高度恒为 0（只剩 padding）；`SUITheme.StyleSubPanel` 又设了 `OverflowHidden = true`，子元素整块被裁；即便渲染出来，命中测试也过不了 0 高度父容器。

修法（只做这一步，别顺手改容器层级）：先数候选，按实际内容给父容器显式高度。

```csharp
int usedRows = (candidates.Count + perRow - 1) / perRow;
panel.FitHeight = candidates.Count == 0;              // 无内容时才自适应（放提示文字）
if (candidates.Count > 0)
    panel.Height = new Dimension(usedRows * step + padding * 2f);
```

嵌套 `FlexGrow` 坑：

```csharp
UIElementGroup root = new() { Column, FitHeight = false, FlexGrow = 1f, Width = 1f }.Join(_content);
UIElementGroup row   = new() { Row,    FitHeight = false, FlexGrow = 1f, Width = 1f }.Join(root); // ← 0 高度
```

`row` 及里面整张物品卡、所有按钮高度算成 0 → 整页失去命中区域，"点按钮完全没反应"。结论：`FlexGrow` 只在"父容器有显式高度"这层可靠；嵌套时每层都给显式 `Height`（`FlexGrow = 1f` 与 `Height = new Dimension(0f, 1f)` 同时给），或别加中间层、只修高度。

排查顺序：`OverflowHidden` → `Positioning.Absolute` → 父容器高度是自适应还是显式（自适应 + 绝对定位 = 0 高度）→ 是否嵌套 `FlexGrow` 而中间层没给显式高度。

### 同族坑：固定高 100% 的兄弟节点挤掉后续元素

症状：状态栏/提示行/页脚永不显示，但赋了值、本地化键也在。

```
mainPanel（Column，Height 0.88f，StylePanel → OverflowHidden = true）
  ├─ headerRow        FitHeight = true（自适应，约 40px）
  ├─ mainRow          FlexGrow = 1f  **并且** Height = 1f   ← 固定吃掉 100%
  └─ _statusLine      Height = 22f                          ← 被挤到可视区下面
```

`mainRow` 同时给 `FlexGrow` 和 `Height = 1f`，固定高度优先 → 总高 `headerRow + 100% + 22px > 100%`，最后 22px 被父容器 `OverflowHidden` 裁掉。

修法：撑满剩余空间的容器**只留 `FlexGrow = 1f`，不给 `Height`**，让它自动让出兄弟节点的空间。
反向：父容器 `FitHeight = true` 或高度不确定时，`FlexGrow` 又算成 0，此时两者都要给。判据：**父容器高度确定 → 只用 FlexGrow；不确定 → 两者都给。**
排错：先把父容器 `OverflowHidden` 临时关掉，立刻看出是被裁、高度为 0，还是跑到别处。

内容变多装不下：没有滚动容器时拆双列 —— 外层改 `FlexDirection = Row`，内嵌两个 `FlexDirection = Column` 子容器，用 `_target` 字段指向"当前写入哪一列"、在构建函数里按语义分段切换（行数动态的那段放最后）。

```csharp
// 每列 50% - 4px：用 Dimension 的**像素**分量补掉一半的 Gap，
// 否则 50% + 50% + 8px = 100% + 8px，右侧会被父容器的 OverflowHidden 裁掉
Width = new Dimension(-4f, 0.5f)
```

`Dimension(float pixels, float percent)`：**第一个参数是像素、第二个是百分比**。

### 数据表条目废弃与新增：保住存档兼容

场景：要移除旧词条/敌人词缀，但条目 id 顺序递增、直接写进玩家存档，重排或删除会让旧装备上的 id 错位（"免疫中毒"变"免疫霜燃"或直接失效）。
做法（以 `AffixDatabase` 为例）：不删不重排旧条目 → 旧条目 `Weight` 改为 `0f` → `PickWeighted` 里过滤 `Weight <= 0` → 新条目追加在列表**末尾**。

```csharp
// 旧词条：存档兼容，不再被新掷出
New("BuffResistPoison", ..., weight: 0f),
...
// 新词条追加在末尾，id 递增，不影响前面
New("BuffResistFrostburn", ..., weight: 0.5f),

// 抽取时过滤
var cands = pool.FindAll(d => !usedStats.Contains(d.Stat) && d.Weight > 0f);
```

旧装备上的旧词条继续生效，新装备只会出新词条，存档不爆炸。

## 8.5 排查工具

```powershell
# 看最新日志尾部
Get-Content "$env:USERPROFILE\Documents\My Games\Terraria\tModLoader\Logs\client.log" -Tail 80

# 验证 .tmod 产物与启用状态
Get-Item "$env:USERPROFILE\Documents\My Games\Terraria\tModLoader\Mods\MyMod.tmod" | Select-Object Length, LastWriteTime
Get-Content "$env:USERPROFILE\Documents\My Games\Terraria\tModLoader\Mods\enabled.json"

# 验证 junction
cmd /c dir "$env:USERPROFILE\Documents\My Games\Terraria\tModLoader\ModSources"
```

## 8.6 求助与发布

求助：tML 官方论坛、Discord、Steam 讨论区（见 09）；提问带 tML 版本、`client.log` 尾部、最小复现代码。

| 症状 | 原因 | 修复 |
|---|---|---|
| 盔甲穿戴错位/花屏 | 装备贴图（_Head/_Body/_Legs）按物品图标尺寸生成，非帧规格 | 见 `11-armor-textures.md` 与模组内 `<Mod>/tools/fix-armor-textures.ps1` |
| 发布/ModSources 构建报 CS0246（`List<>`/`Math` 找不到）但本地 build 过 | tML 发布构建不应用 csproj 的 ImplicitUsings | 显式 using 或 GlobalUsings.cs；本地用 `-p:ImplicitUsings=disable` 验证（见 03） |
| 打包报 `TML003: Please close tModLoader or disable the mod in-game` | tML 客户端或残留 server 占用 .tmod | 区分进程：`-terrariasteamclient`=客户端别杀，裸 tModLoader.dll=残留 server 可杀；退出后再打包（见 03） |
| PowerShell 跑 .ps1 报 "term 'X' is not recognized" 但函数已定义 | .ps1 是 UTF-8 无 BOM + 中文注释，Windows PowerShell 5.1 按 ANSI 解析把函数定义弄坏 | 注释全用 ASCII，或存 UTF-8 BOM |
| 文件被截断成已读行数 | 对整文件 limit 读取后整写覆盖 | 先 git checkout 恢复；大文件用精确 edit（old_string 唯一），勿整写 |

省贴图：`ModBuff` 复用原版图标 —— 大量新 buff（如"命中附加霜燃/灵液/剧毒"）风格要接近原版时，把 `Texture` 指向原版减益贴图：

```csharp
public class FrostburnBuff : ModBuff
{
    public override string Texture => "Terraria/Images/Buff_" + BuffID.Frostburn;
}
```

tML 加载 `Texture` 时会从原版内容里取图，效果与原版 buff 完全一致，不用自己画。`Terraria/Images/Buff_<id>` 的 id 即 `BuffID` 整数值。

## 8.7 接手/审核既有模组：30 分钟体检清单

先跑完再动手，比"读到哪改到哪"高效；每条都能脚本化。

| # | 检查项 | 一行做法 | 典型问题 |
|---|---|---|---|
| 1 | 能否编译 | `dotnet build -c Release -p:BuildMod=false` | 先排除基线问题（游戏开着也能跑） |
| 2 | hjson 语法 | `scripts/check-hjson.ps1` | 一次语法错 = 整个模组被禁用 |
| 3 | **内容类是否有同名 PNG** | 遍历 `class X : ModItem/ModNPC/…`，查同目录 `X.png` | 漏一张就 `MissingResourceException` 禁模组 |
| 4 | `[AutoloadEquip]` / `[AutoloadBossHead]` 贴图 | 查 `X_Head/_Body/_Legs/_Head_Boss.png` | 漏了穿戴/血条头像异常 |
| 5 | 本地化键齐全 | 比对 `DisplayName/MapEntry/Chat*/SetBonus/Configs` | 缺键报 Missing localization key |
| 6 | **配置项是否真的被读取** | `grep -rn "配置属性名"` 看有没有读取点 | 死配置：有滑块有 Tooltip 但没人读 |
| 7 | **进度旗标是否落盘** | 查每个 `ModSystem` 有没有 `SaveWorldData/LoadWorldData` | 只有 `NetSend` = 退出重进全丢（存档级） |
| 8 | **Boss 朝向 vs 贴图形态** | `grep -rn "NPC.rotation = "`，逐张看贴图是否直立型 | 直立 Boss 被当球体旋转 → 倒转贴地 |
| 9 | 诱饵式自我衰减 | `grep -rn "damage \*= \|damage = (int)(.*damage \* "` | 写在 `OnHitNPC` 里 = 每命中一次永久降伤 |
| 10 | 数组索引校验 | 查 `NPC.NewNPC` / `NewProjectile` 返回值有没有判界 | 满槽返回 200，直接用会崩 |
| 11 | 每帧全表遍历 | `grep -rn "ActiveProjectiles\|ActiveNPCs"` | 每帧 O(N) × 实例数 = 卡顿 |
| 12 | 设计文档 vs 实现 | 抽查文档里的数字（波次/血池/掉落） | 文档说 5 波实际 6 波，会误导后续开发 |

- 视觉类问题（朝向、贴图规格）**必须看图**：PNG 放大 3–8 倍用 `NearestNeighbor`，或 `read_image` 直接读原图；别只看尺寸数字下结论。
- 问题先记进 `BUGS.md` 台账（文件/行号/根因/修法/状态），比边读边改可靠。
