@echo off
setlocal
cd /d "%~dp0"
set "FAIL=0"
set "SCRIPTS=%~dp0pack\scripts"
if not exist "%SCRIPTS%\verify-audit-behavior.ps1" (
    REM Falling back means the results describe the installed pack's engine, not this checkout.
    REM Silently switching made an incomplete checkout look like a passing one.
    echo [WARN] pack\scripts not found in this checkout - falling back to the installed pack.
    echo [WARN] Results below test %%USERPROFILE%%\.cursor\AgentStarterPack, not this folder.
    set "SCRIPTS=%USERPROFILE%\.cursor\AgentStarterPack\pack\scripts"
)

where py >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python launcher 'py' not found. Run Check-Requirements.cmd for the install command.
    exit /b 1
)

echo Running tests\test_pack_audit.py ...
py -3 "%~dp0tests\test_pack_audit.py"
if errorlevel 1 set "FAIL=1"
echo.

echo Running verify-audit-behavior.ps1 ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\verify-audit-behavior.ps1"
if errorlevel 1 set "FAIL=1"

REM -SkipBehavior because the line above already ran the behavior suite. Without it,
REM verify-audit-system re-runs the whole suite when the audited root is the pack itself,
REM which paid for it twice (~30s) on every test run and every self-audit.
echo Running verify-audit-system.ps1 ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\verify-audit-system.ps1" -ProjectRoot "%CD%" -SkipBehavior
if errorlevel 1 set "FAIL=1"

if "%FAIL%"=="1" exit /b 1
echo Pack audit tests: OK
exit /b 0
