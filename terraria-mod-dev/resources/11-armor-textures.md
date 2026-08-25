# 11. 装备 / 盔甲贴图规格（Equip Textures）与修复

> 2026-08 实测（对照 tML 官方 ExampleMod 贴图尺寸 + EquipLoader/PlayerDrawLayers 源码）。
> 护甲/装备的穿戴外观贴图（_Head/_Body/_Legs）有**严格尺寸规范**；按物品图标规格做会穿戴错位/花屏。
> 本分册 = 正确规格 + 修复工具 + AI 提示词要点。

## 11.1 AutoloadEquip 自动加载规则

- 护甲物品类加 `[AutoloadEquip(EquipType.Head / Body / Legs)]`，tML 自动加载同目录同名 `_Head` / `_Body` / `_Legs` 贴图。
- 装备贴图是"穿戴在角色身上的帧图"，与物品栏 20×20 图标（同名主 PNG）是**两套完全不同规格**的贴图。
- 其它装备类型：`_Wings`（[AutoloadEquip(EquipType.Wings)]）、`_Back`/`_Front`/`_HandsOn`/`_HandsOff`/`_Shoes`/`_Shield`/`_Neck`/`_Face`/`_Balloon` 等，同样是帧图。

## 11.2 装备贴图尺寸规范（tML 官方 ExampleMod 实测）

| 贴图 | 尺寸 | 结构 | 说明 |
|---|---|---|---|
| `_Head` | **40×1120** | 20 帧 × 40×56 | 覆盖全部头部动画帧 |
| `_Legs` | **40×1120** | 20 帧 × 40×56 | 覆盖全部腿部动画帧 |
| `_Body` | **360×224** | 1.4 composite 新格式：9 列×40px，4 行×56px（躯干/手臂/extended-arm 分块） | tML 对 mod body 强制 `UsesNewFramingCode=true`，**不能退回旧格式** |

- 官方参照文件：ExampleMod 的 `ExampleHelmet_Head.png`(40x1118)、`ExampleCostume_Head.png`(40x1120)、`ExampleLeggings_Legs.png`(40x1120)、`ExampleBreastplate_Body.png`(360x224)。
- 装备贴图必须透明底；帧内内容放对位置即可，**每帧可相同**。

## 11.3 帧内容位置（40×56 帧坐标系）

- **Head**：内容画在帧中央偏上 = 头部位置。官方 ExampleHelmet 约 `x10-31, y10-29`。
- **Legs**：内容画在帧下部 = 腿部位置。官方 ExampleLeggings 约 `x12-29, y42-53`；实用可放宽到 `y26-53`（大腿到小腿）。
- 头饰按类型细分（实用区域）：
  - Helmet 包住头：`(10, 8, 20, 20)`
  - Hood 头+后颈：`(9, 4, 22, 28)`
  - Mask 脸部：`(12, 12, 16, 16)`
  - Headgear 头顶：`(11, 4, 18, 14)`
- **Body** 不自己摆：直接用官方 360×224 模板布局（见 11.4）。

## 11.4 静态帧方案（推荐，省美术）

- **Head/Legs 每帧内容可完全相同**：生成/绘制一张 40×56 单帧，程序复制 20 帧拼成 40×1120 即可。
  - 官方 ExampleCostume_Head 全 20 帧 opaque 完全一致（就是静态帧）。
  - 腿部静态帧：位置正确，只是走路时腿甲不随腿摆动（许多 mod 如此，可接受）。
- **Body 布局继承 + 重着色**：以官方 `ExampleBreastplate_Body.png`（360×224）的 alpha 蒙版为模板，把本套装主题色做 HSV 色相替换（保留官方明暗/形状）→ 布局 100% 正确、颜色是本套主题。
- 反例（本次教训）：_Head/_Body/_Legs 被按**物品图标**规格生成（20×16 / 24×20 / 20×28，内容居中占满画布）→ tML 用 40×56/360×224 源矩形采样 → 越界 → **盔甲穿戴错位/花屏**。

## 11.5 修复工具（Voidfall 可复用）

- `Voidfall/tools/fix-armor-textures.ps1`：扫描 `Content/Items/Armor/*_Head/_Body/_Legs.png`，把图标缩放到帧内标准位置 → 复制 20 帧（40×1120）；Body 用 `tools/ref/ExampleBreastplate_Body.png` 模板重着色 → 360×224。原图备份到 `tools/backup-armor-<ts>/`（已 .gitignore）。
- 维护模板：`tools/ref/ExampleBreastplate_Body.png`（官方 360×224 body 布局基准）。
- 建议流程：图标（透明底）→ 生成单帧 → 拼帧，而不是让 AI 直接出整张精灵表。

## 11.6 AI 生成提示词要点（装备贴图）

- 尺寸规格写「ONE 40x56 equip frame」（单帧），不要「centered on canvas, fill 80-90%」（那是物品图标构图）。
- 位置提示：head armor 在帧上半部（头部区域）、leggings 在帧下半部（腿部区域）。
- 明确「最终精灵表 = 20 帧相同竖向拼接（40x1120）」；transparent background。
- Body 提示词指向官方 composite 模板（tools/ref/ExampleBreastplate_Body.png 布局）。