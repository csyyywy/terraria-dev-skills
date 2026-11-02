using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Terraria;
using Terraria.IO;
using Terraria.ModLoader;

namespace MyMod.Common.Testing
{
    /// <summary>
    /// Headless-test bridge (see resources/13-headless-testing.md).
    /// Copy this file into the mod under test, then:
    ///   - register your cases in Load() via RegisterTest("case", () => detail);
    ///   - launch through scripts/headless-test.ps1, which sets env MOD_TESTDIR
    ///     and writes commands to  <root>/in/commands.txt,
    ///     reads results from      <root>/out/results.txt  ("[TEST] case PASS|FAIL detail").
    ///
    /// Server-side rules: never rely on Main.LocalPlayer / Main.MouseWorld / rendering.
    /// Use fixed seeds inside handlers when you need deterministic randomness.
    /// </summary>
    public class SelfTestSystem : ModSystem
    {
        private static readonly Dictionary<string, Func<string>> Tests = new();
        private string? _root;
        private int _consumed;
        private int _tick;

        /// <summary>Register a test case: body returns detail on success or throws on failure.</summary>
        public static void RegisterTest(string name, Func<string> body) => Tests[name] = body;

        // 只有被 headless-test.ps1 拉起时才启用。两种变量名都认：
        // MOD_TESTDIR（技能默认）与 <ModName>_TESTDIR（按模组名自定）。
        private static string? GetRoot(Mod mod)
            => Environment.GetEnvironmentVariable("MOD_TESTDIR")
               ?? Environment.GetEnvironmentVariable(mod.Name + "_TESTDIR");

        public override bool IsLoadingEnabled(Mod mod) => !string.IsNullOrEmpty(GetRoot(mod));

        public override void Load()
        {
            _root = GetRoot(Mod);
            if (_root == null) return;
            Mod.Logger.Info("[SelfTest] bridge enabled root=" + _root + " dedServ=" + Main.dedServ);

            // ---- built-in smoke case ------------------------------------
            RegisterTest("ping", () => "pong");

            // ---- register YOUR cases here, example shape: ---------------
            // RegisterTest("currency", () =>
            // {
            //     int before = TestState.Shards;
            //     TestState.AddShards(10);
            //     if (TestState.Shards != before + 10) throw new Exception("shards mismatch");
            //     return $"before={before} after={TestState.Shards}";
            // });
        }

        // 世界载入后立刻跑一次：无头服务器**没有客户端时世界不更新**，
        // PostUpdateWorld 永远不触发（实测：结果文件一直为空）。
        public override void OnWorldLoad()
        {
            if (_root == null) return;
            try { Pump(); }
            catch { /* 保持服务器存活，错误留给下一轮 */ }
        }

        // 有客户端连入时世界才会 tick，这里作为补充轮询；无客户端时不依赖它。
        public override void PostUpdateWorld()
        {
            if (_root == null || ++_tick % 30 != 0) return;
            try { Pump(); }
            catch { /* swallow: retry next tick keeps the server alive */ }
        }

        private void Pump()
        {
            if (_root == null) return;
            var cmdFile = Path.Combine(_root, "in", "commands.txt");
            var resFile = Path.Combine(_root, "out", "results.txt");
            if (!File.Exists(cmdFile)) return;

            string[] lines;
            try { lines = File.ReadAllLines(cmdFile); }
            catch (IOException) { return; }                   // transient lock: retry next tick

            for (; _consumed < lines.Length; _consumed++)
            {
                var line = lines[_consumed].Trim();
                if (line.Length == 0) continue;

                if (line.Equals("#exit", StringComparison.OrdinalIgnoreCase))
                {
                    WorldFile.SaveWorld();                    // save, then hard-exit sandbox
                    Environment.Exit(0);
                }
                if (line.StartsWith("#")) continue;           // comment marker

                var name = line.Split(' ')[0];
                if (!Tests.TryGetValue(name, out var body))
                {
                    Emit(resFile, name, "FAIL", "no such test registered");
                    continue;
                }
                try { Emit(resFile, name, "PASS", body() ?? ""); }
                catch (Exception e)
                {
                    Emit(resFile, name, "FAIL", e.GetType().Name + ": " + e.Message);
                }
            }
        }

        private static void Emit(string file, string name, string status, string detail)
            => File.AppendAllText(file, $"[TEST] {name} {status} {detail}{Environment.NewLine}", Encoding.UTF8);
    }
}
