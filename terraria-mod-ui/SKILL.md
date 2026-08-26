---
name: terraria-mod-ui
description: Terraria（泰拉瑞亚）tModLoader 1.4.4 UI 开发与调试实战经验：绘制批次与坐标系（UIScaleMatrix/Main.Transform/screenPosition）、StyleDimension 参数陷阱、绘制钩子选型（PostDraw 1.4.4 不触发的坑）、角色画像渲染（spriteBuffer/SerializedClone）、血条/头顶标签跟随绘制、UIList 排序、调试探针方法论。
whenToUse: 开发或修改 tModLoader 模组的 UI（面板/窗口/画像/血条标签/头顶文字/世界内绘制），或排查"画了但看不见/位置不对/不触发"类问题时加载。
---

# Terraria tModLoader UI 开发与调试（1.4.4 实战经验）

> 全部经验来自实战模组项目（角色属性面板、敌人词缀血条标签、画像渲染），踩坑-定位-修复闭环后沉淀。

环境基线：Terraria 1.4.4 + tModLoader 1.4.4 stable（2026.06）+ .NET 8 SDK。
源码对照：`<TML_SRC>/`（vanilla 反编译 + tML 1.4.4 patch），**查绘制链路前先看这里**。

## 先读（按需）

- `resources/01-coordinates-batches.md`：**坐标系与绘制批次**——UI 批次/世界批次矩阵、screenPosition 减法、UIScaleMatrix 缩放。UI 一切位置问题的根源。
- `resources/02-drawing-hooks.md`：**绘制钩子选型**——ModifyInterfaceLayers / DrawHealthBar / PostDraw（1.4.4 大坑：不触发）/ DrawEffects / PreDraw。画"跟血条走"的东西用哪个钩子。
- `resources/03-portrait-rendering.md`：**角色画像渲染**——spriteBuffer 直绘绕过 UI 批次、DrawPlayer_RenderAllLayersSlow 逃生口、SerializedClone vs clientClone、CurrentPlayerOverride。
- `resources/04-layout-pitfalls.md`：**布局与控件坑**——StyleDimension 参数顺序、UIList 乱序、UIImage 图标居中、缩放与像素对齐。
- `resources/05-debugging.md`：**调试方法论**——探针（日志+色块）区分"没触发"vs"位置错"、client.log 定位、反射读 tML IL、崩溃恢复。
- `resources/06-text-labels.md`：**UI 文字与血条标签细节**——描边文字、逐段配色、血条跟随定位、多行换行、每帧遍历 NPC。

## 一句话流程

确定要画的东西属于哪类（UI 面板 / 世界内叠加 / 血条附属）→ 选对钩子与批次 → 坐标换算（世界坐标画进 UI 批次必须减 screenPosition）→ 编译（BuildMod=false 可游戏开着编）→ 游戏内 Reload → 探针验证 → 提交。

## 三条高频铁律

1. **坐标永远先问批次**：UI 批次（UIScaleMatrix）里画世界坐标必须 `- Main.screenPosition`；世界批次（Main.Transform）里画屏幕坐标反而错。两套批次不能混。
2. **`StyleDimension(px, pct)` 第一个参数是像素、第二个是百分比**——写反 = 面板高度 0.54 像素这种幽灵 bug（元素还在但什么都画不出）。
3. **1.4.4 的 `GlobalNPC.PostDraw` 大概率不触发**（tML patch 挂在旧签名 DrawNPC(int,bool)，vanilla 走 DrawNPC(NPC,bool)→DrawNPCDirect）。画世界内叠加优先用 `ModifyInterfaceLayers` 插层或 `DrawHealthBar` 钩子；不确定就加探针验证，别假设。
