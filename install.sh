#!/usr/bin/env bash
# Unix/macOS install - full parity via PowerShell 7 when available.
set -euo pipefail
SCOPE="${1:-Both}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pack/scripts/pwsh-wrap.sh
. "$ROOT/pack/scripts/pwsh-wrap.sh"
pack_pwsh_require
pack_pwsh_file "$ROOT/install.ps1" -Scope "$SCOPE" -NoPause
