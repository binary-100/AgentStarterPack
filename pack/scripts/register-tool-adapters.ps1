#Requires -Version 5.1
<#
.SYNOPSIS
  Verify (and optionally repair) per-tool project adapter files for Claude, Copilot, and Windsurf.
.DESCRIPTION
  Does not replace install.ps1 (Cursor profile). Claude MCP registration is optional via -InstallMcp.
.PARAMETER ProjectRoot
  Bootstrapped project root.
.PARAMETER Tool
  Claude, Copilot, Windsurf, or All (default All).
.PARAMETER Repair
  Write missing adapter files from pack templates.
.PARAMETER InstallMcp
  Claude only: register agent-hygiene MCP in Claude Desktop config (machine scope).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [ValidateSet('Claude', 'Copilot', 'Windsurf', 'All')]
    [string[]]$Tool = @('All'),
    [switch]$Repair,
    [switch]$InstallMcp,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$script:fail = 0

function Write-Ok($m) { Write-Host "[OK] $m" }
function Write-Fail($m) { Write-Host "[FAIL] $m"; $script:fail++ }

function Test-ToolSelected {
    param([string]$Name)
    if ($Tool -contains 'All') { return $true }
    return $Tool -contains $Name
}

function Expand-TemplateText {
    param([string]$Text, [hashtable]$Vars)
    foreach ($key in $Vars.Keys) {
        $Text = $Text.Replace("{{$key}}", [string]$Vars[$key])
    }
    return $Text
}

. (Join-Path $PSScriptRoot 'pack-paths.ps1')
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$packRoot = Get-AgentStarterPackRoot
if (-not $packRoot) {
    Write-Fail 'Agent Starter Pack root not found'
    exit 1
}
$templates = Join-Path $packRoot 'pack\templates'

