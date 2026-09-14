#Requires -Version 5.1
<#
.SYNOPSIS
  Generic audit machine checks - driven by docs/AUDIT.config.json in the app root.
  All projects use this core; project config defines paths, patterns, and domain map rules.
#>
param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [switch]$SkipTests,
    [switch]$FinalizeOnly,
    [string]$ConfigPath = ''
)

$ErrorActionPreference = 'Continue'
# At script scope, not inside Get-PackRoot: dot-sourcing within a function scopes the definitions to
# that function, so the shared helpers were invisible everywhere else in this file.
. (Join-Path $PSScriptRoot 'pack-paths.ps1')
# Pure functions, no load-time work. Needed for Get-PackChildFailureDetail, so the one place that
# reports a child verify's failure quotes what the child actually said (WQ-463).
. (Join-Path $PSScriptRoot 'verify-lib.ps1')

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$AppRoot = (Resolve-Path -LiteralPath $AppRoot).Path
Set-Location $AppRoot

$Fix = [System.Collections.Generic.List[string]]::new()
$Improve = [System.Collections.Generic.List[string]]::new()
$script:CodeMachineFixes = $null
$script:RequiredSectionCount = 0
$script:TestsGitHead = $null
$script:TestsPassedAt = $null
$script:LegacyNoGitProof = '__no_git__'
$script:AuditPhases = [ordered]@{}
$script:PhaseWatch = $null
$script:PhaseName = ''
$script:AuditRunStarted = $null
$script:AuditMode = 'full'
function Add-Fix([string]$m) { $Fix.Add($m) }
function Add-Improve([string]$m) { $Improve.Add($m) }

function Start-AuditPhase([string]$Name) {
    if ($script:PhaseWatch) { Stop-AuditPhase $script:PhaseName }
    $script:PhaseName = $Name
    $script:PhaseWatch = [System.Diagnostics.Stopwatch]::StartNew()
}

function Stop-AuditPhase([string]$Name) {
    if (-not $script:PhaseWatch) { return }
    $script:PhaseWatch.Stop()
    if ($Name) { $script:AuditPhases[$Name] = [math]::Round($script:PhaseWatch.Elapsed.TotalSeconds, 3) }
    $script:PhaseWatch = $null
    $script:PhaseName = ''
}

function Get-RepoGitHead([string]$Root) {
    # Test-PackGitRepo, not a .git path test: a leftover .git directory (an editor index cache after
    # the repository is deleted) made this run `git rev-parse` against a non-repo, which degraded to
    # a null head correctly but printed a fatal error into the audit's own output (WQ-461).
    if (-not (Test-PackGitRepo -Root $Root)) { return $null }
    try {
        $h = (& git -C $Root rev-parse HEAD 2>$null | Select-Object -First 1)
        if ($h) { return $h.ToString().Trim() }
    } catch { }
    return $null
}

