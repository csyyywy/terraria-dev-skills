using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Xna.Framework;
using Terraria;
using Terraria.DataStructures;
using Terraria.ID;
using Terraria.GameInput;
using Terraria.IO;
using Terraria.ModLoader;

namespace TmlKit.Bridge
{
	// 文件桥：外部脚本写 in/cmd.txt，模组在主线程每 tick 读一次、执行、写 out/log-<side>.txt。
	// 三条约束：主线程内读写；命令集合固定可枚举；没有 TMLKIT_ROOT 就完全惰性。
	public class DevBridge : ModSystem
	{
		public const string EnvRoot = "TMLKIT_ROOT";

		public static string Root { get; private set; }
		public static bool Armed { get; private set; }
		public static long TickCount { get; private set; }
		public static string LastError { get; private set; }

		public static string Side => Main.dedServ ? "server" : "client";

		public static string InDir => Path.Combine(Root, "in");
		public static string OutDir => Path.Combine(Root, "out");
		// 每个 side 一个命令文件：服务器和客户端跑在同一台机器上，共用一个文件必然互相抢。
		public static string CmdPath => Path.Combine(InDir, "cmd-" + Side + ".txt");
		/// <summary>兼容口：不区分 side 的公共投递箱，谁先到谁取（只在单进程场景用）。</summary>
		public static string SharedCmdPath => Path.Combine(InDir, "cmd.txt");
		public static string LogPath => Path.Combine(OutDir, "log-" + Side + ".txt");
		public static string ResultPath => Path.Combine(OutDir, "result-" + Side + ".txt");
		public static string BeatPath => Path.Combine(OutDir, "heartbeat-" + Side + ".txt");
		public static string DiagPath => Path.Combine(OutDir, "diag-" + Side + ".txt");

		/// <summary>模组注册的自定义动词（避免 fork 桥）。</summary>
		static readonly Dictionary<string, Func<string[], string>> CustomVerbs = new Dictionary<string, Func<string[], string>>(StringComparer.OrdinalIgnoreCase);

		/// <summary>模组注册的 UI 动作（缩放、翻页、点按钮等）：uiact &lt;名字&gt; [参数...]。</summary>
		static readonly Dictionary<string, Action<string[]>> UiActions = new Dictionary<string, Action<string[]>>(StringComparer.OrdinalIgnoreCase);

		/// <summary>注册一个 UI 动作。自绘 UI 读的是 Mouse.GetState()，注入打不到，必须由模组自己暴露入口。</summary>
		public static void RegisterUiAction(string name, Action<string[]> handler)
		{
			if (string.IsNullOrWhiteSpace(name) || handler == null) return;
			UiActions[name.Trim().ToLowerInvariant()] = handler;
			Log("ui action registered: " + name);
		}

		/// <summary>模组注册的 UI 打开器：ui &lt;名字&gt; 就调它。</summary>
		static readonly Dictionary<string, Action> UiOpeners = new Dictionary<string, Action>(StringComparer.OrdinalIgnoreCase);

		/// <summary>注册自定义动词；handler 返回一行结果，抛异常会被记为 ERROR。</summary>
		public static void RegisterVerb(string name, Func<string[], string> handler)
		{
			if (string.IsNullOrWhiteSpace(name) || handler == null) return;
			CustomVerbs[name.Trim().ToLowerInvariant()] = handler;
			Log("verb registered: " + name);
		}

		/// <summary>注册一个 UI 打开器，配合 ui &lt;名字&gt; 使用（模组最清楚自己的界面怎么开）。</summary>
		public static void RegisterUi(string name, Action open)
		{
			if (string.IsNullOrWhiteSpace(name) || open == null) return;
			UiOpeners[name.Trim().ToLowerInvariant()] = open;
			Log("ui registered: " + name);
		}

		static readonly Queue<string> Pending = new Queue<string>();
		static int _waitLeft;
		static long _waitLogMs;
		static long _lastBeatMs;
		static bool _inPoll;
		/// <summary>桥版本：ping 回报，便于识别模组里 vendored 的是哪一版。</summary>
		public const string BridgeVersion = "1.4.0";
		static bool _linkTried;
		static string _pendingKey;      // 待注入的触发器名
		static string _lastKey;         // 上一帧注入过的，用于释放
		static int _pendMouseX = -1, _pendMouseY = -1;
		static string _pendClick;       // "left" / "right"
		static int _mouseHold;          // 按下保持的帧数，之后自动抬起

