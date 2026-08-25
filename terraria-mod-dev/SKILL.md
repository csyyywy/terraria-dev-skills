---
name: terraria-mod-dev
description: Terraria（泰拉瑞亚）tModLoader 模组开发的入口技能：环境/工程结构/构建调试发布流水线/API 速查/本地化/网络同步/跨模组/常见坑。细节全部在 resources/ 分册。
whenToUse: 开发或修改 Terraria 模组、提问 tModLoader API/构建/发布/排错时加载。
---

# Terraria 模组开发（tModLoader）

环境基线（本机已验证）：Terraria 1.4.4 + tModLoader 1.4.4 stable（2026.06）+ .NET 8.0.423 SDK。

## 先读（按需）

- `resources/00-quickstart.md`：从零到可玩（能力边界/工程结构/流水线/命令/常见坑）
- `resources/01-environment.md`：环境、PATH 陷阱、验证命令
- `resources/02-project-structure.md`：工程结构、ModSources、junction、贴图必填
- `resources/03-build-test-publish.md`：构建/重载/服务器/调试/发布
- `resources/04-api-cheatsheet.md`：API 速查**总索引**（通用原则 + 子分册映射；Recipe 只能在 AddRecipes 里调用等铁律在子分册内）。已拆分为 6 个小分册，按需取用：
  - `04a-content-types.md`：类型获取 / ModItem / ModNPC / ModProjectile / ModTile / ModBuff（§4.1–4.6）
  - `04b-systems-globals-recipe.md`：ModSystem（含世界持久化）/ ModPlayer / Global* / 合成配方（§4.7–4.10）
  - `04c-ids-damageclass-helpers.md`：ID 枚举 / DamageClass / 常用辅助（QuickSpawnItem 双重载、armor 槽位表）/ 终局 ID 对照（§4.11–4.14）
  - `04d-autoload-town-npc.md`：贴图 Autoload 规则 / 城镇 NPC 全流程（§4.15–4.16）
  - `04e-pitfalls-weapons-armor.md`：实战踩坑——鞭子/OnHit 减益/段身虫/AoE/护甲套装/弹药与 Shoot（§4.17–4.18）
  - `04f-drawing-furniture-grapple.md`：实战踩坑——手持绘制/箱子家具帧/钩爪死循环/贴图白边（§4.19）
- `resources/05-localization.md`：hjson 本地化
- `resources/06-netcode-sync.md`、`resources/07-cross-mod.md`、`resources/08-troubleshooting.md`
- `resources/09-links.md`、`resources/10-official-reference.md`：官方源导航
- `resources/11-armor-textures.md`：装备/盔甲贴图规格（_Head/_Body/_Legs 尺寸、静态帧方案、Body composite、修复工具）
- `resources/12-modconfig.md`：ModConfig 配置系统（值类型 `[DefaultValue]` 铁律、`[Range]`/`[Increment]` 滑块、配置存盘路径、本地化键、版本迁移）
- `resources/13-headless-testing.md`：**无头服务器自动化测试**——免交互启动 + 指令文件桥 + `[TEST]` 标记断言；配套 `scripts/headless-test.ps1` 与 `examples/SelfTestCommand.cs`。注意：stdin 喂命令不可行（Windows 控制台 API 限制，已实测）
- `resources/templates/` 模板、`resources/examples/` 示例、`resources/scripts/` 脚本

## 一句话流程

建工程(模板/junction) → 写内容(Content/ + 同名贴图 + Localization键) → dotnet build(用 %USERPROFILE%\.dotnet\dotnet.exe) → 游戏内 Reload → /命令测试 → Workshop 发布。

## 三条高频铁律

1. 每个内容类(Item/Projectile/NPC/Tile/…)都**必须**有同名贴图 PNG，否则加载抛 MissingResourceException 并禁用模组。
2. 新增内容的**本地化键**必须补到 Localization/*.hjson，否则报 Missing localization key。
3. 构建用带 SDK 的 dotnet（PATH 上那个是纯运行时）；junction 工作区 csproj 用绝对路径导入 tMLMod.targets。
