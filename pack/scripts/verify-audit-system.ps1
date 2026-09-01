#Requires -Version 5.1
param(
    [switch]$FixHints,
    [string]$ProjectRoot = "",
    # The behavior suite is the pack engine's own test suite: it bootstraps and audits probe
    # projects inside the pack folder. A downstream project's audit has no business running it
    # (and step 23 would re-enter this script), so those callers pass -SkipBehavior and prove the
    # engine with audit_code_checks.py --self-test instead.
    [switch]$SkipBehavior
)

$ErrorActionPreference = 'Continue'
$fail = 0
$warn = 0

function Fail($msg) { Write-Host "[FAIL] $msg"; $script:fail++ }
function Warn($msg) { Write-Host "[WARN] $msg"; $script:warn++ }
function Ok($msg) { Write-Host "[OK] $msg" }

function Test-JsonPath($obj, [string]$path) {
    $parts = $path -split '\.'
    $cur = $obj
    foreach ($p in $parts) {
        if ($null -eq $cur) { return $false }
        if ($cur -isnot [System.Management.Automation.PSObject] -and $cur -isnot [hashtable]) { return $false }
        if (-not ($cur.PSObject.Properties.Name -contains $p)) { return $false }
        $cur = $cur.$p
    }
    return $null -ne $cur
}

