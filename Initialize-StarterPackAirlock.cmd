@echo off
REM Create Desktop StarterPack-Airlock (Phase 3). First live run: add -GitMode Copy for parallel build.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack\scripts\Initialize-StarterPackAirlock.ps1" %*
set EXIT=%ERRORLEVEL%
if not defined BUILD_NOPAUSE if %EXIT% neq 0 pause
exit /b %EXIT%
