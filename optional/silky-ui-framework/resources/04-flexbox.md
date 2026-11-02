# Flexbox 布局引擎

> 完整官方文档：仓库 `Layout/FlexboxModule.md`。SilkyUI 的 Flexbox 是工程实现版，不是 CSS 规范的 1:1 复刻。

## 概述

`UIElementGroup` 默认 `LayoutType = Flexbox`。`FlexboxModule` 采用策略模式：`FlexDirection.Row` → `RowLayoutStrategy`，`FlexDirection.Column` → `ColumnLayoutStrategy`；负责主轴方向、换行、主轴对齐、交叉轴单行/多行对齐、`FlexGrow`/`FlexShrink`、`Gap`。

## 容器属性（UIElementGroup）

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `LayoutType` | `LayoutType` | `Flexbox` | `Flexbox`/`Grid`/`Custom` |
| `FlexDirection` | `FlexDirection` | `Row` | 主轴方向 |
| `FlexWrap` | `bool` | `false` | 是否换行 |
| `MainAlignment` | `MainAlignment` | `Start` | 主轴对齐 |
| `CrossAlignment` | `CrossAlignment` | `Start` | 交叉轴单行对齐 |
| `CrossContentAlignment` | `CrossContentAlignment` | `Stretch` | 交叉轴多行对齐 |
| `Gap` | `Size` | `0` | 项间距（`Gap.Width`=水平，`Gap.Height`=垂直） |

### 属性 → CSS 概念映射

| SilkyUI | CSS |
| --- | --- |
| `FlexDirection` | `flex-direction`（仅 Row/Column） |
| `FlexWrap` | `flex-wrap` |
| `MainAlignment` | `justify-content` |
| `CrossAlignment` | `align-items`（单行） |
| `CrossContentAlignment` | `align-content`（多行） |
| `Gap` | `gap` |
| `FlexGrow` | `flex-grow` |
| `FlexShrink` | `flex-shrink` |

**未实现**：`row-reverse`/`column-reverse`、`wrap-reverse`、`space-around`、`baseline`、`flex-basis`、`align-self`。

## 换行触发条件

换行不只看 `FlexWrap=true`，还要求容器在对应轴有固定可用空间：

| 方向 | 换行条件 |
| --- | --- |
| `FlexDirection = Row` | `FlexWrap=true` **且** `FitWidth=false` |
| `FlexDirection = Column` | `FlexWrap=true` **且** `FitHeight=false` |

否则退化为单行（`SingleRow`/`SingleColumn`）。设置了 `FlexWrap` 却不换行，通常是这里不满足。

## 子项属性（UIView）

| 属性 | 默认值 | 说明 |
| --- | --- | --- |
| `FlexGrow` | `0` | 剩余空间>0 时按比例扩展 |
| `FlexShrink` | `0` | 空间不足时按比例收缩 |
| `MinWidth/MaxWidth/MinHeight/MaxHeight` | — | 约束（`Dimension`） |

- 只有父容器是 `LayoutType.Flexbox` 时，这两个属性才触发布局脏标记。
- `FlexGrow`/`FlexShrink` 只在「子项总主轴尺寸 ≠ 容器可用主轴空间」时生效。

## 尺寸分配规则

对每一行（或列），`remaining` 为容器可用主轴空间减去子项总主轴尺寸：

- `remaining > 0`：`FlexGrow > 0` 的元素按比例分增长空间（受 `MaxOuter` 约束）。
- `remaining < 0`：`FlexShrink > 0` 的元素按比例分收缩量（受 `MinOuter` 约束）。

约束按轴取用：宽度看 `MinOuterWidth` / `MaxOuterWidth`，高度看 `MinOuterHeight` / `MaxOuterHeight`。

## 对齐规则

### 主轴对齐（MainAlignment）

`Start` / `End` / `Center` / `SpaceEvenly` / `SpaceBetween`

### 交叉轴单行（CrossAlignment）

