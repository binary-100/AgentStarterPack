#Requires -Version 5.1
# Bootstrap a new project with Agent Starter Pack wiring
# Creates audit files, AGENTS.md, tool-specific instruction files, and optional Python CI stubs.
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [string]$ProjectName = "",
    [ValidateSet("Python", "Generic")]
    [string]$Stack = "Generic",
    [ValidateSet("All", "Cursor", "Portable", "Claude", "Copilot", "Windsurf")]
    [string[]]$Targets = @("All"),
    [string]$SourceModule = "main.py",
    [string]$VersionFile = "VERSION.txt",
    [switch]$Force,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

function Resolve-PackRoot {
    $scriptsDir = $PSScriptRoot
    $packDir = Split-Path $scriptsDir -Parent
    $starterRoot = Split-Path $packDir -Parent
    if (-not (Test-Path (Join-Path $packDir "templates"))) {
        . (Join-Path $scriptsDir 'pack-paths.ps1')
        $found = Get-AgentStarterPackRoot
        if ($found) { return @{ StarterRoot = $found; PackDir = Join-Path $found "pack"; Templates = Join-Path $found "pack\templates" } }
        $starterRoot = Join-Path $env:USERPROFILE ".cursor\AgentStarterPack"
        $packDir = Join-Path $starterRoot "pack"
    }
    return @{ StarterRoot = $starterRoot; PackDir = $packDir; Templates = Join-Path $packDir "templates" }
}

function Expand-TemplateText {
    param([string]$Text, [hashtable]$Vars)
    foreach ($key in $Vars.Keys) {
        $Text = $Text.Replace("{{$key}}", [string]$Vars[$key])
    }
    return $Text
}

# Write-Utf8NoBom comes from pack-paths.ps1 - one writer for the whole pack.

function Write-TemplateFile {
    param(
        [string]$Source,
        [string]$Destination,
        [hashtable]$Vars,
        [switch]$ForceWrite
    )
    # Status goes to the host, not the pipeline: no caller consumes a return value, and emitting one
    # printed a bare "True" after every generated file.
    if (-not (Test-Path $Source)) {
        Write-Warning "Template missing: $Source"
        return
    }
    if ((Test-Path $Destination) -and -not $ForceWrite) {
        Write-Host "[skip] exists: $Destination"
        return
    }
    $dir = Split-Path $Destination -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $raw = Get-Content $Source -Raw -Encoding UTF8
    $raw = Expand-TemplateText $raw $Vars
    if (-not $raw.EndsWith("`n")) { $raw = $raw + "`r`n" }
    Write-Utf8NoBom -Path $Destination -Text $raw
    Write-Host "[ok] $Destination"
}

function Copy-TemplateBinary {
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$ForceWrite
    )
    if (-not (Test-Path $Source)) {
        Write-Warning "Template missing: $Source"
        return
    }
    if ((Test-Path $Destination) -and -not $ForceWrite) {
        Write-Host "[skip] exists: $Destination"
        return
    }
    $dir = Split-Path $Destination -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Copy-Item -Path $Source -Destination $Destination -Force
    Write-Host "[ok] $Destination"
}

function Merge-GitignoreSnippet {
    param([string]$ProjectRootPath, [string]$SnippetPath)
    $gitignore = Join-Path $ProjectRootPath ".gitignore"
    $snippet = Get-Content $SnippetPath -Raw -Encoding UTF8
    if (-not (Test-Path $gitignore)) {
        Write-Utf8NoBom -Path $gitignore -Text $snippet
        Write-Host "[ok] created .gitignore from audit snippet"
        return
    }
    $existing = Get-Content $gitignore -Raw -Encoding UTF8
    if ($existing -match [regex]::Escape("docs/.audit_agent_manifest.json")) {
        Write-Host "[skip] .gitignore already has audit artifacts"
        return
    }
    Write-Utf8NoBom -Path $gitignore -Text ($existing.TrimEnd() + "`r`n`r`n" + $snippet)
    Write-Host "[ok] appended audit snippet to .gitignore"
}

