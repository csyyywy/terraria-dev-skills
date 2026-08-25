using Terraria;
using Terraria.ID;
using Terraria.ModLoader;

namespace MyMod.Content.Buffs;

// 增益：提升 10% 伤害
public class ExampleBuff : ModBuff
{
    public override void SetStaticDefaults()
    {
        Main.debuff[Type] = false;
        Main.buffNoTimeDisplay[Type] = false;
    }

    public override void Update(Player player, ref int buffIndex)
    {
        player.GetDamage(DamageClass.Generic) += 0.1f;
    }
}
