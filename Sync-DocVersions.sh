#!/usr/bin/env bash
# Sync documented versions from the canonical VERSION file (same as Sync-DocVersions.cmd on Windows).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pack/scripts/pwsh-wrap.sh
. "$ROOT/pack/scripts/pwsh-wrap.sh"
pack_pwsh_require
pack_pwsh_file "$ROOT/pack/scripts/sync-doc-versions.ps1" "$@"
