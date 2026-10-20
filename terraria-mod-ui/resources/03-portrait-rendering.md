# 角色画像渲染（spriteBuffer 直绘绕过 UI 批次）
## 问题：`Main.PlayerRenderer.DrawPlayer` 在 UI 批次里画不出来
1.4.4 玩家渲染走 `PlayerDrawLayers.DrawPlayer_RenderAllLayers` → `Main.spriteBuffer`（SpriteDrawBuffer）直接 `DrawIndexedPrimitives`，绕过 UI 的 SpriteBatch，画像不可见或被覆盖。vanilla `UICharacter` 的解法是 `UseImmediateMode = true`（立刻刷出到屏幕），1.4.4 下还需 `CurrentPlayerOverride` 包裹。
## 正解：`DrawPlayer_RenderAllLayersSlow`
tML 1.4.4 未 patch 这个方法，保持 vanilla public，内部走普通 `sb.Draw`，因此能在 UI 批次里画。
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
- 坐标换算：`DrawPlayer_TransformDrawData` 让每层 `position -= Main.screenPosition`，所以要传入世界坐标（`uiPos + Main.screenPosition`），层画出来即 UI 像素；`DrawPlayer_ScaleDrawData` 的缩放锚点是 `drawinfo.Position + Size*(0.5,1) - screenPosition`（脚底）。
- 画笔批次：`sb.Begin(Immediate, AlphaBlend, PointClamp, None, CullNone, null, Main.UIScaleMatrix)`，画完恢复 `Deferred`。
## 克隆玩家：`SerializedClone()` 而非 `clientClone()`
- `clientClone()` 只拷网络状态 + armor/dye/miscEquips 数组，不拷 `headSlot/bodySlot/legSlot`（SetDefaults 时算的派生渲染字段）→ 画像裸体；`SerializedClone()` 全量序列化（vanilla UICharacter 的 `useAClone` 路径）→ 装备正常显示。
- 画前准备顺序（vanilla UICharacter 配方）：`ResetEffects → ResetVisibleAccessories → UpdateMiscCounter → UpdateDyes → PlayerFrame`，再包一层 `using var _ = new Main.CurrentPlayerOverride(clone);`（tML 1.4.4 UICharacter patch 同样如此）。
## 调试点
画像空白而面板其他元素正常 → 先查面板高度与元素尺寸（`StyleDimension` 写反 → 高 0.54px），再查绘制批次；品红探针矩形 + 黄色定位线可确认元素区域大小与位置。
