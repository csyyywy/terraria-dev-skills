using Terraria;
using Terraria.ModLoader;

namespace MyMod.Content.Players;

// 玩家扩展：自定义状态字段 + 钩子
public class ExamplePlayer : ModPlayer
{
    public int Hits; // 命中计数（示例字段）

    // 命中钩子（本版本无 ModPlayer.OnKillNPC；统计"击杀"请用 GlobalNPC.OnKill + NPC.lastInteraction）
    public override void OnHitNPC(NPC target, NPC.HitInfo hit, int damageDone)
    {
        if (!target.friendly)
            Hits++;
    }

    public override void UpdateEquips()
    {
        // 每 tick：饰品/装备效果（ModItem.UpdateAccessory 更常用）
    }

    public override void ResetEffects()
    {
        // 每 tick 清空一次性加成
    }
}
// 使用：player.GetModPlayer<ExamplePlayer>().Hits
