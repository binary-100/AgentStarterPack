#Requires -Version 5.1
<#
.SYNOPSIS
  Dual-zone publish gate (B11): Zone A working copy, B09 sync, Zone B Airlock repo/.
.DESCRIPTION
  Maintainer publish sequence before human git push. Fails closed when:
  - Airlock repo/ is missing or discovery is inactive (unless -PublishRoot is explicit)
  - Zone A behavior suite fails on the working copy
  - B09 sync fails (including VERSION drift)
  - Zone B behavior suite fails on repo/ after sync

  Default mode runs verify-audit-behavior.ps1 in each zone (same arms as S22). Use -FullAudit to
  run run_audit.cmd in each zone instead (S27-class, much slower).

  git push remains human-only (S21 / H01).

.PARAMETER WorkingCopy
  Git-free pack checkout under development. Default: resolved source pack root.
.PARAMETER PublishRoot
  Airlock repo/ directory. Default: Get-AgentStarterPackPublishRoot (Find-StarterPackAirlock).
.PARAMETER Mode
  Behavior (default) or FullAudit.
.PARAMETER SkipZoneA
  Skip working-copy verify (use when Zone A already passed this session).
.PARAMETER SkipSync
  Skip B09 sync (repo/ already matches working copy).
.PARAMETER SkipZoneB
  Skip repo/ verify after sync.
.PARAMETER WhatIf
  Print resolved paths and planned steps only.
#>
param(
    [string]$WorkingCopy = '',
    [string]$PublishRoot = '',
    [string]$RepoRoot = '',
    [ValidateSet('Behavior', 'FullAudit')]
    [string]$Mode = 'Behavior',
    [switch]$SkipZoneA,
    [switch]$SkipSync,
    [switch]$SkipZoneB,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

function Resolve-ExistingDir([string]$Path, [string]$Label) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        Write-Host "[FAIL] $Label not found: $Path"
        exit 1
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Invoke-ZoneAudit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ZoneLabel,
        [Parameter(Mandatory = $true)][string]$AuditMode
    )
    Write-Host ''
    Write-Host "=== $ZoneLabel ==="
    Write-Host "Root: $Root"
    if ($AuditMode -eq 'FullAudit') {
        $auditCmd = Get-PackEntryPoint 'run_audit'
        $auditPath = Join-Path $Root $auditCmd
        if (-not (Test-Path -LiteralPath $auditPath)) {
            Write-Host "[FAIL] missing $auditCmd under $Root"
            return 1
        }
        Push-Location $Root
        try {
            $env:BUILD_NOPAUSE = '1'
            if ($auditPath -match '\.cmd$') {
                & cmd /c $auditPath 2>&1 | Out-Host
            } else {
                Invoke-PackScript -PassOutput -NoProfile -ScriptPath $auditPath -RepoRoot $Root 2>&1 | Out-Host
            }
            return $LASTEXITCODE
        } finally {
            Pop-Location
        }
    }
    $behavior = Join-Path $Root 'pack/scripts/verify-audit-behavior.ps1'
    if (-not (Test-Path -LiteralPath $behavior)) {
        $src = Get-SourceAgentStarterPack
        if ($src) { $behavior = Join-Path $src 'pack/scripts/verify-audit-behavior.ps1' }
    }
    if (-not (Test-Path -LiteralPath $behavior)) {
        Write-Host "[FAIL] verify-audit-behavior.ps1 not found for $ZoneLabel"
        return 1
    }
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $behavior -PackRoot $Root 2>&1 | Out-Host
    return $LASTEXITCODE
}

if ($RepoRoot -and -not $PublishRoot) { $PublishRoot = $RepoRoot }

if (-not $WorkingCopy) {
    $WorkingCopy = Get-SourceAgentStarterPack
    if (-not $WorkingCopy) { $WorkingCopy = Get-AgentStarterPackRoot }
}
if (-not $WorkingCopy) {
    Write-Host '[FAIL] could not resolve working copy - pass -WorkingCopy or run from a pack checkout'
    exit 1
}
$WorkingCopy = Resolve-ExistingDir $WorkingCopy 'WorkingCopy'

