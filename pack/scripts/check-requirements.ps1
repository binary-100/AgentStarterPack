#Requires -Version 5.1
<#
.SYNOPSIS
  Environment preflight - what this machine needs before install, bootstrap, or an audit will work.
.DESCRIPTION
  Runs from the pack folder with no install present, so it is the first thing to run when the pack
  arrives on a new machine. Every requirement reports OK, MISSING (required), or WARN (optional)
  together with the exact command that fixes it, so an agent can act on the output without guessing.

  Required means the audit engine cannot run at all. Optional means one feature degrades:
  no 'mcp' package -> no agent-hygiene MCP tools; no git -> audits fall back to a file-tree
  fingerprint for test-pass proof.

  ASCII only, deliberately: PowerShell 5.1 reads a UTF-8 file with no BOM as ANSI, and a mangled
  dash inside a double-quoted string can end the string early and break parsing.
.PARAMETER Fix
  Install what can be installed non-interactively: the Python packages in mcp\requirements.txt.
  Never installs a language runtime or git - those are printed as commands for the user to approve,
  because silently installing system software is not this script's call to make.
.PARAMETER Json
  Emit results as JSON for agents and doctor.ps1.
.PARAMETER Quiet
  Print problems and the summary only.
.PARAMETER PythonCommand
  Probe this interpreter instead of py / python / python3 - for a custom or non-PATH install.
