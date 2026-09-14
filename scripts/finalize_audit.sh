#!/usr/bin/env bash
# Finalize the audit (same as scripts/finalize_audit.cmd on Windows).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=pack/scripts/pwsh-wrap.sh
. "$ROOT/pack/scripts/pwsh-wrap.sh"
pack_pwsh_require
pack_pwsh_file "$ROOT/scripts/run_audit.ps1" -FinalizeOnly "$@"