function Get-ProjectTemplateVars {
    $name = Split-Path $ProjectRoot -Leaf
    $sourceModule = 'main.py'
    $versionFile = 'VERSION.txt'
    $bootPath = Join-Path $ProjectRoot '.agent-bootstrap.json'
    if (Test-Path -LiteralPath $bootPath) {
        try {
            $boot = Get-Content -LiteralPath $bootPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($boot.projectName) { $name = [string]$boot.projectName }
        } catch { }
    }
    if (Test-Path -LiteralPath (Join-Path $ProjectRoot 'docs\VERSION_SYNC.json')) {
        try {
            $vs = Get-Content -LiteralPath (Join-Path $ProjectRoot 'docs\VERSION_SYNC.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($vs.sourceModule) { $sourceModule = [string]$vs.sourceModule }
            if ($vs.versionFile) { $versionFile = [string]$vs.versionFile }
        } catch { }
    }
    return @{
        PROJECT_NAME  = $name
        SOURCE_MODULE = $sourceModule
        VERSION_FILE  = $versionFile
    }
}

function Test-AdapterContent {
    param(
        [string]$Path,
        [string[]]$RequiredPatterns,
        [string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Fail "$Label missing: $Path"
        return $false
    }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    foreach ($pat in $RequiredPatterns) {
        if ($text -notmatch [regex]::Escape($pat)) {
            Write-Fail "$Label missing required reference: $pat"
            return $false
        }
    }
    Write-Ok "$Label content valid"
    return $true
}

function Repair-FromTemplate {
    param(
        [string]$TemplateRel,
        [string]$Destination,
        [hashtable]$Vars,
        [string]$Label
    )
    $source = Join-Path $templates $TemplateRel
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Fail "template missing for $Label : $TemplateRel"
        return
    }
    $dir = Split-Path $Destination -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $raw = Get-Content -LiteralPath $source -Raw -Encoding UTF8
    $raw = Expand-TemplateText $raw $Vars
    if (-not $raw.EndsWith("`n")) { $raw = $raw + "`r`n" }
    Write-Utf8NoBom -Path $Destination -Text $raw
    Write-Ok "repaired $Label"
}

$vars = Get-ProjectTemplateVars

$bootstrapTargets = @()
$bootPath = Join-Path $ProjectRoot '.agent-bootstrap.json'
if (Test-Path -LiteralPath $bootPath) {
    try {
        $boot = Get-Content -LiteralPath $bootPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $bootstrapTargets = @($boot.targets)
    } catch { }
}

function Test-TargetInBootstrap {
    param([string]$Name)
    if ($bootstrapTargets.Count -eq 0) { return $true }
    if ($bootstrapTargets -contains 'All') { return $true }
    return $bootstrapTargets -contains $Name
}

if (Test-ToolSelected 'Claude') {
    if (-not (Test-TargetInBootstrap 'Claude')) {
        Write-Ok 'Claude adapter skipped (not in bootstrap targets)'
    } else {
    $claudePath = Join-Path $ProjectRoot 'CLAUDE.md'
    $mcpPath = Join-Path $ProjectRoot 'docs\portable\mcp-claude-desktop.json'
    if (-not (Test-Path -LiteralPath $claudePath)) {
        if ($Repair) { Repair-FromTemplate 'portable\CLAUDE.md.template' $claudePath $vars 'Claude entry' }
        else { Write-Fail "CLAUDE.md missing (bootstrap with -Targets Claude or use -Repair)" }
    }
    if (-not (Test-Path -LiteralPath $mcpPath)) {
        if ($Repair) { Repair-FromTemplate 'portable\mcp-claude-desktop.json.template' $mcpPath $vars 'Claude MCP snippet' }
        else { Write-Fail 'docs/portable/mcp-claude-desktop.json missing' }
    }
    if (Test-Path -LiteralPath $claudePath) {
        Test-AdapterContent $claudePath @('AGENTS.md', 'AGENT_SESSION_START.md', 'user verifies') 'Claude entry' | Out-Null
    }
    if ($InstallMcp) {
        $mcpScript = Join-Path $PSScriptRoot 'register-portable-mcp.ps1'
        if (-not (Test-Path -LiteralPath $mcpScript)) {
            Write-Fail "register-portable-mcp.ps1 missing: $mcpScript"
        } else {
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath $mcpScript -Tool Claude -NoPause
            if ($LASTEXITCODE -ne 0) { Write-Fail "register-portable-mcp.ps1 exited $LASTEXITCODE" }
            else { Write-Ok 'Claude Desktop MCP registered (machine scope)' }
        }
    } else {
        Write-Ok 'Claude MCP install skipped (pass -InstallMcp to register Claude Desktop config)'
    }
    }
}

if (Test-ToolSelected 'Copilot') {
    if (-not (Test-TargetInBootstrap 'Copilot')) {
        Write-Ok 'Copilot adapter skipped (not in bootstrap targets)'
    } else {
    $copilotPath = Join-Path $ProjectRoot '.github\copilot-instructions.md'
    if (-not (Test-Path -LiteralPath $copilotPath)) {
        if ($Repair) { Repair-FromTemplate 'portable\copilot-instructions.md.template' $copilotPath $vars 'Copilot entry' }
        else { Write-Fail '.github/copilot-instructions.md missing (bootstrap with -Targets Copilot or use -Repair)' }
    }
    if (Test-Path -LiteralPath $copilotPath) {
        Test-AdapterContent $copilotPath @('AGENTS.md', 'AI_INSTRUCTIONS.md', 'AGENT_SESSION_START.md', 'user verifies') 'Copilot entry' | Out-Null
    }
    }
}

if (Test-ToolSelected 'Windsurf') {
    if (-not (Test-TargetInBootstrap 'Windsurf')) {
        Write-Ok 'Windsurf adapter skipped (not in bootstrap targets)'
    } else {
    $windsurfPath = Join-Path $ProjectRoot '.windsurfrules'
    if (-not (Test-Path -LiteralPath $windsurfPath)) {
        if ($Repair) { Repair-FromTemplate 'portable\windsurfrules.template' $windsurfPath $vars 'Windsurf entry' }
        else { Write-Fail '.windsurfrules missing (bootstrap with -Targets Windsurf or use -Repair)' }
    }
    if (Test-Path -LiteralPath $windsurfPath) {
        Test-AdapterContent $windsurfPath @('AGENTS.md', 'AI_INSTRUCTIONS.md', 'AGENT_SESSION_START.md', 'user verifies') 'Windsurf entry' | Out-Null
    }
    }
}

if ($script:fail -gt 0) {
    Write-Host "Summary: $($script:fail) fail(s)"
    exit 1
}
Write-Ok 'tool adapter registration'
exit 0
