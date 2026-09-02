# Work queue — Agent Starter Pack

**Canonical radar, and the only status claim.** Items are **never deleted** when priorities shift — they
move to **Done**, **Parked**, or stay in **Active** / **Inbox**.

**There is no separate session document.** `HANDOFF_NEXT_AGENT.md` was retired in 2.22.65: a second
place to state what is next produced contradictions three times, and every mechanical check that
existed to reconcile the two is now unnecessary. **Continuing from a prior session? Read this file** —
the Active queue is what is next, the Done log carries per-item evidence, and the reasoning behind each
release is in `pack/docs/AUDIT_SYSTEM_CHANGELOG.md`. Work handed to another machine or agent goes in a
slice under `docs/handoffs/active/` (`pack/docs/AGENT_HANDOFFS.md`).

| Field | Value |
|-------|--------|
| **Next active ID** | **WQ-415** |
| **Last updated** | 2026-09-02 |
| **Pack version** | 1.8.0 |
| **Audit engine** | 2.22.65 |

---

## How to use (humans and agents)

1. **One “next”** — exactly one row in Active has status **Next**; everything else is **Queued**, **In progress**, **Open**, **Held**, **Blocked**, or **Parked**.
2. **Order can change** — reprioritize Active rows when dependencies or findings require it; reconcile every `WQ-xxx` before and after (nothing deleted — see `generic-work-queue-discipline.mdc`).
3. **New findings** — add to **Inbox** first; triage into Active / Parked / Done in the same session when possible.
4. **Replacing a list** — update this file; do not drop IDs. Mark old rows **Superseded by WQ-xxx** in Notes if merged.
5. **Audit run Fix/Improve** — ephemeral per `run_audit.cmd`; recurring engineering debt from reviews lives in **Engineering backlog** below.
6. **Product features** — not here; bootstrapped apps use `docs/ROADMAP.md`. This queue is **maintainer / pack / agent-process** work.

Rule: `generic-work-queue-discipline.mdc` (installed globally).

---

## Lessons that outlived their release

Absorbed from the retired session doc (2.22.65). The bump-by-bump history is in
`pack/docs/AUDIT_SYSTEM_CHANGELOG.md`; each Done row below carries its own evidence. What is worth
carrying forward is the handful of findings that generalise past the bump that produced them.

- **Testing the layer below the one users touch proves nothing about the one they touch.** Forty-seven behavior steps called each `.ps1` with `-NoPause` while four root `.cmd` launchers sat on bare `pause` statements — the layer a human double-clicks and an agent runs.
- **A check that a file exists is not a check that it is right.** The cited-paths check proved a template was present; only bootstrapping a project showed it produced a README titled `{{PROJECT_NAME}}`.
- **A guard narrower than the thing it guards reports success on a broken artifact.** `verify-agent-setup` checked 5 of 12 profile rules and 10 of 174 pack files; the export's completeness guard passed an archive missing seven launchers. None was *wrong* — each was too narrow.
- **A read that never returns raises nothing.** The Cursor session hook promised to fail open on any error and drained stdin with an unbounded `ReadToEnd()`. Cursor closes that handle, so it passed for four releases; bash leaves it open, and the audit hung sixteen minutes. `try/catch` is not a timeout.
- **Diagnose a stall from CPU time, not elapsed time.** What proved that hang was blocked rather than slow: `pwsh` holding 3 seconds of CPU after 16 minutes, with idle children.
- **Plant the defect you mean, and prove it parses.** A negative test whose planted defect was a *syntax* error made the guard look proven when it was not. A planted defect is a test input — verify it is the input you intended.
- **Prefer executing a path over reading it.** Steps 40–43 grepped the `.sh` wrappers for marker text for four releases; the first real `bash` run found a hang in seconds.
- **Assert on the artifact, not the plumbing.** The first fix for the double-encoded agent manifest pinned `PYTHONIOENCODING` and changed nothing, because the JSON was already ASCII-escaped. The test that works reads an em dash out the far end.
- **A checker without exclusions gets muted within a week.** The cited-paths discovery pass produced 52 candidates and exactly one defect; the other 51 were project-relative paths, a deliberately forbidden file, and regex artefacts.
- **Green here is not green anywhere.** Several tests were grading the machine rather than the pack. Tests that touch install state must build their own scratch install and honour `AGENT_STARTER_PACK_INSTALL_ROOT`.
- **A garbled console is not a corrupted file.** Terminal output here shows em dashes as mojibake under the default codepage. Check bytes before reaching for a repair script.
- **The mirror runs one way, source → installed.** A stale install must never overwrite the pack folder or resurrect deleted files; cross-filesystem mtimes (exFAT local vs NTFS UTC) make "newest wins" unsafe.
- **A deferred item that shipped is worse than no list**, and a gap documented in three places but tracked in none still gets forgotten. Both directions are why this file exists.
- **A tripwire calibrated to the wrong value is worse than none** — it fires on the healthy state and stays quiet on the broken one.
- **This checkout does not publish.** Commits and pushes happen on the primary system; see `.cursor/rules/no-publish-from-this-machine.mdc`. A clean audit and a green suite are the finish line here, and an uncommitted tree is the normal state.

