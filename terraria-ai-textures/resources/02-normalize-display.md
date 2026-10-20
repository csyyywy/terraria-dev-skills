# 02. 显示归一化（代码层，不改贴图像素）

> 裁剪后尺寸不一（24×24 ~ 100×100），各绘制路径缩放机制不同，用少量 Global 文件统一处理。
> 系数 = 原显示尺寸 ÷ 裁剪后尺寸（按宽度），用 `scale *=` 兼容已有 scale。

## 数据收集

每张贴图要两组尺寸，据此生成「类型 → 原宽 ÷ 裁剪后宽」映射表（Dictionary）：

- **原尺寸**：替换前 `Content/` 里的尺寸（读备份 `tools/backup-content-textures-<ts>/`）。
- **裁剪后尺寸**：读 `output_trimmed/` 或 `_trim_report.csv`。

## 三类归一化

### 1) 弹幕：`Content/Globals/ProjectileScaleGlobal.cs`（GlobalProjectile）

```csharp
public class ProjectileScaleGlobal : GlobalProjectile
{
    private static readonly Dictionary<int, float> ScaleMap = new()
    {
        [ModContent.ProjectileType<Projectiles.ExampleProjectile>()] = 10f / 77f, // 原宽 / 裁剪后宽
        // ... 全部弹幕
    };
    public override void SetDefaults(Projectile projectile)
    {
        if (ScaleMap.TryGetValue(projectile.type, out float s))
            projectile.scale *= s; // 乘法：兼容已设 scale 的弹幕（如剑气 1.6f）
    }
}
```

只影响**绘制**，碰撞盒 `Projectile.width/height` 不变；GlobalProjectile.SetDefaults 在 ModProjectile.SetDefaults 之后调用，`*=` 作用在既有 scale 上。

### 2) 增益：`Content/Globals/BuffScaleGlobal.cs`（GlobalBuff）

```csharp
public class BuffScaleGlobal : GlobalBuff
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

buff 栏固定显示且 `BuffDrawParams` 无 scale 字段 → 自绘缩放到 32×32 后 return false。

### 3) 物品手持/挥动：`Content/Globals/ItemScaleGlobal.cs`（GlobalItem）

```csharp
public class ItemScaleGlobal : GlobalItem
{
    private static readonly Dictionary<int, float> ScaleMap = new()
    {
        [ModContent.ItemType<Items.Weapons.ExampleSword>()] = 40f / 100f, // 原宽 / 裁剪后宽
        // ... 无 _Held 的物品
    };
    public override void ModifyItemScale(Item item, Player player, ref float scale)
    {
        if (ScaleMap.TryGetValue(item.type, out float s))
            scale *= s;
    }
}
```

- `ModifyItemScale` **只影响手持/挥动/世界绘制，不影响物品栏**（物品栏走 vanilla 自动缩放）。
- **有 `_Held` 手持专用图的武器排除**，只给无 `_Held` 的物品加系数；链节类贴图（如 `ExampleHookChain.png`）无 ModItem 类，不能 `ModContent.ItemType<...>()`，也排除。

### 物品栏：无需代码

vanilla `ItemSlot.Draw` 走 `DrawItem_GetColorAndScale`，超过格子上限的贴图自动等比缩到格子内，裁剪后任意尺寸都正常且更清晰。

## 命名空间陷阱

- 模组主类与命名空间同名（如 `<ModName>`）时，`Projectiles.X` / `Items.X` 会相对解析为 `<ModName>.Content.Projectiles.X`。
- `Dictionary` 依赖 `global using System.Collections.Generic`（GlobalUsings.cs），确保存在。
