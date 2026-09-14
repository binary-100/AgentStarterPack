#!/usr/bin/env bash
# Verify the semantic report (same as scripts/verify_semantic_audit.cmd on Windows).
#
# The audit engine itself lives in the pack, so unlike run_audit.sh this has to locate the pack -
# same three candidates, in the same order, as the .cmd twin. The interpreter check is inline rather
# than sourced from the pack for the reason run_audit.sh.template gives: nothing here may depend on
# a pack helper, so an installed pack older than these scripts still works.
set -euo pipefail
cd "$(dirname "$0")/.."

PROBE="pack/scripts/audit_code_checks.py"
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

# `py -3` in the .cmd twin is the Windows launcher and exists nowhere else. `python` is still a
# Python 2 stub on some distros, so ask the interpreter its own version rather than trust the name.
PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
    PY="$candidate"
    break
  fi
done
if [ -z "$PY" ]; then
  echo "ERROR: Python 3.8+ is required and was not found on PATH." >&2
  exit 1
fi

exec "$PY" "$PACK/$PROBE" "$PWD" --verify-semantic-report
