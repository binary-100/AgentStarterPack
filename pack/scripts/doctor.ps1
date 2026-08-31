#Requires -Version 5.1
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

Write-Host "Agent Starter Pack doctor v$packVersion"

# Which shell hosted this run. The pack pins its own nested calls to 5.1, but running a script directly
# from a pwsh prompt hosts it on 7 - so the same checkout can behave differently depending on how it was
# launched, and the difference is silent. Encoding bugs got in exactly that way.
$shell = Get-PackShellInfo
$hostLine = "Host shell: PowerShell $($shell.hostVersion) ($($shell.hostEdition)) - pack floor is $($shell.floorVersion)"
if ($shell.isCore) {
    Write-Host "$hostLine [!] verify on 5.1 before shipping: pack\scripts\verify-audit-behavior.ps1"
} elseif ($shell.pwshAvailable) {
    Write-Host "$hostLine; pwsh available for a cross-version run (-DualShell)"
} else {
    Write-Host $hostLine
}
Write-Host ''

if ($UserScope -or (-not $UserScope -and -not $ProjectScope)) {
    Write-Host "User scope (~/.cursor):"
    $userCursor = Get-AgentStarterPackUserRoot
    if (-not $userCursor) { $userCursor = Get-DefaultCursorUserRoot }
    if (-not $userCursor) {
        Write-Miss 'cannot resolve Cursor user root (~/.cursor)'
        $userCursor = Join-Path $env:USERPROFILE '.cursor'
    }
    # Enumerated from the pack, never listed by hand: the hardcoded list checked 5 of the 9 rules
    # install.ps1 copies, so four could go missing from the profile and doctor still said [OK].
    $packSkillsDir = Join-Path $packRoot 'pack\skills'
    $packRulesDir = Join-Path $packRoot 'pack\rules'
    if (Test-Path $packSkillsDir) {
        Get-ChildItem $packSkillsDir -Directory | Sort-Object Name | ForEach-Object {
            Test-PathReport "skill $($_.Name)" (Join-Path $userCursor "skills\$($_.Name)\SKILL.md")
        }
    } else {
        Write-Warn "pack\skills not found beside doctor.ps1 - cannot verify installed skills"
    }
    if (Test-Path $packRulesDir) {
        Get-ChildItem $packRulesDir -Filter *.mdc | Sort-Object Name | ForEach-Object {
            Test-PathReport "rule $($_.BaseName)" (Join-Path $userCursor "rules\$($_.Name)")
        }
    } else {
        Write-Warn "pack\rules not found beside doctor.ps1 - cannot verify installed rules"
    }
    Test-PathReport "canonical pack" (Join-Path $installedRoot "pack")
    Test-PathReport "MCP server" (Join-Path $installedRoot "mcp\agent_hygiene_server.py")
    Write-Host ""

    $mcpPath = Join-Path $userCursor 'mcp.json'
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

    $pyProbe = Resolve-PackPythonInvoke

    # One source of truth for environment requirements: doctor reports, check-requirements decides.
    $preflight = Join-Path $PSScriptRoot "check-requirements.ps1"
    if (Test-Path $preflight) {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $preflight -Quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Miss "environment requirements - fix the items listed above"
        } else {
            Write-Ok "environment requirements (Python, audit engine; mcp and git optional)"
        }
    }

    if (-not $SkipSmoke -and $pyProbe) {
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
            $pyArgs = @($pyProbe.prefix + @('-c', $pyCode))
            $smoke = & $pyProbe.exe @pyArgs 2>&1
            if ($LASTEXITCODE -eq 0 -and "$smoke" -match "smoke_ok") {
                Write-Ok "MCP smoke test (agent_hygiene_full_check)"
            } else {
                Write-Warn "MCP smoke test failed: $smoke"
            }
        }
    } elseif (-not $SkipSmoke -and -not $pyProbe) {
        Write-Warn 'MCP smoke test skipped (no Python interpreter found)'
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
