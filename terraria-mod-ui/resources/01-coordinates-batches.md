# 坐标系与绘制批次
## 两套批次，矩阵不同

| 批次 | 活动矩阵 | 用途 | 坐标语义 |
|---|---|---|---|
| 世界批次 | `Main.Transform` = `GameViewMatrix.TransformationMatrix`（含 zoom/相机平移） | 世界内绘制（NPC/弹幕/瓦片/DrawNPC） | **世界坐标**，无需减 screenPosition |
| UI 批次 | `Main.UIScaleMatrix`（`Matrix.CreateScale(UIScale)`） | 血条/名字/物品栏/界面层 | **屏幕坐标**，需手动 `- Main.screenPosition` |

`Main.screenPosition == Main.Camera.UnscaledPosition`（世界相机左上角）。血条、NPC 名字、MouseText 是"世界内实体但画在 UI 层"，vanilla 同样手动减 screenPosition；**世界坐标进 UI 批次时 X 和 Y 都要 `- Main.screenPosition`**，否则画到屏幕外数万像素处，等同没画。
## 典型错位：血条标签不可见
1. `PostDraw` 里传世界坐标（误以为在世界批次）→ 全部画到屏幕外；根因是该钩子跑在 UIScaleMatrix UI 批次。
2. 修复：`x = barCenterX - Main.screenPosition.X - size.X/2; y = barTop - Main.screenPosition.Y + offset` → 立即可见。
## UIScale 相关
`PlayerInput.SetZoom_UI()` 把 `Main.screenWidth/Height` 按 1/UIScale 缩放进 UI 逻辑分辨率，所以 UI 层代码取到的就是 UI 空间尺寸；按屏幕中心定位用 `Main.screenWidth/2` 即可，不必再乘 UIScale。
## 判断当前批次的技巧
- 色块探针：在钩子里画已知颜色的实心大色块（`TextureAssets.MagicPixel.Value`）。出现在错误位置 = 坐标语义错；完全不出现 = 批次或触发问题。
- `SpriteBatch.Draw` 抛 `InvalidOperationException: Draw was called, but Begin has not yet been called` = 在批次外绘制（如 `QueueMainThreadAction` 在 Update 阶段执行）。
