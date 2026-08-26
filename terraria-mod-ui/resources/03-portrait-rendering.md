# 角色画像渲染（spriteBuffer 直绘绕过 UI 批次）

## 问题：`Main.PlayerRenderer.DrawPlayer` 在 UI 批次里画不出来
- 1.4.4 玩家渲染走 `PlayerDrawLayers.DrawPlayer_RenderAllLayers` → `Main.spriteBuffer`（SpriteDrawBuffer）直接 `DrawIndexedPrimitives`，**绕过 UI 的 SpriteBatch** → 画像在面板里不可见/被覆盖。
- vanilla `UICharacter` 的解法是 `UseImmediateMode = true`（立刻刷出到屏幕），但 1.4.4 下 UICharacter 还有 `CurrentPlayerOverride` 包裹。

## 正解：`DrawPlayer_RenderAllLayersSlow`（vanilla 公开方法，走普通 sb.Draw）
tML 1.4.4 未 patch 它 → 保持 vanilla public，用 `Main.spriteBatch.Draw` 逐层画 → 能在 UI 批次里画。

```csharp
public static void DrawPlayer(SpriteBatch sb, Player player, Vector2 uiPos, float scale) {
    // 1. BoringSetup（vanilla：清空 drawData/dust/gore，算基础变换）
    //    uiPos 传世界坐标（uiPos + Main.screenPosition）——见下
    // 2. PlayerLoader.ModifyDrawInfo
    // 3. foreach (PlayerDrawLayerLoader.GetDrawLayers(drawInfo)) layer.DrawWithTransformationAndChildren
    // 4. DrawPlayer_MakeIntoFirstFractalAfterImage
    // 5. DrawPlayer_TransformDrawData（每层位置 - Main.screenPosition → 净成 UI 像素）
    // 6. DrawPlayer_ScaleDrawData(scale)（锚点 = feet：position + Size*(0.5,1) - screenPosition）
    // 7. PlayerLoader.TransformDrawData
    // 8. PlayerDrawLayers.DrawPlayer_RenderAllLayersSlow(drawInfo)  // vanilla 公开，普通 sb.Draw
}
```

## 关键参数语义
- `DrawPlayer_ScaleDrawData` 锚点 = `drawinfo.Position + Size*(0.5,1) - screenPosition`（脚底）。
- `DrawPlayer_TransformDrawData` 里每层 `position -= Main.screenPosition` → **传入世界坐标**（`uiPos + Main.screenPosition`），层画出来就是 UI 像素。
- 画笔批次：`sb.Begin(Immediate, AlphaBlend, PointClamp, None, CullNone, null, Main.UIScaleMatrix)`，画完恢复 `Deferred` 批次。

## 克隆玩家：`SerializedClone()` 而非 `clientClone()`
- `clientClone()` 只拷网络状态 + armor/dye/miscEquips 数组，**不拷 `headSlot/bodySlot/legSlot`**（SetDefaults 时算的派生渲染字段）→ 画像裸体。
- `SerializedClone()` 全量序列化（vanilla UICharacter `useAClone` 路径）→ 正确显示装备。
- 画前准备顺序（vanilla UICharacter 配方）：
  `ResetEffects → ResetVisibleAccessories → UpdateMiscCounter → UpdateDyes → PlayerFrame`
- 包一层 `using var _ = new Main.CurrentPlayerOverride(clone);`（tML 1.4.4 UICharacter patch 也这么做）。

## 调试点
- 画像完全空白 + 面板其他元素正常 → 先怀疑**面板高度/元素尺寸**（StyleDimension 写反 → 高度 0.54px），再怀疑绘制批次。
- 品红探针矩形 + 黄色定位线能快速区分"元素区域多大/在哪"。
