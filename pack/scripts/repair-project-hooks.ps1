#Requires -Version 5.1
<#
.SYNOPSIS
  Repairs a project's generated Cursor session hook when it predates the 2.22.63 stdin fix (WQ-435).

.DESCRIPTION
  Until 2.22.63 the generated hook drained stdin with an unbounded [Console]::In.ReadToEnd(). Cursor
  closes that handle so it returned at once; bash leaves it open and the read waits for an EOF that never
  arrives, which hung an audit for sixteen minutes. The 2.22.63 replacement bounded that read with
  Task::Run and a scriptblock, which faults for want of a runspace and never drains at all (WQ-473);
  the current template reads stdin by no route whatsoever, so two shapes are repairable now rather
  than one. install.ps1 rewrites the profile copy on every
  install, so that one self-heals. bootstrap-project.ps1 copies the project hook with -ForceWrite:$Force,
  so a project bootstrapped before the fix keeps its broken copy until someone re-runs bootstrap -Force -
  which rewrites unrelated generated files too. This repairs the one file.

  Detection matches the *defect*, not a difference from the template. A hash compare would report drift
  for every unrelated template edit and would overwrite a hook somebody customised deliberately; the job
  here is to name the hang, not to enforce sameness.

.PARAMETER VerifyOnly
  Report and exit non-zero on a stale hook; write nothing.

.PARAMETER AuditMode
  Emit [FIX] lines for run_audit_core.ps1 to absorb. Implies VerifyOnly - an audit never mutates the tree.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [switch]$VerifyOnly,
    [switch]$AuditMode
)

$ErrorActionPreference = 'Stop'
# Get-PackRelPathKey: one spelling for a relative path on every OS.
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

# pack/scripts and pack/templates sit side by side in both the source checkout and the installed copy,
# so the template resolves the same way from either without consulting the manifest.
$template = Join-Path $PSScriptRoot '../templates/cursor/hooks/session-freshness.ps1'
if (-not (Test-Path -LiteralPath $template)) {
    Write-Fail "Shipped hook template missing: $template - reinstall the starter pack"
    exit 1
}
$template = (Resolve-Path -LiteralPath $template).Path

$hooksDir = Join-Path $ProjectRoot '.cursor/hooks'
$hookPath = Join-Path $hooksDir 'session-freshness.ps1'
$hooksJson = Join-Path $ProjectRoot '.cursor/hooks.json'

# A project that never took the Cursor target has nothing to repair and is not broken. Reporting it as a
# problem would train people to ignore this script on every non-Cursor project they own.
if (-not (Test-Path -LiteralPath $hooksDir) -and -not (Test-Path -LiteralPath $hookPath)) {
    Write-Info "No .cursor\hooks in $ProjectRoot - nothing to repair (project has no Cursor session hook)"
    exit 0
}

function Get-HookCodeText([string]$Body) {
    # Detection reads code, never prose. A hook's comments routinely name the defect they warn
    # about - the shipped template explains the stdin read it deliberately does not perform - and a
    # text match cannot tell the warning from the thing. It cost a green baseline once: the current
    # template reported itself stale, and every project generated from it followed. The same
    # blindness runs the other way, where a comment mentioning the guard would vouch for a hook that
    # still hangs. Tokenise and drop the comments; everything else is the hook.
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Body, [ref]$tokens, [ref]$parseErrors)
    if (-not $tokens) { return $Body }
    return ((@($tokens) | Where-Object { $_.Kind -ne 'Comment' } | ForEach-Object { $_.Text }) -join ' ')
}

function Test-HookIsStale([string]$RawBody) {
    if ([string]::IsNullOrWhiteSpace($RawBody)) { return $true }
    $Body = Get-HookCodeText $RawBody
    # Two defect shapes, and the second hides behind the first one's test. 2.22.63 bounded the drain
    # with Task::Run and a scriptblock, which needs a runspace that a threadpool thread does not have,
    # so the task faults in milliseconds instead of reading (WQ-473). It never hangs - so every test
    # for the hang calls it current - and it never drains either, leaving unkept the one promise this
    # code exists to make. A project carrying that shape needs the current template as much as a
    # pre-2.22.63 one does.
    # Whitespace-tolerant because the text being matched is rejoined tokens, not the file: the
    # tokeniser splits [System.Threading.Tasks.Task]::Run into a bracket, a type name, a bracket,
    # an operator and an identifier, so nothing in it is adjacent to anything else.
    if ($Body -match 'Task\s*\]\s*::\s*Run') { return $true }
    if ($Body -notmatch 'ReadToEnd\s*\(') { return $false }
    # The fix is two things together: only read when stdin is actually redirected, and bound the wait.
    # Either one missing leaves the hang reachable, so both are required to call a hook current.
    $hasRedirectGuard = $Body -match 'IsInputRedirected'
    $hasBoundedWait = $Body -match 'Wait\s*\(\s*\d+'
    return -not ($hasRedirectGuard -and $hasBoundedWait)
}

$reason = ''
if (-not (Test-Path -LiteralPath $hookPath)) {
    # A registered hook whose script is gone fails on every session start, so it is repairable rather
    # than absent. Without that registration there is nothing to point at, so leave it alone.
    $registered = (Test-Path -LiteralPath $hooksJson) -and
        ((Get-Content -LiteralPath $hooksJson -Raw -Encoding UTF8) -match 'session-freshness')
    if (-not $registered) {
        Write-Info "No session hook and none registered in .cursor\hooks.json - nothing to repair"
        exit 0
    }
    $reason = 'hooks.json registers session-freshness.ps1 but the script is missing'
} else {
    $body = Get-Content -LiteralPath $hookPath -Raw -Encoding UTF8
    if (-not (Test-HookIsStale $body)) {
        Write-Ok "Cursor session hook is current (does not read stdin): $hookPath"
        exit 0
    }
    $reason = if ((Get-HookCodeText $body) -match 'Task\s*\]\s*::\s*Run') {
        'hook carries the 2.22.63 drain, which faults on a threadpool thread and never reads stdin (WQ-473)'
    } else {
        'hook predates the 2.22.63 stdin fix - unbounded ReadToEnd can hang a non-Cursor host'
    }
}

$relHook = Get-PackRelPathKey -Path $hookPath -Root $ProjectRoot

if ($AuditMode) {
    Emit-Fix ("Cursor session hook needs repair - $relHook - $reason - agent: offer to run " +
        "pack\scripts\repair-project-hooks.ps1 -ProjectRoot for this project")
    exit 1
}

if ($VerifyOnly) {
    Write-Fail "$relHook - $reason (run without -VerifyOnly to repair)"
    exit 1
}

New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
if (Test-Path -LiteralPath $hookPath) {
    # Only taken when a repair actually happens, so a second run cannot bury the original under a copy
    # of the repaired file.
    $backup = "$hookPath.bak"
    Copy-Item -LiteralPath $hookPath -Destination $backup -Force
    Write-Info "Previous hook saved: $backup"
}
Copy-Item -LiteralPath $template -Destination $hookPath -Force
Write-Ok "Repaired $relHook from the shipped template ($reason)"
exit 0
