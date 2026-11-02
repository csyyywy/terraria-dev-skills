using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using Microsoft.Xna.Framework;
using Terraria;
using Terraria.DataStructures;
using Terraria.ID;
using Terraria.ModLoader;

namespace TmlKit.Bridge
{
	/// <summary>测试角色配置：只作用于本 side 的 LocalPlayer。</summary>
	public static class TestPlayerConfig
	{
		public static bool God;              // 伤害直接取消（ModifyHurt + Cancel）
		public static bool NoKnockback;      // 免疫击退
		public static int  LockHp = -1;      // >=0：每帧把血锁在这个值（无限血）
		public static bool LockHpOn => LockHp >= 0;
		public static bool KeepHpAfterHurt;  // 受伤流程照跑（特效/音效/无敌帧），血再还回去
		public static int  HpBeforeHurt;

		public static void Reset()
		{
			God = false;
			NoKnockback = false;
			LockHp = -1;
			KeepHpAfterHurt = false;
		}
	}

	public class TestPlayer : ModPlayer
	{
		public override void PostUpdate()
		{
			if (!DevBridge.Armed) return;
			if (Player.whoAmI != Main.myPlayer) return;

			if (TestPlayerConfig.NoKnockback) Player.noKnockback = true;

			if (TestPlayerConfig.LockHpOn) {
				int cap = Math.Min(TestPlayerConfig.LockHp, Player.statLifeMax2);
				if (cap > 0) Player.statLife = cap;
			}
			TestPlayerConfig.HpBeforeHurt = Player.statLife;
		}

		// 这一版 tML 的受伤 API 是 HurtModifiers/HurtInfo（老的 PreHurt 已经没有了）
		public override void ModifyHurt(ref Player.HurtModifiers modifiers)
		{
			if (!DevBridge.Armed) return;
			if (Player.whoAmI != Main.myPlayer) return;
			if (!TestPlayerConfig.God) return;

			modifiers.Cancel();
			DevBridge.RecordHurt("blocked", 0, Player.statLife, Player.statLife);
			DevBridge.Log("hurt BLOCKED by god (hp=" + Player.statLife + ")");
		}

		public override void PostHurt(Player.HurtInfo info)
		{
			if (!DevBridge.Armed) return;
			if (Player.whoAmI != Main.myPlayer) return;

			if (TestPlayerConfig.KeepHpAfterHurt && !TestPlayerConfig.God) {
				Player.statLife = TestPlayerConfig.HpBeforeHurt;
			}
			if (TestPlayerConfig.LockHpOn) {
				int cap = Math.Min(TestPlayerConfig.LockHp, Player.statLifeMax2);
				if (cap > 0) Player.statLife = cap;
			}
			if (TestPlayerConfig.NoKnockback) Player.velocity.X = 0f;

			DevBridge.RecordHurt("applied", info.Damage, TestPlayerConfig.HpBeforeHurt, Player.statLife);
			DevBridge.Log("hurt applied dmg=" + info.Damage + " hp=" + Player.statLife + "/" + Player.statLifeMax2
				+ " immuneTime=" + Player.immuneTime);
		}

		// 兜底：配置了 god / 锁血时，绝不让测试角色真的死掉
		public override bool PreKill(double damage, int hitDirection, bool pvp, ref bool playSound, ref bool genDust, ref PlayerDeathReason damageSource)
		{
			if (!DevBridge.Armed) return true;
			if (Player.whoAmI != Main.myPlayer) return true;
			if (!TestPlayerConfig.God && !TestPlayerConfig.LockHpOn) return true;

			DevBridge.RecordHurt("lethal-blocked", (int)damage, Player.statLife, Player.statLife);
			DevBridge.Log("death BLOCKED dmg=" + (int)damage + " (god=" + TestPlayerConfig.God + " lockhp=" + TestPlayerConfig.LockHp + ")");
			Player.statLife = Math.Max(1, Math.Min(TestPlayerConfig.LockHp > 0 ? TestPlayerConfig.LockHp : Player.statLifeMax2, Player.statLifeMax2));
			Player.immune = true;
			Player.immuneTime = 60;
			return false;
		}
	}

