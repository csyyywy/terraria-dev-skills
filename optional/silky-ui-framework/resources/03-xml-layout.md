# XML 声明式布局

## 基本原理

- XML 布局由 **SilkyUIAnalyzer 增量生成器**在编译期处理。
- XML 文件**与 UI 类同名**（如 `MyPanel.cs` + `MyPanel.xml`；仓库示例用 `.sui.xml` 或 `.xml`，生成器按 `Class` 属性匹配，csproj 把 `**/*.xml` 作为 AdditionalFiles 打包进模组）。
- 根元素 `<Body Class="完整类名">`，`Class` 必须与你的 `partial class` 全名一致。
- 在 `OnInitialize()` 中调用生成的 partial 方法 `InitializeComponent()` 完成建树。

## XML 元素 → 控件映射表

| XML 元素 | C# 类 | 说明 |
| --- | --- | --- |
| `<Body>` | `BaseBody` | 根容器（UI 主体） |
| `<View>` | `UIView` | 基础元素 |
| `<ElementGroup>` | `UIElementGroup` | 容器（Flexbox/Grid） |
| `<TextView>` | `UITextView` | 富文本显示 |
| `<EditText>` | `SUIEditText` | 文本输入框 |
| `<Slider>` | `SUISlider` | 滑块 |
| `<ToggleSwitch>` | `SUIToggleSwitch` | 开关 |
| `<ScrollView>` | `SUIScrollView` | 滚动视图 |
| `<ScrollContainer>` | `SUIScrollContainer` | 滚动容器 |
| `<ScrollMask>` | `SUIScrollMask` | 滚动遮罩 |
| `<DraggableView>` | `SUIDraggableView` | 可拖拽视图 |
| `<Image>` | `SUIImage` | 图片 |
| `<Gif>` | `SUIGif` | GIF 动画 |
| `<ItemSlot>` | `SUIItemSlot` | 物品槽 |
| `<DividingLine>` | `SUIDividingLine` | 分割线 |
| `<BlankSpace>` | `SUIBlankSpace` | 空白占位 |
| `<Cross>` | `SUICross` | 十字关闭按钮 |
| `<Header>` | `UIHeader` | 窗口标题栏（可拖拽+关闭按钮） |

自定义控件加 `[XmlElementMapping("MyControl")]` 即可在 XML 中使用。

## 属性 → C# 赋值规则

XML 属性转成 C# 属性/字段赋值，支持三类类型：

1. 实现 `IParsable<TSelf>` 的任意类（`Dimension`、`Anchor`、`Margin`、`Size`）→ 调用 `Parse`
2. `float / double / char / int / string`
3. `Vector2 / Vector3 / Vector4 / Color`

### 尺寸解析（Dimension）

```
Width="100px"        → 100 像素
Width="50%"          → 父容器宽度的 50%
Width="100px 50%"    → 像素 + 百分比叠加（两个值都要带单位）
```

### 锚点解析（Anchor）

```
Left="10px"          → 像素偏移
Left="50%"           → 百分比偏移
Left="50#"           → 对齐比例（0~1，50# = 居中）
Left="0px -50% 50#"  → 像素 + 百分比 + 对齐 三者组合
```

### 颜色解析（Color）

```
BackgroundColor="#00000000"           → 十六进制 RGBA
BackgroundColor="rgba(0,155,255,0.5)" → CSS rgba 语法
```

### Margin/Size 解析

```
Padding="12 0"   → 水平 12，垂直 0（两值：水平 垂直）
Margin="10"      → 四边统一 10
Gap="8"          → 间距 8
```

## Name 属性 → 生成字段

`Name="Title"` 会让生成器在 partial 类中生成同名属性/字段，由 `InitializeComponent()` 赋值：

```xml
<TextView Name="Title" Text="你好" />
```

```csharp
public partial class MyPanel : BaseBody
{
    protected override void OnInitialize()
    {
        InitializeComponent();   // Title 现在可用
        Title.Text = "改标题";
        Title.TextColor = Color.Yellow;
    }
}
```

## 子元素引用 `M.` 语法

```xml
<ScrollView Name="ScrollView" ...>
    <M.Mask MaxHeight="300px" FitWidth="true" FitHeight="true" />
    <M.Container ...>
    </M.Container>
</ScrollView>
```

`<M.Mask>` / `<M.Container>` 引用 `Name="ScrollView"` 元素的 `Mask` / `Container` 子属性，用于在 XML 里直接摆出并配置复合控件的内部结构。即 XML 可以把已命名元素的公开属性当作节点引用（仓库 `MouseMenuUI.sui.xml` 的用法）。

## 完整示例（仓库 UIHeader）

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Body Class="SilkyUIFramework.Elements.Components.UIHeader"
    Width="100%" Height="40px" BackgroundColor="rgba(0,0,0,0.25)"
    FlexDirection="Row" MainAlignment="SpaceBetween" CrossAlignment="Center">
    <!-- 标题 -->
    <TextView Name="Title" Width="25%" Height="100%" Padding="12 0" TextScale="0.45" TextAlign="0 0.5" />
    <!-- 关闭 -->
    <Cross Name="CloseButton" BoxSizing="Content"
        Width="24px" Height="100%" Padding="12 0" CrossSize="22" CrossBorderRadius="3.5" />
</Body>
```

```csharp
[XmlElementMapping("Header")]
public partial class UIHeader : SUIDraggableView
{
    public UIHeader() : base()
    {
        InitializeComponent();   // 构造器里也能调用
        Title.UseDeathText();
    }
}
```

## 注意事项

1. **XML 与类名必须匹配**：`Class` 是生成器识别 UI 类的唯一依据，写错即生成器静默跳过（或报错）。
2. **改 XML 必须重新编译**：增量生成器在编译期运行，游戏内 Reload 不会重新生成。
3. **`InitializeComponent()` 放 `OnInitialize()` 里**（构造器也能用，但 `OnInitialize` 更规范，此时树已可挂载）。
4. 仓库 `MouseMenuUI.sui.xml` 的 Body 写 `Enabled="false"` 表示初始隐藏——`Enabled` 是 `BaseBody` 的开关。
