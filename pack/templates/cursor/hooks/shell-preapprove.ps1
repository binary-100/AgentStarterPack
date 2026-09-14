<#
  Cursor ADAPTER for shell pre-approval. Runs on `beforeShellExecution` WHEN REGISTERED.

  This file is plumbing, not policy. Every pattern it decides from lives in the host-neutral
  `.agent-control/policy.json`, which OpenCode's native `permission.bash` block compiles from too.
  That separation is the answer to a real objection (WQ-480): a control whose decision data lives
  inside one host's folder is that host's control, and porting it means reimplementing the logic -
  at which point two copies drift and the drift is silent.

  NOT registered by `hooks.json.template`, and that asymmetry is deliberate. The other two hooks
  tighten what the agent gets away with, so shipping them on costs a project nothing it would want.
  This one *widens* what runs unattended, and widening someone else's review posture is not a default
  anybody gets to choose for them. Register it by adding a `beforeShellExecution` entry to
  `.cursor/hooks.json` pointing here.

  What it is for: `agent-defaults-always.mdc` obliges the agent to run its own verify, sync, test and
  process-hygiene commands rather than handing them over. When a per-call reviewer stops those, it
  manufactures exactly the excuse that rule forbids - and the excuse has been used, repeatedly, with
  a runnable sync ending up as a command for the maintainer to type.

  Design rules, in priority order:

  1. REFUSE WINS. Anything matching the policy's refuse list returns no opinion even if an allow
     pattern also matches, because allow patterns are broad and one can launch something else.
  2. NO OPINION IS THE DEFAULT. Unmatched commands print nothing and exit 0, leaving normal review in
     place. This hook only ever widens for a named list; it never narrows.
  3. ONE COMMAND PER DECISION. A line containing a statement separator is refused outright, so
     "verify-x.ps1; <anything>" cannot inherit the allow.

  Known limit, not a bug: rule 3 means a chained command never matches, so the benefit only lands
  when the agent issues single-statement commands.
#>
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'hook-state.ps1')

$log = Join-Path (Get-HookStateDir) 'wq476-shell-preapprove.log'
function Write-Log([string]$Text) { Add-Content -Path $log -Value "$((Get-Date).ToString('o'))  $Text" }
function Write-NoOpinion { Write-Log 'verdict=no-opinion'; exit 0 }

# Evidence trail. Without it, "the hook is installed" and "the hook runs" are indistinguishable - and
# the first version of this hook was installed, silent, and approving nothing for four commands
# straight while looking correct.
Write-Log 'FIRED beforeShellExecution'

$payload = Read-HookPayload -MaxBytes 262144 -TotalSeconds 3 -SliceMs 1000
if ($null -eq $payload) { Write-Log 'no usable payload'; Write-NoOpinion }

$cmd = ([string]$payload.command).Trim()
if ([string]::IsNullOrWhiteSpace($cmd)) { Write-Log 'command field empty or absent'; Write-NoOpinion }

$policy = Get-AgentPolicy
if ($null -eq $policy -or $null -eq $policy.shell) { Write-Log 'no usable .agent-control/policy.json'; Write-NoOpinion }

foreach ($glob in $policy.shell.refuse) {
    if (Test-GlobMatch -Text $cmd -Glob $glob) { Write-Log "refused by glob $glob"; Write-NoOpinion }
}
if ($cmd -match '[;&|]|`n') { Write-Log 'refused: statement separator'; Write-NoOpinion }

foreach ($glob in $policy.shell.allow) {
    if (Test-GlobMatch -Text $cmd -Glob $glob) {
        Write-Log "verdict=allow  glob=$glob  cmd=$cmd"
        # agent_message matters as much as the permission: it tells the agent the allow was a policy
        # decision rather than an accident, so a later turn does not helpfully ask permission anyway.
        [Console]::Out.Write((@{
            permission    = 'allow'
            agent_message = "Pre-approved by agent-control policy: the agent-defaults rule requires the agent to run this itself (matched glob $glob)."
        } | ConvertTo-Json -Compress))
        exit 0
    }
}

Write-NoOpinion
