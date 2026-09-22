---
name: low-cost-routing
description: '低成本工作协议（高效率 & 低消耗至上）：一套已在真机验证的「什么活用什么工具」路由，唯一目标是不把东西塞进主模型上下文。覆盖工作区全文检索(wq)、精确检索(rg/ast-grep)、取字段(jq/yq/sqlite3/pdftotext)、命令输出结构化(jc)、中文 OCR(ocr)、中文去重/召回(bge-small-zh)、免费云端模型档(llm：智谱/OpenRouter/硅基流动/火山方舟)、校准判断(Jev)、确定性代码检查(shellcheck/ruff/shfmt)、密钥扫描(gitleaks)。Use when 要省 token / 省上下文 / 降低消耗 / 提高效率，when 决定该用本地模型、免费云端还是 Jev，when 要在代码库或文档里找东西而不想整读，when 处理截图/PDF/中文向量。Load this before pulling large files or web pages into context.'
license: MIT
metadata:
  tags: "efficiency, cost, routing, context, local-llm, ocr, search"
  category: "productivity"
---

# 低成本路由

> 通用版：不绑定任何特定 agent。shell 工具（`wq`/`ocr`/`llm`/`rg`/`jq`/…）与 skill 格式
> 在 DeepSeek Harness、WorkBuddy 等 agent 上通用；差异只在各自暴露的 MCP 工具面不同。

## 一句话原理

本机真实账本：会话成本的 **67% 是"每一步重发上下文"**，33% 是输出，
**输出单价是缓存命中输入的 200 倍**。推论只有一条：

> **让东西"根本不进上下文"，比把它"算得便宜"值钱一个数量级。**

下面这些工具的意义**不是"更便宜的模型"，是"不需要模型"**。

## 路由表（自上而下选，能用上面的就别用下面的）

| 要做什么 | 用什么 | 为什么 |
|---|---|---|
| 在工作区里找东西 | **`wq <词>`** | 本地 FTS5 索引；一条 SQL 抵一堆 `read` |
| 在已知文件里定位 / 看结构 | `rg -n` / `ast-grep` | 不整读；ast-grep 按语法树更准 |
| 取字段 | `jq`(JSON) `yq`(YAML/TOML) `sqlite3` `pdftotext` | 不整读 |
| 命令输出要结构化 | `LC_ALL=C jc <cmd> \| jq -r '<模板>'` | `jc` 单独用会**变大** |
| 图片取字 | **`ocr <图片>`** | 比把图喂进上下文小 1–2 个数量级 |
| 去重 / 聚类 / 相似召回 | `quentinz/bge-small-zh-v1.5`（Ollama） | 中文区分度 0.41；**别用 nomic** |
| 草稿 / 改写 / 摘要 / 翻译 | `llm zhipu`（或自带 `cheap_llm`），本地 `qwen2.5:1.5b` **必须带 JSON Schema** | 都免费 |
| 代码类 / 要一点真本事 | **`llm zhipu`** | 本地 1.5B 会写错且更慢 |
| 判断 / 分类 / 抽取 / 核验 / 对账 | **`jev_judge`**（MCP `typesafe-jev`） | 唯一校准概率 |
| 代码检查 / 格式化 | `shellcheck` `ruff` `shfmt` | 确定性、毫秒级 |
| 密钥扫描 | `gitleaks`（**在把 diff 读进上下文之前**） | 确定性 |
| 算术 / 排序 / 哈希 / 正则 / 文件比较 | **写代码** | 模型又贵又不可靠 |
| 多步推理 / 代码正确性 / 用户对话 / 完工声明 | **主模型自己** | 不外包 |

**选档顺序**：本地免费 → 免费云端 `llm`（默认 `zhipu`）→ `jev_judge`（付费，但判断只有它准）→ 自己。

## 怎么接上这三样