#>
param(
    [switch]$Fix,
    [switch]$Json,
    [switch]$Quiet,
    [string]$PythonCommand = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

$MinPython = [version]'3.8'

$PackRoot = Get-SourceAgentStarterPack
if (-not $PackRoot) { $PackRoot = Get-AgentStarterPackRoot }

$script:Results = @()

function Add-Result {
    param(
        [string]$Name,
        [ValidateSet('ok', 'missing', 'warn')][string]$Status,
        [bool]$Required,
        [string]$Detail = '',
        [string]$Purpose = '',
        [string]$Fix = ''
    )
    $script:Results += [pscustomobject]@{
        name     = $Name
        status   = $Status
        required = $Required
        detail   = $Detail
        purpose  = $Purpose
        fix      = $Fix
    }
}

function Invoke-Probe {
    # Runs a command without letting a missing executable or non-zero exit become a terminating error.
    param([string]$Exe, [string[]]$Arguments, [string]$WorkingDirectory = '')
    $result = [pscustomobject]@{ ok = $false; output = '' }
    if (-not (Get-Command $Exe -ErrorAction SilentlyContinue)) { return $result }
    $pushed = $false
    try {
        if ($WorkingDirectory -and (Test-Path -LiteralPath $WorkingDirectory)) {
            Push-Location -LiteralPath $WorkingDirectory
            $pushed = $true
        }
        $out = & $Exe @Arguments 2>&1 | Out-String
        $result.ok = ($LASTEXITCODE -eq 0)
        $result.output = $out.Trim()
    } catch {
        $result.output = "$_"
    } finally {
        if ($pushed) { Pop-Location }
    }
    return $result
}

function Get-PythonProbe {
    return Resolve-PackPythonInvoke -PythonCommand $PythonCommand
}

function Invoke-Python {
    param($Probe, [string[]]$Arguments, [string]$WorkingDirectory = '')
    return (Invoke-Probe $Probe.exe (@($Probe.prefix) + $Arguments) -WorkingDirectory $WorkingDirectory)
}

function Test-FastMcpImport {
    # Probes the symbol the server actually imports, from outside the pack folder.
    #
    # `import mcp` is not a valid check: the pack ships its own mcp\ directory, so running the probe
    # with the pack root as the working directory imports that folder as a namespace package and
    # reports success while mcp.server.fastmcp is absent. doctor.ps1 gave that false OK for months.
    param($Probe)
    if (-not $Probe) { return $false }
    $outside = $env:TEMP
    if (-not $outside -or -not (Test-Path -LiteralPath $outside)) { $outside = [System.IO.Path]::GetTempPath() }
    $probe = Invoke-Python $Probe @('-c', 'from mcp.server.fastmcp import FastMCP') -WorkingDirectory $outside
    return $probe.ok
}

# --- PowerShell ---------------------------------------------------------------
$psv = $PSVersionTable.PSVersion
if ($psv.Major -gt 5 -or ($psv.Major -eq 5 -and $psv.Minor -ge 1)) {
    Add-Result -Name 'PowerShell 5.1+' -Status ok -Required $true -Detail "$psv"
} else {
    Add-Result -Name 'PowerShell 5.1+' -Status missing -Required $true -Detail "$psv" `
        -Purpose 'every pack script' -Fix (Get-PackPwshInstallFix)
}

# PowerShell 7 is optional and deliberately not the host: the pack's work is dozens of short-lived
# child shells, and pwsh costs roughly 250ms per launch against 130ms for 5.1, so preferring it would
# make every run slower for no new capability. Its value is verification - running the suite under both
# hosts turns cross-version correctness into a tested property instead of an assumption.
$shellInfo = Get-PackShellInfo
if ($shellInfo.pwshAvailable) {
    Add-Result -Name 'PowerShell 7 (optional)' -Status ok -Required $false `
        -Detail "available at $($shellInfo.pwshPath)" `
        -Purpose 'cross-version verification: verify-audit-behavior.ps1 -DualShell'
} else {
    Add-Result -Name 'PowerShell 7 (optional)' -Status warn -Required $false -Detail 'not installed' `
        -Purpose 'cross-version verification only - the pack runs fully on 5.1 without it' `
        -Fix "$(Get-PackPwshInstallFix)   (optional; nothing in the pack requires it)"
}
if ($shellInfo.isCore -and (Test-PackIsWindows)) {
    Add-Result -Name 'Host shell vs pack floor' -Status warn -Required $false `
        -Detail "hosted on PowerShell $($shellInfo.hostVersion) (Core); floor is $($shellInfo.floorVersion)" `
        -Purpose 'developing only on 7 hides 5.1-only behaviour (Set-Content writes a BOM there)' `
        -Fix 'powershell -NoProfile -File pack\scripts\verify-audit-behavior.ps1   (run the suite on 5.1 too)'
} elseif ($shellInfo.isCore -and -not (Test-PackIsWindows)) {
    Add-Result -Name 'Host shell vs pack floor' -Status ok -Required $false `
        -Detail "hosted on PowerShell $($shellInfo.hostVersion) (Core) - expected on macOS/Linux"
} elseif (-not $shellInfo.isCore) {
    Add-Result -Name 'Host shell vs pack floor' -Status ok -Required $false `
        -Detail "hosted on PowerShell $($shellInfo.hostVersion) (Desktop) - matches the floor"
}

# --- Python ------------------------------------------------------------------
$py = Get-PythonProbe
$pythonFix = Get-PackPythonInstallFix
if (-not $py) {
    $probed = if ($PythonCommand) { $PythonCommand } elseif (Test-PackIsWindows) { 'py, python, python3' } else { 'python3, python' }
    Add-Result -Name 'Python 3' -Status missing -Required $true -Detail "not found (probed: $probed)" `
        -Purpose 'audit machine checks, doc version sync, MCP server' -Fix $pythonFix
} elseif ($py.version -lt $MinPython) {
    Add-Result -Name 'Python 3' -Status missing -Required $true -Detail "$($py.version) via $($py.display), need $MinPython+" `
        -Purpose 'audit machine checks, doc version sync, MCP server' -Fix $pythonFix
} else {
    Add-Result -Name 'Python 3' -Status ok -Required $true -Detail "$($py.version) via $($py.display)"
}

# --- py launcher (Windows only) ------------------------------------------------
# Separate row on Windows: every .cmd and .bat calls `py -3`. Off Windows, use pwsh -File directly.
if (Test-PackIsWindows) {
    $launcher = Invoke-Probe 'py' @('-3', '--version')
    if ($launcher.ok) {
        Add-Result -Name "'py -3' launcher" -Status ok -Required $true -Detail $launcher.output
    } else {
        $detail = if ($py) { "missing (found $($py.display)) - pack .cmd scripts call py -3" } else { 'missing' }
        Add-Result -Name "'py -3' launcher" -Status missing -Required $true -Detail $detail `
            -Purpose 'run_audit.cmd, run_tests.bat and every generated project script' `
            -Fix 'install Python from python.org (bundles the py launcher) or: winget install -e --id Python.Python.3.12'
    }
} else {
    Add-Result -Name "'py -3' launcher" -Status ok -Required $false `
        -Detail 'not applicable on this OS (use pwsh -File for pack scripts; .cmd wrappers are Windows-only)'
}

# --- pip ---------------------------------------------------------------------
if ($py) {
    $pip = Invoke-Python $py @('-m', 'pip', '--version')
    if ($pip.ok) {
        Add-Result -Name 'pip' -Status ok -Required $false -Detail (($pip.output -split "`n")[0].Trim())
    } else {
        Add-Result -Name 'pip' -Status warn -Required $false -Detail 'not available' `
            -Purpose 'installing the MCP Python packages' -Fix "$($py.display) -m ensurepip --upgrade"
    }
} else {
    $pip = $null
    Add-Result -Name 'pip' -Status warn -Required $false -Detail 'skipped (no Python)' `
        -Purpose 'installing the MCP Python packages' -Fix 'install Python first'
}

# --- Audit engine actually runs ----------------------------------------------
# Presence of an interpreter is not proof the engine works on this machine - the self-test is.
$codePy = if ($PackRoot) { Get-PackScriptPath -Root $PackRoot -Name 'audit_code_checks.py' } else { $null }
if (-not $py) {
    Add-Result -Name 'Audit engine self-test' -Status missing -Required $true -Detail 'skipped (no Python)' `
        -Purpose 'run_audit.cmd on any project' -Fix 'install Python (see above), then re-run this check'
} elseif (-not $codePy -or -not (Test-Path -LiteralPath $codePy)) {
    Add-Result -Name 'Audit engine self-test' -Status missing -Required $true `
        -Detail 'audit_code_checks.py not found - incomplete pack folder' `
        -Purpose 'run_audit.cmd on any project' -Fix 'copy the full pack folder, or re-extract the export zip'
} else {
    $selfTest = Invoke-Python $py @($codePy, '--self-test')
    if ($selfTest.ok) {
        Add-Result -Name 'Audit engine self-test' -Status ok -Required $true -Detail 'audit_code_checks.py --self-test'
    } else {
        $tail = (($selfTest.output -split "`n") | Select-Object -Last 1)
        Add-Result -Name 'Audit engine self-test' -Status missing -Required $true -Detail "failed: $tail" `
            -Purpose 'run_audit.cmd on any project' -Fix "$($py.display) `"$codePy`" --self-test   (run for the full error)"
    }
}

