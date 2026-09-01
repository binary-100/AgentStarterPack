@echo off
REM Verify per-tool adapter files (Claude/Copilot/Windsurf) for a bootstrapped project
cd /d "%~dp0"
set "ROOT=%~1"
if "%ROOT%"=="" (
    echo Usage: Register-Tool-Adapters.cmd PROJECT_ROOT [Claude^|Copilot^|Windsurf^|All]
    echo Example: Register-Tool-Adapters.cmd D:\my-app All
    echo.
    echo Optional third arg: -Repair to write missing adapter files from templates
    echo Optional fourth arg: -InstallMcp to register Claude Desktop MCP on this machine
    if not defined BUILD_NOPAUSE pause
    exit /b 1
)
set "TOOL=%~2"
if "%TOOL%"=="" set "TOOL=All"
set "EXTRA="
if /I "%~3"=="-Repair" set "EXTRA=-Repair"
if /I "%~4"=="-InstallMcp" set "EXTRA=%EXTRA% -InstallMcp"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack\scripts\register-tool-adapters.ps1" -ProjectRoot "%ROOT%" -Tool %TOOL% %EXTRA% -NoPause
if errorlevel 1 (
    echo Tool adapter verification failed.
    if not defined BUILD_NOPAUSE pause
    exit /b 1
)
echo.
echo Done. See docs/PORTABLE_SETUP.md for per-tool setup.
REM Keeps the window open for a double-click; agents set BUILD_NOPAUSE=1 so it never blocks.
if not defined BUILD_NOPAUSE pause
