# Handoff — Agent Starter Pack (read this first)

**Purpose:** Onboard an AI agent on **another machine or in a new chat** to continue work on the Agent Starter Pack without re-discovering context from scratch.

**Canonical status:** `docs/WORK_QUEUE.md` — **Next: WQ-011** (flash drive / install on other PC).  
**Human install (new PC / USB stick):** `INSTALL.txt` → `INSTALL.md`.  
**Pack version:** root `VERSION` (**1.8.0**)  
**Audit engine version:** `pack/audit/manifest.json` (**2.22.53**)  
*Version cites in scanned docs are maintained by `Sync-DocVersions.cmd` — use the parenthesised form in those files.*  
**Repo location:** wherever the pack folder lives (Desktop checkout, USB stick, or `%USERPROFILE%\.cursor\AgentStarterPack` after install). Never hard-code a drive letter in scripts or docs.

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

## 2. Standing decisions (carry these forward)

These came from the user across many sessions. They are settled — do not re-litigate them per chat.

- **Smallest correct fix** — no invented alternatives, no over-engineering.
- **Edit only this repo.** Other repos named in docs are references, not targets. Do not run bootstrap or sync with an external `-ProjectRoot` unless the user names that target in this session.
- **No commits from this machine** — publishing happens on the user's primary system. See § Git below.
- **Doc sync is a build step**, not an audit check: `docs/VERSION_SYNC.json`, never a new audit Improve.
- **Generic-only pack** — no product names or user-specific paths in `pack/rules`, templates, or maintainer docs. Examples use `MyApp`, `main.py`, and `pack/audit/behavior-fixture/`.
- **Portable pack folder, machine-local install.** The folder travels (USB, any drive letter) and must run from anywhere; `%USERPROFILE%\.cursor\` installs are per-machine and deliberately *not* portable. Never hard-code either root, and never let an install write back into the pack folder.
- **Multi-tool portability matters** — prefer `docs/` plus CLI over Cursor-only delivery for anything new.
- **This machine maintains the pack and also has an install.** It was maintain-only until 2026-08-27, when the user lifted that specifically so the install paths could be verified — which is how the `mcp.json` data-loss bug surfaced. Still run `install.ps1` only when asked, and say which `%USERPROFILE%\.cursor\` paths will change.
- **Prefer executing a path over reading it.** The two most damaging defects in this workstream — `Merge-McpJson` wiping 13 configured MCP servers, and the installer ignoring the install-root override — both survived several careful code reviews and died on the first real run.

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

## 5. What shipped, and the lessons that outlived it

**The bump-by-bump history is not repeated here.** `pack/docs/AUDIT_SYSTEM_CHANGELOG.md` carries every
engine version with its reasoning, and `docs/WORK_QUEUE.md` § Done log carries every WQ id with its
evidence. Both are maintained; this file used to duplicate them at ~400 lines and drifted from them.

What is worth carrying is the handful of findings that generalise past the bump that produced them.

- **Testing the layer below the one users touch proves nothing about the one they touch.** Forty-seven behavior steps called each `.ps1` with `-NoPause` while four root `.cmd` launchers sat on bare `pause` statements — the layer a human double-clicks and an agent runs.
- **A check that a file exists is not a check that it is right.** The cited-paths check proved a template was present; only bootstrapping a project showed it produced a README titled `{{PROJECT_NAME}}`.
- **When two names collapse into one, check what else the surviving string matches.** Renaming this file, a bare `HANDOFF` match would have selected a work slice out of `docs/handoffs/` instead of the session doc.
- **Assert on the artifact, not the plumbing.** The first fix for the double-encoded agent manifest pinned `PYTHONIOENCODING` and the console encoding and changed nothing, because the JSON was already ASCII-escaped. The test that works reads an em dash out the far end.
- **A checker without exclusions gets muted within a week.** The cited-paths discovery pass produced 52 candidates and exactly one defect; the other 51 were project-relative paths, a deliberately forbidden file, and regex artefacts.
- **Green here is not green anywhere.** Several tests were grading the machine rather than the pack — they compared against whatever was installed in the profile. Tests that touch install state must build their own scratch install and honour `AGENT_STARTER_PACK_INSTALL_ROOT`.
- **A garbled console is not a corrupted file.** Terminal output in this repo displays em dashes and section signs as mojibake under the default codepage. Check bytes before reaching for a repair script; this repo has a real double-encoding history, which makes the false alarm convincing.
- **The mirror runs one way, source → installed.** A stale install must never overwrite the pack folder or resurrect files deleted from it. `-PullFromInstalled` is the explicit opt-out, and cross-filesystem mtimes (exFAT local time vs NTFS UTC) make "newest wins" unsafe anyway.

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

### Where the recent work is written down

Engine **2.22.45 → 2.22.52** covered hermetic tests, an engine split under its own size ceiling, rules
that had been shipping this repo's private state, three mechanical guards for rule and generator
correctness, and the handoff-vocabulary consolidation. Each has a changelog entry with the reasoning
and a Done-log row with the evidence; read those rather than a summary of a summary.

Two operational notes from that stretch that a reader here would otherwise trip on:

- **This file was called `HANDOVER_NEXT_AGENT.md` until 2.22.52.** One word — handoff — now covers both scales: a work slice in `docs/handoffs/active/`, and one session to the next (this file). Behavior step 49 keeps the retired synonym out; `pack/docs/AGENT_HANDOFFS.md` § Terminology holds the decision.
- **Four root documents were deleted in 2.22.53** — two implementer specs, the implementer notes, and a superseded transfer stub — after the work they described shipped. The changelog and the Done log are the record; do not recreate them.

**Certified:** `finalize_audit.cmd` exit 0 on 2026-08-31 at engine **2.22.53** — **Fix: nothing found.
Improve: nothing found.** 19/19 unit tests, 49 behavior steps, sync clean.

### Git / uncommitted work

**This machine does not publish.** Commits and anything reaching GitHub happen from the user's **primary system**; work here is handed over, not pushed. Enforced by `.cursor/rules/no-publish-from-this-machine.mdc` (workspace-only, and listed in `maintainerOnlyPaths` so it never ships). Do not offer a commit as a next step, and do not read an uncommitted tree as unfinished — a clean audit and a green suite are the finish line here.

**Large local diff (WQ-413 hygiene batch onward, engine now 2.22.52)** — carried, not committed. **One rename in that diff:** git sees `HANDOVER_NEXT_AGENT.md` as a deletion and `HANDOFF_NEXT_AGENT.md` as an addition, so the deletion must be staged (`git add -A`) or the old file returns on the primary system alongside the new one — the exact parallel-doc state this change removed. Remote for the primary system: `https://github.com/binary-100/AgentStarterPack.git` (WQ-006). Run `git status` before continuing.

