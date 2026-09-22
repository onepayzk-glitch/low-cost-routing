#!/usr/bin/env bash
# install.sh —— 在新机器（或重装后）把「低成本路由」这套工具装回去。
#
# 设计原则：**幂等**（跑几遍都一样）、**不碰你的密钥**、**不用 sudo**。
# 它只装工具链；API key 永远要你自己用 `setkey <provider>` 写。
#
# 用法：
#   bash install.sh              # 装工具链 + 拉本地模型
#   bash install.sh --no-models  # 只装脚本和 OCR，不拉模型（省 1GB 流量）
#   bash install.sh --check      # 只体检，不改动任何东西
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${HOME}/.local/bin"
TESS="${HOME}/.local/share/tessdata"
NO_MODELS=0; CHECK=0
for a in "$@"; do
  case "$a" in --no-models) NO_MODELS=1 ;; --check) CHECK=1 ;; esac
done

ok()   { printf '  ✅ %s\n' "$1"; }
warn() { printf '  ⚠️  %s\n' "$1"; }
bad()  { printf '  ❌ %s\n' "$1"; }
head_() { printf '\n== %s ==\n' "$1"; }

head_ "1/5 把脚本放进 ~/.local/bin"
mkdir -p "$BIN"
for f in wq ocr llm setkey; do
  if [ "$CHECK" = 1 ]; then
    [ -x "$BIN/$f" ] && ok "$f 已就位" || warn "$f 缺失"
    continue
  fi
  install -m 755 "$HERE/$f" "$BIN/$f" && ok "$f → $BIN/$f"
done
case ":$PATH:" in
  *":$BIN:"*) ok "~/.local/bin 在 PATH 里" ;;
  *) warn "~/.local/bin 不在 PATH —— 加到你的 shell rc：export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

head_ "2/5 基础依赖"
for c in python3 rg jq sqlite3 curl; do
  command -v "$c" >/dev/null && ok "$c" || bad "$c 缺失（必需）"
done
for c in fd yq jc ast-grep shellcheck ruff shfmt gitleaks zbarimg ffmpeg pdftotext; do
  command -v "$c" >/dev/null && ok "$c" || warn "$c 缺失（可选；yq/jc 可用 mise use -g yq jc 免 sudo 装）"
done
command -v ollama >/dev/null && ok "ollama" || warn "ollama 缺失（本地模型档不可用；云端 llm 仍可用）"

head_ "3/5 中文 OCR（用户目录，不需要 sudo）"
if [ -f "$TESS/chi_sim.traineddata" ]; then
  ok "chi_sim 已装"
elif [ "$CHECK" = 1 ]; then
  warn "chi_sim 缺失"
else
  mkdir -p "$TESS"
  for src in /usr/share/tessdata/eng.traineddata /usr/share/tessdata/osd.traineddata; do
    [ -f "$src" ] && cp -n "$src" "$TESS/" 2>/dev/null
  done
  url="https://cdn.jsdelivr.net/gh/tesseract-ocr/tessdata_fast@main/chi_sim.traineddata"
  if curl -sSL --max-time 120 -o "$TESS/chi_sim.traineddata" "$url"; then
    ok "chi_sim 已下载（$(stat -c %s "$TESS/chi_sim.traineddata") 字节）"
  else
    bad "chi_sim 下载失败；手动：curl -sSL -o $TESS/chi_sim.traineddata $url"
  fi
fi

head_ "4/5 本地模型"
if ! command -v ollama >/dev/null; then
  warn "没有 ollama，跳过"
elif [ "$NO_MODELS" = 1 ]; then
  warn "--no-models：跳过（云端 llm 不受影响）"
elif [ "$CHECK" = 1 ]; then
  ollama list 2>/dev/null | grep -q 'bge-small-zh' && ok "bge-small-zh 已拉" || warn "bge-small-zh 未拉"
  ollama list 2>/dev/null | grep -q 'qwen2.5:1.5b' && ok "qwen2.5:1.5b 已拉" || warn "qwen2.5:1.5b 未拉"
else
  for m in "quentinz/bge-small-zh-v1.5" "qwen2.5:1.5b"; do
    if ollama list 2>/dev/null | grep -q "${m##*/}"; then ok "$m 已在"; continue; fi
    printf '  拉取 %s …\n' "$m"
    ollama pull "$m" >/dev/null 2>&1 && ok "$m" || bad "$m 拉取失败"
  done
fi

head_ "5/5 需要你手动做的（脚本不会碰密钥）"
# 密钥目录搜索顺序与 `llm` 保持一致
SEC_DIRS="$HOME/.config/low-cost-routing/secrets $HOME/.dsh/secrets $HOME/.workbuddy/secrets"
have() {
  for d in $SEC_DIRS; do [ -s "$d/$1" ] && return 0; done
  return 1
}
for p in zhipu openrouter siliconflow ark; do
  have "${p}_api_key" && ok "$p 的 key 已配置" || warn "$p 未配置 → setkey $p"
done
have ark_endpoint && ok "ark 接入点已配置" || warn "ark 未配置接入点 → setkey ark_endpoint（若无火山可忽略）"
# Jev 是可选的付费判断档，没装不影响其余部分
if have "typesafe.env" || [ -s "$HOME/.dsh/mcp/jev/typesafe.env" ]; then
  ok "Jev 的 key 已配置"
else
  warn "Jev 未配置（可选；判断档，缺它其余照常用）"
fi

cat <<'EOF'

装完自检：
  llm --health          # 四家云端连通性
  wq --reindex ~/项目     # 建全文索引（默认当前目录；也可 $WQ_ROOTS）
  wq --stats            # 看索引了多少、索引的哪些目录
  ocr 任意截图.png        # 中文 OCR

细节与实测数字：references/ROUTING-NOTES.md
EOF
