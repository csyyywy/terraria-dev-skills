# 09. 参考资料与链接

## 官方（首选）

- **API 文档（类列表入口）**：https://docs.tmodloader.net/docs/stable/annotated.html
- **官方 Wiki（含中文页）**：https://github.com/tModLoader/tModLoader/wiki
- tModLoader GitHub：https://github.com/tModLoader/tModLoader
- Workshop 发布文档：https://github.com/tModLoader/tModLoader/wiki/Workshop
- ExampleMod 示例工程（1.4.4 分支）：https://github.com/tModLoader/tModLoader/tree/1.4.4/ExampleMod
- tModLoader.app：https://tmodloader.app

> 官方页面索引与提取要点见 `10-official-reference.md`。

## 社区

- Terraria 官方论坛 Modding 区：https://forums.terraria.org/index.php?forums/modding.79/
- tModLoader Discord（开发问答）：邀请链接见 wiki 首页
- Steam 讨论区：https://steamcommunity.com/app/1281930/discussions/

## 第三方 / 进阶

- DeepWiki 的 tModLoader 概览（结构 / 构建 / 示例导读）：https://deepwiki.com/tModLoader/tModLoader
- CalamityTeam/tml-build（社区 MSBuild 工具链）：https://github.com/CalamityTeam/tml-build
- 常用库：StructureHelper、SubworldLibrary 等（Steam 创意工坊搜索）
- 大型开源模组参考：CalamityMod、TerrariaOverhaul（GitHub）

## 路径对照

`<TML_DIR>` = tModLoader 安装目录，下表路径以 Windows 默认布局为例。

| 位置 | 典型路径 |
|---|---|
| tModLoader 安装 | `<Steam 库>\steamapps\common\tModLoader` |
| tML 用户数据（Mods / ModSources） | `%USERPROFILE%\Documents\My Games\Terraria\tModLoader` |
| tML 日志 | `<TML_DIR>\tModLoader-Logs\`；部分版本在 `%USERPROFILE%\Documents\My Games\Terraria\tModLoader\Logs\` |
| 构建用 dotnet | `dotnet`（确认 `dotnet --list-sdks` 中有 9.x） |
