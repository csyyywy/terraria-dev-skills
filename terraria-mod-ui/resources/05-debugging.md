# 调试方法论（UI 画不出来/位置不对）

## 核心思想：先二分"没触发" vs "画了但看不见"
80% 的 UI bug 是坐标/批次问题（画到屏幕外），20% 是钩子没触发。先证明钩子跑了，再调坐标。

## 探针三板斧

### 1. 日志探针（证明触发）
```csharp
Mod.Logger.Info($"[PROBE] hook fired: npc={npc.FullName} mode={...} pos={position}");
```
看 `tModLoader-Logs/client.log`（tail = 最新会话）。**有日志 = 钩子触发，问题在坐标；无日志 = 换钩子**。

### 2. 色块探针（证明画了 + 在哪）
```csharp
// 在绘制钩子里直接画（同批次内，不要 QueueMainThreadAction！）
Main.spriteBatch.Draw(TextureAssets.MagicPixel.Value,
    new Rectangle((int)x, (int)y, 200, 200), Color.Magenta);
```
- 品红矩形出现在屏幕某处 = 批次对、坐标对，问题在具体元素。
- 完全不出现 = 批次没激活（见崩溃陷阱）。

### 3. 定位线探针（画像/元素边界）
画半透明矩形覆盖元素区域，确认元素实际尺寸和位置（如面板高度写反成 0.54px 时立刻暴露）。

## 崩溃陷阱（实测）
- `Main.QueueMainThreadAction(() => Main.spriteBatch.Draw(...))` 在 **Update 阶段**执行，此时 spriteBatch **未 Begin** → `InvalidOperationException: Draw was called, but Begin has not yet been called` → **整个游戏崩溃**（tML 弹"看日志"）。
- 画东西必须在自己钩子的绘制批次内，或在 `ModifyInterfaceLayers` 层里（自带 Begin/End）。
- 探针代码要 try/catch 包裹，避免把崩溃带进正式版。

## client.log 定位
- 路径：`tModLoader-Logs/client.log`。
- `[Main Thread/FATAL] Main engine crash` + 堆栈 = 崩溃点，直接看堆栈里本模组命名空间的帧。
- `[WARN] 静默捕获异常` = 被 tML 吞的异常（绘制管线 try/catch），堆栈同样有用。
- 无 `[AFFIXPROBE]` 类自定义日志 = 钩子没触发。

## 反射读 tML IL（确认钩子/批次行为）
- tModLoader.dll 可用 `[Reflection.Assembly]::LoadFrom` 反射（需先加载 `Libraries\FNA\1.0.0\FNA.dll` 等依赖）。
- 例：`GameInterfaceLayer.Draw()` IL = `if(!Active) return false; Begin(UIScaleMatrix); DrawSelf(); End();` → 证实 UI 层自带批次。
- 官方 XML 文档 `tModLoader.xml` 有全部钩子签名/说明（搜方法名）。

## 版本差异警示
- tML 1.4.4 patch 与 vanilla 1.4.4 源码**可能签名错位**（如 DrawNPC 新旧签名）→ 钩子不触发。
- 对照 `<TML_SRC>/`（vanilla 反编译 + patch）确认调用链，别只信 hook 文档。
