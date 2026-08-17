# Verify Agent Starter Pack installation (paths, MCP, deps, live smoke test)
param(
    [switch]$UserScope,
    [switch]$ProjectScope,
    [switch]$SkipSmoke,
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot 'pack-paths.ps1')
$installedRoot = Get-InstalledAgentStarterPack
$ok = $true
$warn = 0
$packRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (Test-Path (Join-Path $packRoot "VERSION")) {
    $packVersion = (Get-Content (Join-Path $packRoot "VERSION") -Raw).Trim()
} else {
    $packVersion = "unknown"
}

function Write-Ok($msg) { Write-Host "[OK] $msg" }
function Write-Miss($msg) { Write-Host "[MISSING] $msg"; $script:ok = $false }
function Write-Warn($msg) { Write-Host "[WARN] $msg"; $script:warn++ }

function Test-PathReport($label, $path) {
    if (Test-Path $path) { Write-Ok "$label : $path" }
    else { Write-Miss "$label : $path" }
}

Write-Host "Agent Starter Pack doctor v$packVersion`n"

if ($UserScope -or (-not $UserScope -and -not $ProjectScope)) {
    Write-Host "User scope (~/.cursor):"
    Test-PathReport "skill agent-code-audit" "$env:USERPROFILE\.cursor\skills\agent-code-audit\SKILL.md"
    Test-PathReport "skill agent-terminal-hygiene" "$env:USERPROFILE\.cursor\skills\agent-terminal-hygiene\SKILL.md"
    Test-PathReport "skill agent-gui-test-hygiene" "$env:USERPROFILE\.cursor\skills\agent-gui-test-hygiene\SKILL.md"
    Test-PathReport "rule audit-protocol" "$env:USERPROFILE\.cursor\rules\audit-protocol.mdc"
    Test-PathReport "rule generic-terminal" "$env:USERPROFILE\.cursor\rules\generic-terminal-and-build-hygiene.mdc"
    Test-PathReport "rule agent-defaults" "$env:USERPROFILE\.cursor\rules\agent-defaults-always.mdc"
    Test-PathReport "canonical pack" (Join-Path $installedRoot "pack")
    Test-PathReport "MCP server" (Join-Path $installedRoot "mcp\agent_hygiene_server.py")
    Write-Host ""

    $mcpPath = Join-Path $env:USERPROFILE ".cursor\mcp.json"
    if (Test-Path $mcpPath) {
        try {
            $mcp = Get-Content $mcpPath -Raw | ConvertFrom-Json
            $entry = $mcp.mcpServers."agent-hygiene"
            if ($entry) {
                Write-Ok "mcp.json agent-hygiene entry present"
                $serverPy = $entry.args | Where-Object { $_ -like "*agent_hygiene_server.py*" } | Select-Object -First 1
                if ($serverPy -and (Test-Path $serverPy)) {
                    Write-Ok "MCP server path resolves: $serverPy"
                } else {
                    Write-Warn "MCP server path in mcp.json may be stale - re-run install.ps1 -RegisterMcp"
                }
            } else {
                Write-Miss "mcp.json has no agent-hygiene server - run install.ps1 -RegisterMcp"
            }
        } catch {
            Write-Miss "mcp.json parse error: $_"
        }
    } else {
        Write-Miss "mcp.json not found - run install.ps1 -RegisterMcp"
    }
    Write-Host ""

    $pyCmd = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { "python" }
    $importTest = & $pyCmd -3 -c "import mcp; print('mcp_ok')" 2>&1
    if ($LASTEXITCODE -eq 0 -and "$importTest" -match "mcp_ok") {
        Write-Ok "Python package 'mcp' importable"
    } else {
        Write-Warn "Python package 'mcp' not found - run install.ps1 -InstallMcpDeps"
    }

    if (-not $SkipSmoke) {
        $server = Join-Path $installedRoot "mcp\agent_hygiene_server.py"
        if (Test-Path $server) {
            $mcpDir = (Split-Path $server -Parent) -replace "'", "''"
            $pyCode = @"
import sys
sys.path.insert(0, r'$mcpDir')
import agent_hygiene_server as h
r = h.agent_hygiene_full_check()
print('smoke_ok' if 'terminals' in r else 'smoke_fail')
"@
            $smoke = & $pyCmd -3 -c $pyCode 2>&1
            if ($LASTEXITCODE -eq 0 -and "$smoke" -match "smoke_ok") {
                Write-Ok "MCP smoke test (agent_hygiene_full_check)"
            } else {
                Write-Warn "MCP smoke test failed: $smoke"
            }
        }
    }
    Write-Host ""
}

if ($ProjectScope -or (-not $UserScope -and -not $ProjectScope)) {
    $root = if ($ProjectRoot) { $ProjectRoot } else { (Get-Location).Path }
    $isPackRepo = (Test-Path (Join-Path $root '.cursor\rules\starter-pack-repo.mdc')) -or
        ((Test-Path (Join-Path $root 'pack\audit\manifest.json')) -and (Test-Path (Join-Path $root 'install.ps1')))
    Write-Host "Project scope ($root):"
    if ($isPackRepo) {
        Test-PathReport "rule starter-pack-repo" "$root\.cursor\rules\starter-pack-repo.mdc"
        Write-Ok "rule audit-protocol (user-global, not duplicated in pack repo)"
        Write-Ok "rule generic-terminal (user-global, not duplicated in pack repo)"
    } else {
        Test-PathReport "rule audit-protocol" "$root\.cursor\rules\audit-protocol.mdc"
        Test-PathReport "rule generic-terminal" "$root\.cursor\rules\generic-terminal-and-build-hygiene.mdc"
    }
    Test-PathReport "rule audit (project)" "$root\.cursor\rules\audit.mdc"
    Test-PathReport "docs AUDIT.md" "$root\docs\AUDIT.md"
    Write-Host ""
}

$orphanScript = Join-Path $PSScriptRoot "cleanup-orphan-processes.ps1"
if (Test-Path $orphanScript) {
    Write-Host "Orphan process scan (report only):"
    & $orphanScript
    Write-Host ""
}

$manifestPath = Join-Path $installedRoot "install-manifest.json"
if (Test-Path $manifestPath) {
    try {
        $mf = Get-Content $manifestPath -Raw | ConvertFrom-Json
        if ($mf.version -ne $packVersion) {
            Write-Warn "Installed manifest version $($mf.version) != pack VERSION $packVersion - re-run install.ps1 to upgrade"
        } else {
            Write-Ok "Install manifest version $packVersion"
        }
    } catch {
        Write-Warn "Could not read install-manifest.json"
    }
}

$verify = Join-Path $PSScriptRoot "verify-audit-system.ps1"
if (Test-Path $verify) {
    Write-Host "Audit system verification:"
    if ($ProjectRoot) {
        & $verify -ProjectRoot $ProjectRoot
    } else {
        & $verify
    }
    Write-Host ""
}

if ($ok -and $warn -eq 0) {
    Write-Host "All checks passed."
    exit 0
}
if ($ok) {
    Write-Host "Checks passed with $warn warning(s)."
    exit 0
}
Write-Host "Some required items missing - run install.ps1 from starter pack root."
exit 1
