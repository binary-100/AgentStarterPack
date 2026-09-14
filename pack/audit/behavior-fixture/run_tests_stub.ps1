#Requires -Version 5.1
# Behavior fixture - fast pass for audit E2E acceptance (not a product test suite).
#
# It loops tests/test_*.py rather than exiting 0 blind: an instant-pass runner is exactly what the
# test-runner coverage check exists to catch, so the fixture must not model one.
#
# PowerShell rather than Batch, and no wrapper pair: a .ps1 is the one runner shape that works on
# every OS, so the fixture demonstrates the answer the audit gives a project whose test script
# cannot run on the host. As a .bat with `py -3` it made the fixture audit - and therefore four
# behavior steps - Windows-only.
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

$py = $null
foreach ($cand in @(@{ exe = 'py'; pre = @('-3') }, @{ exe = 'python3'; pre = @() }, @{ exe = 'python'; pre = @() })) {
    if (Get-Command $cand.exe -ErrorAction SilentlyContinue) { $py = $cand; break }
}
if (-not $py) {
    Write-Host 'No Python 3 found (tried py -3, python3, python).'
    exit 1
}

$tests = @(Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Filter 'test_*.py' -File -ErrorAction SilentlyContinue)
foreach ($t in $tests) {
    & $py.exe @($py.pre + @($t.FullName))
    if ($LASTEXITCODE -ne 0) { exit 1 }
}
exit 0
