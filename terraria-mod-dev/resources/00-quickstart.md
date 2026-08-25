# 00. 从零到可玩（快速上手）

本分册是 SKILL.md 的详细展开：能力边界、工程结构、流水线、命令与常见坑。

## 1. 能力边界（tML 能做什么）

- 物品与装备：物品、武器（近战/远程/魔法/召唤/投掷）、盔甲、饰品、坐骑、钩爪、弹药。
- 战斗内容：NPC（城镇 NPC、Boss）、弹幕、增益/减益、自定义伤害类型（DamageClass）。
- 世界内容：方块(tile)、墙(wall)、生物群系、世界生成。
- 系统逻辑：ModSystem（全局钩子）、ModPlayer（玩家状态）、Global*（全局挂钩）。
- UI 与交互：自定义 UI、游戏内命令（ModCommand）、热键。
- 经济与合成：Recipe、NPC 商店、掉落。
- 网络与跨模组：ModPacket 同步、Mod.Call。

## 2. 工程结构（硬约束）

<ModName>/
├── <ModName>.csproj    # 导入 tML targets
├── <ModName>.cs        # 主类 : Mod
├── build.txt           # displayName / author / version(2~4段数字)
├── description.txt     # 简介
├── icon.png            # 模组图标（推荐；80×80，发布工坊须非默认图标）
├── Localization/en-US.hjson（+zh-Hans.hjson）
└── Content/…           # Items/NPCs/Tiles/Projectiles/Buffs/…

铁律：

1. 主类继承 Mod，类名=工程名。
2. build.txt 大小写敏感；version 用 2~4 段数字。
3. Localization 必填，en-US.hjson 是回退基准。
4. **每个内容类必须有同名贴图**（Content/Items/X.cs → Content/Items/X.png），缺了加载抛 MissingResourceException 并禁用整个模组；没美术就放占位纯色 PNG。
5. 贴图路径 = 工程根 + 命名空间(点变反斜杠) + 类名 + .png。
6. 配方(Recipe.Create)只能在 AddRecipes() 里加（ModItem/ModSystem/GlobalItem 的 AddRecipes），不能放 Load()，否则 RecipeException。

## 3. 开发流水线

1. 建工程：复制 templates/ 或游戏内 Developer Mode 新建；用 scripts/link-mod.ps1 做 ModSources junction。
2. 写内容：Content/ 下按类建目录；本地化键同步 Localization/。
3. 构建：用带 SDK 的 dotnet（见 01）`build <ModName>.csproj -c Debug`；产出 .tmod 到 tML Mods/。
4. 测试：tML 内启用/Reload，进世界用 /命令 或合成验证。
5. 调试：看 tML 日志（本机 tModLoader-Logs/client.log）；对照 08。
6. 发布：游戏内 Workshop 发布（需 Steam 版 + 非受限账号）。

## 4. 关键命令

- 构建：%USERPROFILE%\.dotnet\dotnet.exe build <csproj> -c Debug
- 只编译：加 -p:BuildMod=false -p:TargetFramework=net8.0（只给 BuildMod=false 会报 NETSDK1013）
- 链接：powershell -ExecutionPolicy Bypass -File ...\scripts\link-mod.ps1
- 日志：<STEAM_LIB>\steamapps\common\tModLoader\tModLoader-Logs\client.log

## 5. 常见坑速览

- ".NET SDK not recognised" → PATH 命中无 SDK 副本，用 %USERPROFILE%\.dotnet\dotnet.exe。
- Missing localization key → 补 hjson。
- 缺同名贴图 → 加载禁用模组（见 2）。
- Reload 旧数据残留 → Unload() 清静态字段。
- 多玩家不同步 → ModPacket/NetSend。

## 6. 详见

01 环境 / 02 结构 / 03 构建发布 / 04 API 速查 / 05 本地化 / 06 网络 / 07 跨模组 / 08 排错 / 09 链接 / 10 官方参考。
