#Requires -Version 5.1
<#
.SYNOPSIS
  Final cutover: remove .git from the working copy after Airlock repo/ is proven (parallel mode exit).
.DESCRIPTION
  Use after parallel init (-GitMode Copy) when Zone B, CI, and publish gate are green on repo/.
  Does not touch StarterPack-Airlock/repo/.git. Fail-closed if repo/ is not a git work tree.

.PARAMETER WorkingCopy
  Pack checkout that still has .git at root. Default: script-relative checkout.
.PARAMETER PublishRoot
  Airlock repo/ path. Default: Get-AgentStarterPackPublishRoot (host Desktop discovery).
.PARAMETER WhatIf
  Print planned action without deleting.
.EXAMPLE
  .\pack\scripts\Complete-StarterPackAirlockCutover.ps1 -WorkingCopy '<pack checkout>'
#>
param(
    [string]$WorkingCopy,
    [string]$PublishRoot,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

if (-not $WorkingCopy) {
    $WorkingCopy = Get-CheckoutAgentStarterPack
    if (-not $WorkingCopy) { $WorkingCopy = Get-SourceAgentStarterPack }
}
if (-not $WorkingCopy -or -not (Test-Path -LiteralPath $WorkingCopy)) {
    Write-Host '[FAIL] WorkingCopy not found'
    exit 1
}
$WorkingCopy = (Resolve-Path -LiteralPath $WorkingCopy).Path

if (-not $PublishRoot) {
    $PublishRoot = Get-AgentStarterPackPublishRoot
}
if (-not $PublishRoot -or -not (Test-Path -LiteralPath $PublishRoot)) {
    Write-Host '[FAIL] PublishRoot not found'
    exit 1
}
$publishRoot = (Resolve-Path -LiteralPath $PublishRoot).Path
if (-not (Test-PackGitRepo -Root $publishRoot)) {
    Write-Host '[FAIL] Airlock repo/ is not an active git work tree - prove publish lane before cutover'
    Write-Host "       publishRoot=$publishRoot"
    exit 1
}

Write-Host 'Complete StarterPack-Airlock cutover (working copy -> git-free Zone A)'
Write-Host "  Working copy: $WorkingCopy"
Write-Host "  Publish repo: $publishRoot"
if ($WhatIf) { Write-Host '  Mode: WhatIf' }

if (-not (Test-PackGitRepo -Root $WorkingCopy)) {
    Write-Host '[OK] working copy already git-free - nothing to do'
    exit 0
}

$result = Remove-PackGitFromWorkingCopy -WorkingCopy $WorkingCopy -WhatIf:$WhatIf
Write-Host "[OK] working-copy .git: $result"
if ($result -eq 'remove-failed') { exit 1 }

if (-not $WhatIf) {
    $wcGit = Test-PackGitRepo -Root $WorkingCopy
    $repoGit = Test-PackGitRepo -Root $publishRoot
    Write-Host "[OK] verify: workingCopy.git=$wcGit; repo.git=$repoGit"
    if ($wcGit) {
        Write-Host '[FAIL] working copy still reports as git repo after cutover'
        exit 1
    }
    if (-not $repoGit) {
        Write-Host '[FAIL] repo/ lost git during cutover check'
        exit 1
    }
}

Write-Host 'Next: refresh agent context on the working copy, then run the publish gate before each push.'
exit 0
