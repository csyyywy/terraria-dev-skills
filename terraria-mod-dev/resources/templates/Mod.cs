using Terraria.ModLoader;

namespace MyMod;

// 模组主类：类名 = 工程名（MyMod），继承 Mod。
// tML 隐式加载所有 Mod* 内容类，无需手动注册。
public class MyMod : Mod
{
    public override void Load()
    {
        // 模组加载：注册事件、初始化静态字段
    }

    public override void Unload()
    {
        // 卸载：清空静态引用（Reload 需要），避免旧数据残留
    }

    // 网络消息接收入口（见 06-netcode-sync.md）
    // public override void HandlePacket(System.IO.BinaryReader reader, int whoAmI) { }
}