`Start` / `Center` / `End` / `Stretch`

### 交叉轴多行（CrossContentAlignment）

`Start` / `Center` / `End` / `SpaceEvenly` / `SpaceBetween` / `Stretch`

## 方向语义

| 方向 | 主轴 | 交叉轴 | 项间距 | 行间距 |
| --- | --- | --- | --- | --- |
| `Row` | 水平 | 垂直 | `Gap.Width` | `Gap.Height` |
| `Column` | 垂直 | 水平 | `Gap.Height` | `Gap.Width` |

## 使用示例

### 水平分布（SpaceBetween）

```xml
<ElementGroup FlexDirection="Row"
              MainAlignment="SpaceBetween"
              CrossAlignment="Center"
              Gap="10"
              FitWidth="false"
              Width="600px">
    <View Width="120px" Height="40px" />
    <View Width="120px" Height="40px" />
    <View Width="120px" Height="40px" />
</ElementGroup>
```

### 自动换行卡片流

```xml
<ElementGroup FlexDirection="Row"
              FlexWrap="true"
              MainAlignment="Start"
              CrossContentAlignment="Start"
              Gap="8"
              FitWidth="false"
              Width="500px">
    <View Width="120px" Height="80px" />
    <View Width="120px" Height="80px" />
    <View Width="120px" Height="80px" />
    <View Width="120px" Height="80px" />
</ElementGroup>
```

### 增长与收缩

```xml
<ElementGroup FlexDirection="Row" Gap="6" FitWidth="false" Width="420px">
    <View Width="120px" Height="40px" FlexGrow="1" />
    <View Width="180px" Height="40px" FlexShrink="1" />
    <View Width="180px" Height="40px" FlexShrink="2" />
</ElementGroup>
```

## 快速排查清单

1. 父容器 `LayoutType` 是否为 `Flexbox`。
2. `FlexDirection` 是否符合预期。
3. `FitWidth`/`FitHeight` 是否与换行需求匹配（Row 要 `FitWidth=false`，Column 要 `FitHeight=false`）。
4. 子项是否被最小/最大尺寸约束卡住。
5. 对齐属性是否显式设置（避免默认值干扰判断）。
6. 出现意外拉伸时，检查 `CrossAlignment`/`CrossContentAlignment` 是否为 `Stretch`。

## Grid 布局（实验性）

`LayoutType.Grid` 走 `GridModule`，支持：

- `TemplateRows` / `TemplateColumns`：`GridTrack[]`（`TemplateType.Auto/Fraction/Pixels/Percent`），可用 `GridTrack.Repeat(n, type, value)`。
- 子项 `RowSpan` / `ColumnSpan`：`GridSpan(start?, size)` 控制跨行跨列。
- `AutoFlow.Row/Column`。

仓库 TODO 中 Grid 布局的「设计与实现」仍标记未完成，属实验性，优先用 Flexbox。


## FlexGrow 不等于有尺寸（实测踩坑）

**现象**：宝石页网格 `count=5`，数据正常，但整块面板全空。
**证据**：网格 host 只设了 `FlexGrow = 1`、`FitWidth/FitHeight = false`，宽度算成 **0**；
同项目的装备页显式设了 `Width = new Dimension(0, 1)`，正常显示。

**铁律**：子容器放进"固定高度 / 百分比高度"的父级时，必须显式给主轴尺寸：

```csharp
// ❌ 只有 FlexGrow：父容器按百分比分配高度时，宽度会是 0
new UIView { FlexGrow = 1f }

// ✅ 显式百分比尺寸
new UIView {
    Width  = new Dimension(0f, 1f),
    Height = new Dimension(0f, 1f),
    FlexGrow = 1f,
}
```

排查提示：把"空白页"和"能正常显示的同类页"做 diff，先比 `Width/Height` 再比内容——
宽度为 0 时子元素全在画布外，看起来和"没画"一模一样。
