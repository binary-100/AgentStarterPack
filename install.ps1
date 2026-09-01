#Requires -Version 5.1
# Install Agent Starter Pack - user and/or project scope + optional MCP
param(
    [ValidateSet("User", "Project", "Both")]
    [string]$Scope = "Both",
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$RegisterMcp,
    [switch]$InstallSessionHooks,
    [switch]$InstallMcpDeps,
    [switch]$NoPause,
    [switch]$SkipPreflight,
    [switch]$Prune
)

$ErrorActionPreference = "Stop"
$PackRoot = Join-Path $PSScriptRoot "pack"
$versionFile = Join-Path $PSScriptRoot "VERSION"
$Version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "1.2.0" }
if (-not (Test-Path $PackRoot)) {
    Write-Error "pack/ not found beside install.ps1"
}

# Write-Utf8NoBom and Get-PackShellInfo: the installer used its own inline byte-writer, which is how
# four copies of the same encoding fix ended up in the pack. Also brings the install-root override.
. (Join-Path $PackRoot 'scripts\pack-paths.ps1')

# AGENT_STARTER_PACK_INSTALL_ROOT redirects the destination. Every other script honoured it through
# pack-paths.ps1; this one hardcoded %USERPROFILE%\.cursor, so a test asking for a scratch destination
# was silently given the real profile instead - the one place where ignoring the override does damage.
$installOverride = Get-AgentStarterPackInstallRootOverride
if ($installOverride) {
    $CanonicalRoot = $installOverride
    # Parent of the installed root, so rules\, skills\ and mcp.json move with it instead of half
    # redirecting into the real profile.
    $UserCursor = Get-AgentStarterPackUserRoot
} else {
    $UserCursor = Join-Path $env:USERPROFILE ".cursor"
    $CanonicalRoot = Join-Path $UserCursor "AgentStarterPack"
}
$LegacyCanonical = Join-Path $UserCursor "agent-starter-pack"

function Copy-Tree($src, $dst, [string[]]$SkipNames = @(), [string[]]$SkipDirNames = @(),
                   [string[]]$SkipExtensions = @(), [string[]]$SkipNamePatterns = @(),
                   [string[]]$SkipRelPaths = @()) {
    if (-not (Test-Path $dst)) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
    }
    Get-ChildItem -Path $src -Recurse -File -Force | ForEach-Object {
        if ($SkipNames -contains $_.Name) { return }
        if ($SkipExtensions -contains $_.Extension) { return }
        foreach ($pattern in $SkipNamePatterns) {
            if ($_.Name -like $pattern) { return }
        }
        $rel = $_.FullName.Substring($src.Length).TrimStart("\")
        # Exact relative paths, so excluding a root doc cannot also exclude a same-named file
        # somewhere under pack\. A listed folder excludes everything under it: docs\handoffs
        # accumulates a file per work slice, and naming them one by one guarantees the next one ships.
        if ($SkipRelPaths -contains $rel) { return }
        $inSkippedDir = $false
        foreach ($skipRel in $SkipRelPaths) {
            if ($rel -like "$skipRel\*") { $inSkippedDir = $true; break }
        }
        if ($inSkippedDir) { return }
        foreach ($skipDir in $SkipDirNames) {
            # Nested matches count too: __pycache__ sits under pack\scripts, not at the root.
            if ($rel -like "$skipDir*" -or $rel -like "*\$skipDir*") { return }
        }
        $target = Join-Path $dst $rel
        $dir = Split-Path $target -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Copy-Item -Path $_.FullName -Destination $target -Force
    }
}

