# 绘制钩子选型（tModLoader 1.4.4）
## 三大坑：先验证触发，再调坐标
### 1. `GlobalNPC.PostDraw` —— 1.4.4 大概率不触发
- tML 1.4.4 patch 把 `PostDraw` 插在 `Main.DrawNPC(int iNPCIndex, bool)`（旧签名）里，而 vanilla 的 `DrawNPCs` 实际调用 `DrawNPC(NPC npc, bool)` → `DrawNPCDirect(...)`（新签名）→ 钩子从未被调用，改坐标无效。
- 第三方模组（如 ImproveGame）会 ILHook `Main` 绘制方法，进一步干扰。
### 2. `GlobalNPC.DrawHealthBar` —— 血条附属绘制的正解
- 签名：`bool? DrawHealthBar(NPC npc, byte hbPosition, ref float scale, ref Vector2 position)`。
- 画血条时必然触发（tML patch 在 `DrawInterface_14_EntityHealthBars` 里调 `NPCLoader.DrawHealthBar`）；血条隐藏则不画。
- `position` = 血条中心 X / 顶部 Y 的世界坐标；`scale` 与血条缩放一致（Boss 1.5f）。
- 返回 `null` 保留原版血条，`false` 跳过血条，`true` 用自定 position 画。
- 画在血条下方：`y = position.Y - Main.screenPosition.Y + 36f*scale + offset`（血条高 36px）。天然跟随血条开合，适合附注标签与稀有度标记。
### 3. `ModifyInterfaceLayers` —— 世界内叠加的通用正解
- `ModSystem.ModifyInterfaceLayers(List<GameInterfaceLayer> layers)` 每帧调用，插入 `LegacyGameInterfaceLayer`；层绘制方法自带 `Begin(UIScaleMatrix)` → DrawSelf → End（IL 证实），直接拿 `Main.spriteBatch` 画屏幕坐标。
- 插在 `"Vanilla: Entity Health Bars"` 之后覆盖血条，`"Vanilla: Mouse Text"` 附近覆盖名字。
- 每帧遍历 `Main.npc[]` 自绘，适合"给所有带 X 的实体加标签"。
## 其他钩子速查

| 钩子 | 触发 | 用途 |
|---|---|---|
| `DrawEffects(ref Color drawColor)` | 每帧（tML patch 在 DrawNPC 里调） | 染色（精英紫 / Boss 金） |
| `ModifyTypeName(ref string typeName)` | 名字显示时 | 改名字（前缀等） |
| `PreDraw` | 每帧 | 替换/跳过实体绘制 |
| `PostDraw` | 1.4.4 不可靠 | 实体后叠加改用 UI 层 |

## 判断钩子是否触发的探针
日志探针与色块探针见 05-debugging.md：有探针日志 = 钩子已触发，查坐标与批次；无日志 = 换钩子。
