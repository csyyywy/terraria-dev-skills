# 04. tModLoader API 速查（总索引）

> 完整签名与版本差异以官方 API 文档为准：https://docs.tmodloader.net/docs/stable/ 。以下内容按 1.4.4 / 2026.06 验证。
> 本分册已**拆分为多个小文件**，本页只做导读与章节映射；各 §4.x 编号全库通用，其它分册引用"04.2""§4.13"时按下表定位即可。

## 通用原则（先读，适用于所有子分册）

**⚠️ 最重要原则：能复用已验证源码就复用，别自己写新逻辑！**
- **优先照抄 tML 官方 ExampleMod 示例**（ExampleHook / ExampleChest / ExampleStaff …）与已验证实现，只改数值、贴图、命名空间，不重造结构。tML 示例是久经实战验证的，照抄 = 免费得到正确性。
- **血泪教训（归墟钩爪）**：自写钩爪链条画法 + 50px 高链条贴图（官方 ExampleHook 链条是 14px 小环），50px 步长在钩爪头距玩家 20~50px 时来回过冲 → **死循环卡死**，反复多轮"闪退/卡死/崩溃"排查后才定位；最后回到 ExampleHook 已验证逻辑 + 单次拉伸绘制链条，才稳定。
- **排查路线**：遇到"我抄/自写的代码行为异常"时，先对照官方 ExampleMod 逐行 diff（ExampleHook 在 `<TML_SRC>\ExampleMod\Content\Items\Tools\ExampleHook.cs`），找出每一处结构性差异，而不是在自写代码里打补丁。
- **通用法则**：① 先查 tML 示例有没有现成实现（`<TML_SRC>\ExampleMod\`）；② 有就照抄 + 微调参数/贴图；③ 只有确实没有现成实现时才自写，并给自写部分留最小范围 + 绝对防御（迭代上限、空引用、越界、NaN）。

## 子分册映射

| 文件 | 覆盖章节 | 主题 |
|---|---|---|
| `04a-content-types.md` | §4.1–4.6 | 类型获取 / ModItem / ModNPC / ModProjectile / ModTile / ModBuff |
| `04b-systems-globals-recipe.md` | §4.7–4.10 | ModSystem（含世界持久化）/ ModPlayer / Global* / 合成配方 |
| `04c-ids-damageclass-helpers.md` | §4.11–4.14 | ID 枚举 / DamageClass / 常用辅助（含 QuickSpawnItem 双重载、armor 槽位表）/ 终局 ID 对照 |
| `04d-autoload-town-npc.md` | §4.15–4.16 | 贴图自动加载规则 / 城镇 NPC 全流程 |
| `04e-pitfalls-weapons-armor.md` | §4.17–4.18 | 实战踩坑：鞭子/OnHit 减益/段身虫/AoE/护甲套装/弹药与 Shoot |
| `04f-drawing-furniture-grapple.md` | §4.19 | 实战踩坑：手持绘制 / 箱子家具贴图帧 / 钩爪死循环 / 贴图白边 |
