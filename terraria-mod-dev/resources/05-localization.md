# 05. 本地化（Localization/*.hjson）

## 5.1 为什么必需

tML 1.4 起用 `Localization/<culture>.hjson` 取代旧 `.lang`；新增内容类（物品/NPC/弹幕/增益/方块等）缺键，加载即抛 `Missing localization key: Mods.MyMod.ItemName.X`。

## 5.2 文件位置与命名

```text
Localization/
├── en-US.hjson      # 英文（必须，缺它整体解析失败）
├── zh-Hans.hjson    # 简体中文
└── de-DE.hjson      # 可选多语言
```

## 5.3 键结构

顶层固定 `Mods.<ModName>.`，下面按类别分桶。

```hjson
{
    "Mods": {
        "MyMod": {
            "ItemName":        { "ExampleItem": "Example Item", "ExampleSword": "Example Sword" },
            "ItemTooltip":     { "ExampleItem": "A test item.\nLine 2 of tooltip.", "ExampleSword": "10% more damage" },
            "NPCName":         { "ExampleNPC": "Example Slime" },
            "BuffName":        { "ExampleBuff": "Example Buff" },
            "BuffDescription": { "ExampleBuff": "Increases damage by 5%" },
            "ProjectileName":  { "ExampleProj": "Example Projectile" },
            "Messages":        { "Greeting": "Hello, {0}!" }
        }
    }
}
```

上例是旧式回退桶写法；1.4.4 起显示优先取 §5.7 的作用域键，新内容直接按作用域键补齐，否则 Developer Mode 会追加英文 stub，表现为"写了中文仍显示英文"。

## 5.4 规则与技巧

- 键名 = 类名（不含命名空间），如 `ExampleItem`。
- 值里的 `\n` 是换行（hjson 字符串转义）。
- 各语言文件键结构必须与 en-US 完全一致，缺键回退英文或报错；也可只维护 en-US + zh-Hans，tML 按玩家语言加载。
- 显示文本一律走 hjson，不要硬编码在 .cs 里——既不能多语言，tML 也会告警。

## 5.5 代码里读本地化

```csharp
using Terraria.Localization;

// 值里写 {0}、{1} 占位，读取时按序传参
string s = Language.GetTextValue("Mods.MyMod.Messages.Greeting", "world");
// ModItem/ModNPC 的 DisplayName/Tooltip 由作用域键 Items.X.DisplayName / Items.X.Tooltip 自动提供，
// 旧式 ItemName 桶仅作回退。
```

## 5.6 官方支持的语言（wiki 确认）

- en-US / de-DE / it-IT / fr-FR / es-ES / ru-RU / zh-Hans / pt-BR / pl-PL 等。
- 另支持 `LocalizedText.Format`、复数化、聊天标签；`en-US.hjson` 是回退基准，必须存在且键齐全。

## 5.7 作用域键优先级（1.4.4+）

- 实际显示取作用域键：`Mods.<Mod>.Items.<Class>.DisplayName` / `.Tooltip`、`Projectiles.<Class>.DisplayName`、`NPCs.<Class>.DisplayName`、`Buffs.<Class>.DisplayName/Description`、`Tiles.<Class>.MapEntry`、`DamageClasses.<Class>.DisplayName`；旧版 `ItemName`/`ItemTooltip` 桶只是回退。
- Developer Mode 加载时会把缺失的作用域键以英文追加进源 hjson（tooltip 留空），覆盖显示语言——这是"写了中文还是英文"的常见原因。
- 修法：作用域键也写目标语言并保证键齐全，tML 就不再追加英文键。

## 5.8 hjson 结构陷阱（大文件插键）

- 新键必须插在对应块的闭合 `}` 之前（如 `"Items": { ... }` 内）。插错会落到父级点键 `Mods.<Mod>.X.DisplayName` 而非 `Mods.<Mod>.Items.X.DisplayName`，tML 找不到 → Developer Mode 自动补英文。
- 改完校验 `{` 与 `}` 数量相等，再 Reload 确认键能命中；排查顺序：插错层级 > 键名拼错 > 缺语言文件。

## 5.9 官方范式：覆写共享文案 / 自定义本地化属性

- 多个物品共用一段文案：覆写属性指向共享键（官方 "Overriding Content Localization Keys"）。

  ```csharp
  public override LocalizedText Tooltip => Language.GetOrRegister("Mods.MyMod.Common.SharedTip");
  ```

- 自定义本地化属性，自动写入 .hjson（官方 "Adding Localizable Properties"）：

  ```csharp
  public static LocalizedText RestoreLifeText { get; private set; }
  public override void SetStaticDefaults() => RestoreLifeText = this.GetLocalization(nameof(RestoreLifeText));
  // 运行时取值：RestoreLifeText.Format(arg1, arg2)
  ```
