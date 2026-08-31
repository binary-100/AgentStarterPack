#Requires -Version 5.1
<#
.SYNOPSIS
  Thin alias: ensure handoffs dirs + WORK_COMPLETION overlay (calls ensure-work-completion.ps1).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [string]$PackRoot = '',
    [string]$ProjectName = ''
)

. (Join-Path $PSScriptRoot 'pack-paths.ps1')
$self = Join-Path $PSScriptRoot 'ensure-work-completion.ps1'
$exit = Invoke-PackScript -NoProfile -ScriptPath $self @PSBoundParameters
exit $exit
