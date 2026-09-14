#Requires -Version 5.1
<#
.SYNOPSIS
  Mechanical checks for docs/handoffs/SESSION.md (WQ-438).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [switch]$AllowMissing,
    [switch]$AuditMode
)

$ErrorActionPreference = 'Stop'

# WQ-441: the path vocabulary lives in one file so a new verifier inherits it instead of re-deriving it.
. (Join-Path $PSScriptRoot 'verify-lib.ps1')

function Write-Ok($m) { if (-not $AuditMode) { Write-Host "[OK] $m" } }
function Write-Info($m) { Write-Host "[INFO] $m" }
function Write-Fail($m) { Write-Host "[FAIL] $m"; $script:fail++ }

function Emit-Audit([string]$Level, [string]$m) {
    switch ($Level) {
        'FIX' { Write-Host "[FIX] $m"; $script:fix++ }
        'IMPROVE' { Write-Host "[IMPROVE] $m"; $script:improve++ }
    }
}

$fail = 0
$fix = 0
$improve = 0
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$sessionPath = Join-Path $ProjectRoot 'docs/handoffs/SESSION.md'
$wqPath = Join-Path $ProjectRoot 'docs/WORK_QUEUE.md'

if (-not (Test-Path -LiteralPath $sessionPath)) {
    if ($AllowMissing) {
        Write-Info "SESSION.md missing (allowed): $sessionPath"
        exit 0
    }
    Write-Fail "SESSION.md missing: $sessionPath (run ensure-work-completion.ps1 or copy template)"
    exit 1
}

$raw = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8
Write-Ok 'SESSION.md present'

$forbidden = @(
    @{ Pat = '(?m)^##\s+Active queue'; Msg = 'SESSION must not contain ## Active queue (WQ owns status)' },
    @{ Pat = '\|\s*\*\*Next active ID\*\*'; Msg = 'SESSION must not contain Next active ID table (WQ owns status)' },
    @{ Pat = '(?m)^##\s+Done log'; Msg = 'SESSION must not contain Done log (WQ owns status)' }
)
foreach ($f in $forbidden) {
    if ($raw -match $f.Pat) {
        if ($AuditMode) { Emit-Audit 'FIX' $f.Msg } else { Write-Fail $f.Msg }
    }
}

if ($raw -match '(?i)\*\*Session status:\*\*\s*clear') {
    if ($raw -match '(?m)^-\s*\[\s\]\s+') {
        $msg = 'SESSION status is clear but Open items still has unchecked [ ] rows'
        if ($AuditMode) { Emit-Audit 'FIX' $msg } else { Write-Fail $msg }
    } else {
        Write-Ok 'SESSION status clear and no unchecked open items'
    }
} elseif ($raw -match '(?m)^-\s*\[\s\]\s+') {
    Write-Ok 'SESSION has open items (expected while status active)'
} else {
    Write-Info 'SESSION has no unchecked open items'
}

if (Test-Path -LiteralPath $wqPath) {
    $wqRaw = Get-Content -LiteralPath $wqPath -Raw -Encoding UTF8
    $wqNext = ''
    if ($wqRaw -match '(?m)\|\s*\*\*Next active ID\*\*\s*\|\s*\*\*(WQ-\d+)\*\*') {
        $wqNext = $Matches[1]
    }
    if ($wqNext -and $raw -match '(?i)(?:Next|WQ\s*Next|canonical Next)[^\n]{0,120}(WQ-\d+)') {
        $sessionWq = $Matches[1]
        if ($sessionWq -ne $wqNext) {
            $msg = "SESSION pointer cites $sessionWq but WORK_QUEUE Next active ID is $wqNext"
            if ($AuditMode) { Emit-Audit 'FIX' $msg } else { Write-Fail $msg }
        } else {
            Write-Ok "SESSION pointer aligns with WORK_QUEUE Next ($wqNext)"
        }
    } elseif ($wqNext) {
        Write-Info "WORK_QUEUE Next is $wqNext; SESSION has no explicit WQ pointer (optional)"
    }
}

if ($raw -match '(?m)^\|\s*Blocker\s*\|' -and $raw -match '(?m)^\|\s*(?!Blocker|Owner|Re-open|\*|\-)(.+?)\s*\|') {
    Write-Info 'SESSION lists blockers - agents must resolve before unplanned work'
}

# This file exists to travel between machines, so an absolute root in it is wrong everywhere except
# where it was typed. Behavior step 50 catches it only on the machine that owns that path - a guard
# comparing against the running checkout cannot see a document naming a different one - so the rule has
# to live here too. Strict policy: no illustration exemption, because this file is not documentation.
$absoluteRoots = @(Get-PackMachinePathHit -Text $raw -Policy Strict)
if ($absoluteRoots.Count -gt 0) {
    $msg = ("SESSION names an absolute path, which is wrong on every other machine - use a " +
        "placeholder root such as ``<pack checkout>``: $($absoluteRoots -join ', ')")
    if ($AuditMode) { Emit-Audit 'FIX' $msg } else { Write-Fail $msg }
} else {
    Write-Ok 'SESSION uses placeholder roots, not machine paths'
}

if ($AuditMode) {
    if ($fix -gt 0 -or $improve -gt 0) { exit 1 }
    exit 0
}
if ($fail -gt 0) { exit 1 }
Write-Ok 'session handoff checks'
exit 0
