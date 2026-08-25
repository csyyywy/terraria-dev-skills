# ModConfig 分册（tML 配置系统，2026-08-24 实战验证）

> 来源：实战模组踩坑记录（配置默认值不生效、滑块范围只到 0~1、旧配置残留）。
> tML 源码依据：`patches/tModLoader/Terraria/ModLoader/Config/ConfigManager.cs`（本机 tml-src）。

## 1. 类骨架

```csharp
using Terraria.ModLoader;
using Terraria.ModLoader.Config;

public class MyConfig : ModConfig
{
    public override ConfigScope Mode => ConfigScope.ServerSide; // 或 ClientSide
    // ...字段
}
```

- `ServerSide`：多人下由服务端统一，配置存全局文件（见 §5）。
- `ClientSide`：每个玩家自己的一份。
- 每个 ModConfig 自动注册，无需手动 `AddConfig`。

## 2. ⚠️ 默认值铁律：值类型必须 `[DefaultValue]`（最坑）

tML 反序列化用 Newtonsoft `JsonConvert.PopulateObject(json, config, settings)`，
`serializerSettings` 是 `DefaultValueHandling.IgnoreAndPopulate` + `NullValueHandling.Ignore`。
**后果：JSON 里缺失的值类型字段（bool/int/float）会被重置成 `default(T)`（0/false），
字段初始化器 `= x` 在反序列化时不生效！**

实测（Newtonsoft 13.0.3，与 tML 相同 settings）：

```csharp
public float BloodShardRate = 1f;                    // 无 [DefaultValue]
[DefaultValue(1f)] public float DustRate = 1f;       // 有 [DefaultValue]

// PopulateObject("{}") 之后：
//   BloodShardRate == 0     ← 初始化器被冲掉！
//   DustRate      == 1f     ← [DefaultValue] 生效
// 同理 bool Enable = true → 变 false；int = 5 → 变 0
```

所以：
- **值类型（bool/int/float/enum/struct）**：`[DefaultValue(x)]`（`using System.ComponentModel;`）。
- **引用类型（List/类）**：字段初始化器即可（如 `public List<string> ExcludedItems = new();`）。
  （官方 ExampleMod `ModConfigShowcaseDefaultValues.cs` 明确写了这两条规则。）
- 字段初始化器+`[DefaultValue]` 都写上，双保险。
- 旧配置升级（类里删字段/加字段）时：旧 JSON 缺新字段 → `[DefaultValue]` 兜底；删掉的字段被忽略。
  想让"改默认值"也生效到老用户，用 `OnLoaded()` + 版本字段做迁移（见 §7）。

## 3. ⚠️ 滑块范围陷阱：必须 `[Range]` + `[Increment]`

float/int 字段**不加 `[Range]` 时**，tML 配置 UI 默认只给 **0~1（float）/ 0~100（int）** 的滑块，
声明写"0.1~5"也拖不到 5。修复：

```csharp
[Range(0.1f, 5f)]      // 滑块上下界
[Increment(0.1f)]      // 步进
[DefaultValue(1f)]
public float DropRateMult = 1f;
```

- `RangeAttribute(float,float)` / `RangeAttribute(int,int)`，都在 `Terraria.ModLoader.Config`。
- 整数步进同样 `[Increment(10)]`。
- 没有 `[Range]` 的数值字段 = 文本输入框（或 0~1 滑块），别指望。

## 4. 配置 UI 文案 = 本地化键（zh-Hans + en-US 都要）

- 键格式：`Mods.<ModName>.Configs.<ConfigClassName>.<Field>.Label` / `.Tooltip`；
  配置名 = `...Configs.<ConfigClassName>.DisplayName`。
- ⚠️ 注意是 `Configs`（复数）段，不是 `Config`。
- 两个语言文件（zh-Hans.hjson / en-US.hjson）**必须同时存在**对应键，
  否则 tML Developer Mode 会把缺失键以英文注释 stub 自动写进 hjson（覆盖手写内容）。
- 字段没有 Label/Tooltip 键时，UI 直接显示字段名。

## 5. 配置文件存哪 & 旧配置残留

- 路径：`Main.SavePath/ModConfigs/<ModName>_<ConfigName>.json`
  （本机：`%USERPROFILE%\Documents\My Games\Terraria\tModLoader\ModConfigs\`）。
  注：该 tML 版本里 **ServerSide 配置也存这里**（`ServerModConfigPath` 常量存在但 Load/Save 未用）。
- **读**：`ConfigManager.Load` → `PopulateObject(json, config, serializerSettings)`；
  文件不存在用 `"{}"` → 全走 §2 的默认值规则。
- **写**：改配置/世界保存时 `SerializeObject`（默认值会被 Ignore 掉，文件很干净）。
- **旧配置残留**：老版本留下的 JSON 不会自动重写。升级了字段结构后，
  要么手动删 `ModConfigs/<ModName>_*.json`，要么用 §7 版本迁移自动重置。
- JSON 损坏时 tML 会告警、删文件、用默认值。

## 6. Instance 单例

```csharp
private static MyConfig? _instance;
public static MyConfig Instance => _instance ??= ModContent.GetInstance<MyConfig>();
```

- 消费方直接 `MyConfig.Instance?.Field ?? 默认值`，全模组统一入口。
- ⚠️ 配置实例字段值可能为 0（旧 JSON 缺字段且没 [DefaultValue]），
  消费处仍建议 `?? 默认值` 双保险（也防配置类未注册时 Instance 为空）。

## 7. 版本迁移（可选，推荐）

```csharp
[DefaultValue(0)]
public int ConfigVersion = 0;          // 旧 JSON 缺此字段 → 0

public override void OnLoaded()        // ConfigManager.Add 里 Load 之后调用
{
    if (ConfigVersion < CurrentVersion)
    {
        var fresh = new MyConfig();    // 字段初始化器 = 新默认值模板
        // 逐字段复制 fresh → this（或直接重置）
        ConfigVersion = CurrentVersion;
    }
}
```

- `OnLoaded()` 在 `ConfigManager.Add` 中 `Load(config)` 之后、`OnChanged()` 之前调用（源码确认）。
- 用法：类结构或默认值大改时把 `CurrentVersion` +1，老用户自动整体重置为新默认值。

## 8. 常见坑清单（速查）

| 现象 | 原因 | 修复 |
|---|---|---|
| 新加的配置项显示 0 / 关 | 旧 JSON 缺字段 + 无 `[DefaultValue]` | 值类型加 `[DefaultValue]` |
| 全新安装总开关是 false | `PopulateObject("{}")` 把 bool 冲成 false | `[DefaultValue(true)]` |
| 滑块只能拖到 1 | 没 `[Range]`，默认 0~1 | `[Range(min,max)]` |
| 配置 UI 显示英文字段名 | 缺 Label/Tooltip 键 | 补 hjson 双语键 |
| 升级后旧值残留 | 旧 JSON 未重写 | 删配置 JSON / 版本迁移 |
| hjson 被 tML 自动改写 | 缺键触发 Developer Mode stub | 引用键 zh+en 同时补齐 |
