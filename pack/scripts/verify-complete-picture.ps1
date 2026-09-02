#Requires -Version 5.1
<#
.SYNOPSIS
  Auditable checks for the complete-picture handoff contract (generic-deep-task-execution.mdc).
.DESCRIPTION
  Pack maintainer repos: HANDOFF section 11 must point at docs/WORK_QUEUE.md; stale Done tasks
  in section 11 are Improve. All repos with handoff docs: inventory + pending-keyword scan (INFO).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [switch]$AuditMode,
    [switch]$AllowMissing
)

$ErrorActionPreference = 'Stop'

function Write-Ok($m) { if (-not $AuditMode) { Write-Host "[OK] $m" } }
function Write-Info($m) { Write-Host "[INFO] $m" }
function Write-Fail($m) { Write-Host "[FAIL] $m"; $script:fail++ }

function Emit-Audit([string]$Level, [string]$m) {
    switch ($Level) {
        'FIX' { Write-Host "[FIX] $m"; $script:fix++ }
        'IMPROVE' { Write-Host "[IMPROVE] $m"; $script:improve++ }
        'INFO' { Write-Host "[INFO] $m" }
    }
}

$fail = 0
$fix = 0
$improve = 0
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

function Get-SectionBody([string]$content, [string]$startHdr, [string[]]$endHdrs) {
    $start = $content.IndexOf($startHdr)
    if ($start -lt 0) { return '' }
    $slice = $content.Substring($start + $startHdr.Length)
    $endPos = $slice.Length
    foreach ($eh in $endHdrs) {
        if ($eh -eq '---') {
            $m = [regex]::Match($slice, '(?m)^\s*---\s*$')
        } else {
            $m = [regex]::Match($slice, '(?m)^\s*' + [regex]::Escape($eh))
        }
        if ($m.Success -and $m.Index -lt $endPos) { $endPos = $m.Index }
    }
    return $slice.Substring(0, $endPos)
}

function Get-WqIdsFromSection([string]$body) {
    @([regex]::Matches($body, '\|\s*(WQ-\d+)\s*\|') | ForEach-Object { $_.Groups[1].Value })
}

function Test-ProductTruthRoadmapAlignment {
    if (-not (Test-Path -LiteralPath $wqPath)) { return }
    $roadmapPath = Join-Path $ProjectRoot 'docs\ROADMAP.md'
    if (-not (Test-Path -LiteralPath $roadmapPath)) { return }
    $wqRawAlign = Get-Content -LiteralPath $wqPath -Raw -Encoding UTF8
    $doneBodyAlign = Get-SectionBody $wqRawAlign '## Done log' @('## Cross-references')
    $doneIdSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]](Get-WqIdsFromSection $doneBodyAlign)
    )
    if ($doneIdSet.Count -eq 0) { return }
    $roadmapRaw = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8
    foreach ($doneId in $doneIdSet) {
        $wqSlug = ($doneId -replace '-', '')
        if ($roadmapRaw -match ('(?i)handoffs[/\\]active[/\\]HANDOFF_' + [regex]::Escape($wqSlug))) {
            $msg = "ROADMAP still links handoffs/active for $doneId but WORK_QUEUE lists Done"
            if ($AuditMode) { Emit-Audit 'IMPROVE' $msg } else { Write-Fail $msg }
        }
        foreach ($line in ($roadmapRaw -split "`n")) {
            if ($line -notmatch [regex]::Escape($doneId)) { continue }
            if ($line -match '(?i)\|\s*\*\*Next\*\*' -or $line -match '(?i)\|\s*\*\*In progress\*\*') {
                $msg = "ROADMAP still marks $doneId as Next/In progress but WORK_QUEUE lists Done"
                if ($AuditMode) { Emit-Audit 'IMPROVE' $msg } else { Write-Fail $msg }
                break
            }
        }
    }
}

