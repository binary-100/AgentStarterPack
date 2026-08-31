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
if (-not (Test-AgentStarterPackInstalled)) {
    Info 'This pack is not installed for the current user profile yet - the failures below are the install step, not pack damage. Run install.ps1 from the pack root.'
}
if ($ReferenceProjectRoot) { Write-Host "ReferenceProjectRoot: $ReferenceProjectRoot (reference-project checks enabled)" }
else { Info 'ReferenceProjectRoot not set - pack-only mode (default).' }

# 1. Generic rules sync (optional - only when reference project provided)
$sync = Join-Path $PackRoot 'pack\scripts\sync-project-rules.ps1'
if (-not (Test-Path -LiteralPath $sync)) {
    Fail "Missing sync-project-rules.ps1: $sync"
} elseif ($ReferenceProjectRoot) {
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $sync -ProjectRoot $ReferenceProjectRoot -RulesRelativePath $RulesRelativePath -VerifyOnly | Out-Host
    if ($LASTEXITCODE -ne 0) { Fail "Generic rules drift (pack vs $RulesRelativePath under reference project)" }
    else { Pass 'Generic rules in sync (pack = reference project rules folder)' }
} else {
    Pass 'Generic rules sync verify skipped (no -ReferenceProjectRoot)'
}

# 2. User-global rules present
$userRules = Join-Path $env:USERPROFILE '.cursor\rules'
foreach ($name in @('full-paths-in-chat.mdc', 'agent-defaults-always.mdc', 'generic-agent-doc-hygiene.mdc', 'generic-work-queue-discipline.mdc', 'generic-agent-handoff-discipline.mdc')) {
    $p = Join-Path $userRules $name
    if (Test-Path -LiteralPath $p) { Pass "User global rule: $p" }
    else { Fail "User global rule missing: $p (run install.ps1 from pack root)" }
}

# 3. Canonical pack installed
$installed = Join-Path $env:USERPROFILE '.cursor\AgentStarterPack\pack\audit\manifest.json'
if (Test-Path -LiteralPath $installed) { Pass "Installed pack manifest: $installed" }
else { Fail "Installed pack missing: $installed" }

# 4. Key pack docs and rules
foreach ($rel in @(
        'pack\docs\PACK_MAINTENANCE.md',
        'pack\docs\AGENT_COORDINATION_BACKLOG.md',
        'pack\docs\WORK_COMPLETION.md',
        'pack\docs\AGENT_HANDOFFS.md',
        'pack\rules\full-paths-in-chat.mdc',
        'pack\rules\generic-agent-doc-hygiene.mdc',
        'pack\scripts\archive-completed-handoff.ps1',
        'pack\scripts\verify-complete-picture.ps1',
        'pack\scripts\ensure-work-completion.ps1',
        'Update-AgentRules.cmd'
    )) {
    $p = Join-Path $PackRoot $rel
    if (Test-Path -LiteralPath $p) { Pass "Pack file: $rel" }
    else { Fail "Pack file missing: $p" }
}

# 5. Work queue (pack repo + optional reference project)
$verifyWq = Join-Path $PackRoot 'pack\scripts\verify-work-queue.ps1'
$ensureWq = Join-Path $PackRoot 'pack\scripts\ensure-work-queue.ps1'
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
        $ensureWc = Join-Path $PackRoot 'pack\scripts\ensure-work-completion.ps1'
        if ($root -eq $ReferenceProjectRoot -and (Test-Path -LiteralPath $ensureWc)) {
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath $ensureWc -ProjectRoot $root -PackRoot $PackRoot | Out-Host
            if ($LASTEXITCODE -ne 0) { Fail "ensure-work-completion failed for $root"; continue }
        }
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $verifyWq -ProjectRoot $root 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { Pass "WORK_QUEUE valid: $root" }
        else { Fail "WORK_QUEUE verification failed: $root" }
    }
    $verifyHandoffs = Join-Path $PackRoot 'pack\scripts\verify-agent-handoffs.ps1'
    $verifyCompletePicture = Join-Path $PackRoot 'pack\scripts\verify-complete-picture.ps1'
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
    $portableVerify = Join-Path $PackRoot 'pack\scripts\verify-portable-bootstrap.ps1'
    if (-not (Test-Path -LiteralPath $portableVerify)) {
        Fail "Missing verify-portable-bootstrap.ps1: $portableVerify"
    } else {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $portableVerify -ProjectRoot $ReferenceProjectRoot 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { Pass "Portable bootstrap profile: $ReferenceProjectRoot" }
        else { Fail "Portable bootstrap profile failed: $ReferenceProjectRoot" }
    }

    $registerAdapters = Join-Path $PackRoot 'pack\scripts\register-tool-adapters.ps1'
    if (-not (Test-Path -LiteralPath $registerAdapters)) {
        Fail "Missing register-tool-adapters.ps1: $registerAdapters"
    } else {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $registerAdapters -ProjectRoot $ReferenceProjectRoot -Tool All -NoPause 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { Pass "Tool adapters: $ReferenceProjectRoot" }
        else { Fail "Tool adapter verification failed: $ReferenceProjectRoot" }
    }

    $repairDocs = Join-Path $PackRoot 'pack\scripts\repair-agent-docs.ps1'
    if (-not (Test-Path -LiteralPath $repairDocs)) {
        Fail "Missing repair-agent-docs.ps1: $repairDocs"
    } else {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairDocs -ProjectRoot $ReferenceProjectRoot -PackRoot $PackRoot -VerifyOnly 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { Pass "Hub docs + portable rules: $ReferenceProjectRoot" }
        else { Fail "Hub doc repair verify failed: $ReferenceProjectRoot" }
    }

    $sessionStart = Join-Path $ReferenceProjectRoot 'docs\AGENT_SESSION_START.md'
    if (Test-Path -LiteralPath $sessionStart) { Pass "AGENT_SESSION_START.md present: $ReferenceProjectRoot" }
    else { Warn "AGENT_SESSION_START.md missing - run Refresh-AgentContext.cmd for $ReferenceProjectRoot" }
}

if ($ReferenceProjectRoot) {
    # 7. Audit sync drift (reference project)
    $auditSync = Join-Path $PackRoot 'pack\scripts\sync-audit-system.ps1'
    if (Test-Path -LiteralPath $auditSync) {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $auditSync -VerifyOnly -ProjectRoot $ReferenceProjectRoot 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { Pass 'Audit system sync drift: OK (reference project)' }
        else { Fail 'Audit system sync drift (reference project)' }
    }
} else {
    Info 'Reference-project audit sync skipped. Pass -ReferenceProjectRoot when verifying a bootstrapped app.'

    # Pack self-audit sync verify
    $auditSync = Join-Path $PackRoot 'pack\scripts\sync-audit-system.ps1'
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
