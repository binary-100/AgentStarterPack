#Requires -Version 5.1
<#
.SYNOPSIS
  Sync a project's pack files and write an agent-readable brief of what changed.
.DESCRIPTION
  No chat reloads its instructions when files on disk change, so updating the pack silently leaves
  every open session acting on the old rules. This writes two artifacts the agent can be pointed at:

    AGENT_CONTEXT.json  machine-readable stamp (versions, per-layer state, changed layers)
    AGENT_REFRESH.md    short brief ending in a line to paste into a stale chat
    AGENT_PASTE.txt     the paste line alone, so copying cannot pick up stray whitespace
    AGENT_SESSION_START.md  what an agent should read first in a new session

  The contract is files, not an API - any agent can read them. Where they land depends on the project
  (Get-AgentStateRoot): an ordinary project gets them in its own docs/, since it lives at one path on
  one machine. A **pack root** gets them in a machine-local state directory outside the checkout,
  because the pack folder is portable - a generated file naming this machine's drive and user profile
  is wrong the moment the folder is copied, cloned or downloaded, and it discloses the sender's layout.
  The command prints every path it writes.
.PARAMETER ProjectRoot
  Project to refresh. Defaults to the pack checkout this script belongs to (maintainer mode).
.PARAMETER RulesRelativePath
  Where the project keeps its copy of the generic rules. Default .cursor\rules.
.PARAMETER Install
  Also run install.ps1 -Scope User first. Off by default: installing is a profile-wide change.
.PARAMETER SkipProjectSync
  Write the artifacts without running the project rule and audit-template syncs.
.PARAMETER PackRoot
  Override the pack to read. Default resolves via pack-paths.ps1.
.PARAMETER NoClipboard
  Do not put the paste line on the clipboard (it is still written to AGENT_PASTE.txt).
#>
param(
    [string]$ProjectRoot = '',
    [string]$RulesRelativePath = '.cursor\rules',
    [switch]$Install,
    [switch]$SkipProjectSync,
    [string]$PackRoot = '',
    [string[]]$StarterPackAirlockDesktopRoots = @(),
    [switch]$NoClipboard
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'pack-paths.ps1')

if (-not $PackRoot) {
    $PackRoot = Get-CheckoutAgentStarterPack
    if (-not $PackRoot) { $PackRoot = Get-AgentStarterPackRoot }
}
if (-not $PackRoot -or -not (Test-Path -LiteralPath $PackRoot)) {
    Write-Host 'ERROR: cannot resolve the Agent Starter Pack. Pass -PackRoot or set AGENT_STARTER_PACK_ROOT.'
    exit 1
}

# Maintainer mode: refreshing the pack repo itself is the common case on a maintainer machine.
if (-not $ProjectRoot) { $ProjectRoot = $PackRoot }
if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    Write-Host "ERROR: project root not found: $ProjectRoot"
    exit 1
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$PackRoot = (Resolve-Path -LiteralPath $PackRoot).Path

function Get-TextOrNull([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return (Get-Content -LiteralPath $Path -Raw).Trim() }
    return $null
}

