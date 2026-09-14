# Shared Agent Starter Pack path resolution (supports legacy Cursor-era names/paths).
#
# No #Requires here on purpose: this file is dot-sourced, so the floor is declared by each script that
# sources it. Every other .ps1 in the pack carries "#Requires -Version 5.1" - Windows PowerShell 5.1 is
# the floor because it ships with Windows and the pack has to work on a machine with nothing installed.
# PowerShell 7 runs the pack fine (the suite passes under both); it is just not assumed.
#
# Two roots, deliberately kept separate:
#   Source pack    - the pack these scripts belong to. Portable: any drive, folder, or removable disk.
#   Installed pack - %USERPROFILE%\.cursor\AgentStarterPack, the copy agents and bootstrapped
#                    projects read on this machine (Cursor loads rules/skills from the profile only).
#
# Resolution is source-first so pack scripts always act on the pack they were launched from,
# never on a stale installed copy that happens to exist elsewhere on the machine.

# Captured while this file is dot-sourced: <packRoot>/pack/scripts
$script:AgentStarterPackToolsDir = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { $PSScriptRoot }

function Get-PackManifestPath {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path (Join-Path (Join-Path $Root 'pack') 'audit') 'manifest.json')
}

function Get-PackScriptPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return (Join-Path (Join-Path (Join-Path $Root 'pack') 'scripts') $Name)
}

function Test-AgentStarterPackRoot {
    param([string]$Path)
    if (-not $Path -or -not $Path.Trim()) { return $false }
    return (Test-Path -LiteralPath (Get-PackManifestPath -Root $Path))
}

function Test-PackPublishZoneBTree {
    <#
    .SYNOPSIS
    True when a pack tree has maintainer handoffs stripped (Zone B repo/ after B09 sync).
    #>
    param([Parameter(Mandatory)][string]$Root)
    if (-not (Test-AgentStarterPackRoot $Root)) { return $false }
    $manifestPath = Get-PackManifestPath -Root $Root
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $maintainerOnly = @($manifest.maintainerOnlyPaths | Where-Object { $_ })
    if ($maintainerOnly -notcontains 'docs/handoffs') { return $false }
    return -not (Test-Path -LiteralPath (Join-Path $Root 'docs/handoffs/SESSION.md'))
}

function Get-SourceAgentStarterPack {
    # pack-paths.ps1 lives at <packRoot>\pack\scripts\, so the pack root is two levels up.
    $dir = $script:AgentStarterPackToolsDir
    if (-not $dir) { $dir = $PSScriptRoot }
    if (-not $dir) { return $null }
    $root = Split-Path -Parent (Split-Path -Parent $dir)
    if (Test-AgentStarterPackRoot $root) { return (Resolve-Path -LiteralPath $root).Path }
    return $null
}

function Get-AgentStarterPackCandidates {
    $list = @()
    $source = Get-SourceAgentStarterPack
    if ($source) { $list += $source }
    if ($env:AGENT_STARTER_PACK_ROOT) { $list += $env:AGENT_STARTER_PACK_ROOT }
    if ($env:CURSOR_STARTER_PACK_ROOT) { $list += $env:CURSOR_STARTER_PACK_ROOT }
    $cursorRoot = Get-DefaultCursorUserRoot
    if ($cursorRoot) {
        $list += Join-Path $cursorRoot 'AgentStarterPack'
        $list += Join-Path $cursorRoot 'agent-starter-pack'
    }
    if (Test-PackIsWindows) {
        $list += Join-Path $env:USERPROFILE 'OneDrive/Desktop/AgentStarterPack'
        $list += Join-Path $env:USERPROFILE 'OneDrive/Desktop/CursorAgentStarterPack'
        $desktop = [Environment]::GetFolderPath('Desktop')
        if ($desktop) {
            $list += Join-Path $desktop 'AgentStarterPack'
            $list += Join-Path $desktop 'CursorAgentStarterPack'
        }
    }
    return $list | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique
}

function Get-StarterPackDesktopCandidates {
    <#
    .SYNOPSIS
      Host Desktop folders for StarterPack-Airlock discovery (OneDrive-redirected first on Windows).
    .PARAMETER OverrideRoots
      Simulation or test override; when set, only these roots are considered.
    #>
    param([string[]]$OverrideRoots)
    if ($OverrideRoots -and @($OverrideRoots | Where-Object { $_ -and $_.Trim() }).Count -gt 0) {
        return @($OverrideRoots | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique)
    }
    $list = @()
    if (Test-PackIsWindows) {
        $list += Join-Path $env:USERPROFILE 'OneDrive/Desktop'
        $desktop = [Environment]::GetFolderPath('Desktop')
        if ($desktop) { $list += $desktop }
    } else {
        $list += Join-Path $env:HOME 'Desktop'
    }
    return @($list | Where-Object { $_ } | Select-Object -Unique)
}

