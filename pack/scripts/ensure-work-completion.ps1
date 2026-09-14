#Requires -Version 5.1
<#
.SYNOPSIS
  Create docs/WORK_COMPLETION.md and handoffs scaffold when missing (never overwrite existing).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [string]$PackRoot = '',
    [string]$ProjectName = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

if (-not $PackRoot) {
    $PackRoot = Get-SourceAgentStarterPack
    if (-not $PackRoot) { $PackRoot = Get-AgentStarterPackRoot }
}
if (-not $PackRoot -or -not (Test-Path -LiteralPath $PackRoot)) {
    Write-Host 'ERROR: cannot resolve Agent Starter Pack root for WORK_COMPLETION template.'
    exit 1
}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not $ProjectName) { $ProjectName = Split-Path $ProjectRoot -Leaf }

# Pack trees (maintainer working copy and Zone B repo/ after B09 sync) never get generated handoffs
# or WORK_COMPLETION overlays. Maintainer SESSION lives in the working copy only; sync strips
# maintainer-only paths including docs/handoffs. Generating SESSION here writes absolute paths (WQ-438).
if (Test-AgentStarterPackRoot $ProjectRoot) {
    Write-Host '[skip] pack root - no generated handoffs or WORK_COMPLETION overlay (maintainer-only; see manifest maintainer-only path list)'
    exit 0
}

$docsDir = Join-Path $ProjectRoot 'docs'
foreach ($sub in @('handoffs', 'handoffs\active', 'handoff_archive')) {
    $p = Join-Path $ProjectRoot ("docs\" + ($sub -replace '/', '\'))
    if (-not (Test-Path -LiteralPath $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Write-Host "[ok] created $p"
    }
}

$readmeTpl = Join-Path $PackRoot 'pack/templates/docs/handoffs/README.md.template'
$readmeDst = Join-Path $ProjectRoot 'docs/handoffs/README.md'
if ((Test-Path -LiteralPath $readmeTpl) -and -not (Test-Path -LiteralPath $readmeDst)) {
    # Substitute and write like the WORK_COMPLETION path below: a plain Copy-Item leaves
    # {{PROJECT_NAME}} in the title of every generated project and keeps whatever BOM the
    # template carries.
    $readmeText = Get-Content -LiteralPath $readmeTpl -Raw -Encoding UTF8
    $readmeText = $readmeText.Replace('{{PROJECT_NAME}}', $ProjectName)
    $readmeText = $readmeText.Replace('{{PROJECT_ROOT}}', $ProjectRoot)
    Write-Utf8NoBom -Path $readmeDst -Text $readmeText
    Write-Host "[ok] created docs/handoffs/README.md from template"
}

$sessionTpl = Join-Path $PackRoot 'pack/templates/docs/handoffs/SESSION.md.template'
$sessionDst = Join-Path $ProjectRoot 'docs/handoffs/SESSION.md'
if ((Test-Path -LiteralPath $sessionTpl) -and -not (Test-Path -LiteralPath $sessionDst)) {
    $sessionDate = (Get-Date).ToString('yyyy-MM-dd')
    $sessionText = Get-Content -LiteralPath $sessionTpl -Raw -Encoding UTF8
    $sessionText = $sessionText.Replace('{{PROJECT_NAME}}', $ProjectName)
    $sessionText = $sessionText.Replace('{{PROJECT_ROOT}}', $ProjectRoot)
    $sessionText = $sessionText.Replace('{{SESSION_DATE}}', $sessionDate)
    Write-Utf8NoBom -Path $sessionDst -Text $sessionText
    Write-Host "[ok] created docs/handoffs/SESSION.md from template"
}

$dest = Join-Path $ProjectRoot 'docs/WORK_COMPLETION.md'
if (Test-Path -LiteralPath $dest) {
    Write-Host "[skip] WORK_COMPLETION exists: $dest"
    exit 0
}

$template = Join-Path $PackRoot 'pack/templates/docs/WORK_COMPLETION.md.template'
if (-not (Test-Path -LiteralPath $template)) {
    Write-Host '[warn] WORK_COMPLETION template not found - skip'
    exit 0
}

if (-not (Test-Path -LiteralPath $docsDir)) {
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
}

$text = Get-Content -LiteralPath $template -Raw -Encoding UTF8
$text = $text.Replace('{{PROJECT_NAME}}', $ProjectName)
$text = $text.Replace('{{PROJECT_ROOT}}', $ProjectRoot)
Write-Utf8NoBom -Path $dest -Text $text
Write-Host "[ok] created WORK_COMPLETION from template: $dest"
exit 0