function Test-AuditConfigTemplateKeys([string]$PackRoot, $manifest) {
    if (-not $manifest.auditConfigTemplate) { return }
    $spec = $manifest.auditConfigTemplate
    $req = @($spec.requiredKeys)
    if ($req.Count -lt 1) { return }
    foreach ($rel in @($spec.templatePath)) {
        $p = Join-Path $PackRoot ($rel -replace '/', '\')
        if (-not (Test-Path $p)) {
            Fail "Missing audit config template: $p"
            continue
        }
        try {
            $cfg = Get-Content $p -Raw | ConvertFrom-Json
        } catch {
            Fail "Invalid JSON: $p - $_"
            continue
        }
        foreach ($key in $req) {
            if (Test-JsonPath $cfg $key) { Ok "template has $key" }
            else { Fail "AUDIT.config.json.template missing key: $key" }
        }
    }
    $refRel = $spec.referencePath
    if ($refRel) {
        $ref = Join-Path $PackRoot ($refRel -replace '/', '\')
        if (Test-Path $ref) {
            try {
                $rcfg = Get-Content $ref -Raw | ConvertFrom-Json
                foreach ($key in $req) {
                    if (Test-JsonPath $rcfg $key) { Ok "app reference has $key" }
                    else { Fail "AUDIT.config.app.reference.json missing key: $key (run sync -PushFromProject or update reference)" }
                }
            } catch {
                Fail "Invalid app reference config: $ref - $_"
            }
        } else {
            Warn "App reference config not present: $ref (optional until PushFromProject)"
        }
    }
}

$forbiddenPatterns = @(
    'Phase A sections in order',
    'optional add-ons menu',
    'code-audit-checklist\.mdc',
    'audit-overlay\.mdc',
    'audit with options',
    'run_tests_with_timeout\.bat \(agent'
)

Write-Host "Audit system verification`n"
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

function Get-PackRoots {
    Get-AgentStarterPackCandidates | Where-Object { Test-Path (Join-Path $_ 'pack\audit\manifest.json') }
}

foreach ($root in (Get-PackRoots)) {
    if (-not $root -or -not (Test-Path $root)) { continue }
    Write-Host "Pack: $root"
    $manifestPath = Join-Path $root 'pack\audit\manifest.json'
    if (-not (Test-Path $manifestPath)) {
        Fail "Missing pack/audit/manifest.json under $root"
        continue
    }
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $ver = $manifest.version
    Write-Host "  manifest version: $ver"
    $sysMd = Join-Path $root 'pack\docs\AUDIT_SYSTEM.md'
    if (Test-Path $sysMd) {
        $sysText = Get-Content $sysMd -Raw
        if ($sysText -notmatch "starter pack $([regex]::Escape($ver))") {
            Fail "AUDIT_SYSTEM.md header must mention starter pack $ver (run sync-doc-versions.ps1)"
        } else { Ok 'AUDIT_SYSTEM.md version matches manifest' }
    }
    $chg = Join-Path $root 'pack\docs\AUDIT_SYSTEM_CHANGELOG.md'
    if (Test-Path $chg) {
        $chgText = Get-Content $chg -Raw
        if ($chgText -notmatch "## $([regex]::Escape($ver)) ") {
            Fail "AUDIT_SYSTEM_CHANGELOG.md missing entry for $ver"
        } else { Ok 'AUDIT_SYSTEM_CHANGELOG.md has current version entry' }
    }
    foreach ($rel in @($manifest.packMirror)) {
        $p = Join-Path $root ($rel -replace '/', '\')
        if (Test-Path $p) { Ok (Split-Path $p -Leaf) } else { Fail "Missing: $p" }
    }
    foreach ($ff in @($manifest.forbiddenArtifacts)) {
        $hits = Get-ChildItem -Path (Join-Path $root 'pack') -Recurse -Filter $ff -File -ErrorAction SilentlyContinue
        foreach ($h in $hits) {
            if ($h.FullName -notmatch 'manifest\.json') { Fail "Forbidden in pack: $($h.FullName)" }
        }
    }
    if ($manifest.forbiddenPackPaths) {
        foreach ($rel in @($manifest.forbiddenPackPaths)) {
            $p = Join-Path $root ($rel -replace '/', '\')
            if (Test-Path $p) { Fail "Forbidden pack path exists: $p" }
        }
    }
    Test-AuditConfigTemplateKeys $root $manifest
    Write-Host ''
}

$userCursor = Get-AgentStarterPackUserRoot
Write-Host "User Cursor: $userCursor"

# A profile with no install is not broken - it has not been integrated yet. Report that once,
# and only enforce per-file content checks against a profile the pack was actually installed into.
$profileIntegrated = Test-AgentStarterPackInstalled
if (-not $profileIntegrated) {
    Warn "Pack not installed for this profile - run install.ps1 to integrate it with agents on this machine (pack itself verified above)"
}

if (Test-Path (Join-Path $userCursor 'rules\code-audit-checklist.mdc')) {
    Fail 'Delete: .cursor\rules\code-audit-checklist.mdc'
}
Get-ChildItem (Join-Path $userCursor 'rules') -Filter '*audit-overlay*' -ErrorAction SilentlyContinue | ForEach-Object {
    Fail "Delete overlay: $($_.FullName)"
}
$skill = Join-Path $userCursor 'skills\agent-code-audit\SKILL.md'
if (Test-Path $skill) {
    $c = Get-Content $skill -Raw
    foreach ($pat in $forbiddenPatterns) {
        if ($c -match $pat) { Fail "Old audit text in skill: $pat" }
    }
    if ($c -match 'Fix and Improve|closed scope|AUDIT\.config') { Ok 'agent-code-audit skill' }
} elseif ($profileIntegrated) {
    Warn "Skill not installed: $skill"
}
$defaults = Join-Path $userCursor 'rules\agent-defaults-always.mdc'
if (Test-Path $defaults) {
    $c = Get-Content $defaults -Raw
    foreach ($pat in $forbiddenPatterns) {
        if ($c -match $pat) { Fail "Old audit text in agent-defaults: $pat" }
    }
    if ($c -match 'AUDIT\.md') { Ok 'agent-defaults points to AUDIT.md' }
}
$protocol = Join-Path $userCursor 'rules\audit-protocol.mdc'
if (Test-Path $protocol) {
    $c = Get-Content $protocol -Raw
    if ($c -notmatch 'SkipTests|skip tests') { Fail 'audit-protocol.mdc missing -SkipTests rule' }
    elseif ($c -match 'machine checks only|debug audit script') { Fail 'audit-protocol.mdc has SkipTests loophole' }
    else { Ok 'audit-protocol one-standard text' }
} elseif ($profileIntegrated) {
    Warn 'audit-protocol.mdc not installed'
}
$loopBack = Join-Path $userCursor 'rules\loop-back-protocol.mdc'
if (Test-Path $loopBack) {
    $c = Get-Content $loopBack -Raw
    if ($c -notmatch 'all projects|every project') { Fail 'loop-back-protocol.mdc missing all-projects scope' }
    else { Ok 'loop-back-protocol (all projects)' }
} elseif ($profileIntegrated) {
    Fail 'Missing loop-back-protocol.mdc - run sync-audit-system.ps1'
}
Write-Host ''

if ($ProjectRoot -and (Test-Path $ProjectRoot)) {
    Write-Host "Project: $ProjectRoot"
    $appAudit = Join-Path $ProjectRoot 'app\docs\AUDIT.md'
    $flatAudit = Join-Path $ProjectRoot 'docs\AUDIT.md'
    if (Test-Path $appAudit) { Ok "AUDIT.md: $appAudit" }
    elseif (Test-Path $flatAudit) { Ok "AUDIT.md: $flatAudit" }
    else { Fail 'No docs/AUDIT.md (app or flat layout)' }
    $appCfg = Join-Path $ProjectRoot 'app\docs\AUDIT.config.json'
    $flatCfg = Join-Path $ProjectRoot 'docs\AUDIT.config.json'
    if (Test-Path $appCfg) { Ok 'AUDIT.config.json' } elseif (Test-Path $flatCfg) { Ok 'AUDIT.config.json' }
    else { Fail 'Missing docs/AUDIT.config.json' }
    $coreCandidates = @(Join-Path $ProjectRoot 'pack\scripts\run_audit_core.ps1')
    $resolvedPack = Get-AgentStarterPackRoot
    if ($resolvedPack) { $coreCandidates += (Join-Path $resolvedPack 'pack\scripts\run_audit_core.ps1') }
    $coreCandidates += (Join-Path (Get-InstalledAgentStarterPack) 'pack\scripts\run_audit_core.ps1')
    $core = $coreCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($core) { Ok "run_audit_core.ps1: $core" }
    else { Fail 'Missing run_audit_core.ps1 - run install.ps1, or set AGENT_STARTER_PACK_ROOT to a pack folder' }
    foreach ($or in @('code-audit-checklist.mdc', 'generic-code-audit-checklist.mdc', 'product-audit-overlay.mdc')) {
        foreach ($base in @("$ProjectRoot\.cursor\rules", "$ProjectRoot\app\.cursor\rules")) {
            $p = Join-Path $base $or
            if (Test-Path $p) { Fail "Old project rule: $p" }
        }
    }
    if (Test-Path (Join-Path $ProjectRoot 'app\.cursor\skills\agent-code-audit\SKILL.md')) {
        Warn 'Project copy of agent-code-audit skill (prefer pack skill only)'
    }
    Write-Host ''
}

$sync = Join-Path $PSScriptRoot 'sync-audit-system.ps1'
if (-not (Test-Path $sync)) { $sync = Join-Path (Get-PackRoots | Select-Object -First 1) 'pack\scripts\sync-audit-system.ps1' }
if (Test-Path $sync) {
    Write-Host 'Sync drift check:'
    $syncArgs = @('-VerifyOnly')
    if ($ProjectRoot) { $syncArgs += '-ProjectRoot', $ProjectRoot }
    # -PassOutput matters: without it the child's [DRIFT] lines are swallowed and the run ends at
    # "Summary: 1 fail(s)" with nothing above it saying which file drifted or what to run.
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $sync @syncArgs 2>&1 | Out-Host
    $syncExit = $LASTEXITCODE
    if ($syncExit -ne 0) {
        Fail 'Audit sync drift (see [DRIFT] lines above) - run sync-audit-system.ps1, or install.ps1 -Scope User if the installed copy is behind'
    }
    Write-Host ''
}

$behavior = Join-Path $PSScriptRoot 'verify-audit-behavior.ps1'
if (-not (Test-Path $behavior)) {
    $behavior = Join-Path (Get-PackRoots | Select-Object -First 1) 'pack\scripts\verify-audit-behavior.ps1'
}
if ($SkipBehavior) {
    Write-Host 'Behavior self-test: skipped (-SkipBehavior; pack maintainer check - run verify-audit-behavior.ps1 from the pack folder)'
    Write-Host ''
} elseif (Test-Path $behavior) {
    Write-Host 'Behavior self-test:'
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $behavior 2>&1 | Out-Host
    $behaviorExit = $LASTEXITCODE
    if ($behaviorExit -ne 0) {
        Fail 'Behavior self-test failed (see [FAIL] lines above) - run verify-audit-behavior.ps1 from the pack folder'
    }
    Write-Host ''
}

Write-Host "Summary: $fail fail(s), $warn warn(s)"
if ($FixHints -and $fail -gt 0) {
    Write-Host "`nFix: sync-audit-system.ps1 then verify again. See pack/docs/AUDIT_SYSTEM.md"
}
if ($fail -gt 0) { exit 1 }
exit 0
