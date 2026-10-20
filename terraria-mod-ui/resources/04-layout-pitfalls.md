# 布局与控件坑
## `StyleDimension(percent, pixels)` —— 参数顺序陷阱
签名是 `StyleDimension(float pixels, float percent)`：**第一个参数是固定像素，第二个是父容器百分比**。写反成 `new StyleDimension(PORTRAIT_H, 0f)` 就变成 0.54 像素，面板高 0.54px，元素全跑出屏幕（画像空白的根因之一）；正确写法 `new StyleDimension(0f, 0.54f)`（0px + 父高 54%）。
## UIList 行乱序
UIList 默认用不稳定的 `List.Sort`（常量 CompareTo），添加顺序会被打乱。修复：`list.ManualSortMethod = _ => { };`（保持插入顺序）。
## UIImage 图标居中/尺寸
`UIImage` + `UseTextureSizeForOrigin` 按贴图尺寸居中，32x32 贴图画进 18x18 区域会偏移、模糊。正解：自定义 `IconElement`（UIImage 子类），在 DrawSelf 里按目标矩形精确 Draw，配 `ImageScale` / `OverrideSamplerState = SamplerState.PointClamp` 保持像素风。
## 其他
- 图标"下移一行"类微调直接调元素 `Top`（负数 = 上移），如 `Top = new StyleDimension(-6, 0f)`。
- 面板左右收窄要保持中心不动：`X + W/2` 不变，同时改 X 和 W，行内容宽同步改。
- `UIElement` 默认不画背景；面板背景用 `Main.Asset<Texture2D>("Images/UI/PanelBackground")` 九宫格或自绘。
