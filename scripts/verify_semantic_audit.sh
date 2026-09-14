#!/usr/bin/env bash
# Verify the semantic report (same as scripts/verify_semantic_audit.cmd on Windows).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=pack/scripts/py-wrap.sh
. "$ROOT/pack/scripts/py-wrap.sh"
PY="$ROOT/pack/scripts/audit_code_checks.py"
[ -f "$PY" ] || PY="$HOME/.cursor/AgentStarterPack/pack/scripts/audit_code_checks.py"
pack_py_require
pack_py_file "$PY" "$ROOT" --verify-semantic-report
