# 从零到第一个 UI（Quickstart）

## 最小示例（XML 版）

### 1. 定义 UI 类（.cs）

```csharp
using SilkyUIFramework.Elements;

namespace MyMod.UI;

// 第一个参数 = 图层节点（在该图层之后插入），第二个参数 = 界面名
[RegisterUI("Vanilla: Radial Hotbars", "MyPanel")]
public partial class MyPanel : BaseBody
{
    protected override void OnInitialize()
    {
        InitializeComponent();   // 由 SilkyUIAnalyzer 生成：把 XML 里的元素建出来并赋给 Name 属性

        Title.Text = "我的面板";      // Title 是 XML 里 Name="Title" 生成的属性
    }
}
```

### 2. 写 XML 布局（同名文件，放同目录）

```xml
<?xml version="1.0" encoding="utf-8" ?>
<!-- Class 必须填类的完整名 -->
<Body Class="MyMod.UI.MyPanel" Width="400px" Height="300px">
    <ElementGroup Name="Title" Height="30px" MainAlignment="Center" CrossAlignment="Center">
        <TextView Text="Hello SilkyUI" />
    </ElementGroup>
</Body>
```

### 3. 编译 → 进世界 → UI 出现

## 最小示例（纯代码版）

不写 XML，在 `OnInitialize` 里用代码建树：

```csharp
[RegisterUI("Vanilla: Radial Hotbars", "MyPanel")]
public class MyPanel : BaseBody
{
    protected override void OnInitialize()
    {
        Gap = 8f;
        SetSize(300f, 200f);
        SetLeft(0f, 0f, 0.5f);   // 水平居中
        SetTop(0f, 0f, 0.5f);    // 垂直居中

        var text = new UITextView { Text = "你好，SilkyUI", TextScale = 1f }.Join(this);
        var toggle = new SUIToggleSwitch().Join(this);
        toggle.OnStatusChanges += v => Main.NewText($"开关：{v}");
    }
}
```

`.Join(parent)` 是 `UIElementExtensions` 的扩展：`AddChild` 后返回元素本身，便于链式调用。

## 注册特性二选一

| 特性 | 生命周期 | 显示时机 | 用途 |
| --- | --- | --- | --- |
| `[RegisterUI(layerNode, name, priority=0, interfaceScaleType=UI)]` | Transient（每次进世界重建） | 游戏内（`!Main.gameMenu`） | 游戏内面板、HUD |
| `[RegisterGlobalUI(name, priority=0)]` | Singleton（常驻） | 菜单界面也显示 | 主菜单 UI、全局覆盖层 |

- `layerNode`：插入点，取某个 `GameInterfaceLayer` 的 Name，默认 `"Vanilla: Radial Hotbars"`。
- `priority`：同一栈内排序，数值大者先绘制、先命中（`OrderByDescending`）。
- `InterfaceScaleType`：`UI`（UIScaleMatrix）或 `Game`（GameViewMatrix.ZoomMatrix）。
- `[RegisterGlobalUI]` 在 `Initialize()` 时直接 `SetRoot` + Push 到全局栈，无需进世界。

## 生命周期钩子（UIView 基类）

| 钩子 | 触发时机 | 用途 |
| --- | --- | --- |
| `OnInitialize()` | 首次加入树（懒初始化，每元素一次） | 建子元素、挂事件 |
| `OnEnterTree()` | 进入 UI 树 | 订阅外部事件 |
| `OnExitTree()` | 移出 UI 树 | 取消订阅 |
| `OnUpdate()` | 每帧逻辑更新（`Update` 事件） | 游戏逻辑 |
| `OnUpdateStatus()` / `UpdateStatus()` | 每帧状态更新（绘制前） | 动画、悬停过渡 |
| `OnAddChild()` / `OnRemoveChild()` | 子元素增删 | 容器扩展 |
| `OnSelected()` / `OnDeselected()` | 选中状态变化 | 选择框逻辑 |

## 常用入口

- `SilkyUIRenderSystem.Instance.TryGetInstance<TBody>(out var body)`：取已注册的 UI 实例。
- `SilkyUIRenderSystem.Instance.GetInstances<TBody>()`：取全部实例。
- `SilkyUIManager`：驱动 `Update/Draw/HandleIME/ModifyInterfaceLayers`，一般不需要直接碰。
- `SilkyUISystem.Instance`：`ModSystem` 单例，暴露 `ServiceProvider`。

## 谁在驱动它（理解即可）

框架用 MonoMod `On_`/`IL_` 钩子接入原版绘制循环，你的模组不需要自己挂钩子：

- `On_Main.UpdateUIStates` → `SilkyUIManager.Update`（输入 + 渲染系统更新）
- `On_Main.DrawThickCursor` → `SilkyUIManager.Draw`（渲染系统绘制 + 输入处理）
- `IL_Main.DoDraw` → `HandleIME`（输入法）
- `ModifyInterfaceLayers` → 把每个 RegisterUI 的 Body 包装成 SilkyUILayer 插入图层