$pendingPatterns = @(
    'deferred', 'not built', 'not implemented', 'open question', 'design goal',
    'next step', 'pick up', 'parked', 'remaining', 'tool-neutral', 'multi-tool',
    'Cursor-specific', 'Windows-only', 'audit depth'
)

$knownStalePhrases = @(
    'Implement Agent Context Refresh',
    'refresh-agent-context.ps1 + `Refresh-AgentContext.cmd`',
    'Optional Phase 2: MCP tools on agent-hygiene',
    'Phase 6b (MCP tools) and 6c (mailbox) remain unbuilt',
    'MCP surface for this is Phase 6b, deferred',
    'Also parked: MCP surface for the refresh',
    'WQ-308 (parked)',
    'build when promoted from Parked'
)

# When a WQ id is in Done log, these patterns in handoff docs mean stale "still open" text.
$shippedWqContradictions = @(
    @{
        WqId      = 'WQ-301'
        Label     = 'Phase 6b MCP freshness'
        Patterns  = @(
            '(?i)Phase\s+6b[^\n]{0,160}\|\s*Not built',
            '(?i)Phase 6b[^.\n]{0,120}(remain unbuilt|Also parked)',
            '(?i)MCP surface for this is Phase 6b,\s*deferred',
            '(?i)Also parked:\s*MCP surface'
        )
    },
    @{
        WqId      = 'WQ-308'
        Label     = 'Phase D session-start adapter'
        Patterns  = @(
            '(?i)\|\s*\*\*Work queue\*\*\s*\|\s*WQ-308\s*\(\s*parked\s*\)',
            '(?i)Phase D[^.\n]{0,80}deferred[^.\n]{0,60}WQ-308',
            '(?i)build when promoted from Parked'
        )
    }
)

$alignmentSkipRel = @(
    'pack\docs\AUDIT_SYSTEM_CHANGELOG.md',
    'docs\WORK_QUEUE.md'
)

$handoffSources = [System.Collections.Generic.List[string]]::new()
foreach ($f in Get-ChildItem -LiteralPath $ProjectRoot -Filter 'HANDOFF*.md' -File -ErrorAction SilentlyContinue) {
    [void]$handoffSources.Add($f.FullName)
}
$wqPath = Join-Path $ProjectRoot 'docs\WORK_QUEUE.md'
if (Test-Path -LiteralPath $wqPath) { [void]$handoffSources.Add($wqPath) }
$handoffsDir = Join-Path $ProjectRoot 'docs\handoffs'
if (Test-Path -LiteralPath $handoffsDir) {
    Get-ChildItem -LiteralPath $handoffsDir -Filter '*.md' -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$handoffSources.Add($_.FullName) }
}
$isPackRepo = (Test-Path -LiteralPath (Join-Path $ProjectRoot 'install.ps1')) -and
    (Test-Path -LiteralPath (Join-Path $ProjectRoot 'pack\audit\manifest.json'))
