using System;
using System.IO;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Terraria;
using Terraria.ModLoader;

namespace TmlKit.Bridge
{
	// 截图：从**本进程自己的后缓冲**读像素（GraphicsDevice.GetBackBufferData），不是屏幕抓取。
	// 压在游戏窗口上的任何窗口都进不了这张图 —— 结构性保证，不是运气。
	// 必须在 Main.OnPostDraw（整帧画完之后）取；PostDrawInterface 会拍到画一半的帧。
	public static class BridgeShot
	{
		static readonly System.Collections.Generic.Queue<(string name, Rectangle? area)> _pending = new System.Collections.Generic.Queue<(string, Rectangle?)>();
		public static string LastPath;
		public static string LastError;

		public static void Install()
		{
			if (Main.dedServ) return;   // 专用服务器没有 GraphicsDevice，订阅只会变成空引用等待
			Main.OnPostDraw += Capture;
		}

		public static void Uninstall()
		{
			if (Main.dedServ) return;
			Main.OnPostDraw -= Capture;
		}

		/// <summary>请求截图；area 为 null 时拍全屏，否则只拍该矩形（屏幕坐标）。</summary>
		public static bool Request(string name, out string problem, Rectangle? area = null)
		{
			problem = null;
			if (Main.dedServ) { problem = "a dedicated server has no back buffer - ask a client"; return false; }
			if (string.IsNullOrWhiteSpace(name)) { problem = "no name given"; return false; }
			if (area.HasValue) {
				Rectangle r = area.Value;
				r = Rectangle.Intersect(r, new Rectangle(0, 0, Main.screenWidth, Main.screenHeight));
				if (r.Width <= 0 || r.Height <= 0) { problem = "region is outside the screen: " + area.Value; return false; }
				area = r;
			}
			_pending.Enqueue((name, area));
			return true;
		}

		static void Capture(GameTime gameTime)
		{
			if (_pending.Count == 0) return;
			(string name, Rectangle? area) job = _pending.Dequeue();   // 先出队：下面抛异常时不会每帧重入
			string name = job.name;
			Rectangle? area = job.area;
			try {
				GraphicsDevice device = Main.graphics == null ? null : Main.graphics.GraphicsDevice;
				if (device == null) { LastError = "no graphics device"; return; }

				int w = Main.screenWidth;
				int h = Main.screenHeight;
				if (w <= 0 || h <= 0) { LastError = "screen not ready"; return; }

				Rectangle rect = area ?? new Rectangle(0, 0, w, h);
				var pixels = new Color[rect.Width * rect.Height];
				device.GetBackBufferData(rect, pixels, 0, pixels.Length);
				w = rect.Width; h = rect.Height;

				// 同帧记录坐标：跨帧核对是错误来源（fit/动画会改布局）
				DevBridge.Log("shotframe name=" + name + " tick=" + DevBridge.TickCount + " rect=" + rect.X + "," + rect.Y + "," + rect.Width + "," + rect.Height + " mouse=" + Main.mouseX + "," + Main.mouseY);

				using (var tex = new Texture2D(device, w, h)) {
					tex.SetData(pixels);
					string path = Path.Combine(DevBridge.OutDir, name + ".png");
					string partial = path + ".partial";
					using (var stream = File.Create(partial)) tex.SaveAsPng(stream, w, h);
					File.Move(partial, path, overwrite: true);
					LastPath = path;
					LastError = null;
					DevBridge.Log("shot written -> " + path + " (" + w + "x" + h + ")");
				}
			}
			catch (Exception e) {
				LastError = e.ToString();
				DevBridge.Log("SHOT ERROR " + e.GetType().Name + ": " + e.Message);
			}
		}

		/// <summary>读当前后缓冲的一个像素（同帧），用于像素级断言。</summary>
		public static bool TryPeekPixel(int x, int y, out Color color, out string problem)
		{
			color = default;
			problem = null;
			if (Main.dedServ) { problem = "a dedicated server has no back buffer"; return false; }
			GraphicsDevice device = Main.graphics == null ? null : Main.graphics.GraphicsDevice;
			if (device == null) { problem = "no graphics device"; return false; }
			if (x < 0 || y < 0 || x >= Main.screenWidth || y >= Main.screenHeight) { problem = "point outside screen: " + x + "," + y; return false; }
			try {
				var px = new Color[1];
				device.GetBackBufferData(new Rectangle(x, y, 1, 1), px, 0, 1);
				color = px[0];
				return true;
			}
			catch (Exception e) { problem = e.GetType().Name + ": " + e.Message; return false; }
		}
	}
}