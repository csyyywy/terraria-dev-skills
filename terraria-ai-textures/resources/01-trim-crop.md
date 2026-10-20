# 01. 透明边缘裁剪（trim）

> AI 生成图常留大片透明空白边，裁掉让内容贴边。**像素不缩放**。

## 原理

- System.Drawing 读 ARGB，取 alpha > 10（避开半透明杂点）的内容边界框，`Bitmap.Clone(Rectangle)` 裁出。
- 四边边缘均 ≤1px 视为已铺满，原样复制。

## 处理范围

可改：`Items/`（排除 `_Head/_Body/_Legs/_Wings/_Held/_Back/_Front` 等装备附加帧）、`Projectiles/`、`Buffs/`。

不可裁剪/不可改尺寸：`_Head` 40×1120、`_Body` 360×224、`_Legs` 40×1120、`_Held`、`_Wings`、Tile/Wall（按 TileObjectData 帧）、NPC 实体、`_Head_Boss` 26×26。

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

- `output_trimmed/`：裁剪结果，原 output 不动；`output_backup_<ts>/`：原图备份。
- `output_trimmed/_trim_report.csv`：验收对照 + 归一化映射表数据源。
- 验收后复制进 `Content/`；此前备份模组原贴图到 `tools/backup-content-textures-<ts>/`。

## 易错点

- alpha>10 而非 >0，避免半透明杂边被算进内容；bbox 空（全透明）标 EMPTY 警告，不要裁成 0 尺寸。
- 裁后尺寸各异（24×24 ~ 100×100）属预期，由显示归一化（02）解决。
