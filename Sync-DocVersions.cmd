@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack\scripts\sync-doc-versions.ps1" %*
exit /b %ERRORLEVEL%
