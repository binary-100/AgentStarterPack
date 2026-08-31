@echo off
REM One entry after pack upgrade: optional install + project refresh + open-chat reminder.
REM Usage: Update-AgentStack.cmd [ProjectRoot] [-Install] [-SkipProjectSync] [-NoClipboard]
setlocal
set "PACK=%~dp0"
if "%PACK:~-1%"=="\" set "PACK=%PACK:~0,-1%"
set "SCRIPT=%PACK%\pack\scripts\update-agent-stack.ps1"

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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -ProjectRoot "%~1" %2 %3 %4 %5

:DONE
exit /b %ERRORLEVEL%
