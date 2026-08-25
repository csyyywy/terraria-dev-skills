# 03. 贴图尺寸规范 + 可改 vs 固定分类 + 生成提示词

> 给 AI 生成定规范：哪些贴图可改大小、生成到什么尺寸、提示词怎么写。

## 固定规格（不可改，保持原样）

| 贴图 | 规格 | 说明 |
|---|---|---|
| _Head 装备帧 | 40×1120 | 20 帧 × 40×56，覆盖全部头部动画帧 |
| _Legs 装备帧 | 40×1120 | 20 帧 × 40×56 |
| _Body 装备帧 | 360×224 | 1.4 composite 新格式（9 列×40px，4 行×56px），tML 强制 UsesNewFramingCode |
| _Held 手持图 | 随武器 | 手持专用，原尺寸 |
| _Wings | 帧图 | 装备翅膀帧 |
| Tile / Wall | 按 TileObjectData | 16×16 / 帧布局，裁不得 |
| NPC 实体 | 按碰撞盒 | 裁不得 |
| Boss 地图头像 _Head_Boss | 26×26 | 裁不得 |
| 城镇 NPC | 40×1400 | 25 帧 × 56px |

（装备帧细节见 terraria-mod-dev skill 的 11-armor-textures.md）

## 可改变大小（物品图标 / 弹幕 / 增益）

- 范围：Items/（非装备附加帧）、Projectiles/、Buffs/。
- 放大到 100 宽（高按原比例，如 20×20→100×100、56×30→100×54）：AI 大画布好画，之后再裁剪+代码归一化，生成/裁剪阶段不缩放像素。
- 输出物：全量表 texture-replace-sheet.csv + 可改图标专属表 texture-replace-sheet-icons.csv（5 列：序号, 贴图名称, 对应内容/装备, 尺寸(宽×高), 英文生成提示词）。

## 生成提示词要点

- 尺寸规格写「ONE 40x56 equip frame」这类单帧，不要「centered on canvas, fill 80-90%」（那是物品图标居中构图，会留白）。
- 强调铺满：filling the ENTIRE canvas edge-to-edge, span top to bottom, NO margins/gaps, full-bleed。（对应中文：整个画面从上到下铺满、不留间隙。）
- 明确深色或者黑色背景生成后成透明底）。
- 装备帧位置提示：head 在帧上半、leggings 在帧下半、Body 用官方 composite 模板。

## CSV 编码

- 必须 UTF-8 with BOM：中文 Windows 的 Excel 按 GBK 读无 BOM 文件 → 乱码。
- 用 PowerShell Export-Csv 生成的 .ps1 若含中文属性名（如 贴图名称），脚本文件本身要 UTF-8 BOM 或纯 ASCII（Windows PowerShell 5.1 按 ANSI 读无 BOM 的中文 → 解析错乱/函数找不到）。

## 排查速查

| 症状 | 原因 | 修法 |
|---|---|---|
| 物品栏图标巨大溢出 | 大贴图无自动缩放？ | 实际有：物品栏自动缩放（sizeLimit≈32），正常；检查是否代码里改过 Item.scale |
| 弹幕巨大 | 贴图 1:1 绘制 | GlobalProjectile scale 归一化 |
| 武器挥动巨大 | 手持用主贴图无缩放 | GlobalItem.ModifyItemScale 归一化（排除 _Held 武器） |
| 增益图标大小不一 | buff 栏固定绘制 | GlobalBuff.PreDraw 自绘 32×32 |
| 中文 CSV 乱码 | 缺 UTF-8 BOM | 补 BOM（EF BB BF） |