#Requires -Version 5.1
<#
.SYNOPSIS
  Manifest-driven audit sync — Desktop pack, installed pack, user Cursor, reference project.
.PARAMETER VerifyOnly
  Exit 1 on hash drift (no copies).
.PARAMETER PushFromProject
  Reference project (BSOD) -> pack templates, then mirror to installed + user.
.PARAMETER ProjectRoot
  Repo root for layout detection and drift checks.
#>
param(
    [switch]$VerifyOnly,
    [switch]$AutoFix,
    [switch]$PushFromProject,
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

function Get-DesktopPack {
    Get-DesktopAgentStarterPack
}

function Get-InstalledPack {
    Get-InstalledAgentStarterPack
}

function Get-Manifest([string]$PackRoot) {
    $path = Join-Path $PackRoot 'pack\audit\manifest.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing manifest: $path" }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Test-Drift([string]$Label, [string]$A, [string]$B) {
    $ha = Get-Sha256 $A
    $hb = Get-Sha256 $B
    if ($null -eq $ha -or $null -eq $hb) {
        if ($null -eq $ha -and $null -eq $hb) { return $false }
        Write-Host "[DRIFT] $Label - missing file"
        Write-Host "  A: $A"
        Write-Host "  B: $B"
        return $true
    }
    if ($ha -ne $hb) {
        Write-Host "[DRIFT] $Label"
        Write-Host "  A: $A"
        Write-Host "  B: $B"
        return $true
    }
    return $false
}

function Copy-File([string]$Src, [string]$Dst) {
    $dir = Split-Path -Parent $Dst
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $Src -Destination $Dst -Force
}

function Sync-MirrorFile([string]$Src, [string]$Dst) {
    # Reconcile Desktop (Src) and installed (Dst): newer file wins both ways.
    $srcExists = Test-Path -LiteralPath $Src
    $dstExists = Test-Path -LiteralPath $Dst
    if (-not $srcExists -and -not $dstExists) { return }
    if (-not $srcExists) { Copy-File $Dst $Src; return }
    if (-not $dstExists) { Copy-File $Src $Dst; return }
    $ha = Get-Sha256 $Src
    $hb = Get-Sha256 $Dst
    if ($ha -eq $hb) { return }
    $srcTime = (Get-Item -LiteralPath $Src).LastWriteTimeUtc
    $dstTime = (Get-Item -LiteralPath $Dst).LastWriteTimeUtc
    if ($dstTime -gt $srcTime) {
        Copy-File $Dst $Src
    } else {
        Copy-File $Src $Dst
    }
}

$Desktop = Get-DesktopPack
$Installed = Get-InstalledPack
$UserCursor = Join-Path $env:USERPROFILE '.cursor'
$Source = if ($Desktop) { $Desktop } elseif (Test-Path -LiteralPath $Installed) { $Installed } else {
    throw 'No starter pack (Desktop or installed)'
}

$manifest = Get-Manifest $Source
$drift = 0

# Resolve reference project root
if (-not $ProjectRoot -and $PushFromProject) {
    $def = $manifest.referenceProject.defaultRepoRoot -replace '/', '\'
    $ProjectRoot = Join-Path $env:USERPROFILE $def
}
if ($ProjectRoot) { $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path }

# Push reference project -> templates
if ($PushFromProject) {
    if (-not $ProjectRoot) { throw 'PushFromProject requires -ProjectRoot' }
    foreach ($item in @($manifest.referenceProject.pushToTemplates)) {
        $from = Join-Path $ProjectRoot ($item.from -replace '/', '\')
        $to = Join-Path $Source ($item.to -replace '/', '\')
        if ($VerifyOnly) {
            if (Test-Drift "reference push $($item.from)" $from $to) { $drift++ }
        } elseif (Test-Path -LiteralPath $from) {
            Copy-File $from $to
            Write-Host "[PUSH] $from -> $to"
        } else {
            Write-Host "[SKIP] missing $from"
        }
    }
    if ($manifest.referenceProject.referenceOnly) {
        foreach ($item in @($manifest.referenceProject.referenceOnly)) {
            if ($VerifyOnly) { continue }
            $from = Join-Path $ProjectRoot ($item.from -replace '/', '\')
            $to = Join-Path $Source ($item.to -replace '/', '\')
            if (Test-Path -LiteralPath $from) {
                Copy-File $from $to
                Write-Host "[REF] $from -> $to"
            }
        }
    }
}

# Mirror pack -> installed
foreach ($rel in @($manifest.packMirror)) {
    $relWin = $rel -replace '/', '\'
    $src = Join-Path $Source $relWin
    $dst = Join-Path $Installed $relWin
    if (Test-Drift "pack vs installed $rel" $src $dst) { $drift++ }
    if (-not $VerifyOnly) { Sync-MirrorFile $src $dst }
}

# Remove forbidden orphan paths from installed + user mirrors
if (-not $VerifyOnly -and $manifest.forbiddenPackPaths) {
    foreach ($targetRoot in @($Installed)) {
        foreach ($rel in @($manifest.forbiddenPackPaths)) {
            $bad = Join-Path $targetRoot ($rel -replace '/', '\')
            if (Test-Path -LiteralPath $bad) {
                Remove-Item -LiteralPath $bad -Force
                Write-Host "[CLEAN] removed forbidden $bad"
            }
        }
    }
    foreach ($rel in @($manifest.forbiddenPackPaths)) {
        $bad = Join-Path $Source ($rel -replace '/', '\')
        if (Test-Path -LiteralPath $bad) {
            Remove-Item -LiteralPath $bad -Force
            Write-Host "[CLEAN] removed forbidden $bad"
        }
    }
}

# Mirror pack -> user
foreach ($item in @($manifest.packToUser)) {
    $src = Join-Path $Source ($item.from -replace '/', '\')
    $dst = Join-Path $UserCursor ($item.to -replace '/', '\')
    if (Test-Drift "pack vs user $($item.to)" $src $dst) { $drift++ }
    if (-not $VerifyOnly -and (Test-Path -LiteralPath $src)) { Copy-File $src $dst }
}

# Project layout required files exist
if ($ProjectRoot) {
    $layout = if (Test-Path -LiteralPath (Join-Path $ProjectRoot 'app\docs\AUDIT.md')) {
        $manifest.projectRequired.appLayout
    } else {
        $manifest.projectRequired.flatLayout
    }
    $layout.PSObject.Properties | ForEach-Object {
        $full = Join-Path $ProjectRoot ($_.Value -replace '/', '\')
        if (-not (Test-Path -LiteralPath $full)) {
            Write-Host "[DRIFT] missing project file $($_.Value)"
            $drift++
        }
    }
}

Write-Host ''
if ($VerifyOnly) {
    if ($drift -gt 0) {
        if ($AutoFix) {
            Write-Host "Audit sync: $drift drift(s) - applying AutoFix (pack -> installed + user) ..."
            & $PSCommandPath -ProjectRoot $ProjectRoot
            if ($LASTEXITCODE -ne 0) { exit 1 }
            Write-Host 'Audit sync: AutoFix applied; re-verifying ...'
            & $PSCommandPath -VerifyOnly -ProjectRoot $ProjectRoot
            exit $LASTEXITCODE
        }
        Write-Host ('Audit sync: ' + $drift + ' issue(s). Run: sync-audit-system.ps1 (no -VerifyOnly) or -AutoFix')
        exit 1
    }
    Write-Host 'Audit sync: OK'
    exit 0
}

Write-Host 'Audit sync: all copies updated'
if ($PushFromProject) {
    Write-Host 'Reference templates pushed; installed + user mirrors updated.'
}
exit 0
