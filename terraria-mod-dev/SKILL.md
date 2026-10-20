---
name: terraria-mod-dev
description: Terraria（泰拉瑞亚）tModLoader 模组开发入口：环境与工程结构、构建/调试/发布流水线、tModLoader API 速查、本地化、网络同步、跨模组互操作、无头测试与常见错误排查。细节见 resources/ 分册。
whenToUse: 开发或修改 tModLoader 模组，或需要查询 tModLoader API、构建、发布、排错时加载。
---

# Terraria 模组开发（tModLoader）

面向 tModLoader 1.4.4 模组开发（游戏 1.4.4、目标框架 net8.0）。构建需带 SDK 的 `dotnet`：官方要求 .NET 8 SDK，依赖库用到较新 C# 语法时需 9.x（见 `01-environment.md`）。
下文占位符：`<TML_DIR>` = tModLoader 安装目录，`<TML_SRC>` = tModLoader 源码检出目录，`<WORKSPACE>` = 模组工作区。

## 工作准则

1. **不确定就问。** 机制、数值、设计取舍拿不准时先向用户确认，别靠反复试错硬推。
2. **别猜引擎语义。** 原版行为（`realLife` 何时生效、鞭子标记是否自动、某个钩子跑在哪一端）以源码为准。凭印象写出的代码往往能编译能运行，但逻辑全错，还要等玩家反馈才暴露。

反编译查看原版实现（`tModLoader.dll` 内嵌整个 Terraria，无需另找 Terraria.dll）：

```bash
ilspycmd -t Terraria.NPC "<TML_DIR>/tModLoader.dll" > npc.cs
```

- 输出必须放在**工程目录之外**（如 `<WORKSPACE>/../audit/`），否则 SDK 会把 `.cs` 当源码编译，报大量语法错误。
- 先 `grep -n "关键词"` 定位行号，再用 `awk 'NR>=A && NR<=B'` 取片段；ilspy 输出中的 `Unknown result type` 噪音用 `grep -v` 过滤。

## 一句话流程

建工程（模板或 junction）→ 写内容（`Content/` + 同名 PNG + 本地化键）→ `dotnet build` → 游戏内 Reload → `/命令` 验证 → Workshop 发布。

## 三条硬约束

1. 每个内容类（Item / Projectile / NPC / Tile / …）**必须**有同名 PNG，缺失会抛 `MissingResourceException` 并禁用整个模组。
2. 新增内容的本地化键必须补进 `Localization/*.hjson`，否则报 `Missing localization key`。
3. 构建要用带 SDK 的 `dotnet`（`dotnet --list-sdks` 应能看到 9.x）；junction 工作区的 csproj 需用**绝对路径**导入 `tMLMod.targets`。

## 构建验证的取舍

玩家在玩时 tModLoader 客户端会锁住 `.tmod`，打包报 `TML003: Please close tModLoader or disable the mod in-game` —— 这是文件锁，不是代码错误。

| 目的 | 命令 | 说明 |
|---|---|---|
| 只验证代码可编译 | `dotnet build -c Release -p:BuildMod=false` | 跳过打包，游戏开着也能跑，最快 |
| 验证完整打包 | `dotnet build -c Release` | 需先关客户端 |
| 构建 + hjson 校验 | `scripts/headless-test.ps1 -ProjectPath <csproj> -ModName <Mod>` | 默认只做这两步 |
| 无头服务器加载测试 | 同上加 `-ValidateOnly:$false` | 会起服务器；出问题可先跳过 |

确认锁文件的是不是客户端（别误杀进程）：命令行含 `-terrariasteamclient` 的 `dotnet.exe` 才是游戏客户端。

## 分册索引

- `00-quickstart.md` 能力边界、工程结构、流水线、常见坑
- `01-environment.md` 环境要求、PATH 陷阱、验证命令
- `02-project-structure.md` 工程结构、ModSources、junction、贴图规则
- `03-build-test-publish.md` 构建 / 重载 / 服务器 / 调试 / 发布
- `04-api-cheatsheet.md` API 速查总索引（通用原则 + 子册映射）
  - `04a-content-types.md` §4.1–4.6 类型获取 / ModItem / ModNPC / ModProjectile / ModTile / ModBuff
  - `04b-systems-globals-recipe.md` §4.7–4.10 ModSystem（含世界持久化）/ ModPlayer / Global* / 合成配方
  - `04c-ids-damageclass-helpers.md` §4.11–4.14 ID 枚举 / DamageClass / 常用辅助 / 终局 ID 对照
  - `04d-autoload-town-npc.md` §4.15–4.16 贴图 Autoload 规则 / 城镇 NPC
  - `04e-pitfalls-weapons-armor.md` §4.17–4.18、§4.20–4.21 鞭子 / OnHit 减益 / 段身虫 / AoE / 护甲套装 / 弹药 / Boss 朝向与 AI
  - `04f-drawing-furniture-grapple.md` §4.19 手持绘制 / 箱子家具帧 / 钩爪 / 贴图白边
- `05-localization.md` hjson 本地化
- `06-netcode-sync.md` 网络同步 · `07-cross-mod.md` 跨模组
- `08-troubleshooting.md` 常见错误排查
- `09-links.md` · `10-official-reference.md` 官方资源导航
- `11-armor-textures.md` 装备/盔甲贴图规格
- `12-modconfig.md` ModConfig 配置系统
- `13-headless-testing.md` 无头服务器自动化测试（配合 `scripts/headless-test.ps1`、`examples/SelfTestCommand.cs`）
- `templates/` 模板 · `examples/` 示例 · `scripts/` 脚本
