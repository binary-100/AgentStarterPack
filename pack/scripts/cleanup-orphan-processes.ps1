#Requires -Version 5.1
# Find and optionally kill orphan py/python processes left after force-killed agent terminals.
# Usage:
#   .\cleanup-orphan-processes.ps1              # report only
#   .\cleanup-orphan-processes.ps1 -Kill        # terminate orphans + suspect hung tests

param(
    [switch]$Kill,
    [double]$MinAgeMinutes = 10,
    [double]$MaxCpuSeconds = 3
)

$ErrorActionPreference = "SilentlyContinue"
$protected = @("agent_hygiene_server", "mcp.server.fastmcp")
$hungMarkers = @("test_gui_phase2", "offscreen_main_window", "run_tests.bat", "pytest")

function Test-Protected([string]$cmd) {
    foreach ($m in $protected) {
        if ($cmd -like "*$m*") { return $true }
    }
    return $false
}

$alive = @{}
Get-Process | ForEach-Object { $alive[$_.Id] = $true }

$killedParents = New-Object System.Collections.Generic.HashSet[int]
# Inline, not via pack-paths.ps1: the MCP server calls this on a hot path and it stays dependency-free.
# $env:USERPROFILE is $null off Windows, and SilentlyContinue turned that into an empty root list
# rather than an error - so the scan found no terminals and reported no orphans, which looks identical
# to a clean machine.
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath('UserProfile') }
$roots = @(
    Join-Path $homeDir ".cursor/projects/*/terminals"
)
foreach ($pattern in $roots) {
    Get-ChildItem -Path $pattern -Filter "*.txt" -ErrorAction SilentlyContinue | ForEach-Object {
        $content = Get-Content -Path $_.FullName -Raw
        if ($content -match "(?m)^pid:\s*(\d+)") {
            $pid = [int]$Matches[1]
            if ($content -match "exit_code:\s*4294967295") {
                [void]$killedParents.Add($pid)
            } elseif ($content -match "stale_metadata_repaired:\s*true" -and -not $alive.ContainsKey($pid)) {
                [void]$killedParents.Add($pid)
            }
        }
    }
}

$targets = @()
Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='py.exe'" | ForEach-Object {
    $cmd = $_.CommandLine
    if (Test-Protected $cmd) { return }
    $parent = [int]$_.ParentProcessId
    $pid = [int]$_.ProcessId
    $reason = $null
    if ($parent -gt 0 -and -not $alive.ContainsKey($parent)) {
        $reason = "parent_dead"
    } elseif ($killedParents.Contains($parent)) {
        $reason = "parent_force_killed"
    } else {
        $low = ($cmd + "").ToLower()
        $looksTest = $false
        foreach ($m in $hungMarkers) {
            if ($low.Contains($m)) { $looksTest = $true; break }
        }
        if ($looksTest) {
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($proc -and $proc.CPU -le $MaxCpuSeconds) {
                $age = ((Get-Date) - $proc.StartTime).TotalMinutes
                if ($age -ge $MinAgeMinutes) {
                    $reason = "low_cpu_test_process"
                }
            }
        }
    }
    if ($reason) {
        $targets += [pscustomobject]@{
            Pid = $pid
            ParentPid = $parent
            Reason = $reason
            Command = if ($cmd.Length -gt 160) { $cmd.Substring(0, 160) + "..." } else { $cmd }
        }
    }
}

if (-not $targets.Count) {
    Write-Host "No orphan or suspect hung py/python processes found."
    exit 0
}

Write-Host "Found $($targets.Count) process(es):"
$targets | Format-Table -AutoSize

if (-not $Kill) {
    Write-Host "Report only. Re-run with -Kill to terminate."
    exit 0
}

foreach ($t in $targets) {
    Stop-Process -Id $t.Pid -Force -ErrorAction SilentlyContinue
    Write-Host "Killed PID $($t.Pid) ($($t.Reason))"
}
Write-Host "Done."
