#Requires -Version 5.1
<#
.SYNOPSIS
  Sync a project's pack files and write an agent-readable brief of what changed.
.DESCRIPTION
  No chat reloads its instructions when files on disk change, so updating the pack silently leaves
  every open session acting on the old rules. This writes two artifacts the agent can be pointed at:

    docs/AGENT_CONTEXT.json  machine-readable stamp (versions, per-layer state, changed layers)
    docs/AGENT_REFRESH.md    short brief ending in a line to paste into a stale chat

  Both live under the project's docs/ so any agent can read them - the contract is files, not an API.
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
  Do not put the paste line on the clipboard (it is still written to docs/AGENT_PASTE.txt).
#>
param(
    [string]$ProjectRoot = '',
    [string]$RulesRelativePath = '.cursor\rules',
    [switch]$Install,
    [switch]$SkipProjectSync,
    [string]$PackRoot = '',
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

# Write-Utf8NoBom comes from pack-paths.ps1 - one writer for the whole pack.

$isPackRepo = (Test-Path -LiteralPath (Join-Path $ProjectRoot 'pack\audit\manifest.json')) -and
              (Test-Path -LiteralPath (Join-Path $ProjectRoot 'install.ps1'))

Write-Host "Agent context refresh"
Write-Host "Pack:    $PackRoot"
Write-Host "Project: $ProjectRoot$(if ($isPackRepo) { '  (pack maintainer repo)' })"
Write-Host ''

$docsDir = Join-Path $ProjectRoot 'docs'
if (-not (Test-Path -LiteralPath $docsDir)) {
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
}

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
    $workCompletionLayer = if (-not $hadWc -and (Test-Path -LiteralPath (Join-Path $docsDir 'WORK_COMPLETION.md'))) { 'created' } else { 'ok' }
}

$contextPath = Join-Path $docsDir 'AGENT_CONTEXT.json'
$refreshPath = Join-Path $docsDir 'AGENT_REFRESH.md'
$previous = Get-JsonOrNull $contextPath

