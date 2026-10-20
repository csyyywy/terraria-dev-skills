---
name: terraria-ai-textures
description: 泰拉瑞亚模组 AI 贴图管线：贴图尺寸规范与生成提示词（CSV）→ 透明边缘裁剪（trim）→ 显示归一化（弹幕 / 增益 / 物品手持 scale）→ 替换进模组 / 备份 / 验证。
whenToUse: 需要用 AI 生成或批量替换 tModLoader 模组贴图，或处理"贴图有透明空白边、尺寸不统一、游戏内显示大小不对"等问题时加载。
---

# 泰拉瑞亚 AI 贴图管线

目标：AI 生成大画布高质量贴图 → 裁掉透明空白边缘 → 在游戏内显示归一化。
**全程不缩放像素、不逐个改类文件**，用少量 Global 文件统一处理。

## 触发场景

- 用 AI 生成或替换模组贴图
- 贴图带大量透明边缘 / 空白边，影响展示
- 图标、弹幕、武器挥动大小不对，尺寸不统一
- 需要把可改尺寸的图标统一放大到固定宽度再绘制

## 总流程

生成规范（CSV + 提示词）→ AI 生成到 `output/` → 裁剪透明边缘 → 替换进 `Content/` → 代码层归一化显示 → 构建 / 打包 / 无头验证 → 真机验收。

## 三条硬约束

1. **只裁透明边缘，绝不缩放像素**——像素缩放会破坏像素结构与清晰度。
2. **归一化放在显示层做**——文件尺寸保持裁剪后的原样，靠 scale 让游戏显示为正常大小。
3. **三处备份**：AI 原图 / 裁剪结果 / 模组原贴图，保证每步可回滚。

## 关键路径（占位符）

| 作用 | 路径 |
|---|---|
| AI 输出（目录结构镜像 `Content/`） | `output/` |
| 裁剪结果 | `output_trimmed/` |
| AI 原图备份 | `output_backup_<时间戳>/` |
| 模组原贴图备份 | `<Mod>/tools/backup-content-textures-<时间戳>/` |
| 显示归一化 Global | `<Mod>/Content/Globals/ProjectileScaleGlobal.cs`、`BuffScaleGlobal.cs`、`ItemScaleGlobal.cs` |
| 生成规范 CSV | `<Mod>/tools/texture-replace-sheet.csv`（全量）、`texture-replace-sheet-icons.csv`（可改尺寸图标专用） |

## 分册索引

- `resources/01-trim-crop.md` 透明边缘裁剪——alpha 边界框 + 备份 + 报告
- `resources/02-normalize-display.md` 三类显示归一化——弹幕 / 增益 / 物品手持
- `resources/03-texture-spec.md` 贴图尺寸规范——可改 vs 固定分类、生成提示词

## 验收清单

- [ ] 严格构建 0 错 0 警：`build -c Debug -p:BuildMod=false -p:TargetFramework=net8.0 -p:ImplicitUsings=disable`
- [ ] 全量打包 0 错 0 警，且无头服务器加载通过 Adding / Configuring / Finalizing Content
- [ ] 真机确认：物品栏图标清晰不溢出、弹幕大小如常、武器挥动大小如常、增益图标统一 32×32
- [ ] 三处备份齐全且可回滚
