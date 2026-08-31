@echo off
REM Install global pack rules. Optional: sync generic rules into a project (pass ProjectRoot as %1).
setlocal
set "PACK=%~dp0"
if "%PACK:~-1%"=="\" set "PACK=%PACK:~0,-1%"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PACK%\pack\scripts\update-agents.ps1"
if errorlevel 1 exit /b 1

if "%~1"=="" (
    echo.
    echo Done. To sync generic rules into a project, re-run with ProjectRoot:
    echo   Update-AgentRules.cmd "C:\Users\alice\Projects\MyApp"
    echo Optional second arg: rules relative path ^(default .cursor\rules^)
    exit /b 0
)

set "RULES_PATH=%~2"
if "%RULES_PATH%"=="" set "RULES_PATH=.cursor\rules"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PACK%\pack\scripts\sync-project-rules.ps1" -ProjectRoot "%~1" -RulesRelativePath "%RULES_PATH%"
if errorlevel 1 exit /b 1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PACK%\pack\scripts\sync-project-rules.ps1" -ProjectRoot "%~1" -RulesRelativePath "%RULES_PATH%" -VerifyOnly
exit /b %ERRORLEVEL%
