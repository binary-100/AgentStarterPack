#Requires -Version 5.1
<#
.SYNOPSIS
  Refresh the installed pack for this profile and report exactly what changed.
.DESCRIPTION
  Re-runs install.ps1 -Scope User, then diffs the profile before and after so the caller can see
  which rules, skills, and pack files moved - and what running agents need to do to pick them up.
  Reporting matters because the installer only ever adds and overwrites: a file left behind by an
  older pack version stays in the profile, and nothing else says so.
.PARAMETER Prune
  Remove files in the profile that this pack no longer ships. Reported either way.
.PARAMETER SkipVerify
  Skip doctor.ps1 and the sync verify that normally run after the install.
#>
param(
    [switch]$Prune,
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'pack-paths.ps1')
$sourceRoot = Get-CheckoutAgentStarterPack
if (-not $sourceRoot) { $sourceRoot = Get-AgentStarterPackRoot }
if (-not $sourceRoot -or -not (Test-Path $sourceRoot)) {
    Write-Host 'ERROR: cannot resolve the pack this script belongs to.'
    exit 1
}
$installPs1 = Join-Path $sourceRoot 'install.ps1'
if (-not (Test-Path $installPs1)) {
    Write-Host "ERROR: install.ps1 not found at $installPs1"
    exit 1
}

# Get-PackHomeDir, not $env:USERPROFILE: that variable is Windows-only, so off Windows this line
# threw "Cannot bind argument to parameter 'Path' because it is null" before doing anything - which
# is how Update-AgentRules.sh failed the first time it was ever run (WQ-451/WQ-454). The helper
# returns USERPROFILE first, so Windows behaviour is unchanged.
$userCursor = Join-Path (Get-PackHomeDir) '.cursor'
$installedRoot = Join-Path $userCursor 'AgentStarterPack'
$userRules = Join-Path $userCursor 'rules'
$userSkills = Join-Path $userCursor 'skills'
$mcpPath = Join-Path $userCursor 'mcp.json'

function Get-TreeHashes([string]$Root) {
    $map = @{}
    if (-not (Test-Path $Root)) { return $map }
    $rootFull = (Resolve-Path -LiteralPath $Root).Path
    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\__pycache__\\' } |
        ForEach-Object {
            $rel = Get-PackRelPathKey -Path $_.FullName -Root $rootFull
            $map[$rel] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    return $map
}

function Get-McpServerNames([string]$Path) {
    if (-not (Test-Path $Path)) { return @() }
    try {
        $obj = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $obj.mcpServers) { return @() }
        return @(($obj.mcpServers.PSObject.Properties).Name)
    } catch {
        return @('<unparseable>')
    }
}

function Get-PackVersion([string]$Root) {
    $f = Join-Path $Root 'VERSION'
    if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    return '(none)'
}

function Get-AuditEngineVersion([string]$Root) {
    $f = Join-Path $Root 'pack/audit/manifest.json'
    if (-not (Test-Path $f)) { return '(none)' }
    try { return ((Get-Content $f -Raw -Encoding UTF8) | ConvertFrom-Json).version }
    catch { return '(unreadable)' }
}

Write-Host "Update agents - refresh installed pack for this profile`n"
Write-Host "Source pack: $sourceRoot"
Write-Host "Installed:   $installedRoot"
Write-Host ''

$wasInstalled = Test-Path $installedRoot
$prevManifest = $null
$prevManifestPath = Join-Path $installedRoot 'install-manifest.json'
if (Test-Path $prevManifestPath) {
    try { $prevManifest = Get-Content $prevManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $prevManifest = $null }
}
$before = @{
    pack   = Get-TreeHashes $installedRoot
    rules  = Get-TreeHashes $userRules
    skills = Get-TreeHashes $userSkills
    mcp    = Get-McpServerNames $mcpPath
    ver    = Get-PackVersion $installedRoot
    engine = Get-AuditEngineVersion $installedRoot
}

Write-Host 'Running install.ps1 -Scope User ...'
Write-Host ('-' * 60)
$installArgs = @('-Scope', 'User', '-NoPause')
if ($Prune) { $installArgs += '-Prune' }
$installExit = Invoke-PackScript -NoProfile -ScriptPath $installPs1 @installArgs
Write-Host ('-' * 60)
if ($installExit -ne 0) {
    Write-Host "`nERROR: install failed (exit $installExit). Profile left as the installer wrote it."
    exit 1
}

$after = @{
    pack   = Get-TreeHashes $installedRoot
    rules  = Get-TreeHashes $userRules
    skills = Get-TreeHashes $userSkills
    mcp    = Get-McpServerNames $mcpPath
    ver    = Get-PackVersion $installedRoot
    engine = Get-AuditEngineVersion $installedRoot
}

