# 排错手册

框架仍在迭代，遇到异常行为先对照源码。

## 接入类问题

### 1. Analyzer 没生成 InitializeComponent / Name 属性

- csproj：`SilkyUIAnalyzer` 是否作为 `ProjectReference` + `OutputItemType=Analyzer`；XML 的 `Class` 是否与 `partial class` 全名一致（含命名空间）。
- XML 是否被包含进编译（仓库 csproj 用 `AdditionalFiles Include="**/*.xml"`）；改 XML 后必须重新编译（游戏内 Reload 不触发生成器）。

### 2. 编译报错：找不到 SilkyUI 类型

- `SilkyUIFramework.csproj` 已 ProjectReference（ModSources 下以 `..\SilkyUIFramework` 相对路径克隆），且 `build.txt` 写入 `modReferences = SilkyUIFramework`。

### 3. 游戏内模组报"需要前置 SilkyUI"

- 玩家端需安装 SilkyUI（Steam 创意工坊）；开发时在本地模组列表启用它。

## 布局类问题

### 4. 设置了 FlexWrap=true 但不换行（头号问题）

- Row 方向容器 `FitWidth` 必须为 false，Column 方向 `FitHeight` 必须为 false；否则退化为单行 / 单列，`FlexWrap` 不生效。

### 5. FlexGrow/FlexShrink 没效果

- 仅当"子项总主轴尺寸 ≠ 容器可用主轴空间"时生效（没有剩余空间就不会增长）。
- 子项受 `Min/MaxWidth/Height` 钳制（分配受 `MaxOuter` / `MinOuter` 限制）；父容器不是 `LayoutType.Flexbox` 时这两个属性不触发布局。

### 6. 元素意外拉伸 / 位置不对

- `CrossAlignment` / `CrossContentAlignment` 是否默认为 `Stretch`（`CrossContentAlignment` 默认就是 Stretch）。
- `BoxSizing`：`Content` 模式下 Width/Height 控制内容盒，border + padding 会额外增大外盒；`Positioning` 的 Absolute/Fixed 脱离布局流，位置由 `Left/Top` 锚点决定。

### 7. 尺寸是百分比但没生效

- `Dimension` 解析 `"50%"` 时不要加空格（`"50 %"` 不合法），`"100px 50%"` 两段都要带单位；父容器 `FitWidth=true` 时可用宽度为 0，百分比按 0 计算。

### 8. 布局没更新（改了属性不重排）

- 脏标记会自动重排；手动改 `Bounds` / `LayoutOffset` 之类的内部字段后需 `MarkLayoutDirty()`。
- `SetLeft` / `SetTop` 只标记 PositionDirty（不重排尺寸）；尺寸相关用 `SetWidth` / `SetHeight` / `SetSize`。

## 显示类问题

### 9. UI 完全不显示

- `BaseBody.Enabled` 是否 false（XML `Enabled="false"` 初始隐藏）；`RootNode.Enabled` 为 false 时 `SilkyUI.Update/Draw` 直接 return。
- 是否已进世界：Game UI 在 `OnEnterWorld` 才 `ReloadSilkyUIStacks`；`RegisterUI` 的 `LayerNode` 必须真实存在（`FindIndex` 找不到就跳过插入，默认 `"Vanilla: Radial Hotbars"` 一定存在）。
- 全局 UI 要用 `RegisterGlobalUI`（游戏菜单界面也显示）。

### 10. 元素绘制了但看不到（背景透明 / 尺寸为 0）

- `BackgroundColor` 默认 Transparent，`RectangleRender.Draw` 遇 Transparent 直接不画；尺寸为 0 也不画（`size.X <= 0 || size.Y <= 0` return）。
- TextView 无内容时 `TextSize` 可能为 0（`FitWidth/Height=true` 时尺寸由内容决定）；或被父容器 `OverflowHidden` 裁到区域外。

### 11. 图片（SUIImage）不显示

- `Texture2D` 未加载完成（`Texture2D.Value` 为 null 时不画）或 `ImageColor` 为 `Color.Transparent` 时不画；检查 `ImageAlign` / `ImagePercent` 是否把图片推出可视区。