		public override void Load()
		{
			string env = Environment.GetEnvironmentVariable(EnvRoot);
			try {
				// 载入痕迹：先于一切判断落盘，用来区分"模组没加载"与"环境变量没传进来"
				File.AppendAllText(Path.Combine(Path.GetTempPath(), "tmlkit-load-trace.txt"),
					DateTime.Now.ToString("HH:mm:ss") + " side=" + Side + " dedServ=" + Main.dedServ
					+ " root=" + (env ?? "(null)") + Environment.NewLine);
			} catch { }
			if (string.IsNullOrWhiteSpace(env)) { Armed = false; return; }

			Root = env;
			Armed = true;
			try {
				Directory.CreateDirectory(InDir);
				Directory.CreateDirectory(OutDir);
			}
			catch (Exception e) { LastError = "mkdir: " + e.Message; }

			if (Environment.GetEnvironmentVariable("TMLKIT_MUTE") == "1") {
				Main.soundVolume = 0f;
				Main.musicVolume = 0f;
				Log("mute on (TMLKIT_MUTE=1)");
			}
			Log("bridge armed: side=" + Side + " dedServ=" + Main.dedServ + " root=" + Root);
			Log("verbs: ping diag tick wait shot spawn give tp time weather count find tile save exit");

			// 空服务器不 tick（IL: DedServ_PostModLoad 里 if (Netplay.HasClients) Game.Update）。
			// 这个事件是空服务器里唯一每圈都会被调用的钩子。
			Main.OnTickForThirdPartySoftwareOnly += Pump;
			BridgeShot.Install();
			Poll();
		}

		public override void Unload()
		{
			if (Armed) Main.OnTickForThirdPartySoftwareOnly -= Pump;
			BridgeShot.Uninstall();
			Root = null;
			Armed = false;
			Pending.Clear();
		}

		public override void OnWorldLoad()
		{
			if (!Armed) return;
			Log("world loaded: " + SafeWorldName() + " net=" + Main.netMode);
			Poll();
		}

		/// <summary>输入注入落点：PlayerInput 已经算完本帧的 JustPressed，这里补进去即可被 UI/玩家逻辑看到。</summary>
		public override void PostUpdateInput()
		{
			if (!Armed || Main.dedServ) return;
			try {
				if (_lastKey != null) {   // 上一帧的注入先放掉，避免按键卡住
					PlayerInput.Triggers.Current.KeyStatus[_lastKey] = false;
					PlayerInput.Triggers.JustPressed.KeyStatus[_lastKey] = false;
					_lastKey = null;
				}
				if (_pendMouseX >= 0) {
					Main.mouseX = Math.Min(Math.Max(_pendMouseX, 0), Math.Max(Main.screenWidth - 1, 0));
					Main.mouseY = Math.Min(Math.Max(_pendMouseY, 0), Math.Max(Main.screenHeight - 1, 0));
					Log("mouse -> " + Main.mouseX + "," + Main.mouseY + " (MouseScreen 同步)");
					_pendMouseX = _pendMouseY = -1;
				}
				if (_pendClick != null) {
					if (_pendClick == "right") {
						PlayerInput.Triggers.Current.MouseRight = true;
						PlayerInput.Triggers.JustPressed.MouseRight = true;
						// UI 与第三方框架读的是 Main.mouseRight + Release 的边沿，只写 PlayerInput 打不到控件
						Main.mouseRight = true;
						Main.mouseRightRelease = true;
					} else {
						PlayerInput.Triggers.Current.MouseLeft = true;
						PlayerInput.Triggers.JustPressed.MouseLeft = true;
						Main.mouseLeft = true;
						Main.mouseLeftRelease = true;
					}
					_mouseHold = 2;
					Log("click " + _pendClick + " -> pressed at " + Main.mouseX + "," + Main.mouseY);
					_pendClick = null;
				} else if (_mouseHold > 0 && --_mouseHold == 0) {
					PlayerInput.Triggers.Current.MouseLeft = false;
					PlayerInput.Triggers.Current.MouseRight = false;
					PlayerInput.Triggers.JustPressed.MouseLeft = false;
					PlayerInput.Triggers.JustPressed.MouseRight = false;
					Main.mouseLeft = false; Main.mouseLeftRelease = false;
					Main.mouseRight = false; Main.mouseRightRelease = false;
				}
				if (_pendingKey != null) {
					PlayerInput.Triggers.JustPressed.KeyStatus[_pendingKey] = true;
					PlayerInput.Triggers.Current.KeyStatus[_pendingKey] = true;
					_lastKey = _pendingKey;
					Log("key " + _pendingKey + " -> injected (focus-free)");
					_pendingKey = null;
				}
			}
			catch (Exception e) { Log("key inject ERROR: " + e.GetType().Name + ": " + e.Message); }
		}

		static bool KnownTrigger(string name)
		{
			if (string.IsNullOrWhiteSpace(name)) return false;
			if (PlayerInput.KnownTriggers != null && PlayerInput.KnownTriggers.Contains(name)) return true;
			// 模组键位形如 "ModName/BindName"，不在 KnownTriggers 里，直接放行交给运行时判断
			return name.Contains("/");
		}

