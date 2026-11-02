# 04. L2：客户端接入

## 命令

```
服务端：dotnet tModLoader.dll -server -config <lab>\serverconfig.txt
        -tmlsavedirectory <lab>\saves -modpath <lab>\mods
客户端：dotnet tModLoader.dll -join 127.0.0.1 -port <port> -player <角色名> -skipselect
        -tmlsavedirectory <lab>\saves
```

## 四个必须踩对的点

1. **客户端不认 `-modpath`。** 该参数只在服务端的 `LaunchInitializer.LoadServerParameters` 中解析；
   客户端永远从 `<存档目录>\Mods` 加载。所以要把 `.tmod` 和 `enabled.json` 复制到
   `<lab>/saves/Mods/`，否则日志里只有一句 `Did not find enabled.json file`，模组零加载，
   看起来就像"卡在加载模组"。

2. **不要给子进程接 stdout/stderr 管道。** 没人读的管道写满（4KB）后，主线程会停在
   `log4net → ConsolePal.WindowsConsoleStream.Write`。用文件重定向或不重定向。
   判断依据：线程栈里出现 `WriteFileNative`，且 CPU 停止增长。

3. **等端口在听再起客户端。** 世界还在生成时服务器不监听，客户端白连一趟。
   驱动里用 TCP 往返探测 `127.0.0.1:<port>`。

4. **客户端命令要等进世界。** 菜单里 `Main.LocalPlayer` 尚未 active，改血/受伤会被离线档案覆盖。
   驱动在 `-Client` 时自动先发 `c:waitfor inworld`。

## 隔离安装副本

自己也在玩的时候，第二个客户端会和你的游戏抢 Steam 检测、日志目录与前台焦点。
做法是给 lab 复制一份安装（约 270MB）并从副本启动：

```
<KIT>/_inst/steamapps/common/tModLoader     # 必须保持 ...\steamapps\common\tModLoader 这段结构
```

- 副本路径**必须**含 `steamapps\common\tModLoader`：tModLoader 用"CWD 是否位于 /steamapps/ 下"
  判定 Steam 来源，挪到别处会走另一条检测分支，客户端会卡在模组发现阶段。
- 副本自带 `tModLoader-Logs`，与玩家自己的日志互不覆盖。
- `scripts/tml.ps1` 默认优先用副本，`-UseSteamInstall` 可强制用源安装。

## 起客户端的前提（缺一个就白等）

1. **Steam 在跑**：否则弹 Fatal Error 并卡在对话框（`preflight-client.ps1` 会先判）。
2. **沙盒有完整 `config.json`**：缺了会停在 Select Language，模组枚举不开始；用 `resources/config/client-config.json`。
3. **`saves\Mods` 里有 `.tmod` + `enabled.json`**：客户端不认 `-modpath`。
4. **假连接要关**：`-Client` 时驱动自动下发 `s:link off`。

## 窗口尺寸

配置模板默认 **1920×1080**、`UIScale=1.0`、`Zoom=1.0`——和日常游戏一致，截图也是这个尺寸。

- 改尺寸：`-Resolution 1280x720`（驱动每次运行从模板重建 config，所以改了立刻生效）
- 别用旧的 800×720 + `UIScale=1.7`：那是给小窗口凑视觉的，1080p 下字会大得离谱
- 分辨率越大 PNG 越大（1920×1080 约 0.8–0.9 MB/张），CI 上传 artifact 时注意保留天数

## 截图

- 取的是**本进程后缓冲**：世界、HUD、模组 UI 都会在图里；压在游戏窗口上的其他窗口不会。
- UI 有开启动画（SilkyUI 等），打开后要等几帧再拍，固定套路：`c:ui <页面>; c:wait 20; c:shot <名字>`。
- 驱动侧等图就绪：看 `out/<名字>.png` 出现（写入时先落 `.partial` 再改名，所以看到 `.png` 就是完整的）。


`c:shot <名字>` → `out/<名字>.png`。取的是本进程后缓冲（`GraphicsDevice.GetBackBufferData`，
挂在 `Main.OnPostDraw`），不是屏幕抓取，所以压在上面的窗口进不了图。
同一帧排多张也能各自落盘（内部队列）。
