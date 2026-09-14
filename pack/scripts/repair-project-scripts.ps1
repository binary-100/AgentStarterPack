#Requires -Version 5.1
<#
.SYNOPSIS
  Delivers the POSIX twin of each entry point to a project bootstrapped before 2.22.77 (WQ-450).

.DESCRIPTION
  2.22.76 taught every remediation message to name the entry point the running host can execute, and
  taught bootstrap-project.ps1 to emit both twins. That fixed the pack and every *new* project, and
  did nothing for the projects that already exist: one bootstrapped earlier has a .cmd-only scripts\
  folder, so on Linux its audit stopped naming a .cmd it cannot run and started naming a .sh it does
  not have. Same dead end, different filename - which is why the twins were held out of the manifest's
  projectRequired until a command existed to satisfy them. This is that command.

  Three ways a twin can be unrunnable, all repaired here, because "present" is not the same as
  "works":

    missing  - the Windows twin is there and the .sh is not (a pre-2.22.77 bootstrap)
    CRLF     - the .sh exists but carries carriage returns, so bash answers
               "$'\r': command not found" and names no file. Projects generated from a Windows
               checkout made before the .gitattributes fix in this release have this, because
               *.sh did not match run_audit.sh.template and the template itself was converted
    no +x    - the .sh exists and is clean but is not executable, so ./run_audit.sh answers
               "Permission denied". PowerShell creates files without the bit and no Windows
               filesystem carries one, so any project copied from Windows arrives this way

  Detection matches the *defect*, not a difference from the template, for the reason
  repair-project-hooks.ps1 gives: a hash compare reports drift on every unrelated template edit and
  would overwrite a file somebody customised on purpose. So a missing twin is written from the
  template, but a CRLF one is repaired in place - stripping the carriage returns keeps local edits,
  where a rewrite would silently discard them.

  A project that never took an entry point is not broken and is not reported. Otherwise this script
  would fail on every project that has no test runner, and people would learn to ignore it.

.PARAMETER ProjectRoot
  The project to repair.

.PARAMETER VerifyOnly
  Report and exit non-zero on a stranded twin; write nothing.

.PARAMETER AuditMode
  Emit [FIX] lines for run_audit_core.ps1 to absorb. Implies VerifyOnly - an audit never mutates the
  tree it is auditing.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [switch]$VerifyOnly,
    [switch]$AuditMode
)

$ErrorActionPreference = 'Stop'
# Get-PackRelPathKey / Format-PackDisplayPath / Set-PackExecutableBit / Test-PackIsWindows.
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

function Write-Ok($m) { if (-not $AuditMode) { Write-Host "[OK] $m" } }
function Write-Info($m) { if (-not $AuditMode) { Write-Host "[INFO] $m" } }
function Write-Fail($m) { Write-Host "[FAIL] $m" }
function Emit-Fix($m) { Write-Host "[FIX] $m" }

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    Write-Fail "Project root does not exist: $ProjectRoot"
    exit 1
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

# pack/scripts and pack/templates sit side by side in the source checkout and in the installed copy,
# so the templates resolve the same way from either without consulting the manifest.
$templateRoot = Join-Path $PSScriptRoot '../templates'
if (-not (Test-Path -LiteralPath $templateRoot)) {
    Write-Fail "Shipped templates missing: $templateRoot - reinstall the starter pack"
    exit 1
}
$templateRoot = (Resolve-Path -LiteralPath $templateRoot).Path

# The audit config is what tells the two manifest layouts apart (projectRequired.flatLayout vs
# .appLayout). Guessing flat would send every repair in an app-layout project to a path nothing reads.
$layoutBase = ''
if (Test-Path -LiteralPath (Join-Path $ProjectRoot 'docs/AUDIT.config.json')) {
    $layoutBase = ''
} elseif (Test-Path -LiteralPath (Join-Path $ProjectRoot 'app/docs/AUDIT.config.json')) {
    $layoutBase = 'app'
}

function Resolve-ProjectPath([string]$Rel) {
    $r = if ($layoutBase) { "$layoutBase/$Rel" } else { $Rel }
    return (Join-Path $ProjectRoot $r)
}

# Windows twin -> POSIX twin -> the template the POSIX twin is written from. run_tests is included
# because a generated project's audit shells out to it to earn its test-pass proof, so a project
# whose only runner is a .bat cannot complete an audit off Windows at all.
$pairs = @(
    @{ Win = 'run_audit.cmd'; Sh = 'run_audit.sh'; Template = 'run_audit.sh.template' }
    @{ Win = 'run_tests.bat'; Sh = 'run_tests.sh'; Template = 'run_tests.sh.template' }
    @{ Win = 'scripts/sync_audit_system.cmd'; Sh = 'scripts/sync_audit_system.sh'
        Template = 'scripts/sync_audit_system.sh.template'
    }
    @{ Win = 'scripts/verify_semantic_audit.cmd'; Sh = 'scripts/verify_semantic_audit.sh'
        Template = 'scripts/verify_semantic_audit.sh.template'
    }
    @{ Win = 'scripts/write_semantic_audit_template.cmd'; Sh = 'scripts/write_semantic_audit_template.sh'
        Template = 'scripts/write_semantic_audit_template.sh.template'
    }
    @{ Win = 'scripts/finalize_audit.cmd'; Sh = 'scripts/finalize_audit.sh'
        Template = 'scripts/finalize_audit.sh.template'
    }
)

