#Requires -Version 5.1
<#
.SYNOPSIS
  Materialize StarterPack-Airlock overlay and repo-only files from pack/templates/airlock/.
.DESCRIPTION
  Phase 2 (WQ-485): overlay docs + manifest under AirlockRoot/overlay/; repo-only paths
  (e.g. .github/workflows) under RepoRoot/. Templates are the canonical source for Zone B CI.
.PARAMETER PackRoot
  Pack checkout containing pack/templates/airlock/.
.PARAMETER AirlockRoot
  StarterPack-Airlock root (parent of overlay/ and repo/). Optional when -RepoRoot is set.
.PARAMETER RepoRoot
  Airlock repo/ directory. Optional when -AirlockRoot is set.
.PARAMETER PublisherKeyId
  Substitutes {{PUBLISHER_KEY_ID}} in overlay/manifest.json.template.
.PARAMETER WhatIf
  Print actions without writing files.
#>
param(
    [Parameter(Mandatory = $true)][string]$PackRoot,
    [string]$AirlockRoot,
    [string]$RepoRoot,
    [string]$PublisherKeyId = 'publisher-key',
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

function Resolve-MaterializeDir([string]$Path, [string]$Label) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        Write-Host "[FAIL] $Label not found: $Path"
        exit 1
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

$PackRoot = Resolve-MaterializeDir $PackRoot 'PackRoot'
$templateRoot = Get-StarterPackAirlockTemplateRoot -PackRoot $PackRoot
if (-not (Test-Path -LiteralPath $templateRoot)) {
    Write-Host "[FAIL] airlock templates missing: $templateRoot"
    exit 1
}

if (-not $AirlockRoot -and -not $RepoRoot) {
    Write-Host '[FAIL] specify -AirlockRoot and/or -RepoRoot'
    exit 1
}

function Expand-AirlockTemplateText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [hashtable]$Vars = @{}
    )
    foreach ($key in $Vars.Keys) {
        $token = '{{' + $key + '}}'
        $Text = $Text.Replace($token, [string]$Vars[$key])
    }
    return $Text
}

function Get-AirlockTemplateDestName {
    param([Parameter(Mandatory = $true)][string]$FileName)
    if ($FileName.EndsWith('.template', [StringComparison]::OrdinalIgnoreCase)) {
        return $FileName.Substring(0, $FileName.Length - 9)
    }
    return $FileName
}

function Copy-AirlockTemplateTree {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestRoot,
        [hashtable]$Vars = @{},
        [switch]$WhatIf
    )
    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        Write-Host "[FAIL] template tree missing: $SourceRoot"
        exit 1
    }
    foreach ($file in (Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Force)) {
        $rel = $file.FullName.Substring($SourceRoot.Length).TrimStart('\', '/')
        $relParts = $rel -split '[\\/]'
        $destName = Get-AirlockTemplateDestName -FileName $relParts[-1]
        $relParts[-1] = $destName
        $destRel = ($relParts -join [IO.Path]::DirectorySeparatorChar)
        $destPath = Join-Path $DestRoot $destRel
        if ($WhatIf) {
            Write-Host "[WOULD WRITE] $destPath"
            continue
        }
        $destDir = Split-Path -Parent $destPath
        if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        if ($file.Extension -eq '.template') {
            $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            Write-Utf8NoBom -Path $destPath -Text (Expand-AirlockTemplateText -Text $raw -Vars $Vars)
        } else {
            Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force
        }
        Write-Host "[WROTE] $destPath"
    }
}

if ($AirlockRoot) {
    $AirlockRoot = Resolve-MaterializeDir $AirlockRoot 'AirlockRoot'
    $overlaySrc = Join-Path $templateRoot 'overlay'
    $overlayDest = Join-Path $AirlockRoot 'overlay'
    Write-Host "Materialize overlay -> $overlayDest"
    Copy-AirlockTemplateTree -SourceRoot $overlaySrc -DestRoot $overlayDest -Vars @{
        PUBLISHER_KEY_ID = $PublisherKeyId
    } -WhatIf:$WhatIf
}

if ($RepoRoot) {
    $RepoRoot = Resolve-MaterializeDir $RepoRoot 'RepoRoot'
    $repoSrc = Join-Path $templateRoot 'repo'
    Write-Host "Materialize repo-only -> $RepoRoot"
    Copy-AirlockTemplateTree -SourceRoot $repoSrc -DestRoot $RepoRoot -WhatIf:$WhatIf
}

Write-Host '[OK] airlock templates materialized'
exit 0
