#Requires -Version 5.1
param(
    [switch]$FixHints,
    [string]$ProjectRoot = ""
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
                    if (Test-JsonPath $rcfg $key) { Ok "BSOD reference has $key" }
                    else { Fail "AUDIT.config.bsod.reference.json missing key: $key (run sync -PushFromProject)" }
                }
            } catch {
                Fail "Invalid BSOD reference config: $ref - $_"
            }
        } else {
            Warn "BSOD reference config not present: $ref (optional until PushFromProject)"
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
            Fail "AUDIT_SYSTEM.md header must mention starter pack $ver"
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

$userCursor = Join-Path $env:USERPROFILE '.cursor'
Write-Host "User Cursor: $userCursor"
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
} else {
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
} else {
    Warn 'audit-protocol.mdc not installed'
}
$loopBack = Join-Path $userCursor 'rules\loop-back-protocol.mdc'
if (Test-Path $loopBack) {
    $c = Get-Content $loopBack -Raw
    if ($c -notmatch 'all projects|every project') { Fail 'loop-back-protocol.mdc missing all-projects scope' }
    else { Ok 'loop-back-protocol (all projects)' }
} else {
    Fail 'Missing loop-back-protocol.mdc — run sync-audit-system.ps1'
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
    $core = Join-Path (Get-InstalledAgentStarterPack) 'pack\scripts\run_audit_core.ps1'
    if (Test-Path $core) { Ok 'run_audit_core.ps1 installed' } else { Fail 'Missing run_audit_core.ps1 - reinstall starter pack' }
    foreach ($or in @('code-audit-checklist.mdc', 'generic-code-audit-checklist.mdc', 'bsod-analyzer-audit-overlay.mdc')) {
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
    & powershell -NoProfile -ExecutionPolicy Bypass -File $sync @syncArgs
    if ($LASTEXITCODE -ne 0) { $fail++ }
    Write-Host ''
}

$behavior = Join-Path $PSScriptRoot 'verify-audit-behavior.ps1'
if (-not (Test-Path $behavior)) {
    $behavior = Join-Path (Get-PackRoots | Select-Object -First 1) 'pack\scripts\verify-audit-behavior.ps1'
}
if (Test-Path $behavior) {
    Write-Host 'Behavior self-test:'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $behavior
    if ($LASTEXITCODE -ne 0) { $fail++ }
    Write-Host ''
}

Write-Host "Summary: $fail fail(s), $warn warn(s)"
if ($FixHints -and $fail -gt 0) {
    Write-Host "`nFix: sync-audit-system.ps1 then verify again. See pack/docs/AUDIT_SYSTEM.md"
}
if ($fail -gt 0) { exit 1 }
exit 0
