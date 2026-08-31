#Requires -Version 5.1
<#
.SYNOPSIS
  One entry point after a pack upgrade: optional profile install, then project refresh.
.DESCRIPTION
  Wraps install.ps1 (optional -Install) and refresh-agent-context.ps1, then prints how to
  reach open agent chats (paste line / trigger phrases). Does not modify open chats itself.
.PARAMETER ProjectRoot
  Project to refresh. Default: the pack checkout when run from maintainer repo.
.PARAMETER Install
  Run install.ps1 -Scope User before refreshing the project.
.PARAMETER SkipProjectSync
  Pass through to refresh-agent-context.ps1.
.PARAMETER PackRoot
  Override pack source path.
.PARAMETER NoClipboard
  Pass through to refresh-agent-context.ps1.
#>
param(
    [string]$ProjectRoot = '',
    [switch]$Install,
    [switch]$SkipProjectSync,
    [string]$PackRoot = '',
    [switch]$NoClipboard
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'pack-paths.ps1')

if (-not $PackRoot) {
    $PackRoot = Get-CheckoutAgentStarterPack
    if (-not $PackRoot) { $PackRoot = Get-AgentStarterPackRoot }
}
if (-not $PackRoot -or -not (Test-Path -LiteralPath $PackRoot)) {
    Write-Host 'ERROR: cannot resolve Agent Starter Pack. Pass -PackRoot or set AGENT_STARTER_PACK_ROOT.'
    exit 1
}
$PackRoot = (Resolve-Path -LiteralPath $PackRoot).Path

$refreshArgs = @{
    PackRoot = $PackRoot
}
if ($ProjectRoot) { $refreshArgs['ProjectRoot'] = $ProjectRoot }
if ($SkipProjectSync) { $refreshArgs['SkipProjectSync'] = $true }
if ($NoClipboard) { $refreshArgs['NoClipboard'] = $true }
if ($Install) { $refreshArgs['Install'] = $true }

$refreshPs1 = Join-Path $PSScriptRoot 'refresh-agent-context.ps1'
if (-not (Test-Path -LiteralPath $refreshPs1)) {
    Write-Host "ERROR: missing $refreshPs1"
    exit 1
}

Write-Host 'Update-AgentStack - install (optional) + project refresh'
Write-Host ''

$rc = Invoke-PackScript -NoProfile -ScriptPath $refreshPs1 @refreshArgs
if ($rc -ne 0) { exit $rc }

$isMaintainerPack = Test-Path -LiteralPath (Join-Path $PackRoot 'pack\audit\manifest.json')
if ($isMaintainerPack) {
    $cpScript = Join-Path $PSScriptRoot 'verify-complete-picture.ps1'
    if (Test-Path -LiteralPath $cpScript) {
        Write-Host ''
        Write-Host 'Complete-picture handoff verify (maintainer pack)...'
        $cpRoot = if ($ProjectRoot) { $ProjectRoot } else { $PackRoot }
        $cpRc = Invoke-PackScript -NoProfile -ScriptPath $cpScript -ArgumentList @(
            '-ProjectRoot', $cpRoot
        )
        if ($cpRc -ne 0) {
            Write-Host 'ERROR: verify-complete-picture.ps1 failed - fix handoff/WQ drift before claiming stack update done.'
            exit $cpRc
        }
    }
}

if (-not $ProjectRoot) {
    $ProjectRoot = if (Test-Path -LiteralPath (Join-Path $PackRoot 'pack\audit\manifest.json')) {
        $PackRoot
    } else {
        (Get-Location).Path
    }
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

$ctxPath = Join-Path $ProjectRoot 'docs\AGENT_CONTEXT.json'
$pastePath = Join-Path $ProjectRoot 'docs\AGENT_PASTE.txt'
Write-Host ''
Write-Host 'Open chats do not hot-reload - pick one:'
Write-Host '  1. Type a trigger phrase (see docs/AGENT_CONTEXT.json triggerPhrases)'
Write-Host '  2. Paste from docs/AGENT_PASTE.txt (or clipboard if copied above)'
Write-Host '  3. MCP (Cursor / Claude Desktop): check_pack_freshness, get_agent_refresh_brief'
if (Test-Path -LiteralPath $pastePath) {
    Write-Host "  Paste file: $pastePath"
}
if (Test-Path -LiteralPath $ctxPath) {
    Write-Host "  Contract:   $ctxPath"
}
Write-Host ''
Write-Host 'Full path: docs/AGENT_UPGRADE_PATH.md in the pack or project docs after sync.'
exit 0