function Get-StarterPackAirlockManifest {
    param([Parameter(Mandatory = $true)][string]$AirlockRoot)
    $manifestPath = Join-Path $AirlockRoot 'overlay/manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { return $null }
    try {
        return (Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Test-StarterPackPublisherKey {
    param(
        [Parameter(Mandatory = $true)][string]$AirlockRoot,
        $Manifest
    )
    $keyPath = Join-Path $AirlockRoot 'publisher.key'
    if (-not (Test-Path -LiteralPath $keyPath)) { return $false }
    if ($null -eq $Manifest -or [string]::IsNullOrWhiteSpace([string]$Manifest.keyId)) { return $false }
    $keyText = (Get-Content -LiteralPath $keyPath -Raw).Trim()
    return ($keyText -eq [string]$Manifest.keyId)
}

function Test-StarterPackOverlayComplete {
    param(
        [Parameter(Mandatory = $true)][string]$AirlockRoot,
        $Manifest
    )
    if ($null -eq $Manifest) { return $false, @('manifest missing or unparseable') }
    $problems = @()
    $overlayDir = Join-Path $AirlockRoot ([string]$Manifest.overlayDir)
    if (-not (Test-Path -LiteralPath $overlayDir)) { $problems += 'overlay directory missing' }
    foreach ($rel in @($Manifest.requiredReads)) {
        if ([string]::IsNullOrWhiteSpace([string]$rel)) { continue }
        $abs = if ([System.IO.Path]::IsPathRooted([string]$rel)) { [string]$rel } else { Join-Path $AirlockRoot ([string]$rel) }
        if (-not (Test-Path -LiteralPath $abs)) { $problems += "requiredRead missing: $rel" }
    }
    return ($problems.Count -eq 0), $problems
}

function Find-StarterPackAirlock {
    <#
    .SYNOPSIS
      Resolve StarterPack-Airlock on the host Desktop when publisher key and overlay validate.
    .DESCRIPTION
      Fail-closed: wrong key, missing overlay file, or incomplete requiredReads returns $null.
      First valid Desktop candidate wins (see simulate S13).
    .PARAMETER DesktopRoots
      Optional override for simulation probes; default uses Get-StarterPackDesktopCandidates.
    #>
    param([string[]]$DesktopRoots)
    foreach ($desktop in (Get-StarterPackDesktopCandidates -OverrideRoots $DesktopRoots)) {
        $airlock = Join-Path $desktop 'StarterPack-Airlock'
        if (-not (Test-Path -LiteralPath $airlock -PathType Container)) { continue }
        $manifest = Get-StarterPackAirlockManifest -AirlockRoot $airlock
        if (-not (Test-StarterPackPublisherKey -AirlockRoot $airlock -Manifest $manifest)) { continue }
        $ok, $null = Test-StarterPackOverlayComplete -AirlockRoot $airlock -Manifest $manifest
        if (-not $ok) { continue }
        $repoDir = Join-Path $airlock ([string]$manifest.repoDir)
        return [pscustomobject]@{
            AirlockRoot   = $airlock
            DesktopRoot   = $desktop
            Manifest      = $manifest
            RepoPath      = $repoDir
            OverlayPath   = Join-Path $airlock ([string]$manifest.overlayDir)
            RequiredReads = @($manifest.requiredReads | ForEach-Object {
                if ([System.IO.Path]::IsPathRooted([string]$_)) { [string]$_ }
                else { (Resolve-Path -LiteralPath (Join-Path $airlock ([string]$_))).Path }
            })
        }
    }
    return $null
}

function Merge-StarterPackAirlockRequiredReads {
    <#
    .SYNOPSIS
      Append Airlock overlay requiredReads to a base requiredReads list (deduped, order preserved).
    .DESCRIPTION
      Phase 4 (WQ-487): overlay paths are absolute under StarterPack-Airlock; never copy overlay
      WORK_QUEUE into the working copy - only merge into AGENT_CONTEXT.json requiredReads.
    #>
    param(
        [string[]]$BaseReads,
        $AirlockDiscovery
    )
    $merged = New-Object System.Collections.ArrayList
    foreach ($path in @($BaseReads)) {
        if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
        if ($merged -notcontains $path) { [void]$merged.Add($path) }
    }
    if ($null -ne $AirlockDiscovery -and $AirlockDiscovery.RequiredReads) {
        foreach ($path in @($AirlockDiscovery.RequiredReads)) {
            if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
            if ($merged -notcontains $path) { [void]$merged.Add($path) }
        }
    }
    return @($merged)
}

function Get-AgentStarterPackPublishRoot {
    <#
    .SYNOPSIS
      Airlock repo/ when discovery is active; otherwise $null (git-free working copy has no publish root).
    #>
    $disc = Find-StarterPackAirlock
    if ($null -eq $disc) { return $null }
    if (-not (Test-Path -LiteralPath $disc.RepoPath)) { return $null }
    return $disc.RepoPath
}

function Get-StarterPackAirlockTemplateRoot {
    param([Parameter(Mandatory = $true)][string]$PackRoot)
    return Join-Path $PackRoot 'pack/templates/airlock'
}

function Get-StarterPackAirlockLayoutPaths {
    <#
    .SYNOPSIS
      Resolve StarterPack-Airlock root, repo/, overlay/, and publisher.key paths.
    #>
    param(
        [string]$DesktopRoot,
        [string]$AirlockRoot
    )
    if ($AirlockRoot) {
        $airlock = (Resolve-Path -LiteralPath $AirlockRoot).Path
        $desktop = $DesktopRoot
        if (-not $desktop) {
            $desktop = Split-Path -Parent $airlock
        }
    } else {
        if (-not $DesktopRoot) {
            $desktops = Get-StarterPackDesktopCandidates
            if (@($desktops | Where-Object { $_ }).Count -eq 0) { return $null }
            $DesktopRoot = @($desktops | Where-Object { $_ })[0]
        }
        $desktop = $DesktopRoot
        $airlock = Join-Path $DesktopRoot 'StarterPack-Airlock'
    }
    return [pscustomobject]@{
        DesktopRoot      = $desktop
        AirlockRoot      = $airlock
        RepoPath         = Join-Path $airlock 'repo'
        OverlayPath      = Join-Path $airlock 'overlay'
        PublisherKeyPath = Join-Path $airlock 'publisher.key'
    }
}

function Test-PackGitCursorLock {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Test-Path -LiteralPath (Join-Path $Root '.git/cursor'))
}

function Move-PackGitToAirlockRepo {
    <#
    .SYNOPSIS
      Move .git from a working copy into Airlock repo/ (Phase 3 / sim S12).
    .OUTPUTS
      absent | repo-already-has-git | migrated | would-migrate
    #>
    param(
        [Parameter(Mandatory = $true)][string]$WorkingCopy,
        [Parameter(Mandatory = $true)][string]$RepoDir,
        [switch]$WhatIf
    )
    $gitSrc = Join-Path $WorkingCopy '.git'
    if (-not (Test-Path -LiteralPath $gitSrc)) { return 'absent' }
    $repoGit = Join-Path $RepoDir '.git'
    if (Test-Path -LiteralPath $repoGit) { return 'repo-already-has-git' }
    if (-not (Test-Path -LiteralPath $RepoDir)) {
        if ($WhatIf) {
            Write-Host "[WOULD CREATE] $RepoDir"
        } else {
            New-Item -ItemType Directory -Path $RepoDir -Force | Out-Null
        }
    }
    if ($WhatIf) {
        Write-Host "[WOULD MOVE] $gitSrc -> $repoGit"
        return 'would-migrate'
    }
    Move-Item -LiteralPath $gitSrc -Destination $repoGit -Force
    return 'migrated'
}

function Copy-PackGitToAirlockRepo {
    <#
    .SYNOPSIS
      Copy .git from working copy into Airlock repo/ without removing the source (parallel / soft cutover).
    .OUTPUTS
      absent | repo-already-has-git | copied | would-copy | copy-failed
    #>
    param(
        [Parameter(Mandatory = $true)][string]$WorkingCopy,
        [Parameter(Mandatory = $true)][string]$RepoDir,
        [switch]$WhatIf
    )
    $gitSrc = Join-Path $WorkingCopy '.git'
    if (-not (Test-Path -LiteralPath $gitSrc)) { return 'absent' }
    $repoGit = Join-Path $RepoDir '.git'
    if (Test-Path -LiteralPath $repoGit) { return 'repo-already-has-git' }
    if (-not (Test-Path -LiteralPath $RepoDir)) {
        if ($WhatIf) {
            Write-Host "[WOULD CREATE] $RepoDir"
        } else {
            New-Item -ItemType Directory -Path $RepoDir -Force | Out-Null
        }
    }
    if ($WhatIf) {
        Write-Host "[WOULD COPY] $gitSrc -> $repoGit (working copy keeps .git)"
        return 'would-copy'
    }
    $robolog = robocopy $gitSrc $repoGit /E /COPY:DAT /DCOPY:DA /R:2 /W:2 /NFL /NDL /NJH /NJS /nc /ns /np 2>&1
    $rc = $LASTEXITCODE
    if ($rc -ge 8) {
        Write-Host "[FAIL] robocopy .git exit $rc"
        if ($robolog) { $robolog | Select-Object -Last 5 | ForEach-Object { Write-Host $_ } }
        return 'copy-failed'
    }
    return 'copied'
}

function Remove-PackGitFromWorkingCopy {
    <#
    .SYNOPSIS
      Remove .git from the working copy only (final cutover after repo/ is proven).
    .OUTPUTS
      absent | removed | would-remove | remove-failed
    #>
    param(
        [Parameter(Mandatory = $true)][string]$WorkingCopy,
        [switch]$WhatIf
    )
    $gitPath = Join-Path $WorkingCopy '.git'
    if (-not (Test-Path -LiteralPath $gitPath)) { return 'absent' }
    if (Test-PackGitCursorLock -Root $WorkingCopy) {
        Write-Host '[WARN] .git/cursor present - close Cursor on this checkout before cutover (WQ-461)'
    }
    if ($WhatIf) {
        Write-Host "[WOULD REMOVE] $gitPath (repo/ .git unchanged)"
        return 'would-remove'
    }
    try {
        Remove-Item -LiteralPath $gitPath -Recurse -Force -ErrorAction Stop
        return 'removed'
    } catch {
        Write-Host "[FAIL] could not remove working-copy .git: $($_.Exception.Message)"
        return 'remove-failed'
    }
}

function Get-AgentStarterPackRoot {
    foreach ($base in (Get-AgentStarterPackCandidates)) {
        if (Test-AgentStarterPackRoot $base) { return $base }
    }
    return $null
}

function Get-CheckoutAgentStarterPack {
    # A full checkout (ships install.ps1), as opposed to the installed profile mirror.
    foreach ($base in (Get-AgentStarterPackCandidates)) {
        if (Test-Path -LiteralPath (Join-Path $base 'install.ps1')) { return $base }
    }
    return $null
}

function Get-DesktopAgentStarterPack {
    # Back-compat alias from when the maintainer checkout always lived on the Desktop.
    Get-CheckoutAgentStarterPack
}

function Get-AgentStarterPackInstallRootOverride {
    # Redirects the install *destination* (not the source pack). Two uses:
    #   - self-tests, so the pack -> installed mirror can run without writing into %USERPROFILE%
    #   - unusual profiles where .cursor is relocated
    # Deliberately separate from AGENT_STARTER_PACK_ROOT, which names a source pack to read.
    if ($env:AGENT_STARTER_PACK_INSTALL_ROOT -and $env:AGENT_STARTER_PACK_INSTALL_ROOT.Trim()) {
        return $env:AGENT_STARTER_PACK_INSTALL_ROOT.Trim()
    }
    return $null
}

function Get-InstalledAgentStarterPack {
    $override = Get-AgentStarterPackInstallRootOverride
    if ($override) { return $override }
    $cursorRoot = Get-DefaultCursorUserRoot
    if (-not $cursorRoot) { return $null }
    $preferred = Join-Path $cursorRoot 'AgentStarterPack'
    if (Test-Path -LiteralPath (Get-PackManifestPath -Root $preferred)) { return $preferred }
    $legacy = Join-Path $cursorRoot 'agent-starter-pack'
    if (Test-Path -LiteralPath (Get-PackManifestPath -Root $legacy)) { return $legacy }
    return $preferred
}

function Test-AgentStarterPackInstalled {
    return (Test-AgentStarterPackRoot (Get-InstalledAgentStarterPack))
}

function Get-AgentStateRoot {
    # Where per-machine agent-context artifacts live for a given project.
    #
    # For an ordinary project, that is its own docs\ folder: the project sits at one path on one
    # machine, and a brief naming that path is exactly right there.
    #
    # A pack root is different, and the difference is the whole reason this function exists. The pack
    # folder is portable by policy - USB stick, any drive letter, a clone, a download - so a generated
    # file recording this machine's paths is wrong the moment the folder moves, and it discloses the
    # sending machine's user name and layout to whoever receives it. Until 2.22.59 the pack audited and
    # refreshed itself through the project code path, so five such files accumulated in its own docs\
    # and had to be gitignored, dropped from the export, and cleaned by a sanitizer after any copy.
    # Not writing them into the folder removes the class instead of policing it.
    #
    # Keyed by a hash of the checkout path so two checkouts on one machine (a stick and a Desktop
    # clone) keep separate state instead of overwriting each other's stamps. Python computes the same
    # key from the same rule in agent_context_freshness.py; behavior step 51 compares the two.
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $full = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    if (-not (Test-AgentStarterPackRoot $full)) { return (Join-Path $full 'docs') }

    # Test and unusual-setup override, same shape as AGENT_STARTER_PACK_INSTALL_ROOT. The behavior
    # suite needs it: a probe pack root under .tmp would otherwise write its stamp into the real
    # %LOCALAPPDATA% and leave it there, which is the same non-hermetic mistake that made step 38
    # depend on whatever the local profile happened to hold (2.22.45).
    $override = $env:AGENT_STARTER_PACK_STATE_ROOT
    if ($override -and $override.Trim()) { return $override.Trim() }

    $key = ($full -replace '\\', '/').ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($key)) |
            ForEach-Object { $_.ToString('x2') }) -join ''
    } finally {
        $sha.Dispose()
    }
    $leaf = (Split-Path -Leaf $full) -replace '[^A-Za-z0-9._-]', '_'
    if (-not $leaf) { $leaf = 'pack' }

    # Machine-local by definition, so it belongs in the machine-local place: LOCALAPPDATA on Windows,
    # XDG_STATE_HOME on POSIX. Not the pack's install root - state must resolve identically whether or
    # not the pack was ever installed on this machine.
    if (Test-PackIsWindows) {
        $base = $env:LOCALAPPDATA
        if (-not $base) { $base = Join-Path $env:USERPROFILE 'AppData/Local' }
    } else {
        $base = $env:XDG_STATE_HOME
        if (-not $base) { $base = Join-Path $HOME '.local/state' }
    }
    return (Join-Path (Join-Path (Join-Path $base 'AgentStarterPack') 'state') "$leaf-$($hash.Substring(0, 12))")
}