function Get-ProofFileContentHash([string]$LiteralPath) {
    $ext = [System.IO.Path]::GetExtension($LiteralPath).ToLowerInvariant()
    $textExts = @('.py', '.md', '.json', '.ps1', '.mdc', '.txt', '.yml', '.yaml', '.sh', '.bat', '.cmd', '.template')
    if ($textExts -contains $ext) {
        $text = [System.IO.File]::ReadAllText($LiteralPath)
        $normalized = $text -replace "`r`n", "`n" -replace "`r", "`n"
        $bytes = [Text.Encoding]::UTF8.GetBytes($normalized)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        return -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
    }
    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-AuditTreeFingerprint([string]$AppRoot, $Cfg) {
    $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($Cfg.tests -and $Cfg.tests.script) {
        $tp = Join-Path $AppRoot ($Cfg.tests.script -replace '/', '\')
        if (Test-Path -LiteralPath $tp) { [void]$paths.Add((Resolve-Path -LiteralPath $tp).Path) }
    }
    foreach ($rel in @('docs\AUDIT.config.json', 'docs\AUDIT.md')) {
        $p = Join-Path $AppRoot $rel
        if (Test-Path -LiteralPath $p) { [void]$paths.Add((Resolve-Path -LiteralPath $p).Path) }
    }
    $dm = $Cfg.domainMap
    if ($dm) {
        $scanDir = Join-Path $AppRoot (($dm.scanDir -replace '/', '\'))
        if (-not $dm.scanDir -or $dm.scanDir -eq '.') { $scanDir = $AppRoot }
        $glob = if ($dm.scanGlob) { $dm.scanGlob } else { '*.py' }
        if (Test-Path -LiteralPath $scanDir) {
            Get-ChildItem -LiteralPath $scanDir -Filter $glob -File -ErrorAction SilentlyContinue | ForEach-Object {
                [void]$paths.Add($_.FullName)
            }
        }
        foreach ($subdir in @($dm.moduleSearchDirs)) {
            $sd = Join-Path $AppRoot ($subdir -replace '/', '\')
            if (Test-Path -LiteralPath $sd) {
                Get-ChildItem -LiteralPath $sd -Filter $glob -File -ErrorAction SilentlyContinue | ForEach-Object {
                    [void]$paths.Add($_.FullName)
                }
            }
        }
    } else {
        $scanDir = $AppRoot
        if (Test-Path -LiteralPath $scanDir) {
            Get-ChildItem -LiteralPath $scanDir -Filter '*.py' -File -ErrorAction SilentlyContinue | ForEach-Object {
                [void]$paths.Add($_.FullName)
            }
        }
    }
    # sha256 of nothing is a constant, so an empty set would pass as a proof that matches forever.
    if ($paths.Count -eq 0) { return $null }
    # Contents, not size and mtime: mtimes do not survive a copy to another drive and can be
    # restored, so an mtime proof can be stale and matching at the same time. Must stay
    # byte-identical to compute_tree_fingerprint in audit_code_checks.py.
    $appFull = (Resolve-Path -LiteralPath $AppRoot).Path.TrimEnd('\')
    $byRel = @{}
    foreach ($f in $paths) {
        $full = (Resolve-Path -LiteralPath $f).Path
        if ($full.StartsWith(($appFull + '\'), [StringComparison]::OrdinalIgnoreCase)) {
            $rel = $full.Substring($appFull.Length + 1)
        } else {
            $rel = $full
        }
        $rel = ($rel -replace '\\', '/').ToLowerInvariant()
        $byRel[$rel] = Get-ProofFileContentHash -LiteralPath $full
    }
    # Ordinal sort: Sort-Object is culture-aware and orders punctuation differently from Python's
    # sorted(), and both sides have to hash the same sequence.
    $rels = [string[]]@($byRel.Keys)
    [Array]::Sort($rels, [System.StringComparer]::Ordinal)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $ms = New-Object System.IO.MemoryStream
    foreach ($rel in $rels) {
        $bytes = [Text.Encoding]::UTF8.GetBytes("$rel|$($byRel[$rel])`n")
        $ms.Write($bytes, 0, $bytes.Length)
    }
    $hash = $sha.ComputeHash($ms.ToArray())
    return 'tree:' + (-join ($hash | ForEach-Object { $_.ToString('x2') }))
}

function Get-TestsProofHeadFromPython([string]$AppRoot) {
    $codePy = Join-Path $PSScriptRoot 'audit_code_checks.py'
    if (-not (Test-Path -LiteralPath $codePy)) { return $null }
    $out = Invoke-PackPython $codePy $AppRoot --print-tests-git-head 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }
    $line = ($out | Select-Object -Last 1).ToString().Trim()
    if ($line) { return $line }
    return $null
}

function Get-TestsProofHead([string]$RepoRoot, [string]$AppRoot, $Cfg) {
    # Python owns this computation: audit_code_checks.py recomputes the same proof when it
    # verifies semantic freshness, and it resolves the repo from AppRoot. Asking Python first
    # keeps both sides identical even when AppRoot sits inside an outer git repo it cannot see.
    $pyHead = Get-TestsProofHeadFromPython $AppRoot
    if ($pyHead) { return $pyHead }
    # HEAD is a prefix, never the whole proof: it does not move for uncommitted edits, so on its
    # own it let a reviewed-and-passed project change code and keep the pass.
    $fp = Get-AuditTreeFingerprint $AppRoot $Cfg
    $git = Get-RepoGitHead $RepoRoot
    if (-not $fp) { return $git }
    if ($git) { return "$git+$fp" }
    return $fp
}

function Test-ManifestFinalizeAllowed([string]$AppRoot, [string]$RepoRoot, $Cfg) {
    $path = Join-Path $AppRoot 'docs/.audit_agent_manifest.json'
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Fix "Audit finalize blocked - no docs\.audit_agent_manifest.json - run full $(Get-PackEntryPoint 'run_audit') first"
        return $false
    }
    try {
        $script:FinalizeManifest = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Add-Fix 'Audit finalize blocked - invalid docs\.audit_agent_manifest.json'
        return $false
    }
    $man = $script:FinalizeManifest
    if (-not $man.testsPassedAt -or -not $man.testsGitHead) {
        Add-Fix "Audit finalize blocked - manifest has no test-pass proof - run full $(Get-PackEntryPoint 'run_audit') first"
        return $false
    }
    if ($man.testsGitHead -eq $script:LegacyNoGitProof) {
        Add-Fix "Audit finalize blocked - stale test proof - run full $(Get-PackEntryPoint 'run_audit') first"
        return $false
    }
    $head = Get-TestsProofHead $RepoRoot $AppRoot $Cfg
    if (-not $head) {
        Add-Fix "Audit finalize blocked - cannot compute test-pass proof - run full $(Get-PackEntryPoint 'run_audit')"
        return $false
    }
    if ($head -ne $man.testsGitHead.ToString()) {
        Add-Fix "Audit finalize blocked - source tree changed since last test pass - run full $(Get-PackEntryPoint 'run_audit')"
        return $false
    }
    $script:TestsGitHead = $man.testsGitHead.ToString()
    $script:TestsPassedAt = $man.testsPassedAt.ToString()
    return $true
}

function Test-SemanticPassIncomplete {
    return @($Fix | Where-Object { $_ -match '^Semantic report' }).Count -gt 0
}

function Test-AuditGateIncomplete {
    return @($Fix | Where-Object {
        $_ -match '^Semantic report missing|^Semantic report invalid|^Semantic report verify failed|^Incomplete audit'
    }).Count -gt 0
}

function Write-SemanticNextSteps {
    Write-Host ''
    Write-Host 'Semantic pass incomplete. Next steps:'
    Write-Host "  1. If needed: $(Get-PackEntryPoint 'scripts/write_semantic_audit_template') (auto-written on step 1 when missing)"
    if ($script:RequiredSectionCount -gt 0) {
        Write-Host "  2. Edit docs\.audit_semantic_report.json - all $script:RequiredSectionCount sections (reviewed + summary + evidence when not clean)"
    } else {
        Write-Host '  2. Edit docs\.audit_semantic_report.json - all required sections'
    }
    Write-Host "  3. $(Get-PackEntryPoint 'scripts/verify_semantic_audit')"
    Write-Host "  4. $(Get-PackEntryPoint 'scripts/finalize_audit')   (or $(Get-PackEntryPoint 'run_audit') -FinalizeOnly - skips tests if git HEAD unchanged)"
    Write-Host "  5. Or run full $(Get-PackEntryPoint 'run_audit') again if the tree changed since tests ran"
}

function Update-ManifestMachineFixes(
    [string]$ManifestPath,
    [System.Collections.Generic.List[string]]$AllFixes,
    [hashtable]$CodeMachineFixes = $null,
    [string]$TestsGitHead = '',
    [string]$TestsPassedAt = '',
    [hashtable]$MachineImproves = $null
) {
    if (-not $ManifestPath -or -not (Test-Path -LiteralPath $ManifestPath)) { return }
    try {
        $bySec = [ordered]@{}
        $gateFixes = [System.Collections.Generic.List[string]]::new()
        function Add-SectionFix([string]$Letter, [string]$Text) {
            if (-not $bySec[$Letter]) { $bySec[$Letter] = [System.Collections.Generic.List[string]]::new() }
            if ($bySec[$Letter] -notcontains $Text) { [void]$bySec[$Letter].Add($Text) }
        }
        if ($CodeMachineFixes) {
            foreach ($letter in $CodeMachineFixes.Keys) {
                foreach ($item in @($CodeMachineFixes[$letter])) {
                    if ($item) { Add-SectionFix $letter $item }
                }
            }
        }
        foreach ($f in $AllFixes) {
            if ($f -match '^Semantic report missing|^Semantic report invalid|^Semantic report verify failed|^Incomplete audit') {
                if ($gateFixes -notcontains $f) { [void]$gateFixes.Add($f) }
                continue
            }
            if ($f -match '^Section ([A-N]) ') { Add-SectionFix $Matches[1] $f; continue }
            if ($f -match '^Semantic report - section ([A-N]) ') { Add-SectionFix $Matches[1] $f; continue }
            if ($f -match '^(Version |Tests failed|Dist version|Import smoke)') { Add-SectionFix 'A' $f; continue }
            if ($f -match 'Stale doc|Stale logs|Build cruft|Cache cruft|Possible secret|Committed env|Obsolete|Stable |Old folder|Missing path|Domain map - ') {
                Add-SectionFix 'B' $f; continue
            }
            if ($f -match 'Audit sync|Audit wiring|Code checks|Missing audit file|Old audit|forbidden rule|Forbidden') {
                Add-SectionFix 'L' $f; continue
            }
        }
        $out = @{}
        foreach ($k in $bySec.Keys) { $out[$k] = @($bySec[$k]) }
        $sectionsWithFixes = @($bySec.Keys | Sort-Object)
        # -Encoding UTF8, not cosmetic: PowerShell 5.1 reads a BOM-less UTF-8 file as ANSI, so this
        # read turned every em dash in the manifest into three characters and the write below stored
        # them as UTF-8 - the agent's brief was double-encoded a little more on each audit.
        $man = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $man | Add-Member -NotePropertyName machineFixesBySection -NotePropertyValue $out -Force
        $man | Add-Member -NotePropertyName machineSectionsWithFixes -NotePropertyValue $sectionsWithFixes -Force
        # Improve lines get their own channel: an agent that only reads machineFixesBySection sees
        # "delete dist/" and calls the section done, which is how layout review kept getting skipped.
        $improveOut = @{}
        if ($MachineImproves) {
            foreach ($k in $MachineImproves.Keys) {
                $vals = @($MachineImproves[$k] | Where-Object { $_ })
                if ($vals.Count -gt 0) { $improveOut[$k] = $vals }
            }
        }
        $man | Add-Member -NotePropertyName machineImprovesBySection -NotePropertyValue $improveOut -Force
        $man | Add-Member -NotePropertyName machineSectionsWithImproves -NotePropertyValue @($improveOut.Keys | Sort-Object) -Force
        $man | Add-Member -NotePropertyName auditGateFixes -NotePropertyValue @($gateFixes) -Force
        if ($TestsGitHead) {
            $man | Add-Member -NotePropertyName testsGitHead -NotePropertyValue $TestsGitHead -Force
        } elseif ($man.PSObject.Properties.Name -contains 'testsGitHead') {
            $man | Add-Member -NotePropertyName testsGitHead -NotePropertyValue $man.testsGitHead -Force
        }
        if ($TestsPassedAt) {
            $man | Add-Member -NotePropertyName testsPassedAt -NotePropertyValue $TestsPassedAt -Force
        } elseif ($man.PSObject.Properties.Name -contains 'testsPassedAt') {
            $man | Add-Member -NotePropertyName testsPassedAt -NotePropertyValue $man.testsPassedAt -Force
        }
        $man | ConvertTo-Json -Depth 12 | ForEach-Object { Write-Utf8JsonFile $ManifestPath $_ }
    } catch { }
}

function Write-Utf8JsonFile([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Write-AuditTimingLog([int]$ExitCode, [string]$ProjectLabel) {
    Stop-AuditPhase $script:PhaseName
    if (-not $script:AuditRunStarted) { return }
    $script:AuditRunStarted.Stop()
    $timingPath = Join-Path $AppRoot 'docs/.audit_timing.jsonl'
    $total = [math]::Round($script:AuditRunStarted.Elapsed.TotalSeconds, 3)
    $entry = @{
        runAt        = (Get-Date).ToUniversalTime().ToString('o')
        mode         = $script:AuditMode
        project      = $ProjectLabel
        phases       = $script:AuditPhases
        totalSeconds = $total
        exitCode     = $ExitCode
    }
    try {
        $dir = Split-Path -Parent $timingPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Utf8NoBomLine -Path $timingPath -Line ($entry | ConvertTo-Json -Compress)
        Write-Host "Audit timing: docs\.audit_timing.jsonl (${total}s total)"
    } catch {
        # Timing is diagnostic, so a failure here must not fail the audit - but swallowing it silently
        # hid the log disappearing entirely, which only a behavior test noticed.
        Write-Host "[WARN] could not write docs\.audit_timing.jsonl - $_"
    }
}

function Write-AuditReport {
    Write-Host ''
    Write-Host '========== AUDIT (machine + semantic gate) =========='
    Write-Host '## Fix'
    if ($Fix.Count -eq 0) { Write-Host 'Nothing found.' } else { $Fix | ForEach-Object { Write-Host "- $_" } }
    Write-Host ''
    Write-Host '## Improve'
    if ($Improve.Count -eq 0) { Write-Host 'Nothing found.' } else { $Improve | ForEach-Object { Write-Host "- $_" } }
    Write-Host ''
    Write-Host 'Agent: read docs\.audit_agent_manifest.json - semantic review (machine checks above).'
    Write-Host '============================================'
}

function Get-PackRoot {
    param([string]$PreferAppRoot = '')
    . (Join-Path $PSScriptRoot 'pack-paths.ps1')
    if ($PreferAppRoot) {
        $manifest = Join-Path $PreferAppRoot 'pack/audit/manifest.json'
        $install = Join-Path $PreferAppRoot 'install.ps1'
        if ((Test-Path -LiteralPath $manifest) -and (Test-Path -LiteralPath $install)) {
            return $PreferAppRoot
        }
    }
    Get-AgentStarterPackRoot
}

function Get-JsonFromOutput([string]$Text) {
    if (-not $Text) { return $null }
    $start = $Text.IndexOf('{')
    $end = $Text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { return $null }
    return $Text.Substring($start, $end - $start + 1)
}

function Load-AuditConfig([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Fix "Missing AUDIT.config.json - copy from starter pack templates/docs/AUDIT.config.json.template"
        return $null
    }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Add-Fix "Invalid AUDIT.config.json - $_"
        return $null
    }
}

if (-not $ConfigPath) { $ConfigPath = Join-Path $AppRoot 'docs/AUDIT.config.json' }
$cfg = Load-AuditConfig $ConfigPath
$projectLabel = if ($cfg.projectName) { $cfg.projectName } else { Split-Path $RepoRoot -Leaf }

Write-Host "$projectLabel audit (machine + semantic gate)"
Write-Host "Repo: $RepoRoot"
Write-Host "App:  $AppRoot"
Write-Host ""

# Prefix for remediation text, so a Fix line names a path this project actually has. Hardcoded
# "app\" here came from the nested-only era and told flat projects - what bootstrap generates - to
# fix app\docs\AUDIT.md and run app\scripts\sync_audit_system.cmd, neither of which exists there.
$appPrefix = ''
try {
    if ((Resolve-Path -LiteralPath $AppRoot).Path -ne (Resolve-Path -LiteralPath $RepoRoot).Path) {
        $appPrefix = (Split-Path -Leaf $AppRoot) + (Get-PackPathSeparator)
    }
} catch { $appPrefix = '' }

if (-not $cfg) {
    Write-AuditReport
    Write-AuditTimingLog 1 $projectLabel
    exit 1
}

$script:AuditRunStarted = [System.Diagnostics.Stopwatch]::StartNew()
if ($FinalizeOnly) { $script:AuditMode = 'finalize' }
elseif ($SkipTests) { $script:AuditMode = 'skip_tests' }
else { $script:AuditMode = 'full' }
Start-AuditPhase 'init'

if ($FinalizeOnly -and $SkipTests) {
    Add-Fix 'Audit finalize blocked - do not combine -FinalizeOnly with -SkipTests'
}

$testsPassed = $false

if ($FinalizeOnly) {
    Write-Host 'Mode: FinalizeOnly (skip tests; reuse manifest test-pass proof)'
    if (Test-ManifestFinalizeAllowed $AppRoot $RepoRoot $cfg) { $testsPassed = $true }
}
# A full run captures the proof after the tests pass (see the tests phase below), not here.
# Capturing it pre-test recorded the tree as it was before the test script ran, and a test script
# that runs a version or doc sync rewrites files the proof covers. With a git repo the proof is a
# stable HEAD so it never showed, but in fingerprint mode - any project that has not run git init -
# the verifier's post-test recompute could never match, leaving the semantic gate permanently stale.
# Zone B: validate publish attestation before tests or version sync can mutate the proof tree.
$script:ZoneBAttestationAtStart = $null
if (Test-PackPublishZoneBTree -Root $AppRoot) {
    $script:ZoneBAttestationAtStart = Test-PackPublishAttestation -Root $AppRoot
}

Stop-AuditPhase 'init'

# --- Version sync ---
Start-AuditPhase 'version_sync'
if ($cfg.versionSync) {
    $vs = $cfg.versionSync
    $pyVer = $null
    $pyFile = Join-Path $AppRoot ($vs.codeFile -replace '/', '\')
    if (Test-Path -LiteralPath $pyFile) {
        $m = Select-String -Path $pyFile -Pattern $vs.codePattern | Select-Object -First 1
        if ($m -and $m.Matches.Groups.Count -gt 1) { $pyVer = $m.Matches.Groups[1].Value }
    }
    $txtFile = Join-Path $AppRoot ($vs.txtFile -replace '/', '\')
    $txtVer = $null
    if (Test-Path -LiteralPath $txtFile) {
        $m = Select-String -Path $txtFile -Pattern $vs.txtPattern | Select-Object -First 1
        if ($m -and $m.Matches.Groups.Count -gt 1) { $txtVer = $m.Matches.Groups[1].Value }
    }
    if (-not $pyVer) { Add-Fix "Version - $($vs.codeFile) - missing version" }
    elseif (-not $txtVer) { Add-Fix "Version - $($vs.txtFile) - missing" }
    elseif ($pyVer -ne $txtVer) { Add-Fix "Version mismatch - $pyVer vs $txtVer" }
    if ($pyVer -and $vs.distTxtFile) {
        $distFile = Join-Path $AppRoot ($vs.distTxtFile -replace '/', '\')
        if (Test-Path -LiteralPath $distFile) {
            $dm = Select-String -Path $distFile -Pattern $vs.distTxtPattern | Select-Object -First 1
            if ($dm -and $dm.Matches.Groups.Count -gt 1) {
                $distVer = $dm.Matches.Groups[1].Value
                if ($distVer -ne $pyVer) { Add-Fix "Dist version - $($vs.distTxtFile) is $distVer, code is $pyVer" }
            }
        }
    }
}

Stop-AuditPhase 'version_sync'

# --- Tests ---
Start-AuditPhase 'tests'
if (-not $FinalizeOnly -and -not $SkipTests -and $cfg.tests -and $cfg.tests.script) {
    # Which entry point this OS runs. tests.script is the Windows one; tests.scriptPosix is the
    # non-Windows one, declared rather than inferred - a .sh guessed from the .bat's name is a
    # second runner nobody verified, and the audit's test-pass proof gates finalize, so the phase
    # must never be quietly satisfied by something other than the project's real suite.
    $testRel = $cfg.tests.script
    if (-not (Test-PackIsWindows) -and $cfg.tests.scriptPosix) { $testRel = $cfg.tests.scriptPosix }
    $testScript = Join-Path $AppRoot $testRel
    $runner = Get-PackScriptRunner -ScriptPath $testScript
    if (-not (Test-Path -LiteralPath $testScript)) {
        Add-Fix "Missing test script - $testRel"
    } elseif ($runner.reason) {
        # A Fix, never a skip: skipping would leave the phase silent on this OS while finalize still
        # asks for a test-pass proof, and the audit would report clean without having run a test.
        $key = if (Test-PackIsWindows) { 'tests.script' } else { 'tests.scriptPosix' }
        Add-Fix ("Tests cannot run on this OS - $testRel : $($runner.reason). " +
            "Declare a runnable entry point in AUDIT.config.json under $key (a .ps1 implementation runs on every OS).")
    } else {
        if ($cfg.tests.env) {
            $cfg.tests.env.PSObject.Properties | ForEach-Object { Set-Item -Path "Env:$($_.Name)" -Value $_.Value }
        }
        $env:PYTHONPATH = $AppRoot
        # Without this the audit's own test run leaves __pycache__ behind, which the cruft check
        # then reports - a Fix item the audit creates for itself and the user can never clear.
        $env:PYTHONDONTWRITEBYTECODE = '1'
        $testLog = Join-Path (Get-PackTempDir) "audit_tests_$PID.log"
        Write-Host "Running $testRel (via $($runner.label)) ..."
        # Redirection belongs to the host shell, so the log is captured here instead of being
        # appended to the command line - `> file 2>&1` inside an -ArgumentList is cmd.exe syntax and
        # would arrive at bash or pwsh as literal arguments.
        $runArgs = @($runner.prefix) + @($testScript) + @($runner.suffix) | Where-Object { $null -ne $_ -and $_ -ne '' }
        $p = Start-Process -FilePath $runner.exe -ArgumentList $runArgs -WorkingDirectory $AppRoot `
            -Wait -PassThru -NoNewWindow -RedirectStandardOutput $testLog -RedirectStandardError "$testLog.err"
        if (Test-Path -LiteralPath "$testLog.err") {
            $errText = Get-Content -LiteralPath "$testLog.err" -Raw -ErrorAction SilentlyContinue
            if ($errText -and $errText.Trim()) { Add-Content -LiteralPath $testLog -Value $errText }
            Remove-Item -LiteralPath "$testLog.err" -Force -ErrorAction SilentlyContinue
        }
        if ($p.ExitCode -ne 0) { Add-Fix "Tests failed - $testRel exit $($p.ExitCode) - see $testLog" }
        else {
            Write-Host 'Tests: OK'
            $testsPassed = $true
            # Stamp the moment the tests passed, not the end of the run. Stamping it at the end put
            # testsPassedAt *after* the semantic template this same run writes, so an auditor who
            # filled that template in place was told the deep scan predated the test pass - a false
            # stale signal on the documented workflow.
            $script:TestsPassedAt = (Get-Date).ToUniversalTime().ToString('o')
            if (-not $script:TestsGitHead) { $script:TestsGitHead = Get-TestsProofHead $RepoRoot $AppRoot $cfg }
        }
    }
} elseif ($FinalizeOnly) {
    # testsPassed set from manifest gate
} elseif (-not $SkipTests) { Write-Host 'Tests: skipped (no test script in config)' }
Stop-AuditPhase 'tests'

Start-AuditPhase 'machine_checks'
if ($cfg.requiredPaths) {
    foreach ($rel in @($cfg.requiredPaths.app)) {
        $p = Join-Path $AppRoot ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $p)) { Add-Fix "Missing path - $appPrefix$(Format-PackDisplayPath $rel)" }
    }
    foreach ($rel in @($cfg.requiredPaths.repo)) {
        $p = Join-Path $RepoRoot ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $p)) { Add-Fix "Missing path - $rel" }
    }
}

# --- Stale docs ---
if ($cfg.staleDocs -and $cfg.staleDocs.pattern -and ($cfg.staleDocs.pattern.ToString().Trim())) {
    $mdFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    if ($cfg.staleDocs.scanRepoMd) {
        Get-ChildItem -LiteralPath $RepoRoot -Filter '*.md' -File -ErrorAction SilentlyContinue | ForEach-Object { $mdFiles.Add($_) }
    }
    if ($cfg.staleDocs.scanAppDocsMd) {
        $docsDir = Join-Path $AppRoot 'docs'
        if (Test-Path -LiteralPath $docsDir) {
            Get-ChildItem -LiteralPath $docsDir -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $mdFiles.Add($_) }
        }
    }
    foreach ($extra in @($cfg.staleDocs.extraFiles)) {
        $p = if ($extra -eq 'AGENTS.md') { Join-Path $AppRoot $extra } else { Join-Path $RepoRoot $extra }
        if (Test-Path -LiteralPath $p) { $mdFiles.Add((Get-Item -LiteralPath $p)) }
    }
    $excludeFiles = @($cfg.staleDocs.excludeFiles)
    $excludeDirs = @($cfg.staleDocs.excludeDirs)
    $seen = @{}
    foreach ($md in ($mdFiles | Sort-Object FullName)) {
        if ($seen[$md.FullName]) { continue }
        $seen[$md.FullName] = $true
        if ($excludeFiles -contains $md.Name) { continue }
        $skip = $false
        foreach ($ed in $excludeDirs) { if ($md.FullName -match [regex]::Escape($ed)) { $skip = $true; break } }
        if ($skip) { continue }
        if (Select-String -Path $md.FullName -Pattern $cfg.staleDocs.pattern -Quiet) {
            $rel = Get-PackRelPathKey -Path $md.FullName -Root $RepoRoot
            Add-Fix "Stale doc - $rel - matches stale pattern"
        }
    }
}

# --- Cruft ---
if ($cfg.cruft) {
    foreach ($bad in @($cfg.cruft.dirs)) {
        $p = Join-Path $AppRoot ($bad -replace '/', '\')
        if (Test-Path -LiteralPath $p) { Add-Fix "Build cruft - $appPrefix$bad - delete" }
    }
    foreach ($glob in @($cfg.cruft.globFiles)) {
        if (Get-ChildItem -LiteralPath $AppRoot -Filter $glob -File -ErrorAction SilentlyContinue) {
            Add-Fix "Stale files - $appPrefix$glob - delete"
        }
    }
    $logCount = 0
    foreach ($ld in @($cfg.cruft.logDirs)) {
        $base = if ($ld -eq 'repo') { $RepoRoot } elseif ($ld -eq 'app') { $AppRoot } else { Join-Path $AppRoot $ld }
        if (Test-Path -LiteralPath $base) {
            $logCount += @(Get-ChildItem -LiteralPath $base -Filter '*.log' -File -ErrorAction SilentlyContinue).Count
        }
    }
    if ($logCount -gt 0) { Add-Fix "Stale logs - delete $logCount log file(s)" }
    $cacheEx = if ($cfg.cruft.cacheExcludeRegex) { $cfg.cruft.cacheExcludeRegex } else { '\\tests\\' }
    $pycache = @(Get-ChildItem -LiteralPath $AppRoot -Directory -Recurse -Filter '__pycache__' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $cacheEx })
    if ($pycache.Count -gt 0) { Add-Fix "Cache cruft - $($pycache.Count) __pycache__ dir(s) - delete" }
    if (Test-Path -LiteralPath (Join-Path $AppRoot '.pytest_cache')) { Add-Fix "Cache cruft - $appPrefix.pytest_cache - delete" }
}

# --- Layout hygiene (Section B) ---
# Cruft above answers "delete this"; it says nothing about whether the tree is understandable. A
# project can pass every delete check and still have three folders whose names do not say which is
# build output, which is runtime user data, and which is a duplicate release copy. Those are Improve
# lines - the audit reports them, the user decides. Nothing here deletes or prompts.
$script:LayoutImproves = [System.Collections.Generic.List[string]]::new()
function Add-LayoutImprove([string]$m) {
    if (-not $script:LayoutImproves.Contains($m)) { [void]$script:LayoutImproves.Add($m) }
    Add-Improve $m
}
function Add-LayoutFix([string]$m) {
    if (-not $script:LayoutImproves.Contains($m)) { [void]$script:LayoutImproves.Add($m) }
    Add-Fix $m
}

if ($cfg.layoutPolicy -and $cfg.layoutPolicy.enabled) {
    $lp = $cfg.layoutPolicy

    if ($lp.glossaryDoc -and $lp.glossaryDoc.ToString().Trim()) {
        $glossaryRel = $lp.glossaryDoc.ToString() -replace '/', '\'
        $glossaryPath = Join-Path $RepoRoot $glossaryRel
        if (-not (Test-Path -LiteralPath $glossaryPath)) {
            Add-LayoutImprove "Layout - $glossaryRel missing - add a folder glossary (build output vs runtime data vs archive)"
        } elseif ($lp.glossaryHeading -and $lp.glossaryHeading.ToString().Trim()) {
            $heading = $lp.glossaryHeading.ToString()
            $glossaryText = Get-Content -LiteralPath $glossaryPath -Raw -Encoding UTF8
            if ($glossaryText -notmatch [regex]::Escape($heading)) {
                Add-LayoutImprove "Layout - $glossaryRel has no '$heading' section - document what each folder is for"
            }
        }
    }

    if ($lp.forbiddenInRepoStableCopy -and $lp.forbiddenInRepoStableCopy.ToString().Trim()) {
        $dupRel = $lp.forbiddenInRepoStableCopy.ToString() -replace '/', '\'
        if (Test-Path -LiteralPath (Join-Path $AppRoot $dupRel)) {
            Add-LayoutImprove "Layout - duplicate stable copy in repo - $appPrefix$dupRel - policy prefers an external release archive"
        }
    }

    if ($lp.buildOutputDir -and $lp.buildOutputDir.ToString().Trim()) {
        $buildRel = $lp.buildOutputDir.ToString() -replace '/', '\'
        $buildPath = Join-Path $AppRoot $buildRel
        if (Test-Path -LiteralPath $buildPath) {
            # One dirname in two places (beside the source tree and beside the shipped binary) reads
            # as two products to anyone who did not build it.
            if ($lp.portableDataDirname -and $lp.portableDataDirname.ToString().Trim()) {
                $dataName = $lp.portableDataDirname.ToString() -replace '/', '\'
                $besideSource = Test-Path -LiteralPath (Join-Path $AppRoot $dataName)
                $besideBinary = Test-Path -LiteralPath (Join-Path $buildPath $dataName)
                if ($besideSource -and $besideBinary) {
                    Add-LayoutImprove "Layout - $dataName exists both beside the source tree and inside $buildRel - name or document which is runtime user data"
                }
            }
        }
    }

    # Ephemeral dirs are normal after a build. Worth naming so nobody treats a rebuild as a
    # regression - but only Fix when the build output is actually committed.
    foreach ($eph in @($lp.ephemeralDirs)) {
        if (-not $eph) { continue }
        $ephRel = $eph.ToString() -replace '/', '\'
        $ephPath = Join-Path $AppRoot $ephRel
        if (-not (Test-Path -LiteralPath $ephPath)) { continue }
        $tracked = $false
        # Same correction as Get-RepoGitHead (WQ-461): nothing can be "committed to git" in a tree
        # git does not recognise, and a leftover .git directory made this ask anyway.
        if (Test-PackGitRepo -Root $RepoRoot) {
            $prev = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $lsOut = & git -C $RepoRoot ls-files --error-unmatch -- "$ephRel/*" 2>$null
                $tracked = ($LASTEXITCODE -eq 0 -and $lsOut)
            } catch { $tracked = $false } finally { $ErrorActionPreference = $prev }
        }
        if ($tracked) {
            Add-LayoutFix "Layout - $appPrefix$ephRel is committed to git - build output belongs in .gitignore"
        } else {
            Add-LayoutImprove "Layout - $appPrefix$ephRel present (expected after a build) - document as ephemeral or delete before release"
        }
    }

    # A script that recreates what the checklist forbids means one of the two is wrong.
    foreach ($cs in @($lp.contradictionScripts)) {
        if (-not $cs -or -not $cs.script) { continue }
        $scriptRel = $cs.script.ToString() -replace '/', '\'
        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $scriptRel))) { continue }
        $target = if ($cs.createsForbiddenDir) { $cs.createsForbiddenDir.ToString() } else { '' }
        $msg = if ($cs.message) { $cs.message.ToString() } else { "Script recreates a path the layout policy forbids$(if ($target) { ": $target" })" }
        $line = "Layout - $scriptRel - $msg"
        if ("$($cs.flag)" -eq 'Fix') { Add-LayoutFix $line } else { Add-LayoutImprove $line }
    }
}

# --- Secrets ---
if ($cfg.secretsScan -and $cfg.secretsScan.enabled) {
    $secretPat = '(?i)(api[_-]?key\s*[:=]|password\s*[:=]\s*[''"][^''"]+|BEGIN (RSA |OPENSSH )?PRIVATE KEY)'
    $extPat = ($cfg.secretsScan.extensions | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $skipPat = if ($cfg.secretsScan.excludePathRegex) { $cfg.secretsScan.excludePathRegex } else { '\\tests\\fixtures\\' }
    Get-ChildItem -LiteralPath $AppRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match "($extPat)$" -and $_.FullName -notmatch $skipPat } |
        ForEach-Object {
            if (Select-String -Path $_.FullName -Pattern $secretPat -Quiet) {
                $rel = Get-PackRelPathKey -Path $_.FullName -Root $RepoRoot
                Add-Fix "Possible secret - $rel - review"
            }
        }
    Get-ChildItem -LiteralPath $RepoRoot -Filter '.env' -File -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Fix "Committed env file - $($_.Name) - remove or gitignore"
    }
}

# --- Obsolete paths ---
if ($cfg.obsoletePaths) {
    foreach ($rel in @($cfg.obsoletePaths.repo)) {
        $p = Join-Path $RepoRoot ($rel -replace '/', '\')
        if (Test-Path -LiteralPath $p) { Add-Improve "Obsolete - $rel - remove or archive" }
    }
    if ($cfg.obsoletePaths.desktopFolder) {
        # OneDrive-redirected Desktop is a Windows arrangement, but the Join-Path is not guarded, so
        # $env:USERPROFILE being $null off Windows threw here for any project whose config sets
        # desktopFolder - a config-gated crash, which is why no Linux run had hit it.
        $desk = Join-Path (Get-PackHomeDir) 'OneDrive/Desktop'
        if (-not (Test-Path -LiteralPath $desk)) { $desk = [Environment]::GetFolderPath('Desktop') }
        $old = Join-Path $desk $cfg.obsoletePaths.desktopFolder
        if (Test-Path -LiteralPath $old) { Add-Fix "Old folder - Desktop\$($cfg.obsoletePaths.desktopFolder) still exists" }
    }
}

# --- Forbidden audit artifacts ---
$packRoot = Get-PackRoot -PreferAppRoot $AppRoot
# The manifest owns this list. There used to be a copy of it here as a fallback, which meant a pack
# whose manifest could not be read went on checking a snapshot of the list from whenever that literal
# was last edited - and reported a clean audit either way. A stale answer presented as a current one is
# worse than a stated gap, so an unreadable manifest is now visible in the report.
$forbidden = @()
$forbiddenSource = ''
if ($packRoot) {
    $manifestPath = Join-Path $packRoot 'pack/audit/manifest.json'
    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($manifest.forbiddenArtifacts) {
            $forbidden = @($manifest.forbiddenArtifacts)
            $forbiddenSource = $manifestPath
        }
    }
}
if (-not $forbiddenSource) {
    Add-Fix ('Forbidden-artifact check skipped - no readable pack manifest' +
        $(if ($packRoot) { " at $packRoot" } else { ' (pack root not resolved)' }))
}
foreach ($or in $forbidden) {
    if ($or -match '\.mdc$') {
        $p = Join-Path $AppRoot ".cursor/rules/$or"
        if (Test-Path -LiteralPath $p) { Add-Fix "Old audit rule - app\.cursor\rules\$or - delete" }
    } else {
        $p = Join-Path $AppRoot $or
        if (Test-Path -LiteralPath $p) { Add-Fix "Obsolete - $or - delete" }
    }
}
Get-ChildItem -LiteralPath (Join-Path $AppRoot 'docs') -Filter 'CODE_AUDIT*.md' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -notmatch 'audit_archive' } |
    ForEach-Object { Add-Fix "Old audit doc - $($_.Name) - move to audit_archive" }

# --- Agent context freshness ---
# The refresh brief only helps if someone learns it is stale, and until now the only way to find out
# was to run the refresh - which is the thing you would have needed the warning to tell you to do.
# The audit is where users and agents already look, so the staleness lands here. The remediation is
# addressed to the agent on purpose: it should offer to run Refresh-AgentContext.cmd and let the user
# approve the run, rather than handing over a command to type. Improve, not Fix - a stale stamp breaks
# nothing, and it clears itself on the next refresh. Silent when the project has no stamp at all.
if ($manifest -and $manifest.version) {
    $ctxPath = Join-Path $AppRoot 'docs/AGENT_CONTEXT.json'
    if (Test-Path -LiteralPath $ctxPath) {
        try {
            $ctx = Get-Content -LiteralPath $ctxPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $stamped = $ctx.auditEngineVersion
            if (-not $stamped) {
                Add-Improve "Agent context never refreshed - docs\AGENT_CONTEXT.json is still the bootstrap stub - agent: offer to run $(Get-PackEntryPoint 'Refresh-AgentContext') for this project, then read docs\AGENT_REFRESH.md"
            } elseif ($stamped -ne $manifest.version) {
                Add-Improve "Agent context stale - stamped $stamped, audit engine is $($manifest.version) - agent: offer to run $(Get-PackEntryPoint 'Refresh-AgentContext') for this project, then read docs\AGENT_REFRESH.md"
            }
        } catch {
            Add-Improve "Agent context unreadable - docs\AGENT_CONTEXT.json did not parse - agent: offer to run $(Get-PackEntryPoint 'Refresh-AgentContext') to regenerate it"
        }
    }
}

# --- Cursor session hook (WQ-435) ---
# A repair nobody knows to run is not a repair path, so the project's own audit is what reports it. Fix
# rather than Improve: a pre-2.22.63 hook hangs any host that leaves stdin open, and one such run cost
# sixteen minutes of a wedged audit. -AuditMode writes nothing; the remedy is addressed to the agent so
# it offers the run instead of handing over a command to type.
if ($packRoot) {
    $hookRepair = Join-Path $packRoot 'pack/scripts/repair-project-hooks.ps1'
    if (Test-Path -LiteralPath $hookRepair) {
        try {
            $hrLines = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $hookRepair -ProjectRoot $AppRoot -AuditMode 2>&1
            foreach ($line in @($hrLines)) {
                $t = [string]$line
                if ($t -match '^\[FIX\]\s*(.+)') { Add-Fix $Matches[1].Trim() }
                elseif ($t -match '^\[IMPROVE\]\s*(.+)') { Add-Improve $Matches[1].Trim() }
            }
        } catch {
            Add-Improve "Cursor hook check failed - $($_.Exception.Message)"
        }
    }
}

# --- POSIX entry-point twins (WQ-450) ---
# Fix rather than Improve, and reported by the project's own audit rather than left to a command
# nobody runs: a project bootstrapped before 2.22.77 is told by the lines above to run entry points it
# does not have, so the audit cannot be finished on the host reading it. The check is silent on a
# project that never took an entry point and on Windows, where a missing .sh costs nothing today - but
# it still reports one, because the same folder gets opened on Linux by somebody else.
if ($packRoot) {
    $scriptsRepair = Join-Path $packRoot 'pack/scripts/repair-project-scripts.ps1'
    if (Test-Path -LiteralPath $scriptsRepair) {
        try {
            $srLines = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $scriptsRepair -ProjectRoot $AppRoot -AuditMode 2>&1
            foreach ($line in @($srLines)) {
                $t = [string]$line
                if ($t -match '^\[FIX\]\s*(.+)') { Add-Fix $Matches[1].Trim() }
                elseif ($t -match '^\[IMPROVE\]\s*(.+)') { Add-Improve $Matches[1].Trim() }
            }
        } catch {
            Add-Improve "POSIX entry-point twin check failed - $($_.Exception.Message)"
        }
    }
}

# --- Agent handoffs (layout + completion; never auto-delete) ---
if ($packRoot) {
    $handoffScript = Join-Path $packRoot 'pack/scripts/verify-agent-handoffs.ps1'
    if (Test-Path -LiteralPath $handoffScript) {
        try {
            $hoLines = Invoke-PackScript -PassOutput -NoProfile -ScriptPath $handoffScript -ProjectRoot $AppRoot -AuditMode 2>&1
            foreach ($line in @($hoLines)) {
                $t = [string]$line
                if ($t -match '^\[FIX\]\s*(.+)') { Add-Fix $Matches[1].Trim() }
                elseif ($t -match '^\[IMPROVE\]\s*(.+)') { Add-Improve $Matches[1].Trim() }
            }
        } catch {
            Add-Improve "Handoff verify failed - $($_.Exception.Message)"
        }
    }
}

# --- Stables ---
if ($cfg.stables -and $cfg.stables.enabled) {
    $desk = Join-Path (Get-PackHomeDir) 'OneDrive/Desktop'
    if (-not (Test-Path -LiteralPath $desk)) { $desk = [Environment]::GetFolderPath('Desktop') }
    $stableRoot = Join-Path $desk $cfg.stables.desktopFolder
    $expected = @($cfg.stables.expected)
    if ((Test-Path -LiteralPath $stableRoot) -and $expected.Count -gt 0) {
        $found = @(Get-ChildItem -LiteralPath $stableRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        if ($found.Count -ne $expected.Count) { Add-Fix "Stable count - expected $($expected.Count), found $($found.Count)" }
        else {
            foreach ($e in $expected) {
                if ($e -notin $found) { Add-Fix "Stable missing - $e" }
            }
        }
    }
}

# --- Domain map ---
if ($cfg.domainMap) {
    $dm = $cfg.domainMap
    $auditMd = Join-Path $AppRoot ($dm.auditMd -replace '/', '\')
    $scanDir = Join-Path $AppRoot ($dm.scanDir -replace '/', '\')
    if (-not (Test-Path -LiteralPath $auditMd)) {
        Add-Fix "Domain map - missing $($dm.auditMd)"
    } else {
        # -Encoding UTF8 is required, not cosmetic: without it PowerShell 5.1 reads a BOM-less UTF-8
        # AUDIT.md as ANSI, so every em dash became three characters and that corruption was copied
        # verbatim into docs\.audit_agent_manifest.json - the file the next agent reads as its brief.
        $allLines = Get-Content -LiteralPath $auditMd -Encoding UTF8
        $heading = if ($dm.sectionHeading) { $dm.sectionHeading } else { '## Domain map' }
        # The line must START with the heading. A plain substring match also hit prose that merely
        # mentions "## Domain map" mid-sentence (the AUDIT.md template does), so the chunk stopped
        # at the next heading and the real table below was never read - every module then looked
        # unmapped. Trailing text stays allowed: "## Domain map (example - replace ...)".
        $headingRe = '^\s*' + [regex]::Escape($heading)
        $startIdx = -1
        for ($i = 0; $i -lt $allLines.Count; $i++) {
            if ($allLines[$i] -match $headingRe) { $startIdx = $i; break }
        }
        $domainText = if ($startIdx -ge 0) {
            $chunk = @()
            for ($j = $startIdx; $j -lt $allLines.Count; $j++) {
                if ($j -gt $startIdx -and $allLines[$j] -match '^## ') { break }
                $chunk += $allLines[$j]
            }
            $chunk -join "`n"
        } else { '' }
        if (-not $domainText) { Add-Fix "Domain map - missing section $heading in $($dm.auditMd)" }
        else {
            $exclude = @($dm.excludeModules)
            $wildcards = @($dm.wildcardPatterns)
            Get-ChildItem -LiteralPath $scanDir -Filter $dm.scanGlob -File -ErrorAction SilentlyContinue | ForEach-Object {
                $name = $_.Name
                if ($exclude -contains $name) { return }
                $covered = $domainText.Contains($name)
                if (-not $covered) {
                    foreach ($w in $wildcards) {
                        $pat = '^' + ($w -replace '\*', '.*') + '$'
                        if ($name -match $pat) { $covered = $true; break }
                    }
                }
                if (-not $covered) {
                    foreach ($wm in [regex]::Matches($domainText, '`([a-z_]+\*[^`]*\.py)`')) {
                        $pat = '^' + ($wm.Groups[1].Value -replace '\*', '.*') + '$'
                        if ($name -match $pat) { $covered = $true; break }
                    }
                }
                if (-not $covered) {
                    Add-Fix "Domain map - $name not in domain map - add row in $($dm.auditMd)"
                }
            }
        }
    }
}

# --- Project required files (manifest) ---
if ($packRoot) {
    $manifest = Get-Content -LiteralPath (Join-Path $packRoot 'pack/audit/manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $reqBase = $RepoRoot
    $layout = $manifest.projectRequired.flatLayout
    if (Test-Path -LiteralPath (Join-Path $RepoRoot 'app/docs/AUDIT.md')) {
        $layout = $manifest.projectRequired.appLayout
    } elseif (Test-Path -LiteralPath (Join-Path $AppRoot 'docs/AUDIT.md')) {
        $reqBase = $AppRoot
    }
    $layout.PSObject.Properties | ForEach-Object {
        $full = Join-Path $reqBase ($_.Value -replace '/', '\')
        if (-not (Test-Path -LiteralPath $full)) {
            Add-Fix "Missing audit file - $($_.Value)"
        }
    }
}

Stop-AuditPhase 'machine_checks'

# --- Code checks (sections D-K: import smoke, static patterns, section tests) ---
Start-AuditPhase 'code_checks'
$codeScript = $null
if ($cfg.codeChecks) {
    if (-not $packRoot) { $packRoot = Get-PackRoot -PreferAppRoot $AppRoot }
    $codeScript = if ($packRoot) { Join-Path $packRoot 'pack/scripts/audit_code_checks.py' } else { $null }
    if (-not $codeScript -or -not (Test-Path -LiteralPath $codeScript)) {
        Add-Fix 'Code checks - audit_code_checks.py missing - reinstall starter pack'
    } else {
        Write-Host 'Running audit_code_checks.py ...'
        # Do not pass a repo root here. Python resolves it from AppRoot by the same rule as
        # run_audit.ps1.template, and it must keep doing so: a bespoke wrapper (the behavior
        # fixture) declares an outer RepoRoot, and forcing that on Python would tie the fixture's
        # test-pass proof to the pack's git HEAD, where edits to fixture code stop invalidating it.
        # Behavior step 23 asserts the two layers agree on a generated project.
        # Invoke-PackPython supplies the interpreter and its own switches; the launcher's -3 used to
        # live here, back when the call was `py -3`. It survived the migration because it sat in a
        # variable rather than at the call site, and `py -3 -3 script.py` reaches python as an unknown
        # option - which killed the code checks, and with them the agent manifest, on both hosts.
        $codeArgs = @($codeScript, $AppRoot)
        if ($testsPassed) { $codeArgs += '--full-tests-ran' }
        if ($SkipTests) { $codeArgs += '--lightweight' }
        $jsonOut = Invoke-PackPython @codeArgs 2>&1 | Out-String
        $jsonBlock = Get-JsonFromOutput $jsonOut
        try {
            if (-not $jsonBlock) { throw 'no JSON object in output' }
            $codeResult = $jsonBlock | ConvertFrom-Json
            foreach ($f in @($codeResult.fixes)) { Add-Fix $f }
            foreach ($im in @($codeResult.improve)) { Add-Improve $im }
            $script:RequiredSectionCount = @($codeResult.requiredSections).Count
            $script:CodeMachineFixes = @{}
            if ($codeResult.machineFixesBySection) {
                $codeResult.machineFixesBySection.PSObject.Properties | ForEach-Object {
                    $script:CodeMachineFixes[$_.Name] = @($_.Value)
                }
            }
            $manifestOut = Join-Path $AppRoot 'docs/.audit_agent_manifest.json'
            $manifestObj = [ordered]@{
                requiredSections         = @($codeResult.requiredSections)
                semanticReportFile       = $codeResult.semanticReportFile
                machineCoverage          = $codeResult.machineCoverage
                agentSections            = $codeResult.agentSections
                machineClosed            = $codeResult.machineClosed
                machineFixesBySection    = $codeResult.machineFixesBySection
                machineSectionsWithFixes = $codeResult.machineSectionsWithFixes
                auditGateFixes           = @()
                generatedAt              = (Get-Date).ToUniversalTime().ToString('o')
            }
            if ($script:TestsGitHead) { $manifestObj['testsGitHead'] = $script:TestsGitHead }
            if ($script:TestsPassedAt) { $manifestObj['testsPassedAt'] = $script:TestsPassedAt }
            Write-Utf8JsonFile $manifestOut ($manifestObj | ConvertTo-Json -Depth 12)
            Write-Host 'Agent manifest: docs\.audit_agent_manifest.json (all sections + semantic report path)'
        } catch {
            Add-Fix "Code checks - audit_code_checks.py failed: $_"
            if ($jsonOut) { Write-Host $jsonOut }
        }
    }
}

Stop-AuditPhase 'code_checks'

# --- Semantic report verify (required for complete audit) ---
Start-AuditPhase 'semantic'
$zoneBPublishTree = Test-PackPublishZoneBTree -Root $AppRoot
$zoneBAttestation = if ($zoneBPublishTree) {
    if ($null -ne $script:ZoneBAttestationAtStart) { $script:ZoneBAttestationAtStart }
    else { Test-PackPublishAttestation -Root $AppRoot }
} else { $null }
if ($zoneBPublishTree -and $zoneBAttestation.Valid) {
    Write-Host "[OK] Zone B publish tree - semantic review attested at publish (tree fingerprint matches)"
}
if ($testsPassed -and -not $SkipTests -and $cfg.codeChecks) {
    $requireSemantic = $true
    if ($cfg.codeChecks.PSObject.Properties.Name -contains 'semanticReportRequiredInRunAudit') {
        $requireSemantic = [bool]$cfg.codeChecks.semanticReportRequiredInRunAudit
    }
    if ($zoneBPublishTree -and $zoneBAttestation.Valid) {
        $requireSemantic = $false
    } elseif ($zoneBPublishTree -and -not $zoneBAttestation.Valid) {
        Add-Fix "Publish attestation - $($zoneBAttestation.Reason)"
        $requireSemantic = $false
    }
    if ($requireSemantic -and $codeScript -and (Test-Path -LiteralPath $codeScript)) {
        $semRel = if ($cfg.codeChecks.semanticReportFile) { $cfg.codeChecks.semanticReportFile } else { 'docs/.audit_semantic_report.json' }
        $semPath = Join-Path $AppRoot ($semRel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $semPath)) {
            Write-Host 'Writing semantic report template (auditor must complete before audit can pass) ...'
            Invoke-PackPython $codeScript $AppRoot --write-semantic-template 2>&1 | Out-Host
        }
        Write-Host 'Running semantic report verify ...'
        $semOut = Invoke-PackPython $codeScript $AppRoot --verify-semantic-report 2>&1 | Out-String
        $semJson = Get-JsonFromOutput $semOut
        try {
            if (-not $semJson) { throw 'no JSON from verify-semantic-report' }
            $semResult = $semJson | ConvertFrom-Json
            $semanticGuidanceShown = $false
            foreach ($f in @($semResult.fixes)) {
                Add-Fix $f
            }
            if (@($semResult.fixes).Count -gt 0 -and -not $semanticGuidanceShown) {
                Write-SemanticNextSteps
                $semanticGuidanceShown = $true
            }
        } catch {
            Add-Fix "Semantic report verify failed - $_"
            if ($semOut) { Write-Host $semOut }
        }
    }
}

Stop-AuditPhase 'semantic'

# --- Sync + legacy verify (verify-audit-system only when semantic + sync gates pass) ---
Start-AuditPhase 'sync_verify'
$semanticIncomplete = Test-SemanticPassIncomplete
$syncBlocked = $false
if ($cfg.syncAndVerify) {
    if ($cfg.syncAndVerify.runSyncVerify) {
        $sync = Join-Path $packRoot 'pack/scripts/sync-audit-system.ps1'
        if (-not $packRoot -or -not (Test-Path -LiteralPath $sync)) {
            Add-Fix 'Audit sync - sync-audit-system.ps1 not found - install starter pack'
            $syncBlocked = $true
        } else {
            $autoFix = $false
            if ($cfg.syncAndVerify.PSObject.Properties.Name -contains 'autoFixDrift') {
                $autoFix = [bool]$cfg.syncAndVerify.autoFixDrift
            }
            Write-Host 'Running sync-audit-system.ps1 -VerifyOnly ...'
            if ($autoFix) {
                Invoke-PackScript -PassOutput -NoProfile -ScriptPath $sync -VerifyOnly -AutoFix -ProjectRoot $RepoRoot | Out-Host
            } else {
                Invoke-PackScript -PassOutput -NoProfile -ScriptPath $sync -VerifyOnly -ProjectRoot $RepoRoot | Out-Host
            }
            if ($LASTEXITCODE -ne 0) {
                Add-Fix "Audit sync drift - run $($appPrefix)$(Get-PackEntryPoint 'scripts/sync_audit_system')"
                $syncBlocked = $true
            } else { Write-Host 'sync-audit-system: OK' }
        }
    }
    if ($cfg.syncAndVerify.runLegacyVerify) {
        if ($semanticIncomplete) {
            Write-Host 'Skipping verify-audit-system.ps1 (semantic pass incomplete - finish semantic report first; verify runs on complete pass).'
            Add-Improve 'Section L - verify-audit-system.ps1 skipped (semantic pass incomplete) - finalize semantic report to run harness checks'
        } elseif ($syncBlocked) {
            Write-Host "Skipping verify-audit-system.ps1 (sync drift - run $(Get-PackEntryPoint 'scripts/sync_audit_system') first)."
            Add-Improve "Section L - verify-audit-system.ps1 skipped (sync drift) - run $(Get-PackEntryPoint 'scripts/sync_audit_system') first"
        } else {
            $verify = Join-Path $packRoot 'pack/scripts/verify-audit-system.ps1'
            if (Test-Path -LiteralPath $verify) {
                # The behavior suite is the pack engine's own test suite, and it bootstraps probe
                # projects inside the pack folder. Auditing a product must not run it: it says
                # nothing about this project, costs ~30s, writes into the pack, and re-enters this
                # script. The engine is still proven here - by its own self-test, below.
                #
                # "Is the repo being audited the pack that supplies this engine?" - not merely
                # "does a manifest.json exist somewhere below it", which also matched a product
                # repo that vendors a pack copy at its root.
                $isPackSelfAudit = $false
                if ($packRoot) {
                    try {
                        $isPackSelfAudit =
                            (Resolve-Path -LiteralPath $RepoRoot).Path -eq (Resolve-Path -LiteralPath $packRoot).Path
                    } catch { $isPackSelfAudit = $false }
                }
                Write-Host 'Running verify-audit-system.ps1 (Section L harness check; independent of product Fix lines) ...'
                # Captured, not piped straight to the host: this failure used to report only that a
                # verify "failed", discarding the child's own [FAIL] lines. When it fired inside the
                # behavior suite - where the child's console output is already swallowed by the
                # harness - there was nothing left to diagnose from, and the same intermittent took
                # four full audit runs to attribute (WQ-463). The output is still printed.
                $vasOut = if ($isPackSelfAudit) {
                    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $verify -ProjectRoot $RepoRoot 2>&1 | Out-String
                } else {
                    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $verify -ProjectRoot $RepoRoot -SkipBehavior 2>&1 | Out-String
                }
                $vasExit = $LASTEXITCODE
                Write-Host $vasOut
                if ($vasExit -ne 0) {
                    $vasDetail = Get-PackChildFailureDetail -Output $vasOut -ExitCode $vasExit
                    if ($isPackSelfAudit) {
                        Add-Fix ('Audit wiring - verify-audit-system.ps1 failed - run sync + verify after audit-system edits' + $vasDetail)
                    } else {
                        # Aimed at the right person: these checks cover the starter pack's own files,
                        # so a product auditor cannot fix them from inside their project.
                        Add-Fix ('Audit wiring - verify-audit-system.ps1 failed against the starter pack itself - run sync-audit-system.ps1 then verify-audit-system.ps1 in the pack folder (not a defect in this project)' + $vasDetail)
                    }
                } else { Write-Host 'verify-audit-system: OK' }
                if (-not $isPackSelfAudit) {
                    $codePy = Join-Path $packRoot 'pack/scripts/audit_code_checks.py'
                    if (Test-Path -LiteralPath $codePy) {
                        Write-Host 'Running audit_code_checks.py --self-test (engine proof for this machine) ...'
                        Invoke-PackPython $codePy --self-test | Out-Host
                        if ($LASTEXITCODE -ne 0) {
                            Add-Fix 'Audit engine - audit_code_checks.py --self-test failed - audit results are not trustworthy on this machine'
                        } else { Write-Host 'audit engine self-test: OK' }
                    }
                }
            }
        }
    }
}

Stop-AuditPhase 'sync_verify'

Write-AuditReport
$manifestOut = Join-Path $AppRoot 'docs/.audit_agent_manifest.json'
# Do not introduce a local $testsPassedAt here: PowerShell variable names are case-insensitive, so
# it IS $script:TestsPassedAt, and resetting it silently discarded the stamp taken when the tests
# passed. FinalizeOnly keeps the value Test-ManifestFinalizeAllowed loaded from the manifest.
if (-not $FinalizeOnly -and -not ($testsPassed -and -not $SkipTests -and $script:TestsGitHead)) {
    $script:TestsPassedAt = ''
}
$machineImproves = @{}
if ($script:LayoutImproves -and $script:LayoutImproves.Count -gt 0) {
    $machineImproves['B'] = @($script:LayoutImproves)
}
Update-ManifestMachineFixes $manifestOut $Fix $script:CodeMachineFixes $script:TestsGitHead $script:TestsPassedAt $machineImproves
if ($Fix.Count -eq 0 -and $codeScript -and (Test-Path -LiteralPath $codeScript)) {
    Invoke-PackPython $codeScript $AppRoot --write-audit-receipt 2>&1 | Out-Null
}
if ($Fix.Count -gt 0) {
    Write-AuditTimingLog 1 $projectLabel
    exit 1
}
Write-AuditTimingLog 0 $projectLabel
exit 0
