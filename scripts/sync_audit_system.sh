#!/usr/bin/env bash
# Push pack audit-system files into this project (same as scripts/sync_audit_system.cmd on Windows).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=pack/scripts/pwsh-wrap.sh
. "$ROOT/pack/scripts/pwsh-wrap.sh"
SYNC="$ROOT/pack/scripts/sync-audit-system.ps1"
[ -f "$SYNC" ] || SYNC="$HOME/.cursor/AgentStarterPack/pack/scripts/sync-audit-system.ps1"
pack_pwsh_require
pack_pwsh_file "$SYNC" -ProjectRoot "$ROOT" "$@"
