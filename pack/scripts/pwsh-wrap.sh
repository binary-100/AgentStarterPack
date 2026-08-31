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
