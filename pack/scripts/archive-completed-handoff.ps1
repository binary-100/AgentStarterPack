#Requires -Version 5.1
<#
.SYNOPSIS
  Preview or move completed build handoffs to docs/handoff_archive/.
.DESCRIPTION
  DEFAULT IS PREVIEW ONLY - no filesystem changes unless -Apply.

  Moves (never deletes) a handoff when ALL gates pass:
  - docs/handoffs/active/HANDOFF_*.md
  - kind=build, status=completed, completed: date set, wq_id in WORK_QUEUE Done
  - agents_remaining empty
  - verify-agent-handoffs.ps1 exit 0 (unless -SkipVerify)
  - destination file does not exist (unless -Apply -Force)

  Agents should run without -Apply unless the user explicitly confirmed archive.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [switch]$Apply,
    [switch]$Force,
    [switch]$SkipVerify,
    [string]$HandoffName
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
. (Join-Path $PSScriptRoot 'pack-paths.ps1')
$docs = Join-Path $ProjectRoot 'docs'
$active = Join-Path $docs 'handoffs\active'
$archive = Join-Path $docs 'handoff_archive'
$wqPath = Join-Path $docs 'WORK_QUEUE.md'
$packRoot = Get-SourceAgentStarterPack
if (-not $packRoot) { $packRoot = Get-AgentStarterPackRoot }
$verifyScript = if ($packRoot) { Join-Path $packRoot 'pack\scripts\verify-agent-handoffs.ps1' } else { '' }

function Write-Preview([string]$m) { Write-Host "[PREVIEW] $m" }
function Write-Skip([string]$m) { Write-Host "[SKIP] $m" }
function Write-Err([string]$m) { Write-Host "[ERROR] $m"; $script:errors++ }

$errors = 0
$eligible = 0
$moved = 0

if (-not (Test-Path -LiteralPath $active)) {
    Write-Host "[INFO] No docs/handoffs/active/ - nothing to archive"
    exit 0
}

if (-not $SkipVerify) {
    if (-not (Test-Path -LiteralPath $verifyScript)) {
        Write-Err "verify-agent-handoffs.ps1 not found at $verifyScript (use -SkipVerify only if human accepts risk)"
        exit 2
    }
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $verifyScript -ProjectRoot $ProjectRoot 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Err "verify-agent-handoffs.ps1 failed (exit $LASTEXITCODE) - fix handoff/WQ drift before archive"
        exit 2
    }
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

$doneIds = [System.Collections.Generic.HashSet[string]]::new()
if (Test-Path -LiteralPath $wqPath) {
    $wqRaw = Get-Content -LiteralPath $wqPath -Raw -Encoding UTF8
    $doneBody = Get-SectionBody $wqRaw '## Done log' @('## Cross-references', '---', '**Agents:**')
    foreach ($m in [regex]::Matches($doneBody, '\|\s*(WQ-\d+)\s*\|')) {
        [void]$doneIds.Add($m.Groups[1].Value)
    }
} else {
    Write-Err "docs/WORK_QUEUE.md missing - cannot confirm WQ Done"
    exit 2
}

$files = Get-ChildItem -LiteralPath $active -Filter 'HANDOFF_*.md' -File -ErrorAction SilentlyContinue
if ($HandoffName) {
    $files = @($files | Where-Object { $_.Name -eq $HandoffName })
    if ($files.Count -eq 0) {
        Write-Err "Handoff not found in active/: $HandoffName"
        exit 2
    }
}

foreach ($item in $files) {
    $raw = Get-Content -LiteralPath $item.FullName -Raw -Encoding UTF8
    $reg = Parse-RegistryTable $raw
    $kind = if ($reg['kind']) { $reg['kind'].Trim().ToLower() } else { '' }
    $status = if ($reg['status']) { $reg['status'].Trim().ToLower() } else { '' }
    $wq = if ($reg['wq_id']) { $reg['wq_id'].Trim() } else { '' }
    $remaining = if ($reg['agents_remaining']) { $reg['agents_remaining'].Trim() } else { '' }
    $completedDate = if ($reg['completed']) { $reg['completed'].Trim() } else { '' }
    $label = $item.Name

    if ($kind -ne 'build') {
        Write-Skip "$label - kind is '$kind' (only build handoffs in active/ are archived here)"
        continue
    }
    if ($status -ne 'completed') {
        Write-Skip "$label - status is '$status' (need completed)"
        continue
    }
    if ([string]::IsNullOrWhiteSpace($completedDate)) {
        Write-Skip "$label - completed: date empty in registry"
        continue
    }
    if ([string]::IsNullOrWhiteSpace($wq)) {
        Write-Skip "$label - wq_id empty (build handoffs require WQ Done match)"
        continue
    }
    if (-not $doneIds.Contains($wq)) {
        Write-Skip "$label - $wq not in WORK_QUEUE Done log"
        continue
    }
    if (-not [string]::IsNullOrWhiteSpace($remaining)) {
        Write-Skip "$label - agents_remaining is not empty"
        continue
    }

    $dest = Join-Path $archive $item.Name
    if ((Test-Path -LiteralPath $dest) -and -not $Force) {
        Write-Skip "$label - already exists at $dest (use -Force with -Apply to overwrite - not recommended)"
        continue
    }

    $eligible++
    if (-not $Apply) {
        Write-Preview "Would move $($item.FullName) -> $dest"
        continue
    }

    if (-not (Test-Path -LiteralPath $archive)) {
        New-Item -ItemType Directory -Path $archive -Force | Out-Null
    }
    if ((Test-Path -LiteralPath $dest) -and $Force) {
        Write-Host "[WARN] Overwriting existing archive file: $dest"
    }
    Move-Item -LiteralPath $item.FullName -Destination $dest -Force:$Force
    Write-Host "[OK] Archived $label -> $dest"
    $moved++
}

if (-not $Apply) {
    if ($eligible -eq 0) {
        Write-Host "[INFO] No handoffs pass archive gates (preview only, no changes made)"
    } else {
        Write-Host "[INFO] Preview only - $eligible handoff(s) eligible. Re-run with -Apply after human confirms."
    }
    exit 0
}

if ($moved -eq 0) {
    Write-Host "[INFO] -Apply set but nothing moved (see SKIP and ERROR lines above)"
}
exit 0
