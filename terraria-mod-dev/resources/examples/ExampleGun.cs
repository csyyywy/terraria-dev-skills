using Microsoft.Xna.Framework;
using Terraria;
using Terraria.ID;
using Terraria.ModLoader;

namespace MyMod.Content.Items;

// 远程枪：发射自定义弹幕 ExampleProjectile
public class ExampleGun : ModItem
{
    public override void SetDefaults()
    {
        Item.width = 42;
        Item.height = 18;
        Item.useStyle = ItemUseStyleID.Shoot;
        Item.useTime = 12;
        Item.useAnimation = 12;
        Item.autoReuse = true;
        Item.damage = 20;
        Item.knockBack = 3f;
        Item.DamageType = DamageClass.Ranged;
        Item.shoot = ModContent.ProjectileType<Projectiles.ExampleProjectile>();
        Item.shootSpeed = 12f;
        Item.useAmmo = AmmoID.Bullet;
        Item.noMelee = true;
        Item.rare = ItemRarityID.Blue;
        Item.value = Item.sellPrice(silver: 50);
        Item.UseSound = SoundID.Item11;
    }

    public override void AddRecipes()
    {
        Recipe.Create(Type)
            .AddIngredient(ItemID.IronBar, 10)
            .AddTile(TileID.Anvils)
            .Register();
    }
}
