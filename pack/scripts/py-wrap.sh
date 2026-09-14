#!/usr/bin/env bash
# Python invocation for the pack's .sh entry points - the shell twin of Invoke-PackPython in
# pack-paths.ps1.
#
# The .cmd entry points call `py -3`. That is the Windows Python launcher and exists nowhere else,
# so the shell side has to resolve an interpreter itself rather than translate the Batch line: a
# literal port would fail with "py: command not found", which reads like a missing Python rather
# than a Windows-only launcher.

pack_py_require() {
  if [ -n "${PACK_PY:-}" ]; then
    return 0
  fi
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
      # `python` is still a Python 2 stub on some distros, and the pack needs 3.8+. Asking the
      # interpreter its own version is the only reliable test - the name says nothing.
      if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
        PACK_PY="$candidate"
        return 0
      fi
    fi
  done
  echo "ERROR: Python 3.8+ is required and was not found on PATH." >&2
  echo "Install Python 3.8+ (python.org/downloads, brew install python@3.12, apt install python3, etc.)" >&2
  exit 1
}

pack_py_file() {
  local script_path="$1"
  shift
  exec "$PACK_PY" "$script_path" "$@"
}
