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

$docsDir = Join-Path $ProjectRoot 'docs'
foreach ($sub in @('handoffs', 'handoffs\active', 'handoff_archive')) {
    $p = Join-Path $ProjectRoot ("docs\" + ($sub -replace '/', '\'))
    if (-not (Test-Path -LiteralPath $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Write-Host "[ok] created $p"
    }
}

$readmeTpl = Join-Path $PackRoot 'pack\templates\docs\handoffs\README.md.template'
$readmeDst = Join-Path $ProjectRoot 'docs\handoffs\README.md'
if ((Test-Path -LiteralPath $readmeTpl) -and -not (Test-Path -LiteralPath $readmeDst)) {
    Copy-Item -LiteralPath $readmeTpl -Destination $readmeDst -Force
    Write-Host "[ok] created docs/handoffs/README.md from template"
}

$dest = Join-Path $ProjectRoot 'docs\WORK_COMPLETION.md'
if (Test-Path -LiteralPath $dest) {
    Write-Host "[skip] WORK_COMPLETION exists: $dest"
    exit 0
}

$template = Join-Path $PackRoot 'pack\templates\docs\WORK_COMPLETION.md.template'
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
