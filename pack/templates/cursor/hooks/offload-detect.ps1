<#
  Cursor ADAPTER, stage 1 of 2 - the stage that can see what was said. Runs on `afterAgentResponse`.

  Policy lives in the host-neutral `.agent-control/policy.json`; this file is only the Cursor
  plumbing that reads a Cursor payload and writes a verdict. Keeping those apart is what lets the
  same policy drive OpenCode's native permission layer without anyone reimplementing the decision
  logic in TypeScript (WQ-480) - two implementations of one rule drift, and silently.

  Why this control exists at all: the rule it enforces was already written, already loaded, and
  already ignored. `agent-defaults-always.mdc` forbids ending a turn with "run X to fix" when the
  agent can run X; that paragraph sits inside ~53k characters of always-on text, was violated across
  four sessions, and was closed three times by rewording it. A sentence in chat promising compliance
  is a status field, and a status field cannot hold a proof. A hook runs whether or not the agent
  remembers the rule.

  Why two hooks rather than one - measured, not inferred from documentation:

    afterAgentResponse  carries the assistant's message in `text`, fires ~560ms earlier, cannot act
    stop                carries `status`, `loop_count`, `transcript_path` - and NO message text

  The event that can see is not the event that can act, so detection writes a verdict to disk and
  `completion-gate.ps1` acts on it.

  Scanning only the ask section is what keeps this usable rather than muted. A message that
  *discusses* offloading - a changelog entry, or any turn explaining this very rule - names those
  commands in prose without asking anyone to run them. Flagging that would train everyone to ignore
  the hook within a day, which is the recorded fate of every checker shipped without exclusions.

  Asserts nothing, blocks nothing, always exits 0.
#>
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'hook-state.ps1')

$stateDir = Get-HookStateDir
$log  = Join-Path $stateDir 'wq476-offload-detect.log'
$flag = Join-Path $stateDir 'wq476-offload-flag.json'
function Write-Log([string]$Text) { Add-Content -Path $log -Value "$((Get-Date).ToString('o'))  $Text" }

$payload = Read-HookPayload
if ($null -eq $payload) { Write-Log 'no usable payload'; exit 0 }

$text = [string]$payload.text
$gen  = [string]$payload.generation_id
if ([string]::IsNullOrWhiteSpace($text)) { Write-Log "empty text (gen=$gen)"; exit 0 }

$policy = Get-AgentPolicy
if ($null -eq $policy) { Write-Log 'no usable .agent-control/policy.json - cannot judge, staying silent'; exit 0 }

$reason   = $null
$evidence = $null

# --- self-test trigger -----------------------------------------------------------------------------
# A live way to prove this control still fires without committing a real violation to do it. Kept on
# purpose: a control nobody can exercise on demand is a control nobody notices has died. This is how
# the handback was first proven end to end rather than installed and assumed.
if ($text -match 'WQ476-SELFTEST-TRIGGER') {
    $reason   = 'selftest'
    $evidence = 'sentinel WQ476-SELFTEST-TRIGGER present in the message'
}

# --- real detection, on the ask section only --------------------------------------------------------
if (-not $reason) {
    $askMatch = [regex]::Match($text, '(?ms)^##\s*What I need from you\s*\r?\n(.*?)(?:\r?\n##\s|\z)')
    if ($askMatch.Success) {
        $ask = $askMatch.Groups[1].Value

        # A decision the owner already made. Checked BEFORE the command list and deliberately not
        # subject to the refuse skip below - "this is the human's call" is the exact framing that
        # produced the defect. WQ-465 was recorded as an open publish decision while publish is
        # StarterPack-Airlock-only; every agent that
        # read the queue honestly re-derived the same ask from the file. Re-asking a settled decision
        # is worse than offloading a command: offloading spends a turn, this tells the owner their
        # answer did not stick.
        foreach ($entry in $policy.settled) {
            if (-not (Test-GlobMatch -Text $ask -Glob $entry.pattern)) { continue }
            $line = ($ask -split "`r?`n" | Where-Object { Test-GlobMatch -Text $_ -Glob $entry.pattern } | Select-Object -First 1)
            $reason   = 'settled'
            $evidence = "the ask re-raises a settled decision ($($entry.decision) Recorded in $($entry.recorded)): $($line.Trim())"
            break
        }

        foreach ($glob in $policy.shell.allow) {
            if ($reason) { break }
            if (-not (Test-GlobMatch -Text $ask -Glob $glob)) { continue }
            $line = ($ask -split "`r?`n" | Where-Object { Test-GlobMatch -Text $_ -Glob $glob } | Select-Object -First 1)
            # A refuse entry on the same line means the ask is legitimately the owner's: "run
            # install.ps1" is not an offload, it is one of the two categories this pack has always
            # said belongs to the maintainer.
            $refused = $false
            foreach ($r in $policy.shell.refuse) { if (Test-GlobMatch -Text $line -Glob $r) { $refused = $true; break } }
            if ($refused) { Write-Log "ask names $glob but the line also matches a refuse entry - legitimately the owner's"; continue }
            $reason   = 'offload'
            $evidence = "the ask section names a pre-approved command (glob $glob): $($line.Trim())"
            break
        }
    }
}

if (-not $reason) {
    if (Test-Path -LiteralPath $flag) { Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue }
    Write-Log "clean (gen=$gen, $($text.Length) chars)"
    exit 0
}

Write-HookUtf8NoBom -Path $flag -Text (@{
    generation_id = $gen
    reason        = $reason
    evidence      = $evidence
    at            = (Get-Date).ToString('o')
} | ConvertTo-Json -Compress)

Write-Log "FLAGGED reason=$reason gen=$gen :: $evidence"
exit 0