	public static class DevPlayer
	{
		public static bool TryExecute(string verb, string[] a)
		{
			Player p = Main.LocalPlayer;
			bool hasPlayer = p != null && Main.myPlayer >= 0 && p.active;

			switch (verb) {
				case "god":
					TestPlayerConfig.God = Arg(a, 1, "on") != "off";
					DevBridge.Log("god=" + TestPlayerConfig.God);
					return true;

				case "kb":
					TestPlayerConfig.NoKnockback = Arg(a, 1, "on") != "off";
					if (hasPlayer && TestPlayerConfig.NoKnockback) p.noKnockback = true;
					DevBridge.Log("knockbackImmune=" + TestPlayerConfig.NoKnockback);
					return true;

				case "lockhp": {
					if (a.Length > 1 && a[1].ToLowerInvariant() == "off") {
						TestPlayerConfig.LockHp = -1;
						DevBridge.Log("lockhp=off");
						return true;
					}
					int v = a.Length > 1 ? int.Parse(a[1], CultureInfo.InvariantCulture) : 1;
					if (v < 1) { DevBridge.Log("lockhp REFUSED: value must be >= 1"); return true; }
					if (!hasPlayer) { DevBridge.Log("lockhp REFUSED: no local player on this side"); return true; }
					TestPlayerConfig.LockHp = Math.Min(v, p.statLifeMax2);
					p.statLife = TestPlayerConfig.LockHp;
					DevBridge.Log("lockhp=" + TestPlayerConfig.LockHp);
					return true;
				}

				case "keepalive":
					TestPlayerConfig.KeepHpAfterHurt = Arg(a, 1, "on") != "off";
					DevBridge.Log("keepHpAfterHurt=" + TestPlayerConfig.KeepHpAfterHurt);
					return true;

				case "hp": {
					if (!hasPlayer) { DevBridge.Log("hp REFUSED: no local player on this side"); return true; }
					int v = int.Parse(a[1], CultureInfo.InvariantCulture);
					p.statLife = Math.Clamp(v, 1, p.statLifeMax2);
					DevBridge.Log("hp=" + p.statLife + "/" + p.statLifeMax2);
					return true;
				}

				case "hpmax": {
					if (!hasPlayer) { DevBridge.Log("hpmax REFUSED: no local player on this side"); return true; }
					int v = Math.Max(1, int.Parse(a[1], CultureInfo.InvariantCulture));
					p.statLifeMax = v;
					p.statLifeMax2 = v;
					if (p.statLife > v) p.statLife = v;
					DevBridge.Log("hpmax=" + p.statLifeMax2 + " hp=" + p.statLife);
					return true;
				}

				case "defense": {
					if (!hasPlayer) { DevBridge.Log("defense REFUSED: no local player on this side"); return true; }
					p.statDefense.AdditiveBonus += float.Parse(a[1], CultureInfo.InvariantCulture);
					DevBridge.Log("defense=" + p.statDefense);
					return true;
				}

				case "hurt": {
					if (!hasPlayer) { DevBridge.Log("hurt REFUSED: no local player on this side"); return true; }
					int dmg = Math.Max(1, int.Parse(a[1], CultureInfo.InvariantCulture));
					int dir = a.Length > 2 ? int.Parse(a[2], CultureInfo.InvariantCulture) : 0;
					int before = p.statLife;
					double dealt = p.Hurt(PlayerDeathReason.ByCustomReason(Terraria.Localization.NetworkText.FromLiteral("tmlkit test")), dmg, dir);
					DevBridge.Log("hurt requested=" + dmg + " dealt=" + (int)dealt + " hp " + before + " -> " + p.statLife
						+ " immuneTime=" + p.immuneTime);
					return true;
				}

				case "immune": {
					if (!hasPlayer) { DevBridge.Log("immune REFUSED: no local player on this side"); return true; }
					int frames = a.Length > 1 ? int.Parse(a[1], CultureInfo.InvariantCulture) : 60;
					p.immune = true;
					p.immuneTime = frames;
					DevBridge.Log("immuneTime=" + p.immuneTime);
					return true;
				}

				case "buff": {
					if (!hasPlayer) { DevBridge.Log("buff REFUSED: no local player on this side"); return true; }
					int id = int.Parse(a[1], CultureInfo.InvariantCulture);
					int secs = a.Length > 2 ? int.Parse(a[2], CultureInfo.InvariantCulture) : 10;
					p.AddBuff(id, secs * 60);
					DevBridge.Log("buff " + id + " for " + secs + "s");
					return true;
				}

				case "clearbuffs": {
					if (!hasPlayer) { DevBridge.Log("clearbuffs REFUSED: no local player on this side"); return true; }
					for (int i = 0; i < p.buffType.Length; i++) { p.buffType[i] = 0; p.buffTime[i] = 0; }
					DevBridge.Log("buffs cleared");
					return true;
				}

				case "playerreset":
					TestPlayerConfig.Reset();
					if (hasPlayer) p.noKnockback = false;
					DevBridge.Log("test player config reset");
					return true;

				case "state":
					DevBridge.Log(StateLine(p, hasPlayer));
					return true;

				case "check":
					return Check(a, p, hasPlayer);

				default:
					return false;
			}
		}

