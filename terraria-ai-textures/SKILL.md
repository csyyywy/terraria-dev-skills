---
name: terraria-ai-textures
description: 泰拉瑞亚模组 AI 生成贴图的完整管线：贴图尺寸规范/生成提示词(CSV) → 透明边缘裁剪(trim) → 显示归一化(弹幕/增益/物品 scale) → 替换进模组/备份/验证。当用户提出"AI 生成贴图、贴图有透明空白边、尺寸不统一、显示大小不对"等需求时加载。
whenToUse: 处理 tModLoader 模组 AI 贴图：生成规范、裁剪透明边缘、统一显示大小、替换进模组。
---

# 泰拉瑞亚 AI 贴图管线（terraria-ai-textures）

> 2026-08 实战沉淀（Voidfall 归墟纪元 147 张贴图全流程）。目标：AI 生成大画布高质量贴图 → 裁剪掉透明空白边缘 → 游戏内显示归一化。**全程不缩放像素、不改每个类文件**，用少量 Global 文件统一处理。

## 触发场景

用户提以下需求时加载本 skill：
- "用 AI 生成/替换模组贴图"
- "贴图有大量透明边缘 / 空白边，影响展示"
- "图标/弹幕/武器挥动大小不对 / 尺寸不统一"
- "要能改大小的图标统一放大到 100 宽方便绘制"

## 总流程

1. 生成规范(CSV+提示词) → 2. AI 生成到 output/ → 3. 裁剪透明边缘(trim)
→ 4. 替换进 Content/ → 5. 代码归一化显示 → 6. 严格构建+打包+无头验证 → 7. 真机验收

## 三条铁律

1. **只裁剪透明边缘，绝不缩放像素**——像素缩放会破坏像素结构/清晰度。
2. **归一化在代码显示层做**——文件尺寸保持裁剪后原样，用 scale 让游戏显示为正常大小。
3. **备份三处**：AI 原图 / 裁剪结果 / 模组原贴图，每步可回滚。

## 关键路径（Voidfall 实例）

| 作用 | 路径 |
|---|---|
| AI 输出（路径镜像 Content/） | <COMFYUI_OUTPUT>\ |
| 裁剪结果 | output_trimmed\ |
| AI 原图备份 | output_backup_<时间戳>\ |
| 模组原贴图备份 | <Mod>\tools\backup-content-textures-<时间戳>\ |
| 归一化 Global | <Mod>\Content\Globals\VoidfallProjectileGlobal.cs / VoidfallBuffGlobal.cs / VoidfallItemScaleGlobal.cs |
| 生成规范 CSV | <Mod>\tools\texture-replace-sheet.csv（全量） + texture-replace-sheet-icons.csv（可改图标专属） |

## 详细分册

- resources/01-trim-crop.md：透明边缘裁剪（alpha 边界框 + 备份 + 报告）
- resources/02-normalize-display.md：三类显示归一化（弹幕 / 增益 / 物品手持）
- resources/03-texture-spec.md：贴图尺寸规范 + 可改 vs 固定分类 + 生成提示词

## 验收清单（交付前逐项确认）

- [ ] 严格构建 0 错 0 警：build -c Debug -p:BuildMod=false -p:TargetFramework=net8.0 -p:ImplicitUsings=disable
- [ ] 全量打包 0 错 0 警 + 无头 server 加载 Adding/Configuring/Finalizing Content 通过
- [ ] 真机：物品栏图标清晰不溢出、弹幕大小如常、武器挥动大小如常、增益图标统一 32×32
- [ ] 三处备份齐全、可回滚