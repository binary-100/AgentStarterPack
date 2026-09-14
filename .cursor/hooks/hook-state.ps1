<#
  Shared helpers for the agent control hooks. Dot-sourced by each of them.

  Four jobs, and every one of them exists because getting it wrong cost something already:

  1. Resolve a writable state directory WITHOUT assuming Windows. `$env:LOCALAPPDATA` is empty on
     macOS and Linux, and `Join-Path` throws on a null Path - the exact defect that took behavior
     step 54 red in 2.22.119, where a guard on the result could not protect against a null input.

  2. Read a hook payload from stdin with a BOUNDED off-thread read. Not theoretical here:
     `[Console]::In.ReadToEnd()` in the session hook hung an audit for sixteen minutes under bash
     (2.22.63), and the bounded replacement that shipped next faulted in ~6ms for want of a runspace
     and never read at all (WQ-473). This form was measured against the failing shape - stdin held
     open, never written, no EOF - and returned in 1743ms.

  3. Locate the HOST-NEUTRAL policy by walking up the tree, the way OpenCode discovers `.opencode`.
     The policy must not live under `.cursor/`: it is the one file every host's control compiles
     from, and putting shared data inside one host's folder is how the data becomes that host's.

  4. Compile a glob to a regex. The policy is authored in globs **because** that direction is
     lossless and the other is not - a glob becomes a regex by escaping and substitution, while a
     regex cannot become a glob at all. Authoring in regex would have locked the policy to whichever
     adapter was written first, which was the maintainer's exact objection (WQ-480).

  Cursor prefixes every hook payload with a UTF-8 BOM. That is measured, not assumed: the first
  version of shell-preapprove.ps1 returned no opinion for every command including exact matches,
  because ConvertFrom-Json threw on the U+FEFF that UTF8.GetString faithfully preserves.
#>

function Get-HookStateDir {
    $base = $null
    foreach ($candidate in @($env:LOCALAPPDATA, $env:XDG_STATE_HOME, $env:HOME, $env:TMPDIR, $env:TEMP)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $base = $candidate; break }
    }
    if ([string]::IsNullOrWhiteSpace($base)) { $base = [IO.Path]::GetTempPath() }
    $dir = Join-Path $base 'AgentStarterPack/state'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
    }
    return $dir
}

function Read-HookPayload {
    param([int]$MaxBytes = 4194304, [int]$TotalSeconds = 5, [int]$SliceMs = 1500)

    $raw = ''
    try {
        $stdin = [Console]::OpenStandardInput()
        $buffer = New-Object byte[] $MaxBytes
        $total = 0
        $deadline = [DateTime]::UtcNow.AddSeconds($TotalSeconds)
        while ([DateTime]::UtcNow -lt $deadline -and $total -lt $buffer.Length) {
            $async = $stdin.BeginRead($buffer, $total, $buffer.Length - $total, $null, $null)
            if (-not $async.AsyncWaitHandle.WaitOne($SliceMs)) { break }
            $read = $stdin.EndRead($async)
            if ($read -le 0) { break }
            $total += $read
        }
        if ($total -gt 0) { $raw = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $total) }
    } catch { return $null }

    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $brace = $raw.IndexOf('{')
    if ($brace -gt 0) { $raw = $raw.Substring($brace) }
    try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

function Convert-GlobToRegex {
    param([Parameter(Mandatory = $true)][string]$Glob)
    # Escape everything, then re-open the two wildcards. Escaping first is what makes this safe for a
    # policy that contains dots, backslashes and parentheses - a hand-rolled character walk is how a
    # pattern like *run_audit.cmd* silently starts matching runXaudit.cmd.
    $escaped = [regex]::Escape($Glob)
    $escaped = $escaped.Replace('\*', '.*')
    $escaped = $escaped.Replace('\?', '.')
    return $escaped
}

function Test-GlobMatch {
    param([string]$Text, [string]$Glob)
    if ([string]::IsNullOrEmpty($Text) -or [string]::IsNullOrEmpty($Glob)) { return $false }
    return [regex]::IsMatch($Text, (Convert-GlobToRegex $Glob), 'IgnoreCase')
}

function Get-AgentPolicy {
    # Walk up from the hook's own folder looking for the neutral policy, then fall back to a copy
    # beside the hooks. Walking up is how a shared file stays shared: the same policy.json serves the
    # Cursor hooks in .cursor/hooks/ and the OpenCode permission block compiled into opencode.json,
    # without either host's folder owning it.
    $dir = $PSScriptRoot
    for ($i = 0; $i -lt 8 -and $dir; $i++) {
        $candidate = Join-Path $dir '.agent-control/policy.json'
        if (Test-Path -LiteralPath $candidate) {
            try { return (Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json) } catch { return $null }
        }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    $beside = Join-Path $PSScriptRoot 'policy.json'
    if (Test-Path -LiteralPath $beside) {
        try { return (Get-Content -LiteralPath $beside -Raw | ConvertFrom-Json) } catch { return $null }
    }
    return $null
}

function Write-HookUtf8NoBom {
    param([string]$Path, [string]$Text)
    # Not Set-Content -Encoding UTF8: that writes a BOM on 5.1 and none on 7, which behavior step 61
    # refuses - and a control already bitten by one unexpected BOM should not emit another.
    [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}
