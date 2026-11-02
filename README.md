# terraria-dev-skills

tModLoader 1.4.4（游戏 1.4.4 / net8.0）模组开发的 Agent Skills 合集。每个技能是 `SKILL.md` + `resources/` 分册，
可直接放进 agent 的技能目录（如 `.dsh/skills/`）按需加载。

## 技能

| 技能 | 用途 |
|---|---|
| `terraria-mod-dev` | 开发入口：环境与工程结构、构建 / 调试 / 发布、API 速查（6 个分册）、本地化、网络同步、跨模组、排错 |
| `terraria-headless-test` | 自动化自测：热会话（单条约 1s）、无窗口真实世界、真帧截图与免焦点 UI 操作、批量 suite、并行 lab |
| `silky-ui-framework` | SilkyUI 框架：接入、XML 布局、Flexbox、定位与 Bounds、控件、事件、数据绑定、渲染、动画 |
| `terraria-mod-ui` | 原生 UI 与绘制：批次与坐标系、绘制钩子、角色画像、血条与标签、控件坑、探针方法 |
| `terraria-ai-textures` | AI 贴图管线：尺寸规范与提示词 → 透明边缘裁剪 → 显示归一化 → 替换与验收 |

## 安装

把需要的技能目录放进 agent 的技能目录，重新扫描即可。技能自带 `description` / `whenToUse`，由 agent 按任务匹配加载。

```
.dsh/skills/
├── terraria-mod-dev/
├── terraria-headless-test/
├── silky-ui-framework/
├── terraria-mod-ui/
└── terraria-ai-textures/
```

## 占位符

文档不写死本机路径，统一使用下列占位符。

| 占位符 | 含义 |
|---|---|
| `<TML_DIR>` | tModLoader 安装目录（Steam 库下 `steamapps\common\tModLoader`） |
| `<TML_SRC>` | tModLoader 源码 / ExampleMod 检出目录（对照 API 用，可选） |
| `<WORKSPACE>` | 模组工作区根目录 |
| `<KIT>` | 技能目录本身（放 bridge / 脚本的位置） |
| `<ModName>` | 模组工程名 |
| `<LAB>` | 一轮测试的隔离沙盒目录 |
| `%USERPROFILE%` | Windows 用户目录（PowerShell 写作 `$env:USERPROFILE`） |

## 脚本

以下脚本均已参数化，不含机器专属路径。

| 脚本 | 作用 | 关键参数 |
|---|---|---|
| `terraria-mod-dev/resources/scripts/build.ps1` | 构建，可只编译不打包 | `-ProjectPath` `-Config` `-SkipPack` |
| `…/link-mod.ps1` / `unlink-mod.ps1` | 把工程 junction 进 `ModSources` / 移除 | `-ModName` `-Workspace` |
| `…/check-hjson.ps1` | 用真实 Hjson 解析器校验本地化 | `-Dir` `-DotNet` |
| `terraria-mod-dev/resources/scripts/headless-test.ps1` | 构建验证 / 无头服务器用例：`-Mode Validate\|Server`，桥自证就绪 | `-ModName` `-ProjectPath` `-TmlDir` `-ExpectCases` `-PlanOnly` |
| `terraria-headless-test/resources/scripts/preflight-client.ps1` | L2 前 40 秒体检：能否走到 `Finding Mods` | `-TmlDir` `-WaitSec` |
| `terraria-headless-test/resources/scripts/tml.ps1` | 起一轮（或 `-Detach` 起常驻会话）并跑命令 | `-Lab` `-Tmod` `-TmlDir` `-Client` `-Detach` `-Commands` `-Expect` |
| `terraria-headless-test/resources/scripts/session.ps1` | 热会话：Run / Suite / Status / Stop（单条约 1s） | `-Action` `-Lab` `-Commands` `-ExpectLog` `-Recipe` `-Suite` |
| `terraria-headless-test/resources/scripts/suites.ps1` | 并行跑多个 suite（独立 lab + 端口） | `-Suite` `-Parallel` `-ModName` `-Tmod` `-TmlDir` |
| `terraria-headless-test/resources/scripts/boot-log.ps1` | 读启动日志（不依赖模组）：里程碑 / 错误 / 跟踪 | `-Lab` `-Side` `-Only` `-Tail` `-Follow` |
| `terraria-headless-test/resources/scripts/win-ui.ps1` | 桥不可用时的桌面兜底：截窗口 / 点击 / 发键 | `-Action List\|Shot\|Click\|Key` `-Title` `-Out` `-X` `-Y` `-Keys` |

## 目录结构

```
terraria-dev-skills/
├── terraria-mod-dev/
│   ├── SKILL.md
│   └── resources/
│       ├── 00-quickstart.md … 13-headless-testing.md   # 04 拆为 04a–04f
│       ├── examples/    # 示例内容类与自检系统
│       ├── scripts/     # 构建 / 链接 / hjson 校验 / 无头测试
│       └── templates/   # 工程模板
├── terraria-headless-test/
│   ├── SKILL.md
│   └── resources/
│       ├── 01-architecture.md … 06-verification.md
│       ├── bridge/      # 可 vendored 的 C# 桥（文件桥 / 截帧 / 假连接 / 测试角色）
│       └── scripts/tml.ps1
├── silky-ui-framework/
├── terraria-mod-ui/
└── terraria-ai-textures/
```

## 说明

- 内容来自真实模组开发实践，已去除本机路径、内部代号与私有联系方式；示例中的模组名、类名、物品名均为占位。
- 基线：tModLoader 1.4.4（2026.06+ stable）。API 签名以[官方文档](https://docs.tmodloader.net/docs/stable/)与本地源码为准。
- SilkyUI 说明以上游仓库为准：<https://github.com/487666123/SilkyUIFramework>

---

## 开源与发布

- 代码许可：MIT（见 [LICENSE](LICENSE)）
- 第三方依赖与出处：见 [NOTICE.md](NOTICE.md)（tModLoader / Terraria / SilkyUI 等，仓库不含任何游戏素材）
- 导出可公开副本（会做本机路径与标识检查）：

```powershell
pwsh -File tools/export-oss.ps1 -Out <目标目录> -Init          # 生成独立仓库并首次提交
pwsh -File tools/export-oss.ps1 -Out <目标目录> -Init -Remote git@github.com:<你>/<仓库>.git
```

导出脚本只复制技能内容 + LICENSE/NOTICE/README，**不会**带上父仓库里的个人项目与历史。

---

## 可选包（默认不加载）

DSH 只扫描 `skills/` 下一层的 `SKILL.md`。放在 `skills/optional/` 里的技能**不进入技能目录**，
模型不会自动选中它们；需要时显式启用：

```powershell
pwsh -File tools/skill-pack.ps1 -List                              # 看哪些启用/收起
pwsh -File tools/skill-pack.ps1 -Name silky-ui-framework -Enable    # 启用
pwsh -File tools/skill-pack.ps1 -Name silky-ui-framework -Disable   # 收起
```

| 可选包 | 什么时候启用 |
|---|---|
| `silky-ui-framework` | 用户明确提到 SilkyUI / 项目已引用该框架。**默认 UI 方案是 `terraria-mod-ui` 的原生 UI** |

已收起的技能即使被 `skill` 工具点名也取不到（这是刻意的隔离）。
