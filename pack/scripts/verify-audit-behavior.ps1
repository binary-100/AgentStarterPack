#Requires -Version 5.1
<#
.SYNOPSIS
  Behavioral self-test for the audit system (no product test suite required).
.PARAMETER PackRoot
  Override the pack to test. Default resolves from this script's location.
.PARAMETER DualShell
  After passing, run the whole suite again on the other PowerShell host (5.1 <-> 7) and require that to
  pass too. Opt-in: it doubles the runtime. Step 29 always checks the encoding difference that matters.
#>
param(
    [string]$PackRoot = '',
    [switch]$DualShell
)

$ErrorActionPreference = 'Stop'
$fail = 0

function Fail($msg) { Write-Host "[FAIL] $msg"; $script:fail++ }
function Ok($msg) { Write-Host "[OK] $msg" }

# Set-Content -Encoding UTF8 writes a BOM on Windows PowerShell 5.1. This suite restores tracked
# fixture files after mutating them, so every run was re-adding a BOM to committed code - which is
# how catalog_cache.py ended up in the repo with one, under the very check meant to prevent it.
# Write-Utf8NoBom comes from pack-paths.ps1 - one writer for the whole pack.

function Get-JsonFromOutput([string]$Text) {
    if (-not $Text) { return $null }
    $start = $Text.IndexOf('{')
    $end = $Text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { return $null }
    return $Text.Substring($start, $end - $start + 1)
}

. (Join-Path $PSScriptRoot 'pack-paths.ps1')
if (-not $PackRoot) {
    $PackRoot = Get-AgentStarterPackRoot
}
if (-not $PackRoot -or -not (Test-Path $PackRoot)) {
    Fail 'Pack root not found'
    Write-Host "Summary: $fail fail(s)"
    exit 1
}

Write-Host "Audit behavior verification`nPack: $PackRoot`n"

# --fill-semantic-fixture-test marks every checklist section reviewed with no findings. This suite
# is the only thing allowed to use it; step 25 asserts it refuses without this opt-in.
$env:AUDIT_FIXTURE_TEST = '1'

$codePy = Join-Path $PackRoot 'pack\scripts\audit_code_checks.py'
$corePs1 = Join-Path $PackRoot 'pack\scripts\run_audit_core.ps1'
$fixture = Join-Path $PackRoot 'pack\audit\behavior-fixture'

# 1. Python self-test (domain map parser)
Write-Host '1. audit_code_checks.py --self-test'
& py -3 $codePy --self-test 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Fail 'audit_code_checks --self-test failed' } else { Ok 'self-test' }

# 2. JSON parse + manifest union on fixture
Write-Host '2. Fixture JSON + manifest sections F and K'
$out = & py -3 $codePy $fixture --full-tests-ran 2>&1 | Out-String
$json = Get-JsonFromOutput $out
if (-not $json) { Fail 'No JSON from fixture run' }
else {
    try {
        $obj = $json | ConvertFrom-Json
        if (-not $obj.agentSections.F) { Fail 'Manifest missing section F (multi-module domain row)' }
        elseif ($obj.agentSections.F.modules -notcontains 'hardware_cache.py') {
            Fail 'Manifest F missing hardware_cache.py from multi-module row'
        } else { Ok 'section F in manifest' }
        if (-not $obj.agentSections.K) { Fail 'Manifest missing section K (sectionTests-only)' }
        else { Ok 'section K in manifest' }
        if (-not $obj.agentSections.A) { Fail 'Manifest missing section A (checklist-only)' }
        else { Ok 'section A in manifest (checklist parse)' }
        if ($obj.requiredSections -and ($obj.requiredSections | Measure-Object).Count -lt 3) {
            Fail 'requiredSections too short'
        } else { Ok 'requiredSections populated' }
        if (-not $obj.machineCoverage.A.agentFocus) { Fail 'machineCoverage missing agentFocus' }
        elseif ($null -eq $obj.machineCoverage.A.machineCheckCount) { Fail 'machineCoverage missing machineCheckCount' }
        else { Ok 'machineCoverage agentFocus + machineCheckCount' }
        if (-not $obj.machineFixesBySection) { Fail 'JSON missing machineFixesBySection' }
        else { Ok 'machineFixesBySection present' }
        if ($null -eq $obj.machineSectionsWithFixes) { Fail 'JSON missing machineSectionsWithFixes' }
        elseif ($obj.machineFixesBySection.PSObject.Properties.Name.Count -ne $obj.machineSectionsWithFixes.Count) {
            Fail 'machineSectionsWithFixes length mismatch vs machineFixesBySection'
        } else { Ok 'machineSectionsWithFixes aligned' }
    } catch {
        Fail "JSON parse failed: $_"
    }
}

# 3. SkipTests must fail incomplete audit on fixture
Write-Host '3. run_audit_core.ps1 -SkipTests must exit 1'
Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 -RepoRoot $PackRoot -AppRoot $fixture -SkipTests *> $null
if ($LASTEXITCODE -ne 1) { Fail "SkipTests exit code $($LASTEXITCODE), expected 1" }
else { Ok 'SkipTests exits 1' }
$fixtureManifest = Join-Path $fixture 'docs\.audit_agent_manifest.json'
if (Test-Path $fixtureManifest) { Remove-Item $fixtureManifest -Force -ErrorAction SilentlyContinue }

# 4. No orphan duplicate AUDIT template at pack root
Write-Host '4. Template hygiene'
$orphan = Join-Path $PackRoot 'pack\templates\AUDIT.md.template'
if (Test-Path $orphan) { Fail "Orphan template exists: $orphan (use pack/templates/docs/AUDIT.md.template)" }
else { Ok 'no orphan AUDIT.md.template' }

# 5. Protocol + skill forbid SkipTests loopholes
Write-Host '5. Rules and skill one-standard text'
$skillPath = Join-Path $PackRoot 'pack\skills\agent-code-audit\SKILL.md'
$protoPath = Join-Path $PackRoot 'pack\rules\audit-protocol.mdc'
foreach ($pair in @(@($skillPath, 'skill'), @($protoPath, 'audit-protocol'))) {
    $p, $label = $pair
    if (-not (Test-Path $p)) { Fail "Missing $label"; continue }
    $c = Get-Content $p -Raw
    if ($c -notmatch 'SkipTests|skip tests') { Fail "$label missing -SkipTests prohibition" }
    elseif ($c -match 'machine checks only|debug audit script') { Fail "$label still has SkipTests loophole" }
    else { Ok "$label one-standard text" }
}

# Anything install.ps1 copies into a profile must also be listed in the manifest, or it lands once
# on a fresh install and then goes stale forever: incremental syncs never see it and no check
# reports it. install.ps1 uses Copy-Tree on the whole rules and skills folders, so everything in
# them is installed whether the manifest knows about it or not. Four rules were in exactly that
# state; when this check covered rules only, two of the three skills still were.
Write-Host '5b. Every installed rule and skill is tracked by the manifest'
try {
    $manifestPath = Join-Path $PackRoot 'pack\audit\manifest.json'
    $mf = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $mirror = @($mf.packMirror)
    $toUser = @($mf.packToUser | ForEach-Object { $_.from })
    $installed = @()
    foreach ($r in (Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack\rules') -Filter *.mdc -File)) {
        $installed += "pack/rules/$($r.Name)"
    }
    foreach ($s in (Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack\skills') -Directory)) {
        foreach ($f in (Get-ChildItem -LiteralPath $s.FullName -Filter *.md -File -Recurse)) {
            $rel = $f.FullName.Substring($PackRoot.Length).TrimStart('\') -replace '\\', '/'
            $installed += $rel
        }
    }
    $missingMirror = @($installed | Where-Object { $mirror -notcontains $_ })
    $missingUser = @($installed | Where-Object { $toUser -notcontains $_ })
    if ($missingMirror.Count -gt 0) { Fail "installed files missing from manifest packMirror (installed but never synced): $($missingMirror -join ', ')" }
    elseif ($missingUser.Count -gt 0) { Fail "installed files missing from manifest packToUser (installed but never synced): $($missingUser -join ', ')" }
    else { Ok "all $($installed.Count) installed rules and skills are tracked for sync" }

    # Same trap, third occurrence: pack\docs travels into the profile with the rest of the tree, so a
    # maintainer doc left out of packMirror is copied once and then frozen. An agent reading the
    # installed copy gets last month's answer - which is how a doc still claiming a shipped feature
    # was "planned, not built" would survive. Enumerated, not listed, so a new doc is covered on
    # creation. packToUser is not asserted here: these are maintainer docs, not profile rules.
    # Generated per machine, gitignored, and dropped from the export - mirroring it would push one
    # machine's absolute paths into the install.
    $generatedDocs = @('AGENT_REFRESH.md', 'AGENT_SESSION_START.md', 'AGENT_PASTE.txt')
    $trackedDocs = @()
    foreach ($docDir in @('pack\docs', 'docs')) {
        $full = Join-Path $PackRoot $docDir
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $prefix = $docDir -replace '\\', '/'
        foreach ($f in (Get-ChildItem -LiteralPath $full -Filter *.md -File)) {
            if ($generatedDocs -contains $f.Name) { continue }
            $trackedDocs += "$prefix/$($f.Name)"
        }
    }
    $docsUnmirrored = @($trackedDocs | Where-Object { $mirror -notcontains $_ })
    if ($docsUnmirrored.Count -gt 0) {
        Fail "docs missing from manifest packMirror (installed once, then stale forever): $($docsUnmirrored -join ', ')"
    } else { Ok "all $($trackedDocs.Count) pack/docs + docs files are tracked for sync" }

    # The machinery itself had the same hole, and it bites harder than docs: bootstrap-project.ps1 and
    # every template it writes were unmirrored, and bootstrapping *from the installed pack* is the
    # documented normal path - so a project generated after the second pack update would have been
    # built from the first update's templates. doctor.ps1 was unmirrored too, and the handoff tells
    # you to run it out of the profile. Enumerated so a new script or template is covered on creation.
    $machinery = @()
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack\scripts') -File)) {
        if ($f.Extension -in @('.ps1', '.py')) { $machinery += "pack/scripts/$($f.Name)" }
    }
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack\templates') -Recurse -File)) {
        $machinery += ($f.FullName.Substring($PackRoot.Length).TrimStart('\') -replace '\\', '/')
    }
    $machineryUnmirrored = @($machinery | Where-Object { $mirror -notcontains $_ })
    if ($machineryUnmirrored.Count -gt 0) {
        Fail "scripts/templates missing from manifest packMirror (the installed copy would never be updated): $($machineryUnmirrored -join ', ')"
    } else { Ok "all $($machinery.Count) pack scripts and templates are tracked for sync" }

    # Fifth appearance of the same hole, one layer further out: install.ps1 copies the repo root, so the
    # user's profile gets Refresh-AgentContext.cmd, Bootstrap-Project.cmd and friends - but only
    # run_audit.cmd and run_audit_tests.bat were mirrored, so a fix to any other wrapper stopped at the
    # source pack. A user running the installed Refresh-AgentContext.cmd would keep the old one forever.
    $rootEntry = @()
    foreach ($f in (Get-ChildItem -LiteralPath $PackRoot -File)) {
        if ($f.Extension -in @('.cmd', '.bat', '.ps1', '.sh')) { $rootEntry += $f.Name }
    }
    $rootUnmirrored = @($rootEntry | Where-Object { $mirror -notcontains $_ })
    if ($rootUnmirrored.Count -gt 0) {
        Fail "root entry points missing from manifest packMirror (install copies them, sync would not): $($rootUnmirrored -join ', ')"
    } else { Ok "all $($rootEntry.Count) root entry points are tracked for sync" }

    # Same hole once more, this time for the files nobody thought of as pack content: install.ps1 copies
    # the entire checkout, so README.md and VERSION shipped without being mirrored (stale in the profile
    # until the next full install) while session handoffs and implementation specs shipped when they
    # should never leave the repo. Every root file now has to be one or the other, so a new document
    # forces the question at test time rather than showing up in someone's profile months later.
    $generatedAtRoot = @('install-manifest.json')
    $maintainerOnly = @($mf.maintainerOnlyPaths | Where-Object { $_ })
    $rootDocs = @()
    foreach ($f in (Get-ChildItem -LiteralPath $PackRoot -File)) {
        if ($f.Extension -in @('.cmd', '.bat', '.ps1', '.sh', '.zip')) { continue }
        if ($f.Name -in $generatedAtRoot -or $f.Name -like '.*') { continue }
        $rootDocs += $f.Name
    }
    $unclassified = @($rootDocs | Where-Object { $mirror -notcontains $_ -and $maintainerOnly -notcontains $_ })
    $bothWays = @($rootDocs | Where-Object { $mirror -contains $_ -and $maintainerOnly -contains $_ })
    $installPs1 = Get-Content -LiteralPath (Join-Path $PackRoot 'install.ps1') -Raw
    if ($unclassified.Count -gt 0) {
        Fail "root files are neither mirrored nor maintainer-only - install ships them and sync cannot refresh them: $($unclassified -join ', ')"
    } elseif ($bothWays.Count -gt 0) {
        Fail "root files listed as both mirrored and maintainer-only: $($bothWays -join ', ')"
    } elseif ($installPs1 -notmatch 'maintainerOnlyPaths') {
        Fail 'install.ps1 ignores maintainerOnlyPaths - handoffs and specs would still ship to the profile'
    } else {
        Ok "all $($rootDocs.Count) root files classified ($($maintainerOnly.Count) maintainer-only, rest mirrored)"
    }

    # Sixth appearance, found by asking "what class of file have we not enumerated yet" instead of
    # waiting for the next symptom: mcp/agent_hygiene_server.py, the server install.ps1 registers in
    # mcp.json. A stale copy in the profile is a stale MCP server for every agent on the machine.
    $mcpFiles = @()
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $PackRoot 'mcp') -Recurse -File -ErrorAction SilentlyContinue)) {
        if ($f.Extension -in @('.py', '.json')) { $mcpFiles += ($f.FullName.Substring($PackRoot.Length).TrimStart('\') -replace '\\', '/') }
    }
    $mcpUnmirrored = @($mcpFiles | Where-Object { $mirror -notcontains $_ })
    if ($mcpUnmirrored.Count -gt 0) {
        Fail "MCP server files missing from manifest packMirror: $($mcpUnmirrored -join ', ')"
    } else { Ok "all $($mcpFiles.Count) MCP server file(s) are tracked for sync" }

    # The manifest is only half the path: sync-project-rules.ps1 pushes rules into a project, and it
    # used to carry its own hardcoded list - so a rule added later reached profiles but never
    # projects, silently. Run it for real and require every rule on disk to arrive.
    $ruleProbe = Join-Path $PackRoot ".tmp\ruleset-probe-$PID"
    try {
        New-Item -ItemType Directory -Path $ruleProbe -Force | Out-Null
        $syncRulesPs1 = Join-Path $PackRoot 'pack\scripts\sync-project-rules.ps1'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $syncRulesPs1 `
            -ProjectRoot $ruleProbe -RulesRelativePath '.cursor\rules' *> $null
        $srcNames = @(Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack\rules') -Filter *.mdc -File |
            Select-Object -ExpandProperty Name)
        $gotNames = @(Get-ChildItem -LiteralPath (Join-Path $ruleProbe '.cursor\rules') -Filter *.mdc -File `
                -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        $notSynced = @($srcNames | Where-Object { $gotNames -notcontains $_ })
        if ($notSynced.Count -gt 0) {
            Fail "sync-project-rules.ps1 did not deliver: $($notSynced -join ', ')"
        } else { Ok "sync-project-rules.ps1 delivers all $($srcNames.Count) rules" }
    } finally {
        Remove-Item $ruleProbe -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    Fail "rule and skill manifest coverage check error: $_"
}

# 6. Dead config key removed from generic template
Write-Host '6. Config template hygiene'
$cfgTpl = Join-Path $PackRoot 'pack\templates\docs\AUDIT.config.json.template'
if (Test-Path $cfgTpl) {
    $cfgText = Get-Content $cfgTpl -Raw
    if ($cfgText -match 'runSectionTestsWhenSkipFull') { Fail 'AUDIT.config.json.template still has runSectionTestsWhenSkipFull' }
    else { Ok 'no runSectionTestsWhenSkipFull in template' }
}

Write-Host '7. Agent workflow docs'
foreach ($rel in @('pack/docs/AGENT_WORKFLOW.md', 'pack/docs/AUDIT_SYSTEM_CHANGELOG.md')) {
    $p = Join-Path $PackRoot ($rel -replace '/', '\')
    if (-not (Test-Path $p)) { Fail "Missing $rel" } else { Ok (Split-Path $p -Leaf) }
}
$wfPath = Join-Path $PackRoot 'pack\docs\AGENT_WORKFLOW.md'
if (Test-Path $wfPath) {
    $wf = Get-Content $wfPath -Raw
    if ($wf -notmatch 'all projects|Loop-back protocol \(all projects\)') { Fail 'AGENT_WORKFLOW.md missing all-projects loop-back' }
    else { Ok 'AGENT_WORKFLOW all-projects loop-back' }
}
$lb = Join-Path $PackRoot 'pack\rules\loop-back-protocol.mdc'
if (-not (Test-Path $lb)) { Fail 'Missing loop-back-protocol.mdc' } else { Ok 'loop-back-protocol.mdc' }

# 8. Semantic report verify (template + validate)
Write-Host '8. Semantic report verify'
$manProbe = Join-Path $fixture 'docs\.audit_agent_manifest.json'
$treeHead = (& py -3 $codePy $fixture --print-tests-git-head 2>&1 | Select-Object -Last 1).ToString().Trim()
if (-not $treeHead) { Fail 'could not compute tests git/tree head for fixture' }
@{ testsGitHead = $treeHead; testsPassedAt = (Get-Date).ToUniversalTime().ToString('o'); machineFixesBySection = @{} } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manProbe -Encoding UTF8
& py -3 $codePy $fixture --write-semantic-template 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'write-semantic-template failed' }
else { Ok 'write-semantic-template' }
& py -3 $codePy $fixture --fill-semantic-fixture-test 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'fill-semantic-fixture-test failed' }
$semPath = Join-Path $fixture 'docs\.audit_semantic_report.json'
if (-not (Test-Path $semPath)) { Fail 'semantic report template not written' }
else {
    & py -3 $codePy $fixture --verify-semantic-report 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'verify-semantic-report failed after fill' }
    else { Ok 'verify-semantic-report' }
    Remove-Item $semPath -Force -ErrorAction SilentlyContinue
}

Write-Host '9. Semantic cite validation'
$treeHead9 = (& py -3 $codePy $fixture --print-tests-git-head 2>&1 | Select-Object -Last 1).ToString().Trim()
@{ testsGitHead = $treeHead9; testsPassedAt = (Get-Date).ToUniversalTime().ToString('o'); machineFixesBySection = @{} } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $fixture 'docs\.audit_agent_manifest.json') -Encoding UTF8
& py -3 $codePy $fixture --write-semantic-template 2>&1 | Out-Null
$semPath2 = Join-Path $fixture 'docs\.audit_semantic_report.json'
$badPy = @"
import json
from pathlib import Path
p = Path(r'$semPath2')
d = json.loads(p.read_text(encoding='utf-8'))
for k in d['sections']:
    d['sections'][k] = {
        'reviewed': True,
        'summary': 'Nothing found.' if k != 'D' else 'problem found with no cite',
        'evidence': [] if k != 'D' else [{'type': 'command', 'ref': 'manual review only'}],
    }
p.write_text(json.dumps(d, indent=2), encoding='utf-8')
"@
& py -3 -c $badPy
& py -3 $codePy $fixture --verify-semantic-report 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Fail 'verify-semantic-report should fail without cite on non-clean summary' }
else { Ok 'cite validation rejects vague summary' }
Remove-Item $semPath2 -Force -ErrorAction SilentlyContinue

