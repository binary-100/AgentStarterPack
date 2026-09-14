# StarterPack-Airlock — design and simulation plan

**Status:** **through Phase 4** in product code (2026-09-13); Phase 5 (first CI from live `repo/`) blocked on maintainer migration  
**Related WQ:** WQ-465 (decided), WQ-455 (parked — needs Airlock CI), WQ-488 (dual-zone gate B10/B11)  
**Last simulation run:** see `pack/scripts/simulate-airlock-scenarios.ps1` output

---

## Problem

Default pack copies are **git-free** and complete for install, audit, and development. Publishing, git remotes, and CI need a **separate zone** so agents in ordinary copies never re-ask publish setup and exported zips never carry maintainer-only git history.

---

## Zones

| Zone | Location | Contains | Used for |
|------|----------|----------|----------|
| **Working copy** | Any path (flash, export, Desktop dev folder) | Full pack, no `.git` / `.github` | Install, audit, develop, export |
| **StarterPack-Airlock** | Host Desktop only (`StarterPack-Airlock/`) | `publisher.key`, `repo/` (git + CI), `overlay/` (publish WQ, rules, verify) | Publish, push, CI, maintainer overlay reads |
| **Bootstrapped apps** | User projects | Their own git if chosen | Product work |

**Settled policy (WQ-465):** Publishing, git, and CI require StarterPack-Airlock on the host Desktop with a valid publisher key. Default pack copies are git-free.

---

## Discovery (planned product behavior)

1. Resolve **host Desktop** — native folder from `[Environment]::GetFolderPath('Desktop')` and, on Windows, common OneDrive-redirected Desktop paths (same pattern as `Get-AgentStarterPackCandidates` today).
2. If `{Desktop}/StarterPack-Airlock/` exists **and** `publisher.key` validates against `overlay/manifest.json` → Airlock **active**.
3. When active, `refresh-agent-context.ps1` merges overlay `requiredReads` (absolute paths under Airlock) into `AGENT_CONTEXT.json`.
4. When absent or invalid key → git-free mode; no publish prompts beyond settled policy in working-copy `.agent-control/policy.json`.

**Not in working copy:** username paths, “flash vs Desktop,” or multi-machine geography in product text.

---

## Overlay manifest (draft schema v1)

```json
{
  "schema": 1,
  "keyId": "publisher-id-string",
  "repoDir": "repo",
  "overlayDir": "overlay",
  "requiredReads": [
    "overlay/docs/WORK_QUEUE.md",
    "overlay/docs/PUBLISH.md"
  ]
}
```

`publisher.key` — single line; must match `keyId` in manifest (simulation uses plain equality; production may add fingerprint).

---

## Phased implementation (after simulations pass)

| Phase | Deliverable |
|-------|-------------|
| **1** | Spec (this doc), manifest schema, `Find-StarterPackAirlock` in `pack-paths.ps1`, unit probes |
| **2** | Overlay templates extracted from core (publish WQ slice, `.github` only in `repo/`) |
| **3** | `Initialize-StarterPackAirlock.ps1` — create Desktop Airlock, migrate `.git` → `repo/` |
| **4** | Wire `refresh-agent-context.ps1` + behavior step for discovery |
| **5** | First CI run from `repo/` (unblocks WQ-455) — **pre-shipped:** `verify-airlock-publish-gate.ps1` (B11), `-PublishRoot` on `verify-audit-system.ps1` (B10), behavior step **86** |

---

## Simulation matrix

Executable harness: `pack/scripts/simulate-airlock-scenarios.ps1`  
Uses `%TEMP%\AgentStarterPack-airlock-sim-$PID` — **never writes real Desktop**.