function Get-RelativeFileSet([string]$Root) {
    $set = @{}
    if (-not (Test-Path $Root)) { return $set }
    $full = (Resolve-Path -LiteralPath $Root).Path
    Get-ChildItem -LiteralPath $full -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $set[$_.FullName.Substring($full.Length).TrimStart('\')] = $true
    }
    return $set
}

# Copy-Tree only ever adds, so a file the pack stopped shipping lives in the profile forever - and a
# stale rule keeps instructing agents in every project on the machine. The canonical tree is entirely
# pack-owned, so anything there without a source counterpart is stale. Profile rules and skills also
# hold the user's own files, so those are matched against what a previous install recorded shipping.
function Get-StaleInstalledFiles([string]$SourceRoot, [string]$InstalledRoot, [string]$RulesDir,
                                 [string]$SkillsDir, $PreviousManifest) {
    $stale = New-Object System.Collections.ArrayList
    $sourceFiles = Get-RelativeFileSet $SourceRoot
    foreach ($rel in (Get-RelativeFileSet $InstalledRoot).Keys) {
        if ($rel -eq 'install-manifest.json') { continue }
        # Scratch and bytecode are pruned elsewhere and may be in use by a concurrent run.
        if ($rel -like '.tmp\*' -or $rel -like '__pycache__\*' -or $rel -like '*\__pycache__\*') { continue }
        if (-not $sourceFiles.ContainsKey($rel)) { [void]$stale.Add((Join-Path $InstalledRoot $rel)) }
    }
    if ($PreviousManifest) {
        foreach ($pair in @(
                @{ recorded = $PreviousManifest.rules; source = (Join-Path $SourceRoot 'pack\rules'); dest = $RulesDir },
                @{ recorded = $PreviousManifest.skills; source = (Join-Path $SourceRoot 'pack\skills'); dest = $SkillsDir })) {
            if (-not $pair.recorded -or -not $pair.dest) { continue }
            foreach ($rel in $pair.recorded) {
                if (Test-Path -LiteralPath (Join-Path $pair.source $rel)) { continue }
                $installed = Join-Path $pair.dest $rel
                if (Test-Path -LiteralPath $installed) { [void]$stale.Add($installed) }
            }
        }
    }
    return $stale
}

function Merge-McpJson {
    $mcpPath = Join-Path $UserCursor "mcp.json"
    $serverPy = Join-Path $CanonicalRoot "mcp\agent_hygiene_server.py"
    $pyCmd = "py"
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        $pyCmd = "python"
    }
    $entry = [pscustomobject]@{
        command = $pyCmd
        args    = @("-3", $serverPy)
    }
    $root = [pscustomobject]@{ mcpServers = [pscustomobject]@{} }
    if (Test-Path $mcpPath) {
        try {
            $root = Get-Content $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            # An unreadable config is the user's data: back it up, leave it in place, register nothing.
            $bak = "$mcpPath.bak"
            Copy-Item $mcpPath $bak -Force
            Write-Warning "Could not parse $mcpPath - MCP not registered (backup: $bak)."
            Write-Warning "Fix the JSON, then re-run: install.ps1 -RegisterMcp"
            return
        }
        if (-not $root.PSObject.Properties['mcpServers'] -or $null -eq $root.mcpServers) {
            $root | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) -Force
        }
    }
    # Dot-assignment of a new key throws on a PSCustomObject from ConvertFrom-Json; Add-Member -Force
    # both adds and replaces, and keeps every server the user already configured.
    $root.mcpServers | Add-Member -NotePropertyName 'agent-hygiene' -NotePropertyValue $entry -Force
    $total = (($root.mcpServers.PSObject.Properties).Name).Count
    $json = $root | ConvertTo-Json -Depth 10
    Write-Utf8NoBom -Path $mcpPath -Text $json
    Write-Host "MCP registered: $mcpPath (server: agent-hygiene; $total server(s) total)"
    Write-Host "Restart Cursor to load MCP tools."
}

function Merge-SessionHooks {
    $hooksDir = Join-Path $UserCursor 'hooks'
    $hooksPath = Join-Path $UserCursor 'hooks.json'
    $srcScript = Join-Path $PSScriptRoot 'pack\templates\cursor\hooks\session-freshness.ps1'
    if (-not (Test-Path -LiteralPath $srcScript)) {
        Write-Warning "Session hook template missing: $srcScript"
        return
    }
    if (-not (Test-Path -LiteralPath $hooksDir)) {
        New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $srcScript -Destination (Join-Path $hooksDir 'session-freshness.ps1') -Force
    $ourCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File hooks/session-freshness.ps1'
    $entry = @{ command = $ourCmd }

    $root = @{ version = 1; hooks = @{ sessionStart = @($entry) } }
    if (Test-Path -LiteralPath $hooksPath) {
        try {
            $existing = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $existing.hooks) {
                $existing | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $kept = @()
            if ($existing.hooks.sessionStart) {
                foreach ($h in @($existing.hooks.sessionStart)) {
                    if ($h.command -notmatch 'session-freshness\.ps1') { $kept += $h }
                }
            }
            $kept += $entry
            $existing.hooks.sessionStart = $kept
            $root = $existing
        } catch {
            Write-Warning "Could not parse $hooksPath - session hooks not registered (backup and fix JSON first)."
            return
        }
    }
    Write-Utf8NoBom -Path $hooksPath -Text ($root | ConvertTo-Json -Depth 8)
    Write-Host "Session hooks registered: $hooksPath (sessionStart -> session-freshness.ps1)"
    Write-Host "Restart Cursor to load sessionStart hook."
}

Write-Host "Agent Starter Pack v$Version - install ($Scope)`n"

# Preflight before copying anything: a machine without Python gets a named requirement and an
# install command here, instead of a cryptic failure the first time an audit shells out to py -3.
if (-not $SkipPreflight) {
    $preflight = Join-Path $PackRoot 'scripts\check-requirements.ps1'
    if (Test-Path $preflight) {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $preflight -Quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Host ''
            Write-Host 'Install stopped: the requirements above are missing.'
            Write-Host 'Install them and re-run, or use -SkipPreflight to install the files anyway.'
            if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
            exit 1
        }
    }
}

# Migrate legacy canonical folder name (pre-1.7.0)
if ((Test-Path $LegacyCanonical) -and -not (Test-Path $CanonicalRoot)) {
    Move-Item -LiteralPath $LegacyCanonical -Destination $CanonicalRoot
    Write-Host "Migrated canonical install: agent-starter-pack -> AgentStarterPack"
}

