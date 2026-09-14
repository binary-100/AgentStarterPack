#Requires -Version 5.1
# Zip starter pack for portable transfer (includes mcp/ + install scripts)
param(
    [string]$OutDir = $PSScriptRoot
)

$ErrorActionPreference = "Stop"
# Get-PackTempDir: this script staged the export under $env:TEMP, which exists only on Windows, so
# exporting from macOS or Linux failed at the first Join-Path - the pack could not produce a transfer
# archive on two of the three platforms it claims to support.
. (Join-Path $PSScriptRoot 'pack/scripts/pack-paths.ps1')
$versionFile = Join-Path $PSScriptRoot "VERSION"
$version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "0.0.0" }
$stamp = Get-Date -Format "yyyyMMdd"
$zipName = "AgentStarterPack-v${version}-${stamp}.zip"
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$zipPath = Join-Path $OutDir $zipName

# The pack audits itself, so a transferred copy needs its own audit entry points - run_audit.cmd,
# scripts\, tests\, .cursor\rules\audit.mdc and AGENTS.md were all missing from this list, which
# meant every "copy the pack to another PC" instruction produced a pack that could not run the
# audit its own docs tell you to run. The manifest check at the end of this script now fails the
# export instead of letting the list drift again.
$items = @(
    "VERSION",
    "README.md",
    "INSTALL.md",
    "INSTALL.txt",
    "CHANGELOG.md",
    "AGENTS.md",
    "install.ps1",
    "install.sh",
    "export.ps1",
    "build_installer_exe.ps1",
    "Bootstrap-Project.cmd",
    "Install-AgentStarterPack.cmd",
    "Check-Requirements.cmd",
    "Sync-DocVersions.cmd",
    "Update-AgentRules.cmd",
    "Refresh-AgentContext.cmd",
    "Verify-AgentSetup.cmd",
    "run_audit.cmd",
    "run_audit_tests.bat",
    "install_launcher.py",
    ".gitignore",
    ".gitattributes",
    ".cursor",
    "pack",
    "mcp",
    "docs",
    "scripts",
    "tests"
)

# $PID, because $stamp is day-granular: two exports on the same day resolved to the same staging
# directory, and the next line deletes it. Concurrent runs therefore destroyed each other - one
# zipping a tree the other had just removed. Found by running the behavior suite in parallel lanes,
# where step 52 failed with "cannot access the file" and "could not find a part of the path" in every
# lane at once (WQ-474), but the collision needs no test harness: two exports at once is enough.
$temp = Join-Path (Get-PackTempDir) "cursor-starter-export-$stamp-$PID"
if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
New-Item -ItemType Directory -Path $temp | Out-Null

# Root entry points are taken from the manifest rather than restated here. packMirror already declares
# every file a working copy of the pack must have, and keeping a second hand-maintained list of the
# same thing drifted exactly the way the machine-local lists did: the export shipped without
# Update-AgentStack.cmd, Bootstrap-Portable-Project.cmd, Register-Tool-Adapters.cmd and the four .sh
# launchers, so a downloaded pack failed its own test suite with "missing at pack root". Found by
# unzipping an export into a scratch folder and running it as a first-time recipient, which is the only
# thing that would have caught it - the export succeeded and this checkout stayed green throughout.
# The literals above remain for what packMirror does not cover: dotfiles, installers, INSTALL.txt.
$itemsManifestPath = Join-Path $PSScriptRoot 'pack/audit/manifest.json'
if (Test-Path -LiteralPath $itemsManifestPath) {
    $itemsManifest = Get-Content -LiteralPath $itemsManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $items += @($itemsManifest.packMirror | Where-Object { $_ -and ($_ -notmatch '[\\/]') })
    $items = @($items | Select-Object -Unique)
}

function Copy-ExportItem {
    # Copy-Item -Recurse skips hidden children, and on Linux every dot-prefixed name is hidden - so
    # exporting from macOS or Linux silently dropped .cursor/rules/audit.mdc and the fixture's
    # .gitignore, producing an archive whose recipient could not run the audit the docs tell them to
    # run. Enumerating with -Force is the whole fix; the recursion is here because Copy-Item's own
    # recursion is what skipped them.
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    if (Test-Path -LiteralPath $Source -PathType Container) {
        if (-not (Test-Path -LiteralPath $Destination)) {
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        }
        foreach ($child in (Get-ChildItem -LiteralPath $Source -Force)) {
            Copy-ExportItem -Source $child.FullName -Destination (Join-Path $Destination $child.Name)
        }
    } else {
        $parent = Split-Path -Parent $Destination
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

foreach ($item in $items) {
    $src = Join-Path $PSScriptRoot $item
    if (Test-Path $src) {
        Copy-ExportItem -Source $src -Destination (Join-Path $temp $item)
    }
}

# Machine-local leftovers: bytecode, scratch, and the previous machine's audit results. A receiving
# machine that inherits a test-pass proof and semantic report would start from a stale clean audit.
Get-ChildItem -Path $temp -Recurse -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @('__pycache__', '.tmp', '.pytest_cache') } |
    ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
Get-ChildItem -Path $temp -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '.audit_*' -or $_.Extension -eq '.pyc' } |
    ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

