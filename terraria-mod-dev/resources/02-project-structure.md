# 02. 工程结构、ModSources 与 junction 工作流

占位符：`<ModName>` = 模组工程名，`<WORKSPACE>` = 工作区根目录，`<TML_DIR>` = tModLoader 安装目录，`%USERPROFILE%` = 当前用户目录（PowerShell 写 `$env:USERPROFILE`）。

## 2.1 标准模组工程目录

tML 的 Developer Mode 扫描 `%USERPROFILE%\Documents\My Games\Terraria\tModLoader\ModSources\<ModName>` 下的工程：

```text
<ModName>/
├── <ModName>.csproj                # 必须；导入 tML targets（见 templates/MyMod.csproj）
├── <ModName>.cs                    # 必须；主类 class <ModName> : Terraria.ModLoader.Mod
├── build.txt                       # 必须；displayName / author / version
├── description.txt  icon.png       # 推荐；模组简介 + 80×80 图标（发布工坊必须非默认图标）
├── Properties/launchSettings.json  # 可选；VS/VS Code F5 调试启动
├── Localization/                   # en-US.hjson 必须（英文键，新建内容必须补键）；zh-Hans 推荐；de-DE 等可选
├── Content/…                       # 内容类，子目录约定见下
├── bin/  obj/                      # 构建产物（.gitignore）
└── .gitignore
```

`Content/` 子目录与内容类：`Items/`→ModItem（物品/武器/饰品/护甲/坐骑）、`NPCs/`→ModNPC（怪物/城镇 NPC/Boss）、`Projectiles/`→ModProjectile、`Tiles/`→ModTile、ModWall、`Buffs/`→ModBuff、`Mounts/`→ModMountData、`Dusts/`→ModDust、`Waters/`→ModWaterStyle、ModWaterfallStyle、`Systems/`→ModSystem。

## 2.2 硬约束（写错必炸）

1. 主类必须继承 `Mod`；类名 / 程序集名 = 工程名（tML 据此关联）。
2. `build.txt` 每行 `key = value`，至少含 `displayName`、`author`、`version`；`version` 用语义化版本。
3. `Localization/en-US.hjson` 必须有；缺失会导致全部文本键解析失败。
4. 内容类必须补本地化键（ItemName / ItemTooltip / NPCName / BuffName…），否则加载报 MissingLocalization。
5. 贴图文件名 = 类名（如 `ExampleItem.png`），放在类文件同目录，**必填**：缺同名贴图会在加载时抛 `MissingResourceException: 未找到预期的资源` 并**禁用整个模组**。无美术时放占位纯色 PNG（32×32 即可）。
6. 不要手改 csproj 的 `TargetFramework` / `LangVersion`（`tMLMod.targets` 已锁定 net8.0 / 12.0）。
7. 不要往工程里塞无关 DLL（引用冲突）；需引第三方库时放独立文件夹并在 csproj 加 `<Reference>`。

## 2.3 ModSources 与 junction 工作流

目标：源码留在工作区 `<WORKSPACE>\<ModName>`，同时让 tML 在 `ModSources\<ModName>` 看到它。用 **junction**（目录联接，同盘/跨盘均可）：

```powershell
New-Item -ItemType Junction `
  -Path   "$env:USERPROFILE\Documents\My Games\Terraria\tModLoader\ModSources\MyMod" `
  -Target "<WORKSPACE>\MyMod"   # 幂等；脚本见 resources/scripts/link-mod.ps1

cmd /c dir "$env:USERPROFILE\Documents\My Games\Terraria\tModLoader\ModSources"
# 应看到：<JUNCTION> MyMod [\<WORKSPACE>\MyMod]

Remove-Item "$env:USERPROFILE\Documents\My Games\Terraria\tModLoader\ModSources\MyMod" -Force  # 只删链接，不删源码
```

**junction 与 csproj 的相对导入**：工程位于 junction 里时，MSBuild 把工程目录解析为真实路径（`<WORKSPACE>\MyMod`），所以 `..\tModLoader.targets` 会解析到 `<WORKSPACE>\tModLoader.targets`（不存在）。因此：

- **junction 工作流**：csproj 用属性导入 `<Import Project="$(TMLDir)\tMLMod.targets" />`，构建时传 `-p:TMLDir="<TML_DIR>"`（模板见 `templates/MyMod.csproj`）。也可直接写死绝对路径，代价是换机器就要改。
- **直接放 ModSources** 的规范工程：用相对导入 `<Import Project="..\tModLoader.targets" />`（tML 在 ModSources 维护这个包装文件）。

## 2.4 工作区布局

```text
<WORKSPACE>\
└── <ModName>\       # 工程根，内容同 §2.1；csproj 用 $(TMLDir) 属性导入 tMLMod.targets
```

`<tML 用户数据>\ModSources\<ModName>` → junction → `<WORKSPACE>\<ModName>`：源码只维护一份，tML 通过链接看到它。

## 2.5 资源（贴图/音效/本地化资源）约定

- 物品贴图：**本体必填**（文件名 = 类名）；`_Glow` 发光图、`_Hands` / `_Held` 手持图可选。无美术时放占位纯色 PNG。
- NPC 贴图：本体 + `_Head`（城镇 NPC 头像）+ `_Party`（可选）。
- 方块贴图：按 `TileObjectData` 尺寸排布；`Main.tileSolid` 等由代码设置。
- 音效：`SoundStyle` 指向 `Assets/Sounds/...` 或 `SoundID`。
- 本地化资源 `.hjson` 见 05。
