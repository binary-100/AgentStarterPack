# Handover — Agent Starter Pack (read this first)

**Purpose:** Onboard an AI agent on **another machine or in a new chat** to continue work on the Agent Starter Pack without re-discovering context from scratch.

**Last updated:** 2026-08-30 (installed to profile; audit engine **2.22.24**; canonical queue in `docs/WORK_QUEUE.md`)

**Continuing over a weekend or on another machine?** Read **`WEEKEND_HANDOFF.md`** first — it carries the
transfer path, the one remaining portability limit, and what is deliberately deferred.  
**Pack version:** root `VERSION` (**1.8.0**)  
**Audit engine version:** `pack/audit/manifest.json` (**2.22.43**)  
*Both cites above are maintained by `Sync-DocVersions.cmd` — the sync only recognises the parenthesised form, so keep it.*  
**Repo location:** wherever the pack folder is plugged in. It is carried on a **removable exFAT drive** (was `D:\AgentStarterPack` when this was written; the letter changes per machine). Paths below are relative to the pack root — never hard-code the drive.

**Also read:** `AGENTS.md` → `pack/docs/START_HERE.md`

---

## 0. First 5 minutes on a new machine

```powershell
cd <this pack folder>
.\Check-Requirements.cmd              # can this machine run the pack? names what is missing
.\run_audit_tests.bat                 # pack tests + behavior + system verify — expect exit 0
py -3 .\pack\scripts\sync_doc_versions.py (Get-Location).Path --verify
```

All pass **without** installing and **without** any environment variable: pack scripts resolve the pack they were launched from, so the drive letter is irrelevant.

**Requirements (2.21.17):** PowerShell 5.1+, Python 3.8+ **with the `py -3` launcher**, and a passing `audit_code_checks.py --self-test` are required; the `mcp` package and git are optional and named as such. `Check-Requirements.cmd` prints the install command for anything missing (`-Fix` installs the Python packages, `-Json` for agents). `install.ps1` runs the same check and stops on a missing required item.

On a machine with no install, expect one **`[WARN] Pack not installed for this profile`**. That warning is the integration step, not damage. Only run install when the user asks; it writes `%USERPROFILE%\.cursor\{AgentStarterPack,rules,skills,mcp.json}`. **Back up `mcp.json` first** — it is the user's own config, the installer rewrites the whole file, and until 2.21.22 it deleted every server already in there.

This machine now *has* a user-scope install (2026-08-27), so those checks report green here. See section 6.

