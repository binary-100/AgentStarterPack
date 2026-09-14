param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$FinalizeOnly,
    [switch]$SkipTests
)

function Resolve-AuditCore([string]$Root) {
    $local = Join-Path $Root 'pack/scripts/run_audit_core.ps1'
    if (Test-Path -LiteralPath $local) { return $local }
    . (Join-Path $Root 'pack/scripts/pack-paths.ps1')
    foreach ($base in (Get-AgentStarterPackCandidates)) {
        $core = Join-Path $base 'pack/scripts/run_audit_core.ps1'
        if (Test-Path -LiteralPath $core) { return $core }
    }
    Write-Error "run_audit_core.ps1 not found. Install Agent Starter Pack ($(Get-PackEntryPoint 'install'))."
}

$core = Resolve-AuditCore $RepoRoot
if ($FinalizeOnly) {
    & $core -RepoRoot $RepoRoot -AppRoot $RepoRoot -FinalizeOnly
} elseif ($SkipTests) {
    & $core -RepoRoot $RepoRoot -AppRoot $RepoRoot -SkipTests
} else {
    & $core -RepoRoot $RepoRoot -AppRoot $RepoRoot
}
exit $LASTEXITCODE
