# NOTICE — 第三方内容与出处

本仓库（`.dsh/skills`）是**文档 + 桥接代码 + PowerShell 脚本**的集合，不包含任何游戏素材。

## 运行时依赖

| 名称 | 许可 | 与本项目的关系 | 是否分发其代码 |
|---|---|---|---|
| [tModLoader](https://github.com/tModLoader/tModLoader) | MIT | 全部功能运行在它的 API 之上（`ModSystem`、`Main`、`PlayerInput` 等） | **否**，仅调用公开 API |
| [Terraria](https://terraria.org) | 商业软件 | 被测试的游戏本体 | **否**，不附带任何贴图/音效/世界文件 |
| [.NET 8](https://github.com/dotnet/runtime) | MIT | 运行时 | 否 |
| [PowerShell 7](https://github.com/PowerShell/PowerShell) | MIT | 脚本宿主 | 否 |

## 文档中提及的第三方模组/框架

仅作文档引用与兼容性说明，**不包含其代码**：

| 名称 | 出处 | 用途 |
|---|---|---|
| SilkyUI（SilkyUIFramework） | <https://github.com/487666123/SilkyUIFramework> | UI 框架；`silky-ui-framework` 技能按上游 API 整理 |
| SubworldLibrary | Steam 创意工坊 | 子世界库，仅作为"依赖模组如何进沙盒"的示例 |

## 参考过但未采用

| 名称 | 结论 |
|---|---|
| terrex（Python 协议客户端） | 评估后不采用：需自行复刻协议版本，维护成本高于收益。结论记录在 `terraria-headless-test/docs/tier0-terrex-spike.md` |

## 素材与隐私

- 仓库内 `terraria-mod-dev/resources/templates/` 的示例 PNG 为本项目自制占位图（纯色/简单图形），非游戏素材。
- `terraria-headless-test/resources/config/client-config.json` 是**去标识化**的客户端配置模板：`ClientUUID` 已置零，不含任何用户或机器标识。
- 所有示例路径使用占位符（`<TML_DIR>`、`<你的模组>`），不含原作者本机路径。

## 商标

Terraria 是 Re-Logic 的商标；tModLoader 是 tModLoader 团队的项目。本项目与二者无隶属关系，
仅为社区工具。
