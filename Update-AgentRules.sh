#!/usr/bin/env bash
# Install global pack rules; optionally sync generic rules into a project.
# POSIX twin of Update-AgentRules.cmd (WQ-451).
#
# Usage: bash Update-AgentRules.sh [PROJECT_ROOT] [RULES_RELATIVE_PATH]
#   no arguments  - install the global rules only
#   PROJECT_ROOT  - also sync this pack's generic rules into that project, then verify the result
#
# The project argument writes into a repo that is not this one. That is the whole point of the
# command, but it means the path is never defaulted or guessed: with no argument it does the global
# half and stops.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pack/scripts/pwsh-wrap.sh
. "$ROOT/pack/scripts/pwsh-wrap.sh"
pack_pwsh_require

# Not pack_pwsh_file: that execs, and this wrapper has up to three steps.
pack_pwsh_run "$ROOT/pack/scripts/update-agents.ps1"

if [ "$#" -eq 0 ]; then
  echo
  echo "Done. To sync generic rules into a project, re-run with its root:"
  echo "  bash Update-AgentRules.sh /home/alice/projects/MyApp"
  echo "Optional second argument: rules path relative to the project (default .cursor/rules)"
  exit 0
fi

PROJECT_ROOT="$1"
RULES_PATH="${2:-.cursor/rules}"

pack_pwsh_run "$ROOT/pack/scripts/sync-project-rules.ps1" \
  -ProjectRoot "$PROJECT_ROOT" -RulesRelativePath "$RULES_PATH"

# Second pass in verify mode, so the command reports whether it achieved what it just did rather
# than assuming the write succeeded - the .cmd twin does the same.
pack_pwsh_file "$ROOT/pack/scripts/sync-project-rules.ps1" \
  -ProjectRoot "$PROJECT_ROOT" -RulesRelativePath "$RULES_PATH" -VerifyOnly