function Get-AgentStarterPackUserRoot {
    # Profile folder holding the installed pack plus the rules\, skills\ and mcp.json agents read.
    # Derived from the installed root (.../.cursor/AgentStarterPack -> .../.cursor) so an install-root
    # override moves the whole set together instead of half-redirecting it.
    $parent = Split-Path -Parent (Get-InstalledAgentStarterPack)
    if ($parent) { return $parent }
    $default = Get-DefaultCursorUserRoot
    if ($default) { return $default }
    if ($env:USERPROFILE) { return (Join-Path $env:USERPROFILE '.cursor') }
    return $null
}

# The one BOM-free text writer for the whole pack.
#
# Windows PowerShell 5.1 writes a UTF-8 BOM with Set-Content -Encoding UTF8; PowerShell 7 does not.
# That single difference is the only behavioural split between the two hosts that has actually bitten
# this pack: a BOM in generated JSON crashes Python's json module, and a BOM at the top of a .cmd file
# is a parsing hazard. Writing bytes ourselves makes output identical on both hosts.
#
# This lived as three near-copies (Write-TextNoBom, Set-TextNoBom, Write-Utf8NoBom) that had already
# drifted - only one of them created the parent directory - so a caller's behaviour depended on which
# file it happened to be in.
function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Text = ''
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Add-Utf8NoBomLine {
    # Append variant, for JSONL logs. Add-Content -Encoding UTF8 puts a BOM on the first line of a new
    # file, which breaks reading the log back as JSON lines - the same 5.1 default, different cmdlet.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Line = ''
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::AppendAllText($Path, ($Line + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
}

function ConvertTo-PackPathKey {
    # One spelling for a relative path, so a comparison never depends on which OS produced it.
    #
    # Every path rule in this pack was written in backslashes and compared against paths that
    # Windows happened to produce in backslashes, so the two sides matched by coincidence rather
    # than by agreement. Under pwsh on Linux the same code builds `docs/handoffs/x.md`, no
    # `\`-shaped pattern matches, and the checks do not fail - they pass while excluding nothing.
    # install.ps1's copy filter is the one that matters: it is the only thing keeping
    # maintainer-only and machine-local files out of an installed profile.
    #
    # Callers may pass either spelling; both arrive here as forward slashes with no leading or
    # trailing separator. Compare keys to keys, and use Split-PackPathKey when the question is
    # about a path segment (a directory name at any depth) rather than a whole path.
    param([Parameter(ValueFromPipeline = $true)][AllowEmptyString()][AllowNull()][string]$Path)
    process {
        if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
        ($Path -replace '[\\/]+', '/').Trim('/')
    }
}

function Split-PackPathKey {
    # The segments of a path key, for "is any directory in this path called __pycache__" questions.
    # Wildcards cannot answer that without encoding a separator: `*\.git\*` misses a `.git` at the
    # root and misses everything on Linux, and `*.git*` also matches a file named `x.gitignore`.
    #
    # Not a pipeline function, and it returns the segments unrolled. Emitting `,@($parts)` from a
    # process block hands back one object that happens to be an array, so `@(Split-PackPathKey $rel)`
    # is a single element holding an array and `-contains '.git'` is false for every input. That
    # spelling silently disabled install.ps1's whole directory filter.
    param([AllowEmptyString()][AllowNull()][string]$Path)
    $key = ConvertTo-PackPathKey $Path
    if (-not $key) { return @() }
    return @($key -split '/')
}

function Get-PackRelPathKey {
    # The path key of $Path relative to $Root. Substring arithmetic on raw paths is where the
    # leading separator survives: TrimStart('\') leaves the `/` on Linux, and every comparison
    # downstream then sees `/docs/x.md` where the manifest says `docs/x.md`.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )
    $rootKey = ConvertTo-PackPathKey $Root
    $pathKey = ConvertTo-PackPathKey $Path
    if (-not $rootKey) { return $pathKey }
    if ($pathKey -eq $rootKey) { return '' }
    # Case: Windows and macOS are case-insensitive by default, Linux is not. A relative path is
    # derived from a root the caller already resolved, so compare case-insensitively to avoid
    # returning the absolute path when only the drive letter's case differs.
    if ($pathKey.StartsWith("$rootKey/", [StringComparison]::OrdinalIgnoreCase)) {
        return $pathKey.Substring($rootKey.Length + 1)
    }
    return $pathKey
}

function Test-PackPathKeyUnder {
    # Does $PathKey name $PrefixKey itself, or something inside it? Folder entries in the manifest
    # ("docs/handoffs") must exclude the whole subtree, or the next work slice ships into a profile.
    # StartsWith alone would also match a sibling called "docs/handoffs-archive".
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PathKey,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PrefixKey
    )
    $p = ConvertTo-PackPathKey $PathKey
    $q = ConvertTo-PackPathKey $PrefixKey
    if (-not $q) { return $false }
    if ($p -eq $q) { return $true }
    return $p.StartsWith("$q/", [StringComparison]::OrdinalIgnoreCase)
}

function Test-PackIsWindows {
    # Test-only: verify-audit-behavior.ps1 step 43 and test-os-portability-probe.ps1 mock non-Windows
    # branches on a Windows host. Never set AGENT_STARTER_PACK_TEST_OS in production workflows.
    $testOs = $env:AGENT_STARTER_PACK_TEST_OS
    if ($testOs -and $testOs.Trim()) {
        $t = $testOs.Trim().ToLowerInvariant()
        if ($t -in @('linux', 'nonwindows', 'non-windows', 'darwin', 'macos', 'osx')) { return $false }
        if ($t -eq 'windows') { return $true }
    }
    if ($null -ne $IsWindows) { return [bool]$IsWindows }
    if ($env:OS -match 'Windows') { return $true }
    if ($PSVersionTable.OS -match 'Windows') { return $true }
    return $false
}

function Get-PackHomeDir {
    # The user's home directory on any OS. $env:USERPROFILE is Windows-only and is $null elsewhere,
    # where `Join-Path $env:USERPROFILE '.cursor'` throws "Cannot bind argument to parameter 'Path'
    # because it is null" - which is how a Windows-shaped assumption surfaces off Windows: as a
    # null-binding error several frames from the assumption, naming a parameter and not the cause.
    # USERPROFILE stays first so Windows behaviour is unchanged.
    if ($env:USERPROFILE -and $env:USERPROFILE.Trim()) { return $env:USERPROFILE.Trim() }
    if ($env:HOME -and $env:HOME.Trim()) { return $env:HOME.Trim() }
    return [Environment]::GetFolderPath('UserProfile')
}

function Get-PackTempDir {
    # %TEMP% on Windows, $TMPDIR or /tmp elsewhere. GetTempPath covers both, but $env:TEMP stays
    # first so a Windows machine keeps using exactly the directory it used before.
    if ($env:TEMP -and $env:TEMP.Trim()) { return $env:TEMP.Trim() }
    return [System.IO.Path]::GetTempPath()
}

function Get-DefaultCursorUserRoot {
    if ($env:AGENT_STARTER_PACK_USER_ROOT -and $env:AGENT_STARTER_PACK_USER_ROOT.Trim()) {
        return $env:AGENT_STARTER_PACK_USER_ROOT.Trim()
    }
    $homeRoot = if ($env:HOME -and $env:HOME.Trim()) { $env:HOME.Trim() } else { $env:USERPROFILE }
    if (-not $homeRoot) { return $null }
    return (Join-Path $homeRoot '.cursor')
}

function Get-PackPythonInstallFix {
    if (Test-PackIsWindows) {
        return 'winget install -e --id Python.Python.3.12   (or python.org/downloads - tick "Add python.exe to PATH")'
    }
    return 'Install Python 3.8+ (python.org/downloads, brew install python@3.12, apt install python3, etc.)'
}

function Get-PackPwshInstallFix {
    if (Test-PackIsWindows) {
        return 'winget install -e --id Microsoft.PowerShell'
    }
    return 'https://learn.microsoft.com/powershell/scripting/install/installing-powershell'
}

function Get-PackGitInstallFix {
    if (Test-PackIsWindows) {
        return 'winget install -e --id Git.Git'
    }
    return 'Install git via your package manager (brew install git, apt install git, etc.)'
}

# Every entry point the pack names in instruction text, and the file each host can actually run.
#
# Instruction text must never spell these inline. The audit told a Linux reader to finish up with
# `scripts\write_semantic_audit_template.cmd` for several releases and nothing failed, because that
# string is only ever read by a human - the Batch name and the backslash were both wrong and the
# suite had no way to know. Routing every mention through Get-PackEntryPoint makes the next one
# impossible in two ways: an unregistered name throws, and a registered name whose twin is missing
# fails the pairing check in verify-audit-behavior.ps1.
#
# Names are asymmetric on purpose - `install` ships as Install-AgentStarterPack.cmd and install.sh -
# so this maps per host rather than gluing an extension onto a shared base name.
$script:PackEntryPoints = [ordered]@{
    'run_audit'              = @{ win = 'run_audit.cmd'; posix = 'run_audit.sh' }
    'run_audit_tests'        = @{ win = 'run_audit_tests.bat'; posix = 'run_audit_tests.sh' }
    'Bootstrap-Project'      = @{ win = 'Bootstrap-Project.cmd'; posix = 'Bootstrap-Project.sh' }
    'Check-Requirements'     = @{ win = 'Check-Requirements.cmd'; posix = 'Check-Requirements.sh' }
    'Refresh-AgentContext'   = @{ win = 'Refresh-AgentContext.cmd'; posix = 'Refresh-AgentContext.sh' }
    'Update-AgentStack'      = @{ win = 'Update-AgentStack.cmd'; posix = 'Update-AgentStack.sh' }
    'Register-Tool-Adapters' = @{ win = 'Register-Tool-Adapters.cmd'; posix = 'Register-Tool-Adapters.sh' }
    'Sync-DocVersions'       = @{ win = 'Sync-DocVersions.cmd'; posix = 'Sync-DocVersions.sh' }
    'install'                = @{ win = 'Install-AgentStarterPack.cmd'; posix = 'install.sh' }

    # WQ-451: documented entry points that had no POSIX twin, so a message naming one was unrunnable
    # off Windows and the registry could not spell them at all - Get-PackEntryPoint throws on an
    # unregistered name, which is what kept them out rather than any decision that they were
    # Windows-only. The two multi-step wrappers use pack_pwsh_run, because pack_pwsh_file execs.
    'Verify-AgentSetup'         = @{ win = 'Verify-AgentSetup.cmd'; posix = 'Verify-AgentSetup.sh' }
    'Update-AgentRules'         = @{ win = 'Update-AgentRules.cmd'; posix = 'Update-AgentRules.sh' }
    'Bootstrap-Portable-Project' = @{
        win   = 'Bootstrap-Portable-Project.cmd'
        posix = 'Bootstrap-Portable-Project.sh'
    }

    'scripts/write_semantic_audit_template' = @{
        win   = 'scripts/write_semantic_audit_template.cmd'
        posix = 'scripts/write_semantic_audit_template.sh'
    }
    'scripts/verify_semantic_audit'         = @{
        win   = 'scripts/verify_semantic_audit.cmd'
        posix = 'scripts/verify_semantic_audit.sh'
    }
    'scripts/finalize_audit'                = @{
        win   = 'scripts/finalize_audit.cmd'
        posix = 'scripts/finalize_audit.sh'
    }
    'scripts/sync_audit_system'             = @{
        win   = 'scripts/sync_audit_system.cmd'
        posix = 'scripts/sync_audit_system.sh'
    }
}

function Get-PackPathSeparator {
    # For message text only. Real path work goes through Join-Path, which is already host-correct;
    # this exists because remediation strings concatenate their own paths and were hardcoding '\'.
    if (Test-PackIsWindows) { return '\' } else { return '/' }
}

function Format-PackDisplayPath {
    <#
    .SYNOPSIS
    A repo-relative path spelled with this host's separator, for message text.

    .DESCRIPTION
    `docs\.audit_semantic_report.json` is not just ugly on Linux - pasted into bash, `\.` collapses
    to `.` and names a different file. Messages that print a path a reader may retype run it
    through here.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)
    if (Test-PackIsWindows) { return ($Path -replace '/', '\') }
    return ($Path -replace '\\', '/')
}

function Get-PackEntryPointNames {
    return @($script:PackEntryPoints.Keys)
}

function Get-PackEntryPointSpec {
    param([Parameter(Mandatory)][string]$Name)
    return $script:PackEntryPoints[$Name]
}

function Get-PackEntryPoint {
    <#
    .SYNOPSIS
    Spells a pack entry point the way the current host can run it.

    .DESCRIPTION
    Returns 'run_audit.cmd' on Windows and './run_audit.sh' elsewhere, separators included, so
    instruction text stays runnable as written on the host reading it. -ForWindows / -ForPosix ask
    for a specific host's spelling instead of this one's; the pairing check uses both.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$ForWindows,
        [switch]$ForPosix
    )
    $entry = $script:PackEntryPoints[$Name]
    if (-not $entry) {
        throw ("Unknown pack entry point '$Name'. Register it in `$script:PackEntryPoints " +
            "(pack-paths.ps1) and ship both twins - an entry point with only one is an instruction " +
            "that cannot be followed on the other host. Known: " +
            ((Get-PackEntryPointNames) -join ', '))
    }
    $windows = if ($ForWindows) { $true } elseif ($ForPosix) { $false } else { Test-PackIsWindows }
    if ($windows) { return ($entry.win -replace '/', '\') }
    # './' so the line is runnable as printed; a bare run_audit.sh is not on a default PATH.
    return "./$($entry.posix)"
}

$script:PackPythonInvoke = $null
function Invoke-PackPython {
    # The one way a pack script runs Python. `py -3` is the Windows launcher and does not exist anywhere
    # else, so every hardcoded use of it was a Windows-only call site - which is why the behavior suite
    # aborted on its own first step under Linux, three seconds in. Resolve-PackPythonInvoke below already
    # knew the cross-platform answer and two scripts already asked it; sixty-three call sites did not.
    #
    # Resolution is cached: the resolver runs `--version` on each candidate, and the suite alone calls
    # this forty times.
    param([Parameter(ValueFromRemainingArguments = $true)]$Arguments)
    if (-not $script:PackPythonInvoke) {
        $script:PackPythonInvoke = Resolve-PackPythonInvoke
        if (-not $script:PackPythonInvoke) {
            throw 'No Python 3.8+ found. Tried the Windows launcher (py -3), python3 and python.'
        }
    }
    $p = $script:PackPythonInvoke
    # Flatten one level of nesting before handing the list to a native command. `Invoke-PackPython @args`
    # (splat) arrives as separate values, but `Invoke-PackPython @('a','b')` - an array literal, which
    # reads identically - arrives as a single array element, and PowerShell stringifies that into one
    # space-joined argument. Python then reports a filename with the other arguments inside it. Both
    # spellings must mean the same thing, or the difference shows up as an unrelated-looking error.
    $flat = @()
    foreach ($a in @($p.prefix) + @($Arguments)) {
        if ($null -eq $a) { continue }
        if ($a -is [System.Array]) { $flat += @($a | Where-Object { $null -ne $_ }) } else { $flat += $a }
    }
    # A child's stderr is output, not a terminating error for this process. Every pack script sets
    # ErrorActionPreference = 'Stop', and under it PowerShell wraps a native command's stderr in a
    # NativeCommandError that terminates the caller - so a Python tool reporting a problem the way
    # Python reports problems killed whatever was running it, mid-run, before the exit code could be
    # read. That is how the behavior suite died on its own first step and wrote no results at all,
    # and how the guard runner died quoting the crash (WQ-475). The verdict is $LASTEXITCODE, which
    # this does not touch; assignment here is function-scoped and leaves the caller's preference be.
    $ErrorActionPreference = 'Continue'
    & $p.exe @flat
}

function Resolve-PackPythonInvoke {
    param([string]$PythonCommand = '')
    $MinPython = [version]'3.8'
    $candidates = @()
    if ($PythonCommand) {
        $candidates += , @($PythonCommand, @())
    } elseif (Test-PackIsWindows) {
        $candidates += , @('py', @('-3'))
        $candidates += , @('python', @())
        $candidates += , @('python3', @())
    } else {
        $candidates += , @('python3', @())
        $candidates += , @('python', @())
    }
    foreach ($candidate in $candidates) {
        $exe = $candidate[0]
        $exeExists = if ($exe -match '[\\/]' -or $exe -match '^\.') {
            Test-Path -LiteralPath $exe
        } else {
            [bool](Get-Command $exe -ErrorAction SilentlyContinue)
        }
        if (-not $exeExists) { continue }
        $prefix = @($candidate[1])
        try {
            $out = & $exe @($prefix + @('--version')) 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { continue }
        } catch { continue }
        $m = [regex]::Match($out.Trim(), '(\d+)\.(\d+)(?:\.(\d+))?')
        if (-not $m.Success) { continue }
        $patch = if ($m.Groups[3].Success) { $m.Groups[3].Value } else { '0' }
        $display = (@($exe) + $prefix) -join ' '
        $ver = [version]"$($m.Groups[1].Value).$($m.Groups[2].Value).$patch"
        if ($ver -lt $MinPython) { continue }
        return [pscustomobject]@{
            exe     = $exe
            prefix  = $prefix
            version = $ver
            display = $display
        }
    }
    return $null
}

function Get-PackPowerShellPath {
    if (Test-PackIsWindows) {
        $winPs = Get-Command powershell.exe -ErrorAction SilentlyContinue
        if ($winPs) { return $winPs.Source }
    }
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCmd) { return $pwshCmd.Source }
    if (Test-PackIsWindows) {
        throw 'Agent Starter Pack requires Windows PowerShell 5.1+ or PowerShell 7 (pwsh).'
    }
    throw 'Agent Starter Pack on this OS requires PowerShell 7 (pwsh). Install: https://learn.microsoft.com/powershell/scripting/install/installing-powershell'
}

function Set-PackExecutableBit {
    # Make a shell script runnable as ./script.sh. A no-op on Windows, which has no execute bit.
    #
    # PowerShell creates files without it, so every .sh a script writes off Windows lands at 644 and
    # `./run_audit.sh` answers "Permission denied" - which reads like a broken install rather than a
    # missing chmod. A folder copied from Windows has the same problem: FAT and NTFS carry no mode,
    # so the bit has to be (re)applied wherever the file is produced.
    param([Parameter(Mandatory = $true)][string[]]$Path)
    if (Test-PackIsWindows) { return }
    $chmod = Get-Command chmod -ErrorAction SilentlyContinue
    if (-not $chmod) { return }
    foreach ($p in $Path) {
        if (-not $p) { continue }
        if (-not (Test-Path -LiteralPath $p)) { continue }
        & $chmod.Source '+x' $p 2>$null
    }
}

function Test-PackPathHasSegment {
    # Is any directory in this path one of $Segment? The question every scratch-and-VCS filter is
    # really asking, and the one a wildcard cannot ask without hardcoding a separator: '\.git\'
    # misses a .git at the root and matches nothing at all on Linux, so the filter passes everything
    # through while looking like it filters. Bare '__pycache__' has the opposite fault - it also
    # matches a *file* called __pycache__.txt.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][AllowNull()][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Segment
    )
    $segs = @(Split-PackPathKey $Path)
    if ($segs.Count -eq 0) { return $false }
    foreach ($s in $Segment) {
        $key = ConvertTo-PackPathKey $s
        if ($key -and ($segs -contains $key)) { return $true }
    }
    return $false
}

function Convert-PackPathToPosix {
    # A Windows path as the given bash understands it. There is no single answer: Git bash maps
    # D:\x to /d/x and WSL maps it to /mnt/d/x, so code that hardcodes either mapping breaks the
    # moment the machine grows the other bash. That is not hypothetical - `bash` on PATH is
    # System32\bash.exe (WSL) once WSL is installed, and it takes precedence over Git bash, so a
    # probe that had passed for releases started reporting "No such file or directory" on a machine
    # where nothing about the pack had changed.
    #
    # Each flavour ships its own translator, so ask the shell instead of guessing: cygpath under
    # Git bash, wslpath under WSL. The old mapping stays only as a last resort.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$BashExe
    )
    if (-not (Test-PackIsWindows)) { return $Path }
    if ($BashExe -and (Test-Path -LiteralPath $BashExe)) {
        $translate = "if command -v cygpath >/dev/null 2>&1; then cygpath -u '$Path'; " +
            "elif command -v wslpath >/dev/null 2>&1; then wslpath -u '$Path'; else echo ''; fi"
        $out = (& $BashExe -lc $translate 2>$null | Out-String).Trim()
        if ($out) { return $out }
    }
    $posix = $Path -replace '\\', '/'
    if ($posix -match '^([A-Za-z]):(.*)$') { return '/' + $Matches[1].ToLowerInvariant() + $Matches[2] }
    return $posix
}

function Get-PackScriptRunner {
    # How to execute $ScriptPath on this OS, decided by extension rather than by guessing.
    #
    # The audit's test phase ran every project's test script through `cmd.exe /c`, so the whole
    # phase was Windows-only: off Windows it failed with "the term 'cmd' is not recognized", which
    # reads like a missing dependency rather than a design assumption. Extension is the honest
    # signal - a .bat is Windows-only no matter which OS asks - and returning a reason instead of
    # throwing lets the caller report a Fix that names the config key to add.
    #
    # Returns @{ exe; prefix; suffix; label } or @{ reason } when this OS cannot run the script.
    # suffix carries arguments that must follow the script path (cmd.exe redirection does not).
    param([Parameter(Mandatory = $true)][string]$ScriptPath)
    $ext = [System.IO.Path]::GetExtension($ScriptPath).ToLowerInvariant()
    switch ($ext) {
        { $_ -in @('.bat', '.cmd') } {
            if (-not (Test-PackIsWindows)) {
                return @{ reason = "$ext scripts run only on Windows (cmd.exe does not exist on this OS)" }
            }
            return @{ exe = 'cmd.exe'; prefix = @('/c'); suffix = @(); label = 'cmd.exe' }
        }
        '.ps1' {
            $exe = Get-PackPowerShellPath
            return @{ exe = $exe; prefix = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File'); suffix = @(); label = $exe }
        }
        '.sh' {
            $bash = Get-Command bash -ErrorAction SilentlyContinue
            if (-not $bash) {
                if (Test-PackIsWindows) {
                    return @{ reason = '.sh scripts need bash; on Windows install Git for Windows or use the .bat entry point' }
                }
                return @{ reason = '.sh scripts need bash, which was not found on PATH' }
            }
            return @{ exe = $bash.Source; prefix = @(); suffix = @(); label = $bash.Source }
        }
        '.py' {
            $py = Resolve-PackPythonInvoke
            if (-not $py) { return @{ reason = "no Python 3.8+ found. $(Get-PackPythonInstallFix)" } }
            return @{ exe = $py.exe; prefix = @($py.prefix); suffix = @(); label = "$($py.exe) $($py.prefix -join ' ')".Trim() }
        }
        default {
            return @{ reason = "unrecognised test script type '$ext' - use .ps1 (runs on every OS), .bat/.cmd, .sh or .py" }
        }
    }
}

function Expand-PackListArgument {
    <#
    .SYNOPSIS
      A list parameter's real values, however the shell delivered them.
    .DESCRIPTION
      `powershell -File script.ps1 -Targets Claude Copilot Windsurf` does not pass three values. The
      binder takes the first and drops the rest on the floor, and the comma form is no better: it
      arrives as the single string 'Claude,Copilot,Windsurf', which a ValidateSet then rejects as one
      unknown name. Neither failure is loud - the first is silent by construction.

      That is not theory. Behavior step 34 bootstrapped a project for Claude, Copilot and Windsurf,
      and got one for Claude; the two adapters it never wrote were reported as "skipped (not in
      bootstrap targets)" and the step printed OK for all three. It took a guard proof of that step
      to notice, because nothing else looks at what the project actually contains.

      Invoke-PackScript sends arguments through `-File`, so every pack entry point with a list
      parameter has this problem. Splitting here, on the comma, is the fix that works for both
      spellings and for a real array passed in-process.
    #>
    param([Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][string[]]$Value)
    $out = @()
    foreach ($item in @($Value)) {
        foreach ($part in "$item".Split(',')) {
            $t = $part.Trim()
            if ($t) { $out += $t }
        }
    }
    return @($out)
}

function Invoke-PackScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$ArgumentList = @(),
        [switch]$NoProfile,
        [switch]$PassOutput,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$ScriptArgument
    )
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Pack script not found: $ScriptPath"
    }
    $exe = Get-PackPowerShellPath
    $invokeArgs = @()
    if ($NoProfile) { $invokeArgs += '-NoProfile' }
    $invokeArgs += '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath
    $scriptArgs = @()
    if ($ArgumentList -and $ArgumentList.Count -gt 0) { $scriptArgs += $ArgumentList }
    if ($ScriptArgument -and $ScriptArgument.Count -gt 0) { $scriptArgs += $ScriptArgument }
    if ($scriptArgs.Count -gt 0) { $invokeArgs += $scriptArgs }
    # Same reason as Invoke-PackPython above: a child script writing to stderr must not terminate the
    # parent under ErrorActionPreference = 'Stop'. Several pack scripts report findings that way, and
    # a caller that dies on the first one cannot report the rest of them (WQ-475).
    $ErrorActionPreference = 'Continue'
    if ($PassOutput) {
        & $exe @invokeArgs
        return
    }
    & $exe @invokeArgs 1>$null 2>$null
    return $LASTEXITCODE
}

