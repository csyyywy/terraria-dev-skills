# Tier 0（terrex 纯协议客户端）可行性 spike

日期：2026-11-02　环境：Windows / Python 3.14.6（miniconda 基座）/ terrex 2.0.1

## 结论

**不采用。** 两个独立原因，任何一个都足以否决：

1. **发布的 wheel 结构是坏的**（实测）。
   - `pip install terrex` 成功，版本 2.0.1；
   - 但它把包内容**平铺到 site-packages 顶层**（`net/`、`entity/`、`event/`、`id/`、`item/`、`packet/`、`player/`、`world/`、`util/`），
     `RECORD` 里 **0 个 `terrex/` 条目**；
   - 而它自己的模块内部用 `from terrex.event.manager import ...` 导入自己 → 运行即 `ModuleNotFoundError: No module named 'terrex'`；
   - 顶层还占用了 `id`、`item`、`net` 这类高危名字，装进主环境会污染其他项目。
2. **协议层面不匹配本项目**（读源码/README）。
   - terrex 是**原版 Terraria 协议**客户端（源自 TerraBot）；
   - tModLoader 服务器在加入阶段要求交换 mod 列表，客户端必须是 tML；
   - 本项目实测反证：客户端缺 `.tmod` 时会走"从服务器下载 mod → 连接丢失"。

## 实测记录

```
$ python -m venv .venv-terrex && ./.venv-terrex/Scripts/python.exe -m pip install terrex
Requirement already satisfied: terrex in .venv-terrex\Lib\site-packages (2.0.1)

$ .../python.exe -c "import terrex"
ModuleNotFoundError: No module named 'terrex'

$ .../python.exe -c "import net"
net ok                     # 顶层模块能导入，但内部再 import terrex 就炸

$ grep -c '^terrex/' .../terrex-2.0.1.dist-info/RECORD
0

$ ls -d site-packages/*/ | basename
entity event id item localization net numpy packet pip player util world
```

（另：官方 PyPI 直连可用但清华镜像返回 403；这不影响结论。）

## 价值评估（即使包是好的）

| 场景 | 能否替代现有方案 |
|---|---|
| 服务端逻辑断言（L1） | 不能。L1 用进程内假连接，0.6s/条，无需实现协议 |
| UI / 截图（L2） | 不能。协议客户端没有渲染 |
| 真实封包路径 / 多客户端并发 | 唯一独有价值，但与当前"UI 回归"痛点不重合 |

## 决定

- 不引入 terrex，也不自研协议客户端（成本远超收益，且需跟 tML 的 mod 握手与版本演进）；
- 维持 **L1（假连接）+ L2（真客户端）** 双层结构；
- 若未来出现"网络同步类缺陷"需求，再单独立项评估"用 tML 自身程序集实现最小协议客户端"，并在那时重新审视上游是否修好打包。

## 复现命令

```powershell
python -m venv .venv-terrex
.\.venv-terrex\Scripts\python.exe -m pip install terrex
.\.venv-terrex\Scripts\python.exe -c "import terrex"     # 预期 ModuleNotFoundError
```