if (-not $PublishRoot) {
    $PublishRoot = Get-AgentStarterPackPublishRoot
}
if (-not $PublishRoot) {
    Write-Host '[FAIL] Airlock publish root not found - Initialize-StarterPackAirlock or pass -PublishRoot'
    Write-Host '       Publishing requires StarterPack-Airlock on the host Desktop (WQ-465, settled).'
    exit 1
}
$PublishRoot = Resolve-ExistingDir $PublishRoot 'PublishRoot (Airlock repo/)'

$syncScript = Join-Path $WorkingCopy 'pack/scripts/sync-working-copy-to-airlock-repo.ps1'
if (-not (Test-Path -LiteralPath $syncScript)) {
    $src = Get-SourceAgentStarterPack
    if ($src) { $syncScript = Join-Path $src 'pack/scripts/sync-working-copy-to-airlock-repo.ps1' }
}

Write-Host 'Airlock dual-zone publish gate (B11)'
Write-Host "  Mode:         $Mode"
Write-Host "  Working copy: $WorkingCopy"
Write-Host "  Publish repo: $PublishRoot"
Write-Host "  Skip Zone A:  $([bool]$SkipZoneA)"
Write-Host "  Skip sync:    $([bool]$SkipSync)"
Write-Host "  Skip Zone B:  $([bool]$SkipZoneB)"

if ($WhatIf) {
    Write-Host ''
    Write-Host '[WhatIf] Planned steps:'
    if (-not $SkipZoneA) { Write-Host "  1. Zone A ($Mode) on working copy" }
    if (-not $SkipSync) { Write-Host "  2. B09 sync: $syncScript" }
    if (-not $SkipZoneB) { Write-Host "  3. Zone B ($Mode) on repo/" }
    Write-Host '  4. Human git push from repo/ only (not run by this script)'
    exit 0
}

$zoneAExit = 0
$zoneBExit = 0

if (-not $SkipZoneA) {
    $zoneAExit = Invoke-ZoneAudit -Root $WorkingCopy -ZoneLabel 'Zone A (working copy)' -AuditMode $Mode
    if ($zoneAExit -ne 0) {
        Write-Host ''
        Write-Host "[FAIL] Zone A failed (exit $zoneAExit) - fix the working copy before sync/publish"
        exit 1
    }
    Write-Host '[OK] Zone A passed'
}

if (-not $SkipSync) {
    Write-Host ''
    Write-Host '=== B09 sync (working copy -> repo/) ==='
    if (-not (Test-Path -LiteralPath $syncScript)) {
        Write-Host "[FAIL] sync script missing: $syncScript"
        exit 1
    }
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $syncScript `
        -WorkingCopy $WorkingCopy -RepoRoot $PublishRoot 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host "[FAIL] B09 sync failed (exit $LASTEXITCODE) - publish blocked"
        exit 1
    }
    Write-Host '[OK] B09 sync complete'
}

if (-not $SkipZoneB) {
    $zoneBExit = Invoke-ZoneAudit -Root $PublishRoot -ZoneLabel 'Zone B (Airlock repo/)' -AuditMode $Mode
    if ($zoneBExit -ne 0) {
        Write-Host ''
        if (-not $SkipZoneA -and $zoneAExit -eq 0) {
            Write-Host '[DUAL-ZONE FAIL] Zone A passed but Zone B failed - repo/ is not publish-ready.'
            Write-Host '  Likely causes: sync lag, git arms SKIP (.git missing in repo/), or Zone-B-only drift.'
            Write-Host '  Re-run B09 sync, then Zone B only: verify-airlock-publish-gate.ps1 -SkipZoneA -SkipSync'
        } else {
            Write-Host "[FAIL] Zone B failed (exit $zoneBExit)"
        }
        exit 1
    }
    Write-Host '[OK] Zone B passed'
}

Write-Host ''
Write-Host 'Dual-zone publish gate: OK (Zone A + sync + Zone B). Human git push from repo/ only.'
exit 0
