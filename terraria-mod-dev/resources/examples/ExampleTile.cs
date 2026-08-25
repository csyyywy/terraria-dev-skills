using Microsoft.Xna.Framework;
using Terraria;
using Terraria.ID;
using Terraria.ModLoader;
using Terraria.ObjectData;

namespace MyMod.Content.Tiles;

// 简单实心方块：可采挖（MinPick 65）、发光
public class ExampleTile : ModTile
{
    public override void SetStaticDefaults()
    {
        Main.tileSolid[Type] = true;
        Main.tileBlockLight[Type] = true;
        Main.tileLighted[Type] = true;
        AddMapEntry(new Color(100, 100, 200), CreateMapEntryName());
        DustType = DustID.Stone;
        HitSound = SoundID.Tink;
        MinPick = 65;
        MineResist = 2f;

        TileObjectData.newTile.CopyFrom(TileObjectData.Style1x1);
        TileObjectData.addTile(Type);
    }

    public override void ModifyLight(int i, int j, ref float r, ref float g, ref float b)
    {
        r = 0.2f; g = 0.4f; b = 0.9f;
    }
}
