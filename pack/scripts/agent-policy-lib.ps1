#Requires -Version 5.1
<#
  Agent control policy: load and compile (WQ-480).

  One host-neutral policy, many adapters. This file is the compiler half - it turns
  `.agent-control/policy.json` into whatever a given host's native mechanism wants. It is a separate
  library rather than inline code in bootstrap so the behavior suite can test the compile in-process,
  which is this pack's standing preference: a transformation proven by running it beats one proven by
  reading the caller.

  Why the policy is authored in globs: the direction is lossless. A glob becomes a regex by escaping
  and substitution; a regex cannot become a glob at all. The Cursor hooks compile globs to regex at
  runtime, and OpenCode takes globs natively, so authoring in regex would have locked the policy to
  whichever adapter happened to be written first. That was the maintainer's objection and it was
  correct.

  Why refuse compiles to `ask` and never `deny`: refuse means "this control has no opinion, let normal
  review happen". It is the owner's call, not a prohibition. Compiling it to `deny` would remove the
  approval the owner is entitled to give, turning a hands-off list into a lockout.

  Rule order is measured, not assumed. `opencode debug agent build` on 1.18.30 resolves its own
  built-ins as a broad `*` allow FOLLOWED BY narrower `ask` rules, so later and more specific rules
  are the ones that bind. This emits allow first, then refuse as `ask`, matching that shape.
#>

function Get-PackAgentPolicy {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Test-PackAgentPolicyShape {
    <# Returns a list of problems; empty means usable. Reported rather than thrown so a caller can
       degrade to "no opinion" instead of failing a bootstrap over a policy it could simply skip. #>
    param($Policy)
    $problems = @()
    if ($null -eq $Policy) { return @('policy is missing or unparseable') }
    if ($null -eq $Policy.shell) { $problems += 'policy has no shell section' }
    else {
        if (@($Policy.shell.allow).Count -eq 0) { $problems += 'policy shell.allow is empty - the control would approve nothing' }
        if (@($Policy.shell.refuse).Count -eq 0) { $problems += 'policy shell.refuse is empty - nothing would be held back for the owner' }
    }
    foreach ($entry in @($Policy.settled)) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.pattern)) { $problems += 'a settled entry has no pattern' }
        if ([string]::IsNullOrWhiteSpace([string]$entry.recorded)) { $problems += "settled entry '$($entry.pattern)' does not say where the decision is recorded" }
    }
    return $problems
}

function ConvertTo-PackOpenCodePermission {
    <# Compile to OpenCode's `permission.bash` glob->effect map. Schema confirmed against the real
       binary (1.18.30): permission.<action> is either a bare "allow"/"ask"/"deny" or an object of
       pattern -> effect. Neither documented array shape was what the binary actually resolved, which
       is why this waited for a measurement instead of shipping from the docs. #>
    param($Policy)
    $map = [ordered]@{}
    foreach ($glob in @($Policy.shell.allow)) {
        if ([string]::IsNullOrWhiteSpace([string]$glob)) { continue }
        $map[[string]$glob] = 'allow'
    }
    # Refuse last so the narrower rule binds, mirroring how the binary orders its own built-ins.
    foreach ($glob in @($Policy.shell.refuse)) {
        if ([string]::IsNullOrWhiteSpace([string]$glob)) { continue }
        $map[[string]$glob] = 'ask'
    }
    return $map
}

function ConvertTo-PackOpenCodePermissionJson {
    <# The `permission` block as JSON, indented to sit inside opencode.json at two spaces. Emitted as
       text rather than assembled by ConvertTo-Json on the whole file so the template stays readable
       and diffable - a generated config nobody can read is a config nobody audits. #>
    param($Policy, [int]$Indent = 2)
    $map = ConvertTo-PackOpenCodePermission -Policy $Policy
    $pad = ' ' * $Indent
    $inner = ' ' * ($Indent + 4)
    $lines = @()
    foreach ($key in $map.Keys) {
        $escaped = ([string]$key).Replace('\', '\\').Replace('"', '\"')
        $lines += "$inner`"$escaped`": `"$($map[$key])`""
    }
    $body = $lines -join ",`n"
    return "$pad`"permission`": {`n$pad  `"bash`": {`n$body`n$pad  }`n$pad}"
}