```bash
# 1) 云端免费档（OpenAI 兼容，四家）
llm --health                # 连通性
llm --quota                 # 额度（只有 openrouter 可查）
llm zhipu "把这段改成规范 commit message：修了个bug"
echo "长文本" | llm zhipu --stdin

# 2) 本地全文检索 / OCR
wq 关键词
wq --reindex ~/项目 ; wq --stats   # 建索引 / 看索引范围
ocr 截图.png                        # 中文（数据在 ~/.local/share/tessdata/）

# 3) 判断档（可选，付费）
#    如果你接了校准判断模型：优先用它的 MCP 工具；没有就用 CLI。
#    下两行是 TypeSafe Jev 的两种形态，仅作示例：
#      <agent 的 MCP 工具，如 mcp__jev__*>
#      <Jev CLI> verify '{"claims":["..."],"evidence":{"text":"..."}}'
```

密钥写入（不回显、不进 bash_history）：

```bash
setkey zhipu                              # 写到默认密钥目录
LCR_SECRETS_DIR=~/.config/low-cost-routing/secrets setkey zhipu   # 指定目录
```

## 每条路线的实测数字

| 工具 | 实测 | 关键坑 |
|---|---|---|
| `wq` | 285 文件 / 12.2 万行 / **64MB 索引** / 建索引 **5.1s** | FTS5 默认分词器**不切中文**（0 命中），必须 `trigram`；**trigram 要求查询词 ≥3 字**，1–2 字回退 LIKE（已内置） |
| `rg` vs 整读 | 21,910 字节文件 → 函数索引 **202 字节**（108×） | — |
| `jc` | `LC_ALL=C jc df \| jq -r` = **143 字节**（原始 944，6.6×） | 中文 locale 下**字段错位**，必须 `LC_ALL=C`；单独用**会变大**（944→1727） |
| `ocr` | 界面截图 1.17s 出正确中文 | 只装 `eng` 时输出乱码（`Q #FRES`）；chi_sim 在用户目录，**无需 sudo** |
| `bge-small-zh` | 48MB；**区分度 0.413** | `nomic-embed-text` 中文仅 **0.092**，几乎不区分 |
| 本地 `qwen2.5:1.5b` | 986MB；分类 1.4s | 加 **JSON Schema** 后答对且快 2–4 倍（只传 `format:"json"` 不够）；**注入检测方向是反的（17%），禁止用于安全判断** |
| `llm` 四家 | 手机号正则任务：硅基流动 0.74s 6/6、智谱 1.77s 6/6、OpenRouter 4.2s 6/6；本地 1.5B **4.12s 4/6（错）** | 见下 |
| `ark`（豆包） | 默认开思考 673–2390 token / 13.7–67.3s；**关掉后 47–66 token / 1.3–2.6s** | `llm` 已自动注入 `thinking:disabled`，`--think` 开回 |

## 免费档的额度真相

| provider | 定位 | 额度可见性 |
|---|---|---|
| `zhipu` glm-4-flash | **默认首选**，真免费 | 无计数器 |
| `openrouter` | 需特定模型时用 | **可见**：`:free` 请求 50/天 |
| `siliconflow` | 最快，但用完**静默转计费** | **查不到**（`/v1/user/info` 已废弃 410） |
| `ark` | 已关思考可用 | 查不到 |

## 判断环节（Jev）的三条铁律

1. **评分类（ordinal）必须给带描述的锚点 rubric**，禁止裸标签。
   实测：裸标签 67% / MAE 0.47 → 加锚点 **100% / MAE 0.03**（三个不同引擎都是这么修好的）。
2. **`confidence` 不是免检门闸**。实测 Jev 两次错误都是**高置信**（0.91/0.97），
   而置信最低的一次（0.49）**反而判对**。门闸是「锚点 rubric + 第二条核验路径」。
3. **不在琐事上调**。

## 两条行为规则（踩过的坑）

- **单个断言只写一件事，并注明来源**。不要把多次测量、多个事实捆成一句。
- **判"能不能连上"要看响应体，不是状态码**。实测 `models.github.ai` 对所有请求都返回字面量
  `OK`（HTTP 200），它根本不是可用的 API。

## 在新机器上装回去

```bash
bash scripts/install.sh          # 幂等；装脚本 + 中文 OCR 数据 + 本地模型；不改密钥
bash scripts/install.sh --check  # 只体检
bash scripts/install.sh --no-models   # 跳过模型拉取（省约 1GB 流量）
```

完整细节、全部原始数字、环境边界见 [`references/ROUTING-NOTES.md`](references/ROUTING-NOTES.md)。