| ID | Scenario | Expect |
|----|----------|--------|
| S01 | No Airlock folder | Discovery null; working copy git-free checks pass |
| S02 | Valid Airlock (key + manifest + overlay + repo) | Discovery active; requiredReads merged |
| S03 | Airlock folder, no `publisher.key` | Discovery null (fail closed) |
| S04 | Airlock, wrong key | Discovery null |
| S05 | Working copy nested under git repo (pre-migration Desktop shape) | `Test-PackGitRoot` false at nested path; WQ verify skips Done-log cite |
| S06 | Git only in `repo/`, working copy git-free | Working copy not a git repo; `repo/` is git root |
| S07 | Export working copy | No `.git`, no `.github` in archive |
| S08 | Airlock on OneDrive-style Desktop path | Discovery finds Airlock on redirected Desktop |
| S09 | Overlay manifest missing required file | Discovery reports invalid overlay (fail closed) |
| S10 | `bootstrap-project.ps1` on sim app | Creates `.agent-control`, does **not** create Airlock |
| S11 | Policy settled prose without Airlock | Hooks compile; publish patterns still settled |
| S12 | Migrate `.git` from working copy → `repo/` | After migrate sim: working copy git-free, repo has git |
| S13 | Dual Desktop candidates | First valid Airlock wins; no duplicate merge |
| S14 | Live maintainer checkout | Reports current git-at-root baseline (pre-migration) |
| S15 | `verify-work-queue` at nested path | `[SKIP] not the git repository root` |
| S16 | B09 sync script present | `sync-working-copy-to-airlock-repo.ps1` exists |
| S17 | Git-free mirror (robocopy) | `tree:<hash>` proof only; no git repo |
| S18 | Git-free WQ verify | Structure OK; Done-log git arm `[SKIP]` |
| S19 | Airlock `repo/` with git | `commit+tree:<hash>` proof |
| S20 | Sync target after export-style strip | No `maintainerOnlyPaths`, `machineLocalPaths`, `.git`, or `.github` |
| S21 | Working-copy shell policy | `git push` matches `shell.refuse` (not pre-approved) |
| S22 | Zone B steps 62+50 on full `repo/` tree | Git index arms run (not SKIP) — **pass `-IncludeHeavy`** |
| S23 | VERSION drift pre-push | Mismatch detectable between working copy and `repo/` |
| S24 | Full `run_audit.cmd` on git-free mirror | `finalize_audit` exit 0 — **pass `-IncludeHeavy`** |
| S25 | G01 Python `git_head()` parity | Stale `.git` dir → `tree:` only; `Test-PackGitRepo` false |
| S26 | B09 sync working copy → `repo/` | Hygiene + VERSION drift gate |
| S27 | Publish path sync → Zone B finalize | B09 + `run_audit`/`finalize` from `repo/` — **pass `-IncludeHeavy`** |
| S28 | `Initialize-StarterPackAirlock.ps1` (Move) | Full init; wc git-free, repo git |
| S29 | Parallel init (`-GitMode Copy`) + cutover | Both trees git until `Complete-StarterPackAirlockCutover.ps1` |

Heavy scenarios (S22, S24, S27): `simulate-airlock-scenarios.ps1 -IncludeHeavy` — tens of minutes.

---

## Simulation results

**Latest run:** 2026-09-13 — **29 pass, 0 fail** default harness; **S22/S24/S27** need `-IncludeHeavy` for full Zone B audit arms (heavy run **28/0** on matrix S01–S28 before S29 landed)

```powershell
& '<PACK_ROOT>\pack\scripts\simulate-airlock-scenarios.ps1'
```

Full audit coverage contract: **`docs/AUDIT_AIRLOCK_COVERAGE.md`**