**Maintainer commits and pushes from their own machine** unless the user explicitly asks the agent to commit here. Before push after doc/manifest bumps:

- Stage deletions (e.g. **`AGENT_CHAT_SYNC.md`** removed — do not restore).
- **Untrack generated files that are now ignored** if git still tracks them:

```powershell
git rm --cached pack/audit/behavior-fixture/docs/.audit_domain_expanded.json
git rm --cached pack/audit/behavior-fixture/docs/.audit_inventory.json
git ls-files -i -c --exclude-standard   # expect empty afterwards
```

**Removable drive (exFAT):** `git config --global --add safe.directory <pack path>` once per machine if git refuses the repo path.

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

**The remaining tie is the shell, not the editor.** See **`docs/OS_PORTABILITY_PLAN.md`** and **`docs/PORTABLE_SETUP.md`** § Platform scope.

Full guide: **`docs/PORTABLE_SETUP.md`**, **`docs/MULTI_INSTANCE_GUIDE.md`**

---

## 9. Key file map

```
AgentStarterPack/
├── HANDOFF_NEXT_AGENT.md          ← YOU ARE HERE
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
│   ├── WORK_QUEUE.md               ← Canonical task radar
│   ├── handoffs/active/            ← Work slices handed to another agent or machine
│   ├── handoff_archive/            ← Completed slices (archive-completed-handoff.ps1 -Apply)
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
    ├── audit/manifest.json         ← Audit engine version (2.22.53)
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

**Canonical queue:** `docs/WORK_QUEUE.md` in this pack folder — this section is a short pointer only. (It named one machine's Desktop path until 2.22.45, which is exactly what the rest of this document tells you not to do.)

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
| **`HANDOFF_NEXT_AGENT.md`** | Session handoff (this file) |
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

*End of handoff. Point the next agent at this file: **`HANDOFF_NEXT_AGENT.md`** in the Agent Starter Pack repo root.*
