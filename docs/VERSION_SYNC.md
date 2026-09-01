# Version sync pattern (starter pack 1.3.0+)

## Problem

Agents bump `VERSION` in code but forget `VERSION.txt`, README, `AGENTS.md`, or release notes. Failures show up late in tests or audit Section M.

## Solution (build pipeline — not audit)

1. **One canonical source** per project (Python: `VERSION = "x.y.z"` in main module).
2. **`docs/VERSION_SYNC.json`** — which docs to update when version changes (build config, separate from audit).
3. **`scripts/apply_version.py sync`** — updates `VERSION.txt` **and** documentation cites.
4. **`run_tests.bat`** / **`build_ci.bat`** — call `apply_version.py sync` **before** tests/build.

Audit may still flag stale cites if someone skipped the build sync — that is a backstop, not the primary path.

## Bootstrap (Python app)

```text
docs/VERSION_SYNC.json.template          → docs/VERSION_SYNC.json
pack/scripts/doc_version_sync.py         → scripts/doc_version_sync.py
pack/templates/apply_version.py.template → scripts/apply_version.py
pack/templates/run_tests.bat.template      → run_tests.bat  (sync enabled)
pack/templates/build-ci.bat.template     → build_ci.bat
```

Configure `SOURCE_MODULE`, `PROJECT_NAME` in `apply_version.py`. Tune `docSync.scanFiles` in `VERSION_SYNC.json`.

## Commands

```bat
py -3 scripts\apply_version.py sync    REM version + docs (before test/build)
scripts\sync_doc_versions.cmd          REM docs only
build_ci.bat                           REM tests (includes sync) then compile
```

**Agents:** edit only canonical `VERSION` in source; never hand-edit `VERSION.txt` or version strings in README/AGENTS.

## Node / other stacks

Add equivalent `VERSION_SYNC.json` + a small sync script; run it in `pretest` / CI before build.

## Agent Starter Pack (maintainers)

Uses **`maintainerDocSync`** in `docs/VERSION_SYNC.json` (pack + audit-engine cites). Run **`Sync-DocVersions.cmd`** after manifest bumps.

**Write the cite in the parenthesised form, or it is silently not synced.** The matcher looks for a
context word (`manifest.json`, `audit engine`, `starter pack`, `pack version`, root `` `VERSION` ``)
followed by the version **in parentheses**:

| Form | Synced? |
|------|---------|
| `` `pack/audit/manifest.json` (**2.22.5**) `` | **Yes** |
| ``Audit engine version (2.22.5)`` | **Yes** |
| `` `pack/audit/manifest.json` = **2.22.5** `` | **No** — no pattern matches, and `--verify` reports `ok: true` because it sees nothing to change |

That last row is not hypothetical: `HANDOFF_NEXT_AGENT.md` carried its engine cite that way, so it
drifted a full four bumps while verify stayed green. Adding a file to `auditVersionScanFiles` does
nothing on its own if the cite inside it is written in an unrecognised form.
