#!/usr/bin/env bash
# Push pack audit-system files into this project (same as scripts/sync_audit_system.cmd on Windows).
#
# The sync script lives in the pack, so this has to locate the pack - same three candidates, in the
# same order, as the .cmd twin. The pwsh check is inline rather than sourced from the pack for the
# reason run_audit.sh.template gives: nothing here may depend on a pack helper, so an installed pack
# older than these scripts still works.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

PROBE="pack/scripts/sync-audit-system.ps1"
PACK=""
for base in "${AGENT_STARTER_PACK_ROOT:-}" "$HOME/.cursor/AgentStarterPack" "$HOME/.cursor/agent-starter-pack"; do
  if [ -n "$base" ] && [ -f "$base/$PROBE" ]; then
    PACK="$base"
    break
  fi
done
if [ -z "$PACK" ]; then
  echo "[ERROR] Agent Starter Pack not found. Run install.sh from the pack, or set AGENT_STARTER_PACK_ROOT to the pack folder." >&2
  exit 1
fi

if ! command -v pwsh >/dev/null 2>&1; then
  echo "ERROR: PowerShell 7 (pwsh) is required to sync the audit system on this OS." >&2
  echo "Install: https://learn.microsoft.com/powershell/scripting/install/installing-powershell" >&2
  exit 1
fi

exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$PACK/$PROBE" -ProjectRoot "$REPO" "$@"
