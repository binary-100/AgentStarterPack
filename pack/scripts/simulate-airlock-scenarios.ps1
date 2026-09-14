#Requires -Version 5.1
<#
.SYNOPSIS
  Pre-implementation simulations for StarterPack-Airlock discovery and layout.
.DESCRIPTION
  Builds temporary filesystem layouts under Get-PackTempDir - never touches the real Desktop.
  Discovery uses Find-StarterPackAirlock from pack-paths.ps1 (Phase 1); layout builders stay sim-only.
  Exit 0 when all scenarios pass; non-zero lists failures.
#>
param(
    [switch]$KeepTemp,
    [switch]$IncludeHeavy
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')
. (Join-Path $PSScriptRoot 'agent-policy-lib.ps1')

$PackRoot = if ($env:AGENT_STARTER_PACK_ROOT) { $env:AGENT_STARTER_PACK_ROOT } else {
    $r = Get-CheckoutAgentStarterPack
    if (-not $r) { $r = Get-AgentStarterPackRoot }
    $r
}
if (-not $PackRoot -or -not (Test-Path -LiteralPath $PackRoot)) {
    Write-Error 'Cannot resolve pack root. Run from the maintainer checkout or set AGENT_STARTER_PACK_ROOT.'
}

$SimRoot = Join-Path (Get-PackTempDir) "AgentStarterPack-airlock-sim-$PID"
if (Test-Path -LiteralPath $SimRoot) { Remove-Item -LiteralPath $SimRoot -Recurse -Force }
New-Item -ItemType Directory -Path $SimRoot -Force | Out-Null

$script:Pass = 0
$script:Fail = 0
$script:Gaps = [System.Collections.Generic.List[string]]::new()

function Write-ScenarioResult {
    param([string]$Id, [string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) {
        $script:Pass++
        Write-Host "[PASS] $Id - $Name" -ForegroundColor Green
    } else {
        $script:Fail++
        Write-Host "[FAIL] $Id - $Name" -ForegroundColor Red
    }
    if ($Detail) { Write-Host "       $Detail" }
}

function Add-Gap {
    param([string]$Text)
    if ($script:Gaps -notcontains $Text) { [void]$script:Gaps.Add($Text) }
}

#region Discovery (product: pack-paths.ps1 Find-StarterPackAirlock; sim-only merge helper below)

function Merge-SimRequiredReads {
    param(
        [string[]]$BaseReads,
        $AirlockDiscovery
    )
    return Merge-StarterPackAirlockRequiredReads -BaseReads $BaseReads -AirlockDiscovery $AirlockDiscovery
}

#endregion

#region Layout builders

function New-SimMinimalWorkingCopy {
    param([Parameter(Mandatory = $true)][string]$Root)
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root '.agent-control') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PackRoot 'pack/templates/agent-control/policy.json') `
        -Destination (Join-Path $Root '.agent-control/policy.json') -Force
    Write-Utf8NoBom -Path (Join-Path $Root 'VERSION') -Text "1.8.0`r`n"
    New-Item -ItemType Directory -Path (Join-Path $Root 'docs') -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $Root 'docs/WORK_QUEUE.md') -Text "# sim`r`n"
    Write-Utf8NoBom -Path (Join-Path $Root 'AGENTS.md') -Text "sim`r`n"
}

function New-SimAirlockLayout {
    param(
        [Parameter(Mandatory = $true)][string]$DesktopRoot,
        [string]$KeyId = 'sim-publisher-key',
        [switch]$OmitKey,
        [switch]$WrongKey,
        [switch]$OmitOverlayFile,
        [switch]$WithRepoGit
    )
    $airlock = Join-Path $DesktopRoot 'StarterPack-Airlock'
    $overlay = Join-Path $airlock 'overlay'
    $repo = Join-Path $airlock 'repo'
    New-Item -ItemType Directory -Path $overlay -Force | Out-Null
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    $materialize = Join-Path $PackRoot 'pack/scripts/materialize-starter-pack-airlock-templates.ps1'
    if (-not (Test-Path -LiteralPath $materialize)) { throw "materialize script missing: $materialize" }
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $materialize `
        -PackRoot $PackRoot -AirlockRoot $airlock -PublisherKeyId $KeyId 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'New-SimAirlockLayout: overlay materialize failed' }

    if ($OmitOverlayFile) {
        $requiredReads = @('overlay/docs/WORK_QUEUE.md', 'overlay/docs/MISSING.md')
        $manifest = @{
            schema        = 1
            keyId         = $KeyId
            repoDir       = 'repo'
            overlayDir    = 'overlay'
            requiredReads = $requiredReads
        } | ConvertTo-Json -Depth 5
        Write-Utf8NoBom -Path (Join-Path $overlay 'manifest.json') -Text ($manifest + "`r`n")
    }

    if (-not $OmitKey) {
        $keyVal = if ($WrongKey) { 'wrong-key-content' } else { $KeyId }
        Write-Utf8NoBom -Path (Join-Path $airlock 'publisher.key') -Text $keyVal
    }

    if ($WithRepoGit) {
        $git = Get-Command git -ErrorAction SilentlyContinue
        if (-not $git) { throw 'git required for WithRepoGit simulation arm' }
        if (-not (Invoke-SimGitInit -Root $repo)) { throw 'WithRepoGit: git init/commit failed in repo/' }
    }

    return $airlock
}

function Invoke-SimGitCommand {
    param([Parameter(Mandatory = $true)][scriptblock]$Command)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Command 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } finally { $ErrorActionPreference = $prev }
}

function Invoke-SimGitInit {
    param([Parameter(Mandatory = $true)][string]$Root)
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return $false }
    Push-Location $Root
    try {
        if (Test-Path -LiteralPath '.git') { return $true }
        if (-not (Invoke-SimGitCommand { git init -q })) { return $false }
        $seed = Join-Path $Root 'sim.txt'
        Write-Utf8NoBom -Path $seed -Text "x`r`n"
        if (-not (Test-Path -LiteralPath $seed)) { return $false }
        if (-not (Invoke-SimGitCommand { git add sim.txt })) { return $false }
        if (-not (Invoke-SimGitCommand { git -c user.email=sim@local -c user.name=sim commit -m 'sim' -q })) { return $false }
        return $true
    } finally { Pop-Location }
}

function Move-SimGitToRepo {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingCopy,
        [Parameter(Mandatory = $true)][string]$RepoDir
    )
    $result = Move-PackGitToAirlockRepo -WorkingCopy $WorkingCopy -RepoDir $RepoDir
    return ($result -eq 'migrated')
}

