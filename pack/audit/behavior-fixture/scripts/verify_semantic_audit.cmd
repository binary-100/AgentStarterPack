@echo off
setlocal
cd /d "%~dp0.."
set "PACK=%AGENT_STARTER_PACK_ROOT%"
if not exist "%PACK%\pack\scripts\audit_code_checks.py" set "PACK=%USERPROFILE%\.cursor\AgentStarterPack"
if not exist "%PACK%\pack\scripts\audit_code_checks.py" set "PACK=%USERPROFILE%\.cursor\agent-starter-pack"
if not exist "%PACK%\pack\scripts\audit_code_checks.py" (
  echo [ERROR] Agent Starter Pack not found. Run install.ps1 from the pack, or set AGENT_STARTER_PACK_ROOT to the pack folder.
  exit /b 1
)
py -3 "%PACK%\pack\scripts\audit_code_checks.py" "%CD%" --verify-semantic-report
exit /b %ERRORLEVEL%
