using Terraria;
using Terraria.ModLoader;

namespace MyMod;

// 聊天命令：/example item 给玩家一个 ExampleItem（测试用）
public class ExampleCommand : ModCommand
{
    public override string Command => "example";
    public override CommandType Type => CommandType.Chat;
    public override string Usage => "/example item";
    public override string Description => "Gives the ExampleItem (debug aid).";

    public override void Action(CommandCaller caller, string input, string[] args)
    {
        if (args.Length >= 1 && args[0] == "item")
        {
            caller.Player.QuickSpawnItem(caller.Player.GetSource_FromThis("example"), ModContent.ItemType<Content.Items.ExampleItem>());
        }
    }
}