		public override void PostUpdateEverything()
		{
			if (!Armed) return;
			TickCount++;
			Heartbeat();
			Poll(advanceClock: true);
		}

		static void Pump()
		{
			if (!Armed) return;
			if (!_linkTried) { _linkTried = true; HeadlessLink.TryInstall(); }
			HeadlessLink.KeepAlive();
			Heartbeat();
			Poll();
		}

		static void Heartbeat()
		{
			long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
			if (now - _lastBeatMs < 250) return;
			_lastBeatMs = now;
			try {
				File.WriteAllText(BeatPath, string.Format(CultureInfo.InvariantCulture,
					"ms={0}\ntick={1}\nside={2}\nnet={3}\nworld={4}\nplayer={5}\nfps={6}\n",
					now, TickCount, Side, Main.netMode, SafeWorldName(), LocalPlayerName(), Fps()));
			}
			catch (Exception e) { LastError = "beat: " + e.Message; }
		}

		static string Fps()
		{
			try { return Math.Round((double)Main.frameRate, 1).ToString(CultureInfo.InvariantCulture); }
			catch { return "0"; }
		}

		static string SafeWorldName()
		{
			try { return Main.worldName ?? "(none)"; } catch { return "(err)"; }
		}

		static string LocalPlayerName()
		{
			try {
				Player p = Main.LocalPlayer;
				return p != null && !string.IsNullOrEmpty(p.name) ? p.name : "(none)";
			}
			catch { return "(err)"; }
		}

		static void Poll(bool advanceClock = false)
		{
			if (_inPoll) return;
			_inPoll = true;
			// 在菜单里（还没进世界）也要有心跳：客户端启动后到进入世界之间有几十秒，
			// 没有心跳的话驱动只能瞎等，且分不清"起不来"和"起来了但还没进去"。
			Heartbeat();
			try {
				foreach (string path in new[] { CmdPath, SharedCmdPath }) {
					if (!File.Exists(path)) continue;
					string[] lines;
					using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
					using (var sr = new StreamReader(fs, Encoding.UTF8)) {
						lines = sr.ReadToEnd().Split('\n');
					}
					try { File.Delete(path); } catch { }
					int n = 0;
					foreach (string raw in lines) {
						string line = raw.Trim().TrimEnd('\r');
						if (line.Length == 0 || line.StartsWith("#")) continue;
						if (!Mine(line)) continue;
						Pending.Enqueue(line);
						n++;
					}
					Log("got " + n + " command(s) from " + Path.GetFileName(path));
				}

				while (Pending.Count > 0) {
					if (_waitLeft > 0) { if (advanceClock) _waitLeft--; break; }
					string line = Pending.Peek();
					if (!Execute(line)) break;
					Pending.Dequeue();
				}
			}
			catch (Exception e) {
				LastError = "poll: " + e.Message;
				Log("POLL ERROR " + e.Message);
			}
			finally { _inPoll = false; }
		}

		static bool Mine(string line)
		{
			if (line.StartsWith("s:")) return Side == "server";
			if (line.StartsWith("c:")) return Side == "client";
			return true;
		}

		static string Strip(string line)
		{
			if (line.StartsWith("s:") || line.StartsWith("c:")) return line.Substring(2).Trim();
			return line;
		}