		static string Arg(string[] a, int i, string fallback)
		{
			if (a.Length <= i) return fallback;
			string v = a[i].ToLowerInvariant();
			if (v == "on" || v == "true" || v == "1") return "on";
			if (v == "off" || v == "false" || v == "0") return "off";
			return v;
		}

		static string StateLine(Player p, bool hasPlayer)
		{
			if (!hasPlayer) return "state: no local player (side=" + DevBridge.Side + ")";
			var sb = new StringBuilder();
			sb.Append("hp=").Append(p.statLife).Append('/').Append(p.statLifeMax2);
			sb.Append(" defense=").Append(p.statDefense);
			sb.Append(" immune=").Append(p.immune);
			sb.Append(" immuneTime=").Append(p.immuneTime);
			sb.Append(" noKnockback=").Append(p.noKnockback);
			sb.Append(" dead=").Append(p.dead);
			sb.Append(" inventory=").Append(Main.playerInventory);
			sb.Append(" mouse=").Append(Main.mouseX).Append(",").Append(Main.mouseY);
			sb.Append(" menu=").Append(Main.menuMode);
			int npcAlive = 0; foreach (NPC n in Main.npc) { if (n != null && n.active) npcAlive++; }
			sb.Append(" npc=").Append(npcAlive);
			int playersAlive = 0; foreach (Player pl in Main.player) { if (pl != null && pl.active) playersAlive++; }
			sb.Append(" players=").Append(playersAlive);
			sb.Append(" vol=").Append(Main.soundVolume);
			sb.Append(" pos=").Append((int)(p.Center.X / 16f)).Append(',').Append((int)(p.Center.Y / 16f));
			sb.Append(" | config god=").Append(TestPlayerConfig.God)
				.Append(" lockhp=").Append(TestPlayerConfig.LockHp)
				.Append(" kbImmune=").Append(TestPlayerConfig.NoKnockback)
				.Append(" keepHp=").Append(TestPlayerConfig.KeepHpAfterHurt);
			return sb.ToString();
		}

		/// <summary>check hp&gt;=40 / check alive / check npc&lt;=3，直接产出 [TEST] 行给 -Expect 收。</summary>
		static bool Check(string[] a, Player p, bool hasPlayer)
		{
			if (a.Length < 2) { DevBridge.Log("check REFUSED: usage check hp>=40 | check alive | check npc<=3"); return true; }
			string expr = a[1];
			// 名字要可预测：hp>=60 -> check_hpgte60 / hp<25 -> check_hplt25 / npc<=3 -> check_npclte3
			string name = "check_" + expr.Replace(">=", "gte").Replace("<=", "lte").Replace(">", "gt").Replace("<", "lt").Replace("=", "eq");

			if (expr == "alive" || expr == "dead") {
				if (!hasPlayer) { DevBridge.Report(name, false, "no local player"); return true; }
				bool wantAlive = expr == "alive";
				bool ok = wantAlive ? (p.active && !p.dead) : p.dead;
				DevBridge.Report(name, ok, "dead=" + p.dead + " hp=" + p.statLife);
				return true;
			}

			if (expr.StartsWith("npc")) {
				int n = Main.npc.Count(x => x.active);
				bool ok = Compare(n, expr.Substring(3), out string op, out int want);
				DevBridge.Report(name, ok, "npc=" + n + " want " + op + want);
				return true;
			}

			if (expr.StartsWith("hp")) {
				if (!hasPlayer) { DevBridge.Report(name, false, "no local player"); return true; }
				bool ok = Compare(p.statLife, expr.Substring(2), out string op, out int want);
				DevBridge.Report(name, ok, "hp=" + p.statLife + "/" + p.statLifeMax2 + " want " + op + want);
				return true;
			}

			DevBridge.Report(name, false, "unknown check target (use hp / npc / alive / dead)");
			return true;
		}

		static bool Compare(int actual, string rest, out string op, out int want)
		{
			op = "?";
			want = 0;
			string s = rest.Trim();
			int i = 0;
			while (i < s.Length && (s[i] == '<' || s[i] == '>' || s[i] == '=' || s[i] == '!')) i++;
			op = s.Substring(0, i);
			if (!int.TryParse(s.Substring(i).Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out want)) return false;
			switch (op) {
				case ">": return actual > want;
				case ">=": return actual >= want;
				case "<": return actual < want;
				case "<=": return actual <= want;
				case "=":
				case "==": return actual == want;
				case "!=": return actual != want;
				default: return false;
			}
		}
	}
}
