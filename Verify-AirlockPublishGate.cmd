@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack\scripts\verify-airlock-publish-gate.ps1" %*
exit /b %ERRORLEVEL%