# Canonical copy under ~/.cursor/AgentStarterPack for stable MCP paths.
# The skips matter because Copy-Tree only ever adds: bytecode from another Python version, a live
# .tmp scratch dir, git internals, and the source machine's audit results (.audit_* - a recorded
# test-pass proof and semantic report) would all take up permanent residence in the profile.
#
# maintainerOnlyPaths keeps pack-development notes out of the install: handoffs and implementation
# specs are written for whoever picks up the pack next, and a user who installed it has no use for
# a stale one. .zip is excluded for the same reason - a release archive in the checkout is a build
# artifact, not something to carry into every profile.
$maintainerOnly = @()
$mirrorManifest = Join-Path $PSScriptRoot 'pack\audit\manifest.json'
if (Test-Path -LiteralPath $mirrorManifest) {
    try {
        $mm = Get-Content -LiteralPath $mirrorManifest -Raw | ConvertFrom-Json
        $maintainerOnly = @($mm.maintainerOnlyPaths | Where-Object { $_ }) | ForEach-Object { $_ -replace '/', '\' }
    } catch {
        Write-Warning "Could not read maintainerOnlyPaths from the manifest - shipping the full tree: $_"
    }
}
Copy-Tree $PSScriptRoot $CanonicalRoot `
    -SkipDirNames @('.git\', '.tmp\', '__pycache__\', '.pytest_cache\') `
    -SkipExtensions @('.pyc', '.pyo', '.zip') -SkipNamePatterns @('.audit_*') `
    -SkipRelPaths $maintainerOnly
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

if ($InstallSessionHooks) {
    Merge-SessionHooks
}

if ($InstallMcpDeps) {
    $req = Join-Path $CanonicalRoot "mcp\requirements.txt"
    if (Test-Path $req) {
        Write-Host "Installing MCP Python deps..."
        & py -3 -m pip install --user -r $req --quiet
    }
}

$manifestPath = Join-Path $CanonicalRoot "install-manifest.json"
$previousManifest = $null
if (Test-Path $manifestPath) {
    try { $previousManifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $previousManifest = $null }
}

$stale = Get-StaleInstalledFiles $PSScriptRoot $CanonicalRoot (Join-Path $UserCursor 'rules') `
    (Join-Path $UserCursor 'skills') $previousManifest
if ($stale.Count -gt 0) {
    if ($Prune) {
        foreach ($f in $stale) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        # Directories emptied by the removals above (a whole skill folder, for instance).
        foreach ($root in @($CanonicalRoot, (Join-Path $UserCursor 'rules'), (Join-Path $UserCursor 'skills'))) {
            if (-not (Test-Path $root)) { continue }
            Get-ChildItem -LiteralPath $root -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                Sort-Object { $_.FullName.Length } -Descending |
                Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue) } |
                ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
        }
        Write-Host "Pruned $($stale.Count) file(s) this pack no longer ships."
    } else {
        Write-Host "$($stale.Count) file(s) in the profile are no longer shipped by this pack:"
        foreach ($f in ($stale | Select-Object -First 10)) { Write-Host "  $f" }
        if ($stale.Count -gt 10) { Write-Host "  ... and $($stale.Count - 10) more" }
        Write-Host 'Re-run with -Prune to remove them.'
    }
}

# Recorded so a later install can tell its own leftovers from rules and skills the user added.
$shippedRules = @(Get-ChildItem (Join-Path $PackRoot 'rules') -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
$skillsRoot = Join-Path $PackRoot 'skills'
$shippedSkills = @((Get-RelativeFileSet $skillsRoot).Keys)

$manifest = @{
    version      = $Version
    installed_at = (Get-Date).ToUniversalTime().ToString("o")
    scope        = $Scope
    project_root = $ProjectRoot
    mcp          = ($RegisterMcp -or $Scope -eq "User" -or $Scope -eq "Both")
    sessionHooks = [bool]$InstallSessionHooks
    canonical    = $CanonicalRoot
    rules        = $shippedRules
    skills       = $shippedSkills
} | ConvertTo-Json

Set-Content -Path $manifestPath -Value $manifest

$syncScript = Join-Path $CanonicalRoot "pack\scripts\sync-audit-system.ps1"
if (Test-Path $syncScript) {
    Write-Host "Syncing audit system..."
    # These steps run Python out of the installed tree, which would otherwise leave __pycache__
    # behind in the profile - the same artifacts Copy-Tree above deliberately refuses to copy.
    $prevNoBytecode = $env:PYTHONDONTWRITEBYTECODE
    $env:PYTHONDONTWRITEBYTECODE = '1'
    try {
        $syncExit = Invoke-PackScript -ScriptPath $syncScript -NoProfile
        if ($syncExit -ne 0) { throw "sync-audit-system.ps1 exited $syncExit" }
    } finally {
        $env:PYTHONDONTWRITEBYTECODE = $prevNoBytecode
    }
}

# Bytecode from an earlier install, or from an audit that resolved this installed pack.
Get-ChildItem $CanonicalRoot -Recurse -Force -Directory -Filter '__pycache__' -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }

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
