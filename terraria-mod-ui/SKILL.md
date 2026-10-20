---
name: terraria-mod-ui
description: Terraria（泰拉瑞亚）tModLoader 1.4.4 UI 开发与调试经验：绘制批次与坐标系（UIScaleMatrix / Main.Transform / screenPosition）、StyleDimension 参数陷阱、绘制钩子选型（PostDraw 在 1.4.4 不触发的坑）、角色画像渲染（spriteBuffer / SerializedClone）、血条与头顶标签跟随绘制、UIList 排序、调试探针方法论。
whenToUse: 开发或修改 tModLoader 模组 UI（面板 / 窗口 / 画像 / 血条标签 / 头顶文字 / 世界内绘制），或排查"画了看不见 / 位置不对 / 钩子不触发"类问题时加载。
---

# tModLoader UI 开发与调试（1.4.4）

> 经验来自实战模组（属性面板、词缀血条标签、画像渲染），均经过"踩坑 → 定位 → 修复"验证。

环境：Terraria 1.4.4 + tModLoader 1.4.4 stable。查绘制链路前先看源码（`<TML_SRC>` = tModLoader 源码检出目录，含反编译 vanilla 与 1.4.4 patch）。

## 一句话流程

判断绘制对象类型（UI 面板 / 世界内叠加 / 血条附属）→ 选钩子与批次 → 换算坐标（世界坐标画进 UI 批次必须减 `screenPosition`）→ 编译 → 游戏内 Reload → 探针验证。

## 三条易错点

1. **坐标先问批次**：UI 批次（`UIScaleMatrix`）里画世界坐标必须 `- Main.screenPosition`；世界批次（`Main.Transform`）里反而不能减。两套批次不能混用。
2. **`StyleDimension(px, pct)` 第一个参数是像素、第二个是百分比**，写反会得到"元素存在但什么都画不出"的幽灵 bug（例如面板高度 0.54 像素）。
3. **1.4.4 的 `GlobalNPC.PostDraw` 大概率不触发**：tML 的 patch 挂在旧签名 `DrawNPC(int, bool)` 上，而 vanilla 走 `DrawNPC(NPC, bool) → DrawNPCDirect`。画世界内叠加优先用 `ModifyInterfaceLayers` 插层或 `DrawHealthBar`；不确定就加探针验证，别假设。

## 分册索引

- `01-coordinates-batches.md` 坐标系与绘制批次——UI 批次/世界批次矩阵、`screenPosition` 减法、`UIScaleMatrix` 缩放。UI 位置问题的根源。
- `02-drawing-hooks.md` 绘制钩子选型——`ModifyInterfaceLayers` / `DrawHealthBar` / `PostDraw`（1.4.4 不触发）/ `DrawEffects` / `PreDraw`。
- `03-portrait-rendering.md` 角色画像渲染——`spriteBuffer` 直绘绕过 UI 批次、`DrawPlayer_RenderAllLayersSlow`、`SerializedClone` vs `clientClone`、`CurrentPlayerOverride`。
- `04-layout-pitfalls.md` 布局与控件坑——`StyleDimension` 参数顺序、`UIList` 乱序、`UIImage` 图标居中、缩放与像素对齐。
- `05-debugging.md` 调试方法论——探针（日志 + 色块）区分"没触发"与"位置错"、`client.log` 定位、反射读 tML IL、崩溃恢复。
- `06-text-labels.md` UI 文字与血条标签细节——描边文字、逐段配色、血条跟随定位、多行换行、每帧遍历 NPC。
