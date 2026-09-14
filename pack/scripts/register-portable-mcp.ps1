#Requires -Version 5.1
# Register agent-hygiene MCP for non-Cursor AI tools
param(
    [ValidateSet("Claude", "All")]
    [string]$Tool = "Claude",
    [switch]$InstallDeps,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

function Get-StarterPackRoot {
    . (Join-Path $PSScriptRoot 'pack-paths.ps1')
    $found = Get-AgentStarterPackRoot
    if ($found) { return $found }
    throw "Agent Starter Pack not found. Run $(Get-PackEntryPoint 'install') first."
}

function Merge-McpEntry {
    param(
        [string]$ConfigPath,
        [hashtable]$Entry
    )
    $root = @{ mcpServers = @{ "agent-hygiene" = $Entry } }
    if (Test-Path $ConfigPath) {
        try {
            $existing = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $existing.mcpServers) {
                $existing | Add-Member -NotePropertyName mcpServers -NotePropertyValue (@{})
            }
            $existing.mcpServers."agent-hygiene" = $Entry
            $root = $existing
        } catch {
            Write-Warning "Could not parse $ConfigPath; backing up and rewriting."
            Copy-Item $ConfigPath "$ConfigPath.bak" -Force
        }
    } else {
        $dir = Split-Path $ConfigPath -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    Write-Utf8NoBom $ConfigPath (($root | ConvertTo-Json -Depth 6))
    Write-Host "[ok] MCP registered: $ConfigPath"
}

$starterRoot = Get-StarterPackRoot
$serverPy = Join-Path $starterRoot "mcp/agent_hygiene_server.py"
if (-not (Test-Path $serverPy)) {
    Write-Error "agent_hygiene_server.py not found. Run $(Get-PackEntryPoint 'install') first."
}

$pyCmd = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { "python" }
$entry = @{
    command = $pyCmd
    args    = @("-3", $serverPy)
}

if ($InstallDeps) {
    $req = Join-Path $starterRoot "mcp/requirements.txt"
    if (Test-Path $req) {
        Write-Host "Installing MCP Python deps..."
        & $pyCmd -3 -m pip install -r $req --quiet
    }
}

if ($Tool -eq "Claude" -or $Tool -eq "All") {
    $claudeConfig = Join-Path $env:APPDATA "Claude/claude_desktop_config.json"
    Merge-McpEntry -ConfigPath $claudeConfig -Entry $entry
    Write-Host "Restart Claude Desktop to load MCP."
}

Write-Host ""
Write-Host "See docs/PORTABLE_SETUP.md for other tools."
Write-Host "Project adapters: pack\scripts\register-tool-adapters.ps1 -ProjectRoot YOUR_REPO"

if (-not $NoPause) {
    Read-Host "Press Enter to close"
}