function Get-PackShellInfo {
    # Which shell is hosting this run, and is the other one available? Reported by doctor.ps1 and
    # check-requirements.ps1 because the hosting split is invisible otherwise: the .cmd entry points and
    # nested calls pin themselves to powershell 5.1, while running a script directly from a pwsh prompt
    # hosts it on 7. Developing on one host and shipping to the other is how encoding bugs get in.
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        hostVersion   = $PSVersionTable.PSVersion.ToString()
        hostEdition   = "$($PSVersionTable.PSEdition)"
        isCore        = ($PSVersionTable.PSEdition -eq 'Core')
        floorVersion  = '5.1'
        pwshAvailable = [bool]$pwshCmd
        pwshPath      = if ($pwshCmd) { $pwshCmd.Source } else { $null }
    }
}

# SHA256 for drift checks - works when Get-FileHash is unavailable (e.g. nested PS 2.0 host).
function Test-PackGitRepo {
    <#
      "Is this a git work tree?" and "does a .git entry exist?" are different questions, and every
      guard in this pack that asked the second one meant the first. The gap is not hypothetical:
      deleting a repository can leave a .git directory behind holding an editor's index cache, and a
      worktree or a submodule records .git as a *file* rather than a directory. In all three cases a
      path test answers yes and the very next git command answers "fatal: not a git repository" - so
      the guard reports that it checked something and the work fails underneath it, which is the
      WQ-443 shape one layer out.

      Ask git, and treat any non-zero exit as "not usable here" - unreadable is the same outcome as
      absent for every caller. safe.directory=* is set because ownership is a property of the disk,
      not of the repository: a checkout on removable or foreign-owned media is a repo git can read
      perfectly well once told to, and refusing it would reintroduce a false negative on exactly the
      media this pack is carried on.
    #>
    # AllowEmptyString because a caller passing an unset root is asking the same question as one
    # passing a missing path, and a parameter-binding exception is a worse answer than $false.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Root)
    if (-not $Root) { return $false }
    if (-not (Test-Path -LiteralPath $Root)) { return $false }
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) { return $false }
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $answer = (& $gitCmd.Source -c safe.directory=* -C $Root rev-parse --is-inside-work-tree 2>&1 |
            Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join ''
        return (($LASTEXITCODE -eq 0) -and ($answer -match 'true'))
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $prior
    }
}

