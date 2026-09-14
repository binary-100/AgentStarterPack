#Requires -Version 5.1
<#
.SYNOPSIS
  Mechanical checks that product-truth docs exist and do not contradict shipped work or code.
.DESCRIPTION
  Step 3c companion for bootstrapped apps. Resolves paths from docs/WORK_COMPLETION.md overlay
  (Product-truth docs table) or sensible defaults. Optional docs/.product_truth_verify.json
  declares doc/code claims. Skips path checks on the pack maintainer repo (no product overlay).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [switch]$AuditMode,
    [switch]$AllowMissing
)

$ErrorActionPreference = 'Stop'
# Get-PackRelPathKey: one spelling for a relative path on every OS.
. (Join-Path $PSScriptRoot 'pack-paths.ps1')
. (Join-Path $PSScriptRoot 'verify-lib.ps1')

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


function Normalize-ProductTruthRelPath([string]$rawPath) {
    if ([string]::IsNullOrWhiteSpace($rawPath)) { return $null }
    $p = $rawPath.Trim().Trim('`').Trim()
    if ($p -match '\{\{PROJECT_ROOT\}\}') {
        $p = $p -replace '\{\{PROJECT_ROOT\}\}\\?', ''
    }
    if ($p -match '^[A-Za-z]:\\') {
        $pr = $ProjectRoot.TrimEnd('\')
        if ($p.StartsWith($pr, [System.StringComparison]::OrdinalIgnoreCase)) {
            $p = Get-PackRelPathKey -Path $p -Root $pr
        }
    }
    $p = $p -replace '/', '\'
    if ($p -match '(?i)\s+or\s+') {
        $p = ($p -split '(?i)\s+or\s+')[0].Trim()
    }
    if ($p -match '(?i)install section') { return $null }
    if ($p -match '\*') { return $null }
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    return $p
}

function Get-ProductTruthPathsFromOverlay {
    $wcPath = Join-Path $ProjectRoot 'docs/WORK_COMPLETION.md'
    if (-not (Test-Path -LiteralPath $wcPath)) { return @() }
    $raw = Get-Content -LiteralPath $wcPath -Raw -Encoding UTF8
    if ($raw -notmatch '(?i)###\s+Product-truth docs') { return @() }
    $body = Get-PackSectionBody $raw '### Product-truth docs' @('---', '## ', '### ')
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($body -split "`r?`n")) {
        if ($line -notmatch '\|') { continue }
        if ($line -match '^\|\s*[-|]+\s*\|') { continue }
        if ($line -match '^\|\s*Role\s*\|') { continue }
        $cells = @($line -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        if ($cells.Count -lt 2) { continue }
        $pathCell = $cells[1]
        foreach ($m in [regex]::Matches($pathCell, '`([^`]+)`')) {
            $rel = Normalize-ProductTruthRelPath $m.Groups[1].Value
            if ($rel) { [void]$paths.Add($rel) }
        }
        if ($pathCell -notmatch '`') {
            $rel = Normalize-ProductTruthRelPath $pathCell
            if ($rel) { [void]$paths.Add($rel) }
        }
    }
    return @($paths | Select-Object -Unique)
}

function Get-DefaultProductTruthPaths {
    @(
        'docs\DOC_MAP.md',
        'docs\PRODUCT_REFERENCE.md',
        'docs\KNOWN_LIMITATIONS.md',
        'docs\ROADMAP.md'
    )
}

function Get-DoneWqIds {
    $wqPath = Join-Path $ProjectRoot 'docs/WORK_QUEUE.md'
    if (-not (Test-Path -LiteralPath $wqPath)) { return @() }
    $raw = Get-Content -LiteralPath $wqPath -Raw -Encoding UTF8
    $doneBody = Get-PackSectionBody $raw '## Done log' @('## Cross-references', '## ')
    @([regex]::Matches($doneBody, '\|\s*(WQ-\d+)\s*\|') | ForEach-Object { $_.Groups[1].Value })
}

function Test-ProductTruthFilesExist([string[]]$RelPaths) {
    foreach ($rel in $RelPaths) {
        $full = Join-Path $ProjectRoot $rel
        if (Test-Path -LiteralPath $full) {
            Write-Ok "product-truth path exists: $rel"
        } elseif ($AllowMissing) {
            Write-Info "product-truth path missing (allowed): $rel"
        } else {
            Write-Fail "product-truth path missing: $rel"
        }
    }
}

$staleShippedPatterns = @(
    '(?i)\bnot\s+(yet\s+)?implemented\b',
    '(?i)\bnot\s+built\b',
    '(?i)\b(still\s+)?deferred\b',
    '(?i)\bnot\s+shipped\b',
    '(?i)\bparked\s*-\s*not\s+building\b'
)

function Test-DoneWqProseContradictions([string[]]$DocRelPaths, [string[]]$DoneIds) {
    if ($DoneIds.Count -eq 0) { return }
    foreach ($rel in $DocRelPaths) {
        $full = Join-Path $ProjectRoot $rel
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $lines = Get-Content -LiteralPath $full -Encoding UTF8
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            foreach ($wqId in $DoneIds) {
                if ($line -notmatch [regex]::Escape($wqId)) { continue }
                $hit = $false
                foreach ($pat in $staleShippedPatterns) {
                    if ($line -match $pat) { $hit = $true; break }
                }
                if (-not $hit -and $i + 1 -lt $lines.Count) {
                    $next = $lines[$i + 1]
                    foreach ($pat in $staleShippedPatterns) {
                        if ($next -match $pat) { $hit = $true; break }
                    }
                }
                if ($hit) {
                    $msg = "$rel line $($i + 1): $wqId in Done log but prose reads not built/deferred"
                    if ($AuditMode) { Emit-Audit 'IMPROVE' $msg } else { Write-Fail $msg }
                }
            }
        }
    }
}

