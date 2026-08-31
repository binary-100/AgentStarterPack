#!/usr/bin/env bash
# Bootstrap a new repo with audit wiring + multi-tool agent instructions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pack/scripts/pwsh-wrap.sh
. "$ROOT/pack/scripts/pwsh-wrap.sh"
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 PROJECT_ROOT [ProjectName]" >&2
  echo "Example: $0 /home/dev/my-app MyApp" >&2
  exit 1
fi
PROJECT_ROOT="$1"
NAME="${2:-$(basename "$1")}"
pack_pwsh_require
pack_pwsh_file "$ROOT/pack/scripts/bootstrap-project.ps1" \
  -ProjectRoot "$PROJECT_ROOT" \
  -ProjectName "$NAME" \
  -Stack Python \
  -Targets All \
  -NoPause
