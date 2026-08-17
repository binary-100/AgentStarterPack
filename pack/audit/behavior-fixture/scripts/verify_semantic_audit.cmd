@echo off
py -3 "%USERPROFILE%\.cursor\AgentStarterPack\pack\scripts\audit_code_checks.py" "%CD%" --verify-semantic-report
