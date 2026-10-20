# 07. 跨模组（ModReferences / Mod.Call）

## 7.1 依赖声明（ModReferences）

`build.txt` 里声明对其他模组的**内部名**依赖：

```text
displayName = MyMod
author = you
version = 0.1.0
modReferences = CalamityMod, ExampleLib
# 可选软依赖：weakReferences = ExampleLib（装了可联动、没装也能跑）
```

依赖未装时本模组不加载并给出提示。多模组共享用 `ModContent.Find<Mod>(name)`。

## 7.2 公共 API：Mod.Call

库模组用 `Mod.Call(params object[] args)` 提供稳定接口，调用方不必硬引用 DLL：

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

## 7.3 可选依赖

`ModLoader.GetMod()` 判空即可实现"装了联动、没装不崩"，比硬 References 宽容，适合增强型联动。

## 7.4 引用外部模组 DLL（**不要用 ProjectReference**）

依赖别人的模组时，csproj 用 `<Reference>` 指向它构建好的 DLL，不要用 `<ProjectReference>` 指向源码工程。

### 为什么 ProjectReference 会出事

`<ProjectReference Include="..\OtherMod\OtherMod.csproj" />` 会把对方工程拉进你的构建图，连带构建它的子工程，本地还会重编一个无关的库。案例（示例模组 → SilkyUIFramework → SilkyUIAnalyzer）：

- 对方的 Roslyn 分析器子工程用了 C# 14 `extension(...)` 扩展成员；
- 游戏内构建器只带 SDK 8.0.423，其 Roslyn 不认该语法，把它解析成"名为 extension 的方法" → 块内成员被当局部函数 → `CS0106: 修饰符"public"对该项无效`；
- 于是**游戏内 Build + Reload 直接失败**，而本地 9.x SDK 能编过，迷惑性强。

### 正确写法

```xml
<PropertyGroup>
  <!-- 探测依赖 DLL：先 Release、后 Debug 输出目录（游戏内构建即 ModSources 同级路径） -->
  <MyDepDll Condition="'$(MyDepDll)' == '' AND Exists('$(MSBuildProjectDirectory)\..\OtherMod\bin\Release\net8.0\OtherMod.dll')">$(MSBuildProjectDirectory)\..\OtherMod\bin\Release\net8.0\OtherMod.dll</MyDepDll>
  <MyDepDll Condition="'$(MyDepDll)' == '' AND Exists('$(MSBuildProjectDirectory)\..\OtherMod\bin\Debug\net8.0\OtherMod.dll')">$(MSBuildProjectDirectory)\..\OtherMod\bin\Debug\net8.0\OtherMod.dll</MyDepDll>
</PropertyGroup>

<ItemGroup Condition="'$(MyDepDll)' != ''">
  <!-- Private=false：不复制别人的 DLL 到输出目录，也不打进 .tmod -->
  <Reference Include="OtherMod">
    <HintPath>$(MyDepDll)</HintPath>
    <Private>false</Private>
  </Reference>
</ItemGroup>

<Target Name="CheckDepRef" BeforeTargets="Build" Condition="'$(MyDepDll)' == ''">
  <Error Text="找不到 OtherMod.dll：请先构建一次该模组，或用 -p:MyDepDll=&lt;路径&gt; 指定" />
</Target>
```

### 配套要点

- `build.txt` 的 `modReferences` 必须保留，那是**运行时**依赖声明。
- 不要把依赖 DLL 拷进自己的仓库：多数 tML 模板的 `.gitignore` 含 `*.dll`，拷了也提交不上去，换机器就构建失败。放到仓库外，用上面的探测链引用。
- 打包阶段 tML 会自动处理编译期引用：`ModCompile.cs`（tML 源码）打包时把 `modReferences` 里每个模组的程序集抽出加入编译引用。所以打包不依赖 csproj 引用，csproj 引用只是让本地 `dotnet build` 能过。（`tMLMod.targets` 只引用 `tModLoader.dll` + `Libraries/**`，不管 `modReferences`——这是本地构建必须自己加 `<Reference>` 的原因。）
- `warning MSB3277`（如 tML 的 `Microsoft.Extensions.*` 8.0.0.0 与依赖 bin 目录里的 9.0.0.0 冲突）正常且无害：MSBuild 会选 tML 那份主版本。只要 `Private=false`，那些依赖 DLL 也不会被复制进输出目录。
- 改完用游戏内构建器同款的 SDK 8.0.423 验证一次，别只测本地 9.x。

## 7.5 注意事项

- `Mod.Call` 是字符串协议的弱类型接口：参数/返回约定要写文档，改动要兼容旧调用。
- 硬引用其他模组 DLL（强依赖 + 编译期 API）适合深耦合：csproj 加 `<Reference>`，同时在 `build.txt` 写 `modReferences`，保证依赖先于本模组加载。
- 在 `Unload()` 里清掉跨模组缓存引用。
