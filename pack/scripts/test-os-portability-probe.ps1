#Requires -Version 5.1
<#
.SYNOPSIS
  Smoke-test cross-platform pack-paths and preflight on non-Windows (native or mocked via AGENT_STARTER_PACK_TEST_OS).
.PARAMETER PackRoot
  Pack checkout root (contains pack\audit\manifest.json).
.PARAMETER TestOs
  When set to linux on a Windows host, sets AGENT_STARTER_PACK_TEST_OS for mock non-Windows resolution.
#>
param(
    [Parameter(Mandatory = $true)][string]$PackRoot,
    [ValidateSet('linux', 'windows', '')][string]$TestOs = ''
)

$ErrorActionPreference = 'Stop'

$savedTestOs = $env:AGENT_STARTER_PACK_TEST_OS
$savedHome = $env:HOME
$savedUserRoot = $env:AGENT_STARTER_PACK_USER_ROOT
$tempRoot = if ($env:TEMP -and $env:TEMP.Trim()) { $env:TEMP.Trim() }
    elseif ($env:TMPDIR -and $env:TMPDIR.Trim()) { $env:TMPDIR.Trim() }
    else { [System.IO.Path]::GetTempPath() }
$fakeHome = Join-Path $tempRoot "asp-os-probe-$PID"

function Write-ProbeFail([string]$Message) {
    Write-Host "[FAIL] $Message"
    exit 1
}

function Get-HostPythonCommandForProbe {
    param([string]$PackRootPath)
    Remove-Item Env:AGENT_STARTER_PACK_TEST_OS -ErrorAction SilentlyContinue
    . (Join-Path (Join-Path (Join-Path $PackRootPath 'pack') 'scripts') 'pack-paths.ps1')
    $probe = Resolve-PackPythonInvoke
    if (-not $probe) { return $null }
    if ($probe.prefix -and $probe.prefix.Count -gt 0) {
        $out = & $probe.exe @($probe.prefix + @('-c', 'import sys; print(sys.executable)')) 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $out.Trim()) { return $out.Trim() }
    }
    if ($probe.exe -match '[\\/]') { return $probe.exe }
    $cmd = Get-Command $probe.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $probe.exe
}