Write-Host '10. Semantic evidence validation'
$treeHead10 = (& py -3 $codePy $fixture --print-tests-git-head 2>&1 | Select-Object -Last 1).ToString().Trim()
@{ testsGitHead = $treeHead10; testsPassedAt = (Get-Date).ToUniversalTime().ToString('o'); machineFixesBySection = @{} } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $fixture 'docs\.audit_agent_manifest.json') -Encoding UTF8
& py -3 $codePy $fixture --write-semantic-template 2>&1 | Out-Null
& py -3 $codePy $fixture --fill-semantic-fixture-test 2>&1 | Out-Null
$semPath3 = Join-Path $fixture 'docs\.audit_semantic_report.json'
$noEvPy = @"
import json
from pathlib import Path
p = Path(r'$semPath3')
d = json.loads(p.read_text(encoding='utf-8'))
d['sections']['D'] = {
    'reviewed': True,
    'summary': 'Issue in `main.py` needs fix',
    'evidence': [],
}
for k, v in d['sections'].items():
    if k != 'D':
        v['reviewed'] = True
        v['summary'] = 'Nothing found.'
        v['evidence'] = []
p.write_text(json.dumps(d, indent=2), encoding='utf-8')
"@
& py -3 -c $noEvPy
& py -3 $codePy $fixture --verify-semantic-report 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Fail 'verify-semantic-report should fail without evidence on non-clean D' }
else { Ok 'evidence required when not clean' }
$goodEvPy = @"
import json
from pathlib import Path
fixture = Path(r'$fixture')
p = fixture / 'docs/.audit_semantic_report.json'
d = json.loads(p.read_text(encoding='utf-8'))
exp = json.loads((fixture / 'docs/.audit_domain_expanded.json').read_text(encoding='utf-8'))
d['sections']['D'] = {
    'reviewed': True,
    'summary': 'Reviewed `main.py` - clean',
    'evidence': [{'type': 'file', 'ref': 'main.py'}],
    'modulesReviewed': list((exp.get('sections') or {}).get('D', ['main.py'])),
}
for k, v in d['sections'].items():
    if k != 'D':
        v['reviewed'] = True
        v['summary'] = 'Nothing found.'
        v['evidence'] = []
        v['modulesReviewed'] = list((exp.get('sections') or {}).get(k, []))
p.write_text(json.dumps(d, indent=2), encoding='utf-8')
"@
& py -3 -c $goodEvPy
& py -3 $codePy $fixture --verify-semantic-report 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'verify-semantic-report should pass with valid file evidence' }
else { Ok 'evidence file path validated' }
Remove-Item $semPath3 -Force -ErrorAction SilentlyContinue

Write-Host '11. machineCoverage completeness'
$mcOut = & py -3 $codePy $fixture --full-tests-ran 2>&1 | Out-String
$mcJson = Get-JsonFromOutput $mcOut
if (-not $mcJson) { Fail 'No JSON for machineCoverage test' }
else {
    try {
        $mcObj = $mcJson | ConvertFrom-Json
        if (-not $mcObj.machineCoverage.F) { Fail 'machineCoverage missing section F' }
        elseif ($null -eq $mcObj.machineCoverage.F.machineCheckCount) { Fail 'machineCoverage missing machineCheckCount' }
        else { Ok 'machineCoverage sections populated' }
    } catch { Fail "machineCoverage parse: $_" }
}

Write-Host '12. Semantic vs machine alignment'
$missingMod = Join-Path $fixture 'hardware_cache.py'
$modBackup = $null
if (Test-Path $missingMod) { $modBackup = Get-Content $missingMod -Raw; Remove-Item $missingMod -Force }
try {
    & py -3 $codePy $fixture --write-semantic-template 2>&1 | Out-Null
    & py -3 $codePy $fixture --fill-semantic-fixture-test 2>&1 | Out-Null
    $semPath4 = Join-Path $fixture 'docs\.audit_semantic_report.json'
    $allCleanPy = @"
import json
from pathlib import Path
p = Path(r'$semPath4')
d = json.loads(p.read_text(encoding='utf-8'))
d['sections']['F']['summary'] = 'Nothing found.'
d['sections']['F']['modulesReviewed'] = [m for m in d['sections']['F'].get('modulesReviewed', []) if m != 'hardware_cache.py']
p.write_text(json.dumps(d, indent=2), encoding='utf-8')
"@
    & py -3 -c $allCleanPy
    & py -3 $codePy $fixture --verify-semantic-report 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Fail 'verify-semantic-report should fail when F missing domain module but semantic clean' }
    else { Ok 'semantic vs machine blocks clean F when domain module missing' }
    Remove-Item $semPath4 -Force -ErrorAction SilentlyContinue
} finally {
    if ($null -ne $modBackup) { Write-Utf8NoBom $missingMod $modBackup }
}

Write-Host '13. Section L gitignore audit artifacts'
$giPath = Join-Path $fixture '.gitignore'
$giBackup = Get-Content $giPath -Raw
try {
    Write-Utf8NoBom $giPath "docs/.audit_agent_manifest.json`r`n"
    $giOut = & py -3 $codePy $fixture --lightweight --full-tests-ran 2>&1 | Out-String
    $giJson = Get-JsonFromOutput $giOut
    if (-not $giJson) { Fail 'No JSON for gitignore test' }
    else {
        $giObj = $giJson | ConvertFrom-Json
        $gitHit = @($giObj.fixes | Where-Object { $_ -match 'gitignore missing audit artifact' })
        if ($gitHit.Count -lt 1) { Fail 'expected Section L gitignore fix in JSON output' }
        else { Ok 'gitignore check flags missing semantic report path' }
    }
} finally {
    # A BOM here is not cosmetic: git would not match the first pattern in the file.
    Write-Utf8NoBom $giPath $giBackup
}

Write-Host '14. auditGateFixes manifest (Incomplete audit not in Section L)'
$manGate = Join-Path $fixture 'docs\.audit_agent_manifest.json'
Remove-Item $manGate -Force -ErrorAction SilentlyContinue
Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 -RepoRoot $PackRoot -AppRoot $fixture -SkipTests *> $null
if (-not (Test-Path $manGate)) { Fail 'manifest not written after SkipTests probe' }
else {
    try {
        $mg = Get-Content $manGate -Raw | ConvertFrom-Json
        if ($null -eq $mg.auditGateFixes) { Fail 'manifest missing auditGateFixes array' }
        $inc = @($mg.auditGateFixes | Where-Object { $_ -match 'Incomplete audit' })
        if ($inc.Count -lt 1) { Fail 'auditGateFixes missing Incomplete audit entry' }
        $badL = @()
        if ($mg.machineFixesBySection.L) {
            $badL = @($mg.machineFixesBySection.L | Where-Object { $_ -match 'Incomplete audit|Semantic report missing|Semantic report invalid' })
        }
        if ($badL.Count -gt 0) { Fail 'gate fix incorrectly mapped to Section L' }
        else { Ok 'auditGateFixes holds Incomplete audit; gate not in L' }
    } catch { Fail "auditGateFixes manifest parse: $_" }
}
Remove-Item $manGate -Force -ErrorAction SilentlyContinue

Write-Host '15. Semantic gate fix patterns (not Section L wiring)'
$gateSamples = @(
    'Semantic report missing - docs/.audit_semantic_report.json - run scripts/write_semantic_audit_template.cmd',
    'Semantic report invalid - .audit_semantic_report.json - JSON',
    'Semantic report - section D not marked reviewed',
    'Incomplete audit - full run_tests.bat required'
)
foreach ($sample in $gateSamples) {
    if ($sample -match '^Semantic report - section ') { continue }
    if ($sample -notmatch '^Semantic report missing|^Semantic report invalid|^Incomplete audit') {
        Fail "expected gate-class fix pattern: $sample"
    }
}
if ('Semantic report missing - x' -match 'Audit sync|Missing audit file|forbidden rule') { Fail 'semantic missing matches L wiring bucket' }
Ok 'gate fix patterns distinct from L wiring'

Write-Host '16. FinalizeOnly blocked without prior test pass'
Remove-Item $manGate -Force -ErrorAction SilentlyContinue
Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 -RepoRoot $PackRoot -AppRoot $fixture -FinalizeOnly 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Fail 'FinalizeOnly should fail without manifest test-pass proof' }
else { Ok 'FinalizeOnly requires manifest testsGitHead' }

Write-Host '17. FinalizeOnly preserves manifest test-pass proof'
Remove-Item $manGate -Force -ErrorAction SilentlyContinue
Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 -RepoRoot $PackRoot -AppRoot $fixture 2>&1 | Out-Null
if (-not (Test-Path $manGate)) { Fail 'pass 1 did not write manifest for preserve probe' }
else {
    try {
        $mg1 = Get-Content $manGate -Raw | ConvertFrom-Json
        $headProof = $mg1.testsGitHead.ToString()
        if (-not $headProof -or $headProof -eq '__no_git__') { Fail "pass 1 missing tree/git test proof (got $headProof)" }
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 -RepoRoot $PackRoot -AppRoot $fixture -FinalizeOnly 2>&1 | Out-Null
        $mg = Get-Content $manGate -Raw | ConvertFrom-Json
        if ($mg.testsGitHead -ne $headProof) { Fail "FinalizeOnly wiped testsGitHead (got $($mg.testsGitHead))" }
        elseif (-not $mg.testsPassedAt) { Fail 'FinalizeOnly wiped testsPassedAt' }
        else { Ok 'FinalizeOnly preserves testsGitHead + testsPassedAt' }
    } catch { Fail "FinalizeOnly manifest preserve parse: $_" }
}

Write-Host '18. Auditor workflow E2E - pass 1, semantic, finalize exit 0'
$semPathE2e = Join-Path $fixture 'docs\.audit_semantic_report.json'
$timingPath = Join-Path $fixture 'docs\.audit_timing.jsonl'
Remove-Item $manGate, $semPathE2e, $timingPath -Force -ErrorAction SilentlyContinue
Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 -RepoRoot $PackRoot -AppRoot $fixture 2>&1 | Out-Null
if (-not (Test-Path $semPathE2e)) { Fail 'pass 1 did not write semantic template' }
else {
    $fillPy = @"
import json
from datetime import datetime, timezone
from pathlib import Path
fixture = Path(r'$fixture')
man = json.loads((fixture / 'docs/.audit_agent_manifest.json').read_text(encoding='utf-8-sig'))
sem = json.loads((fixture / 'docs/.audit_semantic_report.json').read_text(encoding='utf-8-sig'))
exp = json.loads((fixture / 'docs/.audit_domain_expanded.json').read_text(encoding='utf-8-sig'))
inv = json.loads((fixture / 'docs/.audit_inventory.json').read_text(encoding='utf-8-sig'))
fixes = man.get('machineFixesBySection') or {}
evidence_by_letter = {
    'A': 'run_tests_stub.bat', 'D': 'main.py', 'F': 'app_settings.py',
    'K': 'main.py', 'L': 'docs/AUDIT.md', 'M': 'docs/AUDIT.md', 'N': 'main.py',
}
for letter, sec in sem.get('sections', {}).items():
    sec['reviewed'] = True
    sec['modulesReviewed'] = list((exp.get('sections') or {}).get(letter, []))
    mf = fixes.get(letter) or []
    if mf:
        ref = evidence_by_letter.get(letter, 'main.py')
        sec['summary'] = f'Addressed machine finding - reviewed `{ref}`'
        sec['evidence'] = [{'type': 'file', 'ref': ref}]
    else:
        sec['summary'] = 'Nothing found.'
        sec['evidence'] = []
if 'B' in sem.get('sections', {}):
    sem['sections']['B']['inventoryAck'] = {
        'productionModules': inv.get('productionModules', 0),
        'testFiles': inv.get('testFiles', 0),
        'productionLoc': inv.get('productionLoc', 0),
    }
sem['testsGitHead'] = man.get('testsGitHead') or sem.get('testsGitHead') or ''
sem['generatedAt'] = datetime.now(timezone.utc).isoformat()
(fixture / 'docs/.audit_semantic_report.json').write_text(json.dumps(sem, indent=2), encoding='utf-8')
"@
    & py -3 -c $fillPy
    if ($LASTEXITCODE -ne 0) { Fail 'semantic fill helper failed' }
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 -RepoRoot $PackRoot -AppRoot $fixture -FinalizeOnly 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'finalize should exit 0 with complete semantic report on fixture' }
    else { Ok 'auditor workflow E2E finalize exit 0' }
}

Write-Host '19. Audit phase timing log'
if (-not (Test-Path $timingPath)) { Fail 'missing docs/.audit_timing.jsonl after audit run' }
else {
    try {
        $lastLine = (Get-Content -LiteralPath $timingPath -Tail 1) | Select-Object -Last 1
        $tl = $lastLine | ConvertFrom-Json
        if (-not $tl.phases) { Fail 'timing log missing phases' }
        elseif ($null -eq $tl.totalSeconds) { Fail 'timing log missing totalSeconds' }
        else { Ok 'audit timing jsonl written with phases' }
    } catch { Fail "timing log parse: $_" }
}
Remove-Item $manGate, $semPathE2e, $timingPath -Force -ErrorAction SilentlyContinue

Write-Host '20. Mirror direction - source pack wins, installed copy never writes back'
# Runs the real sync against a miniature pack and a scratch install target, so the direction rules
# are enforced by tests instead of by reading the code. AGENT_STARTER_PACK_INSTALL_ROOT keeps every
# write inside the pack: nothing here may touch %USERPROFILE%\.cursor.
$probeRoot = Join-Path $PackRoot '.tmp\mirror-probe'
$prevInstallRoot = $env:AGENT_STARTER_PACK_INSTALL_ROOT
try {
    if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force }
    $probeSource = Join-Path $probeRoot 'source'
    $probeInstalled = Join-Path $probeRoot 'installed\AgentStarterPack'
    foreach ($d in @("$probeSource\pack\audit", "$probeSource\pack\scripts", "$probeSource\pack\rules", "$probeInstalled\pack\audit", "$probeInstalled\pack\rules")) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }

    $probeManifest = @'
{
  "version": "mirror-probe",
  "packMirror": [
    "pack/rules/probe-mirror.mdc",
    "pack/rules/probe-only-installed.mdc"
  ],
  "packToUser": [
    { "from": "pack/rules/probe-mirror.mdc", "to": "rules/probe-mirror.mdc" }
  ],
  "forbiddenPackPaths": []
}
'@
    $probeManifest | Set-Content -LiteralPath "$probeSource\pack\audit\manifest.json" -Encoding UTF8
    $probeManifest | Set-Content -LiteralPath "$probeInstalled\pack\audit\manifest.json" -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $PackRoot 'pack\scripts\pack-paths.ps1') -Destination "$probeSource\pack\scripts\pack-paths.ps1"
    Copy-Item -LiteralPath (Join-Path $PackRoot 'pack\scripts\sync-audit-system.ps1') -Destination "$probeSource\pack\scripts\sync-audit-system.ps1"
    $probeSync = "$probeSource\pack\scripts\sync-audit-system.ps1"

    # Write mode must never create an install. A project audit with autoFixDrift enabled runs this
    # script without -VerifyOnly, and the mirror used to materialize %USERPROFILE%\.cursor from
    # nothing - installing the pack as a side effect of auditing a project.
    $absentInstall = Join-Path $probeRoot 'never-installed\AgentStarterPack'
    Set-Content -LiteralPath "$probeSource\pack\rules\probe-mirror.mdc" -Value 'source' -Encoding UTF8
    $env:AGENT_STARTER_PACK_INSTALL_ROOT = $absentInstall
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeSync *> $null
    if (Test-Path -LiteralPath $absentInstall) { Fail 'sync created an install where none existed' }
    elseif (Test-Path -LiteralPath (Join-Path $probeRoot 'never-installed\rules')) { Fail 'sync created profile rules where no install existed' }
    else { Ok 'sync never creates an install (install.ps1 only)' }

    $srcMirror = "$probeSource\pack\rules\probe-mirror.mdc"
    $dstMirror = "$probeInstalled\pack\rules\probe-mirror.mdc"
    $dstOnly = "$probeInstalled\pack\rules\probe-only-installed.mdc"
    $srcOnly = "$probeSource\pack\rules\probe-only-installed.mdc"
    Set-Content -LiteralPath $srcMirror -Value 'source' -Encoding UTF8
    Set-Content -LiteralPath $dstMirror -Value 'installed' -Encoding UTF8
    Set-Content -LiteralPath $dstOnly -Value 'installed-only' -Encoding UTF8
    # Installed copy looks newer - the case a removable source pack must survive.
    (Get-Item -LiteralPath $dstMirror).LastWriteTime = (Get-Date).AddHours(2)
    (Get-Item -LiteralPath $dstOnly).LastWriteTime = (Get-Date).AddHours(2)

    $env:AGENT_STARTER_PACK_INSTALL_ROOT = $probeInstalled
    $syncOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeSync 2>&1 | Out-String

    if ((Get-Content -LiteralPath $dstMirror -Raw).Trim() -ne 'source') {
        Fail 'default sync did not push source pack over newer installed file'
    } else { Ok 'newer installed file loses to source pack' }

    if (Test-Path -LiteralPath $srcOnly) {
        Fail 'default sync copied an installed-only file back into the source pack'
    } elseif (Test-Path -LiteralPath $dstOnly) {
        Fail 'default sync left an installed-only file behind, so VerifyOnly can never go green'
    } elseif ($syncOut -notmatch '\[CLEAN\] removed from installed copy') {
        Fail 'default sync did not report removing the installed-only file'
    } else { Ok 'installed-only file dropped, source pack untouched' }

    $probeUserRule = Join-Path $probeRoot 'installed\rules\probe-mirror.mdc'
    if (-not (Test-Path -LiteralPath $probeUserRule)) {
        Fail 'packToUser mirror did not follow the install-root override'
    } elseif (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.cursor\rules\probe-mirror.mdc')) {
        Fail 'probe leaked into the real user profile'
    } else { Ok 'packToUser mirror honors install-root override' }

    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeSync -VerifyOnly *> $null
    $verifyClean = $LASTEXITCODE
    Set-Content -LiteralPath $dstMirror -Value 'installed' -Encoding UTF8
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeSync -VerifyOnly *> $null
    if ($verifyClean -ne 0) { Fail "VerifyOnly exit $verifyClean on a synced mirror, expected 0" }
    elseif ($LASTEXITCODE -eq 0) { Fail 'VerifyOnly missed drift in the installed mirror' }
    else { Ok 'VerifyOnly reports drift without copying' }

    Set-Content -LiteralPath $dstOnly -Value 'installed-only' -Encoding UTF8
    (Get-Item -LiteralPath $dstMirror).LastWriteTime = (Get-Date).AddHours(2)
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeSync -PullFromInstalled *> $null
    if ((Get-Content -LiteralPath $srcMirror -Raw).Trim() -ne 'installed') {
        Fail '-PullFromInstalled did not let the newer installed file win'
    } elseif (-not (Test-Path -LiteralPath $srcOnly)) {
        Fail '-PullFromInstalled did not restore the installed-only file'
    } else { Ok '-PullFromInstalled recovers installed edits' }
} catch {
    Fail "mirror direction probe error: $_"
} finally {
    $env:AGENT_STARTER_PACK_INSTALL_ROOT = $prevInstallRoot
    if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue }
    $tmpRoot = Join-Path $PackRoot '.tmp'
    if ((Test-Path -LiteralPath $tmpRoot) -and -not (Get-ChildItem -LiteralPath $tmpRoot -Force)) {
        Remove-Item -LiteralPath $tmpRoot -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '21. Requirements preflight'
$preflight = Join-Path $PackRoot 'pack\scripts\check-requirements.ps1'
if (-not (Test-Path -LiteralPath $preflight)) { Fail 'missing pack\scripts\check-requirements.ps1' }
else {
    # This machine has Python (the suite is running), so a clean probe must pass.
    $reqJson = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $preflight -Json 2>&1 | Out-String
    $reqExit = $LASTEXITCODE
    $reqObj = $null
    try { $reqObj = (Get-JsonFromOutput $reqJson) | ConvertFrom-Json } catch { }
    if (-not $reqObj) { Fail 'preflight -Json produced no parseable JSON' }
    elseif ($reqExit -ne 0) { Fail "preflight exit $reqExit on a machine that is running the suite" }
    elseif (-not $reqObj.ok) { Fail 'preflight reported required items missing while the suite runs' }
    else { Ok 'preflight passes with JSON output' }

    if ($reqObj) {
        $names = @($reqObj.results | ForEach-Object { $_.name })
        foreach ($needed in @('Python 3', 'Audit engine self-test')) {
            if ($names -notcontains $needed) { Fail "preflight missing required check: $needed" }
        }
        if (Test-PackIsWindows) {
            if ($names -notcontains "'py -3' launcher") { Fail "preflight missing required check: 'py -3' launcher" }
            else { Ok 'Windows py launcher required in preflight' }
        } else {
            $launcherRow = @($reqObj.results | Where-Object { $_.name -eq "'py -3' launcher" } | Select-Object -First 1)
            if (-not $launcherRow -or $launcherRow.required) { Fail 'py launcher should be optional/N/A off Windows' }
            else { Ok 'py launcher not required off Windows' }
        }
        $optional = @($reqObj.results | Where-Object { -not $_.required } | ForEach-Object { $_.name })
        if ($optional -notcontains 'git') { Fail 'git should be an optional requirement, not required' }
        else { Ok 'required vs optional split (git and mcp optional)' }
    }

    # Missing interpreter must be named and exit non-zero, not fail somewhere deeper later.
    $psExe = Get-PackPowerShellPath
    $badJson = & $psExe -NoProfile -ExecutionPolicy Bypass -File $preflight -PythonCommand 'nonexistent-python-xyz' -Json 2>&1 | Out-String
    $badExit = $LASTEXITCODE
    $badObj = $null
    try { $badObj = (Get-JsonFromOutput $badJson) | ConvertFrom-Json } catch { }
    $pyRow = if ($badObj) { $badObj.results | Where-Object { $_.name -eq 'Python 3' } | Select-Object -First 1 } else { $null }
    $pyFix = [string]($badObj.results | Where-Object { $_.name -eq 'Python 3' } | Select-Object -First 1 -ExpandProperty fix)
    if ($badExit -eq 0) { Fail 'preflight should exit 1 when Python cannot be found' }
    elseif (-not $pyRow -or $pyRow.status -ne 'missing') { Fail 'preflight did not name Python as the missing item' }
    elseif ([string]::IsNullOrWhiteSpace($pyFix)) { Fail "preflight missing Python fix field (badJson length $($badJson.Length))" }
    elseif ($pyFix -notmatch '(?i)(winget|python\.org|package manager|brew install|apt install)') {
        Fail "preflight fix not actionable: $pyFix"
    } else { Ok 'missing Python reported with an install command' }

    # The pack ships an mcp\ folder that shadows the real package as a namespace package, so the
    # probe must test mcp.server.fastmcp from outside the pack root (doctor.ps1 got this wrong).
    $reqText = Get-Content -LiteralPath $preflight -Raw
    if ($reqText -notmatch 'mcp\.server\.fastmcp') { Fail 'mcp probe must import mcp.server.fastmcp, not bare mcp' }
    else { Ok 'mcp probe tests the symbol the server imports' }
}

Write-Host '22. Pack tests run without pytest'
$packTests = Join-Path $PackRoot 'tests\test_pack_audit.py'
if (-not (Test-Path -LiteralPath $packTests)) { Fail 'missing tests\test_pack_audit.py' }
else {
    # 2>&1 into the pipeline, not *>$null: the MCP server prints to stderr when the optional mcp
    # package is absent, and $ErrorActionPreference='Stop' turns native stderr into a failure.
    & py -3 $packTests 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'tests\test_pack_audit.py failed when run directly' }
    else { Ok 'test_pack_audit.py runs standalone' }
    $runner = Join-Path $PackRoot 'run_audit_tests.bat'
    if ((Test-Path -LiteralPath $runner) -and ((Get-Content -LiteralPath $runner -Raw) -notmatch 'test_pack_audit\.py')) {
        Fail 'run_audit_tests.bat does not run tests\test_pack_audit.py'
    } else { Ok 'run_audit_tests.bat runs the pack tests' }
}