---

## Active queue (ordered)

Work **top to bottom**. Do not skip ahead without user approval or marking the row **Blocked** with reason.

| ID | Task | Status | Notes |
|----|------|--------|-------|
| WQ-415 | **Product-truth verify — limitations/capability prose vs code** | **Next** | Promoted from Engineering backlog 2026-09-01; see WQ-414 archive § Open engineering |
| WQ-416 | Extend complete-picture or verify-product-truth-paths.ps1 | Queued | After WQ-415 or parallel if scoped |
| WQ-417 | Wire Step 3 / 5b into Update-AgentStack | Queued | |

---

## Inbox (triage required)

| ID | Task | Source | Triage |
|----|------|--------|--------|
| *(empty)* | | | |

---

## Engineering backlog (from audit depth review — not ephemeral audit)

| ID | Task | Priority hint |
|----|------|----------------|
| WQ-418 | **repair-handoff-status.ps1** (optional auto-repair) | Low |
| WQ-419 | **Audit skill: product-truth contradictions → Fix not Improve** | Medium |
| WQ-420 | **DOC_MAP.md.template § product-truth owners** | Medium — bootstrap gap |
| WQ-421 | **Project-scoped rule path verify (step 47 in app repo)** | Low |
| WQ-422 | **Limitation doc date headers / VERSION_SYNC preset** | Low |
| WQ-425 | **`install.ps1` should skip `machineLocalPaths`** — installing from a transferred folder can copy a foreign context stamp into the profile | Low — step 50 and `sanitize-machine-state.ps1` cover the transfer itself |
| WQ-431 | **Session doc header status is unchecked** — `verify-complete-picture.ps1` reads `## 11.` only. Hand-fixed twice: the header read "Active queue empty" against WQ-415 Next (2.22.55), and contradicted §11 again for WQ-426 (2026-09-01). Either read the header line or drop it and keep §11 as the single status claim | Medium — a documented gap with two occurrences |
| WQ-432 | **WORK_COMPLETION step order when behavior changed** — audit is step 6, *after* step 5 WQ Done, while Step 3d says product-truth drift blocks the close. Review whether the audit should run before WQ Done in that case | Medium — recommended twice (`HANDOFF_WQ414` § Recommended next work #2, session handoff §14) with no id until now |
| WQ-433 | **Cited paths under `docs/`, `scripts/`, `tests/` are unchecked here** — step 47 resolves `pack/`-rooted cites only; a design-reference doc cited but absent survived until a manual sweep (2.22.55). Needs per-path ownership to avoid the noise that muted the first cited-path pass | Low — most such cites are project-relative by design |
| WQ-437 | **Nothing protects historical version cites from a bump** — a blanket replace of the engine version rewrote the WQ-430 Done row (2.22.62) and then the WQ-434 row plus three handoff cites (2.22.65), each time claiming work shipped in a release that postdates it. Checkable: every `Engine 2.22.N` in the Done log must match a changelog section that names that WQ id | Medium — **three hand-fixes in one day**, and the repo's own rule is that a repeated correction becomes a check |
| WQ-436 | **The wrappers have never run on macOS** — step 54 covers Windows-with-bash, `pack-os-smoke.yml` covers `ubuntu-latest`; no macOS runner exists. `pack-paths.ps1` treats all non-Windows alike (`pwsh` only), so the risk is Homebrew `pwsh` discovery and BSD-vs-GNU shell tooling, not the delegation logic | Low — a `macos-latest` job is cheap; nothing suggests a defect, only that the claim is untested |
| WQ-435 | **Generated Cursor hooks have no refresh path** — `bootstrap-project.ps1 -Force` is the only writer; `repair-agent-docs.ps1` covers docs but not `.cursor/hooks/`. Any project bootstrapped before 2.22.63 keeps the hook that hangs on an open stdin | Medium — surfaced by WQ-434; the pack cannot reach those projects, so it needs a repair command the user runs there |

Detail: the WQ-414 archive (consolidated into the drive-root transfer document 2026-09-01; its open items are the WQ-415-422 rows above) § Open engineering. **WQ-415–417** promoted to Active queue 2026-09-01.

**WQ-431–434 were filed 2026-09-01 from a read of the handoff set.** All four already existed in prose —
in the handoff design reference (since consolidated), `pack/docs/RULES_AND_VERIFY_MAP.md` known gaps, the
WQ-414 archive's recommendations, and §7 of the session handoff — but none had an id, so none was on
this radar. **A gap documented in three places and tracked in none still gets forgotten**, which is what
this file exists to prevent (`generic-work-queue-discipline.mdc`). The same read found two entries in §7
deferring work that had already shipped; those were deleted rather than filed.

---

## Parked / deferred (explicit — still on radar)

| ID | Task | Re-open when |
|----|------|----------------|
| WQ-302 | **Phase 6c** — multi-agent mailbox (`pack/docs/AGENT_COORDINATION_BACKLOG.md`) | Platform change / user asks |

---

## Done log

| ID | Task | Completed | Evidence |
|----|------|-----------|----------|
| WQ-426 | **Land the machine-local fix on the primary system and publish it** | 2026-09-02 | Commit **`e6056cb`** pushed to `origin/master`; `install.ps1 -Scope User -NoPause -Prune` pruned 6 stale profile files; engine **2.22.65** / pack **1.8.0** |
| WQ-434 | **Run the `.sh` wrappers instead of reading them — and the defect that found** | 2026-09-01 | Promoted from backlog and closed the same session. Steps 40–43 asserted each wrapper's *text* delegated through `pwsh-wrap.sh`; `pack-os-smoke.yml` triggered on `*.sh` and then ran the `.ps1` files directly, so **nothing had ever run `bash ./install.sh`** in four releases. The first real run of `./run_audit.sh` **hung for 16 minutes** — `pwsh` had used 3s of CPU, its three children were idle, so blocked rather than slow. Cause: `pack/templates/cursor/hooks/session-freshness.ps1` drained stdin with an unbounded `[Console]::In.ReadToEnd()`. Cursor closes the handle after its payload so it returned instantly there; bash holds the pipe open, and the read waits for an EOF that never comes. **The script's own fail-open promise could not save it — a read that never returns throws nothing.** Fixed with a bounded drain (`IsInputRedirected` + a 250 ms task wait), proven both ways: old code killed at 20s, fixed returns in 440 ms with valid hook JSON. **Step 54** runs four wrappers under bash (`install.sh` writes the profile, `run_audit.sh` would re-enter the suite — CI covers both) and states a skip when bash is absent; a new arm in step 39 starts the hook with stdin held open. CI now executes the wrappers on the `ubuntu-latest` runner, including `install.sh User` and `run_audit.sh` under a 12-minute timeout. Both guards negative-tested; the first attempt planted a *syntax* error rather than the real defect and had to be redone with a parse check on the planted defect. Engine 2.22.63 |
| WQ-430 | **Find the rest of the duplicate-list class** | 2026-09-01 | Three releases in a row fixed one shape of bug — a script holding its own copy of a list the manifest declares. Scanned every literal file-name array in the pack's scripts and found two more, both green, both narrower than what they guard: `verify-agent-setup.ps1` checked **5 of 12** profile rules and **10 of 174** pack files; `verify-portable-bootstrap.ps1` checked **5 of 9** required project files, so a project missing four audit entry points read as portable and failed on the recipient's machine instead. Now read `packToUser` (15), `packMirror` (174) and `projectRequired.flatLayout` (13 with the portable extras). `run_audit_core.ps1`'s stale literal fallback removed — it matched the manifest and was unreachable while any manifest resolves, which is why nobody noticed; an unreadable manifest is now a reported gap. `verify-complete-picture.ps1`'s 8 docs stay curated, with the reason written down. **Step 53** asserts the coupling survives. Negative-tested three ways. Engine 2.22.61 |
| WQ-429 | **Prove portability cold: run an export as a first-time recipient** | 2026-09-01 | Everything since 2.22.56 had been verified on this checkout - git history, synced install, populated state dir. Unzipped an export into a scratch folder and ran it cold. Identity result held (180 files, no user name, no reference to the sending checkout), but the copy **failed its own suite with seven `missing at pack root`** errors: `Update-AgentStack.cmd`, `Bootstrap-Portable-Project.cmd`, `Register-Tool-Adapters.cmd`, four `.sh` launchers. Cause: `export.ps1` kept a hand-written `$items` list beside `packMirror` (third time this shape has surfaced in four releases), and its completeness guard checked `flatLayout` plus three named files - narrower than what it protects, so it passed a broken archive. `$items` now unions root-level `packMirror`; the guard checks every entry; **step 52** runs the real export, unzips it and asserts both halves. Negative-tested by hiding a launcher (export exits 1). Cold copy then green: 19/19 unit, behavior 0 fail. Engine 2.22.60 |
| WQ-428 | **The portable folder generates no machine state at all** | 2026-09-01 | Three releases policed this file class while the files kept being written. Cause: the pack audits and refreshes **itself** through the bootstrapped-app code path, which writes a per-machine brief into `docs/` - right for an app pinned to one location, wrong for a folder meant to travel. `Get-AgentStateRoot` (PS) and `agent_state_root()` (Py) now send the four context artifacts to `%LOCALAPPDATA%\AgentStarterPack\state\<leaf>-<hash>` (POSIX `$XDG_STATE_HOME`) for a pack root, keyed by checkout path so a stick and a clone stay separate; `ensure-work-completion.ps1` generates no overlay for a pack root. `AGENT_STARTER_PACK_STATE_ROOT` keeps probes out of the real profile. **Step 50** now fails if any entry merely *exists* here or if the state root resolves inside the checkout; **step 51** compares the two resolvers, because a silent disagreement would read as *missing AGENT_CONTEXT.json*. Consumers (`update-agent-stack`, `verify-agent-setup`, the session opener) resolve instead of assuming `docs\`. Projects unaffected. Engine 2.22.59 |
| WQ-427 | **Where the checkout lives is machine state too** | 2026-09-01 | Step 50 allowed any drive-letter path that named no real person, so a tracked doc could record the sending machine's own pack folder - wrong on every other machine, and unlike a generated stamp it survives a **clone or download**, not just a folder copy. The pack's own rule said never hard-code a drive letter; nothing enforced it. New arm fails on this checkout's absolute path in any travelling file (native, JSON-escaped and forward-slash forms); machine-local files stay exempt and `alice`-style illustrations are untouched. Found two real cases in archived handoffs plus three historical evidence rows. Handoff openers may now use a placeholder root (`<pack folder>\...`), since a slice written for another machine cannot name a path that exists there - `verify-agent-handoffs.ps1` accepts absolute or placeholder, bare relative still rejected. **Method note:** the arm's first run reported clean only because it was dot-sourced instead of run with `-File`, the same shape as the `.tmp` exclusion bug in 2.22.56. Certified: `finalize_audit.cmd` exit 0, Fix and Improve empty. Engine 2.22.58 |
| WQ-424 | **No machine identity travels with the pack** | 2026-09-01 | Three files carried another machine's profile path and two were **tracked**: the generated `docs/WORK_COMPLETION.md` (7 paths, also in `packMirror`), `docs/AGENT_SESSION_START.md` (5 paths, in no exclusion list), and a stale foreign `install-manifest.json` (tracked despite being gitignored). Cause was four disagreeing lists, not robocopy — `machineLocalPaths` in the manifest is now the single one, read by `export.ps1` and the guard. Added `sanitize-machine-state.ps1` for folder-copy transfers (preview by default) and **step 50**, which fails on a real user path in any travelling file, on gitignore/mirror contradictions, and on a preview that deletes. Freshness now reports *written on another machine* instead of *missing*, and no longer lets a matching version reset `stale`. **2.22.57** added the arm that closes the round trip: machine-local files are exempt from the identity scan, so a tracked copy returning from another machine would have passed - the index arm fails when any `machineLocalPaths` entry is tracked, and reads `ls-files` output rather than its exit code so a git failure on removable media cannot read as clean. Engine 2.22.56-2.22.57 |
| WQ-423 | Reconcile the incoming 2.22.54 state on the transfer machine | 2026-09-01 | Deep scan of the returned folder against its own handoffs. Suite green (19/19 unit, behavior **0 fail**), `verify-complete-picture` exit 0; install drift was the only suite failure and was expected (profile at 2.22.53 vs source 2.22.54) — synced. Three doc defects fixed: the handoff design reference existed only at the transfer-drive root though two documents cited it in-repo (then moved into `docs/` and `maintainerOnlyPaths`), the session doc header said "Active queue empty" against **WQ-415** Next, and the reference misstated `docs/WORK_QUEUE.md` as not installed. `docs/AGENT_CONTEXT.json` arrived describing the other machine's roots — re-stamped here. **Note:** 2.22.54 was archived without a `finalize_audit.cmd` run, so this state is verified by the suite but not certified. Engine 2.22.55 |
| WQ-414 | **Product-truth propagation (WORK_COMPLETION Step 3 + verify 2.22.54)** | 2026-09-01 | Rules + WORK_COMPLETION §3 + `verify-complete-picture` ROADMAP check + behavior step 37 probe; handoff for WQ-414 (archived, then consolidated 2026-09-01); arrived by robocopy onto the transfer drive |
| WQ-011 | Flash drive / install on primary PC | 2026-08-31 | D: → Desktop robocopy `/MIR` (`.git` preserved); engine **2.22.53**; 19/19 unit + 49 behavior **0 fail**; `install.ps1 -Scope User`; `refresh-agent-context.ps1`; commit **`83f750e`** pushed; **Pack OS smoke** run **33465257061** success; backup `AgentStarterPack_backup_20260831` |
| WQ-214 | Root cleanup against the settled definitions | 2026-08-31 | Four finished root docs deleted (two specs, implementer notes, a superseded stub) with the checks that policed them; `HANDOFF_NEXT_AGENT.md` trimmed 788 → ~470 lines, section numbers preserved for the `## 11.` reader. Found two defects while doing it: `install.ps1` `SkipRelPaths` ignored folder entries, so `docs/handoffs/` would have shipped every work slice to every profile (**step 26** now asserts folder exclusion and its prefix boundary), and this repo's own handoffs README still read `{{PROJECT_NAME}}`. `no-publish-from-this-machine.mdc` gitignored — it is false on the machine that publishes. Engine 2.22.53 |
| WQ-213 | One word for one concept: handoff | 2026-08-31 | Two synonyms had been used as if they meant different things — 519 occurrences, 56 files. `HANDOVER_NEXT_AGENT.md` renamed to `HANDOFF_NEXT_AGENT.md` and every reference updated (`manifest.json`, `VERSION_SYNC.json` ×2, `export.ps1`, `AGENTS.md`, freshness `requiredReads`). Two matches narrowed by hand so the rename could not misfire: `verify-complete-picture.ps1` and step 46's token table both had to become `HANDOFF_NEXT_AGENT`, since bare `HANDOFF` also matches the legitimate `docs/handoffs/` convention. **Step 49** guards the vocabulary; glossary in `pack/docs/AGENT_HANDOFFS.md`. Engine 2.22.52 |
| WQ-212 | Generator sweep — run every generator and read its output | 2026-08-31 | Found 12 bare `pause` calls in 4 root launchers, violating the pack's own build-hygiene rule; the suite missed them because it always calls the `.ps1` with `-NoPause`. All gated behind `BUILD_NOPAUSE`, **step 48** guards it, verified both paths. Bootstrap clean across 6 stack/target combos: manifest matches disk, no placeholders/BOM/mojibake. Engine 2.22.51 |
| WQ-211 | Generated projects carry no unsubstituted placeholders | 2026-08-31 | `ensure-work-completion.ps1` plain-copied the handoffs README, so it landed with `{{PROJECT_NAME}}` in the title; now substitutes and writes BOM-free like the WORK_COMPLETION path beside it. **Step 23** fails on `{{[A-Z_]+}}` in any generated file. Verified by bootstrap: title renders `# Handoffs - ProbeApp`. Engine 2.22.50 |
| WQ-210 | Cited pack files must exist (rule advice, not just wording) | 2026-08-31 | Behavior **step 47**; found `ensure-work-completion.ps1` copying `pack/templates/docs/handoffs/README.md.template`, which was never created — both handoff templates written and mirrored. Proven to fire on a renamed script and to ignore project-relative paths, deliberately-forbidden files and globs. Engine 2.22.49 |
| WQ-209 | Mechanical check that shipped rules stay generic | 2026-08-31 | Behavior **step 46**; caught 11 further leaks the reading pass missed (`§11` refs, `HANDOFF_NEXT_AGENT.md` as a universal instruction), all reworded; proven to fail on a planted leak and to honour maintainer-scoped lines. Engine 2.22.48 |
| WQ-207 | Terminal hygiene split by job across its three surfaces | 2026-08-31 | `generic-terminal-and-build-hygiene.mdc` rewritten as build hygiene and states what it does **not** cover; diagnosis stays in skill `agent-terminal-hygiene`, the before/after sequence in `agent-defaults-always`. Note: the premise "cuts the always-on budget" was wrong — the duplication lived in an on-demand rule, so this buys one owner per concern, not context |
| WQ-208 | Audit trigger vocabulary aligned | 2026-08-31 | One list in `audit-protocol.mdc` (canonical), repeated verbatim in `agent-defaults-always` and this repo's `.cursor/rules/audit.mdc`; `generic-deep-task-execution` links to it instead of implying a second vocabulary |
| WQ-001 | Handoff doc cleanup | 2026-08-29 | Root transfer notes folded into `HANDOFF_NEXT_AGENT.md`; the superseded stubs were deleted 2026-08-31 (WQ-214) |
| WQ-002 | Audit depth review | 2026-08-29 | Behavior steps 1–30: **0 fail**; Findings → Engineering backlog WQ-201–206 |
| WQ-100 | D:\ vs Desktop deep compare + merger | 2026-08-29 | Desktop canonical; backup `_AgentStarterPack_merge_staging` |
| WQ-101 | `generic-deep-task-execution.mdc` complete-picture contract | 2026-08-29 | Engine 2.22.12 |
| WQ-102 | Work queue discipline in Starter Pack | 2026-08-29 | `generic-work-queue-discipline.mdc`, template, bootstrap, `docs/WORK_QUEUE.md` |
| WQ-103 | Multi-tool Phase 1 parity matrix | 2026-08-29 | `docs/MULTI_TOOL_GAP_PLAN.md` |
| WQ-104 | WORK_QUEUE backfill (`ensure-work-queue.ps1` + refresh) | 2026-08-29 | Engine 2.22.15 |
| WQ-105 | WORK_QUEUE automated verify (`verify-work-queue.ps1`, step 31) | 2026-08-29 | Engine 2.22.15 |
| WQ-009 | Refresh pack agent context | 2026-08-29 | `refresh-agent-context.ps1`; stamp 2.22.15 |
| WQ-106 | Multi-tool Phase 2 portable exports | 2026-08-29 | `sync-portable-docs.ps1`, `pack/docs/portable/` |
| WQ-107 | Multi-tool Phase 3 Portable bootstrap guidance | 2026-08-29 | `Bootstrap-Portable-Project.cmd`, `verify-portable-bootstrap.ps1`, step 33 |
| WQ-108 | Multi-tool Phase 4 tool adapter register | 2026-08-29 | `register-tool-adapters.ps1`, `Register-Tool-Adapters.cmd`, step 34 |
| WQ-003 | Multi-tool / reduce Cursor dependency | 2026-08-29 | Phases 1–6 complete (incl. WQ-301 freshness, WQ-308 session-start); see `docs/MULTI_TOOL_GAP_PLAN.md` |
| WQ-201 | Section E semantic hardening (checklist path modulesReviewed) | 2026-08-29 | `semanticChecklistPathSections`, engine 2.22.19 |
| WQ-203 | agent-code-audit skill Section E note | 2026-08-29 | Shipped with WQ-201 |
| WQ-005 | VERSION bump 1.7.0 → 1.8.0 | 2026-08-29 | `CHANGELOG.md`, doc sync |
| WQ-202 | Sections H/I semantic hardening | 2026-08-29 | `semanticChecklistPathSections` H+I, engine 2.22.20 |
| WQ-205 | PS LOC cite 3,300 → 4,900 | 2026-08-29 | `docs/AUDIT.md` + pack reference template |
| WQ-007 | Refresh agent docs in a bootstrapped app | 2026-08-30 | Ran against an external app checkout (path deliberately not recorded — this file is mirrored into installs and pushed) — pack 1.8.0 / engine 2.22.20 |
| WQ-306 | Agent context contract v2 + upgrade path doc (Phase A) | 2026-08-30 | schema v2, `docs/AGENT_UPGRADE_PATH.md`, behavior step 27 |
| WQ-301 | Phase 6b MCP freshness tools (Phase B) | 2026-08-30 | `agent_context_freshness.py`, MCP tools, step 35 |
| WQ-307 | Update-AgentStack.cmd unified upgrade (Phase C) | 2026-08-30 | `update-agent-stack.ps1`, root entry point |
| WQ-010 | Delete merge staging folder | 2026-08-30 | `_AgentStarterPack_merge_staging` removed from Desktop |
| WQ-012 | Desktop pack cleanup + sync | 2026-08-30 | Installed→Desktop mirror; backup folder removed; archive deleted; the transfer-drive checkout deleted; manifest **2.22.24** on both |
| WQ-008 | Install with `-Prune` | 2026-08-30 | `install.ps1 -Prune` 2026-08-30; 0 stale files; profile at **2.22.24**; `doctor.ps1` user scope OK |
| WQ-204 | machineCoverage empty-section fix | 2026-08-30 | `collect_config_machine_checks` only lists domain map existence for sections with modules; engine **2.22.25** |
| WQ-206 | Complete-picture handoff verify | 2026-08-30 | `verify-complete-picture.ps1`; wired verify-agent-setup + behavior step 37 |
| WQ-303 | Global rules with workspace-specific boundaries | 2026-08-30 | **Rejected** — violates generic-only policy; profile-only preferences stay in `%USERPROFILE%\.cursor\rules\` |
| WQ-305 | Import smoke beyond root `*.py` | 2026-08-30 | import smoke `moduleSearchDirs`; bootstrap `$PackDir`; archive `Get-SectionBody` line-boundary fix; `hardware_cache.py` fixture stub; behavior **0 fail**; `install.ps1 -Prune`; engine **2.22.28** |
| WQ-308 | Phase D freshness adapter (D1-D3) | 2026-08-30 | session-start file + Cursor hook; `repair-agent-docs.ps1`; behavior steps 38-39 **0 fail**; engine **2.22.32**; BSOD hub rollout |
| WQ-304 | **`install.sh` / OS parity (Phases 1–6)** | 2026-08-30 | `pack-paths.ps1`, `.sh` wrappers, behavior steps 40–43 **0 fail**; `test-os-portability-probe.ps1`; CI `pack-os-smoke.yml`; engine **2.22.37** |
| WQ-006 | Git commit + remote | 2026-08-30 | `48968bf`→`968c4e9` pushed to `https://github.com/binary-100/AgentStarterPack.git`; **Pack OS smoke run #11 success** |
| WQ-413 | Maintainer hygiene backlog (P0–S2 scans) | 2026-08-30 | WORK_QUEUE fix; doc/portable sync; rules map; AGENT_CHAT_SYNC removed; Update-AgentStack verify; S2-9 WORK_QUEUE in VERSION_SYNC; profile install **2.22.43** |

---

## Cross-references

| Doc | Role |
|-----|------|
| `HANDOFF_NEXT_AGENT.md` | Session handoff + pitfalls; §11 points here |
| `docs/MULTI_TOOL_GAP_PLAN.md` | WQ-003 Phase 1 deliverable |
| `docs/AUDIT.md` | Audit protocol (Fix/Improve per run) |
| `pack/docs/AGENT_COORDINATION_BACKLOG.md` | WQ-302 detail |
| `pack/docs/RULES_AND_VERIFY_MAP.md` | Rules vs verify inventory; status propagation channels |
| `docs/ROADMAP.md` | *Not used in this repo* — product apps only |