# Machine-local files record absolute paths (this drive letter, this user profile), this machine's
# install record, and the versions at the moment they were generated. Shipping them tells the receiving
# machine's agents to read files at paths that do not exist there, and gives refresh-agent-context.ps1 a
# foreign "previous" state to diff against. Each is regenerated on the target.
#
# The list is read from the manifest, not written here: this file used to carry its own copy of it, and
# it disagreed with .gitignore for long enough that two generated files were committed. Behavior step 50
# fails when the lists drift. The templates under pack\templates stay - that is what bootstrap copies.
$exportManifestPath = Join-Path $temp 'pack/audit/manifest.json'
if (Test-Path -LiteralPath $exportManifestPath) {
    $exportManifest = Get-Content -LiteralPath $exportManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($generated in @($exportManifest.machineLocalPaths | Where-Object { $_ })) {
        Remove-Item (Join-Path $temp ($generated -replace '/', '\')) -Force -ErrorAction SilentlyContinue
    }
    # install.ps1 has stripped maintainerOnlyPaths since it learned to; this script never did, so the two
    # distribution channels disagreed about the same manifest list. The zip therefore carried
    # .cursor\rules\no-publish-from-this-machine.mdc - a workspace rule telling the *recipient's* agent
    # not to commit or push, which is the one thing the rule's own text says to delete on arrival - plus
    # docs\handoffs, this repo's session notes. Same list, same semantics, read from the manifest:
    # an entry may name a folder, so this removal recurses.
    foreach ($maintainerOnly in @($exportManifest.maintainerOnlyPaths | Where-Object { $_ })) {
        Remove-Item (Join-Path $temp ($maintainerOnly -replace '/', '\')) -Recurse -Force -ErrorAction SilentlyContinue
    }
    # repoOnlyPaths belong in Airlock repo/ only (materialized at sync). Defense in depth for S07.
    foreach ($repoOnly in @($exportManifest.repoOnlyPaths | Where-Object { $_ })) {
        Remove-Item (Join-Path $temp ($repoOnly -replace '/', '\')) -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# The audit refuses to run without these, so a missing one has to fail the export, not the user.
# A missing manifest is the worst case rather than an excuse to skip: guarding the check with
# Test-Path would make the emptiest possible export the one that passes silently.
$manifestPath = Join-Path $temp 'pack/audit/manifest.json'
$missing = @()
if (-not (Test-Path -LiteralPath $manifestPath)) {
    $missing += 'pack\audit\manifest.json'
} else {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $required = $manifest.projectRequired.flatLayout
    if (-not $required) { $missing += 'pack\audit\manifest.json (projectRequired.flatLayout)' }
    else {
        foreach ($prop in $required.PSObject.Properties) {
            # No separator flip: Join-Path takes the manifest's forward slashes on every OS, and
            # translating them to backslashes turned each one into a single literal filename off
            # Windows - so this guard reported every nested file missing from a correct export.
            $rel = [string]$prop.Value
            if (-not (Test-Path -LiteralPath (Join-Path $temp $rel))) { $missing += $rel }
        }
    }
}
foreach ($rel in @('run_audit_tests.bat', 'run_audit_tests.sh', 'tests/test_pack_audit.py', 'AGENTS.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $temp $rel))) { $missing += $rel }
}
# Everything packMirror declares, not a curated subset. The previous guard checked flatLayout plus
# three named files and passed an export that was missing seven launchers - a check narrower than the
# thing it protects is a check that reports success while the product is broken. Machine-local paths
# are removed above by design, so they are not expected here.
if (Test-Path -LiteralPath $manifestPath) {
    $mirrorGuard = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $machineLocalGuard = @($mirrorGuard.machineLocalPaths)
    foreach ($rel in @($mirrorGuard.packMirror | Where-Object { $_ })) {
        if ($machineLocalGuard -contains $rel) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $temp $rel))) { $missing += $rel }
    }
}
if ($missing.Count -gt 0) {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    throw "Export incomplete - the pack could not audit itself on the target machine. Missing: $($missing -join ', '). Add them to the `$items list in export.ps1."
}

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
# Not Compress-Archive: it cannot include hidden files off Windows. A `*` wildcard silently omits
# them, and naming them explicitly fails outright with "Could not find item .gitattributes" - so on
# Linux and macOS the archive either lost .cursor/, .gitignore and .gitattributes or the export died.
# ZipFile archives the staged directory wholesale, dotfiles included, on every platform.
if (-not ('System.IO.Compression.ZipFile' -as [type])) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
}
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $temp, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item $temp -Recurse -Force

Write-Host "Exported: $zipPath"
Write-Host "Version: $version"
Write-Host "On target machine: unzip, run .\Check-Requirements.cmd, then .\install.ps1 -Scope User -RegisterMcp -InstallMcpDeps -NoPause"
