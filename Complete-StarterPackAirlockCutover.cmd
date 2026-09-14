@echo off
REM Remove .git from working copy after Airlock repo/ is proven (parallel mode cutover)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack\scripts\Complete-StarterPackAirlockCutover.ps1" %*
set EXIT=%ERRORLEVEL%
if not defined BUILD_NOPAUSE if %EXIT% neq 0 pause
exit /b %EXIT%
