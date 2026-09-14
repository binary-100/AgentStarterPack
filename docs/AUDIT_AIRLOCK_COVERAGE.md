# Audit coverage under StarterPack-Airlock (dual-zone model)

**Purpose:** Define what "full audit accuracy" means when the working copy is git-free and git lives in Airlock `repo/`. This is the coverage contract for design and implementation — not a product feature doc for end users.

**Related:** `docs/STARTERPACK_AIRLOCK_PLAN.md`, `pack/docs/AUDIT_SYSTEM.md` (test-pass proof), WQ-459, WQ-461.

---

## Correcting "degrades gracefully"

That phrase was wrong for product audit.

| Term | Meaning |
|------|---------|
| **Product audit (Zone A)** | Everything a recipient needs: tests, machine checks, semantic gates, layout, wiring. **Full accuracy.** Proof = `tree:<sha256>` of audited file **contents**. |
| **Maintainer git audit (Zone B)** | **Additional** checks that only apply when git records history or file modes. Not a substitute for Zone A — an extra gate before publish/CI. |
| **SKIP** | A Zone B check reporting "not applicable in this zone" — **not** a weakened Zone A check. A passing run with `[SKIP]` lines is **expected** (behavior step 82). |

**Accuracy rule:** Zone A must pass with **zero `[FAIL]`** on a git-free tree. Zone B must pass on Airlock `repo/` before any publish. **Both** are required for a maintainer publish; **only Zone A** is required for a handout copy.

**Why `tree:` is not weaker:** HEAD alone does *not* detect uncommitted edits (documented in `AUDIT_SYSTEM.md`). The content fingerprint is the proof; git adds a commit prefix when available. On git-free copies, the fingerprint-only path is the **strict** path — behavior step 23 proves tampering after a pass is caught.

---

## Zones and where each check runs

| Zone | Path | Git | Audit entry |
|------|------|-----|-------------|
| **A — Working copy** | Any portable path | No | `run_audit.cmd` on working copy |
| **B — Airlock repo** | `StarterPack-Airlock/repo/` | Yes | `run_audit.cmd -RepoRoot …/repo` (planned) + CI |
| **C — Airlock overlay** | `StarterPack-Airlock/overlay/` | No | Merged into agent `requiredReads`; not a second product tree |

---

## Complete git-touchpoint inventory

Every functional git use in the audit stack, classified by zone.

### Zone A — Always runs (git not involved)

| ID | Component | What it checks |
|----|-----------|----------------|
| A01 | `audit_code_checks.py` | Sections A–M machine checks, semantic gates, domain map, static patterns |
| A02 | `run_audit_core.ps1` | Test runner, layout (non-git arms), manifest, timing |
| A03 | `verify-audit-behavior.ps1` | Steps 1–83 except git-only arms (most steps) |
| A04 | Section L | `.gitignore` **file content** for audit artifacts (reads file; no git command) |
| A05 | Test-pass proof | `tree:<sha256>` fingerprint of test runner + config + scanned code |
| A06 | `check-requirements.ps1` | git listed **optional** (`Required: false`) |
| A07 | Step 23 smoke | Creates **temp** git project to prove **both** proof modes work |
| A08 | Step 64 arms 1–4 | Done-log region without git backstop |
| A09 | Step 67 / WQ-454 | POSIX `bash install.sh` at mode 644 (no git required) |
| A10 | Step 80 | macOS-hostile construct scan in `.sh` files (no git) |
| A11 | Export / install | Strip `.git`, machine-local paths; manifest guard |

### Zone B — Git-only (must run in Airlock `repo/` before publish)

| ID | Component | What it checks | If skipped on working copy |
|----|-----------|----------------|----------------------------|
| B01 | Behavior **step 62** | Tracked `.sh` files mode `100755` in git index | `[SKIP] not a git checkout` |
| B02 | Behavior **step 50** (arm) | Machine-local paths **tracked** in git index | `[INFO] not a git checkout - index check skipped` |
| B03 | `run_audit_core.ps1` | Ephemeral dirs **committed** to git | Layout arm skipped |
| B04 | Section **N** (pack config) | Semantic cite after VERSION commits in git log | No git log → no N fix (opt-in section) |
| B05 | `verify-work-queue.ps1` | Done-log engine cites vs `git show HEAD:` history | `[SKIP] not a git checkout` |
| B06 | Step **64 arm 5** | Hand-edit to committed Done-log caught | Proven via **scratch repo** in step (not pack root) |
| B07 | `.github/workflows/pack-os-smoke.yml` | CI: clone execute-bit + mode-stripped install | Not in export zip |
| B08 | Test-pass proof prefix | `commit+tree:` when git answers | Working copy uses `tree:` only — **correct for Zone A** |

### Zone B — Planned (not built)

