@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\run_audit.ps1" -FinalizeOnly
