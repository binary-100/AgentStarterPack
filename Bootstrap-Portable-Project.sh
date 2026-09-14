#!/usr/bin/env bash
# Bootstrap a new repo for non-Cursor agents (Portable target - no editor-specific entry files).
# POSIX twin of Bootstrap-Portable-Project.cmd (WQ-451).
#
# Usage: bash Bootstrap-Portable-Project.sh PROJECT_ROOT [ProjectName]
# For Cursor plus every other editor, use Bootstrap-Project.sh instead.
#
# The .cmd twin pauses so a double-clicked window stays readable. There is no double-click case
# here, so this passes -NoPause and lets the exit code speak.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pack/scripts/pwsh-wrap.sh
. "$ROOT/pack/scripts/pwsh-wrap.sh"

if [ "$#" -lt 1 ]; then
  echo "Usage: bash Bootstrap-Portable-Project.sh PROJECT_ROOT [ProjectName]" >&2
  echo "Example: bash Bootstrap-Portable-Project.sh /home/dev/my-app MyApp" >&2
  echo >&2
  echo "Uses -Targets Portable. For Cursor + all editors, use Bootstrap-Project.sh instead." >&2
  exit 1
fi

PROJECT_ROOT="$1"
NAME="${2:-$(basename "$1")}"
pack_pwsh_require

echo "Bootstrapping $PROJECT_ROOT as $NAME (Portable / multi-tool, no Cursor-only extras) ..."

# Not pack_pwsh_file: that execs, and the verification below is the half that makes this command
# different from plain bootstrap - a Portable project that quietly grew a Cursor-only file is the
# defect -RequirePortableOnly exists to catch.
pack_pwsh_run "$ROOT/pack/scripts/bootstrap-project.ps1" \
  -ProjectRoot "$PROJECT_ROOT" -ProjectName "$NAME" -Stack Python -Targets Portable -NoPause

echo
echo "Done. At session start: paste pack/docs/portable/GENERIC_RULES.md plus this project's AI_INSTRUCTIONS.md"
echo "Customize docs/AUDIT.md then run ./run_audit.sh"

pack_pwsh_file "$ROOT/pack/scripts/verify-portable-bootstrap.ps1" \
  -ProjectRoot "$PROJECT_ROOT" -RequirePortableOnly
