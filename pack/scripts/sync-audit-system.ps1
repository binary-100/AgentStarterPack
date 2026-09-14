#Requires -Version 5.1
<#
.SYNOPSIS
  Manifest-driven audit sync - source pack, installed pack, user Cursor, reference project.
  Source pack is the checkout these scripts live in, wherever it sits on disk.
.PARAMETER VerifyOnly
  Exit 1 on hash drift (no copies).
.PARAMETER PushFromProject
  Optional reference application -> pack templates, then mirror to installed + user.
  Requires -ProjectRoot (or env AUDIT_REFERENCE_PROJECT_ROOT).
.PARAMETER ProjectRoot
  Repo root for layout detection and drift checks.
.PARAMETER PullFromInstalled
  Let the installed copy win when it is newer, and copy back files missing from the source pack.
  Only for recovering edits made directly in %USERPROFILE%\.cursor\AgentStarterPack.
  Off by default: the source pack is authoritative, so a stale machine-local install can never
  overwrite or resurrect files in the checkout.
#>
param(
    [switch]$VerifyOnly,
    [switch]$AutoFix,
    [switch]$PushFromProject,
    [string]$ProjectRoot = '',
    [switch]$PullFromInstalled
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

function Get-SourcePack {
    $root = Get-SourceAgentStarterPack
    if (-not $root) { $root = Get-CheckoutAgentStarterPack }
    return $root
}

function Get-InstalledPack {
    Get-InstalledAgentStarterPack
}

function Get-Manifest([string]$PackRoot) {
    $path = Join-Path $PackRoot 'pack/audit/manifest.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing manifest: $path" }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-Sha256([string]$Path) {
    Get-PackFileSha256 -Path $Path
}

$script:SyncDriftEvents = @()

function Get-SyncDriftEventKey([string]$Path) {
    if (-not $Path) { return $null }
    return ([System.IO.Path]::GetFullPath($Path)).ToLowerInvariant()
}

function Register-SyncDriftEvent([string]$Label, [string]$A, [string]$B, [string]$HashA, [string]$HashB) {
    $keyPath = if ($B) { $B } else { $A }
    $script:SyncDriftEvents += [pscustomobject]@{
        Label = $Label
        PathA = $A
        PathB = $B
        HashA = $HashA
        HashB = $HashB
        Key   = Get-SyncDriftEventKey $keyPath
    }
}

function Get-SyncDriftSessionPath([string]$SourceRoot) {
    $stateRoot = Get-AgentStateRoot $SourceRoot
    if (-not (Test-Path -LiteralPath $stateRoot)) {
        New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    }
    Join-Path $stateRoot 'sync-drift-session.json'
}

function Read-SyncDriftSession([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-SyncDriftSession([string]$Path, $LastRun) {
    $payload = [ordered]@{ lastRun = $LastRun }
    Write-Utf8NoBom $Path (($payload | ConvertTo-Json -Depth 6 -Compress))
}

function Clear-SyncDriftSession([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

function ConvertTo-SyncDriftStringList($Value) {
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return @($Value | ForEach-Object { "$_".ToLowerInvariant() } | Where-Object { $_ })
    }
    $one = "$Value".ToLowerInvariant()
    if ($one) { return @($one) }
    return @()
}

function Get-RecurringSyncDriftEvents($PreviousRun, $CurrentEvents) {
    if (-not $PreviousRun) { return @() }
    $prev = ConvertTo-SyncDriftStringList $PreviousRun.keys
    if ($prev.Count -eq 0) { return @() }
    $recurring = @()
    foreach ($ev in @($CurrentEvents)) {
        if (-not $ev.Key) { continue }
        $key = "$($ev.Key)".ToLowerInvariant()
        if ($prev -contains $key) { $recurring += $ev }
    }
    return $recurring
}

function Write-RecurringSyncDriftAdvice($RecurringEvents) {
    # return @() from a function assigns $null; @($null).Count is 1 in PowerShell.
    $events = @($RecurringEvents | Where-Object { $_ })
    if ($events.Count -eq 0) { return }
    Write-Host ''
    Write-Host '[RECURRING DRIFT] The same path drifted on a second verify-only run in this session.'
    Write-Host '  This is not ordinary staleness - something is still writing to the installed or profile copy.'
    foreach ($ev in $events) {
        Write-Host "  - $($ev.Label)"
        if ($ev.PathB) { Write-Host "    B: $($ev.PathB)" }
        elseif ($ev.PathA) { Write-Host "    A: $($ev.PathA)" }
    }
    $lockPath = Join-Path (Get-PackTempDir) 'guard-proofs.lock'
    if (Test-Path -LiteralPath $lockPath) {
        try {
            $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $lockPid = [int]$lock.pid
            if ($lockPid -gt 0 -and (Get-Process -Id $lockPid -ErrorAction SilentlyContinue)) {
                Write-Host "  Active guard proof run (PID $lockPid since $($lock.started)) - lock: $lockPath"
                Write-Host '  Stop that process before syncing again; escaped registry mutations sync to the profile during proof runs.'
            } else {
                Write-Host "  Stale guard-proofs.lock at $lockPath (PID $($lock.pid) not running) - remove the lock file."
            }
        } catch {
            Write-Host "  guard-proofs.lock present at $lockPath - inspect manually."
        }
    } else {
        Write-Host '  No guard-proofs.lock - look for other live writers (background verify-guard-proofs.ps1, editor saves, parallel agents).'
    }
    Write-Host '  Do not run sync again blindly; find and stop the writer first.'
}

function Test-Drift([string]$Label, [string]$A, [string]$B) {
    $ha = Get-Sha256 $A
    $hb = Get-Sha256 $B
    if ($null -eq $ha -or $null -eq $hb) {
        if ($null -eq $ha -and $null -eq $hb) { return $false }
        Write-Host "[DRIFT] $Label - missing file"
        Write-Host "  A: $A"
        Write-Host "  B: $B"
        Register-SyncDriftEvent $Label $A $B $ha $hb
        return $true
    }
    if ($ha -ne $hb) {
        Write-Host "[DRIFT] $Label"
        Write-Host "  A: $A"
        Write-Host "  B: $B"
        Register-SyncDriftEvent $Label $A $B $ha $hb
        return $true
    }
    return $false
}

function Copy-File([string]$Src, [string]$Dst) {
    $dir = Split-Path -Parent $Dst
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $Src -Destination $Dst -Force
}

function Sync-MirrorFile([string]$Src, [string]$Dst) {
    # Source pack (Src) is authoritative; installed copy (Dst) is machine-local and disposable.
    # Comparing mtimes across filesystems is unreliable (removable exFAT media store local time,
    # NTFS stores UTC), so the source only loses when -PullFromInstalled is explicit.
    $srcExists = Test-Path -LiteralPath $Src
    $dstExists = Test-Path -LiteralPath $Dst
    if (-not $srcExists -and -not $dstExists) { return }
    if (-not $srcExists) {
        # The source is authoritative about absences too, otherwise -VerifyOnly stays red forever
        # (and -AutoFix loops) on a file the mirror is never allowed to reconcile.
        if ($script:PullFromInstalledMode) { Copy-File $Dst $Src }
        else {
            Remove-Item -LiteralPath $Dst -Force
            Write-Host "[CLEAN] removed from installed copy, not in source pack: $Dst"
            Write-Host '        (use -PullFromInstalled to copy it into the source pack instead)'
        }
        return
    }
    if (-not $dstExists) { Copy-File $Src $Dst; return }
    $ha = Get-Sha256 $Src
    $hb = Get-Sha256 $Dst
    if ($ha -eq $hb) { return }
    if ($script:PullFromInstalledMode) {
        $srcTime = (Get-Item -LiteralPath $Src).LastWriteTimeUtc
        $dstTime = (Get-Item -LiteralPath $Dst).LastWriteTimeUtc
        if ($dstTime -gt $srcTime) {
            Copy-File $Dst $Src
            return
        }
    }
    Copy-File $Src $Dst
}

$script:PullFromInstalledMode = [bool]$PullFromInstalled
$Installed = Get-InstalledPack
$UserCursor = Get-AgentStarterPackUserRoot
$Source = Get-SourcePack
if (-not $Source -and (Test-AgentStarterPackInstalled)) { $Source = $Installed }
if (-not $Source) {
    throw 'No Agent Starter Pack found. Run this from a pack checkout, or set AGENT_STARTER_PACK_ROOT to its folder.'
}

# A machine with no installed copy is not "drifted" - it just has not been integrated yet.
#
# Skipped in write mode too, not only under -VerifyOnly: mirroring used to CREATE the installed copy
# and the profile rules/skills, so a project audit with autoFixDrift enabled silently installed the
# pack into %USERPROFILE%\.cursor. Installing is install.ps1's job and must stay an explicit,
# per-machine decision - this script only keeps an existing install aligned.
$PackInstalled = Test-AgentStarterPackInstalled
$SkipProfileMirror = -not $PackInstalled

$manifest = Get-Manifest $Source
$drift = 0

# Resolve reference project root
if (-not $ProjectRoot -and $PushFromProject) {
    $envName = $manifest.referenceProject.repoRootEnv
    if ($envName) {
        $fromEnv = [Environment]::GetEnvironmentVariable($envName)
        if ($fromEnv) { $ProjectRoot = $fromEnv }
    }
    if (-not $ProjectRoot) {
        $def = ($manifest.referenceProject.defaultRepoRoot -replace '/', '\').Trim()
        if ($def) { $ProjectRoot = Join-Path (Get-PackHomeDir) $def }
    }
}
if ($ProjectRoot) { $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path }

# Push reference project -> templates
if ($PushFromProject) {
    if (-not $ProjectRoot) { throw 'PushFromProject requires -ProjectRoot or AUDIT_REFERENCE_PROJECT_ROOT' }
    foreach ($item in @($manifest.referenceProject.pushToTemplates)) {
        $from = Join-Path $ProjectRoot ($item.from -replace '/', '\')
        $to = Join-Path $Source ($item.to -replace '/', '\')
        if ($VerifyOnly) {
            if (Test-Drift "reference push $($item.from)" $from $to) { $drift++ }
        } elseif (Test-Path -LiteralPath $from) {
            Copy-File $from $to
            Write-Host "[PUSH] $from -> $to"
        } else {
            Write-Host "[SKIP] missing $from"
        }
    }
    if ($manifest.referenceProject.referenceOnly) {
        foreach ($item in @($manifest.referenceProject.referenceOnly)) {
            if ($VerifyOnly) { continue }
            $from = Join-Path $ProjectRoot ($item.from -replace '/', '\')
            $to = Join-Path $Source ($item.to -replace '/', '\')
            if (Test-Path -LiteralPath $from) {
                Copy-File $from $to
                Write-Host "[REF] $from -> $to"
            }
        }
    }
}

# Doc version cites first: this rewrites files that are themselves mirrored (START_HERE.md,
# AUDIT_SYSTEM.md). Running it after the mirror copied the pre-sync text, so the very next verify
# reported drift on a tree that had just been synced.
$docSync = Join-Path $Source 'pack/scripts/sync-doc-versions.ps1'
$docSyncRan = $false
if (-not $VerifyOnly -and (Test-Path -LiteralPath $docSync) -and
    (Test-Path -LiteralPath (Join-Path $Source 'docs/AUDIT.config.json'))) {
    Write-Host 'Syncing maintainer doc versions...'
    Invoke-PackScript -PassOutput -NoProfile -ScriptPath $docSync -ProjectRoot $Source
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] sync-doc-versions reported stale cites - run $(Get-PackEntryPoint 'Sync-DocVersions') or fix manually"
    }
    $docSyncRan = $true
}

$portableSync = Join-Path $Source 'pack/scripts/sync-portable-docs.ps1'
if ((Test-Path -LiteralPath $portableSync) -and
    (Test-Path -LiteralPath (Join-Path $Source 'docs/AUDIT.config.json'))) {
    if ($VerifyOnly) {
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $portableSync -PackRoot $Source -VerifyOnly 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { $drift++ }
    } else {
        Write-Host 'Syncing portable rule/skill exports...'
        Invoke-PackScript -PassOutput -NoProfile -ScriptPath $portableSync -PackRoot $Source 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { exit 1 }
    }
}

# Mirror pack -> installed
if ($SkipProfileMirror) {
    Write-Host "[INFO] No installed pack at $Installed - run install.ps1 to integrate this pack with agents on this machine."
    Write-Host '[INFO] Skipping the installed + user mirror entirely; this script never creates an install.'
} else {
    foreach ($rel in @($manifest.packMirror)) {
        $relWin = $rel -replace '/', '\'
        $src = Join-Path $Source $relWin
        $dst = Join-Path $Installed $relWin
        if (Test-Drift "pack vs installed $rel" $src $dst) { $drift++ }
        if (-not $VerifyOnly) { Sync-MirrorFile $src $dst }
    }
}

# Remove forbidden orphan paths from installed + user mirrors
if (-not $VerifyOnly -and $manifest.forbiddenPackPaths) {
    foreach ($targetRoot in @($Installed)) {
        foreach ($rel in @($manifest.forbiddenPackPaths)) {
            $bad = Join-Path $targetRoot ($rel -replace '/', '\')
            if (Test-Path -LiteralPath $bad) {
                Remove-Item -LiteralPath $bad -Force
                Write-Host "[CLEAN] removed forbidden $bad"
            }
        }
    }
    foreach ($rel in @($manifest.forbiddenPackPaths)) {
        $bad = Join-Path $Source ($rel -replace '/', '\')
        if (Test-Path -LiteralPath $bad) {
            Remove-Item -LiteralPath $bad -Force
            Write-Host "[CLEAN] removed forbidden $bad"
        }
    }
}

# Maintainer-only files: deleted from the installed copy, never from the source pack - that is where
# they belong. Installs made before install.ps1 learned to skip them still carry the old handoffs.
if (-not $VerifyOnly -and -not $SkipProfileMirror -and $manifest.maintainerOnlyPaths) {
    foreach ($rel in @($manifest.maintainerOnlyPaths)) {
        $shipped = Join-Path $Installed ($rel -replace '/', '\')
        if (Test-Path -LiteralPath $shipped) {
            # An entry may name a folder (docs/handoffs), and -Force alone will not remove one.
            $recurse = (Get-Item -LiteralPath $shipped) -is [System.IO.DirectoryInfo]
            Remove-Item -LiteralPath $shipped -Force -Recurse:$recurse
            Write-Host "[CLEAN] removed maintainer-only path from install: $shipped"
        }
    }
}

# Machine-local files that were copied into the install before they were classified. They are no longer
# mirrored, so nothing would ever refresh them - they would sit in the profile holding whichever
# machine's absolute paths were current when that install ran. install-manifest.json is the exception:
# install.ps1 *writes* it into the target as that install's own record, so it belongs there.
if (-not $VerifyOnly -and -not $SkipProfileMirror -and $manifest.machineLocalPaths) {
    foreach ($rel in @($manifest.machineLocalPaths)) {
        if ($rel -eq 'install-manifest.json') { continue }
        $copied = Join-Path $Installed ($rel -replace '/', '\')
        if (Test-Path -LiteralPath $copied) {
            $recurse = (Get-Item -LiteralPath $copied) -is [System.IO.DirectoryInfo]
            Remove-Item -LiteralPath $copied -Force -Recurse:$recurse
            Write-Host "[CLEAN] removed copied machine-local file from install: $copied"
        }
    }
}

# Mirror pack -> user
if (-not $SkipProfileMirror) {
    foreach ($item in @($manifest.packToUser)) {
        $src = Join-Path $Source ($item.from -replace '/', '\')
        $dst = Join-Path $UserCursor ($item.to -replace '/', '\')
        if (Test-Drift "pack vs user $($item.to)" $src $dst) { $drift++ }
        if (-not $VerifyOnly -and (Test-Path -LiteralPath $src)) { Copy-File $src $dst }
    }
}

# Project layout required files exist
if ($ProjectRoot) {
    $layout = if (Test-Path -LiteralPath (Join-Path $ProjectRoot 'app/docs/AUDIT.md')) {
        $manifest.projectRequired.appLayout
    } else {
        $manifest.projectRequired.flatLayout
    }
    $layout.PSObject.Properties | ForEach-Object {
        $full = Join-Path $ProjectRoot ($_.Value -replace '/', '\')
        if (-not (Test-Path -LiteralPath $full)) {
            Write-Host "[DRIFT] missing project file $($_.Value)"
            $drift++
        }
    }
}

Write-Host ''
if ($VerifyOnly) {
    $driftSessionPath = Get-SyncDriftSessionPath $Source
    if ($drift -gt 0) {
        $previousRun = $null
        $existingSession = Read-SyncDriftSession $driftSessionPath
        if ($existingSession) { $previousRun = $existingSession.lastRun }
        $recurring = @(Get-RecurringSyncDriftEvents $previousRun $script:SyncDriftEvents)
        Write-RecurringSyncDriftAdvice $recurring
        $lastRun = [ordered]@{
            at     = (Get-Date).ToString('o')
            keys   = [object[]]@($script:SyncDriftEvents | ForEach-Object { $_.Key } | Where-Object { $_ })
            labels = [object[]]@($script:SyncDriftEvents | ForEach-Object { $_.Label })
        }
        Write-SyncDriftSession $driftSessionPath $lastRun
        if ($AutoFix) {
            $target = if ($PackInstalled) { 'source pack -> installed + user' } else { 'source pack only - not installed on this machine' }
            Write-Host "Audit sync: $drift drift(s) - applying AutoFix ($target) ..."
            & $PSCommandPath -ProjectRoot $ProjectRoot -PullFromInstalled:$PullFromInstalled
            if ($LASTEXITCODE -ne 0) { exit 1 }
            Write-Host 'Audit sync: AutoFix applied; re-verifying ...'
            & $PSCommandPath -VerifyOnly -ProjectRoot $ProjectRoot
            exit $LASTEXITCODE
        }
        Write-Host ('Audit sync: ' + $drift + ' issue(s). Run: sync-audit-system.ps1 (no -VerifyOnly) or -AutoFix')
        exit 1
    }
    Clear-SyncDriftSession $driftSessionPath
    if ($SkipProfileMirror) {
        Write-Host 'Audit sync: OK (pack source only - not installed on this machine; run install.ps1 to integrate)'
    } else {
        Write-Host 'Audit sync: OK'
    }
    exit 0
}

if ($PackInstalled) { Write-Host 'Audit sync: all copies updated' }
else { Write-Host 'Audit sync: source pack checked; no installed copy to update on this machine' }
if ($PushFromProject) {
    Write-Host 'Reference templates pushed; installed + user mirrors updated.'
}

if (-not $docSyncRan -and -not $VerifyOnly) {
    Write-Host '[INFO] Doc version sync skipped (not the pack maintainer repo).'
}

exit 0
