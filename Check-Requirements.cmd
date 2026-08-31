@echo off
REM Environment preflight: what this machine needs before install, bootstrap, or an audit.
REM Run this first when the pack folder arrives on a new machine. Add -Fix to install Python packages.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack\scripts\check-requirements.ps1" %*
set "RC=%ERRORLEVEL%"
if "%RC%" neq "0" (
    echo.
    echo Required items are missing - see the commands above.
)
if "%~1"=="" pause
exit /b %RC%
