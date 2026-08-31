@echo off
setlocal
set "REPO=%~dp0.."
set "PACK=%AGENT_STARTER_PACK_ROOT%"
if not exist "%PACK%\pack\scripts\sync-audit-system.ps1" set "PACK=%USERPROFILE%\.cursor\AgentStarterPack"
if not exist "%PACK%\pack\scripts\sync-audit-system.ps1" set "PACK=%USERPROFILE%\.cursor\agent-starter-pack"
if not exist "%PACK%\pack\scripts\sync-audit-system.ps1" (
  echo [ERROR] Agent Starter Pack not found. Run install.ps1 from the pack, or set AGENT_STARTER_PACK_ROOT to the pack folder.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PACK%\pack\scripts\sync-audit-system.ps1" -ProjectRoot "%REPO%" %*
exit /b %ERRORLEVEL%
