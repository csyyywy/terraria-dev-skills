# 02. 工程结构、ModSources 与 junction 工作流

## 2.1 标准模组工程目录

tML 的 Developer Mode 会扫描 `Documents\My Games\Terraria\tModLoader\ModSources\<ModName>` 下的工程。一个完整工程：

```
<ModName>/
├── <ModName>.csproj               # 必须；导入 tML targets（见 templates/MyMod.csproj）
├── <ModName>.cs                   # 必须；主类 class <ModName> : Terraria.ModLoader.Mod
├── build.txt                      # 必须；displayName / author / version
├── description.txt                # 推荐；模组简介（工坊/列表显示）
├── icon.png                       # 推荐；80×80 图标（本地加载缺省回落占位图；发布工坊必须非默认图标）
├── Properties/
│   └── launchSettings.json        # 可选；VS/VS Code F5 调试启动
├── Localization/
│   ├── en-US.hjson                # 必须；英文键（新建内容必须补键）
│   ├── zh-Hans.hjson              # 推荐；简体中文
│   └── …（de-DE / fr-FR / ru-RU 等可选）
├── Content/
│   ├── Items/                     # ModItem（物品/武器/饰品/护甲/坐骑…）
│   ├── NPCs/                      # ModNPC（怪物/城镇 NPC/Boss）
│   ├── Projectiles/               # ModProjectile（弹幕）
│   ├── Tiles/                     # ModTile（方块）、ModWall（墙）
│   ├── Buffs/                     # ModBuff（增益/减益）
│   ├── Mounts/                    # ModMountData（坐骑）
│   ├── Dusts/                     # ModDust（粒子）
│   ├── Waters/                    # ModWaterStyle / ModWaterfallStyle（液体）
│   ├── Systems/                   # ModSystem（游戏系统）
│   └── …
├── bin/  obj/                     # 构建产物（.gitignore）
└── .gitignore
```

## 2.2 硬约束（写错必炸）

1. **主类必须继承 `Mod`**，且类名/程序集名 = 工程名（tML 据此关联）。
2. **`build.txt`** 每行 `key = value`，至少含 `displayName`、`author`、`version`。version 用语义化版本。
3. **`Localization/en-US.hjson` 必须有**；`en-US` 缺失会导致全部文本键解析失败。
4. **内容类必须有对应本地化键**（ItemName/ItemTooltip/NPCName/BuffName…），否则加载报 MissingLocalization。
5. 内容类对应的**贴图文件名 = 类名**（如 `ExampleItem.png`），放在类文件同目录；**必填**——缺同名贴图会在加载时抛 `MissingResourceException: 未找到预期的资源` 并**禁用整个模组**。没有美术时放占位纯色 PNG（32×32 即可）。
6. **csproj 的 TargetFramework/LangVersion 不要手改**（tMLMod.targets 已锁定 net8.0 / 12.0）。
7. 不要往工程里塞无关 DLL（避免引用冲突）；需要引第三方库时用 `Libraries` 外的独立文件夹并在 csproj 加 `<Reference>`。

## 2.3 ModSources 与 junction 工作流（本工作区采用）

目标：源码留在 AI 工作区 `<WORKSPACE>\<ModName>`，同时让 tML 能在 `ModSources\<ModName>` 看到它。用 **junction**（目录联接，同盘/跨盘均可）：

```powershell
# 生成链接（幂等，脚本在 resources/scripts/link-mod.ps1）
New-Item -ItemType Junction -Path "%USERPROFILE%\Documents\My Games\Terraria\tModLoader\ModSources\MyMod" -Target "<WORKSPACE>\MyMod"

# 验证
cmd /c dir "%USERPROFILE%\Documents\My Games\Terraria\tModLoader\ModSources"
# 应看到：<JUNCTION> MyMod [\??\<WORKSPACE>\MyMod]

# 删除链接（不删源码）
Remove-Item "%USERPROFILE%\Documents\My Games\Terraria\tModLoader\ModSources\MyMod" -Force
```

⚠️ **junction 与 csproj 的相对导入**：工程位于 junction 里时，MSBuild 把工程目录解析为真实路径（`<WORKSPACE>\MyMod`），所以 `..\tModLoader.targets` 解析到 `<WORKSPACE>\tModLoader.targets`（不存在）。因此：

- **junction 工作流**：csproj 用**绝对路径**导入 `<Import Project="<STEAM_LIB>\steamapps\common\tModLoader\tMLMod.targets" />`（见 templates/MyMod.csproj）。
- **直接放 ModSources** 的规范工程：用相对导入 `<Import Project="..\tModLoader.targets" />`（tML 会在 ModSources 维护这个包装文件）。

## 2.4 本工作区实测布局

```
<WORKSPACE>\
├── MyMod\                  # 模组源码（工程根）
│   ├── MyMod.csproj         # 绝对路径导入 tMLMod.targets
│   ├── MyMod.cs
│   ├── build.txt  description.txt  .gitignore
│   ├── Localization\en-US.hjson  zh-Hans.hjson
│   ├── Properties\launchSettings.json
│   └── Content\Items\ExampleItem.cs
├── skills\terraria-mod-dev\   # 本技能
└── README.md                # 工作区说明
```

`%USERPROFILE%\Documents\My Games\Terraria\tModLoader\ModSources\MyMod` → junction → `<WORKSPACE>\MyMod`。

## 2.5 资源（贴图/音效/本地化资源）约定

- 物品贴图：**本体贴图必填**（文件名=类名），`_Glow` 发光图 / `_Hands`/`_Held` 手持图可选。无美术时放占位纯色 PNG。
- NPC 贴图：本体 + `_Head`（城镇 NPC 头像）+ `_Party`（可选）。
- 方块贴图：按 `TileObjectData` 尺寸排布；`Main.tileSolid` 等由代码设置。
- 音效：`SoundStyle` 指向 `Assets/Sounds/...` 或 `SoundID`。
- 本地化资源 `.hjson` 见 05。
