using Terraria;
using Terraria.ID;
using Terraria.ModLoader;

namespace MyMod.Content.Projectiles;

// 简单直飞弹幕，穿透 2 个敌人后消失
public class ExampleProjectile : ModProjectile
{
    public override void SetDefaults()
    {
        Projectile.width = 12;
        Projectile.height = 12;
        Projectile.friendly = true;
        Projectile.DamageType = DamageClass.Ranged;
        Projectile.penetrate = 2;
        Projectile.timeLeft = 300;
        Projectile.tileCollide = true;
        Projectile.ignoreWater = false;
        Projectile.aiStyle = ProjAIStyleID.Arrow; // 标准直飞
    }

    public override void AI()
    {
        // 拖尾粒子
        if (Main.rand.NextBool(3))
            Dust.NewDust(Projectile.position, Projectile.width, Projectile.height, DustID.Torch, Projectile.velocity.X * -0.2f, Projectile.velocity.Y * -0.2f);
    }
}
