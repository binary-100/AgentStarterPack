#Requires -Version 5.1
<#
.SYNOPSIS
  Pack test suite: python tests + behavior suite (both hosts) + audit-system verify.

.DESCRIPTION
  The one implementation. run_audit_tests.bat and run_audit_tests.sh are thin wrappers around this
  file, the same way run_audit.cmd and run_audit.sh both delegate to scripts/run_audit.ps1.

  This logic used to live in run_audit_tests.bat, which made the pack's own test entry point
  Windows-only by construction: Batch does not exist off Windows, so there was nothing for a .sh
  wrapper to wrap. The audit's test phase shells out to the project's declared test script, so a
  Batch-only runner meant the pack could not complete its own audit on macOS or Linux - an audit
  tool that cannot audit itself on an OS does not support that OS.
#>
param(
    [switch]$SkipDualShell
)

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $RepoRoot 'pack/scripts/pack-paths.ps1')

$fail = $false
$scripts = Join-Path $RepoRoot 'pack/scripts'
if (-not (Test-Path -LiteralPath (Join-Path $scripts 'verify-audit-behavior.ps1'))) {
    # Falling back means the results describe the installed pack's engine, not this checkout.
    # Silently switching made an incomplete checkout look like a passing one.
    Write-Host '[WARN] pack/scripts not found in this checkout - falling back to the installed pack.'
    $installed = Get-InstalledAgentStarterPack
    if (-not $installed) {
        Write-Host "[ERROR] No installed pack found either. Run $(Get-PackEntryPoint 'install')."
        exit 1
    }
    Write-Host "[WARN] Results below test $installed, not this folder."
    $scripts = Join-Path $installed 'pack/scripts'
}

$py = Resolve-PackPythonInvoke
if (-not $py) {
    Write-Host "[ERROR] Python 3.8+ not found. $(Get-PackPythonInstallFix)"
    exit 1
}

# Doc version cites are synced here, before anything reads them, because they are derived files and
# this is the build/test entry point that owns them - the audit does not (see the doc-hygiene rule).
# WQ-463: bumping the engine leaves pack/docs/AUDIT_SYSTEM.md carrying the old version, and
# verify-audit-system.ps1 fails on that mismatch. Inside a full audit the failure surfaced two layers
# away - in a *generated project's* bootstrap check, as "verify-audit-system.ps1 failed against the
# starter pack itself" - and then vanished, because the audit's own later sync repaired the header
# before the next run. That is the whole "first audit after a bump fails, the second passes" effect.
$docSync = Join-Path $RepoRoot 'pack/scripts/sync-doc-versions.ps1'
if (Test-Path -LiteralPath $docSync) {
    Write-Host 'Syncing derived version cites (sync-doc-versions.ps1) ...'
    Invoke-PackScript -ScriptPath $docSync -NoProfile -PassOutput
    # Deliberately not fatal: a stale cite it cannot fix is reported by the verify below, which is
    # the step that owns that judgement. Failing here would hide it behind a different message.
    if ($LASTEXITCODE -ne 0) { Write-Host '[WARN] sync-doc-versions reported a problem - see the verify output below.' }
    Write-Host ''
}

Write-Host 'Running tests/test_pack_audit.py ...'
Invoke-PackPython (Join-Path $RepoRoot 'tests/test_pack_audit.py')
if ($LASTEXITCODE -ne 0) { $fail = $true }
Write-Host ''

# The suite runs on both hosts when both are present. 5.1 is the floor and stays the launcher on
# Windows - it is the host guaranteed on a bare Windows machine - but the pack also runs under pwsh
# on macOS and Linux, and until this existed nobody ran the other host: Windows contributors only
# ever exercised 5.1 and everyone else only ever exercised 7. "Passes under both" was a comment,
# not a tested claim. Off Windows there is only one host, so the suite reports the parity step as a
# skip rather than pretending to have tested two.
$shell = Get-PackShellInfo
$bothHosts = $shell.pwshAvailable -and (Test-PackIsWindows)
$dual = @()
if ($bothHosts -and -not $SkipDualShell -and -not ($env:PACK_SKIP_DUALSHELL -and $env:PACK_SKIP_DUALSHELL.Trim())) {
    $dual = @('-DualShell')
}

Write-Host 'Running verify-audit-behavior.ps1 ...'
# Not assigned: with -PassOutput the child's output goes to the pipeline, so capturing the call
# would hide the suite's own report and leave only an exit code.
Invoke-PackScript -ScriptPath (Join-Path $scripts 'verify-audit-behavior.ps1') `
    -NoProfile -PassOutput -ArgumentList $dual
if ($LASTEXITCODE -ne 0) { $fail = $true }

# -SkipBehavior because the line above already ran the behavior suite. Without it,
# verify-audit-system re-runs the whole suite when the audited root is the pack itself,
# which paid for it twice (~30s) on every test run and every self-audit.
Write-Host 'Running verify-audit-system.ps1 ...'
Invoke-PackScript -ScriptPath (Join-Path $scripts 'verify-audit-system.ps1') `
    -NoProfile -PassOutput -ArgumentList @('-ProjectRoot', $RepoRoot, '-SkipBehavior')
if ($LASTEXITCODE -ne 0) { $fail = $true }

if ($fail) { exit 1 }
Write-Host 'Pack audit tests: OK'
exit 0
