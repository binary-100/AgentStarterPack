#Requires -Version 5.1
# Copy generic pack rules into a project .cursor/rules folder (one-way: pack -> project).
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    # Flat layout is what bootstrap generates and what Update-AgentRules.cmd assumes. The old
    # 'app\.cursor\rules' default came from the nested layout and silently created an app\ tree in
    # projects that do not have one. Nested projects pass this explicitly.
    [string]$RulesRelativePath = '.cursor\rules',
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

$packRoot = Get-AgentStarterPackRoot
if (-not $packRoot) {
    $packRoot = Get-InstalledAgentStarterPack
}
if (-not $packRoot -or -not (Test-Path (Join-Path $packRoot 'pack\audit\manifest.json'))) {
    Write-Error 'Agent Starter Pack not found. Run install.ps1 first.'
}
$srcDir = Join-Path $packRoot 'pack\rules'
$destDir = Join-Path $ProjectRoot $RulesRelativePath

if (-not (Test-Path $srcDir)) {
    Write-Error "Pack rules missing: $srcDir"
}

# Enumerated, not listed: a hardcoded set silently skips any rule added to the pack later, which is
# how doctor.ps1 came to validate 5 of 9. pack/rules is generic-only by policy, so everything in it
# belongs in a project that syncs.
$genericRules = @(Get-ChildItem -LiteralPath $srcDir -Filter '*.mdc' -File -ErrorAction SilentlyContinue |
    Sort-Object Name | Select-Object -ExpandProperty Name)
if ($genericRules.Count -eq 0) {
    Write-Error "No .mdc rules found in $srcDir"
}

if (-not (Test-Path $destDir)) {
    if ($VerifyOnly) {
        Write-Host "FAIL: destination missing: $destDir"
        exit 1
    }
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

$fail = 0
$updated = 0

foreach ($name in $genericRules) {
    $src = Join-Path $srcDir $name
    $dst = Join-Path $destDir $name
    if (-not (Test-Path $src)) {
        Write-Host "FAIL: pack rule missing: $src"
        $fail++
        continue
    }
    if ($VerifyOnly) {
        if (-not (Test-Path $dst)) {
            Write-Host "FAIL: project rule missing: $dst"
            $fail++
            continue
        }
        $srcHash = Get-PackFileSha256 -Path $src
        $dstHash = Get-PackFileSha256 -Path $dst
        if ($srcHash -ne $dstHash) {
            Write-Host "FAIL: drift $name (pack != project)"
            $fail++
        } else {
            Write-Host "OK: $name"
        }
    } else {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "Synced: $name -> $dst"
        $updated++
    }
}

if ($VerifyOnly) {
    if ($fail -gt 0) {
        Write-Host "`nFix: sync-project-rules.ps1 -ProjectRoot `"$ProjectRoot`" -RulesRelativePath `"$RulesRelativePath`""
        exit 1
    }
    Write-Host "`nGeneric project rules: OK ($($genericRules.Count) files)"
    exit 0
}

Write-Host "`nSynced $updated generic rule(s) to $destDir"
Write-Host 'See pack/docs/PACK_MAINTENANCE.md - edit pack/rules only, not project copies.'
exit 0
