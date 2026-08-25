using Terraria;
using Terraria.ID;
using Terraria.ModLoader;

namespace MyMod.Content.Items;

// 最小物品：可堆叠消耗品，工作台合成
public class ExampleItem : ModItem
{
    public override void SetDefaults()
    {
        Item.width = 20;
        Item.height = 20;
        Item.maxStack = 999;
        Item.value = 100;
        Item.rare = ItemRarityID.Blue;
        Item.useStyle = ItemUseStyleID.Swing;
        Item.useTime = 20;
        Item.useAnimation = 20;
        Item.autoReuse = true;
        Item.consumable = true;
    }

    public override void AddRecipes()
    {
        Recipe.Create(Type)
            .AddIngredient(ItemID.Wood, 1)
            .AddIngredient(ItemID.StoneBlock, 1)
            .AddTile(TileID.WorkBenches)
            .Register();
    }
}
