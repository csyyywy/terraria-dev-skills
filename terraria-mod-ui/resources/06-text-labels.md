# UI 文字与血条标签细节

## 文字绘制
- `Utils.DrawBorderStringFourWay(sb, font, text, x, y, color, borderColor, Vector2.Zero, scale)` = 描边文字（黑边白字等）。
- font 用 `FontAssets.MouseText.Value`（ReLogic.Graphics.DynamicSpriteFont，非 XNA SpriteFont）。
- 逐段不同颜色：先 MeasureString 算总宽居中，再逐段 DrawBorderStringFourWay 并推进 x。

## 血条标签跟随（词缀标签案例）
- 钩子：`GlobalNPC.DrawHealthBar`（必触发，见 02）。
- 位置：`y = position.Y - Main.screenPosition.Y + 36f*scale + offset`（血条高 36px）。
- 多行：每行 `y += font.MeasureString(line).Y * scale + 2f`。
- 超长换行：`lineW + w > 250f * scale` 时换行。
- Boss 放大：`scale` 参数本身就是血条 scale（Boss 1.5f），标签同步乘它。

## 配色（敌人词缀档位）
- 普通（Common）：`Color(110,195,255)` 蓝
- 精英（Champion）：`Color(180,95,235)` 紫
- Boss 专属（BossExclusive）：`Color(255,205,60)` 金
- 白字 + 黑描边 `Color.Black * 0.8f` 保证任何背景下可读。

## 每帧遍历 NPC 自绘（UI 层方案）
- `ModifyInterfaceLayers` 插层后，`for i in Main.maxNPCs` 遍历 `Main.npc[i]`：
  过滤 `!active || life<=0 || shimmerTransparency!=0`，再 `npc.GetGlobalNPC<T>()` 拿数据。
- 比 PostDraw 可靠（不受版本签名错位影响），适合"所有带 X 的实体"类标签。
