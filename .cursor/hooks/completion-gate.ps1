<#
  WQ-476 stage 2 of 2 - the stage that can act. Runs on `stop`.

  `stop` is where a turn ends. Its payload carries `status` and `loop_count` - the field Cursor's hook
  guidance ties to follow-up loops - but no message text, which is why `offload-detect.ps1` runs first
  on `afterAgentResponse` and leaves a verdict on disk. This hook only decides whether to hand the
  turn back, and returns `followup_message` when it does.

  Proven end to end on 2026-09-11: the detector flagged at 09:16:09.40, this gate handed back at
  09:16:10.03, and the follow-up arrived as a turn. Before that run, "the hook emits a followup" and
  "Cursor delivers it" were two different claims and only the first was evidence.

  Three guards, because a control that can restart a turn can also trap one:

  1. `generation_id` must match. A flag from a finished turn is stale by construction, and acting on it
     would loop on a violation that is already over.
  2. `loop_count` must be 0. One handback per turn. If the agent offloads again after being told, that
     is a finding for the human to see, not something to grind on.
  3. The flag is deleted on every path, including the paths that decline to act. A flag that outlives
     its own decision is an inert artifact that still speaks with authority.

  Fails open in every sense: no flag, bad payload, or unreadable state all exit 0 with no output,
  leaving the turn exactly as it would have ended.
#>
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'hook-state.ps1')

$stateDir = Get-HookStateDir
$log  = Join-Path $stateDir 'wq476-completion-gate.log'
$flag = Join-Path $stateDir 'wq476-offload-flag.json'
function Write-Log([string]$Text) { Add-Content -Path $log -Value "$((Get-Date).ToString('o'))  $Text" }
function Clear-Flag { if (Test-Path -LiteralPath $flag) { Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue } }

# Checked before reading stdin so the common case - a clean turn - costs nothing.
if (-not (Test-Path -LiteralPath $flag)) { Write-Log 'no flag - turn ends as written'; exit 0 }

$payload = Read-HookPayload -MaxBytes 262144 -TotalSeconds 3 -SliceMs 1000
if ($null -eq $payload) { Write-Log 'flag present but payload unusable - declining to act'; Clear-Flag; exit 0 }

$gen  = [string]$payload.generation_id
$loop = 0
if ($null -ne $payload.loop_count) { $loop = [int]$payload.loop_count }

try { $flagData = Get-Content -LiteralPath $flag -Raw | ConvertFrom-Json } catch { Write-Log 'flag unparseable'; Clear-Flag; exit 0 }

if ([string]$flagData.generation_id -ne $gen) {
    Write-Log "stale flag (flag gen=$($flagData.generation_id), stop gen=$gen) - discarded"
    Clear-Flag
    exit 0
}

if ($loop -ge 1) {
    Write-Log "loop guard: loop_count=$loop, declining a second handback for gen=$gen (reason was $($flagData.reason))"
    Clear-Flag
    exit 0
}

$reason   = [string]$flagData.reason
$evidence = [string]$flagData.evidence

if ($reason -eq 'selftest') {
    $message = @"
WQ-476 self-test: this follow-up was produced by the completion gate, not by the human.
It proves the control can hand a turn back. Evidence: $evidence

Say so plainly in your next message - that the handback arrived, and that the control is therefore
proven end to end rather than installed and assumed. Then carry on with your work.
"@
} elseif ($reason -eq 'settled') {
    $message = @"
STOP - you were about to end this turn by asking the owner to decide something already decided.

Evidence: $evidence

Read the recorded decision before you write anything else. It is settled, and asking again does not
just waste the turn - it tells the owner their answer did not stick, which is why this check exists.

Rewrite the ending: drop the ask, state what the decision means for the work in front of you, and
carry on. If the decision genuinely does not cover your case, say precisely which part it leaves open
- do not restate the whole question.
"@
} else {
    $message = @"
STOP - you were about to end this turn by asking the human to run something you are cleared to run.

Evidence: $evidence

The agent-defaults rule 'Fixes the agent runs (do not offload)' forbids exactly this, and
preapproved.json lists that command as one a hook already approves for unattended execution - so no
reviewer is in your way and there is no blocker to name.

Run it now, report the paths, stdout highlights and exit code, and remove it from the ask section. If
something genuinely prevents you - and a per-call review prompt is not that, because the approval card
is a retry you are expected to use - then name the blocker and say what remains unverified.
"@
}

Write-Log "HANDBACK reason=$reason gen=$gen"
Clear-Flag
[Console]::Out.Write((@{ followup_message = $message } | ConvertTo-Json -Compress))
exit 0
