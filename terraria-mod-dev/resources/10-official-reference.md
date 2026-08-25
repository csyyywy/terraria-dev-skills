# 10. 官方参考资料导航与要点（2026-08 参照 docs.tmodloader.net + GitHub wiki 整理）

> 本分册把两个官方源整理成可导航的索引，并提取直接可用的要点。写 API 前先在这里定位，再点开对应官方页核对细节。

## 10.1 官方 API 文档（docs.tmodloader.net）

- 类列表入口（annotated）：https://docs.tmodloader.net/docs/stable/annotated.html
- 用法：先看类列表找类 → 点进类页看"构造/方法/字段"清单 → 每个成员有签名与说明。
- 常见类页（stable 版 URL 模式 `https://docs.tmodloader.net/docs/stable/class_<名字>.html`，全大写类名会转成 `_` 分隔小写，如 ModNPC → `class_mod_n_p_c.html`）：

| 类 | 官方页 | 主要用途 |
|---|---|---|
| ModItem | class_mod_item | 物品/武器/饰品/护甲 |
| ModNPC | class_mod_n_p_c | 敌人/城镇NPC/Boss |
| ModProjectile | class_mod_projectile | 弹幕 |
| ModTile | class_mod_tile | 方块 |
| ModWall | class_mod_wall | 墙 |
| ModSystem | class_mod_system | 游戏系统/世界钩子 |
| ModPlayer | class_mod_player | 玩家扩展 |
| ModBuff | class_mod_buff | 增益/减益 |
| ModMount | class_mod_mount | 坐骑 |
| ModCommand | class_mod_command | 聊天命令 |
| ModContent | class_mod_content | 类型获取/加载 |
| GlobalItem / GlobalNPC | class_global_item / class_global_n_p_c | 全局钩子 |
| Recipe | class_recipe | 合成配方 |
| DamageClass | class_damage_class | 自定义伤害类型 |
| IEntitySource | 见 wiki IEntitySource | 物品来源溯源 |

## 10.2 官方 Wiki（github tModLoader/tModLoader wiki）

入口：https://github.com/tModLoader/tModLoader/wiki （raw 页面：`https://raw.githubusercontent.com/wiki/tModLoader/tModLoader/<页名>.md`）

| 主题 | Wiki 页 | 用途 |
|---|---|---|
| 入门 | Basic-tModLoader-Modding-Guide | 从零建 mod |
| 开发者总览 | tModLoader-guide-for-developers | 环境/IDE/.NET 要求 |
| build.txt | build.txt | 元数据属性全表 |
| description.txt | description.txt | 简介文件 |
| 本地化 | Localization（另有 zh-Localization-本地化 中文版） | hjson 结构/替换/格式化 |
| 自动加载/贴图 | Basic-Autoload | 内容贴图=类名+命名空间→目录规则 |
| 发光图 | Basic-glowmask-guide | `_Glow` 贴图 |
| 绘图 | Spriting | 美术规格 |
| 合成/掉落/坐标 | Basic-* 系列、IEntitySource | 进阶主题 |
| 发布 | Workshop | 创意工坊发布门槛 |
| 服务器 | Starting-a-modded-server / DedicatedServerUtils | 专用服务器 |
| 命令行 | Command-Line | -skipselect 等调试参数 |
| 跨模组 | Expert-Cross-Mod-Content | modReferences/weakReferences/Mod.Call |
| 更新迁移 | Update-Migration-Guide | 版本迁移/API 变化 |

## 10.3 从官方源提取的关键要点

### build.txt（官方全属性，注意**大小写敏感**）

`property = value` 每行一个，列表用逗号分隔。常用：

| 属性 | 说明 |
|---|---|
| displayName / author | 显示名/作者 |
| version | **2~4 段数字**（如 1.2.3.4），不是小数；`1` 或 `1.2.3.4.5` 非法 |
| homepage | 主页链接 |
| modReferences | 强依赖模组列表（无则不能加载本 mod） |
| weakReferences | 可选依赖（有则编译可用、缺省可运行） |
| dllReferences | 额外 DLL，文件放工程顶层 `lib/`，按文件名（无扩展名）引用 |
| noCompile | 是否用预编译 dll（名 = `ModName.dll`）代替源码编译 |
| hideCode / hideResources | 是否在"提取 mod"时隐藏代码/资源（会影响跨模组互操作） |

### 贴图自动加载规则（官方确认）

- **Items / Projectiles / NPC 必须有贴图**，缺一个模组就无法加载（正是我们踩过的 MissingResourceException）。
- 贴图路径 = 工程根 + 命名空间（`.` 变 `\`）+ 类名 + `.png`；即 .cs 与同名 .png 同目录即可。
- 特殊贴图：饰品 `[AutoloadEquip(EquipType.X)]` → `_Back`/`_Shield` 等；城镇NPC/Boss `[AutoloadHead]`/`[AutoloadBossHead]` → `_Head`/`_Head_Boss`；发光贴图 `_Glow`。

### 本地化（官方要点）

- 支持语言：en-US / de-DE / it-IT / fr-FR / es-ES / ru-RU / zh-Hans / pt-BR / pl-PL 等。
- 键结构 `Mods.<Mod>.ItemName.<Class>` 等；支持占位符 `{0}`、绑定值、`LocalizedText.Format`、复数化、聊天标签、`NetworkText`。
- `en-US.hjson` 是回退基准，**务必存在且键齐全**。
- 1.4.4 起 hjson 是唯一本地化方式（旧 `.lang` 废弃）。

### 发布（Workshop 官方要求）

- 需要 **Steam 版 tModLoader** + 非受限 Steam 账号（通常要求账号在 Steam 消费 ≥ $5）。
- 流程：构建 → 游戏内 `Workshop -> Publish`（或 `-publish` 命令行）→ 填信息（description.txt 作简介、icon 作图标、build.txt version 作版本）。
- 更新：改 version 后重新发布；贡献者管理在工坊页 "Add/remove Contributors"。

### 命令行与调试（官方）

| 参数 | 用途 |
|---|---|
| `-skipselect "玩家:世界"` | 自动选第 1 个玩家/世界直接进游戏（调试神器，配合 VS F5） |
| `-savedirectory <path>` / `-tmlsavedirectory <path>` | 指定存档目录 |
| `-modpack <name>` | 用指定 modpack |
| `-modpath <path>` | 指定 .tmod 目录（托管服务器用） |
| `-publish` / `-ciprep` / `-steamworkshopfolder` | CI 发布相关 |
| `-loadlib` / `-experimental` | 加载/实验特性 |

### 服务器（官方）

- 1.4.4 专用服务器说明见 DedicatedServerUtils（`tModLoader` 安装目录 `DedicatedServerUtils/` 有 Docker/脚本）。
- 托管环境用 `-modpath` 指 Mods 目录、`-savedirectory` 指定存档。

### 跨模组（官方）

- 三种做法：强依赖（modReferences）、弱依赖（weakReferences）、运行时 Mod.Call/ModLoader.GetMod。
- 官方建议优先让本 mod 能独立加载；Mod.Call 是字符串协议，需文档化并向后兼容。

### 环境（官方）

- 官方要求 **.NET 8 SDK**（不要 .NET 9/10）；`dotnet --list-sdks` 验证。
- 官方推荐 VS 2022 17.8+；本技能在本机 VS Code 场景同样适用（见 01）。
