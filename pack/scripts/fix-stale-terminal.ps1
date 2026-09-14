#Requires -Version 5.1
# Fix Cursor agent terminal logs missing exit_code footer (stale metadata).
# Usage: .\fix-stale-terminal.ps1 [-TerminalsDir "path\to\terminals"]

param(
    [string]$TerminalsDir = ""
)

$ErrorActionPreference = "SilentlyContinue"

if (-not $TerminalsDir) {
    # Resolved inline rather than through pack-paths.ps1: this script and cleanup-orphan-processes.ps1
    # are called by the MCP server on a hot path and are deliberately dependency-free. $env:USERPROFILE
    # is $null off Windows, and with $ErrorActionPreference SilentlyContinue that did not throw - the
    # Join-Path simply produced nothing and the candidate list silently lost the user's terminals
    # directory, so the script reported "no terminals found" instead of failing.
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath('UserProfile') }
    $candidates = @(
        Join-Path $homeDir ".cursor/projects/*/terminals"
        Join-Path (Get-Location) ".cursor/terminals"
    )
    foreach ($pattern in $candidates) {
        $found = Get-ChildItem -Path $pattern -Filter "*.txt" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $TerminalsDir = $found.DirectoryName
            break
        }
    }
}

if (-not $TerminalsDir -or -not (Test-Path $TerminalsDir)) {
    Write-Host "No terminals directory found. Pass -TerminalsDir explicitly."
    exit 1
}

Write-Host "Scanning: $TerminalsDir"
$fixed = 0

Get-ChildItem -Path $TerminalsDir -Filter "*.txt" | ForEach-Object {
    $content = Get-Content -Path $_.FullName -Raw
    if ($content -match "exit_code:\s*\d") {
        return
    }
    if ($content -notmatch "running_for_ms:") {
        return
    }

    $pid = 0
    if ($content -match "(?m)^pid:\s*(\d+)") {
        $pid = [int]$Matches[1]
    }

    $alive = $false
    if ($pid -gt 0) {
        $alive = $null -ne (Get-Process -Id $pid -ErrorAction SilentlyContinue)
    }

    if ($alive) {
        Write-Host "SKIP (process alive): $($_.Name) pid=$pid"
        return
    }

    $ended = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $content = $content -replace "running_for_ms:\s*\d+\s*", "ended_at: $ended`n"

    if ($content -match "error|failed|FAILED") {
        $code = 1
    } else {
        $code = 0
    }

    $footer = @"

---
exit_code: $code
elapsed_ms: 0
ended_at: $ended
stale_metadata_repaired: true
---
"@

    Set-Content -Path $_.FullName -Value ($content.TrimEnd() + $footer) -NoNewline
    Write-Host "FIXED: $($_.Name) (exit_code=$code)"
    $fixed++
}

Write-Host "Done. Fixed $fixed file(s). Cursor UI tabs may still need manual Kill Terminal."
