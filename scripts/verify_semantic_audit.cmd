@echo off
cd /d "%~dp0.."
set "PY=%CD%\pack\scripts\audit_code_checks.py"
if not exist "%PY%" set "PY=%USERPROFILE%\.cursor\AgentStarterPack\pack\scripts\audit_code_checks.py"
py -3 "%PY%" "%CD%" --verify-semantic-report
exit /b %ERRORLEVEL%
