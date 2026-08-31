@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack\scripts\verify-agent-setup.ps1" %*
exit /b %ERRORLEVEL%