try {
    $needMockPython = ($TestOs -eq 'linux')
    $hostPythonCmd = $null
    if ($needMockPython) {
        $hostPythonCmd = Get-HostPythonCommandForProbe -PackRootPath $PackRoot
        if (-not $hostPythonCmd) { Write-ProbeFail 'host Python required for mock Linux probe' }
    }

    if ($TestOs) { $env:AGENT_STARTER_PACK_TEST_OS = $TestOs }
    if (Test-Path -LiteralPath $fakeHome) {
        Remove-Item -LiteralPath $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $fakeHome -Force | Out-Null
    $env:HOME = $fakeHome
    Remove-Item Env:AGENT_STARTER_PACK_USER_ROOT -ErrorAction SilentlyContinue

    . (Join-Path (Join-Path (Join-Path $PackRoot 'pack') 'scripts') 'pack-paths.ps1')

    $expectNonWindows = if ($TestOs -eq 'linux') { $true } elseif ($TestOs -eq 'windows') { $false } else { -not (Test-PackIsWindows) }
    if ($TestOs -eq 'linux' -and (Test-PackIsWindows)) {
        Write-ProbeFail 'Test-PackIsWindows should be false when TestOs=linux'
    }
    if ($TestOs -eq 'windows' -and -not (Test-PackIsWindows)) {
        Write-ProbeFail 'Test-PackIsWindows should be true when TestOs=windows'
    }

    $cursorRoot = Get-DefaultCursorUserRoot
    $expectedRoot = Join-Path $fakeHome '.cursor'
    if ($cursorRoot.TrimEnd('\', '/') -ne $expectedRoot.TrimEnd('\', '/')) {
        Write-ProbeFail "Get-DefaultCursorUserRoot expected $expectedRoot got $cursorRoot"
    }

    $psPath = Get-PackPowerShellPath
    if ($expectNonWindows) {
        if ($psPath -notmatch '(?i)pwsh') {
            Write-ProbeFail "Get-PackPowerShellPath should resolve pwsh off Windows, got $psPath"
        }
        $pyFix = Get-PackPythonInstallFix
        if ($pyFix -match '(?i)winget') {
            Write-ProbeFail 'Get-PackPythonInstallFix should not mention winget off Windows'
        }
        if ($expectNonWindows -and $env:USERPROFILE -and $env:USERPROFILE.Trim()) {
        $candidates = @(Get-AgentStarterPackCandidates)
        $sourceRoot = Get-SourceAgentStarterPack
        # These are the Windows-only Desktop heuristics from pack-paths.ps1, spelled out so the probe
        # can assert none of them is picked off Windows. The names include the old CursorAgentStarterPack
        # folder on purpose; this file is excluded from the legacy-pack-folder-name static check for the
        # same reason pack-paths.ps1 is - it is the code that owns that list, not a stale reference to it.
        $winHeuristics = @(
            (Join-Path $env:USERPROFILE 'OneDrive/Desktop/AgentStarterPack')
            (Join-Path $env:USERPROFILE 'OneDrive/Desktop/CursorAgentStarterPack')
        )
        $desktop = [Environment]::GetFolderPath('Desktop')
        if ($desktop) {
            $winHeuristics += Join-Path $desktop 'AgentStarterPack'
            $winHeuristics += Join-Path $desktop 'CursorAgentStarterPack'
        }
        foreach ($w in ($winHeuristics | Select-Object -Unique)) {
            if (-not $w -or -not (Test-Path -LiteralPath $w)) { continue }
            if ($sourceRoot -and ((Resolve-Path -LiteralPath $w).Path -eq (Resolve-Path -LiteralPath $sourceRoot).Path)) { continue }
            if ($candidates -contains $w) {
                Write-ProbeFail "Get-AgentStarterPackCandidates should skip Windows-only heuristic off Windows: $w"
            }
        }
        }
    }

    $req = Join-Path (Join-Path (Join-Path $PackRoot 'pack') 'scripts') 'check-requirements.ps1'
    if (-not (Test-Path -LiteralPath $req)) { Write-ProbeFail 'check-requirements.ps1 missing' }
    $reqArgs = @('-Json')
    if ($needMockPython) { $reqArgs += @('-PythonCommand', $hostPythonCmd) }
    $reqJson = & $psPath -NoProfile -ExecutionPolicy Bypass -File $req @reqArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Write-ProbeFail "check-requirements -Json exit $LASTEXITCODE on probe host" }
    $start = $reqJson.IndexOf('{')
    $end = $reqJson.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { Write-ProbeFail 'check-requirements -Json produced no JSON' }
    $reqObj = ($reqJson.Substring($start, $end - $start + 1)) | ConvertFrom-Json
    if (-not $reqObj.ok) {
        $missing = @($reqObj.results | Where-Object { $_.status -eq 'missing' -and $_.required } | ForEach-Object { $_.name })
        Write-ProbeFail "check-requirements missing required: $($missing -join ', ')"
    }
    if ($expectNonWindows) {
        $launcherRow = @($reqObj.results | Where-Object { $_.name -eq "'py -3' launcher" } | Select-Object -First 1)
        if (-not $launcherRow) { Write-ProbeFail "preflight missing 'py -3' launcher row" }
        if ($launcherRow.required) { Write-ProbeFail 'py launcher should not be required off Windows' }
    }

    $echoPs1 = Join-Path $fakeHome 'echo-probe.ps1'
    Write-Utf8NoBom -Path $echoPs1 -Text "Write-Output 'invoke-ok'`r`nexit 7`r`n"
    $code = Invoke-PackScript -ScriptPath $echoPs1 -NoProfile
    if ($null -eq $code -or $code -ne 7) { Write-ProbeFail "Invoke-PackScript exit code expected 7 got $code" }

    Write-Output 'os-portability-probe-ok'
    exit 0
} finally {
    if ($null -eq $savedTestOs) { Remove-Item Env:AGENT_STARTER_PACK_TEST_OS -ErrorAction SilentlyContinue }
    else { $env:AGENT_STARTER_PACK_TEST_OS = $savedTestOs }
    if ($null -eq $savedHome) { Remove-Item Env:HOME -ErrorAction SilentlyContinue }
    else { $env:HOME = $savedHome }
    if ($null -eq $savedUserRoot) { Remove-Item Env:AGENT_STARTER_PACK_USER_ROOT -ErrorAction SilentlyContinue }
    else { $env:AGENT_STARTER_PACK_USER_ROOT = $savedUserRoot }
    if (Test-Path -LiteralPath $fakeHome) {
        Remove-Item -LiteralPath $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}
