#Requires -Version 5.1
<#
.SYNOPSIS
  Validate docs/handoffs/ layout, registry tables, and WORK_QUEUE reconciliation.
.DESCRIPTION
  Audit mode (-AuditMode): emit [FIX] / [IMPROVE] / [INFO] for run_audit_core.ps1.
  Never deletes files. Archive-ready handoffs get Improve only after status=completed,
  WQ in Done log, and agents_remaining empty.
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
function Write-ImproveLine($m) { Write-Host "[IMPROVE] $m"; $script:improve++ }

function Emit-Audit($level, $m) {
    switch ($level) {
        'FIX' { Write-Host "[FIX] $m"; $script:fix++ }
        'IMPROVE' { Write-Host "[IMPROVE] $m"; $script:improve++ }
        'INFO' { Write-Host "[INFO] $m" }
    }
}

$fail = 0
$fix = 0
$improve = 0
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$docs = Join-Path $ProjectRoot 'docs'
$handoffs = Join-Path $docs 'handoffs'
$active = Join-Path $handoffs 'active'
$archive = Join-Path $docs 'handoff_archive'

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

function Parse-RegistryTable([string]$raw) {
    $result = @{}
    if ($raw -notmatch '## Handoff registry') { return $result }
    $body = Get-SectionBody $raw '## Handoff registry' @('**Session opener')
    $matches = [regex]::Matches($body, '\|\s*\*\*([^*]+)\*\*\s*\|\s*([^|]*?)\s*\|')
    foreach ($m in $matches) {
        $key = ($m.Groups[1].Value -replace '\s+', '_' ).Trim('_').ToLower()
        $val = $m.Groups[2].Value.Trim()
        if ($key) { $result[$key] = $val }
    }
    return $result
}

function Test-SessionOpener([string]$raw, [string]$kind) {
    if ($raw -notmatch 'Session opener \(only') { return $false }
    $verb = if ($kind -eq 'orientation') { 'confirm' } else { 'implement' }
    if ($raw -notmatch "and $verb") { return $false }
    # Require a root-anchored path inside the backtick opener (may be on the line after the label).
    # A real absolute path is the normal case. A placeholder root - <pack folder>\..., %PACK_ROOT%\...,
    # $env:SOMETHING\... - counts too, because a handoff written for *another* machine cannot name a
    # path that exists here, and hard-coding the sending machine's path into a tracked file is the
    # disclosure that machine-local classification exists to prevent. What stays banned is a bare
    # relative path, which opens the wrong file in whichever workspace happens to be current.
    if ($raw -match '`Read\s+([^`]+)\s+and\s+' + [regex]::Escape($verb) + '\.`') {
        $pathPart = $Matches[1].Trim()
        if ($pathPart -match '^[A-Za-z]:\\' -or $pathPart -match '^/') { return $true }
        if ($pathPart -match '^(<[^>]+>|%[^%]+%|\$env:[A-Za-z_][A-Za-z0-9_]*)[\\/]') { return $true }
    }
    return $false
}

function Get-WqIdsFromSection([string]$body) {
    @([regex]::Matches($body, '\|\s*(WQ-\d+)\s*\|') | ForEach-Object { $_.Groups[1].Value })
}

function Get-RegVal([hashtable]$reg, [string]$key) {
    if ($reg.ContainsKey($key) -and $null -ne $reg[$key]) { return [string]$reg[$key] }
    return ''
}

$wqPath = Join-Path $docs 'WORK_QUEUE.md'
$doneIds = [System.Collections.Generic.HashSet[string]]::new()
$activeWqIds = [System.Collections.Generic.HashSet[string]]::new()
if (Test-Path -LiteralPath $wqPath) {
    $wqRaw = Get-Content -LiteralPath $wqPath -Raw -Encoding UTF8
    $doneBody = Get-SectionBody $wqRaw '## Done log' @('## Cross-references', '---', '**Agents:**')
    $activeBody = Get-SectionBody $wqRaw '## Active queue' @('## Inbox', '## Engineering backlog', '## Parked', '## Done log')
    foreach ($id in (Get-WqIdsFromSection $doneBody)) { [void]$doneIds.Add($id) }
    foreach ($id in (Get-WqIdsFromSection $activeBody)) { [void]$activeWqIds.Add($id) }
} elseif (-not $AllowMissing) {
    if ($AuditMode) { Emit-Audit 'INFO' 'WORK_QUEUE.md missing -  handoff/WQ cross-check skipped' }
    else { Write-Info 'WORK_QUEUE missing -  WQ cross-check skipped' }
}

$handoffFiles = [System.Collections.Generic.List[string]]::new()

# Legacy names at docs root
Get-ChildItem -LiteralPath $docs -Filter 'AGENT_HANDOFF_*.md' -File -ErrorAction SilentlyContinue |
    ForEach-Object { [void]$handoffFiles.Add($_.FullName) }

if (Test-Path -LiteralPath $handoffs) {
    Get-ChildItem -LiteralPath $handoffs -Filter 'HANDOFF_*.md' -File -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$handoffFiles.Add($_.FullName) }
}
if (Test-Path -LiteralPath $active) {
    Get-ChildItem -LiteralPath $active -Filter 'HANDOFF_*.md' -File -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$handoffFiles.Add($_.FullName) }
}

if ($handoffFiles.Count -eq 0 -and -not (Test-Path -LiteralPath $handoffs)) {
    if ($AllowMissing) {
        Write-Info 'No handoffs/ folder (allowed)'
        exit 0
    }
}

