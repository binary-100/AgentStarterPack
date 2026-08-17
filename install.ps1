# Install Agent Starter Pack - user and/or project scope + optional MCP
param(
    [ValidateSet("User", "Project", "Both")]
    [string]$Scope = "Both",
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$RegisterMcp,
    [switch]$InstallMcpDeps,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
$PackRoot = Join-Path $PSScriptRoot "pack"
$versionFile = Join-Path $PSScriptRoot "VERSION"
$Version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "1.2.0" }
$UserCursor = Join-Path $env:USERPROFILE ".cursor"
$CanonicalRoot = Join-Path $UserCursor "AgentStarterPack"
$LegacyCanonical = Join-Path $UserCursor "agent-starter-pack"

if (-not (Test-Path $PackRoot)) {
    Write-Error "pack/ not found beside install.ps1"
}

function Copy-Tree($src, $dst, [string[]]$SkipNames = @(), [string[]]$SkipDirNames = @()) {
    if (-not (Test-Path $dst)) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
    }
    Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
        if ($SkipNames -contains $_.Name) { return }
        $rel = $_.FullName.Substring($src.Length).TrimStart("\")
        foreach ($skipDir in $SkipDirNames) {
            if ($rel -like "$skipDir*") { return }
        }
        $target = Join-Path $dst $rel
        $dir = Split-Path $target -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Copy-Item -Path $_.FullName -Destination $target -Force
    }
}

function Merge-McpJson {
    $mcpPath = Join-Path $UserCursor "mcp.json"
    $serverPy = Join-Path $CanonicalRoot "mcp\agent_hygiene_server.py"
    $pyCmd = "py"
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        $pyCmd = "python"
    }
    $entry = @{
        command = $pyCmd
        args    = @("-3", $serverPy)
    }
    $root = @{ mcpServers = @{ "agent-hygiene" = $entry } }
    if (Test-Path $mcpPath) {
        try {
            $existing = Get-Content $mcpPath -Raw | ConvertFrom-Json
            if (-not $existing.mcpServers) {
                $existing | Add-Member -NotePropertyName mcpServers -NotePropertyValue (@{})
            }
            $existing.mcpServers."agent-hygiene" = $entry
            $root = $existing
        } catch {
            Write-Warning "Could not parse existing mcp.json; backing up and rewriting."
            Copy-Item $mcpPath "$mcpPath.bak" -Force
        }
    }
    ($root | ConvertTo-Json -Depth 6) | Set-Content -Path $mcpPath -Encoding UTF8
    Write-Host "MCP registered: $mcpPath (server: agent-hygiene)"
    Write-Host "Restart Cursor to load MCP tools."
}

Write-Host "Agent Starter Pack v$Version - install ($Scope)`n"

# Migrate legacy canonical folder name (pre-1.7.0)
if ((Test-Path $LegacyCanonical) -and -not (Test-Path $CanonicalRoot)) {
    Move-Item -LiteralPath $LegacyCanonical -Destination $CanonicalRoot
    Write-Host "Migrated canonical install: agent-starter-pack -> AgentStarterPack"
}

# Canonical copy under ~/.cursor/AgentStarterPack for stable MCP paths
Copy-Tree $PSScriptRoot $CanonicalRoot
Write-Host "Canonical: $CanonicalRoot"

if ($Scope -eq "User" -or $Scope -eq "Both") {
    $userSkills = Join-Path $UserCursor "skills"
    $userRules = Join-Path $UserCursor "rules"
    Copy-Tree (Join-Path $PackRoot "skills") $userSkills
    Copy-Tree (Join-Path $PackRoot "rules") $userRules
    Write-Host "User skills: $userSkills"
    Write-Host "User rules:  $userRules"
    $legacy = @(
        "code-audit-checklist.mdc",
        "generic-code-audit-checklist.mdc"
    )
    foreach ($name in $legacy) {
        $p = Join-Path $userRules $name
        if (Test-Path $p) {
            Remove-Item $p -Force
            Write-Host "Removed legacy rule: $name"
        }
    }
    Get-ChildItem $userRules -Filter "*audit-overlay*" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Host "Removed legacy overlay: $($_.Name)"
    }
}

if ($Scope -eq "Project" -or $Scope -eq "Both") {
    $projSkills = Join-Path $ProjectRoot ".cursor\skills"
    $projRules = Join-Path $ProjectRoot ".cursor\rules"
    Copy-Tree (Join-Path $PackRoot "skills") $projSkills -SkipDirNames @('agent-code-audit\')
    Copy-Tree (Join-Path $PackRoot "rules") $projRules
    Write-Host "Project skills: $projSkills (agent-code-audit excluded - use user pack skill)"
    Write-Host "Project rules:  $projRules"
}

if ($RegisterMcp -or $Scope -eq "User" -or $Scope -eq "Both") {
    if (Test-Path (Join-Path $CanonicalRoot "mcp\agent_hygiene_server.py")) {
        Merge-McpJson
    }
}

if ($InstallMcpDeps) {
    $req = Join-Path $CanonicalRoot "mcp\requirements.txt"
    if (Test-Path $req) {
        Write-Host "Installing MCP Python deps..."
        & py -3 -m pip install --user -r $req --quiet
    }
}

$manifest = @{
    version      = $Version
    installed_at = (Get-Date).ToUniversalTime().ToString("o")
    scope        = $Scope
    project_root = $ProjectRoot
    mcp          = ($RegisterMcp -or $Scope -eq "User" -or $Scope -eq "Both")
    canonical    = $CanonicalRoot
} | ConvertTo-Json

Set-Content -Path (Join-Path $CanonicalRoot "install-manifest.json") -Value $manifest

$syncScript = Join-Path $CanonicalRoot "pack\scripts\sync-audit-system.ps1"
if (Test-Path $syncScript) {
    Write-Host "Syncing audit system..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $syncScript
}

Write-Host ''
Write-Host 'Done. Verify:'
Write-Host "  & `"$CanonicalRoot\pack\scripts\verify-audit-system.ps1`""
Write-Host "  & `"$CanonicalRoot\pack\scripts\verify-audit-behavior.ps1`""
Write-Host "  & `"$CanonicalRoot\pack\scripts\sync-audit-system.ps1`" -VerifyOnly"
Write-Host "  & `"$CanonicalRoot\pack\scripts\doctor.ps1`""
Write-Host 'MCP tools after Cursor restart: agent_hygiene_full_check, scan_orphan_agent_processes,'
Write-Host '  cleanup_orphan_agent_processes, fix_stale_terminal_logs, kill_terminal_process'
if (-not $NoPause) {
    Write-Host ''
    Read-Host 'Press Enter to close'
}
