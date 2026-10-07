#!/usr/bin/env bash
# agent-skills 一键引导（macOS / Linux）
# 用法:  curl -fsSL https://raw.githubusercontent.com/ai-evolution-lab/agent-skills/main/install.sh | bash
set -euo pipefail
REPO_URL="https://github.com/ai-evolution-lab/agent-skills.git"
DIR="$HOME/.agents/agent-skills"

command -v git  >/dev/null || { echo "缺少 git：先执行 xcode-select --install"; exit 1; }
command -v node >/dev/null || { echo "缺少 node：brew install node（或官网安装）"; exit 1; }

if [ -d "$DIR/.git" ]; then
  git -C "$DIR" pull --ff-only
else
  mkdir -p "$HOME/.agents"
  git clone "$REPO_URL" "$DIR"
fi

MARK='# >>> agent-skills >>>'
RC="$HOME/.zshrc"; touch "$RC"
if ! grep -qF "$MARK" "$RC"; then
  cat >> "$RC" <<'EOF'
# >>> agent-skills >>>
skills() { node "$HOME/.agents/agent-skills/tools/skills.mjs" "$@"; }
skills-dashboard() { node "$HOME/.agents/agent-skills/tools/skills.mjs" dashboard; }
# <<< agent-skills <<<
EOF
fi

node "$DIR/tools/skills.mjs" init
echo
echo "✅ 引导完成。重开终端（或 source ~/.zshrc）后："
echo "   skills list        查看仓库全量 skill 与本机安装状态"
echo "   skills dashboard   打开可视化页面（勾选即装/卸，同步/回推一键）"
