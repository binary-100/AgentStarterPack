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

function Write-Ok($m) { Write-Host "[OK] $m" }
function Write-Fail($m) { Write-Host "[FAIL] $m"; $script:fail++ }

$fail = 0
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$path = Join-Path $ProjectRoot 'docs\WORK_QUEUE.md'

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
    $body = Get-SectionBody $raw $def.Start $def.Ends
    $ids = @([regex]::Matches($body, '\|\s*(WQ-\d+)\s*\|') | ForEach-Object { $_.Groups[1].Value })
    $idBySection[$name] = $ids
    foreach ($id in $ids) { [void]$allIds.Add($id) }
}

$dupGroups = $allIds | Group-Object | Where-Object { $_.Count -gt 1 }
foreach ($g in $dupGroups) {
    $where = @($sectionDefs.Keys | Where-Object { $idBySection[$_] -contains $g.Name }) -join ', '
    Write-Fail "duplicate ID $($g.Name) appears in: $where"
}

$activeBody = Get-SectionBody $raw '## Active queue' @('## Inbox', '## Engineering backlog', '## Parked', '## Done log', '## Cross-references')
$nextRows = @([regex]::Matches($activeBody, '\|\s*WQ-\d+\s*\|[^|]*\|\s*\*\*Next\*\*') )
if ($nextRows.Count -eq 0) {
    Write-Fail 'Active queue has no row with status **Next**'
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