function Test-TargetEnabled {
    # "Portable" is a real value of -Targets but never reaches this function: the portable
    # AI_INSTRUCTIONS.md is written for every project, so -Targets Portable means "that file and no
    # editor-specific ones". The generated audit config is adjusted below to match, because it used
    # to require .cursor\rules\audit.mdc unconditionally and any non-Cursor target therefore
    # produced a project that failed its own first audit.
    param([string]$Name)
    if ($script:EffectiveTargets -contains "All") { return $true }
    return $script:EffectiveTargets -contains $Name
}

$paths = Resolve-PackRoot
$StarterRoot = $paths.StarterRoot
$PackDir = $paths.PackDir
$Templates = $paths.Templates
if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    # Bootstrapping a brand new project is the common case; failing with a raw Resolve-Path error
    # because the folder does not exist yet is not helpful.
    New-Item -ItemType Directory -Path $ProjectRoot -Force | Out-Null
    Write-Host "[ok] created project folder: $ProjectRoot"
}
$ProjectRoot = (Resolve-Path $ProjectRoot).Path
if (-not $ProjectName) {
    $ProjectName = Split-Path $ProjectRoot -Leaf
}

$EffectiveTargets = @($Targets)
. (Join-Path $PSScriptRoot 'pack-paths.ps1')
$canonicalPack = Get-InstalledAgentStarterPack
$mcpServer = Join-Path $canonicalPack "mcp\agent_hygiene_server.py"
if (-not (Test-Path $mcpServer)) {
    # Falling back to this pack folder bakes its current path into the project's MCP config.
    # That breaks when the pack lives on removable media (drive letter changes, disk unplugged).
    $mcpServer = Join-Path $StarterRoot "mcp\agent_hygiene_server.py"
    Write-Host "[WARN] Pack not installed on this machine - MCP path will point at $StarterRoot"
    Write-Host "[WARN] Run install.ps1 first if that path is a removable drive or may move."
}

$vars = @{
    PROJECT_NAME   = $ProjectName
    SOURCE_MODULE  = $SourceModule
    VERSION_FILE   = $VersionFile
    MCP_SERVER_PATH = ($mcpServer -replace '\\', '/')
}

# Warn, do not block: the files this writes are still correct on a machine that has not installed
# Python yet, but the generated run_audit.cmd will not run until it does.
$preflight = Join-Path $PSScriptRoot 'check-requirements.ps1'
if (Test-Path $preflight) {
    $preflightOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $preflight -Quiet 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $preflightOut
        Write-Host '[WARN] Requirements above are missing - the generated audit scripts will fail until they are installed.'
        Write-Host ''
    }
}

Write-Host "Agent Starter Pack - bootstrap project"
Write-Host "  Project: $ProjectRoot"
Write-Host "  Name:    $ProjectName"
Write-Host "  Stack:   $Stack"
Write-Host "  Targets: $($EffectiveTargets -join ', ')"
Write-Host ""

# --- Core (always) ---
$coreMaps = @(
    @{ Src = "docs\AUDIT.md.template"; Dst = "docs\AUDIT.md" }
    @{ Src = "docs\AUDIT.config.json.template"; Dst = "docs\AUDIT.config.json" }
    @{ Src = "run_audit.cmd.template"; Dst = "run_audit.cmd" }
    @{ Src = "run_audit.ps1.template"; Dst = "scripts\run_audit.ps1" }
    @{ Src = "scripts\sync_audit_system.cmd.template"; Dst = "scripts\sync_audit_system.cmd" }
    @{ Src = "scripts\verify_semantic_audit.cmd.template"; Dst = "scripts\verify_semantic_audit.cmd" }
    @{ Src = "scripts\write_semantic_audit_template.cmd.template"; Dst = "scripts\write_semantic_audit_template.cmd" }
    @{ Src = "scripts\finalize_audit.cmd.template"; Dst = "scripts\finalize_audit.cmd" }
    @{ Src = "AGENTS.md.template"; Dst = "AGENTS.md" }
    @{ Src = "portable\AI_INSTRUCTIONS.md.template"; Dst = "AI_INSTRUCTIONS.md" }
    @{ Src = "docs\ROADMAP.md.template"; Dst = "docs\ROADMAP.md" }
    @{ Src = "docs\WORK_QUEUE.md.template"; Dst = "docs\WORK_QUEUE.md" }
    @{ Src = "docs\KNOWN_LIMITATIONS.md.template"; Dst = "docs\KNOWN_LIMITATIONS.md" }
)

