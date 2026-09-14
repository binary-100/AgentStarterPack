#!/usr/bin/env bash
# Shared helpers for repo-root .sh entry points (source, do not execute directly).
pack_pwsh_require() {
  if command -v pwsh >/dev/null 2>&1; then
    return 0
  fi
  echo "ERROR: PowerShell 7 (pwsh) is required on macOS/Linux." >&2
  echo "Install: https://learn.microsoft.com/powershell/scripting/install/installing-powershell" >&2
  exit 1
}

pack_pwsh_file() {
  local script_path="$1"
  shift
  exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$script_path" "$@"
}

# The same call without exec, for a wrapper that has more than one step. pack_pwsh_file replaces the
# shell, so it can only ever be the last line - and a .cmd twin that runs two or three .ps1 files in
# sequence (Update-AgentRules, Bootstrap-Portable-Project) cannot be expressed with it at all. Rolling
# a bare `pwsh` line by hand in each of those is what this file exists to prevent: the flags would
# drift, and the entry-point scanner reads invocations through these helpers.
# Returns the script's exit code; the caller decides whether to stop.
pack_pwsh_run() {
  local script_path="$1"
  shift
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$script_path" "$@"
}
