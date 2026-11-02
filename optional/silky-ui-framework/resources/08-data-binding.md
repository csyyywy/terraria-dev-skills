# 数据绑定与命令

## DataContext（数据上下文）

- `DataContext`：当前生效的数据上下文（`object`，虚属性，对外只读）。优先取 `LocalDataContext`，为空则继承 `Parent.DataContext`；由 `UpdateDataContext()` 计算：`DataContext = LocalDataContext ?? Parent?.DataContext`。
- `LocalDataContext`：本地数据上下文，优先级最高，不应频繁变更。
- 容器 `AddChild`/`RemoveChild` 时自动 `UpdateDataContext()`；子元素没有本地上下文则跟随父级。

## 绑定（Bind）

`public void Bind(string sourcePropName, string targetPropName)`：创建源属性到目标属性的绑定，支持点分隔的嵌套路径。

- 源路径可嵌套：`"User.Profile.AvatarUrl"`（`PropertyPathParser.Parse` 按 `.` 拆分）。
- 同一目标重复 `Bind` 会替换旧绑定（旧绑定 Source 置 null，释放订阅）。
- 绑定在元素进入 UI 树后才生效（`IsInsideTree` 时把 `DataContext` 设为 Source）。

### 示例

```csharp
// ViewModel 实现 INotifyPropertyChanged
public class MyViewModel : INotifyPropertyChanged
{
    private string _title;
    public string Title
    {
        get => _title;
        set { _title = value; PropertyChanged?.Invoke(this, new(nameof(Title))); }
    }
    public event PropertyChangedEventHandler PropertyChanged;
}

var vm = new MyViewModel { Title = "初始标题" };
panel.LocalDataContext = vm;                              // 设置数据上下文
panel.TitleView.Bind("Title", nameof(UITextView.Text));   // 单向绑定：vm.Title → Text
```

### 绑定机制（BindingEntry）

- 源对象实现 `INotifyPropertyChanged` 时，按路径层级逐层订阅 `PropertyChanged`。
- 属性变化 → 清除后续层级订阅 → 重建（处理中间层对象被替换）→ `SyncBinding()` 同步最新值到目标。
- 目标属性 setter 走 `ObjectAccessorCache` 反射缓存（`GetAccessor(target).GetSetter(name)`），无运行时反射开销；嵌套路径中间层为 null 时短路，不抛异常。
- 目前只有单向（源→目标）；值转换器（IValueConverter）与双向绑定尚未实现。

## 命令（ICommand）

```csharp
public ICommand Command { get; set; }         // UIView 上
protected virtual object CommandParameter => null;
protected void ExecuteCommand()               // 鼠标按下时执行
{
    if (Command == null) return;
    var obj = CommandParameter;
    if (Command.CanExecute(obj)) Command.Execute(obj);
}
```

- `OnLeftMouseDown` 冒泡链末尾调用 `ExecuteCommand()`。
- 接口为 `System.Windows.Input.ICommand`（WPF 接口，tModLoader 环境可用）。
- `SUISlider.DragCommand`：拖拽时执行（`OnDrag` 里 `DragCommand.CanExecute(Value)` 后 `Execute(Value)`）；`slider.DragCommand = new RelayCommand(v => { /* 拖拽回调 */ });`（`RelayCommand` 需自实现 `ICommand`）。

## 生命周期与绑定的配合

| 时机 | 动作 |
| --- | --- |
| `HandleEnterTree` | `SubscribeDataContext()`：所有绑定的 `Source = DataContext` |
| `HandleExitTree` | `UnsubscribeDataContext()`：绑定的 `Source = null`（释放订阅） |
| `LocalDataContext` 变化 | `UpdateDataContext()` 重新计算并订阅 |

绑定是源→目标的只读监听，不会反向写回源对象。

## 常见坑

1. **`OnInitialize` 里 Bind 时 DataContext 还没设**：绑定在元素进树时生效；先 Bind 后设 DataContext 时，进树时 `SubscribeDataContext` 会把当前 DataContext 作为 Source。
2. **源类没实现 `INotifyPropertyChanged`**：只在设置 Source 时同步一次（`SyncBinding`），之后源变化不推送。
3. **目标属性名必须存在**：`ObjectAccessorCache.GetSetter` 找不到会抛异常；属性名用 `nameof` 防拼错，如 `Bind("Title", nameof(UITextView.Text))`。
