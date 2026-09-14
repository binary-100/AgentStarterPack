@echo off
REM Thin wrapper. The implementation is scripts\run_audit_tests.ps1, shared with run_audit_tests.sh,
REM the same way run_audit.cmd and run_audit.sh share scripts\run_audit.ps1. The five test steps used
REM to live here in Batch, which made the pack's own test entry point Windows-only by construction.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\run_audit_tests.ps1" %*
exit /b %ERRORLEVEL%