Write-Host '23. Bootstrap smoke - a generated project audits itself'
# Reading templates is not evidence that bootstrap output works. Running this by hand once found
# three shipped defects (BOM crash in load_config, a project audit installing the pack into
# %USERPROFILE%, and the parent-folder repo root), so it belongs in the suite.
# Per-run folder: a shared path fails the whole step when a leftover process, an antivirus scan, or
# a second concurrent run holds a probe file open, and the message ("cannot access the file") reads
# like a product defect instead of scratch contention.
$smokeRoot = Join-Path $PackRoot ".tmp\bootstrap-smoke-$PID"
$prevSmokePackRoot = $env:AGENT_STARTER_PACK_ROOT
$prevSmokeInstall = $env:AGENT_STARTER_PACK_INSTALL_ROOT
try {
    if (Test-Path -LiteralPath $smokeRoot) { Remove-Item -LiteralPath $smokeRoot -Recurse -Force -ErrorAction SilentlyContinue }
    $smokeProj = Join-Path $smokeRoot 'ProbeApp'
    $smokeInstall = Join-Path $smokeRoot 'no-install\AgentStarterPack'

    # Redirect the install target so nothing here can reach the real profile, and so "did anything
    # try to install?" is observable as a path that must stay absent.
    $env:AGENT_STARTER_PACK_INSTALL_ROOT = $smokeInstall
    # Put a README.md beside the probe so its parent looks like a repo root. The Python layer used
    # to promote the parent on exactly that evidence while the PowerShell wrapper kept the app root,
    # so the two layers disagreed about what they were auditing on an ordinary flat project.
    New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null
    # The version cite matters: doc sync rewrites v0.0.1 patterns in files it collects, and the old
    # repo-root rule collected them from this parent folder. If it ever regresses, this file changes.
    $smokeParentReadme = Join-Path $smokeRoot 'README.md'
    Set-Content -LiteralPath $smokeParentReadme -Value '# scratch parent v0.0.1' -Encoding ASCII
    $bootstrap = Join-Path $PackRoot 'pack\scripts\bootstrap-project.ps1'
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $bootstrap -ProjectRoot $smokeProj `
        -ProjectName 'ProbeApp' -Stack Python -Targets All -NoPause *> $null
    $bootExit = $LASTEXITCODE
    if ($bootExit -ne 0) { Fail "bootstrap exited $bootExit" }
    elseif (-not (Test-Path -LiteralPath (Join-Path $smokeProj 'run_audit.cmd'))) { Fail 'bootstrap produced no run_audit.cmd' }
    elseif (-not (Test-Path -LiteralPath (Join-Path $smokeProj 'docs\AUDIT.config.json'))) { Fail 'bootstrap produced no docs\AUDIT.config.json' }
    else { Ok 'bootstrap generates a project into a new folder' }

    $bomHits = @()
    foreach ($gen in @(Get-ChildItem -LiteralPath $smokeProj -Recurse -File -Include *.json, *.cmd, *.bat, *.md, *.py -ErrorAction SilentlyContinue)) {
        $bytes = [System.IO.File]::ReadAllBytes($gen.FullName)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $bomHits += $gen.Name }
    }
    if ($bomHits.Count -gt 0) { Fail "generated files carry a UTF-8 BOM: $($bomHits -join ', ')" }
    else { Ok 'generated files are BOM-free' }

    # Same failure shape as the BOM check: the generator hands the user a file it half-finished.
    # ensure-work-completion.ps1 substituted {{PROJECT_NAME}} for WORK_COMPLETION.md but plain-copied
    # the handoffs README, so every project got a literal placeholder in its title.
    $placeholderHits = @()
    foreach ($gen in @(Get-ChildItem -LiteralPath $smokeProj -Recurse -File -Include *.json, *.cmd, *.bat, *.md, *.py, *.mdc -ErrorAction SilentlyContinue)) {
        $genText = Get-Content -LiteralPath $gen.FullName -Raw -Encoding UTF8
        if ($genText -match '\{\{[A-Z_]+\}\}') {
            $placeholderHits += "$($gen.Name) ($($Matches[0]))"
        }
    }
    if ($placeholderHits.Count -gt 0) { Fail "generated files still contain template placeholders: $($placeholderHits -join ', ')" }
    else { Ok 'no unsubstituted template placeholders' }

    $env:AGENT_STARTER_PACK_ROOT = $PackRoot
    $auditCmd = Join-Path $smokeProj 'run_audit.cmd'
    $auditOut = & cmd /c "`"$auditCmd`" 2>&1" | Out-String
    # Audit twice: the second run takes the "already synced" path through the generated version
    # script, where a single non-ASCII character used to fail the whole test step.
    $auditOut2 = & cmd /c "`"$auditCmd`" 2>&1" | Out-String

    $projPattern = [regex]::Escape($smokeProj)
    if ($auditOut -notmatch "Repo:\s+$projPattern\s") { Fail 'audit repo root is not the project root (parent-folder regression)' }
    elseif ($auditOut -notmatch "App:\s+$projPattern\s") { Fail 'audit app root is not the project root' }
    else { Ok 'repo root and app root both resolve to the project' }

    # Both layers must agree, or the machine checks and the Python checks audit different trees.
    $pyRepo = (& py -3 (Join-Path $PackRoot 'pack\scripts\audit_code_checks.py') $smokeProj --print-repo-root 2>&1 | Out-String).Trim()
    if ($pyRepo -ne $smokeProj) { Fail "python repo root disagrees with the wrapper: '$pyRepo' vs '$smokeProj'" }
    else { Ok 'python and powershell agree on the repo root' }

    # Third implementation of the same decision, and the only one that writes: doc_version_sync
    # resolves scanFiles against this root, so a wrong answer rewrites files outside the project.
    $dvsProbe = "import sys; sys.path.insert(0, r'$(Join-Path $PackRoot 'pack\scripts')'); " +
        "from pathlib import Path; import doc_version_sync as d; print(d.resolve_repo_root(Path(r'$smokeProj')))"
    $dvsRepo = (& py -3 -c $dvsProbe 2>&1 | Out-String).Trim()
    if ($dvsRepo -ne $smokeProj) { Fail "doc_version_sync repo root disagrees: '$dvsRepo' vs '$smokeProj'" }
    else { Ok 'doc_version_sync agrees on the repo root' }

    # Behavioural half: the generated tests ran doc sync twice by now (once per audit).
    if ((Get-Content -LiteralPath $smokeParentReadme -Raw) -notmatch 'v0\.0\.1') {
        Fail 'doc sync rewrote a file outside the project (parent README version cite changed)'
    } else { Ok 'doc sync writes stay inside the project' }

    if ($auditOut -notmatch 'Wrote semantic report template') { Fail 'audit did not reach the semantic gate - engine failed early' }
    elseif ($auditOut -match 'no JSON object in output|Unexpected UTF-8 BOM') { Fail 'audit_code_checks.py failed on generated files' }
    else { Ok 'audit engine runs against generated files' }

    if ($auditOut -match 'missing project file') { Fail 'sync reports phantom missing project files' }
    elseif ($auditOut -notmatch 'Audit sync: OK') { Fail 'sync did not report OK on a freshly generated project' }
    else { Ok 'no phantom sync drift' }

    if ($auditOut -match 'Semantic report stale') { Fail 'fresh project reports a stale semantic report' }
    else { Ok 'test-pass proof is not stale on first run' }

    if ($auditOut2 -match 'Tests failed') { Fail 'generated tests pass once then fail on re-run' }
    elseif ($auditOut2 -notmatch 'Tests: OK') { Fail 'generated tests did not pass on the second audit' }
    else { Ok 'generated tests pass on a repeat audit' }

    # Only the semantic report should be left for the auditor. Anything else here is the generator
    # handing the user a Fix item for a file or setting the generator itself produced.
    # Section B's inventoryAck is semantic too: the auditor states the scope they reviewed, and
    # pre-filling those counts would defeat the acknowledgement.
    $semanticPattern = 'Semantic report|Section L|Section B - inventoryAck'
    $leftover = @(($auditOut2 -split "`r?`n") |
        Where-Object { $_ -match '^- ' -and $_ -notmatch $semanticPattern })
    if ($leftover.Count -gt 0) { Fail "generated project is not machine-clean: $($leftover -join ' | ')" }
    else { Ok 'generated project is machine-clean except semantic review' }

    if (Test-Path -LiteralPath $smokeInstall) { Fail 'auditing a project created an install' }
    else { Ok 'auditing a project installs nothing' }

    $genProj = Join-Path $smokeRoot 'GenApp'
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $bootstrap -ProjectRoot $genProj `
        -ProjectName 'GenApp' -Stack Generic -Targets All -NoPause *> $null
    if (-not (Test-Path -LiteralPath (Join-Path $genProj 'docs\AUDIT.config.json'))) { Fail 'Generic bootstrap produced no config' }
    else {
        $genCmd = Join-Path $genProj 'run_audit.cmd'
        $genOut = & cmd /c "`"$genCmd`" 2>&1" | Out-String
        $genLeft = @(($genOut -split "`r?`n") |
            Where-Object { $_ -match '^- ' -and $_ -notmatch $semanticPattern })
        if ($genLeft.Count -gt 0) { Fail "Generic project is not machine-clean: $($genLeft -join ' | ')" }
        else { Ok 'Generic stack project is machine-clean' }

        # No project may pass an audit having reviewed nothing. Both stacks must land on a real gate.
        if ($genOut -notmatch 'Semantic report - section A not marked reviewed') {
            Fail 'generated project has no semantic gate (nothing required to review)'
        } else { Ok 'generated project starts with a real semantic gate' }

        # A flat project may legitimately be named "app" - PowerShell matches that case-insensitively,
        # so a name alone must never make the audit treat the parent folder as the repo root.
        $namedApp = Join-Path $smokeRoot 'app'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $bootstrap -ProjectRoot $namedApp `
            -ProjectName 'app' -Stack Generic -Targets All -NoPause *> $null
        $appOut = & cmd /c "`"$(Join-Path $namedApp 'run_audit.cmd')`" 2>&1" | Out-String
        if ($appOut -notmatch "Repo:\s+$([regex]::Escape($namedApp))\s") {
            Fail 'a flat project named "app" audits its parent folder'
        } else { Ok 'folder named "app" does not hijack the repo root' }

        # Walk the documented three-step workflow on generated output: machine pass, auditor fills
        # the semantic report, finalize. A new project must be able to reach a clean audit.
        & py -3 (Join-Path $PackRoot 'pack\scripts\audit_code_checks.py') $genProj --fill-semantic-fixture-test *> $null
        $genFinal = & cmd /c "`"$genCmd`" -FinalizeOnly 2>&1" | Out-String
        $genFinalLeft = @(($genFinal -split "`r?`n") | Where-Object { $_ -match '^- ' })
        if ($genFinalLeft.Count -gt 0) { Fail "generated project cannot reach a clean audit: $($genFinalLeft -join ' | ')" }
        else { Ok 'generated project reaches a clean audit after semantic review' }

        # A product audit must never run the pack's own behavior suite: it would bootstrap probe
        # projects inside the pack folder, cost ~30s, and re-enter this script without end.
        if ($genFinal -match 'Bootstrap smoke') { Fail 'product audit ran the pack behavior suite' }
        elseif ($genFinal -match 'Skipping verify-audit-system') {
            # Distinct from the case below: verify never ran at all, so -SkipBehavior proves nothing.
            # Conflating the two reported "ran without -SkipBehavior" for a run that ran nothing.
            Fail 'product audit skipped verify-audit-system entirely on a complete semantic pass'
        }
        elseif ($genFinal -notmatch 'Behavior self-test: skipped') { Fail 'product audit ran verify-audit-system without -SkipBehavior' }
        elseif ($genFinal -notmatch 'audit engine self-test: OK') { Fail 'product audit skipped the behavior suite without proving the engine' }
        else { Ok 'product audit proves the engine without running the pack suite' }

        # A test pass has to be proof about the code, not about the commit. HEAD does not move for
        # uncommitted edits, so a git project could pass an audit, change a file, and keep the
        # pass - while a project without git was policed strictly. Same tree, opposite verdicts.
        $gitProj = Join-Path $smokeRoot 'GitApp'
        $prevGitCount = $env:GIT_CONFIG_COUNT
        $prevGitKey = $env:GIT_CONFIG_KEY_0
        $prevGitVal = $env:GIT_CONFIG_VALUE_0
        $prevEap = $ErrorActionPreference
        try {
            # Removable media carries no ownership records, so git refuses the repo as dubious.
            # Trust it through the environment rather than writing the user's git config.
            $env:GIT_CONFIG_COUNT = '1'
            $env:GIT_CONFIG_KEY_0 = 'safe.directory'
            $env:GIT_CONFIG_VALUE_0 = '*'
            # git reports line-ending conversions on stderr, and with ErrorActionPreference Stop a
            # native command writing stderr aborts the whole step on a message that is not an error.
            $ErrorActionPreference = 'Continue'
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath $bootstrap -ProjectRoot $gitProj `
                -ProjectName 'GitApp' -Stack Python -Targets All -NoPause *> $null
            & git -C $gitProj init -q *> $null
            & git -C $gitProj add -A *> $null
            & git -C $gitProj -c user.email=probe@example.com -c user.name=probe commit -q -m 'probe' *> $null
            $gitHead = ((& git -C $gitProj rev-parse HEAD 2>$null) | Select-Object -First 1)
            $gitHead = if ($gitHead) { $gitHead.ToString().Trim() } else { '' }
            if ($gitHead -notmatch '^[0-9a-f]{40}$') { Fail "git probe repo has no HEAD ($gitHead) - proof mode untested" }
            else {
                $gitCmd = Join-Path $gitProj 'run_audit.cmd'
                & cmd /c "`"$gitCmd`" 2>&1" | Out-Null
                & py -3 $codePy $gitProj --fill-semantic-fixture-test *> $null
                $gitClean = & cmd /c "`"$gitCmd`" -FinalizeOnly 2>&1" | Out-String
                $gitCleanLeft = @(($gitClean -split "`r?`n") | Where-Object { $_ -match '^- ' })
                $recordedProof = ''
                $manPath = Join-Path $gitProj 'docs\.audit_agent_manifest.json'
                if (Test-Path -LiteralPath $manPath) {
                    $recordedProof = ((Get-Content -LiteralPath $manPath -Raw | ConvertFrom-Json).testsGitHead)
                }
                if ($gitCleanLeft.Count -gt 0) { Fail "git-backed project cannot reach a clean audit: $($gitCleanLeft -join ' | ')" }
                elseif ($recordedProof -notmatch '^[0-9a-f]{40}\+tree:[0-9a-f]{64}$') {
                    Fail "test-pass proof in a git repo is not commit+content: '$recordedProof'"
                } else {
                    # Same line count, so the old size-and-mtime fingerprint would not have moved either.
                    $probeMain = Join-Path $gitProj 'main.py'
                    (Get-Content -LiteralPath $probeMain -Raw) -replace 'def main\(\)', 'def main_BROKEN()' |
                        Set-Content -LiteralPath $probeMain -NoNewline -Encoding ASCII
                    $tampered = & cmd /c "`"$gitCmd`" -FinalizeOnly 2>&1" | Out-String
                    if ($tampered -notmatch 'source tree changed since last test pass') {
                        Fail 'code changed after a clean audit in a git repo and the audit still passed'
                    } else { Ok 'proof is commit+content: an uncommitted code change invalidates the pass' }
                }
            }
        } finally {
            $ErrorActionPreference = $prevEap
            $env:GIT_CONFIG_COUNT = $prevGitCount
            $env:GIT_CONFIG_KEY_0 = $prevGitKey
            $env:GIT_CONFIG_VALUE_0 = $prevGitVal
        }

        # Only the runner's exit code was checked, so `exit /b 0` in run_tests.bat passed the whole
        # test gate with tests/ untouched.
        $hollowProj = Join-Path $smokeRoot 'HollowApp'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $bootstrap -ProjectRoot $hollowProj `
            -ProjectName 'HollowApp' -Stack Python -Targets All -NoPause *> $null
        if (-not (Test-Path -LiteralPath (Join-Path $hollowProj 'tests'))) { Fail 'hollow-runner probe has no tests to miss' }
        else {
            Write-Utf8NoBom (Join-Path $hollowProj 'run_tests.bat') "@echo off`r`nexit /b 0`r`n"
            $hollowOut = & cmd /c "`"$(Join-Path $hollowProj 'run_audit.cmd')`" 2>&1" | Out-String
            if ($hollowOut -notmatch 'Test runner - run_tests\.bat never runs') {
                Fail 'a test runner that runs nothing passed the test gate'
            } else { Ok 'a runner that skips the test files is caught' }
        }
    }
} catch {
    Fail "bootstrap smoke error: $_"
} finally {
    $env:AGENT_STARTER_PACK_ROOT = $prevSmokePackRoot
    $env:AGENT_STARTER_PACK_INSTALL_ROOT = $prevSmokeInstall
    if (Test-Path -LiteralPath $smokeRoot) { Remove-Item -LiteralPath $smokeRoot -Recurse -Force -ErrorAction SilentlyContinue }
    $tmpRoot2 = Join-Path $PackRoot '.tmp'
    if ((Test-Path -LiteralPath $tmpRoot2) -and -not (Get-ChildItem -LiteralPath $tmpRoot2 -Force)) {
        Remove-Item -LiteralPath $tmpRoot2 -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '24. Executed code is ASCII and BOM-free'
# Three separate failures came from text encoding: a generated project crashed on a BOM, this
# preflight failed to parse because an em dash became a stray quote when PowerShell 5.1 read the
# file as ANSI, and a generated project's tests died on UnicodeEncodeError printing an arrow to a
# cp1252 console. Markdown keeps its typography; code that runs does not.
try {
    $codeOffenders = New-Object System.Collections.ArrayList
    $bomOffenders = New-Object System.Collections.ArrayList
    $crOffenders = New-Object System.Collections.ArrayList
    $scanned = 0
    # Filter by extension in code: -Include is silently ignored with -LiteralPath, which quietly
    # dragged in .pyc bytecode and Markdown and made this check fail on files it must not judge.
    $codeExt = @('.ps1', '.py', '.cmd', '.bat', '.sh')
    $codeFiles = New-Object System.Collections.ArrayList
    function Add-CodeFile($f) {
        if ($f.FullName -match '\\(__pycache__|\.tmp|\.git)\\') { return }
        if ($codeExt -contains $f.Extension) { [void]$script:codeFiles.Add($f); return }
        # .gitignore is not executed, but a BOM makes git skip the file's first pattern, and the
        # suite rewrites tracked .gitignore files while testing the Section L check.
        if ($f.Name -eq '.gitignore') { [void]$script:codeFiles.Add($f); return }
        # Templates only when they generate executed code: run_tests.bat.template, apply_version.py.template.
        if ($f.Extension -eq '.template' -and $f.Name -match '\.(ps1|py|cmd|bat)\.template$') { [void]$script:codeFiles.Add($f) }
    }
    # pack\audit was missing here, which left 13 executed files unscanned - the behavior fixture's
    # own wrappers and modules, which this suite runs - and one of them was committed with a BOM.
    foreach ($dir in @('pack\scripts', 'pack\templates', 'pack\audit', 'scripts', 'tests', 'mcp')) {
        $full = Join-Path $PackRoot $dir
        if (-not (Test-Path -LiteralPath $full)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $full -Recurse -File -ErrorAction SilentlyContinue)) { Add-CodeFile $f }
    }
    foreach ($f in (Get-ChildItem -LiteralPath $PackRoot -File -ErrorAction SilentlyContinue)) { Add-CodeFile $f }
    foreach ($f in $codeFiles) {
        $scanned++
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            [void]$bomOffenders.Add($f.Name)
        }
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        $hits = [regex]::Matches($text, '[^\x00-\x7F\uFEFF]')
        if ($hits.Count -gt 0) { [void]$codeOffenders.Add("$($f.Name) ($($hits.Count))") }
        # One CR is enough to make a shebang unrunnable, and .gitattributes only protects a checkout
        # made after it was added - the file itself still has to be right.
        if ($f.Extension -eq '.sh' -and $text.Contains("`r")) { [void]$crOffenders.Add($f.Name) }
    }
    if ($scanned -lt 20) { Fail "encoding scan found only $scanned code files - scan roots are wrong" }
    elseif ($codeOffenders.Count -gt 0) { Fail "non-ASCII in executed code: $(($codeOffenders | Select-Object -First 6) -join ', ')" }
    elseif ($bomOffenders.Count -gt 0) { Fail "UTF-8 BOM in executed code: $(($bomOffenders | Select-Object -First 6) -join ', ')" }
    elseif ($crOffenders.Count -gt 0) { Fail "CRLF in a shell script - the shebang will not run: $($crOffenders -join ', ')" }
    else { Ok "executed code is ASCII, BOM-free, and shell scripts are LF ($scanned files, incl. pack\audit and .gitignore)" }
} catch {
    Fail "encoding scan error: $_"
}

