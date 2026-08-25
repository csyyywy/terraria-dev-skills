# 01. 透明边缘裁剪（trim）

> 目标：AI 生成图常有大量透明空白边缘（内容只占画布一小块），先裁掉，让内容贴边。**像素不缩放**。

## 原理

- 用 System.Drawing 读 ARGB，统计 alpha > 10（阈值，避开半透明杂点）的内容边界框 (minX,minY)-(maxX,maxY)。
- 边界框裁剪（Bitmap.Clone(Rectangle)），得到内容贴边的新图。
- 若内容已铺满（四边边缘 ≤1px）则原样复制，不裁。

## 处理范围（分类铁律）

只处理**可改变大小**的贴图：
- `Items/`（物品图标，排除 `_Head/_Body/_Legs/_Wings/_Held/_Back/_Front` 等装备附加帧）
- `Projectiles/`（弹幕）
- `Buffs/`（增益图标）

**不可裁剪/不可改尺寸**（保持原规格）：装备帧（`_Head` 40×1120、`_Body` 360×224、`_Legs` 40×1120）、`_Held`、`_Wings`、Tile/Wall（按 TileObjectData 帧）、NPC 实体、Boss 地图头像（`_Head_Boss` 26×26）。

## 脚本要点（PowerShell + System.Drawing）

```powershell
# 遍历 Items/Projectiles/Buffs 的 png
# 1) 备份原图 -> output_backup_<ts>/（保持相对路径）
# 2) LockBits 读 ARGB，算内容 bbox（alpha>10）
# 3) bbox 到画布边缘均 <=1px -> 原样复制；否则 Clone(bbox)
# 4) 保存 -> output_trimmed/<相对路径>（**不缩放**）
# 5) 输出裁剪报告 CSV（Path, Old=原尺寸, New=裁剪后尺寸）
```

## 输出与备份

- 裁剪结果：`output_trimmed/`（原 output 目录不动）
- 原图备份：`output_backup_<时间戳>/`
- 裁剪报告：`output_trimmed/_trim_report.csv`（供用户验收对照，也是归一化映射表的数据源）
- 验收后再把 `output_trimmed/` 复制进模组 `Content/`（先备份模组原贴图到 `tools/backup-content-textures-<ts>/`）。

## 易错点

- 阈值 alpha>10 而非 >0：避免半透明杂边被误算进内容。
- 内容全透明（bbox 空）要标记 EMPTY 警告，不要 0 尺寸裁剪。
- 非方形裁剪后尺寸各异（24×24 ~ 100×100），这是预期——由显示归一化（02）解决。