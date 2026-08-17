@echo off
setlocal
cd /d "%~dp0"
set "FAIL=0"
set "SCRIPTS=%~dp0pack\scripts"
if not exist "%SCRIPTS%\verify-audit-behavior.ps1" set "SCRIPTS=%USERPROFILE%\.cursor\AgentStarterPack\pack\scripts"

echo Running verify-audit-behavior.ps1 ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\verify-audit-behavior.ps1"
if errorlevel 1 set "FAIL=1"

echo Running verify-audit-system.ps1 ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\verify-audit-system.ps1" -ProjectRoot "%CD%"
if errorlevel 1 set "FAIL=1"

if "%FAIL%"=="1" exit /b 1
echo Pack audit tests: OK
exit /b 0
