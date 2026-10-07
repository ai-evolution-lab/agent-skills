@echo off
title Skills Console - agent-skills
setlocal
rem Double-click launcher for the Skills dashboard (Windows).
rem Prefers the installed copy at %USERPROFILE%\.agents\agent-skills so the
rem page shows the real installed/uninstalled state.

set "CANONICAL=%USERPROFILE%\.agents\agent-skills"
set "SCRIPT="

where node >nul 2>nul
if errorlevel 1 (
  echo [X] node not found. Install it from https://nodejs.org then run this again.
  pause
  exit /b 1
)

if exist "%CANONICAL%\tools\skills.mjs" (
  set "SCRIPT=%CANONICAL%\tools\skills.mjs"
) else if exist "%~dp0tools\skills.mjs" (
  set "SCRIPT=%~dp0tools\skills.mjs"
  echo [i] No local install found - running from this repo copy directly.
  echo [i] All skills will show as "not installed", which is normal until you install.
  echo [i] To install properly, run:
  echo     powershell -C "irm https://raw.githubusercontent.com/ai-evolution-lab/agent-skills/main/install.ps1 | iex"
) else (
  echo [X] tools\skills.mjs not found. Keep this .bat inside the agent-skills repo folder.
  pause
  exit /b 1
)

echo Starting Skills Console... your browser will open automatically.
echo Close this window (or press Ctrl+C) to stop the server.
node "%SCRIPT%" dashboard
pause
