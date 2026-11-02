# 内置控件速查

> 完整控件文档：仓库 `Elements.md`。

## 基础控件

### UIView（XML: `View`）

所有元素的基类。

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `Width/Height/Min/Max` | `Dimension` | 尺寸（`SetSize/SetWidth/SetHeight`） |
| `Padding/Margin` | `Margin` | 内/外边距（`SetPadding/SetMargin`） |
| `BackgroundColor` | `Color` | 背景 |
| `Border` | `float` | 边框宽度 |
| `BorderColor` | `Color` | 边框颜色 |
| `BorderRadius` | `Vector4` | 圆角（左↑、右↑、右↓、左↓） |
| `Positioning` | `Positioning` | `Relative/Absolute/Sticky/Fixed/Static` |
| `IgnoreMouseInteraction` | `bool` | 忽略鼠标交互（**不影响**子元素） |
| `DisableMouseInteraction` | `bool` | 禁用鼠标交互（**影响**子元素） |
| `Invalid` | `bool` | 无效（不参与布局/更新/绘制，等效隐藏） |
| `ZIndex` | `int` | 同级绘制顺序（小→大） |
| `BoxSizing` | `BoxSizing` | `Border`/`Content` |
| `FlexGrow/FlexShrink` | `float` | Flexbox 子项 |
| `RowSpan/ColumnSpan` | `GridSpan` | Grid 子项 |
| `Opacity` | `float` | 全局透明度（BaseBody） |

事件：`MouseEnter/MouseLeave/MouseDown/MouseUp/MouseClick`，详见 07-events-input.md。

### UIElementGroup（XML: `ElementGroup`）

容器。`OverflowHidden`（溢出裁剪）、`IndependentRenderTarget`（裁剪时用独立 RenderTarget，`OverflowHidden=true` 时生效）、`Children`/`ChildrenCache`（子元素列表，只读）；`Gap`/`LayoutType`/Flexbox 系列见 04-flexbox.md。

方法：`AddChild(child, index?)`、`RemoveChild`、`RemoveAllChildren`、`IndexOf`。

### BaseBody（XML: `Body`）

根容器，继承 `UIElementGroup`。构造默认：尺寸 480×270（16:9），`Gap=10`、`Positioning=Fixed`、`Border=2` 黑、`BackgroundColor=White*0.25`、`LayoutType=Flexbox`、`FlexDirection=Column`、`MainAlignment=Start`、`FlexWrap=false`。

`Enabled`（false = 不更新不绘制不命中）、`IsInteractable`（命中测试前置条件）、`UseRenderTarget`（离屏合成，过渡动画用）、`EnableBlur`（背景模糊）、`BlurElements`（模糊采样元素集合）。

## 文本控件

### UITextView（XML: `TextView`）

| 属性 | 说明 |
| --- | --- |
| `Text` | 文本（支持泰拉 RichText 标签如 `[c/ff0000:红]`、`\n` 换行） |
| `Font` | 默认 `FontAssets.MouseText.Value`；`UseDeathText()`/`UseMouseText()` |
| `WordWrap` | 自动换行 |
| `MaxLines` | 最大行数（-1 不限） |
| `TextScale` | 缩放（默认 1） |
| `TextColor/TextBorder/TextBorderColor` | 颜色/描边 |
| `TextOffset/TextPercentOffset/TextPercentOrigin/TextAlign` | 定位（0~1 对齐） |
| `IgnoreTextColor` | 忽略片段颜色 |
| `MaximumCharacters` | 最大字符（仅输入时） |
| `TextSize` | 只读，测量尺寸 |

事件：`ContentChanging`（可改新值）、`ContentChanged`。

```csharp
var tv = new UITextView { Text = "Hello", TextColor = Color.Yellow, TextScale = 1.5f, WordWrap = true }.Join(this);
```

### SUIEditText（XML: `EditText`）

继承 `UITextView` 的输入框，支持占位符、光标、Ctrl+X/C/V、长按退格加速、Shift+Enter 换行。

`Placeholder`（占位符）、`PlaceholderColor`/`PlaceholderBorderColor`（占位符配色）、`CursorColor`/`CursorFlashColor`（光标配色）、`CursorIndex`（光标位置）、`OccupyPlayerInput`（接管键盘输入，构造默认 true）。

事件：`OnEnterKeyDown`、`StartTakingInput`、`EndTakingInput`。

## 交互控件

