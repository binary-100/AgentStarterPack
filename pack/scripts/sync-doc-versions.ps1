#Requires -Version 5.1
# Sync maintainer doc version cites to root VERSION + pack/audit/manifest.json.
param(
    [switch]$VerifyOnly,
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

if (-not $ProjectRoot) {
    $ProjectRoot = Get-AgentStarterPackRoot
    if (-not $ProjectRoot) { $ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

$pyScript = Join-Path $PSScriptRoot 'sync_doc_versions.py'
$vsCfg = Join-Path $ProjectRoot 'docs/VERSION_SYNC.json'
$auditCfg = Join-Path $ProjectRoot 'docs/AUDIT.config.json'
if (-not (Test-Path -LiteralPath $vsCfg) -and -not (Test-Path -LiteralPath $auditCfg)) {
    Write-Host "SKIP: no docs/VERSION_SYNC.json or docs/AUDIT.config.json at $ProjectRoot"
    exit 0
}

$pyCmd = if (Get-Command py -ErrorAction SilentlyContinue) { 'py' } else { 'python' }
$flag = if ($VerifyOnly) { '--verify' } else { '' }

Write-Host "Doc version sync (build pipeline) - $ProjectRoot"
if ($VerifyOnly) {
    & $pyCmd -3 $pyScript $ProjectRoot --verify
} else {
    & $pyCmd -3 $pyScript $ProjectRoot
}
exit $LASTEXITCODE