function Get-CodeMatchCount([string]$SearchRoot, [string]$GlobPattern, [string]$Pattern) {
    if (-not (Test-Path -LiteralPath $SearchRoot)) { return 0 }
    $count = 0
    $files = Get-ChildItem -LiteralPath $SearchRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-PackPathHasSegment -Path $_.FullName -Segment @('.git', '__pycache__', '.pytest_cache', 'node_modules')) }
    if ($GlobPattern -match '\*\.(\w+)$') {
        $ext = ".$($Matches[1])"
        $files = @($files | Where-Object { $_.Extension -eq $ext })
    } elseif ($GlobPattern -and $GlobPattern -ne '*.*') {
        $files = @($files | Where-Object { $_.Name -like $GlobPattern })
    }
    foreach ($f in $files) {
        try {
            $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop
            if ($text -match $Pattern) { $count++ }
        } catch { }
    }
    return $count
}

function Test-ProductTruthClaims([string[]]$DoneIds) {
    $cfgPath = Join-Path $ProjectRoot 'docs/.product_truth_verify.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) { return }
    try {
        $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Fail "docs/.product_truth_verify.json is not valid JSON: $_"
        return
    }
    if (-not $cfg.claims) {
        Write-Info 'product_truth_verify.json has no claims array'
        return
    }
    foreach ($claim in @($cfg.claims)) {
        $id = [string]$claim.id
        if (-not $id) { Write-Fail 'product_truth claim missing id'; continue }
        if ($claim.whenDoneWq) {
            $need = [string]$claim.whenDoneWq
            if ($DoneIds -notcontains $need) {
                Write-Info "claim $id skipped (whenDoneWq $need not in Done log)"
                continue
            }
        }
        $docRel = [string]$claim.doc
        if (-not $docRel) { Write-Fail "claim $id missing doc"; continue }
        $docFull = Join-Path $ProjectRoot ($docRel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $docFull)) {
            Write-Fail "claim $id doc missing: $docRel"
            continue
        }
        $docText = Get-Content -LiteralPath $docFull -Raw -Encoding UTF8
        if ($claim.docPattern) {
            if ($docText -notmatch [string]$claim.docPattern) {
                $msg = "claim $id docPattern not found in $docRel"
                if ($AuditMode) { Emit-Audit 'FIX' $msg } else { Write-Fail $msg }
            } else { Write-Ok "claim $id docPattern matched" }
        }
        if ($claim.docMustNotMatch) {
            if ($docText -match [string]$claim.docMustNotMatch) {
                $msg = "claim $id docMustNotMatch hit in $docRel"
                if ($AuditMode) { Emit-Audit 'FIX' $msg } else { Write-Fail $msg }
            } else { Write-Ok "claim $id docMustNotMatch clear" }
        }
        if ($claim.codePattern) {
            $glob = if ($claim.codeGlob) { [string]$claim.codeGlob } else { '*.py' }
            $root = if ($claim.codeRoot) { Join-Path $ProjectRoot ([string]$claim.codeRoot) } else { $ProjectRoot }
            $min = 1
            if ($null -ne $claim.minCodeMatches) { $min = [int]$claim.minCodeMatches }
            $hits = Get-CodeMatchCount $root $glob ([string]$claim.codePattern)
            if ($hits -lt $min) {
                $msg = "claim $id codePattern matched $hits file(s), need $min (glob $glob)"
                if ($AuditMode) { Emit-Audit 'FIX' $msg } else { Write-Fail $msg }
            } else { Write-Ok "claim $id codePattern matched $hits file(s)" }
        }
    }
}

$isPackRepo = (Test-Path -LiteralPath (Join-Path $ProjectRoot 'install.ps1')) -and
    (Test-Path -LiteralPath (Join-Path $ProjectRoot 'pack/audit/manifest.json'))
if ($isPackRepo) {
    Write-Info 'pack maintainer repo - no product-truth overlay; skipping path/claim checks'
    exit 0
}

$overlayPaths = Get-ProductTruthPathsFromOverlay
$relPaths = if ($overlayPaths.Count -gt 0) { $overlayPaths } else { Get-DefaultProductTruthPaths }
if ($overlayPaths.Count -gt 0) {
    Write-Ok "resolved $($overlayPaths.Count) product-truth path(s) from WORK_COMPLETION overlay"
} else {
    Write-Info 'no overlay table - using default product-truth path list'
}

Test-ProductTruthFilesExist $relPaths
$doneIds = Get-DoneWqIds
Test-DoneWqProseContradictions $relPaths $doneIds
Test-ProductTruthClaims $doneIds

if ($AuditMode) {
    if ($fix -gt 0 -or $improve -gt 0) { exit 1 }
    exit 0
}
if ($fail -gt 0) { exit 1 }
exit 0
