#Requires -Version 5.1
# Zip starter pack for transfer to another machine (includes mcp/ + install scripts)
param(
    [string]$OutDir = $PSScriptRoot
)

$ErrorActionPreference = "Stop"
$versionFile = Join-Path $PSScriptRoot "VERSION"
$version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "0.0.0" }
$stamp = Get-Date -Format "yyyyMMdd"
$zipName = "AgentStarterPack-v${version}-${stamp}.zip"
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
    "HANDOVER_NEXT_AGENT.md",
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

$temp = Join-Path $env:TEMP "cursor-starter-export-$stamp"
if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
New-Item -ItemType Directory -Path $temp | Out-Null

foreach ($item in $items) {
    $src = Join-Path $PSScriptRoot $item
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $temp $item) -Recurse -Force
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

# The agent-context stamp is per-machine: it records absolute paths (this drive letter, this user
# profile) and the versions at the moment it was generated. Shipping it tells the receiving machine's
# agents to read files at paths that do not exist there, and gives refresh-agent-context.ps1 a foreign
# "previous" state to diff against. Regenerated on the target by Refresh-AgentContext.cmd.
# The template under pack\templates stays - that is what bootstrap copies.
foreach ($generated in @('docs\AGENT_CONTEXT.json', 'docs\AGENT_REFRESH.md', 'docs\AGENT_PASTE.txt')) {
    Remove-Item (Join-Path $temp $generated) -Force -ErrorAction SilentlyContinue
}

# The audit refuses to run without these, so a missing one has to fail the export, not the user.
# A missing manifest is the worst case rather than an excuse to skip: guarding the check with
# Test-Path would make the emptiest possible export the one that passes silently.
$manifestPath = Join-Path $temp 'pack\audit\manifest.json'
$missing = @()
if (-not (Test-Path -LiteralPath $manifestPath)) {
    $missing += 'pack\audit\manifest.json'
} else {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $required = $manifest.projectRequired.flatLayout
    if (-not $required) { $missing += 'pack\audit\manifest.json (projectRequired.flatLayout)' }
    else {
        foreach ($prop in $required.PSObject.Properties) {
            $rel = ($prop.Value -replace '/', '\')
            if (-not (Test-Path -LiteralPath (Join-Path $temp $rel))) { $missing += $rel }
        }
    }
}
foreach ($rel in @('run_audit_tests.bat', 'tests\test_pack_audit.py', 'AGENTS.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $temp $rel))) { $missing += $rel }
}
if ($missing.Count -gt 0) {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    throw "Export incomplete - the pack could not audit itself on the target machine. Missing: $($missing -join ', '). Add them to the `$items list in export.ps1."
}

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $temp "*") -DestinationPath $zipPath -Force
Remove-Item $temp -Recurse -Force

Write-Host "Exported: $zipPath"
Write-Host "Version: $version"
Write-Host "On target machine: unzip, run .\Check-Requirements.cmd, then .\install.ps1 -Scope User -RegisterMcp -InstallMcpDeps -NoPause"