function Get-SimManifestList {
    param([Parameter(Mandatory = $true)][string]$Key)
    $manifestPath = Join-Path $PackRoot 'pack/audit/manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { return @() }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($manifest.$Key)
}

function Invoke-SimRobocopyMirror {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Dest
    )
    if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    $null = robocopy $Source $Dest /MIR /XD .git .tmp __pycache__ .pytest_cache /NFL /NDL /NJH /NJS /nc /ns /np 2>&1
}

function Invoke-SimStripExportPaths {
    param([Parameter(Mandatory = $true)][string]$TreeRoot)
    foreach ($rel in (Get-SimManifestList -Key 'maintainerOnlyPaths')) {
        if ([string]::IsNullOrWhiteSpace([string]$rel)) { continue }
        $abs = Join-Path $TreeRoot ([string]$rel)
        if (Test-Path -LiteralPath $abs) { Remove-Item -LiteralPath $abs -Recurse -Force -ErrorAction SilentlyContinue }
    }
    foreach ($rel in (Get-SimManifestList -Key 'machineLocalPaths')) {
        if ([string]::IsNullOrWhiteSpace([string]$rel)) { continue }
        $abs = Join-Path $TreeRoot ([string]$rel)
        if (Test-Path -LiteralPath $abs) { Remove-Item -LiteralPath $abs -Recurse -Force -ErrorAction SilentlyContinue }
    }
    foreach ($rel in (Get-SimManifestList -Key 'repoOnlyPaths')) {
        if ([string]::IsNullOrWhiteSpace([string]$rel)) { continue }
        $abs = Join-Path $TreeRoot ([string]$rel)
        if (Test-Path -LiteralPath $abs) { Remove-Item -LiteralPath $abs -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $gitPath = Join-Path $TreeRoot '.git'
    if (Test-Path -LiteralPath $gitPath) { Remove-Item -LiteralPath $gitPath -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SimExportHygiene {
    param([Parameter(Mandatory = $true)][string]$TreeRoot)
    $leaks = @()
    foreach ($rel in (Get-SimManifestList -Key 'maintainerOnlyPaths')) {
        if ([string]::IsNullOrWhiteSpace([string]$rel)) { continue }
        $abs = Join-Path $TreeRoot ([string]$rel)
        if (Test-Path -LiteralPath $abs) { $leaks += "maintainerOnly: $rel" }
    }
    foreach ($rel in (Get-SimManifestList -Key 'machineLocalPaths')) {
        if ([string]::IsNullOrWhiteSpace([string]$rel)) { continue }
        $abs = Join-Path $TreeRoot ([string]$rel)
        if (Test-Path -LiteralPath $abs) { $leaks += "machineLocal: $rel" }
    }
    foreach ($rel in (Get-SimManifestList -Key 'repoOnlyPaths')) {
        if ([string]::IsNullOrWhiteSpace([string]$rel)) { continue }
        $abs = Join-Path $TreeRoot ([string]$rel)
        if (Test-Path -LiteralPath $abs) { $leaks += "repoOnly: $rel" }
    }
    if (Test-Path -LiteralPath (Join-Path $TreeRoot '.git')) { $leaks += '.git present' }
    return ($leaks.Count -eq 0), $leaks
}

function Test-SimRepoSyncHygiene {
    param([Parameter(Mandatory = $true)][string]$TreeRoot)
    $leaks = @()
    foreach ($rel in (Get-SimManifestList -Key 'maintainerOnlyPaths')) {
        if ([string]::IsNullOrWhiteSpace([string]$rel)) { continue }
        $abs = Join-Path $TreeRoot ([string]$rel)
        if (Test-Path -LiteralPath $abs) { $leaks += "maintainerOnly: $rel" }
    }
    foreach ($rel in (Get-SimManifestList -Key 'machineLocalPaths')) {
        if ([string]::IsNullOrWhiteSpace([string]$rel)) { continue }
        $abs = Join-Path $TreeRoot ([string]$rel)
        if (Test-Path -LiteralPath $abs) { $leaks += "machineLocal: $rel" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $TreeRoot '.git'))) { $leaks += '.git missing (Zone B needs repo git)' }
    $wf = Join-Path $TreeRoot '.github/workflows/pack-os-smoke.yml'
    if (-not (Test-Path -LiteralPath $wf)) { $leaks += 'repo-only CI workflow missing (.github/workflows/pack-os-smoke.yml)' }
    return ($leaks.Count -eq 0), $leaks
}

function Test-SimVersionDrift {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingCopy,
        [Parameter(Mandatory = $true)][string]$RepoCopy
    )
    $wcPath = Join-Path $WorkingCopy 'VERSION'
    $repoPath = Join-Path $RepoCopy 'VERSION'
    if (-not (Test-Path -LiteralPath $wcPath) -or -not (Test-Path -LiteralPath $repoPath)) { return $false }
    $wc = (Get-Content -LiteralPath $wcPath -Raw).Trim()
    $repo = (Get-Content -LiteralPath $repoPath -Raw).Trim()
    return ($wc -ne $repo)
}

#endregion

Write-Host "`n=== StarterPack-Airlock simulations ===" -ForegroundColor Cyan
Write-Host "Sim root: $SimRoot"
Write-Host "Pack root: $PackRoot`n"

# --- S01: No Airlock ---
$s01Desktop = Join-Path $SimRoot 'S01/desktop'
New-Item -ItemType Directory -Path $s01Desktop -Force | Out-Null
$wc01 = Join-Path $SimRoot 'S01/working'
New-SimMinimalWorkingCopy -Root $wc01
$disc01 = Find-StarterPackAirlock -DesktopRoots @($s01Desktop)
$s01Ok = ($null -eq $disc01) -and (-not (Test-PackGitRepo -Root $wc01))
Write-ScenarioResult -Id 'S01' -Name 'No Airlock folder' -Ok $s01Ok -Detail $(if ($disc01) { 'discovery should be null' } else { 'discovery null; working copy git-free' })

# --- S02: Valid Airlock ---
$s02Desktop = Join-Path $SimRoot 'S02/desktop'
New-Item -ItemType Directory -Path $s02Desktop -Force | Out-Null
$null = New-SimAirlockLayout -DesktopRoot $s02Desktop -WithRepoGit
$disc02 = Find-StarterPackAirlock -DesktopRoots @($s02Desktop)
$merged02 = Merge-SimRequiredReads -BaseReads @((Join-Path $wc01 'AGENTS.md')) -AirlockDiscovery $disc02
$s02Ok = ($null -ne $disc02) -and ($disc02.RequiredReads.Count -ge 2) -and ($merged02.Count -ge 3)
Write-ScenarioResult -Id 'S02' -Name 'Valid Airlock (key + manifest + overlay + repo git)' -Ok $s02Ok `
    -Detail $(if ($disc02) { "requiredReads=$($disc02.RequiredReads.Count); repo git=$(Test-PackGitRepo -Root $disc02.RepoPath)" } else { 'discovery failed' })

# --- S03: No publisher.key ---
$s03Desktop = Join-Path $SimRoot 'S03/desktop'
New-Item -ItemType Directory -Path $s03Desktop -Force | Out-Null
$null = New-SimAirlockLayout -DesktopRoot $s03Desktop -OmitKey
$disc03 = Find-StarterPackAirlock -DesktopRoots @($s03Desktop)
Write-ScenarioResult -Id 'S03' -Name 'Airlock without publisher.key' -Ok ($null -eq $disc03) -Detail 'fail closed'

# --- S04: Wrong key ---
$s04Desktop = Join-Path $SimRoot 'S04/desktop'
New-Item -ItemType Directory -Path $s04Desktop -Force | Out-Null
$null = New-SimAirlockLayout -DesktopRoot $s04Desktop -WrongKey
$disc04 = Find-StarterPackAirlock -DesktopRoots @($s04Desktop)
Write-ScenarioResult -Id 'S04' -Name 'Airlock with wrong publisher.key' -Ok ($null -eq $disc04)

# --- S05: Nested path inside git repo (Desktop pre-migration shape) ---
$s05Root = Join-Path $SimRoot 'S05/git-parent'
New-SimMinimalWorkingCopy -Root $s05Root
$nested = Join-Path $s05Root 'pack/audit/behavior-fixture'
New-Item -ItemType Directory -Path $nested -Force | Out-Null
if (Invoke-SimGitInit -Root $s05Root) {
    $repoYes = Test-PackGitRepo -Root $nested
    $rootNo = -not (Test-PackGitRoot -Root $nested)
    Write-ScenarioResult -Id 'S05' -Name 'Nested path inside git repo' -Ok ($repoYes -and $rootNo) `
        -Detail "Test-PackGitRepo=$repoYes; Test-PackGitRoot=$([bool](Test-PackGitRoot -Root $nested)) (expect true/false)"
} else {
    Write-ScenarioResult -Id 'S05' -Name 'Nested path inside git repo' -Ok $false -Detail 'git not available'
    Add-Gap 'S05 skipped - git not on PATH'
}

# --- S06: Git only in repo/, working copy git-free ---
$s06Desktop = Join-Path $SimRoot 'S06/desktop'
New-Item -ItemType Directory -Path $s06Desktop -Force | Out-Null
$null = New-SimAirlockLayout -DesktopRoot $s06Desktop -WithRepoGit
$wc06 = Join-Path $SimRoot 'S06/working'
New-SimMinimalWorkingCopy -Root $wc06
$disc06 = Find-StarterPackAirlock -DesktopRoots @($s06Desktop)
$s06Ok = (-not (Test-PackGitRepo -Root $wc06)) -and ($null -ne $disc06) -and (Test-PackGitRoot -Root $disc06.RepoPath)
Write-ScenarioResult -Id 'S06' -Name 'Git only in Airlock repo/' -Ok $s06Ok `
    -Detail "working git=$(Test-PackGitRepo -Root $wc06); repo git root=$(Test-PackGitRoot -Root $disc06.RepoPath)"

# --- S07: Export excludes .git / .github ---
$s07Out = Join-Path $SimRoot 'S07'
$s07Zip = Join-Path $s07Out 'export.zip'
New-Item -ItemType Directory -Path $s07Out -Force | Out-Null
$s07Ok = $false
$s07Detail = ''
try {
    $exportScript = Join-Path $PackRoot 'export.ps1'
    & $exportScript -OutDir $s07Out 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "export.ps1 exit $LASTEXITCODE" }
    $zip = Get-ChildItem -LiteralPath $s07Out -Filter 'AgentStarterPack-*.zip' | Select-Object -First 1
    if (-not $zip) { throw 'no zip produced' }
    $extract = Join-Path $s07Out 'extracted'
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
    New-Item -ItemType Directory -Path $extract -Force | Out-Null
    if (-not ('System.IO.Compression.ZipFile' -as [type])) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip.FullName, $extract)
    $hasGit = Test-Path -LiteralPath (Join-Path $extract '.git')
    $hasGithub = Test-Path -LiteralPath (Join-Path $extract '.github')
    $s07Ok = (-not $hasGit) -and (-not $hasGithub)
    $s07Detail = "zip=$($zip.Name); .git=$hasGit; .github=$hasGithub"
} catch {
    $s07Detail = $_.Exception.Message
    Add-Gap "S07 export simulation: $($_.Exception.Message)"
}
Write-ScenarioResult -Id 'S07' -Name 'Export working copy has no .git/.github' -Ok $s07Ok -Detail $s07Detail

# --- S08: OneDrive-style Desktop path ---
$s08Desktop = Join-Path $SimRoot 'S08/OneDrive/Desktop'
New-Item -ItemType Directory -Path $s08Desktop -Force | Out-Null
$null = New-SimAirlockLayout -DesktopRoot $s08Desktop
$disc08 = Find-StarterPackAirlock -DesktopRoots @(
    (Join-Path $SimRoot 'S08/OneDrive/Desktop'),
    (Join-Path $SimRoot 'S08/other-desktop')
)
Write-ScenarioResult -Id 'S08' -Name 'Airlock on OneDrive-style Desktop' -Ok ($null -ne $disc08) `
    -Detail $(if ($disc08) { $disc08.AirlockRoot } else { 'not found' })

# --- S09: Incomplete overlay ---
$s09Desktop = Join-Path $SimRoot 'S09/desktop'
New-Item -ItemType Directory -Path $s09Desktop -Force | Out-Null
$null = New-SimAirlockLayout -DesktopRoot $s09Desktop -OmitOverlayFile
$disc09 = Find-StarterPackAirlock -DesktopRoots @($s09Desktop)
Write-ScenarioResult -Id 'S09' -Name 'Overlay manifest references missing file' -Ok ($null -eq $disc09) -Detail 'fail closed on incomplete overlay'

# --- S10: Bootstrap does not create Airlock ---
$s10App = Join-Path $SimRoot 'S10/MyApp'
New-Item -ItemType Directory -Path $s10App -Force | Out-Null
$bootstrap = Join-Path $PackRoot 'pack/scripts/bootstrap-project.ps1'
& $bootstrap -ProjectRoot $s10App -ProjectName 'MyApp' -Stack Generic -NoPause 2>&1 | Out-Null
$hasPolicy = Test-Path -LiteralPath (Join-Path $s10App '.agent-control/policy.json')
$airlockOnDesktop = Test-Path -LiteralPath (Join-Path $SimRoot 'S10/desktop/StarterPack-Airlock')
$s10Ok = $hasPolicy -and (-not $airlockOnDesktop)
Write-ScenarioResult -Id 'S10' -Name 'Bootstrap delivers policy, not Airlock' -Ok $s10Ok `
    -Detail "policy=$hasPolicy; spurious Airlock=$airlockOnDesktop"

# --- S11: Policy settled without Airlock ---
$s11Policy = Get-PackAgentPolicy -Path (Join-Path $PackRoot '.agent-control/policy.json')
$s11Problems = Test-PackAgentPolicyShape -Policy $s11Policy
$s11Publish = @($s11Policy.settled | Where-Object { [string]$_.pattern -like '*publish*' })
$s11Ok = ($s11Problems.Count -eq 0) -and ($s11Publish.Count -ge 1) -and ($s11Publish[0].decision -match 'StarterPack-Airlock')
Write-ScenarioResult -Id 'S11' -Name 'Working-copy policy settled prose' -Ok $s11Ok `
    -Detail $(if ($s11Ok) { 'publish settled without Airlock present' } else { ($s11Problems -join '; ') })

# --- S12: Migrate .git working copy to repo/ ---
$s12Desktop = Join-Path $SimRoot 'S12/desktop'
New-Item -ItemType Directory -Path $s12Desktop -Force | Out-Null
$air12 = New-SimAirlockLayout -DesktopRoot $s12Desktop
$wc12 = Join-Path $SimRoot 'S12/working'
New-SimMinimalWorkingCopy -Root $wc12
$migrated = $false
if (Invoke-SimGitInit -Root $wc12) {
    $repo12 = Join-Path $air12 'repo'
    $migrated = Move-SimGitToRepo -WorkingCopy $wc12 -RepoDir $repo12
}
$s12Ok = $migrated -and (-not (Test-PackGitRepo -Root $wc12)) -and (Test-PackGitRepo -Root (Join-Path $air12 'repo'))
Write-ScenarioResult -Id 'S12' -Name 'Migrate .git from working copy to repo/' -Ok $s12Ok `
    -Detail "migrated=$migrated; wc git=$(Test-PackGitRepo -Root $wc12); repo git=$(Test-PackGitRepo -Root (Join-Path $air12 'repo'))"
if (-not $migrated) { Add-Gap 'S12: git migrate simulation needs git on PATH and writable .git move' }

# --- S13: Dual desktop - first valid wins ---
$s13A = Join-Path $SimRoot 'S13/desktop-a'
$s13B = Join-Path $SimRoot 'S13/desktop-b'
New-Item -ItemType Directory -Path $s13A -Force | Out-Null
New-Item -ItemType Directory -Path $s13B -Force | Out-Null
$null = New-SimAirlockLayout -DesktopRoot $s13A -KeyId 'key-a'
# B has folder but invalid key
$null = New-SimAirlockLayout -DesktopRoot $s13B -KeyId 'key-b' -WrongKey
$disc13 = Find-StarterPackAirlock -DesktopRoots @($s13A, $s13B)
$s13Ok = ($null -ne $disc13) -and ($disc13.DesktopRoot -eq $s13A)
Write-ScenarioResult -Id 'S13' -Name 'First valid Desktop Airlock wins' -Ok $s13Ok `
    -Detail $(if ($disc13) { "picked $($disc13.DesktopRoot)" } else { 'none' })

# --- S14: Live maintainer checkout still has git at pack root (pre-migration) ---
$s14HasGit = Test-PackGitRepo -Root $PackRoot
$s14IsRoot = Test-PackGitRoot -Root $PackRoot
Write-ScenarioResult -Id 'S14' -Name 'Live checkout git-at-root baseline' -Ok $true `
    -Detail "INFO packRoot=$PackRoot; gitRepo=$s14HasGit; gitRoot=$s14IsRoot (target after migrate: working git-free, repo/ holds git)"
if ($s14HasGit -and $s14IsRoot) {
    Add-Gap 'Desktop maintainer checkout still has .git at pack root - run Initialize-StarterPackAirlock (-GitMode Copy for parallel, or Move for full cutover)'
}

# --- S15: verify-work-queue skips Done-log cite at nested path ---
# verify-work-queue uses Test-PackGitRoot; Write-Host output is not capturable from nested calls,
# so assert the same predicate on the real behavior-fixture (nested inside this checkout's git repo).
$s15Ok = $false
$s15Detail = ''
$nested15 = Join-Path $PackRoot 'pack/audit/behavior-fixture'
if (Test-Path -LiteralPath (Join-Path $nested15 'docs/WORK_QUEUE.md')) {
    $repo15 = Test-PackGitRepo -Root $nested15
    $root15 = Test-PackGitRoot -Root $nested15
    $s15Ok = $repo15 -and (-not $root15)
    $s15Detail = "behavior-fixture gitRepo=$repo15 gitRoot=$root15 (verify-work-queue emits SKIP when repo and not root)"
} elseif (-not (Test-PackGitRepo -Root $PackRoot)) {
    $s15Detail = 'pack root not a git repo - nested SKIP probe N/A on git-free copy'
    $s15Ok = $true
} else {
    $s15Detail = 'behavior-fixture WORK_QUEUE missing'
}
Write-ScenarioResult -Id 'S15' -Name 'verify-work-queue skips nested git path' -Ok $s15Ok -Detail $s15Detail

# --- S16: B09 sync script present ---
$syncPublish = Join-Path $PackRoot 'pack/scripts/sync-working-copy-to-airlock-repo.ps1'
$s16Ok = Test-Path -LiteralPath $syncPublish
Write-ScenarioResult -Id 'S16' -Name 'B09 sync script present' -Ok $s16Ok `
    -Detail $(if ($s16Ok) { 'sync-working-copy-to-airlock-repo.ps1 shipped' } else { 'missing B09 sync script' })
if (-not $s16Ok) { Add-Gap 'No sync-working-copy-to-airlock-repo.ps1 - need working-copy to repo/ merge before publish' }

# --- S17: Git-free mirror - tree proof only (recipient audit mode) ---
$s17Root = Join-Path $SimRoot 'S17/gitfree'
if (Test-Path -LiteralPath $s17Root) { Remove-Item -LiteralPath $s17Root -Recurse -Force }
New-Item -ItemType Directory -Path $s17Root -Force | Out-Null
$robolog = robocopy $PackRoot $s17Root /MIR /XD .git .tmp __pycache__ .pytest_cache /NFL /NDL /NJH /NJS /nc /ns /np 2>&1
$s17Ok = $false
$s17Detail = ''
if (-not (Test-Path -LiteralPath (Join-Path $s17Root '.git'))) {
    try {
        $headLine = (Invoke-PackPython (Join-Path $PackRoot 'pack/scripts/audit_code_checks.py') $s17Root '--print-tests-git-head' 2>&1 |
            Select-Object -Last 1).ToString().Trim()
        $s17Ok = ($headLine -match '^tree:[0-9a-f]{64}$') -and (-not (Test-PackGitRepo -Root $s17Root))
        $s17Detail = "proof=$headLine"
    } catch {
        $s17Detail = "Python probe failed: $($_.Exception.Message)"
        Add-Gap 'S17: Python required to verify tree: proof on git-free copy'
    }
} else {
    $s17Detail = 'robocopy left .git behind'
}
Write-ScenarioResult -Id 'S17' -Name 'Git-free mirror uses tree: proof only' -Ok $s17Ok -Detail $s17Detail

# --- S18: Git-free mirror - WQ verify skips Done-log git arm ---
$s18Ok = $false
$s18Detail = ''
if (Test-Path -LiteralPath (Join-Path $s17Root 'docs/WORK_QUEUE.md')) {
    $wqScript = Join-Path $PackRoot 'pack/scripts/verify-work-queue.ps1'
    $s18Out = & powershell -NoProfile -ExecutionPolicy Bypass -File $wqScript -ProjectRoot $s17Root 2>&1 | Out-String
    $s18Ok = ($s18Out -match '\[SKIP\] not a git checkout') -and ($s18Out -match '\[OK\] WORK_QUEUE structure')
    $s18Detail = $(if ($s18Ok) { 'WQ valid; Done-log git arm skipped' } else { 'expected SKIP + OK structure' })
} else {
    $s18Detail = 'S17 mirror missing WORK_QUEUE'
}
Write-ScenarioResult -Id 'S18' -Name 'Git-free copy WQ verify skips git history' -Ok $s18Ok -Detail $s18Detail

# --- S19: Airlock repo/ uses commit+tree proof when git present ---
$s19Ok = $false
$s19Detail = ''
$s19Desktop = Join-Path $SimRoot 'S19/desktop'
New-Item -ItemType Directory -Path $s19Desktop -Force | Out-Null
$null = New-SimAirlockLayout -DesktopRoot $s19Desktop -WithRepoGit
$disc19 = Find-StarterPackAirlock -DesktopRoots @($s19Desktop)
if ($disc19 -and (Test-PackGitRoot -Root $disc19.RepoPath)) {
    $wc19 = Join-Path $SimRoot 'S19/working'
    New-SimMinimalWorkingCopy -Root $wc19
    # Copy pack-like tree into repo/ for proof probe (minimal: VERSION + docs config paths)
    New-Item -ItemType Directory -Path (Join-Path $disc19.RepoPath 'docs') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PackRoot 'docs/AUDIT.config.json') -Destination (Join-Path $disc19.RepoPath 'docs/AUDIT.config.json') -Force
    Copy-Item -LiteralPath (Join-Path $PackRoot 'docs/AUDIT.md') -Destination (Join-Path $disc19.RepoPath 'docs/AUDIT.md') -Force
    Copy-Item -LiteralPath (Join-Path $PackRoot 'VERSION') -Destination (Join-Path $disc19.RepoPath 'VERSION') -Force
    try {
        $head19 = (Invoke-PackPython (Join-Path $PackRoot 'pack/scripts/audit_code_checks.py') $disc19.RepoPath '--print-tests-git-head' 2>&1 |
            Select-Object -Last 1).ToString().Trim()
        $s19Ok = ($head19 -match '^[0-9a-f]{40}\+tree:[0-9a-f]{64}$')
        $s19Detail = "repo proof=$head19"
    } catch {
        $s19Detail = "Python probe failed: $($_.Exception.Message)"
    }
} else {
    $s19Detail = 'Airlock repo git not ready'
}
Write-ScenarioResult -Id 'S19' -Name 'Airlock repo/ uses commit+tree proof' -Ok $s19Ok -Detail $s19Detail

