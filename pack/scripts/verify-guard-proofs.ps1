#Requires -Version 5.1
<#
.SYNOPSIS
  Proves the behavior suite's guards are able to fail, by breaking what they guard (WQ-443 Phase 4).

.DESCRIPTION
  Maintainer script, deliberately NOT part of `run_audit.cmd`: each entry costs a full suite run, and
  the audit already runs the suite once. Plan: `docs/GUARD_PROOF_PLAN.md`.

  For every `mutation` entry in `pack/audit/behavior-controls.json`:

    1. copy the pack to a disposable tree
    2. apply the spec there - `replace` needs exactly one occurrence, `create` needs the file to be
       absent and `delete` needs it present (a guard whose subject is a file's presence or absence
       cannot be broken by editing text)
    3. run the suite in the copy with `-ResultsPath`
    4. require every step in `expectFailIn` to have reported a failure
    5. discard the copy

  Two design points that are not incidental.

  **Never the live tree.** A mutation whose restore path fails would leave a defect in the pack that
  is indistinguishable from a real one, and the restore path is the code most likely to be wrong the
  first time it runs. This pack also keeps no version control by decision (WQ-459), so there is
  nothing to restore from. Copies cost minutes; the alternative costs the checkout.

  **A green baseline first.** Without it, a copy that fails for an unrelated reason - a missing tool,
  an environment difference - would make every mutation look proven while proving nothing. The
  baseline is the control on the runner itself.

.PARAMETER Only
  Prove just these steps instead of every mutation entry. Takes a list, because a retrofit batch
  otherwise pays a full suite run for every step already proven in an earlier release.

  Strings, not integers, and split here rather than by PowerShell. Under `-File` every argument
  arrives as text, and `[int[]]'4,7'` does not fail - it parses as **47**, because the comma reads as
  a digit-group separator. A run asked for steps 4 and 7 proved step 47 instead and exited 0, which
  is this repo's own defect shape: a tool reporting success for work nobody requested. Multi-digit
  pairs were caught only by luck, since '15,18' happens to make 1518 and no step has that number.

.PARAMETER SkipBaseline
  Skip the unmutated run. Saves one suite run when you have just seen a green suite, and weakens
  every result in exchange: a failure can no longer be attributed to the mutation rather than to the
  copy. Reported in the output when used.

.PARAMETER KeepWork
  Leave the disposable trees in place for inspection.

.PARAMETER TimeoutMinutes
  How long one suite run may take before it is killed and recorded as hung. A mutation does not only
  make a guard fail - it can make the guarded code *hang*, and an unbounded runner then waits on it
  forever. The step 38 proof did exactly that: restoring an unbounded stdin read left a run sitting
  for half an hour with no output, which is indistinguishable from slow progress until someone looks.
  A full suite takes two to three minutes.

.PARAMETER FailFast
  Exit on the first failed proof, profile drift, or pack-tree change during the run. Use with
  `-Only` to fix one step at a time (~2-3 min per failure) instead of running all mutations before
  learning the environment moved. Tree drift is a warning without `-FailFast`; with it, drift fails.