if ($isPackRepo) {
    # Curated on purpose, unlike the manifest-derived lists elsewhere: these are the documents that
    # make claims about handoff state, so they are the ones worth scanning for claims that contradict
    # the work queue. Scanning every pack doc would bury the real contradictions in prose that merely
    # mentions a handoff. Add a document here when it starts asserting what is in progress.
    foreach ($rel in @(
            'pack\docs\AGENT_HANDOFFS.md',
            'pack\docs\AGENT_WORKFLOW.md',
            'pack\docs\PACK_MAINTENANCE.md',
            'pack\docs\AGENT_COORDINATION_BACKLOG.md',
            'pack\docs\RULES_AND_VERIFY_MAP.md',
            'docs\MULTI_TOOL_GAP_PLAN.md',
            'docs\AGENT_UPGRADE_PATH.md',
            'docs\AGENT_FRESHNESS_ADAPTER_PLAN.md'
        )) {
        $p = Join-Path $ProjectRoot $rel
        if (Test-Path -LiteralPath $p) { [void]$handoffSources.Add($p) }
    }

    Get-ChildItem -LiteralPath $ProjectRoot -Filter 'STICK_*.txt' -File -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Fail "parallel install doc - use INSTALL.txt: $($_.Name)" }
    Get-ChildItem -LiteralPath $ProjectRoot -Filter '*_INSTALL.txt' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'INSTALL.txt' } |
        ForEach-Object { Write-Fail "parallel install doc - use INSTALL.txt: $($_.Name)" }

    $installTxtPath = Join-Path $ProjectRoot 'INSTALL.txt'
    $versionPath = Join-Path $ProjectRoot 'VERSION'
    if ((Test-Path -LiteralPath $installTxtPath) -and (Test-Path -LiteralPath $versionPath)) {
        $canonicalPack = (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim()
        if ($canonicalPack -match '(\d+\.\d+\.\d+)') { $canonicalPack = $Matches[1] }
        $installRaw = Get-Content -LiteralPath $installTxtPath -Raw -Encoding UTF8
        if ($installRaw -match 'QUICK INSTALL \(v(\d+\.\d+\.\d+)\)') {
            if ($Matches[1] -ne $canonicalPack) {
                Write-Fail "INSTALL.txt title ($($Matches[1])) != VERSION ($canonicalPack) - run Sync-DocVersions.cmd"
            } else {
                Write-Ok 'INSTALL.txt title version aligns with VERSION'
            }
        } else {
            Write-Fail 'INSTALL.txt missing QUICK INSTALL (vX.Y.Z) title line'
        }
    }

}

if ($handoffSources.Count -eq 0) {
    if ($AllowMissing) {
        Write-Info 'no handoff sources found (allowed)'
        exit 0
    }
    Write-Fail 'no handoff sources found'
    exit 1
}

$uniqueSources = $handoffSources | Select-Object -Unique
if ($AuditMode) {
    Emit-Audit 'INFO' "complete-picture inventory: $($uniqueSources.Count) handoff source(s)"
} else {
    Write-Ok "handoff source inventory: $($uniqueSources.Count) file(s)"
}

