#Requires -Version 5.1
<#
.SYNOPSIS
  Create StarterPack-Airlock on the host Desktop and migrate git into repo/ (Phase 3).
.DESCRIPTION
  Publisher bootstrap per docs/AIRLOCK_MIGRATION_CHECKLIST.md:
  1. Materialize overlay + repo-only templates under {Desktop}/StarterPack-Airlock/
  2. Write publisher.key (or validate an existing key)
  3. Git into repo/ - Move (default cutover), Copy (parallel build), or Skip
  4. Run sync-working-copy-to-airlock-repo.ps1 to align repo/ content

  Does not configure remotes, push, or CI secrets - human steps after init.
  **Recommended first live run:** `-GitMode Copy` keeps .git on the working copy until
  `Complete-StarterPackAirlockCutover.cmd` after publish gate + CI are proven.

.PARAMETER WorkingCopy
  Pack checkout under development (install.ps1 + VERSION). Default: script-relative checkout.
.PARAMETER DesktopRoot
  Desktop folder that will hold StarterPack-Airlock/. Default: first Get-StarterPackDesktopCandidates entry.
.PARAMETER AirlockRoot
  Optional full path to StarterPack-Airlock (overrides DesktopRoot).
.PARAMETER PublisherKeyId
  Overlay manifest keyId and publisher.key contents. Default: new random id when creating a key.
.PARAMETER GitMode
  Move - move .git to repo/ (final layout). Copy - copy .git to repo/, keep on working copy (parallel).
  Skip - no git change. `-SkipGitMigrate` is equivalent to `-GitMode Skip`.
.PARAMETER SkipGitMigrate
  Deprecated alias for `-GitMode Skip`.
.PARAMETER SkipSync
  Skip B09 sync after layout/migrate (simulation or dry layout only).
.PARAMETER Force
  Re-materialize overlay/repo templates when Airlock already exists.
.PARAMETER WhatIf
  Print planned actions without writing.
.EXAMPLE
  .\pack\scripts\Initialize-StarterPackAirlock.ps1 -WorkingCopy 'C:\dev\AgentStarterPack'
