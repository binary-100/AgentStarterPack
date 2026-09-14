#!/usr/bin/env bash
# Finalize the audit (same as scripts/finalize_audit.cmd on Windows).
# Thin wrapper: the implementation is scripts/run_audit.ps1, which is local to this project, so no
# pack lookup is needed here. The pwsh check is inline for the reason run_audit.sh.template gives -
# a generated project must be able to audit itself without the pack checkout present.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v pwsh >/dev/null 2>&1; then
  echo "ERROR: PowerShell 7 (pwsh) is required to run the audit on this OS." >&2
  echo "Install: https://learn.microsoft.com/powershell/scripting/install/installing-powershell" >&2
  exit 1
fi
exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$ROOT/scripts/run_audit.ps1" -FinalizeOnly "$@"
