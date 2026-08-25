# terraria-dev-skills

泰拉瑞亚（tModLoader 1.4.4 / net8.0）模组开发的 Agent Skills 合集（`SKILL.md` + `resources/` 分册结构）。

> 公开版已**去除所有本机路径**，统一替换为通用占位符（见下表）。两条技能都来自真实的「归墟纪元 Voidfall」大型模组开发实战沉淀。

## 包含

| Skill | 说明 |
|---|---|
| `terraria-mod-dev` | 模组开发全流程：环境 / 工程结构 / 构建打包发布流水线 / API 速查（06 个小分册）/ 本地化 / 网络同步 / 跨模组 / 无头自动化测试 / 常见坑与实战教训 |
| `terraria-ai-textures` | AI 生成贴图管线：贴图尺寸规范与生成提示词 / 透明边缘裁剪 / 显示归一化（弹幕·增益·物品 scale）/ 备份与验收 |

## 安装

把 `terraria-mod-dev/` 与 `terraria-ai-textures/` 放入你的 agent 技能目录（如 `skills/` 或 `.dsh/skills/`），然后在 agent 技能设置中重新扫描 / 注册。技能按需由 AI 自动加载。

## 路径占位符

| 占位符 | 含义 |
|---|---|
| `<WORKSPACE>` | 模组源码工作区根目录（如 `D:\ai\mod`） |
| `<STEAM_LIB>` | Steam 游戏库根目录（如 `E:\SteamLibrary`） |
| `%USERPROFILE%` | 当前用户主目录（Windows 标准环境变量，展开为 `C:\Users\<用户>`） |
| `<TML_INSTALL>` | 你的 tModLoader 安装目录（如 `<STEAM_LIB>\steamapps\common\tModLoader`） |
| `<TML_SRC>` | tModLoader 源码 / ExampleMod 克隆目录（可选，参考 API 用） |
| `<COMFYUI_OUTPUT>` | ComfyUI 图像输出目录（terraria-ai-textures 用） |
| `TMLInstall` | 构建时环境变量：指向 tML 安装目录（`templates/MyMod.csproj` 的 `<Import>` 用它） |
| `TML_SELFTEST_DIR` | 无头测试桥接目录环境变量（`scripts/headless-test.ps1` 与 `examples/SelfTestCommand.cs` 的约定名） |

脚本（`scripts/*.ps1`）默认按**相对脚本位置**自动探测工作区与工具链；无法探测时请显式传参（`-Workspace` / `-TmlDir` / `-DotNet`）。

## 结构

```
terraria-dev-skills/
├── README.md
├── terraria-mod-dev/
│   ├── SKILL.md
│   └── resources/
│       ├── 00-quickstart.md ... 13-headless-testing.md   # 分册（04 拆成 04a..04f 六个小分册）
│       ├── examples/    # 示例代码（ExampleItem / ExampleSword / SelfTestCommand 等）
│       ├── scripts/     # build.ps1 / link-mod.ps1 / unlink-mod.ps1 / headless-test.ps1
│       └── templates/   # 工程模板（MyMod.csproj / Mod.cs / launchSettings.json / hjson / 占位贴图）
└── terraria-ai-textures/
    ├── SKILL.md
    └── resources/
        ├── 01-trim-crop.md
        ├── 02-normalize-display.md
        └── 03-texture-spec.md
```

## 许可证

内容随使用场景自由采用；若发布产物请保留本说明与出处。
