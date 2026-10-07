@echo off
chcp 65001 >nul
title Skills 控制台 - agent-skills
setlocal
rem 双击启动 Skills 可视化控制台（Windows）。
rem 自动优先使用本机安装真源 ~/.agents/agent-skills，保证「已装/未装」状态准确。

set "CANONICAL=%USERPROFILE%\.agents\agent-skills"
set "SCRIPT="

where node >nul 2>nul
if errorlevel 1 (
  echo [X] 未找到 node，请先安装: https://nodejs.org  装完重开本脚本。
  pause
  exit /b 1
)

if exist "%CANONICAL%\tools\skills.mjs" (
  set "SCRIPT=%CANONICAL%\tools\skills.mjs"
) else if exist "%~dp0tools\skills.mjs" (
  set "SCRIPT=%~dp0tools\skills.mjs"
  echo [i] 未检测到本机安装，直接用当前仓库运行（页面会全部显示未装，属正常）。
  echo [i] 完整安装请先运行: powershell -C "irm https://raw.githubusercontent.com/ai-evolution-lab/agent-skills/main/install.ps1 | iex"
) else (
  echo [X] 找不到 tools\skills.mjs，请确认本脚本位于 agent-skills 仓库内。
  pause
  exit /b 1
)

echo 正在启动 Skills 控制台... 浏览器将自动打开；关闭本窗口即退出服务。
node "%SCRIPT%" dashboard
pause
