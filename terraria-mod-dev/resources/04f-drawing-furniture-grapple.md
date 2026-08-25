# 04f. 实战踩坑 · 手持绘制 / 箱子家具 / 钩爪 / 贴图白边

> 属 04 分册家族（原 §4.19）；索引与通用原则见 `04-api-cheatsheet.md`。以下均为实测验证条目。

## 4.19 手持绘制/容器家具/钩爪（2026-08 M9 反馈轮验证）

**手持位置数学用「贴图原始帧尺寸」而非缩放后尺寸**：`PlayerDrawLayers.HeldItem` 里 `itemDrawFrame = GetItemDrawFrame(type)` = 贴图完整帧（AI 贴图 100x100 → 100px）。而 `ModifyItemScale` 只改 `GetAdjustedItemScale`（绘制 scale，如 0.4），**位置/原点偏移仍按 100px 帧算** → 大贴图武器手持「偏低、离角色太远」。闲置时 `itemLocation.X = 角色中心 + (帧宽×0.5 + 2)×朝向`（100px → 52px 前伸；原版 28px 武器仅 16px）。近战挥动数学自带大帧补偿（num 随帧宽 14/24/28/38 递增）所以剑/工具正常。
- 修复钩子：**`GlobalItem.PreModifyItemDraw(Item, ref PlayerDrawSet, ref DrawData drawData, ref DrawData? colored, ref DrawData? glow)`** —— `ref DrawData` 直接改写最终手持绘制位置（`drawData.position += new Vector2(-shiftToward*direction, -shiftUp)`），上移+朝角色收拢，两朝向自动处理。ItemLoader 顺序：PreModifyItemDraw → ModItem.ModifyItemDraw → PostModifyItemDraw。
- tML 1.4 **不自动加载 `_Held` 贴图**（1.3 旧机制），手持一律用主贴图。`_Held` 文件留着无害但不生效。

**模组箱子必须自己开箱**：`Main.tileContainer` + `TileID.Sets.BasicChest` 只让原版开箱逻辑认它；原版代码不处理 mod 箱子类型。必须覆写（照抄 ExampleMod `ExampleChest.cs`）：
- `RightClick(int i, int j)`：`Chest.FindChest(left, top)` → `player.OpenChest(left, top, chest)`；帧定位 `left = i - (frameX % 36 != 0 ? 1 : 0)`，`top = j - (frameY != 0 ? 1 : 0)`。
- `HasSmartInteract(...) => true`（**悬停高亮与智能光标都靠它**）。
- `MouseOver` / `MouseOverFar`（显示"虚空箱"图标与名称）。
- 贴图帧：Style2x2 箱子帧 36x34（CoordinateHeights {16,18}），sheet 至少 2 列（style）× 1+ 行。

**方块高亮贴图（`_Highlight`）**：tML 自动从 `主贴图路径 + "_Highlight"` 加载到 `TextureAssets.HighlightMask`。绘制条件是**方块被 smart interact 选中** → 必须有 `TileID.Sets.HasOutlines[Type] = true` + `HasSmartInteract(...) => true`。贴图尺寸须与主贴图 sheet 一致。

**钩爪（ModProjectile）**：照抄 ExampleMod `ExampleHook`（`CloneDefaults(GemHookAmethyst)` + `PreDrawExtras` 画链条）。`ModType.Load()` 有效（继承自 ModType，ModProjectile 可用），链条贴图请求放 Load 里。**链条绘制加防御**：`chainTexture == null || chainTexture.Value == null` 或 `owner` 越界时 `return false` 退回原版链条，避免空引用崩溃。**钩爪弹幕别放进 GlobalProjectile.ScaleMap 归一化**（会缩成 18px 之类）——钩爪头尺寸靠弹幕自身贴图/scale 控制。

**钩爪「卡死/未响应」根因（死循环，非异常）**：链条绘制 while 循环每轮步进链条贴图高。若链条贴图高 >20px（如 50px），当钩爪头距玩家 ∈ (20, 高-20)（如 25px）时步长过冲来回振荡 → 死循环 → 游戏卡死、音乐循环、鼠标转圈、未响应。ExampleHook 链条 14px 高（步长≤20）所以官方无事。
- 修复：步长钳制 **step = Math.Min(chainTexture.Height(), distanceToPlayer - 20f)**，保证逐步逼近永不振荡。
- 排查技巧：这种卡死**不留异常日志**（旧日志/旋转 zip 都干净），只能靠读源码找循环；症状是「卡死+未响应」而非「闪退」。

**箱子标准贴图 = 36×114 三行（开箱帧机制）**：TileDrawing.CacheSpecialDraws_Part2 对 BasicChest 读 Main.chest[i].frame（0=关 / 1=开盖中 / 2=开）并给绘制帧加 addFrY += 38 / 76（即 sheet 行高 38）。所以**标准箱子 sheet 是 36 宽 × 114 高**（或 72×114 两列 style）：行0(frameY 0-38)=关、行1(38-76)=开盖中、行2(76-114)=开。用户设计「左=关、右=开」的 72×38 必须转成 36×114（关→行0，开→行2，行1 可复用关）。只给 1 行 38px 的 sheet，打开时会去画 sheet 外 → 显示为白色。Chest.OpenChest / Chest 类**不切帧**，开合帧完全由上述绘制偏移驱动。
- 桌子：贴图 32×16 是 2×1（Style2x1）；若代码写 Style1x2（1×2）会读 16×32 帧 → 下半截越界 → 显示不全。

**贴图「白边/光晕」= 预乘 alpha 问题 + 雾边残留（重要！）**：Terraria 用 `BlendState.AlphaBlend`（XNA 预乘混合：srcColor*1 + dst*(1-srcAlpha)），而 tML 加载 mod 贴图为**原始非预乘 RGBA**（ImageIO.ToRaw 原样写、RawImgReader 直读）。于是**半透明像素（alpha<255）会按原 RGB 全亮叠加 → 白边/光晕**；AI 白底残留的"半透明白色雾边"最明显。图像编辑器按普通 alpha 显示所以**看不到**，只有游戏里才露馅。ExampleMod 贴图 0 个半透明像素（官方避开此问题）。
- ⚠️ **预乘（rgb=rgb*a/255）虽消白边，但会压暗半透明边缘**——暗色贴图边缘会融入背景、观感"内容消失"，用户不接受。
- ⚠️ **自动去雾边方案已测试并回退**：全局阈值(只删 min>=170 半透明亮像素)、只删边缘、自适应亮度 3 种都试过，**全部会误伤"暗色主体+亮色发光边缘"的贴图**（VoidTitan/VoidEnd/Stellar 系等，其发光描边与雾边是同一类"半透明亮像素"，无法用颜色/位置区分）。用户观察到"像素损坏"后已还原。**结论：白边无可靠自动修复**。
- ✅ **根治 = 重新生成贴图**：AI 提示词强调"背景纯透明、边缘干净、无白色光晕"，从源头避免雾边（官方 ExampleMod 就是 0 半透明像素的硬边）。
- 次选：接受白边（美学问题，不影响功能）；或手工逐张清理最严重者。
- 箱子开箱白屏与雾边无关，用标准 36×114 三行已解决（见上）。
