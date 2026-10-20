# 04f. 实战踩坑 · 手持绘制 / 箱子家具 / 钩爪 / 贴图白边

> 属 04 分册家族，§4.19；索引与通用原则见 `04-api-cheatsheet.md`。

## 4.19 手持绘制 / 容器家具 / 钩爪

**手持位置按「贴图原始帧尺寸」计算，不是缩放后尺寸**
`PlayerDrawLayers.HeldItem` 的 `itemDrawFrame = GetItemDrawFrame(type)` 取贴图完整帧（100×100 的 AI 贴图 = 100px）；`ModifyItemScale` 只改 `GetAdjustedItemScale`（绘制 scale，如 0.4），位置 / 原点偏移仍按 100px 帧算 → 大贴图武器手持「偏低、离角色太远」。闲置时 `itemLocation.X = 角色中心 + (帧宽×0.5 + 2)×朝向`（100px 帧前伸 52px，原版 28px 武器仅 16px）；近战挥动数学自带大帧补偿（`num` 随帧宽 14/24/28/38 递增），所以剑 / 工具正常。修法用 `GlobalItem.PreModifyItemDraw(Item, ref PlayerDrawSet, ref DrawData drawData, ref DrawData? colored, ref DrawData? glow)`：`ref DrawData` 直接改写最终绘制位置（`drawData.position += new Vector2(-shiftToward*direction, -shiftUp)`），上移 + 朝角色收拢，两朝向自动处理；ItemLoader 顺序 `PreModifyItemDraw` → `ModItem.ModifyItemDraw` → `PostModifyItemDraw`。tML 1.4 不自动加载 `_Held` 贴图（1.3 旧机制），手持一律用主贴图，`_Held` 文件留着无害但不生效。

**模组箱子必须自己开箱**
`Main.tileContainer` + `TileID.Sets.BasicChest` 只让原版开箱逻辑「认」它，原版代码不处理 mod 箱子类型。照抄 ExampleMod `ExampleChest.cs`：`RightClick(int i, int j)` 里 `Chest.FindChest(left, top)` → `player.OpenChest(left, top, chest)`，帧定位 `left = i - (frameX % 36 != 0 ? 1 : 0)`、`top = j - (frameY != 0 ? 1 : 0)`；`HasSmartInteract(...) => true`（悬停高亮与智能光标都靠它）；再用 `MouseOver` / `MouseOverFar` 显示图标与名称。贴图帧：Style2x2 箱子帧 36×34（`CoordinateHeights {16,18}`），sheet 至少 2 列 style × 1 行以上。

**方块高亮（`_Highlight`）**
tML 自动从 `主贴图路径 + "_Highlight"` 加载到 `TextureAssets.HighlightMask`，绘制条件是方块被 smart interact 选中 → 必须 `TileID.Sets.HasOutlines[Type] = true` 且 `HasSmartInteract(...) => true`；贴图尺寸须与主贴图 sheet 一致。

**钩爪（ModProjectile）**
照抄 ExampleMod `ExampleHook`：`CloneDefaults(GemHookAmethyst)` + `PreDrawExtras` 画链条。`ModType.Load()` 有效（ModProjectile 继承 ModType），链条贴图请求放 `Load`；绘制前加防御，`chainTexture == null || chainTexture.Value == null` 或 `owner` 越界时 `return false` 退回原版链条。钩爪弹幕不要放进 `GlobalProjectile.ScaleMap` 归一化（会缩成 18px 之类），钩爪头尺寸由弹幕自身贴图 / scale 控制。

**钩爪「卡死 / 未响应」= 死循环，不是异常**
链条绘制 `while` 循环每轮按链条贴图高度步进。贴图高 > 20px（如 50px）时，钩爪头距玩家 ∈ (20, 高度−20)（如 25px）会让步长过冲、来回振荡 → 死循环 → 游戏卡死、音乐循环、鼠标转圈、未响应。ExampleHook 链条 14px 高（步长 ≤ 20）所以官方无事。修法 `step = Math.Min(chainTexture.Height(), distanceToPlayer - 20f)`。这类卡死不**留异常日志**（旧日志、旋转 zip 都干净），只能读源码找循环；症状是「卡死 + 未响应」而非闪退。

