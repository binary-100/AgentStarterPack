#!/usr/bin/env bash
# Register per-tool adapter files (same as Register-Tool-Adapters.cmd on Windows).
# Usage: ./Register-Tool-Adapters.sh PROJECT_ROOT [Claude|Copilot|Windsurf|All] [-Repair] [-InstallMcp]
#
# The .cmd twin pauses on error so a double-clicked window stays readable. There is no double-click
# case here, so this passes -NoPause and lets the exit code speak.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pack/scripts/pwsh-wrap.sh
. "$ROOT/pack/scripts/pwsh-wrap.sh"
if [ "$#" -eq 0 ]; then
  echo "Usage: ./Register-Tool-Adapters.sh PROJECT_ROOT [Claude|Copilot|Windsurf|All] [-Repair] [-InstallMcp]" >&2
  echo "Example: ./Register-Tool-Adapters.sh ~/my-app All" >&2
  echo "See docs/PORTABLE_SETUP.md for per-tool setup." >&2
  exit 1
fi
PROJECT_ROOT="$1"
shift
TOOL="All"
if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
  TOOL="$1"
  shift
fi
pack_pwsh_require
pack_pwsh_file "$ROOT/pack/scripts/register-tool-adapters.ps1" \
  -ProjectRoot "$PROJECT_ROOT" -Tool "$TOOL" "$@" -NoPause