### 12. 文本不换行

- 需 `WordWrap=true` 且容器宽度固定（`FitWidth=false`）；Fit 模式下宽度由内容决定，不会换行；`MaxLines` 过小时 `_lines.Count >= _maxLines` 不再加行。

### 13. 模糊背景不生效

- `EnableBlur`（BaseBody）与 `BlurMakeSystem.EnableBlur`（全局，默认 true）都要开。
- `Lighting.NotRetro` 为 false（复古光照）时 `BlurAvailable=false`；`SingleBlur=false` 是全局模糊，`true` 是每个 UI 独立计算。

### 14. 裁剪区域不对

- `HiddenBox`（Outer/Middle/Inner）决定被裁剪的盒模型区域；`GetClippingRectangle` 的 Transform 要与当前 SpriteBatch 矩阵一致。

## 事件类问题

### 15. 鼠标事件不触发

- 元素尺寸为 0（`ContainsPoint` 用 Bounds 判定）；`IgnoreMouseInteraction=true`（自己不响应，子元素仍响应）或 `DisableMouseInteraction=true`（子元素也不响应）。
- `BaseBody.IsInteractable` 为 false（`SilkyUI.HitTest` 前置条件）；`Main.hideUI` 为 true 时 `SilkyUIManager.Update` 直接 return。
- 被上层元素遮挡：命中测试按绘制顺序逆序，`ZIndex` 大者在上。

### 16. Click 不触发（但 Down/Up 触发）

- Click 要求按下与抬起都在同一元素上（`target != HoverTarget` 则不触发 Click）；抬起前元素被移走或被置顶遮挡会改变 HoverTarget。

### 17. 事件冒泡导致父容器也响应

- 事件默认沿 `Parent` 链冒泡（`evt.Previous = this; Parent?.OnXxx(evt)`）；用 `evt.Source` 判断最初触发者（如 SUISlider 用 `evt.Source != Thumb` 区分点击轨道 / 滑块）。

### 18. 滚轮滚动穿透到下层 UI

- `LockScroll(view)` 只锁定一次（`ScrollElement` 非空后忽略）；确认 SUIScrollView 命中在最上层（`OnMouseWheel` 里 `if (evt.ScrollElement != null) return;`）。

### 19. 输入框（EditText）无法输入 / IME 不弹

- 焦点是否在输入框上（点击获得焦点）、`OccupyPlayerInput` 是否为 true（`SUIEditText` 构造默认 true）；窗口失焦时（`Main.hasFocus=false`）不处理输入。

## 绑定类问题

### 20. 绑定不更新

- 源类是否实现 `INotifyPropertyChanged`（不实现则只有初始同步一次）；`Bind` 是否在元素进树后设置（`IsInsideTree` 时才订阅）。
- 嵌套路径中间层被替换时，若该对象未实现 `INotifyPropertyChanged` 则替换后不会通知。

## 渲染性能类问题

### 21. 大量 OverflowHidden 卡顿

- `IndependentRenderTarget=true`（默认）每帧离屏绘制开销大，内容简单时设 false 走 Scissor；减少嵌套裁剪容器。

### 22. UI 闪烁 / 批次冲突

- 自定义 `Draw` 里乱调 `spriteBatch.End/Begin` 会破坏框架的批次管理（框架用 `ReBegin` 保持矩阵与裁剪状态）。
- 画原版内容（物品图标等）用 `SUIItemSlot.DrawItemIcon` / `DrawHelper.DrawItemIcon` 等封装好的方法。

## 通用排查法

1. **探针法**：给可疑元素设高对比 `BackgroundColor`（如 `Color.Red * 0.3f`）+ `BorderColor`，看它实际占用的区域。
2. **日志**：`Mod.Logger.Info(...)` 输出 `Bounds` / `InnerBounds` / `LayoutIsDirty` 等布局关键值。
3. **源码与示例**：直接读框架源码；仓库 `UserInterfaces/` 下有 MouseMenuUI（右键菜单：动画 + 滚动 + 置顶）、DialogBoxUI（DEBUG 开关）、TestUI（悬停动画 + XML 映射）。