function Test-ShHasCr([string]$Path) {
    # Bytes, not Get-Content: the reader strips line endings, so a text compare cannot see the very
    # thing being tested. A single CR anywhere is enough - it is the shebang line that matters, and a
    # CR there makes the interpreter path itself wrong.
    try { return ([System.IO.File]::ReadAllBytes($Path) -contains 13) } catch { return $false }
}

function Test-ShIsExecutable([string]$Path) {
    # Unanswerable on Windows, which has no execute bit, so report executable there rather than
    # inventing a defect that cannot exist on the host doing the asking.
    if (Test-PackIsWindows) { return $true }
    $testCmd = Get-Command test -ErrorAction SilentlyContinue
    if (-not $testCmd) { return $true }
    & $testCmd.Source '-x' $Path
    return ($LASTEXITCODE -eq 0)
}

$problems = @()
$repaired = @()
$skipped = 0

foreach ($pair in $pairs) {
    $winPath = Resolve-ProjectPath $pair.Win
    $shPath = Resolve-ProjectPath $pair.Sh
    $hasWin = Test-Path -LiteralPath $winPath
    $hasSh = Test-Path -LiteralPath $shPath

    if (-not $hasWin -and -not $hasSh) { $skipped++; continue }

    $relSh = Get-PackRelPathKey -Path $shPath -Root $ProjectRoot
    $display = Format-PackDisplayPath $relSh

    if (-not $hasSh) {
        $problems += @{
            Pair = $pair; Path = $shPath; Display = $display; Kind = 'missing'
            Reason = 'no POSIX twin - project was bootstrapped before 2.22.77'
        }
        continue
    }
    if (Test-ShHasCr $shPath) {
        $problems += @{
            Pair = $pair; Path = $shPath; Display = $display; Kind = 'crlf'
            Reason = 'carriage returns in a shell script - bash fails with "$''\r'': command not found"'
        }
        continue
    }
    if (-not (Test-ShIsExecutable $shPath)) {
        $problems += @{
            Pair = $pair; Path = $shPath; Display = $display; Kind = 'noexec'
            Reason = 'not executable - ./ answers "Permission denied"'
        }
        continue
    }
    Write-Ok "runnable on this host: $display"
}

if ($skipped -gt 0) {
    Write-Info "$skipped entry point(s) absent in both spellings - this project never took them, nothing to repair"
}

if ($problems.Count -eq 0) {
    Write-Ok "All POSIX entry-point twins present, LF and executable: $ProjectRoot"
    exit 0
}

if ($AuditMode) {
    # One line, not one per file: six Fix rows saying the same thing about six files buries the rest
    # of the report, and the remedy is a single run either way.
    $names = ($problems | ForEach-Object { $_.Display }) -join ', '
    $repairRel = Format-PackDisplayPath 'pack/scripts/repair-project-scripts.ps1'
    Emit-Fix ("POSIX entry-point twins unrunnable ($($problems.Count)) - $names - " +
        "this project's audit names steps it cannot run on a non-Windows host - agent: offer to run " +
        "$repairRel -ProjectRoot for this project")
    exit 1
}

if ($VerifyOnly) {
    foreach ($p in $problems) { Write-Fail "$($p.Display) - $($p.Reason)" }
    Write-Fail "$($problems.Count) unrunnable twin(s) (run without -VerifyOnly to repair)"
    exit 1
}

foreach ($p in $problems) {
    switch ($p.Kind) {
        'missing' {
            $tpl = Join-Path $templateRoot $p.Pair.Template
            if (-not (Test-Path -LiteralPath $tpl)) {
                Write-Fail "$($p.Display) - shipped template missing ($($p.Pair.Template)) - reinstall the starter pack"
                continue
            }
            # LF on the way out regardless of what the template carries. The templates are pinned LF
            # in .gitattributes as of this release, but an installed pack copied from an older Windows
            # checkout still holds converted ones, and writing those through would hand the project
            # the CRLF defect this same script exists to repair.
            $text = [System.IO.File]::ReadAllText($tpl) -replace "`r`n", "`n"
            Write-Utf8NoBom -Path $p.Path -Text $text
            Set-PackExecutableBit -Path @($p.Path)
            $repaired += "$($p.Display) (written from $($p.Pair.Template))"
        }
        'crlf' {
            # In place, not from the template: a rewrite would discard a project's own edits, and the
            # carriage returns are the whole defect.
            $text = [System.IO.File]::ReadAllText($p.Path) -replace "`r`n", "`n"
            Write-Utf8NoBom -Path $p.Path -Text $text
            Set-PackExecutableBit -Path @($p.Path)
            $repaired += "$($p.Display) (carriage returns stripped)"
        }
        'noexec' {
            Set-PackExecutableBit -Path @($p.Path)
            $repaired += "$($p.Display) (execute bit set)"
        }
    }
}

foreach ($r in $repaired) { Write-Ok "Repaired $r" }
if ($repaired.Count -ne $problems.Count) {
    Write-Fail "Repaired $($repaired.Count) of $($problems.Count) - see the failures above"
    exit 1
}
Write-Ok "Repaired $($repaired.Count) POSIX entry-point twin(s) in $ProjectRoot"
exit 0
