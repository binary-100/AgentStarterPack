#Requires -Version 5.1
<#
.SYNOPSIS
  Cursor sessionStart hook - inject agent context freshness (Phase D2 / WQ-308).
.DESCRIPTION
  Reads project docs/AGENT_CONTEXT.json via agent_context_freshness.py and emits Cursor hook JSON:
  { "additional_context": "...", "continue": true }

  Fail-open: any error yields empty context so sessions are never blocked.
  Project hook: run from workspace root (.cursor/hooks/session-freshness.ps1).
  User hook: installed copy under %USERPROFILE%\.cursor\hooks\ (same script, cwd = project).
#>
$ErrorActionPreference = 'Stop'

try {
    $null = [Console]::In.ReadToEnd()
} catch {
    # stdin optional for sessionStart
}

function Write-HookJson([string]$Context) {
    $payload = [ordered]@{
        additional_context = $Context
        continue           = $true
    }
    Write-Output ($payload | ConvertTo-Json -Compress)
}

function Write-HookEmpty() {
    Write-HookJson ''
    exit 0
}

try {
    $projectRoot = (Get-Location).Path
    $packRoot = $env:AGENT_STARTER_PACK_ROOT
    if (-not $packRoot) {
        $packRoot = Join-Path $env:USERPROFILE '.cursor\AgentStarterPack'
    }
    $freshPy = Join-Path $packRoot 'pack\scripts\agent_context_freshness.py'
    if (-not (Test-Path -LiteralPath $freshPy)) {
        Write-HookEmpty
    }

    $raw = & py -3 $freshPy --session-brief --project-root $projectRoot 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-HookEmpty
    }

    $brief = $raw | ConvertFrom-Json
    if (-not $brief) {
        Write-HookEmpty
    }

    $ctx = [string]$brief.openerLine
    if ($brief.stale -and $brief.markdownPath) {
        $ctx = ($ctx + "`n`nRead: " + [string]$brief.markdownPath).Trim()
    }
    Write-HookJson $ctx
    exit 0
} catch {
    Write-HookEmpty
}
