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

$items = @(
    "VERSION",
    "README.md",
    "INSTALL.md",
    "INSTALL.txt",
    "install.ps1",
    "install.sh",
    "export.ps1",
    "Bootstrap-Project.cmd",
    "Install-AgentStarterPack.cmd",
    "install_launcher.py",
    "install-manifest.json",
    "pack",
    "mcp",
    "docs"
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
Get-ChildItem -Path $temp -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Recurse -Force }

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $temp "*") -DestinationPath $zipPath -Force
Remove-Item $temp -Recurse -Force

Write-Host "Exported: $zipPath"
Write-Host "Version: $version"
Write-Host "On target machine: unzip, then .\install.ps1 -Scope User -RegisterMcp -InstallMcpDeps -NoPause"
