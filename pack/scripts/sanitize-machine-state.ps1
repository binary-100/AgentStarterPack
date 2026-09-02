#Requires -Version 5.1
<#
.SYNOPSIS
  Remove machine-local artifacts from a pack checkout that arrived by folder copy.
.DESCRIPTION
  export.ps1 drops these when it builds a transfer archive, and .gitignore keeps them out of a clone.
  A plain folder copy reads neither list: robocopy /MIR, drag-and-drop, and file-sync clients copy the
  sending machine's agent-context stamp, install record, generated overlay and audit results verbatim.
  The receiving machine then has agents reading absolute paths that do not exist on it, and an audit
  receipt proving tests passed on a tree it never had.

  The list lives in one place - machineLocalPaths in pack/audit/manifest.json - so this script,
  export.ps1 and behavior step 50 cannot drift apart.

  Every file removed here is regenerated where it is needed: Refresh-AgentContext.cmd writes the agent
  stamp, ensure-work-completion.ps1 writes the overlay during audit, install.ps1 writes the install
  record into its target, and run_audit.cmd rebuilds the audit artifacts.
.PARAMETER ProjectRoot
  Pack checkout to clean. Defaults to the pack root resolved from this script's location.
.PARAMETER Apply
  Delete. Without it, this lists what would be deleted and changes nothing.
.EXAMPLE
  .\pack\scripts\sanitize-machine-state.ps1
  .\pack\scripts\sanitize-machine-state.ps1 -Apply
#>
param(
    [string]$ProjectRoot = '',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

if (-not $ProjectRoot) {
    $ProjectRoot = Get-SourceAgentStarterPack
    if (-not $ProjectRoot) { $ProjectRoot = Get-AgentStarterPackRoot }
}
if (-not $ProjectRoot -or -not (Test-Path -LiteralPath $ProjectRoot)) {
    Write-Host 'ERROR: cannot resolve a pack checkout to sanitize.'
    exit 1
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

$manifestPath = Join-Path $ProjectRoot 'pack\audit\manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-Host "ERROR: no pack/audit/manifest.json under $ProjectRoot - is this a pack checkout?"
    exit 1
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$listed = @($manifest.machineLocalPaths | Where-Object { $_ })
if ($listed.Count -eq 0) {
    Write-Host 'ERROR: manifest has no machineLocalPaths - refusing to guess what is machine-local.'
    exit 1
}

Write-Host "Sanitize machine-local state: $ProjectRoot"
Write-Host ("Mode: {0}" -f $(if ($Apply) { 'APPLY (deleting)' } else { 'PREVIEW (use -Apply to delete)' }))

$targets = @()
foreach ($rel in $listed) {
    $full = Join-Path $ProjectRoot ($rel -replace '/', '\')
    if (Test-Path -LiteralPath $full) { $targets += $full }
}

# Wildcard classes the manifest cannot enumerate: audit artifacts are per-run, bytecode is per
# interpreter, and the scratch roots are per test process.
foreach ($dirName in @('__pycache__', '.tmp', '.pytest_cache')) {
    Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $dirName } |
        ForEach-Object { $targets += $_.FullName }
}
Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch '\\\.git\\' -and
        ($_.Name -like '.audit_*' -or $_.Extension -in @('.pyc', '.pyo'))
    } |
    ForEach-Object { $targets += $_.FullName }

$targets = @($targets | Select-Object -Unique)

if ($targets.Count -eq 0) {
    Write-Host '[OK] nothing machine-local found - this checkout is already clean.'
    exit 0
}

foreach ($t in $targets) {
    $rel = $t.Substring($ProjectRoot.Length).TrimStart('\')
    if ($Apply) {
        $isDir = (Get-Item -LiteralPath $t -ErrorAction SilentlyContinue) -is [System.IO.DirectoryInfo]
        Remove-Item -LiteralPath $t -Force -Recurse:$isDir -ErrorAction SilentlyContinue
        Write-Host "[REMOVED] $rel"
    } else {
        Write-Host "[WOULD REMOVE] $rel"
    }
}

Write-Host ""
if ($Apply) {
    Write-Host "Removed $($targets.Count) machine-local item(s)."
    Write-Host 'Next on this machine: Refresh-AgentContext.cmd, then run_audit.cmd to rebuild audit state.'
} else {
    Write-Host "$($targets.Count) machine-local item(s) would be removed. Re-run with -Apply."
}
exit 0