#>
param(
    [string]$WorkingCopy,
    [string]$DesktopRoot,
    [string]$AirlockRoot,
    [string]$PublisherKeyId,
    [ValidateSet('Move', 'Copy', 'Skip')]
    [string]$GitMode = 'Move',
    [switch]$SkipGitMigrate,
    [switch]$SkipSync,
    [switch]$Force,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

if ($SkipGitMigrate) { $GitMode = 'Skip' }

function Resolve-InitDir([string]$Path, [string]$Label, [switch]$Optional) {
    if (-not $Path) {
        if ($Optional) { return $null }
        Write-Host "[FAIL] $Label is required"
        exit 1
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "[FAIL] $Label not found: $Path"
        exit 1
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

if (-not $WorkingCopy) {
    $WorkingCopy = Get-CheckoutAgentStarterPack
    if (-not $WorkingCopy) { $WorkingCopy = Get-SourceAgentStarterPack }
}
$WorkingCopy = Resolve-InitDir $WorkingCopy 'WorkingCopy'

foreach ($req in @('install.ps1', 'VERSION', 'pack/audit/manifest.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $WorkingCopy ($req -replace '/', '\')))) {
        Write-Host "[FAIL] working copy missing $req"
        exit 1
    }
}

$layout = Get-StarterPackAirlockLayoutPaths -DesktopRoot $DesktopRoot -AirlockRoot $AirlockRoot
if ($null -eq $layout) {
    Write-Host '[FAIL] could not resolve Desktop path for StarterPack-Airlock'
    exit 1
}

Write-Host 'Initialize StarterPack-Airlock (Phase 3)'
Write-Host "  Working copy: $WorkingCopy"
Write-Host "  Airlock:      $($layout.AirlockRoot)"
Write-Host "  Repo:         $($layout.RepoPath)"
Write-Host "  GitMode:      $GitMode"
if ($WhatIf) { Write-Host '  Mode: WhatIf' }

if ($GitMode -ne 'Skip' -and (Test-PackGitCursorLock -Root $WorkingCopy)) {
    Write-Host '[WARN] .git/cursor present - close Cursor on this checkout before git copy/move (WQ-461)'
}
if ($GitMode -eq 'Copy') {
    Write-Host '[INFO] parallel build - working copy keeps .git until Complete-StarterPackAirlockCutover.cmd'
}

$existing = Find-StarterPackAirlock -DesktopRoots @($layout.DesktopRoot)
if ($existing -and -not $Force) {
    Write-Host "[FAIL] StarterPack-Airlock already validates on $($layout.DesktopRoot) - use -Force to re-materialize templates"
    exit 1
}

$keyPath = $layout.PublisherKeyPath
$keyId = $PublisherKeyId
if (Test-Path -LiteralPath $keyPath) {
    $keyId = (Get-Content -LiteralPath $keyPath -Raw).Trim()
    Write-Host "[OK] using existing publisher.key (keyId=$keyId)"
} elseif (-not $keyId) {
    $keyId = 'publisher-' + ([guid]::NewGuid().ToString('N').Substring(0, 12))
}

if ($WhatIf) {
    Write-Host ('[WOULD CREATE] ' + $layout.AirlockRoot)
    Write-Host ('[WOULD WRITE] ' + $keyPath + ' = ' + $keyId)
} else {
    New-Item -ItemType Directory -Path $layout.AirlockRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $layout.RepoPath -Force | Out-Null
    if (-not (Test-Path -LiteralPath $keyPath)) {
        $enc = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($keyPath, ($keyId + "`n"), $enc)
        Write-Host "[OK] wrote publisher.key"
    }
}

$materialize = Join-Path $WorkingCopy 'pack/scripts/materialize-starter-pack-airlock-templates.ps1'
if (-not (Test-Path -LiteralPath $materialize)) {
    Write-Host "[FAIL] materialize script missing: $materialize"
    exit 1
}

if ($WhatIf) {
    Write-Host '[WOULD RUN] materialize overlay + repo templates'
} else {
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $materialize `
        -PackRoot $WorkingCopy -AirlockRoot $layout.AirlockRoot -RepoRoot $layout.RepoPath `
        -PublisherKeyId $keyId 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] materialize exit $LASTEXITCODE"
        exit 1
    }
    Write-Host '[OK] overlay and repo-only templates materialized'
}

$migrateResult = 'skipped'
if ($GitMode -ne 'Skip') {
    if (Test-PackGitRoot -Root $WorkingCopy) {
        if ($GitMode -eq 'Copy') {
            $migrateResult = Copy-PackGitToAirlockRepo -WorkingCopy $WorkingCopy -RepoDir $layout.RepoPath -WhatIf:$WhatIf
            Write-Host "[OK] git copy: $migrateResult"
        } else {
            $migrateResult = Move-PackGitToAirlockRepo -WorkingCopy $WorkingCopy -RepoDir $layout.RepoPath -WhatIf:$WhatIf
            Write-Host "[OK] git move: $migrateResult"
        }
        if ($migrateResult -eq 'repo-already-has-git') {
            Write-Host '[WARN] repo/ already has .git - working copy git unchanged'
        }
        if ($migrateResult -eq 'copy-failed') {
            Write-Host '[FAIL] git copy failed - close Cursor and retry, or use -GitMode Skip and init repo/ manually'
            exit 1
        }
    } elseif (Test-PackGitRepo -Root $WorkingCopy) {
        Write-Host '[WARN] working copy is inside a git tree but not the root - .git not changed automatically'
        $migrateResult = 'nested-git'
    } else {
        Write-Host '[OK] working copy has no .git to migrate'
        $migrateResult = 'absent'
    }
} else {
    Write-Host '[OK] git step skipped (GitMode Skip)'
}

if (-not $SkipSync) {
    $syncScript = Join-Path $WorkingCopy 'pack/scripts/sync-working-copy-to-airlock-repo.ps1'
    if ($WhatIf) {
        Write-Host ('[WOULD RUN] ' + $syncScript)
    } else {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $syncScript `
            -WorkingCopy $WorkingCopy -RepoRoot $layout.RepoPath
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[FAIL] sync exit $LASTEXITCODE"
            exit 1
        }
        Write-Host '[OK] B09 sync complete'
    }
} else {
    Write-Host '[OK] B09 sync skipped (-SkipSync)'
}

if (-not $WhatIf) {
    $disc = Find-StarterPackAirlock -DesktopRoots @($layout.DesktopRoot)
    if ($null -eq $disc) {
        Write-Host '[FAIL] Find-StarterPackAirlock failed after init - overlay/key incomplete'
        exit 1
    }
    $wcGit = Test-PackGitRepo -Root $WorkingCopy
    $repoGit = Test-PackGitRepo -Root $layout.RepoPath
    Write-Host "[OK] discovery active; workingCopy.git=$wcGit; repo.git=$repoGit; migrate=$migrateResult"
}

if ($GitMode -eq 'Copy') {
    Write-Host 'Next: Verify-AirlockPublishGate.cmd, configure remote on repo/, prove CI - then Complete-StarterPackAirlockCutover.cmd.'
} else {
    Write-Host 'Next: Verify-AirlockPublishGate.cmd (Zone A + sync + Zone B), configure remote on repo/, human git push only.'
}
exit 0
