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
    [switch]$DualShell,
    [string]$ResultsPath = ''
)

$ErrorActionPreference = 'Stop'
$fail = 0
$script:failRecords = @()
$script:suiteAnnouncements = $null

function Get-SuiteAnnouncementMap {
    <#.SYNOPSIS This suite's own step announcements, parsed once and cached (WQ-443 attribution).#>
    if ($null -ne $script:suiteAnnouncements) { return $script:suiteAnnouncements }
    $script:suiteAnnouncements = @()
    # Guarded: Fail exists before verify-lib.ps1 is dot-sourced, and the pack-root failure below can
    # fire in between. An unattributed failure is acceptable; a crash inside the failure reporter is not.
    if (Get-Command Get-PackBehaviorStepAnnouncement -ErrorAction SilentlyContinue) {
        try {
            $script:suiteAnnouncements = @(Get-PackBehaviorStepAnnouncement -SuiteText (Get-Content -LiteralPath $PSCommandPath -Raw -Encoding UTF8))
        } catch { $script:suiteAnnouncements = @() }
    }
    return $script:suiteAnnouncements
}

function Get-SuiteTopLevelLine {
    <#
    .SYNOPSIS
      The line in this file currently executing at top-level scope, or 0 when it cannot be determined.
    .DESCRIPTION
      `$MyInvocation.ScriptLineNumber` is **0** at top-level scope, which is not an error code - it
      silently resolves to "before every announcement" and attributes nothing. Step 72's live check was
      written against it and failed on first run for exactly that reason, while `Fail` - already using
      the call stack - attributed that same failure correctly. One helper now, so the check and the
      thing it checks cannot use different mechanisms and disagree.
    #>
    $me = $PSCommandPath
    $frames = @(Get-PSCallStack | Where-Object { $_.ScriptName -eq $me })
    if ($frames.Count -eq 0) { return 0 }
    return [int]$frames[-1].ScriptLineNumber
}

function Fail($msg) {
    Write-Host "[FAIL] $msg"
    $script:fail++
    # The printed line above is deliberately unchanged, so everything that greps [FAIL] keeps working.
    # The step is recorded separately and is derived from the *call site*, never from the output: a
    # planted control runs child verifies that print the identical prefix, and a trial parse of one
    # run credited five failures to two steps when the real count was one. The frame we want is the
    # last one in this file - the top-level scope - so a Fail raised inside a helper is credited to the
    # step that called the helper rather than to wherever the helper is defined.
    $stepNum = $null
    $stepLine = 0
    try {
        $stepLine = Get-SuiteTopLevelLine
        $stepNum = Resolve-PackBehaviorStep -Announcements (Get-SuiteAnnouncementMap) -Line $stepLine
    } catch { $stepNum = $null }
    # The raw line is recorded as well as the resolved step, and it is not redundant: a mutation can
    # break the resolver itself, in which case the suite fails as intended but can no longer say which
    # step did. The runner then re-attributes the line with its own unmutated code.
    $script:failRecords += [pscustomobject]@{ step = $stepNum; line = $stepLine; message = $msg }
}
function Ok($msg) { Write-Host "[OK] $msg" }

function Write-SuiteResults {
    <#.SYNOPSIS Machine-readable run result for the WQ-443 mutation runner. No-op without -ResultsPath.#>
    if (-not $ResultsPath) { return }
    try {
        $payload = [ordered]@{
            generatedAt  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            failCount    = $script:fail
            unattributed = @($script:failRecords | Where-Object { $null -eq $_.step }).Count
            failures     = @($script:failRecords)
        }
        Write-Utf8NoBom $ResultsPath ($payload | ConvertTo-Json -Depth 5)
    } catch {
        Write-Host "[WARN] could not write results to $ResultsPath - $_"
    }
}

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
. (Join-Path $PSScriptRoot 'verify-lib.ps1')
if (-not $PackRoot) {
    $PackRoot = Get-AgentStarterPackRoot
}
if (-not $PackRoot -or -not (Test-Path $PackRoot)) {
    Fail 'Pack root not found'
    Write-Host "Summary: $fail fail(s)"
    Write-SuiteResults
    exit 1
}

Write-Host "Audit behavior verification`nPack: $PackRoot`n"

# --fill-semantic-fixture-test marks every checklist section reviewed with no findings. This suite
# is the only thing allowed to use it; step 25 asserts it refuses without this opt-in.
$env:AUDIT_FIXTURE_TEST = '1'

$codePy = Join-Path $PackRoot 'pack/scripts/audit_code_checks.py'
$corePs1 = Join-Path $PackRoot 'pack/scripts/run_audit_core.ps1'
$fixture = Join-Path $PackRoot 'pack/audit/behavior-fixture'

# 1. Python self-test (domain map parser)
Write-Host '1. audit_code_checks.py --self-test'
Invoke-PackPython $codePy --self-test 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Fail 'audit_code_checks --self-test failed' } else { Ok 'self-test' }

# 2. JSON parse + manifest union on fixture
Write-Host '2. Fixture JSON + manifest sections F and K'
$out = Invoke-PackPython $codePy $fixture --full-tests-ran 2>&1 | Out-String
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
$fixtureManifest = Join-Path $fixture 'docs/.audit_agent_manifest.json'
if (Test-Path $fixtureManifest) { Remove-Item $fixtureManifest -Force -ErrorAction SilentlyContinue }

# 4. No orphan duplicate AUDIT template at pack root
Write-Host '4. Template hygiene'
$orphan = Join-Path $PackRoot 'pack/templates/AUDIT.md.template'
if (Test-Path $orphan) { Fail "Orphan template exists: $orphan (use pack/templates/docs/AUDIT.md.template)" }
else { Ok 'no orphan AUDIT.md.template' }

# 5. Protocol + skill forbid SkipTests loopholes
Write-Host '5. Rules and skill one-standard text'
$skillPath = Join-Path $PackRoot 'pack/skills/agent-code-audit/SKILL.md'
$protoPath = Join-Path $PackRoot 'pack/rules/audit-protocol.mdc'
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
    $manifestPath = Join-Path $PackRoot 'pack/audit/manifest.json'
    $mf = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $mirror = @($mf.packMirror)
    $toUser = @($mf.packToUser | ForEach-Object { $_.from })
    $installed = @()
    foreach ($r in (Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack/rules') -Filter *.mdc -File)) {
        $installed += "pack/rules/$($r.Name)"
    }
    foreach ($s in (Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack/skills') -Directory)) {
        foreach ($f in (Get-ChildItem -LiteralPath $s.FullName -Filter *.md -File -Recurse)) {
            $rel = Get-PackRelPathKey -Path $f.FullName -Root $PackRoot
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
    # A maintainer-only doc is exempt because it is never installed at all, so it cannot be the stale
    # copy this check exists to prevent. Without this the two mechanisms contradict each other: any
    # docs/ file added to maintainerOnlyPaths fails here, which is what happened when the handoff
    # design reference moved into the repo.
    # Read from the manifest, not listed here: this array was the fourth copy of "what is generated per
    # machine", and while it agreed with the export it disagreed with .gitignore, so two of these files
    # were committed with one maintainer's profile path in them. Step 50 owns that list now.
    $generatedDocs = @($mf.machineLocalPaths | Where-Object { $_ })
    $maintainerOnly = @($mf.maintainerOnlyPaths | Where-Object { $_ })
    $trackedDocs = @()
    foreach ($docDir in @('pack\docs', 'docs')) {
        $full = Join-Path $PackRoot $docDir
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $prefix = $docDir -replace '\\', '/'
        foreach ($f in (Get-ChildItem -LiteralPath $full -Filter *.md -File)) {
            $rel = "$prefix/$($f.Name)"
            if ($generatedDocs -contains $rel) { continue }
            if ($maintainerOnly -contains $rel) { continue }
            # A folder entry excludes everything under it, same rule install.ps1 applies.
            if (@($maintainerOnly | Where-Object { $rel -like "$_/*" }).Count -gt 0) { continue }
            $trackedDocs += $rel
        }
    }
    $docsUnmirrored = @($trackedDocs | Where-Object { $mirror -notcontains $_ })
    $docsBothWays = @($mirror | Where-Object { $maintainerOnly -contains $_ })
    if ($docsUnmirrored.Count -gt 0) {
        Fail "docs missing from manifest packMirror (installed once, then stale forever): $($docsUnmirrored -join ', ')"
    } elseif ($docsBothWays.Count -gt 0) {
        # Contradictory: install would skip the file while sync would try to refresh it.
        Fail "paths listed as both mirrored and maintainer-only: $($docsBothWays -join ', ')"
    } else { Ok "all $($trackedDocs.Count) pack/docs + docs files are tracked for sync ($($maintainerOnly.Count) maintainer-only paths exempt)" }

    # The machinery itself had the same hole, and it bites harder than docs: bootstrap-project.ps1 and
    # every template it writes were unmirrored, and bootstrapping *from the installed pack* is the
    # documented normal path - so a project generated after the second pack update would have been
    # built from the first update's templates. doctor.ps1 was unmirrored too, and the handoff tells
    # you to run it out of the profile. Enumerated so a new script or template is covered on creation.
    $machinery = @()
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack/scripts') -File)) {
        if ($f.Extension -in @('.ps1', '.py')) { $machinery += "pack/scripts/$($f.Name)" }
    }
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack/templates') -Recurse -File)) {
        $machinery += (Get-PackRelPathKey -Path $f.FullName -Root $PackRoot)
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
    } elseif ($installPs1 -notmatch 'repoOnlyPaths') {
        Fail 'install.ps1 ignores repoOnlyPaths - .github would ship to the profile and export zip'
    } else {
        Ok "all $($rootDocs.Count) root files classified ($($maintainerOnly.Count) maintainer-only, rest mirrored)"
    }

    # Sixth appearance, found by asking "what class of file have we not enumerated yet" instead of
    # waiting for the next symptom: mcp/agent_hygiene_server.py, the server install.ps1 registers in
    # mcp.json. A stale copy in the profile is a stale MCP server for every agent on the machine.
    $mcpFiles = @()
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $PackRoot 'mcp') -Recurse -File -ErrorAction SilentlyContinue)) {
        if ($f.Extension -in @('.py', '.json')) { $mcpFiles += (Get-PackRelPathKey -Path $f.FullName -Root $PackRoot) }
    }
    $mcpUnmirrored = @($mcpFiles | Where-Object { $mirror -notcontains $_ })
    if ($mcpUnmirrored.Count -gt 0) {
        Fail "MCP server files missing from manifest packMirror: $($mcpUnmirrored -join ', ')"
    } else { Ok "all $($mcpFiles.Count) MCP server file(s) are tracked for sync" }

    # The manifest is only half the path: sync-project-rules.ps1 pushes rules into a project, and it
    # used to carry its own hardcoded list - so a rule added later reached profiles but never
    # projects, silently. Run it for real and require every rule on disk to arrive.
    $ruleProbe = Join-Path $PackRoot ".tmp/ruleset-probe-$PID"
    try {
        New-Item -ItemType Directory -Path $ruleProbe -Force | Out-Null
        $syncRulesPs1 = Join-Path $PackRoot 'pack/scripts/sync-project-rules.ps1'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $syncRulesPs1 `
            -ProjectRoot $ruleProbe -RulesRelativePath '.cursor\rules' *> $null
        $srcNames = @(Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack/rules') -Filter *.mdc -File |
            Select-Object -ExpandProperty Name)
        $gotNames = @(Get-ChildItem -LiteralPath (Join-Path $ruleProbe '.cursor/rules') -Filter *.mdc -File `
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
$cfgTpl = Join-Path $PackRoot 'pack/templates/docs/AUDIT.config.json.template'
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
$wfPath = Join-Path $PackRoot 'pack/docs/AGENT_WORKFLOW.md'
if (Test-Path $wfPath) {
    $wf = Get-Content $wfPath -Raw
    if ($wf -notmatch 'all projects|Loop-back protocol \(all projects\)') { Fail 'AGENT_WORKFLOW.md missing all-projects loop-back' }
    else { Ok 'AGENT_WORKFLOW all-projects loop-back' }
}
$lb = Join-Path $PackRoot 'pack/rules/loop-back-protocol.mdc'
if (-not (Test-Path $lb)) { Fail 'Missing loop-back-protocol.mdc' } else { Ok 'loop-back-protocol.mdc' }

# 8. Semantic report verify (template + validate)
Write-Host '8. Semantic report verify'
$manProbe = Join-Path $fixture 'docs/.audit_agent_manifest.json'
$treeHead = (Invoke-PackPython $codePy $fixture --print-tests-git-head 2>&1 | Select-Object -Last 1).ToString().Trim()
if (-not $treeHead) { Fail 'could not compute tests git/tree head for fixture' }
Write-Utf8NoBom $manProbe (@{ testsGitHead = $treeHead; testsPassedAt = (Get-Date).ToUniversalTime().ToString('o'); machineFixesBySection = @{} } | ConvertTo-Json -Depth 4)
Invoke-PackPython $codePy $fixture --write-semantic-template 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'write-semantic-template failed' }
else { Ok 'write-semantic-template' }
Invoke-PackPython $codePy $fixture --fill-semantic-fixture-test 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'fill-semantic-fixture-test failed' }
$semPath = Join-Path $fixture 'docs/.audit_semantic_report.json'
if (-not (Test-Path $semPath)) { Fail 'semantic report template not written' }
else {
    Invoke-PackPython $codePy $fixture --verify-semantic-report 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'verify-semantic-report failed after fill' }
    else { Ok 'verify-semantic-report' }
    Remove-Item $semPath -Force -ErrorAction SilentlyContinue
}

Write-Host '9. Semantic cite validation'
$treeHead9 = (Invoke-PackPython $codePy $fixture --print-tests-git-head 2>&1 | Select-Object -Last 1).ToString().Trim()
Write-Utf8NoBom (Join-Path $fixture 'docs/.audit_agent_manifest.json') (@{ testsGitHead = $treeHead9; testsPassedAt = (Get-Date).ToUniversalTime().ToString('o'); machineFixesBySection = @{} } | ConvertTo-Json -Depth 4)
Invoke-PackPython $codePy $fixture --write-semantic-template 2>&1 | Out-Null
$semPath2 = Join-Path $fixture 'docs/.audit_semantic_report.json'
# The missing cite must be the *only* defect. It was not: modulesReviewed[] is required for sections
# D-K and was omitted, and D's lone 'command' evidence also tripped the file/test requirement, so the
# verify had two other reasons to reject. The step stayed green with cite checking mutated off -
# passing for reasons it does not name (WQ-462 batch five).
$badPy = @"
import json
from pathlib import Path
fixture = Path(r'$fixture')
p = fixture / 'docs/.audit_semantic_report.json'
d = json.loads(p.read_text(encoding='utf-8'))
exp = json.loads((fixture / 'docs/.audit_domain_expanded.json').read_text(encoding='utf-8'))
secs = (exp.get('sections') or {})
for k in d['sections']:
    d['sections'][k] = {
        'reviewed': True,
        'summary': 'Nothing found.' if k != 'D' else 'problem found with no cite',
        'evidence': [] if k != 'D' else [{'type': 'file', 'ref': 'main.py'}],
        'modulesReviewed': list(secs.get(k, ['main.py'] if k == 'D' else [])),
    }
p.write_text(json.dumps(d, indent=2), encoding='utf-8')
"@
Invoke-PackPython -c $badPy
$badOut = Invoke-PackPython $codePy $fixture --verify-semantic-report 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) { Fail 'verify-semantic-report should fail without cite on non-clean summary' }
elseif ($badOut -notmatch 'needs file/behavior cite') {
    Fail "the report was rejected, but not for a missing cite - the step is not reading what it claims: $($badOut.Trim())"
} else { Ok 'cite validation rejects a vague summary, and the rejection names the cite' }
Remove-Item $semPath2 -Force -ErrorAction SilentlyContinue

Write-Host '10. Semantic evidence validation'
$treeHead10 = (Invoke-PackPython $codePy $fixture --print-tests-git-head 2>&1 | Select-Object -Last 1).ToString().Trim()
Write-Utf8NoBom (Join-Path $fixture 'docs/.audit_agent_manifest.json') (@{ testsGitHead = $treeHead10; testsPassedAt = (Get-Date).ToUniversalTime().ToString('o'); machineFixesBySection = @{} } | ConvertTo-Json -Depth 4)
Invoke-PackPython $codePy $fixture --write-semantic-template 2>&1 | Out-Null
Invoke-PackPython $codePy $fixture --fill-semantic-fixture-test 2>&1 | Out-Null
$semPath3 = Join-Path $fixture 'docs/.audit_semantic_report.json'
# The fixture must be valid in every respect *except* the empty evidence array, or the step proves
# nothing about evidence. It did not: modulesReviewed[] is required for sections D-K, the fixture
# omitted it, and the verify was rejecting the report over that instead. The step stayed green with
# the evidence minimum mutated to zero - passing for a reason it does not name (WQ-462 batch five).
$noEvPy = @"
import json
from pathlib import Path
fixture = Path(r'$fixture')
p = fixture / 'docs/.audit_semantic_report.json'
d = json.loads(p.read_text(encoding='utf-8'))
exp = json.loads((fixture / 'docs/.audit_domain_expanded.json').read_text(encoding='utf-8'))
secs = (exp.get('sections') or {})
d['sections']['D'] = {
    'reviewed': True,
    'summary': 'Issue in `main.py` needs fix',
    'evidence': [],
    'modulesReviewed': list(secs.get('D', ['main.py'])),
}
for k, v in d['sections'].items():
    if k != 'D':
        v['reviewed'] = True
        v['summary'] = 'Nothing found.'
        v['evidence'] = []
        v['modulesReviewed'] = list(secs.get(k, []))
p.write_text(json.dumps(d, indent=2), encoding='utf-8')
"@
Invoke-PackPython -c $noEvPy
$noEvOut = Invoke-PackPython $codePy $fixture --verify-semantic-report 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) { Fail 'verify-semantic-report should fail without evidence on non-clean D' }
elseif ($noEvOut -notmatch 'needs >= \d+ evidence item') {
    # Rejected, but not over the evidence array - which is how this step passed while the evidence
    # minimum was disabled. Naming the reason is the difference between a proof and a coincidence.
    Fail "the report was rejected, but not for missing evidence - the step is not reading what it claims: $($noEvOut.Trim())"
} else { Ok 'evidence required when not clean, and the rejection names evidence' }
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
Invoke-PackPython -c $goodEvPy
Invoke-PackPython $codePy $fixture --verify-semantic-report 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'verify-semantic-report should pass with valid file evidence' }
else { Ok 'evidence file path validated' }
Remove-Item $semPath3 -Force -ErrorAction SilentlyContinue

Write-Host '11. machineCoverage completeness'
$mcOut = Invoke-PackPython $codePy $fixture --full-tests-ran 2>&1 | Out-String
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
    Invoke-PackPython $codePy $fixture --write-semantic-template 2>&1 | Out-Null
    Invoke-PackPython $codePy $fixture --fill-semantic-fixture-test 2>&1 | Out-Null
    $semPath4 = Join-Path $fixture 'docs/.audit_semantic_report.json'
    # The clean summary must be the *only* defect. It was not: the fixture also dropped the module from
    # modulesReviewed[], which raises its own "modulesReviewed missing" fix, so the verify was rejecting
    # the report over coverage and the step stayed green with the alignment test negated - passing for a
    # reason it does not name, the third instance of that shape in this batch family (WQ-462 batch six).
    # modulesReviewed keeps hardware_cache.py: the expanded domain map is built from config, not disk,
    # so listing a module that has been deleted is exactly the state under test - the section claims to
    # have reviewed it while the machine reports it missing.
    $allCleanPy = @"
import json
from pathlib import Path
p = Path(r'$semPath4')
d = json.loads(p.read_text(encoding='utf-8'))
d['sections']['F']['summary'] = 'Nothing found.'
p.write_text(json.dumps(d, indent=2), encoding='utf-8')
"@
    Invoke-PackPython -c $allCleanPy
    $alignOut = Invoke-PackPython $codePy $fixture --verify-semantic-report 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { Fail 'verify-semantic-report should fail when F missing domain module but semantic clean' }
    elseif ($alignOut -notmatch "cannot be 'Nothing found\.'") {
        Fail "the report was rejected, but not for contradicting the machine half - the step is not reading what it claims: $($alignOut.Trim())"
    } else { Ok 'semantic vs machine blocks clean F when domain module missing, and the rejection says so' }
    Remove-Item $semPath4 -Force -ErrorAction SilentlyContinue
} finally {
    if ($null -ne $modBackup) { Write-Utf8NoBom $missingMod $modBackup }
}

Write-Host '13. Section L gitignore audit artifacts'
$giPath = Join-Path $fixture '.gitignore'
$giBackup = Get-Content $giPath -Raw
try {
    Write-Utf8NoBom $giPath "docs/.audit_agent_manifest.json`r`n"
    $giOut = Invoke-PackPython $codePy $fixture --lightweight --full-tests-ran 2>&1 | Out-String
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
$manGate = Join-Path $fixture 'docs/.audit_agent_manifest.json'
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
# Four sample strings were written out here and matched against two regexes also written out here,
# so this step asserted that four literals matched a pattern eight lines above them. It could not
# fail for any reason in the pack, and it passed unchanged while the engine reworded its messages -
# the WQ-443 shape, in the suite that exists to catch it. Both halves are now read from the product:
# the classifier's own patterns out of run_audit_core.ps1, and the messages the engine actually
# emits out of audit_code_checks.py. The invariant is that those two agree, which is what breaks
# when someone rewords one of them.
$coreText15 = Get-Content -LiteralPath $corePs1 -Raw -Encoding UTF8
$enginePy15 = Get-Content -LiteralPath $codePy -Raw -Encoding UTF8
$gatePattern = $null
$wiringPattern = $null
if ($coreText15 -match "if \(\`$f -match '(\^Semantic report[^']+)'\) \{") { $gatePattern = $Matches[1] }
if ($coreText15 -match "if \(\`$f -match '(Audit sync\|[^']+)'\) \{") { $wiringPattern = $Matches[1] }
if (-not $gatePattern) { Fail 'cannot find the gate-class fix pattern in run_audit_core.ps1 - this step is reading nothing' }
elseif (-not $wiringPattern) { Fail 'cannot find the Section L wiring pattern in run_audit_core.ps1 - this step is reading nothing' }
else {
    # The literal prefixes the engine emits for a gate refusal. Read as source text rather than by
    # running it, because these are the branches an audit takes only when the report is missing,
    # invalid, or the tests were skipped.
    $emitted = @([regex]::Matches($enginePy15, '"(Semantic report (?:missing|invalid|verify failed)[^"\r\n]*|Incomplete audit[^"\r\n]*)') |
        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($emitted.Count -lt 3) {
        Fail "found only $($emitted.Count) gate-class message(s) in audit_code_checks.py - the engine's wording moved and this step went blind"
    } else {
        $unclassified = @($emitted | Where-Object { $_ -notmatch $gatePattern })
        $misfiled = @($emitted | Where-Object { $_ -match $wiringPattern })
        # A section-level finding is semantic content, not a gate refusal, and must stay out of the
        # gate bucket - the positive control that stops a pattern of '^Semantic report' passing here.
        $sectionSample = @([regex]::Matches($enginePy15, '"(Semantic report - section [^"\r\n]*)') |
            ForEach-Object { $_.Groups[1].Value } | Select-Object -First 1)
        if ($unclassified.Count -gt 0) {
            Fail "the engine emits gate fixes run_audit_core.ps1 does not classify as gate-class: $($unclassified -join ' | ')"
        } elseif ($misfiled.Count -gt 0) {
            Fail "gate fixes also match the Section L wiring bucket: $($misfiled -join ' | ')"
        } elseif ($sectionSample.Count -eq 0) {
            Fail 'no section-level semantic message found in audit_code_checks.py to control the gate pattern against'
        } elseif ($sectionSample[0] -match $gatePattern) {
            Fail "a section-level finding is classified as a gate refusal: $($sectionSample[0])"
        } else {
            Ok "all $($emitted.Count) engine gate messages classify as gate-class and none as L wiring"
        }
    }
}

Write-Host '16. FinalizeOnly blocked without prior test pass'
Remove-Item $manGate -Force -ErrorAction SilentlyContinue
# Non-zero is not enough - see the note above step 37's sweep. A run this deliberately broken has
# several ways to fail, and "it exited 1" would pass with the test-pass gate removed entirely.
$finOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $corePs1 -RepoRoot $PackRoot -AppRoot $fixture -FinalizeOnly 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) { Fail 'FinalizeOnly should fail without manifest test-pass proof' }
# 'test|proof|manifest' stood here and matched ordinary audit output - every refusal path in
# Test-ManifestFinalizeAllowed opens with this phrase, and nothing else in a run emits it, so this
# is the token that separates "refused the finalize" from "failed on its way there".
elseif ($finOut -notmatch 'Audit finalize blocked') {
    Fail "FinalizeOnly failed, but not over the missing test-pass proof: $($finOut.Trim())"
} else { Ok 'FinalizeOnly requires manifest testsGitHead, and says so' }

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
$semPathE2e = Join-Path $fixture 'docs/.audit_semantic_report.json'
$timingPath = Join-Path $fixture 'docs/.audit_timing.jsonl'
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
    'A': 'run_tests_stub.ps1', 'D': 'main.py', 'F': 'app_settings.py',
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
    Invoke-PackPython -c $fillPy
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
        # An empty map survives -not, because an object with no properties is still an object. The
        # question this log exists to answer is "which phase was slow", and {} answers nothing.
        elseif (@($tl.phases.PSObject.Properties).Count -eq 0) { Fail 'timing log carries an empty phases map' }
        elseif ($null -eq $tl.totalSeconds) { Fail 'timing log missing totalSeconds' }
        else { Ok "audit timing jsonl written with $(@($tl.phases.PSObject.Properties).Count) phase(s)" }
    } catch { Fail "timing log parse: $_" }
}
Remove-Item $manGate, $semPathE2e, $timingPath -Force -ErrorAction SilentlyContinue

Write-Host '20. Mirror direction - source pack wins, installed copy never writes back'
# Runs the real sync against a miniature pack and a scratch install target, so the direction rules
# are enforced by tests instead of by reading the code. AGENT_STARTER_PACK_INSTALL_ROOT keeps every
# write inside the pack: nothing here may touch %USERPROFILE%\.cursor.
$probeRoot = Join-Path $PackRoot '.tmp/mirror-probe'
$prevInstallRoot = $env:AGENT_STARTER_PACK_INSTALL_ROOT
try {
    if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force }
    $probeSource = Join-Path $probeRoot 'source'
    $probeInstalled = Join-Path $probeRoot 'installed/AgentStarterPack'
    foreach ($d in @("$probeSource/pack/audit", "$probeSource/pack/scripts", "$probeSource/pack/rules", "$probeInstalled/pack/audit", "$probeInstalled/pack/rules")) {
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
    Write-Utf8NoBom "$probeSource/pack/audit/manifest.json" ($probeManifest)
    Write-Utf8NoBom "$probeInstalled/pack/audit/manifest.json" ($probeManifest)
    Copy-Item -LiteralPath (Join-Path $PackRoot 'pack/scripts/pack-paths.ps1') -Destination "$probeSource/pack/scripts/pack-paths.ps1"
    Copy-Item -LiteralPath (Join-Path $PackRoot 'pack/scripts/sync-audit-system.ps1') -Destination "$probeSource/pack/scripts/sync-audit-system.ps1"
    $probeSync = "$probeSource/pack/scripts/sync-audit-system.ps1"

    # Write mode must never create an install. A project audit with autoFixDrift enabled runs this
    # script without -VerifyOnly, and the mirror used to materialize %USERPROFILE%\.cursor from
    # nothing - installing the pack as a side effect of auditing a project.
    $absentInstall = Join-Path $probeRoot 'never-installed/AgentStarterPack'
    Write-Utf8NoBom "$probeSource/pack/rules/probe-mirror.mdc" ('source')
    $env:AGENT_STARTER_PACK_INSTALL_ROOT = $absentInstall
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeSync *> $null
    if (Test-Path -LiteralPath $absentInstall) { Fail 'sync created an install where none existed' }
    elseif (Test-Path -LiteralPath (Join-Path $probeRoot 'never-installed/rules')) { Fail 'sync created profile rules where no install existed' }
    else { Ok 'sync never creates an install (install.ps1 only)' }

    $srcMirror = "$probeSource/pack/rules/probe-mirror.mdc"
    $dstMirror = "$probeInstalled/pack/rules/probe-mirror.mdc"
    $dstOnly = "$probeInstalled/pack/rules/probe-only-installed.mdc"
    $srcOnly = "$probeSource/pack/rules/probe-only-installed.mdc"
    Write-Utf8NoBom $srcMirror ('source')
    Write-Utf8NoBom $dstMirror ('installed')
    Write-Utf8NoBom $dstOnly ('installed-only')
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

    $probeUserRule = Join-Path $probeRoot 'installed/rules/probe-mirror.mdc'
    if (-not (Test-Path -LiteralPath $probeUserRule)) {
        Fail 'packToUser mirror did not follow the install-root override'
    } elseif (Test-Path -LiteralPath (Join-Path (Get-PackHomeDir) '.cursor/rules/probe-mirror.mdc')) {
        Fail 'probe leaked into the real user profile'
    } else { Ok 'packToUser mirror honors install-root override' }

    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeSync -VerifyOnly *> $null
    $verifyClean = $LASTEXITCODE
    Write-Utf8NoBom $dstMirror ('installed')
    # The clean run above is already a two-way control, so a blanket always-fail is caught. What it
    # does not catch is a verify that rejects for an unrelated reason, so the drifted file is named.
    $driftOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeSync -VerifyOnly 2>&1 | Out-String
    if ($verifyClean -ne 0) { Fail "VerifyOnly exit $verifyClean on a synced mirror, expected 0" }
    elseif ($LASTEXITCODE -eq 0) { Fail 'VerifyOnly missed drift in the installed mirror' }
    elseif ($driftOut -notmatch [regex]::Escape((Split-Path $dstMirror -Leaf))) {
        Fail "VerifyOnly failed without naming the drifted file: $($driftOut.Trim())"
    } else { Ok 'VerifyOnly reports drift without copying, naming the drifted file' }

    Write-Utf8NoBom $dstOnly ('installed-only')
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
$preflight = Join-Path $PackRoot 'pack/scripts/check-requirements.ps1'
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
$packTests = Join-Path $PackRoot 'tests/test_pack_audit.py'
if (-not (Test-Path -LiteralPath $packTests)) { Fail 'missing tests\test_pack_audit.py' }
else {
    # 2>&1 into the pipeline, not *>$null: the MCP server prints to stderr when the optional mcp
    # package is absent, and $ErrorActionPreference='Stop' turns native stderr into a failure.
    Invoke-PackPython $packTests 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'tests\test_pack_audit.py failed when run directly' }
    else { Ok 'test_pack_audit.py runs standalone' }
    # The test entry point is a wrapper pair over one implementation, like run_audit.cmd/.sh over
    # scripts/run_audit.ps1. It used to be Batch holding all five steps, which made the pack's own
    # test command Windows-only by construction: the audit runs a project's declared test script, so
    # a Batch-only runner meant the pack could never complete its own audit off Windows.
    #
    # Assert the property that matters - both wrappers delegate to the same implementation, and the
    # implementation still does the work - rather than grepping one wrapper for the work itself.
    $impl = Join-Path $PackRoot 'scripts/run_audit_tests.ps1'
    $winWrap = Join-Path $PackRoot 'run_audit_tests.bat'
    $posixWrap = Join-Path $PackRoot 'run_audit_tests.sh'
    $tFails = @()
    foreach ($pair in @(@{ p = $impl; n = 'scripts/run_audit_tests.ps1' },
            @{ p = $winWrap; n = 'run_audit_tests.bat' }, @{ p = $posixWrap; n = 'run_audit_tests.sh' })) {
        if (-not (Test-Path -LiteralPath $pair.p)) { $tFails += "missing $($pair.n)" }
    }
    if (-not $tFails) {
        $implText = Get-Content -LiteralPath $impl -Raw
        $winText = Get-Content -LiteralPath $winWrap -Raw
        $posixText = Get-Content -LiteralPath $posixWrap -Raw
        if ($implText -notmatch 'test_pack_audit\.py') { $tFails += 'the implementation does not run tests/test_pack_audit.py' }
        if ($implText -notmatch 'verify-audit-behavior\.ps1') { $tFails += 'the implementation does not run the behavior suite' }
        if ($implText -notmatch 'verify-audit-system\.ps1') { $tFails += 'the implementation does not run verify-audit-system' }
        # Both hosts, or the cross-version claim is untested. 5.1 stays the launcher because it is the
        # only host guaranteed present on Windows; the second host is what the gate adds.
        if ($implText -notmatch '-DualShell') { $tFails += 'the implementation no longer runs the suite on both hosts (-DualShell) - cross-version breakage would ship unseen' }
        # Wrappers must delegate, not re-implement: a wrapper that grew its own steps is how the two
        # platforms drift into running different test suites.
        if ($winText -notmatch 'run_audit_tests\.ps1') { $tFails += 'run_audit_tests.bat does not delegate to scripts/run_audit_tests.ps1' }
        if ($posixText -notmatch 'run_audit_tests\.ps1') { $tFails += 'run_audit_tests.sh does not delegate to scripts/run_audit_tests.ps1' }
        if ($posixText -notmatch 'pwsh-wrap\.sh') { $tFails += 'run_audit_tests.sh does not use pwsh-wrap.sh like the other .sh entry points' }
        if ($winText -match 'test_pack_audit\.py') { $tFails += 'run_audit_tests.bat re-implements a test step instead of delegating' }
    }
    if ($tFails) { Fail "pack test entry point: $($tFails -join '; ')" }
    else { Ok 'test entry point is one implementation behind a .bat and a .sh wrapper, on both hosts' }
}

Write-Host '23. Bootstrap smoke - a generated project audits itself'
# Reading templates is not evidence that bootstrap output works. Running this by hand once found
# three shipped defects (BOM crash in load_config, a project audit installing the pack into
# %USERPROFILE%, and the parent-folder repo root), so it belongs in the suite.
# Per-run folder: a shared path fails the whole step when a leftover process, an antivirus scan, or
# a second concurrent run holds a probe file open, and the message ("cannot access the file") reads
# like a product defect instead of scratch contention.
function Invoke-ProjectAudit {
    # A generated project's audit, through the entry point this OS actually uses: run_audit.cmd via
    # cmd.exe on Windows, run_audit.sh via bash elsewhere. Hardcoding `cmd /c` made this step
    # Windows-only - off Windows it died with "the term 'cmd' is not recognized", which reads like a
    # missing tool rather than a probe that only knows one platform.
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$ExtraArgs = ''
    )
    if (Test-PackIsWindows) {
        $cmdPath = Join-Path $ProjectRoot 'run_audit.cmd'
        $tail = if ($ExtraArgs) { " $ExtraArgs" } else { '' }
        return (& cmd /c "`"$cmdPath`"$tail 2>&1" | Out-String)
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'run_audit.sh'))) {
        return "PROBE ERROR: no run_audit.sh - a generated project cannot audit itself on this OS"
    }
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if (-not $bash) { return 'PROBE ERROR: bash not found' }
    # stderr merged inside bash: this script runs with ErrorActionPreference='Stop', which turns a
    # native command's stderr into a terminating error - it would abort the step instead of asserting.
    $posixRoot = Convert-PackPathToPosix -Path $ProjectRoot -BashExe $bash.Source
    return (& $bash.Source -lc "cd '$posixRoot' && { ./run_audit.sh $ExtraArgs ; } 2>&1" | Out-String)
}

$smokeRoot = Join-Path $PackRoot ".tmp/bootstrap-smoke-$PID"
$prevSmokePackRoot = $env:AGENT_STARTER_PACK_ROOT
$prevSmokeInstall = $env:AGENT_STARTER_PACK_INSTALL_ROOT
try {
    if (Test-Path -LiteralPath $smokeRoot) { Remove-Item -LiteralPath $smokeRoot -Recurse -Force -ErrorAction SilentlyContinue }
    $smokeProj = Join-Path $smokeRoot 'ProbeApp'
    $smokeInstall = Join-Path $smokeRoot 'no-install/AgentStarterPack'

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
    $bootstrap = Join-Path $PackRoot 'pack/scripts/bootstrap-project.ps1'
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $bootstrap -ProjectRoot $smokeProj `
        -ProjectName 'ProbeApp' -Stack Python -Targets All -NoPause *> $null
    $bootExit = $LASTEXITCODE
    if ($bootExit -ne 0) { Fail "bootstrap exited $bootExit" }
    elseif (-not (Test-Path -LiteralPath (Join-Path $smokeProj 'run_audit.cmd'))) { Fail 'bootstrap produced no run_audit.cmd' }
    elseif (-not (Test-Path -LiteralPath (Join-Path $smokeProj 'docs/AUDIT.config.json'))) { Fail 'bootstrap produced no docs\AUDIT.config.json' }
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
    $auditOut = Invoke-ProjectAudit -ProjectRoot $smokeProj
    # Audit twice: the second run takes the "already synced" path through the generated version
    # script, where a single non-ASCII character used to fail the whole test step.
    $auditOut2 = Invoke-ProjectAudit -ProjectRoot $smokeProj

    $projPattern = [regex]::Escape($smokeProj)
    if ($auditOut -notmatch "Repo:\s+$projPattern\s") { Fail 'audit repo root is not the project root (parent-folder regression)' }
    elseif ($auditOut -notmatch "App:\s+$projPattern\s") { Fail 'audit app root is not the project root' }
    else { Ok 'repo root and app root both resolve to the project' }

    # Both layers must agree, or the machine checks and the Python checks audit different trees.
    $pyRepo = (Invoke-PackPython (Join-Path $PackRoot 'pack/scripts/audit_code_checks.py') $smokeProj --print-repo-root 2>&1 | Out-String).Trim()
    if ($pyRepo -ne $smokeProj) { Fail "python repo root disagrees with the wrapper: '$pyRepo' vs '$smokeProj'" }
    else { Ok 'python and powershell agree on the repo root' }

    # Third implementation of the same decision, and the only one that writes: doc_version_sync
    # resolves scanFiles against this root, so a wrong answer rewrites files outside the project.
    $dvsProbe = "import sys; sys.path.insert(0, r'$(Join-Path $PackRoot 'pack/scripts')'); " +
        "from pathlib import Path; import doc_version_sync as d; print(d.resolve_repo_root(Path(r'$smokeProj')))"
    $dvsRepo = (Invoke-PackPython -c $dvsProbe 2>&1 | Out-String).Trim()
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
    if (-not (Test-Path -LiteralPath (Join-Path $genProj 'docs/AUDIT.config.json'))) { Fail 'Generic bootstrap produced no config' }
    else {
        $genCmd = Join-Path $genProj 'run_audit.cmd'
        $genOut = Invoke-ProjectAudit -ProjectRoot $genProj
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
        $appOut = Invoke-ProjectAudit -ProjectRoot $namedApp
        if ($appOut -notmatch "Repo:\s+$([regex]::Escape($namedApp))\s") {
            Fail 'a flat project named "app" audits its parent folder'
        } else { Ok 'folder named "app" does not hijack the repo root' }

        # Walk the documented three-step workflow on generated output: machine pass, auditor fills
        # the semantic report, finalize. A new project must be able to reach a clean audit.
        Invoke-PackPython (Join-Path $PackRoot 'pack/scripts/audit_code_checks.py') $genProj --fill-semantic-fixture-test *> $null
        $genFinal = Invoke-ProjectAudit -ProjectRoot $genProj -ExtraArgs '-FinalizeOnly'
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
                Invoke-ProjectAudit -ProjectRoot $gitProj | Out-Null
                Invoke-PackPython $codePy $gitProj --fill-semantic-fixture-test *> $null
                $gitClean = Invoke-ProjectAudit -ProjectRoot $gitProj -ExtraArgs '-FinalizeOnly'
                $gitCleanLeft = @(($gitClean -split "`r?`n") | Where-Object { $_ -match '^- ' })
                $recordedProof = ''
                $manPath = Join-Path $gitProj 'docs/.audit_agent_manifest.json'
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
                    $tampered = Invoke-ProjectAudit -ProjectRoot $gitProj -ExtraArgs '-FinalizeOnly'
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
            $hollowOut = Invoke-ProjectAudit -ProjectRoot $hollowProj
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
        if (Test-PackPathHasSegment -Path $f.FullName -Segment @('__pycache__', '.tmp', '.git')) { return }
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
    $fillOut = Invoke-PackPython $codePy $fixture --fill-semantic-fixture-test 2>&1 | Out-String
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
$probe = Join-Path $PackRoot ".tmp/installer-probe-$PID"
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
            '.cursor\rules\no-publish-from-this-machine.mdc', 'docs\handoffs\active\HANDOFF_WQ001_x.md',
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
        -SkipRelPaths @('.cursor\rules\no-publish-from-this-machine.mdc', 'docs\handoffs')
    $leaked = @('pack\scripts\__pycache__\x.cpython-314.pyc', '.git\config', '.tmp\scratch.txt',
        '.pytest_cache\c.json', 'docs\.audit_semantic_report.json',
        '.cursor\rules\no-publish-from-this-machine.mdc', 'docs\handoffs\active\HANDOFF_WQ001_x.md', 'docs\handoffs\README.md') |
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
    $redirectRoot = Join-Path $probe 'redirect/cursor/AgentStarterPack'
    # Hash only what an install owns. The first version of this check stamped all of %USERPROFILE%\.cursor
    # and went flaky: the running editor writes there constantly, so an unrelated write looked like the
    # installer escaping its redirect.
    $realProfileCursor = Join-Path (Get-PackHomeDir) '.cursor'
    function Get-ProfileInstallStamp($cursorDir) {
        @(@(Join-Path $cursorDir 'AgentStarterPack/install-manifest.json'), (Join-Path $cursorDir 'mcp.json')) |
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
    if (-not (Test-Path -LiteralPath (Join-Path $redirectRoot 'pack/audit/manifest.json'))) {
        Fail 'install ignored AGENT_STARTER_PACK_INSTALL_ROOT - the pack tree did not land in the scratch destination'
    } elseif (-not (Test-Path -LiteralPath (Join-Path $redirectRoot '../rules'))) {
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
$ctxProbe = Join-Path $PackRoot ".tmp/context-probe-$PID"
$savedInstallRoot = $env:AGENT_STARTER_PACK_INSTALL_ROOT
try {
    $refreshPs1 = Join-Path $PackRoot 'pack/scripts/refresh-agent-context.ps1'
    if (-not (Test-Path $refreshPs1)) { throw "refresh-agent-context.ps1 not found at $refreshPs1" }

    $fakePack = Join-Path $ctxProbe 'pack-src'
    $appProj = Join-Path $ctxProbe 'app-proj'
    $packProj = Join-Path $ctxProbe 'pack-proj'
    New-Item -ItemType Directory -Path (Join-Path $fakePack 'pack/rules') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fakePack 'pack/audit') -Force | Out-Null
    New-Item -ItemType Directory -Path $appProj -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $packProj 'pack/audit') -Force | Out-Null
    Write-Utf8NoBom (Join-Path $fakePack 'VERSION') "9.9.9`r`n"
    Write-Utf8NoBom (Join-Path $fakePack 'pack/audit/manifest.json') '{ "version": "9.9.9-audit" }'
    Write-Utf8NoBom (Join-Path $fakePack 'pack/rules/probe-rule.mdc') "# probe`r`n"
    Write-Utf8NoBom (Join-Path $appProj 'AGENTS.md') "# app`r`n"
    Write-Utf8NoBom (Join-Path $packProj 'AGENTS.md') "# pack`r`n"
    Write-Utf8NoBom (Join-Path $packProj 'install.ps1') "# marker`r`n"
    Write-Utf8NoBom (Join-Path $packProj 'pack/audit/manifest.json') '{ "version": "9.9.9-audit" }'
    # No installed pack in scope: keeps the layer state deterministic on any machine.
    $env:AGENT_STARTER_PACK_INSTALL_ROOT = (Join-Path $ctxProbe 'no-install')
    # pack-proj is a pack root, so its artifacts now resolve to a machine-local state directory.
    # Without this the probe would write its stamp into the real %LOCALAPPDATA% and leave it there -
    # a test that mutates the machine it runs on. app-proj is unaffected: not a pack root, own docs\.
    $ctxStateDir = Join-Path $ctxProbe 'state'
    $env:AGENT_STARTER_PACK_STATE_ROOT = $ctxStateDir

    function Invoke-Refresh([string]$Proj) {
        # -NoClipboard: a test must not reach into the user's clipboard.
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $refreshPs1 `
            -ProjectRoot $Proj -PackRoot $fakePack -SkipProjectSync -NoClipboard 2>&1 | Out-Null
        return $LASTEXITCODE
    }
    function Get-CtxDir([string]$Proj) {
        return (Get-AgentStateRoot -ProjectRoot $Proj)
    }
    function Get-Ctx([string]$Proj) {
        Get-Content (Join-Path (Get-CtxDir $Proj) 'AGENT_CONTEXT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $rc = Invoke-Refresh $appProj
    $ctxFile = Join-Path $appProj 'docs/AGENT_CONTEXT.json'
    $mdFile = Join-Path $appProj 'docs/AGENT_REFRESH.md'
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
        $pasteFile = Join-Path $appProj 'docs/AGENT_PASTE.txt'
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

        Write-Utf8NoBom (Join-Path $fakePack 'pack/rules/probe-rule.mdc') "# probe edited`r`n"
        [void](Invoke-Refresh $appProj)
        $c3 = Get-Ctx $appProj
        if (@($c3.changedLayers) -notcontains 'rules') { Fail 'edited rule text did not surface as a changed layer' }
        elseif ($c3.rulesRevision -eq $c2.rulesRevision) { Fail 'rulesRevision did not move when a rule changed' }
        else { Ok 'rule edits move rulesRevision and are reported' }

        # Two layers at once, so the next assertion can prove the paste line does not grow per change.
        Write-Utf8NoBom (Join-Path $fakePack 'VERSION') "9.9.10`r`n"
        Write-Utf8NoBom (Join-Path $fakePack 'pack/rules/probe-rule.mdc') "# probe edited twice`r`n"
        [void](Invoke-Refresh $appProj)
        $c4 = Get-Ctx $appProj
        $md4 = Get-Content $mdFile -Raw
        if (@($c4.changedLayers) -notcontains 'packVersion') { Fail 'pack version bump was not reported' }
        elseif ($md4 -notmatch '9\.9\.10') { Fail 'brief still cites the previous pack version' }
        else { Ok 'version bumps are reported and re-cited in the brief' }

        # The paste line must stay a pointer. An update notice that grows an entry per change becomes a
        # document, and a pasted document is what makes agents skim or stall - the whole reason the
        # change list lives in the brief, which the agent opens itself.
        $pasteMulti = [System.IO.File]::ReadAllText((Join-Path $appProj 'docs/AGENT_PASTE.txt'))
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
    # The split this asserts: a pack root writes nothing into its own docs\ (it travels), an ordinary
    # project keeps its brief there (it does not).
    $packStateMd = Join-Path $ctxStateDir 'AGENT_REFRESH.md'
    $packInFolder = Join-Path $packProj 'docs/AGENT_REFRESH.md'
    if (-not (Test-Path -LiteralPath $packStateMd)) {
        Fail "pack-root refresh did not write the brief to the state root ($packStateMd)"
    } elseif (Test-Path -LiteralPath $packInFolder) {
        Fail 'pack-root refresh wrote machine state into the portable checkout'
    } else {
        Ok 'pack root writes context outside itself; project keeps it in docs\'
    }
    $packMd = Get-Content $packStateMd -Raw
    $appMd = Get-Content $mdFile -Raw
    # Sending an app agent into the pack's own maintainer reading is the failure this split exists to
    # prevent. The discriminator was HANDOFF_NEXT_AGENT.md until 2.22.65 retired it; pack\docs\START_HERE.md
    # is the replacement because it is pack-only, whereas docs\WORK_QUEUE.md exists in both.
    if ($packMd -notmatch '(?m)^\d+\. .*START_HERE\.md') {
        Fail 'pack-repo brief does not list pack\docs\START_HERE.md as required reading'
    } elseif ($appMd -match '(?m)^\d+\. .*pack.docs.START_HERE\.md') {
        Fail "app brief sends the agent into the pack repo's maintainer reading"
    } elseif ((Get-Ctx $packProj).isPackRepo -ne $true) {
        Fail 'pack repo was not detected as a pack repo'
    } else { Ok 'pack and app briefs point at different required reading' }

    # WQ-456: the brief must name the rule files, not just say "re-read the rules".
    #
    # The defect this closes had two halves and both were invisible. install.ps1 put 13 .mdc rules in
    # %USERPROFILE%\.cursor\rules\ and 15+ docs called them always-on, but Cursor documents four rule
    # locations and a home-folder rules directory is not one of them - so nine rules carrying
    # alwaysApply: true bound nothing for months while doctor.ps1 stayed green, because every guard
    # asked whether the files had arrived at the destination rather than whether anything reads it.
    # The second half is here: the refresh brief is the only channel that can reach a chat that is
    # already open (editors build rule context at session start and never reload it), and it listed
    # docs only. `changedLayers` already said 'rules' and the prose already said "re-read the rules"
    # with no paths - unactionable, and pointing at a folder nobody reads.
    #
    # Asserted on a scratch project, both directions, because "lists the rules" and "does not list
    # them every run" fail in opposite ways: one leaves an agent stale, the other grows the required
    # reading by eighteen entries per refresh until nobody follows it.
    $ruleProj = Join-Path $ctxProbe 'rule-proj'
    $ruleProjRules = Join-Path $ruleProj '.cursor/rules'
    New-Item -ItemType Directory -Path $ruleProjRules -Force | Out-Null
    Write-Utf8NoBom (Join-Path $ruleProj 'AGENTS.md') "# rule proj`r`n"

    # Negative control: a load path with no always-on rule must report stale and say how to fix it.
    # alwaysApply:false is the planted defect - it is a rule file that must not count as loaded.
    Write-Utf8NoBom (Join-Path $ruleProjRules 'off.mdc') "---`r`ndescription: x`r`nalwaysApply: false`r`n---`r`nbody`r`n"
    [void](Invoke-Refresh $ruleProj)
    $rc1 = Get-Ctx $ruleProj
    $rMd1 = Get-Content (Join-Path $ruleProj 'docs/AGENT_REFRESH.md') -Raw
    $rFields = @('ruleLoadPath', 'loadedRulesRevision', 'alwaysOnRules') |
        Where-Object { -not ($rc1.PSObject.Properties.Name -contains $_) }
    if ($rFields) {
        Fail "stamp is missing rule-load field(s): $($rFields -join ', ')"
    } elseif ($rc1.layers.loadedRules -notlike 'stale*') {
        Fail "a folder whose only rule is alwaysApply:false reported '$($rc1.layers.loadedRules)', expected stale"
    } elseif (@($rc1.alwaysOnRules).Count -ne 0) {
        Fail "alwaysApply:false was counted as always-on ($(@($rc1.alwaysOnRules).Count) file(s))"
    } elseif ($rMd1 -notmatch 'sync-project-rules') {
        Fail 'brief reports no loaded rules but does not name the command that delivers them'
    } else { Ok 'no always-on rule in the load path reports stale and names the remedy' }

    # Positive control: one real always-on rule must flip the layer, land in requiredReads, and be
    # flagged in the brief as something the editor will not reload on its own.
    Write-Utf8NoBom (Join-Path $ruleProjRules 'on.mdc') "---`r`ndescription: y`r`nalwaysApply: true`r`n---`r`nbody`r`n"
    [void](Invoke-Refresh $ruleProj)
    $rc2 = Get-Ctx $ruleProj
    $rMd2 = Get-Content (Join-Path $ruleProj 'docs/AGENT_REFRESH.md') -Raw
    $onPath = Join-Path $ruleProjRules 'on.mdc'
    if ($rc2.layers.loadedRules -notlike 'ok*') {
        Fail "an always-on rule in the load path still reports '$($rc2.layers.loadedRules)'"
    } elseif (@($rc2.requiredReads) -notcontains $onPath) {
        Fail 'a newly loaded always-on rule is not in requiredReads - the change cannot reach an open chat'
    } elseif ($rc2.loadedRulesRevision -eq $rc1.loadedRulesRevision) {
        Fail 'loadedRulesRevision did not move when a rule arrived in the load path'
    } elseif ($rMd2 -notmatch 'will not reload it mid-session') {
        Fail 'brief lists the rule without warning that the editor will not reload it'
    } else { Ok 'a rule arriving in the load path is listed and flagged as not reloaded mid-session' }

    # The other direction: an unchanged rule set must not re-list every rule on every refresh.
    [void](Invoke-Refresh $ruleProj)
    $rc3 = Get-Ctx $ruleProj
    $mdcReads = @($rc3.requiredReads | Where-Object { $_ -match '\.mdc$' })
    if ($mdcReads.Count -ne 0) {
        Fail "steady-state refresh re-listed $($mdcReads.Count) rule file(s); required reading grows every run"
    } elseif (@($rc3.changedLayers) -contains 'loadedRules') {
        Fail 'unchanged rule set still reports loadedRules as changed'
    } else { Ok 'unchanged rule set is not re-listed on a steady-state refresh' }

    # Migration: a stamp written before rule awareness must trigger the listing once. Without this the
    # fix ships and lies dormant on exactly the installs that needed it - every existing one.
    $rcFile = Join-Path $ruleProj 'docs/AGENT_CONTEXT.json'
    $oldStamp = Get-Content $rcFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $oldStamp.PSObject.Properties.Remove('alwaysOnRules')
    $oldStamp.PSObject.Properties.Remove('loadedRulesRevision')
    Write-Utf8NoBom $rcFile ($oldStamp | ConvertTo-Json -Depth 6)
    [void](Invoke-Refresh $ruleProj)
    $rc4 = Get-Ctx $ruleProj
    if (@($rc4.requiredReads) -notcontains $onPath) {
        Fail 'a stamp predating rule awareness did not trigger the one-time rule listing'
    } else { Ok 'a pre-fix stamp migrates once and lists the always-on rules' }

    # The profile copy must stop being described as authoritative, in the artifact an agent reads.
    if ($rc4.layers.PSObject.Properties.Name -notcontains 'globalRules') {
        Fail 'stamp dropped the globalRules layer'
    } elseif ($rc4.layers.globalRules -eq 'ok') {
        Fail "globalRules still reports a bare 'ok' - it asserts nothing about whether a rule loads"
    } else { Ok "globalRules is qualified, not a bare ok: '$($rc4.layers.globalRules)'" }

    $rulePath = Join-Path $PackRoot 'pack/rules/agent-defaults-always.mdc'
    $ruleText = if (Test-Path $rulePath) { Get-Content $rulePath -Raw } else { '' }
    $manifestText = Get-Content (Join-Path $PackRoot 'pack/audit/manifest.json') -Raw
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
    # Leaving this set would redirect every later step's state resolution at a directory this block
    # just deleted, which is how one step's scaffolding becomes another step's mystery failure.
    Remove-Item Env:\AGENT_STARTER_PACK_STATE_ROOT -ErrorAction SilentlyContinue
    Remove-Item $ctxProbe -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host '28. Layout hygiene reports Improve, not delete-only Fix'
# The failure this closes: Section B only ever said "delete dist", so an agent could delete it, close
# the section, and never look at whether the tree is comprehensible. Layout findings must arrive as
# Improve, in their own manifest channel, and must not be answerable with "Nothing found."
$layoutDirs = @('MyApp_v6', 'MyApp_v6\MyApp_portable', 'MyApp_portable', 'MyApp_v6_stable', 'build')
$layoutScript = Join-Path $fixture 'scripts/publish_release.bat'
$semBackup = $null
$semLayoutPath = Join-Path $fixture 'docs/.audit_semantic_report.json'
try {
    if (Test-Path $semLayoutPath) { $semBackup = Get-Content $semLayoutPath -Raw }
    foreach ($d in $layoutDirs) { New-Item -ItemType Directory -Path (Join-Path $fixture $d) -Force | Out-Null }
    Write-Utf8NoBom (Join-Path $fixture 'MyApp_v6/MyApp.exe.txt') "placeholder`r`n"
    Write-Utf8NoBom (Join-Path $fixture 'MyApp_v6_stable/MyApp.exe.txt') "placeholder`r`n"
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

    $layoutMan = Get-Content (Join-Path $fixture 'docs/.audit_agent_manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
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
    Invoke-PackPython $codePy $fixture --write-semantic-template 2>&1 | Out-Null
    Invoke-PackPython $codePy $fixture --fill-semantic-fixture-test 2>&1 | Out-Null
    if (Test-Path $semLayoutPath) {
        $sem = Get-Content $semLayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $sem.sections.B.summary = 'Nothing found.'
        Write-Utf8NoBom $semLayoutPath ($sem | ConvertTo-Json -Depth 12)
        $vOut = Invoke-PackPython $codePy $fixture --verify-semantic-report 2>&1 | Out-String
        # Match the message, not the exit code: an unrelated failure would otherwise pass this.
        $rejected = ($vOut -match 'section B does not address \d+ machine Improve line')
        $sem.sections.B.summary = 'Reviewed layout: MyApp_v6_stable duplicates the release archive; build is ephemeral. Improve only, see `docs/AUDIT.md`.'
        Write-Utf8NoBom $semLayoutPath ($sem | ConvertTo-Json -Depth 12)
        $vOut2 = Invoke-PackPython $codePy $fixture --verify-semantic-report 2>&1 | Out-String
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
$parityDir = Join-Path $PackRoot ".tmp/parity-$PID"
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
$ctxProbe = Join-Path $fixture 'docs/AGENT_CONTEXT.json'
$ctxBackup = if (Test-Path $ctxProbe) { Get-Content $ctxProbe -Raw } else { $null }
try {
    $engineVersion = (Get-Content (Join-Path $PackRoot 'pack/audit/manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version

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
    } elseif ($staleOut -notmatch ('agent: offer to run ' +
            [regex]::Escape((Get-PackEntryPoint -Name 'Refresh-AgentContext')))) {
        # The entry point is spelled through the helper, not hardcoded: this assertion named
        # `Refresh-AgentContext.cmd` literally, so the moment the message became host-correct the
        # check failed on Linux while passing on Windows. What it is really asserting is the
        # "agent: offer to run" phrasing - the filename is incidental and must follow the host.
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
        Remove-Item (Join-Path $fixture 'docs/WORK_QUEUE.md') -Force -ErrorAction SilentlyContinue
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $ensureWq -ProjectRoot $fixture -PackRoot $PackRoot 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'ensure-work-queue failed on behavior fixture' }
        else { Ok 'ensure-work-queue runs on fixture (creates or skips)' }
        $vqOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $verifyWq -ProjectRoot $PackRoot 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Fail "pack WORK_QUEUE invalid: $vqOut" }
        else { Ok 'pack WORK_QUEUE passes verify-work-queue.ps1' }
        if (-not (Test-Path (Join-Path $fixture 'docs/WORK_QUEUE.md'))) {
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
# WQ-471: this step was one assertion - the verify exited 0 - with its output thrown away, so it
# could not say which comparison had been made, and a detector that had stopped comparing anything
# would have satisfied it. The export is the paste-at-session-start rules file for every tool that is
# not Cursor, and that population cannot notice staleness any other way, so the drift detector now
# gets a positive control on a disposable pack: plant each kind of drift and require it to be named.
try {
    $portableSync = Join-Path $PSScriptRoot 'sync-portable-docs.ps1'
    if (-not (Test-Path -LiteralPath $portableSync)) { Fail 'sync-portable-docs.ps1 missing' }
    else {
        $portOut = (Invoke-PackScript -PassOutput -NoProfile -ScriptPath $portableSync -PackRoot $PackRoot -VerifyOnly 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { Fail "portable exports stale or missing (run sync-portable-docs.ps1): $($portOut.Trim())" }
        elseif ($portOut -notmatch 'GENERIC_RULES\.md matches pack/rules') {
            Fail "the verify exited 0 without judging GENERIC_RULES.md: $($portOut.Trim())"
        } elseif ($portOut -notmatch '\d+ loaded rule\(s\) in \.cursor/rules match pack/rules') {
            Fail "the verify exited 0 without comparing this repo's loaded rules - that arm skips silently where .cursor/rules is absent, and here it must run (WQ-456): $($portOut.Trim())"
        } else { Ok 'portable GENERIC_RULES.md, skill mirrors and this repo''s loaded rules all match pack/rules' }

        # The positive control, on a pack of its own so nothing here is touched.
        $portRoot = Join-Path $PackRoot ".tmp/portable-drift-probe-$PID"
        if (Test-Path -LiteralPath $portRoot) { Remove-Item -LiteralPath $portRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path (Join-Path $portRoot 'pack/rules') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $portRoot 'pack/skills/probe-skill') -Force | Out-Null
        Write-Utf8NoBom (Join-Path $portRoot 'VERSION') '9.9.9'
        Write-Utf8NoBom (Join-Path $portRoot 'pack/rules/probe-rule.mdc') "---`r`ndescription: probe`r`nalwaysApply: false`r`n---`r`n`r`n# Probe rule`r`n`r`nBody text.`r`n"
        Write-Utf8NoBom (Join-Path $portRoot 'pack/skills/probe-skill/SKILL.md') "---`r`nname: probe-skill`r`n---`r`n`r`n# Probe skill`r`n`r`nBody text.`r`n"
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $portableSync -PackRoot $portRoot 2>&1 | Out-Null
        $probeRules = Join-Path $portRoot 'pack/docs/portable/GENERIC_RULES.md'
        $probeSkill = Join-Path $portRoot 'pack/docs/portable/skills/probe-skill.md'
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $probeRules) -or -not (Test-Path -LiteralPath $probeSkill)) {
            Fail 'the sync did not produce exports on a minimal pack, so the drift controls below would prove nothing'
        } else {
            $driftCases = @(
                @{
                    What   = 'a stale rules export'
                    Plant  = { Write-Utf8NoBom $probeRules ((Get-Content -LiteralPath $probeRules -Raw -Encoding UTF8) + "edited by hand`r`n") }
                    Expect = 'GENERIC_RULES.md is stale'
                },
                @{
                    What   = 'a deleted rules export'
                    Plant  = { Remove-Item -LiteralPath $probeRules -Force }
                    Expect = 'missing'
                },
                @{
                    What   = 'a stale skill mirror'
                    Plant  = { Write-Utf8NoBom $probeSkill "not what the skill says`r`n" }
                    Expect = 'stale skill export: probe-skill.md'
                },
                @{
                    What   = 'a loaded rule that drifted from pack/rules'
                    Plant  = {
                        New-Item -ItemType Directory -Path (Join-Path $portRoot '.cursor/rules') -Force | Out-Null
                        Write-Utf8NoBom (Join-Path $portRoot '.cursor/rules/probe-rule.mdc') "---`r`ndescription: probe`r`nalwaysApply: false`r`n---`r`n`r`n# Probe rule`r`n`r`nSomething else entirely.`r`n"
                    }
                    Expect = 'loaded rules drifted from pack/rules \(probe-rule\.mdc\)'
                }
            )
            $driftMissed = @()
            foreach ($c in $driftCases) {
                # Each case starts from a clean export, so one plant cannot be proven by another's damage.
                Invoke-PackScript -PassOutput -NoProfile -ScriptPath $portableSync -PackRoot $portRoot 2>&1 | Out-Null
                Remove-Item (Join-Path $portRoot '.cursor') -Recurse -Force -ErrorAction SilentlyContinue
                & $c.Plant
                $driftOut = (Invoke-PackScript -PassOutput -NoProfile -ScriptPath $portableSync -PackRoot $portRoot -VerifyOnly 2>&1 | Out-String)
                if ($LASTEXITCODE -eq 0) { $driftMissed += "$($c.What) verified clean" }
                elseif ($driftOut -notmatch $c.Expect) { $driftMissed += "$($c.What) rejected without naming it: $($driftOut.Trim())" }
            }
            if ($driftMissed.Count -gt 0) { Fail "planted export drift not reported: $($driftMissed -join ' | ')" }
            else { Ok "all $($driftCases.Count) kinds of export drift are detected and named" }
        }
        Remove-Item -LiteralPath $portRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    Fail "portable export checks error: $_"
}

Write-Host "`n33. Portable bootstrap (-Targets Portable)"
try {
    $portableVerify = Join-Path $PSScriptRoot 'verify-portable-bootstrap.ps1'
    $bootstrap = Join-Path $PackRoot 'pack/scripts/bootstrap-project.ps1'
    if (-not (Test-Path -LiteralPath $portableVerify)) { Fail 'verify-portable-bootstrap.ps1 missing' }
    elseif (-not (Test-Path -LiteralPath $bootstrap)) { Fail 'bootstrap-project.ps1 missing' }
    else {
        $portableRoot = Join-Path $PackRoot ".tmp/bootstrap-portable-$PID"
        $portableProj = Join-Path $portableRoot 'PortableApp'
        if (Test-Path -LiteralPath $portableRoot) { Remove-Item -LiteralPath $portableRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $portableRoot -Force | Out-Null
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $bootstrap -ProjectRoot $portableProj `
            -ProjectName 'PortableApp' -Stack Generic -Targets Portable -NoPause 2>&1 | Out-Null
        # WQ-471: a zero exit was the whole assertion here, so a bootstrap that generated nothing and
        # a verify that judged nothing would both have satisfied this step. The files a Portable
        # project is bootstrapped *for* are read directly, and the verify has to name the profile it
        # enforced rather than merely exiting 0.
        $portableMissing = @()
        foreach ($rel in @('AI_INSTRUCTIONS.md', 'docs/portable/GENERIC_RULES.md', '.agent-bootstrap.json')) {
            if (-not (Test-Path -LiteralPath (Join-Path $portableProj $rel))) { $portableMissing += $rel }
        }
        if ($LASTEXITCODE -ne 0) { Fail "Portable bootstrap exited $LASTEXITCODE" }
        elseif ($portableMissing.Count -gt 0) {
            Fail "Portable bootstrap exited 0 without writing: $($portableMissing -join ', ')"
        } else { Ok 'Portable bootstrap writes the instructions hub and the rules export it promises' }
        $portableVerifyOut = (Invoke-PackScript -PassOutput -NoProfile -ScriptPath $portableVerify -ProjectRoot $portableProj -RequirePortableOnly 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { Fail "verify-portable-bootstrap failed on Portable target project: $($portableVerifyOut.Trim())" }
        elseif ($portableVerifyOut -notmatch 'Portable-only bootstrap profile') {
            Fail "the verify exited 0 without asserting the Portable-only profile - the one thing -RequirePortableOnly is for: $($portableVerifyOut.Trim())"
        } else { Ok 'Portable bootstrap matches verify-portable-bootstrap profile, and the verify says which profile' }
        Remove-Item -LiteralPath $portableRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    Fail "Portable bootstrap checks error: $_"
}

Write-Host "`n34. Tool adapter register (Claude/Copilot/Windsurf)"
try {
    $adapterScript = Join-Path $PSScriptRoot 'register-tool-adapters.ps1'
    $bootstrap = Join-Path $PackRoot 'pack/scripts/bootstrap-project.ps1'
    if (-not (Test-Path -LiteralPath $adapterScript)) { Fail 'register-tool-adapters.ps1 missing' }
    elseif (-not (Test-Path -LiteralPath $bootstrap)) { Fail 'bootstrap-project.ps1 missing' }
    else {
        $adapterRoot = Join-Path $PackRoot ".tmp/bootstrap-adapters-$PID"
        $adapterProj = Join-Path $adapterRoot 'AdapterApp'
        if (Test-Path -LiteralPath $adapterRoot) { Remove-Item -LiteralPath $adapterRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $adapterRoot -Force | Out-Null
        # Comma-joined, and then checked against what landed on disk. Passed as @('Claude','Copilot',
        # 'Windsurf') this step bootstrapped a project for **Claude only**: Invoke-PackScript sends
        # arguments through `-File`, whose binder keeps the first element of a list and discards the
        # rest without a word. register-tool-adapters then reported the two missing adapters as
        # "skipped (not in bootstrap targets)" and exited 0, so both lines below printed OK while
        # two thirds of this step's subject was never written. Found by a guard proof: mutating the
        # Windsurf template changed nothing, because no Windsurf file was ever there.
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $bootstrap -ProjectRoot $adapterProj `
            -ProjectName 'AdapterApp' -Stack Generic -Targets 'Claude,Copilot,Windsurf' -NoPause 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "editor-target bootstrap exited $LASTEXITCODE" }
        else { Ok 'Claude/Copilot/Windsurf bootstrap exits 0' }

        # The list survived the trip: asserted on the project, not on the argument, because the
        # argument looked correct the whole time it was being dropped.
        $bootRecord = Join-Path $adapterProj '.agent-bootstrap.json'
        $recordedTargets = @()
        if (Test-Path -LiteralPath $bootRecord) {
            try { $recordedTargets = @((Get-Content -LiteralPath $bootRecord -Raw -Encoding UTF8 | ConvertFrom-Json).targets) } catch { }
        }
        $missingTargets = @(@('Claude', 'Copilot', 'Windsurf') | Where-Object { $recordedTargets -notcontains $_ })
        if ($missingTargets.Count -gt 0) {
            Fail "bootstrap recorded targets [$($recordedTargets -join ', ')] - the list did not survive the call, so $($missingTargets -join ', ') were never written"
        } else { Ok 'all three editor targets survive the call into bootstrap' }

        $adapterFiles = @(
            @{ Rel = 'CLAUDE.md'; Label = 'Claude' },
            @{ Rel = '.github/copilot-instructions.md'; Label = 'Copilot' },
            @{ Rel = '.windsurfrules'; Label = 'Windsurf' }
        )
        $absentAdapters = @($adapterFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $adapterProj $_.Rel)) } |
            ForEach-Object { "$($_.Label) ($($_.Rel))" })
        if ($absentAdapters.Count -gt 0) {
            Fail "editor-target bootstrap wrote no adapter for: $($absentAdapters -join ', ')"
        } else { Ok 'all three adapter files are on disk to be checked' }

        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $adapterScript -ProjectRoot $adapterProj -Tool All -NoPause 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'register-tool-adapters failed on editor-target project' }
        else { Ok 'register-tool-adapters passes on Claude/Copilot/Windsurf project' }

        # A registration that skips every tool also exits 0, which is how the defect above stayed
        # invisible. Require the run to have judged all three by name.
        $adapterOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $adapterScript -ProjectRoot $adapterProj -Tool 'Claude,Copilot,Windsurf' -NoPause 2>&1 | Out-String
        $skipped = @($adapterFiles | Where-Object { $adapterOut -match "$($_.Label) adapter skipped" } | ForEach-Object { $_.Label })
        if ($skipped.Count -gt 0) {
            Fail "register-tool-adapters skipped $($skipped -join ', ') and still exited 0 - an exit code alone does not say what it read"
        } else { Ok 'registration judged all three adapters rather than skipping them' }
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
        $selfOut = Invoke-PackPython $freshPy --self-test 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Fail "agent_context_freshness self-test failed: $selfOut" }
        else { Ok 'agent_context_freshness.py self-test passes' }
        $mcpPy = Join-Path $PackRoot 'mcp/agent_hygiene_server.py'
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
    elseif (-not (Test-Path -LiteralPath (Join-Path $PackRoot 'pack/docs/WORK_COMPLETION.md'))) {
        Fail 'pack/docs/WORK_COMPLETION.md missing'
    } else {
        $probeRoot = Join-Path $PackRoot ".tmp/archive-probe-$PID"
        if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path (Join-Path $probeRoot 'docs/handoffs/active') -Force | Out-Null
        $handoffName = 'HANDOFF_WQ099_probe.md'
        $handoffPath = Join-Path $probeRoot "docs/handoffs/active/$handoffName"
        $wqPath = Join-Path $probeRoot 'docs/WORK_QUEUE.md'

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
        $archPath = Join-Path $probeRoot "docs/handoff_archive/$handoffName"
        if (Test-Path -LiteralPath $handoffPath) { Fail '-Apply did not move handoff when all gates pass' }
        elseif (-not (Test-Path -LiteralPath $archPath)) { Fail 'handoff missing from handoff_archive after -Apply' }
        else { Ok '-Apply moves to handoff_archive when all gates pass' }

        New-Item -ItemType Directory -Path (Join-Path $probeRoot 'docs/handoffs/active') -Force | Out-Null
        Write-ProbeHandoff 'completed' '2026-01-01'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $archiveScript -ProjectRoot $probeRoot -Apply -SkipVerify 2>&1 | Out-Null
        if (-not (Test-Path -LiteralPath $archPath)) { Fail 'second apply removed archive copy' }
        else { Ok 'second -Apply skips when archive file already exists' }
    }
} catch {
    Fail "handoff archive script checks error: $_"
} finally {
    Remove-Item (Join-Path $PackRoot ".tmp/archive-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n37. Complete-picture handoff verify (WQ-206)"
try {
    $cpScript = Join-Path $PSScriptRoot 'verify-complete-picture.ps1'
    if (-not (Test-Path -LiteralPath $cpScript)) { Fail 'verify-complete-picture.ps1 missing' }
    elseif (Test-PackPublishZoneBTree $PackRoot) {
        Ok 'Zone B publish tree - complete-picture skipped (maintainer handoffs stripped by B09)'
    } else {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $cpScript -ProjectRoot $PackRoot 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'pack repo failed verify-complete-picture.ps1' }
        else { Ok 'pack repo passes complete-picture handoff checks' }
        $probeRoot = Join-Path $PackRoot ".tmp/complete-picture-probe-$PID"
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
        Write-Utf8NoBom (Join-Path $probeRoot 'docs/WORK_QUEUE.md') @"
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
        # 2.22.65: the stale-claim scan reads the queue's own Active section instead of a session
        # document's section 11. Same defect class, one fewer document to disagree with.
        Write-Utf8NoBom (Join-Path $probeRoot 'docs/WORK_QUEUE.md') @"
# Work queue probe

## Active queue

| ID | Task | Status | Notes |
|----|------|--------|-------|
| WQ-001 | live | **Next** | WQ-308 (parked) |

## Done log

| ID | Task | Completed | Evidence |
|----|------|-----------|----------|
| WQ-999 | old | 2026-01-01 | done |
"@
        $auditOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $cpScript -ProjectRoot $probeRoot -AuditMode 2>&1 | Out-String
        if ($auditOut -notmatch '\[IMPROVE\]') { Fail 'AuditMode did not report a stale shipped-task phrase in the Active queue' }
        else { Ok 'AuditMode flags stale shipped-task phrases in the queue' }

        # An id in Active and Done at once is the self-contradiction a single status claim can still
        # produce, and it is a FIX rather than an Improve: one of the two rows is simply wrong.
        Write-Utf8NoBom (Join-Path $probeRoot 'docs/WORK_QUEUE.md') @"
# Work queue probe

## Active queue

| ID | Task | Status | Notes |
|----|------|--------|-------|
| WQ-001 | live | **Next** | |

## Done log

| ID | Task | Completed | Evidence |
|----|------|-----------|----------|
| WQ-001 | same id | 2026-01-01 | done |
"@
        $dupOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $cpScript -ProjectRoot $probeRoot -AuditMode 2>&1 | Out-String
        if ($dupOut -notmatch '\[FIX\].*both Active and Done') { Fail 'an id in both Active and Done was not reported as FIX' }
        else { Ok 'AuditMode reports an id listed in both Active and Done' }

        $roadmapProbe = Join-Path $PackRoot ".tmp/roadmap-probe-$PID"
        if (Test-Path -LiteralPath $roadmapProbe) { Remove-Item -LiteralPath $roadmapProbe -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path (Join-Path $roadmapProbe 'docs') -Force | Out-Null
        Write-Utf8NoBom (Join-Path $roadmapProbe 'docs/WORK_QUEUE.md') @"
# Work queue probe

## Done log

| ID | Task | Completed | Evidence |
|----|------|-----------|----------|
| WQ-042 | shipped slice | 2026-01-01 | done |
"@
        Write-Utf8NoBom (Join-Path $roadmapProbe 'docs/ROADMAP.md') @"
# Roadmap probe

## Work queue (current)

| Name | PLAN | Phase | Status |
|------|------|-------|--------|
| Old slice | plan.md | 1 | **Next** - WQ-042 handoff [handoffs/active/HANDOFF_WQ042_feature.md](handoffs/active/HANDOFF_WQ042_feature.md) |
"@
        # These probes are deliberately sparse projects, so the verify has several honest reasons to
        # exit non-zero. Asserting only the exit code lets each arm pass while the check it names is
        # switched off - three fixtures in WQ-462 batches five and six did exactly that, so every
        # rejection here has to name itself.
        $rmOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $cpScript -ProjectRoot $roadmapProbe 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Fail 'ROADMAP probe should FAIL when Done WQ still reads Next' }
            # Not bare 'ROADMAP': -notmatch is case-insensitive and the probe's own directory name
            # carries the word, so the loose form matched any output that echoed the project root.
            elseif ($rmOut -notmatch 'ROADMAP still marks') {
            Fail "the ROADMAP probe failed for some other reason: $($rmOut.Trim())"
        } else { Ok 'complete-picture FAILs ROADMAP Next/active handoff for Done WQ, naming ROADMAP' }

        $ptProbe = Join-Path $PackRoot ".tmp/cp-product-truth-probe-$PID"
        if (Test-Path -LiteralPath $ptProbe) { Remove-Item -LiteralPath $ptProbe -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path (Join-Path $ptProbe 'docs') -Force | Out-Null
        Write-Utf8NoBom (Join-Path $ptProbe 'docs/WORK_COMPLETION.md') @"
# overlay

### Product-truth docs

| Role | Path |
|------|------|
| Cap | ``docs\PRODUCT_REFERENCE.md`` |
"@
        # A WORK_QUEUE is required for the delegation to be reached at all. Without it the verify
        # stopped at `no handoff sources found` and this arm passed on that, never once exercising the
        # product-truth delegation it claims to prove - found by asserting the rejection text below.
        Write-Utf8NoBom (Join-Path $ptProbe 'docs/WORK_QUEUE.md') @"
# probe

| Field | Value |
|-------|--------|
| **Next active ID** | **WQ-001** |

## Active queue

| ID | Task | Status |
|----|------|--------|
| WQ-001 | probe | **Next** |

## Inbox

## Parked / deferred

## Done log

| ID | Task | Completed | Evidence |
|----|------|-----------|----------|
"@
        $ptOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $cpScript -ProjectRoot $ptProbe 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Fail 'complete-picture should FAIL when delegated product-truth path missing' }
        elseif ($ptOut -notmatch 'PRODUCT_REFERENCE|product-truth') {
            Fail "the product-truth probe failed for some other reason - the delegation may not be happening: $($ptOut.Trim())"
        } else { Ok 'complete-picture delegates product-truth path verify, naming the missing doc' }

        $hdrProbe = Join-Path $PackRoot ".tmp/wq-header-probe-$PID"
        if (Test-Path -LiteralPath $hdrProbe) { Remove-Item -LiteralPath $hdrProbe -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path (Join-Path $hdrProbe 'docs'), (Join-Path $hdrProbe 'pack/audit') -Force | Out-Null
        Write-Utf8NoBom (Join-Path $hdrProbe 'install.ps1') "# probe`r`n"
        Write-Utf8NoBom (Join-Path $hdrProbe 'pack/audit/manifest.json') '{ "version": "0.0.0" }'
        Write-Utf8NoBom (Join-Path $hdrProbe 'docs/WORK_QUEUE.md') @"
# probe

| Field | Value |
|-------|--------|
| **Next active ID** | **WQ-999** |

## Active queue

| ID | Task | Status |
|----|------|--------|
| WQ-001 | other | **Next** |

## Inbox

## Parked / deferred

## Done log
"@
        $hdrOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $cpScript -ProjectRoot $hdrProbe 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Fail 'pack probe should FAIL when WORK_QUEUE header Next != Active Next' }
        elseif ($hdrOut -notmatch 'WQ-999|WQ-001|Next active') {
            Fail "the header-mismatch probe failed for some other reason: $($hdrOut.Trim())"
        } else { Ok 'complete-picture FAILs WORK_QUEUE header vs Active Next mismatch, naming the ids' }
    }
} catch {
    Fail "complete-picture checks error: $_"
} finally {
    Remove-Item (Join-Path $PackRoot ".tmp/complete-picture-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $PackRoot ".tmp/roadmap-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $PackRoot ".tmp/cp-product-truth-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $PackRoot ".tmp/wq-header-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
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
        $probeRoot = Join-Path $PackRoot ".tmp/session-start-probe-$PID"
        if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path (Join-Path $probeRoot 'docs') -Force | Out-Null
        Write-Utf8NoBom -Path (Join-Path $probeRoot 'AGENTS.md') -Text "# probe`r`n"
        $engine = (Get-Content -LiteralPath (Join-Path $PackRoot 'pack/audit/manifest.json') -Raw | ConvertFrom-Json).version
        $freshInstall = Join-Path $probeRoot 'installed-fresh'
        New-Item -ItemType Directory -Path (Join-Path $freshInstall 'pack/audit') -Force | Out-Null
        Write-Utf8NoBom -Path (Join-Path $freshInstall 'pack/audit/manifest.json') -Text "{`"version`": `"$engine`"}`r`n"
        $env:AGENT_STARTER_PACK_INSTALL_ROOT = $freshInstall
        Write-Utf8NoBom -Path (Join-Path $probeRoot 'docs/AGENT_CONTEXT.json') -Text (@{
            schemaVersion = 2
            auditEngineVersion = [string]$engine
            packVersion = '1.8.0'
            canonicalProjectRoot = $probeRoot
            requiredReads = @((Join-Path $probeRoot 'AGENTS.md'))
            layers = @{ installedPack = 'ok' }
        } | ConvertTo-Json -Depth 4)

        $briefJson = Invoke-PackPython $freshPy --session-brief --project-root $probeRoot 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Fail "session-brief failed: $briefJson" }
        else {
            $brief = $briefJson | ConvertFrom-Json
            if ($brief.stale) { Fail 'fresh stamp should not be stale in session-brief probe' }
            elseif ($brief.permission -ne 'none') { Fail 'fresh session-brief permission should be none' }
            elseif (-not $brief.openerLine) { Fail 'session-brief missing openerLine' }
            else { Ok 'session-brief JSON for fresh context' }
        }

        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $invokeFresh -ProjectRoot $probeRoot -WriteSessionStart 2>&1 | Out-Null
        $ssoPath = Join-Path $probeRoot 'docs/AGENT_SESSION_START.md'
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

        $giSnippet = Join-Path $PackRoot 'pack/templates/docs/gitignore.audit.snippet'
        if (-not (Select-String -Path $giSnippet -Pattern 'AGENT_SESSION_START' -Quiet)) {
            Fail 'gitignore snippet missing AGENT_SESSION_START.md'
        } else { Ok 'gitignore snippet tracks AGENT_SESSION_START.md' }

        $bootstrap = Join-Path $PackRoot 'pack/scripts/bootstrap-project.ps1'
        $hookRoot = Join-Path $PackRoot ".tmp/session-hook-probe-$PID"
        if (Test-Path -LiteralPath $hookRoot) { Remove-Item -LiteralPath $hookRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $hookRoot -Force | Out-Null
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $bootstrap -ProjectRoot (Join-Path $hookRoot 'HookApp') `
            -ProjectName 'HookApp' -Stack Generic -Targets Cursor -NoPause 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'Cursor bootstrap for session hook exited non-zero' }
        else {
            $hookProj = Join-Path $hookRoot 'HookApp'
            $hookJson = Join-Path $hookProj '.cursor/hooks.json'
            $hookPs1 = Join-Path $hookProj '.cursor/hooks/session-freshness.ps1'
            if (-not (Test-Path -LiteralPath $hookJson)) { Fail 'bootstrap missing .cursor/hooks.json' }
            elseif (-not (Test-Path -LiteralPath $hookPs1)) { Fail 'bootstrap missing session-freshness.ps1' }
            else { Ok 'bootstrap installs Cursor sessionStart hook files' }
        }

        if ($hookProj -and (Test-Path -LiteralPath $hookPs1)) {
            Write-Utf8NoBom -Path (Join-Path $hookProj 'AGENTS.md') -Text "# hook probe`r`n"
            Write-Utf8NoBom -Path (Join-Path $hookProj 'docs/AGENT_CONTEXT.json') -Text (@{
                schemaVersion = 2
                auditEngineVersion = [string]$engine
                packVersion = '1.8.0'
                canonicalProjectRoot = $hookProj
                requiredReads = @((Join-Path $hookProj 'AGENTS.md'))
                layers = @{ installedPack = 'ok' }
            } | ConvertTo-Json -Depth 4)
            # Started the way Cursor starts it - stdin redirected, then closed - and bounded, which
            # the plain call here was not. That mattered: a hook that reads stdin without a bound
            # does not fail this arm, it hangs it, and with it the suite and anything waiting on the
            # suite. That is the 2.22.63 incident reproducing inside the guard meant to catch it,
            # found when a mutation restoring the original defect ran for half an hour instead of
            # failing in twenty seconds.
            $hookArgs = if (Test-PackIsWindows) {
                "-NoProfile -ExecutionPolicy Bypass -File `"$hookPs1`""
            } else {
                "-NoProfile -File `"$hookPs1`""
            }
            $freshPsi = New-Object System.Diagnostics.ProcessStartInfo
            $freshPsi.FileName = Get-PackPowerShellPath
            $freshPsi.Arguments = $hookArgs
            $freshPsi.WorkingDirectory = $hookProj
            $freshPsi.RedirectStandardInput = $true
            $freshPsi.RedirectStandardOutput = $true
            $freshPsi.RedirectStandardError = $true
            $freshPsi.UseShellExecute = $false
            $freshProc = [System.Diagnostics.Process]::Start($freshPsi)
            try {
                $freshProc.StandardInput.Close()
                if (-not $freshProc.WaitForExit(20000)) {
                    Fail 'sessionStart hook did not return within 20s with stdin closed, as Cursor leaves it'
                } elseif ($freshProc.ExitCode -ne 0) {
                    Fail "session-freshness.ps1 exited $($freshProc.ExitCode)"
                } else {
                    $hookOut = $freshProc.StandardOutput.ReadToEnd()
                    $parsed = $hookOut.Trim() | ConvertFrom-Json
                    if (-not $parsed.PSObject.Properties['additional_context']) {
                        Fail 'hook stdout missing additional_context'
                    } elseif ($parsed.additional_context -notmatch 'Agent context OK') {
                        Fail 'fresh hook should mention context OK'
                    } else { Ok 'sessionStart hook emits Cursor JSON on fresh context' }
                }
            } finally {
                if (-not $freshProc.HasExited) { $freshProc.Kill() }
                $freshProc.Dispose()
            }

            # The same hook, started the way anything other than Cursor starts it: stdin redirected and
            # never written to. Cursor closes the handle after its payload, so the hook's
            # [Console]::In.ReadToEnd() returned instantly and this step passed for four releases -
            # while bash holds the pipe open, and `./run_audit.sh` therefore hung the entire audit for
            # eleven minutes with no output. A read that never returns throws nothing, so the script's
            # fail-open guarantee could not catch it (2.22.63). Assert the hook always returns.
            $hookHost = Get-PackPowerShellPath
            $hookArgList = if (Test-PackIsWindows) {
                "-NoProfile -ExecutionPolicy Bypass -File `"$hookPs1`""
            } else {
                "-NoProfile -File `"$hookPs1`""
            }
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $hookHost
            $psi.Arguments = $hookArgList
            $psi.WorkingDirectory = $hookProj
            $psi.RedirectStandardInput = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $hookProc = [System.Diagnostics.Process]::Start($psi)
            try {
                if (-not $hookProc.WaitForExit(20000)) {
                    Fail ('sessionStart hook blocked for 20s with stdin held open - an unbounded ' +
                        'stdin read hangs every session start that is not Cursor')
                } else {
                    $blockOut = $hookProc.StandardOutput.ReadToEnd().Trim()
                    if ($blockOut -notmatch 'additional_context') {
                        Fail "hook returned without Cursor JSON when stdin stayed open: $blockOut"
                    } else { Ok 'sessionStart hook returns with stdin held open (no unbounded read)' }
                }
            } finally {
                if (-not $hookProc.HasExited) { $hookProc.Kill() }
                $hookProc.Dispose()
            }
        }

        # Both directions, or the step proves nothing: a probe that reports "fresh" because it cannot
        # find an install to compare against would have passed every assertion above. Point the same
        # fixture at an install one version behind and the verdict must flip, naming both versions.
        $staleInstall = Join-Path $probeRoot 'installed-stale'
        New-Item -ItemType Directory -Path (Join-Path $staleInstall 'pack/audit') -Force | Out-Null
        Write-Utf8NoBom -Path (Join-Path $staleInstall 'pack/audit/manifest.json') -Text "{`"version`": `"0.0.1`"}`r`n"
        $env:AGENT_STARTER_PACK_INSTALL_ROOT = $staleInstall
        $staleJson = Invoke-PackPython $freshPy --session-brief --project-root $probeRoot 2>&1 | Out-String
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
    Remove-Item (Join-Path $PackRoot ".tmp/session-start-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $PackRoot ".tmp/session-hook-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n39. Hub doc repair + project-local portable rules (WQ-308 D3)"
try {
    $repairDocs = Join-Path $PSScriptRoot 'repair-agent-docs.ps1'
    if (-not (Test-Path -LiteralPath $repairDocs)) { Fail 'repair-agent-docs.ps1 missing' }
    else {
        $repairRoot = Join-Path $PackRoot ".tmp/repair-docs-probe-$PID"
        if (Test-Path -LiteralPath $repairRoot) { Remove-Item -LiteralPath $repairRoot -Recurse -Force -ErrorAction SilentlyContinue }
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath (Join-Path $PSScriptRoot 'bootstrap-project.ps1') `
            -ProjectRoot (Join-Path $repairRoot 'RepairProbe') -ProjectName 'RepairProbe' -Stack Generic -Targets Portable -NoPause 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "Portable bootstrap for repair probe exited $LASTEXITCODE" }
        else {
            $proj = Join-Path $repairRoot 'RepairProbe'
            Remove-Item (Join-Path $proj 'docs/portable/GENERIC_RULES.md') -Force -ErrorAction SilentlyContinue
            $aiPath = Join-Path $proj 'AI_INSTRUCTIONS.md'
            if (Test-Path -LiteralPath $aiPath) {
                $aiOld = Get-Content -LiteralPath $aiPath -Raw -Encoding UTF8
                $aiOld = $aiOld -replace 'user verifies', 'user reviews'
                Write-Utf8NoBom -Path $aiPath -Text $aiOld
            }
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairDocs -ProjectRoot $proj -PackRoot $PackRoot 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Fail 'repair-agent-docs.ps1 failed on probe project' }
            elseif (-not (Test-Path -LiteralPath (Join-Path $proj 'docs/portable/GENERIC_RULES.md'))) {
                Fail 'repair did not restore docs/portable/GENERIC_RULES.md'
            } else {
                $aiNew = Get-Content -LiteralPath $aiPath -Raw -Encoding UTF8
                if ($aiNew -notmatch 'user verifies') { Fail 'repair did not restore execute/verify in AI_INSTRUCTIONS.md' }
                else { Ok 'repair-agent-docs restores hub patterns and portable GENERIC_RULES' }
            }
            # WQ-471: this arm asserted a zero exit and read nothing, so it could not tell a working
            # verify from one reporting "matches pack export" about a file that is not on disk - which
            # is exactly what step 39's own mutation makes it do. Both directions are now asserted by
            # the line the script prints, not by its exit code.
            $verifyOut = (Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairDocs -ProjectRoot $proj -PackRoot $PackRoot -VerifyOnly 2>&1 | Out-String)
            $verifyRc = $LASTEXITCODE
            if ($verifyRc -ne 0) { Fail "repair-agent-docs -VerifyOnly failed after repair: $($verifyOut.Trim())" }
            elseif ($verifyOut -notmatch 'GENERIC_RULES\.md matches pack export') {
                Fail "-VerifyOnly exited 0 without judging the portable export - a silent pass cannot distinguish a match from a check that never ran: $($verifyOut.Trim())"
            } else {
                Remove-Item (Join-Path $proj 'docs/portable/GENERIC_RULES.md') -Force -ErrorAction SilentlyContinue
                $goneOut = (Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairDocs -ProjectRoot $proj -PackRoot $PackRoot -VerifyOnly 2>&1 | Out-String)
                if ($LASTEXITCODE -eq 0) {
                    Fail 'a project whose portable GENERIC_RULES.md is deleted passes -VerifyOnly - the case the repair exists for is the case it cannot see'
                } elseif ($goneOut -notmatch 'GENERIC_RULES\.md stale vs pack export|docs/portable/ missing') {
                    Fail "-VerifyOnly rejected the project without naming the missing export: $($goneOut.Trim())"
                } else { Ok 'repair-agent-docs -VerifyOnly names the export it judged, in both directions' }
            }
        }
    }
} catch {
    Fail "hub doc repair checks error: $_"
} finally {
    Remove-Item (Join-Path $PackRoot ".tmp/repair-docs-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n40. OS shell helper smoke (WQ-304 Phase 1)"
try {
    if (-not (Get-Command Test-PackIsWindows -ErrorAction SilentlyContinue)) {
        Fail 'pack-paths missing Test-PackIsWindows'
    } elseif (-not (Get-Command Invoke-PackScript -ErrorAction SilentlyContinue)) {
        Fail 'pack-paths missing Invoke-PackScript'
    } else {
        $probeRoot = Join-Path $PackRoot ".tmp/shell-helper-probe-$PID"
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
    Remove-Item (Join-Path $PackRoot ".tmp/shell-helper-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n41. OS preflight scope (WQ-304 Phase 3)"
try {
    $reqScript = Join-Path $PackRoot 'pack/scripts/check-requirements.ps1'
    $docScript = Join-Path $PackRoot 'pack/scripts/doctor.ps1'
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
    $wrapSh = Join-Path $PackRoot 'pack/scripts/pwsh-wrap.sh'
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
    $probeScript = Join-Path $PackRoot 'pack/scripts/test-os-portability-probe.ps1'
    if (-not (Test-Path -LiteralPath $probeScript)) { Fail 'test-os-portability-probe.ps1 missing' }
    elseif (-not (Select-String -Path (Join-Path $PackRoot 'pack/scripts/pack-paths.ps1') -Pattern 'AGENT_STARTER_PACK_TEST_OS' -Quiet)) {
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
    $vsysPath = Join-Path $PackRoot 'pack/scripts/verify-audit-system.ps1'
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
    $encAudit = Join-Path $encProj 'docs/AUDIT.md'
    $emDash = [char]0x2014
    # Inside a checklist section, not appended at the end: only section bullets and domain-map rows
    # are copied into the manifest, so a trailing line proves nothing.
    $marker = "encoding probe $emDash keep this dash"
    $encText = (Get-Content -LiteralPath $encAudit -Raw -Encoding UTF8) -replace '- no legacy audit rules', "- no legacy audit rules`r`n- $marker"
    Write-Utf8NoBom $encAudit $encText
    Invoke-PackScript -NoProfile -ScriptPath $corePs1 -RepoRoot $encProj -AppRoot $encProj -SkipTests *> $null
    $encMan = Join-Path $encProj 'docs/.audit_agent_manifest.json'
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
        'HANDOFF_NEXT_AGENT'         = "this repo's retired session doc - do not resurrect the name"
        'WEEKEND_HANDOFF'            = 'a maintainer-only transfer note'
        'MULTI_TOOL_GAP_PLAN'        = 'a pack-only plan doc'
        'PACK_IMPLEMENTER'           = 'a pack-only spec'
        'AGENT_COORDINATION_BACKLOG' = 'a pack-only backlog'
        'Phase 6[a-z]?\b'            = 'a phase number that means nothing outside this repo'
        '\u00A7\s*\d+'               = 'a section number in one of this repo''s docs'
    }
    $ruleDir = Join-Path $PackRoot 'pack/rules'
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
    # Shared with step 81, which holds the same documents to the same standard for the other three
    # roots - see Get-PackCitedReferenceFile for why that list has one home.
    $refFiles = @(Get-PackCitedReferenceFile -PackRoot $PackRoot)
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
                $_.Name -ne 'AUDIT_SYSTEM_CHANGELOG.md' -and
                # A linter has to spell the word it bans, so it cannot lint itself. Name, not full
                # path: a probe copy of this script under a scratch root is the same file.
                $_.Name -ne (Split-Path $PSCommandPath -Leaf) -and
                # Same reason, third file: the WQ-443 registry stores the *defect* each step is proven
                # by, and step 49's defect is the retired word itself. Found by the mutation runner's
                # baseline, which refused the whole batch because adding that spec made the pack fail
                # this step - a general constraint worth remembering, since a mutation spec cannot hold
                # text another guard bans without tripping it from inside the registry.
                $_.Name -ne 'behavior-controls.json' -and
                $vocabExts -contains $_.Extension -and
                # Relative, so a scratch pack root under .tmp does not exclude its own contents.
                -not (Test-PackPathHasSegment -Path (Get-PackRelPathKey -Path $_.FullName -Root $PackRoot) `
                        -Segment @('.git', '__pycache__', '.tmp'))
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

# 50. No machine identity leaves this checkout
# The pack folder travels - USB, robocopy, a zip - and it had been carrying the sending machine's
# identity: docs/WORK_COMPLETION.md (generated with {{PROJECT_ROOT}} replaced by an absolute path) and
# docs/AGENT_SESSION_START.md were both committed with one maintainer's user profile path, and a stale
# install-manifest.json was tracked despite being gitignored. Four lists disagreed about what counts as
# machine-local - .gitignore, export.ps1, install.ps1 and a hardcoded array in this file - which is how
# a file could be dropped from the export and committed anyway. machineLocalPaths in the manifest is now
# the only list; this step fails when a consumer drifts from it or when a real user name appears.
Write-Host "`n50. No machine identity leaves this checkout"
try {
    $mlManifest = Get-Content -LiteralPath (Join-Path $PackRoot 'pack/audit/manifest.json') -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $machineLocal = @($mlManifest.machineLocalPaths | Where-Object { $_ })
    if ($machineLocal.Count -eq 0) {
        Fail 'manifest has no machineLocalPaths - nothing declares which files carry this machine''s paths'
    }

    # Illustration names are the point of the convention: docs need *a* concrete path to show, and
    # placeholder tokens ($env:, %USERPROFILE%, <you>) are substituted before anyone runs them.
    # WQ-441: one list, shared with the Illustrative policy in verify-lib.ps1, so a name that is legal
    # in a doc cannot become illegal in this scan without both moving together.
    $allowedUsers = @(Get-PackIllustrationUserName)
    $textExts = @('.md', '.mdc', '.ps1', '.py', '.cmd', '.bat', '.sh', '.json', '.txt', '.template', '.yml', '.yaml')
    $identityHits = @()
    # Where this checkout happens to live is machine state too, one level below a user name: it is
    # wrong on every other machine, it survives a clone and a download rather than only a folder copy,
    # and the pack's own standing rule is never to hard-code a drive letter in scripts or docs. Match
    # the three forms a path can take in a text file: native, JSON-escaped, and forward-slash.
    $rootForms = @($PackRoot, ($PackRoot -replace '\\', '\\'), ($PackRoot -replace '\\', '/')) |
        Select-Object -Unique
    $rootHits = @()
    # Excluded on the path *relative to the pack root*, not the absolute path: a probe pack root lives
    # under .tmp, so an absolute match excluded every file in it and the scan passed on a tree with a
    # planted user path. A check that cannot fail is worse than no check.
    foreach ($f in (Get-ChildItem -LiteralPath $PackRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -notlike '.audit_*' -and
                $textExts -contains $_.Extension -and
                -not (Test-PackPathHasSegment -Path (Get-PackRelPathKey -Path $_.FullName -Root $PackRoot) `
                        -Segment @('.git', '__pycache__', '.tmp', '.pytest_cache'))
            })) {
        $rel = Get-PackRelPathKey -Path $f.FullName -Root $PackRoot
        # A machine-local file is *supposed* to name this machine; that is why it never travels.
        if ($machineLocal -contains ($rel -replace '\\', '/')) { continue }
        $body = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $body) { continue }
        foreach ($m in [regex]::Matches($body, '(?i)(?:Users[\\/]|/home/)([A-Za-z0-9_.$%<{-]+)')) {
            $who = $m.Groups[1].Value
            # Anything holding a substitution marker is a placeholder, not a person.
            if ($who -match '[$%<{.]') { continue }
            if ($allowedUsers -contains $who.ToLower()) { continue }
            $identityHits += "$rel ($who)"
        }
        foreach ($form in $rootForms) {
            if ($body.Contains($form)) { $rootHits += $rel; break }
        }
    }
    $identityHits = @($identityHits | Select-Object -Unique)
    $rootHits = @($rootHits | Select-Object -Unique)
    if ($identityHits.Count -gt 0) {
        Fail ("a real user profile path is recorded in files that travel with the pack - " +
            "use an illustration name or a placeholder: $($identityHits -join ', ')")
    } elseif ($rootHits.Count -gt 0) {
        Fail ("this checkout's own absolute path is recorded in files that travel - use a " +
            "repo-relative path or a placeholder root: $($rootHits -join ', ')")
    } else {
        Ok "no machine identity or checkout path in any file that travels"
    }

    # The strongest form of the rule, and the one that makes the rest belt-and-braces: since 2.22.59
    # nothing writes these into a pack checkout, so any of them existing here means a writer regressed
    # or a copy was trusted without sanitizing. Policing content was always second best - a file that
    # is never created cannot leak.
    $present = @($machineLocal | Where-Object { Test-Path -LiteralPath (Join-Path $PackRoot ($_ -replace '/', '\')) })
    if ($present.Count -gt 0) {
        Fail ("machine-local files exist in the pack checkout - nothing should write them here; " +
            "run sanitize-machine-state.ps1 -Apply: $($present -join ', ')")
    } else {
        Ok 'no machine-local file exists in the checkout'
    }

    # The state directory has to be somewhere the pack folder does not travel to.
    $stateRoot = Get-AgentStateRoot -ProjectRoot $PackRoot
    if ($stateRoot.TrimEnd('\', '/').StartsWith($PackRoot.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
        Fail "agent state root is inside the pack checkout ($stateRoot) - it would travel with the folder"
    } else {
        Ok 'agent state root resolves outside the checkout'
    }

    # Every consumer reads the same list, or the list is decoration.
    $gitignoreText = Get-Content -LiteralPath (Join-Path $PackRoot '.gitignore') -Raw -Encoding UTF8
    $notIgnored = @($machineLocal | Where-Object { $gitignoreText -notmatch ('(?m)^\s*' + [regex]::Escape($_) + '\s*$') })
    $alsoMirrored = @($machineLocal | Where-Object { @($mlManifest.packMirror) -contains $_ })
    $exportText = Get-Content -LiteralPath (Join-Path $PackRoot 'export.ps1') -Raw -Encoding UTF8
    $sanitizePath = Join-Path $PackRoot 'pack/scripts/sanitize-machine-state.ps1'
    if ($notIgnored.Count -gt 0) {
        Fail "machineLocalPaths not covered by .gitignore (they would be committed): $($notIgnored -join ', ')"
    } elseif ($alsoMirrored.Count -gt 0) {
        # Mirroring a per-machine file pushes one machine's absolute paths into the install.
        Fail "machineLocalPaths also listed in packMirror: $($alsoMirrored -join ', ')"
    } elseif ($exportText -notmatch 'machineLocalPaths') {
        Fail 'export.ps1 does not read machineLocalPaths - its own copy of the list will drift again'
    } elseif (-not (Test-Path -LiteralPath $sanitizePath)) {
        Fail 'sanitize-machine-state.ps1 missing - a folder copy has no way to clean machine state'
    } elseif ((Get-Content -LiteralPath $sanitizePath -Raw -Encoding UTF8) -notmatch 'machineLocalPaths') {
        Fail 'sanitize-machine-state.ps1 does not read machineLocalPaths'
    } elseif ((Get-Content -LiteralPath (Join-Path $PackRoot 'pack/scripts/sync-audit-system.ps1') `
                -Raw -Encoding UTF8) -notmatch 'machineLocalPaths') {
        # Unmirrored means nothing refreshes them, so an install made before this classification keeps
        # whichever machine's paths it copied. Sync has to remove them, not ignore them.
        Fail 'sync-audit-system.ps1 does not clear machine-local files from an existing install'
    } else {
        Ok "all $($machineLocal.Count) machine-local paths are gitignored, unmirrored, and known to export + sanitize"
    }

    # Listing a file in .gitignore does nothing once git has it in the index - that is exactly how a
    # foreign install-manifest.json stayed tracked while being "ignored", and how the two generated docs
    # were committed. It also closes the round trip: a machine-local file is exempt from the identity
    # scan above (it is supposed to name this machine), so if a transfer brings the tracked copies back,
    # this is the only arm that notices. git is an optional requirement, so absence is not a failure.
    if ((Test-Path -LiteralPath (Join-Path $PackRoot '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $prevEapGit = $ErrorActionPreference
        try {
            # Same reason as the git probe further up: removable media records no ownership, so git
            # refuses the repo as dubious. Trust it through the environment, never the user's config.
            # Without this the check would report "not tracked" for every file on a USB checkout.
            $ErrorActionPreference = 'Continue'
            $gitOkProbe = (& git -c safe.directory=* -C $PackRoot rev-parse --is-inside-work-tree 2>&1 |
                Select-Object -First 1)
            if ("$gitOkProbe".Trim() -ne 'true') {
                Write-Host "[INFO] git cannot read this checkout ($gitOkProbe) - index check skipped"
            } else {
                $trackedLocal = @()
                foreach ($rel in $machineLocal) {
                    # Output, not exit code: ls-files exits 0 whether or not the path is tracked, so a
                    # git failure cannot be misread as "clean". Prints the path only when tracked.
                    $lsOut = (& git -c safe.directory=* -C $PackRoot ls-files -- $rel 2>$null |
                        Select-Object -First 1)
                    if ("$lsOut".Trim()) { $trackedLocal += $rel }
                }
                if ($trackedLocal.Count -gt 0) {
                    Fail ("machine-local files are tracked in git - .gitignore cannot undo that, " +
                        "run git rm --cached and stage the deletion: $($trackedLocal -join ', ')")
                } else {
                    Ok 'no machine-local file is tracked in git'
                }
            }
        } finally {
            $ErrorActionPreference = $prevEapGit
        }
    } else {
        Write-Host '[INFO] not a git checkout (or git absent) - index check skipped'
    }

    # Preview must not delete: the receiving machine runs this before it trusts the folder.
    $mlProbe = Join-Path $PackRoot ".tmp/machine-local-probe-$PID"
    try {
        New-Item -ItemType Directory -Path (Join-Path $mlProbe 'pack/audit') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $mlProbe 'docs') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PackRoot 'pack/audit/manifest.json') `
            -Destination (Join-Path $mlProbe 'pack/audit/manifest.json') -Force
        Write-Utf8NoBom (Join-Path $mlProbe 'docs/AGENT_CONTEXT.json') '{"projectRoot":"somewhere else"}'
        Invoke-PackScript -NoProfile -ScriptPath $sanitizePath -ProjectRoot $mlProbe 2>&1 | Out-Null
        $survived = Test-Path -LiteralPath (Join-Path $mlProbe 'docs/AGENT_CONTEXT.json')
        Invoke-PackScript -NoProfile -ScriptPath $sanitizePath -ProjectRoot $mlProbe -Apply 2>&1 | Out-Null
        $removed = -not (Test-Path -LiteralPath (Join-Path $mlProbe 'docs/AGENT_CONTEXT.json'))
        if (-not $survived) { Fail 'sanitize preview deleted a file without -Apply' }
        elseif (-not $removed) { Fail 'sanitize -Apply left a machine-local file in place' }
        else { Ok 'sanitize previews by default and removes only with -Apply' }
    } finally {
        Remove-Item -LiteralPath $mlProbe -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    Fail "machine identity check error: $_"
}

# 51. One state root, two implementations
# PowerShell writes the agent-context artifacts and Python reads them, so they have to agree on where
# those artifacts are. Two hand-written copies of a hash rule is exactly the shape that drifted four
# ways for machineLocalPaths, and a disagreement here is silent: the refresh reports success, the
# freshness check reports "missing AGENT_CONTEXT.json", and nothing points at the cause. The Python
# side is exposed as --print-state-root purely so this comparison can exist.
Write-Host "`n51. One state root, two implementations"
try {
    $srProbe = Join-Path $PackRoot ".tmp/state-root-probe-$PID"
    try {
        # A pack root (redirects outside the folder) and a plain project (keeps its own docs\), so
        # both branches of the rule are compared, not just the one this repo happens to be.
        New-Item -ItemType Directory -Path (Join-Path $srProbe 'packish/pack/audit') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PackRoot 'pack/audit/manifest.json') `
            -Destination (Join-Path $srProbe 'packish/pack/audit/manifest.json') -Force
        New-Item -ItemType Directory -Path (Join-Path $srProbe 'plainproj/docs') -Force | Out-Null

        $freshPy = Join-Path $PackRoot 'pack/scripts/agent_context_freshness.py'
        $mismatch = @()
        foreach ($case in @($PackRoot, (Join-Path $srProbe 'packish'), (Join-Path $srProbe 'plainproj'))) {
            $psSide = (Get-AgentStateRoot -ProjectRoot $case).TrimEnd('\', '/')
            $pySide = (Invoke-PackPython $freshPy --print-state-root --project-root $case 2>&1 |
                Select-Object -Last 1).ToString().Trim().TrimEnd('\', '/')
            if ($psSide -ne $pySide) { $mismatch += "$case -> ps '$psSide' vs py '$pySide'" }
        }
        # Two checkouts on one machine must not share a state directory, or refreshing one reports the
        # other's stamp as "changed" and each overwrites the other.
        $keyA = Get-AgentStateRoot -ProjectRoot $PackRoot
        $keyB = Get-AgentStateRoot -ProjectRoot (Join-Path $srProbe 'packish')
        if ($mismatch.Count -gt 0) {
            Fail "state root differs between PowerShell and Python: $($mismatch -join ' | ')"
        } elseif ($keyA -eq $keyB) {
            Fail 'two different pack checkouts resolve to the same state directory'
        } else {
            Ok 'PowerShell and Python agree on the state root; distinct checkouts stay distinct'
        }
    } finally {
        Remove-Item -LiteralPath $srProbe -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    Fail "state root parity error: $_"
}

# 52. An exported pack is a working pack
# The export copies a hand-written $items list, and that list drifted from packMirror: an archive
# shipped without Update-AgentStack.cmd, Bootstrap-Portable-Project.cmd, Register-Tool-Adapters.cmd and
# the four .sh launchers, so a downloaded pack failed its own suite with "missing at pack root". Nothing
# noticed for as long as it took someone to unzip one and run it - the export exits 0, and this checkout
# stays green because the files are right here. The export now unions packMirror into $items and
# verifies the result, and this step runs the real thing rather than trusting that it still does.
Write-Host "`n52. An exported pack is a working pack"
$expProbe = Join-Path $PackRoot ".tmp/export-probe-$PID"
try {
    New-Item -ItemType Directory -Path $expProbe -Force | Out-Null
    $exportPs1 = Join-Path $PackRoot 'export.ps1'
    if (-not (Test-Path -LiteralPath $exportPs1)) {
        Fail 'export.ps1 missing - the documented transfer path does not exist'
    } else {
        Invoke-PackScript -NoProfile -ScriptPath $exportPs1 -OutDir $expProbe 2>&1 | Out-Null
        $zip = Get-ChildItem -LiteralPath $expProbe -Filter '*.zip' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($LASTEXITCODE -ne 0 -or -not $zip) {
            Fail "export.ps1 produced no archive (exit $LASTEXITCODE)"
        } else {
            $unzip = Join-Path $expProbe 'unzipped'
            Expand-Archive -Path $zip.FullName -DestinationPath $unzip -Force
            $manifestExp = Get-Content -LiteralPath (Join-Path $PackRoot 'pack/audit/manifest.json') `
                -Raw -Encoding UTF8 | ConvertFrom-Json
            $mlExp = @($manifestExp.machineLocalPaths)
            $absent = @()
            foreach ($rel in @($manifestExp.packMirror | Where-Object { $_ })) {
                if ($mlExp -contains $rel) { continue }
                if (-not (Test-Path -LiteralPath (Join-Path $unzip ($rel -replace '/', '\')))) {
                    $absent += $rel
                }
            }
            # The other half: the archive is how the pack reaches a machine that never had it, so it
            # must not carry the sending machine's state either.
            $carried = @($mlExp | Where-Object {
                Test-Path -LiteralPath (Join-Path $unzip ($_ -replace '/', '\'))
            })
            # install.ps1 stripped maintainerOnlyPaths; export.ps1 did not, so the two channels for the
            # same manifest list disagreed and the zip carried this repo's session notes plus
            # no-publish-from-this-machine.mdc - a rule instructing the *recipient's* agent not to
            # commit or push. An entry may name a folder, so match it and anything beneath it.
            $maintainerCarried = @()
            foreach ($rel in @($manifestExp.maintainerOnlyPaths | Where-Object { $_ })) {
                $relWin = $rel -replace '/', '\'
                $full = Join-Path $unzip $relWin
                if (Test-Path -LiteralPath $full) {
                    # A folder that exists but is empty is still a leak of the layout, not of content;
                    # report either way so the fix is to exclude it, not to empty it.
                    $maintainerCarried += $rel
                }
            }
            $repoOnlyCarried = @()
            foreach ($rel in @($manifestExp.repoOnlyPaths | Where-Object { $_ })) {
                $relWin = $rel -replace '/', '\'
                $full = Join-Path $unzip $relWin
                if (Test-Path -LiteralPath $full) { $repoOnlyCarried += $rel }
            }
            if ($absent.Count -gt 0) {
                Fail ("exported archive is missing files the pack needs to work: " +
                    "$($absent -join ', ')")
            } elseif ($carried.Count -gt 0) {
                Fail "exported archive carries machine-local files: $($carried -join ', ')"
            } elseif ($maintainerCarried.Count -gt 0) {
                Fail ("exported archive carries maintainer-only paths that install.ps1 strips: " +
                    "$($maintainerCarried -join ', ')")
            } elseif ($repoOnlyCarried.Count -gt 0) {
                Fail ("exported archive carries repo-only paths (Airlock repo/ only): " +
                    "$($repoOnlyCarried -join ', ')")
            } else {
                Ok 'export ships every mirrored file, no machine-local state, no maintainer-only notes, no repo-only CI'
            }
        }
    }
} catch {
    Fail "export check error: $_"
} finally {
    Remove-Item -LiteralPath $expProbe -Recurse -Force -ErrorAction SilentlyContinue
}

# 53. Manifest-declared lists have no rival copies
# Three releases in a row were spent on one bug: a script keeping its own copy of a list the manifest
# already declares, then drifting from it. machineLocalPaths across four consumers (2.22.56), the
# export's $items (2.22.60), and the verifiers below - verify-agent-setup checked 5 of 12 profile rules
# and 10 of 174 pack files, verify-portable-bootstrap checked 5 of 9 required project files. None of
# them was *wrong*; each was narrower than the thing it guarded, which is the failure that reports
# success on a broken artifact. This asserts each consumer still reads its manifest key. It cannot
# prove the reading is correct - only that the coupling was not quietly removed.
Write-Host "`n53. Manifest-declared lists have no rival copies"
try {
    $consumers = @(
        @{ File = 'pack\scripts\verify-agent-setup.ps1'; Keys = @('packToUser', 'packMirror') },
        @{ File = 'pack\scripts\verify-portable-bootstrap.ps1'; Keys = @('projectRequired') },
        @{ File = 'pack\scripts\run_audit_core.ps1'; Keys = @('forbiddenArtifacts') },
        @{ File = 'export.ps1'; Keys = @('packMirror', 'machineLocalPaths', 'maintainerOnlyPaths', 'repoOnlyPaths') },
        @{ File = 'pack\scripts\sanitize-machine-state.ps1'; Keys = @('machineLocalPaths') }
    )
    $unlinked = @()
    foreach ($c in $consumers) {
        $path = Join-Path $PackRoot $c.File
        if (-not (Test-Path -LiteralPath $path)) { $unlinked += "$($c.File) (missing)"; continue }
        # Comment lines dropped, and the key matched as a whole token: WQ-462's mutation run proved
        # the old substring grep could not fail. Renaming the read to `projectRequiredPrivateCopy`
        # left the guard green twice over - the prefix still matched, and the comment above the read
        # would have satisfied it on its own. A consumer that only talks about the list in prose has
        # already grown the private copy this step exists to catch.
        $body = @(Get-Content -LiteralPath $path -Encoding UTF8 | Where-Object { $_.TrimStart() -notmatch '^#' }) -join "`n"
        foreach ($key in $c.Keys) {
            if ($body -notmatch ('(?<![A-Za-z0-9_])' + [regex]::Escape($key) + '(?![A-Za-z0-9_])')) {
                $unlinked += "$($c.File) -> $key"
            }
        }
    }
    if ($unlinked.Count -gt 0) {
        Fail ("consumer no longer reads the manifest list it depends on - a private copy will drift: " +
            "$($unlinked -join ', ')")
    } else {
        Ok "all $($consumers.Count) list consumers still read the manifest"
    }
} catch {
    Fail "manifest list consumer check error: $_"
}

# 54. The .sh wrappers are run, not read
# Steps 40-43 assert each wrapper's *text* delegates through pwsh-wrap.sh, and pack-os-smoke.yml
# triggers on changes to *.sh and then executes the .ps1 files directly - so for four releases nothing
# anywhere ran `bash ./install.sh`. The first real run found a defect no marker grep could see: the
# generated Cursor hook read stdin with an unbounded ReadToEnd, which returns instantly under Cursor
# (it closes the handle) and never returns under bash, hanging the audit with no output. Hence this
# step. install.sh and run_audit.sh are deliberately not run here - one writes the user profile, and
# the other would re-enter this suite (see the pitfall about product audits) - CI covers both.
Write-Host "`n54. The .sh wrappers are run, not read"
$shProbe = Join-Path $PackRoot ".tmp/sh-wrappers-$PID"
try {
    $bashExe = $null
    # Git bash first on Windows, because these wrappers are the Windows-side bash entry points and
    # Git bash shares this filesystem. Plain `bash` on PATH is System32\bash.exe once WSL exists,
    # which would run the wrappers inside the distro against /mnt/d - a different OS, a different
    # pwsh, and not what this step claims to cover. WSL bash still works if it is all there is;
    # Convert-PackPathToPosix asks whichever shell is chosen how it spells this path.
    $bashCandidates = @()
    if (Test-PackIsWindows) {
        # Guard the *inputs*, not the results. The `if (-not $cand) { continue }` below was written to
        # tolerate a missing candidate, but it never gets the chance: `Join-Path` throws on a null Path
        # first, and under $ErrorActionPreference = 'Stop' that aborts the whole step. Observed on a
        # shell where ${env:ProgramFiles(x86)} was empty - the step failed with "Cannot bind argument to
        # parameter 'Path' because it is null", which names neither the variable nor the step's subject.
        foreach ($candidate in @(
            @{ Base = $env:ProgramFiles;            Leaf = 'Git/bin/bash.exe' },
            @{ Base = ${env:ProgramFiles(x86)};     Leaf = 'Git/bin/bash.exe' },
            @{ Base = $env:LOCALAPPDATA;            Leaf = 'Programs/Git/bin/bash.exe' }
        )) {
            if ([string]::IsNullOrWhiteSpace($candidate.Base)) { continue }
            $bashCandidates += (Join-Path $candidate.Base $candidate.Leaf)
        }
    }
    $bashCandidates += @('bash')
    foreach ($cand in $bashCandidates) {
        if (-not $cand) { continue }
        if (Test-Path -LiteralPath $cand) { $bashExe = $cand; break }
        $resolved = Get-Command $cand -ErrorAction SilentlyContinue
        if ($resolved) { $bashExe = $resolved.Source; break }
    }

    if (-not $bashExe) {
        # A stated skip, not a silent pass: on a machine with no bash this proves nothing, and saying so
        # is the difference between "not covered here" and "covered".
        Write-Host '[SKIP] no bash on this machine - wrapper execution is covered by pack-os-smoke.yml'
    } elseif (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-Host '[SKIP] no pwsh - the wrappers require PowerShell 7 by design'
    } else {
        New-Item -ItemType Directory -Path $shProbe -Force | Out-Null
        # bash needs a POSIX form of the pack root, and the spelling depends on which bash this is.
        $packPosix = Convert-PackPathToPosix -Path $PackRoot -BashExe $bashExe
        $probePosix = "$packPosix/.tmp/sh-wrappers-$PID"

        function Invoke-ShWrapper([string]$Command) {
            # stderr is merged inside bash, not by PowerShell. This script runs with
            # ErrorActionPreference = 'Stop', which turns a native command's stderr into a terminating
            # error - so the usage-guard case, which is *supposed* to print usage to stderr and exit 1,
            # aborted the whole step instead of being asserted. Same trap as the py-launcher probe above.
            $output = & $bashExe -lc "cd '$packPosix' && { $Command ; } 2>&1"
            return [pscustomobject]@{ Code = $LASTEXITCODE; Text = (($output | Out-String).Trim()) }
        }

        $shFails = @()

        # Argument pass-through: -Json reaches check-requirements.ps1 and comes back parseable.
        $req = Invoke-ShWrapper './Check-Requirements.sh -Json'
        if ($req.Code -ne 0) { $shFails += "Check-Requirements.sh exit $($req.Code)" }
        else {
            try { $null = $req.Text | ConvertFrom-Json }
            catch { $shFails += 'Check-Requirements.sh -Json did not return JSON' }
        }

        # The usage guard must fail, or the wrapper would hand an empty project root to bootstrap.
        $usage = Invoke-ShWrapper './Bootstrap-Project.sh'
        if ($usage.Code -eq 0) { $shFails += 'Bootstrap-Project.sh with no args should exit non-zero' }
        elseif ($usage.Text -notmatch 'Usage:') { $shFails += 'Bootstrap-Project.sh gives no usage line' }

        $boot = Invoke-ShWrapper "./Bootstrap-Project.sh '$probePosix/ShApp' ShApp"
        if ($boot.Code -ne 0) { $shFails += "Bootstrap-Project.sh exit $($boot.Code)" }
        elseif (-not (Test-Path -LiteralPath (Join-Path $shProbe 'ShApp/AGENTS.md'))) {
            $shFails += 'Bootstrap-Project.sh produced no AGENTS.md'
        }

        # Both branches of the refresh wrapper's argument parsing: a project root, and a leading switch.
        # The second one targets the pack itself, so keep its state write inside the probe folder.
        $refresh = Invoke-ShWrapper "./Refresh-AgentContext.sh '$probePosix/ShApp' -NoClipboard"
        if ($refresh.Code -ne 0) { $shFails += "Refresh-AgentContext.sh exit $($refresh.Code)" }
        elseif (-not (Test-Path -LiteralPath (Join-Path $shProbe 'ShApp/docs/AGENT_CONTEXT.json'))) {
            $shFails += 'Refresh-AgentContext.sh wrote no AGENT_CONTEXT.json'
        }
        $switchFirst = Invoke-ShWrapper (
            "AGENT_STARTER_PACK_STATE_ROOT='$probePosix/state' ./Refresh-AgentContext.sh -NoClipboard")
        if ($switchFirst.Code -ne 0) {
            $shFails += "Refresh-AgentContext.sh with a leading switch exit $($switchFirst.Code)"
        }

        if ($shFails.Count -gt 0) {
            Fail "shell wrapper execution failed: $($shFails -join '; ')"
        } else {
            Ok "four .sh wrappers executed under $(Split-Path -Leaf $bashExe) (install.sh and run_audit.sh: CI)"
        }
    }
} catch {
    Fail "shell wrapper execution error: $_"
} finally {
    Remove-Item -LiteralPath $shProbe -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n55. Product-truth paths and prose vs code (WQ-415)"
try {
    $ptScript = Join-Path $PSScriptRoot 'verify-product-truth-paths.ps1'
    if (-not (Test-Path -LiteralPath $ptScript)) { Fail 'verify-product-truth-paths.ps1 missing' }
    else {
        # WQ-471: a skip and a full pass both exit 0, so the exit code cannot tell them apart - and
        # this arm's claim is specifically that the checks were *skipped* on a repo with no overlay.
        $ptSkipOut = (Invoke-PackScript -PassOutput -NoProfile -ScriptPath $ptScript -ProjectRoot $PackRoot 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { Fail "pack repo should skip product-truth checks (exit 0): $($ptSkipOut.Trim())" }
        elseif ($ptSkipOut -notmatch 'skipping path/claim checks') {
            Fail "the pack repo exited 0 without saying it skipped the overlay checks, so this arm cannot tell a skip from a pass: $($ptSkipOut.Trim())"
        } else { Ok 'pack repo skips product-truth overlay checks, and says so' }

        $probeRoot = Join-Path $PackRoot ".tmp/product-truth-probe-$PID"
        if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path (Join-Path $probeRoot 'docs') -Force | Out-Null
        Write-Utf8NoBom (Join-Path $probeRoot 'docs/WORK_COMPLETION.md') @"
# Work completion probe

### Product-truth docs

| Role | Path |
|------|------|
| Capabilities | ``docs\PRODUCT_REFERENCE.md`` |
| Limitations | ``docs\KNOWN_LIMITATIONS.md`` |
"@
        # Name the rejection, do not settle for a non-zero exit: this probe is a two-file project and
        # has other ways to be unhappy (WQ-462 batches five and six, three fixtures).
        $ovOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $ptScript -ProjectRoot $probeRoot 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Fail 'missing overlay paths should FAIL' }
        elseif ($ovOut -notmatch 'PRODUCT_REFERENCE|KNOWN_LIMITATIONS') {
            Fail "the overlay probe failed without naming a missing product-truth path: $($ovOut.Trim())"
        } else { Ok 'missing product-truth paths FAIL, and the missing path is named' }

        Write-Utf8NoBom (Join-Path $probeRoot 'docs/PRODUCT_REFERENCE.md') "# Cap`r`n"
        Write-Utf8NoBom (Join-Path $probeRoot 'docs/KNOWN_LIMITATIONS.md') "# Lim`r`n"
        Write-Utf8NoBom (Join-Path $probeRoot 'docs/WORK_QUEUE.md') @"
# Work queue probe

## Done log

| ID | Task | Completed | Evidence |
|----|------|-----------|----------|
| WQ-042 | shipped | 2026-01-01 | done |
"@
        Write-Utf8NoBom (Join-Path $probeRoot 'docs/PRODUCT_REFERENCE.md') @"
# Cap

WQ-042 is not built yet.
"@
        $contraOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $ptScript -ProjectRoot $probeRoot 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Fail 'Done WQ with not-built prose should FAIL' }
        elseif ($contraOut -notmatch 'WQ-042') {
            Fail "the contradiction probe failed without naming the Done id it contradicts: $($contraOut.Trim())"
        } else { Ok 'Done WQ prose contradiction FAILs, naming WQ-042' }

        Write-Utf8NoBom (Join-Path $probeRoot 'docs/PRODUCT_REFERENCE.md') @"
# Cap

WQ-042 shipped in 6.5.0.
"@
        New-Item -ItemType Directory -Path (Join-Path $probeRoot 'src') -Force | Out-Null
        Write-Utf8NoBom (Join-Path $probeRoot 'src/app.py') "install_mode = 'portable'`r`n"
        Write-Utf8NoBom (Join-Path $probeRoot 'docs/.product_truth_verify.json') @'
{
  "schemaVersion": 1,
  "claims": [
    {
      "id": "portable-code",
      "doc": "docs/PRODUCT_REFERENCE.md",
      "docPattern": "(?i)shipped",
      "codeGlob": "*.py",
      "codePattern": "install_mode",
      "minCodeMatches": 1
    }
  ]
}
'@
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $ptScript -ProjectRoot $probeRoot 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'valid product_truth_verify.json claim should pass' }
        else { Ok 'product_truth_verify.json doc/code claim passes' }
    }
} catch {
    Fail "product-truth verify error: $_"
} finally {
    Remove-Item (Join-Path $PackRoot ".tmp/product-truth-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n56. Update-AgentStack -VerifyOnly (WQ-417)"
try {
    $uasScript = Join-Path $PSScriptRoot 'update-agent-stack.ps1'
    if (-not (Test-Path -LiteralPath $uasScript)) { Fail 'update-agent-stack.ps1 missing' }
    else {
        # WQ-471: the Ok line claimed Step 5b had run while the arm only read an exit code, so a
        # -VerifyOnly that stopped delegating entirely would have kept this green - and the step's own
        # mutation is a misspelled script name, which is exactly that failure. Asserting the child's
        # output does not work here and the reason is worth writing down: this script delegates
        # without -PassOutput, so verify-complete-picture prints to the host and never reaches a
        # captured stream. What discriminates is the *verdict*, so a project that must fail Step 5b
        # is the control - a delegation that has stopped happening cannot report a failure.
        if (Test-PackPublishZoneBTree $PackRoot) {
            Ok 'Zone B publish tree - Update-AgentStack -VerifyOnly skipped (maintainer handoffs stripped by B09)'
        } else {
            $uasOut = (Invoke-PackScript -PassOutput -NoProfile -ScriptPath $uasScript -PackRoot $PackRoot -VerifyOnly 2>&1 | Out-String)
            if ($LASTEXITCODE -ne 0) { Fail "Update-AgentStack -VerifyOnly should pass on aligned pack repo: $($uasOut.Trim())" }
            elseif ($uasOut -notmatch 'WORK_COMPLETION Step 5b') {
                Fail "-VerifyOnly exited 0 without announcing Step 5b at all: $($uasOut.Trim())"
            } else { Ok 'Update-AgentStack -VerifyOnly runs Step 5b on pack repo' }
        }

        $uasProbe = Join-Path $PackRoot ".tmp/update-stack-probe-$PID"
        if (Test-Path -LiteralPath $uasProbe) { Remove-Item -LiteralPath $uasProbe -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path (Join-Path $uasProbe 'docs') -Force | Out-Null
        Write-Utf8NoBom (Join-Path $uasProbe 'docs/WORK_QUEUE.md') @"
# Work queue probe

## Done log

| ID | Task | Completed | Evidence |
|----|------|-----------|----------|
| WQ-042 | shipped slice | 2026-01-01 | done |
"@
        Write-Utf8NoBom (Join-Path $uasProbe 'docs/ROADMAP.md') @"
# Roadmap probe

## Work queue (current)

| Name | PLAN | Phase | Status |
|------|------|-------|--------|
| Old slice | plan.md | 1 | **Next** - WQ-042 handoff [handoffs/active/HANDOFF_WQ042_feature.md](handoffs/active/HANDOFF_WQ042_feature.md) |
"@
        $uasBadOut = (Invoke-PackScript -PassOutput -NoProfile -ScriptPath $uasScript -PackRoot $PackRoot -VerifyOnly -ProjectRoot $uasProbe 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0) {
            Fail 'Update-AgentStack -VerifyOnly passed a project whose ROADMAP still marks a shipped WQ as Next - Step 5b is announced but not reaching a verdict'
        } elseif ($uasBadOut -notmatch 'verify-complete-picture\.ps1 failed') {
            Fail "-VerifyOnly rejected the probe without naming the delegated verify: $($uasBadOut.Trim())"
        } else { Ok 'Step 5b reaches a verdict: a project with stale ROADMAP status is rejected, naming the delegate' }
        Remove-Item -LiteralPath $uasProbe -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath (Join-Path $PackRoot 'pack/templates/docs/DOC_MAP.md.template'))) {
            Fail 'DOC_MAP.md.template missing (WQ-420)'
        } else { Ok 'DOC_MAP.md.template ships product-truth owners section' }
    }
} catch {
    Fail "Update-AgentStack -VerifyOnly error: $_"
}

Write-Host "`n57. Session handoff verify (WQ-438)"
try {
    $shScript = Join-Path $PSScriptRoot 'verify-session-handoff.ps1'
    if (-not (Test-Path -LiteralPath $shScript)) { Fail 'verify-session-handoff.ps1 missing' }
    else {
        if (Test-PackPublishZoneBTree $PackRoot) {
            Ok 'Zone B publish tree - SESSION verify skipped (maintainer handoffs stripped by B09)'
        } else {
            $packSession = Join-Path $PackRoot 'docs/handoffs/SESSION.md'
            if (-not (Test-Path -LiteralPath $packSession)) { Fail 'pack repo missing docs/handoffs/SESSION.md' }
            else {
                & $shScript -ProjectRoot $PackRoot
                if ($LASTEXITCODE -ne 0) { Fail 'verify-session-handoff should pass on pack SESSION.md' }
                else { Ok 'verify-session-handoff passes on pack repo' }
            }
        }
        $badRoot = Join-Path $PackRoot ".tmp/session-bad-probe-$PID"
        New-Item -ItemType Directory -Path (Join-Path $badRoot 'docs/handoffs') -Force | Out-Null
        $badSession = Join-Path $badRoot 'docs/handoffs/SESSION.md'
        Write-Utf8NoBom $badSession (@'
# Bad SESSION

**Session status:** clear

## Open items

- [ ] still open

| **Next active ID** | **WQ-999** |
'@)
        $badWq = Join-Path $badRoot 'docs/WORK_QUEUE.md'
        Write-Utf8NoBom $badWq (@'
| **Next active ID** | **WQ-001** |
'@)
        # This fixture breaks two rules at once, which is exactly the shape that hides a disabled check:
        # either finding alone makes the exit code non-zero, so the arm has to see both named. Step 57
        # already learned the multi-check lesson once (its mutation had to break the exit threshold);
        # this is the reporting half of it.
        # `*>&1`, not `2>&1`: this script reports findings with Write-Host, which is the information
        # stream, so an error-only redirect captured an empty string and the assertion below read it
        # as "the finding is missing". A capture that cannot see the output is not a check.
        $shOut = & $shScript -ProjectRoot $badRoot *>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Fail 'verify-session-handoff should FAIL on forbidden Next table + clear/open mismatch' }
            # Each pattern is the producer's own sentence. 'Next' and 'open' both occur in ordinary
            # guidance text this script prints, so the short forms passed whatever the run said.
            elseif ($shOut -notmatch 'must not contain Next active ID table') { Fail "no forbidden-Next-table finding in the output: $($shOut.Trim())" }
            elseif ($shOut -notmatch 'status is clear but Open items still has unchecked') { Fail "no clear/open contradiction finding in the output: $($shOut.Trim())" }
        else { Ok 'verify-session-handoff FAILs on duplicate Next and clear/open contradiction, reporting both' }

        # The session file's whole purpose is to travel, so an absolute root in it is wrong everywhere
        # but where it was typed. The first SESSION.md written named a portable media path; step 50 caught it
        # only on the machine that owned that path, because a guard comparing against the running
        # checkout cannot see a document naming a different one. Placeholder and env-var roots stay
        # legal, which is the half worth testing - a rule this blunt would otherwise ban the syntax the
        # pack tells people to use.
        $pathRoot = Join-Path $PackRoot ".tmp/session-path-probe-$PID"
        New-Item -ItemType Directory -Path (Join-Path $pathRoot 'docs/handoffs') -Force | Out-Null
        $pathSession = Join-Path $pathRoot 'docs/handoffs/SESSION.md'
        $pathWq = Join-Path $pathRoot 'docs/WORK_QUEUE.md'
        Write-Utf8NoBom $pathWq ('| **Next active ID** | **WQ-001** |')
        Write-Utf8NoBom $pathSession (@'
# SESSION

**Session status:** active

## Pointers

| Kind | Location |
|------|----------|
| Work queue | `E:\SomeCheckout\docs\WORK_QUEUE.md` |
'@)
        # `*>&1 | Out-String`, not `2>&1 | Out-Null`: this script reports with Write-Host, so an
        # error-only redirect captures nothing and discards nothing - the finding printed straight to
        # the host, where the parent audit picked it up and quoted a *planted fixture's* [FAIL] line
        # into its Fix line as though the pack itself had failed. That cost a full diagnosis pass on
        # the 2.22.109 certification (WQ-472). Capturing serves both halves: the host stays quiet on a
        # green run, and the text is here to assert on instead of an exit code.
        $absOut = & $shScript -ProjectRoot $pathRoot *>&1 | Out-String
        $absoluteRejected = $LASTEXITCODE -ne 0
        $absNamed = $absOut -match 'names an absolute path' -and $absOut -match 'SomeCheckout'
        Write-Utf8NoBom $pathSession (@'
# SESSION

**Session status:** active

## Pointers

| Kind | Location |
|------|----------|
| Work queue | `<pack checkout>\docs\WORK_QUEUE.md` |
| State | `%LOCALAPPDATA%\AgentStarterPack\state` |
| Example | `C:\Users\<you>\AgentStarterPack\docs\handoffs\SESSION.md` |
'@)
        $phOut = & $shScript -ProjectRoot $pathRoot *>&1 | Out-String
        $placeholderAccepted = $LASTEXITCODE -eq 0
        Remove-Item -LiteralPath $pathRoot -Recurse -Force -ErrorAction SilentlyContinue
        if (-not $absoluteRejected) { Fail "verify-session-handoff accepted an absolute checkout path in SESSION.md: $($absOut.Trim())" }
        elseif (-not $absNamed) { Fail "the rejection never named the absolute path it found: $($absOut.Trim())" }
        elseif (-not $placeholderAccepted) { Fail "verify-session-handoff rejected placeholder and env-var roots: $($phOut.Trim())" }
        elseif ($phOut -notmatch 'placeholder roots') { Fail "the accepting run never said it judged the roots: $($phOut.Trim())" }
        else { Ok 'SESSION must use placeholder roots; env vars and <you> markers stay legal' }
    }
} catch {
    Fail "session handoff verify error: $_"
} finally {
    Remove-Item (Join-Path $PackRoot ".tmp/session-bad-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n58. Cursor hook repair for pre-2.22.63 projects (WQ-435)"
try {
    $repairScript = Join-Path $PSScriptRoot 'repair-project-hooks.ps1'
    $hookTemplate = Join-Path $PackRoot 'pack/templates/cursor/hooks/session-freshness.ps1'
    if (-not (Test-Path -LiteralPath $repairScript)) { Fail 'repair-project-hooks.ps1 missing' }
    elseif (-not (Test-Path -LiteralPath $hookTemplate)) { Fail 'hook template missing - cannot test repair' }
    else {
        $hookProbe = Join-Path $PackRoot ".tmp/hook-repair-probe-$PID"
        $probeHooks = Join-Path $hookProbe '.cursor/hooks'
        New-Item -ItemType Directory -Path $probeHooks -Force | Out-Null
        $probeHook = Join-Path $probeHooks 'session-freshness.ps1'
        $probeBak = "$probeHook.bak"
        Write-Utf8NoBom (Join-Path $hookProbe '.cursor/hooks.json') `
            '{ "version": 1, "hooks": { "sessionStart": [ { "command": "powershell -File hooks/session-freshness.ps1" } ] } }'

        # The project is assembled by hand rather than bootstrapped: this step is about the repair, the
        # existing hook step already covers what bootstrap writes, and a bootstrap here would add seconds
        # to every suite run for no extra coverage.
        Copy-Item -LiteralPath $hookTemplate -Destination $probeHook -Force
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairScript -ProjectRoot $hookProbe 2>&1 | Out-Null
        $currentOk = ($LASTEXITCODE -eq 0) -and -not (Test-Path -LiteralPath $probeBak)

        # The planted defect is the pre-fix shape: an unbounded drain with neither the redirect guard nor
        # a bounded wait. It is parse-checked below because a planted *syntax* error would make the guard
        # look proven while testing nothing - the mistake made on this same hook in 2.22.63.
        Write-Utf8NoBom $probeHook @'
#Requires -Version 5.1
try {
    $payload = [Console]::In.ReadToEnd()
    if ($payload) { $null = $payload.Length }
} catch { }
exit 0
'@
        $probeParseErr = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($probeHook, [ref]$null, [ref]$probeParseErr)
        $plantedParses = @($probeParseErr).Count -eq 0
        $staleHash = (Get-FileHash -LiteralPath $probeHook).Hash

        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairScript -ProjectRoot $hookProbe -VerifyOnly 2>&1 | Out-Null
        $verifyRejects = $LASTEXITCODE -ne 0
        $verifyWroteNothing = (Get-FileHash -LiteralPath $probeHook).Hash -eq $staleHash

        # Write-Host does not reach the success stream, so a same-process call captures nothing and the
        # assertion below would pass on an empty string. Invoke-PackScript runs a child, which is why
        # every other step in this suite reads output that way.
        $auditOut = (Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairScript -ProjectRoot $hookProbe -AuditMode 2>&1 | Out-String)
        $auditReports = $auditOut -match '\[FIX\]'
        $auditWroteNothing = (Get-FileHash -LiteralPath $probeHook).Hash -eq $staleHash

        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairScript -ProjectRoot $hookProbe 2>&1 | Out-Null
        $repaired = Get-Content -LiteralPath $probeHook -Raw -Encoding UTF8
        # What repair owes the project is the shipped template, byte for byte. Whether that template
        # is itself sound is the current-hook arm's job above - it asks the repair script, which
        # judges code rather than prose - and the hang itself belongs to step 38. Pattern-matching
        # the repaired file here would duplicate that judgement in a weaker form, which is how the
        # template's own comment about the stdin read it does not perform once reddened this step.
        $isFixed = (Get-FileHash -LiteralPath $probeHook).Hash -eq (Get-FileHash -LiteralPath $hookTemplate).Hash
        $backupHasOriginal = (Test-Path -LiteralPath $probeBak) -and
            ((Get-FileHash -LiteralPath $probeBak).Hash -eq $staleHash)

        # Second run: a repair that re-copies on every invocation would bury the original backup under a
        # copy of the repaired file, destroying the only record of what the project used to have.
        $repairedHash = (Get-FileHash -LiteralPath $probeHook).Hash
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairScript -ProjectRoot $hookProbe 2>&1 | Out-Null
        $idempotent = ((Get-FileHash -LiteralPath $probeHook).Hash -eq $repairedHash) -and
            ((Get-FileHash -LiteralPath $probeBak).Hash -eq $staleHash)

        # A project that never took the Cursor target is not broken, and reporting it would train people
        # to ignore this check everywhere else.
        $bareProbe = Join-Path $PackRoot ".tmp/hook-bare-probe-$PID"
        New-Item -ItemType Directory -Path $bareProbe -Force | Out-Null
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairScript -ProjectRoot $bareProbe 2>&1 | Out-Null
        $bareIsOk = $LASTEXITCODE -eq 0

        # The second defect shape, and the first arm is blind to it by construction: the 2.22.63 hook
        # is guarded and bounded and still never drains, because a scriptblock handed to Task::Run has
        # no runspace on a threadpool thread and faults instead of reading (WQ-473). Anything testing
        # for the hang accepts it. Projects bootstrapped in that window carry it today.
        $inertProbe = Join-Path $PackRoot ".tmp/hook-inert-probe-$PID"
        New-Item -ItemType Directory -Path (Join-Path $inertProbe '.cursor/hooks') -Force | Out-Null
        $inertHook = Join-Path $inertProbe '.cursor/hooks/session-freshness.ps1'
        Write-Utf8NoBom (Join-Path $inertProbe '.cursor/hooks.json') `
            '{ "version": 1, "hooks": { "sessionStart": [ { "command": "powershell -File hooks/session-freshness.ps1" } ] } }'
        Write-Utf8NoBom $inertHook @'
#Requires -Version 5.1
try {
    if ([Console]::IsInputRedirected) {
        $drain = [System.Threading.Tasks.Task]::Run([Func[string]] { [Console]::In.ReadToEnd() })
        [void]$drain.Wait(250)
    }
} catch { }
exit 0
'@
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairScript -ProjectRoot $inertProbe -VerifyOnly 2>&1 | Out-Null
        $inertRejected = $LASTEXITCODE -ne 0
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $repairScript -ProjectRoot $inertProbe 2>&1 | Out-Null
        $inertRepaired = (Get-FileHash -LiteralPath $inertHook).Hash -eq (Get-FileHash -LiteralPath $hookTemplate).Hash

        Remove-Item -LiteralPath $hookProbe -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $bareProbe -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $inertProbe -Recurse -Force -ErrorAction SilentlyContinue

        if (-not $plantedParses) { Fail 'planted stale hook did not parse - the negative test proves nothing' }
        elseif (-not $currentOk) { Fail 'repair reported or altered a current hook' }
        elseif (-not $verifyRejects) { Fail '-VerifyOnly accepted a stale hook' }
        elseif (-not $verifyWroteNothing) { Fail '-VerifyOnly modified the hook' }
        elseif (-not $auditReports) { Fail '-AuditMode did not report a stale hook as FIX' }
        elseif (-not $auditWroteNothing) { Fail '-AuditMode modified the hook - an audit must not mutate' }
        elseif (-not $isFixed) { Fail 'repair did not install the shipped template byte for byte' }
        elseif (-not $backupHasOriginal) { Fail 'repair did not back up the previous hook' }
        elseif (-not $idempotent) { Fail 'second repair run was not idempotent (hook or backup changed)' }
        elseif (-not $bareIsOk) { Fail 'a project with no Cursor hooks was reported as needing repair' }
        elseif (-not $inertRejected) { Fail 'repair accepted the 2.22.63 hook whose drain faults instead of reading (WQ-473)' }
        elseif (-not $inertRepaired) { Fail 'repair left the inert Task::Run drain in place' }
        else { Ok 'both stale hook shapes repair, idempotently, and a current or absent hook is left alone' }
    }
} catch {
    Fail "hook repair check error: $_"
} finally {
    Remove-Item (Join-Path $PackRoot ".tmp/hook-repair-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $PackRoot ".tmp/hook-bare-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $PackRoot ".tmp/hook-inert-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n59. One home for the path vocabulary (WQ-441)"
try {
    $libPath = Join-Path $PackRoot 'pack/scripts/verify-lib.ps1'
    if (-not (Test-Path -LiteralPath $libPath)) { Fail 'verify-lib.ps1 missing - the shared path rules have no home' }
    else {
        $libManifest = Get-Content -LiteralPath (Join-Path $PackRoot 'pack/audit/manifest.json') -Raw -Encoding UTF8 |
            ConvertFrom-Json
        $allowed = @($libManifest.pathRulePrimitiveAllowlist | Where-Object { $_ })
        if ($allowed.Count -eq 0) { Fail 'manifest has no pathRulePrimitiveAllowlist - nothing declares where the rule lives' }

        # A fourth private copy is how this class recurs: verify-session-handoff.ps1 shipped in 2.22.68
        # with no path rule because there was nothing to inherit, and the lesson sat in a different
        # script's differently-shaped rule. Anything not declared must use the library.
        $rivals = @()
        foreach ($f in (Get-ChildItem (Join-Path $PackRoot 'pack/scripts') -Filter '*.ps1' -File)) {
            $rel = 'pack/scripts/' + $f.Name
            if ($allowed -contains $rel) { continue }
            $body = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
            if ($body -match '\[A-Za-z\]:' -or $body -match '<\[\^>\]\+>' -or $body -match 'alice') {
                $rivals += $rel
            }
        }

        # The rules composed from the vocabulary must actually behave. These are the two that disagreed:
        # one requires a root, the other forbids a machine path, and both must read placeholders alike.
        $midLine = @(Get-PackMachinePathHit -Text 'the queue at C:\Work\pack\docs sits here' -Policy Strict)
        $placeholderClean = @(Get-PackMachinePathHit -Text 'Read <pack checkout>\docs\WORK_QUEUE.md' -Policy Strict)
        $illustrationOk = @(Get-PackMachinePathHit -Text 'e.g. C:\Users\alice\Projects\MyApp' -Policy Illustrative)
        # Built at runtime, not written as a literal: step 50 scans this very file for recorded profile
        # paths and would flag a hard-coded name here - correctly, since a test fixture that names a
        # person travels just as far as prose does. The runtime value is deliberately absent from the
        # illustration list, so the assertion still proves the policy catches a non-example user.
        $probeUser = 'someoneelse'
        $realUserHit = @(Get-PackMachinePathHit -Text "C:\Users\$probeUser\Desktop\pack" -Policy Illustrative)
        $anchoredAbs = Test-PackRootAnchoredPath 'D:\pack\docs\x.md'
        $anchoredPlaceholder = Test-PackRootAnchoredPath '<pack checkout>\docs\x.md'
        $relativeRejected = -not (Test-PackRootAnchoredPath 'docs\x.md')

        if ($rivals.Count -gt 0) {
            Fail ("scripts carry their own path pattern instead of verify-lib.ps1: $($rivals -join ', ') " +
                '- use the shared predicates or declare the file in pathRulePrimitiveAllowlist')
        }
        elseif ($midLine.Count -ne 1) { Fail 'shared rule missed an absolute path that was not at line start' }
        elseif ($placeholderClean.Count -ne 0) { Fail 'shared rule flagged a placeholder root' }
        elseif ($illustrationOk.Count -ne 0) { Fail 'Illustrative policy flagged a documented example path' }
        elseif ($realUserHit.Count -ne 1) { Fail 'Illustrative policy let a real user path through' }
        elseif (-not $anchoredAbs) { Fail 'root-anchored predicate rejected an absolute path' }
        elseif (-not $anchoredPlaceholder) { Fail 'root-anchored predicate rejected a placeholder root' }
        elseif (-not $relativeRejected) { Fail 'root-anchored predicate accepted a bare relative path' }
        else { Ok 'path vocabulary has one home; both rules composed from it behave' }
    }
} catch {
    Fail "path vocabulary check error: $_"
}

Write-Host "`n60. Every manifest list has declared readers (WQ-442)"
try {
    $regManifestPath = Join-Path $PackRoot 'pack/audit/manifest.json'
    $regManifest = Get-Content -LiteralPath $regManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $consumers = $regManifest.listConsumers
    $channels = @($regManifest.distributionChannels | Where-Object { $_ })
    $criticalKeys = @($regManifest.distributionCriticalKeys | Where-Object { $_ })

    if (-not $consumers) { Fail 'manifest has no listConsumers - nothing declares who must read each list' }
    elseif ($channels.Count -eq 0) { Fail 'manifest declares no distributionChannels' }
    elseif ($criticalKeys.Count -eq 0) { Fail 'manifest declares no distributionCriticalKeys' }
    else {
        # Cache every candidate reader once: the checkout's own scripts, wherever they live.
        # Filter by extension explicitly: -Include against -LiteralPath silently matches everything, which
        # first swept .gitignore and the semantic report in here and reported them as undeclared readers.
        $regFiles = @{}
        foreach ($sf in (Get-ChildItem -LiteralPath $PackRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.ps1', '.py') } |
                Where-Object { -not (Test-PackPathHasSegment -Path $_.FullName -Segment @('.git', '.tmp', '__pycache__', 'audit_archive')) })) {
            $relKey = Get-PackRelPathKey -Path $sf.FullName -Root $PackRoot
            $regFiles[$relKey] = (Get-Content -LiteralPath $sf.FullName -Raw -Encoding UTF8)
        }

        # 1. A declared reader that stopped reading. This is the failure a registry exists to catch: a
        #    refactor drops the lookup, the list stays authoritative on paper, and the consumer quietly
        #    ships everything.
        $silentReaders = @()
        foreach ($prop in $consumers.PSObject.Properties) {
            foreach ($reader in @($prop.Value | Where-Object { $_ })) {
                if (-not $regFiles.ContainsKey($reader)) { $silentReaders += "$reader (missing file, declared for $($prop.Name))"; continue }
                if ($regFiles[$reader] -notmatch [regex]::Escape($prop.Name)) { $silentReaders += "$reader (declared for $($prop.Name), does not read it)" }
            }
        }

        # 2. A distribution channel that honours one critical list but not the others. Both halves of this
        #    have shipped: export carried maintainer-only notes it should have stripped, and install kept
        #    machine-local state that export already dropped.
        $partialChannels = @()
        foreach ($channel in $channels) {
            foreach ($key in $criticalKeys) {
                $declared = @($consumers.$key) -contains $channel
                $reads = $regFiles.ContainsKey($channel) -and ($regFiles[$channel] -match [regex]::Escape($key))
                if (-not ($declared -and $reads)) { $partialChannels += "$channel does not honour $key" }
            }
        }

        # 3. An undeclared reader of a critical list. A new channel is caught here before it can disagree
        #    with the others, because the registry is required to be complete rather than merely correct.
        $undeclared = @()
        foreach ($key in $criticalKeys) {
            $declaredFor = @($consumers.$key)
            foreach ($relKey in $regFiles.Keys) {
                if ($declaredFor -contains $relKey) { continue }
                if ($regFiles[$relKey] -match [regex]::Escape($key)) { $undeclared += "$relKey reads $key" }
            }
        }

        # 4. The behaviour the registry exists to protect. A declaration that install reads the list is
        #    not proof that a transferred folder's state stops at the door, and the checkout itself holds
        #    none of these files - so an install from *here* would pass while proving nothing. Build a
        #    scratch source, plant another machine's state in it, and install from that.
        $plantedLeaks = @()
        $regSrc = Join-Path $PackRoot ".tmp/consumer-src-$PID"
        $regDst = Join-Path $PackRoot ".tmp/consumer-dst-$PID"
        $prevRegRoot = $env:AGENT_STARTER_PACK_INSTALL_ROOT
        try {
            New-Item -ItemType Directory -Path $regSrc -Force | Out-Null
            foreach ($sf in (Get-ChildItem -LiteralPath $PackRoot -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { -not (Test-PackPathHasSegment -Path $_.FullName -Segment @('.git', '.tmp', '__pycache__', '.pytest_cache')) })) {
                $relPath = Get-PackRelPathKey -Path $sf.FullName -Root $PackRoot
                $target = Join-Path $regSrc $relPath
                $targetDir = Split-Path $target -Parent
                if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
                Copy-Item -LiteralPath $sf.FullName -Destination $target -Force
            }
            # A foreign root, spelled the way a real transferred checkout would spell it.
            $foreignRoot = 'E:\SomeOtherCheckout'
            Write-Utf8NoBom (Join-Path $regSrc 'install-manifest.json') "{ ""canonical"": ""$($foreignRoot -replace '\\', '\\')"" }"
            Write-Utf8NoBom (Join-Path $regSrc 'docs/AGENT_CONTEXT.json') "{ ""projectRoot"": ""$($foreignRoot -replace '\\', '\\')"" }"
            Write-Utf8NoBom (Join-Path $regSrc 'docs/AGENT_PASTE.txt') 'paste text belonging to another machine'

            # install runs sync-audit-system.ps1 from the installed tree afterwards, and sync deletes
            # machine-local files. That masked the copy filter completely: with the filter removed the
            # planted state still vanished, so this arm could not fail. Disable sync in the probe source
            # and the arm tests what it claims - install's own filter, which is what WQ-425 changed.
            # Before that fix, the profile did hold another machine's context stamp until a later step
            # happened to clean it up.
            $probeSync = Join-Path $regSrc 'pack/scripts/sync-audit-system.ps1'
            if (Test-Path -LiteralPath $probeSync) { Rename-Item -LiteralPath $probeSync -NewName 'sync-audit-system.probe-disabled.ps1' }

            $env:AGENT_STARTER_PACK_INSTALL_ROOT = $regDst
            Invoke-PackScript -PassOutput -NoProfile -ScriptPath (Join-Path $regSrc 'install.ps1') `
                -Scope User -NoPause -SkipPreflight *> $null
            $env:AGENT_STARTER_PACK_INSTALL_ROOT = $prevRegRoot

            foreach ($rel in @('docs\AGENT_CONTEXT.json', 'docs\AGENT_PASTE.txt')) {
                if (Test-Path -LiteralPath (Join-Path $regDst $rel)) { $plantedLeaks += $rel }
            }
            # install writes its own record at the destination, so the file is expected to exist. What
            # must not survive is the sending machine's root inside it.
            $dstRecord = Join-Path $regDst 'install-manifest.json'
            if ((Test-Path -LiteralPath $dstRecord) -and
                ((Get-Content -LiteralPath $dstRecord -Raw -Encoding UTF8) -match 'SomeOtherCheckout')) {
                $plantedLeaks += 'install-manifest.json (carries the source machine''s canonical root)'
            }
            if (-not (Test-Path -LiteralPath (Join-Path $regDst 'pack/audit/manifest.json'))) {
                $plantedLeaks += '(install produced no tree - the probe proved nothing)'
            }
        } finally {
            $env:AGENT_STARTER_PACK_INSTALL_ROOT = $prevRegRoot
            Remove-Item -LiteralPath $regSrc -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $regDst -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $PackRoot ".tmp/consumer-dst-$PID/../rules") -Recurse -Force -ErrorAction SilentlyContinue
        }

        if ($silentReaders.Count -gt 0) {
            Fail ("declared readers that no longer read their list: $($silentReaders -join '; ')")
        } elseif ($plantedLeaks.Count -gt 0) {
            Fail ("installing from a folder carrying another machine's state planted it here: " +
                "$($plantedLeaks -join ', ')")
        } elseif ($partialChannels.Count -gt 0) {
            Fail ("distribution channel honours some critical lists but not all: $($partialChannels -join '; ')")
        } elseif ($undeclared.Count -gt 0) {
            Fail ("undeclared readers of a distribution-critical list - add them to listConsumers: " +
                "$($undeclared -join '; ')")
        } else {
            Ok ("$(@($consumers.PSObject.Properties).Count) manifest lists have declared readers; " +
                'every channel honours every critical list')
        }
    }
} catch {
    Fail "list consumer registry check error: $_"
}

Write-Host "`n61. Constructs that behave differently on 5.1 and 7 are refused"
# Step 29 proves the shared writer produces identical bytes on both hosts. This is the static half: the
# constructs that *differ* between the hosts, banned before they reach a script. Each one here has already
# cost a session.
#
#   -Include without -Recurse   5.1 matched 3723 files in a folder holding 3538; 7 matched 4. Neither is
#                               what the author meant, and a survey built on it reports a clean sweep of
#                               almost nothing.
#   .Replace(a, b, third)       5.1 throws (no such overload). 7 binds the third argument to
#                               StringComparison and replaces *every* match, silently - the worse failure,
#                               because the script keeps going with the wrong text.
#   -Encoding UTF8              5.1 writes a BOM, 7 does not. A BOM in generated JSON crashes Python's
#                               json module. Write-Utf8NoBom / Add-Utf8NoBomLine exist for this.
try {
    $hostDiffFiles = @(Get-ChildItem -LiteralPath $PackRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.ps1' } |
        Where-Object { -not (Test-PackPathHasSegment -Path $_.FullName -Segment @('.git', '.tmp', '__pycache__', 'audit_archive')) })
    $hostDiffHits = @()
    foreach ($hf in $hostDiffFiles) {
        $rel = Get-PackRelPathKey -Path $hf.FullName -Root $PackRoot
        $hAst = [System.Management.Automation.Language.Parser]::ParseFile($hf.FullName, [ref]$null, [ref]$null)
        if (-not $hAst) { continue }

        foreach ($cmd in $hAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $cname = $cmd.GetCommandName()
            if (-not $cname) { continue }
            $pnames = @($cmd.CommandElements |
                Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } |
                ForEach-Object { $_.ParameterName.ToLower() })

            if ($cname -match '^(Get-ChildItem|gci|ls|dir)$' -and
                ($pnames | Where-Object { 'include'.StartsWith($_) }) -and
                -not ($pnames | Where-Object { 'recurse'.StartsWith($_) })) {
                $hostDiffHits += "$rel line $($cmd.Extent.StartLineNumber): -Include without -Recurse"
            }

            if ($cname -match '^(Set-Content|Add-Content|Out-File)$') {
                $ce = @($cmd.CommandElements)
                for ($ci = 0; $ci -lt $ce.Count; $ci++) {
                    $el = $ce[$ci]
                    if ($el -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                    if ($el.ParameterName -notmatch '^Enc') { continue }
                    $encText = if ($el.Argument) { $el.Argument.Extent.Text } elseif ($ci + 1 -lt $ce.Count) { $ce[$ci + 1].Extent.Text } else { '' }
                    if ($encText -match 'UTF8|utf-8') {
                        $hostDiffHits += "$rel line $($cmd.Extent.StartLineNumber): $cname -Encoding $encText (use Write-Utf8NoBom)"
                    }
                }
            }
        }

        foreach ($inv in $hAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
            # Static calls are a different API: [regex]::Replace(input, pattern, replacement) is correct
            # with three arguments. Only the instance method has the overload that splits the hosts.
            if ($inv.Static) { continue }
            if ("$($inv.Member)" -ne 'Replace') { continue }
            if (@($inv.Arguments).Count -lt 3) { continue }
            $hostDiffHits += "$rel line $($inv.Extent.StartLineNumber): .Replace() with 3 arguments"
        }
    }

    if ($hostDiffFiles.Count -lt 20) {
        Fail "host-parity scan found only $($hostDiffFiles.Count) scripts - the enumeration is wrong, not the tree"
    } elseif ($hostDiffHits.Count -gt 0) {
        Fail ("constructs that differ between PowerShell 5.1 and 7: " + ($hostDiffHits -join '; '))
    } else {
        Ok "$($hostDiffFiles.Count) scripts carry no host-divergent constructs"
    }
} catch {
    Fail "host-divergent construct scan error: $_"
}

Write-Host "`n62. Shipped .sh entry points are executable"
# Every .sh in this pack was committed 100644, so a fresh clone on Linux or macOS answered
# "Permission denied" to ./install.sh - the first command the install instructions give. No test
# could see it: Windows has no execute bit, and a WSL run reads /mnt/* as 777 no matter what the
# file says, so both hosts reported success on a pack nobody could actually start.
#
# git is the only durable record of the mode - a folder copy, a zip and a Windows checkout all lose
# it - so that is what this asks, on whichever OS is running.
try {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { Write-Host '[SKIP] git not on PATH - the executable bit lives in the index' }
    elseif (-not (Test-PackGitRepo -Root $PackRoot)) {
        # Asks git rather than testing for a .git path: this checkout had its repository deleted and
        # kept a .git directory holding the editor's index cache, so the path test passed and
        # `git ls-files` failed the step on a tree that simply is not versioned (WQ-461).
        Write-Host '[SKIP] not a git checkout - nothing records the mode here'
    } else {
        $modeLines = @(& $git.Source -C $PackRoot ls-files -s -- '*.sh' 2>$null)
        if (-not $modeLines -or $modeLines.Count -eq 0) { Fail 'no .sh files are tracked - the shell entry points are not shipping' }
        else {
            $notExec = @()
            foreach ($line in $modeLines) {
                if ($line -match '^(?<mode>\d{6})\s+\S+\s+\d+\s+(?<path>.+)$') {
                    if ($Matches['mode'] -ne '100755') { $notExec += "$($Matches['path']) ($($Matches['mode']))" }
                }
            }
            if ($notExec.Count -gt 0) {
                Fail ("shipped .sh files are not executable in git - a clone cannot run them: " +
                    ($notExec -join ', ') + " - fix with: git update-index --chmod=+x <file>")
            } else { Ok "$($modeLines.Count) shipped .sh entry points are mode 100755" }

            # Untracked .sh files are reported, not failed: an uncommitted tree is the normal state of
            # this checkout. But git records the mode at `git add` time, so a new wrapper added the
            # ordinary way lands at 100644 and re-introduces exactly the defect above - for one file,
            # which is how this class of bug survives a guard that only looks at what is already tracked.
            $trackedSh = @(& $git.Source -C $PackRoot ls-files -- '*.sh' 2>$null)
            $onDisk = @(Get-ChildItem -LiteralPath $PackRoot -Recurse -File -Filter '*.sh' -ErrorAction SilentlyContinue |
                    Where-Object { -not (Test-PackPathHasSegment -Path $_.FullName -Segment @('.git', '.tmp', 'node_modules')) } |
                    ForEach-Object { Get-PackRelPathKey -Path $_.FullName -Root $PackRoot })
            $untracked = @($onDisk | Where-Object { $trackedSh -notcontains $_ })
            if ($untracked.Count -gt 0) {
                Write-Host ("[INFO] .sh not yet tracked - add with the bit set or it ships at 100644: " +
                    "git add --chmod=+x " + ($untracked -join ' '))
            }
        }
    }
} catch {
    Fail "executable-bit check error: $_"
}

Write-Host "`n63. The path-key primitives answer, and answer differently (WQ-446)"
# Around 430 call sites now compare paths through these five helpers, and every one of those
# comparisons decides whether a file is filtered, mirrored or reported. Nothing tested the helpers
# themselves - the port proved them only indirectly, by other steps passing.
#
# The failure to guard against is not a wrong answer but a uniform one. `Substring().TrimStart('\')`
# was wrong on Linux in exactly this way: it kept the separator, so every key mismatched, and the
# filters built on it excluded nothing while still looking like filters. A helper that answered
# `$true` to everything, or `$false`, would pass any check that only asks "did it return something".
# So the pairs below are chosen to differ: a prefix that matches versus one that is only a string
# prefix (`handoffs` versus `handoffs-archive`), a real path segment versus a name that merely
# contains it (`.git/` versus `x.gitignore`).
try {
    $sep = [IO.Path]::DirectorySeparatorChar
    $probeRoot = "${sep}root${sep}proj"
    $cases = @(
        @{ What = 'separators normalise'; Got = (ConvertTo-PackPathKey 'a\b\c'); Want = 'a/b/c' }
        @{ What = 'edge separators trim'; Got = (ConvertTo-PackPathKey '/a/b/'); Want = 'a/b' }
        @{ What = 'relative key drops the root and its separator'
            Got  = (Get-PackRelPathKey -Path (Join-Path $probeRoot 'docs/x.md') -Root $probeRoot); Want = 'docs/x.md'
        }
        @{ What = 'a path under the prefix is under it'
            Got  = "$(Test-PackPathKeyUnder -PathKey 'docs/handoffs/a.md' -PrefixKey 'docs/handoffs')"; Want = 'True'
        }
        @{ What = 'a sibling that merely starts with the prefix is not'
            Got  = "$(Test-PackPathKeyUnder -PathKey 'docs/handoffs-archive/a.md' -PrefixKey 'docs/handoffs')"; Want = 'False'
        }
        @{ What = 'a real segment is found'; Got = "$(Test-PackPathHasSegment -Path 'a/.git/b' -Segment @('.git'))"; Want = 'True' }
        @{ What = 'a name containing the segment is not'
            Got  = "$(Test-PackPathHasSegment -Path 'a/x.gitignore' -Segment @('.git'))"; Want = 'False'
        }
        @{ What = 'a key splits into its segments'; Got = "$((Split-PackPathKey 'a/b/c').Count)"; Want = '3' }
    )
    # The count is asserted before the answers: building the list by calling the helpers means a
    # missing helper produces an empty list, and an empty list has no wrong answers in it. The
    # negative-control harness for this slice reported success that way before it was fixed.
    if ($cases.Count -ne 8) { Fail "path-key probe built $($cases.Count) of 8 cases - the helpers did not load" }
    else {
        $wrong = @()
        foreach ($c in $cases) {
            if ([string]$c.Got -ne $c.Want) { $wrong += "$($c.What): got '$($c.Got)', wanted '$($c.Want)'" }
        }
        if ($wrong.Count -gt 0) { Fail ("path-key primitives answer wrongly: " + ($wrong -join '; ')) }
        else { Ok "8 path-key cases answer correctly, including the four that must differ from their near-miss" }
    }
} catch {
    Fail "path-key primitive check error: $_"
}

Write-Host "`n64. A bump moves current cites and never the Done log (WQ-437)"
# The work queue is the one document that mixes a current-state claim (which engine is running)
# with historical ones (which engine shipped each Done row). Four historical cites were rewritten
# in two days, twice in one session, and each time the documented protection was a habit: "split
# the file at the Done-log heading and replace only above it, by hand".
#
# Three things now hold that boundary, and all three are planted against here, because a guard
# written in the same session as its fix is the guard most likely to be checking nothing:
#   the tool     - doc_version_sync refuses to write below the heading
#   the config   - VERSION_SYNC.json says where the heading is, and cannot lose the entry quietly
#   the backstop - the set of engine versions the Done log cites may only grow, versus git HEAD
$wqProbe = Join-Path $PackRoot ".tmp/wq437-$PID"
try {
    $verifyWq = Join-Path $PSScriptRoot 'verify-work-queue.ps1'
    New-Item -ItemType Directory -Path (Join-Path $wqProbe 'docs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $wqProbe 'pack/audit') -Force | Out-Null
    Write-Utf8NoBom (Join-Path $wqProbe 'VERSION') "1.8.0`n"
    Write-Utf8NoBom (Join-Path $wqProbe 'pack/audit/manifest.json') '{ "version": "2.22.99" }'

    # A queue the structural checks accept, so the only thing under test is the region policy.
    $queueBody = @(
        '# Work queue - probe',
        '',
        '| Field | Value |',
        '|-------|--------|',
        '| **Next active ID** | **WQ-900** |',
        '| **Pack version** | 1.8.0 |',
        '| **Audit engine** | 2.22.99 |',
        '',
        '## How to use (humans and agents)',
        '',
        '1. One next.',
        '',
        '## Active queue (ordered)',
        '',
        '| ID | Task | Status | Notes |',
        '|----|------|--------|-------|',
        '| WQ-900 | **Probe item** | **Next** | probe |',
        '',
        '## Inbox (triage required)',
        '',
        'None.',
        '',
        '## Engineering backlog',
        '',
        'None.',
        '',
        '## Parked / deferred (explicit - still on radar)',
        '',
        'None.',
        '',
        '## Done log',
        '',
        '| ID | Task | Completed | Evidence |',
        '|----|------|-----------|----------|',
        '| WQ-899 | **Shipped earlier** | 2026-01-01 | proof; Engine **2.22.50** |'
    ) -join "`n"
    $wqFile = Join-Path $wqProbe 'docs/WORK_QUEUE.md'
    Write-Utf8NoBom $wqFile ($queueBody + "`n")

    # Mirrors the shape of the pack's own docs/VERSION_SYNC.json, including the anchored header rule
    # that is what legitimately moves on a bump - without it, arm 4 could not tell "left the past
    # alone" apart from "did nothing at all".
    function New-ProbeVersionSyncConfig {
        param([object[]]$HistoricalRegions)
        $cfg = [ordered]@{
            canonical = [ordered]@{ txtFile = 'VERSION'; txtPattern = '^(\d+\.\d+\.\d+)' }
        }
        if ($null -ne $HistoricalRegions) { $cfg['historicalRegions'] = $HistoricalRegions }
        $cfg['maintainerDocSync'] = [ordered]@{
            enabled               = $true
            auditManifestPath     = 'pack/audit/manifest.json'
            auditVersionScanFiles = @('docs/WORK_QUEUE.md')
            auditContextKeywords  = @('manifest.json', 'audit engine', 'starter pack')
            extraReplacements     = @(
                [ordered]@{
                    file        = 'docs/WORK_QUEUE.md'
                    pattern     = '\| \*\*Audit engine\*\* \| \d+\.\d+\.\d+ \|'
                    replace     = '| **Audit engine** | {auditVersion} |'
                    versionKind = 'audit'
                }
            )
        }
        return ($cfg | ConvertTo-Json -Depth 8)
    }
    $goodRegion = @(([ordered]@{ file = 'docs/WORK_QUEUE.md'; fromHeading = '## Done log' }))
    $cfgFile = Join-Path $wqProbe 'docs/VERSION_SYNC.json'
    Write-Utf8NoBom $cfgFile (New-ProbeVersionSyncConfig -HistoricalRegions $goodRegion)

    $vq = { Invoke-PackScript -PassOutput -NoProfile -ScriptPath $verifyWq -ProjectRoot $wqProbe 2>&1 | Out-String }

    # Arm 1: declared and present - the check must pass, or the failures below prove nothing.
    $out = & $vq
    if ($out -notmatch 'declared a historical region') {
        Fail "verify-work-queue did not confirm the declared region: $out"
    } else { Ok 'a declared Done-log region is recognised' }

    # Arm 2: entry deleted. This is how the protection would actually disappear - someone tidies
    # the config - and nothing else in the system would notice.
    Write-Utf8NoBom $cfgFile (New-ProbeVersionSyncConfig -HistoricalRegions $null)
    $out = & $vq
    if ($out -notmatch 'declares no historicalRegions entry') {
        Fail "a missing historicalRegions entry was not reported: $out"
    } else { Ok 'deleting the region declaration fails the verify' }

    # Arm 3: entry present but pointing at a heading that does not exist. The config still claims
    # protection while the tool syncs the file end to end - the worst of the three states.
    Write-Utf8NoBom $cfgFile (New-ProbeVersionSyncConfig -HistoricalRegions @(
        ([ordered]@{ file = 'docs/WORK_QUEUE.md'; fromHeading = '## Shipped log' })))
    $out = & $vq
    if ($out -notmatch 'but no such heading exists') {
        Fail "a region pointing at an absent heading was not reported: $out"
    } else { Ok 'a region naming a heading that does not exist fails the verify' }
    Write-Utf8NoBom $cfgFile (New-ProbeVersionSyncConfig -HistoricalRegions $goodRegion)

    # Arm 4: the tool itself. The planted Done row uses the phrasing the sync engine does match, so
    # this fails if the boundary is gone - not merely if the patterns change.
    $syncPy = Join-Path $PSScriptRoot 'sync_doc_versions.py'
    Write-Utf8NoBom $wqFile (($queueBody -replace '\| \*\*Audit engine\*\* \| 2\.22\.99 \|', '| **Audit engine** | 2.22.50 |') + "`n" +
        '| WQ-898 | **Older item** | 2025-12-01 | shipped in starter pack 2.22.50 |' + "`n")
    Invoke-PackPython $syncPy $wqProbe 2>&1 | Out-Null
    $after = Get-Content -LiteralPath $wqFile -Raw
    $headerMoved = $after -match '\|\s*\*\*Audit engine\*\*\s*\|\s*2\.22\.99\s*\|'
    $historyHeld = $after -match 'starter pack 2\.22\.50'
    if (-not $headerMoved) { Fail 'doc sync did not update the current-state header cite' }
    elseif (-not $historyHeld) { Fail 'doc sync rewrote a Done-log historical cite - the WQ-437 defect' }
    else { Ok 'sync moved the header cite and left the Done-log cite untouched' }

    # Arm 5: the git backstop, which is the only arm that sees a hand edit. A real commit is needed
    # because the check compares against HEAD, so the probe makes one.
    $gitExe = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitExe) { Write-Host '[SKIP] git not on PATH - cannot exercise the Done-log history backstop' }
    else {
        # core.autocrlf=false: with it on, `git add` writes "LF will be replaced by CRLF" to stderr,
        # and a native command's stderr is a terminating error under this suite's preference - so a
        # line-ending setting on the machine failed the step. Discarding stderr as well, because the
        # next warning git invents should not decide whether this arm runs.
        $safe = @('-c', "safe.directory=$wqProbe", '-c', 'core.autocrlf=false')
        $ident = @('-c', 'user.email=probe@example.invalid', '-c', 'user.name=probe')
        Write-Utf8NoBom $wqFile ($queueBody + "`n")
        & $gitExe.Source @safe init -q $wqProbe 2>$null | Out-Null
        & $gitExe.Source @safe @ident -C $wqProbe add docs/WORK_QUEUE.md 2>$null | Out-Null
        & $gitExe.Source @safe @ident -C $wqProbe commit -q -m probe 2>$null | Out-Null
        # The verify script runs git itself, in a child process, and a scratch repo under .tmp can
        # sit on a filesystem that records no ownership - git then refuses to read it and the check
        # skips. GIT_CONFIG_* passes safe.directory down to that child without touching the user's
        # global config, which a test has no business editing.
        $gitEnvSaved = @{
            count = $env:GIT_CONFIG_COUNT; key = $env:GIT_CONFIG_KEY_0; value = $env:GIT_CONFIG_VALUE_0
        }
        $env:GIT_CONFIG_COUNT = '1'
        $env:GIT_CONFIG_KEY_0 = 'safe.directory'
        $env:GIT_CONFIG_VALUE_0 = $wqProbe
        $out = & $vq
        try {
            if ($out -notmatch 'Done-log engine cites only grew') {
                # Not an Ok: an unproven backstop is the state this whole step exists to end.
                Fail ("history backstop never ran against the probe repo, so it is unproven: " +
                    (($out -split "`n" | Where-Object { $_ -match '\[SKIP\]' }) -join ' / '))
            } else {
                # The blanket-replace signature: the version bumped *from* stops being cited at all.
                Write-Utf8NoBom $wqFile (($queueBody -replace '2\.22\.50', '2.22.99') + "`n")
                $out = & $vq
                if ($out -notmatch 'no longer cites engine version') {
                    Fail 'a rewritten Done-log cite was not caught by the history backstop'
                } else { Ok 'rewriting a committed Done-log cite fails the verify' }
            }
        } finally {
            $env:GIT_CONFIG_COUNT = $gitEnvSaved.count
            $env:GIT_CONFIG_KEY_0 = $gitEnvSaved.key
            $env:GIT_CONFIG_VALUE_0 = $gitEnvSaved.value
        }
    }
} catch {
    Fail "historical region checks error: $_"
} finally {
    if (Test-Path -LiteralPath $wqProbe) { Remove-Item -LiteralPath $wqProbe -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n65. Instructions name an entry point this host can run (WQ-449)"
# Running ./run_audit.sh on Ubuntu completed the audit and then printed four next steps, three of
# which named a .cmd that did not exist on that machine - with the wrong separator. Nothing failed,
# because the only consumer of those strings is a human, which is why it survived the Linux port and
# several releases after it.
#
# Two defects, so two kinds of arm. The strings were wrong *and* three of the files they named were
# never written, so a speller alone would have had nothing to spell. Arms 2 and 6 assert the twins
# exist; arms 1, 3 and 4 assert the speller answers; arm 5 is the one that keeps the next string
# from regressing, and it is planted against rather than trusted.
try {
    $epCases = @()
    foreach ($n in (Get-PackEntryPointNames)) {
        $epCases += @{
            Name  = $n
            Win   = (Get-PackEntryPoint -Name $n -ForWindows)
            Posix = (Get-PackEntryPoint -Name $n -ForPosix)
            Spec  = (Get-PackEntryPointSpec -Name $n)
        }
    }
    # Count first, for the reason step 63 records: a list built by calling the thing under test is
    # empty when that thing failed to load, and an empty list has no wrong answers in it.
    if ($epCases.Count -lt 13) {
        Fail "entry-point probe built $($epCases.Count) cases - the registry did not load"
    } else {
        # Arm 1: the two spellings must actually differ. A speller that returned its input, or the
        # Windows name on every host, is precisely the bug and would satisfy any check that only
        # asks whether a string came back.
        $same = @($epCases | Where-Object { $_.Win -eq $_.Posix } | ForEach-Object { $_.Name })
        if ($same.Count -gt 0) {
            Fail ("entry points spell the same on both hosts, so the host is not being consulted: " +
                ($same -join ', '))
        } else { Ok "$($epCases.Count) entry points spell differently per host" }

        # Arm 2: a registered name whose twin was never written is an instruction that cannot be
        # followed - the actual WQ-449 defect, not a wording problem.
        $unpaired = @()
        foreach ($c in $epCases) {
            foreach ($rel in @($c.Spec.win, $c.Spec.posix)) {
                if (-not (Test-Path -LiteralPath (Join-Path $PackRoot $rel))) {
                    $unpaired += "$($c.Name) -> $rel"
                }
            }
        }
        if ($unpaired.Count -gt 0) {
            Fail ("registered entry points are missing a twin, so remediation text names a file " +
                "that does not exist: " + ($unpaired -join '; '))
        } else { Ok 'every registered entry point ships both twins' }

        # Arm 3: the Python layer is a second copy of the registry, kept for the reason its module
        # docstring gives. Two copies are only safe while something compares them.
        # From $PackRoot, not $PSScriptRoot: the suite takes -PackRoot to test a pack other than the
        # one it ships in, and an arm that reads its own folder silently tests the wrong tree.
        $pyScript = Join-Path $PackRoot 'pack/scripts/pack_entry_points.py'
        $pyRender = Invoke-PackPython $pyScript '--render' 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or -not $pyRender.Trim()) {
            Fail "could not render the Python entry-point registry: $pyRender"
        } else {
            $pyMap = @{}
            foreach ($line in ($pyRender -split "`r?`n")) {
                if ($line -match '^(?<n>[^\t]+)\t(?<w>[^\t]*)\t(?<p>[^\t]*)$') {
                    $pyMap[$Matches.n] = @{ Win = $Matches.w; Posix = $Matches.p }
                }
            }
            $disagree = @()
            foreach ($c in $epCases) {
                $py = $pyMap[$c.Name]
                if (-not $py) { $disagree += "$($c.Name): absent from the Python registry"; continue }
                if ($py.Win -ne $c.Win) { $disagree += "$($c.Name) windows: ps '$($c.Win)' vs py '$($py.Win)'" }
                if ($py.Posix -ne $c.Posix) { $disagree += "$($c.Name) posix: ps '$($c.Posix)' vs py '$($py.Posix)'" }
            }
            foreach ($k in $pyMap.Keys) {
                if (-not ($epCases | Where-Object { $_.Name -eq $k })) {
                    $disagree += "${k}: absent from the PowerShell registry"
                }
            }
            if ($disagree.Count -gt 0) {
                Fail ("the two entry-point registries disagree: " + ($disagree -join '; '))
            } else { Ok "both layers render all $($pyMap.Count) entry points identically" }
        }

        # Arm 4: an unregistered name must be refused in both layers. This is what stops a new
        # message inventing an entry point that has no twin - the quiet way this defect returns.
        $refused = 0
        try { Get-PackEntryPoint -Name 'not-an-entry-point' | Out-Null } catch { $refused++ }
        $pyRefuse = Invoke-PackPython $pyScript '--check-unknown' 2>&1 | Out-String
        if ($pyRefuse -match 'refused') { $refused++ }
        if ($refused -ne 2) {
            Fail "an unregistered entry point was not refused by both layers (refused=$refused of 2)"
        } else { Ok 'both layers refuse an unregistered entry point' }

        # Arm 5: the scanner that catches the 35th string. Instruction text must route through the
        # speller, so a Windows entry-point literal in a message is a defect. Two lines are allowed
        # and both are named here rather than skipped by file, because a file-level exemption would
        # let the next bad string in beside a good one.
        $allowed = @(
            # A Windows-only branch (Test-PackIsWindows) describing the .cmd scripts themselves.
            "-Purpose 'run_audit.cmd, run_tests.bat and every generated project script'",
            # An evidence reference naming a real file, not an instruction to run it.
            '{"type": "file", "ref": "run_audit_tests.bat"}'
        )
        $winLiterals = @($epCases | ForEach-Object { $_.Spec.win } | ForEach-Object { Split-Path $_ -Leaf })
        $litPattern = ($winLiterals | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $msgPattern = '(Write-Host|Write-Warning|Write-Error|throw |print\(|Add-Fix|Add-Improve|' +
        'reasons\.append|Write-Fail|Warn |-Purpose|-Detail|-Fix |f"|echo )'

        function Test-InstructionLine {
            # Returns the offending trimmed line, or $null. Split out so arm 5b can plant against it.
            param([string]$Line, [string]$LitPattern, [string]$MsgPattern, [string[]]$Allowed)
            $t = $Line.Trim()
            if ($t -match '^(#|//|::|<#)') { return $null }
            if ($t -notmatch $LitPattern) { return $null }
            if ($t -notmatch $MsgPattern) { return $null }
            foreach ($a in $Allowed) { if ($t.Contains($a)) { return $null } }
            return $t
        }

        # This file declares the literals and quotes both allowed lines, so scanning it would report
        # its own source. The registry files hold the mapping by definition.
        $selfExempt = @('verify-audit-behavior.ps1', 'pack-paths.ps1', 'pack_entry_points.py')
        $scanFiles = @()
        foreach ($dir in @((Join-Path $PackRoot 'pack/scripts'), (Join-Path $PackRoot 'scripts'))) {
            if (Test-Path -LiteralPath $dir) {
                $scanFiles += @(Get-ChildItem -LiteralPath $dir -File |
                        Where-Object { $_.Extension -in '.ps1', '.py' -and $_.Name -notin $selfExempt })
            }
        }
        if ($scanFiles.Count -lt 20) {
            Fail "instruction scan found only $($scanFiles.Count) files - it is not looking at the pack"
        } else {
            $offenders = @()
            foreach ($f in $scanFiles) {
                $lineNo = 0
                foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
                    $lineNo++
                    $hit = Test-InstructionLine -Line $line -LitPattern $litPattern `
                        -MsgPattern $msgPattern -Allowed $allowed
                    if ($hit) { $offenders += "$($f.Name):${lineNo}: $hit" }
                }
            }
            if ($offenders.Count -gt 0) {
                Fail ("instruction text names a Windows entry point directly instead of calling the " +
                    "speller - unrunnable as printed off Windows: " + ($offenders -join ' | '))
            } else { Ok "$($scanFiles.Count) script files route entry points through the speller" }

            # Arm 5c: keep prose out of the files this scanner reads (WQ-469). The scan above fired
            # three times on one physical line of fill_pack_semantic_report.py - release narrative that
            # *mentioned* an entry point, and later the word for raising an exception, and once `-fix `
            # inside the phrase naming the forbidden behaviour, since -match is case-insensitive. The
            # guard was right every time: it cannot tell prose about an instruction from an
            # instruction, and a file-level exemption would have let the next real one in beside the
            # tolerated one. So the narrative moved to scripts/semantic_report_content.json, and this
            # arm is what stops it moving back.
            #
            # Length is the discriminator, and the measurement is not close: with the narrative out,
            # the longest line in the whole scanned set is 239 characters, while the line it left was
            # 88,997. A limit of 600 is therefore generous to code and impossible for a release note.
            $proseLimit = 600
            $longLines = @()
            foreach ($f in $scanFiles) {
                $lineNo = 0
                foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
                    $lineNo++
                    if ($line.Length -gt $proseLimit) { $longLines += "$($f.Name):${lineNo} is $($line.Length) chars" }
                }
            }
            if ($longLines.Count -gt 0) {
                Fail ("a scanned script carries a line too long to be code, which is how narrative got " +
                    "in front of this scanner three times - move the prose to a data file (WQ-469): " +
                    ($longLines -join ' | '))
            } else { Ok "no scanned script carries a line over $proseLimit chars - narrative stays in data files" }

            # Arm 5b: plant against the scanner. A clean sweep above is only meaningful if the
            # sweep can come back dirty, and this scanner is new in the same slice as its fix.
            $planted = @(
                "    Write-Host 'next: run run_audit.cmd to finish'",
                '    Add-Fix "run scripts\finalize_audit.cmd first"',
                "    reasons.append('run Refresh-AgentContext.cmd')"
            )
            $missed = @($planted | Where-Object {
                    -not (Test-InstructionLine -Line $_ -LitPattern $litPattern `
                            -MsgPattern $msgPattern -Allowed $allowed)
                })
            # And the converse: the scanner must not flag what it is supposed to tolerate, or the
            # clean sweep above proves nothing except that everything was exempted.
            $falsePos = @(
                "# run_audit.cmd is the Windows entry point",
                "    Write-Host `"run `$(Get-PackEntryPoint 'run_audit') next`""
            ) | Where-Object {
                Test-InstructionLine -Line $_ -LitPattern $litPattern `
                    -MsgPattern $msgPattern -Allowed $allowed
            }
            if ($missed.Count -gt 0) {
                Fail ("the instruction scanner missed a planted .cmd instruction: " + ($missed -join ' | '))
            } elseif (@($falsePos).Count -gt 0) {
                Fail ("the instruction scanner flagged a legitimate line: " + (@($falsePos) -join ' | '))
            } else { Ok 'the instruction scanner catches 3 planted defects and tolerates 2 valid lines' }
        }

        # Arm 6: the generated-project templates. A project bootstrapped with only the .cmd half
        # could run run_audit.sh and then had nothing to run for the steps the audit named next.
        $tplDir = Join-Path $PackRoot 'pack/templates/scripts'
        $tplMissing = @()
        foreach ($cmdTpl in @(Get-ChildItem -LiteralPath $tplDir -Filter '*.cmd.template' -File)) {
            # sync_doc_versions ships a .py payload rather than a shell twin.
            if ($cmdTpl.Name -eq 'sync_doc_versions.cmd.template') { continue }
            $shTpl = Join-Path $tplDir ($cmdTpl.Name -replace '\.cmd\.template$', '.sh.template')
            if (-not (Test-Path -LiteralPath $shTpl)) { $tplMissing += $cmdTpl.Name }
        }
        if ($tplMissing.Count -gt 0) {
            Fail ("generated projects would get a Windows-only entry point: " + ($tplMissing -join ', '))
        } else { Ok 'every scripts/ template ships both twins for generated projects' }

        # Arm 7: bootstrap must emit the .sh twins and mark them executable, or the project gets a
        # file it cannot run - step 62's defect, one layer up.
        $bootstrapText = Get-Content -LiteralPath (Join-Path $PackRoot 'pack/scripts/bootstrap-project.ps1') -Raw
        $notEmitted = @()
        foreach ($stem in @('sync_audit_system', 'verify_semantic_audit', 'write_semantic_audit_template', 'finalize_audit')) {
            if ($bootstrapText -notmatch [regex]::Escape("scripts\$stem.sh.template")) { $notEmitted += "$stem (not copied)" }
            if ($bootstrapText -notmatch [regex]::Escape("scripts/$stem.sh")) { $notEmitted += "$stem (no execute bit)" }
        }
        if ($notEmitted.Count -gt 0) {
            Fail ("bootstrap does not ship a runnable .sh twin: " + ($notEmitted -join ', '))
        } else { Ok 'bootstrap copies all four .sh twins and sets the execute bit' }
    }
} catch {
    Fail "entry-point spelling checks error: $_"
}

# WQ-450. 2.22.76 fixed the pack and every new project, and left the existing ones stranded a
# different way: their audit stopped naming a .cmd they cannot run and started naming a .sh they do
# not have. This step holds the two halves together - a twin the manifest requires must be one the
# repair script can actually deliver, and the repair must work on a project shaped like the ones
# already out there.
Write-Host "`n66. A required POSIX twin has a delivery path (WQ-450)"
try {
    $sRepair = Join-Path $PSScriptRoot 'repair-project-scripts.ps1'
    if (-not (Test-Path -LiteralPath $sRepair)) {
        Fail 'repair-project-scripts.ps1 missing - projectRequired demands twins nothing can deliver'
    } else {
        $sRepairText = Get-Content -LiteralPath $sRepair -Raw -Encoding UTF8
        $bManifest = Get-Content -LiteralPath (Join-Path $PackRoot 'pack/audit/manifest.json') -Raw -Encoding UTF8 |
            ConvertFrom-Json

        # Arm 1: both directions. A required twin with no deliverer is unclearable drift (the reason
        # these keys were held out of 2.22.76); a deliverable twin nobody requires is a repair that
        # never gets asked for. The script keeps its own table because a pair needs a template name
        # too, which projectRequired cannot express - so the lists are cross-checked, not shared.
        $deliverable = @([regex]::Matches($sRepairText, "Sh\s*=\s*'([^']+)'") |
            ForEach-Object { ConvertTo-PackPathKey $_.Groups[1].Value })
        $undeliverable = @()
        foreach ($layout in @('flatLayout', 'appLayout')) {
            $lay = $bManifest.projectRequired.$layout
            if (-not $lay) { $undeliverable += "$layout absent from projectRequired"; continue }
            foreach ($prop in $lay.PSObject.Properties) {
                if ($prop.Value -notmatch '\.sh$') { continue }
                # appLayout prefixes every path with app/, which is where the project root points.
                $rel = ConvertTo-PackPathKey ($prop.Value -replace '^app/', '')
                if ($deliverable -notcontains $rel) { $undeliverable += "$layout.$($prop.Name) -> $($prop.Value)" }
            }
        }
        if ($undeliverable.Count -gt 0) {
            Fail ("projectRequired demands a twin the repair script cannot write: " + ($undeliverable -join ', '))
        } else { Ok 'every POSIX twin projectRequired demands is one repair-project-scripts.ps1 delivers' }

        $flatSh = @($bManifest.projectRequired.flatLayout.PSObject.Properties |
            Where-Object { $_.Value -match '\.sh$' } | ForEach-Object { ConvertTo-PackPathKey $_.Value })
        if ($flatSh.Count -eq 0) {
            Fail 'projectRequired declares no POSIX twin - a project can be .cmd-only and still pass as portable'
        } else { Ok "projectRequired requires $($flatSh.Count) POSIX twins per layout" }

        # Arm 2: the templates the repair writes from. Without these the repair reports "shipped
        # template missing" for a file it is the only way to obtain.
        $tplGone = @()
        foreach ($m in [regex]::Matches($sRepairText, "Template\s*=\s*'([^']+)'")) {
            $t = Join-Path $PackRoot ('pack/templates/' + $m.Groups[1].Value)
            if (-not (Test-Path -LiteralPath $t)) { $tplGone += $m.Groups[1].Value }
        }
        if ($tplGone.Count -gt 0) {
            Fail ("repair-project-scripts.ps1 names templates that do not ship: " + ($tplGone -join ', '))
        } else { Ok 'every template the repair writes from is present in pack/templates' }

        # Arm 3: the payload's line endings are pinned by .gitattributes, not by the suffix. *.sh
        # never matched run_audit.sh.template, so the templates fell through to "* text=auto" and a
        # Windows checkout (core.autocrlf=true by default) converted them - after which every
        # generated project got CRLF shell entry points and bash answered "$'\r': command not found",
        # naming no file. Nothing in the tree could see this, because the working copy of an
        # uncommitted file is whatever wrote it.
        $ga = Join-Path $PackRoot '.gitattributes'
        if (-not (Test-Path -LiteralPath $ga)) { Fail '.gitattributes missing - shell endings unpinned' }
        else {
            $gaText = Get-Content -LiteralPath $ga -Raw -Encoding UTF8
            $unpinned = @()
            foreach ($pat in @('*.sh', '*.sh.template')) {
                if ($gaText -notmatch ([regex]::Escape($pat) + '\s+text\s+eol=lf')) { $unpinned += $pat }
            }
            if ($unpinned.Count -gt 0) {
                Fail (".gitattributes does not pin LF for: " + ($unpinned -join ', ') +
                    " - a Windows checkout converts them and the shebang stops resolving")
            } else { Ok '.gitattributes pins LF for shell scripts and shell-script templates' }

            # And the endings on disk now, which the attribute governs only from the next checkout.
            # -Filter twice rather than one -Recurse over everything: the unfiltered enumeration walks
            # .git's object store on every suite run for two suffixes.
            $shOnDisk = @(Get-ChildItem -LiteralPath $PackRoot -Recurse -File -Filter '*.sh' -ErrorAction SilentlyContinue) +
                @(Get-ChildItem -LiteralPath $PackRoot -Recurse -File -Filter '*.sh.template' -ErrorAction SilentlyContinue)
            $crFiles = @()
            foreach ($f in $shOnDisk) {
                if (Test-PackPathHasSegment -Path $f.FullName -Segment @('.git', '.tmp', 'node_modules')) { continue }
                if ([System.IO.File]::ReadAllBytes($f.FullName) -contains 13) {
                    $crFiles += (Get-PackRelPathKey -Path $f.FullName -Root $PackRoot)
                }
            }
            if ($crFiles.Count -gt 0) {
                Fail ("carriage returns in a shell script or its template: " + ($crFiles -join ', '))
            } else { Ok 'no shell script or template in the tree carries a carriage return' }
        }

        # Arm 4: the repair on a project shaped like the ones already out there - Windows twins only,
        # which is exactly what a pre-2.22.77 bootstrap produced.
        $sProbe = Join-Path $PackRoot ".tmp/twin-repair-probe-$PID"
        Remove-Item -LiteralPath $sProbe -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path (Join-Path $sProbe 'scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $sProbe 'docs') -Force | Out-Null
        Write-Utf8NoBom (Join-Path $sProbe 'docs/AUDIT.config.json') '{ "projectName": "TwinProbe" }'
        Write-Utf8NoBom (Join-Path $sProbe 'run_audit.cmd') "@echo off`r`n"
        foreach ($stem in @('sync_audit_system', 'verify_semantic_audit', 'write_semantic_audit_template', 'finalize_audit')) {
            Write-Utf8NoBom (Join-Path $sProbe "scripts/$stem.cmd") "@echo off`r`n"
        }
        # One twin present but CRLF, with content of its own, so the repair is tested on the
        # present-but-unrunnable case and on whether it preserves a project's edits.
        $customSh = Join-Path $sProbe 'run_audit.sh'
        [System.IO.File]::WriteAllText($customSh, "#!/usr/bin/env bash`r`necho PROJECT_CUSTOM_LINE`r`n")

        $sAuditOut = (Invoke-PackScript -PassOutput -NoProfile -ScriptPath $sRepair -ProjectRoot $sProbe -AuditMode 2>&1 | Out-String)
        $sAuditRc = $LASTEXITCODE
        $sAuditReports = ($sAuditOut -match '\[FIX\]') -and ($sAuditRc -ne 0)
        $sAuditWroteNothing = -not (Test-Path -LiteralPath (Join-Path $sProbe 'scripts/finalize_audit.sh'))
        if (-not $sAuditReports) {
            Fail 'a .cmd-only project is not reported by its own audit - the twins would be required with nothing saying they are absent'
        } elseif (-not $sAuditWroteNothing) {
            Fail '-AuditMode wrote into the project - an audit must not mutate the tree it audits'
        } else { Ok '-AuditMode reports the stranded twins as Fix and writes nothing' }

        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $sRepair -ProjectRoot $sProbe -VerifyOnly 2>&1 | Out-Null
        $sVerifyRejects = $LASTEXITCODE -ne 0
        $sVerifyWroteNothing = -not (Test-Path -LiteralPath (Join-Path $sProbe 'scripts/finalize_audit.sh'))
        if (-not ($sVerifyRejects -and $sVerifyWroteNothing)) {
            Fail '-VerifyOnly did not reject the stranded project, or it wrote to disk'
        } else { Ok '-VerifyOnly rejects and writes nothing' }

        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $sRepair -ProjectRoot $sProbe 2>&1 | Out-Null
        $sRepairRc = $LASTEXITCODE
        $stillMissing = @()
        foreach ($rel in @('run_audit.sh', 'scripts/sync_audit_system.sh', 'scripts/verify_semantic_audit.sh',
                'scripts/write_semantic_audit_template.sh', 'scripts/finalize_audit.sh')) {
            $p = Join-Path $sProbe $rel
            if (-not (Test-Path -LiteralPath $p)) { $stillMissing += "$rel (absent)" }
            elseif ([System.IO.File]::ReadAllBytes($p) -contains 13) { $stillMissing += "$rel (CRLF)" }
        }
        if ($sRepairRc -ne 0) { Fail "the repair exited $sRepairRc on a project it is meant to fix" }
        elseif ($stillMissing.Count -gt 0) {
            Fail ("the repair left twins unrunnable: " + ($stillMissing -join ', '))
        } else { Ok 'the repair delivers all five twins as LF' }

        # The CRLF case is repaired in place: rewriting from the template would silently discard a
        # project's own edits, and the carriage returns are the whole defect.
        $customAfter = [System.IO.File]::ReadAllText($customSh)
        if ($customAfter -notmatch 'PROJECT_CUSTOM_LINE') {
            Fail 'the CRLF repair overwrote the project file from the template and lost its content'
        } elseif ($customAfter -match "`r") {
            Fail 'the CRLF repair left carriage returns in place'
        } else { Ok 'a CRLF twin is repaired in place, keeping the project''s own content' }

        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $sRepair -ProjectRoot $sProbe -VerifyOnly 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'the repair does not satisfy its own -VerifyOnly' }
        else { Ok 'after the repair, -VerifyOnly passes' }

        # Arm 5: an entry point the project never took is not a defect. Without this the check fails
        # on every project with no test runner, and people learn to ignore it. run_tests is absent in
        # both spellings in the probe above, so this asserts the skip on the probe already built.
        if (Test-Path -LiteralPath (Join-Path $sProbe 'run_tests.sh')) {
            Fail 'the repair invented run_tests.sh for a project that has no test runner in either spelling'
        } else { Ok 'an entry point absent in both spellings is left alone' }

        # Arm 6: the two places a project can reach this repair. A repair nobody runs repairs nothing,
        # and both couplings have been silently removable until now.
        # Matched on the invocation line, not within a character window of the script name: the
        # neighbouring hook and handoff blocks both pass -AuditMode, so a window wide enough to reach
        # this call is also wide enough to be satisfied by theirs - a guard that reads as specific and
        # cannot fail.
        $wiring = @(
            @{ File = 'pack/scripts/run_audit_core.ps1'; Call = '\$scriptsRepair\b[^\r\n]*-AuditMode'
                Why = "the project's own audit would stop reporting the gap, or would mutate the tree it audits"
            }
            @{ File = 'pack/scripts/update-agent-stack.ps1'; Call = '\$scriptsRepairPs1\b[^\r\n]*-ProjectRoot'
                Why = 'the entry point people run after upgrading would stop delivering the twins'
            }
        )
        $unwired = @()
        foreach ($w in $wiring) {
            $t = Get-Content -LiteralPath (Join-Path $PackRoot $w.File) -Raw -Encoding UTF8
            if ($t -notmatch 'repair-project-scripts\.ps1') {
                $unwired += "$($w.File) - does not reference the repair at all - $($w.Why)"
            } elseif ($t -notmatch $w.Call) {
                $unwired += "$($w.File) - names the repair but does not invoke it as required - $($w.Why)"
            }
        }
        if ($unwired.Count -gt 0) {
            Fail ("the repair is not reachable: " + ($unwired -join ' | '))
        } else { Ok 'the audit reports the gap and Update-AgentStack closes it' }

        Remove-Item -LiteralPath $sProbe -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    Fail "POSIX twin delivery checks error: $_"
} finally {
    Remove-Item -LiteralPath (Join-Path $PackRoot ".tmp/twin-repair-probe-$PID") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n67. The documented POSIX start command runs at mode 644 (WQ-454)"
# Everything the pack does to survive a non-git delivery depends on one command being right.
#
# The execute bit is recorded by git and by nothing else this pack travels through: a folder copy, an
# unzipped archive and exFAT/FAT media all deliver mode 644, and a Windows checkout has no bit to
# carry. install.ps1 repairs that at the destination - but it is reached, off Windows, through
# install.sh, so the one command that fixes the problem is the one command the problem stops.
# `bash install.sh` breaks the loop because bash runs a file it is handed at any mode; `./install.sh`
# does not, and exits 126 before printing anything a reader could act on.
#
# So this is a check on prose, because prose is the delivery mechanism: an agent reads these files and
# types what they say. Measured before writing it, all five primary install docs named a Windows .cmd
# and nothing else - `bash install.sh` appeared in zero documents and `./install.sh` only in changelog
# narrative about past bugs.
try {
    # Docs a reader or agent actually starts from. The changelog and WORK_QUEUE are deliberately out:
    # they discuss `./install.sh` as history, and a scanner that cannot tell narrative from
    # instruction would have to be silenced everywhere, which is how a guard becomes decorative.
    $startDocs = @(
        'README.md'
        'INSTALL.md'
        'INSTALL.txt'
        'AGENTS.md'
        'pack/docs/START_HERE.md'
        'docs/PORTABLE_SETUP.md'
    )

    $posixNames = @()
    foreach ($n in (Get-PackEntryPointNames)) {
        $spec = Get-PackEntryPointSpec -Name $n
        if ($spec -and $spec.posix) { $posixNames += [regex]::Escape($spec.posix) }
    }
    if ($posixNames.Count -eq 0) { Fail 'no POSIX entry points in the registry - nothing to check' }
    else { Ok "$($posixNames.Count) POSIX entry points to hold the docs against" }

    # A line that *begins* with ./entrypoint.sh is an instruction to run it. A mention inside a
    # sentence - "use bash install.sh, not ./install.sh" - is the explanation, and has to stay legal
    # or the note explaining this rule would violate it.
    #
    # The prefix alone cannot separate them, which the negative controls below proved on the first
    # run: a bullet that reads `- ./install.sh` is an instruction, and a wrapped prose line that
    # happens to begin `` `./install.sh` on such a copy ... `` is not, and both start the same way.
    # What separates them is what FOLLOWS the command - arguments, or English. So: strip the marker,
    # then treat the line as prose if any remaining token is an ordinary lowercase word. Real
    # arguments to these entry points are flags, paths, or capitalised (User, Both, MyApp).
    $dotSlashRx = [regex]::new('^\s*(?:[-*>]\s*|\d+[.)]\s*)?`?\.\/(' + ($posixNames -join '|') + ')(?<rest>.*)$')

    function Get-BadStartLines([string[]]$Lines) {
        $hits = @()
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $m = $dotSlashRx.Match($Lines[$i])
            if (-not $m.Success) { continue }
            $rest = ($m.Groups['rest'].Value -replace '`', '').Trim()
            $isProse = $false
            foreach ($tok in @($rest -split '\s+' | Where-Object { $_ })) {
                if ($tok -cmatch '^[a-z]{2,}[.,;:]?$') { $isProse = $true; break }
            }
            if (-not $isProse) { $hits += "line $($i + 1): $($Lines[$i].Trim())" }
        }
        return $hits
    }

    $offenders = @()
    $silent = @()
    foreach ($rel in $startDocs) {
        $p = Join-Path $PackRoot $rel
        if (-not (Test-Path -LiteralPath $p)) { Fail "start doc missing: $rel"; continue }
        $lines = @(Get-Content -LiteralPath $p)
        $bad = @(Get-BadStartLines $lines)
        if ($bad.Count -gt 0) { $offenders += "$rel -> " + ($bad -join '; ') }
        # The other direction, and the one that actually shipped: a doc can satisfy "no ./ command"
        # by naming no POSIX command at all. Windows-only instructions are how this got here.
        if (-not ($lines -join "`n").Contains('install.sh')) { $silent += $rel }
    }

    if ($offenders.Count -gt 0) {
        Fail ("a start doc tells a POSIX reader to run './...', which fails at mode 644 - use 'bash <file>': " +
            ($offenders -join ' | '))
    } else { Ok "$($startDocs.Count) start docs give no './' command" }

    if ($silent.Count -gt 0) {
        Fail ("start doc names no POSIX install path at all - a macOS/Linux reader is told only to run a .cmd: " +
            ($silent -join ', '))
    } else { Ok 'every start doc documents the POSIX install' }

    # Proven able to fail, both directions, per WQ-443. A scanner that flags nothing and one that
    # flags its own explanatory note both read as a clean sweep.
    $planted = @(
        './install.sh User'
        '  ./run_audit.sh'
        '1. ./Check-Requirements.sh'
        '- `./install.sh`'
    )
    $missed = @($planted | Where-Object { (Get-BadStartLines @($_)).Count -eq 0 })
    if ($missed.Count -gt 0) { Fail ("scanner misses a './' instruction: " + ($missed -join ' | ')) }
    else { Ok "scanner catches all $($planted.Count) planted './' instructions" }

    $legal = @(
        'Use `bash install.sh`, not `./install.sh`.'
        'bash install.sh User'
        '`./install.sh` on such a copy answers Permission denied'
        'pwsh -File install.ps1 -Scope User'
        '| Install pack | `Install-AgentStarterPack.cmd` | `install.sh` |'
    )
    $falsePos = @($legal | Where-Object { (Get-BadStartLines @($_)).Count -gt 0 })
    if ($falsePos.Count -gt 0) { Fail ("scanner flags a legal line: " + ($falsePos -join ' | ')) }
    else { Ok "scanner tolerates all $($legal.Count) legal mentions" }

    # The installer must repair both properties the transport drops, or the docs are writing cheques
    # install.ps1 does not honour.
    $installPs1 = Get-Content -LiteralPath (Join-Path $PackRoot 'install.ps1') -Raw
    $needs = @{
        'a CRLF strip on the delivered .sh'        = 'ReadAllBytes'
        'the execute bit on the destination'       = 'Set-PackExecutableBit -Path $installedSh'
        'the execute bit on the source it ran from' = '$PSScriptRoot -Recurse -File -Filter ''*.sh'''
    }
    $absent = @($needs.Keys | Where-Object { -not $installPs1.Contains($needs[$_]) })
    if ($absent.Count -gt 0) { Fail ("install.ps1 no longer applies: " + ($absent -join ', ')) }
    else { Ok 'install.ps1 repairs line endings and both execute-bit locations' }

    # CI must not manufacture the condition it is testing. The blanket chmod that used to open the
    # wrapper step made the Linux job unable to fail while every shipped .sh was committed 100644.
    $wf = Join-Path $PackRoot '.github/workflows/pack-os-smoke.yml'
    if (-not (Test-Path -LiteralPath $wf)) { Fail 'pack-os-smoke.yml missing' }
    else {
        $wfText = Get-Content -LiteralPath $wf -Raw
        if ($wfText -match '(?m)^\s*chmod \+x \./\*\.sh') {
            Fail 'CI blanket-chmods the wrappers before running them - it cannot see a delivery that lost the bit'
        } else { Ok 'CI does not chmod before exercising the wrappers' }

        if ($wfText.Contains('bash install.sh') -and $wfText -match 'chmod 644') {
            Ok 'CI exercises a mode-stripped delivery through bash install.sh'
        } else {
            Fail 'CI has no mode-stripped install arm - the documented first command is untested'
        }

        if ($wfText.Contains('macos-latest')) { Ok 'CI has a macOS job' }
        else { Fail 'no macOS job - macOS is assumed to behave like Linux, which is what WQ-446 disproved' }
    }

    # pack_pwsh_run exists because pack_pwsh_file execs, so a multi-step wrapper cannot use it. Two of
    # the three twins added here have more than one step.
    $wrapText = Get-Content -LiteralPath (Join-Path $PackRoot 'pack/scripts/pwsh-wrap.sh') -Raw
    $missingFn = @(@('pack_pwsh_require', 'pack_pwsh_file', 'pack_pwsh_run') |
            Where-Object { -not ($wrapText -match "(?m)^$_\(\)") })
    if ($missingFn.Count -gt 0) { Fail ("pwsh-wrap.sh is missing: " + ($missingFn -join ', ')) }
    else { Ok 'pwsh-wrap.sh exports require, file (exec) and run (non-exec)' }
} catch {
    Fail "POSIX start-command checks error: $_"
}

Write-Host "`n68. No shipped doc calls the profile rules folder a load path (WQ-457)"
# WQ-456 established that %USERPROFILE%\.cursor\rules is not a rule load path in any editor, and
# corrected the claim in roughly fifteen documents. It came back immediately, in the one file built
# for users of other tools: pack/docs/portable/GENERIC_RULES.md opened with a table headed
# "Load path" whose first row was that folder. Two things let it through, and this step exists for
# both.
#
# 1. The text was a string literal inside sync-portable-docs.ps1, so a sweep of .md files could not
#    reach it. Generated docs need checking at their output, not only their source.
# 2. No single line carried both the path and a load claim - the header two rows up made the
#    assertion. A line-at-a-time grep, which is what the WQ-456 sweep was, is structurally unable to
#    see a claim distributed across a markdown table. So the scanner carries table context.
try {
    function Get-BadLoadClaimLines([string[]]$Lines) {
        $bad = @()
        $headerSaysLoad = $false
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $l = $Lines[$i]

            # Markdown table context: a row whose next line is a |---| separator is a header. Keep
            # its verdict until a blank line or a non-table line closes the table.
            if ($l -match '^\s*\|') {
                if ($l -match '^\s*\|[\s\-:|]+\|\s*$') {
                    # separator - the header's verdict still stands
                } elseif (-not $headerSaysLoad -and $i + 1 -lt $Lines.Count -and
                          $Lines[$i + 1] -match '^\s*\|[\s\-:|]+\|\s*$') {
                    $headerSaysLoad = $l -match '(?i)\|\s*[^|]*\b(load path|loads|loaded|read by)\b'
                }
            } elseif ($l.Trim() -eq '') {
                $headerSaysLoad = $false
            }

            $namesProfileRules =
                ($l -match '%USERPROFILE%\\\.cursor\\rules') -or
                ($l -match '\$env:USERPROFILE\\\.cursor\\rules') -or
                ($l -match '~/\.cursor/rules') -or
                ($l -match 'USERPROFILE.{0,4}\\\.cursor\\rules')
            if (-not $namesProfileRules) { continue }

            $claimsLoad =
                ($l -match '(?i)\b(load path|load from|loads|load|is loaded|are loaded|reads|always-on|applies|apply from|in context)\b') -or
                ($headerSaysLoad -and $l -match '^\s*\|')
            if (-not $claimsLoad) { continue }

            # Prose wraps, so a correct sentence can put its negation on the previous line
            # ("... is not / a place any editor reads."). Widen the disclaimer window by one line
            # rather than exempting the file: the file is fine, the line-at-a-time reading is not.
            $window = if ($i -gt 0) { $Lines[$i - 1] + ' ' + $l } else { $l }
            if ($window -match ('(?i)(best-effort|best effort|not a documented|does not load|' +
                    'do not load|no editor|never loads|not one of|reference copy|will not load|' +
                    'is not loaded|is not\b|unloaded|not load|nothing loads|is not a place)')) {
                continue
            }

            $bad += "line $($i + 1): " + $l.Trim()
        }
        return $bad
    }

    $exts = @('.md', '.mdc', '.template', '.txt')
    $claimScan = New-Object System.Collections.ArrayList
    foreach ($sub in @('pack/docs', 'pack/rules', 'pack/templates', 'docs')) {
        $d = Join-Path $PackRoot $sub
        if (Test-Path -LiteralPath $d) {
            # Deliberately not -Include with -LiteralPath -Recurse: that pair matches every file and
            # has already produced two false-clean verifies in this repo (WQ-443).
            Get-ChildItem -LiteralPath $d -Recurse -File |
                Where-Object { $exts -contains $_.Extension } |
                ForEach-Object { [void]$claimScan.Add($_) }
        }
    }
    foreach ($one in @('AGENTS.md', 'README.md', 'INSTALL.txt')) {
        $p = Join-Path $PackRoot $one
        if (Test-Path -LiteralPath $p) { [void]$claimScan.Add((Get-Item -LiteralPath $p)) }
    }

    # Two maintainer-history files are exempt, and the reason is not convenience. Both must describe
    # this defect in order to record it: the changelog entry for this release and the WORK_QUEUE row
    # that tracked it. A guard that forbids naming the bug it prevents cannot be documented.
    # Everything an installed pack delivers as guidance is in scope.
    $claimExempt = @('AUDIT_SYSTEM_CHANGELOG.md', 'WORK_QUEUE.md')
    $claimFiles = @($claimScan | Sort-Object FullName -Unique |
            Where-Object { $claimExempt -notcontains $_.Name })

    $claimHits = @()
    foreach ($f in $claimFiles) {
        $h = @(Get-BadLoadClaimLines @(Get-Content -LiteralPath $f.FullName))
        if ($h.Count -gt 0) {
            $rel = $f.FullName.Substring($PackRoot.Length).TrimStart('\', '/')
            $claimHits += "$rel -> " + ($h -join '; ')
        }
    }
    if ($claimHits.Count -gt 0) {
        Fail ("a doc presents %USERPROFILE%\.cursor\rules as a place rules load from - WQ-456 " +
            "established it is not: " + ($claimHits -join ' | '))
    } else { Ok "$($claimFiles.Count) docs make no profile-rules load claim" }

    # The generated export is the file that regressed, so assert the generator and its output agree.
    # A correct generator with a stale output is the state this release started in.
    $genOut = Join-Path $PackRoot 'pack/docs/portable/GENERIC_RULES.md'
    if (-not (Test-Path -LiteralPath $genOut)) { Fail 'portable GENERIC_RULES.md missing' }
    else {
        $genText = Get-Content -LiteralPath $genOut -Raw
        if ($genText -notmatch '(?i)\|\s*Load path\s*\|') {
            Fail 'GENERIC_RULES.md lost its load-path table - the claim can no longer be checked'
        } elseif ($genText -notmatch '(?i)\.cursor\\rules\\\*\.mdc.{0,200}No\b') {
            Fail 'GENERIC_RULES.md load-path table does not mark the profile copy as not loading'
        } else { Ok 'the portable export marks the profile copy as not loading' }
    }

    # Proven able to fail, per WQ-443 - and in both directions, because this scanner has to survive
    # contact with ~90 files that mention the profile path legitimately. A scanner that flags nothing
    # and one that flags every correct mention are the same useless result.
    $plantedClaims = @(
        @('| Load path | Tool |', '|---|---|', '| `%USERPROFILE%\.cursor\rules\*.mdc` | Cursor |'),
        @('Rules load from `%USERPROFILE%\.cursor\rules\`.'),
        @('Cursor reads always-on rules from ~/.cursor/rules.'),
        @('| Where rules are loaded | Tool |', '|---|---|', '| `%USERPROFILE%\.cursor\rules` | Cursor |'),
        @('The always-on rules in `%USERPROFILE%\.cursor\rules\` apply to every project.')
    )
    $missedClaims = @(0..($plantedClaims.Count - 1) |
            Where-Object { (Get-BadLoadClaimLines $plantedClaims[$_]).Count -eq 0 })
    if ($missedClaims.Count -gt 0) {
        Fail ("load-claim scanner misses planted defect(s) at index: " + ($missedClaims -join ', '))
    } else { Ok "scanner catches all $($plantedClaims.Count) planted load claims" }

    $legalClaims = @(
        @('`install.ps1` writes a best-effort reference copy to `%USERPROFILE%\.cursor\rules\`.'),
        @('No editor documents loading `%USERPROFILE%\.cursor\rules\`.'),
        @('| Path | Purpose |', '|---|---|', '| `%USERPROFILE%\.cursor\rules\` | Reference copy, does not load |'),
        @('doctor.ps1 checks `%USERPROFILE%\.cursor\rules\` is present.'),
        @('that folder is loaded and %USERPROFILE%\.cursor\rules is not. Those copies are what'),
        @('the profile copy at `%USERPROFILE%\.cursor\rules\` is not a documented load location')
    )
    $falseClaims = @(0..($legalClaims.Count - 1) |
            Where-Object { (Get-BadLoadClaimLines $legalClaims[$_]).Count -gt 0 })
    if ($falseClaims.Count -gt 0) {
        Fail ("load-claim scanner flags correct text at index: " + ($falseClaims -join ', '))
    } else { Ok "scanner tolerates all $($legalClaims.Count) correct mentions" }
} catch {
    Fail "profile-rules load-claim checks error: $_"
}

Write-Host "`n69. 'Is this a git work tree' is asked of git, not of the filesystem (WQ-461)"
# Eleven guards tested `Test-Path .git` and meant "is this versioned". The two questions differ in
# more states than they agree in: a deleted repository can leave a `.git` directory behind holding an
# editor's index cache, a worktree and a submodule record `.git` as a *file*, and a corrupt repo has
# every path in place. This pack hit the first of those an hour after certifying itself git-optional -
# the audit failed on a tree whose only change was that git no longer applied to it.
#
# Both directions are asserted, and the True cases are the important half: a probe that answered
# "not a repo" everywhere would make every git-guarded step skip forever, reporting success while
# observing nothing. That is the WQ-443 failure, and it is strictly worse than the bug it replaces.
# Probes live outside the pack folder so a maintainer checkout that still carries .git does not
# make every subfolder answer "inside work tree" to git -C (WQ-461 / step 69 false positive).
$gitProbeRoot = Join-Path (Get-PackTempDir) "AgentStarterPack-gitrepo-probe-$PID"
try {
    if (Test-Path -LiteralPath $gitProbeRoot) { Remove-Item -LiteralPath $gitProbeRoot -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $gitProbeRoot -Force | Out-Null

    $noGitDir = Join-Path $gitProbeRoot 'absent'
    New-Item -ItemType Directory -Path $noGitDir -Force | Out-Null

    # `.git` as a file is the worktree/submodule shape, and it defeats a path test just as thoroughly
    # as a directory does - Test-Path answers yes for both.
    $gitAsFile = Join-Path $gitProbeRoot 'dotgit-is-a-file'
    New-Item -ItemType Directory -Path $gitAsFile -Force | Out-Null
    Write-Utf8NoBom (Join-Path $gitAsFile '.git') 'gitdir: /nowhere/that/exists'

    # The exact shape that broke this pack: a `.git` directory containing only an editor's cache.
    $gitCacheOnly = Join-Path $gitProbeRoot 'dotgit-cache-only'
    New-Item -ItemType Directory -Path (Join-Path $gitCacheOnly '.git/cursor/crepe') -Force | Out-Null
    Write-Utf8NoBom (Join-Path $gitCacheOnly '.git/cursor/crepe/index.bin') 'x'

    $expectations = @(
        @{ label = 'no .git at all';                 root = $noGitDir;                             want = $false },
        @{ label = '.git is a file pointing nowhere'; root = $gitAsFile;                           want = $false },
        @{ label = '.git holds only an editor cache'; root = $gitCacheOnly;                        want = $false },
        @{ label = 'path does not exist';             root = (Join-Path $gitProbeRoot 'ghost');    want = $false },
        @{ label = 'empty string root';               root = '';                                   want = $false }
    )

    # The positive controls need a real repository, so they only run where git does. Skipped rather
    # than assumed: without them this step proves only that the probe can say no.
    $gitForProbe = Get-Command git -ErrorAction SilentlyContinue
    if ($gitForProbe) {
        $realRepo = Join-Path $gitProbeRoot 'real'
        New-Item -ItemType Directory -Path $realRepo -Force | Out-Null
        & $gitForProbe.Source init -q $realRepo *> $null
        $nestedInRepo = Join-Path $realRepo 'nested/deeper'
        New-Item -ItemType Directory -Path $nestedInRepo -Force | Out-Null
        $expectations += @{ label = 'fresh git init repository';       root = $realRepo;     want = $true }
        $expectations += @{ label = 'subdirectory of a real repository'; root = $nestedInRepo; want = $true }
    } else {
        Write-Host '[SKIP] git not on PATH - the positive controls need a real repository'
    }

    $wrongAnswers = @()
    foreach ($case in $expectations) {
        $got = Test-PackGitRepo -Root $case.root
        if ($got -ne $case.want) {
            $wrongAnswers += ("$($case.label): got $got, want $($case.want)")
        }
    }
    if ($wrongAnswers.Count -gt 0) {
        Fail ("Test-PackGitRepo answers wrongly - " + ($wrongAnswers -join '; '))
    } else {
        $positives = @($expectations | Where-Object { $_.want }).Count
        Ok "Test-PackGitRepo correct on $($expectations.Count) controls ($positives positive)"
    }

    # The guard is only useful where it is used. A future edit that reverts a call site to a path test
    # would leave this step passing while the defect returns, so the call sites are asserted too.
    $gitGuardCallers = @{
        'pack/scripts/verify-audit-behavior.ps1' = 1
        'pack/scripts/verify-work-queue.ps1'     = 1
        'pack/scripts/run_audit_core.ps1'        = 2
    }
    $missingGuard = @()
    foreach ($callerRel in $gitGuardCallers.Keys) {
        $callerPath = Join-Path $PackRoot ($callerRel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $callerPath)) { $missingGuard += "$callerRel (absent)"; continue }
        $uses = @(Select-String -LiteralPath $callerPath -Pattern 'Test-PackGitRepo\s+-Root' -AllMatches)
        if ($uses.Count -lt $gitGuardCallers[$callerRel]) {
            $missingGuard += "$callerRel ($($uses.Count) of $($gitGuardCallers[$callerRel]))"
        }
    }
    if ($missingGuard.Count -gt 0) {
        Fail ("git-repo guard is not used where it must be: " + ($missingGuard -join ', ') +
            " - a .git path test there fails the audit on a tree that simply is not versioned")
    } else { Ok 'all 4 git-guarded call sites ask git rather than the filesystem' }
} catch {
    Fail "git work tree probe checks error: $_"
} finally {
    # A git repo created under .tmp holds no locks, but leaving it would put a nested repository
    # inside this checkout, which is exactly the kind of thing other steps scan for.
    if (Test-Path -LiteralPath $gitProbeRoot) {
        Get-ChildItem -LiteralPath $gitProbeRoot -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_.Attributes = 'Normal' } catch { } }
        Remove-Item -LiteralPath $gitProbeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n70. An inert always-on rule in the profile is reported, not trusted (WQ-460)"
# Step 68 scans *shipped* docs for the false claim that the profile rules folder is a load path. It
# cannot see the other half of the same defect: a rule file sitting in that folder, shipped by
# nobody, declaring alwaysApply:true. One did, for months - it also claimed to be "referenced from
# agent-defaults-always.mdc" and to be "the canonical copy", and all three claims were false. That is
# worse than a missing rule, because a missing rule is silent while this one reads as authoritative
# to anyone who opens it, including an agent told to go and read the rules.
#
# `install.ps1 -Prune` structurally cannot catch it: pruning removes what a previous install recorded
# shipping, and an orphan is by definition absent from that record. Detection is the only option.
#
# Tests Get-PackOrphanAlwaysOnRule directly against planted fixtures, and separately asserts that
# doctor.ps1 calls it. The first version of this step shelled out to doctor.ps1 instead, which
# recursed: doctor calls verify-audit-system.ps1, which runs this suite, which called doctor. It ran
# twelve levels deep and had to be killed - so the rule for this suite is that no step may invoke
# doctor.ps1, and testing the extracted function is what makes that possible.
$orphanProbe = Join-Path $PackRoot ".tmp/orphan-rule-probe-$PID"
try {
    if (Test-Path -LiteralPath $orphanProbe) { Remove-Item -LiteralPath $orphanProbe -Recurse -Force -ErrorAction SilentlyContinue }
    $fakeRules = Join-Path $orphanProbe 'rules'
    New-Item -ItemType Directory -Path $fakeRules -Force | Out-Null

    $shippedNames = @(Get-ChildItem (Join-Path $PackRoot 'pack/rules') -Filter *.mdc | ForEach-Object { $_.Name })
    if ($shippedNames.Count -eq 0) { throw 'no shipped rules found - the fixture would prove nothing' }

    # A shipped rule, copied in under its real name: delivery is not the defect, so this must not be
    # reported however many alwaysApply:true lines it contains.
    $shippedSample = @(Get-ChildItem (Join-Path $PackRoot 'pack/rules') -Filter *.mdc |
        Where-Object { ((Get-Content -LiteralPath $_.FullName -TotalCount 12) -join "`n") -match '(?m)^\s*alwaysApply:\s*true\s*$' } |
        Select-Object -First 1)
    if (-not $shippedSample) { throw 'no shipped alwaysApply:true rule to build the negative control from' }
    Copy-Item -LiteralPath $shippedSample.FullName -Destination (Join-Path $fakeRules $shippedSample.Name) -Force

    $cleanOrphans = @(Get-PackOrphanAlwaysOnRule -ProfileRulesDir $fakeRules -ShippedRuleNames $shippedNames)

    # The exact shape that survived for months, including the false cross-reference.
    Write-Utf8NoBom (Join-Path $fakeRules 'planted-inert-rule.mdc') @"
---
description: Planted orphan for step 70
alwaysApply: true
---

# Planted

Referenced from ``agent-defaults-always.mdc`` (always-on).
"@
    # An orphan that makes no always-on claim - somebody's private note. Must stay unreported, or the
    # warning that matters gets tuned out.
    Write-Utf8NoBom (Join-Path $fakeRules 'planted-optional-rule.mdc') @"
---
description: Planted orphan that makes no always-on claim
alwaysApply: false
---

# Planted optional
"@
    # Discusses alwaysApply in the body without declaring it - which the pack's own docs do when they
    # explain this very defect. Front matter is the claim; prose about it is not.
    Write-Utf8NoBom (Join-Path $fakeRules 'planted-discusses-only.mdc') @"
---
description: Planted orphan that only discusses the flag
alwaysApply: false
---

# Discussion

A file that sets ``alwaysApply: true`` in the profile applies to nothing.
"@
    $plantedOrphans = @(Get-PackOrphanAlwaysOnRule -ProfileRulesDir $fakeRules -ShippedRuleNames $shippedNames)
    $plantedNames = @($plantedOrphans | ForEach-Object { $_.Name })

    $orphanProblems = @()
    if ($cleanOrphans.Count -ne 0) {
        $orphanProblems += "flags a shipped rule as an orphan ($(@($cleanOrphans | ForEach-Object { $_.Name }) -join ', '))"
    }
    if ($plantedNames -notcontains 'planted-inert-rule.mdc') {
        $orphanProblems += 'misses a planted alwaysApply:true orphan'
    }
    if ($plantedNames -contains 'planted-optional-rule.mdc') {
        $orphanProblems += 'flags an orphan that makes no always-on claim'
    }
    if ($plantedNames -contains 'planted-discusses-only.mdc') {
        $orphanProblems += 'flags a file that only discusses alwaysApply in its body'
    }
    if ($plantedNames -contains $shippedSample.Name) {
        $orphanProblems += 'flags a shipped rule once other orphans are present'
    }
    if ((Get-PackOrphanAlwaysOnRule -ProfileRulesDir '' ).Count -ne 0) {
        $orphanProblems += 'returns hits for an empty directory argument'
    }
    if ((Get-PackOrphanAlwaysOnRule -ProfileRulesDir (Join-Path $orphanProbe 'nowhere')).Count -ne 0) {
        $orphanProblems += 'returns hits for a directory that does not exist'
    }
    if ($orphanProblems.Count -gt 0) {
        Fail ("orphan always-on rule detection is wrong - " + ($orphanProblems -join '; '))
    } else {
        Ok 'inert always-on orphan is detected; shipped, optional and discussion-only files are not'
    }

    # The detector is only useful where it is called. Asserted by inspection rather than by running
    # doctor, for the recursion reason above.
    $doctorText = Get-Content -LiteralPath (Join-Path $PackRoot 'pack/scripts/doctor.ps1') -Raw
    if ($doctorText -notmatch 'Get-PackOrphanAlwaysOnRule') {
        Fail 'doctor.ps1 no longer calls Get-PackOrphanAlwaysOnRule - an inert profile rule would go unreported'
    } elseif ($doctorText -notmatch 'inert rule') {
        Fail 'doctor.ps1 calls the detector but no longer reports what it found'
    } else { Ok 'doctor.ps1 calls the detector and reports the file it names' }

    # Guards the recursion itself, since that cost a killed 25-minute run: no step in this suite may
    # invoke doctor.ps1, because doctor runs verify-audit-system.ps1, which runs this suite.
    $selfText = Get-Content -LiteralPath $PSCommandPath -Raw
    # Single-quoted on purpose: in a double-quoted string PowerShell expands $doctor to nothing and
    # leaves a trailing backslash, so the pattern fails to compile rather than failing to match.
    $doctorInvocations = @([regex]::Matches($selfText, '(?m)^[^#\r\n]*-File\s+\$doctor')) +
        @([regex]::Matches($selfText, '(?m)^[^#\r\n]*ScriptPath\s+\$doctor'))
    if ($doctorInvocations.Count -gt 0) {
        Fail ("this suite invokes doctor.ps1 ($($doctorInvocations.Count) site(s)) - doctor runs " +
            'verify-audit-system.ps1, which runs this suite, so the run recurses until killed')
    } else { Ok 'no step invokes doctor.ps1 - the suite cannot recurse through it' }
} catch {
    Fail "orphan always-on rule checks error: $_"
} finally {
    if (Test-Path -LiteralPath $orphanProbe) {
        Remove-Item -LiteralPath $orphanProbe -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n71. A step cannot be added without declaring how it is proven able to fail (WQ-443)"
# The suite is the thing this pack trusts most, and nothing stopped a step from arriving with no
# control at all - six such guards shipped in a single day. This step closes the door for step 72
# onward by comparing the suite's own announcements against pack/audit/behavior-controls.json.
#
# What it deliberately does NOT do is read a step's body looking for a plant. That was implemented
# first and abandoned on evidence: three legitimate idioms are in use, and a heuristic wide enough to
# accept all three scored step 69 - seven controls, two of them positive - as having none. A guard
# that cannot tell a real control from a comment claiming one is the WQ-443 defect wearing the
# WQ-443 fix as a costume. Comparing two declared lists is exact, and the seal is what stops the
# declaration being free: `grandfathered-pre-wq443` is valid only at or below schemaSealedAtStep.
$controlsPath = Join-Path $PackRoot 'pack\audit\behavior-controls.json'
if (-not (Test-Path -LiteralPath $controlsPath)) {
    Fail "no control registry at pack\audit\behavior-controls.json - every behavior step must declare how it is proven able to fail (WQ-443)"
} else {
    $registry = $null
    try { $registry = Get-Content -LiteralPath $controlsPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { $registry = $null }

    $suiteText = Get-Content -LiteralPath $PSCommandPath -Raw -Encoding UTF8
    $controlProblems = @(Get-PackBehaviorControlProblem -SuiteText $suiteText -Registry $registry)
    if ($controlProblems.Count -gt 0) {
        Fail ("suite and control registry disagree - " + ($controlProblems -join '; '))
    } else {
        $declared = @($registry.steps).Count
        $exemptCount = @($registry.steps | Where-Object { $_.status -eq 'exempt' }).Count
        $mutationCount = @($registry.steps | Where-Object { $_.status -eq 'mutation' }).Count
        # The exempt set is printed as the declared list, not only as a total: WQ-467's incident was a
        # status change nobody could account for, and a bare count is what let it pass as scenery.
        $exemptDeclared = @(@($registry.exemptSteps) | ForEach-Object { [int]$_ } | Sort-Object -Unique)
        $exemptLabel = if ($exemptDeclared.Count -gt 0) { "exempt $exemptCount (declared: $($exemptDeclared -join ', '))" } else { "exempt $exemptCount" }
        Ok "all $declared steps declared (mutation $mutationCount, $exemptLabel, seal $($registry.schemaSealedAtStep))"
        # Reported every run, on purpose. A retrofit backlog nobody sees is how an exclusion list turns
        # into no checker at all - the same way a checker without exclusions gets muted.
        if ($exemptCount -gt 0) {
            Write-Host "[INFO] $exemptCount step(s) still exempt as grandfathered - retrofit backlog, see docs/GUARD_PROOF_PLAN.md Phase 5"
        }
    }

    # WQ-443 on this step itself. The positive control matters as much as the negatives: a checker that
    # returned a problem for everything would fail the suite loudly and prove nothing.
    # Assembled from fragments rather than written out, because the checker reads *this* file: a
    # literal announcement inside a fixture registers as a real step. Written as a here-string first,
    # and the checker's duplicate arm caught it immediately - 73 announcements for 71 steps, with
    # "step 1 is announced 2 times". That duplicate arm is also the standing guard against anyone
    # reintroducing a literal fixture here, so no further mechanism is needed.
    # (The escaped-quote form used in the cases below is safe: `Write-Host `" does not match the
    # pattern, which requires a bare quote straight after the command.)
    $mkAnnounce = { param($n, $t) 'Write-Host "' + '`n' + "$n. $t" + '"' }
    $goodSuite = (& $mkAnnounce 1 'first step') + "`n" + (& $mkAnnounce 2 "'quoted' second step")
    $goodRegistry = [pscustomobject]@{
        schemaSealedAtStep = 2
        closedReasons      = @('grandfathered-pre-wq443')
        reasonVocabulary   = [pscustomobject]@{ 'grandfathered-pre-wq443' = 'x'; 'not-applicable' = 'y' }
        exemptSteps        = @(1, 2)
        steps              = @(
            [pscustomobject]@{ step = 1; title = 'first step';           status = 'exempt'; reason = 'grandfathered-pre-wq443' },
            [pscustomobject]@{ step = 2; title = "'quoted' second step"; status = 'exempt'; reason = 'grandfathered-pre-wq443' }
        )
    }

    $baseline = @(Get-PackBehaviorControlProblem -SuiteText $goodSuite -Registry $goodRegistry)
    if ($baseline.Count -ne 0) {
        Fail ("control registry checker rejects a correct suite/registry pair, so its negatives prove nothing - " +
            ($baseline -join '; '))
    } else {
        # Each case mutates the good pair in exactly one way and must be caught.
        $newReg = {
            param($mutate)
            $copy = $goodRegistry | ConvertTo-Json -Depth 8 | ConvertFrom-Json
            & $mutate $copy
            return $copy
        }
        $controlCases = @(
            # Built with $mkAnnounce, not written out. The first version appended the announcement in
            # escaped form, which does not match the pattern - so the "undeclared step" was never in
            # the fixture and the control passed while planting nothing. Step 71 failed on its own
            # first run and said so, which is the only reason this is written correctly now.
            @{ label = 'a step the registry does not declare'
               suite = ($goodSuite + "`n" + (& $mkAnnounce 3 'undeclared step'))
               reg   = $goodRegistry
               wantAnnounced = 3 }
            @{ label = 'a registry entry the suite does not announce'
               suite = $goodSuite
               reg   = (& $newReg { param($r) $r.steps = @($r.steps) + [pscustomobject]@{ step = 9; title = 'ghost'; status = 'exempt'; reason = 'grandfathered-pre-wq443' } }) }
            @{ label = 'a title that drifted from the suite'
               suite = $goodSuite
               reg   = (& $newReg { param($r) $r.steps[1].title = 'something else' }) }
            @{ label = 'grandfathering claimed above the seal'
               suite = ($goodSuite + "`n" + (& $mkAnnounce 3 'a new step'))
               reg   = (& $newReg { param($r) $r.steps = @($r.steps) + [pscustomobject]@{ step = 3; title = 'a new step'; status = 'exempt'; reason = 'grandfathered-pre-wq443' } })
               wantAnnounced = 3 }
            @{ label = 'a mutation status with no spec to apply'
               suite = $goodSuite
               reg   = (& $newReg { param($r) $r.steps[0].status = 'mutation'; $r.steps[0].reason = $null }) }
            @{ label = 'a mutation whose find and replace are identical'
               suite = $goodSuite
               reg   = (& $newReg { param($r)
                        $r.steps[0].status = 'mutation'
                        $r.steps[0].reason = $null
                        $r.steps[0] | Add-Member -NotePropertyName expectFailIn -NotePropertyValue @(1) -Force
                        $r.steps[0] | Add-Member -NotePropertyName mutation -NotePropertyValue ([pscustomobject]@{ file = 'x'; find = 'same'; replace = 'same' }) -Force }) }
            @{ label = 'a create mutation with nothing to write'
               suite = $goodSuite
               reg   = (& $newReg { param($r)
                        $r.steps[0].status = 'mutation'
                        $r.steps[0].reason = $null
                        $r.steps[0] | Add-Member -NotePropertyName expectFailIn -NotePropertyValue @(1) -Force
                        $r.steps[0] | Add-Member -NotePropertyName mutation -NotePropertyValue ([pscustomobject]@{ file = 'x'; action = 'create' }) -Force }) }
            @{ label = 'a mutation action the runner cannot apply'
               suite = $goodSuite
               reg   = (& $newReg { param($r)
                        $r.steps[0].status = 'mutation'
                        $r.steps[0].reason = $null
                        $r.steps[0] | Add-Member -NotePropertyName expectFailIn -NotePropertyValue @(1) -Force
                        $r.steps[0] | Add-Member -NotePropertyName mutation -NotePropertyValue ([pscustomobject]@{ file = 'x'; action = 'rename' }) -Force }) }
            @{ label = 'not-applicable with no justification'
               suite = $goodSuite
               reg   = (& $newReg { param($r) $r.steps[0].reason = 'not-applicable' }) }
            @{ label = 'a reason outside the vocabulary'
               suite = $goodSuite
               reg   = (& $newReg { param($r) $r.steps[0].reason = 'because-i-said-so' }) }
            @{ label = 'a status that is neither proven nor exempt'
               suite = $goodSuite
               reg   = (& $newReg { param($r) $r.steps[0].status = 'probably-fine' }) }
            @{ label = 'the same step declared twice'
               suite = $goodSuite
               reg   = (& $newReg { param($r) $r.steps = @($r.steps) + $r.steps[0] }) }
            @{ label = 'no seal, so a closed reason never expires'
               suite = $goodSuite
               reg   = (& $newReg { param($r) $r.PSObject.Properties.Remove('schemaSealedAtStep') }) }
            # WQ-467, both directions. The benign one matters as much as the regression: a row that
            # gained a proof without the declaration being updated is how the declaration rots into
            # a number nobody trusts, which is the state the incident was found in.
            @{ label = 'a row that stopped being exempt without the declaration changing'
               suite = $goodSuite
               reg   = (& $newReg { param($r)
                        $r.steps[0].status = 'mutation'
                        $r.steps[0].reason = $null
                        $r.steps[0] | Add-Member -NotePropertyName expectFailIn -NotePropertyValue @(1) -Force
                        $r.steps[0] | Add-Member -NotePropertyName mutation -NotePropertyValue ([pscustomobject]@{ file = 'x'; find = 'a'; replace = 'b' }) -Force }) }
            @{ label = 'a row exempt without being declared exempt'
               suite = $goodSuite
               reg   = (& $newReg { param($r) $r.exemptSteps = @(1) }) }
            @{ label = 'no exemptSteps list at all, so a status change disagrees with nothing'
               suite = $goodSuite
               reg   = (& $newReg { param($r) $r.PSObject.Properties.Remove('exemptSteps') }) }
            @{ label = 'a missing registry'
               suite = $goodSuite
               reg   = $null }
            @{ label = 'a suite whose announcement shape changed'
               suite = "Write-Step 'nothing matches this'"
               reg   = $goodRegistry }
        )
        # A plant has to be the input it claims to be before its result means anything. The cases that
        # add a step say how many announcements their fixture should contain, so an inert plant fails
        # here with the reason, instead of passing quietly as a caught defect.
        $inertPlants = @()
        foreach ($case in $controlCases) {
            if ($null -eq $case.wantAnnounced) { continue }
            $parsed = @(Get-PackBehaviorStepAnnouncement -SuiteText $case.suite).Count
            if ($parsed -ne $case.wantAnnounced) {
                $inertPlants += "$($case.label): fixture parses to $parsed announcement(s), expected $($case.wantAnnounced)"
            }
        }
        if ($inertPlants.Count -gt 0) {
            Fail ("planted fixtures are not the input they claim to be - " + ($inertPlants -join '; '))
        }

        $uncaught = @()
        foreach ($case in $controlCases) {
            $got = @(Get-PackBehaviorControlProblem -SuiteText $case.suite -Registry $case.reg)
            if ($got.Count -eq 0) { $uncaught += $case.label }
        }
        if ($uncaught.Count -gt 0) {
            Fail ("control registry checker misses planted defects: " + ($uncaught -join '; '))
        } else {
            Ok "checker accepts a correct pair and catches all $($controlCases.Count) planted defects"
        }
    }

    # The seal is the whole enforcement mechanism, so raising it must be a deliberate, visible act
    # rather than the easiest way to make this step green again.
    if ([int]$registry.schemaSealedAtStep -ne 70) {
        Fail ("control registry seal is $($registry.schemaSealedAtStep), expected 70 - raising the seal " +
            'grandfathers new steps wholesale; if that is intended, change it here and say why in the changelog')
    } else { Ok 'seal is pinned at 70, so a new step cannot inherit grandfathering' }
}

Write-Host "`n72. A failure is attributed to the step that raised it (WQ-443 Phase 3)"
# The mutation runner has to know which step went red, not merely that something did. Output parsing
# cannot answer that: a planted control invokes child verifies whose output carries the identical
# `[FAIL]` prefix, and a trial parse of one run credited five failures to two steps when the suite's
# own count was one. So attribution comes from the call site. This step proves the mapping, and it
# proves it partly against *itself* - the announcement above is the live input.
$attrProblems = @()

# Deliberately unsorted, and with a gap: nothing may depend on registration order or on steps being
# contiguous, which they stop being the moment one is removed.
$attrMap = @(
    [pscustomobject]@{ Step = 40; Line = 300 },
    [pscustomobject]@{ Step = 10; Line = 100 },
    [pscustomobject]@{ Step = 20; Line = 200 }
)
$attrCases = @(
    @{ label = 'line before every announcement'; line = 50;  want = $null },
    @{ label = 'exactly on an announcement';     line = 100; want = 10 },
    @{ label = 'just after an announcement';     line = 101; want = 10 },
    @{ label = 'just before the next one';       line = 199; want = 10 },
    @{ label = 'inside the middle step';         line = 250; want = 20 },
    @{ label = 'far past the last announcement'; line = 9999; want = 40 }
)
foreach ($c in $attrCases) {
    $got = Resolve-PackBehaviorStep -Announcements $attrMap -Line $c.line
    if ($got -ne $c.want) {
        $attrProblems += "$($c.label): got '$got', want '$($c.want)'"
    }
}
# A resolver that answered $null everywhere would satisfy only the first case, and one that answered
# the last step everywhere would satisfy only the last - the pair above is what makes it a control.
if ($null -ne (Resolve-PackBehaviorStep -Announcements $null -Line 5)) {
    $attrProblems += 'a null announcement map should resolve to nothing, not to a step'
}
if ($null -ne (Resolve-PackBehaviorStep -Announcements @() -Line 5)) {
    $attrProblems += 'an empty announcement map should resolve to nothing, not to a step'
}
if ($attrProblems.Count -gt 0) {
    Fail ('step attribution is wrong - ' + ($attrProblems -join '; '))
} else {
    Ok "line-to-step resolution correct on $($attrCases.Count) controls plus both empty cases"
}

# Live self-check: the map really parsed from this file, and this step's own body resolves to 72.
# If the announcement pattern or the map ever stops matching reality, this fails here rather than
# silently mis-crediting a mutation to the wrong step later.
$liveMap = @(Get-SuiteAnnouncementMap)
$hereLine = Get-SuiteTopLevelLine
$hereStep = Resolve-PackBehaviorStep -Announcements $liveMap -Line $hereLine
if ($liveMap.Count -lt 1) {
    Fail 'the suite could not parse its own announcements, so no failure can be attributed'
} elseif ($hereLine -le 0) {
    Fail 'the top-level line could not be determined, so every failure would attribute to nothing'
} elseif ($hereStep -ne 72) {
    Fail "this step's own body attributes to step '$hereStep', not 72 - the announcement map disagrees with the file"
} else {
    Ok "live map holds $($liveMap.Count) steps and this body attributes to step 72"
}

# The results file is the runner's only input, so its shape is asserted here rather than discovered
# in Phase 4. Written in-process with a synthetic record: running the suite again to produce a real
# one is the recursion step 70 was killed for.
$resultsProbe = Join-Path $PackRoot ".tmp/attr-results-$PID.json"
$savedRecords = @($script:failRecords)
$savedResultsPath = $ResultsPath
try {
    $script:failRecords = @(
        [pscustomobject]@{ step = 72; line = 4321; message = 'synthetic attributed failure' },
        [pscustomobject]@{ step = $null; line = 4322; message = 'synthetic unattributed failure' }
    )
    $ResultsPath = $resultsProbe
    Write-SuiteResults
    if (-not (Test-Path -LiteralPath $resultsProbe)) {
        Fail '-ResultsPath wrote nothing, so the mutation runner would have no input'
    } else {
        $parsed = Get-Content -LiteralPath $resultsProbe -Raw -Encoding UTF8 | ConvertFrom-Json
        $shape = @()
        if (@($parsed.failures).Count -ne 2) { $shape += "expected 2 failure records, got $(@($parsed.failures).Count)" }
        if ($parsed.unattributed -ne 1) { $shape += "expected unattributed=1, got '$($parsed.unattributed)'" }
        if (@($parsed.failures | Where-Object { $_.step -eq 72 }).Count -ne 1) { $shape += 'the attributed record lost its step number' }
        if ($null -eq $parsed.failCount) { $shape += 'failCount is absent' }
        # The raw line must survive too. Without it a mutation that breaks the resolver leaves the
        # runner with nothing to re-attribute from, which is how step 72 came back "not proven" on the
        # runner's very first execution.
        if (@($parsed.failures | Where-Object { [int]$_.line -gt 0 }).Count -ne 2) { $shape += 'the recorded line is missing, so a broken resolver could not be recovered from' }
        if ($shape.Count -gt 0) { Fail ('results file shape is wrong - ' + ($shape -join '; ')) }
        else { Ok 'results file carries failCount, per-failure step numbers and an unattributed count' }
    }
} finally {
    $script:failRecords = $savedRecords
    $ResultsPath = $savedResultsPath
    Remove-Item -LiteralPath $resultsProbe -Force -ErrorAction SilentlyContinue
}

Write-Host "`n73. A mutation that changes nothing cannot pass as a proof (WQ-443 Phase 4)"
# verify-guard-proofs.ps1 breaks what a step guards and requires that step to go red. Its two
# judgements - "can this spec be applied" and "did the run prove what it claimed" - are the places
# where a runner would quietly report success having observed nothing, so they live in verify-lib.ps1
# and are planted against here, in-process.
#
# The step deliberately does NOT invoke the runner: the runner runs this suite, and step 70 was killed
# after recursing twelve levels deep for 25 minutes because it shelled out to a script that does that.
# The last arm below is the standing guard against anyone reintroducing such a call.
$mutProbe = Join-Path $PackRoot ".tmp/mutspec-probe-$PID"
try {
    New-Item -ItemType Directory -Path $mutProbe -Force | Out-Null
    Write-Utf8NoBom (Join-Path $mutProbe 'target.txt') "alpha`nbeta`nalpha`n"
    Write-Utf8NoBom (Join-Path $mutProbe 'once.txt') "unique-marker`nfiller`n"

    $mk = { param($f, $find, $rep) [pscustomobject]@{ file = $f; find = $find; replace = $rep } }
    # create and delete invert the applicability question in opposite directions: one needs its
    # target absent and the other needs it present, and neither carries a find. Planted both ways
    # round, because a create spec validated by the replace rules would demand a find that has
    # nothing to search and be rejected for a reason that is not true of it.
    $mkNew = { param($f, $content) [pscustomobject]@{ file = $f; action = 'create'; content = $content } }
    $mkGone = { param($f) [pscustomobject]@{ file = $f; action = 'delete' } }
    $specCases = @(
        @{ label = 'a spec that applies cleanly';          spec = (& $mk 'once.txt' 'unique-marker' 'broken'); wantProblem = $false },
        @{ label = 'find absent from the file';            spec = (& $mk 'once.txt' 'not-in-there' 'x');       wantProblem = $true },
        @{ label = 'find matching twice';                  spec = (& $mk 'target.txt' 'alpha' 'x');            wantProblem = $true },
        @{ label = 'find and replace identical';           spec = (& $mk 'once.txt' 'unique-marker' 'unique-marker'); wantProblem = $true },
        @{ label = 'no file named';                        spec = (& $mk '' 'unique-marker' 'x');              wantProblem = $true },
        @{ label = 'a file that does not exist';           spec = (& $mk 'ghost.txt' 'unique-marker' 'x');     wantProblem = $true },
        @{ label = 'an empty find';                        spec = (& $mk 'once.txt' '' 'x');                   wantProblem = $true },
        @{ label = 'a missing spec';                       spec = $null;                                       wantProblem = $true },
        @{ label = 'a create spec for an absent file';     spec = (& $mkNew 'orphan.txt' 'planted');           wantProblem = $false },
        @{ label = 'a create spec whose file is there';    spec = (& $mkNew 'once.txt' 'planted');             wantProblem = $true },
        @{ label = 'a create spec with no content';        spec = (& $mkNew 'orphan.txt' '');                  wantProblem = $true },
        @{ label = 'a delete spec for a file that is there'; spec = (& $mkGone 'once.txt');                    wantProblem = $false },
        @{ label = 'a delete spec for a file already gone'; spec = (& $mkGone 'ghost.txt');                    wantProblem = $true },
        @{ label = 'an action the runner cannot apply';    spec = ([pscustomobject]@{ file = 'once.txt'; action = 'rename' }); wantProblem = $true }
    )
    $specWrong = @()
    foreach ($c in $specCases) {
        $got = @(Get-PackMutationSpecProblem -Spec $c.spec -Root $mutProbe)
        $hasProblem = ($got.Count -gt 0)
        if ($hasProblem -ne $c.wantProblem) {
            $specWrong += "$($c.label): problems=$($got.Count), expected $(if ($c.wantProblem) { 'a problem' } else { 'none' })"
        }
    }
    if ($specWrong.Count -gt 0) {
        Fail ('mutation spec validation is wrong - ' + ($specWrong -join '; '))
    } else {
        Ok "mutation spec validation correct on $($specCases.Count) controls (3 applicable, 11 rejected)"
    }

    # Which steps were asked for. This arm exists because the runner proved step 47 when it was asked
    # for steps 4 and 7: under -File the pair arrives as the string '4,7', and casting that to int[]
    # yields 47 rather than failing, because .NET reads the comma as a digit-group separator. The run
    # exited 0 and reported a proof for a step nobody named - success claimed for unrequested work,
    # in the runner built to catch exactly that.
    $askCases = @(
        @{ label = 'one step';                    tokens = @('7');        want = @(7);     bad = 0 },
        @{ label = 'a comma pair in one token';   tokens = @('4,7');      want = @(4, 7);  bad = 0 },
        @{ label = 'separate tokens';             tokens = @('4', '7');   want = @(4, 7);  bad = 0 },
        @{ label = 'spaces around the comma';     tokens = @('15, 18');   want = @(15, 18); bad = 0 },
        @{ label = 'a trailing comma';            tokens = @('23,');      want = @(23);    bad = 0 },
        @{ label = 'nothing asked for';           tokens = @();           want = @();      bad = 0 },
        @{ label = 'a word where a number goes';  tokens = @('4,seven');  want = @(4);     bad = 1 }
    )
    $askWrong = @()
    foreach ($c in $askCases) {
        $got = Get-PackRequestedStepNumber -Tokens $c.tokens
        if ((@($got.Numbers) -join ',') -ne (@($c.want) -join ',')) {
            $askWrong += "$($c.label): got [$(@($got.Numbers) -join ',')], want [$(@($c.want) -join ',')]"
        } elseif (@($got.Unreadable).Count -ne $c.bad) {
            $askWrong += "$($c.label): $(@($got.Unreadable).Count) unreadable, expected $($c.bad)"
        }
    }
    if ($askWrong.Count -gt 0) {
        Fail ('the runner would prove steps other than the ones asked for - ' + ($askWrong -join '; '))
    } else {
        Ok "step selection correct on $($askCases.Count) controls, including the pair that once resolved to one step"
    }

    # Outcome judgement. The case that matters most is a green suite: if a mutation is applied and
    # nothing fails, the step under test is not reading what it claims to, and calling that a proof is
    # the whole defect WQ-443 names.
    $res = { param($count, $steps) [pscustomobject]@{ failCount = $count; failures = @($steps | ForEach-Object { [pscustomobject]@{ step = $_; message = 'x' } }) } }
    $outcomeCases = @(
        @{ label = 'the expected step failed';                results = (& $res 1 @(72));     expect = @(72); wantProblem = $false },
        @{ label = 'expected step failed among others';       results = (& $res 3 @(72, 5, 9)); expect = @(72); wantProblem = $false },
        @{ label = 'the suite stayed green';                  results = (& $res 0 @());       expect = @(72); wantProblem = $true },
        @{ label = 'a different step failed instead';         results = (& $res 1 @(5));      expect = @(72); wantProblem = $true },
        @{ label = 'only one of two expected steps failed';   results = (& $res 1 @(72));     expect = @(72, 73); wantProblem = $true },
        @{ label = 'no results file at all';                  results = $null;                expect = @(72); wantProblem = $true },
        @{ label = 'nothing was expected to fail';            results = (& $res 1 @(72));     expect = @();   wantProblem = $true },
        @{ label = 'a failure that attributed to no step';    results = (& $res 1 @($null));  expect = @(72); wantProblem = $true }
    )
    $outcomeWrong = @()
    foreach ($c in $outcomeCases) {
        $got = @(Test-PackMutationOutcome -Results $c.results -ExpectFailIn $c.expect)
        $hasProblem = ($got.Count -gt 0)
        if ($hasProblem -ne $c.wantProblem) {
            $outcomeWrong += "$($c.label): problems=$($got.Count), expected $(if ($c.wantProblem) { 'a problem' } else { 'none' })"
        }
    }
    if ($outcomeWrong.Count -gt 0) {
        Fail ('mutation outcome judgement is wrong - ' + ($outcomeWrong -join '; '))
    } else {
        Ok "mutation outcome judgement correct on $($outcomeCases.Count) controls (2 proven, 6 rejected)"
    }

    # Re-attribution: the arm that exists because the runner's first real execution reported step 72 as
    # not proven. Step 72's mutation disables the resolver, so the suite failed as designed and every
    # record came back with no step. Recovering the step from the recorded line - with the runner's own
    # unmutated parser - is what keeps the measurement outside the mutation's blast radius.
    # The `n here must be the two literal characters an announcement contains in source, written as
    # '`n' - not "`n", which is a real newline and splits the announcement across two lines where it
    # matches nothing. That mistake was made here and caught by the arm below; it is the same inert
    # fixture that cost step 71 two runs, so the fixture now declares what it must parse to.
    $reSuite = ('Write-Host "' + '`n' + '5. five"') + "`n`n`n`n`n" + ('Write-Host "' + '`n' + '9. nine"')
    $reAnnounced = @(Get-PackBehaviorStepAnnouncement -SuiteText $reSuite)
    if ($reAnnounced.Count -ne 2) {
        Fail "re-attribution fixture parses to $($reAnnounced.Count) announcement(s), expected 2 - the controls below would prove nothing"
    }
    $reCases = @(
        @{ label = 'a record with no step recovers from its line'
           results = [pscustomobject]@{ failCount = 1; failures = @([pscustomobject]@{ step = $null; line = 7; message = 'x' }) }
           wantSteps = @(9) },
        @{ label = 'an already-attributed record is left alone'
           results = [pscustomobject]@{ failCount = 1; failures = @([pscustomobject]@{ step = 5; line = 7; message = 'x' }) }
           wantSteps = @(5) },
        @{ label = 'a record with neither step nor usable line stays unattributed'
           results = [pscustomobject]@{ failCount = 1; failures = @([pscustomobject]@{ step = $null; line = 0; message = 'x' }) }
           wantSteps = @($null) },
        @{ label = 'no results at all yields nothing'
           results = $null
           wantSteps = @() }
    )
    $reWrong = @()
    foreach ($c in $reCases) {
        $got = @(Resolve-PackMutationFailureStep -Results $c.results -SuiteText $reSuite)
        $gotSteps = @($got | ForEach-Object { $_.step })
        if (($gotSteps -join ',') -ne (@($c.wantSteps) -join ',')) {
            $reWrong += "$($c.label): got [$($gotSteps -join ',')], want [$(@($c.wantSteps) -join ',')]"
        }
    }
    if ($reWrong.Count -gt 0) {
        Fail ('re-attribution from a recorded line is wrong - ' + ($reWrong -join '; '))
    } else {
        Ok "re-attribution correct on $($reCases.Count) controls, so a mutation cannot hide which step it broke"
    }

    # The runner is only useful if it asks these questions, and only safe if this suite never calls it.
    $runnerPath = Join-Path $PackRoot 'pack\scripts\verify-guard-proofs.ps1'
    if (-not (Test-Path -LiteralPath $runnerPath)) {
        Fail 'pack\scripts\verify-guard-proofs.ps1 is missing - the registry declares mutations nothing can execute'
    } else {
        $runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
        $missingUse = @()
        foreach ($fn in 'Get-PackMutationSpecProblem', 'Test-PackMutationOutcome', 'Resolve-PackMutationFailureStep',
                        'Get-PackRequestedStepNumber', 'Get-PackMutationAction') {
            if ($runnerText -notmatch [regex]::Escape($fn)) { $missingUse += $fn }
        }
        if ($runnerText -notmatch 'ResultsPath') { $missingUse += '-ResultsPath (it would have no attribution to read)' }
        if ($runnerText -notmatch 'baseline|Baseline') { $missingUse += 'a baseline run (without one, an unrelated failure reads as a proof)' }
        if ($missingUse.Count -gt 0) {
            Fail ("verify-guard-proofs.ps1 does not use: " + ($missingUse -join ', ') + " - the arms proven above would not be the ones it runs")
        } else { Ok 'the runner uses the validated spec and outcome checks, a results file and a baseline' }

        $suiteSelf = Get-Content -LiteralPath $PSCommandPath -Raw -Encoding UTF8
        if ($suiteSelf -match '(?m)^\s*[^#\r\n]*verify-guard-proofs\.ps1[^\r\n]*$' -and
            $suiteSelf -match '(?m)^\s*[^#\r\n]*(&|Invoke-PackScript|pwsh|powershell)[^\r\n]*verify-guard-proofs\.ps1') {
            Fail 'a step invokes verify-guard-proofs.ps1, which runs this suite - that recursion killed step 70 once already'
        } else { Ok 'no step invokes the runner - the suite cannot recurse through it' }
    }
} catch {
    Fail "mutation proof checks error: $_"
} finally {
    if (Test-Path -LiteralPath $mutProbe) { Remove-Item -LiteralPath $mutProbe -Recurse -Force -ErrorAction SilentlyContinue }
}

# 74. A parent that reports "the child failed" must say what the child said
# WQ-463: two bootstrap checks in step 23 failed intermittently with `verify-audit-system.ps1 failed
# against the starter pack itself` and nothing else. The child's output went to the host, which the
# harness swallows, so four full audit runs produced no reason - and two plausible causes were
# investigated and disproven purely because the evidence had been thrown away. The detail is built by
# a function so it can be exercised here instead of inferred from reading run_audit_core.ps1.
Write-Host "`n74. A failing child's reason survives into the Fix line (WQ-463)"
try {
    $childOk = "[OK] all good`n"
    $childBad = "Running checks`n[FAIL] first thing broke`nnoise`n[WARN] second thing`n"
    $childMute = "something happened`nno markers here`n"

    $dOk = Get-PackChildFailureDetail -Output $childBad -ExitCode 0
    if ($dOk -ne '') { Fail "a child that exited 0 must produce no detail, got: $dOk" }
    else { Ok 'a successful child adds nothing to the report' }

    $dBad = Get-PackChildFailureDetail -Output $childBad -ExitCode 1
    if ($dBad -notmatch 'first thing broke') { Fail "detail dropped the child's first [FAIL] line: $dBad" }
    elseif ($dBad -notmatch 'second thing') { Fail "detail dropped the child's [WARN] line: $dBad" }
    elseif ($dBad -match 'noise') { Fail "detail quoted an unmarked line: $dBad" }
    else { Ok 'detail quotes the marked lines and nothing else' }

    # The case that made WQ-463 expensive: a non-zero exit with nothing printed. Reporting an empty
    # detail there would read as "the child had nothing to say" rather than "it would not say".
    $dMute = Get-PackChildFailureDetail -Output $childMute -ExitCode 3
    if ($dMute -notmatch 'no \[FAIL\] line') { Fail "a silent failing child must be named as such: $dMute" }
    elseif ($dMute -notmatch 'exit code was 3') { Fail "a silent failing child must report its exit code: $dMute" }
    else { Ok 'a silent failing child is reported as silent, with its exit code' }

    $manyLines = (1..9 | ForEach-Object { "[FAIL] problem $_" }) -join "`n"
    $dMany = Get-PackChildFailureDetail -Output $manyLines -ExitCode 1 -MaxLines 4
    if ($dMany -match 'problem 5') { Fail "detail exceeded MaxLines: $dMany" }
    elseif ($dMany -notmatch '\+5 more') { Fail "truncation must be stated, got: $dMany" }
    else { Ok 'quoting is capped and the truncation is stated' }

    if ($dOk -ne (Get-PackChildFailureDetail -Output $childOk -ExitCode 0)) {
        Fail 'detail for a successful child depends on its output, which it must not'
    } else { Ok 'success is judged by exit code, not by scanning for markers' }

    # The helper existing proves nothing if the audit still builds its own message inline.
    $coreText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run_audit_core.ps1') -Raw -Encoding UTF8
    if ($coreText -notmatch 'Get-PackChildFailureDetail') {
        Fail 'run_audit_core.ps1 does not use Get-PackChildFailureDetail - the Fix line would drop the reason again'
    } else { Ok 'run_audit_core.ps1 reports the child reason through the tested helper' }
} catch {
    Fail "child failure detail checks error: $_"
}

# 75. A backup copy of the pack is not a thing to audit
# WQ-463's cause. Pack discovery has to be broad - it finds a pack from inside an unrelated project by
# looking in the profile, the Desktop and the OneDrive Desktop. verify-audit-system.ps1 reused that
# list and validated every copy it found, so a backup of the pack on a OneDrive Desktop was audited
# alongside the checkout. It failed, the failure surfaced during a bootstrap check as "verify-audit-
# system.ps1 failed against the starter pack itself", and nothing in the project being audited or the
# checkout being edited could fix a folder the user keeps as a backup. OneDrive hydrating and
# re-syncing that folder is what made it come and go.
Write-Host "`n75. Verification covers the pack under test and this machine's install, not backups (WQ-463)"
try {
    $src = 'D:\Work\AgentStarterPack'
    $inst = 'C:\Users\alice\.cursor\AgentStarterPack'
    $backup = 'C:\Users\alice\OneDrive - Corp\Desktop\AgentStarterPack'
    $stick = 'E:\AgentStarterPack'

    $scoped = @(Get-PackVerifyRoot -Candidate @($src, $inst, $backup, $stick) -SourceRoot $src -InstalledRoot $inst)
    if ($scoped.Count -ne 2) { Fail "expected the source and the install, got $($scoped.Count): $($scoped -join ', ')" }
    elseif ($scoped -contains $backup) { Fail 'a Desktop/OneDrive backup was accepted for verification' }
    elseif ($scoped -contains $stick) { Fail 'a removable-disk copy was accepted for verification' }
    else { Ok 'a backup and a removable-disk copy are both excluded' }

    # Case and trailing separators differ between discovery sources, and a missed match here would
    # drop the real pack rather than a backup - a silent no-op verify, which reads as success.
    $sloppy = @(Get-PackVerifyRoot -Candidate @("$src\", $src.ToUpperInvariant(), ($inst -replace '\\', '/')) `
            -SourceRoot $src -InstalledRoot $inst)
    if ($sloppy.Count -ne 2) { Fail "path spelling changed the answer, got: $($sloppy -join ', ')" }
    else { Ok 'case, trailing separators and slash direction do not change the answer' }

    if (@(Get-PackVerifyRoot -Candidate @($backup) -SourceRoot $src -InstalledRoot $inst).Count -ne 0) {
        Fail 'a run that finds only a backup must verify nothing rather than verify the backup'
    } else { Ok 'finding only a backup yields nothing to verify' }

    # An uninstalled machine still has a pack under test; dropping it would verify nothing at all.
    $noInstall = @(Get-PackVerifyRoot -Candidate @($src, $backup) -SourceRoot $src -InstalledRoot '')
    if ($noInstall.Count -ne 1 -or $noInstall[0] -ne $src) {
        Fail "with no install, the source pack must still be verified, got: $($noInstall -join ', ')"
    } else { Ok 'with no install, the source pack is still verified' }

    $vasText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'verify-audit-system.ps1') -Raw -Encoding UTF8
    if ($vasText -notmatch 'Get-PackVerifyRoot') {
        Fail 'verify-audit-system.ps1 does not scope its roots - it would audit every copy on the disk again'
    } elseif ($vasText -notmatch 'not verified') {
        Fail 'verify-audit-system.ps1 drops other copies silently - say which copies were skipped and why'
    } else { Ok 'verify-audit-system.ps1 scopes its roots and names the copies it skipped' }
} catch {
    Fail "pack verify scope checks error: $_"
}

# 76. Derived version cites are synced before anything checks them (WQ-463)
# The actual cause of WQ-463, found only once the child's reason survived into the Fix line (step 74).
# Bumping the engine leaves pack/docs/AUDIT_SYSTEM.md carrying the old version, and
# verify-audit-system.ps1 fails on the mismatch. Inside a full audit that surfaced two layers away, in
# a generated project's bootstrap check, as "verify-audit-system.ps1 failed against the starter pack
# itself" - and then disappeared, because the audit's own later sync repaired the header before the
# next run. Hence "the first audit after a bump fails and the second passes". The sync now runs in the
# test entry point, which owns derived files, and the order is what this step guards: a sync that
# happens after the check repairs the symptom for next time and proves nothing about this run.
Write-Host "`n76. Derived version cites are synced before they are checked (WQ-463)"
try {
    $testsPs1 = Join-Path $PackRoot 'scripts/run_audit_tests.ps1'
    if (-not (Test-Path -LiteralPath $testsPs1)) { Fail 'scripts/run_audit_tests.ps1 missing - the pack test entry point' }
    else {
        $tText = Get-Content -LiteralPath $testsPs1 -Raw -Encoding UTF8
        $iSync = $tText.IndexOf('-ScriptPath $docSync')
        $iVerify = $tText.IndexOf("verify-audit-system.ps1'")
        if ($iSync -lt 0) {
            Fail 'run_audit_tests.ps1 does not invoke sync-doc-versions - a version bump would fail the next audit in a generated project two layers away'
        } elseif ($iVerify -lt 0) {
            Fail 'run_audit_tests.ps1 no longer invokes verify-audit-system.ps1 - the ordering this step guards has no second half'
        } elseif ($iSync -gt $iVerify) {
            Fail 'sync-doc-versions runs after verify-audit-system - a sync that follows the check repairs the next run and proves nothing about this one'
        } else { Ok 'the test entry point syncs derived cites before it verifies them' }

        # The sync must be the build/test step's job, not the audit's: an audit that rewrites the files
        # it is judging cannot report on them. Asserted so the fix does not get "helpfully" moved.
        $coreText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run_audit_core.ps1') -Raw -Encoding UTF8
        if ($coreText -match 'Invoke-PackScript[^\r\n]*sync-doc-versions') {
            Fail 'run_audit_core.ps1 invokes sync-doc-versions - the audit would rewrite the version cites it is supposed to judge'
        } else { Ok 'the audit judges version cites rather than rewriting them' }
    }
} catch {
    Fail "version cite ordering checks error: $_"
}

# 77. The markdown section slicer has one home (WQ-444)
# Five scripts each carried a byte-identical private copy, which is how one defect cost five patches in
# 2.22.73: the start-header search was unanchored, so it matched a heading quoted inside a table cell,
# began the Done section in the middle of the Active table, and reported every Active id as both active
# and done. The behaviour is asserted here as well as the single home, because "one copy" of the wrong
# thing is not an improvement.
Write-Host "`n77. The markdown section slicer has one home (WQ-444)"
try {
    # Both headers are quoted in a table cell before their real heading, because start and end are
    # matched by separate code: a fixture that only quotes the end header leaves the start anchor
    # untested, and the first version of this step passed with that anchor deliberately removed.
    $secDoc = @(
        '## How to read this queue',
        '',
        '| Term | Meaning |',
        '|------|---------|',
        '| `## Active queue` | PREAMBLE-MARKER, the rows being worked |',
        '',
        '## Active queue',
        '',
        '| ID | Task |',
        '|----|------|',
        '| WQ-001 | Move a row to the `## Done log` when it ships |',
        '| WQ-002 | Second row |',
        '',
        '## Done log',
        '',
        '| WQ-000 | Shipped |',
        '',
        '---',
        '',
        '## Cross-references'
    ) -join "`n"

    # The defect itself: `## Done log` appears inside an Active table cell before the real heading.
    $active = Get-PackSectionBody -Content $secDoc -StartHeader '## Active queue' -EndHeader @('## Done log')
    if ($active -match 'PREAMBLE-MARKER') {
        Fail 'the section started at a heading quoted in a table cell - the start-header match is not anchored to a line'
    } elseif ($active -notmatch 'WQ-002') {
        Fail 'the Active section was cut short - an end match found the heading quoted in a table cell'
    } elseif ($active -match 'WQ-000') {
        Fail 'the Active section ran into the Done log - the end header did not anchor'
    } else { Ok 'a heading quoted inside a table cell neither starts nor ends a section' }

    $done = Get-PackSectionBody -Content $secDoc -StartHeader '## Done log' -EndHeader @('---', '## Cross-references')
    if ($done -notmatch 'WQ-000') { Fail "the Done section lost its own row: $done" }
    elseif ($done -match 'Cross-references') { Fail 'the horizontal-rule terminator was ignored' }
    else { Ok "'---' terminates at a horizontal rule, not at a heading" }

    if ((Get-PackSectionBody -Content $secDoc -StartHeader '## Parked' -EndHeader @('---')) -ne '') {
        Fail 'a missing heading must yield empty, not the whole document'
    } elseif ((Get-PackSectionBody -Content '' -StartHeader '## Active queue' -EndHeader @('---')) -ne '') {
        Fail 'an empty document must yield empty'
    } else { Ok 'a missing heading and an empty document both yield empty' }

    $rivals = @()
    foreach ($f in (Get-ChildItem (Join-Path $PackRoot 'pack/scripts') -Filter '*.ps1' -File)) {
        if ($f.Name -eq 'verify-lib.ps1') { continue }
        $body = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        if ($body -match '(?m)^\s*function\s+Get-(Pack)?SectionBody\b') { $rivals += $f.Name }
    }
    if ($rivals.Count -gt 0) {
        Fail ("a private section slicer is back, and the next fix to it will miss these: " + ($rivals -join ', '))
    } else { Ok 'no pack script defines its own section slicer' }
} catch {
    Fail "section slicer checks error: $_"
}

# 78. A generated project's runners stay thin (WQ-447)
# Step 22 proves the *pack's* pair delegates to one implementation. Nothing proved the same of the
# pair a generated project receives, and that is where the drift costs most: a project whose .bat grew
# a step its .sh lacks runs a different suite per platform, and only one of those suites is what the
# audit's test-pass proof actually observed. Asserted on generated output rather than on the templates,
# because reading a template is evidence about the template.
Write-Host "`n78. A generated project's runners delegate to one implementation (WQ-447)"
$thinRoot = Join-Path $PackRoot ".tmp/runner-thin-$PID"
$prevThinInstall = $env:AGENT_STARTER_PACK_INSTALL_ROOT
try {
    if (Test-Path -LiteralPath $thinRoot) { Remove-Item -LiteralPath $thinRoot -Recurse -Force -ErrorAction SilentlyContinue }
    # Same guard step 23 uses: nothing here may reach the real profile.
    $env:AGENT_STARTER_PACK_INSTALL_ROOT = Join-Path $thinRoot 'no-install/AgentStarterPack'
    $thinProj = Join-Path $thinRoot 'ThinApp'
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath (Join-Path $PackRoot 'pack/scripts/bootstrap-project.ps1') `
        -ProjectRoot $thinProj -ProjectName 'ThinApp' -Stack Generic -Targets All -NoPause *> $null
    $thinExit = $LASTEXITCODE

    if ($thinExit -ne 0) { Fail "bootstrap exited $thinExit - cannot judge runners that were never generated" }
    else {
        # Which scripts a runner hands off to. Comments are dropped: a wrapper that only *mentions* a
        # second step in prose has not grown one, and a wrapper that stops mentioning the
        # implementation in prose has not stopped delegating.
        function Get-ThinRunnerTargets([string]$Text) {
            $code = @($Text -split "`r?`n" | Where-Object { $_.TrimStart() -notmatch '^(REM |::|#)' })
            $names = @()
            foreach ($m in [regex]::Matches(($code -join "`n"), '[A-Za-z0-9_.-]+\.(ps1|py|bat|cmd|sh)')) {
                $n = $m.Value.ToLowerInvariant()
                if ($names -notcontains $n) { $names += $n }
            }
            return @($names | Sort-Object)
        }

        foreach ($pair in @(
                @{ Kind = 'tests'; Win = 'run_tests.bat'; Posix = 'run_tests.sh'; Impl = 'scripts/run_tests.ps1' },
                @{ Kind = 'audit'; Win = 'run_audit.cmd'; Posix = 'run_audit.sh'; Impl = 'scripts/run_audit.ps1' })) {
            $winP = Join-Path $thinProj $pair.Win
            $posixP = Join-Path $thinProj $pair.Posix
            $implP = Join-Path $thinProj $pair.Impl
            $missing = @()
            foreach ($t in @(@{ p = $winP; n = $pair.Win }, @{ p = $posixP; n = $pair.Posix }, @{ p = $implP; n = $pair.Impl })) {
                if (-not (Test-Path -LiteralPath $t.p)) { $missing += $t.n }
            }
            if ($missing.Count -gt 0) {
                Fail "generated $($pair.Kind) runner incomplete - missing: $($missing -join ', ')"
                continue
            }
            $implLeaf = (Split-Path $pair.Impl -Leaf).ToLowerInvariant()
            $winTargets = Get-ThinRunnerTargets (Get-Content -LiteralPath $winP -Raw -Encoding UTF8)
            $posixTargets = Get-ThinRunnerTargets (Get-Content -LiteralPath $posixP -Raw -Encoding UTF8)

            if ($winTargets -notcontains $implLeaf) {
                Fail "generated $($pair.Win) does not delegate to $($pair.Impl)"
            } elseif ($posixTargets -notcontains $implLeaf) {
                Fail "generated $($pair.Posix) does not delegate to $($pair.Impl)"
            } elseif (($winTargets -join ',') -ne ($posixTargets -join ',')) {
                # The WQ-447 failure exactly: the two entry points would run different work, and the
                # audit's test-pass proof would cover only whichever platform ran it.
                $onlyWin = @($winTargets | Where-Object { $posixTargets -notcontains $_ })
                $onlyPosix = @($posixTargets | Where-Object { $winTargets -notcontains $_ })
                Fail ("generated $($pair.Kind) runners would run different work - only in $($pair.Win): " +
                    "[$($onlyWin -join ', ')]; only in $($pair.Posix): [$($onlyPosix -join ', ')]")
            } elseif ($winTargets.Count -ne 1) {
                Fail "generated $($pair.Win) invokes more than the implementation: $($winTargets -join ', ')"
            } else { Ok "generated $($pair.Kind) pair delegates to $($pair.Impl) and nothing else" }
        }

        # The implementation must still do the work, or "both wrappers agree" is agreement on nothing.
        $tImpl = Join-Path $thinProj 'scripts/run_tests.ps1'
        if ((Test-Path -LiteralPath $tImpl) -and (Get-Content -LiteralPath $tImpl -Raw -Encoding UTF8).Trim().Length -lt 40) {
            Fail 'the generated test implementation is empty - two wrappers agreeing on nothing is not delegation'
        } else { Ok 'the generated implementation carries the work the wrappers delegate' }
    }
} catch {
    Fail "generated runner checks error: $_"
} finally {
    if ($null -eq $prevThinInstall) { Remove-Item Env:AGENT_STARTER_PACK_INSTALL_ROOT -ErrorAction SilentlyContinue }
    else { $env:AGENT_STARTER_PACK_INSTALL_ROOT = $prevThinInstall }
    if (Test-Path -LiteralPath $thinRoot) { Remove-Item -LiteralPath $thinRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

# 79. An AGENTS.md written for a Linux reader passes its own audit (WQ-452)
# Section L required the literal strings run_audit.cmd and run_tests.bat, so a project whose AGENTS.md
# correctly tells a Linux reader to run ./run_audit.sh failed its own audit for being correct. The
# requirement is that AGENTS.md names the audit and test entry points - not that it names the Windows
# ones. Entries are now any-of; a config may still pin exact strings.
Write-Host "`n79. AGENTS.md may name the entry points this OS actually uses (WQ-452)"
$phraseRoot = Join-Path $PackRoot ".tmp/agents-phrases-$PID"
try {
    if (Test-Path -LiteralPath $phraseRoot) { Remove-Item -LiteralPath $phraseRoot -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $phraseRoot -Force | Out-Null
    $probe = Join-Path $phraseRoot 'probe.py'
    $checks = (Join-Path $PackRoot 'pack/scripts/audit_code_checks.py') -replace '\\', '/'
    $posixRootLit = ($phraseRoot -replace '\\', '/')
    @(
        'import importlib.util, json, pathlib, sys',
        "spec = importlib.util.spec_from_file_location('acc', r'$checks')",
        'acc = importlib.util.module_from_spec(spec)',
        'spec.loader.exec_module(acc)',
        "root = pathlib.Path(r'$posixRootLit')",
        'cfg = {"codeChecks": {"sectionMachineChecks": {"L": {"enabled": True}}}}',
        'out = {}',
        '# Linux-facing: names only the .sh entry points.',
        '(root / "AGENTS.md").write_text("Run ./run_audit.sh then ./run_tests.sh\\n", encoding="utf-8")',
        'out["posix"] = [f for f in acc.verify_section_l_wiring(root, cfg) if "required phrase" in f]',
        '# Windows-facing: names only the Windows entry points.',
        '(root / "AGENTS.md").write_text("Run run_audit.cmd then run_tests.bat\\n", encoding="utf-8")',
        'out["windows"] = [f for f in acc.verify_section_l_wiring(root, cfg) if "required phrase" in f]',
        '# Names neither: must still be caught, or the check has stopped checking.',
        '(root / "AGENTS.md").write_text("Read the docs and hope\\n", encoding="utf-8")',
        'out["neither"] = [f for f in acc.verify_section_l_wiring(root, cfg) if "required phrase" in f]',
        '# A config that pins exact strings keeps doing so - projects depend on that.',
        'pinned = {"codeChecks": {"sectionMachineChecks": {"L": {"enabled": True, "agentsMdRequiredPhrases": ["run_audit.cmd"]}}}}',
        '(root / "AGENTS.md").write_text("Run ./run_audit.sh then ./run_tests.sh\\n", encoding="utf-8")',
        'out["pinned"] = [f for f in acc.verify_section_l_wiring(root, pinned) if "required phrase" in f]',
        'print(json.dumps(out))'
    ) -join "`n" | ForEach-Object { Write-Utf8NoBom -Path $probe -Text $_ }

    $raw = (Invoke-PackPython $probe 2>&1 | Out-String)
    $jsonLine = @($raw -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -Last 1)
    if (-not $jsonLine) { Fail "Section L probe produced no result: $($raw.Trim())" }
    else {
        $r = $jsonLine[0] | ConvertFrom-Json
        if (@($r.posix).Count -gt 0) {
            Fail "an AGENTS.md naming ./run_audit.sh and ./run_tests.sh fails Section L: $(@($r.posix) -join '; ')"
        } else { Ok 'an AGENTS.md written for a Linux reader passes' }

        if (@($r.windows).Count -gt 0) {
            Fail "an AGENTS.md naming the Windows entry points fails Section L: $(@($r.windows) -join '; ')"
        } else { Ok 'an AGENTS.md written for a Windows reader still passes' }

        # Permissiveness is only correct while the check still catches the real gap.
        if (@($r.neither).Count -lt 2) {
            Fail "an AGENTS.md naming no entry point at all was not caught: $(@($r.neither).Count) of 2 reported"
        } else { Ok 'an AGENTS.md naming no entry point at all is still caught' }

        if (@($r.pinned).Count -ne 1) {
            Fail "a config pinning an exact phrase no longer pins it: $(@($r.pinned).Count) reported, expected 1"
        } else { Ok 'a config that pins exact strings still pins them' }
    }
} catch {
    Fail "Section L phrase checks error: $_"
} finally {
    if (Test-Path -LiteralPath $phraseRoot) { Remove-Item -LiteralPath $phraseRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

# 80. The shipped POSIX surface avoids what macOS does not have (WQ-455)
# macOS is not "Linux, near enough" - WQ-436 found 16 real failures against an estimate of 24 different
# ones. Two families of that cost are decidable by reading the script: GNU coreutils macOS does not
# ship, and bash 4 syntax macOS will never have (it is pinned at 3.2). Checked here because the
# alternative is a macOS runner and this pack's maintainer has no Mac. It does not replace one - a
# case-insensitive filesystem is not visible in the text - it removes the part that is.
Write-Host "`n80. The shipped POSIX surface avoids what macOS does not have (WQ-455)"
try {
    $portableSample = @(
        '#!/usr/bin/env bash',
        'set -euo pipefail',
        '# sha256sum and declare -A are named here in a comment and must not be reported.',
        'shasum -a 256 "$f" | cut -d" " -f1',
        'sed -i "" "s/a/b/" "$f"',
        'find . -name "*.sh" -print'
    ) -join "`n"
    $portableHits = @(Get-PackPosixPortabilityHit -Text $portableSample)
    if ($portableHits.Count -ne 0) {
        Fail "portable script reported as unportable, which would make the check unusable: $($portableHits -join '; ')"
    } else { Ok 'portable equivalents pass, and a construct named in a comment is not a call' }

    # Every rule gets a positive case: a detector nobody has seen fire is a detector nobody has tested.
    $mustCatch = @(
        @{ Line = 'sha256sum "$f"'; What = 'sha256sum' },
        @{ Line = 'timeout 30 pwsh -File x.ps1'; What = 'timeout' },
        @{ Line = 'stat -c "%a" "$f"'; What = 'stat -c' },
        @{ Line = 'grep -P "\d+" "$f"'; What = 'grep -P' },
        @{ Line = 'sed -i "s/a/b/" "$f"'; What = 'sed -i with no backup arg' },
        @{ Line = 'mapfile -t lines < "$f"'; What = 'mapfile' },
        @{ Line = 'declare -A seen'; What = 'declare -A' },
        @{ Line = 'echo "${name^^}"'; What = 'case-modifying expansion' }
    )
    $missed = @()
    foreach ($c in $mustCatch) {
        if (@(Get-PackPosixPortabilityHit -Text $c.Line).Count -eq 0) { $missed += $c.What }
    }
    if ($missed.Count -gt 0) { Fail "these macOS-hostile constructs are not detected: $($missed -join ', ')" }
    else { Ok "all $($mustCatch.Count) macOS-hostile constructs are detected" }

    # The real surface. Scoped to shipped .sh files on purpose: a Linux-only CI job may legitimately
    # call GNU tools, and failing it for that would teach the next maintainer to mute this check.
    $shFiles = @(Get-ChildItem -LiteralPath $PackRoot -Recurse -File -Filter '*.sh' -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-PackPathHasSegment -Path $_.FullName.Substring($PackRoot.Length).TrimStart('\', '/') -Segment @('.tmp', '.git')) })
    if ($shFiles.Count -lt 10) { Fail "only $($shFiles.Count) .sh files found - the scan is not seeing the POSIX surface" }
    else {
        $unportable = @()
        foreach ($f in $shFiles) {
            $rel = Get-PackRelPathKey -Path $f.FullName -Root $PackRoot
            foreach ($h in (Get-PackPosixPortabilityHit -Text (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8))) {
                $unportable += "${rel}: $h"
            }
        }
        if ($unportable.Count -gt 0) { Fail "macOS-hostile constructs in shipped shell scripts: $($unportable -join ' | ')" }
        else { Ok "all $($shFiles.Count) shipped .sh files avoid GNU-only and bash-4-only constructs" }
    }
} catch {
    Fail "POSIX portability checks error: $_"
}

# 81. A cite under docs/, scripts/ or tests/ has an owner, and the pack can still deliver its own (WQ-433)
# Step 47 resolves `pack/`-rooted cites only, and the reason those three roots stayed out is that a
# doc naming `docs/ROADMAP.md` is usually describing the reader's project - this pack has no roadmap
# by decision. An indiscriminate scan of them reports 68 findings on a clean tree, all of them correct
# advice about somebody else's tree, which is how the first attempt got muted. So the work here is not
# the scan, it is ownership: undeclared means it must exist here, `delivered` means the pack writes it
# into a project and the check is whether it still can, and `reader` means nobody here can check it
# and the exemption is printed every run rather than being silently absent.
Write-Host "`n81. Cited project paths are owned, and delivered ones are still deliverable (WQ-433)"
try {
    # Extraction first, in memory, because two of these cost a false run to find.
    $sample = @(
        'Read `docs/ROADMAP.md` and then pack/docs/START_HERE.md for the rest.',
        'py -3 scripts\apply_version.py sync',
        '| `docs/AUDIT.md.template` | `docs/AUDIT.md` |',
        'A plan lives at docs/<slug>_PLAN.md and MyApp/docs/notes.md is an example.'
    )
    $hits = @(Get-PackCitedProjectPathReference -Lines $sample)
    $got = @($hits | ForEach-Object { $_.Ref })
    $extractProblems = @()
    foreach ($want in @('docs/ROADMAP.md', 'scripts/apply_version.py', 'docs/AUDIT.md.template', 'docs/AUDIT.md')) {
        if ($got -notcontains $want) { $extractProblems += "did not extract $want" }
    }
    # `pack/`-rooted cites belong to step 47; a placeholder path resolves nowhere and must not be
    # chased; and `docs/AUDIT.md.template` must not arrive truncated to a second `docs/AUDIT.md`.
    if ($got -contains 'docs/START_HERE.md') { $extractProblems += 'a pack/-rooted cite was read as a project-relative one' }
    if (@($got | Where-Object { $_ -match '<|MyApp' }).Count -gt 0) { $extractProblems += 'a placeholder path was extracted as a cite' }
    if (@($got | Where-Object { $_ -eq 'docs/AUDIT.md' }).Count -ne 1) { $extractProblems += 'the .md.template cite truncated to .md as well' }
    if ($extractProblems.Count -gt 0) { Fail "cite extraction: $($extractProblems -join '; ')" }
    else { Ok 'extraction reads backslash cites, keeps .md.template whole, and leaves pack/ cites to step 47' }

    # Judgement, against a synthetic tree so each planted defect is attributable.
    $ownRoot = Join-Path $PackRoot ".tmp/cited-owner-probe-$PID"
    if (Test-Path -LiteralPath $ownRoot) { Remove-Item -LiteralPath $ownRoot -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path (Join-Path $ownRoot 'docs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ownRoot 'pack/templates/docs') -Force | Out-Null
    Write-Utf8NoBom (Join-Path $ownRoot 'docs/HERE.md') 'present in this checkout'
    Write-Utf8NoBom (Join-Path $ownRoot 'pack/templates/docs/REAL.md.template') 'a real deliverer'
    $mkRef = {
        param($ref)
        [pscustomobject]@{ Source = 'probe.mdc'; Line = 1; Ref = $ref }
    }
    $cleanOwnership = [pscustomobject]@{
        'docs/SHIPPED.md'  = [pscustomobject]@{ owner = 'delivered'; deliveredBy = 'pack/templates/docs/REAL.md.template'; why = 'a project receives it' }
        'docs/THEIRS.md'   = [pscustomobject]@{ owner = 'reader'; why = 'the project owns it under whatever name it uses' }
    }
    $cleanRefs = @((& $mkRef 'docs/HERE.md'), (& $mkRef 'docs/SHIPPED.md'), (& $mkRef 'docs/THEIRS.md'))
    $clean = Get-PackCitedProjectPathProblem -Reference $cleanRefs -Ownership $cleanOwnership -PackRoot $ownRoot
    if (@($clean.Problems).Count -ne 0) {
        Fail "a correctly owned set was reported as broken, which is what gets a check muted: $(@($clean.Problems) -join '; ')"
    } elseif (@($clean.Delivered).Count -ne 1 -or @($clean.Unchecked).Count -ne 1) {
        Fail "the clean case must account for what it checked and what it did not: $(@($clean.Delivered).Count) delivered, $(@($clean.Unchecked).Count) unchecked"
    } else { Ok 'a resolving cite, a deliverable one and a declared reader-owned one all pass, and the unchecked one is named' }

    $ownCases = @(
        @{
            What       = 'a cite that is neither here nor declared'
            Refs       = @((& $mkRef 'docs/GONE.md'))
            Ownership  = $cleanOwnership
            Expect     = 'not declared in citedPathOwnership'
        },
        @{
            What      = 'delivered by a template that no longer exists'
            Refs      = @((& $mkRef 'docs/SHIPPED.md'))
            Ownership = [pscustomobject]@{ 'docs/SHIPPED.md' = [pscustomobject]@{ owner = 'delivered'; deliveredBy = 'pack/templates/docs/DELETED.md.template'; why = 'a project receives it' } }
            Expect    = 'cannot produce the file its own advice'
        },
        @{
            What      = 'delivered with no deliverer named'
            Refs      = @((& $mkRef 'docs/SHIPPED.md'))
            Ownership = [pscustomobject]@{ 'docs/SHIPPED.md' = [pscustomobject]@{ owner = 'delivered'; why = 'a project receives it' } }
            Expect    = 'names no deliveredBy'
        },
        @{
            What      = 'an exemption with no reason'
            Refs      = @((& $mkRef 'docs/THEIRS.md'))
            Ownership = [pscustomobject]@{ 'docs/THEIRS.md' = [pscustomobject]@{ owner = 'reader' } }
            Expect    = 'has no why'
        },
        @{
            What      = 'an owner value that means nothing'
            Refs      = @((& $mkRef 'docs/THEIRS.md'))
            Ownership = [pscustomobject]@{ 'docs/THEIRS.md' = [pscustomobject]@{ owner = 'somebody'; why = 'unclear' } }
            Expect    = "has owner 'somebody'"
        },
        @{
            What      = 'a declaration nothing cites any more'
            Refs      = @((& $mkRef 'docs/HERE.md'))
            Ownership = [pscustomobject]@{ 'docs/RETIRED.md' = [pscustomobject]@{ owner = 'reader'; why = 'the project owns it' } }
            Expect    = 'no rule, skill or doc cites any more'
        }
    )
    $ownMissed = @()
    foreach ($c in $ownCases) {
        $res = Get-PackCitedProjectPathProblem -Reference $c.Refs -Ownership $c.Ownership -PackRoot $ownRoot
        if (@($res.Problems | Where-Object { $_ -like "*$($c.Expect)*" }).Count -eq 0) {
            $ownMissed += "$($c.What) -> $(if (@($res.Problems).Count -eq 0) { 'reported nothing' } else { @($res.Problems) -join ' / ' })"
        }
    }
    if ($ownMissed.Count -gt 0) { Fail "ownership defects not reported: $($ownMissed -join ' | ')" }
    else { Ok "all $($ownCases.Count) ownership defects are reported, including a stale exemption" }

    # The real surface.
    $citeFiles = @(Get-PackCitedReferenceFile -PackRoot $PackRoot)
    $liveRefs = @()
    foreach ($f in $citeFiles) {
        foreach ($h in (Get-PackCitedProjectPathReference -Lines (Get-Content -LiteralPath $f.FullName -Encoding UTF8))) {
            $liveRefs += [pscustomobject]@{ Source = $f.Name; Line = $h.Line; Ref = $h.Ref }
        }
    }
    if ($liveRefs.Count -lt 100) {
        Fail "only $($liveRefs.Count) project-relative cites found across $($citeFiles.Count) files - the scan is not seeing the surface it claims to check"
    } else {
        $manifest81 = Get-Content -LiteralPath (Join-Path $PackRoot 'pack/audit/manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $own = $manifest81.citedPathOwnership
        if ($null -eq $own) {
            Fail 'pack/audit/manifest.json has no citedPathOwnership - without it every cite falls to the default and the exemptions are nowhere'
        } else {
            $live = Get-PackCitedProjectPathProblem -Reference $liveRefs -Ownership $own -PackRoot $PackRoot
            if (@($live.Problems).Count -gt 0) {
                Fail "cited project paths: $(@($live.Problems) -join ' | ')"
            } else {
                Ok "$($live.Cited) distinct cites across $($citeFiles.Count) documents resolve, deliver or are declared"
                Write-Host "   deliverable: $(@($live.Delivered).Count) path(s) the pack writes into a project"
                foreach ($u in @($live.Unchecked)) { Write-Host "   [INFO] not checkable here - $u" }
            }
        }
    }
    if (Test-Path -LiteralPath $ownRoot) { Remove-Item -LiteralPath $ownRoot -Recurse -Force -ErrorAction SilentlyContinue }
} catch {
    Fail "cited project path checks error: $_"
}

# 82. A [FAIL] line printed by a run that passed (WQ-472)
# The suite deliberately runs child verifies against broken fixtures and requires them to fail, so
# those children print findings that are not findings. One arm (step 57's absolute-path case) tried to
# discard that output with `2>&1 | Out-Null`, which cannot touch Write-Host, so the finding reached the
# host, the audit quoted it into its Fix line, and a certification run reported a SESSION path that is
# in no file in this checkout. The diagnosis took a full pass to reach "the fixture said it."
#
# The invariant belongs to the parent, since it is the only layer that sees both the exit code and
# everything the child wrote. Suppressing child output would also satisfy it, and is forbidden for a
# reason (WQ-463): a failing child that says nothing is the more expensive defect.
Write-Host "`n82. A passing run must not print a [FAIL] line (WQ-472)"
try {
    $strayNone = Get-PackStrayFailureLine -Output @('[OK] fine', '', '[WARN] careful', '[SKIP] not here') -ExitCode 0
    if (@($strayNone).Count -ne 0) { Fail "a clean passing run reported stray lines: $(@($strayNone) -join ' | ')" }
    else { Ok 'a passing run with only [OK], [WARN] and [SKIP] lines is clean' }

    # The defect itself: exit 0 with a marked failure line in the output.
    $strayLeak = Get-PackStrayFailureLine -Output @('running', '[FAIL] SESSION names an absolute path: E:\Nowhere\x.md', 'done') -ExitCode 0
    if (@($strayLeak).Count -ne 1) { Fail "the leaked [FAIL] line was not reported: $(@($strayLeak) -join ' | ')" }
    elseif (@($strayLeak)[0] -notmatch 'absolute path') { Fail "the report dropped the line's text: $(@($strayLeak) -join ' | ')" }
    else { Ok 'exit 0 with a [FAIL] line in the output is reported, with the line' }

    # A failing run is the normal case for marked lines, and this check must stay out of its way -
    # otherwise every real failure would be reported twice, once as itself and once as a leak.
    $strayReal = Get-PackStrayFailureLine -Output @('[FAIL] a real finding') -ExitCode 1
    if (@($strayReal).Count -ne 0) { Fail 'a failing run had its own [FAIL] lines reported as strays' }
    else { Ok 'a non-zero exit leaves its marked lines alone' }

    # One string rather than an array of lines: verify-audit-system tees a pipeline, but a caller that
    # captured with Out-String must get the same answer, and the blank line is the WQ-433 lesson -
    # a parameter that rejects empty input reports every clean run as silent.
    $strayBlob = Get-PackStrayFailureLine -Output ("first`n`n[FAIL] leaked once`nlast") -ExitCode 0
    if (@($strayBlob).Count -ne 1) { Fail "a single captured string was not scanned line by line: $(@($strayBlob) -join ' | ')" }
    else { Ok 'one captured string and an array of lines give the same answer' }
    if (@(Get-PackStrayFailureLine -Output @() -ExitCode 0).Count -ne 0) { Fail 'an empty capture must report nothing' }
    else { Ok 'an empty capture reports nothing rather than erroring' }

    # The helper proves nothing if the parent never calls it.
    $vasText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'verify-audit-system.ps1') -Raw -Encoding UTF8
    if ($vasText -notmatch 'Get-PackStrayFailureLine') {
        Fail 'verify-audit-system.ps1 does not use Get-PackStrayFailureLine - a leaked fixture line would reach the Fix line again'
    } elseif ($vasText -notmatch 'Tee-Object') {
        Fail 'verify-audit-system.ps1 no longer keeps a copy of the behavior output - there is nothing to check for strays'
    } else { Ok 'verify-audit-system.ps1 keeps the suite output and checks it through the tested helper' }

    # The idiom that caused it, in this suite's own source. An in-process script call is not a native
    # process: Write-Host goes to the information stream, so an error-only redirect neither captures it
    # nor discards it. `*>&1` does both. This is a source shape rather than a behaviour, and it is here
    # because the invariant above only fires once a leak exists, while this fires when one is written.
    $selfLines = Get-Content -LiteralPath $PSCommandPath -Encoding UTF8
    $leakShape = @()
    for ($i = 0; $i -lt $selfLines.Count; $i++) {
        $line = $selfLines[$i]
        if ($line -match '^\s*#') { continue }
        if ($line -notmatch '2>&1\s*\|\s*Out-Null') { continue }
        # Native processes and the wrappers around them redirect fine; only in-process `& $script -Arg`
        # calls have an information stream to lose.
        if ($line -match 'Invoke-Pack|\.Source|\$exe|\$psExe|\$bashExe|git\b|Tee-Object') { continue }
        if ($line -match '&\s*\$\w+\s+-\w') { $leakShape += "line $($i + 1): $($line.Trim())" }
    }
    if ($leakShape.Count -gt 0) {
        Fail ("an in-process script call discards only stderr, so Write-Host findings will print to the host - use `*>&1`: " +
            ($leakShape -join ' | '))
    } else { Ok 'no in-process script call in this suite suppresses with an error-only redirect' }
} catch {
    Fail "stray failure line checks error: $_"
}

# 83. The offload hooks decide, not merely exist (WQ-476)
# The rule these hooks enforce was already written, already loaded, and already ignored - violated
# across four sessions and closed three times by rewording it. What was missing was never the rule;
# it was that nothing ran. So this step runs them: a shipped hook that is present and inert is the
# exact artifact this engine keeps deleting, and the first live version of shell-preapprove.ps1 was
# installed, silent, and approving nothing for four commands straight because Cursor prefixes its
# payload with a UTF-8 BOM and ConvertFrom-Json threw. Every payload below carries that BOM.
#
# The asymmetry in hooks.json.template is asserted, not assumed: the two hooks that *tighten* what the
# agent gets away with ship registered, and the one that *widens* unattended execution ships available
# but off. A future edit that quietly registers the third would change other people's review posture.
Write-Host "`n83. The offload hooks decide, not merely exist (WQ-476)"
try {
    $hookDir = Join-Path $PackRoot 'pack/templates/cursor/hooks'
    $policyPath = Join-Path $PackRoot 'pack/templates/agent-control/policy.json'
    $conformancePath = Join-Path $PackRoot 'pack/templates/agent-control/conformance.json'
    $hookFiles = @('hook-state.ps1', 'offload-detect.ps1', 'completion-gate.ps1', 'shell-preapprove.ps1')
    $missingHooks = @($hookFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $hookDir $_)) })
    if ($missingHooks.Count -gt 0) { Fail "shipped hook files missing: $($missingHooks -join ', ')" }
    elseif (-not (Test-Path -LiteralPath $policyPath)) { Fail "the neutral policy is missing: $policyPath - every adapter compiles from it" }
    else { Ok "all $($hookFiles.Count) hook adapters and the neutral policy ship" }

    # WQ-480: the policy must be authored in the form that travels. A regex-only policy is what locks
    # a control to whichever adapter was written first - the objection that produced this design.
    . (Join-Path $PSScriptRoot 'agent-policy-lib.ps1')
    $policy = Get-PackAgentPolicy -Path $policyPath
    $policyProblems = Test-PackAgentPolicyShape -Policy $policy
    if ($policyProblems.Count -gt 0) { Fail "shipped policy is not usable: $($policyProblems -join '; ')" }
    else { Ok "the neutral policy is usable ($(@($policy.shell.allow).Count) allow, $(@($policy.shell.refuse).Count) refuse, $(@($policy.settled).Count) settled)" }

    $regexOnly = @(@($policy.shell.allow) + @($policy.shell.refuse) | Where-Object { $_ -match '\\\\|\[\\w|\\s\+|\(\?' })
    if ($regexOnly.Count -gt 0) {
        Fail ("policy entries look like regexes rather than globs, which does not compile to a host that takes globs: " +
            ($regexOnly -join ' | '))
    } else { Ok 'policy patterns are globs, so they compile to both a regex host and a glob host' }

    # The compile, in-process. OpenCode's schema was confirmed against the real binary (1.18.30):
    # permission.<action> is a bare effect or a pattern->effect object, and NEITHER documented array
    # shape matched what it resolved - which is why this is asserted rather than assumed.
    $ocMap = ConvertTo-PackOpenCodePermission -Policy $policy
    $firstAllow = @($policy.shell.allow)[0]
    $firstRefuse = @($policy.shell.refuse)[0]
    if ($ocMap[$firstAllow] -ne 'allow') { Fail "compile dropped an allow entry: '$firstAllow' -> '$($ocMap[$firstAllow])'" }
    elseif ($ocMap[$firstRefuse] -ne 'ask') {
        Fail ("refuse must compile to 'ask', never 'deny' - it means the control has no opinion, not that the owner is locked out: " +
            "'$firstRefuse' -> '$($ocMap[$firstRefuse])'")
    } elseif (@($ocMap.Keys)[0] -ne $firstAllow) {
        Fail 'the compiled map must emit allow before refuse, so the narrower rule binds last as the binary orders its own built-ins'
    } else { Ok "policy compiles to an OpenCode permission.bash map ($($ocMap.Count) rules, refuse as ask)" }

    $ocTemplate = Get-Content -LiteralPath (Join-Path $PackRoot 'pack/templates/portable/opencode.json.template') -Raw -Encoding UTF8
    if ($ocTemplate -notmatch 'OPENCODE_PERMISSION_BLOCK') {
        Fail 'opencode.json.template has no permission placeholder - the compiled policy would never reach the file'
    } elseif ($ocTemplate -notmatch '\.cursor/rules/\*\.mdc') {
        Fail 'opencode.json.template no longer loads the pack rules by glob - that is the line that makes them work unconverted'
    } else { Ok 'opencode.json.template carries the rule globs and a slot for the compiled policy' }

    $tmplPath = Join-Path $PackRoot 'pack/templates/cursor/hooks.json.template'
    $tmpl = Get-Content -LiteralPath $tmplPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $registered = @($tmpl.hooks.PSObject.Properties.Name)
    if ($registered -notcontains 'afterAgentResponse' -or $registered -notcontains 'stop') {
        Fail "hooks.json.template must register afterAgentResponse and stop; it registers: $($registered -join ', ')"
    } elseif ($tmpl.hooks.stop[0].loop_limit -ne 1) {
        Fail "the stop hook must cap its follow-up loop at 1; template says '$($tmpl.hooks.stop[0].loop_limit)'"
    } elseif ($registered -contains 'beforeShellExecution') {
        Fail ('hooks.json.template registers beforeShellExecution - pre-approval widens what runs unattended, ' +
            'and that is a project owner decision rather than a shipped default')
    } else { Ok 'template registers the two tightening hooks with a loop cap, and leaves pre-approval off' }

    $psExe = Get-PackPowerShellPath
    # A probe state dir, because these hooks write a flag and logs and must not touch the real ones.
    # LOCALAPPDATA is first in Get-HookStateDir's candidate list on every OS, so it steers all of them.
    $hookProbe = Join-Path $PackRoot ".tmp/wq476-hooks-$PID"
    New-Item -ItemType Directory -Path $hookProbe -Force | Out-Null
    $savedLocalAppData = $env:LOCALAPPDATA
    $probeFlag = Join-Path $hookProbe 'AgentStarterPack/state/wq476-offload-flag.json'

    # Staged as a PROJECT rather than run where they ship, because the hooks locate the neutral policy
    # by walking up for `.agent-control/policy.json` (WQ-480). Running them in pack/templates would
    # exercise the fallback and leave the discovery walk - the thing that makes one policy serve two
    # hosts - untested. The layout mirrors what bootstrap writes.
    $probeProject = Join-Path $hookProbe 'project'
    $runDir = Join-Path $probeProject '.cursor/hooks'
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $probeProject '.agent-control') -Force | Out-Null
    foreach ($f in $hookFiles) { Copy-Item -LiteralPath (Join-Path $hookDir $f) -Destination (Join-Path $runDir $f) -Force }
    Copy-Item -LiteralPath $policyPath -Destination (Join-Path $probeProject '.agent-control/policy.json') -Force

    try {
        $env:LOCALAPPDATA = $hookProbe

        function Invoke-HookScript([string]$Name, [hashtable]$Payload) {
            # U+FEFF on purpose: Cursor sends one, and a hook that cannot read past it is a no-op.
            $json = ([char]0xFEFF) + ($Payload | ConvertTo-Json -Compress -Depth 6)
            return (($json | & $psExe -NoProfile -File (Join-Path $runDir $Name)) | Out-String).Trim()
        }
        function Reset-ProbeFlag { if (Test-Path -LiteralPath $probeFlag) { Remove-Item -LiteralPath $probeFlag -Force } }

        # --- the detector: flags an offload, and only an offload ---------------------------------
        Reset-ProbeFlag
        $askText = "Done.`n`n## What I need from you`n`n1. Run ``run_audit.cmd`` because I could not.`n"
        Invoke-HookScript 'offload-detect.ps1' @{ text = $askText; generation_id = 'gen-83'; hook_event_name = 'afterAgentResponse' } | Out-Null
        if (-not (Test-Path -LiteralPath $probeFlag)) {
            Fail 'offload-detect.ps1 did not flag an ask section telling the human to run run_audit.cmd'
        } else {
            $flagged = Get-Content -LiteralPath $probeFlag -Raw | ConvertFrom-Json
            if ([string]$flagged.reason -ne 'offload') { Fail "the flag names the wrong reason: '$($flagged.reason)'" }
            elseif ([string]$flagged.evidence -notmatch 'run_audit') { Fail "the flag does not quote what it found: '$($flagged.evidence)'" }
            elseif ([string]$flagged.generation_id -ne 'gen-83') { Fail "the flag lost the generation id: '$($flagged.generation_id)'" }
            else { Ok 'an ask naming a pre-approved command is flagged, with the reason, the evidence and the generation' }
        }

        # Discrimination, and this is the half that decides whether anyone leaves the hook enabled.
        # An ask naming install.ps1 is the maintainer's by policy, and prose that merely mentions a
        # command is not an ask at all - a checker that cannot tell those apart gets muted in a week.
        Reset-ProbeFlag
        $ownAsk = "Summary.`n`n## What I need from you`n`n- Run install.ps1 -Scope User to update your profile.`n"
        Invoke-HookScript 'offload-detect.ps1' @{ text = $ownAsk; generation_id = 'gen-83'; hook_event_name = 'afterAgentResponse' } | Out-Null
        $flaggedOwn = Test-Path -LiteralPath $probeFlag

        Reset-ProbeFlag
        $proseOnly = "I ran run_audit.cmd and pack\scripts\verify-audit-system.ps1; both exit 0. The rule forbids ending with run X to fix.`n"
        Invoke-HookScript 'offload-detect.ps1' @{ text = $proseOnly; generation_id = 'gen-83'; hook_event_name = 'afterAgentResponse' } | Out-Null
        $flaggedProse = Test-Path -LiteralPath $probeFlag

        if ($flaggedOwn) { Fail 'offload-detect.ps1 flagged an ask to run install.ps1, which is a profile write the human owns' }
        elseif ($flaggedProse) { Fail 'offload-detect.ps1 flagged prose that merely mentions commands - it must read the ask section, not the message' }
        else { Ok 'a profile-write ask and command-naming prose both pass clean' }

        # WQ-477: a decision the owner already made. This is the one case where "it is the human's
        # call" is not a defence - WQ-465 was recorded as an open publish decision for two days while
        # WQ-465 records publish as StarterPack-Airlock-only, so the
        # file itself kept regenerating the ask. The settled list must win over the refuse list,
        # which is why this arm uses a line that also matches the refuse entry for `git push`.
        Reset-ProbeFlag
        $settledAsk = "Done.`n`n## What I need from you`n`n- Decide where to publish this, then git push it so CI can run.`n"
        Invoke-HookScript 'offload-detect.ps1' @{ text = $settledAsk; generation_id = 'gen-83'; hook_event_name = 'afterAgentResponse' } | Out-Null
        if (-not (Test-Path -LiteralPath $probeFlag)) {
            Fail 'offload-detect.ps1 did not flag an ask re-raising a settled decision - a refuse-list match must not excuse it'
        } else {
            $settledFlag = Get-Content -LiteralPath $probeFlag -Raw | ConvertFrom-Json
            if ([string]$settledFlag.reason -ne 'settled') { Fail "a re-raised decision was reported as '$($settledFlag.reason)' rather than 'settled'" }
            elseif ([string]$settledFlag.evidence -notmatch 'WQ-465') { Fail 'the flag does not cite where the decision is recorded, so the handback would assert rather than point' }
            else { Ok 'an ask re-raising a settled decision is flagged, and cites where the decision is recorded' }
        }
        Reset-ProbeFlag
        $settledProse = "Publish tasks require StarterPack-Airlock on the host Desktop, so the macOS baseline will come from a CI run there.`n"
        Invoke-HookScript 'offload-detect.ps1' @{ text = $settledProse; generation_id = 'gen-83'; hook_event_name = 'afterAgentResponse' } | Out-Null
        if (Test-Path -LiteralPath $probeFlag) { Fail 'stating what a settled decision means was flagged - the check must read asks, not mentions' }
        else { Ok 'stating a settled decision without asking about it passes clean' }

        Write-Utf8NoBom -Path $probeFlag -Text (@{ generation_id = 'gen-83'; reason = 'settled'; evidence = 'step 83 fixture, recorded in WQ-465'; at = 'now' } | ConvertTo-Json -Compress)
        $gateSettled = Invoke-HookScript 'completion-gate.ps1' @{ generation_id = 'gen-83'; loop_count = 0; status = 'completed'; hook_event_name = 'stop' }
        if ($gateSettled -notmatch 'followup_message') { Fail "completion-gate.ps1 did not hand back on a settled verdict: '$gateSettled'" }
        elseif ($gateSettled -notmatch 'already decided') { Fail 'the settled handback reads like the offload one - the agent would look for a command to run instead of a decision to read' }
        else { Ok 'a settled verdict hands back with its own instruction, not the offload one' }

        # --- the gate: hands back once, and only on a live verdict --------------------------------
        Reset-ProbeFlag
        $gateSilent = Invoke-HookScript 'completion-gate.ps1' @{ generation_id = 'gen-83'; loop_count = 0; status = 'completed'; hook_event_name = 'stop' }
        if (-not [string]::IsNullOrWhiteSpace($gateSilent)) { Fail "completion-gate.ps1 spoke with no flag present: $gateSilent" }
        else { Ok 'no verdict on disk leaves the turn exactly as written' }

        Write-Utf8NoBom -Path $probeFlag -Text (@{ generation_id = 'gen-83'; reason = 'offload'; evidence = 'step 83 fixture'; at = 'now' } | ConvertTo-Json -Compress)
        $gateActs = Invoke-HookScript 'completion-gate.ps1' @{ generation_id = 'gen-83'; loop_count = 0; status = 'completed'; hook_event_name = 'stop' }
        if ($gateActs -notmatch 'followup_message') { Fail "completion-gate.ps1 did not hand the turn back on a matching verdict: '$gateActs'" }
        elseif ($gateActs -notmatch 'step 83 fixture') { Fail 'the handback dropped the evidence, so the agent would not know what it did' }
        elseif (Test-Path -LiteralPath $probeFlag) { Fail 'the verdict survived being acted on - a stale flag would fire again next turn' }
        else { Ok 'a matching verdict hands the turn back with its evidence, and is consumed' }

        # Both guards, because either one missing turns one handback into a loop the human has to break.
        Write-Utf8NoBom -Path $probeFlag -Text (@{ generation_id = 'gen-OLD'; reason = 'offload'; evidence = 'stale'; at = 'then' } | ConvertTo-Json -Compress)
        $gateStale = Invoke-HookScript 'completion-gate.ps1' @{ generation_id = 'gen-83'; loop_count = 0; status = 'completed'; hook_event_name = 'stop' }
        Write-Utf8NoBom -Path $probeFlag -Text (@{ generation_id = 'gen-83'; reason = 'offload'; evidence = 'looping'; at = 'now' } | ConvertTo-Json -Compress)
        $gateLoop = Invoke-HookScript 'completion-gate.ps1' @{ generation_id = 'gen-83'; loop_count = 1; status = 'completed'; hook_event_name = 'stop' }
        if (-not [string]::IsNullOrWhiteSpace($gateStale)) { Fail "a flag from another generation was acted on: $gateStale" }
        elseif (-not [string]::IsNullOrWhiteSpace($gateLoop)) { Fail "loop_count 1 still produced a handback: $gateLoop" }
        else { Ok 'a stale generation and a second loop are both declined' }

        # --- the approver, tested even though it ships unregistered -------------------------------
        $allowOut = Invoke-HookScript 'shell-preapprove.ps1' @{ command = "powershell -File $PackRoot\pack\scripts\verify-work-queue.ps1"; hook_event_name = 'beforeShellExecution' }
        $denyOut = Invoke-HookScript 'shell-preapprove.ps1' @{ command = "powershell -File $PackRoot\install.ps1 -Scope User"; hook_event_name = 'beforeShellExecution' }
        $chainOut = Invoke-HookScript 'shell-preapprove.ps1' @{ command = 'powershell -File pack\scripts\verify-work-queue.ps1; git push'; hook_event_name = 'beforeShellExecution' }
        if ($allowOut -notmatch '"permission"\s*:\s*"allow"') { Fail "shell-preapprove.ps1 did not allow a pack verify script: '$allowOut'" }
        elseif (-not [string]::IsNullOrWhiteSpace($denyOut)) { Fail "shell-preapprove.ps1 offered an opinion on install.ps1: '$denyOut'" }
        elseif (-not [string]::IsNullOrWhiteSpace($chainOut)) { Fail "an allow pattern followed by a second command was approved: '$chainOut'" }
        else { Ok 'pre-approval allows a verify gate, and refuses a profile write and a chained command' }

        # WQ-480: the shared vectors. One policy file stops two adapters disagreeing about the DATA; it
        # does nothing about them disagreeing over the SEMANTICS - which rule wins, what counts as an
        # ask, whether prose naming a command is a request to run it. Those are exactly the judgements
        # that make this control usable rather than muted, so they are measured as data too, and any
        # future host's adapter is held to the same file rather than trusted to have read this one.
        # Must run INSIDE this try: the finally restores LOCALAPPDATA and deletes the staged project,
        # and the first version of this loop sat below it - every hook then ran with a deleted script
        # path and printed a PowerShell banner, which the shell cases reported as an unparseable
        # verdict and the response cases as a clean turn. A control measured after its fixture is gone
        # measures nothing, which is this step's own subject.
        if (-not (Test-Path -LiteralPath $conformancePath)) {
            Fail "the shared conformance vectors are missing: $conformancePath - without them a second adapter is only reviewed, never checked"
        } else {
            $vectors = Get-Content -LiteralPath $conformancePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $conformanceFails = @()

            $caseIndex = 0
            foreach ($case in @($vectors.response_cases)) {
                $caseIndex++
                if (Test-Path -LiteralPath $probeFlag) { Remove-Item -LiteralPath $probeFlag -Force }
                Invoke-HookScript 'offload-detect.ps1' @{ text = $case.text; generation_id = "conf-$caseIndex" } | Out-Null
                $got = 'clean'
                if (Test-Path -LiteralPath $probeFlag) {
                    $verdict = Get-Content -LiteralPath $probeFlag -Raw | ConvertFrom-Json
                    $got = "flag:$($verdict.reason)"
                }
                if ($got -ne $case.expect) { $conformanceFails += "$($case.name): expected $($case.expect), got $got" }
            }

            foreach ($case in @($vectors.shell_cases)) {
                $out = Invoke-HookScript 'shell-preapprove.ps1' @{ command = $case.command }
                $got = 'no-opinion'
                if (-not [string]::IsNullOrWhiteSpace($out)) {
                    try { $got = ($out | ConvertFrom-Json).permission } catch { $got = "unparseable:$out" }
                }
                if ($got -ne $case.expect) { $conformanceFails += "$($case.name): expected $($case.expect), got $got" }
            }

            if (Test-Path -LiteralPath $probeFlag) { Remove-Item -LiteralPath $probeFlag -Force }
            $caseCount = @($vectors.response_cases).Count + @($vectors.shell_cases).Count
            if ($conformanceFails.Count -gt 0) {
                Fail ("the Cursor adapter fails $($conformanceFails.Count) of $caseCount shared conformance cases: " + ($conformanceFails -join ' | '))
            } else { Ok "the Cursor adapter passes all $caseCount shared conformance cases" }
        }
    } finally {
        $env:LOCALAPPDATA = $savedLocalAppData
        Remove-Item -LiteralPath $hookProbe -Recurse -Force -ErrorAction SilentlyContinue
    }

    # One decision list, read by every adapter. Two copies would drift silently: the detector would
    # stop flagging exactly the commands the approver had started allowing, and nothing would report
    # it. Asserted on the source because it is a structural claim - the behaviour arms above already
    # prove the policy is what they actually decide from.
    $detectText = Get-Content -LiteralPath (Join-Path $hookDir 'offload-detect.ps1') -Raw -Encoding UTF8
    $approveText = Get-Content -LiteralPath (Join-Path $hookDir 'shell-preapprove.ps1') -Raw -Encoding UTF8
    if ($detectText -notmatch 'Get-AgentPolicy' -or $approveText -notmatch 'Get-AgentPolicy') {
        Fail 'both adapters must read the neutral policy - a private copy of either list drifts without saying so'
    } elseif ($detectText -match 'preapproved\.json' -or $approveText -match 'preapproved\.json') {
        Fail 'an adapter still names the retired Cursor-local decision file'
    } else { Ok 'both adapters decide from the one host-neutral policy' }

    # The bootstrap half: a project gets the policy outside .cursor/, or the next adapter cannot find it.
    $bootstrapText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bootstrap-project.ps1') -Raw -Encoding UTF8
    if ($bootstrapText -notmatch '\.agent-control/policy\.json') {
        Fail 'bootstrap-project.ps1 does not deliver .agent-control/policy.json - the hooks would fall back to a per-host copy'
    } elseif ($bootstrapText -notmatch 'ConvertTo-PackOpenCodePermissionJson') {
        Fail 'bootstrap-project.ps1 writes opencode.json without compiling the policy into it'
    } else { Ok 'bootstrap delivers the neutral policy and compiles it for OpenCode' }
} catch {
    Fail "offload hook checks error: $_"
}

Write-Host "`n84. StarterPack-Airlock discovery and refresh overlay merge (WQ-487)"
try {
    function New-Wq487ProbeAirlock {
        param(
            [Parameter(Mandatory = $true)][string]$DesktopRoot,
            [string]$KeyId = 'wq487-probe-key',
            [switch]$WrongKey,
            [switch]$OmitKey
        )
        $airlock = Join-Path $DesktopRoot 'StarterPack-Airlock'
        New-Item -ItemType Directory -Path (Join-Path $airlock 'overlay') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $airlock 'repo') -Force | Out-Null
        $materialize = Join-Path $PackRoot 'pack/scripts/materialize-starter-pack-airlock-templates.ps1'
        if (-not (Test-Path -LiteralPath $materialize)) { throw "materialize script missing: $materialize" }
        $matExit = Invoke-PackScript -NoProfile -ScriptPath $materialize `
            -PackRoot $PackRoot -AirlockRoot $airlock -PublisherKeyId $KeyId
        if ($matExit -ne 0) { throw 'materialize failed for WQ-487 probe airlock' }
        if (-not $OmitKey) {
            $keyVal = if ($WrongKey) { 'wrong-key' } else { $KeyId }
            Write-Utf8NoBom -Path (Join-Path $airlock 'publisher.key') -Text $keyVal
        }
        return $airlock
    }

    $probeRoot = Join-Path $PackRoot ".tmp/wq487-airlock-$PID"
    if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null

    $emptyDesktop = Join-Path $probeRoot 'empty-desktop'
    New-Item -ItemType Directory -Path $emptyDesktop -Force | Out-Null
    if ($null -ne (Find-StarterPackAirlock -DesktopRoots @($emptyDesktop))) {
        Fail 'Find-StarterPackAirlock must return null when no Airlock folder exists (S01)'
    } else { Ok 'no Airlock folder yields null discovery (S01)' }

    $validDesktop = Join-Path $probeRoot 'valid-desktop'
    New-Item -ItemType Directory -Path $validDesktop -Force | Out-Null
    $null = New-Wq487ProbeAirlock -DesktopRoot $validDesktop
    $discValid = Find-StarterPackAirlock -DesktopRoots @($validDesktop)
    if ($null -eq $discValid) {
        Fail 'Find-StarterPackAirlock failed on a valid key + overlay layout (S02)'
    } elseif ($discValid.RequiredReads.Count -lt 2) {
        Fail "valid Airlock must expose at least two overlay requiredReads; got $($discValid.RequiredReads.Count)"
    } else { Ok "valid Airlock resolves with $($discValid.RequiredReads.Count) overlay requiredReads (S02)" }

    $badKeyDesktop = Join-Path $probeRoot 'bad-key-desktop'
    New-Item -ItemType Directory -Path $badKeyDesktop -Force | Out-Null
    $null = New-Wq487ProbeAirlock -DesktopRoot $badKeyDesktop -WrongKey
    if ($null -ne (Find-StarterPackAirlock -DesktopRoots @($badKeyDesktop))) {
        Fail 'Find-StarterPackAirlock must fail closed on wrong publisher.key (S04)'
    } else { Ok 'wrong publisher.key yields null discovery (S04)' }

    $noKeyDesktop = Join-Path $probeRoot 'no-key-desktop'
    New-Item -ItemType Directory -Path $noKeyDesktop -Force | Out-Null
    $null = New-Wq487ProbeAirlock -DesktopRoot $noKeyDesktop -OmitKey
    if ($null -ne (Find-StarterPackAirlock -DesktopRoots @($noKeyDesktop))) {
        Fail 'Find-StarterPackAirlock must fail closed when publisher.key is absent (S03)'
    } else { Ok 'missing publisher.key yields null discovery (S03)' }

    $incompleteDesktop = Join-Path $probeRoot 'incomplete-desktop'
    New-Item -ItemType Directory -Path $incompleteDesktop -Force | Out-Null
    $badAirlock = Join-Path $incompleteDesktop 'StarterPack-Airlock'
    New-Item -ItemType Directory -Path (Join-Path $badAirlock 'overlay/docs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $badAirlock 'repo') -Force | Out-Null
    $badManifest = @{
        schema        = 1
        keyId         = 'wq487-incomplete'
        repoDir       = 'repo'
        overlayDir    = 'overlay'
        requiredReads = @('overlay/docs/WORK_QUEUE.md', 'overlay/docs/MISSING.md')
    } | ConvertTo-Json -Depth 5
    Write-Utf8NoBom -Path (Join-Path $badAirlock 'overlay/manifest.json') -Text ($badManifest + "`r`n")
    Write-Utf8NoBom -Path (Join-Path $badAirlock 'publisher.key') -Text 'wq487-incomplete'
    if ($null -ne (Find-StarterPackAirlock -DesktopRoots @($incompleteDesktop))) {
        Fail 'Find-StarterPackAirlock must fail closed when overlay requiredReads are incomplete (S09)'
    } else { Ok 'incomplete overlay requiredReads yield null discovery (S09)' }

    $probeState = Join-Path $probeRoot 'state'
    New-Item -ItemType Directory -Path $probeState -Force | Out-Null
    $savedStateRoot = $env:AGENT_STARTER_PACK_STATE_ROOT
    $refreshScript = Join-Path $PackRoot 'pack/scripts/refresh-agent-context.ps1'
    try {
        $env:AGENT_STARTER_PACK_STATE_ROOT = $probeState
        Invoke-PackScript -NoProfile -ScriptPath $refreshScript -PackRoot $PackRoot -ProjectRoot $PackRoot `
            -SkipProjectSync -NoClipboard -StarterPackAirlockDesktopRoots @($validDesktop) | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "refresh with active Airlock failed (exit $LASTEXITCODE)" }
        $ctxPath = Join-Path $probeState 'AGENT_CONTEXT.json'
        if (-not (Test-Path -LiteralPath $ctxPath)) { throw 'AGENT_CONTEXT.json missing after refresh probe' }
        $ctx = Get-Content -LiteralPath $ctxPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $ctx.starterPackAirlockActive) {
            Fail 'refresh did not record starterPackAirlockActive when Desktop Airlock is present'
        } elseif (@($ctx.overlayRequiredReads).Count -lt 2) {
            Fail 'refresh did not record overlay requiredReads from the active Airlock'
        } else {
            $projectWq = Join-Path $PackRoot 'docs/WORK_QUEUE.md'
            $reads = @($ctx.requiredReads)
            $missingOverlay = @($ctx.overlayRequiredReads | Where-Object { $reads -notcontains $_ })
            if ($missingOverlay.Count -gt 0) {
                Fail ('requiredReads omits overlay paths: ' + ($missingOverlay -join '; '))
            } elseif ($reads -notcontains $projectWq) {
                Fail 'requiredReads must still include the working-copy docs/WORK_QUEUE.md - overlay must not replace project WQ'
            } elseif (@($reads | Where-Object { $_ -match 'overlay[\\/]docs[\\/]WORK_QUEUE\.md' }).Count -lt 1) {
                Fail 'requiredReads must include the overlay WORK_QUEUE path as an extra read, not a copy into the working copy'
            } else { Ok 'refresh merges overlay requiredReads and keeps project WORK_QUEUE canonical' }
        }

        Invoke-PackScript -NoProfile -ScriptPath $refreshScript -PackRoot $PackRoot -ProjectRoot $PackRoot `
            -SkipProjectSync -NoClipboard -StarterPackAirlockDesktopRoots @($emptyDesktop) | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "refresh without Airlock failed (exit $LASTEXITCODE)" }
        $ctxNoAirlock = Get-Content -LiteralPath $ctxPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($ctxNoAirlock.starterPackAirlockActive) {
            Fail 'refresh reported Airlock active when probe desktop has no Airlock folder'
        } elseif (@($ctxNoAirlock.overlayRequiredReads).Count -gt 0) {
            Fail 'overlayRequiredReads must be empty when discovery is inactive'
        } else { Ok 'refresh leaves overlay reads empty when no Airlock is present' }
    } finally {
        if ($null -eq $savedStateRoot) { Remove-Item Env:AGENT_STARTER_PACK_STATE_ROOT -ErrorAction SilentlyContinue }
        else { $env:AGENT_STARTER_PACK_STATE_ROOT = $savedStateRoot }
    }
} catch {
    Fail "StarterPack-Airlock discovery/refresh checks error: $_"
} finally {
    if (Test-Path -LiteralPath (Join-Path $PackRoot ".tmp/wq487-airlock-$PID")) {
        Remove-Item -LiteralPath (Join-Path $PackRoot ".tmp/wq487-airlock-$PID") -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n85. Recurring audit sync drift names a live writer (WQ-481)"
# When the same installed path drifts on two verify-only runs, "run sync again" conceals a live writer
# (escaped guard mutations, background proof runs). Session state lives under Get-AgentStateRoot.
try {
    $syncScript = Join-Path $PackRoot 'pack/scripts/sync-audit-system.ps1'
    $syncText = Get-Content -LiteralPath $syncScript -Raw -Encoding UTF8
    if ($syncText -notmatch '\[RECURRING DRIFT\]') {
        Fail 'sync-audit-system.ps1 does not distinguish recurring drift from ordinary staleness'
    } elseif ($syncText -notmatch 'guard-proofs\.lock') {
        Fail 'sync-audit-system.ps1 does not mention guard-proofs.lock when recurring drift is detected'
    } else { Ok 'sync script carries recurring-drift guidance and guard-proof lock hint' }

    $wq481Root = Join-Path $PackRoot ".tmp/wq481-recurring-$PID"
    $wq481Source = Join-Path $wq481Root 'source'
    $wq481Installed = Join-Path $wq481Root 'installed/AgentStarterPack'
    $prevInstall = $env:AGENT_STARTER_PACK_INSTALL_ROOT
    $prevState = $env:AGENT_STARTER_PACK_STATE_ROOT
    try {
        if (Test-Path -LiteralPath $wq481Root) { Remove-Item -LiteralPath $wq481Root -Recurse -Force }
        foreach ($d in @("$wq481Source/pack/audit", "$wq481Source/pack/scripts", "$wq481Source/pack/rules", "$wq481Installed/pack/audit", "$wq481Installed/pack/rules")) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
        $wq481Manifest = @'
{
  "version": "wq481-recurring-probe",
  "packMirror": [ "pack/rules/wq481-probe.mdc" ],
  "packToUser": [],
  "forbiddenPackPaths": []
}
'@
        Write-Utf8NoBom "$wq481Source/pack/audit/manifest.json" ($wq481Manifest)
        Write-Utf8NoBom "$wq481Installed/pack/audit/manifest.json" ($wq481Manifest)
        Copy-Item -LiteralPath (Join-Path $PackRoot 'pack/scripts/pack-paths.ps1') -Destination "$wq481Source/pack/scripts/pack-paths.ps1"
        Copy-Item -LiteralPath $syncScript -Destination "$wq481Source/pack/scripts/sync-audit-system.ps1"
        $probeSync = "$wq481Source/pack/scripts/sync-audit-system.ps1"

        $srcFile = "$wq481Source/pack/rules/wq481-probe.mdc"
        $dstFile = "$wq481Installed/pack/rules/wq481-probe.mdc"
        Write-Utf8NoBom $srcFile 'source-authoritative'
        Write-Utf8NoBom $dstFile 'installed-drift'

        $env:AGENT_STARTER_PACK_INSTALL_ROOT = $wq481Installed
        $env:AGENT_STARTER_PACK_STATE_ROOT = Join-Path $wq481Root 'state'

        $firstOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeSync -VerifyOnly 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Fail 'first VerifyOnly expected drift on the installed mirror' }
        elseif ($firstOut -match '\[RECURRING DRIFT\]') {
            Fail 'first VerifyOnly must not report recurring drift before a prior run recorded the path'
        } else { Ok 'first drift run records session state without recurring warning' }

        $secondOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeSync -VerifyOnly 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Fail 'second VerifyOnly expected the same drift' }
        elseif ($secondOut -notmatch '\[RECURRING DRIFT\]') {
            Fail "second VerifyOnly on unchanged drift did not report recurring drift: $($secondOut.Trim())"
        } elseif ($secondOut -notmatch 'Do not run sync again blindly') {
            Fail 'recurring drift message must warn against blind re-sync'
        } else { Ok 'second drift run reports recurring drift and warns against blind re-sync' }

        Write-Utf8NoBom $dstFile 'installed-drift'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeSync 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "sync after drift failed (exit $LASTEXITCODE)" }
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $probeSync -VerifyOnly 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'VerifyOnly still red after sync fixed the mirror' }
        else { Ok 'clean verify clears recurring-drift session state' }
    } finally {
        if ($null -eq $prevInstall) { Remove-Item Env:AGENT_STARTER_PACK_INSTALL_ROOT -ErrorAction SilentlyContinue }
        else { $env:AGENT_STARTER_PACK_INSTALL_ROOT = $prevInstall }
        if ($null -eq $prevState) { Remove-Item Env:AGENT_STARTER_PACK_STATE_ROOT -ErrorAction SilentlyContinue }
        else { $env:AGENT_STARTER_PACK_STATE_ROOT = $prevState }
        if (Test-Path -LiteralPath $wq481Root) { Remove-Item -LiteralPath $wq481Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
} catch {
    Fail "recurring sync drift checks error: $_"
}

Write-Host "`n86. Dual-zone Airlock publish gate (WQ-488)"
try {
    $gateScript = Join-Path $PackRoot 'pack/scripts/verify-airlock-publish-gate.ps1'
    $vsysPath = Join-Path $PackRoot 'pack/scripts/verify-audit-system.ps1'
    if (-not (Test-Path -LiteralPath $gateScript)) {
        Fail 'verify-airlock-publish-gate.ps1 missing (B11)'
    } elseif ((Get-Content -LiteralPath $gateScript -Raw -Encoding UTF8) -notmatch '\[DUAL-ZONE FAIL\]') {
        Fail 'publish gate does not distinguish Zone A pass + Zone B fail'
    } elseif ((Get-Content -LiteralPath $gateScript -Raw -Encoding UTF8) -notmatch 'sync-working-copy-to-airlock-repo\.ps1') {
        Fail 'publish gate does not invoke B09 sync script'
    } else { Ok 'publish gate script carries dual-zone + B09 wiring' }

    $vsys = Get-Content -LiteralPath $vsysPath -Raw -Encoding UTF8
    if ($vsys -notmatch '\[string\]\$PublishRoot') {
        Fail 'verify-audit-system.ps1 missing -PublishRoot for Zone B behavior pass (B10)'
    } elseif ($vsys -notmatch 'Zone B publish-root behavior') {
        Fail 'verify-audit-system.ps1 does not run a Zone B behavior pass when -PublishRoot is set'
    } else { Ok 'verify-audit-system.ps1 accepts -PublishRoot for Zone B behavior' }

    $wq488Root = Join-Path $PackRoot ".tmp/wq488-gate-$PID"
    $wq488Wc = Join-Path $wq488Root 'working'
    $wq488Repo = Join-Path $wq488Root 'repo'
    try {
        if (Test-Path -LiteralPath $wq488Root) { Remove-Item -LiteralPath $wq488Root -Recurse -Force }
        foreach ($d in @("$wq488Wc/pack/audit", "$wq488Wc/pack/scripts", "$wq488Repo/pack/audit")) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
        $miniManifest = @'
{
  "version": "wq488",
  "maintainerOnlyPaths": ["docs/handoffs"],
  "machineLocalPaths": ["install-manifest.json"],
  "repoOnlyPaths": [".github"],
  "packMirror": [],
  "forbiddenPackPaths": []
}
'@
        Write-Utf8NoBom "$wq488Wc/pack/audit/manifest.json" ($miniManifest)
        Write-Utf8NoBom "$wq488Repo/pack/audit/manifest.json" ($miniManifest)
        Write-Utf8NoBom "$wq488Wc/VERSION" '1.0.0'
        Write-Utf8NoBom "$wq488Repo/VERSION" '9.9.9'
        Copy-Item -LiteralPath (Join-Path $PackRoot 'pack/scripts/pack-paths.ps1') `
            -Destination "$wq488Wc/pack/scripts/pack-paths.ps1"
        Copy-Item -LiteralPath (Join-Path $PackRoot 'pack/scripts/sync-working-copy-to-airlock-repo.ps1') `
            -Destination "$wq488Wc/pack/scripts/sync-working-copy-to-airlock-repo.ps1"
        Copy-Item -LiteralPath $gateScript -Destination "$wq488Wc/pack/scripts/verify-airlock-publish-gate.ps1"

        $gateCopy = "$wq488Wc/pack/scripts/verify-airlock-publish-gate.ps1"
        $whatIfOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $gateCopy `
            -WorkingCopy $wq488Wc -PublishRoot $wq488Repo -WhatIf 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Fail "publish gate -WhatIf failed (exit $LASTEXITCODE)" }
        elseif ($whatIfOut -notmatch 'B09 sync') { Fail 'publish gate -WhatIf did not mention B09 sync' }
        else { Ok 'publish gate -WhatIf plans Zone A, sync, and Zone B' }

        $driftOut = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $gateCopy `
            -WorkingCopy $wq488Wc -PublishRoot $wq488Repo -SkipZoneA -SkipZoneB 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Fail 'publish gate should fail B09 sync on VERSION drift'
        } elseif ($driftOut -notmatch 'VERSION drift') {
            Fail "publish gate sync did not report VERSION drift: $($driftOut.Trim())"
        } else { Ok 'publish gate fails closed on VERSION drift during B09 sync' }
    } finally {
        if (Test-Path -LiteralPath $wq488Root) {
            Remove-Item -LiteralPath $wq488Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} catch {
    Fail "dual-zone publish gate checks error: $_"
}

Write-Host "`n87. Zone B publish attestation (B12)"
try {
    $syncScript = Join-Path $PackRoot 'pack/scripts/sync-working-copy-to-airlock-repo.ps1'
    $coreScript = Join-Path $PackRoot 'pack/scripts/run_audit_core.ps1'
    $pathsScript = Join-Path $PackRoot 'pack/scripts/pack-paths.ps1'
    if (-not (Test-Path -LiteralPath $syncScript)) { Fail 'sync-working-copy-to-airlock-repo.ps1 missing' }
    elseif (-not (Test-Path -LiteralPath $coreScript)) { Fail 'run_audit_core.ps1 missing' }
    else {
        $syncBody = Get-Content -LiteralPath $syncScript -Raw -Encoding UTF8
        $coreBody = Get-Content -LiteralPath $coreScript -Raw -Encoding UTF8
        $pathsBody = Get-Content -LiteralPath $pathsScript -Raw -Encoding UTF8
        if ($syncBody -notmatch 'Write-PackPublishAttestation') {
            Fail 'B09 sync does not write publish attestation'
        } elseif ($coreBody -notmatch 'Test-PackPublishAttestation') {
            Fail 'run_audit_core does not validate publish attestation on Zone B trees'
        } elseif ($pathsBody -notmatch 'function Write-PackPublishAttestation') {
            Fail 'pack-paths.ps1 missing Write-PackPublishAttestation'
        } else {
            $gateScript87 = Join-Path $PackRoot 'pack/scripts/verify-airlock-publish-gate.ps1'
            if (-not (Test-Path -LiteralPath $gateScript87)) {
                Fail 'verify-airlock-publish-gate.ps1 missing'
            } elseif ((Get-Content -LiteralPath $gateScript87 -Raw -Encoding UTF8) -notmatch 'Test-PackPublishAttestation') {
                Fail 'publish gate does not verify attestation after B09 sync'
            } else { Ok 'Zone B attestation wired in sync, run_audit_core, and publish gate' }
        }
    }
} catch {
    Fail "Zone B publish attestation checks error: $_"
}

Write-Host "`nSummary: $fail fail(s)"
Write-SuiteResults
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
