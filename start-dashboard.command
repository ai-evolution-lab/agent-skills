#!/usr/bin/env bash
# 双击启动 Skills 可视化控制台（macOS / Linux，Finder 里双击 .command 文件）。
# 自动优先使用本机安装真源 ~/.agents/agent-skills，保证「已装/未装」状态准确。
# 若提示无执行权限，终端里执行一次: chmod +x start-dashboard.command

CANONICAL="$HOME/.agents/agent-skills"

if ! command -v node >/dev/null 2>&1; then
  echo "[X] 未找到 node，请先安装: brew install node（或 https://nodejs.org）"
  read -n 1 -s -r -p "按任意键关闭..."
  exit 1
fi

if [ -f "$CANONICAL/tools/skills.mjs" ]; then
  SCRIPT="$CANONICAL/tools/skills.mjs"
elif [ -f "$(cd "$(dirname "$0")" && pwd)/tools/skills.mjs" ]; then
  SCRIPT="$(cd "$(dirname "$0")" && pwd)/tools/skills.mjs"
  echo "[i] 未检测到本机安装，直接用当前仓库运行（页面会全部显示未装，属正常）。"
  echo "[i] 完整安装请先执行: curl -fsSL https://raw.githubusercontent.com/ai-evolution-lab/agent-skills/main/install.sh | bash"
else
  echo "[X] 找不到 tools/skills.mjs，请确认本脚本位于 agent-skills 仓库内。"
  read -n 1 -s -r -p "按任意键关闭..."
  exit 1
fi

echo "正在启动 Skills 控制台... 浏览器将自动打开；关闭本终端窗口即退出服务。"
node "$SCRIPT" dashboard
