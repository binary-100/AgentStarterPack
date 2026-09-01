@echo off
REM Bootstrap a new repo for non-Cursor agents (Portable target - no editor-specific entry files)
cd /d "%~dp0"
set "ROOT=%~1"
if "%ROOT%"=="" (
    echo Usage: Bootstrap-Portable-Project.cmd PROJECT_ROOT [ProjectName]
    echo Example: Bootstrap-Portable-Project.cmd D:\my-app MyApp
    echo.
    echo Uses -Targets Portable. For Cursor + all editors, use Bootstrap-Project.cmd instead.
    if not defined BUILD_NOPAUSE pause
    exit /b 1
)
set "NAME=%~2"
if "%NAME%"=="" set "NAME=%~n1"
echo Bootstrapping %ROOT% as %NAME% (Portable / multi-tool, no Cursor-only extras) ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack\scripts\bootstrap-project.ps1" -ProjectRoot "%ROOT%" -ProjectName "%NAME%" -Stack Python -Targets Portable -NoPause
if errorlevel 1 (
    echo Bootstrap failed.
    if not defined BUILD_NOPAUSE pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack\scripts\verify-portable-bootstrap.ps1" -ProjectRoot "%ROOT%" -RequirePortableOnly
if errorlevel 1 (
    echo Portable bootstrap verification failed.
    if not defined BUILD_NOPAUSE pause
    exit /b 1
)
echo.
echo Done. At session start: paste pack/docs/portable/GENERIC_RULES.md plus this project's AI_INSTRUCTIONS.md
echo Customize docs/AUDIT.md then run run_audit.cmd
REM Keeps the window open for a double-click; agents set BUILD_NOPAUSE=1 so it never blocks.
if not defined BUILD_NOPAUSE pause