**链条贴图不是可重复小环时：按固定步长平铺**
贴图若是一张 52×50 的整块藤蔓 / 锥形图，就不要「逐环平铺 + 步长钳制」，更别纵向拉伸——`scale = (1, distance / tex.Height)` 会让长度一变就严重变形。改为沿直线按固定步长放块、每块按原始宽高比绘制：
```csharp
const float ChainStep = 44f;      // 相邻块间距（略小于贴图高度形成重叠）
const int   MaxChainBlocks = 200; // 硬上限，绝无死循环可能
Vector2 unit = direction / distance;
int blocks = (int)(distance / ChainStep) + 1;
for (int i = 0; i < blocks && i < MaxChainBlocks; i++) {
    Vector2 pos = hookCenter + unit * (i * ChainStep);
    Main.EntitySpriteDraw(tex, pos - Main.screenPosition, tex.Bounds, drawColor,
        rotation, tex.Size() * 0.5f, new Vector2(1f, ChainStep / tex.Height), SpriteEffects.None, 0);
}
```
双保险：`distance < 8f` 直接 return + 块数上限，结构上不存在死循环。❌ 不要用 `FillWhipControlPoints` 给钩爪画曲线：它依赖鞭子的 `ai[0]` / `timeToFlyOut` 挥出进度（内部读 `GetWhipSettings` 的 `useAnimation`），钩爪没有这个语义，套用只会得到无意义曲线；钩爪索是直线力学，平铺直线才对。细节：`Request<Texture2D>(path, AssetRequestMode.ImmediateLoad)` 可消掉 "spending Nms blocking on asset loading" 警告；`Main.dedServ` 时不请求；静态字段在 `Unload()` 置 null。残留观感是整块图平铺有重复感，根治 = 重做成可无缝接续的环状链条贴图（建议 16×16 或 24×24）。

**箱子标准贴图 = 36×114 三行（开箱帧机制）**
`TileDrawing.CacheSpecialDraws_Part2` 对 BasicChest 读 `Main.chest[i].frame`（0=关 / 1=开盖中 / 2=开）并给绘制帧加 `addFrY += 38 / 76`（sheet 行高 38），所以标准箱子 sheet 是 36 宽 × 114 高（或 72×114 两列 style）：行0（frameY 0–38）= 关、行1（38–76）= 开盖中、行2（76–114）= 开。「左=关、右=开」的 72×38 设计必须转成 36×114（关 → 行0，开 → 行2，行1 可复用关）。只给 1 行 38px 的 sheet，打开时会画到 sheet 外 → 显示为白色；`Chest.OpenChest` / Chest 类**不切帧**，开合帧完全由上述绘制偏移驱动。桌子贴图 32×16 是 2×1（Style2x1），代码写成 Style1x2（1×2）会读 16×32 帧 → 下半截越界 → 显示不全。

**贴图「白边 / 光晕」= 预乘 alpha + 雾边残留**
Terraria 用 `BlendState.AlphaBlend`（XNA 预乘混合 `srcColor*1 + dst*(1-srcAlpha)`），而 tML 加载 mod 贴图是原始非预乘 RGBA（`ImageIO.ToRaw` 原样写、`RawImgReader` 直读），于是半透明像素（alpha < 255）按原 RGB 全亮叠加 → 白边 / 光晕，AI 白底残留的「半透明白色雾边」最明显。图像编辑器按普通 alpha 显示所以看不到，只有游戏里露馅；ExampleMod 贴图 0 个半透明像素，官方主动避开。
- ⚠️ 预乘（`rgb = rgb * a / 255`）能消白边，但会压暗半透明边缘——暗色贴图边缘融入背景，观感是内容消失。
- 自动去雾边的三种方案（全局阈值只删 min ≥ 170 的半透明亮像素 / 只删边缘 / 自适应亮度）全部误伤「暗色主体 + 亮色发光边缘」的贴图：发光描边与雾边同为半透明亮像素，无法用颜色或位置区分。白边无可靠自动修复。
- ✅ 根治 = 重新生成贴图，AI 提示词强调「背景纯透明、边缘干净、无白色光晕」；次选是接受白边（美学问题，不影响功能）或手工清理最严重的几张。
- 箱子开箱白屏与雾边无关，用标准 36×114 三行已解决。
