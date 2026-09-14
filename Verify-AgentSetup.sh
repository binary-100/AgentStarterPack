#!/usr/bin/env bash
# Verify the installed pack, global rules/skills and (optionally) a reference project.
# POSIX twin of Verify-AgentSetup.cmd (WQ-451).
#
# Start it as `bash Verify-AgentSetup.sh`, not `./Verify-AgentSetup.sh`, unless you arrived by
# git clone - see INSTALL.md. Flags pass straight through, e.g. -ReferenceProjectRoot.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pack/scripts/pwsh-wrap.sh
. "$ROOT/pack/scripts/pwsh-wrap.sh"
pack_pwsh_require
pack_pwsh_file "$ROOT/pack/scripts/verify-agent-setup.ps1" "$@"
