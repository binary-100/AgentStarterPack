#Requires -Version 5.1
<#
.SYNOPSIS
  Sync a git-free working copy into StarterPack-Airlock repo/ before Zone B audit (B09).
.DESCRIPTION
  Publisher workflow step 3 (see docs/AUDIT_AIRLOCK_COVERAGE.md): mirror the working tree into
  Airlock repo/, strip paths that must not ship (maintainerOnlyPaths, machineLocalPaths from
  pack/audit/manifest.json), and remove stale audit artifacts so Zone B runs on a fresh receipt.

  Preserves repo/.git (and any repo-only content excluded from the working copy) via robocopy /XD .git.
  Does not run git push - publish remains human-only until overlay policy is designed (H01).

.PARAMETER WorkingCopy
  Git-free (or git-at-root) pack checkout under development. Source of file content.
.PARAMETER RepoRoot
  Airlock repo/ directory - must exist and contain a valid git work tree after migration.
.PARAMETER AllowVersionDrift
  Skip the VERSION equality gate. Default fails closed when working copy and repo/ differ.
.PARAMETER WhatIf
  Print actions without copying or deleting.
.EXAMPLE
  .\pack\scripts\sync-working-copy-to-airlock-repo.ps1 `
    -WorkingCopy '/path/to/git-free-pack-checkout' `
    -RepoRoot '/path/to/StarterPack-Airlock/repo'
#>
param(
    [Parameter(Mandatory = $true)][string]$WorkingCopy,
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [switch]$AllowVersionDrift,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

function Resolve-PackDir([string]$Path, [string]$Label) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        Write-Host "[FAIL] $Label not found: $Path"
        exit 1
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

$WorkingCopy = Resolve-PackDir $WorkingCopy 'WorkingCopy'
$RepoRoot = Resolve-PackDir $RepoRoot 'RepoRoot'

$manifestPath = Join-Path $WorkingCopy 'pack/audit/manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-Host "[FAIL] no pack/audit/manifest.json under working copy"
    exit 1
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$maintainerOnly = @($manifest.maintainerOnlyPaths | Where-Object { $_ })
$machineLocal = @($manifest.machineLocalPaths | Where-Object { $_ })
$repoOnly = @($manifest.repoOnlyPaths | Where-Object { $_ })
if ($maintainerOnly.Count -eq 0 -or $machineLocal.Count -eq 0) {
    Write-Host '[FAIL] manifest missing maintainerOnlyPaths or machineLocalPaths'
    exit 1
}

$wcVersionPath = Join-Path $WorkingCopy 'VERSION'
$repoVersionPath = Join-Path $RepoRoot 'VERSION'
if (-not (Test-Path -LiteralPath $wcVersionPath)) {
    Write-Host '[FAIL] working copy has no VERSION file'
    exit 1
}
$wcVersion = (Get-Content -LiteralPath $wcVersionPath -Raw).Trim()
if (Test-Path -LiteralPath $repoVersionPath) {
    $repoVersion = (Get-Content -LiteralPath $repoVersionPath -Raw).Trim()
    if ($wcVersion -ne $repoVersion) {
        if (-not $AllowVersionDrift) {
            Write-Host "[FAIL] VERSION drift (working=$wcVersion repo=$repoVersion) - sync blocked; use -AllowVersionDrift to override"
            exit 1
        }
        Write-Host "[WARN] VERSION drift allowed: working=$wcVersion repo=$repoVersion"
    } else {
        Write-Host "[OK] VERSION match: $wcVersion"
    }
} else {
    Write-Host "[WARN] repo/ has no VERSION yet - first sync will write $wcVersion"
}

if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
    Write-Host '[WARN] repo/ has no .git directory - Zone B git arms will SKIP until migration completes'
}

Write-Host "Sync working copy -> Airlock repo/"
Write-Host "  From: $WorkingCopy"
Write-Host "  To:   $RepoRoot"
if ($WhatIf) { Write-Host '  Mode: WhatIf (no changes)' }

