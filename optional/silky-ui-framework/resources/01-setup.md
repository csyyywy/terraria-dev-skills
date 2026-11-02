# 接入前置（Setup）

## 1. 前置模组声明（build.txt）

在你的模组 `build.txt` 中添加：

```txt
modReferences = SilkyUIFramework
```

SilkyUI 是前置模组，玩家的 tModLoader 需已安装 SilkyUI（Steam 创意工坊搜 "SilkyUI"）。

## 2. 克隆两个必要项目

在 `ModSources` 目录下：

```sh
git clone https://github.com/487666123/SilkyUIFramework.git
git clone https://github.com/487666123/SilkyUIAnalyzer.git
```

`SilkyUIAnalyzer` 是 XML 布局的**增量生成器**（source generator）：编译期扫描 `*.sui.xml`，生成 `InitializeComponent()` 与 `Name` 属性映射；只作 Analyzer 引用，不打包进你的模组。

## 3. csproj 引用

把两个项目加入你的解决方案，然后在**你的模组 csproj** 中添加：

```xml
<ItemGroup>
    <!-- Analyzer：生成 XML 布局代码，不参与运行时引用 -->
    <ProjectReference Include="..\SilkyUIAnalyzer\SilkyUIAnalyzer.csproj">
        <OutputItemType>Analyzer</OutputItemType>
        <ReferenceOutputAssembly>false</ReferenceOutputAssembly>
    </ProjectReference>
    <!-- 框架本体：运行时前置库 -->
    <ProjectReference Include="..\SilkyUIFramework\SilkyUIFramework.csproj"></ProjectReference>
</ItemGroup>
```

`ProjectReference` 路径相对模组项目目录，`..\` 即 `ModSources` 下的同级目录。

## 4. 官方依赖清单（框架自身用的，你不需要重复引用）

`Microsoft.Extensions.DependencyInjection 9.0.9`（DI 容器）、`Solaestas.tModLoader.ModBuilder 1.6.1`（tModLoader 构建工具链）、`SixLabors.ImageSharp 3.1.11`（GIF 解析）。

目标框架 `net8.0`，`LangVersion=preview`（源码使用 `field` 关键字、集合表达式、主构造函数等 C# preview 特性）。

## 5. 版本与分支

| 分支 | 说明 |
| --- | --- |
| `main` | Steam 创意工坊已发布版（0.3.0） |
| `preview` | 最新开发版，定期并入 main |

版本号三段式 `X.MINOR.PATCH`：X=架构重大变更，MINOR=功能，PATCH=修复。`MigrationGuide.md` 记录命名空间/类名变更，如 `0.2.25.09171`：`BasicElements`+`BasicComponents` → `Elements`，`BasicBody` → `BaseBody`。

## 6. 验证接入成功

- 构建无 Analyzer 报错。
- 游戏内模组列表能看到 SilkyUI（绿色已启用）。
- 进世界后 UI 才出现：Game UI 依赖 `SilkyUIPlayer.OnEnterWorld` 触发 `ReloadSilkyUIStacks`，停在主菜单不会初始化。
