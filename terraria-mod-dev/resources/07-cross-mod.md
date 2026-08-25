# 07. 跨模组（ModReferences / Mod.Call）

## 7.1 依赖声明（ModReferences）

在 `build.txt` 里声明对其他模组的**内部名**依赖：

```
displayName = MyMod
author = you
version = 0.1.0
modReferences = CalamityMod, ExampleLib
# 可选软依赖：weakReferences = ExampleLib（装了可联动、没装也能跑）
```

依赖模组未装时，本模组不加载（并提示）。多模组共享：用 `ModContent.Find<Mod>(name)`。

## 7.2 公共 API：Mod.Call

库模组提供 `Mod.Call(params object[] args)` 作为稳定接口，调用方不硬引用 DLL：

```csharp
// 调用方
Mod cal = ModLoader.GetMod("ExampleLib");
if (cal != null)
{
    object result = cal.Call("GetSomething", arg1, arg2);
}

// 提供方（在 Mod 类里）
public override object Call(params object[] args)
{
    if (args.Length > 0 && args[0] is string name)
    {
        switch (name)
        {
            case "GetSomething":
                return MyValue;
        }
    }
    return null;
}
```

## 7.3 可选依赖（不强制）

用 `ModLoader.GetMod()` 判空实现"装了就有联动，没装也不崩"。比硬 References 更宽容，适合增强型联动。

## 7.4 注意事项

- `Mod.Call` 是字符串协议的弱类型接口：参数/返回约定要写文档，改动要兼容旧调用。
- 硬引用其他模组 DLL（强依赖 + 编译期 API）适合深耦合；此时在 csproj 加 `<Reference>`，同时在 build.txt 写 `modReferences` 保证依赖先于本模组加载。
- 别忘了在 `Unload()` 清掉跨模组缓存引用。