function Write-TreeDiff([string]$Label, [hashtable]$Before, [hashtable]$After, [string]$SourceMirror,
                        [string[]]$PreviouslyShipped = $null) {
    $added = @($After.Keys | Where-Object { -not $Before.ContainsKey($_) } | Sort-Object)
    $updated = @($After.Keys | Where-Object { $Before.ContainsKey($_) -and $Before[$_] -ne $After[$_] } | Sort-Object)
    $same = @($After.Keys | Where-Object { $Before.ContainsKey($_) -and $Before[$_] -eq $After[$_] }).Count
    Write-Host "$Label - added $($added.Count), updated $($updated.Count), unchanged $same"
    foreach ($f in $added) { Write-Host "    + $f" }
    foreach ($f in $updated) { Write-Host "    ~ $f" }
    # The installer never deletes, so anything here that the pack no longer ships stays forever.
    if ($SourceMirror -and (Test-Path $SourceMirror)) {
        # install-manifest.json is written by the installer itself and has no source counterpart.
        $orphans = @($After.Keys | Where-Object {
                $_ -ne 'install-manifest.json' -and -not (Test-Path -LiteralPath (Join-Path $SourceMirror $_))
            } | Sort-Object)
        if ($orphans.Count -gt 0) {
            # A file the pack once installed is a leftover; anything else belongs to the user.
            $wasShipped = @($orphans | Where-Object { $PreviouslyShipped -and $PreviouslyShipped -contains $_ })
            $notOurs = @($orphans | Where-Object { -not ($PreviouslyShipped -and $PreviouslyShipped -contains $_) })
            if ($wasShipped.Count -gt 0) {
                Write-Host "    stale - this pack installed these and no longer ships them ($($wasShipped.Count)); remove with -Prune:"
                foreach ($f in $wasShipped) { Write-Host "      - $f" }
            }
            if ($notOurs.Count -gt 0) {
                Write-Host "    not from this pack ($($notOurs.Count)) - yours, never touched:"
                foreach ($f in $notOurs) { Write-Host "      . $f" }
            }
        }
    }
}

Write-Host ''
Write-Host '=== What changed in this profile ==='
if (-not $wasInstalled) { Write-Host 'First install for this profile - everything below is new.' }
Write-Host "Pack version:  $($before.ver) -> $($after.ver)"
Write-Host "Audit engine:  $($before.engine) -> $($after.engine)"
Write-Host ''
$prevRules = if ($prevManifest -and $prevManifest.rules) { @($prevManifest.rules) } else { @() }
$prevSkills = if ($prevManifest -and $prevManifest.skills) { @($prevManifest.skills) } else { @() }
Write-TreeDiff 'Rules ' $before.rules $after.rules (Join-Path $sourceRoot 'pack/rules') $prevRules
Write-TreeDiff 'Skills' $before.skills $after.skills (Join-Path $sourceRoot 'pack/skills') $prevSkills
Write-TreeDiff 'Pack  ' $before.pack $after.pack $sourceRoot

$mcpAdded = @($after.mcp | Where-Object { $before.mcp -notcontains $_ })
$mcpLost = @($before.mcp | Where-Object { $after.mcp -notcontains $_ })
Write-Host "MCP servers - $($after.mcp.Count) configured$(if ($mcpAdded) { "; added: $($mcpAdded -join ', ')" })"
if ($mcpLost.Count -gt 0) {
    Write-Host "  WARNING: servers present before this run are now missing: $($mcpLost -join ', ')"
    Write-Host "  A timestamped backup of the previous file may exist as $mcpPath.bak"
}

$verifyFailed = $false
if (-not $SkipVerify) {
    Write-Host ''
    Write-Host '=== Verify ==='
    $doctor = Join-Path $installedRoot 'pack/scripts/doctor.ps1'
    if (Test-Path $doctor) {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $doctor | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) { $verifyFailed = $true; Write-Host '  doctor.ps1 reported failures' }
    }
    $sync = Join-Path $sourceRoot 'pack/scripts/sync-audit-system.ps1'
    if (Test-Path $sync) {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $sync -VerifyOnly | Select-Object -Last 2 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) { $verifyFailed = $true; Write-Host '  sync verify reported drift' }
    }
}

Write-Host ''
Write-Host '=== Agents ==='
# WQ-456: this used to promise rules load automatically. Skills do - `~/.cursor/skills/` is a
# documented global load path. Rules do not: no editor documents reading a home-folder rules
# directory, so a rule binds only where it has been synced into a project's `.cursor/rules/`.
Write-Host 'New chats read the updated skills automatically.'
Write-Host 'Rules do not load from the user profile - no editor documents reading that folder.'
Write-Host 'Deliver them per project:  sync-project-rules.ps1 -ProjectRoot <project>'
Write-Host "Already-open chat: run $(Get-PackEntryPoint 'Refresh-AgentContext') - it names the rule files to re-read."
if ($mcpAdded.Count -gt 0 -or -not $wasInstalled) {
    Write-Host 'Restart Cursor once so the MCP server list reloads.'
}
$changedAgentFacing = @($after.rules.Keys | Where-Object {
        -not $before.rules.ContainsKey($_) -or $before.rules[$_] -ne $after.rules[$_]
    }).Count -gt 0
if ($changedAgentFacing) {
    Write-Host 'A chat already in progress still has the old rule text in context. Paste this into it:'
    Write-Host ''
    Write-Host "  The Agent Starter Pack was updated. Re-read $userRules and"
    Write-Host "  $installedRoot\pack\docs\START_HERE.md before continuing."
}

Write-Host ''
if ($verifyFailed) {
    Write-Host 'Update finished, but verification reported problems (see above).'
    exit 1
}
Write-Host 'Update complete.'
exit 0