# --- MCP package (optional) --------------------------------------------------
$reqTxt = if ($PackRoot) { Join-Path $PackRoot 'mcp\requirements.txt' } else { $null }
$pyDisplay = if ($py) { $py.display } else { 'py -3' }
$mcpFix = if ($reqTxt -and (Test-Path -LiteralPath $reqTxt)) {
    "install.ps1 -InstallMcpDeps   (or: $pyDisplay -m pip install --user -r `"$reqTxt`")"
} else {
    'install.ps1 -InstallMcpDeps'
}
$mcpOk = Test-FastMcpImport $py
if ($mcpOk) {
    Add-Result -Name "Python package 'mcp'" -Status ok -Required $false -Detail 'mcp.server.fastmcp importable'
} else {
    Add-Result -Name "Python package 'mcp'" -Status warn -Required $false -Detail 'mcp.server.fastmcp not importable' `
        -Purpose 'agent-hygiene MCP tools (audits and bootstrap work without it)' -Fix $mcpFix
}

# --- git (optional) ----------------------------------------------------------
$gitProbe = Invoke-Probe 'git' @('--version')
if ($gitProbe.ok) {
    Add-Result -Name 'git' -Status ok -Required $false -Detail $gitProbe.output
} else {
    Add-Result -Name 'git' -Status warn -Required $false -Detail 'not found' `
        -Purpose 'audit test-pass proof uses git HEAD; without it a file-tree fingerprint is used' `
        -Fix (Get-PackGitInstallFix)
}

