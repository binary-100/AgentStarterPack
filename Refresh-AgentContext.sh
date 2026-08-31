#!/usr/bin/env bash
# Refresh agent context: sync pack files and write docs/AGENT_CONTEXT.json + docs/AGENT_REFRESH.md.
# Usage: ./Refresh-AgentContext.sh [ProjectRoot] [-Install] [-NoClipboard] ...
# If the first argument starts with '-', it is passed through (no ProjectRoot).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pack/scripts/pwsh-wrap.sh
. "$ROOT/pack/scripts/pwsh-wrap.sh"
SCRIPT="$ROOT/pack/scripts/refresh-agent-context.ps1"
pack_pwsh_require
if [ "$#" -eq 0 ]; then
  pack_pwsh_file "$SCRIPT"
elif [ "${1#-}" != "$1" ]; then
  pack_pwsh_file "$SCRIPT" "$@"
else
  pack_pwsh_file "$SCRIPT" -ProjectRoot "$1" "${@:2}"
fi
