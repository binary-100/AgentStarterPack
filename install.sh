#!/usr/bin/env bash
# Unix install — rules and skills only (PowerShell scripts are Windows-oriented)
set -euo pipefail
SCOPE="${1:-Both}"
PACK="$(cd "$(dirname "$0")/pack" && pwd)"
USER_SKILLS="${HOME}/.cursor/skills"
USER_RULES="${HOME}/.cursor/rules"

copy_tree() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  cp -R "$src"/. "$dst"/
}

echo "Agent Starter Pack — install ($SCOPE)"

if [[ "$SCOPE" == "User" || "$SCOPE" == "Both" ]]; then
  copy_tree "$PACK/skills" "$USER_SKILLS"
  copy_tree "$PACK/rules" "$USER_RULES"
  echo "User: $USER_SKILLS, $USER_RULES"
fi

if [[ "$SCOPE" == "Project" || "$SCOPE" == "Both" ]]; then
  copy_tree "$PACK/skills" ".cursor/skills"
  copy_tree "$PACK/rules" ".cursor/rules"
  echo "Project: .cursor/skills, .cursor/rules"
fi

echo "Done. See README.md for audit + terminal hygiene usage."
