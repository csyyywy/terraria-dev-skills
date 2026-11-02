# 03. 动词表

未知动词一律拒绝并列出可用项——这条路故意不提供"反射调用任意方法"。

## 读取

| 命令 | 说明 |
|---|---|
| `ping` | 回一行 `pong tick=… side=… net=… world=…` |
| `diag` | 写 `out/diag-<side>.txt`：side / net / world / tick / 时间 / 玩家数 / NPC / 物品 / 弹幕 / hasClients |
| `tick` | 当前帧号 |
| `state` | 本侧玩家一行 key=value：hp、defense、immune、noKnockback、dead、pos、当前配置 |
| `count npc\|item\|proj\|player` | 计数 |
| `find npc\|item [type]` | 逐条列出槽位、类型、坐标、生命或堆叠 |
| `tile <x> <y>` | 单格 tile / wall / 液体 |

## 世界与对象

| 命令 | 说明 |
|---|---|
| `spawn <npcId> <n>` | 在玩家（或出生点）上方生成 |
| `give <itemId> <n>` | 需要本侧有玩家 |
| `tp <tileX> <tileY>` | 传送本侧玩家 |
| `time <day\|noon\|night\|midnight>` | 设置时间 |
| `weather <rain\|clear>` | 设置天气 |
| `save` | `WorldFile.SaveWorld()` |

## 界面与输入

| 命令 | 说明 |
|---|---|
| `ui <名字>` | 调用模组注册的打开器；内置 `inventory`（开背包）与 `close` |
| `key <触发器名>` | **进程内注入**（写 `PlayerInput.Triggers.JustPressed`），不依赖窗口焦点：最小化、无人值守都能用。常见触发器 `Inventory / Map / Chat / MouseLeft / Grapple / QuickMount`，模组键位写 `<Mod>/<Bind>` |
| `key vk:<键>` | Win32 `keybd_event`，只有窗口在前台时有效，仅作兜底 |
| `mouse <x> <y>` | 移动光标：直接改 `Main.mouseX/mouseY`（`MouseScreen` 同帧生效，UI 命中测试看的就是它） |
| `click [left\|right] [x y]` | 点击：先移到坐标再按下/抬起（保持 2 帧），走 `PlayerInput.Triggers.Mouse*`，与真鼠标等价 |
| `wheel <delta>` | 滚轮：写 `PlayerInput.ScrollWheelValue` 与 `ScrollWheelDeltaForUI`（正=上滚）。**只对读这两者的 UI 有效**，自绘 UI 用 `uiact` |
| `shot <名字> [x y w h]` | 截图；给 4 个整数就只拍该区域（屏幕坐标）。同帧打印 `shotframe … rect=… mouse=…` |
| `assertpix <x> <y> <#rrggbb> [tol]` | **同帧**读后缓冲取色断言，产出 `[TEST] assertpix PASS|FAIL got=… want=… d=…` |
| `uiact <名字> [参数...]` | 调模组注册的 UI 动作（`RegisterUiAction`）。**自绘 UI 只能走这条**——它们读 `Mouse.GetState()`，注入无效 |
| `mute [on\|off]` | 静音：`soundVolume`/`musicVolume` 归零；默认由驱动用 `TMLKIT_MUTE=1` 打开 |
| `link on\|off` | 假连接开关。**L2 必须 `link off`**：假连接占着槽位时真客户端会被挤掉。驱动在 `-Client` 时自动下发 |

`ui` 的打开器与自定义动词都由模组注册，技能不需要知道界面结构：

```csharp
DevBridge.RegisterUi("gems", () => TalentTree.Open());
DevBridge.RegisterVerb("grid", args => $"count={InventoryGrid.Count}");
```

未知名字会被拒绝并列出已注册项：

```
ui REFUSED: 'nope' not registered; mod: demo; builtin: inventory, close
key REFUSED: no window on a dedicated server (use L2 / -Client)
```

## 测试角色（L2）

| 命令 | 说明 |
|---|---|
| `god <on\|off>` | 伤害整个取消（`ModifyHurt → Cancel()`） |
| `kb <on\|off>` | 免疫击退 |
| `lockhp <n\|off>` | 每帧把血钳到 n，`PreKill` 兜底不死 |
| `keepalive <on\|off>` | 受伤流程照跑，事后还原血量 |
| `hp <n>` / `hpmax <n>` / `defense <n>` | 改当前血 / 上限 / 防御 |
| `hurt <n> [dir]` | 主动造成伤害，走完整受伤流程 |
| `immune <frames>` / `buff <id> <秒>` / `clearbuffs` | 无敌帧与增益 |
| `playerreset` | 清空以上配置 |

受伤记录写入 `out/hurt-<side>.txt`：

```
kind=blocked        dmg=0   hp=60->60     # god 拦下
kind=applied        dmg=5   hp=25->20     # 正常受伤
kind=lethal-blocked dmg=999 hp=25->25     # 致命伤害被 PreKill 拦住
```

**注意**：`hurt` 受无敌帧限制。两次之间要 `wait`（60fps 下 90–120 帧），否则 `Player.Hurt`
直接返回 0，钩子一个都不进。

## 时间单位（容易误读）

`wait 20` = **20 tick**（60 tick/s，约 0.33 秒），不是 20 秒。

| 写法 | 含义 |
|---|---|
| `wait 60` | 60 tick ≈ 1 秒 |
| `wait 20t` | 同上，显式 tick |
| `wait 1s` | 1 秒 = 60 tick（支持小数：`wait 0.5s`） |

## 断言

| 命令 | 产出 |
|---|---|
| `assert hp>=60` | `[TEST] assert_hpgte60 PASS hp=100 期望 >= 60` |
| `assert npc<=3` | `[TEST] assert_npclte3 …` |
| `assert inventory==true` | `[TEST] assert_inventoryeq1 …` |
| `assert players>=1` / `defense>0` / `hpmax>=20` | 同理 |
| `check hp>=40` | `[TEST] check_hpgte40 …`（等价写法，历史命名） |

运算：`>=` `<=` `==` `!=` `>` `<`；字段：`hp` `hpmax` `defense` `npc` `players` `inventory`。
值可写数字或 `true`/`false`（布尔按 1/0 比）。

`state` 现在带 `mouse=x,y` `menu=<menuMode>` `vol=<音量>` `npc=<存活数>` `players=<在线数>`，
点完界面不用截图也能判断是否生效。
