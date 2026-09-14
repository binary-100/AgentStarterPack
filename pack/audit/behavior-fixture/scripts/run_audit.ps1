#Requires -Version 5.1
param([switch]$SkipTests, [switch]$FinalizeOnly)

$App = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $App))

function Resolve-AuditCore {
    # Portable: explicit override first, then the pack installed for this user profile.
    $candidates = @()
    if ($env:AGENT_STARTER_PACK_ROOT) { $candidates += $env:AGENT_STARTER_PACK_ROOT }
    if ($env:CURSOR_STARTER_PACK_ROOT) { $candidates += $env:CURSOR_STARTER_PACK_ROOT }
    $candidates += Join-Path $env:USERPROFILE '.cursor/AgentStarterPack'
    $candidates += Join-Path $env:USERPROFILE '.cursor/agent-starter-pack'
    foreach ($base in $candidates) {
        if (-not $base) { continue }
        $core = Join-Path $base 'pack/scripts/run_audit_core.ps1'
        if (Test-Path -LiteralPath $core) { return $core }
    }
    return $null
}

$core = Resolve-AuditCore
if (-not $core) {
    Write-Error 'run_audit_core.ps1 not found. Run install.ps1 from the pack, or set AGENT_STARTER_PACK_ROOT to the pack folder.'
    exit 1
}
& $core -RepoRoot $RepoRoot -AppRoot $App -SkipTests:$SkipTests -FinalizeOnly:$FinalizeOnly
exit $LASTEXITCODE
