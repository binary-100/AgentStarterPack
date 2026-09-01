@echo off
REM Bootstrap a new repo with audit wiring + multi-tool agent instructions
cd /d "%~dp0"
set "ROOT=%~1"
if "%ROOT%"=="" (
    echo Usage: Bootstrap-Project.cmd PROJECT_ROOT [ProjectName]
    echo Example: Bootstrap-Project.cmd D:\my-app MyApp
    if not defined BUILD_NOPAUSE pause
    exit /b 1
)
set "NAME=%~2"
if "%NAME%"=="" set "NAME=%~n1"
echo Bootstrapping %ROOT% as %NAME% ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack\scripts\bootstrap-project.ps1" -ProjectRoot "%ROOT%" -ProjectName "%NAME%" -Stack Python -Targets All -NoPause
if errorlevel 1 (
    echo Bootstrap failed.
    if not defined BUILD_NOPAUSE pause
    exit /b 1
)
echo.
echo Done. Customize docs/AUDIT.md then run run_audit.cmd
REM Keeps the window open for a double-click; agents set BUILD_NOPAUSE=1 so it never blocks.
if not defined BUILD_NOPAUSE pause
