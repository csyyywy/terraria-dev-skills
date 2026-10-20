# 定位与盒模型

## 核心类型

### Dimension（尺寸）

```csharp
public readonly struct Dimension(float pixels = 0f, float percent = 0f)
```

- `CalculateSize(containerSize) => Pixels + containerSize * Percent`
- 字符串解析：`"100px"`、`"50%"`、`"100px 50%"`（两个值都要带单位）
- 设置：`Width = new Dimension(0f, 1f)`，或 `SetWidth(pixels, percent)`、`SetSize(w, h, w%, h%)`

### Anchor（锚点）

```csharp
public readonly struct Anchor(float pixels = 0f, float percent = 0f, float alignment = 0f)
```

- `CalculatePosition(availableSize, elementSize) => Pixels + availableSize*Percent + (availableSize-elementSize)*Alignment`
- 解析：`"10px"`、`"50%"`、`"50#"`（# = 对齐比例）、`"0px -50% 50#"` 三段式
- 常用：`SetLeft(pixels, percent, alignment)` / `SetTop(...)`

### Size / Margin

```csharp
Size(width, height)          // 也有隐式转换自 float / Vector2
Margin(left, top, right, bottom)   // Margin(uniform) / Margin(horizontal, vertical)
```

### Positioning（定位方式）

| 值 | 含义 | 相对谁 |
| --- | --- | --- |
| `Relative` | 相对定位（默认，参与布局流，位置由布局引擎计算） | 父容器 |
| `Absolute` | 绝对定位（**脱离布局流**，`SetLeft/SetTop` 相对父容器） | 父容器 |
| `Fixed` | 固定定位（**脱离布局流**，相对屏幕） | 屏幕 |
| `Sticky` | 粘性定位（参与流 + 按 `StickyType`/`Sticky` 约束） | 父容器 |
| `Static` | 完全由父元素控制 | 父容器 |

`PositioningExtensions.IsOutOfFlow`：`Fixed` 或 `Absolute` 为 true。

### StickyType / Sticky

```csharp
[Flags] StickyType { Left, Top, Right, Bottom, LeftTop, ... }
Sticky = Vector4(x, y, z, w)  // 对应 Left/Top/Right/Bottom 的粘性距离
```

`HandleStickyPositioning` 按旗标把元素位置钳制在容器内。

## 三套 Bounds（盒模型）

每个 `UIView` 有三个 `Bounds`（float X/Y/Width/Height 结构，含 `Contains`/`Intersects`），由外到内嵌套：

- `OuterBounds`：布局引擎使用，含 margin
- `Bounds`：绘制/事件使用，含 border
- `InnerBounds`：内容区，含 padding

换算关系（默认 `BoxSizing.Border`）：

- `Bounds.Width = OuterBounds.Width - Margin.Horizontal`
- `InnerBounds.Width = Bounds.Width - Padding.Horizontal - Border*2`

布局引擎直接操作 `SetOuterBoundsWidthRaw`/`SetInnerBoundsWidthRaw` 等内部方法，你一般只需**读**这三个 Bounds。

## 布局脏标记

- 属性 setter（尺寸/间距/定位/对齐/子元素增删）自动调用 `MarkLayoutDirty()`，无需手动 `Recalculate()`。
- `MarkLayoutDirty(bool force=false)`：默认向父级冒泡（`Positioning.IsOutOfFlow` 的除外）；`force=true` 强制整条链。
- 布局管线（`SilkyUI.Draw`）每帧：`Initialize → UpdateLayout → UpdatePosition → UpdateElementsOrder → HandleUpdateStatus → (再次 UpdateLayout/Position/Order) → HandleDraw`。
- 顶部 Body 始终独立跑完整布局（`RunIndependentLayoutPass`）；脱离文档流的元素（Absolute/Fixed）也各自独立布局，流内元素由父容器统一驱动。

## 尺寸约束（AxisMetrics）

每元素缓存 `WidthMertrics`（源码拼写如此）/`HeightMertrics`：

- `Min/Max/Value`：声明约束（对应 MinWidth/MaxWidth 等 Dimension）
- `MinInner/MaxInner`、`MinOuter/MaxOuter`：按 BoxSizing 换算后的内外盒约束
- `ClampInner/ClampOuter/SetValueClamped` 用于约束钳制

## BoxSizing

| 值 | 含义 |
| --- | --- |
| `Border`（默认） | `Width/Height` 控制**边框盒**（border+padding+content） |
| `Content` | `Width/Height` 控制**内容盒**（content），border+padding 额外增加 |

## FitWidth / FitHeight

- `FitWidth=true`：宽度由**内容反推**（如 TextView 由文本宽度决定，Image 由贴图宽度决定）。
- `FitWidth=false`：宽度由声明 `Width` 计算（`px + %`）。
- 根元素（无 Parent）用屏幕可用空间（`GetBackBufferSizeByUIScale`）。

## 常用定位写法

```csharp
// 屏幕居中（Fixed）
SetLeft(0f, 0f, 0.5f);
SetTop(0f, 0f, 0.5f);

// 相对父容器右下角（Absolute）
Positioning = Positioning.Absolute;
SetLeft(-10f, 1f, 0f);   // 右边缘向内 10px
SetTop(-10f, 1f, 0f);

// 相对定位 + 手动偏移
SetLeft(20f);
SetTop(20f);
```

## 拖拽偏移（DragOffset / LayoutOffset）

- `LayoutOffset`：布局引擎写入的偏移，不要手改。
- `DragOffset`：用户拖拽偏移（`SUIDraggableView` 写入）。
- `RecalculatePosition` 中：`Fixed` 位置 = `Left/Top` 计算 + `DragOffset`；`Relative/Sticky` = 父容器 + 滚动偏移 + `Left/Top` + `LayoutOffset` + `DragOffset`。
