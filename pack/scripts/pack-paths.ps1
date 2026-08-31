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
        $list += Join-Path $env:USERPROFILE 'OneDrive\Desktop\AgentStarterPack'
        $list += Join-Path $env:USERPROFILE 'OneDrive\Desktop\CursorAgentStarterPack'
        $desktop = [Environment]::GetFolderPath('Desktop')
        if ($desktop) {
            $list += Join-Path $desktop 'AgentStarterPack'
            $list += Join-Path $desktop 'CursorAgentStarterPack'
        }
    }
    return $list | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique
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
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
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
    if ($PassOutput) {
        & $exe @invokeArgs
        return
    }
    & $exe @invokeArgs | Out-Null
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
