# 坐标系与绘制批次（UI 一切位置问题的根源）

## 两套批次，矩阵不同

| 批次 | 活动矩阵 | 用途 | 坐标语义 |
|---|---|---|---|
| 世界批次 | `Main.Transform` = `GameViewMatrix.TransformationMatrix`（含 zoom/相机平移） | 世界内绘制（NPC/弹幕/瓦片/DrawNPC） | **世界坐标**（无需手动减 screenPosition） |
| UI 批次 | `Main.UIScaleMatrix`（`Matrix.CreateScale(UIScale)`） | 血条/名字/物品栏/界面层 | **屏幕坐标**（需手动 `- Main.screenPosition` 把世界坐标转屏幕） |

- `Main.screenPosition == Main.Camera.UnscaledPosition`（世界相机左上角）。
- 血条、NPC 名字、MouseText 这些"世界内实体但画在 UI 层"的东西，vanilla 自己手动减 screenPosition。
- **铁律：把世界坐标画进 UI 批次，X 和 Y 都要 `- Main.screenPosition`，否则画到屏幕外数万像素处（肉眼=没画）**。

## 实测翻车案例（敌人词缀血条标签）

1. 第一版：`PostDraw` 里传世界坐标（以为在世界批次）→ 全画到屏幕外。**根因：血条绘制钩子跑在 UIScaleMatrix UI 批次**。
2. 修复：`x = barCenterX - Main.screenPosition.X - size.X/2; y = barTop - Main.screenPosition.Y + offset` → 立即可见。

## UIScale 相关

- `PlayerInput.SetZoom_UI()` 会把 `Main.screenWidth/Height` 按 1/UIScale 缩放（UI 逻辑分辨率），UI 层代码里用 `Main.screenWidth` 得到的是 UI 空间尺寸。
- 想按"屏幕中心"定位 UI 元素：`Main.screenWidth/2`（UI 空间）即可，不必手动乘 UIScale。

## 判断当前批次的技巧

- 在钩子里画一个**已知颜色的大色块**（`TextureAssets.MagicPixel.Value`），看它出现在哪——出现在错误位置说明坐标语义错了；完全不出现说明批次/触发问题。
- `SpriteBatch.Draw` 抛 `InvalidOperationException: Draw was called, but Begin has not yet been called` = 你在批次外画了（如 `QueueMainThreadAction` 在 Update 阶段执行）。