$layers = [ordered]@{
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
    $syncRules = Join-Path $PackRoot 'pack\scripts\sync-project-rules.ps1'
    if (Test-Path -LiteralPath $syncRules) {
        Write-Host 'Syncing generic rules into the project ...'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $syncRules -ProjectRoot $ProjectRoot `
            -RulesRelativePath $RulesRelativePath | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: rule sync failed (exit $LASTEXITCODE)"; exit 1 }
        $layers.projectRules = 'updated'
    }
    $syncAudit = Join-Path $PackRoot 'pack\scripts\sync-audit-system.ps1'
    if (Test-Path -LiteralPath $syncAudit) {
        Write-Host 'Syncing audit templates into the project ...'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $syncAudit -ProjectRoot $ProjectRoot | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: audit template sync failed (exit $LASTEXITCODE)"; exit 1 }
        $layers.auditTemplates = 'updated'
    }
    $repairDocs = Join-Path $PackRoot 'pack\scripts\repair-agent-docs.ps1'
    if (Test-Path -LiteralPath $repairDocs) {
        Write-Host 'Repairing tool-neutral hub docs (AI_INSTRUCTIONS, portable rules, adapters) ...'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairDocs -ProjectRoot $ProjectRoot -PackRoot $PackRoot 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: repair-agent-docs failed (exit $LASTEXITCODE)"; exit 1 }
        $layers.agentHubDocs = 'updated'
    }
}

$packVersion = Get-TextOrNull (Join-Path $PackRoot 'VERSION')
$packManifest = Get-JsonOrNull (Join-Path $PackRoot 'pack\audit\manifest.json')
$auditEngineVersion = if ($packManifest) { $packManifest.version } else { $null }
$rulesRevision = Get-RulesRevision (Join-Path $PackRoot 'pack\rules')

$installedRoot = Get-InstalledAgentStarterPack
if (Test-AgentStarterPackInstalled) {
    $installedManifest = Get-JsonOrNull (Join-Path $installedRoot 'pack\audit\manifest.json')
    $installedVersion = if ($installedManifest) { $installedManifest.version } else { $null }
    # A stale install is what agents actually load from, so name the drift rather than the intent.
    $layers.installedPack = if ($installedVersion -eq $auditEngineVersion) { 'ok' } else { 'stale' }
} else {
    $installedVersion = $null
    $layers.installedPack = 'skipped'
    $installedRoot = $null
}
if ($layers.globalRules -eq 'skipped' -and $layers.installedPack -eq 'ok') { $layers.globalRules = 'ok' }

$changed = New-Object System.Collections.ArrayList
if ($previous) {
    if ($previous.packVersion -ne $packVersion) { [void]$changed.Add('packVersion') }
    if ($previous.auditEngineVersion -ne $auditEngineVersion) { [void]$changed.Add('auditEngineVersion') }
    if ($previous.rulesRevision -ne $rulesRevision) { [void]$changed.Add('rules') }
    foreach ($name in @($layers.Keys)) {
        $was = if ($previous.layers) { $previous.layers.$name } else { $null }
        if ($layers[$name] -eq 'updated' -and $was -ne 'updated') { [void]$changed.Add($name) }
        elseif ($layers[$name] -eq 'stale' -and $was -ne 'stale') { [void]$changed.Add($name) }
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
[void]$requiredReads.Add((Join-Path $canonicalProjectRoot 'docs\AGENT_REFRESH.md'))
if (Test-Path -LiteralPath (Join-Path $canonicalProjectRoot 'docs\WORK_QUEUE.md')) {
    [void]$requiredReads.Add((Join-Path $canonicalProjectRoot 'docs\WORK_QUEUE.md'))
}
if ($isPackRepo) {
    [void]$requiredReads.Add((Join-Path $canonicalProjectRoot 'HANDOFF_NEXT_AGENT.md'))
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
    layers                 = $layers
    changedLayers          = @($changed)
    requiredReads          = @($requiredReads)
    triggerPhrases         = $triggerPhrases
    handshake              = $handshake
}
Write-Utf8NoBom $contextPath (($context | ConvertTo-Json -Depth 6))

$plain = @{
    firstRefresh       = 'First refresh for this project - treat all pack guidance as new.'
    packVersion        = "Pack version is now $packVersion."
    auditEngineVersion = "Audit engine is now $auditEngineVersion."
    rules              = 'Generic rule text changed - re-read the rules before acting on remembered ones.'
    globalRules        = 'Global rules and skills in the user profile were reinstalled.'
    installedPack      = "Installed pack differs from this pack ($installedVersion vs $auditEngineVersion) - run install to align."
    projectRules       = 'This project''s copy of the generic rules was updated.'
    auditTemplates     = 'This project''s audit templates were updated.'
}
$changeLines = if ($changed.Count -eq 0) {
    @('- Nothing changed since the last refresh; the stamp below is current.')
} else {
    @($changed | ForEach-Object { '- ' + $(if ($plain[$_]) { $plain[$_] } else { "Layer changed: $_" }) })
}

$readList = New-Object System.Collections.ArrayList
$idx = 1
foreach ($abs in @($requiredReads)) {
    if ($abs -match 'HANDOFF_NEXT_AGENT\.md$') {
        [void]$readList.Add("$idx. ``$abs`` - pack maintainers only")
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
$refreshDocPath = Join-Path $ProjectRoot 'docs\AGENT_REFRESH.md'
$agentsPath = Join-Path $ProjectRoot 'AGENTS.md'
$pasteLine = if ($isPackRepo) {
    "PACK CONTEXT REFRESHED $stampShort (pack $packVersion, audit engine $auditEngineVersion). " +
    "Before your next action: read $refreshDocPath, then re-read $agentsPath and " +
    "$(Join-Path $ProjectRoot 'HANDOFF_NEXT_AGENT.md'). Treat conclusions from earlier in this chat " +
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

## Reminders

- Version and doc cites are a build step (``docs/VERSION_SYNC.json`` / ``apply_version.py sync``), not an audit step.
- Audits report Fix and Improve; they do not delete or restructure anything on their own.
$(if (-not $isPackRepo) { "- ``HANDOFF_NEXT_AGENT.md`` belongs to the Agent Starter Pack repo - do not read it for this project.`n" })
## Paste into an open chat

Three ways to do this, easiest first:

1. **Cursor:** type **refresh pack context** in the chat - no copying at all.
2. **Clipboard:** the refresh command already copied the line below; just paste (Ctrl+V).
3. **File:** open ``docs/AGENT_PASTE.txt`` (one line, nothing else) and copy all of it.

``````text
$pasteLine
``````

The agent should answer with the two version numbers. If it replies without them, it did not read the
files - paste again rather than continuing.

Machine-readable stamp: ``docs/AGENT_CONTEXT.json``
"@
Write-Utf8NoBom $refreshPath $md

# A dedicated single-line file: selecting text out of a wrapped console window is where copies pick up
# stray spaces and line breaks. Nothing else goes in this file.
$pastePath = Join-Path $docsDir 'AGENT_PASTE.txt'
Write-Utf8NoBom $pastePath $pasteLine

$sessionStartPath = Join-Path $docsDir 'AGENT_SESSION_START.md'
& py -3 (Join-Path $PSScriptRoot 'agent_context_freshness.py') --write-session-start --project-root $ProjectRoot 2>&1 | Out-Null
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
Write-Host ''
if ($changed.Count -gt 0) {
    Write-Host 'Changed since last refresh:'
    foreach ($line in $changeLines) { Write-Host "  $($line.TrimStart('- '))" }
} else {
    Write-Host 'No changes since the last refresh.'
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