foreach ($fp in $handoffFiles) {
    $rel = $fp.Substring($ProjectRoot.Length).TrimStart('\', '/')
    $raw = Get-Content -LiteralPath $fp -Raw -Encoding UTF8

    if ($rel -match 'AGENT_HANDOFF_') {
        $msg = "Legacy handoff path -  migrate to docs/handoffs/ per pack/docs/AGENT_HANDOFFS.md: $rel"
        if ($AuditMode) { Emit-Audit 'IMPROVE' $msg } else { Write-Fail $msg }
        continue
    }

    $reg = Parse-RegistryTable $raw
    $kind = (Get-RegVal $reg 'kind').ToLower()
    $status = (Get-RegVal $reg 'status').ToLower()
    $multi = (Get-RegVal $reg 'multi_agent').ToLower()
    if ([string]::IsNullOrWhiteSpace($multi)) { $multi = 'no' }
    $wqId = (Get-RegVal $reg 'wq_id').Trim()
    $remaining = (Get-RegVal $reg 'agents_remaining').Trim()
    $handoffId = (Get-RegVal $reg 'handoff_id').Trim()

    if (-not $reg.Count) {
        $msg = "Handoff missing ## Handoff registry table: $rel"
        if ($AuditMode) { Emit-Audit 'FIX' $msg } else { Write-Fail $msg }
        continue
    }

    if (-not (Test-SessionOpener $raw $kind)) {
        $msg = "Handoff missing single session opener with a root-anchored path - absolute, or a placeholder root like <pack folder>\... (and implement/confirm): $rel"
        if ($AuditMode) { Emit-Audit 'FIX' $msg } else { Write-Fail $msg }
    }

    if ($kind -eq 'build' -and $rel -notmatch 'handoffs[/\\]active[/\\]') {
        $msg = "Build handoff should live under docs/handoffs/active/: $rel"
        if ($AuditMode) { Emit-Audit 'IMPROVE' $msg } else { Write-Info $msg }
    }

    if ($kind -eq 'build' -and $wqId -and $doneIds.Contains($wqId) -and $status -eq 'active') {
        $msg = "Handoff status still active but $wqId is in WORK_QUEUE Done -  set status: completed on $rel"
        if ($AuditMode) { Emit-Audit 'FIX' $msg } else { Write-Fail $msg }
    }

    if ($status -eq 'completed' -and $wqId -and -not $doneIds.Contains($wqId)) {
        $msg = "Handoff completed but $wqId not in WORK_QUEUE Done log -  reconcile WQ or handoff: $rel"
        if ($AuditMode) { Emit-Audit 'FIX' $msg } else { Write-Fail $msg }
    }

    $canArchive = ($status -eq 'completed') -and ($multi -ne 'yes' -or [string]::IsNullOrWhiteSpace($remaining))
    if ($multi -eq 'yes' -and -not [string]::IsNullOrWhiteSpace($remaining)) {
        if ($AuditMode) {
            Emit-Audit 'INFO' "Multi-agent handoff in progress ($handoffId) -  agents_remaining set; audit will not suggest archive"
        }
        continue
    }

    if ($canArchive -and $wqId -and $doneIds.Contains($wqId)) {
        $label = if ($handoffId) { $handoffId } else { $rel }
        $msg = "Handoff $label verified complete (WQ Done + status completed) -  move to docs/handoff_archive/ after semantic review; audit does not auto-delete"
        if ($AuditMode) { Emit-Audit 'IMPROVE' $msg } else { Write-Ok $msg }
    } elseif ($canArchive -and -not $wqId -and $kind -eq 'orientation') {
        $msg = "Orientation handoff completed -  archive to docs/handoff_archive/ when superseded: $rel"
        if ($AuditMode) { Emit-Audit 'IMPROVE' $msg } else { Write-Info $msg }
    }

    if ($kind -eq 'build' -and $status -eq 'active' -and $wqId -and -not $activeWqIds.Contains($wqId) -and -not $doneIds.Contains($wqId)) {
        $msg = "Active build handoff $wqId not in WORK_QUEUE Active -  reconcile queue or handoff status: $rel"
        if ($AuditMode) { Emit-Audit 'IMPROVE' $msg } else { Write-Info $msg }
    }
}

# Duplicate active build handoffs for same WQ
if (Test-Path -LiteralPath $active) {
    $byWq = @{}
    Get-ChildItem -LiteralPath $active -Filter 'HANDOFF_*.md' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $r = Parse-RegistryTable (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8)
        $wq = (Get-RegVal $r 'wq_id').Trim()
        if ($wq -and (Get-RegVal $r 'status').ToLower() -eq 'active') {
            if (-not $byWq.ContainsKey($wq)) { $byWq[$wq] = @() }
            $byWq[$wq] += $_.Name
        }
    }
    foreach ($wq in $byWq.Keys) {
        if ($byWq[$wq].Count -gt 1) {
            $msg = "Multiple active handoffs for $wq : $($byWq[$wq] -join ', ')"
            if ($AuditMode) { Emit-Audit 'FIX' $msg } else { Write-Fail $msg }
        }
    }
}

if ($AuditMode) {
    if ($fix -gt 0) { exit 2 }
    exit 0
}

if ($fail -gt 0) {
    Write-Host "Summary: $fail fail(s)"
    exit 1
}
Write-Ok 'Handoff layout and registry checks passed'
exit 0
