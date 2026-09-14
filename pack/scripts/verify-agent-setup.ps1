#Requires -Version 5.1
# One-shot validation for Agent Starter Pack install and optional reference-project checks.
param(
    [string]$PackRoot = '',
    [string]$ReferenceProjectRoot = '',
    [string]$RulesRelativePath = '.cursor\rules'
)

$ErrorActionPreference = 'Continue'
$fail = 0
$warn = 0

function Pass($msg) { Write-Host "[PASS] $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; $script:fail++ }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow; $script:warn++ }
function Info($msg) { Write-Host "[INFO] $msg" }

. (Join-Path $PSScriptRoot 'pack-paths.ps1')
if (-not $PackRoot) {
    $PackRoot = Get-AgentStarterPackRoot
    if (-not $PackRoot) { $PackRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
}

Write-Host "`n=== Agent Starter Pack setup verification ===`n"
Write-Host "PackRoot: $PackRoot"

# Sections 2 and 4 check what the manifest declares rather than lists kept in this file, so a missing
# manifest has to stop the run: with $manifest empty every foreach below would iterate nothing and the
# script would report a verified setup after checking zero files.
$setupManifestPath = Get-PackManifestPath -Root $PackRoot
if (-not (Test-Path -LiteralPath $setupManifestPath)) {
    Write-Host "[FAIL] No pack manifest at $setupManifestPath - cannot verify anything." -ForegroundColor Red
    exit 1
}
$manifest = Get-Content -LiteralPath $setupManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not (Test-AgentStarterPackInstalled)) {
    Info 'This pack is not installed for the current user profile yet - the failures below are the install step, not pack damage. Run install.ps1 from the pack root.'
}
if ($ReferenceProjectRoot) { Write-Host "ReferenceProjectRoot: $ReferenceProjectRoot (reference-project checks enabled)" }
else { Info 'ReferenceProjectRoot not set - pack-only mode (default).' }

# 1. Generic rules sync (optional - only when reference project provided)
$sync = Join-Path $PackRoot 'pack/scripts/sync-project-rules.ps1'
if (-not (Test-Path -LiteralPath $sync)) {
    Fail "Missing sync-project-rules.ps1: $sync"
} elseif ($ReferenceProjectRoot) {
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $sync -ProjectRoot $ReferenceProjectRoot -RulesRelativePath $RulesRelativePath -VerifyOnly | Out-Host
    if ($LASTEXITCODE -ne 0) { Fail "Generic rules drift (pack vs $RulesRelativePath under reference project)" }
    else { Pass 'Generic rules in sync (pack = reference project rules folder)' }
} else {
    Pass 'Generic rules sync verify skipped (no -ReferenceProjectRoot)'
}

# 2. User-global rules and skills present
# Read from packToUser rather than a list kept here. This used to name five rules out of the twelve
# the manifest declares, so seven could fail to install and this script would still say the setup was
# verified - the same "guard narrower than the thing it guards" that let a broken export ship
# (2.22.60). Anything added to packToUser is now checked without touching this file.
$userRoot = Get-AgentStarterPackUserRoot
if (-not $userRoot) { $userRoot = Join-Path (Get-PackHomeDir) '.cursor' }
$toUser = @($manifest.packToUser | Where-Object { $_.to })
if ($toUser.Count -eq 0) {
    Fail 'manifest has no packToUser entries - cannot verify what install should have placed in the profile'
} else {
    $missingUser = @()
    foreach ($entry in $toUser) {
        $p = Join-Path $userRoot ($entry.to -replace '/', '\')
        if (-not (Test-Path -LiteralPath $p)) { $missingUser += $entry.to }
    }
    if ($missingUser.Count -gt 0) {
        Fail ("User-global files missing under ${userRoot}: $($missingUser -join ', ') " +
            '(run install.ps1 from pack root)')
    } else {
        Pass "User-global rules and skills present ($($toUser.Count) from packToUser): $userRoot"
    }
}

# 3. Canonical pack installed
# Unconditional, so this was the line that made Verify-AgentSetup.sh impossible off Windows: no
# guard, no fallback, and $env:USERPROFILE is $null there. $userRoot above is already resolved.
$installed = Join-Path $userRoot 'AgentStarterPack/pack/audit/manifest.json'
if (Test-Path -LiteralPath $installed) { Pass "Installed pack manifest: $installed" }
else { Fail "Installed pack missing: $installed" }

# 4. Pack files the manifest declares
# Was ten hand-picked paths, which answered "are these ten here?" rather than "is this pack complete?".
# packMirror is the list that already means the latter, so it is the one to check; machine-local paths
# are excluded because they are supposed to be absent from a checkout.
$mirrorExpected = @($manifest.packMirror | Where-Object { $_ })
$machineLocalExpected = @($manifest.machineLocalPaths)
if ($mirrorExpected.Count -eq 0) {
    Fail 'manifest has no packMirror entries - cannot verify the pack is complete'
} else {
    $missingPack = @()
    foreach ($rel in $mirrorExpected) {
        if ($machineLocalExpected -contains $rel) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $PackRoot ($rel -replace '/', '\')))) {
            $missingPack += $rel
        }
    }
    if ($missingPack.Count -gt 0) {
        Fail "Pack files missing (declared in packMirror): $($missingPack -join ', ')"
    } else {
        Pass "All $($mirrorExpected.Count) packMirror files present: $PackRoot"
    }
}

# 5. Work queue (pack repo + optional reference project)
$verifyWq = Join-Path $PackRoot 'pack/scripts/verify-work-queue.ps1'
$ensureWq = Join-Path $PackRoot 'pack/scripts/ensure-work-queue.ps1'
if (-not (Test-Path -LiteralPath $verifyWq)) {
    Fail "Missing verify-work-queue.ps1: $verifyWq"
} else {
    $wqRoots = @($PackRoot)
    if ($ReferenceProjectRoot) { $wqRoots += $ReferenceProjectRoot }
    foreach ($root in $wqRoots) {
        if ($root -eq $ReferenceProjectRoot -and (Test-Path -LiteralPath $ensureWq)) {
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath $ensureWq -ProjectRoot $root -PackRoot $PackRoot | Out-Host
            if ($LASTEXITCODE -ne 0) { Fail "ensure-work-queue failed for $root"; continue }
        }
        $ensureWc = Join-Path $PackRoot 'pack/scripts/ensure-work-completion.ps1'
        if ($root -eq $ReferenceProjectRoot -and (Test-Path -LiteralPath $ensureWc)) {
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath $ensureWc -ProjectRoot $root -PackRoot $PackRoot | Out-Host
            if ($LASTEXITCODE -ne 0) { Fail "ensure-work-completion failed for $root"; continue }
        }
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $verifyWq -ProjectRoot $root 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { Pass "WORK_QUEUE valid: $root" }
        else { Fail "WORK_QUEUE verification failed: $root" }
    }
    $verifyHandoffs = Join-Path $PackRoot 'pack/scripts/verify-agent-handoffs.ps1'
    $verifyCompletePicture = Join-Path $PackRoot 'pack/scripts/verify-complete-picture.ps1'
    if (Test-Path -LiteralPath $verifyHandoffs) {
        foreach ($root in $wqRoots) {
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath $verifyHandoffs -ProjectRoot $root -AllowMissing 2>&1 | Out-Host
            if ($LASTEXITCODE -eq 0) { Pass "Handoffs valid (or none): $root" }
            else { Fail "Handoff verification failed: $root" }
        }
    }
    if (Test-Path -LiteralPath $verifyCompletePicture) {
        foreach ($root in $wqRoots) {
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath $verifyCompletePicture -ProjectRoot $root -AllowMissing 2>&1 | Out-Host
            if ($LASTEXITCODE -eq 0) { Pass "Complete-picture handoff checks: $root" }
            else { Fail "Complete-picture verification failed: $root" }
        }
    }
}

# 6. Portable bootstrap profile (reference project)
if ($ReferenceProjectRoot) {
    $portableVerify = Join-Path $PackRoot 'pack/scripts/verify-portable-bootstrap.ps1'
    if (-not (Test-Path -LiteralPath $portableVerify)) {
        Fail "Missing verify-portable-bootstrap.ps1: $portableVerify"
    } else {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $portableVerify -ProjectRoot $ReferenceProjectRoot 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { Pass "Portable bootstrap profile: $ReferenceProjectRoot" }
        else { Fail "Portable bootstrap profile failed: $ReferenceProjectRoot" }
    }

    $registerAdapters = Join-Path $PackRoot 'pack/scripts/register-tool-adapters.ps1'
    if (-not (Test-Path -LiteralPath $registerAdapters)) {
        Fail "Missing register-tool-adapters.ps1: $registerAdapters"
    } else {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $registerAdapters -ProjectRoot $ReferenceProjectRoot -Tool All -NoPause 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { Pass "Tool adapters: $ReferenceProjectRoot" }
        else { Fail "Tool adapter verification failed: $ReferenceProjectRoot" }
    }

    $repairDocs = Join-Path $PackRoot 'pack/scripts/repair-agent-docs.ps1'
    if (-not (Test-Path -LiteralPath $repairDocs)) {
        Fail "Missing repair-agent-docs.ps1: $repairDocs"
    } else {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairDocs -ProjectRoot $ReferenceProjectRoot -PackRoot $PackRoot -VerifyOnly 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { Pass "Hub docs + portable rules: $ReferenceProjectRoot" }
        else { Fail "Hub doc repair verify failed: $ReferenceProjectRoot" }
    }

    # Resolved rather than assumed: a pack checkout keeps its context artifacts in a machine-local
    # state directory, so checking docs\ there would warn about a file that is correctly absent.
    $sessionStart = Join-Path (Get-AgentStateRoot -ProjectRoot $ReferenceProjectRoot) 'AGENT_SESSION_START.md'
    if (Test-Path -LiteralPath $sessionStart) { Pass "AGENT_SESSION_START.md present: $ReferenceProjectRoot" }
    else { Warn "AGENT_SESSION_START.md missing - run $(Get-PackEntryPoint 'Refresh-AgentContext') for $ReferenceProjectRoot" }
}

if ($ReferenceProjectRoot) {
    # 7. Audit sync drift (reference project)
    $auditSync = Join-Path $PackRoot 'pack/scripts/sync-audit-system.ps1'
    if (Test-Path -LiteralPath $auditSync) {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $auditSync -VerifyOnly -ProjectRoot $ReferenceProjectRoot 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { Pass 'Audit system sync drift: OK (reference project)' }
        else { Fail 'Audit system sync drift (reference project)' }
    }
} else {
    Info 'Reference-project audit sync skipped. Pass -ReferenceProjectRoot when verifying a bootstrapped app.'

    # Pack self-audit sync verify
    $auditSync = Join-Path $PackRoot 'pack/scripts/sync-audit-system.ps1'
    if (Test-Path -LiteralPath $auditSync) {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $auditSync -VerifyOnly -ProjectRoot $PackRoot 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { Pass 'Audit system sync drift: OK (pack repo)' }
        else { Fail 'Audit system sync drift (pack repo - run sync-audit-system.ps1)' }
    }
}

Write-Host "`n=== Summary ==="
Write-Host "Fail: $fail  Warn: $warn"
if ($fail -eq 0) {
    Write-Host "`nAll checks passed."
    exit 0
}
Write-Host "`nFix: run install.ps1 from pack root, or pass -ReferenceProjectRoot for app checks."
exit 1
