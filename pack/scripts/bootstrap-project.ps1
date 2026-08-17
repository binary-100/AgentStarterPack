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

function Write-TemplateFile {
    param(
        [string]$Source,
        [string]$Destination,
        [hashtable]$Vars,
        [switch]$ForceWrite
    )
    if (-not (Test-Path $Source)) {
        Write-Warning "Template missing: $Source"
        return $false
    }
    if ((Test-Path $Destination) -and -not $ForceWrite) {
        Write-Host "[skip] exists: $Destination"
        return $false
    }
    $dir = Split-Path $Destination -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $raw = Get-Content $Source -Raw -Encoding UTF8
    $raw = Expand-TemplateText $raw $Vars
    Set-Content -Path $Destination -Value $raw -Encoding UTF8 -NoNewline
    Add-Content -Path $Destination -Value "" -Encoding UTF8
    Write-Host "[ok] $Destination"
    return $true
}

function Copy-TemplateBinary {
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$ForceWrite
    )
    if (-not (Test-Path $Source)) {
        Write-Warning "Template missing: $Source"
        return $false
    }
    if ((Test-Path $Destination) -and -not $ForceWrite) {
        Write-Host "[skip] exists: $Destination"
        return $false
    }
    $dir = Split-Path $Destination -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Copy-Item -Path $Source -Destination $Destination -Force
    Write-Host "[ok] $Destination"
    return $true
}

function Merge-GitignoreSnippet {
    param([string]$ProjectRootPath, [string]$SnippetPath)
    $gitignore = Join-Path $ProjectRootPath ".gitignore"
    $snippet = Get-Content $SnippetPath -Raw -Encoding UTF8
    if (-not (Test-Path $gitignore)) {
        Set-Content -Path $gitignore -Value $snippet -Encoding UTF8
        Write-Host "[ok] created .gitignore from audit snippet"
        return
    }
    $existing = Get-Content $gitignore -Raw -Encoding UTF8
    if ($existing -match [regex]::Escape("docs/.audit_agent_manifest.json")) {
        Write-Host "[skip] .gitignore already has audit artifacts"
        return
    }
    Add-Content -Path $gitignore -Value "`n$snippet" -Encoding UTF8
    Write-Host "[ok] appended audit snippet to .gitignore"
}

function Test-TargetEnabled {
    param([string]$Name)
    if ($script:EffectiveTargets -contains "All") { return $true }
    return $script:EffectiveTargets -contains $Name
}

$paths = Resolve-PackRoot
$StarterRoot = $paths.StarterRoot
$Templates = $paths.Templates
$ProjectRoot = (Resolve-Path $ProjectRoot).Path
if (-not $ProjectName) {
    $ProjectName = Split-Path $ProjectRoot -Leaf
}

$EffectiveTargets = @($Targets)
. (Join-Path $PSScriptRoot 'pack-paths.ps1')
$canonicalPack = Get-InstalledAgentStarterPack
$mcpServer = Join-Path $canonicalPack "mcp\agent_hygiene_server.py"
if (-not (Test-Path $mcpServer)) {
    $mcpServer = Join-Path $StarterRoot "mcp\agent_hygiene_server.py"
}

$vars = @{
    PROJECT_NAME   = $ProjectName
    SOURCE_MODULE  = $SourceModule
    VERSION_FILE   = $VersionFile
    MCP_SERVER_PATH = ($mcpServer -replace '\\', '/')
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
    $cfgRaw = $cfgRaw.Replace('"main.py"', "`"$SourceModule`"")
    Set-Content -Path $configPath -Value $cfgRaw -Encoding UTF8
    Write-Host "[ok] customized docs/AUDIT.config.json"
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
if (Test-TargetEnabled "Cursor") {
    Copy-TemplateBinary -Source (Join-Path $Templates "audit.mdc.template") `
        -Destination (Join-Path $ProjectRoot ".cursor\rules\audit.mdc") -ForceWrite:$Force
    if ($Stack -eq "Python") {
        Copy-TemplateBinary -Source (Join-Path $Templates "version-sync.mdc.template") `
            -Destination (Join-Path $ProjectRoot ".cursor\rules\version-sync.mdc") -ForceWrite:$Force
    }
}

# --- Python stack (or minimal test runner for Generic) ---
if ($Stack -eq "Python") {
    $pyMaps = @(
        @{ Src = "apply_version.py.template"; Dst = "scripts\apply_version.py"; Vars = $true }
        @{ Src = "test_version_consistency.py.template"; Dst = "tests\test_version_consistency.py"; Vars = $true }
        @{ Src = "run_tests.bat.template"; Dst = "run_tests.bat"; Vars = $false }
        @{ Src = "build-ci.bat.template"; Dst = "build_ci.bat"; Vars = $false }
    )
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
        @"
"""{{PROJECT_NAME}} - stub entry module (customize)."""

VERSION = "0.1.0"


def main() -> None:
    print("{{PROJECT_NAME}} v" + VERSION)


if __name__ == "__main__":
    main()
"@ -replace '\{\{PROJECT_NAME\}\}', $ProjectName | Set-Content -Path $mainPy -Encoding UTF8
        Write-Host "[ok] stub $SourceModule (add VERSION = ...)"
    }
} else {
    Copy-TemplateBinary -Source (Join-Path $Templates "run_tests.bat.template") `
        -Destination (Join-Path $ProjectRoot "run_tests.bat") -ForceWrite:$Force
    if (-not (Test-Path (Join-Path $ProjectRoot "tests"))) {
        New-Item -ItemType Directory -Path (Join-Path $ProjectRoot "tests") -Force | Out-Null
    }
}

# --- Bootstrap manifest ---
$manifest = @{
    bootstrapVersion = "1.7.0"
    projectName      = $ProjectName
    projectRoot      = $ProjectRoot
    stack            = $Stack
    targets          = $EffectiveTargets
    bootstrappedAt   = (Get-Date).ToUniversalTime().ToString("o")
    starterPackRoot  = $StarterRoot
    docs             = @(
        "AGENTS.md",
        "AI_INSTRUCTIONS.md",
        "docs/AUDIT.md",
        "docs/AUDIT.config.json",
        "docs/ROADMAP.md",
        "docs/KNOWN_LIMITATIONS.md"
    )
} | ConvertTo-Json -Depth 6

Set-Content -Path (Join-Path $ProjectRoot ".agent-bootstrap.json") -Value $manifest -Encoding UTF8
Write-Host "[ok] .agent-bootstrap.json"

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Customize docs/AUDIT.md domain map for your modules"
Write-Host "  2. Edit docs/AUDIT.config.json paths if layout differs"
if (Test-TargetEnabled "Cursor") {
    Write-Host "  3. Cursor: install starter pack once - Install-AgentStarterPack.cmd"
}
if (Test-TargetEnabled "Claude") {
    Write-Host "  4. Claude: merge docs/portable/mcp-claude-desktop.json (see PORTABLE_SETUP.md)"
    Write-Host "     Or run: pack\scripts\register-portable-mcp.ps1 -Tool Claude"
}
Write-Host "  5. Run run_audit.cmd after first test wiring"
Write-Host ""
Write-Host "Guide: $StarterRoot\docs\PORTABLE_SETUP.md"

if (-not $NoPause) {
    Read-Host "Press Enter to close"
}
