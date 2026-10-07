# agent-skills 一键引导（Windows）
# 用法:  powershell -C "irm https://raw.githubusercontent.com/ai-evolution-lab/agent-skills/main/install.ps1 | iex"
$ErrorActionPreference = 'Stop'
$RepoDir = Join-Path $HOME '.agents\agent-skills'

foreach ($t in 'git', 'node') {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
    throw "缺少 $t。git: https://git-scm.com/download/win  node: https://nodejs.org （装完重开窗口再跑本脚本）"
  }
}

if (-not (Test-Path (Join-Path $RepoDir '.git'))) {
  New-Item -ItemType Directory -Force -Path (Split-Path $RepoDir) | Out-Null
  git clone https://github.com/ai-evolution-lab/agent-skills.git $RepoDir
} else {
  git -C $RepoDir pull --ff-only
}

# 注册 skills 命令（幂等）
$Marker = '# >>> agent-skills >>>'
$Profile1 = $PROFILE.CurrentUserAllHosts
if (-not (Test-Path $Profile1)) { New-Item -ItemType File -Force -Path $Profile1 | Out-Null }
if (-not (Select-String -Path $Profile1 -SimpleMatch $Marker -Quiet)) {
  @"
$Marker
function skills { node "`$HOME\.agents\agent-skills\tools\skills.mjs" @args }
function skills-dashboard { node "`$HOME\.agents\agent-skills\tools\skills.mjs" dashboard }
# <<< agent-skills <<<
"@ | Add-Content -Path $Profile1 -Encoding UTF8
}

node (Join-Path $RepoDir 'tools\skills.mjs') init
Write-Host "`n✅ 引导完成。新开一个终端即可使用：" -ForegroundColor Green
Write-Host "   skills list        查看仓库全量 skill 与本机安装状态"
Write-Host "   skills dashboard   打开可视化页面（勾选即装/卸，同步/回推一键）"