# --- S20: Sync/export hygiene on git-free mirror (maintainer + machineLocal stripped) ---
$s20Root = Join-Path $SimRoot 'S20/sync-target'
Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s20Root
Invoke-SimStripExportPaths -TreeRoot $s20Root
$s20Ok = $false
$s20Detail = ''
$hygieneOk, $leaks = Test-SimExportHygiene -TreeRoot $s20Root
if ($hygieneOk) {
    $s20Ok = $true
    $s20Detail = 'export-style strip leaves no maintainerOnly, machineLocal, .git, or .github (B09 must match export.ps1 + install.ps1)'
} else {
    $s20Detail = "leaks after strip: $($leaks -join '; ')"
}
Write-ScenarioResult -Id 'S20' -Name 'Sync target hygiene probe' -Ok $s20Ok -Detail $s20Detail

# --- S21: Working-copy policy refuses git push (publish is not agent-preapproved here) ---
$s21Ok = $false
$s21Detail = ''
try {
    . (Join-Path $PackRoot 'pack/templates/cursor/hooks/hook-state.ps1')
    $s21Policy = Get-PackAgentPolicy -Path (Join-Path $PackRoot '.agent-control/policy.json')
    $pushCmd = 'git push origin master'
    $matchedRefuse = $false
    foreach ($glob in @($s21Policy.shell.refuse)) {
        if (Test-GlobMatch -Text $pushCmd -Glob $glob) { $matchedRefuse = $true; break }
    }
    $s21Ok = $matchedRefuse
    $s21Detail = $(if ($matchedRefuse) { 'working-copy policy refuses git push (repo overlay policy is Phase 2/3)' } else { 'git push not in refuse list' })
} catch {
    $s21Detail = $_.Exception.Message
}
Write-ScenarioResult -Id 'S21' -Name 'Working-copy shell policy refuses git push' -Ok $s21Ok -Detail $s21Detail

