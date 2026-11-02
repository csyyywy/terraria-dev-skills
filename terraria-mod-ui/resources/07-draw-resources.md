# 07. 绘制资源与画布：四条铁律 + 一张对照表

模组 UI 里"数据都对、就是看不见"，绝大多数不是玄学，而是下面四类之一。
本页所有结论都来自无头测试的截图 + `assertpix` 同帧取色，不是推测。

## 7.1 贴图能不能画：先分清四种失败原因

实测对照（同一帧、同一 SpriteBatch、同一 `Main.UIScaleMatrix`、都请求 `Main.instance.LoadItem`）：

| 组 | 贴图 | 结果 |
|---|---|---|
| A | `TextureAssets.Item[ItemID.Heart]` | **能画**（`assertpix` 取到 `f71318`，标准心形贴图） |
| B | `TextureAssets.MagicPixel` | 能画（`ffffff`） |
| C | `TextureAssets.InventoryBack9` | 能画（`3f5297`） |

所以**"物品贴图在模组 UI 里画不出来"是误判**。真正常见的四种失败：

| 现象 | 真因 | 处理 |
|---|---|---|
| 一片空白，日志里 `tex=null` | 资源没加载：`Asset<T>.Value` 在未请求时可能是 null | `Main.instance.LoadItem(id)` / `ModContent.Request<Texture2D>(path, AssetRequestMode.ImmediateLoad)` |
| 有图但只有几个像素 | 目标矩形被缩放算成 0 或个位数 | 见 7.3 的 clamp |
| 图标被方块盖住 | 画序：后画的把先画的盖了 | 见 7.2 两遍法 |
| 整块区域什么都没画 | SpriteBatch 状态/矩阵不匹配（`sb.End()` 时机、用了世界矩阵） | UI 一律 `Main.UIScaleMatrix`；自己起 Begin 时成对 End |

**装饰用自有贴图**仍然是更省事的选择（不受图集、加载时机影响）：

```csharp
var tex = ModContent.Request<Texture2D>("YourMod/Assets/UI/icon", AssetRequestMode.ImmediateLoad).Value;
```

需要"物品外观"时优先走 `ItemSlot.Draw` / 原版物品栏路径，而不是自己 `sb.Draw` 拼。

**30 秒自证**（不用人眼看图）：

```
c:texprobe                      # 打开探针：同帧画 A/B/C 三块
c:wait 10
c:assertpix 110 110 #ff0000 60  # A：心形
c:assertpix 210 110 #ffffff 20  # B：MagicPixel
c:assertpix 310 110 #3f5297 90  # C：原版 UI 贴图
c:shot probe
```

三条都 PASS 说明"画得出来"，问题在别处（画序、尺寸、布局）；某条 FAIL 就把那一路单独排查。

## 7.2 铁律一：密集画布分两遍画

节点/格子一多，后画的底板会把先画的图标盖掉——用户看到的是"大格子没图标"。

```csharp
// 第一遍：底、框、连线
foreach (var n in nodes) DrawFrame(sb, n);
// 第二遍：图标、色点、选中描边
foreach (var n in nodes) DrawIcon(sb, n);
```

## 7.3 铁律二：低缩放不能"跟着变小"，要 clamp + 描边

0.25 缩放下图标只剩几个像素，肉眼等于空格子。

```csharp
float side = MathHelper.Clamp(Math.Min(nodeW, nodeH) * 0.7f, 10f, 30f);
DrawIcon(sb, tex, center, side);
if (zoom < 0.5f) DrawOutline(sb, nodeRect, areaColor);   // 任何缩放都保留可辨标记
if (zoom < 6f)   DrawDot(sb, center, areaColor);         // 极小缩放退化为实心点
```

## 7.4 铁律三：fit 用内容包围盒，不要用画布常量

用 `CanvasW/H` 算缩放，树一大就算出 0.75，整棵被裁到只剩根节点。

```csharp
Rectangle bbox = ContentBounds();                 // 遍历节点求
float zx = (viewport.Width  - 40f) / Math.Max(1, bbox.Width);
float zy = (viewport.Height - 40f) / Math.Max(1, bbox.Height);
zoom = MathHelper.Clamp(Math.Min(zx, zy), MinZoom, MaxZoom);
pan  = viewport.Center() - (bbox.Center.ToVector2() * zoom);
```

视口尺寸变化 > 8px 时重新 fit，否则窗口一改就错位。

## 7.5 铁律四：恢复上次视角要夹范围

`AutoFit = !restored` 这种写法，在老存档里存着 0.75 缩放 + 旧 pan 时，打开就是"界面空了"。

```csharp
zoom = MathHelper.Clamp(savedZoom, fitZoom * 0.5f, fitZoom * 4f);
pan  = ClampPan(savedPan);
if (DateTime.UtcNow - savedAt > TimeSpan.FromDays(30) || canvasChanged) Fit();
```

## 7.6 排查顺序（省时间的那个顺序）

1. `assertpix` 取色 → 判断"有没有画出来"；
2. 结构化日志打数量/尺寸（`count=5 nonAir=59 filter=True`、`icon w=22 h=22`）；
3. `shot` 区域截图（`c:shot crop 100 100 200 120`）看局部；
4. 最后才怀疑布局：和"能正常显示的同类页面"做 diff（宽度、fit 基准、父容器 Dimension）。

跨帧比对不可靠：日志若来自开页第一帧、截图在 60 tick 后，fit/动画已经改了布局。
`shot` 会额外打印 `shotframe … rect=… mouse=…`，用同一帧的坐标去裁。
