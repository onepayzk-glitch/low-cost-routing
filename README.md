# low-cost-routing

> **Build AI agents that stop paying to think about things they could just look up.**
> A verified "which tool for which job" routing protocol whose single goal is keeping
> content **out of the model's context window**. Ships an installable agent skill plus
> four standalone CLI tools.
>
> 一套已在真机验证的「什么活用什么工具」路由协议，唯一目标是**不把东西塞进主模型上下文**。
> 附四个独立 CLI 工具，可作为 agent skill 安装。

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](#license)

---

## 为什么（不是理论，是账本）

在本机量出来的真实会话数据：

- **67% 的会话成本是"每一步重发上下文"**
- 33% 是输出，而**输出单价是缓存命中输入的 200 倍**

推论只有一条：

> **让东西"根本不进上下文"，比把它"算得便宜"值钱一个数量级。**

所以这套东西的意义**不是"更便宜的模型"，是"不需要模型"**。

## 实测收益（同一台机器，可复现）

| 做法 | 结果 |
|---|---|
| 整读一个 21,910 字节的源文件 | vs **`rg` 取函数索引 202 字节** → 省 108× |
| 读 69,910 字节的 JSON | vs **`jq` 取一个字段 ≈ 60 字节** |
| 原始 `df` 944 字节 | vs **`LC_ALL=C jc df \| jq -r` 143 字节** → 小 6.6× |
| 把界面截图喂给模型 | vs **`ocr` 出的纯文本** → 小 1–2 个数量级，且 $0 |
| 中文去重（1000 条） | 本地 embedding，**1225 对比较 163ms**，$0 |
| 建工作区全文索引 | 314 文件 / 12.8 万行 → **63 MB**，**5 秒** |

## 快速开始

```bash
git clone <this-repo> && cd low-cost-routing
bash scripts/install.sh          # 装脚本 + 中文 OCR 数据 + 本地模型
bash scripts/install.sh --check  # 只体检，不改动任何东西
```

装完**只剩一件事要手动做——写 API key**（脚本永远不碰密钥）：

```bash
setkey zhipu        # 然后 openrouter / siliconflow / ark
```

`setkey` 用 `read -rs` 读输入：**不回显、不出现在命令行、不进 bash_history**。

## 包内容

```
low-cost-routing/
├── SKILL.md                  agent skill 主体（路由表 + 铁律 + 实测数字）
├── scripts/
│   ├── install.sh            幂等安装/体检；不碰密钥
│   ├── wq                    工作区全文检索（SQLite FTS5 + trigram 分词）
│   ├── llm                   四家免费云端档统一入口（OpenAI 兼容）
│   ├── ocr                   中文 OCR（tesseract + chi_sim，用户目录，无需 sudo）
│   └── setkey                密钥写入（不回显 / 不进 history）
└── references/
    └── ROUTING-NOTES.md      全部原始实测数字、坑、降级链、环境边界
```

## 路由表

| 要做什么 | 用什么 |
|---|---|
| 在工作区里找东西 | **`wq <词>`** |
| 在已知文件里定位 / 看结构 | `rg -n` / `ast-grep` |
| 取字段 | `jq` / `yq` / `sqlite3` / `pdftotext` |
| 命令输出要结构化 | `LC_ALL=C jc <cmd> \| jq -r '<模板>'` |
| 图片取字 | **`ocr <图片>`** |
| 去重 / 聚类 / 相似召回 | 本地 embedding（如 `bge-small-zh`） |
| 草稿 / 改写 / 摘要 / 翻译 | 免费云端 `llm`，或本地小模型 |
| 代码类 / 要一点真本事 | **免费云端 `llm`**（本地 1.5B 会写错） |
| 判断 / 分类 / 抽取 / 核验 | 校准判断模型（如 TypeSafe Jev） |
| 代码检查 / 格式化 | `shellcheck` / `ruff` / `shfmt` |
| 密钥扫描 | `gitleaks`（**在把 diff 读进上下文之前**） |
| 算术 / 排序 / 哈希 / 正则 / 文件比较 | **写代码** |
| 多步推理 / 代码正确性 / 完工声明 | **主模型自己** |

## 作为 agent skill 安装

| Agent | 位置 |
|---|---|
| DeepSeek Harness | `cp -r low-cost-routing ~/.dsh/skills/` |
| WorkBuddy | `cp -r low-cost-routing ~/.workbuddy/skills/` |
| 其它（读 `~/.claude/skills` 之类） | `cp -r low-cost-routing <该 agent 的 skills 目录>/` |

skill 格式是通用的：`SKILL.md` + YAML frontmatter（`name` / `description`），
可选 `scripts/` 与 `references/` 子目录。

## CLI 工具

```bash
# wq —— 工作区全文检索（一条 SQL 替代"读一堆文件"）
wq 关键词                 # 中文查询 ≥3 字走 MATCH，1–2 字自动回退 LIKE
wq --reindex ~/项目        # 重建（默认当前目录；也可 $WQ_ROOTS，冒号分隔）
wq --stats                # 看索引了多少、索引的哪些目录

# llm —— 四家免费云端档
llm list ; llm --health ; llm --quota
llm zhipu "把这段改成规范 commit message：修了个bug"
echo "长文本" | llm siliconflow --stdin

# ocr —— 中文 OCR
ocr 截图.png

# setkey —— 写密钥
setkey zhipu
```

密钥搜索顺序：`$LCR_SECRETS_DIR` → `$XDG_CONFIG_HOME/low-cost-routing/secrets`
→ `~/.dsh/secrets` → `~/.workbuddy/secrets`。

## 前置依赖

**必需**：`python3`（3.10+）、`rg`、`jq`、`sqlite3`、`curl`、`tesseract`
**推荐**：`fd` `yq` `jc` `ast-grep` `shellcheck` `ruff` `shfmt` `gitleaks` `zbarimg` `ffmpeg` `pdftotext` `ollama`

免 sudo 装那批 CLI（有 [mise](https://mise.jdx.dev/) 的话）：`mise use -g yq jc`

## 已知的坑（都写进脚本了，但值得知道）

- **SQLite FTS5 默认分词器不切中文**，任何中文查询 0 命中 → 必须 `tokenize='trigram'`，
  而 trigram **要求查询词 ≥3 字符**。
- **FTS5 的 DELETE 不回收空间**：不加 `VACUUM`，索引会越重建越大（实测 64MB → 131MB）。
- **`jc` 在非英文 locale 下字段错位** → 必须 `LC_ALL=C`；而且它**单独用会让输出变大**。
- **`gitleaks --version` 输出是坏的**，别拿它判断是否可用。
- **判断模型的 `confidence` 不能当免检门闸**：实测两次错误都是高置信（0.91/0.97），
  置信最低的一次反而判对。
- **评分类（ordinal）必须给带描述的锚点 rubric**：裸标签实测 67%，加锚点 100%。

## 安全

- 仓库内**不含任何密钥**；`install.sh` 只检查密钥是否存在，**永远不写**。
- `.gitignore` 已排除 `secrets/` `*_api_key` `*.env` `*.db`。
- 提交前建议自查：`gitleaks dir . --no-banner`

### 已知的扫描误报（不是泄漏）

仓库里会出现一处 `AKIAIOSFODNN7EXAMPLE`，出现在本文件与
[`references/ROUTING-NOTES.md`](references/ROUTING-NOTES.md)。

它是 **AWS 官方文档里的占位示例 key**，用来演示一个坑：
`gitleaks` 对它有内置白名单，**扫不到是正常的**，不代表工具坏了。
它不是凭据，也无法用于任何 AWS 账户。任何扫描器对它报警都属于误报。

如果你克隆后跑扫描看到它，可以放心忽略。

## License

MIT，见 [LICENSE](LICENSE)。