foreach ($map in $coreMaps) {
    $src = Join-Path $Templates $map.Src
    $dst = Join-Path $ProjectRoot $map.Dst
    Write-TemplateFile -Source $src -Destination $dst -Vars $vars -ForceWrite:$Force
}

# Patch AUDIT.config.json projectName if still placeholder
$configPath = Join-Path $ProjectRoot "docs\AUDIT.config.json"
if (Test-Path $configPath) {
    $cfgRaw = Get-Content $configPath -Raw -Encoding UTF8
    $cfgRaw = $cfgRaw.Replace('"YOUR_PROJECT_NAME"', "`"$ProjectName`"")
    if ($Stack -ne "Python") {
        # A Generic project has no canonical Python module, so the version pipeline does not apply.
        # Leaving it configured made every Generic audit report "Version - main.py - missing version"
        # for a file this stack never creates.
        $cfgRaw = [regex]::Replace($cfgRaw, '"versionSync"\s*:\s*\{[^}]*\},', '"versionSync": null,')
        $cfgRaw = [regex]::Replace($cfgRaw, '"versionSyncConfigFile"\s*:\s*"[^"]*",', '"versionSyncConfigFile": null,')
    }
    $cfgRaw = $cfgRaw.Replace('"main.py"', "`"$SourceModule`"")
    if ($Stack -eq "Python") {
        # Section D covers the stub module, so point it at the test file this stack generates.
        # An empty map makes the project's first audit report "Section D - no sectionTests".
        $cfgRaw = $cfgRaw.Replace('"sectionTests": {}', '"sectionTests": { "D": ["tests/test_version_consistency.py"] }')
    }
    Write-Utf8NoBom -Path $configPath -Text $cfgRaw
    Write-Host "[ok] customized docs/AUDIT.config.json"
}

if ($Stack -ne "Python") {
    # The template's example domain-map row names main.py, which the Generic stack does not create,
    # so the audit reported a mapped module missing on disk. Leave the table empty for the user.
    $auditMdPath = Join-Path $ProjectRoot "docs\AUDIT.md"
    if (Test-Path $auditMdPath) {
        $mdRaw = Get-Content $auditMdPath -Raw -Encoding UTF8
        $mdPatched = $mdRaw -replace '(?m)^\|\s*`main\.py`\s*\|\s*D\s*\|\r?\n', ''
        if ($mdPatched -ne $mdRaw) {
            Write-Utf8NoBom -Path $auditMdPath -Text $mdPatched
            Write-Host "[ok] docs/AUDIT.md domain map left empty (add your modules)"
        }
    }
}

# AUDIT.config.json lists README.md as a required path, so generate a stub rather than have every
# new project open with a Fix item for a file the generator knows it needs.
$readme = Join-Path $ProjectRoot "README.md"
if (-not (Test-Path $readme)) {
    Write-Utf8NoBom -Path $readme -Text @"
# $ProjectName

## Quick start

``````bat
run_tests.bat
run_audit.cmd
``````

## Audit

1. ``run_audit.cmd`` - machine checks + tests
2. Edit ``docs/.audit_semantic_report.json``, then ``scripts\verify_semantic_audit.cmd``
3. ``scripts\finalize_audit.cmd``

See ``docs/AUDIT.md`` for the checklist and ``AGENTS.md`` for agent instructions.
"@
    Write-Host "[ok] README.md stub"
}

# Stub stamp so a project has the file before its first refresh; the refresh CLI fills it in and
# writes docs/AGENT_REFRESH.md beside it. The engine version is stamped now, not left null: the audit
# reports a stale stamp, and a null would have made every brand-new project open with that Improve
# while a genuinely years-old project stayed just as quiet.
$contextPath = Join-Path $ProjectRoot "docs\AGENT_CONTEXT.json"
if ($Force -or -not (Test-Path $contextPath)) {
    $engineVersion = 'unknown'
    $bootManifest = Join-Path $StarterRoot 'pack\audit\manifest.json'
    if (Test-Path -LiteralPath $bootManifest) {
        try { $engineVersion = (Get-Content -LiteralPath $bootManifest -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch { }
    }
    $contextVars = $vars.Clone()
    $contextVars['AUDIT_ENGINE_VERSION'] = $engineVersion
    Write-TemplateFile -Source (Join-Path $Templates "docs\AGENT_CONTEXT.json.template") `
        -Destination $contextPath -Vars $contextVars -ForceWrite:$Force
}

Merge-GitignoreSnippet -ProjectRootPath $ProjectRoot -SnippetPath (Join-Path $Templates "docs\gitignore.audit.snippet")

# --- Portable instruction files (per tool) ---
if (Test-TargetEnabled "Claude") {
    Write-TemplateFile -Source (Join-Path $Templates "portable\CLAUDE.md.template") `
        -Destination (Join-Path $ProjectRoot "CLAUDE.md") -Vars $vars -ForceWrite:$Force
    $mcpDstDir = Join-Path $ProjectRoot "docs\portable"
    Write-TemplateFile -Source (Join-Path $Templates "portable\mcp-claude-desktop.json.template") `
        -Destination (Join-Path $mcpDstDir "mcp-claude-desktop.json") -Vars $vars -ForceWrite:$Force
}

if (Test-TargetEnabled "Copilot") {
    Write-TemplateFile -Source (Join-Path $Templates "portable\copilot-instructions.md.template") `
        -Destination (Join-Path $ProjectRoot ".github\copilot-instructions.md") -Vars $vars -ForceWrite:$Force
}

if (Test-TargetEnabled "Windsurf") {
    Write-TemplateFile -Source (Join-Path $Templates "portable\windsurfrules.template") `
        -Destination (Join-Path $ProjectRoot ".windsurfrules") -Vars $vars -ForceWrite:$Force
}

# --- Cursor ---
# The audit rule is written for every target, not just Cursor. The audit system requires
# .cursor\rules\audit.mdc of every project (manifest projectRequired, and the sync check), so
# writing it only for Cursor meant -Targets Portable, Claude, or Copilot produced a project whose
# very first run_audit.cmd reported a missing file and a sync drift. Non-Cursor agents read
# AGENTS.md and AI_INSTRUCTIONS.md; this file costs them nothing and keeps one audit standard.
Copy-TemplateBinary -Source (Join-Path $Templates "audit.mdc.template") `
    -Destination (Join-Path $ProjectRoot ".cursor\rules\audit.mdc") -ForceWrite:$Force

if (Test-TargetEnabled "Cursor") {
    if ($Stack -eq "Python") {
        # Write-TemplateFile, not a raw copy: this template carries {{PROJECT_NAME}} and
        # {{SOURCE_MODULE}}, including in the frontmatter globs line, so copying it verbatim shipped
        # a rule whose glob was the literal text "{{SOURCE_MODULE}}" and never matched anything.
        Write-TemplateFile -Source (Join-Path $Templates "version-sync.mdc.template") `
            -Destination (Join-Path $ProjectRoot ".cursor\rules\version-sync.mdc") -Vars $vars -ForceWrite:$Force
    }
    $cursorHooksDir = Join-Path $ProjectRoot ".cursor\hooks"
    if (-not (Test-Path -LiteralPath $cursorHooksDir)) {
        New-Item -ItemType Directory -Path $cursorHooksDir -Force | Out-Null
    }
    Copy-TemplateBinary -Source (Join-Path $Templates "cursor\hooks\session-freshness.ps1") `
        -Destination (Join-Path $cursorHooksDir "session-freshness.ps1") -ForceWrite:$Force
    Copy-TemplateBinary -Source (Join-Path $Templates "cursor\hooks.json.template") `
        -Destination (Join-Path $ProjectRoot ".cursor\hooks.json") -ForceWrite:$Force
}

# --- Python stack (or minimal test runner for Generic) ---
if ($Stack -eq "Python") {
    Write-TemplateFile -Source (Join-Path $Templates "docs\VERSION_SYNC.json.template") `
        -Destination (Join-Path $ProjectRoot "docs\VERSION_SYNC.json") -Vars $vars -ForceWrite:$Force
    $pyMaps = @(
        @{ Src = "apply_version.py.template"; Dst = "scripts\apply_version.py"; Vars = $true }
        @{ Src = "test_version_consistency.py.template"; Dst = "tests\test_version_consistency.py"; Vars = $true }
        @{ Src = "run_tests.bat.template"; Dst = "run_tests.bat"; Vars = $false }
        @{ Src = "build-ci.bat.template"; Dst = "build_ci.bat"; Vars = $false }
        @{ Src = "scripts/sync_doc_versions.cmd.template"; Dst = "scripts\sync_doc_versions.cmd"; Vars = $false }
        @{ Src = "scripts/sync_doc_versions.py.template"; Dst = "scripts\sync_doc_versions.py"; Vars = $false }
    )
    $packScripts = Join-Path $StarterRoot "pack\scripts"
    Copy-TemplateBinary -Source (Join-Path $packScripts "doc_version_sync.py") `
        -Destination (Join-Path $ProjectRoot "scripts\doc_version_sync.py") -ForceWrite:$Force
    foreach ($map in $pyMaps) {
        $src = Join-Path $Templates $map.Src
        $dst = Join-Path $ProjectRoot $map.Dst
        if ($map.Vars) {
            Write-TemplateFile -Source $src -Destination $dst -Vars $vars -ForceWrite:$Force
        } else {
            Copy-TemplateBinary -Source $src -Destination $dst -ForceWrite:$Force
        }
    }
    if (-not (Test-Path (Join-Path $ProjectRoot "tests"))) {
        New-Item -ItemType Directory -Path (Join-Path $ProjectRoot "tests") -Force | Out-Null
    }
    $mainPy = Join-Path $ProjectRoot $SourceModule
    if (-not (Test-Path $mainPy)) {
        $stubText = @"
"""{{PROJECT_NAME}} - stub entry module (customize)."""

VERSION = "0.1.0"


def main() -> None:
    print("{{PROJECT_NAME}} v" + VERSION)


if __name__ == "__main__":
    main()
"@ -replace '\{\{PROJECT_NAME\}\}', $ProjectName
        Write-Utf8NoBom -Path $mainPy -Text $stubText
        Write-Host "[ok] stub $SourceModule (add VERSION = ...)"
    }
    # The audit compares the module version against VERSION.txt before it runs the test script that
    # would generate VERSION.txt, so write the derived file now. Otherwise every new project's first
    # audit opens with "Version - VERSION.txt - missing" that fixes itself on the second run.
    $verTxt = Join-Path $ProjectRoot $VersionFile
    if (-not (Test-Path $verTxt)) {
        $stubVer = "0.1.0"
        if (Test-Path $mainPy) {
            $vm = Select-String -Path $mainPy -Pattern '^VERSION = "([^"]+)"' | Select-Object -First 1
            if ($vm -and $vm.Matches.Groups.Count -gt 1) { $stubVer = $vm.Matches.Groups[1].Value }
        }
        $today = (Get-Date).ToString("yyyy-MM-dd")
        Write-Utf8NoBom -Path $verTxt -Text @"
$ProjectName v$stubVer

====================

Release date: $today

Version: $stubVer

v$stubVer highlights:

- $ProjectName v$stubVer
"@
        Write-Host "[ok] $VersionFile"
    }
} else {
    Copy-TemplateBinary -Source (Join-Path $Templates "run_tests.generic.bat.template") `
        -Destination (Join-Path $ProjectRoot "run_tests.bat") -ForceWrite:$Force
    if (-not (Test-Path (Join-Path $ProjectRoot "tests"))) {
        New-Item -ItemType Directory -Path (Join-Path $ProjectRoot "tests") -Force | Out-Null
    }
}

# --- Bootstrap manifest ---
# Lists what bootstrap actually wrote. docs/AGENT_REFRESH.md is deliberately absent: it is generated
# by Refresh-AgentContext.cmd and only meaningful once there is a real delta to report, so a stub
# would be a brief that states nothing while looking authoritative.
$bootDocs = @(
    "AGENTS.md",
    "AI_INSTRUCTIONS.md",
    "docs/AUDIT.md",
    "docs/AUDIT.config.json",
    "docs/AGENT_CONTEXT.json",
    "docs/ROADMAP.md",
    "docs/WORK_QUEUE.md",
    "docs/KNOWN_LIMITATIONS.md"
)
if ($Stack -eq "Python") {
    $bootDocs = @(
        "AGENTS.md",
        "AI_INSTRUCTIONS.md",
        "docs/AUDIT.md",
        "docs/AUDIT.config.json",
        "docs/AGENT_CONTEXT.json",
        "docs/VERSION_SYNC.json",
        "docs/ROADMAP.md",
        "docs/WORK_QUEUE.md",
        "docs/KNOWN_LIMITATIONS.md"
    )
}
$manifest = @{
    bootstrapVersion = "1.7.0"
    projectName      = $ProjectName
    projectRoot      = $ProjectRoot
    stack            = $Stack
    targets          = $EffectiveTargets
    bootstrappedAt   = (Get-Date).ToUniversalTime().ToString("o")
    starterPackRoot  = $StarterRoot
    docs             = $bootDocs
} | ConvertTo-Json -Depth 6

Write-Utf8NoBom -Path (Join-Path $ProjectRoot ".agent-bootstrap.json") -Text $manifest
Write-Host "[ok] .agent-bootstrap.json"

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Customize docs/AUDIT.md domain map for your modules"
Write-Host "  2. Edit docs/AUDIT.config.json paths if layout differs"
if (Test-TargetEnabled "Cursor") {
    Write-Host "  3. Cursor: install starter pack once - Install-AgentStarterPack.cmd"
    Write-Host "     Optional: install.ps1 -InstallSessionHooks for user-level sessionStart freshness"
    Write-Host "     Project hook: .cursor/hooks.json (installed by bootstrap -Targets Cursor/All)"
}
if (Test-TargetEnabled "Claude") {
    Write-Host "  4. Claude: Register-Tool-Adapters.cmd $ProjectRoot Claude"
    Write-Host "     Or: register-portable-mcp.ps1 -Tool Claude (MCP only)"
}
if (Test-TargetEnabled "Copilot") {
    Write-Host "  Copilot: Register-Tool-Adapters.cmd $ProjectRoot Copilot"
}
if (Test-TargetEnabled "Windsurf") {
    Write-Host "  Windsurf: Register-Tool-Adapters.cmd $ProjectRoot Windsurf"
}
if ($EffectiveTargets -contains 'Portable' -or $EffectiveTargets -contains 'All') {
    Write-Host "  Non-Cursor: read docs/portable/GENERIC_RULES.md + AI_INSTRUCTIONS.md at session start"
    Write-Host "              (project copy synced on bootstrap/refresh; pack install path is fallback)"
}
Write-Host "  5. Run run_audit.cmd after first test wiring"
Write-Host ""
Write-Host "Guide: $StarterRoot\docs\PORTABLE_SETUP.md"

$ensureWc = Join-Path $PSScriptRoot 'ensure-work-completion.ps1'
$repairDocs = Join-Path $PSScriptRoot 'repair-agent-docs.ps1'
if (Test-Path -LiteralPath $repairDocs) {
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairDocs -ProjectRoot $ProjectRoot -PackRoot $StarterRoot 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
if (Test-Path -LiteralPath $ensureWc) {
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $ensureWc -ProjectRoot $ProjectRoot -PackRoot $StarterRoot -ProjectName $ProjectName 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not $NoPause) {
    Read-Host "Press Enter to close"
}
