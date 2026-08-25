# 02. 显示归一化（代码层，不改贴图像素）

> 裁剪后每张贴图尺寸不一（24×24 ~ 100×100）。游戏各绘制路径缩放机制不同，用少量 Global 文件统一处理。
> 核心：归一化系数 = 原显示尺寸 ÷ 裁剪后尺寸（按宽度），用乘法（scale *=）兼容已有 scale 的实体。

## 数据收集（映射表前提）

每个贴图需要两组尺寸：
- **目标（原）尺寸**：模组 Content/ 里被替换前的尺寸（备份 `tools/backup-content-textures-<ts>/` 里读）。
- **裁剪后尺寸**：output_trimmed/（或 `_trim_report.csv`）读。

生成「类型 → 原宽 ÷ 裁剪后宽」映射表（C# Dictionary）。

## 三类归一化（Voidfall 实例文件）

### 1) 弹幕：`Content/Globals/VoidfallProjectileGlobal.cs`（GlobalProjectile）

```csharp
public class VoidfallProjectileGlobal : GlobalProjectile
{
    private static readonly Dictionary<int, float> ScaleMap = new()
    {
        [ModContent.ProjectileType<Projectiles.VoidBullet>()] = 10f / 77f, // 原宽 / 裁剪后宽
        // ... 全部弹幕
    };
    public override void SetDefaults(Projectile projectile)
    {
        if (ScaleMap.TryGetValue(projectile.type, out float s))
            projectile.scale *= s; // 乘法：兼容已设 scale 的弹幕（如剑气 1.6f）
    }
}
```
- 只缩放**绘制**，碰撞盒 `Projectile.width/height` 不变。
- GlobalProjectile.SetDefaults 在 ModProjectile.SetDefaults 之后调用，`*=` 作用在既有 scale 上。

### 2) 增益：`Content/Globals/VoidfallBuffGlobal.cs`（GlobalBuff）

```csharp
public class VoidfallBuffGlobal : GlobalBuff
{
    private const float TargetSize = 32f; // buff 栏统一显示尺寸
    public override bool PreDraw(SpriteBatch spriteBatch, int type, int buffIndex, ref BuffDrawParams drawParams)
    {
        if (ModContent.GetModBuff(type)?.Mod != Mod) return true; // 只处理本模组
        var src = drawParams.SourceRectangle;
        float scale = TargetSize / src.Width;
        int w = (int)MathF.Ceiling(src.Width * scale);
        int h = (int)MathF.Ceiling(src.Height * scale);
        var pos = drawParams.Position;
        spriteBatch.Draw(drawParams.Texture, pos, src, drawParams.DrawColor, 0f, Vector2.Zero, scale, SpriteEffects.None, 0f);
        drawParams.MouseRectangle = new Rectangle((int)pos.X, (int)pos.Y, w, h);
        return false; // 阻止默认绘制
    }
}
```
- buff 栏固定显示、`BuffDrawParams` 无 scale 字段 → 自绘缩放到 32×32 并 return false。

### 3) 物品手持/挥动：`Content/Globals/VoidfallItemScaleGlobal.cs`（GlobalItem）

```csharp
public class VoidfallItemScaleGlobal : GlobalItem
{
    private static readonly Dictionary<int, float> ScaleMap = new()
    {
        [ModContent.ItemType<Items.Weapons.VoidEdge>()] = 40f / 100f, // 原宽 / 裁剪后宽
        // ... 无 _Held 的物品
    };
    public override void ModifyItemScale(Item item, Player player, ref float scale)
    {
        if (ScaleMap.TryGetValue(item.type, out float s))
            scale *= s;
    }
}
```
- `ModifyItemScale` **只影响手持/挥动/世界绘制，不影响物品栏**（物品栏走 vanilla 自动缩放，大贴图自动缩到格子内）。
- **有 `_Held` 手持专用图的武器排除**（手持用原尺寸 _Held，不受裁剪影响）；只给无 _Held 的物品加系数。
- 注意：链节类贴图（如 VoidfallHookChain.png）没有 ModItem 类，不能 `ModContent.ItemType<...>()`，排除。

### 物品栏：无需代码

- vanilla `ItemSlot.Draw` 走 `DrawItem_GetColorAndScale`，对超过格子上限的大贴图自动等比缩放到格子内。裁剪后任意尺寸的物品图标在物品栏都正常且更清晰。

## 命名空间陷阱

- 模组主类与命名空间同名（Voidfall）时，Global 文件里写 `Projectiles.X` / `Items.X` 解析为 `Voidfall.Content.Projectiles.X` 等（相对解析）。
- `Dictionary` 依赖 `global using System.Collections.Generic`（GlobalUsings.cs），确保存在。