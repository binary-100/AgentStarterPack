#!/usr/bin/env bash
# Update the installed pack, then refresh a project's agent context (same as Update-AgentStack.cmd
# on Windows).
# Usage: ./Update-AgentStack.sh [ProjectRoot] [-Switches...]
# If the first argument starts with '-', it is passed through (no ProjectRoot).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pack/scripts/pwsh-wrap.sh
. "$ROOT/pack/scripts/pwsh-wrap.sh"
SCRIPT="$ROOT/pack/scripts/update-agent-stack.ps1"
pack_pwsh_require
if [ "$#" -eq 0 ]; then
  pack_pwsh_file "$SCRIPT"
elif [ "${1#-}" != "$1" ]; then
  pack_pwsh_file "$SCRIPT" "$@"
else
  pack_pwsh_file "$SCRIPT" -ProjectRoot "$1" "${@:2}"
fi