| ID | Component | Purpose |
|----|-----------|---------|
| B09 | `sync-working-copy-to-airlock-repo.ps1` | Sync tree into `repo/` before Zone B audit (**shipped** — sim S26) |
| B10 | `Find-StarterPackAirlock` + `-PublishRoot` on `verify-audit-system.ps1` | **Shipped (WQ-488, 2026-09-13)** — optional second behavior pass on Airlock `repo/` |
| B11 | `verify-airlock-publish-gate.ps1` | **Shipped (WQ-488, 2026-09-13)** — Zone A → B09 sync → Zone B; `[DUAL-ZONE FAIL]` when A green / B red |
| B12 | `docs/.audit_publish_attestation.json` + Zone B `run_audit` | **Shipped (2026-09-14)** — B09 writes tree fingerprint attestation; Zone B defers semantic to Zone A; CI validates attestation |

### Known parity gap (fix in Airlock Phase 1)

| ID | Issue | Risk |
|----|-------|------|
| G01 | Python `git_head()` tests `.git` **path**; PowerShell uses `Test-PackGitRepo` (`git rev-parse`) | Stale `.git` directory could confuse Python proof (WQ-461 class) |
| G02 | Step 50 arm still uses `Test-Path .git` before git calls | Same class on maintainer checkout only |

---

## Multi-angle test matrix (how we prove coverage)

| Angle | Harness | What it proves |
|-------|---------|----------------|
| **1 — Layout sim** | `simulate-airlock-scenarios.ps1` S01–S19 | Discovery, export, migrate, proof shapes |
| **2 — Git-free product** | Full `verify-audit-behavior.ps1 -PackRoot <git-free mirror>` | All 83 steps on tree with no `.git` |
| **3 — Proof algebra** | S17 + S19 + step 23 | `tree:` vs `commit+tree:`; tamper detection |
| **4 — Recipient path** | Robocopy mirror + `check-requirements` + WQ verify | Another system / flash parity |
| **5 — Export zip** | S07 + step 52 | Archive is complete working pack |
| **6 — Airlock repo** | S06, S12, S19 | Git isolated to `repo/` |
| **7 — CI contract** | `pack-os-smoke.yml` (Zone B only) | Clone + bash install path |
| **8 — Dual-zone gate** | **Planned S20+ / B11** | Zone A + Zone B both green before publish |

---

## Evidence: full behavior suite on git-free mirror (2026-09-12)

**Method:** Robocopy maintainer checkout to `%TEMP%\AgentStarterPack-gitfree-full-audit` excluding `.git`, then:

```powershell
verify-audit-behavior.ps1 -PackRoot '<that mirror>'
```

**Runtime:** ~8 minutes.

**Git-related output on git-free pack root (expected):**

- Step 50: `[INFO] not a git checkout (or git absent) - index check skipped`
- Step 62: `[SKIP] not a git checkout - nothing records the mode here`

**Steps that still exercise git:** 23 (temp GitApp), 64 arm 5 (scratch repo), 69 (TEMP probes) — **independent of pack root having `.git`.**

**First run result:** 5 `[FAIL]` — all from **new Airlock session files** not yet in manifest / pack hygiene (not from git removal):

1. Step 5b — `docs/STARTERPACK_AIRLOCK_PLAN.md` not in `packMirror`
2. Step 5b — `pack/scripts/simulate-airlock-scenarios.ps1` not in `packMirror`
3. Step 24 — non-ASCII in simulate script comments
4. Step 50 — user path in plan doc (fixed: placeholders only)
5. Step 61 — `Set-Content -Encoding UTF8` in simulate script (fixed: `Write-Utf8NoBom`)

**After manifest + hygiene fixes (same session):** Re-run on refreshed git-free mirror → **`Summary: 0 fail(s)`** (~8 min). Git SKIPs unchanged (steps 50, 62); all other steps pass.

---

## Publisher workflow (target state)

```
1. Develop in working copy (git-free)
2. Verify-AirlockPublishGate.cmd    -> Zone A + B09 sync + Zone B (WQ-488; or manual steps 2–4)
3. git push from repo/ only (human)
4. CI (pack-os-smoke.yml)           -> Zone B on macOS/Ubuntu
```

**Invariant:** Never treat Zone B SKIP on working copy as "audit passed for publish."

---

## Implementation checklist (coverage gates)

- [x] Zone A: git-free mirror behavior suite **0 fail** (2026-09-12, log: `%TEMP%\AgentStarterPack-gitfree-behavior-log2.txt`)
- [x] Zone B: behavior steps 62 + 50 index run against git repo mirror (2026-09-12; S22 `-IncludeHeavy`; step 50 log `%TEMP%\AgentStarterPack-step50-32848.log`)
- [x] B09 sync script (2026-09-12 — `pack/scripts/sync-working-copy-to-airlock-repo.ps1`, sim S26)
- [x] Publish sequence end-to-end with Zone B `run_audit` from synced `repo/` (sim **S27**, `-IncludeHeavy`; gate **B10/B11** — WQ-488)
- [x] G01: align Python `git_head()` with `Test-PackGitRepo` (S25)
- [x] Behavior step: dual-zone gate — **step 86** (WQ-488, 2026-09-13)
- [x] `AUDIT.md` / `AUDIT_SYSTEM.md` cross-link this doc — **`docs/AUDIT.md`**, **`pack/docs/AUDIT_SYSTEM.md`**

---

## Additional gaps (design review — not yet simulated)

