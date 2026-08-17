@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.cursor\AgentStarterPack\pack\scripts\sync-audit-system.ps1" %*
