#Requires -Version 5.1

<#

.SYNOPSIS

  One entry point after a pack upgrade: optional profile install, then project refresh.

.DESCRIPTION

  Wraps install.ps1 (optional -Install) and refresh-agent-context.ps1, then prints how to

  reach open agent chats (paste line / trigger phrases). Does not modify open chats itself.

.PARAMETER ProjectRoot

  Project to refresh. Default: the pack checkout when run from maintainer repo.

.PARAMETER Install

  Run install.ps1 -Scope User before refreshing the project.

.PARAMETER SkipProjectSync

  Pass through to refresh-agent-context.ps1.

.PARAMETER PackRoot

  Override pack source path.

.PARAMETER NoClipboard

  Pass through to refresh-agent-context.ps1.

.PARAMETER VerifyOnly

  WORK_COMPLETION Step 5b only: run verify-complete-picture.ps1 (includes product-truth paths)

  without refresh or install.

#>

param(

    [string]$ProjectRoot = '',

    [switch]$Install,

    [switch]$SkipProjectSync,

    [string]$PackRoot = '',

    [switch]$NoClipboard,

    [switch]$VerifyOnly

)



$ErrorActionPreference = 'Stop'



. (Join-Path $PSScriptRoot 'pack-paths.ps1')



if (-not $PackRoot) {

    $PackRoot = Get-CheckoutAgentStarterPack

    if (-not $PackRoot) { $PackRoot = Get-AgentStarterPackRoot }

}

if (-not $PackRoot -or -not (Test-Path -LiteralPath $PackRoot)) {

    Write-Host 'ERROR: cannot resolve Agent Starter Pack. Pass -PackRoot or set AGENT_STARTER_PACK_ROOT.'

    exit 1

}

$PackRoot = (Resolve-Path -LiteralPath $PackRoot).Path



function Invoke-WorkCompletionStep5b {

    param([Parameter(Mandatory = $true)][string]$Root)

    $cpScript = Join-Path $PSScriptRoot 'verify-complete-picture.ps1'

    if (-not (Test-Path -LiteralPath $cpScript)) {

        Write-Host "ERROR: missing $cpScript"

        return 1

    }

    Write-Host ''

    Write-Host 'WORK_COMPLETION Step 5b - verify-complete-picture (handoff + ROADMAP + product-truth)...'

    Write-Host "ProjectRoot: $Root"

    $cpRc = Invoke-PackScript -NoProfile -ScriptPath $cpScript -ArgumentList @(

        '-ProjectRoot', $Root, '-AllowMissing'

    )

    if ($cpRc -ne 0) {

        Write-Host 'ERROR: verify-complete-picture.ps1 failed - fix handoff/WQ/product-truth drift before claiming done.'

    }

    return $cpRc

}



if ($VerifyOnly) {

    $verifyRoot = if ($ProjectRoot) {

        (Resolve-Path -LiteralPath $ProjectRoot).Path

    } else {

        $PackRoot

    }

    exit (Invoke-WorkCompletionStep5b -Root $verifyRoot)

}



$refreshArgs = @{

    PackRoot = $PackRoot

}

if ($ProjectRoot) { $refreshArgs['ProjectRoot'] = $ProjectRoot }

if ($SkipProjectSync) { $refreshArgs['SkipProjectSync'] = $true }

if ($NoClipboard) { $refreshArgs['NoClipboard'] = $true }

if ($Install) { $refreshArgs['Install'] = $true }



$refreshPs1 = Join-Path $PSScriptRoot 'refresh-agent-context.ps1'

if (-not (Test-Path -LiteralPath $refreshPs1)) {

    Write-Host "ERROR: missing $refreshPs1"

    exit 1

}



Write-Host 'Update-AgentStack - install (optional) + project refresh'

Write-Host ''



$rc = Invoke-PackScript -NoProfile -ScriptPath $refreshPs1 @refreshArgs

