#Requires -Version 5.1
param([switch]$SkipTests, [switch]$FinalizeOnly)

$App = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $App))

$core = Join-Path $env:USERPROFILE '.cursor\AgentStarterPack\pack\scripts\run_audit_core.ps1'
if (-not (Test-Path -LiteralPath $core)) { Write-Error 'run_audit_core.ps1 not found'; exit 1 }
& $core -RepoRoot $RepoRoot -AppRoot $App -SkipTests:$SkipTests -FinalizeOnly:$FinalizeOnly
exit $LASTEXITCODE
