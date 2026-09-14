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

That last row is not hypothetical: the pack's former session document carried its engine cite that way, so it
drifted a full four bumps while verify stayed green. Adding a file to `auditVersionScanFiles` does
nothing on its own if the cite inside it is written in an unrecognised form.

## Historical regions — the cites a bump must never touch

Some documents hold both kinds of claim. `docs/WORK_QUEUE.md` says which engine is **current** in
its header table, and every **Done-log** row says which engine **shipped** that item. The first must
move on a bump; the second is a statement about the past.

Declare where the past begins:

```json
"historicalRegions": [
  { "file": "docs/WORK_QUEUE.md", "fromHeading": "## Done log" }
]
```

Nothing below that heading is rewritten — not by the line scan, and not by `extraReplacements`,
which are whole-file regexes and so the likeliest to reach backwards.

Three rules follow from this:

- **Never bump a version cite with a find/replace across a whole file.** Run `Sync-DocVersions.cmd`.
 The four known corruptions of this repo's Done log were all hand replaces, twice in one session.
- **A declared heading that does not exist is a failure**, not a warning: the file is being synced end
 to end while the config claims part of it is protected. `--verify` reports it in `missingRegions`.
- **`verify-work-queue.ps1` checks the declaration itself**, so deleting the entry cannot quietly
 remove the protection, and compares the Done log's cited versions against git `HEAD` — that set may
 only grow. A version that was cited at `HEAD` and is not cited now means a bump reached backwards.

Generated projects inherit this: `scanGlobs: ["docs/*.md"]` sweeps up their work queue too.