### SUISlider（XML: `Slider`）

`Value`（0~1 当前值）、`Step`（步进，0=连续）、`SnapByStep`（吸附）、`DragCommand`（拖拽命令）。事件 `ValueChanged`、`Drag`。内置 `Track`（轨道）、`Thumb`（滑块）、`ProgressBar`，支持点击轨道直接跳值。

### SUIToggleSwitch（XML: `ToggleSwitch`）

`Status`（bool 开关）。事件 `OnStatusChanges`；点击即切换，带动画。

### SUIScrollbar

`CurrentScrollPosition`（当前滚动位置，Vector2）、`TargetScrollPosition`（目标，带动画滚动）、`GetScrollRange()`（可滚动范围 = ContentSize - ContainerSize）、`ScrollByTop()`/`ScrollByEnd()`/`HScrollBy()`/`VScrollBy()`（滚动操作）、`SetScrollRange(maskSize, targetSize)`（设置范围）。

事件：`OnCurrentScrollPositionChanged`。

## 容器控件

### SUIScrollView（XML: `ScrollView`）

含 `ScrollBar` + `Mask` + `Container`。`Direction`（`Horizontal`/`Vertical`，构造参数）、`ScrollBar`（滚动条实例）、`Mask`（遮罩，OverflowHidden）、`Container`（内容容器，往里面 AddChild）。

```csharp
var sv = new SUIScrollView(Direction.Vertical).Join(this);
sv.Container.AddChild(new UITextView { Text = "..." });
```

滚轮事件内置处理（`OnMouseWheel` 滚动 + `LockScroll` 防穿透）。

### SUIScrollContainer / SUIScrollMask

- `ScrollContainer`：内容承载，`UpdateScrollPosition` 把 `ScrollOffset = -scrollPosition`。
- `ScrollMask`：遮罩裁剪。

### SUIDraggableView（XML: `DraggableView`）

`ControlTarget`（拖拽控制的目标元素）、`DragIncrement`（吸附步长）、`ConstrainInParent`（限制在父容器内）。在 `ControlTarget` 上拖动时更新其 `DragOffset`。

## 显示控件

### SUIImage（XML: `Image`）

`Texture2D`（`Asset<Texture2D>`）、`ImageOriginalSize`（原始尺寸，只读）、`ImageOffset`/`ImagePercent`/`ImageScale`/`ImageAlign`/`ImageOriginPercent`（定位缩放）、`ImageColor`（染色）、`SourceRectangle`（源矩形）。事件 `TextureChanged`；`new SUIImage(TextureAssets.Item[1])` 默认 Fit 贴图尺寸。

### SUIGif（XML: `Gif`）

`GifRenderer`（GIF 渲染器，ImageSharp 解析）。事件 `GifRendererChanged`。

### SUIItemSlot（XML: `ItemSlot`）

物品槽，显示 + 交互（左键拿放/堆叠，右键拿起/长按快速转移）。`Item`（物品实例）、`DisplayItemInfo`（悬停显示物品信息）、`DisplayItemStack`/`AlwaysDisplayItemStack`（堆叠数显示）、`ItemInteractive`（交互开关）、`ItemIconSizeLimit`/`ItemScale`/`ItemColor`/`ItemOffset`/`ItemAlign`（图标显示）。事件 `ItemChanged`；静态工具 `TryStackItem`、`ItemEqual`、`DrawItemIcon`。

## 辅助控件

| 控件 | XML | 说明 |
| --- | --- | --- |
| `SUIDividingLine` | `DividingLine` | 分割线 |
| `SUIBlankSpace` | `BlankSpace` | 空白占位 |
| `SUICross` | `Cross` | 十字关闭按钮（`CrossSize/CrossBorderRadius/CrossBorder/CrossBorderColor/CrossBackgroundColor`，hover 有音效） |
| `UIHeader` | `Header` | 窗口标题栏（仓库 `Elements/Components/SUICommonHeader.xml`：Title + CloseButton，可拖拽） |

## 自定义控件

```csharp
[XmlElementMapping("MyControl")]
public class MyControl : UIView
{
    public string CustomProperty { get; set; }

    protected override void Draw(GameTime gameTime, SpriteBatch spriteBatch)
    {
        base.Draw(gameTime, spriteBatch);
        // 自定义绘制
    }
}
```

注册 XML 映射后即可在 XML 中使用 `<MyControl>`。
