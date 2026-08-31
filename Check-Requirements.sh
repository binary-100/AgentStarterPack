#!/usr/bin/env bash
# Environment preflight: what this machine needs before install, bootstrap, or an audit.
# Add -Fix to install Python MCP packages when pip is available.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pack/scripts/pwsh-wrap.sh
. "$ROOT/pack/scripts/pwsh-wrap.sh"
pack_pwsh_require
pack_pwsh_file "$ROOT/pack/scripts/check-requirements.ps1" "$@"
