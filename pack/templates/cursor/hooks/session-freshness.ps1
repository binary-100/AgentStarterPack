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

# This hook never reads stdin, and that is the decision rather than an omission.
#
# Cursor writes its sessionStart payload to stdin and closes the handle. Any other parent that
# inherits stdin without writing - bash, a CI step, this pack's own behavior probe - leaves the pipe
# open, and a read then waits for an EOF that never comes. That is how `run_audit.sh` under bash hung
# the whole suite for 11 minutes with no output (2.22.63): a read that never returns raises nothing,
# so the fail-open promise above cannot catch it. The payload is not needed here - this hook reports
# context freshness and ignores what Cursor sends - so the only reason to read was to spare the writer
# a broken pipe, and a payload that size lands in the pipe buffer whether anyone reads it or not.
#
# Two bounded drains were tried and measured, and both cost more than that courtesy is worth.
# Task::Run([Func[string]] { [Console]::In.ReadToEnd() }) shipped for three releases and never ran at
# all: a PowerShell scriptblock cast to a delegate needs a runspace, a threadpool thread has none, so
# the task faulted in ~6ms and its Wait returned instantly whatever bound it held (WQ-473). Replacing
# it with a real off-thread read - BeginRead, bounded by WaitOne(250) - drains correctly in isolation
# and exits in about half a second, but inside this hook, which goes on to run a Python child that
# inherits the same handle, it hung past 15s on both PowerShell hosts with the pipe held open. So the
# working version of that courtesy reintroduces the exact defect it was meant to fix.
#
# What must stay true is the guarantee, not the drain: this hook always returns, whoever started it
# and whatever they do with stdin. Behavior step 38 holds that line by running the hook with stdin
# redirected and never written to, and failing if it has not exited within 20 seconds.

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
        # USERPROFILE is Windows-only and $null elsewhere, where Join-Path then throws before the
        # fail-open path below can report anything useful. Resolved inline rather than through
        # pack-paths.ps1: this hook runs at every session start, and the home directory is needed to
        # find the pack in the first place.
        $home1 = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME }
        else { [Environment]::GetFolderPath('UserProfile') }
        $packRoot = Join-Path $home1 '.cursor/AgentStarterPack'
    }
    $freshPy = Join-Path $packRoot 'pack/scripts/agent_context_freshness.py'
    if (-not (Test-Path -LiteralPath $freshPy)) {
        Write-HookEmpty
    }

    # `py` is the Windows launcher and does not exist on macOS or Linux, where the interpreter is
    # python3 - so this hook produced no context at all off Windows.
    $pyExe = $null
    $pyPre = @()
    foreach ($cand in @(@{ exe = 'py'; pre = @('-3') }, @{ exe = 'python3'; pre = @() }, @{ exe = 'python'; pre = @() })) {
        if (Get-Command $cand.exe -ErrorAction SilentlyContinue) { $pyExe = $cand.exe; $pyPre = $cand.pre; break }
    }
    if (-not $pyExe) {
        Write-HookEmpty
    }

    $raw = & $pyExe @($pyPre + @($freshPy, '--session-brief', '--project-root', $projectRoot)) 2>&1 | Out-String
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
