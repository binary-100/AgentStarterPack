@echo off
REM One-click install: global rules/skills + agent-hygiene MCP
cd /d "%~dp0"
echo Installing Agent Starter Pack (user scope + MCP)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Scope User -RegisterMcp -InstallMcpDeps -NoPause
if errorlevel 1 (
    echo Install failed.
    pause
    exit /b 1
)
echo.
echo Install complete. Restart Cursor, then check Settings - MCP - agent-hygiene
pause