# --- S22: Zone B steps 62 + 50 on full-tree repo/ (heavy) ---
if ($IncludeHeavy) {
    $s22Ok = $false
    $s22Detail = ''
    $s22Repo = Join-Path $SimRoot 'S22/repo'
    Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s22Repo
    if (Invoke-SimGitInit -Root $s22Repo) {
        $suite = Join-Path $PackRoot 'pack/scripts/verify-audit-behavior.ps1'
        $s22LogDir = Join-Path $SimRoot 'S22'
        New-Item -ItemType Directory -Path $s22LogDir -Force | Out-Null
        $s22Out62 = & powershell -NoProfile -ExecutionPolicy Bypass -File $suite -PackRoot $s22Repo -Only 62 2>&1 |
            Tee-Object -FilePath (Join-Path $s22LogDir 'behavior-62.log')
        $s22Text62 = ($s22Out62 | Out-String)
        $s22Ok62 = ($s22Text62 -notmatch '\[SKIP\].*not a git checkout') -and ($s22Text62 -match '\[OK\]|100755|mode')
        $s22Out50 = & powershell -NoProfile -ExecutionPolicy Bypass -File $suite -PackRoot $s22Repo -Only 50 2>&1 |
            Tee-Object -FilePath (Join-Path $s22LogDir 'behavior-50.log')
        $s22Text50 = ($s22Out50 | Out-String)
        $s22Ok50 = ($s22Text50 -notmatch '\[INFO\].*index check skipped') -and
            ($s22Text50 -match 'no machine-local file is tracked in git')
        $s22Ok = $s22Ok62 -and $s22Ok50
        $s22Detail = $(if ($s22Ok) {
            'steps 62+50 git index arms ran on full repo mirror'
        } else {
            "62=$s22Ok62 50=$s22Ok50 - see $s22LogDir"
        })
    } else {
        $s22Detail = 'git init failed on repo mirror'
    }
    Write-ScenarioResult -Id 'S22' -Name 'Zone B behavior steps 62+50 on full repo tree' -Ok $s22Ok -Detail $s22Detail
} else {
    Write-ScenarioResult -Id 'S22' -Name 'Zone B behavior steps 62+50 on full repo tree' -Ok $true `
        -Detail 'SKIPPED (pass -IncludeHeavy to run steps 62+50 on repo mirror)'
}

# --- S23: VERSION drift detector between working copy and repo/ ---
$s23Wc = Join-Path $SimRoot 'S23/working'
$s23Repo = Join-Path $SimRoot 'S23/repo'
Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s23Wc
Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s23Repo
Write-Utf8NoBom -Path (Join-Path $s23Wc 'VERSION') -Text "9.9.9-sim-drift`r`n"
$drift = Test-SimVersionDrift -WorkingCopy $s23Wc -RepoCopy $s23Repo
$s23Ok = $drift
Write-ScenarioResult -Id 'S23' -Name 'VERSION drift detectable pre-push' -Ok $s23Ok `
    -Detail $(if ($drift) { 'mismatch detected (B09 gate must fail closed on this)' } else { 'drift not detected' })

# --- S24: Full product audit on git-free mirror (heavy) ---
$s24AuditCmd = 'run_audit' + '.cmd'
if ($IncludeHeavy) {
    $s24Ok = $false
    $s24Detail = ''
    # S17 mirror is built early; refresh before heavy audit so manifest matches current pack.
    if (Test-Path -LiteralPath $s17Root) { Remove-Item -LiteralPath $s17Root -Recurse -Force }
    New-Item -ItemType Directory -Path $s17Root -Force | Out-Null
    $null = robocopy $PackRoot $s17Root /MIR /XD .git .tmp __pycache__ .pytest_cache /NFL /NDL /NJH /NJS /nc /ns /np 2>&1
    if (Test-Path -LiteralPath (Join-Path $s17Root $s24AuditCmd)) {
        $s24LogDir = Join-Path $SimRoot 'S24'
        New-Item -ItemType Directory -Path $s24LogDir -Force | Out-Null
        $s24Log = Join-Path $s24LogDir 'run_audit.log'
        $s24FinLog = Join-Path $s24LogDir 'finalize.log'
        Push-Location $s17Root
        try {
            $env:BUILD_NOPAUSE = '1'
            & cmd /c $s24AuditCmd 2>&1 | Tee-Object -FilePath $s24Log | Out-Null
            $pass1 = $LASTEXITCODE
            $fillScript = Join-Path $s17Root 'scripts\fill_pack_semantic_report.py'
            if (-not (Test-Path -LiteralPath $fillScript)) {
                $s24Detail = "missing fill script at $fillScript"
            } else {
                Invoke-PackPython $fillScript 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    $s24Detail = "fill exit=$LASTEXITCODE pass1=$pass1 log=$s24Log"
                } else {
                    $finRel = 'scripts\finalize' + '_audit.cmd'
                    & cmd /c $finRel 2>&1 | Tee-Object -FilePath $s24FinLog | Out-Null
                    $finExit = $LASTEXITCODE
                    # pass1 is often 1 until semantic fill; Zone A contract is finalize exit 0.
                    $s24Ok = ($finExit -eq 0)
                    $s24Detail = "pass1=$pass1 finalize=$finExit log=$s24Log fin=$s24FinLog"
                }
            }
        } finally { Pop-Location }
    } else {
        $s24Detail = "S17 mirror missing $s24AuditCmd"
    }
    Write-ScenarioResult -Id 'S24' -Name 'Full product audit on git-free mirror' -Ok $s24Ok -Detail $s24Detail
} else {
    Write-ScenarioResult -Id 'S24' -Name 'Full product audit on git-free mirror' -Ok $true `
        -Detail 'SKIPPED (pass -IncludeHeavy to run full product audit on S17 mirror)'
}

# --- S25: G01 Python git_head vs stale .git directory ---
$s25Ok = $false
$s25Detail = ''
$s25Probe = Join-Path $SimRoot 'S25/stale-git'
Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s25Probe
New-Item -ItemType Directory -Path (Join-Path $s25Probe '.git') -Force | Out-Null
Write-Utf8NoBom -Path (Join-Path $s25Probe '.git/HEAD') -Text 'ref: refs/heads/master'
try {
    $pyOut = @(Invoke-PackPython (Join-Path $PackRoot 'pack/scripts/audit_code_checks.py') $s25Probe '--print-tests-git-head' 2>&1)
    $pyLine = ($pyOut | Select-Object -Last 1).ToString().Trim()
    $psRepo = Test-PackGitRepo -Root $s25Probe
    $s25Ok = ($pyLine -match '^tree:[0-9a-f]{64}$') -and (-not $psRepo)
    $s25Detail = "python=$pyLine psRepo=$psRepo (tree-only proof; git rev-parse must fail on stale .git dir)"
    if (-not $s25Ok -and $pyOut.Count -gt 0 -and $pyLine -notmatch '^tree:') {
        $s25Detail += " stderr=$($pyOut -join ' | ')"
    }
} catch {
    $s25Detail = $_.Exception.Message
}
Write-ScenarioResult -Id 'S25' -Name 'G01 git_head parity on stale .git dir' -Ok $s25Ok -Detail $s25Detail

# --- S26: B09 publish sync dry-run (working copy -> repo/) ---
$s26Ok = $false
$s26Detail = ''
$s26Sync = Join-Path $PackRoot 'pack/scripts/sync-working-copy-to-airlock-repo.ps1'
if (-not (Test-Path -LiteralPath $s26Sync)) {
    $s26Detail = 'B09 sync script missing'
} else {
    $s26Wc = Join-Path $SimRoot 'S26/working'
    $s26Repo = Join-Path $SimRoot 'S26/repo'
    Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s26Wc
    Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s26Repo
    if (Invoke-SimGitInit -Root $s26Repo) {
        $s26Log = Join-Path $SimRoot 'S26/sync.log'
        $s26Out = & powershell -NoProfile -ExecutionPolicy Bypass -File $s26Sync `
            -WorkingCopy $s26Wc -RepoRoot $s26Repo 2>&1 | Tee-Object -FilePath $s26Log
        $s26Exit = $LASTEXITCODE
        $hygieneOk, $leaks = Test-SimRepoSyncHygiene -TreeRoot $s26Repo
        $s26Ok = ($s26Exit -eq 0) -and $hygieneOk
        $s26Detail = $(if ($s26Ok) {
            "sync exit 0; repo hygiene OK; log=$s26Log"
        } else {
            "sync exit=$s26Exit leaks=$($leaks -join '; ') log=$s26Log"
        })
        # VERSION drift gate must fail closed
        $s26DriftWc = Join-Path $SimRoot 'S26/drift-wc'
        $s26DriftRepo = Join-Path $SimRoot 'S26/drift-repo'
        Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s26DriftWc
        Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s26DriftRepo
        Write-Utf8NoBom -Path (Join-Path $s26DriftWc 'VERSION') -Text "9.9.9-sim-drift`r`n"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $s26Sync `
            -WorkingCopy $s26DriftWc -RepoRoot $s26DriftRepo 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $s26Ok = $false
            $s26Detail += ' | VERSION drift gate did not fail'
        }
    } else {
        $s26Detail = 'git init failed on repo mirror'
    }
}
Write-ScenarioResult -Id 'S26' -Name 'B09 sync working copy to repo/' -Ok $s26Ok -Detail $s26Detail

# --- S27: Full publish path Zone A sync -> Zone B audit (heavy) ---
$s27AuditCmd = 'run_audit' + '.cmd'
if ($IncludeHeavy) {
    $s27Ok = $false
    $s27Detail = ''
    $s27Sync = Join-Path $PackRoot 'pack/scripts/sync-working-copy-to-airlock-repo.ps1'
    if (-not (Test-Path -LiteralPath $s27Sync)) {
        $s27Detail = 'B09 sync script missing'
    } else {
        $s27LogDir = Join-Path $SimRoot 'S27'
        New-Item -ItemType Directory -Path $s27LogDir -Force | Out-Null
        $s27Wc = Join-Path $s27LogDir 'working'
        $s27Repo = Join-Path $s27LogDir 'repo'
        Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s27Wc
        Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s27Repo
        if (Invoke-SimGitInit -Root $s27Repo) {
            $s27SyncLog = Join-Path $s27LogDir 'sync.log'
            & powershell -NoProfile -ExecutionPolicy Bypass -File $s27Sync `
                -WorkingCopy $s27Wc -RepoRoot $s27Repo 2>&1 | Tee-Object -FilePath $s27SyncLog | Out-Null
            if ($LASTEXITCODE -ne 0) {
                $s27Detail = "sync exit=$LASTEXITCODE log=$s27SyncLog"
            } elseif (-not (Test-Path -LiteralPath (Join-Path $s27Repo $s27AuditCmd))) {
                $s27Detail = "repo missing $s27AuditCmd after sync"
            } else {
                Push-Location $s27Repo
                try {
                    $env:BUILD_NOPAUSE = '1'
                    $s27AuditLog = Join-Path $s27LogDir 'run_audit.log'
                    & cmd /c $s27AuditCmd 2>&1 | Tee-Object -FilePath $s27AuditLog | Out-Null
                    $pass1 = $LASTEXITCODE
                    $fillScript = Join-Path $s27Repo 'scripts\fill_pack_semantic_report.py'
                    Invoke-PackPython $fillScript 2>&1 | Out-Null
                    $finRel = 'scripts\finalize' + '_audit.cmd'
                    $s27FinLog = Join-Path $s27LogDir 'finalize.log'
                    & cmd /c $finRel 2>&1 | Tee-Object -FilePath $s27FinLog | Out-Null
                    $finExit = $LASTEXITCODE
                    # pass1 may be 1 until semantic fill; publish path closes on finalize exit 0.
                    $s27Ok = ($finExit -eq 0)
                    $s27Detail = $(if ($s27Ok) {
                        "sync+Zone B finalize exit 0; git push human-only (S21); logs=$s27LogDir"
                    } else {
                        "pass1=$pass1 finalize=$finExit logs=$s27LogDir"
                    })
                } finally { Pop-Location }
            }
        } else {
            $s27Detail = 'git init failed on repo mirror'
        }
    }
    Write-ScenarioResult -Id 'S27' -Name 'Publish path sync then Zone B finalize' -Ok $s27Ok -Detail $s27Detail
} else {
    Write-ScenarioResult -Id 'S27' -Name 'Publish path sync then Zone B finalize' -Ok $true `
        -Detail 'SKIPPED (pass -IncludeHeavy for sync + Zone B run_audit + finalize on repo/)'
}

# --- S28: Initialize-StarterPackAirlock.ps1 end-to-end (Phase 3) ---
$s28Ok = $false
$s28Detail = ''
$s28Init = Join-Path $PackRoot 'pack/scripts/Initialize-StarterPackAirlock.ps1'
$s28Desktop = Join-Path $SimRoot 'S28/desktop'
$s28Wc = Join-Path $SimRoot 'S28/working'
if (-not (Test-Path -LiteralPath $s28Init)) {
    $s28Detail = 'Initialize script missing'
} else {
    New-Item -ItemType Directory -Path $s28Desktop -Force | Out-Null
    Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s28Wc
    if (-not (Invoke-SimGitInit -Root $s28Wc)) {
        $s28Detail = 'git init failed on working mirror'
    } else {
        $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $s28Init `
            -WorkingCopy $s28Wc -DesktopRoot $s28Desktop -PublisherKeyId 's28-init-key' 2>&1
        if ($LASTEXITCODE -ne 0) {
            $s28Detail = "init exit=$LASTEXITCODE"
        } else {
            $air28 = Join-Path $s28Desktop 'StarterPack-Airlock'
            $repo28 = Join-Path $air28 'repo'
            $disc28 = Find-StarterPackAirlock -DesktopRoots @($s28Desktop)
            $s28Ok = ($null -ne $disc28) `
                -and (-not (Test-PackGitRepo -Root $s28Wc)) `
                -and (Test-PackGitRepo -Root $repo28) `
                -and (Test-Path -LiteralPath (Join-Path $repo28 '.github/workflows/pack-os-smoke.yml'))
            $s28Detail = "disc=$($null -ne $disc28); wcGit=$(Test-PackGitRepo -Root $s28Wc); repoGit=$(Test-PackGitRepo -Root $repo28)"
        }
    }
}
Write-ScenarioResult -Id 'S28' -Name 'Initialize-StarterPackAirlock.ps1 bootstrap' -Ok $s28Ok -Detail $s28Detail

# --- S29: Parallel init (-GitMode Copy) — both trees keep git until cutover ---
$s29Ok = $false
$s29Detail = ''
$s29Init = Join-Path $PackRoot 'pack/scripts/Initialize-StarterPackAirlock.ps1'
$s29Cut = Join-Path $PackRoot 'pack/scripts/Complete-StarterPackAirlockCutover.ps1'
$s29Desktop = Join-Path $SimRoot 'S29/desktop'
$s29Wc = Join-Path $SimRoot 'S29/working'
if (-not (Test-Path -LiteralPath $s29Init) -or -not (Test-Path -LiteralPath $s29Cut)) {
    $s29Detail = 'init or cutover script missing'
} else {
    New-Item -ItemType Directory -Path $s29Desktop -Force | Out-Null
    Invoke-SimRobocopyMirror -Source $PackRoot -Dest $s29Wc
    if (-not (Invoke-SimGitInit -Root $s29Wc)) {
        $s29Detail = 'git init failed on working mirror'
    } else {
        $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $s29Init `
            -WorkingCopy $s29Wc -DesktopRoot $s29Desktop -PublisherKeyId 's29-parallel-key' -GitMode Copy 2>&1
        if ($LASTEXITCODE -ne 0) {
            $s29Detail = "init Copy exit=$LASTEXITCODE"
        } else {
            $repo29 = Join-Path $s29Desktop 'StarterPack-Airlock/repo'
            $wcGitBefore = Test-PackGitRepo -Root $s29Wc
            $repoGitBefore = Test-PackGitRepo -Root $repo29
            $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $s29Cut `
                -WorkingCopy $s29Wc -PublishRoot $repo29 2>&1
            $cutExit = $LASTEXITCODE
            $wcGitAfter = Test-PackGitRepo -Root $s29Wc
            $repoGitAfter = Test-PackGitRepo -Root $repo29
            $s29Ok = $wcGitBefore -and $repoGitBefore -and ($cutExit -eq 0) -and (-not $wcGitAfter) -and $repoGitAfter
            $s29Detail = "before wc=$wcGitBefore repo=$repoGitBefore; cutover exit=$cutExit; after wc=$wcGitAfter repo=$repoGitAfter"
        }
    }
}
Write-ScenarioResult -Id 'S29' -Name 'Parallel init Copy then cutover' -Ok $s29Ok -Detail $s29Detail

# --- Design gap analysis (static checks) ---
Write-Host "`n--- Design gap probes (static) ---" -ForegroundColor Cyan

$refreshScript = Join-Path $PackRoot 'pack/scripts/refresh-agent-context.ps1'
$gapRefresh = (Select-String -LiteralPath $refreshScript -Pattern 'Find-StarterPackAirlock' -Quiet -ErrorAction SilentlyContinue) -and
    (Select-String -LiteralPath $refreshScript -Pattern 'Merge-StarterPackAirlockRequiredReads' -Quiet -ErrorAction SilentlyContinue)
if (-not $gapRefresh) {
    Add-Gap 'refresh-agent-context.ps1 missing Airlock overlay merge (Phase 4)'
    Write-Host '[GAP]  refresh-agent-context.ps1 - no Airlock overlay merge wired (Phase 4)' -ForegroundColor Yellow
} else {
    Write-Host '[OK]   refresh-agent-context.ps1 merges Airlock overlay requiredReads (Phase 4)' -ForegroundColor DarkGreen
}

$gapPaths = Select-String -LiteralPath (Join-Path $PackRoot 'pack/scripts/pack-paths.ps1') -Pattern 'function Find-StarterPackAirlock' -Quiet -ErrorAction SilentlyContinue
if (-not $gapPaths) {
    Add-Gap 'pack-paths.ps1 has no Find-StarterPackAirlock yet (expected pre-Phase-1)'
    Write-Host '[GAP]  pack-paths.ps1 - no Find-StarterPackAirlock (Phase 1)' -ForegroundColor Yellow
} else {
    Write-Host '[OK]   pack-paths.ps1 has Find-StarterPackAirlock (Phase 1)' -ForegroundColor DarkGreen
}

$initScript = Join-Path $PackRoot 'pack/scripts/Initialize-StarterPackAirlock.ps1'
if (-not (Test-Path -LiteralPath $initScript)) {
    Add-Gap 'Initialize-StarterPackAirlock.ps1 not present (Phase 3)'
    Write-Host '[GAP]  No Initialize-StarterPackAirlock.ps1 bootstrap script (Phase 3)' -ForegroundColor Yellow
} else {
    Write-Host '[OK]   Initialize-StarterPackAirlock.ps1 shipped (Phase 3)' -ForegroundColor DarkGreen
}

# Real Desktop: report only, do not create
$realDesktops = Get-StarterPackDesktopCandidates
$realAirlockPresent = $false
foreach ($d in $realDesktops) {
    $p = Join-Path $d 'StarterPack-Airlock'
    if (Test-Path -LiteralPath $p) { $realAirlockPresent = $true; break }
}
Write-Host "[INFO] Real Desktop Airlock present: $realAirlockPresent (candidates: $($realDesktops -join '; '))"

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Pass: $Pass  Fail: $Fail  Gaps (design, not failures): $($Gaps.Count)"
if ($Gaps.Count -gt 0) {
    Write-Host "`nDesign gaps to close before production:" -ForegroundColor Yellow
    foreach ($g in $Gaps) { Write-Host "  - $g" }
}

if (-not $KeepTemp) {
    Remove-Item -LiteralPath $SimRoot -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "Kept sim root: $SimRoot"
}

if ($Fail -gt 0) { exit 1 }
exit 0
