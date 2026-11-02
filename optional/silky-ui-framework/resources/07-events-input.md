# 事件与输入

## 鼠标事件（UIView 全部支持）

| 事件 | 触发时机 |
| --- | --- |
| `MouseEnter` / `MouseLeave` | 鼠标进入 / 离开元素 |
| `MouseMove` | 鼠标移动（当前实现仅在悬停目标变化时触发 Enter/Leave，Move 事件保留） |
| `Left/Middle/RightMouseDown/Up/Click` | 左 / 中 / 右键按下 / 抬起 / 点击 |
| `MouseWheel` | 滚轮（`UIScrollWheelEvent`） |
| `GotFocus` / `LostFocus` | 焦点获得 / 失去 |
| `Selected` / `Deselected` | 选中 / 取消选中 |

委托：`MouseEventHandler(UIView, UIMouseEvent)`、`MouseWheelEventHandler(UIView, UIScrollWheelEvent)`、`SelectionEventHandler(UIView)`。

```csharp
image.MouseEnter += (source, e) => { ... };
slider.ValueChanged += (sender, value) => { ... };
```

## 事件冒泡链

所有 `On*` 虚方法触发自身事件后设置 `evt.Previous = this` 并调用 `Parent?.OnXxx(evt)`，事件沿父链向上冒泡：

```csharp
public virtual void OnLeftMouseDown(UIMouseEvent evt)
{
    LeftMousePressed = true;
    LeftMouseDown?.Invoke(this, evt);
    evt.Previous = this;
    Parent?.OnLeftMouseDown(evt);   // 冒泡
    ExecuteCommand();
}
```

用途：父容器统一处理子元素事件，例如 SUISlider 用 `evt.Source != Thumb` 判断是否响应轨道点击。

## UIMouseEvent

```csharp
public class UIMouseEvent(UIView source, Vector2 position)
{
    public UIView Source { get; }          // 最初触发事件的元素
    public UIView Previous { get; }        // 冒泡路径上的上一个元素
    public Vector2 MousePosition { get; }
}
public class UIScrollWheelEvent : UIMouseEvent
{
    public int ScrollDelta { get; }
    public UIView ScrollElement { get; private set; }
    public void LockScroll(UIView view);   // 锁定滚动元素（防止穿透）
}
```

## 输入分发（SilkyUIInputState）

每帧自动执行：

1. `UpdateMouseStatus`：缓存 `CurrentMouse`/`PreviousMouse`（左中右）。
2. `UpdateHoverTarget`：`RenderSystem.HitTest` 命中测试，悬停目标变化时触发 `MouseLeave`/`MouseEnter`。
3. `UpdateButtonEvent`：边沿检测；按下记录 `_pressTargetsByButton` 并触发 `MouseDown`，抬起时仍悬停在原目标才触发 `Click`。
4. `UpdateScrollEvent`：`PlayerInput.ScrollWheelDeltaForUI != 0` 时向悬停目标发 `OnMouseWheel`。
5. `UpdateFocusElement`：焦点切换时触发 `LostFocus`/`GotFocus`。

### 命中测试（HitTest）顺序

`RenderSystem.HitTest`：先查全局栈（Global UI）→ 按 `_layerOrder` 逆序（后画的先查）查游戏 UI 栈 → 每层 `SilkyUI.HitTest → RootNode.GetElementAt`（`BaseBody` 先检查 `Enabled && IsInteractable`）。

`GetElementAt` 规则：

- `DisableMouseInteraction`：直接返回 null。
- `IgnoreMouseInteraction`：自己不返回，子元素仍参与查找。
- `OverflowHidden` 容器先检查点是否在容器内。
- 子元素按 `ElementsInOrder.Reverse` 查找（后绘制的先命中）。

### 置顶（BringToFront）

按下鼠标时 `RenderSystem.Activate(hoverTarget)` 把该 UI 所在栈 `BringToFront`（移到栈顶 = 优先绘制与命中），类似窗口点击置顶。

## 焦点与 IME

- `FocusTarget`：当前焦点元素。
- 焦点元素 `OccupyPlayerInput == true`（`SUIEditText` 构造默认 true）时才处理输入：
  - `HandleIME`：`PlayerInput.WritingText = true` + `Main.instance.HandleIME()`。
  - `HandleInput`：读取键盘 → 绘制 IME 面板（`DrawWindowsIMEPanel`）→ 调用 `FocusTarget.HandlePlayerInput(inputMethodStatus)`。
  - `InputMethodPosition`：IME 面板位置，默认 `InnerBounds.BottomLeft + new Vector2(0f, 32f)`。
- 成员签名：`public virtual bool OccupyPlayerInput { get; set; }`、`public virtual Vector2 InputMethodPosition => ...`、`public virtual void HandlePlayerInput(bool inputMethodStatus) { }`。

## 滚轮锁定（防止穿透）

`UIScrollWheelEvent.LockScroll(view)` 写入 `ScrollElement` 后，其他滚动不再生效：

```csharp
public override void OnMouseWheel(UIScrollWheelEvent evt)
{
    if (evt.ScrollElement != null) return;   // 已锁定，忽略
    ScrollBar.VScrollBy(-evt.ScrollDelta);
    evt.LockScroll(this);
    base.OnMouseWheel(evt);
}
```

## 鼠标缩放适配

`PlayerInputHelper.SetZoom(matrix)` 按 TransformMatrix 缩放 `Main.mouseX/Y/screenWidth/screenHeight`，保证 Game 缩放图层下命中测试与输入正确；框架在 `SilkyUI.HitTest` 与 `Draw` 中自动调用。

## BaseBody 交互开关

```csharp
// 悬停时锁定原版滚轮与鼠标
protected override void UpdateStatus(GameTime gameTime)
{
    if (IsMouseHovering)
    {
        if (!AvailableScroll) PlayerInput.LockVanillaMouseScroll("SilkyUIFramework");
        if (!AvailableItem) Main.LocalPlayer.mouseInterface = true;
    }
    base.UpdateStatus(gameTime);
}
```

`AvailableScroll` / `AvailableItem`：`BaseBody` 的 protected 虚属性，默认 false；子类重写为 true 即放行原版交互。
