---
name: terraria-mod-ui
description: tModLoader 1.4.4 原生 UI 与世界内绘制：绘制批次与坐标系、StyleDimension 参数顺序、绘制钩子选型（PostDraw 在 1.4.4 不触发）、角色画像渲染、血条与头顶标签、UIList 排序、探针调试。
whenToUse: 写或改模组 UI（面板 / 窗口 / 画像 / 血条标签 / 世界内叠加），或排查"画了看不见 / 位置不对 / 钩子不触发"时加载。
---

# tModLoader UI 开发与调试（1.4.4）

环境：Terraria 1.4.4 + tModLoader 1.4.4 stable。查绘制链路前先看源码（`<TML_SRC>` = tModLoader 源码检出目录，含反编译 vanilla 与 1.4.4 patch）。

> **默认方案：tModLoader 原生 UI。**
> 本技能不依赖任何 UI 框架。只有当用户**明确点名 SilkyUI**，或项目已引用该框架时，
> 才启用可选包：`pwsh -File tools/skill-pack.ps1 -Name silky-ui-framework -Enable`
> （默认收在 `skills/optional/`，不进入技能目录，不会被自动选中）。

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

- `resources/07-draw-resources.md`：绘制资源与画布四条铁律（A/B/C 实测、两遍画、clamp、bbox、视角夹取）