if (-not $WhatIf) {
    $robolog = robocopy $WorkingCopy $RepoRoot /MIR /XD .git .tmp __pycache__ .pytest_cache `
        /NFL /NDL /NJH /NJS /nc /ns /np 2>&1
    $rc = $LASTEXITCODE
    if ($rc -ge 8) {
        Write-Host "[FAIL] robocopy exit $rc"
        exit 1
    }
    Write-Host "[OK] robocopy mirror complete (exit $rc)"
}

function Remove-SyncPath {
    param([string]$Root, [string]$Rel)
    if ([string]::IsNullOrWhiteSpace($Rel)) { return }
    $abs = Join-Path $Root ($Rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $abs)) { return }
    if ($WhatIf) {
        Write-Host "[WOULD REMOVE] $Rel"
    } else {
        Remove-Item -LiteralPath $abs -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[REMOVED] $Rel"
    }
}

Write-Host 'Stripping maintainer-only paths from repo/ ...'
foreach ($rel in $maintainerOnly) { Remove-SyncPath -Root $RepoRoot -Rel $rel }

Write-Host 'Stripping machine-local paths from repo/ ...'
foreach ($rel in $machineLocal) { Remove-SyncPath -Root $RepoRoot -Rel $rel }

Write-Host 'Stripping repo-only paths from repo/ (re-materialized from templates) ...'
foreach ($rel in $repoOnly) { Remove-SyncPath -Root $RepoRoot -Rel $rel }

Write-Host 'Stripping stale audit artifacts from repo/ ...'
Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object {
        -not (Test-PackPathHasSegment -Path $_.FullName -Segment @('.git')) -and
        ($_.Name -like '.audit_*')
    } |
    ForEach-Object {
        $rel = Get-PackRelPathKey -Path $_.FullName -Root $RepoRoot
        if ($WhatIf) { Write-Host "[WOULD REMOVE] $rel" }
        else {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "[REMOVED] $rel"
        }
    }

$leaks = @()
foreach ($rel in $maintainerOnly) {
    if (Test-Path -LiteralPath (Join-Path $RepoRoot ($rel -replace '/', '\'))) { $leaks += "maintainerOnly: $rel" }
}
foreach ($rel in $machineLocal) {
    if (Test-Path -LiteralPath (Join-Path $RepoRoot ($rel -replace '/', '\'))) { $leaks += "machineLocal: $rel" }
}
if ($leaks.Count -gt 0) {
    Write-Host "[FAIL] sync hygiene leaks: $($leaks -join '; ')"
    exit 1
}

Write-Host '[OK] sync hygiene clean (maintainerOnly + machineLocal absent in repo/)'

if (-not $WhatIf) {
    $materialize = Join-Path $WorkingCopy 'pack/scripts/materialize-starter-pack-airlock-templates.ps1'
    if (-not (Test-Path -LiteralPath $materialize)) {
        Write-Host "[FAIL] materialize script missing: $materialize"
        exit 1
    }
    $matExit = Invoke-PackScript -NoProfile -ScriptPath $materialize `
        -PackRoot $WorkingCopy -RepoRoot $RepoRoot
    if ($matExit -ne 0) {
        Write-Host "[FAIL] repo-only template materialize exit $matExit"
        exit 1
    }
    foreach ($rel in $repoOnly) {
        $abs = Join-Path $RepoRoot ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $abs)) {
            Write-Host "[FAIL] repo-only path missing after materialize: $rel"
            exit 1
        }
    }
    Write-Host '[OK] repo-only templates materialized in repo/'

    if (-not (Write-PackPublishAttestation -RepoRoot $RepoRoot)) {
        Write-Host '[FAIL] publish attestation write failed'
        exit 1
    }
}

# Zone B verify arms (Done-log cite compare, git index) expect HEAD to match the synced tree.
if (-not $WhatIf -and (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        Push-Location $RepoRoot
        try {
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & $gitCmd.Source add -A 2>$null | Out-Null
            $shFiles = @(& $gitCmd.Source ls-files '*.sh' 2>$null | Where-Object { $_ })
            if ($shFiles.Count -gt 0) {
                & $gitCmd.Source add --chmod=+x @($shFiles) 2>$null | Out-Null
            }
            & $gitCmd.Source diff --cached --quiet 2>$null
            if ($LASTEXITCODE -ne 0) {
                & $gitCmd.Source -c user.email=sync@airlock.local -c user.name='Airlock sync' `
                    commit -m 'sync from working copy' -q 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host '[OK] synced tree committed in repo/ for Zone B audit'
                } else {
                    Write-Host '[WARN] git commit after sync failed - Zone B Done-log cite arm may SKIP'
                }
            } else {
                Write-Host '[OK] synced tree already matches HEAD in repo/'
            }
        } finally {
            $ErrorActionPreference = $prevEap
            Pop-Location
        }
    }
}

Write-Host "Next: $(Get-PackEntryPoint 'run_audit') from repo/ (Zone B attestation mode), then git push from repo/ only (human)."
exit 0