Items outside the git-touchpoint inventory that can still break publish, mislead agents, or weaken the dual-zone model.

### High — can block publish or mislead agents

| ID | Gap | Why it matters |
|----|-----|----------------|
| H01 | **Hooks refuse agent `git push`** | **Accepted for v1:** publish is **human-only** from `repo/` (S21, `PUBLISH.md`, migration checklist). Repo-specific policy overlay deferred unless agents must push. |
| H02 | **Full-tree Zone B on live Airlock** | **Sim closed (S22/S27):** full synced `repo/` mirror + step 62/50 arms + publish-path finalize exit 0. **Live Desktop Airlock** still unverified (maintainer migrate). |
| H03 | ~~**Sync script undefined (`B09`)**~~ | **Closed 2026-09-12** — `sync-working-copy-to-airlock-repo.ps1` strips manifest lists and `.audit_*`. |
| H04 | **Dual `WORK_QUEUE` / `SESSION` ownership** | **Mitigated (WQ-487):** merge rules in `docs/AIRLOCK_DISCOVERY_AND_OVERLAY.md` § Overlay and work-queue merge; overlay is `requiredReads` only, not a second **Next**. Refresh step **84** verifies merge. |
| H05 | ~~**Working copy vs `repo/` drift**~~ | **Closed (WQ-488):** `Verify-AirlockPublishGate.cmd` / `verify-airlock-publish-gate.ps1` runs Zone A → B09 sync → Zone B in one sequence; behavior step **86**. |

### Medium — discovery, tooling, migration

| ID | Gap | Why it matters |
|----|-----|----------------|
| M01 | **`Get-AgentStarterPackCandidates` vs publish root** | Working-copy discovery unchanged by design; **`Find-StarterPackAirlock`** + **`Get-AgentStarterPackPublishRoot`** resolve `repo/` (WQ-484/487). Set **`AGENT_STARTER_PACK_ROOT`** when Desktop layout differs. |
| M02 | ~~**Which folder Cursor opens**~~ | **Closed (2026-09-13):** table in `docs/AIRLOCK_DISCOVERY_AND_OVERLAY.md` § Which folder to open in Cursor; migration checklist step 5 cites publish gate. |
| M03 | **`.git` migration on this Desktop** | Editor index under `.git/cursor/` (WQ-461). OneDrive locks. S12 proved move mechanics; not proved on **this** checkout with live Cursor/OneDrive. |
| M04 | **GitHub remote, secrets, branch rules** | **Documented:** `docs/AIRLOCK_MIGRATION_CHECKLIST.md` § GitHub remote and CI. Still **human-only** at migrate time. |
| M05 | ~~**`verify-audit-system.ps1` behavior arm**~~ | **Closed (WQ-488):** `-PublishRoot` runs Zone B behavior pass; **`verify-airlock-publish-gate.ps1`** orchestrates dual-zone verify. |
| M06 | ~~**Full `run_audit.cmd` on git-free mirror**~~ | **Closed (2026-09-13):** sim **S24** `-IncludeHeavy` — `pass1=1 finalize=0` on S17 git-free mirror (`%TEMP%\AgentStarterPack-airlock-sim-26224\S24\`). |
| M07 | ~~**Python `git_head()` path test (G01)**~~ | **Closed (S25):** aligned with `Test-PackGitRepo`. |

### Lower — hygiene, security, process

| ID | Gap | Why it matters |
|----|-----|----------------|
| L01 | ~~**`publisher.key` on OneDrive Desktop**~~ | **Accepted (maintainer 2026-09-13):** key syncs with OneDrive on maintainer account only — no exclusion required. |
| L02 | **Backup / second Desktop copy** | Step 75 excludes backup paths from verify; Airlock + working copy + backup = three trees. Robocopy mirror discipline. |
| L03 | ~~**WQ row for Airlock phases**~~ | **Closed** — WQ-483–488 in `docs/WORK_QUEUE.md` Done log. |
| L04 | **Semantic self-audit sections** | New plan/coverage docs not yet in a completed semantic report pass. |
| L05 | ~~**`.gitattributes` in `repo/`**~~ | **Closed:** B09 `robocopy /MIR` copies root files including `.gitattributes` (not in strip lists). |
| L06 | **Agent refuses `-PushFromProject`** | Correct for default policy; maintainer pushing template fixes from a reference app still **human-only** — confirm acceptable. |

### Angles still worth adding to the sim matrix

| Angle | What it would prove |
|-------|---------------------|
| **S20 — Full sync dry-run** | Robocopy with maintainerOnly + machineLocal strip rules → `repo/` matches export hygiene |
| **S21 — Policy in `repo/`** | Hook simulation: `git push` with repo-root policy overlay vs working-copy policy |
| **S22 — Zone B behavior** | `verify-audit-behavior.ps1 -PackRoot <airlock repo after sync>` — steps 62/50 arms run, not SKIP |
| **S23 — Drift detector** | VERSION mismatch between working copy and `repo/` fails a pre-push gate |
| **S24 — `run_audit.cmd` git-free** | End-to-end product audit path on mirror (not only behavior script) |
