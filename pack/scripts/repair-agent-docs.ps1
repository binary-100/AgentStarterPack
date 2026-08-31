#Requires -Version 5.1
<#
.SYNOPSIS
  Repair tool-neutral hub docs (AI_INSTRUCTIONS, AGENTS, adapters, project-local portable rules).
.DESCRIPTION
  Called from refresh-agent-context.ps1 / Update-AgentStack so existing projects pick up template
  changes without a full rebootstrap. Rewrites hub files when required patterns are missing or -Force.
  Always refreshes docs/portable/GENERIC_RULES.md (+ skill mirrors) from the pack export.
.PARAMETER VerifyOnly
  Exit 1 when repair would be required (missing patterns, portable copy drift, or adapter gaps).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [string]$PackRoot = '',
    [switch]$Force,
    [switch]$VerifyOnly,
    [switch]$SkipAdapters
)

$ErrorActionPreference = 'Stop'
$script:fail = 0

function Write-Ok($m) { Write-Host "[OK] $m" }
function Write-Fail($m) { Write-Host "[FAIL] $m"; $script:fail++ }

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
        [hashtable]$Vars
    )
    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Fail "template missing: $Source"
        return
    }
    $dir = Split-Path $Destination -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $raw = Get-Content -LiteralPath $Source -Raw -Encoding UTF8
    $raw = Expand-TemplateText $raw $Vars
    if (-not $raw.EndsWith("`n")) { $raw = $raw + "`r`n" }
    Write-Utf8NoBom -Path $Destination -Text $raw
    Write-Ok "wrote $Destination"
}

function Test-HubPatterns {
    param(
        [string]$Path,
        [string[]]$Patterns
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    foreach ($pat in $Patterns) {
        if ($text -notmatch [regex]::Escape($pat)) { return $false }
    }
    return $true
}

function Test-AgentsPreserve {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    foreach ($marker in @('PRODUCT_REFERENCE.md', 'AGENT_READINESS.md', 'bsod_analyzer.py')) {
        if ($text -match [regex]::Escape($marker)) { return $true }
    }
    return $false
}

function Sync-ProjectPortableExports {
    param(
        [string]$PackRootPath,
        [string]$ProjectRootPath
    )
    $srcPortable = Join-Path $PackRootPath 'pack\docs\portable'
    $dstPortable = Join-Path $ProjectRootPath 'docs\portable'
    if (-not (Test-Path -LiteralPath (Join-Path $srcPortable 'GENERIC_RULES.md'))) {
        Write-Fail 'pack export missing: pack/docs/portable/GENERIC_RULES.md (run sync-portable-docs.ps1 on pack)'
        return
    }
    if (-not (Test-Path -LiteralPath $dstPortable)) {
        if ($VerifyOnly) { Write-Fail 'docs/portable/ missing (project-local GENERIC_RULES not copied)'; return }
        New-Item -ItemType Directory -Path $dstPortable -Force | Out-Null
    }
    $srcRules = Join-Path $srcPortable 'GENERIC_RULES.md'
    $dstRules = Join-Path $dstPortable 'GENERIC_RULES.md'
    $srcHash = (Get-FileHash -LiteralPath $srcRules -Algorithm SHA256).Hash
    $needsCopy = $true
    if (Test-Path -LiteralPath $dstRules) {
        $dstHash = (Get-FileHash -LiteralPath $dstRules -Algorithm SHA256).Hash
        $needsCopy = ($srcHash -ne $dstHash)
    }
    if ($VerifyOnly) {
        if ($needsCopy) { Write-Fail 'docs/portable/GENERIC_RULES.md stale vs pack export' }
        else { Write-Ok 'docs/portable/GENERIC_RULES.md matches pack export' }
    } elseif ($needsCopy) {
        Copy-Item -LiteralPath $srcRules -Destination $dstRules -Force
        Write-Ok 'synced docs/portable/GENERIC_RULES.md'
    } else {
        Write-Ok 'docs/portable/GENERIC_RULES.md already current'
    }
    $srcSkills = Join-Path $srcPortable 'skills'
    $dstSkills = Join-Path $dstPortable 'skills'
    if (Test-Path -LiteralPath $srcSkills) {
        if ($VerifyOnly) {
            foreach ($skill in Get-ChildItem -LiteralPath $srcSkills -Filter '*.md' -File) {
                $dstSkill = Join-Path $dstSkills $skill.Name
                if (-not (Test-Path -LiteralPath $dstSkill)) {
                    Write-Fail "missing project skill mirror: docs/portable/skills/$($skill.Name)"
                }
            }
        } else {
            if (-not (Test-Path -LiteralPath $dstSkills)) {
                New-Item -ItemType Directory -Path $dstSkills -Force | Out-Null
            }
            foreach ($skill in Get-ChildItem -LiteralPath $srcSkills -Filter '*.md' -File) {
                Copy-Item -LiteralPath $skill.FullName -Destination (Join-Path $dstSkills $skill.Name) -Force
            }
            Write-Ok 'synced docs/portable/skills/*.md'
        }
    }
}

. (Join-Path $PSScriptRoot 'pack-paths.ps1')
if (-not $PackRoot) {
    $PackRoot = Get-AgentStarterPackRoot
    if (-not $PackRoot) { $PackRoot = Get-SourceAgentStarterPack }
}
if (-not $PackRoot -or -not (Test-Path -LiteralPath $PackRoot)) {
    Write-Fail 'cannot resolve Agent Starter Pack root'
    exit 1
}
$PackRoot = (Resolve-Path -LiteralPath $PackRoot).Path
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$templates = Join-Path $PackRoot 'pack\templates'

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
    $mcpServer = Join-Path $PackRoot 'mcp\agent_hygiene_server.py'
    return @{
        PROJECT_NAME    = $name
        SOURCE_MODULE   = $sourceModule
        VERSION_FILE    = $versionFile
        MCP_SERVER_PATH = ($mcpServer -replace '\\', '/')
    }
}

