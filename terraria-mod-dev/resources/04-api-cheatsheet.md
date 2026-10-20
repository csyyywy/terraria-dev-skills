# 04. tModLoader API 速查（总索引）

> 签名与版本差异以官方文档为准：https://docs.tmodloader.net/docs/stable/ 。以下按 tML 1.4.4 / 2026.06 核对。
> 本页只做导读与章节映射（§4.x 编号全库通用，其它分册引用"§4.13"时按下表定位）。路径：`<TML_DIR>` = tModLoader 安装目录，`<TML_SRC>` = tModLoader 源码 / ExampleMod 检出目录。

## 通用原则

**⚠️ 能复用已验证源码，就别自己写新逻辑。** 优先照抄官方 ExampleMod（如 `<TML_SRC>\ExampleMod\Content\Items\Tools\ExampleHook.cs`），只改数值、贴图、命名空间，不重造结构。

- 行为异常时，先与对应 Example 逐行 diff 找结构性差异，而不是在自写代码上打补丁。
- 自写逻辑最容易埋"无异常日志"的故障（钩爪链条死循环就是此类，见 `04f` §4.19）。确无现成实现才自写，且必须圈定范围：迭代上限、空引用、越界、NaN 全部防御。

## 子分册映射

| 文件 | 覆盖章节 | 主题 |
|---|---|---|
| `04a-content-types.md` | §4.1–4.6 | 类型获取 / ModItem / ModNPC / ModProjectile / ModTile / ModBuff |
| `04b-systems-globals-recipe.md` | §4.7–4.10 | ModSystem（含世界持久化）/ ModPlayer / Global* / 合成配方 |
| `04c-ids-damageclass-helpers.md` | §4.11–4.14 | ID 枚举 / DamageClass / 常用辅助（QuickSpawnItem 双重载、armor 槽位表）/ 终局 ID 对照 |
| `04d-autoload-town-npc.md` | §4.15–4.16 | 贴图自动加载规则 / 城镇 NPC 全流程 |
| `04e-pitfalls-weapons-armor.md` | §4.17–4.18、§4.20–4.21 | 实战踩坑：鞭子 / OnHit 减益 / 段身虫 / AoE / 护甲套装 / 弹药与 Shoot / Boss 朝向与 AI 骨架 |
| `04f-drawing-furniture-grapple.md` | §4.19 | 实战踩坑：手持绘制 / 箱子家具贴图帧 / 钩爪死循环 / 贴图白边 |
