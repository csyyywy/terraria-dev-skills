using Terraria;
using Terraria.ID;
using Terraria.ModLoader;

namespace MyMod.Content.NPCs;

// 简单敌对 NPC：左右摆动 + 接触伤害
public class ExampleNPC : ModNPC
{
    public override void SetStaticDefaults()
    {
        Main.npcFrameCount[Type] = 1; // 单帧
    }

    public override void SetDefaults()
    {
        NPC.width = 30;
        NPC.height = 30;
        NPC.damage = 20;
        NPC.defense = 5;
        NPC.lifeMax = 200;
        NPC.knockBackResist = 0.5f;
        NPC.value = 500f;
        NPC.HitSound = SoundID.NPCHit1;
        NPC.DeathSound = SoundID.NPCDeath1;
    }

    public override void AI()
    {
        // 用 ai[0] 累积相位做左右摆动
        NPC.ai[0] += 0.05f;
        NPC.velocity.X = MathF.Cos(NPC.ai[0]) * 2f;
        NPC.velocity.Y = 0;
        NPC.spriteDirection = NPC.velocity.X > 0 ? 1 : -1;
    }

    // 生成：在腐化/血腥地表随机刷（简单演示，正式建议按 biomes 用 NPCSpawnHelper）
    public override float SpawnChance(NPCSpawnInfo spawnInfo)
    {
        if (spawnInfo.Player.ZoneCrimson || spawnInfo.Player.ZoneCorrupt)
            return 0.5f;
        return 0f;
    }
}