| Scenario | Result | Notes |
|----------|--------|-------|
| S01-S04 | PASS | Discovery fail-closed without key, wrong key, or missing overlay |
| S05 | PASS | Nested paths inside git repo: `Test-PackGitRoot` false (WQ-461 fix holds) |
| S06 | PASS | Working copy git-free; `repo/` is git root |
| S07 | PASS | Export zip has no `.git` or `.github` |
| S08 | PASS | OneDrive-style Desktop path resolves Airlock |
| S09 | PASS | Incomplete overlay rejected |
| S10 | PASS | Bootstrap delivers `.agent-control`, does not create Airlock |
| S11 | PASS | Settled publish prose in working-copy policy |
| S12 | PASS | `.git` move from working copy to `repo/` works |
| S13 | PASS | First valid Desktop candidate wins |
| S14 | INFO | This checkout still has git at pack root — migration required |
| S15 | PASS | WQ verify skips Done-log cite at nested path |
| S16 | PASS | B09 `sync-working-copy-to-airlock-repo.ps1` present |
| S17 | PASS | Git-free robocopy mirror → `tree:` proof only |
| S18 | PASS | WQ verify OK with Done-log git arm skipped |
| S19 | PASS | Airlock `repo/` → `commit+tree:` proof |
| S20 | PASS | Export-style strip removes maintainer/machineLocal/.git/.github |
| S21 | PASS | Working-copy policy refuses `git push` |
| S22 | PASS | Full-tree steps 62+50 index arms with `-IncludeHeavy` |
| S23 | PASS | VERSION drift probe detects mismatch |
| S24 | PASS (row-3 probe) | Git-free mirror: `run_audit` tests+machine → `fill_pack_semantic_report.py` → `finalize_audit` **exit 0** — log `%TEMP%\AgentStarterPack-row3-logs-11032\finalize.log` |
| S25 | PASS | G01: stale `.git` dir → Python `tree:` + PS `Test-PackGitRepo` false |
| S26 | PASS | B09 sync working copy → `repo/`; VERSION drift gate fails closed |

---

## Implementation readiness contract (mandatory before Phase 1 code)

**This should have been the first deliverable**, not a follow-up after the maintainer asked what was missing. A layout simulation passing 19/19 is **necessary, not sufficient**. Do not report "design holds up" or start Phase 1 until every row below has evidence.

**Generic rule (all projects):** `pack/rules/generic-implementation-readiness.mdc` — Phase 0 triggers and forbidden claims. This table is the **project-specific** instance for StarterPack-Airlock; other apps copy the appendix in `pack/docs/PHASED_FEATURE_DESIGN.md`.

