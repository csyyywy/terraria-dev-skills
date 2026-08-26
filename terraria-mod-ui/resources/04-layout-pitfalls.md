# 布局与控件坑

## `StyleDimension(precent, pixels)` —— 参数顺序陷阱（最高频 bug）
- 签名：`StyleDimension(float pixels, float percent)`。
- **第一个参数 = 固定像素，第二个 = 父容器百分比**。
- 写反 `new StyleDimension(PORTRAIT_H, 0f)` = 0.54 **像素** → 面板高 0.54px，元素全在屏幕外/不可见（画像空白 bug 根因之一）。
- 正确：`new StyleDimension(0f, 0.54f)`（0px + 父高 54%）。

## UIList 行乱序
- UIList 默认排序是**不稳定**的 `List.Sort`（常量 CompareTo）→ 添加顺序会被打乱。
- 修复：`list.ManualSortMethod = _ => { };`（保持插入顺序）。

## UIImage 图标居中/尺寸
- `UIImage` + `UseTextureSizeForOrigin` 按贴图尺寸居中；若贴图 32x32 而显示区 18x18，会偏移/模糊。
- 正解：自定义 `IconElement`（UIImage 子类）在 DrawSelf 里按目标矩形精确 Draw，配合 `ImageScale`/`OverrideSamplerState = SamplerState.PointClamp` 保持像素风。

## 其他
- 图片/图标"下移一行"类微调：直接调元素 `Top`（负数 = 上移），如 `Top = new StyleDimension(-6, 0f)`。
- 面板左右收窄：固定中心（`X + W/2` 不变）同时改 X 和 W，行内容宽同步改。
- `UIElement` 默认没有背景绘制；面板背景用 `Main.Asset<Texture2D>("Images/UI/PanelBackground")` 九宫格或自绘。