$vars = Get-ProjectTemplateVars

$hubFiles = @(
    @{
        Rel       = 'AI_INSTRUCTIONS.md'
        Template  = 'portable\AI_INSTRUCTIONS.md.template'
        Patterns  = @('user verifies', 'AGENT_SESSION_START', 'GENERIC_RULES', 'agent-code-audit')
    },
    @{
        Rel       = 'AGENTS.md'
        Template  = 'AGENTS.md.template'
        Patterns  = @('user verifies', 'AGENT_SESSION_START')
    }
)

foreach ($hub in $hubFiles) {
    $dest = Join-Path $ProjectRoot $hub.Rel
    $ok = Test-HubPatterns -Path $dest -Patterns $hub.Patterns
    if ($hub.Rel -eq 'AGENTS.md' -and (Test-AgentsPreserve -Path $dest)) {
        if ($VerifyOnly) {
            if ($ok) { Write-Ok "$($hub.Rel) hub patterns present (project-specific AGENTS preserved)" }
            else { Write-Fail "$($hub.Rel) missing hub patterns but project-specific content preserved - merge manually or use -Force" }
        } else {
            Write-Ok "$($hub.Rel) preserved (project-specific markers detected)"
        }
        continue
    }
    if ($VerifyOnly) {
        if ($ok) { Write-Ok "$($hub.Rel) hub patterns present" }
        else { Write-Fail "$($hub.Rel) missing required hub patterns (run refresh or repair-agent-docs.ps1)" }
    } elseif (-not $ok -or $Force) {
        Write-TemplateFile -Source (Join-Path $templates $hub.Template) -Destination $dest -Vars $vars
    } else {
        Write-Ok "$($hub.Rel) hub patterns already present"
    }
}

Sync-ProjectPortableExports -PackRootPath $PackRoot -ProjectRootPath $ProjectRoot

$skipAdapterRepair = [bool]$SkipAdapters
if (-not $skipAdapterRepair) {
    $bootPath = Join-Path $ProjectRoot '.agent-bootstrap.json'
    if (Test-Path -LiteralPath $bootPath) {
        try {
            $boot = Get-Content -LiteralPath $bootPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $targets = @($boot.targets)
            $hasEditor = $false
            foreach ($name in @('All', 'Claude', 'Copilot', 'Windsurf', 'Cursor')) {
                if ($targets -contains $name) { $hasEditor = $true; break }
            }
            if (-not $hasEditor) { $skipAdapterRepair = $true }
        } catch { }
    }
}

if (-not $skipAdapterRepair) {
    $adapterScript = Join-Path $PSScriptRoot 'register-tool-adapters.ps1'
    if (Test-Path -LiteralPath $adapterScript) {
        if ($VerifyOnly) {
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath $adapterScript `
                -ProjectRoot $ProjectRoot -Tool All -NoPause 2>&1 | Out-Host
            if ($LASTEXITCODE -ne 0) { Write-Fail 'register-tool-adapters verification failed' }
        } else {
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath $adapterScript `
                -ProjectRoot $ProjectRoot -Tool All -Repair -NoPause 2>&1 | Out-Host
            if ($LASTEXITCODE -ne 0) { Write-Fail "register-tool-adapters -Repair exited $LASTEXITCODE" }
        }
    }
} else {
    Write-Ok 'adapters skipped (Portable-only or -SkipAdapters)'
}

if ($script:fail -gt 0) {
    Write-Host "Summary: $($script:fail) fail(s)"
    exit 1
}
Write-Ok 'repair agent docs'
exit 0