function Get-JsonOrNull([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

# Stable across runs and across machines: hash file contents, not paths or timestamps.
function Get-RulesRevision([string]$RulesDir) {
    if (-not (Test-Path -LiteralPath $RulesDir)) { return $null }
    $parts = @(Get-ChildItem -LiteralPath $RulesDir -Filter '*.mdc' -File -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object { "$($_.Name):$((Get-PackFileSha256 $_.FullName))" })
    if ($parts.Count -eq 0) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($parts -join "`n"))
    return 'sha256:' + ([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant())
}

# WQ-456: the rules an agent must re-read are the ones an editor actually loads, and that is the
# project's rules folder - never `%USERPROFILE%\.cursor\rules\`. Cursor documents four rule locations
# (project `.cursor/rules/`, User Rules, Team Rules, AGENTS.md) and a home-folder rules directory is
# not among them; a profile copy with `alwaysApply: true` sat inert for months behind a green
# doctor.ps1. Rules also do not reload mid-session, so this list is the only channel that can carry a
# rule change into a chat that is already open.
function Get-AlwaysOnRuleFiles([string]$RulesDir) {
    if (-not (Test-Path -LiteralPath $RulesDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $RulesDir -Filter '*.mdc' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        Where-Object {
            # Frontmatter only: a rule body may quote `alwaysApply: true` while describing another rule.
            $head = @(Get-Content -LiteralPath $_.FullName -TotalCount 12 -ErrorAction SilentlyContinue)
            ($head -join "`n") -match '(?m)^\s*alwaysApply:\s*true\s*$'
        } |
        ForEach-Object { $_.FullName })
}

# Write-Utf8NoBom comes from pack-paths.ps1 - one writer for the whole pack.

$isPackRepo = (Test-Path -LiteralPath (Join-Path $ProjectRoot 'pack/audit/manifest.json')) -and
              (Test-Path -LiteralPath (Join-Path $ProjectRoot 'install.ps1'))

Write-Host "Agent context refresh"
Write-Host "Pack:    $PackRoot"
Write-Host "Project: $ProjectRoot$(if ($isPackRepo) { '  (pack maintainer repo)' })"
Write-Host ''

$docsDir = Join-Path $ProjectRoot 'docs'
if (-not (Test-Path -LiteralPath $docsDir)) {
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
}

# Two destinations, deliberately different. Project docs (WORK_QUEUE, WORK_COMPLETION) belong to the
# repository and are committed. The four generated context artifacts are this machine's answer about
# this checkout - absolute paths, installed engine version, sync state - and for a pack root they go to
# a machine-local state directory instead of docs\, because the pack folder travels. Ordinary projects
# are unaffected: Get-AgentStateRoot returns their own docs\.
$stateDir = Get-AgentStateRoot -ProjectRoot $ProjectRoot
if (-not (Test-Path -LiteralPath $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}
$stateIsOutsideProject = ($stateDir.TrimEnd('\', '/') -ne $docsDir.TrimEnd('\', '/'))

$workQueueLayer = 'skipped'
$ensureWq = Join-Path $PSScriptRoot 'ensure-work-queue.ps1'
if (Test-Path -LiteralPath $ensureWq) {
    $hadWq = Test-Path -LiteralPath (Join-Path $docsDir 'WORK_QUEUE.md')
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $ensureWq -ProjectRoot $ProjectRoot -PackRoot $PackRoot | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: ensure-work-queue failed (exit $LASTEXITCODE)"; exit 1 }
    $workQueueLayer = if (-not $hadWq -and (Test-Path -LiteralPath (Join-Path $docsDir 'WORK_QUEUE.md'))) { 'created' } else { 'ok' }
}

$workCompletionLayer = 'skipped'
$ensureWc = Join-Path $PSScriptRoot 'ensure-work-completion.ps1'
if (Test-Path -LiteralPath $ensureWc) {
    $hadWc = Test-Path -LiteralPath (Join-Path $docsDir 'WORK_COMPLETION.md')
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $ensureWc -ProjectRoot $ProjectRoot -PackRoot $PackRoot | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: ensure-work-completion failed (exit $LASTEXITCODE)"; exit 1 }
    $workCompletionLayer = if (-not $hadWc -and (Test-Path -LiteralPath (Join-Path $docsDir 'WORK_COMPLETION.md'))) {
        'created'
    } elseif ($isPackRepo) {
        # Deliberately absent here: the pack's canonical checklist is pack/docs/WORK_COMPLETION.md.
        # Reporting 'ok' for a file that does not exist is the kind of quiet lie that costs an hour later.
        'n/a (pack root - see pack/docs/WORK_COMPLETION.md)'
    } else {
        'ok'
    }
}

$contextPath = Join-Path $stateDir 'AGENT_CONTEXT.json'
$refreshPath = Join-Path $stateDir 'AGENT_REFRESH.md'
$previous = Get-JsonOrNull $contextPath

$layers = [ordered]@{
    loadedRules    = 'unknown'
    globalRules    = 'skipped'
    installedPack  = 'unknown'
    projectRules   = 'skipped'
    auditTemplates = 'skipped'
    workQueue      = $workQueueLayer
    workCompletion = $workCompletionLayer
}

if ($Install) {
    $installPs1 = Join-Path $PackRoot 'install.ps1'
    if (Test-Path -LiteralPath $installPs1) {
        Write-Host 'Running install.ps1 -Scope User ...'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $installPs1 -Scope User -NoPause | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: install failed (exit $LASTEXITCODE)"; exit 1 }
        $layers.globalRules = 'updated'
    }
}

# The pack repo is the source of the rules and templates, so syncing it into itself is meaningless.
if (-not $SkipProjectSync -and -not $isPackRepo) {
    $syncRules = Join-Path $PackRoot 'pack/scripts/sync-project-rules.ps1'
    if (Test-Path -LiteralPath $syncRules) {
        Write-Host 'Syncing generic rules into the project ...'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $syncRules -ProjectRoot $ProjectRoot `
            -RulesRelativePath $RulesRelativePath | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: rule sync failed (exit $LASTEXITCODE)"; exit 1 }
        $layers.projectRules = 'updated'
    }
    $syncAudit = Join-Path $PackRoot 'pack/scripts/sync-audit-system.ps1'
    if (Test-Path -LiteralPath $syncAudit) {
        Write-Host 'Syncing audit templates into the project ...'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $syncAudit -ProjectRoot $ProjectRoot | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: audit template sync failed (exit $LASTEXITCODE)"; exit 1 }
        $layers.auditTemplates = 'updated'
    }
    $repairDocs = Join-Path $PackRoot 'pack/scripts/repair-agent-docs.ps1'
    if (Test-Path -LiteralPath $repairDocs) {
        Write-Host 'Repairing tool-neutral hub docs (AI_INSTRUCTIONS, portable rules, adapters) ...'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairDocs -ProjectRoot $ProjectRoot -PackRoot $PackRoot 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: repair-agent-docs failed (exit $LASTEXITCODE)"; exit 1 }
        $layers.agentHubDocs = 'updated'
    }
}

$packVersion = Get-TextOrNull (Join-Path $PackRoot 'VERSION')
$packManifest = Get-JsonOrNull (Join-Path $PackRoot 'pack/audit/manifest.json')
$auditEngineVersion = if ($packManifest) { $packManifest.version } else { $null }
$rulesRevision = Get-RulesRevision (Join-Path $PackRoot 'pack/rules')

$installedRoot = Get-InstalledAgentStarterPack
if (Test-AgentStarterPackInstalled) {
    $installedManifest = Get-JsonOrNull (Join-Path $installedRoot 'pack/audit/manifest.json')
    $installedVersion = if ($installedManifest) { $installedManifest.version } else { $null }
    # A stale install is what agents actually load from, so name the drift rather than the intent.
    $layers.installedPack = if ($installedVersion -eq $auditEngineVersion) { 'ok' } else { 'stale' }
} else {
    $installedVersion = $null
    $layers.installedPack = 'skipped'
    $installedRoot = $null
}
# WQ-456: this used to read `globalRules = 'ok'` whenever the installed pack matched, which asserted
# nothing about rules and reassured the reader that a dead path was healthy. The profile copy is
# best-effort by nature - no editor documents reading it - so say so, and report the load path
# separately because that is the one that determines whether a rule has any effect.
if ($layers.globalRules -eq 'skipped' -and $layers.installedPack -eq 'ok') {
    $layers.globalRules = 'best-effort (profile copy; no editor documents loading it)'
}

# The load path, and the always-on rules sitting in it. `stale` here is the finding that matters: rules
# exist in the pack but never reached a folder an editor reads, so nothing the pack says can bind.
$ruleLoadPath = Join-Path $ProjectRoot $RulesRelativePath
$alwaysOnRules = @(Get-AlwaysOnRuleFiles $ruleLoadPath)
# Hashed separately from `rulesRevision`, which covers `pack/rules` - the pack source. A project's
# loaded copy can move without the source moving (a sync lands, a rule is added by hand, a stale
# folder is finally populated), and that is the change an open chat has to be told about.
$loadedRulesRevision = Get-RulesRevision $ruleLoadPath
$layers.loadedRules = if (-not (Test-Path -LiteralPath $ruleLoadPath)) {
    'stale (no rules folder in the project - nothing an editor loads)'
} elseif ($alwaysOnRules.Count -eq 0) {
    'stale (rules folder has no alwaysApply rule)'
} else {
    "ok ($($alwaysOnRules.Count) always-on in $RulesRelativePath)"
}

$changed = New-Object System.Collections.ArrayList
if ($previous) {
    if ($previous.packVersion -ne $packVersion) { [void]$changed.Add('packVersion') }
    if ($previous.auditEngineVersion -ne $auditEngineVersion) { [void]$changed.Add('auditEngineVersion') }
    if ($previous.rulesRevision -ne $rulesRevision) { [void]$changed.Add('rules') }
    if ($previous.loadedRulesRevision -ne $loadedRulesRevision) { [void]$changed.Add('loadedRules') }
    foreach ($name in @($layers.Keys)) {
        $was = if ($previous.layers) { $previous.layers.$name } else { $null }
        # Prefix, not equality: a layer may carry a reason after its status ('stale (no rules folder)')
        # and a status that only counts when it is bare would silently stop reporting.
        if ($changed -contains $name) { continue }
        if ($layers[$name] -like 'updated*' -and $was -notlike 'updated*') { [void]$changed.Add($name) }
        elseif ($layers[$name] -like 'stale*' -and $was -notlike 'stale*') { [void]$changed.Add($name) }
    }
} else {
    [void]$changed.Add('firstRefresh')
}

$bootstrapPath = Join-Path $ProjectRoot '.agent-bootstrap.json'
$canonicalProjectRoot = $ProjectRoot
$boot = Get-JsonOrNull $bootstrapPath
if ($boot -and $boot.projectRoot) {
    $canonicalProjectRoot = (Resolve-Path -LiteralPath $boot.projectRoot).Path
}

$triggerPhrases = @(
    'refresh pack context',
    'sync agent context',
    'context refresh',
    'pack update'
)
$handshake = [ordered]@{
    required = $true
    fields   = @('packVersion', 'auditEngineVersion')
}

$requiredReads = New-Object System.Collections.ArrayList
[void]$requiredReads.Add((Join-Path $canonicalProjectRoot 'AGENTS.md'))
if (Test-Path -LiteralPath (Join-Path $canonicalProjectRoot 'AI_INSTRUCTIONS.md')) {
    [void]$requiredReads.Add((Join-Path $canonicalProjectRoot 'AI_INSTRUCTIONS.md'))
}
[void]$requiredReads.Add($refreshPath)
$sessionHandoffPath = Join-Path $canonicalProjectRoot 'docs/handoffs/SESSION.md'
if (Test-Path -LiteralPath $sessionHandoffPath) {
    [void]$requiredReads.Add($sessionHandoffPath)
}
if (Test-Path -LiteralPath (Join-Path $canonicalProjectRoot 'docs/WORK_QUEUE.md')) {
    [void]$requiredReads.Add((Join-Path $canonicalProjectRoot 'docs/WORK_QUEUE.md'))
}
if ($isPackRepo) {
    [void]$requiredReads.Add((Join-Path $canonicalProjectRoot 'pack/docs/START_HERE.md'))
}

# WQ-456: name the rule files, do not just say "re-read the rules". The old brief carried that sentence
# with no paths, which is unactionable in an open chat - and pointed at a profile folder no editor
# reads. Listed only when the rule text actually moved (or on a first refresh), because a required-read
# list that grows by eighteen entries every run is one nobody follows.
# `alwaysOnRules` absent means the stamp predates rule awareness, so no agent on this machine has ever
# been told to read a rule file. That is a one-time migration, not a steady state - without it the fix
# ships and stays dormant on precisely the installs that needed it.
$stampPredatesRuleReads = ($null -ne $previous) -and ($null -eq $previous.PSObject.Properties['alwaysOnRules'])
# The load path's own revision is the load-bearing condition: it fires when a rule is added, edited or
# removed, and - the case the layer status misses - when a stale folder finally becomes ok, which is
# precisely the moment an agent has never read these rules before.
$loadedRulesMoved = ($null -ne $previous) -and ($previous.loadedRulesRevision -ne $loadedRulesRevision)
$ruleReadsApply = ($changed -contains 'rules') -or ($changed -contains 'firstRefresh') -or
                  ($changed -contains 'projectRules') -or ($changed -contains 'loadedRules') -or
                  $stampPredatesRuleReads -or $loadedRulesMoved
if ($ruleReadsApply) {
    foreach ($rule in $alwaysOnRules) { [void]$requiredReads.Add($rule) }
}

# StarterPack-Airlock Phase 4 (WQ-487): append overlay requiredReads when Desktop discovery is active.
# Overlay WORK_QUEUE is publish-lane status only - never copied into the working copy tree.
$airlockDesktopOverride = if (@($StarterPackAirlockDesktopRoots).Count -gt 0) { @($StarterPackAirlockDesktopRoots) } else { $null }
$airlockDisc = Find-StarterPackAirlock -DesktopRoots $airlockDesktopOverride
$overlayRequiredReads = @()
if ($null -ne $airlockDisc) {
    $overlayRequiredReads = @($airlockDisc.RequiredReads)
    $requiredReads = [System.Collections.ArrayList]@(
        Merge-StarterPackAirlockRequiredReads -BaseReads @($requiredReads) -AirlockDiscovery $airlockDisc)
}

$syncedAt = (Get-Date).ToUniversalTime().ToString('o')
$context = [ordered]@{
    schemaVersion          = 2
    packVersion            = $packVersion
    auditEngineVersion     = $auditEngineVersion
    installedVersion       = $installedVersion
    rulesRevision          = $rulesRevision
    syncedAt               = $syncedAt
    previousSyncedAt       = if ($previous) { $previous.syncedAt } else { $null }
    packRootUsed           = $PackRoot
    installedPackRoot      = $installedRoot
    projectRoot            = $ProjectRoot
    canonicalProjectRoot   = $canonicalProjectRoot
    isPackRepo             = $isPackRepo
    ruleLoadPath           = $ruleLoadPath
    loadedRulesRevision    = $loadedRulesRevision
    alwaysOnRules          = @($alwaysOnRules)
    layers                 = $layers
    changedLayers          = @($changed)
    requiredReads          = @($requiredReads)
    starterPackAirlockActive = ($null -ne $airlockDisc)
    starterPackAirlockRoot = if ($airlockDisc) { $airlockDisc.AirlockRoot } else { $null }
    overlayRequiredReads   = @($overlayRequiredReads)
    triggerPhrases         = $triggerPhrases
    handshake              = $handshake
}
Write-Utf8NoBom $contextPath (($context | ConvertTo-Json -Depth 6))

$plain = @{
    firstRefresh       = 'First refresh for this project - treat all pack guidance as new.'
    packVersion        = "Pack version is now $packVersion."
    auditEngineVersion = "Audit engine is now $auditEngineVersion."
    rules              = "Generic rule text changed - re-read the always-on rules listed below before acting on remembered ones. Editors do not reload rules mid-session, so this list is the only way the change reaches an open chat."
    loadedRules        = if ($layers.loadedRules -like 'stale*') {
        "No always-on rule reached ``$ruleLoadPath`` - the folder an editor loads. A rule in the pack, or in the user profile, binds nothing until it lands there: run ``sync-project-rules.ps1 -ProjectRoot <project>``."
    } else {
        "The always-on rules in ``$ruleLoadPath`` changed. They are listed under Re-read below; your editor will not reload them in this session, so reading them is the only way this reaches an open chat."
    }
    globalRules        = 'Global rules and skills were copied to the user profile. That copy is best-effort - no editor documents loading a home-folder rules directory - so treat the project rules folder as the one that binds.'
    installedPack      = "Installed pack differs from this pack ($installedVersion vs $auditEngineVersion) - run install to align."
    projectRules       = 'This project''s copy of the generic rules was updated.'
    auditTemplates     = 'This project''s audit templates were updated.'
}
# A standing defect is not a change, and forcing it into changedLayers would report it as news on
# every refresh forever. It still has to be said on the first refresh - the one where a project has no
# rules folder yet and nothing the pack says can bind - so stale layers get their own section, driven
# by current status rather than by a diff against a previous stamp.
$attentionLines = @(
    foreach ($name in @($layers.Keys)) {
        if ($layers[$name] -like 'stale*') {
            '- ' + $(if ($plain[$name]) { $plain[$name] } else { "Layer is stale: $name ($($layers[$name]))" })
        }
    }
)

$changeLines = if ($changed.Count -eq 0) {
    @('- Nothing changed since the last refresh; the stamp below is current.')
} else {
    @($changed | ForEach-Object { '- ' + $(if ($plain[$_]) { $plain[$_] } else { "Layer changed: $_" }) })
}

$readList = New-Object System.Collections.ArrayList
$idx = 1
foreach ($abs in @($requiredReads)) {
    if ($abs -match 'START_HERE\.md$') {
        [void]$readList.Add("$idx. ``$abs`` - pack maintainers only")
    } elseif ($abs -match '\.mdc$') {
        [void]$readList.Add("$idx. ``$abs`` - always-on rule; your editor will not reload it mid-session")
    } elseif ($abs -match 'StarterPack-Airlock[\\/]overlay[\\/]') {
        [void]$readList.Add("$idx. ``$abs`` - publish-lane overlay (required when Desktop Airlock is active)")
    } else {
        [void]$readList.Add("$idx. ``$abs``")
    }
    $idx++
}
if ($canonicalProjectRoot -ne $ProjectRoot) {
    [void]$readList.Add('')
    [void]$readList.Add("**Workspace note:** refresh ran on ``$ProjectRoot``; canonical agent root is ``$canonicalProjectRoot`` (from bootstrap). If your editor opened a parent folder, use the absolute paths above.")
}

# The paste line is the whole point of the command, so it is built to survive copying: one line, plain
# ASCII, no backticks or quotes a chat box might mangle, a minute-precision stamp instead of the ISO
# microseconds, absolute paths, and a closing request that makes the agent prove it read the files.
# A silent "ok" is indistinguishable from an agent that ignored the paste.
$stampShort = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'
$refreshDocPath = $refreshPath
$agentsPath = Join-Path $ProjectRoot 'AGENTS.md'
$sessionPathForPaste = Join-Path $ProjectRoot 'docs/handoffs/SESSION.md'
$pasteLine = if ($isPackRepo) {
    $sessionClause = if (Test-Path -LiteralPath $sessionPathForPaste) {
        "read $sessionPathForPaste, then "
    } else { '' }
    "PACK CONTEXT REFRESHED $stampShort (pack $packVersion, audit engine $auditEngineVersion). " +
    "Before your next action: read $refreshDocPath, then ${sessionClause}re-read $agentsPath and " +
    "$(Join-Path $ProjectRoot 'docs/WORK_QUEUE.md'). Treat conclusions from earlier in this chat " +
    "as possibly stale. Confirm by replying with the pack version and audit engine version you just read."
} else {
    "PACK CONTEXT REFRESHED $stampShort (pack $packVersion, audit engine $auditEngineVersion). " +
    "Before your next action: read $refreshDocPath, then re-read $agentsPath. Treat conclusions from " +
    "earlier in this chat as possibly stale. Confirm by replying with the pack version and audit " +
    "engine version you just read."
}
$pasteLine = ($pasteLine -replace '\s+', ' ').Trim()

$md = @"
# Agent context refresh

**Generated:** $syncedAt - pack $packVersion - audit engine $auditEngineVersion

Generated by ``refresh-agent-context.ps1``. Do not edit by hand; re-run the refresh instead.

## Stale chat notice

A chat started before **$syncedAt** still has the previous instructions in its context. Nothing on
disk can reach it - treat earlier messages as possibly stale and re-read the files below.

## Re-read (required)

$($readList -join "`n")

## What changed since the last refresh

$($changeLines -join "`n")
$(if ($attentionLines.Count -gt 0) { "`n## Needs attention (standing, not new)`n`n" + ($attentionLines -join "`n") + "`n" })

## Reminders

- Version and doc cites are a build step (``docs/VERSION_SYNC.json`` / ``apply_version.py sync``), not an audit step.
- Audits report Fix and Improve; they do not delete or restructure anything on their own.
$(if (-not $isPackRepo) { "- ``pack/docs/START_HERE.md`` belongs to the Agent Starter Pack repo - do not read it for this project.`n" })
## Paste into an open chat

Three ways to do this, easiest first:

1. **Cursor:** type **refresh pack context** in the chat - no copying at all.
2. **Clipboard:** the refresh command already copied the line below; just paste (Ctrl+V).
3. **File:** open ``$pastePath`` (one line, nothing else) and copy all of it.

``````text
$pasteLine
``````

The agent should answer with the two version numbers. If it replies without them, it did not read the
files - paste again rather than continuing.

Machine-readable stamp: ``$contextPath``$(if ($stateIsOutsideProject) { "

**This file is not in the repository.** The pack folder is portable - it travels on a stick, in a
clone, in a download - so nothing describing *this* machine is written into it. Per-machine context
lives under the state directory above and is regenerated by ``$(Get-PackEntryPoint 'Refresh-AgentContext')``." })
"@
Write-Utf8NoBom $refreshPath $md

# A dedicated single-line file: selecting text out of a wrapped console window is where copies pick up
# stray spaces and line breaks. Nothing else goes in this file.
$pastePath = Join-Path $stateDir 'AGENT_PASTE.txt'
Write-Utf8NoBom $pastePath $pasteLine

$sessionStartPath = Join-Path $stateDir 'AGENT_SESSION_START.md'
Invoke-PackPython (Join-Path $PSScriptRoot 'agent_context_freshness.py') --write-session-start --project-root $ProjectRoot 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARN: --write-session-start failed (exit $LASTEXITCODE)"
} elseif (-not (Test-Path -LiteralPath $sessionStartPath)) {
    Write-Host "WARN: expected session start file missing: $sessionStartPath"
}

$clipboardOk = $false
if (-not $NoClipboard) {
    try {
        if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
            Set-Clipboard -Value $pasteLine -ErrorAction Stop
            $clipboardOk = $true
        }
    } catch { $clipboardOk = $false }
}

Write-Host "Wrote $contextPath"
Write-Host "Wrote $refreshPath"
Write-Host "Wrote $pastePath"
if (Test-Path -LiteralPath $sessionStartPath) { Write-Host "Wrote $sessionStartPath" }
if ($stateIsOutsideProject) {
    Write-Host ''
    Write-Host 'These four files live outside the pack folder on purpose: the folder is portable, so' -ForegroundColor DarkGray
    Write-Host 'nothing describing this machine is written into it. Re-run this command to regenerate.' -ForegroundColor DarkGray
}
Write-Host ''
if ($changed.Count -gt 0) {
    Write-Host 'Changed since last refresh:'
    foreach ($line in $changeLines) { Write-Host "  $($line.TrimStart('- '))" }
} else {
    Write-Host 'No changes since the last refresh.'
}
if ($attentionLines.Count -gt 0) {
    Write-Host ''
    Write-Host 'Needs attention:'
    foreach ($line in $attentionLines) { Write-Host "  $($line.TrimStart('- '))" }
}
Write-Host ''
# Lead with the action, not the payload. The line below is long enough to fill the window, so a
# clipboard note printed after it reads as a footnote and gets skipped - and then the user hand-selects
# text that is already on their clipboard.
if ($clipboardOk) {
    Write-Host 'COPIED TO YOUR CLIPBOARD - switch to the open chat and press Ctrl+V. Nothing to select.' -ForegroundColor Green
} elseif ($NoClipboard) {
    # Saying "unavailable" when the caller asked to skip it is simply untrue, and a false status line in
    # a tool people run to resolve confusion is the last place to have one.
    Write-Host 'CLIPBOARD SKIPPED (-NoClipboard) - the same single line is in this file:' -ForegroundColor Yellow
    Write-Host "  $pastePath"
} else {
    Write-Host 'CLIPBOARD UNAVAILABLE - open this file and copy the single line in it:' -ForegroundColor Yellow
    Write-Host "  $pastePath"
}
Write-Host ''
Write-Host '===================== WHAT GETS PASTED (for reference) ====================='
Write-Host ''
Write-Host $pasteLine
Write-Host ''
Write-Host '==========================================================================='
Write-Host ''
Write-Host 'In Cursor you can skip the paste entirely: type  refresh pack context'
Write-Host ''
Write-Host 'The agent should reply with the pack and audit engine versions. No versions = it did not read the files.'
exit 0
