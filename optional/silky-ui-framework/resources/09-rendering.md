# 渲染管线

## 绘制入口

```
On_Main.DrawThickCursor → SilkyUIManager.Draw
    → SilkyUIRenderSystem.Draw（全局栈：Global UI）
    → ModifyInterfaceLayers 插入的 SilkyUILayer.DrawSelf（Game UI，按图层顺序）
```

### 全局 UI 绘制（SilkyUIRenderSystem.Draw）

```csharp
var orderedUIs = _globalStack.OrderedUIs;
for (int i = orderedUIs.Count - 1; i >= 0; i--)   // 逆序：高优先级后画
{
    var ui = orderedUIs[i];
    ui.TransformMatrix = Main.UIScaleMatrix;
    spriteBatch.ReBegin(SpriteSortMode.Deferred, null, null, null,
        SilkyUI.ScissorRasterizerState, null, ui.TransformMatrix);
    ui.Draw(gameTime, Main.spriteBatch);
}
```

### Game UI 绘制（SilkyUILayer）

```csharp
public override bool DrawSelf()
{
    var matrix = ScaleType switch
    {
        InterfaceScaleType.Game => Main.GameViewMatrix.ZoomMatrix,
        InterfaceScaleType.UI => Main.UIScaleMatrix,
        { } => Matrix.Identity,
    };
    sb.End();
    sb.Begin(SpriteSortMode.Deferred, null, null, null, SilkyUI.ScissorRasterizerState, null, matrix);
    SilkyUI.TransformMatrix = matrix;
    SilkyUI.Draw(Main.gameTimeCache, Main.spriteBatch);
    return true;
}
```

- `TransformMatrix` 决定整棵 UI 树的坐标系（UI 缩放或 Game 缩放）。
- `RasterizerState` 用 `SilkyUI.ScissorRasterizerState`（`CullMode.None` + `ScissorTestEnable`）：UI 平面不被背面剔除，且支持裁剪。
- Game UI 由 `ModifyInterfaceLayers` 插到指定 `LayerNode` 之后：`layers.Insert(index+1, new SilkyUILayer(...))`。

## SilkyUI.Draw 每帧流程

1. `RootNode == null` 直接 return；否则 `PlayerInputHelper.SetZoom(TransformMatrix)`。
2. `RootNode.Initialize()`；`!RootNode.Enabled` 时 return。
3. `UpdateLayout()` → `UpdatePosition()` → `UpdateElementsOrder()`（布局，脏标记驱动；位置；ZIndex 排序）。
4. `HandleUpdateStatus(gameTime)`：状态与动画；`!RootNode.Enabled` 时 return。
5. 状态可能影响布局，再跑一遍 `UpdateLayout()` / `UpdatePosition()` / `UpdateElementsOrder()`。
6. `HandleDraw(gameTime, spriteBatch)` 绘制。

## 每个元素的绘制链

```
HandleDraw → Draw → RectangleRender（阴影 + 背景/边框矩形）
UIElementGroup.HandleDraw → base + DrawChildren
BaseBody.HandleDraw → (UseRenderTarget ? 离屏) → DrawBodyCore
```

- `UIView.Draw`：`RectangleRender.DrawShadow(position, size, ref matrix)` + `RectangleRender.Draw(position, size, ref matrix)`。
- `RectangleRender`：`BorderRadius`（Vector4 圆角）、`Border`/`BorderColor`、`BackgroundColor`、`ShadowSize`/`ShadowBlurSize`/`ShadowColor`。
- 圆角矩形用 SDF（有向距离场）shader 绘制（`Graphics2D/SDFRectangle.fx`），比九宫格平滑。

## OverflowHidden 裁剪（两种模式）

`UIElementGroup.DrawChildren`：

- `OverflowHidden=false`：按 `ElementsInOrder` 直接绘制子元素。
- `OverflowHidden=true`：先 `sb.End()`，用 `GetClippingRectangle(sb)` 取屏幕空间裁剪矩形，再按模式绘制：
  - **模式 A**（`IndependentRenderTarget=true`，默认）：裁剪矩形宽高均 > 0 时，`RenderTargetPool.Rent` 离屏 → 只画 `OuterBounds` 与 `InnerBounds` 相交的子元素 → `DrawRenderTarget` 回贴 → `Return`。
  - **模式 B**（其余情况）：直接设 `device.ScissorRectangle = scissorRectangle` 裁剪。
