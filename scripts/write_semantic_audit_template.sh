#!/usr/bin/env bash
# Write the semantic report template (same as scripts/write_semantic_audit_template.cmd on Windows).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=pack/scripts/py-wrap.sh
. "$ROOT/pack/scripts/py-wrap.sh"
PY="$ROOT/pack/scripts/audit_code_checks.py"
[ -f "$PY" ] || PY="$HOME/.cursor/AgentStarterPack/pack/scripts/audit_code_checks.py"
pack_py_require
pack_py_file "$PY" "$ROOT" --write-semantic-template