if ($rc -ne 0) { exit $rc }

# WQ-435: a project bootstrapped before 2.22.63 carries a session hook that drains stdin with an
# unbounded ReadToEnd. install.ps1 rewrites the profile copy every install, so only project copies are
# stranded, and bootstrap only replaces one under -Force. This is the entry point people already run
# after upgrading the pack, so the repair belongs here rather than in a command nobody knows about.
# Never fatal: a hook that cannot be repaired must not block a refresh that otherwise succeeded.
$repairPs1 = Join-Path $PSScriptRoot 'repair-project-hooks.ps1'

if (Test-Path -LiteralPath $repairPs1) {

    $repairRoot = if ($ProjectRoot) { (Resolve-Path -LiteralPath $ProjectRoot).Path } else { $PackRoot }

    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairPs1 -ProjectRoot $repairRoot 2>&1 | Out-Host

}

# WQ-450: the same stranding, one release later. 2.22.76 made every message name the entry point the
# running host can execute and made bootstrap emit both twins - so new projects are right and existing
# ones went from being told to run a .cmd they cannot to being told to run a .sh they do not have.
# Bootstrap only writes a project's files under -Force, which rewrites unrelated generated files too,
# so this is the narrow repair. It sits beside the hook repair for the same reason: this is the command
# people already run after upgrading, and a repair nobody knows about repairs nothing. Never fatal.
$scriptsRepairPs1 = Join-Path $PSScriptRoot 'repair-project-scripts.ps1'

if (Test-Path -LiteralPath $scriptsRepairPs1) {

    $scriptsRepairRoot = if ($ProjectRoot) { (Resolve-Path -LiteralPath $ProjectRoot).Path } else { $PackRoot }

    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $scriptsRepairPs1 -ProjectRoot $scriptsRepairRoot 2>&1 | Out-Host

}



$isMaintainerPack = Test-Path -LiteralPath (Join-Path $PackRoot 'pack/audit/manifest.json')

if ($isMaintainerPack -or $ProjectRoot) {

    $cpRoot = if ($ProjectRoot) {

        (Resolve-Path -LiteralPath $ProjectRoot).Path

    } else {

        $PackRoot

    }

    $cpRc = Invoke-WorkCompletionStep5b -Root $cpRoot

    if ($cpRc -ne 0) { exit $cpRc }

}



if (-not $ProjectRoot) {

    $ProjectRoot = if (Test-Path -LiteralPath (Join-Path $PackRoot 'pack/audit/manifest.json')) {

        $PackRoot

    } else {

        (Get-Location).Path

    }

}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path



# Resolved, not assumed: a pack checkout keeps these outside itself, so a hardcoded docs\ path here

# would print a file that does not exist and send the reader looking in the wrong place.

$stateDir = Get-AgentStateRoot -ProjectRoot $ProjectRoot

$ctxPath = Join-Path $stateDir 'AGENT_CONTEXT.json'

$pastePath = Join-Path $stateDir 'AGENT_PASTE.txt'

Write-Host ''

Write-Host 'Open chats do not hot-reload - pick one:'

Write-Host '  1. Type a trigger phrase (see triggerPhrases in the context stamp below)'

Write-Host '  2. Paste from the paste file below (or clipboard if copied above)'

Write-Host '  3. MCP (Cursor / Claude Desktop): check_pack_freshness, get_agent_refresh_brief'

if (Test-Path -LiteralPath $pastePath) {

    Write-Host "  Paste file: $pastePath"

}

if (Test-Path -LiteralPath $ctxPath) {

    Write-Host "  Contract:   $ctxPath"

}

Write-Host ''

Write-Host 'Full path: docs/AGENT_UPGRADE_PATH.md in the pack or project docs after sync.'

    Write-Host "Step 5b only (no refresh): $(Get-PackEntryPoint 'Update-AgentStack') -VerifyOnly [ProjectRoot]"

exit 0