Write-Host '25. Fixture filler refuses outside the harness'
# One command marked every checklist section reviewed with no findings and filled the counts the
# gate cross-checks, so it could stand in for an entire semantic review. It ships in every install.
try {
    Remove-Item Env:AUDIT_FIXTURE_TEST -ErrorAction SilentlyContinue
    $fillOut = & py -3 $codePy $fixture --fill-semantic-fixture-test 2>&1 | Out-String
    $fillCode = $LASTEXITCODE
    $env:AUDIT_FIXTURE_TEST = '1'
    if ($fillCode -eq 0) { Fail 'fixture filler ran without the opt-in - one command fakes a semantic review' }
    elseif ($fillOut -notmatch 'Refusing --fill-semantic-fixture-test') { Fail "fixture filler refused without explaining why: $($fillOut.Trim())" }
    else { Ok 'fixture filler refuses without the harness opt-in' }
} catch {
    $env:AUDIT_FIXTURE_TEST = '1'
    Fail "fixture filler gate error: $_"
}

Write-Host '26. Installer profile writes (MCP merge + copy filter)'
# install.ps1 writes into the user profile, so it is the one script a test cannot run for real.
# Both functions are pulled out of the shipped file by AST and exercised against scratch paths.
# The merge previously destroyed every pre-existing MCP server: dot-assigning a new key on the
# PSCustomObject from ConvertFrom-Json throws, the catch read that as "unparseable", and the
# rewrite kept only agent-hygiene.
$probe = Join-Path $PackRoot ".tmp\installer-probe-$PID"
try {
    $installPs1 = Join-Path $PackRoot 'install.ps1'
    if (-not (Test-Path $installPs1)) { throw "install.ps1 not found at $installPs1" }
    $installAst = [System.Management.Automation.Language.Parser]::ParseFile($installPs1, [ref]$null, [ref]$null)
    foreach ($fnName in @('Copy-Tree', 'Merge-McpJson', 'Get-RelativeFileSet', 'Get-StaleInstalledFiles')) {
        $fnAst = $installAst.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fnName
            }, $true) | Select-Object -First 1
        if (-not $fnAst) { throw "$fnName not found in install.ps1" }
        Invoke-Expression $fnAst.Extent.Text
    }

    if (Test-Path $probe) { Remove-Item $probe -Recurse -Force }
    New-Item -ItemType Directory -Path $probe -Force | Out-Null

    # Merge-McpJson reads these from install.ps1's scope.
    $UserCursor = Join-Path $probe 'cursor'
    $CanonicalRoot = Join-Path $UserCursor 'AgentStarterPack'
    New-Item -ItemType Directory -Path $CanonicalRoot -Force | Out-Null
    $mcpJson = Join-Path $UserCursor 'mcp.json'

    $preExisting = @'
{
  "mcpServers": {
    "keep-me": { "command": "npx", "args": ["-y", "some-server"], "env": { "TOKEN": "x" } },
    "keep-me-too": { "command": "py", "args": ["-3", "other.py"] }
  }
}
'@
    Write-Utf8NoBom $mcpJson $preExisting
    Merge-McpJson | Out-Null
    $merged = (Get-Content $mcpJson -Raw) | ConvertFrom-Json
    $names = @(($merged.mcpServers.PSObject.Properties).Name)
    if ($names.Count -ne 3) { Fail "MCP merge kept $($names.Count) of 3 servers - pre-existing servers destroyed" }
    elseif ($names -notcontains 'agent-hygiene') { Fail 'MCP merge did not register agent-hygiene' }
    elseif ($merged.mcpServers.'keep-me'.env.TOKEN -ne 'x') { Fail 'MCP merge dropped nested server config' }
    else { Ok 'MCP merge preserves pre-existing servers' }

    $bytes = [System.IO.File]::ReadAllBytes($mcpJson)
    if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { Fail 'MCP merge wrote mcp.json with a BOM' }
    else { Ok 'mcp.json written BOM-free' }

    Merge-McpJson | Out-Null
    $again = @((((Get-Content $mcpJson -Raw) | ConvertFrom-Json).mcpServers.PSObject.Properties).Name)
    if ($again.Count -ne 3) { Fail "MCP merge is not idempotent - $($again.Count) servers after second run" }
    else { Ok 'MCP merge is idempotent' }

    # A config this script cannot read is still the user's data: leave it alone, back it up, register nothing.
    Write-Utf8NoBom $mcpJson '{ this is not json'
    Merge-McpJson -WarningAction SilentlyContinue | Out-Null
    if ((Get-Content $mcpJson -Raw).Trim() -ne '{ this is not json') { Fail 'unparseable mcp.json was overwritten instead of preserved' }
    elseif (-not (Test-Path "$mcpJson.bak")) { Fail 'unparseable mcp.json was not backed up' }
    else { Ok 'unparseable mcp.json preserved and backed up' }

    # Copy-Tree only ever adds files, so machine-local artifacts would live in the profile forever.
    $ctSrc = Join-Path $probe 'ct-src'
    $ctDst = Join-Path $probe 'ct-dst'
    foreach ($rel in @('install.ps1', 'pack\scripts\x.py', 'pack\scripts\__pycache__\x.cpython-314.pyc',
            '.git\config', '.tmp\scratch.txt', '.pytest_cache\c.json',
            'docs\.audit_semantic_report.json', 'docs\AUDIT.md', '.gitignore',
            # A maintainer-only entry may name a folder. SkipRelPaths matched exact files only, so
            # docs\handoffs would have shipped every work slice into the profile - and listing the
            # files one by one guarantees the next one is missed.
            'HANDOFF_NEXT_AGENT.md', 'docs\handoffs\active\HANDOFF_WQ001_x.md',
            'docs\handoffs\README.md', 'docs\handoffs-notes.md')) {
        $full = Join-Path $ctSrc $rel
        $dir = Split-Path $full -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Write-Utf8NoBom $full 'x'
    }
    (Get-Item -LiteralPath (Join-Path $ctSrc '.git') -Force).Attributes = 'Directory,Hidden'
    Copy-Tree $ctSrc $ctDst `
        -SkipDirNames @('.git\', '.tmp\', '__pycache__\', '.pytest_cache\') `
        -SkipExtensions @('.pyc', '.pyo') -SkipNamePatterns @('.audit_*') `
        -SkipRelPaths @('HANDOFF_NEXT_AGENT.md', 'docs\handoffs')
    $leaked = @('pack\scripts\__pycache__\x.cpython-314.pyc', '.git\config', '.tmp\scratch.txt',
        '.pytest_cache\c.json', 'docs\.audit_semantic_report.json',
        'HANDOFF_NEXT_AGENT.md', 'docs\handoffs\active\HANDOFF_WQ001_x.md', 'docs\handoffs\README.md') |
        Where-Object { Test-Path -LiteralPath (Join-Path $ctDst $_) }
    # A skipped folder must not take a same-prefixed neighbour with it.
    $dropped = @('install.ps1', 'pack\scripts\x.py', 'docs\AUDIT.md', '.gitignore', 'docs\handoffs-notes.md') |
        Where-Object { -not (Test-Path -LiteralPath (Join-Path $ctDst $_)) }
    if ($leaked) { Fail "install copy filter leaks into the profile: $($leaked -join ', ')" }
    elseif ($dropped) { Fail "install copy filter drops needed files: $($dropped -join ', ')" }
    else { Ok 'install copy filter excludes artifacts and keeps pack files' }

    # Stale-file detection decides what an install may delete from the profile, so the dangerous
    # case is a false positive: removing a rule or skill the user added themselves.
    $srcRoot = Join-Path $probe 'src'
    $instRoot = Join-Path $probe 'inst'
    $rulesDir = Join-Path $probe 'profile-rules'
    $skillsDir = Join-Path $probe 'profile-skills'
    foreach ($spec in @(
            @{ root = $srcRoot; rel = 'pack\rules\kept.mdc' },
            @{ root = $srcRoot; rel = 'pack\skills\kept-skill\SKILL.md' },
            @{ root = $srcRoot; rel = 'install.ps1' },
            @{ root = $instRoot; rel = 'install.ps1' },
            @{ root = $instRoot; rel = 'pack\scripts\dropped-by-pack.ps1' },
            @{ root = $instRoot; rel = 'install-manifest.json' },
            @{ root = $instRoot; rel = '.tmp\live-scratch.txt' },
            @{ root = $rulesDir; rel = 'kept.mdc' },
            @{ root = $rulesDir; rel = 'removed-from-pack.mdc' },
            @{ root = $rulesDir; rel = 'users-own.mdc' },
            @{ root = $skillsDir; rel = 'kept-skill\SKILL.md' },
            @{ root = $skillsDir; rel = 'users-own-skill\SKILL.md' })) {
        $full = Join-Path $spec.root $spec.rel
        $dir = Split-Path $full -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Write-Utf8NoBom $full 'x'
    }
    # What the previous install recorded shipping - the only basis for touching profile rules/skills.
    $prevManifest = [pscustomobject]@{
        rules  = @('kept.mdc', 'removed-from-pack.mdc')
        skills = @('kept-skill\SKILL.md')
    }
    $staleFound = @(Get-StaleInstalledFiles $srcRoot $instRoot $rulesDir $skillsDir $prevManifest)
    $staleRel = @($staleFound | ForEach-Object { Split-Path $_ -Leaf })
    if ($staleRel -notcontains 'dropped-by-pack.ps1') { Fail 'stale scan missed a file the pack stopped shipping' }
    elseif ($staleRel -notcontains 'removed-from-pack.mdc') { Fail 'stale scan missed a rule the pack stopped shipping - it would keep instructing agents' }
    elseif ($staleRel -contains 'users-own.mdc' -or $staleRel -contains 'users-own-skill') { Fail 'stale scan targets files the user added - install must never delete those' }
    elseif ($staleRel -contains 'kept.mdc' -or $staleRel -contains 'install.ps1') { Fail 'stale scan targets files the pack still ships' }
    elseif ($staleRel -contains 'install-manifest.json') { Fail 'stale scan targets the installer own manifest' }
    elseif ($staleRel -contains 'live-scratch.txt') { Fail 'stale scan targets .tmp scratch that a concurrent run may hold open' }
    else { Ok 'stale scan finds dropped pack files and spares user-added ones' }

    $noPrevious = @(Get-StaleInstalledFiles $srcRoot $instRoot $rulesDir $skillsDir $null)
    if (@($noPrevious | Where-Object { $_ -like "$rulesDir*" -or $_ -like "$skillsDir*" }).Count -gt 0) {
        Fail 'with no previous install record, the scan still targets profile rules/skills'
    } else { Ok 'no install record means no profile rule or skill is ever a prune candidate' }

    # install.ps1 runs Python out of the installed tree, then prunes what that leaves behind.
    $installText = Get-Content $installPs1 -Raw
    if ($installText -notmatch 'PYTHONDONTWRITEBYTECODE') { Fail 'install.ps1 no longer suppresses bytecode for its own Python steps' }
    elseif ($installText -notmatch "Filter\s+'__pycache__'") { Fail 'install.ps1 no longer prunes __pycache__ from the installed tree' }
    else { Ok 'install.ps1 keeps bytecode out of the installed tree' }

    # Every other script read the install-root override through pack-paths.ps1; install.ps1 alone
    # hardcoded %USERPROFILE%\.cursor, so asking for a scratch destination silently rewrote the real
    # profile - and no test could exercise a full install without doing that. Run the installer for
    # real against a scratch destination and prove the profile was not the one that moved.
    $redirectRoot = Join-Path $probe 'redirect\cursor\AgentStarterPack'
    # Hash only what an install owns. The first version of this check stamped all of %USERPROFILE%\.cursor
    # and went flaky: the running editor writes there constantly, so an unrelated write looked like the
    # installer escaping its redirect.
    $realProfileCursor = Join-Path $env:USERPROFILE '.cursor'
    function Get-ProfileInstallStamp($cursorDir) {
        @(@(Join-Path $cursorDir 'AgentStarterPack\install-manifest.json'), (Join-Path $cursorDir 'mcp.json')) |
            ForEach-Object {
                if (Test-Path -LiteralPath $_) { "$(Split-Path $_ -Leaf)|$((Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash)" }
                else { "$(Split-Path $_ -Leaf)|absent" }
            }
    }
    $realStamp = (Get-ProfileInstallStamp $realProfileCursor) -join ';'
    $prevOverride = $env:AGENT_STARTER_PACK_INSTALL_ROOT
    try {
        $env:AGENT_STARTER_PACK_INSTALL_ROOT = $redirectRoot
        # -SkipPreflight: the redirect is what is under test, and preflight spawns Python whose child
        # can outlive this step and hold the probe tree open when cleanup runs.
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $installPs1 -Scope User -NoPause -SkipPreflight *> $null
    } finally {
        $env:AGENT_STARTER_PACK_INSTALL_ROOT = $prevOverride
    }
    $redirectManifest = Join-Path $redirectRoot 'install-manifest.json'
    $realStampAfter = (Get-ProfileInstallStamp $realProfileCursor) -join ';'
    if (-not (Test-Path -LiteralPath (Join-Path $redirectRoot 'pack\audit\manifest.json'))) {
        Fail 'install ignored AGENT_STARTER_PACK_INSTALL_ROOT - the pack tree did not land in the scratch destination'
    } elseif (-not (Test-Path -LiteralPath (Join-Path $redirectRoot '..\rules'))) {
        Fail 'install redirected the pack tree but left rules pointing at the real profile'
    } elseif ((Get-Content $redirectManifest -Raw | ConvertFrom-Json).canonical -ne $redirectRoot) {
        Fail 'install recorded a canonical root other than the redirected destination'
    } elseif ($realStamp -ne $realStampAfter) {
        Fail 'a redirected install still rewrote the real profile install record or mcp.json'
    } else { Ok 'install honours AGENT_STARTER_PACK_INSTALL_ROOT for pack, rules and skills' }
} catch {
    Fail "installer profile-write checks error: $_"
} finally {
    # This step now runs a real install, and a Python child from it can still hold a file open for a
    # moment after the installer returns. A single delete attempt then leaves an installer-probe-*
    # folder behind under .tmp, which the audit's own cruft check later reports.
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        if (-not (Test-Path -LiteralPath $probe)) { break }
        Remove-Item $probe -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $probe) { Start-Sleep -Milliseconds 500 }
    }
    if (Test-Path -LiteralPath $probe) {
        Write-Host "  [WARN] could not remove probe tree $probe - a child process may still hold it" -ForegroundColor Yellow
    }
}

Write-Host '27. Agent context refresh (stamp, change detection, pack vs app brief)'
# The brief is only worth pasting if it is true: versions must come off the pack at generation time
# and changedLayers must move when the pack moves. Both are checked against a scratch pack tree so
# the test never depends on this machine's install or on editing the real rules.
$ctxProbe = Join-Path $PackRoot ".tmp\context-probe-$PID"
$savedInstallRoot = $env:AGENT_STARTER_PACK_INSTALL_ROOT
try {
    $refreshPs1 = Join-Path $PackRoot 'pack\scripts\refresh-agent-context.ps1'
    if (-not (Test-Path $refreshPs1)) { throw "refresh-agent-context.ps1 not found at $refreshPs1" }

    $fakePack = Join-Path $ctxProbe 'pack-src'
    $appProj = Join-Path $ctxProbe 'app-proj'
    $packProj = Join-Path $ctxProbe 'pack-proj'
    New-Item -ItemType Directory -Path (Join-Path $fakePack 'pack\rules') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fakePack 'pack\audit') -Force | Out-Null
    New-Item -ItemType Directory -Path $appProj -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $packProj 'pack\audit') -Force | Out-Null
    Write-Utf8NoBom (Join-Path $fakePack 'VERSION') "9.9.9`r`n"
    Write-Utf8NoBom (Join-Path $fakePack 'pack\audit\manifest.json') '{ "version": "9.9.9-audit" }'
    Write-Utf8NoBom (Join-Path $fakePack 'pack\rules\probe-rule.mdc') "# probe`r`n"
    Write-Utf8NoBom (Join-Path $appProj 'AGENTS.md') "# app`r`n"
    Write-Utf8NoBom (Join-Path $packProj 'AGENTS.md') "# pack`r`n"
    Write-Utf8NoBom (Join-Path $packProj 'install.ps1') "# marker`r`n"
    Write-Utf8NoBom (Join-Path $packProj 'pack\audit\manifest.json') '{ "version": "9.9.9-audit" }'
    # No installed pack in scope: keeps the layer state deterministic on any machine.
    $env:AGENT_STARTER_PACK_INSTALL_ROOT = (Join-Path $ctxProbe 'no-install')

    function Invoke-Refresh([string]$Proj) {
        # -NoClipboard: a test must not reach into the user's clipboard.
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $refreshPs1 `
            -ProjectRoot $Proj -PackRoot $fakePack -SkipProjectSync -NoClipboard 2>&1 | Out-Null
        return $LASTEXITCODE
    }
    function Get-Ctx([string]$Proj) {
        Get-Content (Join-Path $Proj 'docs\AGENT_CONTEXT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $rc = Invoke-Refresh $appProj
    $ctxFile = Join-Path $appProj 'docs\AGENT_CONTEXT.json'
    $mdFile = Join-Path $appProj 'docs\AGENT_REFRESH.md'
    if ($rc -ne 0) { Fail "refresh exited $rc on a project with no prior stamp" }
    elseif (-not (Test-Path $ctxFile) -or -not (Test-Path $mdFile)) {
        Fail 'refresh did not write both docs/AGENT_CONTEXT.json and docs/AGENT_REFRESH.md'
    } else { Ok 'refresh writes both artifacts and exits 0' }

    if (Test-Path $ctxFile) {
        $c1 = Get-Ctx $appProj
        $missing = @('schemaVersion', 'packVersion', 'auditEngineVersion', 'rulesRevision', 'syncedAt',
            'layers', 'changedLayers', 'canonicalProjectRoot', 'requiredReads', 'triggerPhrases', 'handshake') |
            Where-Object { -not ($c1.PSObject.Properties.Name -contains $_) }
        if ($missing) { Fail "stamp is missing field(s): $($missing -join ', ')" }
        elseif ($c1.schemaVersion -ne 2) { Fail "stamp schemaVersion is $($c1.schemaVersion), expected 2" }
        elseif ($c1.packVersion -ne '9.9.9' -or $c1.auditEngineVersion -ne '9.9.9-audit') {
            Fail "stamp did not read versions from the pack (got $($c1.packVersion) / $($c1.auditEngineVersion))"
        } elseif (@($c1.changedLayers) -notcontains 'firstRefresh') {
            Fail 'first refresh is not reported as a first refresh'
        } elseif (@($c1.requiredReads) -notcontains (Join-Path $appProj 'AGENTS.md')) {
            Fail 'requiredReads missing absolute AGENTS.md path'
        } elseif (@($c1.triggerPhrases) -notcontains 'refresh pack context') {
            Fail 'triggerPhrases missing refresh pack context'
        } else { Ok 'stamp carries v2 schema, absolute requiredReads, and trigger phrases' }

        # A paste line with a hardcoded version is worse than none - it is confidently wrong.
        $md1 = Get-Content $mdFile -Raw
        if ($md1 -notmatch '9\.9\.9' -or $md1 -notmatch '9\.9\.9-audit') {
            Fail 'brief does not carry the pack versions it was generated from'
        } elseif ($md1 -notmatch '(?m)^PACK CONTEXT REFRESHED ') {
            Fail 'brief has no paste line for a stale chat'
        } else { Ok 'brief carries generated-at versions and a paste line' }

        # The paste line is the deliverable, and copying it is where this goes wrong for users:
        # a wrapped console selection picks up breaks, and non-ASCII survives a chat box badly.
        $pasteFile = Join-Path $appProj 'docs\AGENT_PASTE.txt'
        if (-not (Test-Path $pasteFile)) { Fail 'refresh did not write docs/AGENT_PASTE.txt' }
        else {
            $pasteRaw = [System.IO.File]::ReadAllText($pasteFile)
            $pasteBytes = [System.IO.File]::ReadAllBytes($pasteFile)
            $hasBom = ($pasteBytes.Length -ge 3 -and $pasteBytes[0] -eq 0xEF -and $pasteBytes[1] -eq 0xBB)
            if ($pasteRaw -match '[\r\n]') { Fail 'paste file is not a single line' }
            elseif ($pasteRaw -ne $pasteRaw.Trim()) { Fail 'paste file has leading or trailing whitespace' }
            elseif ($hasBom) { Fail 'paste file has a BOM - it would paste as a stray character' }
            elseif ($pasteRaw -match '[^\x20-\x7E]') { Fail 'paste line contains non-ASCII characters' }
            elseif ($pasteRaw -notmatch '9\.9\.9' -or $pasteRaw -notmatch [regex]::Escape($appProj)) {
                Fail 'paste line is missing the version or the absolute project path'
            } elseif ($pasteRaw -notmatch 'Confirm by replying') {
                Fail 'paste line does not ask the agent to prove it read the files'
            } else {
                $briefLine = ([regex]::Match($md1, '(?m)^PACK CONTEXT REFRESHED [^\r\n]*')).Value
                if ($pasteRaw -ne $briefLine) {
                    Fail 'paste file and brief disagree on the paste line'
                } else { Ok 'paste line is one ASCII line, BOM-free, and matches the brief' }
            }
        }

        Start-Sleep -Milliseconds 20
        [void](Invoke-Refresh $appProj)
        $c2 = Get-Ctx $appProj
        if (@($c2.changedLayers).Count -ne 0) {
            Fail "re-running with an unchanged pack reports changes: $(@($c2.changedLayers) -join ', ')"
        } elseif ($c2.syncedAt -eq $c1.syncedAt -or $c2.previousSyncedAt -ne $c1.syncedAt) {
            Fail 'second refresh did not advance syncedAt / carry previousSyncedAt'
        } else { Ok 'unchanged pack reports no changes but still restamps' }

        Write-Utf8NoBom (Join-Path $fakePack 'pack\rules\probe-rule.mdc') "# probe edited`r`n"
        [void](Invoke-Refresh $appProj)
        $c3 = Get-Ctx $appProj
        if (@($c3.changedLayers) -notcontains 'rules') { Fail 'edited rule text did not surface as a changed layer' }
        elseif ($c3.rulesRevision -eq $c2.rulesRevision) { Fail 'rulesRevision did not move when a rule changed' }
        else { Ok 'rule edits move rulesRevision and are reported' }

        # Two layers at once, so the next assertion can prove the paste line does not grow per change.
        Write-Utf8NoBom (Join-Path $fakePack 'VERSION') "9.9.10`r`n"
        Write-Utf8NoBom (Join-Path $fakePack 'pack\rules\probe-rule.mdc') "# probe edited twice`r`n"
        [void](Invoke-Refresh $appProj)
        $c4 = Get-Ctx $appProj
        $md4 = Get-Content $mdFile -Raw
        if (@($c4.changedLayers) -notcontains 'packVersion') { Fail 'pack version bump was not reported' }
        elseif ($md4 -notmatch '9\.9\.10') { Fail 'brief still cites the previous pack version' }
        else { Ok 'version bumps are reported and re-cited in the brief' }

        # The paste line must stay a pointer. An update notice that grows an entry per change becomes a
        # document, and a pasted document is what makes agents skim or stall - the whole reason the
        # change list lives in the brief, which the agent opens itself.
        $pasteMulti = [System.IO.File]::ReadAllText((Join-Path $appProj 'docs\AGENT_PASTE.txt'))
        $changeProse = @('Pack version is now', 'Audit engine is now', 'Generic rule text changed',
            'were reinstalled', 'audit templates were updated')
        $leaked = @($changeProse | Where-Object { $pasteMulti -like "*$_*" })
        if (@($c4.changedLayers).Count -lt 2) {
            Fail 'probe did not produce a multi-change refresh, so paste growth is untested'
        } elseif ($leaked.Count -gt 0) {
            Fail "paste line enumerates changes instead of pointing at the brief: $($leaked -join '; ')"
        } elseif ($pasteMulti -match '[\r\n]') {
            Fail 'paste line grew past one line on a multi-change refresh'
        } elseif ($pasteMulti.Length -gt 600) {
            Fail "paste line is $($pasteMulti.Length) chars - a pointer should stay well under 600"
        } else {
            Ok "paste stays one line ($($pasteMulti.Length) chars) with $(@($c4.changedLayers).Count) layers changed"
        }
    }

    [void](Invoke-Refresh $packProj)
    $packMd = Get-Content (Join-Path $packProj 'docs\AGENT_REFRESH.md') -Raw
    $appMd = Get-Content $mdFile -Raw
    # Sending an app agent into the pack's handoff is the failure this split exists to prevent.
    if ($packMd -notmatch '(?m)^\d+\. .*HANDOFF_NEXT_AGENT\.md') {
        Fail 'pack-repo brief does not list HANDOFF_NEXT_AGENT.md as required reading'
    } elseif ($appMd -match '(?m)^\d+\. .*HANDOFF_NEXT_AGENT\.md') {
        Fail 'app brief sends the agent to the pack handoff'
    } elseif ((Get-Ctx $packProj).isPackRepo -ne $true) {
        Fail 'pack repo was not detected as a pack repo'
    } else { Ok 'pack and app briefs point at different required reading' }

    $rulePath = Join-Path $PackRoot 'pack\rules\agent-defaults-always.mdc'
    $ruleText = if (Test-Path $rulePath) { Get-Content $rulePath -Raw } else { '' }
    $manifestText = Get-Content (Join-Path $PackRoot 'pack\audit\manifest.json') -Raw
    if ($ruleText -notmatch 'refresh pack context') {
        Fail 'agent-defaults-always.mdc lost the context-refresh trigger phrase'
    } elseif ($ruleText -notmatch 'AGENT_REFRESH\.md') {
        Fail 'context-refresh trigger does not name docs/AGENT_REFRESH.md'
    } elseif ($manifestText -notmatch 'refresh-agent-context\.ps1') {
        Fail 'refresh-agent-context.ps1 is not tracked in the audit manifest'
    } else { Ok 'trigger phrase and manifest tracking are in place' }
} catch {
    Fail "agent context refresh checks error: $_"
} finally {
    if ($null -eq $savedInstallRoot) {
        Remove-Item Env:\AGENT_STARTER_PACK_INSTALL_ROOT -ErrorAction SilentlyContinue
    } else { $env:AGENT_STARTER_PACK_INSTALL_ROOT = $savedInstallRoot }
    Remove-Item $ctxProbe -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host '28. Layout hygiene reports Improve, not delete-only Fix'
# The failure this closes: Section B only ever said "delete dist", so an agent could delete it, close
# the section, and never look at whether the tree is comprehensible. Layout findings must arrive as
# Improve, in their own manifest channel, and must not be answerable with "Nothing found."
$layoutDirs = @('MyApp_v6', 'MyApp_v6\MyApp_portable', 'MyApp_portable', 'MyApp_v6_stable', 'build')
$layoutScript = Join-Path $fixture 'scripts\publish_release.bat'
$semBackup = $null
$semLayoutPath = Join-Path $fixture 'docs\.audit_semantic_report.json'
try {
    if (Test-Path $semLayoutPath) { $semBackup = Get-Content $semLayoutPath -Raw }
    foreach ($d in $layoutDirs) { New-Item -ItemType Directory -Path (Join-Path $fixture $d) -Force | Out-Null }
    Write-Utf8NoBom (Join-Path $fixture 'MyApp_v6\MyApp.exe.txt') "placeholder`r`n"
    Write-Utf8NoBom (Join-Path $fixture 'MyApp_v6_stable\MyApp.exe.txt') "placeholder`r`n"
    Write-Utf8NoBom $layoutScript "@echo off`r`nREM fixture only`r`n"

    $layoutOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 `
        -RepoRoot $PackRoot -AppRoot $fixture -SkipTests 2>&1 | Out-String
    $fixBlock = if ($layoutOut -match '(?s)Fix\s*\r?\n(.*?)(?:Improve|$)') { $Matches[1] } else { '' }

    $expected = @{
        'duplicate stable copy'  = 'duplicate stable copy in repo'
        'ephemeral build dir'    = 'build present \(expected after a build\)'
        'dual-role data dirname' = 'MyApp_portable exists both beside the source tree'
        'contradiction script'   = 'publish_release\.bat'
    }
    $missing = @($expected.Keys | Where-Object { $layoutOut -notmatch $expected[$_] })
    if ($missing.Count -gt 0) { Fail "layout policy did not report: $($missing -join ', ')" }
    else { Ok 'layout policy reports glossary/duplicate/ephemeral/contradiction findings' }

    # Reporting them as Fix would just be a longer delete list.
    if ($fixBlock -match 'Layout - ') { Fail 'layout findings landed in Fix instead of Improve' }
    else { Ok 'layout findings are Improve, not Fix' }

    $layoutMan = Get-Content (Join-Path $fixture 'docs\.audit_agent_manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $improvesB = @()
    if ($layoutMan.machineImprovesBySection -and $layoutMan.machineImprovesBySection.B) {
        $improvesB = @($layoutMan.machineImprovesBySection.B)
    }
    if ($improvesB.Count -lt 3) {
        Fail "machineImprovesBySection.B carries $($improvesB.Count) line(s); expected the layout findings"
    } elseif (@($layoutMan.machineSectionsWithImproves) -notcontains 'B') {
        Fail 'machineSectionsWithImproves does not list B'
    } else { Ok "machineImprovesBySection.B carries $($improvesB.Count) layout line(s)" }

    # A section with machine Improve lines cannot be closed as clean, and a summary that never
    # mentions them is the same miss with more words.
    & py -3 $codePy $fixture --write-semantic-template 2>&1 | Out-Null
    & py -3 $codePy $fixture --fill-semantic-fixture-test 2>&1 | Out-Null
    if (Test-Path $semLayoutPath) {
        $sem = Get-Content $semLayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $sem.sections.B.summary = 'Nothing found.'
        Write-Utf8NoBom $semLayoutPath ($sem | ConvertTo-Json -Depth 12)
        $vOut = & py -3 $codePy $fixture --verify-semantic-report 2>&1 | Out-String
        # Match the message, not the exit code: an unrelated failure would otherwise pass this.
        $rejected = ($vOut -match 'section B does not address \d+ machine Improve line')
        $sem.sections.B.summary = 'Reviewed layout: MyApp_v6_stable duplicates the release archive; build is ephemeral. Improve only, see `docs/AUDIT.md`.'
        Write-Utf8NoBom $semLayoutPath ($sem | ConvertTo-Json -Depth 12)
        $vOut2 = & py -3 $codePy $fixture --verify-semantic-report 2>&1 | Out-String
        $acceptedB = ($vOut2 -notmatch 'section B does not address')
        if (-not $rejected) { Fail 'clean section B summary accepted while machine layout Improve lines exist' }
        elseif (-not $acceptedB) { Fail "summary naming the layout findings still rejected: $vOut2" }
        else { Ok 'section B must address machine Improve lines' }
    }
} catch {
    Fail "layout hygiene checks error: $_"
} finally {
    Remove-Item $layoutScript -Force -ErrorAction SilentlyContinue
    foreach ($d in @('MyApp_v6', 'MyApp_portable', 'MyApp_v6_stable', 'build')) {
        Remove-Item (Join-Path $fixture $d) -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($semBackup) { Write-Utf8NoBom $semLayoutPath $semBackup }
}

Write-Host "`n29. Cross-version parity (PowerShell 5.1 vs 7)"
# The pack's floor is 5.1 but nothing stops a maintainer running it on 7, and the one real behavioural
# split between the hosts is encoding: Set-Content -Encoding UTF8 writes a BOM on 5.1 and not on 7. A
# BOM in generated JSON crashes Python, so it broke every bootstrapped project's first audit. This
# proves the shared writer and the JSON round-trip produce byte-identical output on both hosts, rather
# than trusting that whichever host the maintainer happens to use is the one users have.
$parityDir = Join-Path $PackRoot ".tmp\parity-$PID"
try {
    $otherShell = if ($PSVersionTable.PSEdition -eq 'Core') {
        (Get-Command powershell -ErrorAction SilentlyContinue)
    } else {
        (Get-Command pwsh -ErrorAction SilentlyContinue)
    }
    if (-not $otherShell) {
        Write-Host '[SKIP] only one PowerShell host on this machine - install the other to test parity'
        Write-Host '       (pack floor is 5.1: winget install -e --id Microsoft.PowerShell adds 7)'
    } else {
        New-Item -ItemType Directory -Force -Path $parityDir | Out-Null
        $parityProbe = Join-Path $parityDir 'parity.ps1'
        # Asserted separately on purpose:
        #   writer  - our code, must be byte-identical across hosts
        #   json    - PowerShell's serializer, whose *formatting* legitimately differs (5.1 indents with
        #             its own alignment, 7 uses two spaces), so only the parsed data can be compared
        Write-Utf8NoBom $parityProbe @'
param([string]$PackPaths, [string]$WorkDir)
. $PackPaths
$tag = "$($PSVersionTable.PSEdition)"
$fixed = "first line`r`npath C:\x\y.json`r`nnumber 42`r`n"
$writerOut = Join-Path $WorkDir "writer-$tag.txt"
Write-Utf8NoBom $writerOut $fixed
$wb = [System.IO.File]::ReadAllBytes($writerOut)
$writerBom = ($wb.Length -ge 3 -and $wb[0] -eq 239 -and $wb[1] -eq 187 -and $wb[2] -eq 191)
$writerSha = (Get-FileHash -LiteralPath $writerOut -Algorithm SHA256).Hash
$obj = [pscustomobject]@{ mcpServers = [pscustomobject]@{ keep = [pscustomobject]@{ x = 1 } } }
$obj.mcpServers | Add-Member -NotePropertyName 'added' -NotePropertyValue ([pscustomobject]@{ y = 2 }) -Force
$jsonOut = Join-Path $WorkDir "json-$tag.json"
Write-Utf8NoBom $jsonOut ($obj | ConvertTo-Json -Depth 10)
$jb = [System.IO.File]::ReadAllBytes($jsonOut)
$jsonBom = ($jb.Length -ge 3 -and $jb[0] -eq 239 -and $jb[1] -eq 187 -and $jb[2] -eq 191)
$rt = Get-Content -LiteralPath $jsonOut -Raw -Encoding UTF8 | ConvertFrom-Json
$canon = (($rt.mcpServers.PSObject.Properties | Sort-Object Name |
    ForEach-Object { "$($_.Name)=$(($_.Value.PSObject.Properties | ForEach-Object { "$($_.Name):$($_.Value)" }) -join ',')" }) -join ';')
Write-Output "writerBom=$writerBom writerSha=$writerSha jsonBom=$jsonBom data=$canon"
'@
        $packPaths = Join-Path $PSScriptRoot 'pack-paths.ps1'
        $aOut = (Invoke-PackScript -PassOutput -NoProfile -ScriptPath $parityProbe -PackPaths $packPaths -WorkDir $parityDir 2>&1 | Out-String).Trim()
        $bOut = (& $otherShell.Source -NoProfile -ExecutionPolicy Bypass -File $parityProbe -PackPaths $packPaths -WorkDir $parityDir 2>&1 | Out-String).Trim()
        $otherName = Split-Path $otherShell.Source -Leaf
        if ($aOut -notmatch 'writerSha=' -or $bOut -notmatch 'writerSha=') {
            Fail "parity probe did not run on both hosts - 5.1: $aOut | ${otherName}: $bOut"
        } elseif ($aOut -match 'Bom=True' -or $bOut -match 'Bom=True') {
            Fail "a BOM was written - 5.1: $aOut | ${otherName}: $bOut"
        } elseif ($aOut -ne $bOut) {
            Fail "hosts disagree - 5.1: $aOut | ${otherName}: $bOut"
        } else {
            Ok "5.1 and $otherName agree: BOM-free, identical writer bytes, identical parsed JSON"
        }
    }

    # One writer, one implementation. Five near-copies of this existed, and they had already drifted:
    # only one created the parent directory, and the JSONL logger had its own append variant.
    $writerDefs = @(Select-String -Path (Join-Path $PSScriptRoot '*.ps1') -Pattern '^\s*function\s+(Write-Utf8NoBom|Write-TextNoBom|Set-TextNoBom)\b')
    $inlineWriters = @(Select-String -Path (Join-Path $PSScriptRoot '*.ps1'), (Join-Path $PackRoot '*.ps1') `
            -Pattern 'UTF8Encoding\(\$false\)' -ErrorAction SilentlyContinue |
        Where-Object { $_.Filename -ne 'pack-paths.ps1' })
    if ($writerDefs.Count -ne 1) {
        Fail "expected one BOM-free writer definition, found $($writerDefs.Count): $(($writerDefs | ForEach-Object { $_.Filename }) -join ', ')"
    } elseif ($writerDefs[0].Filename -ne 'pack-paths.ps1') {
        Fail "the writer should live in pack-paths.ps1, found it in $($writerDefs[0].Filename)"
    } elseif ($inlineWriters.Count -gt 0) {
        $where = ($inlineWriters | ForEach-Object { $_.Filename + ':' + $_.LineNumber }) -join ', '
        Fail "inline BOM-free writes bypass the shared helper: $where"
    } else { Ok 'exactly one BOM-free writer, in pack-paths.ps1, with no inline copies' }

    # Every script declares the floor, so nobody has to guess which host a script expects.
    $noFloor = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '*.ps1'), (Join-Path $PackRoot '*.ps1') -File |
        Where-Object { $_.Name -ne 'pack-paths.ps1' -and -not (Select-String -Path $_.FullName -Pattern '^#Requires' -Quiet) })
    if ($noFloor.Count -gt 0) {
        Fail "$($noFloor.Count) script(s) do not declare a version floor: $(($noFloor | ForEach-Object Name) -join ', ')"
    } else { Ok 'every pack script declares #Requires (pack-paths.ps1 is dot-sourced, so it is exempt)' }
} catch {
    Fail "cross-version parity checks error: $_"
} finally {
    Remove-Item $parityDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n30. Stale agent context surfaces in the audit, addressed to the agent"
# Before this, a project could sit for four pack updates with an agent reading rules the pack no longer
# ships, and the only way to find out was to run the refresh - the very thing the warning would have
# told you to run. So the stamp check lives where people already look, and its wording tells the agent
# to offer the run rather than handing the user a command. Asserted in both directions: a silent check
# that never fires is as useless as one that always does.
$ctxProbe = Join-Path $fixture 'docs\AGENT_CONTEXT.json'
$ctxBackup = if (Test-Path $ctxProbe) { Get-Content $ctxProbe -Raw } else { $null }
try {
    $engineVersion = (Get-Content (Join-Path $PackRoot 'pack\audit\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version

    # No stamp at all: a project that never bootstrapped one must not be nagged.
    Remove-Item $ctxProbe -Force -ErrorAction SilentlyContinue
    $noCtxOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 `
        -RepoRoot $PackRoot -AppRoot $fixture -SkipTests 2>&1 | Out-String
    if ($noCtxOut -match 'Agent context') { Fail 'audit nags about agent context on a project that has no stamp' }
    else { Ok 'no AGENT_CONTEXT.json means no agent-context line' }

    # Stamped behind the running engine: must report, as Improve, telling the agent to offer the run.
    Write-Utf8NoBom $ctxProbe "{`r`n  `"schemaVersion`": 1,`r`n  `"auditEngineVersion`": `"0.0.1`"`r`n}`r`n"
    $staleOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 `
        -RepoRoot $PackRoot -AppRoot $fixture -SkipTests 2>&1 | Out-String
    $staleFix = if ($staleOut -match '(?s)Fix\s*\r?\n(.*?)(?:Improve|$)') { $Matches[1] } else { '' }
    if ($staleOut -notmatch 'Agent context stale - stamped 0\.0\.1') {
        Fail 'stale agent context stamp did not surface in the audit'
    } elseif ($staleOut -notmatch [regex]::Escape($engineVersion)) {
        Fail 'stale agent context line does not name the engine version it is behind'
    } elseif ($staleFix -match 'Agent context') {
        Fail 'stale agent context landed in Fix; nothing is broken, so it belongs in Improve'
    } elseif ($staleOut -notmatch 'agent: offer to run Refresh-AgentContext\.cmd') {
        Fail 'agent-context line tells the user to run a command instead of telling the agent to offer'
    } else { Ok 'stale stamp reports as Improve and asks the agent to offer the run' }

    # Bootstrap stub with no version yet.
    Write-Utf8NoBom $ctxProbe "{`r`n  `"schemaVersion`": 1,`r`n  `"auditEngineVersion`": null`r`n}`r`n"
    $stubOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 `
        -RepoRoot $PackRoot -AppRoot $fixture -SkipTests 2>&1 | Out-String
    if ($stubOut -notmatch 'Agent context never refreshed') { Fail 'bootstrap stub stamp did not report as never refreshed' }
    else { Ok 'bootstrap stub reports as never refreshed' }

    # Current stamp: silent, so a refreshed project stays quiet and the line cannot become wallpaper.
    Write-Utf8NoBom $ctxProbe "{`r`n  `"schemaVersion`": 1,`r`n  `"auditEngineVersion`": `"$engineVersion`"`r`n}`r`n"
    $freshOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 `
        -RepoRoot $PackRoot -AppRoot $fixture -SkipTests 2>&1 | Out-String
    if ($freshOut -match 'Agent context') { Fail 'audit still reports agent context after a matching stamp' }
    else { Ok 'a current stamp clears the line' }

    # The instruction has to carry, or the audit line has no one to act on it - and it has to carry
    # outside Cursor. agent-defaults-always.mdc is a .mdc, which only Cursor reads; the first cut of
    # this feature put the instruction there alone, so a Claude, Copilot or Windsurf agent got the
    # audit line with none of the behaviour around it. The tool-neutral files are asserted alongside
    # it so "works on my editor" cannot pass this step.
    $offerPattern = 'offer to run `Refresh-AgentContext\.cmd`'
    $carriers = @{
        'pack\rules\agent-defaults-always.mdc'                = 'Cursor rule'
        'pack\templates\portable\AI_INSTRUCTIONS.md.template' = 'universal entry (all tools)'
        'pack\templates\AGENTS.md.template'                   = 'AGENTS.md (cross-tool entry)'
    }
    $noOffer = @($carriers.Keys | Where-Object {
        -not (Select-String -Path (Join-Path $PackRoot $_) -Pattern $offerPattern -Quiet)
    })
    if ($noOffer.Count -gt 0) {
        Fail "offer-to-run instruction missing from: $(($noOffer | ForEach-Object { "$_ ($($carriers[$_]))" }) -join ', ')"
    } else { Ok "offer-to-run instruction carried by all $($carriers.Count) layers, Cursor and tool-neutral" }
} catch {
    Fail "agent context freshness checks error: $_"
} finally {
    if ($ctxBackup) { Write-Utf8NoBom $ctxProbe $ctxBackup }
    else { Remove-Item $ctxProbe -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n31. Work queue ensure + verify (pack + behavior fixture)"
try {
    $ensureWq = Join-Path $PSScriptRoot 'ensure-work-queue.ps1'
    $verifyWq = Join-Path $PSScriptRoot 'verify-work-queue.ps1'
    if (-not (Test-Path -LiteralPath $ensureWq)) { Fail 'ensure-work-queue.ps1 missing' }
    elseif (-not (Test-Path -LiteralPath $verifyWq)) { Fail 'verify-work-queue.ps1 missing' }
    else {
        Remove-Item (Join-Path $fixture 'docs\WORK_QUEUE.md') -Force -ErrorAction SilentlyContinue
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $ensureWq -ProjectRoot $fixture -PackRoot $PackRoot 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'ensure-work-queue failed on behavior fixture' }
        else { Ok 'ensure-work-queue runs on fixture (creates or skips)' }
        $vqOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $verifyWq -ProjectRoot $PackRoot 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Fail "pack WORK_QUEUE invalid: $vqOut" }
        else { Ok 'pack WORK_QUEUE passes verify-work-queue.ps1' }
        if (-not (Test-Path (Join-Path $fixture 'docs\WORK_QUEUE.md'))) {
            Fail 'behavior fixture missing docs/WORK_QUEUE.md after ensure'
        } else { Ok 'behavior fixture has docs/WORK_QUEUE.md after ensure' }
        $fxOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $verifyWq -ProjectRoot $fixture 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Fail "fixture WORK_QUEUE invalid after ensure: $fxOut" }
        else { Ok 'fixture WORK_QUEUE passes verify-work-queue.ps1 after ensure' }
    }
} catch {
    Fail "work queue checks error: $_"
}

Write-Host "`n32. Portable rule/skill exports (multi-tool Phase 2)"
try {
    $portableSync = Join-Path $PSScriptRoot 'sync-portable-docs.ps1'
    if (-not (Test-Path -LiteralPath $portableSync)) { Fail 'sync-portable-docs.ps1 missing' }
    else {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $portableSync -PackRoot $PackRoot -VerifyOnly 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'portable exports stale or missing (run sync-portable-docs.ps1)' }
        else { Ok 'portable GENERIC_RULES.md and skill mirrors match pack/rules and pack/skills' }
    }
} catch {
    Fail "portable export checks error: $_"
}

Write-Host "`n33. Portable bootstrap (-Targets Portable)"
try {
    $portableVerify = Join-Path $PSScriptRoot 'verify-portable-bootstrap.ps1'
    $bootstrap = Join-Path $PackRoot 'pack\scripts\bootstrap-project.ps1'
    if (-not (Test-Path -LiteralPath $portableVerify)) { Fail 'verify-portable-bootstrap.ps1 missing' }
    elseif (-not (Test-Path -LiteralPath $bootstrap)) { Fail 'bootstrap-project.ps1 missing' }
    else {
        $portableRoot = Join-Path $PackRoot ".tmp\bootstrap-portable-$PID"
        $portableProj = Join-Path $portableRoot 'PortableApp'
        if (Test-Path -LiteralPath $portableRoot) { Remove-Item -LiteralPath $portableRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $portableRoot -Force | Out-Null
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $bootstrap -ProjectRoot $portableProj `
            -ProjectName 'PortableApp' -Stack Generic -Targets Portable -NoPause 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "Portable bootstrap exited $LASTEXITCODE" }
        else { Ok 'Portable bootstrap exits 0' }
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $portableVerify -ProjectRoot $portableProj -RequirePortableOnly 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'verify-portable-bootstrap failed on Portable target project' }
        else { Ok 'Portable bootstrap matches verify-portable-bootstrap profile' }
        Remove-Item -LiteralPath $portableRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    Fail "Portable bootstrap checks error: $_"
}

Write-Host "`n34. Tool adapter register (Claude/Copilot/Windsurf)"
try {
    $adapterScript = Join-Path $PSScriptRoot 'register-tool-adapters.ps1'
    $bootstrap = Join-Path $PackRoot 'pack\scripts\bootstrap-project.ps1'
    if (-not (Test-Path -LiteralPath $adapterScript)) { Fail 'register-tool-adapters.ps1 missing' }
    elseif (-not (Test-Path -LiteralPath $bootstrap)) { Fail 'bootstrap-project.ps1 missing' }
    else {
        $adapterRoot = Join-Path $PackRoot ".tmp\bootstrap-adapters-$PID"
        $adapterProj = Join-Path $adapterRoot 'AdapterApp'
        if (Test-Path -LiteralPath $adapterRoot) { Remove-Item -LiteralPath $adapterRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $adapterRoot -Force | Out-Null
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $bootstrap -ProjectRoot $adapterProj `
            -ProjectName 'AdapterApp' -Stack Generic -Targets @('Claude','Copilot','Windsurf') -NoPause 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "editor-target bootstrap exited $LASTEXITCODE" }
        else { Ok 'Claude/Copilot/Windsurf bootstrap exits 0' }
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $adapterScript -ProjectRoot $adapterProj -Tool All -NoPause 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'register-tool-adapters failed on editor-target project' }
        else { Ok 'register-tool-adapters passes on Claude/Copilot/Windsurf project' }
        Remove-Item -LiteralPath $adapterRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    Fail "Tool adapter checks error: $_"
}

Write-Host "`n35. Agent context freshness MCP module (Phase 6b)"
try {
    $freshPy = Join-Path $PSScriptRoot 'agent_context_freshness.py'
    if (-not (Test-Path -LiteralPath $freshPy)) { Fail 'agent_context_freshness.py missing' }
    else {
        $selfOut = & py -3 $freshPy --self-test 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Fail "agent_context_freshness self-test failed: $selfOut" }
        else { Ok 'agent_context_freshness.py self-test passes' }
        $mcpPy = Join-Path $PackRoot 'mcp\agent_hygiene_server.py'
        if (-not (Test-Path -LiteralPath $mcpPy)) { Fail 'agent_hygiene_server.py missing' }
        elseif (-not (Select-String -Path $mcpPy -Pattern 'check_pack_freshness' -Quiet)) {
            Fail 'MCP server missing check_pack_freshness tool'
        } elseif (-not (Select-String -Path $mcpPy -Pattern 'get_agent_refresh_brief' -Quiet)) {
            Fail 'MCP server missing get_agent_refresh_brief tool'
        } else { Ok 'MCP server exposes pack freshness tools' }
        $stackCmd = Join-Path $PackRoot 'Update-AgentStack.cmd'
        if (-not (Test-Path -LiteralPath $stackCmd)) { Fail 'Update-AgentStack.cmd missing at pack root' }
        else { Ok 'Update-AgentStack.cmd entry point present' }
    }
} catch {
    Fail "agent context MCP checks error: $_"
}

Write-Host "`n36. Handoff archive script (preview default, Apply gated)"
try {
    $archiveScript = Join-Path $PSScriptRoot 'archive-completed-handoff.ps1'
    if (-not (Test-Path -LiteralPath $archiveScript)) { Fail 'archive-completed-handoff.ps1 missing' }
    elseif (-not (Test-Path -LiteralPath (Join-Path $PackRoot 'pack\docs\WORK_COMPLETION.md'))) {
        Fail 'pack/docs/WORK_COMPLETION.md missing'
    } else {
        $probeRoot = Join-Path $PackRoot ".tmp\archive-probe-$PID"
        if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path (Join-Path $probeRoot 'docs\handoffs\active') -Force | Out-Null
        $handoffName = 'HANDOFF_WQ099_probe.md'
        $handoffPath = Join-Path $probeRoot "docs\handoffs\active\$handoffName"
        $wqPath = Join-Path $probeRoot 'docs\WORK_QUEUE.md'

        function Write-ProbeHandoff([string]$status, [string]$completedDate) {
            $body = @"
# Handoff - probe

## Handoff registry

| Field | Value |
|-------|-------|
| **handoff_id** | HANDOFF_WQ099 |
| **kind** | build |
| **status** | $status |
| **multi_agent** | no |
| **wq_id** | WQ-099 |
| **plan** | probe |
| **phases** | P1 |
| **agents_remaining** | |
| **completed** | $completedDate |

**Session opener (only - give the other agent this single line):**

`Read C:\probe\docs\handoffs\active\HANDOFF_WQ099_probe.md and implement.`

---
"@
            Write-Utf8NoBom -Path $handoffPath -Text $body
        }

        function Write-ProbeWq([bool]$done) {
            if ($done) {
                Write-Utf8NoBom -Path $wqPath -Text @"
# Work queue - probe

## Active queue

| ID | Task | Status | Notes |
|----|------|--------|-------|

## Done log

| ID | Task | Completed | Evidence |
|----|------|-----------|----------|
| WQ-099 | probe | 2026-01-01 | tests |
"@
            } else {
                Write-Utf8NoBom -Path $wqPath -Text @"
# Work queue - probe

## Active queue

| ID | Task | Status | Notes |
|----|------|--------|-------|
| WQ-099 | probe | **Next** | |

## Done log

| ID | Task | Completed | Evidence |
|----|------|-----------|----------|
"@
            }
        }

        Write-ProbeHandoff 'active' ''
        Write-ProbeWq $false

        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $archiveScript -ProjectRoot $probeRoot -SkipVerify 2>&1 | Out-Null
        if (-not (Test-Path -LiteralPath $handoffPath)) { Fail 'preview removed active handoff file' }
        else { Ok 'preview leaves active handoff in place' }

        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $archiveScript -ProjectRoot $probeRoot -Apply -SkipVerify 2>&1 | Out-Null
        if (-not (Test-Path -LiteralPath $handoffPath)) { Fail '-Apply moved handoff while status still active' }
        else { Ok '-Apply refuses active handoff' }

        Write-ProbeHandoff 'completed' ''
        Write-ProbeWq $true
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $archiveScript -ProjectRoot $probeRoot -Apply -SkipVerify 2>&1 | Out-Null
        if (-not (Test-Path -LiteralPath $handoffPath)) { Fail '-Apply moved handoff without completed: date' }
        else { Ok '-Apply refuses when completed: date empty' }

        Write-ProbeHandoff 'completed' '2026-01-01'
        Write-ProbeWq $true
        $previewOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $archiveScript -ProjectRoot $probeRoot -SkipVerify 2>&1 | Out-String
        if ($previewOut -notmatch 'PREVIEW|Would move') { Fail 'preview did not report eligible move' }
        elseif (-not (Test-Path -LiteralPath $handoffPath)) { Fail 'preview removed file before -Apply' }
        else { Ok 'preview reports eligible move but keeps file' }

        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $archiveScript -ProjectRoot $probeRoot -Apply -SkipVerify 2>&1 | Out-Null
        $archPath = Join-Path $probeRoot "docs\handoff_archive\$handoffName"
        if (Test-Path -LiteralPath $handoffPath) { Fail '-Apply did not move handoff when all gates pass' }
        elseif (-not (Test-Path -LiteralPath $archPath)) { Fail 'handoff missing from handoff_archive after -Apply' }
        else { Ok '-Apply moves to handoff_archive when all gates pass' }

        New-Item -ItemType Directory -Path (Join-Path $probeRoot 'docs\handoffs\active') -Force | Out-Null
        Write-ProbeHandoff 'completed' '2026-01-01'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $archiveScript -ProjectRoot $probeRoot -Apply -SkipVerify 2>&1 | Out-Null
        if (-not (Test-Path -LiteralPath $archPath)) { Fail 'second apply removed archive copy' }
        else { Ok 'second -Apply skips when archive file already exists' }
    }
} catch {
    Fail "handoff archive script checks error: $_"
} finally {
    Remove-Item (Join-Path $PackRoot ".tmp\archive-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n37. Complete-picture handoff verify (WQ-206)"
try {
    $cpScript = Join-Path $PSScriptRoot 'verify-complete-picture.ps1'
    if (-not (Test-Path -LiteralPath $cpScript)) { Fail 'verify-complete-picture.ps1 missing' }
    else {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $cpScript -ProjectRoot $PackRoot 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'pack repo failed verify-complete-picture.ps1' }
        else { Ok 'pack repo passes complete-picture handoff checks' }
        $probeRoot = Join-Path $PackRoot ".tmp\complete-picture-probe-$PID"
        if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path (Join-Path $probeRoot 'docs') -Force | Out-Null
        $badHandoff = @"
# Handoff probe

## 11. Recommended next steps

1. **Implement Agent Context Refresh (Phase 1)**
2. **Next:** WQ-999 old task

---

## 12. Pitfalls
"@
        Write-Utf8NoBom (Join-Path $probeRoot 'HANDOFF_PROBE.md') $badHandoff
        Write-Utf8NoBom (Join-Path $probeRoot 'docs\WORK_QUEUE.md') @"
# Work queue probe

## Active queue

| ID | Task | Status | Notes |
|----|------|--------|-------|
| WQ-001 | live | **Next** | |

## Done log

| ID | Task | Completed | Evidence |
|----|------|-----------|----------|
| WQ-999 | old | 2026-01-01 | done |
"@
        Rename-Item (Join-Path $probeRoot 'HANDOFF_PROBE.md') 'HANDOFF_NEXT_AGENT.md'
        $auditOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $cpScript -ProjectRoot $probeRoot -AuditMode 2>&1 | Out-String
        if ($auditOut -notmatch '\[IMPROVE\]') { Fail 'AuditMode did not report stale HANDOFF Improve' }
        else { Ok 'AuditMode flags stale section 11 phrases' }
    }
} catch {
    Fail "complete-picture checks error: $_"
} finally {
    Remove-Item (Join-Path $PackRoot ".tmp\complete-picture-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n38. Agent session-start freshness (WQ-308 Phase D1)"
# This step used to measure the probe's stamp against whatever pack happened to be installed in the
# real %USERPROFILE%, so its result depended on the machine: green where the profile matched the source
# pack, green on CI where nothing is installed at all, and red on a machine carrying an older install.
# The probe now redirects the install root at a scratch manifest, so "fresh" and "stale" are both
# properties of the fixture rather than of the developer's profile.
$prevFreshInstall = $env:AGENT_STARTER_PACK_INSTALL_ROOT
# The generated Cursor hook resolves its pack from AGENT_STARTER_PACK_ROOT, falling back to the
# installed copy in the profile - so without this the hook assertion ran the *installed* pack's
# freshness module, not the one in this checkout. On a machine whose install was several versions
# behind, the step was grading code that is not under test.
$prevFreshSource = $env:AGENT_STARTER_PACK_ROOT
$env:AGENT_STARTER_PACK_ROOT = $PackRoot
try {
    $freshPy = Join-Path $PSScriptRoot 'agent_context_freshness.py'
    $invokeFresh = Join-Path $PSScriptRoot 'invoke-agent-freshness.ps1'
    if (-not (Test-Path -LiteralPath $freshPy)) { Fail 'agent_context_freshness.py missing' }
    elseif (-not (Test-Path -LiteralPath $invokeFresh)) { Fail 'invoke-agent-freshness.ps1 missing' }
    else {
        $probeRoot = Join-Path $PackRoot ".tmp\session-start-probe-$PID"
        if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path (Join-Path $probeRoot 'docs') -Force | Out-Null
        Write-Utf8NoBom -Path (Join-Path $probeRoot 'AGENTS.md') -Text "# probe`r`n"
        $engine = (Get-Content -LiteralPath (Join-Path $PackRoot 'pack\audit\manifest.json') -Raw | ConvertFrom-Json).version
        $freshInstall = Join-Path $probeRoot 'installed-fresh'
        New-Item -ItemType Directory -Path (Join-Path $freshInstall 'pack\audit') -Force | Out-Null
        Write-Utf8NoBom -Path (Join-Path $freshInstall 'pack\audit\manifest.json') -Text "{`"version`": `"$engine`"}`r`n"
        $env:AGENT_STARTER_PACK_INSTALL_ROOT = $freshInstall
        Write-Utf8NoBom -Path (Join-Path $probeRoot 'docs\AGENT_CONTEXT.json') -Text (@{
            schemaVersion = 2
            auditEngineVersion = [string]$engine
            packVersion = '1.8.0'
            canonicalProjectRoot = $probeRoot
            requiredReads = @((Join-Path $probeRoot 'AGENTS.md'))
            layers = @{ installedPack = 'ok' }
        } | ConvertTo-Json -Depth 4)

        $briefJson = & py -3 $freshPy --session-brief --project-root $probeRoot 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Fail "session-brief failed: $briefJson" }
        else {
            $brief = $briefJson | ConvertFrom-Json
            if ($brief.stale) { Fail 'fresh stamp should not be stale in session-brief probe' }
            elseif ($brief.permission -ne 'none') { Fail 'fresh session-brief permission should be none' }
            elseif (-not $brief.openerLine) { Fail 'session-brief missing openerLine' }
            else { Ok 'session-brief JSON for fresh context' }
        }

        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $invokeFresh -ProjectRoot $probeRoot -WriteSessionStart 2>&1 | Out-Null
        $ssoPath = Join-Path $probeRoot 'docs\AGENT_SESSION_START.md'
        if ($LASTEXITCODE -ne 0) { Fail 'invoke-agent-freshness -WriteSessionStart failed' }
        elseif (-not (Test-Path -LiteralPath $ssoPath)) { Fail 'AGENT_SESSION_START.md not written' }
        else {
            $sso = Get-Content -LiteralPath $ssoPath -Raw
            if ($sso -notmatch 'Context: OK') { Fail 'session start file should show OK for fresh context' }
            elseif ($sso -notmatch 'user verifies') { Fail 'session start file missing execute/verify discipline' }
            else { Ok 'AGENT_SESSION_START.md written for fresh context (incl. execute/verify)' }
        }

        $opener = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $invokeFresh -ProjectRoot $probeRoot -PrintOpener 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Fail 'invoke-agent-freshness -PrintOpener failed' }
        elseif ($opener.Trim().Length -lt 10) { Fail 'PrintOpener returned empty line' }
        else { Ok 'PrintOpener returns one-line opener' }

        $giSnippet = Join-Path $PackRoot 'pack\templates\docs\gitignore.audit.snippet'
        if (-not (Select-String -Path $giSnippet -Pattern 'AGENT_SESSION_START' -Quiet)) {
            Fail 'gitignore snippet missing AGENT_SESSION_START.md'
        } else { Ok 'gitignore snippet tracks AGENT_SESSION_START.md' }

        $bootstrap = Join-Path $PackRoot 'pack\scripts\bootstrap-project.ps1'
        $hookRoot = Join-Path $PackRoot ".tmp\session-hook-probe-$PID"
        if (Test-Path -LiteralPath $hookRoot) { Remove-Item -LiteralPath $hookRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $hookRoot -Force | Out-Null
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $bootstrap -ProjectRoot (Join-Path $hookRoot 'HookApp') `
            -ProjectName 'HookApp' -Stack Generic -Targets Cursor -NoPause 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'Cursor bootstrap for session hook exited non-zero' }
        else {
            $hookProj = Join-Path $hookRoot 'HookApp'
            $hookJson = Join-Path $hookProj '.cursor\hooks.json'
            $hookPs1 = Join-Path $hookProj '.cursor\hooks\session-freshness.ps1'
            if (-not (Test-Path -LiteralPath $hookJson)) { Fail 'bootstrap missing .cursor/hooks.json' }
            elseif (-not (Test-Path -LiteralPath $hookPs1)) { Fail 'bootstrap missing session-freshness.ps1' }
            else { Ok 'bootstrap installs Cursor sessionStart hook files' }
        }

        if ($hookProj -and (Test-Path -LiteralPath $hookPs1)) {
            Write-Utf8NoBom -Path (Join-Path $hookProj 'AGENTS.md') -Text "# hook probe`r`n"
            Write-Utf8NoBom -Path (Join-Path $hookProj 'docs\AGENT_CONTEXT.json') -Text (@{
                schemaVersion = 2
                auditEngineVersion = [string]$engine
                packVersion = '1.8.0'
                canonicalProjectRoot = $hookProj
                requiredReads = @((Join-Path $hookProj 'AGENTS.md'))
                layers = @{ installedPack = 'ok' }
            } | ConvertTo-Json -Depth 4)
            Push-Location $hookProj
            try {
                $hookOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $hookPs1 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { Fail "session-freshness.ps1 exited $LASTEXITCODE" }
                else {
                    $parsed = $hookOut.Trim() | ConvertFrom-Json
                    if (-not $parsed.PSObject.Properties['additional_context']) {
                        Fail 'hook stdout missing additional_context'
                    } elseif ($parsed.additional_context -notmatch 'Agent context OK') {
                        Fail 'fresh hook should mention context OK'
                    } else { Ok 'sessionStart hook emits Cursor JSON on fresh context' }
                }
            } finally {
                Pop-Location
            }
        }

        # Both directions, or the step proves nothing: a probe that reports "fresh" because it cannot
        # find an install to compare against would have passed every assertion above. Point the same
        # fixture at an install one version behind and the verdict must flip, naming both versions.
        $staleInstall = Join-Path $probeRoot 'installed-stale'
        New-Item -ItemType Directory -Path (Join-Path $staleInstall 'pack\audit') -Force | Out-Null
        Write-Utf8NoBom -Path (Join-Path $staleInstall 'pack\audit\manifest.json') -Text "{`"version`": `"0.0.1`"}`r`n"
        $env:AGENT_STARTER_PACK_INSTALL_ROOT = $staleInstall
        $staleJson = & py -3 $freshPy --session-brief --project-root $probeRoot 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Fail "session-brief failed against stale install: $staleJson" }
        else {
            $staleBrief = $staleJson | ConvertFrom-Json
            if (-not $staleBrief.stale) { Fail 'stamp ahead of the installed pack should report stale' }
            elseif ($staleBrief.openerLine -notmatch '0\.0\.1') { Fail 'stale opener does not name the installed engine version' }
            elseif ($staleBrief.permission -eq 'none') { Fail 'stale context should ask for more than permission none' }
            else { Ok 'stale install flips the verdict and names both versions' }
        }

        # Python must read the same override PowerShell does, which is what made this step machine
        # dependent in the first place.
        $freshPyText = Get-Content -LiteralPath $freshPy -Raw
        if ($freshPyText -notmatch 'AGENT_STARTER_PACK_INSTALL_ROOT') {
            Fail 'agent_context_freshness.py ignores AGENT_STARTER_PACK_INSTALL_ROOT (PowerShell honours it)'
        } else { Ok 'freshness module honours the install-root override' }
    }
} catch {
    Fail "session-start freshness checks error: $_"
} finally {
    if ($null -eq $prevFreshInstall) { Remove-Item Env:\AGENT_STARTER_PACK_INSTALL_ROOT -ErrorAction SilentlyContinue }
    else { $env:AGENT_STARTER_PACK_INSTALL_ROOT = $prevFreshInstall }
    if ($null -eq $prevFreshSource) { Remove-Item Env:\AGENT_STARTER_PACK_ROOT -ErrorAction SilentlyContinue }
    else { $env:AGENT_STARTER_PACK_ROOT = $prevFreshSource }
    Remove-Item (Join-Path $PackRoot ".tmp\session-start-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $PackRoot ".tmp\session-hook-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n39. Hub doc repair + project-local portable rules (WQ-308 D3)"
try {
    $repairDocs = Join-Path $PSScriptRoot 'repair-agent-docs.ps1'
    if (-not (Test-Path -LiteralPath $repairDocs)) { Fail 'repair-agent-docs.ps1 missing' }
    else {
        $repairRoot = Join-Path $PackRoot ".tmp\repair-docs-probe-$PID"
        if (Test-Path -LiteralPath $repairRoot) { Remove-Item -LiteralPath $repairRoot -Recurse -Force -ErrorAction SilentlyContinue }
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath (Join-Path $PSScriptRoot 'bootstrap-project.ps1') `
            -ProjectRoot (Join-Path $repairRoot 'RepairProbe') -ProjectName 'RepairProbe' -Stack Generic -Targets Portable -NoPause 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "Portable bootstrap for repair probe exited $LASTEXITCODE" }
        else {
            $proj = Join-Path $repairRoot 'RepairProbe'
            Remove-Item (Join-Path $proj 'docs\portable\GENERIC_RULES.md') -Force -ErrorAction SilentlyContinue
            $aiPath = Join-Path $proj 'AI_INSTRUCTIONS.md'
            if (Test-Path -LiteralPath $aiPath) {
                $aiOld = Get-Content -LiteralPath $aiPath -Raw -Encoding UTF8
                $aiOld = $aiOld -replace 'user verifies', 'user reviews'
                Write-Utf8NoBom -Path $aiPath -Text $aiOld
            }
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairDocs -ProjectRoot $proj -PackRoot $PackRoot 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Fail 'repair-agent-docs.ps1 failed on probe project' }
            elseif (-not (Test-Path -LiteralPath (Join-Path $proj 'docs\portable\GENERIC_RULES.md'))) {
                Fail 'repair did not restore docs/portable/GENERIC_RULES.md'
            } else {
                $aiNew = Get-Content -LiteralPath $aiPath -Raw -Encoding UTF8
                if ($aiNew -notmatch 'user verifies') { Fail 'repair did not restore execute/verify in AI_INSTRUCTIONS.md' }
                else { Ok 'repair-agent-docs restores hub patterns and portable GENERIC_RULES' }
            }
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairDocs -ProjectRoot $proj -PackRoot $PackRoot -VerifyOnly 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Fail 'repair-agent-docs -VerifyOnly failed after repair' }
            else { Ok 'repair-agent-docs -VerifyOnly passes on repaired project' }
        }
    }
} catch {
    Fail "hub doc repair checks error: $_"
} finally {
    Remove-Item (Join-Path $PackRoot ".tmp\repair-docs-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n40. OS shell helper smoke (WQ-304 Phase 1)"
try {
    if (-not (Get-Command Test-PackIsWindows -ErrorAction SilentlyContinue)) {
        Fail 'pack-paths missing Test-PackIsWindows'
    } elseif (-not (Get-Command Invoke-PackScript -ErrorAction SilentlyContinue)) {
        Fail 'pack-paths missing Invoke-PackScript'
    } else {
        $probeRoot = Join-Path $PackRoot ".tmp\shell-helper-probe-$PID"
        if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
        $savedUserRoot = $env:AGENT_STARTER_PACK_USER_ROOT
        $env:AGENT_STARTER_PACK_USER_ROOT = $probeRoot
        try {
            $resolved = Get-DefaultCursorUserRoot
            if ($resolved -ne $probeRoot) { Fail "Get-DefaultCursorUserRoot expected $probeRoot got $resolved" }
            else { Ok 'Get-DefaultCursorUserRoot honors AGENT_STARTER_PACK_USER_ROOT' }
        } finally {
            if ($null -eq $savedUserRoot) { Remove-Item Env:AGENT_STARTER_PACK_USER_ROOT -ErrorAction SilentlyContinue }
            else { $env:AGENT_STARTER_PACK_USER_ROOT = $savedUserRoot }
        }

        $echoPs1 = Join-Path $probeRoot 'echo-exit.ps1'
        Write-Utf8NoBom -Path $echoPs1 -Text "Write-Output 'pack-script-ok'`r`nexit 42`r`n"
        $code = Invoke-PackScript -ScriptPath $echoPs1 -NoProfile
        if ($code -ne 42) { Fail "Invoke-PackScript exit code expected 42 got $code" }
        else { Ok 'Invoke-PackScript runs nested pack script and returns exit code' }

        $psExe = Get-PackPowerShellPath
        if (-not $psExe -or -not (Test-Path -LiteralPath $psExe)) { Fail "Get-PackPowerShellPath returned invalid path: $psExe" }
        else { Ok "Get-PackPowerShellPath resolves: $psExe" }

        $installSh = Join-Path $PackRoot 'install.sh'
        if (-not (Test-Path -LiteralPath $installSh)) { Fail 'install.sh missing at pack root' }
        else {
            $shText = Get-Content -LiteralPath $installSh -Raw -Encoding UTF8
            if ($shText -notmatch 'pwsh-wrap\.sh' -or $shText -notmatch 'install\.ps1') { Fail 'install.sh does not delegate to pwsh install.ps1' }
            else { Ok 'install.sh delegates full install to pwsh install.ps1' }
        }
    }
} catch {
    Fail "OS shell helper checks error: $_"
} finally {
    Remove-Item (Join-Path $PackRoot ".tmp\shell-helper-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n41. OS preflight scope (WQ-304 Phase 3)"
try {
    $reqScript = Join-Path $PackRoot 'pack\scripts\check-requirements.ps1'
    $docScript = Join-Path $PackRoot 'pack\scripts\doctor.ps1'
    if (-not (Test-Path -LiteralPath $reqScript)) { Fail 'check-requirements.ps1 missing' }
    elseif (-not (Select-String -Path $reqScript -Pattern 'Test-PackIsWindows' -Quiet)) {
        Fail 'check-requirements.ps1 missing Test-PackIsWindows gates'
    } elseif (-not (Select-String -Path $reqScript -Pattern 'Get-PackPythonInstallFix|Resolve-PackPythonInvoke' -Quiet)) {
        Fail 'check-requirements.ps1 missing cross-platform Python helpers'
    } else { Ok 'check-requirements gates Windows-only py launcher and fix hints' }

    if (-not (Test-Path -LiteralPath $docScript)) { Fail 'doctor.ps1 missing' }
    elseif (-not (Select-String -Path $docScript -Pattern 'Get-AgentStarterPackUserRoot|Get-DefaultCursorUserRoot' -Quiet)) {
        Fail 'doctor.ps1 still hardcodes USERPROFILE for user scope paths'
    } elseif (-not (Select-String -Path $docScript -Pattern 'Resolve-PackPythonInvoke' -Quiet)) {
        Fail 'doctor.ps1 missing Resolve-PackPythonInvoke for MCP smoke'
    } else { Ok 'doctor uses cross-platform user root and Python probe' }

    if (-not (Get-Command Resolve-PackPythonInvoke -ErrorAction SilentlyContinue)) {
        Fail 'pack-paths missing Resolve-PackPythonInvoke'
    } else {
        $probe = Resolve-PackPythonInvoke
        if (-not $probe) { Fail 'Resolve-PackPythonInvoke returned null on a machine running this suite' }
        else { Ok "Resolve-PackPythonInvoke finds $($probe.display)" }
    }
} catch {
    Fail "OS preflight scope checks error: $_"
}

Write-Host "`n42. Unix .sh entry points (WQ-304 Phase 4)"
try {
    $wrapSh = Join-Path $PackRoot 'pack\scripts\pwsh-wrap.sh'
    if (-not (Test-Path -LiteralPath $wrapSh)) { Fail 'pack/scripts/pwsh-wrap.sh missing' }
    elseif (-not (Select-String -Path $wrapSh -Pattern 'pack_pwsh_require|pack_pwsh_file' -Quiet)) {
        Fail 'pwsh-wrap.sh missing helper functions'
    } else { Ok 'pwsh-wrap.sh helper present' }

    $shMap = @(
        @{ Name = 'install.sh'; Marker = 'install.ps1' }
        @{ Name = 'Refresh-AgentContext.sh'; Marker = 'refresh-agent-context.ps1' }
        @{ Name = 'Bootstrap-Project.sh'; Marker = 'bootstrap-project.ps1' }
        @{ Name = 'Check-Requirements.sh'; Marker = 'check-requirements.ps1' }
        @{ Name = 'run_audit.sh'; Marker = 'run_audit.ps1' }
    )
    foreach ($entry in $shMap) {
        $shPath = Join-Path $PackRoot $entry.Name
        if (-not (Test-Path -LiteralPath $shPath)) { Fail "$($entry.Name) missing at pack root" }
        else {
            $shText = Get-Content -LiteralPath $shPath -Raw -Encoding UTF8
            if ($shText -match "`r") { Fail "$($entry.Name) must use LF line endings" }
            elseif ($shText -notmatch 'pwsh-wrap\.sh') { Fail "$($entry.Name) must source pwsh-wrap.sh" }
            elseif ($shText -notmatch [regex]::Escape($entry.Marker)) { Fail "$($entry.Name) must delegate to $($entry.Marker)" }
            else { Ok "$($entry.Name) delegates via pwsh-wrap.sh" }
        }
    }

    $refreshSh = Get-Content -LiteralPath (Join-Path $PackRoot 'Refresh-AgentContext.sh') -Raw -Encoding UTF8
    if ($refreshSh -notmatch 'ProjectRoot') { Fail 'Refresh-AgentContext.sh missing ProjectRoot forwarding' }
    else { Ok 'Refresh-AgentContext.sh forwards ProjectRoot and switches' }
} catch {
    Fail "Unix .sh entry point checks error: $_"
}

Write-Host "`n43. OS mock non-Windows smoke (WQ-304 Phase 5)"
try {
    $probeScript = Join-Path $PackRoot 'pack\scripts\test-os-portability-probe.ps1'
    if (-not (Test-Path -LiteralPath $probeScript)) { Fail 'test-os-portability-probe.ps1 missing' }
    elseif (-not (Select-String -Path (Join-Path $PackRoot 'pack\scripts\pack-paths.ps1') -Pattern 'AGENT_STARTER_PACK_TEST_OS' -Quiet)) {
        Fail 'pack-paths.ps1 missing AGENT_STARTER_PACK_TEST_OS hook for mock OS probes'
    } elseif (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Fail 'pwsh required for mock non-Windows probe (install PowerShell 7)'
    } else {
        $probeOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeScript -PackRoot $PackRoot -TestOs linux 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Fail "OS portability probe failed (exit $LASTEXITCODE): $probeOut" }
        elseif ($probeOut -notmatch 'os-portability-probe-ok') { Fail "OS portability probe unexpected output: $probeOut" }
        else { Ok 'mock Linux: HOME/.cursor root, pwsh path, optional py launcher, Invoke-PackScript' }
    }
} catch {
    Fail "OS mock non-Windows checks error: $_"
}

Write-Host "`n44. Verify failures explain themselves"
# verify-audit-system.ps1 counted the sync and behavior child exits as failures while discarding their
# output, so a red run ended at "Summary: 1 fail(s)" with no drifted file named and nothing to act on.
# A test that cannot say why it failed costs more than it saves.
try {
    $vsysPath = Join-Path $PackRoot 'pack\scripts\verify-audit-system.ps1'
    $vsys = Get-Content -LiteralPath $vsysPath -Raw
    $silent = [regex]::Matches($vsys, '(?m)^\s*\$\w+Exit\s*=\s*Invoke-PackScript(?![^\r\n]*-PassOutput)')
    if ($silent.Count -gt 0) {
        Fail "verify-audit-system.ps1 has $($silent.Count) child invocation(s) whose output is discarded - a failure there prints no reason"
    } elseif ($vsys -notmatch "Fail 'Audit sync drift") {
        Fail 'verify-audit-system.ps1 counts sync drift without a Fail message naming the remedy'
    } elseif ($vsys -notmatch "Fail 'Behavior self-test failed") {
        Fail 'verify-audit-system.ps1 counts a behavior failure without a Fail message naming the remedy'
    } else { Ok 'sync + behavior failures print their reason and remedy' }
} catch {
    Fail "verify reporting checks error: $_"
}

# 45. The agent brief survives the pipe from Python
# An em dash in AUDIT.md reached docs\.audit_agent_manifest.json as three characters, because
# PowerShell 5.1 decodes child stdout with the console code page. The file read was fixed once
# with -Encoding UTF8 and the pipe kept the bug, so assert on the artifact rather than the plumbing.
Write-Host "`n45. Agent manifest keeps non-ASCII intact"
try {
    $encProj = Join-Path ([System.IO.Path]::GetTempPath()) ("packenc_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    Copy-Item -LiteralPath $fixture -Destination $encProj -Recurse -Force
    $encAudit = Join-Path $encProj 'docs\AUDIT.md'
    $emDash = [char]0x2014
    # Inside a checklist section, not appended at the end: only section bullets and domain-map rows
    # are copied into the manifest, so a trailing line proves nothing.
    $marker = "encoding probe $emDash keep this dash"
    $encText = (Get-Content -LiteralPath $encAudit -Raw -Encoding UTF8) -replace '- no legacy audit rules', "- no legacy audit rules`r`n- $marker"
    Write-Utf8NoBom $encAudit $encText
    Invoke-PackScript -NoProfile -ScriptPath $corePs1 -RepoRoot $encProj -AppRoot $encProj -SkipTests *> $null
    $encMan = Join-Path $encProj 'docs\.audit_agent_manifest.json'
    if (-not (Test-Path $encMan)) {
        Fail 'encoding probe produced no agent manifest'
    } else {
        $manText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($encMan))
        if ($manText -match [char]0x00E2 + [char]0x20AC) {
            Fail 'agent manifest is double-encoded - run_audit_core.ps1 must pin PYTHONIOENCODING and [Console]::OutputEncoding before capturing py output'
        } elseif ($manText -notmatch 'encoding probe') {
            Fail 'encoding probe line never reached the agent manifest - check the AUDIT.md read path'
        } elseif ($manText -notmatch [regex]::Escape($marker)) {
            Fail 'agent manifest lost the em dash from AUDIT.md'
        } else { Ok 'non-ASCII survives AUDIT.md -> python -> agent manifest' }
    }
    Remove-Item -LiteralPath $encProj -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Fail "encoding probe error: $_"
}

# 46. Rules that install everywhere must not describe this repo
# 2.22.47 found three rules naming WQ ids, phase numbers and HANDOFF sections that exist only here.
# An agent in a bootstrapped app was told to check work items and doc sections it does not have.
# Reading caught those; this catches the next one. A line may still name pack internals when it says
# so - the difference between guidance for every project and a note for the maintainer is the scope
# marker on the line, not the reader's charity.
Write-Host "`n46. Shipped rules stay generic"
try {
    $scopeMarker = 'maintainer repo|maintainer pack|Pack maintenance|Agent Starter Pack maintainer'
    $banned = [ordered]@{
        'WQ-\d+'                     = "a work-queue id from this repo's queue"
        # The full name, not bare HANDOFF: `docs/handoffs/` and `HANDOFF_WQnnn` are the shipped
        # convention every project uses, and rules are supposed to name them.
        'HANDOFF_NEXT_AGENT'         = "this repo's session handoff doc"
        'WEEKEND_HANDOFF'            = 'a maintainer-only transfer note'
        'MULTI_TOOL_GAP_PLAN'        = 'a pack-only plan doc'
        'PACK_IMPLEMENTER'           = 'a pack-only spec'
        'AGENT_COORDINATION_BACKLOG' = 'a pack-only backlog'
        'Phase 6[a-z]?\b'            = 'a phase number that means nothing outside this repo'
        '\u00A7\s*\d+'               = 'a section number in one of this repo''s docs'
    }
    $ruleDir = Join-Path $PackRoot 'pack\rules'
    $leaks = @()
    foreach ($rule in (Get-ChildItem -LiteralPath $ruleDir -Filter *.mdc -File)) {
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $rule.FullName -Encoding UTF8)) {
            $lineNo++
            if ($line -match $scopeMarker) { continue }
            foreach ($pattern in $banned.Keys) {
                # The work-queue rule owns the id convention, so its `WQ-001` examples are the subject
                # matter rather than a reference to live work.
                if ($pattern -eq 'WQ-\d+' -and $rule.Name -eq 'generic-work-queue-discipline.mdc') { continue }
                # -cmatch, because these are file-name tokens: a rule may say "the handoff's status
                # section" as plain English, but naming HANDOFF_NEXT_AGENT.md points at a file only
                # this repo has.
                if ($line -cmatch $pattern) {
                    $leaks += "$($rule.Name):$lineNo names $($banned[$pattern])"
                }
            }
        }
    }
    if ($leaks.Count -gt 0) {
        Fail "pack/rules install into every project and must not name this repo's private state - scope the line to the maintainer repo, or reword it (name a section, do not number into a doc the reader may not have): $($leaks -join '; ')"
    } else {
        Ok "all $((Get-ChildItem -LiteralPath $ruleDir -Filter *.mdc -File).Count) shipped rules are free of this repo's ids, docs and section numbers"
    }
} catch {
    Fail "generic rule check error: $_"
}

# 47. Rules and docs may not send an agent to a file that is not there
# Step 46 checks that a rule's wording stays generic; nothing checked whether its advice is still
# true. `ensure-work-completion.ps1` copied pack\templates\docs\handoffs\README.md.template, which
# was never created - the copy sat behind a Test-Path, so the promised file simply never appeared
# and no test noticed. Only `pack/`-rooted references are resolved: a doc naming `docs/ROADMAP.md`
# or `scripts/apply_version.py` is describing the reader's project, not this pack.
Write-Host "`n47. Cited pack files exist"
try {
    $refFiles = @()
    $refFiles += Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack\rules') -Filter *.mdc -File
    $refFiles += Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack\skills') -Filter SKILL.md -File -Recurse
    # Changelogs describe past state on purpose: a file that existed at 2.22.3 and was renamed later
    # is history, not a broken link.
    $refFiles += Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack\docs') -Filter *.md -File |
        Where-Object { $_.Name -notmatch 'CHANGELOG' }
    $wsRules = Join-Path $PackRoot '.cursor\rules'
    if (Test-Path -LiteralPath $wsRules) {
        $refFiles += Get-ChildItem -LiteralPath $wsRules -Filter *.mdc -File
    }
    # Longest extension first and no second extension after it, or `.md.template` truncates to `.md`
    # and `.jsonl` to `.json` - both looked like 6 broken links on the first run and were neither.
    $extAlt = 'template|mdc|ps1|py|md|json|cmd|bat|sh'
    $refRx = "(?<![\w./\\-])(pack[\\/][\w./\\-]+?\.($extAlt))(?![\w]|\.[A-Za-z]{2,8})"
    $missing = @{}
    foreach ($f in $refFiles) {
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8)) {
            $lineNo++
            # A line whose point is that a file must not exist is not a broken reference.
            if ($line -match 'forbidden|never in pack|must not exist|no longer|removed|deleted') { continue }
            foreach ($m in [regex]::Matches($line, $refRx)) {
                $ref = $m.Groups[1].Value
                if ($ref -match '[*<>{}$]|MyApp|YourApp') { continue }
                $abs = Join-Path $PackRoot ($ref -replace '/', '\')
                if (-not (Test-Path -LiteralPath $abs)) {
                    $missing["$($f.Name)|$ref"] = "$($f.Name):$lineNo -> $ref"
                }
            }
        }
    }
    if ($missing.Count -gt 0) {
        Fail "rules and docs name pack files that do not exist - create the file or fix the reference: $(($missing.Values | Sort-Object) -join '; ')"
    } else {
        Ok "every pack/ path cited by $($refFiles.Count) rules, skills and docs resolves on disk"
    }
} catch {
    Fail "cited path check error: $_"
}

# 48. The pack's own launchers obey the pack's own pause rule
# generic-terminal-and-build-hygiene.mdc tells every project to gate `pause` behind BUILD_NOPAUSE,
# and four root .cmd launchers did not - Bootstrap-Project, Bootstrap-Portable-Project,
# Install-AgentStarterPack and Register-Tool-Adapters, twelve bare pauses between them. The suite
# never caught it because every test calls the .ps1 underneath with -NoPause; the .cmd layer is what
# a human double-clicks and what an agent runs, and there it blocks on a keypress.
Write-Host "`n48. Root .cmd launchers gate every pause"
try {
    $ungated = @()
    foreach ($launcher in (Get-ChildItem -LiteralPath $PackRoot -Filter *.cmd -File)) {
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $launcher.FullName)) {
            $lineNo++
            # A gated pause carries its condition on the same line; a bare one is the whole statement.
            if ($line -match '^\s*pause\s*$') { $ungated += "$($launcher.Name):$lineNo" }
        }
    }
    if ($ungated.Count -gt 0) {
        Fail "bare pause blocks an agent run - use 'if not defined BUILD_NOPAUSE pause': $($ungated -join ', ')"
    } else {
        Ok "all $((Get-ChildItem -LiteralPath $PackRoot -Filter *.cmd -File).Count) root launchers keep the window open without blocking an agent"
    }
} catch {
    Fail "launcher pause check error: $_"
}

# 49. One word for one thing: handoff
# "handoff" and "handover" are synonyms in English - British usage prefers the second - so nothing
# stops a writer alternating, and 2.22.52 found 519 mixed occurrences across 56 files. The pack now
# says handoff everywhere: the work-slice system (docs/handoffs/, HANDOFF_WQnnn, the registry) and
# the session doc (HANDOFF_NEXT_AGENT.md) are the same verb applied at two scales. The changelog is
# exempt because that is where the retired term is explained.
Write-Host "`n49. Vocabulary: handoff only"
try {
    $vocabExts = @('.md', '.mdc', '.ps1', '.py', '.cmd', '.bat', '.json', '.txt', '.template')
    $strays = @()
    foreach ($f in (Get-ChildItem -LiteralPath $PackRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '\\\.git\\|\\__pycache__\\|\\\.tmp\\' -and
                $_.Name -ne 'AUDIT_SYSTEM_CHANGELOG.md' -and
                # A linter has to spell the word it bans, so it cannot lint itself.
                $_.FullName -ne $PSCommandPath -and
                $vocabExts -contains $_.Extension
            })) {
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $lineNo++
            # The retired *word* is banned; the retired *filename* may be cited. Someone searching
            # for HANDOVER_NEXT_AGENT.md has to land somewhere, and a total ban would mean no doc
            # could ever say what this file used to be called.
            $prose = $line -replace 'HANDOVER_NEXT_AGENT', ''
            if ($prose -imatch 'handover') { $strays += "$($f.Name):$lineNo" }
        }
    }
    if ($strays.Count -gt 0) {
        Fail "'handover' is retired - the pack says handoff for both the work-slice files and the session doc: $($strays -join ', ')"
    } else {
        Ok 'no stray handover; one word for one concept'
    }
} catch {
    Fail "vocabulary check error: $_"
}

Write-Host "`nSummary: $fail fail(s)"
if ($fail -gt 0) { exit 1 }

# -DualShell: run the whole suite again on the other host. Opt-in because it doubles the runtime, and
# the parity step above already covers the difference that actually bites.
if ($DualShell) {
    $other = if ($PSVersionTable.PSEdition -eq 'Core') {
        (Get-Command powershell -ErrorAction SilentlyContinue)
    } else {
        (Get-Command pwsh -ErrorAction SilentlyContinue)
    }
    if (-not $other) {
        Write-Host "`n[DualShell] Only one PowerShell host installed - nothing to cross-check."
        exit 0
    }
    Write-Host "`n[DualShell] Re-running the full suite on $($other.Source) ..."
    # Deliberately without -DualShell: the child must not spawn its own cross-check.
    & $other.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[DualShell] FAILED on $($other.Source) - the pack is not cross-version clean."
        exit 1
    }
    Write-Host "[DualShell] Both hosts pass."
}
exit 0
