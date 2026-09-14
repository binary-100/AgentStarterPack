#Requires -Version 5.1
<#
.SYNOPSIS
  Validate docs/WORK_QUEUE.md structure and WQ ID reconciliation.
.DESCRIPTION
  Hard checks: required sections, unique WQ IDs across sections, exactly one **Next** in Active.
  Exit 0 when valid; exit 1 with [FAIL] lines when not.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [switch]$AllowMissing
)

$ErrorActionPreference = 'Stop'

# Path keys for the historical-region checks below. Dot-sourced rather than assumed in scope: a
# helper that is merely referenced silently becomes a null comparison, which reads as a pass.
. (Join-Path $PSScriptRoot 'pack-paths.ps1')
. (Join-Path $PSScriptRoot 'verify-lib.ps1')

function Write-Ok($m) { Write-Host "[OK] $m" }
function Write-Fail($m) { Write-Host "[FAIL] $m"; $script:fail++ }

$fail = 0
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$path = Join-Path $ProjectRoot 'docs/WORK_QUEUE.md'

if (-not (Test-Path -LiteralPath $path)) {
    if ($AllowMissing) {
        Write-Host "[WARN] WORK_QUEUE missing (allowed): $path"
        exit 0
    }
    Write-Fail "WORK_QUEUE missing: $path (run ensure-work-queue.ps1 or refresh-agent-context)"
    exit 1
}

$raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
$lines = $raw -split "`r?`n"

# Control characters mean something wrote this file through a broken escape rather than as text. A row
# added from a PowerShell double-quoted string turned `a into a bell and `v into a vertical tab, eating
# the first letter of five filenames; the row still rendered as a table, so a full audit certified it.
# Tab, CR and LF are the only control characters a queue legitimately contains.
$ctrl = [regex]::Matches($raw, '[\x00-\x08\x0B\x0C\x0E-\x1F]')
if ($ctrl.Count -gt 0) {
    $where = @($ctrl | Select-Object -First 3 | ForEach-Object {
        $lineNo = @($raw.Substring(0, $_.Index) -split "`n").Count
        "line $lineNo (char $([int][char]$_.Value))"
    })
    Write-Fail ("$($ctrl.Count) control character(s) in the queue - text was written through an escape " +
        "sequence instead of literally: $($where -join ', ')")
}

$requiredSections = @(
    '## Active queue',
    '## Inbox',
    '## Parked / deferred',
    '## Done log'
)
foreach ($hdr in $requiredSections) {
    if ($raw -notmatch [regex]::Escape($hdr)) {
        Write-Fail "missing section header: $hdr"
    }
}
if (-not ($raw -match '## Engineering backlog')) {
    Write-Host '[INFO] no Engineering backlog section (optional for new projects)'
}


$sectionDefs = [ordered]@{
    Active      = @{ Start = '## Active queue'; Ends = @('## Inbox', '## Engineering backlog', '## Parked', '## Done log', '## Cross-references') }
    Inbox       = @{ Start = '## Inbox'; Ends = @('## Engineering backlog', '## Parked', '## Done log', '## Cross-references') }
    Engineering = @{ Start = '## Engineering backlog'; Ends = @('## Parked', '## Done log', '## Cross-references') }
    Parked      = @{ Start = '## Parked / deferred'; Ends = @('## Done log', '## Cross-references') }
    Done        = @{ Start = '## Done log'; Ends = @('## Cross-references') }
}

$idBySection = @{}
$allIds = [System.Collections.Generic.List[string]]::new()

foreach ($name in $sectionDefs.Keys) {
    $def = $sectionDefs[$name]
    $body = Get-PackSectionBody $raw $def.Start $def.Ends
    $ids = @([regex]::Matches($body, '\|\s*(WQ-\d+)\s*\|') | ForEach-Object { $_.Groups[1].Value })
    $idBySection[$name] = $ids
    foreach ($id in $ids) { [void]$allIds.Add($id) }
}

$dupGroups = $allIds | Group-Object | Where-Object { $_.Count -gt 1 }
foreach ($g in $dupGroups) {
    $where = @($sectionDefs.Keys | Where-Object { $idBySection[$_] -contains $g.Name }) -join ', '
    Write-Fail "duplicate ID $($g.Name) appears in: $where"
}