- `GetClippingRectangle`：按 `HiddenBox`（Outer/Middle/Inner）选盒 → Transform 到屏幕空间 → 与当前 `ScissorRectangle` 取交集。
- `RenderTargetPool` 租借 / 归还 RenderTarget，避免每帧分配。

## BaseBody 离屏合成（过渡动画）

```csharp
public virtual bool UseRenderTarget { get; set; } = false;
public virtual float Opacity { get; set; } = 1f;         // 回贴透明度
public Matrix RenderTargetMatrix = Matrix.CreateScale(1f, 1f, 1f);  // 回贴矩阵
public virtual bool EnableBlur { get; set; } = false;    // 背景模糊
public virtual IEnumerable<UIView> BlurElements => [this];  // 模糊采样元素
```

重写 `HandleDraw(GameTime gameTime, SpriteBatch spriteBatch)`：`UseRenderTarget || _captureRequested` 为 true 时走 `DrawWithRenderTarget`（离屏绘制 → 回贴，应用 `Opacity` 与 `RenderTargetMatrix`），否则走 `DrawBodyCore`。

典型用法（框架示例 MouseMenuUI）：开关菜单时 `UseRenderTarget = _switchTimer.IsUpdating`、`Opacity = _switchTimer.Lerp(0f, 1f)`、`RenderTargetMatrix = Matrix.CreateTranslation(0, Lerp(10f, 0), 0)`，得到淡入 + 上滑。

## 模糊背景（BlurMakeSystem）

- 启用：`EnableBlur = true`（BaseBody）；全局开关 `BlurMakeSystem.EnableBlur`（默认 true）。
- 可用条件：`BlurAvailable = EnableBlur && Lighting.NotRetro`（复古光照下不可用）。
- `SingleBlur=false`：全局模糊（`On_Main.DrawInterface` 前 `KawaseBlur(Main.screenTarget)` 一次，所有 UI 共享）；`SingleBlur=true`：每个 UI 单独计算。
- `KawaseBlur`：迭代式降采样模糊，`BlurIterationCount` 默认 3。
- `BlurElements`：参与模糊采样的元素集合（默认仅容器自身），可重写为 `[MenuContainer]` 只模糊菜单区域。

## 截图

```csharp
public void RequestScreenshot();     // 标记下一帧截图
public string ScreenshotSavePath;    // 默认：我的文档\My Games\Terraria\tModLoader\{ClassName}.png
```

`DrawWithRenderTarget` 中 `_captureRequested` 为 true 时强制走离屏并 `SaveAsPng`，游戏内输出保存路径。

## RenderTargetPool

`[Service]` 单例，按尺寸分组缓存 `RenderTarget2D`；`Rent(w,h)` / `Return(rt)`，归还未租借的会抛异常。

## 绘制顺序总结

1. 全局栈（Global UI）：高优先级后画（最上层）。
2. 游戏图层栈：按 `_layerOrder` 逆序（后插入的图层先画）。
3. 同容器内：`ElementsInOrder` 由 `ElementsCache.OrderBy(ZIndex)` 得到，ZIndex 大者后画。
4. 命中测试顺序相反：先查最上层。

## 常见坑

1. **批次状态**：框架在图层切换时 `End`/`Begin` 管理批次；自定义绘制里别随意 `End`/`Begin`，否则破坏裁剪状态。
2. **Scissor 越界**：`GetClippingRectangle` 与设备当前 Scissor 取交集。
3. **模糊失效**：先查 `Lighting.NotRetro`（复古光照开启时不可用）与 `EnableBlur`。
4. **独立 RenderTarget 模式卡顿**：大量 `OverflowHidden` 容器每帧离屏开销大，优先 Scissor 模式（`IndependentRenderTarget=false`）或减少嵌套。