		static bool Execute(string rawLine)
		{
			string line = Strip(rawLine);
			string[] a = line.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
			if (a.Length == 0) return true;
			string verb = a[0].ToLowerInvariant();
			try {
				switch (verb) {
					case "ping":
						Log("pong tick=" + TickCount + " side=" + Side + " net=" + Main.netMode + " world=" + SafeWorldName() + " bridge=" + BridgeVersion);
						// 同时产出一条 [TEST]，让"就绪判据"在任意桥上都统一（驱动只认这一种行）
						Report("ping", true, "tick=" + TickCount + " side=" + Side + " world=" + SafeWorldName() + " bridge=" + BridgeVersion);
						return true;

					case "tick":
						Log("tick=" + TickCount);
						return true;

					case "wait": {
						// 默认按 tick；支持后缀：20t（tick）、1s（秒 → 60 tick）
						string spec = a.Length > 1 ? a[1].Trim().ToLowerInvariant() : "60";
						double amount;
						int n;
						if (spec.EndsWith("s") && double.TryParse(spec.Substring(0, spec.Length - 1), NumberStyles.Float, CultureInfo.InvariantCulture, out amount)) {
							n = (int)Math.Round(amount * 60);
						}
						else if (spec.EndsWith("t") && double.TryParse(spec.Substring(0, spec.Length - 1), NumberStyles.Float, CultureInfo.InvariantCulture, out amount)) {
							n = (int)Math.Round(amount);
						}
						else if (!int.TryParse(spec, NumberStyles.Integer, CultureInfo.InvariantCulture, out n)) {
							Log("wait REFUSED: 用法 wait <ticks> | 20t | 1s");
							return true;
						}
						_waitLeft = Math.Max(1, n);
						Log("wait " + _waitLeft + " tick(s) (" + spec + ") from " + TickCount);
						return true;
					}

					case "diag":
						WriteDiag();
						return true;

					case "shot": {
						string name = a.Length > 1 ? a[1] : "shot";
						string problem;
						Rectangle? area = null;
						if (a.Length >= 6) {
							// shot <name> <x> <y> <w> <h>：只拍这块（屏幕坐标），省得整屏裁
							try {
								area = new Rectangle(int.Parse(a[2], CultureInfo.InvariantCulture), int.Parse(a[3], CultureInfo.InvariantCulture),
									int.Parse(a[4], CultureInfo.InvariantCulture), int.Parse(a[5], CultureInfo.InvariantCulture));
							} catch { Log("shot REFUSED: 区域参数必须是 4 个整数 <x> <y> <w> <h>"); return true; }
						}
						if (BridgeShot.Request(name, out problem, area)) {
							Log("shot queued -> " + name + ".png" + (area.HasValue ? " region=" + area.Value : ""));
						}
						else Log("shot REFUSED: " + problem);
						return true;
					}

					case "spawn": {
						int type = int.Parse(a[1], CultureInfo.InvariantCulture);
						int count = a.Length > 2 ? int.Parse(a[2], CultureInfo.InvariantCulture) : 1;
						int made = 0;
						for (int i = 0; i < count; i++) {
							Vector2 at = SpawnPoint(i, count);
							int idx = NPC.NewNPC(new EntitySource_DebugCommand("tmlkit"), (int)at.X, (int)at.Y, type);
							if (idx >= 0 && idx < Main.maxNPCs && Main.npc[idx].active) made++;
						}
						Log("spawn id=" + type + " requested=" + count + " made=" + made);
						return true;
					}

					case "give": {
						int item = int.Parse(a[1], CultureInfo.InvariantCulture);
						int stack = a.Length > 2 ? int.Parse(a[2], CultureInfo.InvariantCulture) : 1;
						Player p = Main.LocalPlayer;
						if (p == null || !p.active) { Log("give REFUSED: no local player on this side"); return true; }
						p.QuickSpawnItem(new EntitySource_DebugCommand("tmlkit"), item, stack);
						Log("give id=" + item + " stack=" + stack + " to " + p.name);
						return true;
					}

					case "tp": {
						Player p = Main.LocalPlayer;
						if (p == null || !p.active) { Log("tp REFUSED: no local player on this side"); return true; }
						float x = float.Parse(a[1], CultureInfo.InvariantCulture) * 16f;
						float y = float.Parse(a[2], CultureInfo.InvariantCulture) * 16f;
						p.position = new Vector2(x, y);
						p.velocity = Vector2.Zero;
						Log("tp player -> tile " + a[1] + "," + a[2]);
						return true;
					}

					case "time": {
						string when = a.Length > 1 ? a[1].ToLowerInvariant() : "noon";
						if (when == "day") { Main.dayTime = true; Main.time = 0; }
						else if (when == "noon") { Main.dayTime = true; Main.time = 27000; }
						else if (when == "night") { Main.dayTime = false; Main.time = 0; }
						else if (when == "midnight") { Main.dayTime = false; Main.time = 16200; }
						else { Log("time REFUSED: '" + when + "' is not one of day noon night midnight"); return true; }
						Log("time=" + when + " dayTime=" + Main.dayTime + " t=" + (int)Main.time);
						return true;
					}

					case "weather": {
						string w = a.Length > 1 ? a[1].ToLowerInvariant() : "clear";
						if (w == "rain") { Main.raining = true; Main.rainTime = 3600; }
						else if (w == "clear") { Main.raining = false; Main.rainTime = 0; }
						else { Log("weather REFUSED: '" + w + "' is not rain or clear"); return true; }
						Log("weather=" + w + " raining=" + Main.raining);
						return true;
					}

					case "count":
						Log(CountVerb(a));
						return true;

					case "find":
						FindVerb(a);
						return true;

					case "tile": {
						int x = int.Parse(a[1], CultureInfo.InvariantCulture);
						int y = int.Parse(a[2], CultureInfo.InvariantCulture);
						Tile t = Main.tile[x, y];
						Log("tile " + x + "," + y + " active=" + t.HasTile + " type=" + t.TileType + " wall=" + t.WallType);
						return true;
					}

					case "waitfor": {
						// 阻塞式前置条件：条件不满足就原地等（Execute 返回 false，下一 tick 再来）
						string cond = a.Length > 1 ? a[1].ToLowerInvariant() : "inworld";
						bool ok;
						if (cond == "inworld") {
							Player lp = Main.LocalPlayer;
							ok = !Main.gameMenu && lp != null && lp.active && !lp.dead;
						}
						else if (cond == "menu") ok = Main.gameMenu;
						else { Log("waitfor REFUSED: '" + cond + "' is not inworld or menu"); return true; }

						if (!ok) {
							if (TickCount % 300 == 0) if (Environment.TickCount64 - _waitLogMs > 1000) { _waitLogMs = Environment.TickCount64;
							Log(string.Join(" ", a) + " ... still waiting (tick=" + TickCount + ")"); }
							return false;
						}
						Log("waitfor " + cond + " ok at tick=" + TickCount);
						return true;
					}

					case "ui": {
						// 打开界面：优先用模组自己注册的打开器（最可靠），内置的只有背包这类纯状态开关
						if (a.Length < 2) {
							Log("ui REFUSED: usage ui <name>; mod: " + (UiOpeners.Count > 0 ? string.Join(",", UiOpeners.Keys) : "(none)") + "; builtin: inventory, close");
							return true;
						}
						string page = a[1].ToLowerInvariant();
						if (page == "inventory") { Main.playerInventory = true; Log("ui inventory -> open"); return true; }
						if (page == "close") { Main.playerInventory = false; Log("ui close -> closed"); return true; }
						if (UiOpeners.TryGetValue(page, out Action opener)) {
							try { opener(); Log("ui " + page + " -> opened"); }
							catch (Exception e) { Log("ui " + page + " ERROR: " + e.GetType().Name + ": " + e.Message); }
							return true;
						}
						Log("ui REFUSED: '" + page + "' not registered; mod: " + (UiOpeners.Count > 0 ? string.Join(",", UiOpeners.Keys) : "(none)") + "; builtin: inventory, close");
						return true;
					}

					case "key": {
						// 默认走进程内注入（PlayerInput.Triggers）：不依赖窗口焦点，最小化/无人值守也能用。
						// 需要真键盘事件的场景（少数 UI 只读 keyboard state）用 key vk:<KEYSYM>。
						if (a.Length < 2) { Log("key REFUSED: usage key <触发器名|vk:KEYSYM>; 例：key Inventory / key Escape / key vk:E"); return true; }
						string spec = a[1];
						if (spec.StartsWith("vk:", StringComparison.OrdinalIgnoreCase)) {
							if (Main.dedServ) { Log("key vk: REFUSED: no window on a dedicated server"); return true; }
							Log(WinKeys.Send(spec.Substring(3)) ? ("key " + spec + " -> sent (win32, 需要窗口焦点)") : ("key REFUSED: '" + spec + "' unknown keysym"));
							return true;
						}
						if (Main.dedServ) { Log("key REFUSED: no input pipeline on a dedicated server (use L2 / -Client)"); return true; }
						if (!KnownTrigger(spec)) { Log("key REFUSED: '" + spec + "' 不是已知触发器；常见：Inventory Map Chat MouseLeft Grapple QuickMount 或模组键位 <Mod>/<Bind>"); return true; }
						_pendingKey = spec;
						Log("key " + spec + " -> queued (注入下一帧)");
						return true;
					}

					case "assert": {
						// 断言直接产出 [TEST] 行：assert hp>=60 / assert npc<=3 / assert inventory==true
						if (a.Length < 2) { Log("assert REFUSED: usage assert <field><op><value>，field: hp hpmax defense npc players inventory"); return true; }
						string expr = string.Concat(a.Skip(1)).Replace(" ", "");
						string field = "", op = "", valueText = "";
						foreach (string candidate in new[] { ">=", "<=", "==", "!=", ">", "<" }) {
							int at = expr.IndexOf(candidate, StringComparison.Ordinal);
							if (at > 0) { field = expr.Substring(0, at); op = candidate; valueText = expr.Substring(at + candidate.Length); break; }
						}
						if (field == "") { Log("assert REFUSED: 缺少比较运算符（>= <= == != > <）"); return true; }
						double actual;
						switch (field.ToLowerInvariant()) {
							case "hp": actual = Main.player[Main.myPlayer].statLife; break;
							case "hpmax": actual = Main.player[Main.myPlayer].statLifeMax2; break;
							case "defense": actual = Main.player[Main.myPlayer].statDefense; break;
							case "npc": actual = 0; foreach (NPC n in Main.npc) { if (n != null && n.active) actual++; } break;
							case "players": actual = 0; foreach (Player pl in Main.player) { if (pl != null && pl.active) actual++; } break;
							case "inventory": actual = Main.playerInventory ? 1 : 0; break;
							default: Log("assert REFUSED: 未知字段 '" + field + "'"); return true;
						}
						double want = 0;
						if (valueText.Equals("true", StringComparison.OrdinalIgnoreCase)) want = 1;
						else if (valueText.Equals("false", StringComparison.OrdinalIgnoreCase)) want = 0;
						else if (!double.TryParse(valueText, out want)) { Log("assert REFUSED: 值不是数字/布尔：'" + valueText + "'"); return true; }
						bool ok;
						switch (op) {
							case ">=": ok = actual >= want; break;
							case "<=": ok = actual <= want; break;
							case "==": ok = Math.Abs(actual - want) < 0.0001; break;
							case "!=": ok = Math.Abs(actual - want) >= 0.0001; break;
							case ">": ok = actual > want; break;
							default: ok = actual < want; break;
						}
						string caseName = "assert_" + field.ToLowerInvariant() + op.Replace(">=", "gte").Replace("<=", "lte").Replace("==", "eq").Replace("!=", "ne").Replace(">", "gt").Replace("<", "lt") + want.ToString("0.##");
						Report(caseName, ok, field + "=" + actual.ToString("0.##") + " 期望 " + op + " " + want.ToString("0.##"));
						return true;
					}

					case "speed": {
						// 加速：关掉固定时间步进，游戏循环按 CPU 速度跑（只适合服务端逻辑测试）
						bool fast = !(a.Length > 1 && a[1].ToLowerInvariant() == "off");
						try { Main.instance.IsFixedTimeStep = !fast; }
						catch (Exception e) { Log("speed ERROR: " + e.Message); return true; }
						Log("speed " + (fast ? "fast (IsFixedTimeStep=false)" : "realtime") + " at tick=" + TickCount);
						return true;
					}

					case "mouse": {
						if (Main.dedServ) { Log("mouse REFUSED: 服务端没有界面"); return true; }
						int mx, my;
						if (a.Length < 3 || !int.TryParse(a[1], out mx) || !int.TryParse(a[2], out my)) {
							Log("mouse REFUSED: usage mouse <x> <y>");
							return true;
						}
						_pendMouseX = mx; _pendMouseY = my;
						Log("mouse " + mx + "," + my + " -> queued");
						return true;
					}

					case "click": {
						if (Main.dedServ) { Log("click REFUSED: 服务端没有界面"); return true; }
						string btn = (a.Length > 1 ? a[1].ToLowerInvariant() : "left");
						int cx, cy;
						if (a.Length >= 4 && int.TryParse(a[2], out cx) && int.TryParse(a[3], out cy)) { _pendMouseX = cx; _pendMouseY = cy; }
						if (btn != "left" && btn != "right") { Log("click REFUSED: 只支持 left / right"); return true; }
						_pendClick = btn;
						Log("click " + btn + " -> queued");
						return true;
					}

					case "assertpix": {
						// assertpix <x> <y> <#rrggbb> [tol]：同帧读后缓冲，直接给 [TEST]
						if (a.Length < 4) { Log("assertpix REFUSED: usage assertpix <x> <y> <#rrggbb> [tol]"); return true; }
						int px, py;
						if (!int.TryParse(a[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out px) ||
						    !int.TryParse(a[2], NumberStyles.Integer, CultureInfo.InvariantCulture, out py)) {
							Log("assertpix REFUSED: 坐标必须是整数"); return true;
						}
						string want = a[3].TrimStart('#');
						if (want.Length != 6) { Log("assertpix REFUSED: 颜色要 #rrggbb"); return true; }
						int tol = 12;
						if (a.Length >= 5) int.TryParse(a[4], NumberStyles.Integer, CultureInfo.InvariantCulture, out tol);
						int wr = Convert.ToInt32(want.Substring(0, 2), 16);
						int wg = Convert.ToInt32(want.Substring(2, 2), 16);
						int wb = Convert.ToInt32(want.Substring(4, 2), 16);
						Color got;
						string problem;
						if (!BridgeShot.TryPeekPixel(px, py, out got, out problem)) { Report("assertpix", false, problem); return true; }
						int dr = Math.Abs(got.R - wr), dg = Math.Abs(got.G - wg), db = Math.Abs(got.B - wb);
						bool pass = dr <= tol && dg <= tol && db <= tol;
						Report("assertpix", pass, "at=" + px + "," + py + " got=" + got.R.ToString("x2") + got.G.ToString("x2") + got.B.ToString("x2") + " want=" + want + " d=" + dr + "," + dg + "," + db + " tol=" + tol);
						return true;
					}

					case "uiact": {
						// 模组自绘 UI 的唯一可靠通道：动作名 + 参数，由模组自己执行
						if (a.Length < 2) {
							Log("uiact REFUSED: usage uiact <名字> [参数...]; 已注册: " + (UiActions.Count > 0 ? string.Join(",", UiActions.Keys) : "(none)"));
							return true;
						}
						string act = a[1].ToLowerInvariant();
						if (!UiActions.TryGetValue(act, out Action<string[]> handler2)) {
							Log("uiact REFUSED: '" + act + "' 未注册; 已注册: " + (UiActions.Count > 0 ? string.Join(",", UiActions.Keys) : "(none)"));
							return true;
						}
						try { handler2(a.Skip(2).ToArray()); Log("uiact " + act + " -> done"); }
						catch (Exception e) { Log("uiact " + act + " ERROR: " + e.GetType().Name + ": " + e.Message); }
						return true;
					}

					case "wheel": {
						// 滚轮：UI（含 SilkyUI）看 PlayerInput.ScrollWheelDeltaForUI，游戏内看 ScrollWheelValue
						if (Main.dedServ) { Log("wheel REFUSED: 服务端没有界面"); return true; }
						int delta;
						if (a.Length < 2 || !int.TryParse(a[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out delta)) {
							Log("wheel REFUSED: usage wheel <delta>（正=上滚，负=下滚）");
							return true;
						}
						try {
							PlayerInput.ScrollWheelValue += delta * 120;
							PlayerInput.ScrollWheelDeltaForUI = delta * 120;
						} catch (Exception e) { Log("wheel ERROR: " + e.Message); return true; }
						Log("wheel " + delta + " -> queued");
						return true;
					}

					case "mute": {
						bool on = !(a.Length > 1 && a[1].ToLowerInvariant() == "off");
						Main.soundVolume = on ? 0f : 1f;
						Main.musicVolume = on ? 0f : 1f;
						Log("mute " + (on ? "on" : "off") + " -> sound=" + Main.soundVolume + " music=" + Main.musicVolume);
						return true;
					}

					case "link": {
						// L1 用 on（无客户端也 tick）；L2 用 off（真客户端就是 HasClients，假连接会把真连接挤掉）
						bool on = !(a.Length > 1 && a[1].ToLowerInvariant() == "off");
						if (on) { HeadlessLink.Disabled = false; bool ok = HeadlessLink.TryInstall(); Log("link on -> " + ok); }
						else { HeadlessLink.Uninstall(); Log("link off"); }
						return true;
					}

					case "save":
						WorldFile.SaveWorld();
						Log("save ok");
						return true;

					case "note":
						Log(line.Substring(4).Trim());
						return true;

					case "exit":
						Log("exit requested at tick=" + TickCount + " side=" + Side);
						if (a.Length > 1 && a[1].ToLowerInvariant() == "save") {
							try { WorldFile.SaveWorld(); } catch (Exception e) { Log("save before exit failed: " + e.Message); }
						}
						Environment.Exit(0);
						return true;

					default:
						if (CustomVerbs.TryGetValue(verb, out var custom)) {
							try { Log(verb + " -> " + (custom(a) ?? "ok")); }
							catch (Exception e) { Log("ERROR " + verb + ": " + e.GetType().Name + ": " + e.Message); }
							return true;
						}
						if (DevPlayer.TryExecute(verb, a)) return true;
						Log("REFUSED: unknown verb '" + verb + "' - builtin: ping diag tick wait shot spawn give tp time weather count find tile save note exit ui key link mouse click mute wheel uiact assertpix speed assert | player: god kb lockhp keepalive hp hpmax defense hurt immune buff clearbuffs state check playerreset"
							+ (CustomVerbs.Count > 0 ? " | mod: " + string.Join(",", CustomVerbs.Keys) : "")
							+ (UiOpeners.Count > 0 ? " | ui: " + string.Join(",", UiOpeners.Keys) : ""));
						return true;
				}
			}
			catch (Exception e) {
				Log("ERROR " + verb + ": " + e.GetType().Name + ": " + e.Message);
				return true;
			}
		}

		static Vector2 SpawnPoint(int i, int count)
		{
			Player p = Main.LocalPlayer;
			Vector2 baseP = p != null && p.active
				? p.Center
				: new Vector2(Main.spawnTileX * 16f, Main.spawnTileY * 16f);
			float spread = (i - (count - 1) / 2f) * 48f;
			return baseP + new Vector2(spread, -160f);
		}

		static string CountVerb(string[] a)
		{
			string kind = a.Length > 1 ? a[1].ToLowerInvariant() : "npc";
			if (kind == "npc") return "count npc = " + Main.npc.Count(n => n.active);
			if (kind == "item") return "count item = " + Main.item.Count(i => i.active);
			if (kind == "proj") return "count proj = " + Main.projectile.Count(p => p.active);
			if (kind == "player") return "count player = " + Main.player.Count(p => p.active);
			return "count REFUSED: '" + kind + "' is not npc item proj player";
		}

		static void FindVerb(string[] a)
		{
			string kind = a.Length > 1 ? a[1].ToLowerInvariant() : "npc";
			int wantType = a.Length > 2 ? int.Parse(a[2], CultureInfo.InvariantCulture) : -1;
			int n = 0;
			if (kind == "npc") {
				foreach (NPC npc in Main.npc) {
					if (!npc.active) continue;
					if (wantType >= 0 && npc.type != wantType) continue;
					Log("npc slot=" + npc.whoAmI + " type=" + npc.type + " pos=" + (int)(npc.position.X / 16) + "," + (int)(npc.position.Y / 16) + " life=" + npc.life + "/" + npc.lifeMax);
					n++;
				}
			}
			else if (kind == "item") {
				foreach (Item it in Main.item) {
					if (!it.active) continue;
					if (wantType >= 0 && it.type != wantType) continue;
					Log("item slot=" + it.whoAmI + " type=" + it.type + " stack=" + it.stack);
					n++;
				}
			}
			else { Log("find REFUSED: '" + kind + "' is not npc or item"); return; }
			Log("find " + kind + " matched=" + n);
		}

		static void WriteDiag()
		{
			var sb = new StringBuilder();
			sb.AppendLine("side: " + Side);
			sb.AppendLine("net: " + Main.netMode);
			sb.AppendLine("world: " + SafeWorldName());
			sb.AppendLine("tick: " + TickCount);
			sb.AppendLine("dayTime: " + Main.dayTime);
			sb.AppendLine("time: " + (int)Main.time);
			sb.AppendLine("players: " + Main.player.Count(p => p.active));
			sb.AppendLine("npc: " + Main.npc.Count(n => n.active));
			sb.AppendLine("items: " + Main.item.Count(i => i.active));
			sb.AppendLine("proj: " + Main.projectile.Count(p => p.active));
			sb.AppendLine("hasClients: " + Netplay.HasClients);
			sb.AppendLine("localPlayer: " + LocalPlayerName());
			File.WriteAllText(DiagPath, sb.ToString());
			Log("diag -> " + DiagPath);
		}

		public static void Log(string message)
		{
			if (Root == null) return;
			try {
				File.AppendAllText(LogPath, "[" + DateTime.Now.ToString("HH:mm:ss.fff") + "] [" + TickCount + "] " + message + Environment.NewLine);
			}
			catch { }
		}

		/// <summary>受伤流水账：每次 hurt/挨打都记一行，用来验证"受伤特效触发了但血没掉"这类断言。</summary>
		public static void RecordHurt(string kind, int requested, int hpBefore, int hpAfter)
		{
			if (Root == null) return;
			try {
				string path = Path.Combine(OutDir, "hurt-" + Side + ".txt");
				File.AppendAllText(path, string.Format(CultureInfo.InvariantCulture,
					"t={0} tick={1} kind={2} dmg={3} hp={4}->{5}{6}",
					DateTime.Now.ToString("HH:mm:ss.fff"), TickCount, kind, requested, hpBefore, hpAfter, Environment.NewLine));
			}
			catch { }
		}

		/// <summary>最小的按键注入：keybd_event。只在有真实窗口的客户端有意义。</summary>
		static class WinKeys
		{
			const uint KEYUP = 0x0002;
			[DllImport("user32.dll")] static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr extra);

			public static bool Send(string spec)
			{
				byte vk = Map(spec);
				if (vk == 0) return false;
				try {
					keybd_event(vk, 0, 0, UIntPtr.Zero);
					System.Threading.Thread.Sleep(30);
					keybd_event(vk, 0, KEYUP, UIntPtr.Zero);
					return true;
				}
				catch { return false; }
			}

			static byte Map(string s)
			{
				if (string.IsNullOrWhiteSpace(s)) return 0;
				string k = s.Trim().ToUpperInvariant();
				if (k.Length == 1) {
					char c = k[0];
					if (c >= 'A' && c <= 'Z') return (byte)c;
					if (c >= '0' && c <= '9') return (byte)c;
				}
				if (k.Length == 2 && k[0] == 'D' && k[1] >= '0' && k[1] <= '9') return (byte)(0x30 + (k[1] - '0'));
				switch (k) {
					case "ESC": case "ESCAPE": return 0x1B;
					case "TAB": return 0x09;
					case "SPACE": return 0x20;
					case "ENTER": return 0x0D;
					case "UP": return 0x26;
					case "DOWN": return 0x28;
					case "LEFT": return 0x25;
					case "RIGHT": return 0x27;
					case "F1": return 0x70;
					case "F2": return 0x71;
					default: return 0;
				}
			}
		}

		public static void Report(string testCase, bool ok, string detail)
		{
			if (Root == null) return;
			string line = ("[TEST] " + testCase + " " + (ok ? "PASS" : "FAIL") + " " + (detail ?? "")).TrimEnd();
			try {
				File.AppendAllText(ResultPath, line + Environment.NewLine);
				Log(line);
			}
			catch { }
		}
	}
}
