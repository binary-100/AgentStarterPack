#Requires -Version 5.1
<#
.SYNOPSIS
  Create docs/WORK_QUEUE.md from the pack template when missing (never overwrite existing).
.DESCRIPTION
  Pre-2.22.13 bootstrapped projects lack the work queue file. Refresh and verify call this
  so users are not asked to copy templates by hand.
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
    Write-Host 'ERROR: cannot resolve Agent Starter Pack root for WORK_QUEUE template.'
    exit 1
}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$dest = Join-Path $ProjectRoot 'docs/WORK_QUEUE.md'
if (Test-Path -LiteralPath $dest) {
    Write-Host "[skip] WORK_QUEUE exists: $dest"
    exit 0
}

$template = Join-Path $PackRoot 'pack/templates/docs/WORK_QUEUE.md.template'
if (-not (Test-Path -LiteralPath $template)) {
    $fallbackRoot = Get-SourceAgentStarterPack
    if ($fallbackRoot) {
        $alt = Join-Path $fallbackRoot 'pack/templates/docs/WORK_QUEUE.md.template'
        if (Test-Path -LiteralPath $alt) { $template = $alt }
    }
}
if (-not (Test-Path -LiteralPath $template)) {
    Write-Host "[warn] WORK_QUEUE template not found under PackRoot or source pack - skip"
    exit 0
}

if (-not $ProjectName) {
    $ProjectName = Split-Path $ProjectRoot -Leaf
}

$text = Get-Content -LiteralPath $template -Raw -Encoding UTF8
$text = $text.Replace('{{PROJECT_NAME}}', $ProjectName)
$docsDir = Split-Path -Parent $dest
if (-not (Test-Path -LiteralPath $docsDir)) {
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
}
Write-Utf8NoBom -Path $dest -Text $text
Write-Host "[ok] created WORK_QUEUE from template: $dest"
exit 0