$activeBody = Get-PackSectionBody $raw '## Active queue' @('## Inbox', '## Engineering backlog', '## Parked', '## Done log', '## Cross-references')
$nextRows = @([regex]::Matches($activeBody, '\|\s*WQ-\d+\s*\|[^|]*\|\s*\*\*Next\*\*') )
$headerAllowsEmpty = ($raw -match '\*\*Next active ID\*\*\s*\|\s*\*\(none')
if ($nextRows.Count -eq 0) {
    if ($headerAllowsEmpty) {
        Write-Ok 'Active queue has no **Next** row (header allows none - triage Parked/Inbox)'
    } else {
        Write-Fail 'Active queue has no row with status **Next**'
    }
} elseif ($nextRows.Count -gt 1) {
    Write-Fail "Active queue has $($nextRows.Count) **Next** rows (must be exactly 1)"
} else {
    Write-Ok 'exactly one **Next** in Active queue'
}

if ($raw -match '\*\*Next active ID\*\*\s*\|\s*\*\*(WQ-\d+)') {
    $headerNext = $Matches[1]
    $activeNext = [regex]::Match($activeBody, '\|\s*(WQ-\d+)\s*\|[^|]*\|\s*\*\*Next\*\*').Groups[1].Value
    if ($activeNext -and $headerNext -ne $activeNext -and $headerNext -notmatch [regex]::Escape($activeNext)) {
        Write-Fail "header Next active ID ($headerNext) does not match Active **Next** row ($activeNext)"
    } else {
        Write-Ok 'header Next active ID aligns with Active queue'
    }
}

