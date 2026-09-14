# StarterPack-Airlock — Desktop migration checklist

**Status:** Phases 3–4 + B10/B11 publish gate + **parallel build (GitMode Copy)** shipped — **live Desktop Airlock still maintainer-only** (this checkout still git-at-root)  
**Bootstrap:** `Initialize-StarterPackAirlock.cmd` or `pack/scripts/Initialize-StarterPackAirlock.ps1`  
**Evidence without live run:** sim **S12** (move), **S28** (full init), **S29** (Copy + cutover), **S14** (this checkout baseline)  
**Related:** `docs/STARTERPACK_AIRLOCK_PLAN.md`, WQ-483 row 13, WQ-465, WQ-489

---

## Re-open when

Maintainer approves creating `{Desktop}/StarterPack-Airlock/` on the host Desktop.

**You do not need to move `.git` on the first attempt** — use **parallel build** below.

---

## Pre-flight

| Step | Check |
|------|--------|
| 1 | Close Cursor windows on this pack checkout if using **`-GitMode Move`** or running **cutover** (`.git/cursor/` locks — WQ-461). **`-GitMode Copy`** can run with Cursor open if copy succeeds; on lock failure, close Cursor and retry. |
| 2 | Confirm OneDrive sync idle for the Desktop folder |
| 3 | Backup full checkout (robocopy or zip) outside OneDrive if unsure |
| 4 | `run_audit.cmd` exit **0** on working copy (Zone A) |
| 5 | Note current `VERSION` and engine in `docs/WORK_QUEUE.md` Done log if shipping |

---

## Parallel build (recommended first live run — WQ-489)

Build live Airlock **without** removing git from this checkout until publish is proven.

| Step | Action |
|------|--------|
| 1 | `Initialize-StarterPackAirlock.cmd -GitMode Copy` (or `-SkipGitMigrate` + manual `git init` in repo/ if copy fails) |
| 2 | Confirm: **both** working copy and `StarterPack-Airlock/repo/` report git (`Test-PackGitRepo` true on both) |
| 3 | **`Verify-AirlockPublishGate.cmd`** — Zone A (this checkout) + B09 sync + Zone B (`repo/`) |
| 4 | Configure remote on **`repo/`** only; human `git push`; first CI run |
| 5 | When satisfied: **`Complete-StarterPackAirlockCutover.cmd`** — **mirrors full working copy (with `.git`) to `D:\AgentStarterPack`**, then removes `.git` from working copy **only** |
| 6 | Post-cutover: working copy git-free; `repo/` still has git; **`D:\AgentStarterPack`** holds the last git-inclusive snapshot; refresh context; publish gate before each push |

**Toggle mental model:** Copy = both designs at once; cutover = flip working copy to git-free Zone A without touching `repo/`.

---

## Full cutover init (single step — when parallel is not needed)

| Step | Action |
|------|--------|
| 1 | `Initialize-StarterPackAirlock.cmd` (default **`-GitMode Move`**) |
| 2 | Creates `{Desktop}/StarterPack-Airlock/` with `publisher.key`, overlay, `repo/` |
| 3 | Moves `.git` from working copy → `repo/.git` (sim **S12**) |
| 4 | B09 sync aligns trees; working copy becomes git-free |

---

## Common sequence (after layout exists)

| Step | Action |
|------|--------|
| 1 | **`Verify-AirlockPublishGate.cmd`** (Zone A + B09 sync + Zone B) — or manual steps in `overlay/docs/PUBLISH.md` |
| 2 | Confirm gate exit **0** before push |
| 3 | Configure git remote on `repo/` only; **human** `git push` (working-copy policy refuses agent push — **S21**) |
| 4 | First CI run from `repo/` (unblocks WQ-455 / readiness row 12) |

---

## Post-migrate / post-cutover verify

- Working copy: `Test-PackGitRepo` **false** at pack root (after cutover or Move init)  
- `repo/`: `Test-PackGitRepo` **true**; behavior steps **50** and **62** index arms run (not SKIP)  
- `Refresh-AgentContext.cmd` on working copy — overlay `requiredReads` merged when discovery active (**WQ-487**)

---

## GitHub remote and CI (M04 — human maintainer)

Moving or copying `.git` to `repo/` does **not** move GitHub configuration. After remote setup:

| Item | Action |
|------|--------|
| **Remote URL** | `git remote -v` in `repo/` — set origin to the publish remote (not the working copy path) |
| **Actions secrets** | Re-create or confirm secrets on the GitHub repo that hosts `repo/` workflows |
| **Branch protection** | Re-apply rules on the publish default branch |
| **First CI run** | Unblocks **WQ-455** / readiness row 12 — read macOS job output before promoting to blocking |

## Not in scope for migration v1

- Repo-specific `.agent-control` overlay for agent `git push` (**H01** — publish stays **human-only**; see `overlay/docs/PUBLISH.md`)
- ~~**L01 `publisher.key` on OneDrive**~~ — **accepted** (maintainer account sync only)
