using System;
using Terraria;
using Terraria.Net;
using Terraria.Net.Sockets;

namespace TmlKit.Bridge
{
	// 无头的关键。IL 证据（本机 tModLoader 1.4.4.9）：
	//   Main.DedServ_PostModLoad: IL_0dbe ldsfld Netplay::HasClients
	//                             IL_0dc3 brfalse.s -> 跳过 Game.Update
	// 即：**没有客户端的专用服务器根本不跑世界**（tick 恒 0，每帧钩子永不进入）。
	// 而 Netplay.UpdateConnectedClients 里 HasClients = 已连接 RemoteClient 数，
	// RemoteClient.IsConnected() = Socket != null && Socket.IsConnected()。
	// 所以给一个槽位塞进假的 ISocket（IsConnected 恒真），服务器就会正常跑 Main.Update ——
	// 没有窗口、没有 GPU、没有第二个进程。
	public static class HeadlessLink
	{
		const int Slot = 254;
		static FakeSocket _sock;

		public static bool Installed { get; private set; }
		/// <summary>被 link off 关掉后保持关闭：Pump 每圈都会尝试安装，不记住状态就会又装回来。</summary>
		public static bool Disabled;
		public static string LastError { get; private set; }

		public static bool TryInstall()
		{
			if (!Main.dedServ) return false;
			if (Disabled) return false;
			if (Installed) return true;
			try {
				if (Netplay.Clients == null || Netplay.Clients.Length <= Slot) {
					LastError = "Netplay.Clients not ready";
					return false;
				}
				RemoteClient rc = Netplay.Clients[Slot];
				if (rc == null) { rc = new RemoteClient(); Netplay.Clients[Slot] = rc; }
				if (rc.Socket is FakeSocket) { Installed = true; return true; }

				_sock = new FakeSocket();
				rc.Socket = _sock;
				rc.Id = Slot;
				rc.IsActive = true;
				rc.State = 0;
				rc.TimeOutTimer = 0;
				Installed = true;
				DevBridge.Log("headless link installed at slot " + Slot + " -> HasClients should now be true");
				return true;
			}
			catch (Exception e) {
				LastError = e.GetType().Name + ": " + e.Message;
				DevBridge.Log("headless link FAILED: " + LastError);
				return false;
			}
		}

		/// <summary>撤掉假连接：L2 有真客户端时必须撤，否则真连接会被服务器判为失效并踢掉。</summary>
		public static void Uninstall()
		{
			Disabled = true;   // 先记住，再做清理：Pump 每圈都会重试安装
			if (!Installed || Netplay.Clients == null) { Installed = false; return; }
			try {
				RemoteClient rc = Netplay.Clients[Slot];
				if (rc != null && rc.Socket is FakeSocket) { rc.Socket = null; rc.IsActive = false; }
			} catch { }
			Installed = false;
			Disabled = true;
			DevBridge.Log("headless link removed (slot " + Slot + ")");
		}

		public static void KeepAlive()
		{
			if (!Installed || Netplay.Clients == null) return;
			try {
				RemoteClient rc = Netplay.Clients[Slot];
				if (rc == null || !(rc.Socket is FakeSocket)) { Installed = false; return; }
				rc.IsActive = true;
				rc.TimeOutTimer = 0;
				rc.PendingTerminationApproved = false;
			}
			catch { }
		}
	}

	sealed class FakeSocket : ISocket
	{
		public bool Connected = true;
		static readonly RemoteAddress _addr = new FakeAddress();

		public void Close() { Connected = false; }
		public bool IsConnected() { return Connected; }
		public void Connect(RemoteAddress address) { Connected = true; }
		public bool IsDataAvailable() { return false; }
		public void SendQueuedPackets() { }
		public void StopListening() { }
		public bool StartListening(SocketConnectionAccepted callback) { return false; }
		public RemoteAddress GetRemoteAddress() { return _addr; }

		public void AsyncSend(byte[] data, int offset, int size, SocketSendCallback callback, object state)
		{
			// 立刻回执：服务器写出去的每个包都算已发完，不会卡住发送窗口。
			if (callback != null) { try { callback(state); } catch { } }
		}

		public void AsyncReceive(byte[] data, int offset, int size, SocketReceiveCallback callback, object state)
		{
			// 永不投递：假客户端不发包，所以永远不会有人真正加入世界。
		}
	}

	sealed class FakeAddress : RemoteAddress
	{
		public override string GetIdentifier() { return "127.0.0.1:0"; }
		public override string GetFriendlyName() { return "tmlkit-headless"; }
		public override bool IsLocalHost() { return true; }
	}
}