# --- Fix pass ----------------------------------------------------------------
if ($Fix -and -not $mcpOk) {
    if ($py -and $pip -and $pip.ok -and $reqTxt -and (Test-Path -LiteralPath $reqTxt)) {
        if (-not $Json) { Write-Host "[FIX] installing MCP Python packages from $reqTxt ..." }
        Invoke-Python $py @('-m', 'pip', 'install', '--user', '-r', $reqTxt, '--quiet') | Out-Null
        $entry = $script:Results | Where-Object { $_.name -eq "Python package 'mcp'" }
        if (Test-FastMcpImport $py) {
            $entry.status = 'ok'
            $entry.detail = 'mcp.server.fastmcp importable (installed by -Fix)'
            $entry.fix = ''
            $mcpOk = $true
        } else {
            $entry.detail = 'install attempted, still not importable'
        }
    } elseif (-not $Json) {
        Write-Host '[FIX] cannot install MCP packages - Python and pip are required first.'
    }
}

# --- Report ------------------------------------------------------------------
$missing = @($script:Results | Where-Object { $_.status -eq 'missing' })
$warnings = @($script:Results | Where-Object { $_.status -eq 'warn' })

if ($Json) {
    [pscustomobject]@{
        packRoot        = $PackRoot
        packInstalled   = (Test-AgentStarterPackInstalled)
        pythonCommand   = $(if ($py) { $py.display } else { '' })
        requiredMissing = $missing.Count
        optionalMissing = $warnings.Count
        ok              = ($missing.Count -eq 0)
        results         = $script:Results
    } | ConvertTo-Json -Depth 4
    if ($missing.Count -gt 0) { exit 1 }
    exit 0
}

Write-Host "`n=== Agent Starter Pack requirements ===`n"
$rootLabel = if ($PackRoot) { $PackRoot } else { '(not resolved)' }
Write-Host "Pack folder: $rootLabel"
if (-not (Test-AgentStarterPackInstalled)) {
    Write-Host 'Installed for this profile: no (not required for this check)'
}
Write-Host ''

foreach ($r in $script:Results) {
    if ($Quiet -and $r.status -eq 'ok') { continue }
    $tag = switch ($r.status) {
        'ok' { '[OK]     ' }
        'warn' { '[WARN]   ' }
        default { '[MISSING]' }
    }
    $line = "$tag $($r.name)"
    if ($r.detail) { $line = $line + ' - ' + $r.detail }
    Write-Host $line
    if ($r.status -ne 'ok' -and $r.purpose) { Write-Host "           needed for: $($r.purpose)" }
}

$actionable = @($script:Results | Where-Object { $_.status -ne 'ok' -and $_.fix })
if ($actionable.Count -gt 0) {
    Write-Host "`nTo fix:"
    foreach ($r in $actionable) {
        $label = if ($r.required) { 'required' } else { 'optional' }
        Write-Host "  ($label) $($r.name):"
        Write-Host "      $($r.fix)"
    }
    if (-not $Fix -and @($warnings | Where-Object { $_.name -eq "Python package 'mcp'" }).Count -gt 0) {
        Write-Host "`n  Re-run with -Fix to install the Python packages automatically."
    }
}

Write-Host ''
if ($missing.Count -gt 0) {
    Write-Host "Requirements: $($missing.Count) required item(s) missing - install those before install.ps1, bootstrap, or an audit."
    exit 1
}
if ($warnings.Count -gt 0) {
    Write-Host "Requirements: OK for audits and bootstrap; $($warnings.Count) optional item(s) missing (see above)."
    exit 0
}
Write-Host 'Requirements: all present.'
exit 0
