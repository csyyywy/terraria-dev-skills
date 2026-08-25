# 04d. API 速查 · 贴图 Autoload / 城镇 NPC

> 属 04 分册家族（原 §4.15–4.16）；索引与通用原则见 `04-api-cheatsheet.md`。

## 4.15 贴图自动加载（官方 Autoload 规则，必读）

- **Items/Projectiles/NPC 必须有同名贴图**，缺一个模组就无法加载（MissingResourceException）。
- 贴图路径 = 工程根 + 命名空间（`.` → `\`）+ 类名 + `.png`；.cs 与同名 .png 同目录即可。
- 特殊贴图：饰品 `[AutoloadEquip(EquipType.X)]` → `_Back`/`_Shield` 等；城镇NPC/Boss `[AutoloadHead]`/`[AutoloadBossHead]` → `_Head`/`_Head_Boss`；发光图 `_Glow`。
- 详见 `10-official-reference.md` 与 wiki `Basic-Autoload`、`Basic-glowmask-guide`。

## 4.16 城镇 NPC（tML 1.4.4 官方模式，2026-08 对照 ExamplePerson 验证）

关键：类上加 [AutoloadHead]（自动加载 Content/NPCs/类名_Head.png），SetDefaults 设 NPC.townNPC=true。

    [AutoloadHead]
    public class MyTownNpc : ModNPC
    {
        public const string ShopName = "Shop";
        private static Profiles.DefaultNPCProfile? NPCProfile; // Terraria.GameContent.Profiles

        public override void SetStaticDefaults()
        {
            Main.npcFrameCount[Type] = 25;                       // 主体贴图 40 宽 x 25帧x56 高 = 40x1400
            NPCID.Sets.ExtraFramesCount[Type] = 9;
            NPCID.Sets.AttackFrameCount[Type] = 4;
            NPCID.Sets.DangerDetectRange[Type] = 700;
            NPCID.Sets.AttackType[Type] = 3;                     // 0扔/1射/2魔/3近战
            NPCID.Sets.AttackTime[Type] = 90;
            NPCID.Sets.AttackAverageChance[Type] = 30;
            NPCID.Sets.HatOffsetY[Type] = 4;
            NPC.Happiness.SetBiomeAffection<MyBiome>(AffectionLevel.Like).SetNPCAffection(NPCID.Guide, AffectionLevel.Like);
            NPCProfile = new Profiles.DefaultNPCProfile(Texture, NPCHeadLoader.GetHeadSlot(HeadTexture), null); // party=null 安全
        }

        public override void SetDefaults()
        {
            NPC.townNPC = true; NPC.friendly = true;
            NPC.width = 18; NPC.height = 40;
            NPC.aiStyle = NPCAIStyleID.Passive;
            NPC.damage = 10; NPC.defense = 15; NPC.lifeMax = 250;
            NPC.HitSound = SoundID.NPCHit1; NPC.DeathSound = SoundID.NPCDeath1;
            NPC.knockBackResist = 0.5f;
            AnimationType = NPCID.Guide;                         // 复用向导动画
        }

        public override ITownNPCProfile TownNPCProfile() => NPCProfile!;

        // 入住条件（单参 int numTownNPCs！）：返回永久旗标即可支持死亡后再入住
        public override bool CanTownNPCSpawn(int numTownNPCs) => MySystem.DownedBoss;
        // 或遍历 Main.ActivePlayers + player.HasItem(...)

        public override List<string> SetNPCNameList() => new() { "甲", "乙" };
        public override string GetChat() => this.GetLocalization("Chat1").Value; // 键 Mods.X.NPCs.类名.Chat1
        public override void SetChatButtons(ref string button, ref string button2) { button = Language.GetTextValue("LegacyInterface.28"); }
        public override void OnChatButtonClicked(bool firstButton, ref string shop) { if (firstButton) shop = ShopName; }

        // 商店：SetupShop 已移除 → AddShops + NPCShop
        public override void AddShops()
        {
            var npcShop = new NPCShop(Type, ShopName).Add<MyItem>();
            npcShop.Register();
        }
        // 可选自卫：TownNPCAttackStrength/Cooldown/Proj/ProjSpeed
    }

- 本地化键：`Mods.<Mod>.NPCs.<类名>.DisplayName`（类型名）、`.Chat1..N`（对话）、`Mods.<Mod>.Items.<X>.DisplayName` 等。
- 对话文案与中文名写进 **en-US.hjson**（游戏语言是英文时 tML 加载 en-US）。
- 无头服务器不校验 `_Head.png` 与 `_Highlight.png`（客户端专属），只能真机 Reload 验证。
- 相关家具：箱 = Style2x2+CoordinateHeights[16,18]+Hook Chest.FindEmptyChest/AfterPlacement_Hook+StyleHorizontal；床 = Style4x2+CoordinatePaddingFix(0,-2)+CanBeSleptIn；灯/烛台 = Style1x2/Style2x2+Main.tileLighted+ModifyLight。
