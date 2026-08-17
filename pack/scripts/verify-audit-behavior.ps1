#Requires -Version 5.1
<#
.SYNOPSIS
  Behavioral self-test for the audit system (no product test suite required).
#>
param(
    [string]$PackRoot = ''
)

$ErrorActionPreference = 'Stop'
$fail = 0

function Fail($msg) { Write-Host "[FAIL] $msg"; $script:fail++ }
function Ok($msg) { Write-Host "[OK] $msg" }

function Get-JsonFromOutput([string]$Text) {
    if (-not $Text) { return $null }
    $start = $Text.IndexOf('{')
    $end = $Text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { return $null }
    return $Text.Substring($start, $end - $start + 1)
}

if (-not $PackRoot) {
    . (Join-Path $PSScriptRoot 'pack-paths.ps1')
    $PackRoot = Get-AgentStarterPackRoot
}
if (-not $PackRoot -or -not (Test-Path $PackRoot)) {
    Fail 'Pack root not found'
    Write-Host "Summary: $fail fail(s)"
    exit 1
}

Write-Host "Audit behavior verification`nPack: $PackRoot`n"

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
        elseif ($obj.agentSections.F.modules -notcontains 'catalog_cache.py') {
            Fail 'Manifest F missing catalog_cache.py from multi-module row'
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
& powershell -NoProfile -ExecutionPolicy Bypass -File $corePs1 -RepoRoot $PackRoot -AppRoot $fixture -SkipTests *> $null
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
    'summary': 'Reviewed `main.py` — clean',
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
$missingMod = Join-Path $fixture 'catalog_cache.py'
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
d['sections']['F']['modulesReviewed'] = [m for m in d['sections']['F'].get('modulesReviewed', []) if m != 'catalog_cache.py']
p.write_text(json.dumps(d, indent=2), encoding='utf-8')
"@
    & py -3 -c $allCleanPy
    & py -3 $codePy $fixture --verify-semantic-report 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Fail 'verify-semantic-report should fail when F missing domain module but semantic clean' }
    else { Ok 'semantic vs machine blocks clean F when domain module missing' }
    Remove-Item $semPath4 -Force -ErrorAction SilentlyContinue
} finally {
    if ($null -ne $modBackup) { Set-Content -LiteralPath $missingMod -Value $modBackup -Encoding UTF8 -NoNewline }
}

Write-Host '13. Section L gitignore audit artifacts'
$giPath = Join-Path $fixture '.gitignore'
$giBackup = Get-Content $giPath -Raw
try {
    'docs/.audit_agent_manifest.json' | Set-Content -LiteralPath $giPath -Encoding UTF8
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
    Set-Content -LiteralPath $giPath -Value $giBackup -Encoding UTF8 -NoNewline
}

Write-Host '14. auditGateFixes manifest (Incomplete audit not in Section L)'
$manGate = Join-Path $fixture 'docs\.audit_agent_manifest.json'
Remove-Item $manGate -Force -ErrorAction SilentlyContinue
& powershell -NoProfile -ExecutionPolicy Bypass -File $corePs1 -RepoRoot $PackRoot -AppRoot $fixture -SkipTests *> $null
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
& powershell -NoProfile -ExecutionPolicy Bypass -File $corePs1 -RepoRoot $PackRoot -AppRoot $fixture -FinalizeOnly 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Fail 'FinalizeOnly should fail without manifest test-pass proof' }
else { Ok 'FinalizeOnly requires manifest testsGitHead' }

Write-Host '17. FinalizeOnly preserves manifest test-pass proof'
Remove-Item $manGate -Force -ErrorAction SilentlyContinue
& powershell -NoProfile -ExecutionPolicy Bypass -File $corePs1 -RepoRoot $PackRoot -AppRoot $fixture 2>&1 | Out-Null
if (-not (Test-Path $manGate)) { Fail 'pass 1 did not write manifest for preserve probe' }
else {
    try {
        $mg1 = Get-Content $manGate -Raw | ConvertFrom-Json
        $headProof = $mg1.testsGitHead.ToString()
        if (-not $headProof -or $headProof -eq '__no_git__') { Fail "pass 1 missing tree/git test proof (got $headProof)" }
        & powershell -NoProfile -ExecutionPolicy Bypass -File $corePs1 -RepoRoot $PackRoot -AppRoot $fixture -FinalizeOnly 2>&1 | Out-Null
        $mg = Get-Content $manGate -Raw | ConvertFrom-Json
        if ($mg.testsGitHead -ne $headProof) { Fail "FinalizeOnly wiped testsGitHead (got $($mg.testsGitHead))" }
        elseif (-not $mg.testsPassedAt) { Fail 'FinalizeOnly wiped testsPassedAt' }
        else { Ok 'FinalizeOnly preserves testsGitHead + testsPassedAt' }
    } catch { Fail "FinalizeOnly manifest preserve parse: $_" }
}

Write-Host '18. Auditor workflow E2E — pass 1, semantic, finalize exit 0'
$semPathE2e = Join-Path $fixture 'docs\.audit_semantic_report.json'
$timingPath = Join-Path $fixture 'docs\.audit_timing.jsonl'
Remove-Item $manGate, $semPathE2e, $timingPath -Force -ErrorAction SilentlyContinue
& powershell -NoProfile -ExecutionPolicy Bypass -File $corePs1 -RepoRoot $PackRoot -AppRoot $fixture 2>&1 | Out-Null
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
        sec['summary'] = f'Addressed machine finding — reviewed `{ref}`'
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
    & powershell -NoProfile -ExecutionPolicy Bypass -File $corePs1 -RepoRoot $PackRoot -AppRoot $fixture -FinalizeOnly 2>&1 | Out-Null
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

Write-Host "`nSummary: $fail fail(s)"
if ($fail -gt 0) { exit 1 }
exit 0
