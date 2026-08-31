@echo off
REM Refresh agent context: sync a project's pack files and write docs\AGENT_CONTEXT.json +
REM docs\AGENT_REFRESH.md. Optional: %1 = ProjectRoot (default: this pack repo).
REM A leading switch (-NoClipboard, -Install, ...) is passed straight through instead of being
REM bound to -ProjectRoot, which used to fail with "Missing an argument for parameter 'ProjectRoot'".
setlocal
set "PACK=%~dp0"
if "%PACK:~-1%"=="\" set "PACK=%PACK:~0,-1%"
set "SCRIPT=%PACK%\pack\scripts\refresh-agent-context.ps1"

set "FIRST=%~1"
if not defined FIRST goto NOARGS
if "%FIRST:~0,1%"=="-" goto SWITCHESONLY
goto WITHROOT

:NOARGS
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
goto DONE

:SWITCHESONLY
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
goto DONE

:WITHROOT
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -ProjectRoot "%~1" %2 %3 %4

:DONE
exit /b %ERRORLEVEL%
