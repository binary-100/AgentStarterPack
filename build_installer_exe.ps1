# Build Install-AgentStarterPack.exe (optional; .cmd installer works without this)
param(
    [string]$OutDir = (Join-Path $PSScriptRoot "dist")
)

$ErrorActionPreference = "Stop"
$launcher = Join-Path $PSScriptRoot "install_launcher.py"
if (-not (Test-Path $launcher)) {
    Write-Error "install_launcher.py not found"
}

& py -3 -m pip install pyinstaller --quiet
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$icon = ""
$args = @(
    "--onefile",
    "--name", "Install-AgentStarterPack",
    "--distpath", $OutDir,
    "--add-data", "$PSScriptRoot;starter-pack",
    $launcher
)

& py -3 -m PyInstaller @args --noconfirm
Write-Host "Built: $OutDir\Install-AgentStarterPack.exe"
Write-Host "Note: .cmd installer is simpler if PyInstaller is not needed."
