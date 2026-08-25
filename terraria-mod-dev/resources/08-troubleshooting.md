# 08. 常见错误与排错

> 通用排查顺序：**先看日志** `...\tModLoader\Logs\client.log`（或 server.log / Launch.log），报错一般有堆栈与模组名；再对号入座。

## 8.1 构建/环境类

| 症状 | 原因 | 修复 |
|---|---|---|
| `No .NET SDKs were found` / 游戏内 ".NET SDK not recognised" | `dotnet` 解析到无 SDK 副本（本机 `C:\Program Files\dotnet`） | 用 `%USERPROFILE%\.dotnet\dotnet.exe` 或调 PATH（见 01） |
| `NETSDK1013: TargetFramework 值为空` | csproj 相对导入 `..\tModLoader.targets` 在 junction 工作区解析失败 | 用绝对路径导入 tMLMod.targets（见 02、templates） |
| `error MSB4019`（找不到导入的 targets） | targets 路径错 | 确认 tML 已安装且路径正确；先让 tML 构建一次生成包装文件 |
| 编译报错是**原版/旧版 API**（如 `Item.useTime` 不存在） | 版本对不上 / 用到 1.4.5 preview 或旧教程 API | 对照 docs.tmodloader.net/docs/stable 的 1.4.4 签名 |
| 构建成功但 .tmod 没更新 | 游戏正在运行锁文件 | 先退出 tML 再构建 |
| `NuGet.targets(745,5): error : Value cannot be null. (Parameter 'path1')`（restore 失败） | 受限 shell 环境剥离了 Windows 特殊目录环境变量（`PROGRAMFILES(X86)`/`PROGRAMDATA`/`APPDATA` 等），NuGet 拼机器级配置路径时 path1 为 null；restore 缓存一旦失效（如 `--force`）就会暴露 | 构建前补齐这些环境变量（见 scripts/build.ps1 顶部），再 restore + build。勿用 `--force` 无谓失效缓存 |

## 8.2 加载/运行类（进游戏或 Reload 红字）

| 症状 | 原因 | 修复 |
|---|---|---|
| `Missing localization key: Mods.MyMod.ItemName.X` | 新内容没写 hjson 键 | 补 `Localization/en-US.hjson`（+zh-Hans）；新版报错为作用域键名（如 `Items.X.DisplayName`），键名=类名（见 05 §5.7） |
| `Missing ModItem.X` / 类未找到 | 类没继承正确基类 / 命名空间/类名与文件不符 | 确认 `: ModItem/ModNPC/...`，类名唯一 |
| `Exception: System.TypeLoadException` | 引用了不存在/改名的 API | 查 API 文档核对签名；必要时 tModPorter |
| Reload 后旧数值残留 | `Unload()` 没清静态字段 | 在 `Mod.Unload()` 里把静态引用置 null、计数器归零 |
| 贴图花屏/错位 | 图片尺寸/命名与类不符；**装备贴图（_Head/_Body/_Legs）按物品图标规格做** | 文件名=类名；tile 尺寸见 02.5；**装备贴图尺寸见 11-armor-textures.md**（40x1120/360x224） |
| `MissingResourceException: 未找到预期的资源 Content/Items/X` | 内容类缺同名贴图 | 放 `Content/Items/X.png`（占位纯色即可），见 02 |
| `MissingResourceException: 未找到预期的资源 Content/Tiles/X_Highlight` | tile 设了 `TileID.Sets.HasOutlines[Type]=true` 但缺 `_Highlight` 轮廓贴图（**客户端专属要求，无头服务器测不出**） | 生成同尺寸白色轮廓 `X_Highlight.png`；或用真机 Reload 验证 |
| `RecipeException: A Recipe can only be created inside recipe related methods` | 在 Load()/Update 等非配方方法里调用了 Recipe.Create | 把配方移到 `ModItem.AddRecipes()` / `ModSystem.AddRecipes()` / `GlobalItem.AddRecipes()` |
| `icon.png` 报错 | 图标格式/尺寸不对 | 80×80 PNG（非该尺寸拒载）；本地加载缺省回落占位图，发布工坊必须非默认图标 |
| 模组没出现在 Mods 列表 | 没放进 ModSources / junction 断了 / 没启用 | 检查 `ModSources\MyMod` junction；Mods 菜单启用 |
| 游戏内点构建卡住 | tML 在等 SDK / 锁文件 | 用命令行构建定位错误，再 Reload |

## 8.3 逻辑/行为类

| 症状 | 原因 | 修复 |
|---|---|---|
| 武器没有伤害 | 忘设 `Item.damage` / `DamageType` / `useStyle` | 对照 04.2 |
| 弹幕不飞/穿透异常 | `Projectile.aiStyle` 与手写 AI 混用 / `friendly` 未设 | 二选一；设 `friendly=true` |
| 物品不能合成 | `AddTile` 站没建 / 材料 ID 错 | 检查 Recipe 条件；用原版材料先验证 |
| NPC 不生成 | 没写生成条件（SpawnChance/OnSpawn/手动生成） | 加生成逻辑或手动 `NPC.NewNPC` |
| 只有主机看到效果 | 网络同步缺失 | 见 06；事件走 ModPacket，世界数据走 NetSend |
| 加载报 `Duplicate`（类型冲突） | 命名空间/类名与其它模组撞 | 模组名+命名空间尽量唯一 |

## 8.4 排查工具

```powershell
# 看最新日志尾部
Get-Content "...\tModLoader\Logs\client.log" -Tail 80

# 验证 .tmod 产物与启用状态
Get-Item "...\tModLoader\Mods\MyMod.tmod" | Select-Object Length, LastWriteTime
Get-Content "...\tModLoader\Mods\enabled.json"

# 验证 junction
cmd /c dir "...\tModLoader\ModSources"
```

## 8.5 求助渠道

- tML 官方论坛、Discord、Steam 讨论区（见 09）。
- 提问带上：tML 版本、`client.log` 尾部、最小复现代码。

## 8.6 发布/贴图轮新增排错（2026-08 实测）

| 症状 | 原因 | 修复 |
|---|---|---|
| 盔甲穿戴错位/花屏 | 装备贴图（_Head/_Body/_Legs）被按物品图标尺寸生成，不是帧规格 | 见 `11-armor-textures.md` + Voidfall/tools/fix-armor-textures.ps1 |
| 发布/ModSources 构建报 CS0246（List<>/Math 找不到）但本地 build 过 | tML 发布构建不应用 csproj ImplicitUsings | 显式 using 或 GlobalUsings.cs；本地用 `-p:ImplicitUsings=disable` 验证（见 03） |
| 打包报 TML003/文件锁 | tML 客户端或残留 server 占用 .tmod | 区分进程：`-terrariasteamclient`=客户端别杀；裸 tModLoader.dll=残留 server 可杀；退出后再打包（见 03） |
| PowerShell 跑 .ps1 报 "term 'X' is not recognized" 但函数已定义 | .ps1 是 UTF-8 无 BOM + 中文注释，Windows PowerShell 5.1 按 ANSI 解析把函数定义弄坏 | .ps1 注释全用 ASCII 或存 UTF-8 BOM |
| 文件被截断成已读行数 | 对整文件 limit 读取后整写覆盖 | 先 git checkout 恢复；大文件用精确 edit（old_string 唯一）勿整写 |