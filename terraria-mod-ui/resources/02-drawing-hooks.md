# 绘制钩子选型（1.4.4 实战）

## 三大坑：先验证触发，再调坐标

### 1. `GlobalNPC.PostDraw` —— 1.4.4 大概率不触发 ❌
- tML 1.4.4 patch 把 `PostDraw` 插在 `Main.DrawNPC(int iNPCIndex, bool)`（**旧签名**）里。
- vanilla 1.4.4 的 `DrawNPCs` 实际调用 `DrawNPC(NPC npc, bool)` → `DrawNPCDirect(...)`（**新签名**）。
- **结果：钩子从未被调用**，代码怎么改坐标都没用。实测踩坑两次才定位。
- 另有第三方模组（如 ImproveGame）会 ILHook `Main` 绘制方法，进一步干扰。

### 2. `GlobalNPC.DrawHealthBar` —— 血条附属绘制的正解 ✅
- 签名：`bool? DrawHealthBar(NPC npc, byte hbPosition, ref float scale, ref Vector2 position)`。
- 血条绘制时必然触发（tML patch 在 `DrawInterface_14_EntityHealthBars` 里调用 `NPCLoader.DrawHealthBar`）。
- `position` 是**血条中心 X / 顶部 Y 的世界坐标**；`scale` 与血条缩放一致（Boss 1.5f）。
- 返回 `null` = 保留原版血条；`false` = 跳过血条；`true` = 用自定 position 画。
- 画在血条下方：`y = position.Y - Main.screenPosition.Y + 36f*scale + offset`（血条高 36px）。
- **天然跟随血条**：血条出现才画、血条隐藏不画——适合词缀标签/稀有度标记。

### 3. `ModifyInterfaceLayers` —— 世界内叠加的通用正解 ✅
- `ModSystem.ModifyInterfaceLayers(List<GameInterfaceLayer> layers)` 每帧调用，插 `LegacyGameInterfaceLayer`。
- 层绘制方法执行时**自带 `Begin(UIScaleMatrix)` → DrawSelf → End**（反射 IL 证实），直接用 `Main.spriteBatch` 画屏幕坐标即可。
- 插在 `"Vanilla: Entity Health Bars"` 之后 = 覆盖血条；`"Vanilla: Mouse Text"` 附近 = 覆盖名字。
- 每帧遍历 `Main.npc[]` 自己画，适合"给所有带 X 的实体加标签"。

## 其他钩子速查

| 钩子 | 触发 | 用途 |
|---|---|---|
| `DrawEffects(ref Color drawColor)` | 每帧（tML patch 在 DrawNPC 里调） | 染色（精英紫/Boss 金） |
| `ModifyTypeName(ref string typeName)` | 名字显示时 | 改名字（前缀等） |
| `PreDraw` | 每帧 | 替换/跳过实体绘制 |
| `PostDraw` | **1.4.4 不可靠** | 实体后叠加——改用 UI 层 |

## 判断钩子是否触发的探针

```csharp
// 钩子内（避免每帧刷屏，加个节流或只在词缀怪时打）
Mod.Logger.Info($"[PROBE] hook fired: npc={npc.FullName} mode={...}");
```
日志在 `tModLoader-Logs/client.log`。看到日志 = 触发了，问题在坐标/批次；看不到 = 钩子没触发，换钩子。
