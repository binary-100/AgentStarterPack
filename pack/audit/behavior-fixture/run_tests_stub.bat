@echo off
rem Behavior fixture - fast pass for audit E2E acceptance (not a product test suite).
rem It loops tests\test_*.py rather than exiting 0 blind: an instant-pass runner is exactly what
rem the test-runner coverage check exists to catch, so the fixture must not model one.
cd /d "%~dp0"
for %%F in (tests\test_*.py) do (
    py -3 "%%F"
    if errorlevel 1 exit /b 1
)
exit /b 0
