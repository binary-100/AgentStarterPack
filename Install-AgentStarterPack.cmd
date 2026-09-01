@echo off
REM One-click install: global rules/skills + agent-hygiene MCP
cd /d "%~dp0"
echo Installing Agent Starter Pack (user scope + MCP)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Scope User -RegisterMcp -InstallMcpDeps -NoPause
if errorlevel 1 (
    echo Install failed.
    if not defined BUILD_NOPAUSE pause
    exit /b 1
)
echo.
echo Install complete. Restart Cursor, then check Settings - MCP - agent-hygiene
REM Keeps the window open for a double-click; agents set BUILD_NOPAUSE=1 so it never blocks.
if not defined BUILD_NOPAUSE pause
