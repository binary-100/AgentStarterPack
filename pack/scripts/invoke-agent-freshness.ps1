#Requires -Version 5.1
<#
.SYNOPSIS
  Thin wrapper around agent_context_freshness.py for hooks, refresh, and CLI.
.PARAMETER ProjectRoot
  Project to check. Defaults to current directory.
.PARAMETER SessionBrief
  Emit session-brief JSON to stdout (for Cursor hooks and scripts).
.PARAMETER WriteSessionStart
  Write docs/AGENT_SESSION_START.md under the canonical project root.
.PARAMETER PrintOpener
  Print only the one-line opener (ASCII) for clipboard or hook injection.
.PARAMETER Check
  Emit full freshness JSON (--check).
#>
param(
    [string]$ProjectRoot = '',
    [switch]$SessionBrief,
    [switch]$WriteSessionStart,
    [switch]$PrintOpener,
    [switch]$Check,
    [string]$PackRoot = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

$freshPy = Join-Path $PSScriptRoot 'agent_context_freshness.py'
if (-not (Test-Path -LiteralPath $freshPy)) {
    Write-Error "agent_context_freshness.py not found: $freshPy"
    exit 2
}

if ($PackRoot) {
    $env:AGENT_STARTER_PACK_ROOT = (Resolve-Path -LiteralPath $PackRoot).Path
}

$rootArg = @()
if ($ProjectRoot) {
    $rootArg = @('--project-root', (Resolve-Path -LiteralPath $ProjectRoot).Path)
}

if ($WriteSessionStart) {
    $out = & py -3 $freshPy @rootArg --write-session-start 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $out
        exit $LASTEXITCODE
    }
    Write-Host $out.Trim()
    exit 0
}

if ($PrintOpener) {
    $json = & py -3 $freshPy @rootArg --session-brief 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $json
        exit $LASTEXITCODE
    }
    $obj = $json | ConvertFrom-Json
    Write-Host $obj.openerLine
    exit 0
}

if ($SessionBrief) {
    & py -3 $freshPy @rootArg --session-brief
    exit $LASTEXITCODE
}

if ($Check) {
    & py -3 $freshPy @rootArg --check
    exit $LASTEXITCODE
}

Write-Host 'Specify -SessionBrief, -WriteSessionStart, -PrintOpener, or -Check'
exit 2
