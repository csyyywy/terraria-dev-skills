---
name: silky-ui-framework
description: SilkyUI（tModLoader UI 框架）：接入与注册、BaseBody / UIView 生命周期、XML 声明式布局、Flexbox、Dimension / Anchor / Bounds、内置控件、事件与输入、DataContext 绑定、渲染管线、动画。
whenToUse: **仅当用户明确提到 SilkyUI / SilkyUIFramework / silky-ui 时使用**（或项目已确认引用该框架）。
  模组 UI 的默认方案是 tModLoader 原生 UI（见技能 terraria-mod-ui），不要主动把需求迁移到本框架。
  本技能默认收在 skills/optional/ 下、不进入技能目录；启用方式：
  `pwsh -File tools/skill-pack.ps1 -Name silky-ui-framework -Enable`。
---

# SilkyUIFramework 使用指南

依据上游 main 分支 v0.3.0 源码整理（https://github.com/487666123/SilkyUIFramework）。
官方文档同在仓库内：`README.md`、`Elements.md`（控件大全）、`Layout/FlexboxModule.md`（布局引擎）、`MigrationGuide.md`（迁移）。

## 定位

以**前置模组**方式被其他模组复用的 Terraria UI 框架，相对 `Terraria.UI` 提供：

- 统一的 UI 管理与层级（`ScenePriority` 排序 + 置顶，行为类似窗口）
- XML 声明式布局（增量生成器 + 元素映射），也支持纯 C# 建树
- Flexbox 布局引擎（脏标记自动触发，无需手动 `Recalculate()`）
- 控件库：文本 / 输入框 / 滑块 / 开关 / 滚动视图 / 物品槽 / 图片 / GIF / 可拖拽视图
- 数据绑定（DataContext / Bind / Command）、模糊背景、SDF 圆角、离屏合成、动画

## 架构

```
SilkyUIFramework (Mod) ── SilkyUISystem (ModSystem) ── ServiceProviderBuilder ── DI 容器
        │ 收集所有已加载 Mod 的类型（RegisterUI / RegisterGlobalUI / Service 特性）
        ▼
SilkyUIManager ── SilkyUIRegistrar（按图层收集 Body 类型）
        │          SilkyUIRenderSystem（全局栈 + 按图层栈 + 命中测试 + 置顶）
        │          SilkyUIInputState（鼠标 / 焦点 / IME 分发）
        │          SilkyUISceneStack（单个 UI 栈：排序 / 置顶 / 命中测试）
        ▼
SilkyUI（单个 UI 实例：RootNode + TransformMatrix）── SilkyUILayer（插入 GameInterfaceLayer）
        ▼
BaseBody（根）─ UIElementGroup（容器：Flexbox / Grid 模块 + 子元素管理）
        ▼
UIView（基类：Bounds / InnerBounds / OuterBounds、定位、事件、绑定、绘制）
```

- **Global UI**（`[RegisterGlobalUI]`）：菜单界面也显示，单例，常驻根节点。
- **Game UI**（`[RegisterUI]`）：进世界后由 `SilkyUIPlayer.OnEnterWorld → ReloadSilkyUIStacks` 重建（Transient），插入到指定 `LayerNode` 之后。
- 每个 `SilkyUI` 实例对应一棵 UI 树，`ScenePriority` 高者先绘制、先命中。

## 一句话流程

接入前置 → 定义 `partial class XXX : BaseBody` 并加注册特性 → `OnInitialize()` 里 `InitializeComponent()`（XML）或代码建树 → 控件挂事件 / 绑定数据 → 编译进游戏 → 按图层自动插入渲染 → 命中测试与输入自动分发。

## 三条易错点

1. **XML 布局是增量生成器**：`Class="命名空间.类名"` 必须与 `partial class` 同名匹配；XML 里的 `Name="Foo"` 会生成 `Foo` 属性，调用 `InitializeComponent()` 后才可用。改 XML 后需重新编译才会更新生成代码。
2. **换行不生效先查 `FitWidth` / `FitHeight`**：Row 方向开启 `FlexWrap=true` 时还必须 `FitWidth=false`；Column 方向必须 `FitHeight=false`，否则退化为单行 / 单列。
3. **所有坐标都是容器内局部坐标**：布局阶段由父容器摆放，不要手算屏幕坐标。需要脱离布局流（悬浮 / 绝对定位）时用 `Positioning.Absolute` / `Fixed` 配合 `SetLeft` / `SetTop(px, %, #对齐)`；事件与绘制用 `Bounds`（已含 margin / border 换算），命中测试用 `InnerBounds`。