function Test-PackGitRoot {
    <#
      True when $Root is the top-level directory of the git work tree git sees from there.
      A subdirectory inside a repository answers yes to Test-PackGitRepo but is not the root -
      verify-work-queue's Done-log cite comparison must run only at the root, or git show HEAD:docs/...
      resolves against the repository root and compares the wrong file (behavior fixture, WQ-461).
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Root)
    if (-not (Test-PackGitRepo -Root $Root)) { return $false }
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) { return $false }
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $top = (& $gitCmd.Source -c safe.directory=* -C $Root rev-parse --show-toplevel 2>&1 |
            Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join ''
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($top)) { return $false }
        return ((Resolve-Path -LiteralPath $Root).Path -eq (Resolve-Path -LiteralPath $top).Path)
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $prior
    }
}

function Get-PackOrphanAlwaysOnRule {
    <#
      Rule files in a profile rules folder that declare alwaysApply:true and that the pack does not
      ship. They are inert - no editor documents reading that folder (WQ-456) - but they read as
      authoritative to anyone who opens them, which is worse than being absent. One such file
      declared itself always-on, "referenced from agent-defaults-always.mdc" and "the canonical
      copy" for months; all three claims were false (WQ-460).

      `install.ps1 -Prune` cannot reach them by design: pruning removes what a previous install
      recorded shipping, and an orphan is by definition absent from that record.

      Only alwaysApply:true files are returned. An orphan that makes no always-on claim is somebody's
      private note rather than a false claim, and reporting it would train the reader to ignore the
      report that matters.

      Lives here, and not inline in doctor.ps1, because the behavior suite has to be able to test it:
      doctor.ps1 calls verify-audit-system.ps1, which runs the behavior suite, so a step that shelled
      out to doctor recursed until it was killed.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ProfileRulesDir,
        [string[]]$ShippedRuleNames = @()
    )
    if (-not $ProfileRulesDir) { return @() }
    if (-not (Test-Path -LiteralPath $ProfileRulesDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $ProfileRulesDir -Filter '*.mdc' -File -ErrorAction SilentlyContinue |
        Where-Object { $ShippedRuleNames -notcontains $_.Name } |
        Where-Object {
            # Front matter only. A body that merely discusses alwaysApply - as the pack's own docs do
            # when explaining this defect - is not a file claiming to be always-on.
            ((Get-Content -LiteralPath $_.FullName -TotalCount 12 -ErrorAction SilentlyContinue) -join "`n") -match
                '(?m)^\s*alwaysApply:\s*true\s*$'
        })
}

function Get-PackFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $bytes = $sha.ComputeHash($stream)
        } finally {
            $stream.Close()
        }
        return ([BitConverter]::ToString($bytes) -replace '-', '')
    } finally {
        $sha.Dispose()
    }
}
