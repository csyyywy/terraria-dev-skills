# 05. 本地化（Localization/*.hjson）

## 5.1 为什么必需

tML 1.4 起用 `Localization/<culture>.hjson` 取代旧 `.lang`。**新增任何内容类（物品/NPC/弹幕/增益/方块等）必须补本地化键**，否则加载时抛 "Missing localization key: Mods.MyMod.ItemName.X" 直接红字。

## 5.2 文件位置与命名

```
Localization/
├── en-US.hjson      # 英文（必须，缺它整体解析失败）
├── zh-Hans.hjson    # 简体中文
├── de-DE.hjson      # 可选多语言
└── …
```

## 5.3 键结构

顶层固定 `Mods.<ModName>.`，下面按类别分桶。

```hjson
{
    "Mods": {
        "MyMod": {
            "ItemName": {
                "ExampleItem": "Example Item",
                "ExampleSword": "Example Sword"
            },
            "ItemTooltip": {
                "ExampleItem": "A test item.\nLine 2 of tooltip.",
                "ExampleSword": "10% more damage"
            },
            "NPCName": {
                "ExampleNPC": "Example Slime"
            },
            "BuffName": {
                "ExampleBuff": "Example Buff"
            },
            "BuffDescription": {
                "ExampleBuff": "Increases damage by 5%"
            },
            "ProjectileName": {
                "ExampleProj": "Example Projectile"
            },
            "Messages": {
                "Greeting": "Hello, {0}!"
            }
        }
    }
}
```

> ⚠️ 上例为旧式回退桶写法。1.4.4 起实际显示优先使用 §5.7 的作用域键（`Items.X.DisplayName` 等）——新内容建议直接按作用域键补齐，否则 Developer Mode 会自动追加英文 stub 造成"写了中文仍显示英文"。

## 5.4 规则与技巧

- 键名 = 类名（不含命名空间），如 `ExampleItem`。
- `\n` 换行（hjson 里字符串转义）。
- 支持占位符与格式化：值里写 `{0}`、`{1}`，代码里 `Language.GetTextValue("Mods.MyMod.Messages.X", arg)`。
- 中文/其他语言文件键结构必须与 en-US 完全一致（缺键 → 显示回退到 en-US 或报错）。
- 也可以只维护 en-US + zh-Hans；tML 自动按玩家语言加载，缺文件时回退英文。
- **不要在 .cs 里硬编码显示文本**，一律走 hjson；否则无法多语言且 tML 会警告硬编码。

## 5.5 代码里读本地化

```csharp
using Terraria.Localization;

string s = Language.GetTextValue("Mods.MyMod.Messages.Greeting", "world");
// 在 ModItem/ModNPC 里常用：
//   DisplayName/Tooltip 由作用域键 Items.X.DisplayName / Items.X.Tooltip 自动提供（旧式 ItemName 桶仅回退）
```

## 5.6 官方支持的语言（wiki 确认）

- en-US / de-DE / it-IT / fr-FR / es-ES / ru-RU / zh-Hans / pt-BR / pl-PL 等。
- 键结构 `Mods.<Mod>.ItemName.<Class>` 等；支持占位符 `{0}`、`LocalizedText.Format`、复数化、聊天标签。
- `en-US.hjson` 是回退基准，务必存在且键齐全；缺某语言时回退英文。

## 5.7 ⚠️ 新版"作用域键"优先级（实测踩坑）

- tML 1.4.4 实际显示用的键是**作用域键**：`Mods.<Mod>.Items.<Class>.DisplayName` / `.Tooltip`、`Projectiles.<Class>.DisplayName`、`NPCs.<Class>.DisplayName`、`Buffs.<Class>.DisplayName/Description`、`Tiles.<Class>.MapEntry`、`DamageClasses.<Class>.DisplayName`。
- 旧版 `ItemName`/`ItemTooltip` 桶**只是回退**，作用域键存在时以作用域键为准。
- **Developer Mode 加载时会自动把缺失的作用域键以英文追加进源 hjson**（tooltip 还是空的），从而覆盖显示语言——这就是"写了中文还是英文"的常见原因。
- 修法：把作用域键也写成目标语言（中文），且保证键齐全，tML 就不会再自动追加英文键。

## 5.8 ⚠️ hjson 结构陷阱（大文件插键）

- 往大 hjson 插新键**必须插到对应块闭合 `}` 之前**（如 Items 桶内、`"Items": { ... }` 的 } 之前）。插错位置会变成父级点键（`Mods.<Mod>.X.DisplayName` 而非 `Mods.<Mod>.Items.X.DisplayName`），tML 找不到 → Developer Mode 自动补英文。
- 改完校验花括号平衡：统计 `{` 与 `}` 数量相等（脚本或编辑器检查），再 Reload 验证键能命中。
- 报错/自动补键时优先怀疑：键插错层级 > 键名拼错 > 缺语言文件。

## 5.9 官方范式：覆写共享文案 / 自定义本地化属性

- **多个物品共用一段文案**：覆写属性指向共享键（官方 "Overriding Content Localization Keys"）：
  ```csharp
  public override LocalizedText Tooltip => Language.GetOrRegister("Mods.MyMod.Common.SharedTip");
  ```
- **自定义本地化属性**（自动写入 .hjson，官方 "Adding Localizable Properties"）：
  ```csharp
  public static LocalizedText RestoreLifeText { get; private set; }
  public override void SetStaticDefaults() => RestoreLifeText = this.GetLocalization(nameof(RestoreLifeText));
  // 运行时取值：RestoreLifeText.Format(arg1, arg2)
  ```