| # | Track | What must be checked | Evidence required | Status (2026-09-12) |
|---|-------|---------------------|-------------------|---------------------|
| 1 | **Audit Zone A** | Full behavior suite on git-free mirror | `Summary: 0 fail(s)` log path | **Done** |
| 2 | **Audit Zone B** | Same suite on **full synced tree** in Airlock `repo/` | Steps 62, 50 index arms run (not SKIP); 0 fail | **Done** — 2026-09-12 git-init repo mirror: step 62 index arm (S22), step 50 index arm `[OK] no machine-local file is tracked in git` — log `%TEMP%\AgentStarterPack-step50-32848.log`; S22 harness runs both with `-IncludeHeavy` |
| 3 | **Product audit path** | Full `run_audit.cmd` on git-free mirror (tests + machine + semantic + finalize) | `finalize_audit` exit 0 | **Done** — 2026-09-12 git-free robocopy mirror (`AgentStarterPack-row3b-11032`): behavior **0 fail**, semantic fill + `finalize_audit` **exit 0**; logs under `%TEMP%\AgentStarterPack-row3-logs-11032\` |
| 4 | **Publish path** | End-to-end: Zone A → sync → Zone B → push (or documented human-only) | Script + log sequence | **Done** — B09 sync + post-sync commit; S27 probe **2026-09-13** `%TEMP%\s27-probe5-33092\`: `pass1=1 finalize=0`; `git push` **human-only** (S21). Full `-IncludeHeavy` sim optional re-run on quiet tree |
| 5 | **Git touchpoint inventory** | Every `.ps1`/`.py`/behavior step using git; classify Zone A vs B | Matrix in `AUDIT_AIRLOCK_COVERAGE.md` | **Done** |
| 6 | **G01 parity** | Python `git_head()` vs `Test-PackGitRepo` on stale `.git` dir | S25 pass | **Done** |
| 7 | **Agent control plane** | Hooks + `.agent-control/policy.json` in **working copy vs `repo/`** | S21 working copy; repo overlay policy Phase 2/3 (H01) | **Done** (Phase 0) — working-copy policy refuses agent `git push` (S21); repo-specific overlay policy deferred **H01** Phase 2/3 |
| 8 | **Discovery consumers** | `Get-AgentStarterPackCandidates`, refresh, doctor, install, sync-audit | `docs/AIRLOCK_DISCOVERY_AND_OVERLAY.md`; wire `Find-StarterPackAirlock` | **Done** (Phase 0) — consumer inventory + merge rules in `docs/AIRLOCK_DISCOVERY_AND_OVERLAY.md`; `Find-StarterPackAirlock` product code is Phase 1 |
| 9 | **Sync hygiene** | Strip `maintainerOnlyPaths`, machineLocal, handoffs on sync to `repo/` | S20 + S26 | **Done** — B09 strips manifest lists + stale `.audit_*`; S26 hygiene pass |
| 10 | **Drift gate** | VERSION/manifest mismatch between working copy and `repo/` fails pre-push | S23 + S26 drift arm | **Done** — B09 fails closed on VERSION mismatch; S26 verifies |
| 11 | **Overlay / WQ** | Single authoritative Next; merge order for `requiredReads` | `docs/AIRLOCK_DISCOVERY_AND_OVERLAY.md` | **Done** (Phase 0) — authoritative Next stays in working-copy `docs/WORK_QUEUE.md`; overlay merge order documented; refresh wire is Phase 4 |
| 12 | **CI / WQ-455** | `pack-os-smoke.yml` runs from `repo/`; secrets/remote checklist | First green workflow run | **Blocked** — owner: maintainer. **Re-open when:** `{Desktop}/StarterPack-Airlock/repo/` exists and first CI run from `repo/` (unblocks WQ-455) |
| 13 | **Migration** | Live Desktop Airlock (parallel **Copy** or full **Move**) | S12/S28/S29 sim pass; S14 reports git-at-root on this checkout | **Blocked** — owner: maintainer. **Re-open when:** run init per `docs/AIRLOCK_MIGRATION_CHECKLIST.md` (**`-GitMode Copy`** recommended first) |
| 14 | **Installed pack / profile** | Guard proofs cannot mutate `%USERPROFILE%\.cursor\AgentStarterPack\` | WQ-481: sandbox + profile stamp exit 0 | **Done** — sandbox, profile stamp, recurring-drift UX, behavior step **85** (2026-09-13) |
| 15 | **Process radar** | WQ row for Airlock phases; SESSION pointers aligned | WQ-483 Active | **Done** |

**Rule for agents:** If the maintainer asks "what could we be missing?", the work failed — this table should already be complete or explicitly red with blockers.

Full gap inventory (H01–L06, S20–S24): `docs/AUDIT_AIRLOCK_COVERAGE.md` § Additional gaps.

---

## Known gaps to close before Phase 1 ship

From simulation run 2026-09-12:

1. ~~**`Find-StarterPackAirlock` in `pack-paths.ps1`**~~ — **shipped (Phase 1, 2026-09-12)**; sim harness delegates to product code.
2. ~~**`Initialize-StarterPackAirlock.ps1`**~~ — **shipped (Phase 3, WQ-486, 2026-09-13)**; sim **S28**; full sim **28/0**; live Desktop migrate still maintainer-only (row 13).
3. ~~**`sync-working-copy-to-airlock-repo.ps1`**~~ — **shipped (B09)**; wire into publish docs and `-IncludeHeavy` Zone B audit from synced `repo/`.
4. ~~**`refresh-agent-context.ps1` overlay merge**~~ — **shipped (Phase 4, WQ-487, 2026-09-13):** `Merge-StarterPackAirlockRequiredReads`; **`AGENT_CONTEXT.json`** fields `starterPackAirlockActive` / `overlayRequiredReads`; behavior **step 84**.
5. **This Desktop checkout** — still has `.git` at pack root; run **`Initialize-StarterPackAirlock.cmd`** when ready (row 13 maintainer-only).
6. ~~**Behavior step**~~ — **shipped (Phase 4, WQ-487, 2026-09-13):** behavior **step 84** (S01–S04, S09, refresh merge); S05–S08 remain sim-only.
7. ~~**Overlay content extraction**~~ — **shipped (Phase 2, WQ-485, 2026-09-13):** `pack/templates/airlock/` overlay + repo templates; manifest `repoOnlyPaths`; `materialize-starter-pack-airlock-templates.ps1`; export/install strip; B09 sync materializes `.github` into `repo/`; sim **27/0**.

---

## Audit system — git-free vs Airlock (impact map)

**Important:** See **`docs/AUDIT_AIRLOCK_COVERAGE.md`** for the dual-zone model. WQ-459 split **product audit (Zone A)** from **maintainer git audit (Zone B)**. Zone A is full accuracy on git-free trees (`tree:<sha256>` proof). Zone B checks **SKIP on working copy by design** and must run against Airlock `repo/` before publish — that is not reduced accuracy, it is a second gate.

### Live probes (2026-09-12)

| Probe | Git-free copy (robocopy, no `.git`) | This checkout (git at pack root) |
|-------|-------------------------------------|----------------------------------|
| `check-requirements.ps1` | All present (git optional) | Same |
| `verify-work-queue.ps1` Done-log arm | `[SKIP] not a git checkout` | Runs at root only |
| `audit_code_checks.py --print-tests-git-head` | `tree:57308cc6…` | `1eaaa159…+tree:57308cc6…` (same tree hash) |
| Section N (`git_recent_changes`) | `False` — no N fixes emitted | Can fire when VERSION commits exist |

### Where each git-dependent check runs

| Component | Without git (export / flash / working copy) | With git (Airlock `repo/` or maintainer pre-migration) |
|-----------|---------------------------------------------|--------------------------------------------------------|
| **Test-pass proof** (`run_audit_core.ps1`, `audit_code_checks.py`) | `tree:<fingerprint>` — **strict** (uncommitted edits invalidate pass) | `HEAD+tree:<fingerprint>` — commit **and** content |
| **Layout: committed build output** (`run_audit_core.ps1`) | Skipped — no `git ls-files` | Fix if ephemeral dirs tracked |
| **Section N** (VERSION/git log hint, pack config) | Disabled in practice (`git_recent_changes` false) | Can require semantic cite after version commits |
| **Section L** (`.gitignore` audit artifacts) | **Runs** — reads `.gitignore` files, no git needed | Same |
| **Behavior step 50** (machine-local tracked in index) | `[INFO] not a git checkout - index check skipped` | Fails if machine-local paths tracked |
| **Behavior step 62** (`.sh` mode 100755 in git index) | `[SKIP] not a git checkout` | Guards clone/install on Unix |
| **Behavior step 64 arm 5** (WQ Done-log history backstop) | `[SKIP]` on product; step builds scratch repo to prove | Proves hand-edits to committed Done log fail |
| **Behavior step 23** (git vs tree proof parity) | Creates temp `GitApp` with `git init` — **still runs** on maintainer machine | Same |
| **`.github/workflows/pack-os-smoke.yml`** | **Not in export** (no `.github` in zip) | CI from Airlock `repo/` only |
| **`verify-work-queue.ps1`** Done-log vs `git show` | `[SKIP] not a git checkout` | Runs at repository root only |

### What the first simulation pass did **not** cover

- Full `run_audit.cmd` / `verify-audit-behavior.ps1` (83 steps) on a **git-free mirror** of this checkout
- Pointing `run_audit` at **Airlock `repo/`** as project root (no wiring yet)
- **Sync** from working copy → `repo/` before publish audit
- **Python vs PowerShell** git detection parity — **closed (S25 / G01):** `audit_code_checks.git_head()` uses `git rev-parse` like `Test-PackGitRepo`

### Design implications for Airlock

1. **Recipient / other system (no key):** Full product audit remains valid in git-free mode. They lose only maintainer-only git backstops (Done-log history, index tracking, `.sh` index mode, Section N git hints) — all **intentionally optional** per WQ-459.
2. **Publisher (Airlock key, `repo/` has git):** Git-only checks must run **against `repo/`**, not the portable working copy — especially step 62, CI workflow, and pre-push proof (`commit+tree:`).
3. **Do not delete git guards** from the shared engine; keep **SKIP-when-no-repo** and add **`AIRLOCK_REPO_ROOT` / discovery** so maintainer verify can target `StarterPack-Airlock/repo/` when present.
4. **Before first publish:** add `sync-working-copy-to-airlock-repo.ps1` and a documented **`run_audit` from `repo/`** (or `-ProjectRoot` override) so git and non-git audits both run in the right zone.

---

## Out of scope for v1

- Remote publisher key rotation / HSM
- Multi-publisher keys on one machine
- Airlock inside the portable pack folder (forbidden — must stay on host Desktop)
