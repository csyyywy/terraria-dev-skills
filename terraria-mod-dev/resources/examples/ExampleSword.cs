using Terraria;
using Terraria.ID;
using Terraria.ModLoader;

namespace MyMod.Content.Items;

// 近战剑
public class ExampleSword : ModItem
{
    public override void SetDefaults()
    {
        Item.width = 40;
        Item.height = 40;
        Item.useStyle = ItemUseStyleID.Swing;
        Item.useTime = 25;
        Item.useAnimation = 25;
        Item.autoReuse = true;
        Item.useTurn = true;
        Item.damage = 50;
        Item.knockBack = 5f;
        Item.DamageType = DamageClass.Melee;
        Item.rare = ItemRarityID.Green;
        Item.value = Item.sellPrice(gold: 1);
        Item.UseSound = SoundID.Item1;
    }

    public override void AddRecipes()
    {
        Recipe.Create(Type)
            .AddIngredient(ItemID.IronBar, 8)
            .AddTile(TileID.Anvils)
            .Register();
    }
}
