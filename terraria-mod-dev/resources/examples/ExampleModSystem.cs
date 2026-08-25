using Terraria;
using Terraria.ID;
using Terraria.ModLoader;

namespace MyMod.Content.Systems;

// 游戏系统：注册全局配方 + 世界更新钩子
public class ExampleSystem : ModSystem
{
    // 注意：Recipe.Create 只能在 AddRecipes() 里调用（不能放在 Load()，否则抛 RecipeException）
    public override void AddRecipes()
    {
        // 给原版物品补一个配方：任何世界都能用 1 个土合成 1 个石块
        Recipe.Create(ItemID.StoneBlock)
            .AddIngredient(ItemID.DirtBlock, 1)
            .AddTile(TileID.WorkBenches)
            .Register();
    }

    public override void PostUpdateWorld()
    {
        // 每 tick 世界逻辑（注意多人只在服务端执行）
        // if (Main.netMode == NetmodeID.Server) { ... }
    }
}