**What "portable" means here (do not widen it):** the **pack folder** travels on a USB stick and must run from any drive letter on any machine. The **install** is deliberately *not* portable — Cursor only reads global rules and skills from `%USERPROFILE%\.cursor\`, so each machine gets its own install, and that copy is machine-local and disposable. Consequences that shaped the design:

- `sync-audit-system.ps1` pushes **one way**, pack folder → installed. A stale install on some machine must never overwrite the stick or resurrect files deleted from it. `-PullFromInstalled` is the explicit opt-out.
- Do not tell users to `setx AGENT_STARTER_PACK_ROOT` to a removable path — the letter changes. It is a per-session override for testing an uninstalled pack.
- Bootstrapping a project on a machine without an install bakes the stick's current path into that project's MCP config. Bootstrap now warns; the fix is to install first.

---

## 1. What this project is

**Agent Starter Pack** is portable tooling that bootstraps AI-friendly projects with:

| Capability | What it gives agents |
|------------|----------------------|
| **Audit system** | Closed-scope audits (`run_audit.cmd`) → report **Fix** and **Improve** only; machine checks + semantic deep scan |
| **Bootstrap** | `bootstrap-project.ps1` — `AGENTS.md`, audit wiring, per-tool entry files (Cursor, Claude, Copilot, Windsurf), Python version sync |
| **Global rules & skills** | `install.ps1` copies generic guidance to the user profile (Cursor-first) |
| **Terminal hygiene** | agent-hygiene MCP + PowerShell fallbacks for stuck terminals and orphan processes |
| **Version + doc sync** | Build pipeline keeps `VERSION`, README, and agent docs aligned (Python apps + pack maintainer docs) |
| **Maintenance scripts** | Sync audit templates, generic rules, doc versions across pack ↔ installed copy ↔ reference projects |

**Design goal:** Work in **as many agents/models/IDEs as possible** via portable repo files (`AGENTS.md`, `AI_INSTRUCTIONS.md`, scripts). Cursor gets the deepest integration (`.mdc` rules, skills, MCP). See `docs/PORTABLE_SETUP.md`.

**Location model (2.21.14):** two roots, kept distinct.

| Root | What it is | Portable? | How it is found |
|------|------------|-----------|-----------------|
| **Source pack** | The pack folder you edit and carry (USB stick) | **Yes** — any drive letter, any machine | `pack-paths.ps1` derives it from the running script's own path |
| **Installed pack** | `%USERPROFILE%\.cursor\AgentStarterPack` + global rules/skills/`mcp.json` | **No, by design** — one per machine | Written by `install.ps1`; what agents and bootstrapped projects read |

Never hard-code either one. Pack scripts derive the source; project scripts check `AGENT_STARTER_PACK_ROOT`, then the profile install. Bootstrapped projects depend on the **installed** copy on purpose, so they keep working after the stick is unplugged.

**Generic-only policy (2.21.13):** The pack must **not** name, path, or document any specific user application. Use placeholders (`MyApp`, `main.py`, `C:\Users\alice\Projects\...`). In-repo examples: **`pack/audit/behavior-fixture/`** and **`pack/templates/docs/AUDIT.app.reference.md`**. Do not edit external app repos from this workspace.

---

## 2. Conversation summary (what the user asked for)

This handover covers a multi-session workstream. Chronological intent:

1. **Explain the project** — Agent Starter Pack for AI agent workflows, not application code.
2. **Hard edit boundary** — Agents working in this workspace may **only** modify `AgentStarterPack`. Other repos in docs are references, not edit targets.
3. **Recommendation discipline** — Before suggesting or executing work: state target paths, layer, whether writes go elsewhere, downside. Default-first; no invented alternatives.
4. **Clarify “every machine/session”** — Distinguish workspace-only rules vs user-global rules installed by `install.ps1`. User rejected vague global scope; pack rules are generic but installed globally by choice.
5. **Doc version drift on updates** — Built automated sync so version bumps propagate to README, START_HERE, audit docs, etc.
6. **User correction: doc sync for all apps, not pack-only** — Extended to bootstrapped Python projects.
7. **User correction: doc sync is build pipeline, not audit** — Moved to `docs/VERSION_SYNC.json` + `doc_version_sync.py`; decoupled from audit `codeChecks`.
8. **Review for breakage** — Found and fixed Generic bootstrap bug, manifest gaps, dual config confusion.
9. **Install + verify** — Ran `install.ps1 -Scope User` and `verify-agent-setup.ps1` successfully (installed copy at 2.21.12).
10. **Sync running agents** — Discussed limitation: open chats cannot hot-reload rules. Proposed **Agent Context Refresh** (tool-neutral `docs/AGENT_REFRESH.md` + CLI). **Built in 2.21.23** and hardened in 2.22.2 — see §5. Do not re-design it.
11. **Portability question** — Confirmed much is Cursor-specific in *delivery* but protocol (files + CLI) can be tool-neutral. Refresh design should live in `docs/`, not `.cursor/`.
12. **This handover** — Full state write-up for the next agent.
13. **Generic-only pack (2.21.13)** — Removed all product-specific references, paths, and audit reference files from the repo. Replaced with generic app reference templates; `-ReferenceProjectRoot` (not product-named params); `Update-AgentRules.cmd` takes optional `%1` ProjectRoot only.
14. **Validation** — Full verify suite + `run_audit_tests.bat` passed at **2.21.13** on the maintainer machine; zero product-name strings on disk (purge stale `pack/scripts/__pycache__` if grep hits bytecode only).
15. **Portability (2.21.14)** — Running the pack folder from another machine broke every maintainer script: pack discovery guessed a fixed list of locations (`%USERPROFILE%\.cursor\...`, then Desktop) instead of using the script's own path, so scripts failed with `No starter pack (Desktop or installed)` — and on a machine that *did* have an install, they silently operated on the installed copy instead of the folder being edited. Fixed source-first; see §5.
16. **User correction: portable means the USB pack folder, not the install (2.21.15)** — Per-machine installs into `%USERPROFILE%\.cursor\` are expected and fine. What must survive travel is the pack folder. Re-audited against that: made the installed mirror one-way so a stale install cannot clobber the stick, warned when bootstrap would bake the stick's path into a project, and removed advice to make `AGENT_STARTER_PACK_ROOT` permanent for a removable drive.

---

## 3. Architecture — rule layers (critical)

| Location | Scope | Examples |
|----------|-------|----------|
| **`.cursor/rules/`** (repo root) | **This workspace only** | `pack-only-edit-boundary.mdc`, `agent-recommendation-discipline.mdc`, `starter-pack-repo.mdc`, `audit.mdc` |
| **`pack/rules/`** | **All projects** after `install.ps1` → `%USERPROFILE%\.cursor\rules\` | `agent-defaults-always.mdc`, `generic-version-sync.mdc`, `generic-agent-doc-hygiene.mdc`, `full-paths-in-chat.mdc`, … |
| **Project `.cursor/rules/`** | **Per app repo** | Product-specific + synced copies of `pack/rules/` via `sync-project-rules.ps1` |

**A profile rule is not proof of a pack rule.** `%USERPROFILE%\.cursor\rules\` also holds rules the
**user** added, which the pack neither ships nor owns. On this machine that includes
`structured-chat-output.mdc` (response formatting): it was briefly added to `pack/rules/`, and the user
corrected that — *"this layout change is for this system and its agents, it's not something that is
supposed to be built into the AgentStarterPack."* It was reverted from the pack and left in the profile
with a footer saying so. So if you see a profile rule or skill that `pack/rules` does not contain:
**do not add it to the pack, and do not prune it.** `update-agents.ps1` already distinguishes the two
using the `rules`/`skills` lists recorded in `install-manifest.json` — files a previous install
recorded shipping are stale candidates; everything else is the user's and is never touched. The
generic-only policy cuts the same way: a preference that belongs to one machine stays on that machine.

**Hard stop:** `pack-only-edit-boundary.mdc` — never write outside `AgentStarterPack` unless the user explicitly opens another repo for editing. Do not run `sync-project-rules.ps1`, `bootstrap-project.ps1 -ProjectRoot …`, or `Update-AgentRules.cmd` with an external path from this workspace unless the user names that target.

**Never add product-specific names or paths** to `pack/rules/`, templates, or maintainer docs — keep the pack reusable for any agent/project.

**Install writes outside the Desktop repo:** `install.ps1` updates `%USERPROFILE%\.cursor\AgentStarterPack\`, `%USERPROFILE%\.cursor\rules\`, skills, `mcp.json`. Only run when the user asks to install/upgrade.

---

## 4. Version & doc sync (current model — read carefully)

### Problem

Agents bump `VERSION` in code but forget README, `AGENTS.md`, maintainer docs, or audit engine version cites.

### Solution (as of 2.21.12)

**Build pipeline, not audit primary path.**

| Piece | Role |
|-------|------|
| **`docs/VERSION_SYNC.json`** | Build config — what to sync (separate from `AUDIT.config.json` `codeChecks`) |
| **`pack/scripts/doc_version_sync.py`** | Standalone sync engine |
| **`pack/scripts/sync_doc_versions.py`** | CLI wrapper |
| **`pack/scripts/sync-doc-versions.ps1`** / **`Sync-DocVersions.cmd`** | PowerShell entry (maintainer) |
| **`apply_version.py`** (bootstrapped) | `sync` subcommand → version + docs before tests |
| **`run_tests.bat` / `build_ci.bat`** (Python template) | Call `apply_version.py sync` before tests |

**Pack maintainer** uses `maintainerDocSync` in `docs/VERSION_SYNC.json` (pack version + audit manifest version cites, including `bootstrap-project.ps1` `bootstrapVersion`).

**Python apps** use `docSync` in their `docs/VERSION_SYNC.json` (from template).

**Legacy:** `docVersionSync` in `AUDIT.config.json` still exists as fallback in `doc_version_sync.py` but is **`enabled: false`** in pack template and pack `docs/AUDIT.config.json`. Prefer `VERSION_SYNC.json`.

**Generic stack bootstrap:** Uses `run_tests.generic.bat.template` — tests only, **no** `apply_version.py` (fixed bug where Generic stack would call missing script).

---

## 5. What was built / changed in this workstream

### Workspace-only (Agent Starter Pack repo)

- **`.cursor/rules/pack-only-edit-boundary.mdc`** — hard edit stop
- **`.cursor/rules/agent-recommendation-discipline.mdc`** — scope before execute, install callout, rule layers
- Updated **`AGENTS.md`**, **`.cursor/rules/starter-pack-repo.mdc`**

### Global pack rules (`pack/rules/` → `install.ps1`)

- **`generic-agent-doc-hygiene.mdc`** — read existing agent docs before adding rules; version cites via build pipeline
- **`generic-version-sync.mdc`** — updated for `VERSION_SYNC.json` + build pipeline
- **`agent-defaults-always.mdc`** — pointer to doc hygiene rule
- **`full-paths-in-chat.mdc`** — full absolute paths in user-facing chat

### Scripts & templates

- **`doc_version_sync.py`**, **`sync_doc_versions.py`**, **`sync-doc-versions.ps1`**
- **`Sync-DocVersions.cmd`** (pack root)
- **`docs/VERSION_SYNC.json`** (pack maintainer config)
- **`pack/templates/docs/VERSION_SYNC.json.template`**
- **`pack/templates/run_tests.generic.bat.template`** — Generic stack tests without version sync
- **`verify-agent-setup.ps1`** — pack-only by default; optional `-ReferenceProjectRoot` for app checks
- **`bootstrap-project.ps1`** — Python-only `VERSION_SYNC.json`; Generic uses generic test bat
- **`sync-project-rules.ps1`** — enumerates `pack/rules/*.mdc` (it carried a hardcoded 9-name list until 2.22.1)
- **`Update-AgentRules.cmd`**, **`Verify-AgentSetup.cmd`**

### Audit engine

- Manifest **2.21.8 → 2.21.13** with changelog entries in **`pack/docs/AUDIT_SYSTEM_CHANGELOG.md`**
- `audit_code_checks.py` delegates `--sync-doc-versions` to `doc_version_sync.py`
- Removed audit Improve loop for app version docs (sync is build-time now)

### Generic-only cleanup (2.21.13)

| Removed | Replaced with |
|---------|----------------|
| Product-specific audit reference JSON/MD templates | **`AUDIT.config.app.reference.json`**, **`AUDIT.app.reference.md`** (`MyApp` / `main.py`) |
| Hardcoded external paths in `Update-AgentRules.cmd` | Install only; optional **`%1` = ProjectRoot**, **`%2` = rules path** (default `.cursor\rules`) |
| Former product-named root parameter and product-specific checks in `verify-agent-setup.ps1` | **`-ReferenceProjectRoot`** — generic rules sync + audit drift only |
| `manifest.referenceProject` default Desktop path | Empty default; **`AUDIT_REFERENCE_PROJECT_ROOT`** env; flat layout push paths |
| Legacy forbidden overlay rule name | **`product-audit-overlay.mdc`** (generic forbidden artifact name) |

**Deleted from working tree (commit when user asks):** old product-specific `AUDIT.config.*.reference.json` and `AUDIT.*.reference.md` template files — do not restore.

### Portable pack root (2.21.14)

| Change | Why |
|--------|-----|
| **`pack-paths.ps1`** — `Get-SourceAgentStarterPack` first, then env vars, installed copy, legacy Desktop names | Scripts act on the pack they were launched from, on any drive |
| **`sync-audit-system.ps1`** — "source pack" replaces "Desktop pack"; no installed copy reports one `[INFO]`, not 77 drift lines | A fresh machine is un-integrated, not drifted |
| **`verify-audit-system.ps1`** — `run_audit_core.ps1` accepted from project / resolved pack / installed; profile checks only enforced when the pack is actually installed | Pre-install verify is honest instead of alarming |
| **`verify-agent-setup.ps1`** — states up front when the profile has no install | Its failures are the install step, not pack damage |
| **Project templates + fixture** — `AGENT_STARTER_PACK_ROOT` then profile install, with an actionable error | Projects can use a pack that was never installed |
| **`run_audit.ps1.template`** — self-contained resolution | It dot-sourced `pack-paths.ps1` from the project's `scripts\` folder, where bootstrap never copies it — every bootstrapped project's audit entry point was broken |
| **`run_audit_core.ps1`** — test-pass proof from `audit_code_checks.py` first | PowerShell recorded the outer repo's git HEAD while Python recomputed an mtime fingerprint from the app root, so finalize was always "stale" once the checkout became a git repo (behavior test 18) |
| Deleted tracked **`install-manifest.json`**, dropped from `export.ps1`, gitignored | It carried one machine's install record and shipped it to other machines |

### Removable-media safety (2.21.15)

| Change | Why |
|--------|-----|
| **`sync-audit-system.ps1`** — one-way mirror (source → installed) by default; **`-PullFromInstalled`** for the old newest-wins reconcile | The old code copied installed → source when the installed file looked newer *or* when the source file was missing. On a USB-hosted pack that means a stale machine-local install can overwrite the stick, and files deleted on purpose come back |
| Same — cross-filesystem mtimes are not comparable | Removable exFAT stores local time, NTFS stores UTC; "newest wins" can pick the wrong side after a timezone or DST change |
| **`bootstrap-project.ps1`** — warns when the pack is not installed on this machine | Otherwise the generated project's MCP path points at the stick; it breaks on drive-letter change or unplug |
| Docs — USB workflow in `docs/PORTABLE_SETUP.md`; `AGENT_STARTER_PACK_ROOT` framed as a session override | A permanent env var pointing at a removable drive letter is worse than none |

### Mirror direction under test (2.21.16)

| Change | Why |
|--------|-----|
| **`verify-audit-behavior.ps1`** step 20 — miniature pack + scratch install target under `.tmp/`, asserting all four direction rules | The 2.21.15 safety property had no test at all: the mirror only runs when an install exists, so `run_audit_tests.bat` never touched it |
| **`pack-paths.ps1`** — `AGENT_STARTER_PACK_INSTALL_ROOT` redirects the install *destination*; `Get-AgentStarterPackUserRoot` derives the profile rules/skills folder from it | Lets the mirror be tested (and a relocated profile be supported) without writing into `%USERPROFILE%`. Step 20 asserts the real profile stays clean |
| **`sync-audit-system.ps1`** — an installed-only file at a manifest path is now deleted from the installed copy, not skipped | **Defect found by the new test:** skipping left `-VerifyOnly` red forever and `-AutoFix` unable to converge. The source pack is authoritative about deletions too; `-PullFromInstalled` still copies it back |

### Dependencies and first-run correctness (2.21.17)

Triggered by a plain question: if the pack needs tools that are not installed, why does nothing check for them? Nothing did — and looking for the answer, an end-to-end bootstrap found three first-run failures.

| Change | Why |
|--------|-----|
| **`check-requirements.ps1`** + **`Check-Requirements.cmd`** — preflight naming every requirement, its purpose, and its install command; `-Fix`, `-Json`, `-PythonCommand` | Missing prerequisites surfaced as cryptic failures deep inside a script. Runs from the pack folder with no install, which is the state a stick arrives in |
| Wired into **`install.ps1`** (stops, `-SkipPreflight` overrides), **`bootstrap-project.ps1`** (warns), **`doctor.ps1`** (delegates) | One source of truth for what the environment needs |
| Preflight runs **`audit_code_checks.py --self-test`** | An interpreter on PATH is not proof the engine runs here |
| **`'py -3' launcher` is a separate required row** | Every `.cmd` in the pack and in generated projects calls `py -3`; a machine with only `python.exe` passes a naive check and still cannot audit |
| **`doctor.ps1` false positive fixed** — probe imports `mcp.server.fastmcp` from outside the pack | `import mcp` succeeds from the pack root because the pack's own `mcp\` folder becomes a namespace package. Doctor reported the dependency present while the server could not start |
| **`tests/test_pack_audit.py`** runs standalone and is wired into `run_audit_tests.bat` | It was pytest-only, so nothing ever ran it — while the audit inventory counted it as coverage. The pack now has no test dependency the preflight does not check |
| **BOM crash** — reads use `utf-8-sig`; bootstrap writes plain UTF-8 | **Every bootstrapped project's first audit died** in `load_config` with `Unexpected UTF-8 BOM`, because `Set-Content -Encoding UTF8` writes a BOM on PowerShell 5.1. The pack's own audit passed, so this was invisible from here |
| **Auditing a project no longer installs the pack** — mirror skipped whenever no install exists, write mode included | A project's `run_audit.cmd` with `autoFixDrift` created `%USERPROFILE%\.cursor\AgentStarterPack` plus profile `rules\` and `skills\`. Found live: it installed 72 files on a machine that had deliberately never installed. Behavior step 20 now asserts `sync never creates an install` |
| **`bootstrap-project.ps1`** — creates the target folder; no bare `True` per file | Bootstrapping a new project failed with a raw `Resolve-Path` error, and every generated file printed a stray `True` |

### Generated projects pass their own audit (2.21.18)

The pack's promise is "drop the folder on a machine, bootstrap a project, audit it." That path had never been executed end to end. Automating it (behavior step 23) found six defects, four of which made a generated project's audit permanently unpassable.

| Change | Why |
|--------|-----|
| **`run_audit.ps1.template`** — repo root stays the app root unless the app is a folder named `app` holding `docs\AUDIT.md` | `Split-Path -Parent $AppRoot` is right only for the nested layout, but bootstrap generates flat projects. Every generated project audited its **parent folder**: scanned sibling projects' `.md` and `.env`, sought `README.md` a level too high, and gave `sync-audit-system.ps1` the wrong `-ProjectRoot`, which reported all nine audit files as drift |
| **`run_audit_core.ps1`** — test-pass proof captured *after* tests pass, not in the init phase | The generated test script runs the version/doc sync, which rewrites files the proof covers. With git the proof is a stable HEAD so this was invisible; without git (any project before `git init`) the verifier's recompute never matched and `Semantic report stale` was permanent |
| Both fingerprint helpers return no proof for an empty file set | They hashed zero files into `sha256("")` — a constant that looks like a valid proof and matches forever |
| **Executable templates are ASCII-only** | `apply_version.py.template` printed a `→` on the "already synced" path. Redirected console output is cp1252, so `UnicodeEncodeError` failed the whole test step: generated tests passed on audit 1 and failed on every audit after |
| **Domain-map heading match anchored to line start**; `scanDir` joined with `\` not `.` | The search matched the template's own prose ("Include a **## Domain map** table..."), so the real table was never read and every module looked unmapped. Trailing text (`## Domain map (example - ...)`) still works |
| Audit test run sets **`PYTHONDONTWRITEBYTECODE`** | Its own test run left `__pycache__`, which the cruft check reported as a Fix the user could never clear |
| **Bootstrap writes `README.md` + `VERSION.txt`**; Python `sectionTests` maps D to the generated test; Generic no longer describes a `main.py` it never creates | The generator handed the user Fix items for files and settings the generator itself produced — four permanent ones on every Generic project |
| **Behavior step 23** — bootstrap both stacks, audit Python twice, assert machine-clean | Reading templates is not evidence |

### The gate itself had to be made honest (2.21.19)

Three checks were producing signals that were not true, and a product audit was doing the pack's work. None of these were caught by reading code; each came from running the workflow a user runs.

| Change | Why |
|--------|-----|
| **A product audit no longer runs the pack's behavior suite** — `run_audit_core.ps1` passes `-SkipBehavior` to `verify-audit-system.ps1` for any root without `pack/audit/manifest.json`, and proves the engine with `audit_code_checks.py --self-test` instead | The suite is the pack's own test suite: it bootstraps and audits probe projects **inside the pack folder**, costs ~30-50s, tells the user nothing about their code, and via step 23 re-enters itself. A Generic project audit now measures 4s; the suite it used to pull in takes ~33s by itself. Drift and doc-version checks still run, so the wiring signal is not lost |
| **Every generated project starts with a real gate** — the `AUDIT.md` template ships six checklist sections (A, B, C, D, K, L); an empty required-section set is now a Fix | Required sections are the union of the checklist, domain map, `sectionTests`, and hints. The template defined none, so a Generic project reported a **clean audit having reviewed nothing** |
| **Nested layout must be proven, not guessed** — app root has no `.git`, is named `app`, holds `docs\AUDIT.md`, and its parent is a git repo | PowerShell compares case-insensitively, so an ordinary flat project named `App` matched `'app'` and audited its parent. Found by accident when a probe folder was named `App` |
| **`testsPassedAt` is stamped when tests pass** | It was stamped at the *end* of the run — after the semantic template that same run writes — so an auditor filling that template in place was told the deep scan predated the test pass. Root cause: `$testsPassedAt = ''` **is** `$script:TestsPassedAt` (case-insensitive names), which silently wiped the stamp |
| **`check_section_n_improve` stands down once section N is reviewed** | It repeated "agent must review release delta" on reports that already contained the review — an Improve line nobody could close |
| **Wiring failure message names the right owner** | A product audit told the user to "run sync + verify after audit-system edits" when the *pack* was internally inconsistent — not something they can fix in their project |
| **Behavior step 24** — executed code is ASCII and BOM-free (`.ps1`, `.py`, `.cmd`, `.bat`, executable templates) | Three separate crashes came from encoding: the bootstrap BOM crash, this preflight failing to parse on an em dash, and generated tests dying on `UnicodeEncodeError`. 37 characters normalized; the `?"` mojibake in the suite's own output is gone |
| **Step 23 walks the full workflow** — bootstrap, machine pass, semantic fill, finalize — and requires a **clean** audit, plus asserts a folder named `app` does not hijack the repo root and that a product audit never runs the pack suite | Machine-clean was too weak a bar: it never proved a new project can actually *finish* an audit |
| **`sync-project-rules.ps1`** defaults to `.cursor\rules`; `AGENT_WORKFLOW.md` and `verify-agent-setup.ps1` added to `packMirror`; dead duplicate `sync_doc_versions()` (181 lines) removed | The old default created a stray `app\` tree in flat projects. The two unmirrored files reached a *fresh* install via `Copy-Tree` but went stale on every later sync — found by the self-audit's own Section B review |

### Proof, runner coverage, and the filler bypass (2.21.20)

See the changelog entry for detail. Three things worth carrying forward: the test-pass proof is
`<git HEAD>+tree:<sha256 of file contents>` and the PowerShell and Python implementations must stay
byte-identical; a test runner that never executes its test files is now a Fix
(`check_test_runner_coverage`); and `--fill-semantic-fixture-test` requires `AUDIT_FIXTURE_TEST=1`
because it could otherwise fake an entire semantic review in one command.

### Whole-folder sweep: transfer, install, and inert checks (2.21.21)

This round started from "check everything, not just the parts you touched." Three sweeps read the
full tree — every check against its test coverage, every file for reachability and encoding, every
doc and rule against the code it describes — and produced ~40 findings. Each was re-verified before
acting on it; one claim (that `install.sh` did not exist) was wrong. What changed:

| Change | Why |
|--------|-----|
| **`export.ps1` verifies the staged tree against `manifest.json` `projectRequired.flatLayout`** and throws with the missing paths named; machine-local leftovers (`.pyc`, `.tmp`, `.audit_*`) are pruned | The hand-maintained item list had drifted: `run_audit.cmd`, `run_audit_tests.bat`, `AGENTS.md`, `scripts\`, `tests\`, and `.cursor\rules\audit.mdc` were all absent, so a transferred pack could not run the audit every transfer doc prescribes — and `Test-Path` guarded each copy, so nothing failed. Proven both ways: dropping `run_audit.cmd` from the list now fails the export |
| **Brace globs are expanded in `scan_static_patterns`**; a rule may declare `requireMatches`; unbalanced braces are always a Fix | `"glob": "*.{md,ps1,...}"` is shell syntax that `rglob` treats as a literal filename, so the pack's only content rule had **never scanned a file**. `requireMatches` is opt-in because an empty scope is legitimate — a Generic project has no `*.py` for the safety patterns |
| **`packReferenceConfig` compares the markdown pair too** | `AUDIT.pack.reference.md` had drifted 16 lines from `docs/AUDIT.md` with nothing checking it |
| **Section N is opt-in, and where enabled it joins the required sections** | N is not a checklist heading, so a default-on check demanded a section `--write-template` never stubbed: an unfixable Fix as soon as git showed a version commit |
| **Skills added to `packMirror`/`packToUser`; behavior step 5b covers skills** | `install.ps1` `Copy-Tree`s the whole skills folder, so two of three skills installed once and then went stale forever — the exact defect 5b was written for, with a rules-only implementation |
| **`doctor.ps1` enumerates `pack\rules` and `pack\skills`** | The hardcoded list validated 5 of 9 rules, so four could be missing from a profile and doctor still said `[OK]` |
| **`install.ps1` skips `.git`, `.tmp`, `__pycache__`, `.pyc`, and `.audit_*`; hidden files are no longer dropped** | It copied the whole tree into the profile and `Copy-Tree` only ever adds, so the sending machine's audit results and bytecode would live there permanently |
| **`run_audit_core.ps1` reads `docs/AUDIT.md` with `-Encoding UTF8`** | PowerShell 5.1 decoded the BOM-less UTF-8 file as ANSI and wrote mangled em dashes into `docs\.audit_agent_manifest.json` — the brief the next agent reads |
| **Bootstrap writes `.cursor\rules\audit.mdc` for every target**; `version-sync.mdc.template` goes through the expanding writer | The audit system requires that rule of every project, so `-Targets Portable`, `Claude`, or `Copilot` produced a project that failed its own first audit. The version-sync rule shipped with `{{SOURCE_MODULE}}` as its literal frontmatter glob |
| **`run_audit_tests.bat` passes `-SkipBehavior` to `verify-audit-system.ps1`** and warns when falling back to the installed pack | The behavior suite ran twice per test run (three times during a self-audit). Full run: ~86s → ~56s, same assertions |
| `install.sh` re-written with LF endings (its `#!/usr/bin/env bash\r` was unrunnable on Unix); `sync-doc-versions.ps1` CR-CR-LF normalized; the `.gitignore` snippet merged into every generated project made ASCII | Encoding defects in shipped files that no gate covered — step 24 scans executed code, not `.sh` or `.snippet` |
| Docs and rules: skill pointers (dead heading, `A–N`, `run_tests.bat`), `-Scope Both` guidance, `%USERPROFILE%` fallbacks in two globally installed rules, Python-only commands in an always-on rule, `-Targets` table, `VERSION` vs `VERSION.txt`, the 1.7.0 installer rename arrow, doc-sync trigger file, step counts | 24 doc/rule discrepancies; these are the ones that would send an agent to a path or command that does not exist |

**Still open, deliberately:** import smoke covers root `*.py` only (modules under `moduleSearchDirs`
are inventoried but not import-tested); `install.sh` does not mirror the PowerShell installer's
project-scope skill exclusion; ~3,300 lines of pack PowerShell remain outside Section B's inventory
(documented in `docs/AUDIT.md`). The pruning gap listed here at 2.21.21 was closed in 2.21.22 —
`install.ps1 -Prune`; see the note in §6.

### Installing it found what reading it could not (2.21.22)

The user authorized a user-scope install on this machine specifically to close the validation gaps
listed below. The very first install **deleted 13 configured MCP servers**:

- **`Merge-McpJson` destroyed every pre-existing server.** It set the new key with
  `$existing.mcpServers."agent-hygiene" = $entry`. Dot-assigning a *new* property on the
  `PSCustomObject` that `ConvertFrom-Json` returns throws on PowerShell 5.1; the `catch` reported
  "could not parse existing mcp.json" (blaming the user's file), and the rewrite that followed wrote
  the freshly built single-server object. Fixed with `Add-Member -Force`; an unparseable config is now
  backed up and **left in place** with nothing registered; `-Depth` 6 to 10; written BOM-free. The
  user's 13 servers were restored from backup and re-verified byte-identical.
- **The installer re-created the bytecode its own copy filter excludes.** 2.21.21 taught `Copy-Tree`
  to skip `__pycache__`; the install then ran doc sync *out of the installed tree*, regenerating it
  there. Bytecode writing is suppressed for those steps and the tree is pruned at the end.
- **Behavior step 26** now covers both profile-writing functions by AST-extracting them from
  `install.ps1` and running them against scratch paths. Proven by reintroducing the old assignment:
  the step fails with the underlying PowerShell error as the reason.
- **`Update-AgentRules.cmd` reports what an update changed** via new `pack/scripts/update-agents.ps1`
  (rules/skills/pack files by hash, MCP servers, files the pack no longer ships, then `doctor.ps1` and
  sync verify), and prints the line to paste into a chat already in progress.

Lesson for the next agent: three previous passes reviewed `install.ps1` by reading it and called it
clean. The defect needed one real run. Prefer executing a path over inspecting it, and when the path
writes to `%USERPROFILE%`, back up what it touches first.

### The two tracks from the other machine's handoff (2.21.23 + 2.22.0)

`PACK_IMPLEMENTER_HANDOFF.txt` and `PACK_IMPLEMENTER_SPEC.md` (repo root, written against baseline
2.21.13) assigned two tracks that had never been built here. Both are now shipped, as separate bumps.

**Phase 6a — agent context refresh (2.21.23).** Updating the pack changes the disk and reaches no
chat that is already open; no agent re-reads its instructions when files change.
`Refresh-AgentContext.cmd` → `pack/scripts/refresh-agent-context.ps1` syncs a project
(`sync-project-rules.ps1` + `sync-audit-system.ps1`, skipped when the target *is* the pack) and writes
`docs/AGENT_CONTEXT.json` (versions, `rulesRevision` over `pack/rules/*.mdc`, per-layer state,
`changedLayers`) plus `docs/AGENT_REFRESH.md` (what to re-read, plus a paste line). Both are
gitignored — they record this machine's absolute paths, so committing them would fight across
machines. `agent-defaults-always.mdc` gained a six-line trigger (**refresh pack context**), bootstrap
writes the stub, and `AI_INSTRUCTIONS.md.template` points non-Cursor agents at the same file. Behavior
step 27 covers it. It deliberately overlaps `Update-AgentRules.cmd`: that reports profile changes at
install time, this leaves a per-project file an agent can read tomorrow.

**Section 12 — layout hygiene (2.22.0).** Every machine check in Section B ended in `- delete`, so an
agent could delete `dist/`, close the section, and never ask whether the tree is comprehensible — and
`dist/` returns on the next build, so "fixed" was never true. Optional `layoutPolicy` in
`AUDIT.config.json` (**disabled by default**, `MyApp` placeholders) checks the folder glossary, an
in-repo duplicate of a release archive, one runtime-data dirname in two roles, ephemeral dirs, and
scripts that recreate a forbidden path. Findings are **Improve** in a new `machineImprovesBySection`
array; only build output actually committed to git is a Fix. `semanticRequireMachineImproveMention`
stops a section closing on "Nothing found." while Improve lines exist. The skill has a mandatory §B
layout pass; `AUDIT_SYSTEM.md` and `AGENT_WORKFLOW.md` carry the taxonomy. Behavior step 28 asserts
the findings appear, that **none** land in Fix, and that the semantic gate holds. The same block still
hardcoded `app\` in its remediation text, so flat projects were told to delete paths they do not have
— fixed.

**Shipped after this block was written:** Phase **6b** MCP tools (**WQ-301**, engine **2.22.21**, behavior step **35**) and Phase **D** session-start adapter (**WQ-308**, steps **38–39**). See `docs/MULTI_TOOL_GAP_PLAN.md` § Phase ID map.

**Still parked:** Phase **6c** multi-agent mailbox (**WQ-302**). Legacy manual paste doc **`AGENT_CHAT_SYNC.md`** was **removed** — use `Refresh-AgentContext.cmd` / `docs/AGENT_REFRESH.md` / `docs/AGENT_PASTE.txt`.

### Rule delivery, paste hygiene, host parity, transfer (2.22.1 – 2.22.4)

Four smaller bumps, each triggered by trying to use the thing rather than read it.

| Bump | Change | Why |
|------|--------|-----|
| **2.22.1** | **`sync-project-rules.ps1` enumerates `pack/rules/*.mdc`** instead of a hardcoded 9-name list; behavior step 5b runs that sync for real against a scratch project and asserts every rule arrives | The same defect already fixed in `doctor.ps1` was still here: `install.ps1` copies the whole rules folder, so a newly added rule reached *profiles* but silently never reached *projects*. Found while adding a rule, not while reviewing code |
| **2.22.2** | **Paste line hardened** — one ASCII line, minute-precision stamp, absolute paths, ends by asking the agent to reply with the versions it just read; written to `docs/AGENT_PASTE.txt` and copied to the clipboard (`-NoClipboard` for tests). Also **`sync-audit-system.ps1` runs doc version sync before the mirror** | Pasted update notices were arriving mangled or truncated, and a long multi-item notice could hang the receiving chat. The sync ordering bug meant every run left drift behind: it mirrored files, then rewrote two of the mirrored docs |
| **2.22.3** | **One BOM-free writer** (`Write-Utf8NoBom` + `Add-Utf8NoBomLine` in `pack-paths.ps1`, replacing five scattered copies); `#Requires -Version 5.1` on every pack script; host shell reported by `doctor.ps1` and `check-requirements.ps1`; **behavior step 29** proves both hosts write identical bytes and semantically identical JSON; **`-DualShell`** re-runs the whole suite on the other host | The maintainer's home machine runs PowerShell 7 while the floor is 5.1, and nothing tested that the two agree. Measured before deciding: 5.1 starts a child shell in ~130ms vs ~250ms for 7.6.5, and this workload is startup-bound, so **5.1 stays the host** — 7 is supported and used for cross-checks. Encoding is the one real divergence; `ConvertTo-Json` formatting differs per host, so generated JSON must never be hash-compared across them |
| **2.22.4** | **`export.ps1` drops the per-machine agent-context stamp** (`docs/AGENT_CONTEXT.json`, `AGENT_REFRESH.md`, `AGENT_PASTE.txt`); **`install.ps1` honours `AGENT_STARTER_PACK_INSTALL_ROOT`**; behavior step 26 runs a real redirected install | Found by taking "portable" literally: export, unzip elsewhere, run it as a receiving machine. The archive shipped this drive letter, this user profile, and a stale version stamp, so a receiving agent was pointed at paths that do not exist. The installer was the one script ignoring the install-root override, so it half-redirected — later steps reported the scratch path while the copy went to the real profile, which is also why no test could exercise a full install without writing the maintainer's profile |

### Fixes from breakage review

| Issue | Fix |
|-------|-----|
| Generic bootstrap called missing `apply_version.py` | `run_tests.generic.bat.template` for Generic stack |
| `VERSION_SYNC.json` copied to all stacks | Python-only in bootstrap |
| `sync_doc_versions.py` missing from manifest `packMirror` | Added to manifest |
| Dual `docVersionSync` + `VERSION_SYNC.json` active | Disabled `docVersionSync` in pack configs |
| Stale `AGENT_WORKFLOW.md` text | Updated sync trigger description |

---

## 6. Current state (pointer — do not duplicate WORK_QUEUE)

**Canonical live state:** `docs/WORK_QUEUE.md` + `pack/audit/manifest.json` + root `VERSION`.

| Artifact | Where to read |
|----------|----------------|
| Pack release | root `VERSION` (sync via `Sync-DocVersions.cmd`) |
| Audit engine | `pack/audit/manifest.json` `"version"` |
| Next maintainer task | `docs/WORK_QUEUE.md` Active **Next** |
| Rules vs verify inventory | `pack/docs/RULES_AND_VERIFY_MAP.md` |
| Installed profile | `%USERPROFILE%\.cursor\AgentStarterPack\` — run `install.ps1 -Scope User` after Desktop edits |

**Verification entry points** (from pack root):

```powershell
.\run_audit_tests.bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\pack\scripts\verify-audit-behavior.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\pack\scripts\verify-complete-picture.ps1 -ProjectRoot (Get-Location).Path
py -3 .\pack\scripts\sync_doc_versions.py (Get-Location).Path --verify
```

Historical session detail (2.22.4-era checks, transfer notes, pruning) lives in **`pack/docs/AUDIT_SYSTEM_CHANGELOG.md`** — do not treat old paragraphs below this section as current if they contradict WORK_QUEUE or the manifest.

**Pruning (still true):** `install.ps1 -Prune` removes files the pack no longer ships; user-added profile rules/skills are never candidates.

**Careful with the install:** pack self-audit may mirror into `%USERPROFILE%\.cursor\AgentStarterPack` via `autoFixDrift` — treat as pack output, not another repo.

**A project audit must never write to `%USERPROFILE%`.** Re-check after mirror/`autoFixDrift` changes.

Optional app-level checks (only when user names a bootstrapped project):

```powershell
.\pack\scripts\verify-agent-setup.ps1 -ReferenceProjectRoot "C:\Users\alice\Projects\MyApp"
```

### Git / uncommitted work

**Large local diff (WQ-413 hygiene batch, engine 2.22.43)** — not committed unless the user asks. Remote: `https://github.com/binary-100/AgentStarterPack.git` (WQ-006). Run `git status` before continuing.

**Maintainer commits and pushes from their own machine** unless the user explicitly asks the agent to commit here. Before push after doc/manifest bumps:

- Stage deletions (e.g. **`AGENT_CHAT_SYNC.md`** removed — do not restore).
- **Untrack generated files that are now ignored** if git still tracks them:

```powershell
git rm --cached pack/audit/behavior-fixture/docs/.audit_domain_expanded.json
git rm --cached pack/audit/behavior-fixture/docs/.audit_inventory.json
git ls-files -i -c --exclude-standard   # expect empty afterwards
```

**Removable drive (exFAT):** `git config --global --add safe.directory <pack path>` once per machine if git refuses the repo path.

### User preferences established

- **Smallest correct fix** — no over-engineering
- **No edits to other repos** from this workspace
- **No commits** unless the user explicitly asks
- **Doc sync = build pipeline**, not audit-connected
- **Multi-tool portability** matters — prefer `docs/` + CLI over Cursor-only paths for new features
- **Generic-only pack** — no product names, user-specific Desktop paths, or reference apps in pack source
- **Portable pack folder, machine-local install** — the pack is carried on a USB stick and must run from any drive letter; per-machine installs into `%USERPROFILE%\.cursor\` are expected and are *not* meant to be portable. Never hard-code the pack's path in scripts, rules, or docs, and never let a machine-local install write back into the pack folder
- **This machine maintains the pack, and now also has an install** — that started as "maintain only, no profile writes," and the user lifted it on 2026-08-27 specifically so the install paths could be verified (which is how the `mcp.json` data-loss bug was found). Still: run `install.ps1` only when asked, and say which `%USERPROFILE%\.cursor\` paths will change
- **Prefer executing a path over reading it** — the two most damaging defects in this workstream (`Merge-McpJson` wiping 13 MCP servers, the installer ignoring the install-root override) both survived multiple careful code reviews and died on the first real run

---

## 7. Agent context refresh (shipped) and what is still deferred

### Agent Context Refresh — **BUILT in 2.21.23, hardened in 2.22.2. Do not rebuild it.**

This section used to be a design proposal; it is kept as usage documentation because the feature now
exists. If you are looking for unbuilt work, skip to *Still deferred* below.

**Problem it solves:** `install.ps1` updates disk; **open agent chats do not hot-reload** rules or context (universal LLM limitation, not Cursor-only).

**As shipped (tool-neutral):**

| Piece | Location | Notes |
|-------|----------|-------|
| Revision stamp | **`docs/AGENT_CONTEXT.json`** | pack version, audit version, `rulesRevision` hash, `syncedAt`, per-layer state, `changedLayers` |
| Refresh brief | **`docs/AGENT_REFRESH.md`** | Generated: what changed, files to re-read, embedded paste line |
| One-line notice | **`docs/AGENT_PASTE.txt`** | Single ASCII line, also placed on the clipboard |
| CLI | **`refresh-agent-context.ps1`** + **`Refresh-AgentContext.cmd`** | optional install + `sync-project-rules` + `sync-audit-system`, then writes the artifacts above |
| Tool adapters | `AI_INSTRUCTIONS.md.template` points non-Cursor agents at the same file; `agent-defaults-always.mdc` carries the **refresh pack context** trigger | MCP: `check_pack_freshness`, `get_agent_refresh_brief` (**WQ-301**, step **35**) |

All three artifacts are **gitignored and excluded from `export.ps1`** — they record one machine's
absolute paths and the versions current when generated, so sharing them misleads the receiving machine
(that was the 2.22.4 export fix).

**User workflow:**

```powershell
.\Refresh-AgentContext.cmd "C:\path\to\project"
```

Getting it into an open chat, easiest first: type **refresh pack context** (Cursor), paste the line the
command already put on the clipboard, or copy the single line in `docs/AGENT_PASTE.txt`. Do not select
it from console output. **2.22.2** hardened this because pasted update notices were arriving mangled:
the line is one ASCII line with a minute-precision stamp and ends by asking the agent to reply with the
pack and audit engine versions, so an agent that did not actually read the files is visible immediately.

**Do not** put the canonical handoff only under `.cursor/` — that breaks portability.

### Still deferred

- **Phase 6c — multi-agent coordination mailbox (**WQ-302**)** — parked in `pack/docs/AGENT_COORDINATION_BACKLOG.md` until a platform change makes it worthwhile.

**Shipped (do not rebuild):** Phase **6b** MCP tools (**WQ-301**); Phase **D** session-start + hub repair (**WQ-308**). Phase ID map: `docs/MULTI_TOOL_GAP_PLAN.md`.
- **Import smoke beyond root `*.py`** — modules under `moduleSearchDirs` are inventoried but never imported.
- **`install.sh` parity** — never executed (no bash on the maintainer machine) and it does not mirror the PowerShell installer's project-scope skill exclusion.

*(Removed from this list: the duplicate `sync_doc_versions()` body, deleted in 2.21.19 — it is not in `audit_code_checks.py`; and installer pruning, shipped in 2.21.22.)*

---

## 8. Cursor-specific vs portable

| Portable (any agent) | Cursor-specific (adapters) |
|----------------------|----------------------------|
| `AGENTS.md`, `AI_INSTRUCTIONS.md` | `.cursor/rules/*.mdc` + `alwaysApply` |
| `docs/AUDIT.md`, `run_audit.cmd`, scripts | Skills in `%USERPROFILE%\.cursor\skills\` |
| `docs/VERSION_SYNC.json`, `apply_version.py` | `install.ps1` → `.cursor\rules\` |
| PowerShell/Python CLI scripts | Cursor MCP via `mcp.json` |
| Bootstrap per-tool entry files | `sync-project-rules.ps1` → `.cursor/rules/` |

**Editor neutrality was re-checked in 2.22.8 and one gap was closed.** The audit's stale-context finding
is tool-neutral and carries its own remediation, but the behaviour around it (offer the run, wait for
approval, read the brief) had been written into `agent-defaults-always.mdc` only — a `.mdc`, which nothing
but Cursor reads, while `AI_INSTRUCTIONS.md` is the pack's own universal entry. It now lives in
`AI_INSTRUCTIONS.md.template` and `AGENTS.md.template` too, and behavior step 30 asserts all three
carriers so a Cursor-only implementation cannot pass again.

**The remaining tie is the shell, not the editor.** See `WEEKEND_HANDOFF.md` § "Portability limit".

Full guide: **`docs/PORTABLE_SETUP.md`**, **`docs/MULTI_INSTANCE_GUIDE.md`**

---

## 9. Key file map

```
AgentStarterPack/
├── HANDOVER_NEXT_AGENT.md          ← YOU ARE HERE
├── AGENTS.md                       ← Agent entry for this repo
├── VERSION                         ← Pack canonical version (1.8.0)
├── Sync-DocVersions.cmd            ← Maintainer doc sync
├── Install-AgentStarterPack.cmd
├── install.ps1
├── Update-AgentRules.cmd           ← install; optional ProjectRoot arg syncs generic rules
├── Refresh-AgentContext.cmd        ← sync a project + write its agent context brief
├── Verify-AgentSetup.cmd
├── Bootstrap-Project.cmd
├── run_audit.cmd                   ← Pack self-audit
├── run_audit_tests.bat             ← Test command (behavior + system verify)
├── export.ps1                      ← Zip for transfer to another machine
├── scripts/                        ← Pack's own audit entry points
├── tests/                          ← test_pack_audit.py
├── docs/
│   ├── VERSION_SYNC.json           ← Pack maintainer doc sync config
│   ├── VERSION_SYNC.md             ← Pattern doc for Python apps
│   ├── PORTABLE_SETUP.md
│   └── AUDIT.config.json           ← Pack self-audit config
├── .cursor/rules/                  ← WORKSPACE ONLY (not installed globally)
│   ├── pack-only-edit-boundary.mdc
│   ├── agent-recommendation-discipline.mdc
│   ├── starter-pack-repo.mdc
│   └── audit.mdc                   ← Says "audit" here → docs/AUDIT.md protocol
└── pack/
    ├── audit/manifest.json         ← Audit engine version (2.22.43)
    ├── audit/behavior-fixture/     ← Generic app fixture for behavior tests
    ├── rules/                      ← Generic rules → install.ps1
    ├── scripts/                    ← Core tooling (pack-paths.ps1 = root resolution)
    ├── templates/                  ← Bootstrap + audit templates
    │   └── docs/
    │       ├── AUDIT.config.app.reference.json   ← Generic app audit config example
    │       └── AUDIT.app.reference.md
    └── docs/
        ├── START_HERE.md
        ├── PACK_MAINTENANCE.md
        ├── AGENT_WORKFLOW.md
        ├── AUDIT_SYSTEM.md
        └── AGENT_COORDINATION_BACKLOG.md  ← Parked
```

**Installed copy (after install):** `%USERPROFILE%\.cursor\AgentStarterPack\`

---

## 10. Commands cheat sheet

### Maintainer — after editing the pack

```powershell
cd <this pack folder>   # any drive or path

# Push to user profile (global rules + pack mirror)
.\install.ps1 -Scope User -NoPause

# After audit-system file edits
.\pack\scripts\sync-audit-system.ps1
.\pack\scripts\verify-audit-system.ps1 -ProjectRoot (Get-Location).Path

# After version/manifest bump — align doc cites
.\Sync-DocVersions.cmd

# Verify everything
.\run_audit_tests.bat
.\Verify-AgentSetup.cmd
.\pack\scripts\doctor.ps1 -ProjectRoot (Get-Location).Path
```

### Reference project (user runs when that repo is open — not from pack workspace unless user directs)

```powershell
# Install global rules (optional: sync into a project)
.\Update-AgentRules.cmd
.\Update-AgentRules.cmd "C:\Users\alice\Projects\MyApp"
.\Update-AgentRules.cmd "C:\Users\alice\Projects\MyApp" ".cursor\rules"

# Sync generic rules into project
.\pack\scripts\sync-project-rules.ps1 -ProjectRoot "C:\Users\alice\Projects\MyApp" -RulesRelativePath ".cursor\rules"

# Sync audit templates into project
.\pack\scripts\sync-audit-system.ps1 -ProjectRoot "C:\Users\alice\Projects\MyApp"

# Both syncs at once, plus a brief for chats already open on that project
.\Refresh-AgentContext.cmd "C:\Users\alice\Projects\MyApp"

# Push mature app audit files back into pack templates (optional maintainer flow)
.\pack\scripts\sync-audit-system.ps1 -PushFromProject -ProjectRoot "C:\Users\alice\Projects\MyApp"
```

### New project bootstrap

```powershell
.\pack\scripts\bootstrap-project.ps1 -ProjectRoot "D:\MyApp" -ProjectName "MyApp" -Stack Python -Targets All
```

### Pack self-audit

```bat
run_audit.cmd
```

Report **Fix** and **Improve** only. Follow `docs/AUDIT.md`.

---

## 11. Recommended next steps (pick up here)

**Canonical queue:** `C:\Users\binar\OneDrive\Desktop\AgentStarterPack\docs\WORK_QUEUE.md` — this section is a short pointer only.

| Priority | ID | Task |
|----------|-----|------|
| **Next** | WQ-011 | Flash drive / install on other PC |

**Recently completed (see Done log):** WQ-413 (hygiene batch); WQ-006 (git remote + CI); WQ-304; WQ-301; WQ-308.

**Parked:** WQ-302 (mailbox).

**CI:** `.github/workflows/pack-os-smoke.yml` — **Pack OS smoke** green on GitHub after WQ-006 push.

**Maintainer workflow:** edit the **Desktop/USB checkout** → `Install-AgentStarterPack.cmd` → agents read `%USERPROFILE%\.cursor\AgentStarterPack\`.

**Product repos:** refresh with `Refresh-AgentContext.cmd` after pack install; do not edit app repos from this workspace unless the user opens them.

---

## 12. Pitfalls for the next agent

1. **Do not edit external application repos** from this workspace — instruct the user or ask them to open that workspace.
2. **Do not run bootstrap/sync with external `-ProjectRoot`** unless the user explicitly names the target.
3. **Doc sync is not an audit step** — wire through build/`VERSION_SYNC.json`, not new audit Improve checks.
4. **Generic vs Python bootstrap** — Generic must not call `apply_version.py`.
5. **Rule layers** — workspace boundaries stay in `.cursor/rules/` here; generic guidance stays in `pack/rules/`.
6. **Commits** — only when the user explicitly requests.
7. **Open chats** — cannot assume rules refreshed; use handoff doc or proposed `AGENT_REFRESH.md` workflow.
8. **Full paths in chat** — when telling the user where files live, use absolute paths (see `full-paths-in-chat.mdc`).
9. **No product-specific content in pack** — examples use `MyApp`, `main.py`, behavior-fixture; never reintroduce user app names or paths into templates/docs/rules.
10. **Stale bytecode** — after renaming strings in Python scripts, delete `pack/scripts/__pycache__` if content searches hit `.pyc` only.
11. **Never hard-code the pack's location** — derive it (`$PSScriptRoot`, `pack-paths.ps1`) or take it as a parameter. The edit boundary is "the open workspace root," not a fixed path, and the drive letter changes between machines.
12. **PowerShell variable names are case-insensitive** — `$testsPassedAt` and `$script:TestsPassedAt` are the same variable. A "local" of the same name silently overwrites script state; that bug made the audit report a false `Semantic report stale` on its own documented workflow. Do not shadow script-scoped names, whatever the casing.
13. **Two roots, never conflated** — source pack (the USB pack folder, portable) vs installed pack (`%USERPROFILE%\.cursor\AgentStarterPack`, one per machine, not portable). "Not installed" is an integration state, not drift; do not chase it as a bug. Never add a code path that writes installed → pack folder without an explicit flag.
14. **Test-pass proof** — `audit_code_checks.py` owns it; `run_audit_core.ps1` asks Python first. Do not reintroduce a second fingerprint implementation in PowerShell, or finalize goes stale in nested layouts.
15. **Behavior is the pack's test suite, not a product check** — `run_audit_core.ps1` passes `-SkipBehavior` to `verify-audit-system.ps1` unless the repo being audited *is* the pack supplying the engine (`RepoRoot` equals the resolved pack root), and proves the engine there with `audit_code_checks.py --self-test`. Never make a product audit run `verify-audit-behavior.ps1`: step 23 bootstraps probe projects inside the pack folder and would re-enter itself.
16. **Executed code is ASCII and BOM-free**, enforced by behavior step 24 (`.ps1`, `.py`, `.cmd`, `.bat`, executable templates). Markdown keeps its typography. This is not style: PowerShell 5.1 reads BOM-less UTF-8 as ANSI, and redirected console output is cp1252, which has crashed both this preflight and generated projects' tests.
17. **Never let a gate pass on nothing** — required sections come from `## Checklist sections` in `docs/AUDIT.md` plus the domain map, `sectionTests`, and hints. An empty set is a Fix. Generated projects ship six real sections; do not "simplify" the template by deleting them.
18. **`Set-Content -Encoding UTF8` writes a BOM on PowerShell 5.1** — never use it for a tracked file. The behavior suite restored fixture files that way and re-added a BOM to committed code on every run, under the check that exists to catch it. Use `Set-TextNoBom` / `[System.IO.File]::WriteAllText(..., UTF8Encoding($false))`.
19. **Anything `install.ps1` copies must be in `pack/audit/manifest.json`** — `Copy-Tree` delivers whole folders on a fresh install, so a file missing from `packMirror`/`packToUser` installs once and then goes stale forever, unreported. Behavior step 5b enforces this for `pack/rules`; apply the same thought to any new installed folder.
20. **Remediation text must name paths the project has** — flat is bootstrap's default layout. Derive an `app\` prefix from `AppRoot -ne RepoRoot`; never hardcode it.
21. **A scope setting that is read but not scanned is a blind spot** — `moduleSearchDirs` resolved modules for years without being inventoried, so the pack's own audit attested to 38 of 3,053 Python lines. When adding a config key that names *where code lives*, wire it into the inventory and orphan scan too, or the gate silently shrinks.
22. **Repo root is decided in three places and must match** — `run_audit.ps1.template`, `resolve_repo_root()` in `audit_code_checks.py`, and `resolve_repo_root()` in `doc_version_sync.py`. The third one **writes**: it resolves doc-sync targets, so a wrong answer rewrote files in the parent folder of every flat project beside a `README.md`. All three apply the same rule (app root unless a nested `app` folder with no local `.git` sits under a git parent). Fixing one and not the other split the audit in half: machine checks on the project, git/version/evidence lookups on the parent. Do **not** "unify" this by passing the wrapper's `-RepoRoot` into Python — the behavior fixture's wrapper declares an outer root, and that would tie the fixture's test-pass proof to the pack's git HEAD and silently kill the staleness tests at `verify-audit-behavior.ps1` steps 8-10. Behavior step 23 asserts agreement instead.

---

## 13. Related documentation index

| Doc | When to read |
|-----|--------------|
| **`HANDOVER_NEXT_AGENT.md`** | Session handoff (this file) |
| **`AGENTS.md`** | Working in this repo |
| **`pack/docs/START_HERE.md`** | Onboarding, install, pitfalls |
| **`pack/docs/PACK_MAINTENANCE.md`** | Pack ↔ project sync workflows |
| **`pack/docs/AGENT_WORKFLOW.md`** | Audit workflow, loop-back |
| **`pack/docs/AUDIT_SYSTEM.md`** | Audit architecture |
| **`pack/docs/AUDIT_SYSTEM_CHANGELOG.md`** | Decisions already made — do not re-debate |
| **`docs/PORTABLE_SETUP.md`** | Multi-tool bootstrap |
| **`docs/VERSION_SYNC.md`** | Python app version sync pattern |
| **`pack/docs/AGENT_COORDINATION_BACKLOG.md`** | Parked multi-agent work |

---

*End of handover. Point the next agent at this file: **`HANDOVER_NEXT_AGENT.md`** in the Agent Starter Pack repo root.*
