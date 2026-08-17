@echo off
set "REPO=%~dp0.."
set "SYNC=%REPO%pack\scripts\sync-audit-system.ps1"
if not exist "%SYNC%" set "SYNC=%USERPROFILE%\.cursor\AgentStarterPack\pack\scripts\sync-audit-system.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SYNC%" -ProjectRoot "%REPO%" %*
exit /b %ERRORLEVEL%
