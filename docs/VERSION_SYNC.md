# Version sync pattern (starter pack 1.3.0+)

## Problem

Agents often bump `VERSION` in code but forget `VERSION.txt`, distrib README, or release notes. Full test suites then fail on `test_version_consistency` — usually late in the workflow.

## Solution

1. **One canonical source** (Python: `VERSION` in main module).
2. **`scripts/apply_version.py sync`** — idempotent; regenerates `VERSION.txt` only when drifted.
3. **`run_tests.bat`** runs sync first (see template).
4. **Cursor rule** — `version-sync.mdc` in project; generic rule in pack.

## Bootstrap (Python app)

```text
pack/templates/apply_version.py.template     → scripts/apply_version.py
pack/templates/test_version_consistency.py.template → tests/test_version_consistency.py
pack/templates/version-sync.mdc.template     → .cursor/rules/version-sync.mdc
pack/templates/run_tests.bat.template        → run_tests.bat
```

Configure `PROJECT_NAME`, `SOURCE_MODULE`, and optional `DIST_DIR_PATTERN` in `apply_version.py`.

## Reference implementation

BSOD Analyzer uses this pattern (`bsod_analyzer.VERSION`, auto-sync in `run_tests.bat`).

## Starter pack itself

This pack uses a single root `VERSION` file — no sync script needed.
