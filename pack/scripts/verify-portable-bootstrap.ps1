#Requires -Version 5.1
<#
.SYNOPSIS
  Verify a bootstrapped project matches its -Targets profile (Portable vs editor adapters).
.PARAMETER ProjectRoot
  Bootstrapped project root.
.PARAMETER RequirePortableOnly
  Exit 1 unless .agent-bootstrap.json targets are exactly Portable.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [switch]$RequirePortableOnly
)

$script:fail = 0
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

. (Join-Path $PSScriptRoot 'pack-paths.ps1')

function Write-Ok($m) { Write-Host "[OK] $m" }
function Write-Fail($m) { Write-Host "[FAIL] $m"; $script:fail++ }
function Write-Warn($m) { Write-Host "[WARN] $m" }

# What a generated project must contain comes from projectRequired.flatLayout in the pack manifest,
# not from a list here. This file used to name five paths while the manifest declared nine, so a
# project could be missing four audit entry points and still be reported portable - the audit would
# then fail on the user's machine, not in this check. The literals below are the portable-specific
# extras the manifest does not cover.
$portableExtras = @('AI_INSTRUCTIONS.md', 'AGENTS.md', 'docs\WORK_QUEUE.md')
$required = $portableExtras
$pbPackRoot = Get-SourceAgentStarterPack
if (-not $pbPackRoot) { $pbPackRoot = Get-AgentStarterPackRoot }
if ($pbPackRoot) {
    $pbManifestPath = Get-PackManifestPath -Root $pbPackRoot
    if (Test-Path -LiteralPath $pbManifestPath) {
        $pbManifest = Get-Content -LiteralPath $pbManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $flat = $pbManifest.projectRequired.flatLayout
        if ($flat) {
            foreach ($prop in $flat.PSObject.Properties) {
                $required += ($prop.Value -replace '/', '\')
            }
        }
    }
}
$required = @($required | Select-Object -Unique)
if ($required.Count -le $portableExtras.Count) {
    Write-Warn 'pack manifest not readable - checking only the portable-specific files, not the audit entry points'
}
foreach ($rel in $required) {
    $p = Join-Path $ProjectRoot $rel
    if (-not (Test-Path -LiteralPath $p)) { Write-Fail "missing required file: $rel" }
    else { Write-Ok "present: $rel" }
}

$aiPath = Join-Path $ProjectRoot 'AI_INSTRUCTIONS.md'
if (Test-Path -LiteralPath $aiPath) {
    $aiText = Get-Content -LiteralPath $aiPath -Raw -Encoding UTF8
    if ($aiText -notmatch 'GENERIC_RULES\.md' -and $aiText -notmatch 'portable/GENERIC_RULES') {
        Write-Fail 'AI_INSTRUCTIONS.md does not point at portable GENERIC_RULES'
    } else { Write-Ok 'AI_INSTRUCTIONS.md cites portable GENERIC_RULES' }
    if ($aiText -notmatch 'user verifies') {
        Write-Fail 'AI_INSTRUCTIONS.md missing execute/verify discipline (user verifies)'
    } else { Write-Ok 'AI_INSTRUCTIONS.md cites execute/verify discipline' }
    if ($aiText -notmatch 'AGENT_SESSION_START') {
        Write-Fail 'AI_INSTRUCTIONS.md missing AGENT_SESSION_START session-start pointer'
    } else { Write-Ok 'AI_INSTRUCTIONS.md cites AGENT_SESSION_START' }
}

$localRules = Join-Path $ProjectRoot 'docs/portable/GENERIC_RULES.md'
if (-not (Test-Path -LiteralPath $localRules)) {
    Write-Fail 'missing docs/portable/GENERIC_RULES.md (run refresh or repair-agent-docs.ps1)'
} else { Write-Ok 'present: docs/portable/GENERIC_RULES.md' }

$bootstrapPath = Join-Path $ProjectRoot '.agent-bootstrap.json'
$targets = @()
if (Test-Path -LiteralPath $bootstrapPath) {
    try {
        $boot = Get-Content -LiteralPath $bootstrapPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $targets = @($boot.targets)
        Write-Ok "bootstrap targets: $($targets -join ', ')"
    } catch {
        Write-Fail '.agent-bootstrap.json did not parse'
    }
} else {
    Write-Warn 'no .agent-bootstrap.json - skipping target profile checks'
}

$editorNames = @('All', 'Cursor', 'Claude', 'Copilot', 'Windsurf')
$hasEditorTarget = $false
foreach ($name in $editorNames) {
    if ($targets -contains $name) { $hasEditorTarget = $true; break }
}
$portableOnly = ($targets.Count -eq 1 -and $targets[0] -eq 'Portable')

if ($RequirePortableOnly -and -not $portableOnly) {
    Write-Fail "expected targets exactly Portable, got: $($targets -join ', ')"
}

if ($portableOnly -or ($targets -contains 'Portable' -and -not $hasEditorTarget)) {
    foreach ($orphan in @(
            @{ Path = '.cursor\rules\version-sync.mdc'; Label = 'Cursor version-sync rule' },
            @{ Path = 'CLAUDE.md'; Label = 'Claude entry' },
            @{ Path = '.github\copilot-instructions.md'; Label = 'Copilot entry' },
            @{ Path = '.windsurfrules'; Label = 'Windsurf entry' }
        )) {
        if (Test-Path -LiteralPath (Join-Path $ProjectRoot $orphan.Path)) {
            Write-Fail "Portable-only bootstrap has orphan $($orphan.Label): $($orphan.Path)"
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.cursor/rules/audit.mdc'))) {
        Write-Fail 'missing .cursor/rules/audit.mdc (required for audit wiring on all targets)'
    } else { Write-Ok 'audit.mdc present (required on all targets)' }
    if ($script:fail -eq 0) { Write-Ok 'Portable-only bootstrap profile' }
} elseif ($targets.Count -gt 0) {
    if ($targets -contains 'Claude' -and -not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'CLAUDE.md'))) {
        Write-Fail 'targets include Claude but CLAUDE.md is missing'
    }
    if ($targets -contains 'Copilot' -and -not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.github/copilot-instructions.md'))) {
        Write-Fail 'targets include Copilot but .github/copilot-instructions.md is missing'
    }
    if ($targets -contains 'Windsurf' -and -not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.windsurfrules'))) {
        Write-Fail 'targets include Windsurf but .windsurfrules is missing'
    }
    if ($script:fail -eq 0) { Write-Ok 'editor target files match bootstrap manifest' }
}

if ($script:fail -gt 0) {
    Write-Host "Summary: $($script:fail) fail(s)"
    exit 1
}
Write-Ok 'portable bootstrap verification'
exit 0
