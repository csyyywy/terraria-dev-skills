# terraria-dev-skills

Terraria（tModLoader 1.4.4 / net8.0）模组开发的 Agent Skills 合集，采用 `SKILL.md` + `resources/` 分册结构，可直接放入 agent 的技能目录（如 `.dsh/skills/`）按需加载。

## 包含的技能

| 技能 | 用途 |
|---|---|
| `terraria-mod-dev` | 模组开发入口：环境与工程结构、构建 / 调试 / 发布流水线、tModLoader API 速查（6 个分册）、本地化、网络同步、跨模组互操作、无头服务器自动化测试、常见错误排查 |
| `silky-ui-framework` | SilkyUIFramework（SilkyUI）UI 框架：前置接入、注册与生命周期、XML 声明式布局、Flexbox 引擎、定位与三套 Bounds、内置控件、事件与输入、数据绑定、渲染管线、动画 |
| `terraria-mod-ui` | 原生 UI 与绘制经验：绘制批次与坐标系、绘制钩子选型（1.4.4 `PostDraw` 不触发）、角色画像渲染、血条与头顶标签、布局控件坑、探针调试方法论 |
| `terraria-ai-textures` | AI 生成贴图管线：尺寸规范与提示词（CSV）→ 透明边缘裁剪 → 显示归一化（弹幕 / 增益 / 物品手持）→ 替换与验收 |

## 安装

把需要的技能目录（例如 `terraria-mod-dev/`）放入 agent 的技能目录，然后重新扫描 / 注册技能。技能自带 `description` / `whenToUse`，由 agent 按任务自动匹配加载。

```
.dsh/skills/
├── terraria-mod-dev/
├── silky-ui-framework/
├── terraria-mod-ui/
└── terraria-ai-textures/
```

## 路径占位符

文档中不写死任何本机路径，统一使用下列占位符。

| 占位符 | 含义 |
|---|---|
| `<TML_DIR>` | tModLoader 安装目录（Steam 库下 `steamapps\common\tModLoader`） |
| `<TML_SRC>` | tModLoader 源码 / ExampleMod 检出目录（对照 API 用，可选） |
| `<WORKSPACE>` | 模组源码工作区根目录 |
| `<ModName>` | 模组工程名 |
| `%USERPROFILE%` | Windows 用户目录（PowerShell 中写 `$env:USERPROFILE`） |
| `$(TMLDir)` | csproj 中导入 `tMLMod.targets` 的 MSBuild 属性；构建时传 `-p:TMLDir="<TML_DIR>"` |
| `MOD_TESTDIR` | 无头测试的指令桥根目录（环境变量，由 `headless-test.ps1` 注入） |

## 脚本

`terraria-mod-dev/resources/scripts/` 下的脚本均已参数化，不再依赖机器专属路径：

| 脚本 | 作用 | 关键参数 |
|---|---|---|
| `build.ps1` | 用带 SDK 的 dotnet 构建，可只编译不打包 | `-ProjectPath` `-Config` `-SkipPack` |
| `link-mod.ps1` | 把工程以 junction 链接进 `ModSources` | `-ModName` `-Workspace` `-TerrariaDocs` |
| `unlink-mod.ps1` | 移除该 junction（不删源码） | `-ModName` `-TerrariaDocs` |
| `check-hjson.ps1` | 用真实 Hjson 解析器校验本地化文件 | `-Dir` `-DotNet` |
| `headless-test.ps1` | 构建验证 / 无头服务器自检 | `-ProjectPath` `-ModName` `-TmlDir` `-ValidateOnly` `-BuildProps` |

## 目录结构

```
terraria-dev-skills/
├── terraria-mod-dev/
│   ├── SKILL.md
│   └── resources/
│       ├── 00-quickstart.md … 13-headless-testing.md   # 04 拆为 04a–04f 六个分册
│       ├── examples/    # 示例内容类与无头自检系统
│       ├── scripts/     # 构建 / 链接 / hjson 校验 / 无头测试
│       └── templates/   # 工程模板（csproj / 主类 / launchSettings / hjson / 占位贴图）
├── silky-ui-framework/
│   ├── SKILL.md
│   └── resources/       # 01-setup … 11-troubleshooting
├── terraria-mod-ui/
│   ├── SKILL.md
│   └── resources/       # 01-coordinates-batches … 06-text-labels
└── terraria-ai-textures/
    ├── SKILL.md
    └── resources/       # 01-trim-crop / 02-normalize-display / 03-texture-spec
```

## 说明

- 内容来自真实模组开发实践，已去除本机路径、内部项目代号与私有联系方式；示例中的模组名、类名、物品名均为通用占位。
- 基线版本：tModLoader 1.4.4（2026.06 stable）。API 签名与行为以 [官方文档](https://docs.tmodloader.net/docs/stable/) 与你本地的 tModLoader 源码为准。
- 第三方框架 SilkyUI 的说明以其上游仓库为准：https://github.com/487666123/SilkyUIFramework