## 分册索引

- `resources/01-setup.md` 接入前置——`build.txt`、双仓库克隆、csproj 引用 Analyzer 与项目引用、依赖包、版本说明
- `resources/02-quickstart.md` 从零到第一个 UI——最小示例（XML 版 + 纯代码版）、生命周期钩子、常用入口
- `resources/03-xml-layout.md` XML 布局语法——元素映射表、属性解析规则（IParsable / 颜色 / 尺寸）、`Name` 映射、`M.` 子元素引用
- `resources/04-flexbox.md` Flexbox 引擎——容器 / 子项属性、换行触发条件、grow / shrink 分配、对齐
- `resources/05-positioning-bounds.md` 定位与盒模型——Dimension / Anchor / Positioning / Size / Margin、三套 Bounds、布局脏标记
- `resources/06-elements.md` 内置控件速查——View / ElementGroup / Body / TextView / EditText / Slider / ToggleSwitch / Scrollbar / ScrollView / Image / Gif / ItemSlot / DividingLine / BlankSpace / Cross / Header / DraggableView
- `resources/07-events-input.md` 事件与输入——鼠标事件冒泡链、HitTest 顺序、输入分发、焦点 / IME、滚轮锁定、缩放适配
- `resources/08-data-binding.md` 数据绑定——DataContext / LocalDataContext 继承、Bind 嵌套路径、ICommand
- `resources/09-rendering.md` 渲染管线——绘制顺序、图层插入、TransformMatrix、OverflowHidden 裁剪、离屏 RenderTarget、模糊、SDF、截图
- `resources/10-animation.md` 动画系统——AnimationTimer 用法与插值、AutoAnimation
- `resources/11-troubleshooting.md` 排错——布局 / 显示 / 事件 / 绑定问题的定位方法

## 快速参考

```csharp
// 1. 注册"游戏内 UI"（进世界后插入到指定图层之后）
[RegisterUI("Vanilla: Radial Hotbars", "MyPanel")]      // 图层节点、界面名
public partial class MyPanel : BaseBody
{
    protected override void OnInitialize()
    {
        InitializeComponent();          // XML 布局（XML 的 Class 必须是本类全名）
        Title.Text = "Hello SilkyUI";
    }
}

// 2. 注册"全局 UI"（菜单界面也显示，单例）
[RegisterGlobalUI(priority: 1000)]
public partial class MyGlobalUI : BaseBody { /* ... */ }

// 3. 代码建树（不用 XML 时）
protected override void OnInitialize()
{
    Gap = 8f;
    var text = new UITextView { Text = "Hello", TextScale = 1.2f }.Join(this);
    var btn = new SUIToggleSwitch().Join(this);
    btn.OnStatusChanges += v => Main.NewText($"toggle: {v}");
}

// 4. 获取已注册的 UI 实例
SilkyUIRenderSystem.Instance.TryGetInstance<MyPanel>(out var panel);
```

## 版本说明

- `main` = Steam 创意工坊已发布版；`preview` = 开发版（定期并入 main）。
- 版本号 `X.MINOR.PATCH`：X = 架构重大变更，MINOR = 功能，PATCH = 修复。
- 0.2.25.09171 起：`BasicElements` / `BasicComponents` 命名空间合并为 `Elements`；`BasicBody` 更名为 `BaseBody`。
- 依赖：`Microsoft.Extensions.DependencyInjection 9.0.9`、`Solaestas.tModLoader.ModBuilder 1.6.1`（构建）、`SixLabors.ImageSharp 3.1.11`（GIF 解析）。目标 `.NET 8`，使用 C# preview 语法（如 `field` 关键字）。
- 配套增量生成器：https://github.com/487666123/SilkyUIAnalyzer
