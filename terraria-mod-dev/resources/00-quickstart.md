# 00. 从零到可玩（快速上手）

占位符：`<ModName>` = 模组工程名，`<TML_DIR>` = tModLoader 安装目录，`%USERPROFILE%` = 当前用户目录。

## 1. 能力边界（tML 能做什么）

- 物品与装备：武器（近战/远程/魔法/召唤/投掷）、盔甲、饰品、坐骑、钩爪、弹药。
- 战斗：NPC（城镇 NPC、Boss）、弹幕、增益/减益、自定义伤害类型（DamageClass）。
- 世界与系统：tile、wall、生物群系、世界生成；ModSystem（全局钩子）、ModPlayer（玩家状态）、Global*。
- 交互与经济：自定义 UI、ModCommand、热键；Recipe、NPC 商店、掉落。
- 网络与跨模组：ModPacket 同步、Mod.Call。

## 2. 工程结构（硬约束）

```text
<ModName>/
├── <ModName>.csproj    # 导入 tML targets
├── <ModName>.cs        # 主类 : Mod
├── build.txt           # displayName / author / version(2~4 段数字)，大小写敏感
├── description.txt  icon.png   # 简介；80×80 图标（发布工坊须非默认图标）
├── Localization/en-US.hjson    # 回退基准，必填（+ zh-Hans.hjson）
└── Content/…           # Items / NPCs / Tiles / Projectiles / Buffs / …
```

完整目录见 02 §2.1。硬约束：

- **每个内容类必须有同名贴图**（`Content/Items/X.cs` → `X.png`；路径 = 工程根 + 命名空间点变反斜杠 + 类名）。缺失时加载抛 `MissingResourceException` 并禁用整个模组；无美术就放占位纯色 PNG。
- 主类继承 `Mod`，类名 = 工程名。新内容的本地化键必须同步到 `Localization/*.hjson`，否则报 Missing localization key。
- 配方（`Recipe.Create`）只能写在 `AddRecipes()`（ModItem / ModSystem / GlobalItem），放 `Load()` 抛 `RecipeException`。

## 3. 开发流水线

1. 建工程：复制 `templates/`，或游戏内 Developer Mode 新建；`scripts/link-mod.ps1` 建 ModSources junction。
2. 写内容：`Content/` 下按类建目录，同步本地化键。
3. 构建：`dotnet build <ModName>.csproj -c Debug`，产出 `.tmod` 到 tML `Mods/`（SDK 要求见 01）。
4. 测试与调试：tML 内启用 / Reload，进世界用 `/命令` 或合成验证；日志见 03 §3.4，排错见 08。
5. 发布：游戏内 Workshop 发布（需 Steam 版 + 非受限账号）。

## 4. 关键命令

- 构建：`dotnet build <csproj> -c Debug`；只编译不打包加 `-p:BuildMod=false -p:TargetFramework=net8.0`（只给前者会报 NETSDK1013）。
- 链接 ModSources：`powershell -ExecutionPolicy Bypass -File scripts/link-mod.ps1`
- SDK 自检：`dotnet --list-sdks` 应列出 9.x（依赖 SilkyUI 等新语法工程时必需，见 01 §1.2）。

## 5. 常见坑速览

- .NET 相关：`No .NET SDKs were found` / ".NET SDK not recognised"，或 `error CS0106: 修饰符"public"对该项无效`（报在 `SilkyUIAnalyzer\ITypeSymbolExtensions.cs`）→ PATH 命中的 SDK 不是 9.x，用 `dotnet --list-sdks` 确认后换安装点；不是你的代码问题。
- Missing localization key → 补 hjson；缺同名贴图 → 补 PNG（缺失会禁用整个模组）。
- Reload 后旧数据残留 → 在 `Unload()` 里清静态字段。
- 多玩家不同步 → `ModPacket` / `NetSend`。

## 6. 详见

01 环境 / 02 结构 / 03 构建发布 / 04 API 速查 / 05 本地化 / 06 网络 / 07 跨模组 / 08 排错 / 09 链接 / 10 官方参考。
