# 动画系统

## AnimationTimer

```csharp
public class AnimationTimer(float speed = 5f, float timerMax = 100f)
```

- `Speed`：速度，越大越快。
- `Timer` / `TimerMax`：内部计时器 / 最大值（默认 100）。
- `Schedule`：进度 0~1，只读。
- `Status`：`AnimationTimerStatus`（`Updating`/`ReverseUpdating`/`Completed`/`ReverseCompleted`）。

### 基本用法

```csharp
private readonly AnimationTimer _timer = new();

_timer.StartUpdate();          // 正向（入场）；已 Completed 则忽略，StartUpdate(true) 强制重置重播
_timer.StartReverseUpdate();   // 反向（退场）；StartReverseUpdate(true) 强制重置
_timer.Update(gameTime);       // 每帧调用，通常在 UpdateStatus 里

float   v = _timer.Lerp(0f, 1f);                              // 0→1
Vector2 p = _timer.Lerp(Vector2.Zero, Vector2.One);           // 支持 float / Vector2 / Color / Vector4
Color   c = _timer.Lerp(Color.Transparent, Color.Red);
Vector4 r = _timer.Lerp(new Vector4(0f), new Vector4(10f));   // 圆角过渡
```

### 状态判断

| 属性 | 含义 |
| --- | --- |
| `IsCompleted` | Completed 或 ReverseCompleted |
| `IsUpdating` | Updating 或 ReverseUpdating |
| `IsForward` / `IsForwardUpdating` / `IsForwardCompleted` | 正向 |
| `IsReverse` / `IsReverseUpdating` / `IsReverseCompleted` | 反向 |

### 事件与直接跳转

```csharp
timer.OnChanged += (sender, value) => { ... };            // 每帧进度变化，value = Schedule
timer.OnUpdateCompleted += () => { ... };                 // 正向完成
timer.OnReverseUpdateCompleted += () => { ... };          // 反向完成

timer.ImmediateCompleted();          // 直接到 Schedule = 1
timer.ImmediateReverseCompleted();   // 直接到 Schedule = 0
```

### 运算符糖（Schedule 乘数）

`AnimationTimer` 可直接参与运算，等价于乘 `Schedule`：

```csharp
Color color = Color.White * timer;
Vector2 v = new Vector2(5f) * timer;
float f = 10f * timer;
```

## 实战模式：菜单开关动画（框架示例 MouseMenuUI）

```csharp
private readonly AnimationTimer _switchTimer = new(3);

public override bool Enabled
{
    get => IsShow || !_switchTimer.IsReverseCompleted;   // 退场动画期间仍绘制
    set => IsShow = value;
}

public override bool IsInteractable => _switchTimer.IsForward;   // 动画中可交互

protected override void UpdateStatus(GameTime gameTime)
{
    if (IsShow) _switchTimer.StartUpdate();
    else _switchTimer.StartReverseUpdate();
    _switchTimer.Update(gameTime);

    UseRenderTarget = _switchTimer.IsUpdating;                                      // 动画期间走离屏合成
    Opacity = _switchTimer.Lerp(0f, 1f);                                            // 淡入淡出
    RenderTargetMatrix = Matrix.CreateTranslation(0, _switchTimer.Lerp(10f, 0), 0); // 上滑
    base.UpdateStatus(gameTime);
}
```

## 实战模式：悬停高亮动画（框架示例 TestUI）

同样的写法：`UpdateStatus` 里 `ItemHoverTimer.Update(gameTime)`，再把 `Lerp` 结果写进属性。

```csharp
HoverView.SetWidth(ItemHoverTimer.Lerp(50f, 62f));                   // 尺寸放大
HoverView.SetHeight(ItemHoverTimer.Lerp(50f, 62f));
HoverView.BorderRadius = new Vector4(ItemHoverTimer.Lerp(4f, 10f));   // 圆角
HoverView.BorderColor = ItemHoverTimer.Lerp(Color.Transparent, Color.Red * 0.5f);  // 描边
// 鼠标进入：ItemHoverTimer.StartUpdate(true)；鼠标离开：ItemHoverTimer.StartReverseUpdate()
```

## 控件内置动画

| 控件 | 动画 |
| --- | --- |
| `SUIToggleSwitch` | `SwitchTimer`（默认 speed=3）滑块移动 |
| `SUIScrollbar` | `ScrollTimer` 滚动条滑动 |
| `SUISliderThumb` | `AutoAnimation<ThumbAnimationArgs>`（悬停 / 按下边框粗细变化） |
| `MouseMenuItem` | `HoverTimer.Lerp(0.25f, 0.4f)` 背景色过渡 |
| `SUICross` | `HoverTimer.Lerp` 颜色过渡 |

## AutoAnimation（自动动画，已标记 Obsolete）

`[Obsolete] public class AutoAnimation<T> where T : IInterpolable<T>`：对实现 `IInterpolable<T>` 的类型做自动补间，`Value = target` 后从当前值动画到目标；`OnChanged` 每帧回调中间值，`Update(gameTime)` 每帧调用。新代码直接用 `AnimationTimer`。

## 每帧更新位置

- 动画一般在 `UpdateStatus`（每帧状态更新，绘制前）里 `Update()` 并写入目标属性。
- 动画改的尺寸属性（Width/Height/BorderRadius 等）会自动 `MarkLayoutDirty`，下一帧布局管线自动重排，无需手动 `Recalculate`。