$versionPath = Join-Path $ProjectRoot 'VERSION'
$manifestPath = Join-Path $ProjectRoot 'pack/audit/manifest.json'
if ((Test-Path -LiteralPath $versionPath) -and (Test-Path -LiteralPath $manifestPath)) {
    $canonicalPack = (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim()
    if ($canonicalPack -match '(\d+\.\d+\.\d+)') { $canonicalPack = $Matches[1] }
    $manifestJson = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $canonicalAudit = [string]$manifestJson.version
    if ($raw -match '\|\s*\*\*Pack version\*\*\s*\|\s*(\d+\.\d+\.\d+)\s*\|') {
        $wqPack = $Matches[1]
        if ($wqPack -ne $canonicalPack) {
            Write-Fail "WORK_QUEUE Pack version ($wqPack) != root VERSION ($canonicalPack) - run $(Get-PackEntryPoint 'Sync-DocVersions')"
        } else {
            Write-Ok 'WORK_QUEUE Pack version aligns with VERSION'
        }
    } else {
        Write-Fail 'WORK_QUEUE header missing **Pack version** row'
    }
    if ($raw -match '\|\s*\*\*Audit engine\*\*\s*\|\s*(\d+\.\d+\.\d+)\s*\|') {
        $wqAudit = $Matches[1]
        if ($wqAudit -ne $canonicalAudit) {
            Write-Fail "WORK_QUEUE Audit engine ($wqAudit) != manifest ($canonicalAudit) - run $(Get-PackEntryPoint 'Sync-DocVersions')"
        } else {
            Write-Ok 'WORK_QUEUE Audit engine aligns with manifest'
        }
    } else {
        Write-Fail 'WORK_QUEUE header missing **Audit engine** row'
    }
}

# The header rows above are the only version cites in this file that may move on a bump. Every
# Done-log row carries a historical one - which engine shipped that item - and four of those were
# rewritten in two days by blanket replaces, twice in a single session (WQ-437). doc_version_sync
# now refuses to touch anything below the Done-log heading, but only because VERSION_SYNC.json says
# where that heading is. Deleting the entry would remove the protection with nothing failing, so
# the declaration is checked here rather than trusted.
$vsPath = Join-Path $ProjectRoot 'docs/VERSION_SYNC.json'
if (Test-Path -LiteralPath $vsPath) {
    try {
        $vsJson = Get-Content -LiteralPath $vsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $wqRegion = @($vsJson.historicalRegions | Where-Object {
                $_.file -and ((ConvertTo-PackPathKey $_.file) -eq 'docs/WORK_QUEUE.md')
            }) | Select-Object -First 1
        if (-not $wqRegion) {
            Write-Fail ('VERSION_SYNC.json declares no historicalRegions entry for docs/WORK_QUEUE.md - ' +
                'a bump would rewrite Done-log cites, which are claims about the past (WQ-437)')
        } elseif (-not $wqRegion.fromHeading) {
            Write-Fail 'VERSION_SYNC.json historicalRegions entry for docs/WORK_QUEUE.md has no fromHeading'
        } else {
            $heading = ([string]$wqRegion.fromHeading).TrimStart('#').Trim()
            $hasHeading = @($raw -split "`n" | Where-Object {
                    $_.Trim().StartsWith('#') -and $_.Trim().TrimStart('#').Trim() -eq $heading
                }).Count -gt 0
            if (-not $hasHeading) {
                Write-Fail "VERSION_SYNC.json freezes WORK_QUEUE from '$($wqRegion.fromHeading)' but no such heading exists - the whole file is being synced"
            } else {
                Write-Ok "Done log is declared a historical region (frozen from '$($wqRegion.fromHeading)')"
            }
        }
    } catch {
        Write-Fail "could not read docs/VERSION_SYNC.json: $_"
    }
}

# Backstop for the hand-edit case the sync boundary cannot reach. The script is safe now, but the
# corruption never came from the script - it came from an agent running a blanket replace across the
# file. Those rewrites always look the same from here: the version being bumped *from* stops being
# cited anywhere in the Done log. So the set of engine versions the Done log cites may only grow.
#
# Known blind spot, stated rather than papered over: the comparison is against git HEAD, so a row
# added and then corrupted before its first commit is invisible to this check - which is exactly
# how the four known cases happened, in a checkout carrying nine unpublished releases. It catches
# the repeat once history is committed, which is when the damage becomes permanent.
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
$doneHeadingRx = '(?m)^#{1,6}\s+Done log\s*$'
if (-not $gitCmd) {
    Write-Host '[SKIP] git not on PATH - cannot compare Done-log cites against history'
} elseif (-not (Test-PackGitRepo -Root $ProjectRoot)) {
    # Asks git, not the filesystem: a deleted repository can leave a .git directory behind (an
    # editor's index cache lives there), and then `git show HEAD:...` fails the whole script on a
    # tree that is simply not versioned (WQ-461).
    Write-Host '[SKIP] not a git checkout - no history to compare Done-log cites against'
} elseif (-not (Test-PackGitRoot -Root $ProjectRoot)) {
    # A nested project root (e.g. behavior-fixture) sits inside a parent repo's work tree but its
    # docs/WORK_QUEUE.md is not at HEAD:docs/WORK_QUEUE.md - comparing would read the wrong file.
    Write-Host '[SKIP] not the git repository root - Done-log cite comparison runs at root only'
} elseif ($raw -notmatch $doneHeadingRx) {
    Write-Host '[SKIP] no Done log section to compare'
} else {
    $relForGit = (ConvertTo-PackPathKey (Get-PackRelPathKey -Path $path -Root $ProjectRoot))
    $gitErr = ''
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $headText = (& $gitCmd.Source -C $ProjectRoot show "HEAD:$relForGit" 2>&1 |
            ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) { $gitErr += "$_`n"; } else { $_ }
            }) -join "`n"
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if (-not $headText) {
        # Distinguished rather than lumped together: "no committed version yet" is a true statement
        # about a new file and a false one about a repo git declined to read, and reporting the
        # second as the first sent a probe of this very check looking in the wrong place.
        if ($gitErr -match 'dubious ownership') {
            Write-Host '[SKIP] git declined to read this repo (dubious ownership) - cannot compare Done-log cites'
        } else {
            Write-Host '[SKIP] WORK_QUEUE has no committed version yet'
        }
    } else {
        function Get-DoneCites {
            param([string]$Text)
            $m = [regex]::Match($Text, $doneHeadingRx)
            if (-not $m.Success) { return @() }
            $body = $Text.Substring($m.Index + $m.Length)
            return @([regex]::Matches($body, '[Ee]ngine\s+\*{0,2}(\d+\.\d+\.\d+)\*{0,2}') |
                ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        }
        $nowCites = @(Get-DoneCites -Text $raw)
        $headCites = @(Get-DoneCites -Text $headText)
        $lost = @($headCites | Where-Object { $nowCites -notcontains $_ })
        if ($lost.Count -gt 0) {
            Write-Fail ("Done log no longer cites engine version(s) it cited at git HEAD: " +
                ($lost -join ', ') + " - a bump rewrote a historical cite; restore it and bump with $(Get-PackEntryPoint 'Sync-DocVersions') (WQ-437)")
        } else {
            Write-Ok "Done-log engine cites only grew ($($headCites.Count) at HEAD, $($nowCites.Count) now)"
        }
    }
}

# Done rows must not remain in Inbox/Active with open status (WQ ID in Done + elsewhere)
$doneIds = @($idBySection['Done'])
foreach ($id in $doneIds) {
    foreach ($sec in @('Active', 'Inbox', 'Engineering', 'Parked')) {
        if ($idBySection[$sec] -contains $id) {
            Write-Fail "ID $id is in Done log and still listed under $sec"
        }
    }
}

$idSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$allIds.ToArray())
Write-Host "WORK_QUEUE: $($idSet.Count) unique WQ ID(s) across sections at $path"

if ($fail -gt 0) {
    Write-Host "Summary: $fail fail(s)"
    exit 1
}
Write-Ok 'WORK_QUEUE structure and ID reconciliation'
exit 0