$patternRe = ($pendingPatterns | ForEach-Object { [regex]::Escape($_) }) -join '|'
foreach ($src in $uniqueSources) {
    $raw = Get-Content -LiteralPath $src -Raw -Encoding UTF8
    $hits = @([regex]::Matches($raw, $patternRe, 'IgnoreCase'))
    if ($hits.Count -gt 0) {
        $rel = $src.Substring($ProjectRoot.Length).TrimStart('\')
        $msg = "pending-work keywords: $rel ($($hits.Count) match(es))"
        if ($AuditMode) { Emit-Audit 'INFO' $msg } else { Write-Info $msg }
    }
}

Test-ProductTruthRoadmapAlignment

# Until 2.22.65 this script reconciled a session document's "section 11" against the queue: same Next,
# no Done id still highlighted, a pointer naming the queue as canonical. All three existed because two
# documents claimed status. One does now, so those checks have nothing to compare and are gone with it.
# What survives is the half that never depended on that section - a Done id must not read as parked or
# not built anywhere in the doc set - and it now runs unconditionally. Previously a project with no
# session document exited here, skipping the contradiction scan entirely: the projects least likely to
# have such a file were the ones getting the least checking.
if (Test-Path -LiteralPath $wqPath) {
    $wqRaw = Get-Content -LiteralPath $wqPath -Raw -Encoding UTF8
    $activeBody = Get-SectionBody $wqRaw '## Active queue' @(
        '## Inbox', '## Engineering backlog', '## Parked', '## Done log', '## Cross-references'
    )
    $doneBody = Get-SectionBody $wqRaw '## Done log' @('## Cross-references')
    $activeNext = [regex]::Match($activeBody, '\|\s*(WQ-\d+)\s*\|[^|]*\|\s*\*\*Next\*\*').Groups[1].Value

    # One Next, and it must not already be finished. With a single status claim the failure mode is no
    # longer disagreement between documents but self-contradiction inside this one.
    $activeIds = @(Get-WqIdsFromSection $activeBody) | Select-Object -Unique
    $doneIds = [System.Collections.Generic.HashSet[string]]::new([string[]](Get-WqIdsFromSection $doneBody))
    $bothIds = @($activeIds | Where-Object { $doneIds.Contains($_) })
    if ($bothIds) {
        $msg = "WORK_QUEUE lists in both Active and Done: $($bothIds -join ', ')"
        if ($AuditMode) { Emit-Audit 'FIX' $msg } else { Write-Fail $msg }
    } elseif ($activeNext) {
        Write-Ok "WORK_QUEUE Active Next is $activeNext and is not in Done"
    } else {
        Write-Info 'WORK_QUEUE Active queue has no Next row'
    }

    foreach ($phrase in $knownStalePhrases) {
        if ($activeBody -match [regex]::Escape($phrase)) {
            $msg = "WORK_QUEUE Active queue contains stale shipped task phrase: $phrase"
            if ($AuditMode) { Emit-Audit 'IMPROVE' $msg } else { Write-Fail $msg }
        }
    }
}

if (Test-Path -LiteralPath $wqPath) {
    $wqRawAlign = Get-Content -LiteralPath $wqPath -Raw -Encoding UTF8
    $doneBodyAlign = Get-SectionBody $wqRawAlign '## Done log' @('## Cross-references')
    $doneIdSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]](Get-WqIdsFromSection $doneBodyAlign)
    )
    foreach ($rule in $shippedWqContradictions) {
        if (-not $doneIdSet.Contains($rule.WqId)) { continue }
        foreach ($src in $uniqueSources) {
            $rel = $src.Substring($ProjectRoot.Length).TrimStart('\').Replace('/', '\')
            if ($alignmentSkipRel -contains $rel) { continue }
            $raw = Get-Content -LiteralPath $src -Raw -Encoding UTF8
            foreach ($pat in $rule.Patterns) {
                if ($raw -match $pat) {
                    $msg = "$rel contradicts $($rule.WqId) Done ($($rule.Label)): matches stale pattern"
                    if ($AuditMode) { Emit-Audit 'IMPROVE' $msg } else { Write-Fail $msg }
                    break
                }
            }
        }
    }
    # Generic: any Done WQ id must not read as parked / not built in handoff sources
    $genericStalePatterns = @(
        '(?i){0}\s*\(\s*parked\s*\)',
        '(?i)\|\s*{0}\s*\|[^|\n]{{0,240}}\|\s*(Not built|Parked|deferred)',
        '(?i)\*\*Work queue\*\*\s*\|\s*{0}\s*\(\s*parked'
    )
    foreach ($doneId in $doneIdSet) {
        foreach ($src in $uniqueSources) {
            $rel = $src.Substring($ProjectRoot.Length).TrimStart('\').Replace('/', '\')
            if ($alignmentSkipRel -contains $rel) { continue }
            $raw = Get-Content -LiteralPath $src -Raw -Encoding UTF8
            foreach ($tpl in $genericStalePatterns) {
                $pat = $tpl -f [regex]::Escape($doneId)
                if ($raw -match $pat) {
                    $msg = "$rel contradicts $doneId Done: still reads parked/not built/deferred"
                    if ($AuditMode) { Emit-Audit 'IMPROVE' $msg } else { Write-Fail $msg }
                    break
                }
            }
        }
    }
}

if ($AuditMode) {
    Write-Host "Summary: fix=$fix improve=$improve"
    exit 0
}

if ($fail -gt 0) {
    Write-Host "Summary: $fail fail(s)"
    exit 1
}
Write-Ok 'complete-picture handoff checks'
exit 0