#>
param(
    [string]$PackRoot = '',
    [string[]]$Only = @(),
    [switch]$SkipBaseline,
    [switch]$KeepWork,
    [switch]$FailFast,
    [int]$TimeoutMinutes = 12
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')
. (Join-Path $PSScriptRoot 'verify-lib.ps1')

if (-not $PackRoot) { $PackRoot = Get-AgentStarterPackRoot }
if (-not $PackRoot -or -not (Test-Path -LiteralPath $PackRoot)) {
    Write-Host '[FAIL] pack root not found'
    exit 1
}
$PackRoot = (Resolve-Path -LiteralPath $PackRoot).Path

$fail = 0
$script:installStart = ''
$script:startStamp = ''
$script:GuardProofLockPath = ''
$script:PrevInstallRoot = $env:AGENT_STARTER_PACK_INSTALL_ROOT

function Fail($msg) { Write-Host "[FAIL] $msg"; $script:fail++ }
function Ok($msg) { Write-Host "[OK] $msg" }

function Stop-GuardProofRun([string]$Reason) {
    Fail $Reason
    Write-Host "`nSummary: $fail fail(s)"
    exit 1
}

function Register-GuardProofLock {
    $lockPath = Join-Path (Get-PackTempDir) 'guard-proofs.lock'
    if (Test-Path -LiteralPath $lockPath) {
        try {
            $existing = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $oldPid = [int]$existing.pid
            if ($oldPid -gt 0 -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
                Fail ("another guard proof run is active (PID $oldPid since $($existing.started)) - lock: $lockPath")
                Write-Host "`nSummary: $fail fail(s)"
                exit 1
            }
        } catch { }
    }
    $script:GuardProofLockPath = $lockPath
    $payload = [ordered]@{
        pid      = $PID
        packRoot = $PackRoot
        started  = (Get-Date).ToString('o')
        only     = @($Only)
        failFast = [bool]$FailFast
    }
    Write-Utf8NoBom $lockPath (($payload | ConvertTo-Json -Compress))
    Write-Host "Lock: $lockPath (PID $PID)"
}

function Remove-GuardProofLock {
    if ($script:GuardProofLockPath -and (Test-Path -LiteralPath $script:GuardProofLockPath)) {
        Remove-Item -LiteralPath $script:GuardProofLockPath -Force -ErrorAction SilentlyContinue
    }
}

function Assert-GuardProofEnvironment {
    param([int]$Step = 0)
    $installNow = Get-InstallProfileStamp
    if ($installNow -ne $script:installStart) {
        $where = if ($Step -gt 0) { "after step $Step - " } else { '' }
        Stop-GuardProofRun ("${where}profile install changed ($($script:installStart) -> $installNow) - " +
            'a mutation reached %USERPROFILE%\.cursor\AgentStarterPack\')
    }
    if ($FailFast) {
        $treeNow = Get-TreeStamp
        if ($treeNow -ne $script:startStamp) {
            $where = if ($Step -gt 0) { "after step $Step - " } else { '' }
            Stop-GuardProofRun ("${where}pack tree changed during run ($($script:startStamp) -> $treeNow) - " +
                'freeze edits or use -Only on a quiet tree')
        }
    }
}

$registryPath = Join-Path $PackRoot 'pack\audit\behavior-controls.json'
if (-not (Test-Path -LiteralPath $registryPath)) {
    Fail 'no pack\audit\behavior-controls.json - nothing declares how a step is proven able to fail'
    exit 1
}
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json

$targets = @($registry.steps | Where-Object { $_.status -eq 'mutation' })
if (@($Only).Count -gt 0) {
    $asked = Get-PackRequestedStepNumber -Tokens $Only
    $wanted = @($asked.Numbers)
    if (@($asked.Unreadable).Count -gt 0) {
        Fail "cannot read step number(s) from: $(@($asked.Unreadable) -join ', ')"
        Write-Host "`nSummary: $fail fail(s)"
        exit 1
    }
    $targets = @($targets | Where-Object { $wanted -contains [int]$_.step })
    # A step named on the command line that carries no mutation would otherwise vanish silently, and
    # the run would report success for a step it never touched.
    $absent = @($wanted | Where-Object { @($targets | ForEach-Object { [int]$_.step }) -notcontains $_ })
    if ($absent.Count -gt 0) {
        Fail "asked to prove step(s) $($absent -join ', '), which declare no mutation in the registry"
    }
}

Write-Host "Guard proofs (WQ-443)`nPack: $PackRoot"
Write-Host "Declared mutations: $(@($registry.steps | Where-Object { $_.status -eq 'mutation' }).Count)   selected: $($targets.Count)"
if ($FailFast) { Write-Host 'Mode: FailFast (exit on first proof or environment failure)' }
$exempt = @($registry.steps | Where-Object { $_.status -eq 'exempt' }).Count
Write-Host "Still exempt (no executable proof): $exempt - retrofit backlog, docs/GUARD_PROOF_PLAN.md Phase 5`n"

if ($targets.Count -eq 0) {
    $forWhich = ''
    if (@($Only).Count -gt 0) { $forWhich = " for step(s) $(@($Only) -join ', ')" }
    Fail "no mutation entries selected$forWhich"
    Write-Host "`nSummary: $fail fail(s)"
    exit 1
}

$workRoot = Join-Path (Get-PackTempDir) "guard-proofs-$PID"
$installSandbox = Join-Path $workRoot 'install-sandbox'
New-Item -ItemType Directory -Path $installSandbox -Force | Out-Null
$suiteRel = 'pack\scripts\verify-audit-behavior.ps1'
$startStamp = ''

function New-PackCopy([string]$label) {
    $dest = Join-Path $workRoot $label
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    # Scratch and caches are excluded for the same reason install.ps1 excludes them: they are not the
    # pack, and .tmp in particular is where the suite writes its own probes.
    $skip = @('.tmp', '__pycache__', '.pytest_cache', '.git')
    Get-ChildItem -LiteralPath $PackRoot -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($PackRoot.Length).TrimStart('\', '/')
        foreach ($s in $skip) { if (Test-PackPathHasSegment -Path $rel -Segment @($s)) { return } }
        $target = Join-Path $dest $rel
        if ($_.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
        } else {
            $parent = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        }
    }
    return $dest
}

function Get-TreeStamp {
    # Cheap fingerprint of the live tree: how many files and the newest write time. Enough to notice
    # that the tree changed *during* the run, which is not a hypothetical - the first real execution
    # copied a half-edited tree while a version bump was in progress, and two unrelated steps failed in
    # two of the three mutated runs. Those failures read exactly like collateral from a broad mutation.
    $files = @(Get-ChildItem -LiteralPath $PackRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-PackPathHasSegment -Path $_.FullName.Substring($PackRoot.Length).TrimStart('\', '/') -Segment @('.tmp', '__pycache__', '.pytest_cache', '.git')) })
    $newest = ($files | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
    return "$($files.Count) files, newest $($newest.ToString('yyyy-MM-dd HH:mm:ss'))"
}

function Get-InstallProfileStamp {
    # WQ-481: mutations must not reach the live profile install. The sandbox redirect is set inside
    # each job; this stamp catches a leak if something still wrote there.
    $root = Join-Path $env:USERPROFILE '.cursor\AgentStarterPack'
    if (-not (Test-Path -LiteralPath $root)) { return 'absent' }
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { return 'empty' }
    $newest = ($files | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
    return "$($files.Count) files, newest $($newest.ToString('yyyy-MM-dd HH:mm:ss'))"
}

function Invoke-SuiteIn([string]$root, [string]$resultsPath) {
    $suite = Join-Path $root $suiteRel
    if (-not (Test-Path -LiteralPath $suite)) { return $null }
    $log = "$resultsPath.log"
    $pwshExe = Get-PackPowerShellPath
    # Run in a job for two reasons that both cost a run to learn.
    #
    # A job can be waited on with a timeout, and a plain call cannot. A mutation does not only make a
    # guard report failure - it can make the guarded code hang, and then the runner waits with it.
    # Restoring the session hook's unbounded stdin read did that for half an hour (WQ-473/WQ-475).
    #
    # A job also does not inherit this script's ErrorActionPreference = 'Stop', under which PowerShell
    # turns a native command's stderr into a terminating NativeCommandError. A mutated suite is
    # supposed to complain, and its children complain on stderr: step 1's self-test printed its
    # finding and killed the run at the invoke line, leaving a call stack where a verdict belonged.
    # The verdict is the results file; stderr is evidence, and it lands in $log either way.
    $script:LastRunTimedOut = $false
    $job = Start-Job -ScriptBlock {
        param($exe, $suitePath, $packRoot, $results, $installRoot)
        # WQ-481: the copy is the sync source - redirect install output so AutoFix never reaches
        # %USERPROFILE%\.cursor\AgentStarterPack\ during a mutation proof run.
        $env:AGENT_STARTER_PACK_INSTALL_ROOT = $installRoot
        & $exe -NoProfile -ExecutionPolicy Bypass -File $suitePath -PackRoot $packRoot -ResultsPath $results *>&1
    } -ArgumentList $pwshExe, $suite, $root, $resultsPath, $installSandbox
    $finished = Wait-Job -Job $job -Timeout ($TimeoutMinutes * 60)
    if (-not $finished) {
        $script:LastRunTimedOut = $true
        Stop-Job -Job $job -ErrorAction SilentlyContinue
    }
    Write-Utf8NoBom $log ((Receive-Job -Job $job -ErrorAction SilentlyContinue 2>&1 | Out-String))
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    if ($script:LastRunTimedOut) { return $null }
    if (-not (Test-Path -LiteralPath $resultsPath)) { return $null }
    return (Get-Content -LiteralPath $resultsPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

try {
    Register-GuardProofLock
    # WQ-481: parent process and every suite job share one install sandbox for the whole run.
    $env:AGENT_STARTER_PACK_INSTALL_ROOT = $installSandbox
    $script:startStamp = Get-TreeStamp
    $script:installStart = Get-InstallProfileStamp
    Write-Host "Tree at start: $($script:startStamp)"
    Write-Host "Profile install at start: $($script:installStart)"
    Write-Host "Install sandbox: $installSandbox`n"

    if (-not $SkipBaseline) {
        Write-Host 'Baseline: unmutated copy must be green, or no failure below can be blamed on a mutation.'
        $baseRoot = New-PackCopy 'baseline'
        $baseResults = Invoke-SuiteIn $baseRoot (Join-Path $workRoot 'baseline-results.json')
        if ($script:LastRunTimedOut) {
            Fail "the baseline copy was still running after $TimeoutMinutes minutes and was killed - nothing below can be measured against it"
            Write-Host "`nSummary: $fail fail(s)"
            exit 1
        }
        if ($null -eq $baseResults) {
            Fail 'the baseline copy produced no results file - the runner cannot measure anything'
            Write-Host "`nSummary: $fail fail(s)"
            exit 1
        }
        if ([int]$baseResults.failCount -ne 0) {
            $who = @(@($baseResults.failures) | ForEach-Object { "step $($_.step): $($_.message)" }) -join '; '
            Fail "baseline copy is not green ($([int]$baseResults.failCount) failure(s)) - fix these before trusting any proof: $who"
            Write-Host "`nSummary: $fail fail(s)"
            exit 1
        }
        Ok 'baseline copy is green'
    } else {
        Write-Host '[WARN] -SkipBaseline: a failure below cannot be attributed to the mutation rather than to the copy.'
    }

    foreach ($entry in $targets) {
        $step = [int]$entry.step
        Write-Host "`nStep $step - $($entry.title)"

        $workCopy = New-PackCopy "step$step"
        $specProblems = @(Get-PackMutationSpecProblem -Spec $entry.mutation -Root $workCopy)
        if ($specProblems.Count -gt 0) {
            Fail "step $step mutation cannot be applied - $($specProblems -join '; ')"
            if ($FailFast) { Stop-GuardProofRun "step $step mutation cannot be applied" }
            continue
        }

        $targetFile = Join-Path $workCopy ([string]$entry.mutation.file -replace '/', '\')
        $action = Get-PackMutationAction -Spec $entry.mutation
        if ($action -eq 'create') {
            # A guard that asserts a file is *absent* cannot be broken by editing anything. Step 4
            # keeps an orphan duplicate template out of the pack, and with replace as the only action
            # it was unprovable for a reason about the runner rather than about the step.
            $parent = Split-Path -Parent $targetFile
            if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Write-Utf8NoBom $targetFile ([string]$entry.mutation.content)
            Write-Host "  applied: created $($entry.mutation.file)"
        } elseif ($action -eq 'delete') {
            # The mirror case: a guard whose subject is that a file is *there*. Step 7 requires two
            # agent docs, and a rename is exactly the regression it exists to catch.
            Remove-Item -LiteralPath $targetFile -Force
            Write-Host "  applied: removed $($entry.mutation.file)"
        } else {
            $before = Get-Content -LiteralPath $targetFile -Raw -Encoding UTF8
            $after = $before.Replace([string]$entry.mutation.find, [string]$entry.mutation.replace)
            if ($after -eq $before) {
                # Belt and braces: the spec check above already requires one occurrence, but a replacement
                # that leaves the text identical is the exact failure this whole phase exists to catch.
                Fail "step $step mutation left the file unchanged despite matching - it would prove nothing"
                if ($FailFast) { Stop-GuardProofRun "step $step mutation left the file unchanged" }
                continue
            }
            Write-Utf8NoBom $targetFile $after
            Write-Host "  applied: $($entry.mutation.file)  ('$($entry.mutation.find)' -> '$($entry.mutation.replace)')"
        }

        $results = Invoke-SuiteIn $workCopy (Join-Path $workRoot "step$step-results.json")
        if ($script:LastRunTimedOut) {
            # Not the same as a step that failed to fail. A mutation that hangs the suite has reached
            # the behaviour - it just stopped the run instead of reddening it, and a guard that can
            # hang rather than fail will stop an audit the same way in front of a user.
            Fail "step $step hung: the mutated run was still going after $TimeoutMinutes minutes and was killed - bound whatever it blocked on, then re-run"
            if ($FailFast) { Stop-GuardProofRun "step $step hung after $TimeoutMinutes minutes" }
            continue
        }

        # Re-attribute before judging. A mutation can disable the suite's own attribution - step 72's
        # does, by design, since attribution is what step 72 guards - and then the suite fails exactly
        # as intended while reporting no step at all. Parsing the copy's suite text with *this* pack's
        # unmutated functions keeps the measurement outside the blast radius.
        $effective = $results
        if ($null -ne $results) {
            $copySuite = Get-Content -LiteralPath (Join-Path $workCopy $suiteRel) -Raw -Encoding UTF8
            $effective = [pscustomobject]@{
                failCount = $results.failCount
                failures  = @(Resolve-PackMutationFailureStep -Results $results -SuiteText $copySuite)
            }
            $recovered = @(@($effective.failures) | Where-Object { $null -ne $_.step }).Count -
                         @(@($results.failures) | Where-Object { $null -ne $_.step }).Count
            if ($recovered -gt 0) {
                Write-Host "  note: $recovered failure(s) had no step - re-attributed from the recorded line, because this mutation breaks attribution itself"
            }
        }
        $outcome = @(Test-PackMutationOutcome -Results $effective -ExpectFailIn $entry.expectFailIn)
        if ($outcome.Count -gt 0) {
            Fail "step $step is NOT proven able to fail - $($outcome -join '; ')"
            if ($FailFast) { Stop-GuardProofRun "step $step is NOT proven able to fail" }
        } else {
            $collateral = @(@($effective.failures) | Where-Object { @($entry.expectFailIn) -notcontains [int]$_.step } |
                ForEach-Object { [int]$_.step } | Select-Object -Unique)
            $note = ''
            if ($collateral.Count -gt 0) { $note = " (also failed: $($collateral -join ', ') - consider a narrower mutation)" }
            Ok "step $step reported a failure under its own mutation$note"
        }
        Assert-GuardProofEnvironment -Step $step
    }
    # Each entry copies the tree afresh, so an edit mid-run means the copies were not the same pack.
    # Reported rather than failed: the proofs above may still be sound, but collateral failures cannot
    # be told apart from real ones, and that ambiguity should not be discovered by re-reading a log.
    $endStamp = Get-TreeStamp
    if ($endStamp -ne $script:startStamp) {
        if ($FailFast) {
            Stop-GuardProofRun "pack tree changed during run ($($script:startStamp) -> $endStamp) - freeze edits or use -Only on a quiet tree"
        } else {
            Write-Host "`n[WARN] the pack changed while this ran ($($script:startStamp) -> $endStamp)."
            Write-Host '       Each entry copies the tree again, so the copies were not identical packs and any'
            Write-Host '       collateral failure above may be a mid-edit tree rather than the mutation. Re-run on a quiet tree.'
        }
    }
    Assert-GuardProofEnvironment
    Ok 'profile install unchanged (WQ-481 sandbox held)'
} finally {
    Remove-GuardProofLock
    if ($null -eq $script:PrevInstallRoot) {
        Remove-Item Env:\AGENT_STARTER_PACK_INSTALL_ROOT -ErrorAction SilentlyContinue
    } else {
        $env:AGENT_STARTER_PACK_INSTALL_ROOT = $script:PrevInstallRoot
    }
    if ($KeepWork) {
        Write-Host "`nWork kept at $workRoot"
    } elseif (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`nSummary: $fail fail(s)"
if ($fail -gt 0) { exit 1 }
exit 0
