# Audit system changelog

Decisions already made — **do not re-debate**. Before changing audit design, read this + `AUDIT_SYSTEM.md` + `AGENT_WORKFLOW.md`.

Bump **`pack/audit/manifest.json`** `"version"` when you change synced audit files. Add an entry here in the same commit/sync.

---

---

## 2.22.53 (2026-08-31)

**Root cleanup, and the mechanism that made it unsafe.** With the vocabulary settled, four root
documents had no remaining job: two implementation specs and the implementer notes whose work shipped,
and a transfer stub that had already been reduced to a redirect. All four deleted, along with the code
that policed them — `verify-complete-picture.ps1` no longer collects a stub it will never find, and no
longer lists two specs among its pack sources.

- **`install.ps1` `SkipRelPaths` matched exact files only**, so a `maintainerOnlyPaths` entry naming a *folder* did nothing. `docs/handoffs/` accumulates a file per work slice, and listing them one at a time guarantees the next one ships into every user's profile. A listed folder now excludes everything under it, `sync-audit-system.ps1` removes a directory entry with `-Recurse`, and **step 26** asserts both — including that skipping `docs\handoffs` does not take a same-prefixed neighbour (`docs\handoffs-notes.md`) with it
- **`HANDOFF_NEXT_AGENT.md`: 788 lines to ~470.** Roughly 400 lines were a bump-by-bump history the changelog already holds, and it had started to contradict it. What replaced it: the standing decisions in one place, and the findings that generalise past the bump that produced them. Section numbering is unchanged, because `verify-complete-picture.ps1` reads `## 11.` for the queue pointer
- **The pack's own `docs/handoffs/README.md` still said `{{PROJECT_NAME}}`** — scaffolded before 2.22.50 fixed the substitution, so this repo carried the exact defect it had shipped a guard for. Generated projects were already correct; only this copy predated the fix
- **`.cursor/rules/no-publish-from-this-machine.mdc` is now gitignored.** It tells an agent never to commit or push, which is true of the working copy and *false* on the machine that publishes — committing it would instruct an agent there to refuse the push it was asked for
- **`docs/handoffs/active/HANDOFF_WQ011_primary_system_update.md`** — the pack now uses its own handoff convention for the transfer to the primary system, and passes `verify-agent-handoffs.ps1`

## 2.22.52 (2026-08-31)

**One word for one concept: handoff.** The pack had been using "handoff" and "handover" as if they
were distinct terms — 519 occurrences across 56 files, 132 of them the second spelling. They are not
distinct: English treats them as synonyms and the second is simply the British-leaning form, so no
reader, human or agent, can infer a difference that the language does not carry.

- **`HANDOVER_NEXT_AGENT.md` → `HANDOFF_NEXT_AGENT.md`**, with every reference updated: `manifest.json` `maintainerOnlyPaths`, `VERSION_SYNC.json` `scanFiles` (both entries), `export.ps1`, root `AGENTS.md`, the session-start and refresh docs, and the freshness `requiredReads`
- **Two spots a blind replace would have broken, fixed by hand.** `verify-complete-picture.ps1` picked the session doc out of a source list with `-match 'HANDOVER'`; that list also holds `docs/handoffs/active/HANDOFF_WQnnn` files, so a bare `HANDOFF` match would have grabbed a work slice and then failed to find a section it never had — now `HANDOFF_NEXT_AGENT`. Step 46's banned-token table had the same shape: bare `HANDOFF` would have flagged the shipped handoff convention that rules are *supposed* to name
- **Two words the sweep left alone on purpose:** `WEEKEND_HANDOFF.md` and `PACK_IMPLEMENTER_HANDOFF.txt` were already correct
- **Step 49** fails on any reappearance of the retired synonym in `.md`, `.mdc`, `.ps1`, `.py`, `.cmd`, `.bat`, `.json`, `.txt` or `.template`. Proved by planting a stray in `docs/` — which also tripped the unmapped-doc check, so two guards caught one file
- **Its first real run failed on the documentation of its own change**, which is how the exemptions got their final shape. A total ban meant no file could record what this one used to be called, so the old **filename** `HANDOVER_NEXT_AGENT.md` stays citable while the bare word does not; a search for the old name still has to land somewhere. The changelog is exempt because it records the retirement, and the checker because a linter has to spell the word it bans
- **Glossary in `pack/docs/AGENT_HANDOFFS.md`** states the decision and the two scales it covers: one work slice (`HANDOFF_WQnnn_<slug>.md` plus registry) and one session (`HANDOFF_NEXT_AGENT.md`). Same verb, different grain

**Encoding note for whoever reads a console during this work:** the sweep rewrote 31 files by reading
and writing UTF-8 explicitly, and a byte-level check afterward found 194 valid UTF-8 files, 74 with
real em dashes and zero mojibake. Terminal output during the pass *displayed* em dashes and section
signs as garbage — that is the console codepage, not the files. Check bytes before "repairing" them.

## 2.22.51 (2026-08-31)

**The pack broke its own rule, in the layer its tests never touch:**

- **Twelve bare `pause` statements across four root launchers** - `Bootstrap-Project.cmd`, `Bootstrap-Portable-Project.cmd`, `Install-AgentStarterPack.cmd`, `Register-Tool-Adapters.cmd` - while `generic-terminal-and-build-hygiene.mdc` tells every project to gate `pause` behind `BUILD_NOPAUSE`. All now read `if not defined BUILD_NOPAUSE pause`, so a double-clicked window still stays open and an agent run never waits for a keypress
- **Why no test caught it:** every behavior step invokes the `.ps1` underneath with `-NoPause`. The `.cmd` layer is the one a human double-clicks and an agent runs, and it was never exercised. Found by running the launchers instead of the scripts they wrap - `Bootstrap-Portable-Project.cmd` printed "Press any key to continue"
- **Behavior step 48** fails on any bare `pause` in a root `.cmd`. `START_HERE.md` and the always-on rule now say an agent should set `BUILD_NOPAUSE=1` before running a launcher, the same as for a project build
- **The rest of the generator sweep came back clean:** bootstrap across 6 stack/target combinations produces no unsubstituted placeholders, no BOM and no mojibake in any file type (including `.windsurfrules`, which the step 23 include list does not cover), and every path in `.agent-bootstrap.json` exists on disk. `bootstrapVersion` is covered by `VERSION_SYNC.json` `extraReplacements`, so it cannot go stale at the next bump. Two citations that looked wrong - `docs/VERSION_SYNC.md` and `docs/PORTABLE_SETUP.md` in generated docs - are correct pack-scoped references, verified rather than "fixed"

## 2.22.50 (2026-08-31)

**Found by using the fix from 2.22.49 instead of trusting it:**

- **The handoffs README shipped with `{{PROJECT_NAME}}` in its title.** `ensure-work-completion.ps1` substitutes `{{PROJECT_NAME}}` and `{{PROJECT_ROOT}}` and writes BOM-free for `WORK_COMPLETION.md`, but plain-copied the handoffs README - a branch written when no such template existed, so nothing ever exercised it. Both paths now use the same substitution and the same writer
- **Bootstrap smoke (step 23) fails on any unsubstituted placeholder.** Same shape as the BOM assertion beside it: both catch the generator handing a user a file it half-finished. `{{[A-Z_]+}}` anywhere in the generated `.md`, `.json`, `.cmd`, `.bat`, `.py` or `.mdc` output is a failure
- Verified by bootstrapping a project and reading the file: title renders as **`# Handoffs - ProbeApp`**, no BOM, zero placeholders remaining anywhere in the tree

## 2.22.49 (2026-08-31)

**A rule's wording was checked; its advice was not:**

- **`ensure-work-completion.ps1` copied a template that never existed.** It creates the `docs/handoffs/` scaffold for a project and then copies `pack\templates\docs\handoffs\README.md.template` - a file no one ever wrote. The copy sits behind `Test-Path`, so the promised README simply never appeared, no error was raised, and `pack/docs/AGENT_HANDOFFS.md` advertised that template plus `HANDOFF_BUILD.md.template` in its pack-files table. Both templates now exist and are in `packMirror`: the README explains the folder and the status/WORK_QUEUE invariant, the build starter carries the registry table, the absolute-path opener and an acceptance checklist that ends in "WQ row moved to Done"
- **Behavior step 47 resolves every `pack/`-rooted path cited by rules, skills and pack docs.** Only `pack/` paths: a doc naming `docs/ROADMAP.md` or `scripts/apply_version.py` is describing the reader's project, not this pack, and flagging those would make the check noise. Changelogs are excluded because describing a file that has since been renamed is their job
- **Three exclusions the discovery run earned.** A second extension after the first is not a match (`pack/templates/x.md.template` was reading as a missing `x.md`, and `.jsonl` as a missing `.json` - six phantom findings on the first pass); a line whose point is that a file *must not* exist is skipped, so `AUDIT_SYSTEM.md`'s "orphan `pack/templates/AUDIT.md.template` is forbidden" stays legal; globs and placeholders are skipped. Bare `.mdc` names are deliberately **not** resolved - `PACK_MAINTENANCE.md` lists `agent-readiness.mdc` and four others under **Project-only rules (never in pack)**, and a checker that cannot tell those from a pack rule would report the doc for being right

## 2.22.48 (2026-08-31)

**The rules scan's findings, closed mechanically instead of by memory:**

- **Behavior step 46 fails when a shipped rule describes this repo** (WQ-209) - `WQ-\d+`, `HANDOFF`, `WEEKEND_HANDOFF`, pack-only spec and plan names, `Phase 6x`, and section numbers like `§11`. A line may still name pack internals when it carries a scope marker (**Agent Starter Pack maintainer repo:**, **Maintainer pack**, or a **Pack maintenance** section), because the difference between guidance for every project and a note for the maintainer is the marker, not the reader's charity. Case-**sensitive** on purpose: a rule may say "the handoff's status section" in plain English, but naming `HANDOFF_NEXT_AGENT.md` points at a file only this repo has. `generic-work-queue-discipline.mdc` is exempt from the id ban - it owns the id convention, so its `WQ-001` examples are the subject matter
- **It immediately found 11 more leaks that reading had missed** - `§11` and `§5` cross-references, `HANDOFF*.md` in a doc-pattern list, and an instruction to overwrite `HANDOFF_NEXT_AGENT.md` given to every project. All reworded to name sections rather than number into documents the reader may not have
- **Terminal hygiene now has one owner per job** (WQ-207) - `generic-terminal-and-build-hygiene.mdc` is build hygiene (prompt gating, exit codes, reading output) and opens by saying what it does *not* cover; diagnosis stays in skill `agent-terminal-hygiene`; the before/after sequence stays in `agent-defaults-always.mdc`, which is the copy that actually loads. The queue row claimed this would cut the always-on budget - it does not, the duplication lived in a rule that never auto-loads, and the real gain is that three copies can no longer drift apart
- **One audit trigger list** (WQ-208) - canonical in `audit-protocol.mdc`, repeated verbatim in `agent-defaults-always.mdc` and the pack's own `audit.mdc`. Before this, "find problems" reached only one of the three surfaces

## 2.22.47 (2026-08-31)

**Rules that shipped this repo's private state to every project:**

- **`generic-deep-task-execution.mdc` no longer names WQ-301/302, phase 6b/6c, `HANDOFF` §1/§8/§11 or `WEEKEND_HANDOFF`.** Those lines told an agent in a bootstrapped app to check a work item, a phase number and two doc sections that do not exist there. The contract they encoded is real and stays - separate the tracks, keep deferred work on the list, do not close one track because a neighbour shipped - now stated in terms any project can satisfy. Source inventory (step 1) likewise says "every agent-doc folder the project uses" instead of `pack/docs/`, and the grep list ends in "the project's own recurring qualifiers" rather than this pack's
- **`generic-agent-doc-hygiene.mdc`** loses "Phase 6b not built" and the unscoped `docs/MULTI_TOOL_GAP_PLAN.md` cite; the maintainer-only step keeps its **Agent Starter Pack maintainer repo:** prefix, which is what made the neighbouring `INSTALL.txt` line acceptable all along
- **The agent's brief was corrupting itself, one audit at a time.** `Update-AgentManifest` re-read `docs\.audit_agent_manifest.json` with `Get-Content -Raw` and no `-Encoding UTF8`, so PowerShell 5.1 decoded a BOM-less UTF-8 file as ANSI, turned every em dash into three characters, and wrote them back as UTF-8 - compounding on each run. All five JSON reads in `run_audit_core.ps1` are pinned now, matching the fix the domain-map read already had. **Behavior step 45** copies the fixture, puts an em dash in a checklist bullet, runs the audit and fails if the manifest lost it or doubled it - the artifact is asserted, not the plumbing, because the first attempt at this fixed the wrong layer (the Python pipe, which was already ASCII-escaped and clean)
- **`agent-defaults-always.mdc` gains a Session start section.** All five tool entry templates tell agents to read `docs/AGENT_SESSION_START.md` on the first turn and no rule did, so a project bootstrapped before that template - or one with a hand-edited `AGENTS.md` - never heard about the file the freshness system writes. Four lines in the always-on rule rather than a thirteenth rule file, per the pack's own extend-over-duplicate guidance

## 2.22.46 (2026-08-31)

**The engine now passes the rule it enforces:**

- **`audit_code_checks.py` 2592 → 2174 LOC** against its own 2500 ceiling. Two groups moved out whole, no behavior change: **`audit_version_docs.py`** (Section M cites - audit engine, pack release, app docs, changelog) and **`audit_install_wiring.py`** (the checks that read *outside* the repo: installed-vs-source, `mcp.json`, reference templates). **`audit_common.py`** holds the four primitives all three need - config, repo root, canonical version, manifest version - so the modules do not import each other in a circle
- **Public surface unchanged** - the moved names are re-exported from `audit_code_checks`, because `run_audit_core.ps1` and the self-test call them by name; a test asserts all nine stay reachable, and another fails if the engine creeps back over the threshold
- **`doc_version_sync.py` untouched** - it keeps its own copy of `resolve_repo_root` and the version regexes on purpose (build pipeline must not depend on the audit engine); behavior step 23 still asserts the copies agree
- Three new production modules means three new domain-map rows, mirror entries and real tests - the split closes the Improve without opening a Section B orphan or a Section D test gap
- **`maintainerOnlyPaths` takes nested paths too** - a workspace rule describing one machine's publishing policy has no business in someone else's install, even sitting inert inside the copied tree

## 2.22.45 (2026-08-31)

**Tests that graded the machine instead of the pack, and a failure that said nothing:**

- **`agent_context_freshness.py`** — honours **`AGENT_STARTER_PACK_INSTALL_ROOT`**, which PowerShell has read since 2.22.4. Python resolving the install straight from `%USERPROFILE%` made the freshness verdict a property of the developer's profile: behavior **step 38** passed where the install happened to match the source pack, passed on a machine with no install at all, and failed on one carrying an older install. Same fix in **`audit_code_checks.py`** for the installed-vs-source check, and its `mcp.json` lookup now follows the override's user root
- **Step 38 is hermetic and proves both directions** — the probe builds its own scratch install to compare against, then repeats the check against an install one version behind and requires the verdict to flip. Previously a probe that found no install to compare against would have satisfied every assertion. It also sets `AGENT_STARTER_PACK_ROOT` for the generated Cursor hook, which otherwise ran the *installed* pack's freshness module rather than the code under test
- **`verify-audit-system.ps1` printed failures with no reason** — the sync and behavior children were invoked without `-PassOutput`, so a red run ended at `Summary: 1 fail(s)` with no `[DRIFT]` line above it and no remedy. Both now stream their output and emit a `Fail` naming what to run. Locked in by new behavior **step 44**
- **`maintainerOnlyPaths`** (manifest) — `install.ps1` copies the whole checkout, so session handoffs and implementation specs were landing in every user's profile, while `README.md`, `INSTALL.md`, `CHANGELOG.md`, `INSTALL.txt`, `VERSION` and `install_launcher.py` shipped *without* being mirrored and could only be refreshed by a full re-install. Root docs are now mirrored, maintainer notes are skipped by install and deleted from existing installs by sync, `.zip` release artifacts no longer ship, and a new guard requires every root file to be one or the other

## 2.22.44 (2026-08-31)

**Doc hygiene widen + enforce (no new rule):**

- **`generic-agent-doc-hygiene.mdc`** — maintainer entry docs in scope; forbid parallel `STICK_*` / `*_INSTALL.txt`; delete redundant copies when consolidating
- **`verify-complete-picture.ps1`** — pack repo: INSTALL.txt vs VERSION, WEEKEND redirect stub, no parallel install docs, HANDOFF must not primary-point WEEKEND
- **Doc consolidation:** `INSTALL.txt` / `INSTALL.md` / `HANDOFF` / `WEEKEND_HANDOFF` redirect; `INSTALL.txt` in `VERSION_SYNC.json`

## 2.22.43 (2026-08-30)

**Hygiene batch (WQ-413):**

- **`VERSION` → 1.8.0** + `CHANGELOG.md`; maintainer doc sync targets refreshed
- **`AGENT_CHAT_SYNC.md` deleted** — superseded by refresh pipeline
- **`HANDOFF_NEXT_AGENT.md` §6** — pointer-only (removed stale 2.22.4 block)
- **`verify-work-queue.ps1`** — allow empty Active **Next** when header says `(none)`
- **`update-agent-stack.ps1`** — runs **`verify-complete-picture.ps1`** on maintainer pack after refresh
- **`generic-agent-handoff-discipline.mdc`** — completion defers to **`WORK_COMPLETION.md`** (removed duplicate checklist)
- **`docs/VERSION_SYNC.json`** — **`docs/WORK_QUEUE.md`** in maintainer doc sync + table `extraReplacements` (S2-9)
- **`verify-work-queue.ps1`** — header **Pack version** / **Audit engine** vs `VERSION` + manifest

---

## 2.22.42 (2026-08-30)

**Rules / verify consolidation (status drift prevention):**

- **`pack/docs/RULES_AND_VERIFY_MAP.md`** — inventory of rules vs verify scripts, overlaps, prevention vs detection, canonical status propagation
- **`generic-work-queue-discipline.mdc`** — propagate status to all derivative docs + run `verify-complete-picture.ps1` on Done/Parked
- **`generic-agent-doc-hygiene.mdc`** — §6 after-ship status alignment (distinct from version sync)
- **`generic-agent-handoff-discipline.mdc`** — completion checklist defers to `WORK_COMPLETION.md` + map (less duplication)
- **`verify-complete-picture.ps1`** — scans more pack handoff sources; generic Done-WQ vs parked/not-built patterns for any Done id

---

## 2.22.41 (2026-08-30)

**Handoff / WQ alignment (post-ship doc hygiene):**

- **`verify-complete-picture.ps1`** — when a WQ id is in **Done log**, **FAIL** handoff/spec files that still say that slice is parked, not built, or deferred (WQ-301 / WQ-308 rules; changelog + WORK_QUEUE excluded)
- **`pack/docs/WORK_COMPLETION.md`** — step **5b**: run complete-picture verify after moving WQ to Done
- **Docs aligned:** Phase ID map in `docs/MULTI_TOOL_GAP_PLAN.md`; stale 6b/308 parked text removed from HANDOFF, WEEKEND_HANDOFF, PACK_IMPLEMENTER_SPEC, AGENT_COORDINATION_BACKLOG, AGENT_UPGRADE_PATH, AGENT_FRESHNESS_ADAPTER_PLAN
- **Spec field names:** Phase 6b MCP return shape uses shipped `installedEngineVersion` / `stampedEngineVersion` (not design-era `desktopVersion`)
- **`generic-deep-task-execution.mdc`** track **(F)** — deferred = **6c / WQ-302** only

---

## 2.22.40 (2026-08-30)

**Linux CI probe fix:**

- **`Invoke-PackScript`** — capture exit code without stdout pipeline (Linux `$LASTEXITCODE` loss)
- **`test-os-portability-probe.ps1`** — native Linux uses PATH python; absolute `-PythonCommand` only for mock

---

## 2.22.39 (2026-08-30)

**Linux CI probe fix:**

- **`Resolve-PackPythonInvoke`** — accept absolute `PythonCommand` paths (Linux CI passes `sys.executable`; `Get-Command` missed it)

---

## 2.22.38 (2026-08-30)

**Linux CI path fixes (WQ-304 / pack-os-smoke):**

- **`Get-PackManifestPath` / `Get-PackScriptPath`** in `pack-paths.ps1` — forward-slash-safe joins for manifest and script paths
- **`check-requirements.ps1`** — audit engine self-test path uses helper (fixes ubuntu CI probe)

---

## 2.22.37 (2026-08-30)

**OS portability Phases 5–6 (WQ-304):**

- **`Test-PackIsWindows`** — test-only `AGENT_STARTER_PACK_TEST_OS` hook for mock non-Windows probes on Windows hosts
- **`pack/scripts/test-os-portability-probe.ps1`** — HOME/.cursor resolution, pwsh path, preflight launcher optional, `Invoke-PackScript` smoke
- **Behavior step 43** — mock Linux portability probe
- **`docs/PORTABLE_SETUP.md`** — verified cross-host matrix
- **`.github/workflows/pack-os-smoke.yml`** — optional `ubuntu-latest` + `pwsh` CI smoke

---

## 2.22.36 (2026-08-30)

**OS portability Phase 4 (WQ-304):**

- **`pack/scripts/pwsh-wrap.sh`** — shared `pwsh` require + exec helper
- **Root `.sh` entry points:** `Refresh-AgentContext.sh`, `Bootstrap-Project.sh`, `Check-Requirements.sh`, `run_audit.sh` (plus existing `install.sh`)
- **`docs/PORTABLE_SETUP.md`** — cross-host entry point matrix updated
- **Behavior step 42** — `.sh` wrapper smoke

---

## 2.22.35 (2026-08-30)

**OS portability Phase 3 (WQ-304):**

- **`Resolve-PackPythonInvoke`** + install-fix helpers in `pack-paths.ps1` (`Get-PackPythonInstallFix`, etc.)
- **`check-requirements.ps1`** — `python3` first off Windows; `py -3` launcher required Windows-only; cross-platform fix hints
- **`doctor.ps1`** — `Get-AgentStarterPackUserRoot` / `Get-DefaultCursorUserRoot`; MCP smoke uses resolved Python
- **Behavior steps 21 (OS-aware) + 41** — preflight/doctor scope gates

---

## 2.22.34 (2026-08-30)

**OS portability Phase 2 (WQ-304):**

- **`Invoke-PackScript`** — `-PassOutput`, `ValueFromRemainingArguments` for script params; quiet mode returns exit code
- **Core scripts** — nested spawns routed through helper (install, refresh, bootstrap, sync, verify-*, run_audit_core, update-agents/stack, repair, adapters, archive, behavior suite)
- **Intentional exceptions** — DualShell + step 29 cross-host parity still invoke `$otherShell.Source` directly; hook JSON string in `install.ps1`

---

## 2.22.33 (2026-08-30)

**OS portability Phase 1 (WQ-304):**

- **`pack-paths.ps1`** — `Test-PackIsWindows`, `Get-DefaultCursorUserRoot`, `Get-PackPowerShellPath`, `Invoke-PackScript`; cross-platform `$HOME/.cursor` user root
- **`install.sh`** — full install via `pwsh -File install.ps1` when PS 7 is present (no partial copy-only path)
- **`install.ps1`** — post-install sync uses `Invoke-PackScript`
- **`docs/OS_PORTABILITY_PLAN.md`** — phased checklist (Phases 2–6 remain)
- **`docs/PORTABLE_SETUP.md`** — WQ-304 active; honest Windows-first entry points until Phase 4
- **Behavior step 40** — shell helper + `install.sh` delegation smoke

---

## 2.22.32 (2026-08-30)

**Hub repair preserve + rollout:**

- **`repair-agent-docs.ps1`** — skips rewriting **`AGENTS.md`** when project-specific markers detected (`PRODUCT_REFERENCE.md`, `AGENT_READINESS.md`, `bsod_analyzer.py`, etc.)
- **`AI_INSTRUCTIONS.md.template`** — execute/verify cites project-local `docs/portable/GENERIC_RULES.md` first

---

## 2.22.31 (2026-08-30)

**Multi-model hub coverage (WQ-308 Phase D3) — repair + verify + portable project copy:**

- **`repair-agent-docs.ps1`** — refreshes `AI_INSTRUCTIONS.md` / `AGENTS.md` when hub patterns missing; syncs **`docs/portable/GENERIC_RULES.md`** + skill mirrors; runs **`register-tool-adapters -Repair`**
- **`refresh-agent-context.ps1`** — calls repair after audit template sync (existing projects pick up template changes)
- **`bootstrap-project.ps1`** — calls repair at end (portable bootstrap always gets project-local rules)
- **`agent_context_freshness.py`** — session-start markdown includes execute/verify one-liner
- **`verify-portable-bootstrap.ps1`**, **`verify-agent-setup.ps1`** — hub pattern + portable copy + session-start checks
- **Behavior step 39** — repair probe + VerifyOnly gate
- **`docs/PORTABLE_SETUP.md`** — PS 7 cross-host vs Windows entry-point scope clarified

---

## 2.22.30 (2026-08-30)

**Agent freshness adapter Phase D2 (WQ-308) — Cursor sessionStart hooks:**

- **`pack/templates/cursor/hooks.json.template`** + **`session-freshness.ps1`** — inject `additional_context` from `agent_context_freshness.py`
- **`bootstrap-project.ps1`** — `-Targets Cursor` writes `.cursor/hooks.json` + hook script
- **`install.ps1 -InstallSessionHooks`** — optional user-level hook under `%USERPROFILE%\.cursor\hooks\`
- **Behavior step 38** — bootstrap hook files + stdout JSON smoke

---

## 2.22.29 (2026-08-30)

**Agent freshness adapter Phase D1 (WQ-308):**

- **`agent_context_freshness.py`** — `--session-brief`, `--write-session-start`; builds `docs/AGENT_SESSION_START.md`
- **`invoke-agent-freshness.ps1`** — wrapper for hooks/CLI (`-SessionBrief`, `-WriteSessionStart`, `-PrintOpener`)
- **`refresh-agent-context.ps1`** — writes session-start file after refresh
- **Templates** — `AI_INSTRUCTIONS.md`, `AGENTS.md`, gitignore snippet cite session-start file
- **Behavior step 38** — session-brief JSON + file write smoke

---

## 2.22.28 (2026-08-30)

**Handoff archive Done-log parse (WQ-305 follow-up):**

- **`Get-SectionBody`** (archive, handoffs, work-queue, complete-picture) — end markers match at line start only; fixes false truncate on markdown table `|---|` rows (behavior step 36)

---

## 2.22.27 (2026-08-30)

**Behavior suite follow-up (WQ-305):**

- **`behavior-fixture/hardware_cache.py`** — restore stub on disk (domain map listed it after `catalog_cache.py` removal; steps 8/10 failed on missing module)
- **`verify-audit-behavior.ps1`** — always dot-source `pack-paths.ps1` (fixes `Write-Utf8NoBom` when `-PackRoot` is passed)

---

## 2.22.26 (2026-08-30)

**Import smoke + behavior-suite fixes (WQ-305):**

- **`audit_code_checks.py`** — import smoke scans `domainMap.moduleSearchDirs` (and optional `importSmoke.searchDirs`), not only root `*.py`
- **`bootstrap-project.ps1`** — fix `$PackDir` / `ensure-work-completion.ps1` path (exit 0; behavior steps 23/33/34)
- **`archive-completed-handoff.ps1`** — trim registry values; resolve verify script via `pack-paths.ps1`
- **Behavior fixture** — drop removed `catalog_cache.py` from domain map + manifest
- **`verify-audit-behavior.ps1`** — steps 2/12/36 aligned; manifest tracks `audit_allowlist.json.template`

---

## 2.22.25 (2026-08-30)

**machineCoverage + complete-picture handoff verify (WQ-204, WQ-206):**

- **`audit_code_checks.py`** — `domain map module existence` in `machineCoverage` only for domain-map sections that list modules (not empty D–K)
- **`verify-complete-picture.ps1`** — inventories handoff sources, scans pending-work keywords (INFO), flags stale HANDOFF section 11 vs `docs/WORK_QUEUE.md` (Improve in audit mode)
- **`verify-agent-setup.ps1`** — runs complete-picture verify on pack + reference project
- **`verify-audit-behavior.ps1` step 37** — pack repo passes; probe proves stale phrase detection

---

## 2.22.24 (2026-08-30)

**Work completion + safe handoff archive (preview default):**

- **`pack/docs/WORK_COMPLETION.md`** — three cleanup channels (Fix vs Improve vs work completion); forbidden bulk deletes
- **`archive-completed-handoff.ps1`** — **preview by default**; **`-Apply`** required to move; gates: completed date, WQ Done, verify handoffs, no overwrite unless `-Force`
- **`ensure-work-completion.ps1`** — creates `docs/WORK_COMPLETION.md` + handoffs scaffold when missing (never overwrite)
- **`verify-audit-behavior.ps1` step 36** — proves preview never moves; `-Apply` refuses active/incomplete; moves only when all gates pass
- **`refresh-agent-context.ps1` / `bootstrap-project.ps1`** — call ensure-work-completion
- **`verify-agent-setup.ps1`** — checks WORK_COMPLETION + archive script present; ensure on reference project
- **`verify-agent-handoffs.ps1`** — session opener must use full absolute path

---

## 2.22.22 (2026-08-30)

**Agent handoff discipline + audit verification (no auto-delete):**

- **`generic-agent-handoff-discipline.mdc`** — one session opener per handoff; multi-agent `agents_remaining`; PC-local exempt paths unchanged
- **`pack/docs/AGENT_HANDOFFS.md`** — folder layout (`docs/handoffs/active/`), registry table, lifecycle
- **`verify-agent-handoffs.ps1`** — registry/WQ reconciliation; **Improve** when archive-safe (completed + Done log + empty `agents_remaining`); **Fix** when status/WQ drift
- **`run_audit_core.ps1`** — invokes handoff verify in machine phase (Improve/Fix only; never deletes files)
- **`verify-agent-setup.ps1`** — optional handoff check on reference project
- **`generic-work-queue-discipline.mdc`** — completing WQ updates handoff status before audit archive

---

## 2.22.21 (2026-08-30)

**Agent upgrade path Phases A–C (WQ-306, WQ-301, WQ-307):**

- **`docs/AGENT_CONTEXT.json` schema v2** — `canonicalProjectRoot`, absolute `requiredReads`, `triggerPhrases`, `handshake`
- **`docs/AGENT_UPGRADE_PATH.md`** — tool-neutral install → refresh → open-chat steps
- **`Update-AgentStack.cmd`** — optional `-Install` + project refresh + remediation printout
- **`pack/scripts/agent_context_freshness.py`** — shared freshness logic; **`--self-test`**
- **MCP `check_pack_freshness`**, **`get_agent_refresh_brief`** on agent-hygiene server
- **Behavior step 35** — Python self-test + MCP tool presence + Update-AgentStack entry point
- **`AI_INSTRUCTIONS.md.template`**, **`agent-defaults-always.mdc`** — v2 contract + MCP + handshake

**Phase D (Cursor session hooks)** — parked WQ-308; not in this release.

---

## 2.22.20 (2026-08-29)

**Sections H/I semantic hardening (WQ-202) + doc cite (WQ-205):**

- **`semanticChecklistPathSections`** extended to **H** and **I** — template and maintainer doc paths require `modulesReviewed[]`
- **`docs/AUDIT.md`** — PS LOC cite ~4,900 lines; explicit H/I checklist paths

---

## 2.22.19 (2026-08-29)

**Section E semantic hardening (WQ-201):**

- **`semanticChecklistPathSections`** in `AUDIT.config.json` — pack Section **E** requires `modulesReviewed[]` for every checklist file path
- **`parse_checklist_paths`**, **`verify_checklist_paths_reviewed`** in `audit_code_checks.py`
- **`agent-code-audit` skill** — Section E checklist paths called out explicitly

---

## 2.22.18 (2026-08-29)

**Multi-tool Phase 4 — per-tool register adapters (WQ-003):**

- **`register-tool-adapters.ps1`** — verify/repair Claude, Copilot, Windsurf project files; optional `-InstallMcp` for Claude Desktop
- **`Register-Tool-Adapters.cmd`** — one-click wrapper
- Behavior **step 34**; **`verify-agent-setup.ps1`** runs adapter verify when `-ReferenceProjectRoot` set

---

## 2.22.17 (2026-08-29)

**Multi-tool Phase 3 — Portable bootstrap guidance (WQ-003):**

- **`Bootstrap-Portable-Project.cmd`** — one-click `-Targets Portable`
- **`verify-portable-bootstrap.ps1`** — required files, GENERIC_RULES cite, no orphan editor files on Portable-only; wired into **`verify-agent-setup.ps1`** and behavior **step 33**
- **`docs/PORTABLE_SETUP.md`**, **`new-project-bootstrap.mdc`** — choose `-Targets` table

---

## 2.22.16 (2026-08-29)

**Multi-tool Phase 2 — portable markdown exports (WQ-003):**

- **`sync-portable-docs.ps1`** — exports `pack/docs/portable/GENERIC_RULES.md` + `skills/*.md` from `pack/rules` and `pack/skills`; `-VerifyOnly` for drift
- Wired into **`sync-audit-system.ps1`** (maintainer repo) and behavior **step 32**
- **`docs/PORTABLE_SETUP.md`**, **`AI_INSTRUCTIONS.md.template`**, bootstrap next-steps updated

---

## 2.22.15 (2026-08-29)

**Work queue automation (backfill + hard verify):**

- **`ensure-work-queue.ps1`** — creates `docs/WORK_QUEUE.md` from template when missing; called from **`refresh-agent-context.ps1`**
- **`verify-work-queue.ps1`** — required sections, unique WQ IDs, exactly one **Next**, Done vs open reconciliation; wired into **`verify-agent-setup.ps1`** and behavior **step 31**
- **Template** — ships valid placeholder `WQ-001` **Next** so new projects pass verify immediately

---

## 2.22.14 (2026-08-29)

**Work queue reprioritization (explicit):**

- **`generic-work-queue-discipline.mdc`** — **When reprioritizing** section: reorder Active rows for dependencies/blockers; reconcile all WQ IDs before/after; forbid deleting rows without Done/Parked/Superseded
- **`AI_INSTRUCTIONS.md.template`** — tool-neutral read-first + non-negotiable for `docs/WORK_QUEUE.md`
- **`new-project-bootstrap.mdc`** — layout includes `docs/WORK_QUEUE.md`

---

## 2.22.13 (2026-08-29)

**Work queue discipline (nothing slips off the radar when priorities change):**

- **`generic-work-queue-discipline.mdc`** — always-on rule: stable WQ IDs, Inbox triage, Done log, one Next; update `docs/WORK_QUEUE.md` before rewriting chat/handoff lists
- **`pack/templates/docs/WORK_QUEUE.md.template`** — bootstrapped with every project; **`docs/ROADMAP.md`** stays product-only
- **`docs/WORK_QUEUE.md`** — pack maintainer canonical queue; **`docs/MULTI_TOOL_GAP_PLAN.md`** — WQ-003 Phase 1 parity matrix
- **`bootstrap-project.ps1`** — copies `WORK_QUEUE.md` from template

---

## 2.22.12 (2026-08-29)

**Complete-picture contract for agent analysis (closes shallow handoff/doc reviews):**

- **`generic-deep-task-execution.mdc`** — new **complete picture** contract: inventory all handoff sources, grep pending-work patterns, separate OS vs tool/model vs audit vs git tracks, cross-check user callouts
- **`HANDOFF_NEXT_AGENT.md` §11** — multi-tool / reduce Cursor dependency restored as active track; OS portability split out

## 2.22.11 (2026-08-29)

**Merger integration — deep task execution rule (from Desktop session):**

- **`pack/rules/generic-deep-task-execution.mdc`** — mandatory depth contracts for deep compare, full scan, and exhaustive requests; forbids deflecting to user phrasing
- **`agent-defaults-always.mdc`**, **`loop-back-protocol.mdc`** — pointers and pushback triggers
- Merged **`D:\AgentStarterPack`** (2.22.10) with Desktop-only docs (`PHASE_6_IMPLEMENTATION_SPEC.md`, `AGENT_CHAT_SYNC.md`)

## 2.22.10 (2026-08-28)

**`mcp/agent_hygiene_server.py` mirrored - sixth and last known instance of the unmirrored hole.** Found
by asking which class of shipped file had not been enumerated yet, rather than waiting for the next
symptom. This one mattered more than most: it is the server `install.ps1` writes into `mcp.json`, so a
stale copy in the profile is a stale MCP server for every agent on the machine. Step 5b now enumerates
`mcp/*.{py,json}` as well.

Enumerated classes are now rules, skills, `pack/docs` + repo `docs/*.md`, `pack/scripts/*.{ps1,py}`, all
of `pack/templates`, root `*.{cmd,bat,ps1,sh}`, and `mcp/`. A seventh class is still possible - the
lesson from six repeats is that the test must enumerate a directory, never list filenames.

---

## 2.22.9 (2026-08-28)

**The unmirrored hole, fifth and outermost appearance: the root entry points.** `install.ps1` copies the
repo root into the profile, so a user gets `Refresh-AgentContext.cmd`, `Bootstrap-Project.cmd`,
`Update-AgentRules.cmd` and the rest - but only two of them were in
`packMirror`. Every other wrapper was write-once: fixed in the pack, stale in the profile forever. (The
two that were tracked are `run_audit.cmd` and `run_audit_tests.bat`.) Found
while fixing the wrapper below, which would itself never have reached an installed copy.

- **Eleven root entry points added to `packMirror`**, and step 5b now enumerates root
  `*.cmd`/`*.bat`/`*.ps1`/`*.sh` the same way it enumerates rules, skills, docs, scripts and templates.
- **`Refresh-AgentContext.cmd` accepts a leading switch.** `Refresh-AgentContext.cmd -NoClipboard` bound
  `-NoClipboard` to `-ProjectRoot` and died with *"Missing an argument for parameter 'ProjectRoot'"*.
  A leading `-` now passes straight through; a first argument without one is still the project root.
- **`refresh-agent-context.ps1` no longer claims the clipboard was "UNAVAILABLE" when `-NoClipboard`
  asked it to skip.** A false status line in the tool people run to clear up confusion is the last place
  to have one.

---

## 2.22.8 (2026-08-28)

**2.22.7's instruction only reached Cursor.** The audit line is tool-neutral and carries its own
remediation, but the behaviour around it - offer the run, wait for approval, read the brief in the same
turn - was written into `pack/rules/agent-defaults-always.mdc` only. That is a `.mdc`, which no tool
but Cursor reads, and `AI_INSTRUCTIONS.md` is the pack's own universal entry point. So a Claude, Copilot
or Windsurf agent saw the audit line with none of the surrounding behaviour, in a pack whose whole point
is being tool-neutral.

- **The offer-to-run instruction now lives in `AI_INSTRUCTIONS.md.template` and
  `AGENTS.md.template`** as well as the Cursor rule. `CLAUDE.md`, `copilot-instructions.md` and
  `.windsurfrules` already delegate to those two, so they inherit it without duplicating text.
- **Step 30 asserts all three carriers**, naming which layer is missing when one is. A test that only
  checked the `.mdc` is what let a Cursor-only feature look finished.
- **The instruction states the mechanism generically:** any agent host that can run a shell command with
  user consent can do this - approving a proposed command is the entire interaction. No editor-specific
  UI is assumed.

---

## 2.22.7 (2026-08-28)

**Staleness now finds the user, and the agent does the work.** The refresh brief existed since 2.21.23,
but nothing told anyone it had gone stale — the only way to learn was to run the refresh, which is what
the warning would have told you to do. Spec §4.10 proposed putting the warning in
`verify-agent-setup.ps1`; that is another command you must remember to run, so it would only have spoken
up in a session where you were already looking.

- **The audit reports it.** `run_audit_core.ps1` reads `docs/AGENT_CONTEXT.json` and emits an **Improve**
  when `auditEngineVersion` is behind the engine running the audit, or when the stamp is a never-refreshed
  stub or unparseable. Improve, not Fix — nothing is broken. Silent when the project has no stamp or a
  current one, so it clears itself and cannot become wallpaper.
- **The remediation is addressed to the agent, not the user:** *offer to run `Refresh-AgentContext.cmd`
  for this project, then read `docs/AGENT_REFRESH.md`*. `agent-defaults-always.mdc` carries the matching
  instruction, so the user approves a run rather than copying a command — the friction that let projects
  go stale in the first place. The audit still only reports; it never mutates.
- **Bootstrap stamps the engine version it generated from.** The stub previously left
  `auditEngineVersion` null, which made every brand-new project open with this Improve while a genuinely
  old project stayed just as quiet. Caught by the bootstrap smoke tests before it shipped.
- **Step 30** asserts both directions: fires when the stamp is behind, names the engine it is behind,
  lands in Improve rather than Fix, uses the offer-to-run wording, and stays silent on a current stamp or
  no stamp at all. It also asserts the rule still carries the offer instruction, since an audit line with
  no one instructed to act on it is just text.

---

## 2.22.6 (2026-08-28)

**The unmirrored-file hole reached the machinery, not just the docs.** An independent pass over
`PACK_IMPLEMENTER_SPEC.md` confirmed both assigned tracks were complete, and its small parity findings
led here.

- **`bootstrap-project.ps1`, `doctor.ps1`, three hygiene scripts, and all nine project templates joined
  `packMirror`** (14 files). This is the same defect as 2.22.5 but with sharper teeth: bootstrapping
  *from the installed pack* is the documented normal path, so after a second pack update a new project
  would have been generated from the first update's templates - `AGENTS.md`, `AI_INSTRUCTIONS.md`,
  `CLAUDE.md`, the Copilot and Windsurf files, the version-sync rule. `doctor.ps1` was in the same
  state while the handoff tells you to run it out of the profile. Behavior step 5b now enumerates
  `pack/scripts/*.{ps1,py}` and all of `pack/templates`, so a new script or template is covered the
  moment it is created rather than when someone notices.
- **`AI_INSTRUCTIONS.md.template` carries all four refresh trigger phrases.** It listed three of the
  four in `agent-defaults-always.mdc`, so a non-Cursor agent would not have recognised
  **sync agent context**.
- **`.agent-bootstrap.json` no longer claims `docs/AGENT_REFRESH.md`.** Bootstrap never wrote it - the
  brief is generated by `Refresh-AgentContext.cmd` and is only meaningful once there is a real delta,
  so a stub would state nothing while looking authoritative. The manifest now lists only what bootstrap
  actually produced.
- **`PACK_IMPLEMENTER_SPEC.md` no longer contradicts itself.** Its Section 12 header still read
  "Not implemented" and its implementer checklist read as open work, four bumps after both shipped.

---

## 2.22.5 (2026-08-28)

**Handoff documents that contradicted themselves, and the unmirrored-file trap for the third time.**
Prompted by a plain question - is anything still missing from the handoff docs - answered by checking
each claim against the code instead of re-reading the prose.

- **`pack/docs/*.md` and `docs/*.md` are enumerated against `packMirror`** in behavior step 5b. Six
  files were in the state this check already covered for rules and skills: `install.ps1` copies the
  whole tree, so they reach a *fresh* install and are then frozen, because incremental syncs only walk
  manifest paths. An agent reading the installed copy would have been told the context refresh was
  "planned, not built", and `bootstrap-project.ps1` prints a path into the installed `docs\` folder, so
  a user could be sent to a stale `PORTABLE_SETUP.md`. All six are now mirrored, and the check
  enumerates both folders so a new doc is covered the moment it is created. `docs/AGENT_REFRESH.md` is
  excluded by name: it is generated per machine, so mirroring it would push one machine's absolute
  paths into the install.
- **`HANDOFF_NEXT_AGENT.md` joined `maintainerDocSync`** in `docs/VERSION_SYNC.json`. Its version
  cites were hand-maintained, and one had already drifted (the key file map still said 2.22.0). Adding
  it was verified safe first: the sync rewrote exactly that one line and left every historical version
  reference in the narrative alone.
- **Seven stale or self-contradicting claims corrected in the handoff**, each re-checked against code
  rather than assumed: the context refresh described as unimplemented in one section and shipped in
  another; a "still never prunes" note fixed in 2.21.22; a dead-code item deleted in 2.21.19; the MCP
  SDK reported absent after it was installed; `sync-project-rules.ps1` described by its old hardcoded
  rule count; a stated preference of "no install on this machine" that the user had since lifted; and
  no narrative at all for 2.22.1 through 2.22.4.
- **The machine-local rule boundary is now written down.** A rule in the profile that the pack does not
  ship belongs to the *user* - it must not be added to `pack/rules/` and must not be pruned. That
  distinction lived only in `update-agents.ps1` logic and in one chat.

---

## 2.22.4 (2026-08-28)

**The export shipped one machine's identity, and the installer ignored the one override that keeps
tests off a real profile.** Both were found by taking the portability claim literally: export the
pack, unzip it somewhere else, and run it as a receiving machine would.

- **`export.ps1` no longer ships the agent-context stamp.** `docs/AGENT_CONTEXT.json`,
  `docs/AGENT_REFRESH.md` and `docs/AGENT_PASTE.txt` are generated per machine: they record absolute
  paths (the sending drive letter, the sending user profile) and the versions current when they were
  written. A receiving machine inherited a brief telling its agents to read files at paths that do not
  exist there, plus a `previous` state for `refresh-agent-context.ps1` to diff against that belonged
  to another machine. Same reasoning that already excluded `.audit_*`: inherited state is worse than
  no state. The template under `pack/templates/docs/` still ships - that is what bootstrap copies.
- **`install.ps1` honours `AGENT_STARTER_PACK_INSTALL_ROOT`.** Every other script read the override
  through `pack-paths.ps1`; the installer hardcoded `%USERPROFILE%\.cursor`. Asking for a scratch
  destination therefore rewrote the real profile while the *later* steps of the same run reported the
  scratch path - a half-redirect. Rules, skills and `mcp.json` follow the override via
  `Get-AgentStarterPackUserRoot`, so the set moves together.
- **Behavior step 26 now runs a real redirected install.** It asserts the pack tree, rules and
  recorded canonical path land in the scratch destination and that the real profile `.cursor`
  directory is byte-for-byte untouched. Until this fix no test could exercise a full install without
  writing the maintainer's profile.

---

## 2.22.3 (2026-08-28)

**Five copies of the same encoding fix, and no test that the two PowerShell hosts agree.** Raised by a
maintainer whose development machine runs PowerShell 7 while the pack's floor is 5.1: code written on
one host and shipped to the other had produced BOM bugs before. Investigation found the drift was real
but narrower than assumed - and that the pack had no way to detect it.

What the measurements actually showed (worth recording, because the intuitions were wrong):

- **No PowerShell 7-only syntax anywhere** in 47 scripts and templates, and the full behavior suite
  passes under 7. The pack was already cross-version clean by luck, not by test
- **Only encoding truly differs.** `Set-Content -Encoding UTF8` writes a BOM on 5.1, not on 7.
  Dot-assigning a new property onto a `PSCustomObject` throws on *both* hosts, so the mcp.json data
  loss in 2.21.22 was a plain logic bug, not version drift. `ConvertTo-Json` truncates at depth 2 on
  both; 7 merely warns
- **7 is slower for this workload.** A child shell costs ~130 ms on 5.1 and ~250 ms on 7 (the Store
  package alias is not the cause; the real exe measures the same). An audit spawns dozens, so hosting
  the pack on 7 would cost seconds per run and buy nothing. 5.1 stays the host

Changes:

- **One writer.** `Write-Utf8NoBom` now lives in `pack-paths.ps1`, replacing `Write-TextNoBom`,
  `Set-TextNoBom`, a third `Write-Utf8NoBom`, and two inline `UTF8Encoding($false)` writes across 39
  call sites. The copies had already drifted - only one created the parent directory
- **`Add-Utf8NoBomLine`** for the JSONL timing log, which needed append rather than whole-file write
- **`#Requires -Version 5.1` on every script** (12 were missing it). `pack-paths.ps1` is exempt and
  says why: it is dot-sourced
- **Host shell is reported**, by `doctor.ps1` and `check-requirements.ps1`, with a warning when hosted
  on Core that the floor is 5.1. PowerShell 7 is listed as an optional requirement with its winget
  command - never auto-installed, matching the existing policy on runtimes
- **Behavior step 29 (always on)** runs a probe on both hosts: identical writer bytes, no BOM, identical
  parsed JSON. It also fails if a second BOM-free writer or an inline copy reappears, or if any script
  drops its `#Requires`. Skips with a note when only one host exists
- **`-DualShell`** runs the whole suite on the other host (~140s instead of ~70s). Opt-in

Two bugs surfaced while building this:

- **`run_audit_core.ps1` dot-sourced `pack-paths.ps1` inside a function**, which scopes the definitions
  to that function - the shared helpers were invisible in the rest of the file. Moved to script scope
- **The timing-log write was wrapped in an empty `catch {}`**, so the log silently vanished when that
  broke. It now warns; the audit still does not fail on a diagnostic write

## 2.22.2 (2026-08-28)

**The refresh's paste line was hard to copy correctly.** 6a printed it indented inside wrapped console
output, so selecting it dragged in leading spaces and line breaks, and it carried an ISO stamp with
microseconds. A mangled paste is worse than no paste: the agent half-reads it, answers as if it
refreshed, and the session continues on stale rules. Reported from real use - pasted updates "get
hung/misunderstood/or just plain wonky."

- **`docs/AGENT_PASTE.txt`** - the line alone, one line, ASCII only, BOM-free, no trailing whitespace.
  Nothing to select around
- **Clipboard by default.** The refresh puts the line on the clipboard; `-NoClipboard` opts out (tests
  use it, since a suite must not touch the user's clipboard)
- **Console leads with the clipboard state** (`COPIED TO YOUR CLIPBOARD ... press Ctrl+V`, or the file
  path when the clipboard is unavailable), then shows the line unindented between banner rules as
  reference. A clipboard note printed *after* a 380-character line reads as a footnote, and the user
  hand-selects text they already have
- **Line rewritten to be unambiguous.** Minute-precision UTC stamp, `PACK CONTEXT REFRESHED` prefix,
  imperative "Before your next action", absolute paths, and a closing request to reply with both
  version numbers - so a bare "ok" is visibly a failure to read rather than a silent one
- **Behavior step 27 asserts the copy properties**, not just that a line exists: single line, no BOM,
  no stray whitespace, ASCII, versions and absolute path present, and identical to the brief's copy
- **The paste line is pinned as a pointer.** A multi-change refresh must still produce one line under
  600 characters, and the line must not contain any of the per-change prose - that belongs in the brief,
  which the agent opens itself. An update notice that grows an entry per change turns into a document,
  and pasting a document is what makes agents skim it or stall partway through

**Also: `sync-audit-system.ps1` left drift behind on every run.** It mirrored the pack, then ran
doc-version sync - which rewrites `START_HERE.md` and `AUDIT_SYSTEM.md`, both mirrored files. The
install therefore held the pre-sync text and the next verify failed on a tree that had just been
synced, so `run_audit_tests.bat` needed two sync runs after any version bump. Doc sync now runs
*before* the mirror; one run leaves a clean `-VerifyOnly`.

## 2.22.1 (2026-08-28)

**A rule added to the pack reached user profiles but never projects.** `sync-project-rules.ps1`
carried its own hardcoded list of nine rule filenames - the same defect 2.21.21 fixed in `doctor.ps1`,
where a hardcoded list validated 5 of 9 rules, left live on the project-sync path. `install.ps1`
copies the whole `pack/rules` folder, so new rules did land in `%USERPROFILE%\.cursor\rules\`, and
nothing reported that projects were being skipped. Found by adding a tenth rule and watching it not
arrive.

- **`sync-project-rules.ps1` enumerates `pack/rules` now.** The folder is generic-only by policy, so
  everything in it belongs in a project that syncs; an empty folder is an error rather than a silent
  no-op
- **Behavior step 5b runs that sync for real** against a scratch project and requires every rule on
  disk to arrive. Manifest coverage alone could not catch this: the manifest was correct while
  delivery was incomplete, which is exactly the gap that let it survive 2.21.21

## 2.22.0 (2026-08-28)

**Section B could be closed by deleting a folder, so that is what agents did.** Every machine check
in B ended in `- delete`: `Build cruft - dist - delete`, `Cache cruft - ... - delete`. An agent that
read `machineFixesBySection.B`, deleted what it named, and wrote a clean summary had satisfied
everything the machine asked - while never asking whether a reader can tell build output from runtime
user data from a duplicate release copy. Worse, the delete-only framing is misleading: `dist/` comes
back on the next build, so "fixed" was never true. Layout clarity is now reported as **Improve**, in
its own channel:

- **`layoutPolicy` in `AUDIT.config.json`** (optional, **disabled by default**, `MyApp` placeholders
  only) checks for a folder glossary and heading, an in-repo duplicate of a release archive, one
  runtime-data dirname living both beside the source tree and inside the build output, ephemeral dirs,
  and scripts that recreate a path the policy forbids. `layoutPolicy.enabled` joined
  `auditConfigTemplate.requiredKeys`, so template and reference configs cannot drift apart
- **Findings are Improve, with one exception** - build output that is actually **committed to git** is
  a Fix, because that one does break the repo. Nothing deletes, nothing restructures, and the audit
  CLI never asks "want me to clean this up?"
- **`machineImprovesBySection` is a new array in `docs/.audit_agent_manifest.json`**, beside
  `machineFixesBySection`. Sharing the Fix channel is precisely what trained agents to read B as a
  delete list, so Improve lines get their own key and `machineSectionsWithImproves` alongside it
- **`semanticRequireMachineImproveMention`** closes the obvious hole: Fix lines already blocked a
  clean summary, Improve lines blocked nothing, so a layout finding could sit in the manifest while
  the section closed on "Nothing found." The summary must now mention layout or cite a flagged path
- **The skill gained a mandatory §B layout pass** - read the glossary doc, locate build output vs
  runtime data vs archive copy, address `machineImprovesBySection.B`, and it is explicitly forbidden
  to close B with "removed `dist/`" when the glossary and duplicate-copy workflow were never examined.
  `AUDIT.md.template` §B, `AUDIT_SYSTEM.md`, and `AGENT_WORKFLOW.md` carry the same Fix vs Improve
  taxonomy
- **Behavior step 28** creates the layout tree under the fixture, then asserts the findings appear,
  that **none of them landed in Fix**, that `machineImprovesBySection.B` carries them, and that a
  clean §B summary is rejected while a summary naming them passes. The fixture checklist gained a
  §B so the semantic half is exercised rather than skipped
- **Cruft remediation paths were still nested-only.** `Build cruft - app\dist - delete`,
  `Stale files - app\*.tmp`, and `Cache cruft - app\.pytest_cache` hardcoded `app\` - the bug fixed
  elsewhere in 2.21.x but missed in this block, so flat projects (what bootstrap generates) were told
  to delete paths they do not have. They use `$appPrefix` now

## 2.21.23 (2026-08-28)

**Updating the pack changed the disk and reached none of the agents already working.** No chat -
Cursor, Claude, Copilot, or otherwise - reloads its instructions when files change, so a session
opened before an install kept acting on the previous rules with nothing to signal otherwise. The only
answer available was for the user to hand-write what changed, including version numbers they had to
look up. `Refresh-AgentContext.cmd` (wrapping `pack/scripts/refresh-agent-context.ps1`) now syncs a
project and writes what changed as files the agent can read:

- **`docs/AGENT_CONTEXT.json`** - schema-versioned stamp: pack version, audit engine version, the
  installed pack's version when it differs, a `rulesRevision` hash over `pack/rules/*.mdc`, per-layer
  state (`ok` / `updated` / `stale` / `skipped` / `unknown`), and `changedLayers` computed against the
  previous stamp
- **`docs/AGENT_REFRESH.md`** - short brief: stale-chat notice, the files to re-read as absolute
  paths, plain-language change lines, and a paste line at the bottom carrying versions read from the
  pack at generation time, so it cannot cite a number that is already wrong
- **Given a project root it applies the syncs first** - `sync-project-rules.ps1` and
  `sync-audit-system.ps1` - so the brief describes a project that has actually been updated rather
  than one that is merely told about it. Run against the pack repo it skips those (the pack is the
  source) and writes the maintainer variant of the brief, which is the only one that names
  `HANDOFF_NEXT_AGENT.md`; an app brief says explicitly that the handoff is not its file
- **`agent-defaults-always.mdc` gained a six-line trigger** so **refresh pack context** (or *context
  refresh* / *pack update*) sends the agent to the brief without the user pasting anything, and
  `AI_INSTRUCTIONS.md.template` points non-Cursor agents at the same file
- **Bootstrap writes the stub** `docs/AGENT_CONTEXT.json` and lists both artifacts in
  `.agent-bootstrap.json`, so the path exists before the first refresh
- **Overlap with `Update-AgentRules.cmd` is deliberate and split**: that reports what changed in the
  *profile* at install time, this leaves a per-project file that an agent can still read tomorrow

## 2.21.22 (2026-08-27)

**Installing the pack destroyed every MCP server the user already had.** The first real install on a
profile with existing servers found it: `Merge-McpJson` read `mcp.json`, then set the new key with
`$existing.mcpServers."agent-hygiene" = $entry`. Dot-assigning a *new* property on the
`PSCustomObject` that `ConvertFrom-Json` returns throws on Windows PowerShell 5.1, the `catch` read
that exception as "could not parse existing mcp.json", and the rewrite that followed wrote the
freshly built single-server object - so a machine with 13 configured servers came out with one, under
a warning that blamed the user's file. Now `Add-Member -Force` adds the key (it also replaces, so
re-running is idempotent), a genuinely unparseable config is backed up and **left in place** with
nothing registered rather than overwritten, `-Depth` went 6 to 10 so deeply nested server configs
survive the round trip, and the file is written without a BOM.

- **The installer left bytecode in the profile it had just filtered.** 2.21.21 taught `Copy-Tree` to
  skip `__pycache__` and `.pyc`; the install then ran doc sync *out of the installed tree*, which
  regenerated them there. Python bytecode writing is suppressed for those steps and `__pycache__` is
  pruned from the installed tree at the end
- **Behavior step 26 covers the two functions that write to the user profile.** `install.ps1` is the
  one script a test cannot simply run, so both functions are lifted out of the shipped file by AST
  and exercised against scratch paths: pre-existing MCP servers survive with nested config intact,
  the merge is idempotent, an unparseable config is preserved and backed up, the output is BOM-free,
  and the copy filter still excludes artifacts while keeping hidden pack files. Reintroducing the old
  assignment fails the step with the exact PowerShell error as the reason
- **The installer never removed anything, so a dropped file lived in the profile forever** - and a
  rule the pack stopped shipping kept instructing agents in every project on the machine.
  `install.ps1 -Prune` (opt-in; reported either way) removes them. The canonical tree is entirely
  pack-owned, so anything there without a source counterpart is stale; profile rules and skills also
  hold the user's own files, so those are only removed when a **previous install recorded shipping
  them** - `install-manifest.json` now lists the rules and skills each install delivered. With no such
  record, no profile rule or skill is ever a prune candidate. `.tmp` scratch is spared because a
  concurrent run may hold it open. Behavior step 26 asserts the dangerous direction: a rule the user
  added themselves is never a candidate, and files the pack still ships are never candidates
- **Nothing checked shell scripts, and git could re-break the one that exists.** Step 24 scanned
  `.ps1`, `.py`, `.cmd`, and `.bat`, so `install.sh` - fixed in 2.21.21 for having CRLF endings that
  made its shebang unrunnable - was never covered by the check that would have caught it. `.sh` is now
  scanned, a CR in a shell script is a named failure, and a `.gitattributes` pins `*.sh` to LF (with
  `*.cmd` and `*.bat` to CRLF) so a checkout on another machine cannot reintroduce it. Proven by
  converting `install.sh` to CRLF and watching the step fail
- **`Update-AgentRules.cmd` now reports what an update changed** (`pack/scripts/update-agents.ps1`):
  rules, skills, and pack files added or updated by hash, MCP servers configured, files in the
  profile this pack no longer ships (the installer never deletes), then `doctor.ps1` and a sync
  verify, exiting non-zero if either complains. It also prints the line to paste into a chat that is
  already running, which otherwise keeps the old rule text in context

---

## 2.21.21 (2026-08-27)

**A transferred pack could not audit itself, and three checks were scanning nothing:**

- **`export.ps1` shipped a pack with no audit entry points.** The hand-maintained item list had drifted from the manifest: `run_audit.cmd`, `run_audit_tests.bat`, `AGENTS.md`, `scripts\`, `tests\`, and `.cursor\rules\audit.mdc` were all absent, so on the receiving machine the `run_audit.cmd` that every transfer doc tells you to run did not exist. `Test-Path` guarded each copy, so nothing ever failed. The export now verifies the staged tree against `manifest.json` `projectRequired.flatLayout` and throws with the missing paths named; a missing manifest is the loudest case rather than a reason to skip the check, and machine-local leftovers (`.pyc`, `.tmp`, `.audit_*`) are pruned so a receiving machine cannot inherit the sender's test-pass proof
- **The pack's only content rule matched zero files.** `"glob": "*.{md,ps1,mdc,cmd,bat,json,py}"` is shell syntax; `pathlib.rglob` treats it as a literal filename, so the legacy-path scan had never run. Braces are now expanded, and the revived rule found five real hits (all self-referential - the checklist line describing the rule and the config defining it), so it gained an `allowLineRegex` and excludes for generated artifacts. A rule may now declare `requireMatches`, which turns "this glob stopped matching anything" into a Fix; unbalanced braces are always a Fix. It is opt-in because an empty scope is legitimate - a Generic project has no `*.py` for the safety patterns to scan
- **`docs/AUDIT.md` had a reference copy that nothing compared,** and it had drifted 16 lines from the real checklist. `packReferenceConfig` now checks the markdown pair as well as the JSON pair
- **Section N could demand a semantic section that no template ever produced.** The N machine check defaulted to enabled, but N is not a checklist heading, so `--write-template` wrote no N stub: any config that left N alone hit an unfixable Fix the moment git showed a version commit. N is now opt-in, and where it is switched on it joins the required sections so the template stubs it. `fill_pack_semantic_report.py` leaves a required section it has no canned text for unreviewed instead of raising `KeyError`

**Installed and generated files that no check could see:**

- **Two of three skills were outside the manifest.** `install.ps1` `Copy-Tree`s the whole skills folder, so `agent-gui-test-hygiene` and `agent-terminal-hygiene` landed on a fresh install and then went stale forever - the same defect 2.21.19 fixed for four rules, with a step 5b that covered rules only. Step 5b now covers skills too
- **`doctor.ps1` validated 5 of the 9 installed rules** from a hardcoded list. It now enumerates `pack\rules` and `pack\skills`, so a rule cannot be installed and unverified at once
- **`install.ps1` copied the whole source tree into the profile,** including `.git`, a live `.tmp`, `__pycache__`, `.pyc` files, and the source machine's `.audit_*` results - and `Copy-Tree` only ever adds, so they stayed forever. Those are now skipped, and hidden files (the `.cursor` rules the audit requires) are no longer silently dropped
- **`run_audit_core.ps1` read `docs/AUDIT.md` without `-Encoding`,** so PowerShell 5.1 decoded a BOM-less UTF-8 file as ANSI and copied mangled em dashes straight into `docs\.audit_agent_manifest.json` - the brief the next agent reads
- **A non-Cursor bootstrap produced a project that failed its own first audit.** `.cursor\rules\audit.mdc` was written only for Cursor targets while the audit system requires it of every project, so `-Targets Portable`, `Claude`, or `Copilot` opened with a missing-file Fix and a sync drift. The rule is now written for every target. `version-sync.mdc.template` was copied verbatim despite carrying `{{PROJECT_NAME}}` and `{{SOURCE_MODULE}}`, shipping a rule whose frontmatter glob was the literal placeholder text; it now goes through the expanding writer
- **`run_audit_tests.bat` ran the behavior suite twice** (directly, then again inside `verify-audit-system.ps1`), and the pack self-audit made it three times. It now passes `-SkipBehavior` to the second call: the suite runs once in tests and once in the audit's Section L verify, and a full test run dropped from ~86s to ~56s. The fallback to the installed pack also warns instead of silently testing a different engine
- `install.sh` had CRLF line endings, so `#!/usr/bin/env bash\r` made it unrunnable on the Unix systems it exists for; `sync-doc-versions.ps1` had CR-CR-LF throughout; the `.gitignore` snippet merged into every generated project carried a non-ASCII dash

## 2.21.20 (2026-08-27)

**The test-pass proof did not cover the code, so in a git repo a clean audit survived a code change:**

- **`git HEAD` was the whole proof whenever git answered, and HEAD does not move for uncommitted edits.** A generated project was taken to a clean audit, then `def main()` was renamed to `def main_BROKEN()` without committing - same line count - and `run_audit.cmd -FinalizeOnly` still reported `Fix: Nothing found`, exit 0. The strictness was inverted from what matters: a project *without* working git fell back to the tree fingerprint and was policed properly, while an ordinary git repo was not. The first probe of this hid the bug - it ran on removable media where git refuses the repo as dubious ownership, so it silently took the strict path and the gate looked sound
- **The proof is now the content of the audited files, with HEAD prefixed when git answers** (`<sha>+tree:<sha256>`), so an uncommitted edit and a commit each invalidate it. Size and mtime are gone as inputs: mtimes do not survive a copy to another drive - which is how this pack ships - and can be restored, so an mtime proof can be stale and matching at the same time
- **The two implementations were never byte-identical.** PowerShell hashed `FullName|Length|LastWriteTimeUtc.Ticks`, Python hashed `resolved path|st_size|st_mtime_ns`; they agreed only because the wrapper asks Python first and uses its own answer as a fallback. A proof written on one path could never match the other. Both now hash file contents keyed by a lowercased app-relative path, sorted ordinally because `Sort-Object` is culture-aware and Python's `sorted()` is not
- Behavior step 23 git-initializes a probe project, takes it to a clean audit, asserts the recorded proof is commit+content, then makes a line-count-neutral edit and requires finalize to block

**A test runner that ran nothing satisfied the entire test gate:**

- Only the runner's exit code was checked, so replacing a generated `run_tests.bat` with `exit /b 0` printed `Tests: OK` while `tests/test_version_consistency.py` was never executed. `docs/AUDIT.md` already asked a reviewer to confirm the runner covers every test file; `check_test_runner_coverage` now checks that promise, gated by `codeChecks.testRunnerCoverage.enabled`. Globbed and discovered runs (`tests\test_*.py`, `pytest`, `unittest discover`) count as covering everything, and one level of delegation to another in-project script is followed
- It caught the pack's own `run_tests_stub.bat`, which was an instant `exit /b 0` beside two test files - the fixture was modelling the exact defect. The stub now loops `tests\test_*.py`

**One shipped command could stand in for an entire semantic review:**

- `--fill-semantic-fixture-test` marks every checklist section reviewed with `"Nothing found."`, empty evidence, and the `modulesReviewed` and `inventoryAck` values the gate cross-checks - a complete semantic pass in one command, ungated, in every install. It now requires `AUDIT_FIXTURE_TEST=1`, which only the behavior suite sets, and refuses with an explanation otherwise. New behavior step 25 fails if it ever runs without the opt-in

## 2.21.19 (2026-08-27)

**Accuracy of the gate itself. Two checks were lying, and one project audit was doing the pack's work:**

- **No project could pass an audit while reviewing nothing.** Required sections are the union of the checklist sections in `docs/AUDIT.md`, the domain map, `sectionTests`, and semantic hints - and the project template defined none of them, so a Generic project reported a clean audit with an empty gate. The template now ships six real sections (A test harness, B scope, C documentation, D core modules, K security, L agent wiring), and an empty required-section set is a Fix rather than a pass
- **A flat project named `app` audited its parent folder.** PowerShell compares strings case-insensitively, so the nested-layout check in `run_audit.ps1.template` matched `App`, `APP`, and `app`. Nested layout must now be proven: the app root has no `.git`, is named `app`, holds `docs\AUDIT.md`, and its parent is a git repo
- **The stale-semantics check fired on the documented workflow.** `testsPassedAt` was stamped at the *end* of the run - after the semantic template that same run writes - so an auditor who filled that template in place was told their deep scan predated the test pass. Root cause was a shadowed variable: PowerShell names are case-insensitive, so the local `$testsPassedAt = ''` **was** `$script:TestsPassedAt` and silently wiped it. The stamp is taken when the tests pass and is no longer reset
- **A product audit ran the pack's own 23-step behavior suite** (~50s), which bootstraps and audits probe projects *inside the pack folder*, and with step 23 present would re-enter itself. Behavior is the pack's test suite: `verify-audit-system.ps1 -SkipBehavior` is now used for anything that is not the pack, and the engine is still proven there by `audit_code_checks.py --self-test`. A Generic project audit now measures 4s; the suite it used to pull in takes ~33s by itself

**Found by an independent review of this same workstream - the parent-folder bug had a second half:**

- **The Python layer promoted the parent on evidence the wrapper ignored.** `run_audit.ps1.template` was fixed to keep the app root, but `resolve_repo_root()` in `audit_code_checks.py` still climbed whenever the parent held a `README.md` or a `.git` directory. Any flat project under a folder with a README - the normal case for `C:\Projects\MyApp` - had its machine checks scan the project while its git history, test-pass proof, version-doc scan, and evidence paths came from the parent. Both layers now apply the same rule, and `.git` is tested for existence so worktrees and submodules (where `.git` is a file) count
- The wrapper deliberately does **not** pass its repo root to Python. The behavior fixture's bespoke wrapper declares an outer repo root, and forcing that on Python would tie the fixture's test-pass proof to the pack's git HEAD, where edits to fixture code stop invalidating it - which is the staleness detection the fixture exists to test. Agreement is asserted instead: behavior step 23 compares `--print-repo-root` against the wrapper's `Repo:` line, with a `README.md` planted in the probe's parent so the old rule would fail the test
- **`$isPackSelfAudit` matched any repo containing `pack\audit\manifest.json`,** so a product repo that vendors a pack copy at its root would have run the pack's behavior suite. It now asks whether the repo being audited *is* the pack supplying the engine (`RepoRoot` equals the resolved pack root)

**The inventory only saw one folder, so the pack was auditing 38 of its own 3,053 Python lines:**

- **`moduleSearchDirs` was trusted to resolve modules but never scanned.** A project could declare where its code lives and still be inventoried on `scanDir` alone: the pack reported **1 production module / 38 lines** while holding a 2,168-line engine under `pack/scripts`, and the orphan scan could not see an unmapped module there. The domain scan now covers `scanDir` plus `moduleSearchDirs` for inventory, orphan detection, wildcard expansion, and the fingerprint. Projects that leave `moduleSearchDirs` at `["."]` - which is what the template ships - are unaffected. The pack now inventories **5 modules / 3,053 lines**
- **That immediately exposed a third copy of the repo-root rule - the one that writes.** `doc_version_sync.py` carried the old loose version, and `_collect_doc_paths` resolves `scanFiles` and `scanGlobs` against that root, so `apply_version.py sync` in any flat project sitting beside a `README.md` rewrote version cites **in the parent folder**. Reproduced on a generated project: the parent's `v0.0.1` became the project's `v0.1.0`. All three implementations now apply the same rule; behavior step 23 asserts all three agree *and* that the parent file is untouched after two audits
- Two modules surfaced as Section B orphans (`doc_version_sync.py`, `sync_doc_versions.py`) and are mapped to D, the section that requires a reviewed-module list. The test-gap hint that followed is closed by three new tests: repo-root resolution across flat, nested, and own-`.git` layouts; the stale-detect / sync / idempotent round trip; and the `sync_doc_versions.py` CLI contract (7 pack tests, up from 4)
- `docs/AUDIT.md` states the remaining limit plainly: roughly 3,300 lines of pack PowerShell are outside this inventory because the code checks are Python-specific, and are covered by the behavior suite instead. A clean Section B is not "all pack code inspected"

**Found by an adversarial verification pass that re-tested every claim above by running it:**

- **Four installed rules were invisible to sync and verify.** `install.ps1` `Copy-Tree`s the whole `pack/rules` folder, so all nine rules reach a profile, but the manifest listed only five in `packMirror` and `packToUser`. The other four - `generic-phased-feature-design`, `generic-terminal-and-build-hygiene`, `generic-version-sync`, `new-project-bootstrap` - landed once on a fresh install and then went stale permanently: incremental syncs never saw them, write-mode sync did not repair them, and no check reported it. This is the same defect this release fixed for `AGENT_WORKFLOW.md` and `verify-agent-setup.ps1`, left behind on four files. New behavior step 5b fails if any rule on disk is missing from either list, so a tenth rule cannot repeat it
- **The suite was re-adding a UTF-8 BOM to committed fixture code on every run.** `Set-Content -Encoding UTF8` writes a BOM on Windows PowerShell 5.1, and steps 12 and 13 restore tracked fixture files that way after mutating them - which is how `catalog_cache.py` came to be committed with a BOM *under the check meant to prevent exactly that*. Restores now go through a no-BOM writer, and the audit timing log is appended without one
- **Step 24 was not scanning `pack\audit`,** leaving 13 executed files unchecked, including the fixture wrappers this suite runs. It now scans that tree (65 files, up from 50) and includes `.gitignore`, where a BOM silently disables the file's first pattern
- **Flat projects were told to run a path they do not have.** `Add-Fix 'Audit sync drift - run app\scripts\sync_audit_system.cmd'` and `Missing path - app\...` hardcoded the nested-layout prefix, so bootstrap's default layout got unactionable remediation. The prefix is derived from whether the app root differs from the repo root
- The step 23 assertion could not tell "ran verify without `-SkipBehavior`" from "skipped verify entirely," and reported the former for the latter. The behavior probe root is now per-process, so a locked file or a concurrent run no longer fails the step with a message that reads like a product defect
- `.gitignore` shipped with an em dash already destroyed by an ANSI/UTF-8 round trip (`install record -?" written into...`); repaired, and the `description` fields in `pack/audit/manifest.json` and `docs/VERSION_SYNC.json` are ASCII

**Encoding class closed, not just patched:**

- All executed code is ASCII and BOM-free - 37 typographic characters normalized across `audit_code_checks.py`, `run_audit_core.ps1`, `sync-audit-system.ps1`, `pack-paths.ps1`, `verify-*.ps1`, `doc_version_sync.py`, `agent_hygiene_server.py`, `test_pack_audit.py`. This also clears the mojibake PowerShell 5.1 produced when reading BOM-less UTF-8 as ANSI
- Behavior step 24 enforces it for `.ps1`, `.py`, `.cmd`, `.bat`, and executable templates; Markdown keeps its typography

**Behavior suite (now 24 steps):** step 23 walks a generated project through the full documented workflow - bootstrap, machine pass, semantic fill, finalize - and asserts it reaches a clean audit, that a folder named `app` does not hijack the repo root, and that a product audit never runs the pack suite.

**An Improve line nobody could close:** `check_section_n_improve` asked for a release-delta review on every run where git showed recent `VERSION` commits, including runs whose semantic report already contained that review. It now stands down once section N is reviewed with a real summary; `verify_section_n_semantic` still enforces the quality of that review.

**Cleanup:** removed the dead duplicate `sync_doc_versions()` implementation and its four helpers from `audit_code_checks.py` (181 lines; `doc_version_sync.py` owns doc sync). `sync-project-rules.ps1` defaults to `.cursor\rules` instead of the nested-layout `app\.cursor\rules`. Superseded doc-sync bullets in 2.21.10 and 2.21.11 are marked as such.

## 2.21.18 (2026-08-27)

**Generated projects now pass their own audit. Six defects, all found by running bootstrap output instead of reading it:**

- **Every generated project audited its parent folder.** `run_audit.ps1.template` set `$RepoRoot = Split-Path -Parent $AppRoot`, which is only right for the nested `<repo>\app` layout — but bootstrap generates flat projects, where the app root *is* the repo root. A project at `C:\Projects\MyApp` therefore scanned `C:\Projects` for `.md` and `.env` files (sibling projects included), looked for `README.md` one level too high, and passed the wrong `-ProjectRoot` to `sync-audit-system.ps1`, which reported every audit file as drift. The template now keeps the app root and only steps up for a folder literally named `app` holding `docs\AUDIT.md`
- **The semantic gate could never be satisfied without git.** On a full run the test-pass proof was captured in the init phase, *before* the test script ran — and a generated project's test script runs the version/doc sync, which rewrites files the proof covers. With a git repo the proof is a stable HEAD so it never showed; in fingerprint mode (any project before `git init`) the verifier's recompute never matched and the audit reported `Semantic report stale` forever. The proof is now taken after tests pass
- **An empty file set produced a valid-looking proof.** Both fingerprint helpers hashed zero files into `sha256("")` — a constant that matches forever. No files now means no proof
- **Generated tests passed once, then failed on every later audit.** `apply_version.py.template` printed a `→` on the "already synced" path; redirected console output is cp1252, so it raised `UnicodeEncodeError` and failed the whole test step. Executable templates are ASCII-only now (`apply_version.py`, `run_tests.bat`, `build-ci.bat`, `run_tests.generic.bat`, `test_version_consistency.py`); Markdown keeps its typography
- **Domain map: every module looked unmapped.** The heading search matched any line *containing* `## Domain map`, including the template's own prose ("Include a **## Domain map** table..."), so the chunk ended at the next heading and the real table below was never read. The match is anchored to the line start, so trailing text like `## Domain map (example - replace ...)` still works. Also `scanDir` was joined with `-replace '/', '.'` instead of `'\'`, so any nested scan dir resolved to a bogus path
- **The audit created cruft it then reported.** Its own test run left `__pycache__` behind, which the cruft check flagged as a Fix the user could never clear; the test run now sets `PYTHONDONTWRITEBYTECODE`

**Bootstrap output matches the audit it ships with:**

- Writes `README.md` and `VERSION.txt` — both are required by the config it generates, and `VERSION.txt` was checked before the test script that would create it, so run 1 always reported it missing
- Python stack: `sectionTests` maps section D to the generated test file instead of shipping `{}`
- Generic stack: no longer describes a `main.py` it never creates — `versionSync` is null and the example domain-map row is dropped, which was four permanent Fix items on every Generic project
- Removed a duplicate `mcpWiring` key from the config template (JSON kept the last one, so the first was dead)

**`verify-audit-behavior.ps1` step 23 — bootstrap smoke:** generates a Python project and a Generic project, audits the Python one twice (the repeat run is what exposed the encoding crash), and asserts BOM-free output, repo root == app root, no phantom drift, no stale proof, tests still passing on re-run, machine-clean except the auditor's semantic sections, and that nothing was installed. The Generic probe disables `runLegacyVerify`: its audit reaches a complete semantic pass, which would re-enter this suite and recurse without end.

## 2.21.17 (2026-08-27)

**Dependencies are checked and named, not discovered by failure:**

- **`pack/scripts/check-requirements.ps1`** + **`Check-Requirements.cmd`** — environment preflight that runs from the pack folder with no install. Reports PowerShell, Python 3.8+, the `py -3` launcher, pip, `mcp`, and git as OK / MISSING (required) / WARN (optional), each with the exact install command. `-Fix` installs the Python packages; `-Json` for agents and `doctor.ps1`; `-PythonCommand` probes a non-PATH interpreter
- Required vs optional is explicit: without `mcp` the MCP tools are unavailable but audits and bootstrap work; without git the audit uses a file-tree fingerprint for test-pass proof
- Proof over presence — the preflight runs `audit_code_checks.py --self-test`, since an interpreter on PATH is not evidence the engine works on this machine
- **`'py -3' launcher` is its own required row** — a machine with only `python.exe` passed a naive Python check and still could not run `run_audit.cmd`, because every `.cmd` in the pack and in generated projects calls `py -3`
- **`install.ps1`** — preflight first, stops on a missing required item (`-SkipPreflight` to override); **`bootstrap-project.ps1`** warns; **`doctor.ps1`** delegates instead of keeping its own check
- **`doctor.ps1` false positive fixed** — it tested `import mcp`, which succeeds from the pack root because the pack's own `mcp\` folder becomes a namespace package. The probe now imports `mcp.server.fastmcp` (what the server needs) from outside the pack folder
- **`tests/test_pack_audit.py`** — runs standalone (`py -3 tests\test_pack_audit.py`) and is wired into **`run_audit_tests.bat`**. It was pytest-only, so nothing ever ran it while the audit inventory counted it as coverage; the pack now has no test dependency the preflight does not check
- **`verify-audit-behavior.ps1`** — steps 21 and 22 cover the preflight (JSON shape, required/optional split, missing-interpreter exit code and install hint, fastmcp probe) and the standalone pack tests

**Three defects found by actually bootstrapping a project and running its audit:**

- **BOM crash — every bootstrapped project's first audit failed.** `bootstrap-project.ps1` wrote files with `Set-Content -Encoding UTF8` (a BOM on Windows PowerShell 5.1) while `audit_code_checks.py` read them as plain `utf-8`, so `load_config` died with `Unexpected UTF-8 BOM` before any check ran. Reads now use `utf-8-sig` (`audit_code_checks.py`, `doc_version_sync.py`, `fill_pack_semantic_report.py`) and bootstrap writes plain UTF-8 via `Write-TextNoBom` — a BOM at the top of a generated `.cmd` was a hazard too
- **Auditing a project installed the pack.** With `syncAndVerify.autoFixDrift` enabled, a project's `run_audit.cmd` ran `sync-audit-system.ps1` in write mode, which *created* `%USERPROFILE%\.cursor\AgentStarterPack` plus profile `rules\` and `skills\`. The mirror is now skipped whenever no install exists, in write mode as well as `-VerifyOnly`: keeping an install aligned is this script's job, creating one is `install.ps1`'s. Locked in by behavior step 20 (`sync never creates an install`)
- **`bootstrap-project.ps1`** — creates the target folder instead of failing with a raw `Resolve-Path` error, and no longer prints a bare `True` after every generated file (the template writers returned a value no caller consumed)

## 2.21.16 (2026-08-27)

**Mirror direction is now tested, not just documented:**

- **`verify-audit-behavior.ps1`** — new step 20 builds a miniature pack plus a scratch install target under `.tmp/` and asserts: a newer installed file loses to the source pack, an installed-only file never lands in the source pack, `-VerifyOnly` reports drift without copying, and `-PullFromInstalled` still recovers installed edits. Nothing in the suite exercised the mirror before, because it needs an install to exist
- **`pack-paths.ps1`** — **`AGENT_STARTER_PACK_INSTALL_ROOT`** redirects the install *destination* (self-tests, relocated profiles); **`Get-AgentStarterPackUserRoot`** derives the profile rules/skills folder from it, so an override moves the whole mirror instead of half of it
- **`sync-audit-system.ps1`** — a manifest-listed file present only in the installed copy is now **removed** from it rather than skipped forever. Skipping (2.21.15) left `-VerifyOnly` permanently red and `-AutoFix` unable to converge; the source pack is authoritative about deletions too. `-PullFromInstalled` still copies it back instead
- Docs — `AUDIT_SYSTEM.md` mirror-direction section; dropped stale "newer file wins" and Desktop-as-canonical wording

## 2.21.15 (2026-08-27)

**Pack folder travels, install does not (removable-media safety):**

- **`sync-audit-system.ps1`** — mirror is now one-way, source pack → installed. A stale machine-local install can no longer overwrite the pack folder, and files deliberately deleted from it are no longer resurrected. New **`-PullFromInstalled`** restores the old newest-wins reconcile for recovering edits made inside `%USERPROFILE%\.cursor\AgentStarterPack`
- Rationale: mtime comparison across filesystems is unreliable — removable exFAT stores local time, NTFS stores UTC — so "newest wins" could pick the wrong side on a USB-hosted pack
- **`bootstrap-project.ps1`** — warns when the pack is not installed on this machine, because the generated project's MCP path then points at the pack folder's current location (breaks on drive-letter change or unplug)
- Docs — `PORTABLE_SETUP.md` USB workflow and per-machine install model; `AGENT_STARTER_PACK_ROOT` documented as a session override, not a permanent setting for removable drives

## 2.21.14 (2026-08-27)

**Portable pack root (runs from any drive or folder):**

- **`pack/scripts/pack-paths.ps1`** — resolves the pack the script runs from (`Get-SourceAgentStarterPack`) before env vars, the installed copy, or legacy Desktop paths; adds `Test-AgentStarterPackRoot` / `Test-AgentStarterPackInstalled`
- **`sync-audit-system.ps1`** — source pack replaces "Desktop pack"; a machine with no installed copy reports one actionable `[INFO]` instead of per-file drift
- **`verify-audit-system.ps1`** — `run_audit_core.ps1` accepted from the project, resolved pack, or installed copy
- **Project templates + behavior fixture** — `AGENT_STARTER_PACK_ROOT` honored, then the profile install; `run_audit.ps1.template` no longer needs `pack-paths.ps1` beside it (it was never copied into projects)
- **`run_audit_core.ps1`** — test-pass proof comes from `audit_code_checks.py` first, so the recorded proof matches the one semantic freshness recomputes; fixes finalize being reported stale when the app root sits inside an outer git repo

## 2.21.13 (2026-08-27)

**Generic-only pack (no product-specific references):**

- Removed product-specific audit reference configs — replaced with **`AUDIT.config.app.reference.json`** / **`AUDIT.app.reference.md`**
- **`manifest.referenceProject`** — no default external repo path; flat layout paths; env **`AUDIT_REFERENCE_PROJECT_ROOT`**
- **`verify-agent-setup.ps1`** — `-ReferenceProjectRoot` for optional app checks; removed product-specific file checks
- **`Update-AgentRules.cmd`** — install + optional `%1` ProjectRoot (no hardcoded app paths)
- Docs, templates, rules — generic placeholders (`MyApp`, `main.py`, behavior-fixture) only

## 2.21.12 (2026-08-26)

**Doc sync = build pipeline (decoupled from audit):**

- **`docs/VERSION_SYNC.json`** — build config for version + doc cite sync (not `AUDIT.config.json` codeChecks)
- **`pack/scripts/doc_version_sync.py`** + **`sync_doc_versions.py`** — standalone; no `audit_code_checks.py` on build path
- **`apply_version.py sync`** → version + docs; wired in **`run_tests.bat`** / **`build_ci.bat`** templates
- Bootstrap copies **`doc_version_sync.py`** + **`VERSION_SYNC.json`** to every project

## 2.21.11 (2026-08-26)

**App doc version sync (all bootstrapped projects):**

> **Superseded by 2.21.12:** doc sync moved to the build pipeline (`docs/VERSION_SYNC.json` +
> `doc_version_sync.py`). `docVersionSync` in `AUDIT.config.json` is a disabled fallback - do not
> re-enable it, and do not read the bullets below as the current model.

- **`appVersionDocs`** in `AUDIT.config.json` — sync `vX.Y.Z` in README/AGENTS/docs from `versionSync` canonical
- **Bootstrap template** — `docVersionSync` + `appVersionDocs` **enabled by default**
- **`apply_version.py`** — after sync/bump, runs `--sync-doc-versions` via installed pack
- **`scripts/sync_doc_versions.cmd.template`** — manual doc sync for Python projects
- Audit **Improve** — `check_app_version_docs_improve` when sync was skipped

## 2.21.10 (2026-08-26)

**Automated maintainer doc version sync:**

> **Superseded by 2.21.12:** `audit_code_checks.py` is no longer on the doc-sync path; its duplicate
> `sync_doc_versions()` body was removed in 2.21.19. Use `Sync-DocVersions.cmd` or
> `apply_version.py sync`.

- **`pack/scripts/sync-doc-versions.ps1`** + **`Sync-DocVersions.cmd`** — align version cites in README/INSTALL/START_HERE/AUDIT_SYSTEM/etc. from root `VERSION` + `manifest.json`
- **`audit_code_checks.py`** — `--sync-doc-versions` / `--verify-doc-versions` (uses `auditVersionDocs`, `packVersionDocs`, `docVersionSync` in `AUDIT.config.json`)
- **`install.ps1`**, **`sync-audit-system.ps1`** — run doc sync when `docVersionSync.enabled`
- **`generic-agent-doc-hygiene.mdc`** — run sync after version bumps; enable `docVersionSync` in project config

## 2.21.9 (2026-08-26)

**Agent doc hygiene + recommendation discipline:**

- **`pack/rules/generic-agent-doc-hygiene.mdc`** — read existing rules/`AGENTS.md` before adding agent docs (all projects via `install.ps1`)
- **`agent-defaults-always.mdc`** — pointer to generic-agent-doc-hygiene
- **`sync-project-rules.ps1`** — includes generic-agent-doc-hygiene in generic rule set
- **`.cursor/rules/agent-recommendation-discipline.mdc`** — scope before execute, install callout, rule layers, script path defaults
- **`verify-agent-setup.ps1`** — pack-only by default; `-ReferenceProjectRoot` optional for app checks; no hardcoded external defaults

## 2.21.8 (2026-08-25)

**Pack ↔ project sync (no forked generic rules):**

- **`pack/docs/PACK_MAINTENANCE.md`** — where to edit; generic vs project-only rules; drift checks
- **`pack/scripts/sync-project-rules.ps1`** — one-way copy `pack/rules/` → project `app/.cursor/rules/` (+ `-VerifyOnly`)
- **`full-paths-in-chat.mdc`** — examples generalized (no product-specific paths in pack)

## 2.21.7 (2026-08-25)

**Full paths in chat (always-on rule):**

- **`pack/rules/full-paths-in-chat.mdc`** — new canonical rule; `alwaysApply: true`
- **`agent-defaults-always.mdc`** — Chat paths pointer to `full-paths-in-chat.mdc`
- **`doctor.ps1`** — verifies `%USERPROFILE%\.cursor\rules\full-paths-in-chat.mdc` after install
- **`START_HERE.md`** — pre-flight step 8 (full absolute paths in chat)
- **`manifest.json`** — `packMirror` + `packToUser` include `full-paths-in-chat.mdc`

## 2.21.6 (2026-08-17)

**Final maintainer drift checks:**

- **`changelogVersionDocs`** — CHANGELOG.md latest release vs root `VERSION`
- **`mcpWiring`** — mcp.json, requirements pin, Python `import mcp` (section G)
- **`run_audit_core.ps1`** — Improve when verify-audit-system skipped (semantic/sync gates)
- **`AUDIT.config.json.template`** — disabled stubs for pack-only `codeChecks` keys

## 2.21.5 (2026-08-17)

**Maintainer drift Improve checks (pack self-audit):**

- **`packVersionDocs`** — README/INSTALL/START_HERE vs root `VERSION`
- **`auditVersionDocs`** — extended scan to `pack/docs/README.md`, `AGENT_WORKFLOW.md`
- **`packReferenceConfig`** — `docs/AUDIT.config.json` must match `AUDIT.config.pack.reference.json`
- **`installedVsSource`** — workspace vs `~/.cursor/AgentStarterPack` manifest/file drift
- **Section N** enabled for pack — git hints on VERSION/changelog/manifest edits

## 2.21.4 (2026-08-17)

**Pack root resolution (Fix):**

- **`run_audit_core.ps1`** — when `AppRoot` is the pack repo (`install.ps1` + `pack/audit/manifest.json`), use it for `audit_code_checks.py` and sync/verify instead of always preferring `~/.cursor/AgentStarterPack`

## 2.21.3 (2026-08-17)

**Maintainer doc drift (Improve):**

- **`auditVersionDocs`** in `AUDIT.config.json` — machine **Improve** when README/INSTALL/START_HERE/AUDIT_SYSTEM cite an audit-engine version that does not match `pack/audit/manifest.json`
- Pack self-audit reference config enables this check

## 2.21.2 (2026-08-17)

**Pack self-audit:**

- Root **`docs/AUDIT.md`** + **`docs/AUDIT.config.json`** — full machine + semantic workflow on AgentStarterPack repo
- **`run_audit_tests.bat`** — `verify-audit-behavior.ps1` + `verify-audit-system.ps1` as product test gate
- **`run_audit.cmd`** + **`scripts/*`** + **`.cursor/rules/audit.mdc`** — same three-step auditor workflow as products
- **`tests/test_pack_audit.py`** — section test hook for engine smoke
- **`syncAndVerify`** enabled — self-audit run also checks pack mirror drift

## 2.21.1 (2026-08-16)

**Template drift guard:**

- **`AUDIT.config.json.template`** — full 2.21.0 `codeChecks` keys for new projects
- **`manifest.auditConfigTemplate.requiredKeys`** — `verify-audit-system.ps1` fails if template or app reference missing keys
- **`AGENT_WORKFLOW.md`** — pre-flight checklist: template + reference + manifest keys stay in sync

## 2.21.0 (2026-08-16)

**Complete-audit anti-gaming (items 1–13):**

- **Orphan scan** — disk→map: unmapped `app/*.py` → Section B Fix
- **Expanded domain map** — `docs/.audit_domain_expanded.json` resolves wildcards (`gui_*`, etc.)
- **`modulesReviewed[]`** — semantic verify requires every D–K module listed
- **Semantic freshness** — `generatedAt` vs `testsPassedAt`; `testsGitHead` must match manifest
- **Inventory** — `docs/.audit_inventory.json` auto-written; Section B `inventoryAck` must match
- **LOC improve** — modules over threshold → machine Improve by section
- **Dead code hints** — optional unused-import scan → Improve
- **Test gap hints** — modules not referenced in tests → Improve
- **Repo root paths** — Section B verifies README, PROJECT_LAYOUT, etc.
- **`audit_allowlist.json`** — documented `except: pass` lines skip static check
- **Audit receipt** — `docs/.audit_receipt.json` on successful finalize
- **Tree drift block** — semantic stale when source changed since test pass
- **Sync AutoFix** — `sync-audit-system.ps1 -AutoFix` on drift when `autoFixDrift` enabled

## 2.20.0 (2026-08-09)

**Closed remaining workflow gaps (no deferrals):**

- **Tree fingerprint** — no-git repos store `testsGitHead: tree:…` (SHA256 of test script + domain-map sources + audit config); finalize detects source changes without git
- **Legacy `__no_git__` rejected** — forces one fresh pass 1 to pick up tree fingerprint
- **Audit phase timing** — `docs/.audit_timing.jsonl` appended each run (phases: tests, code_checks, semantic, sync_verify, totalSeconds)
- **Behavior fixture `run_tests_stub.bat`** — instant pass 1 for acceptance tests
- **Behavior steps 18–19** — full auditor E2E (pass 1 → semantic → finalize exit 0) + timing log verification
- **`AUDIT.md.template`** — three-step workflow for new projects
- **Gitignore / Section L** — `docs/.audit_timing.jsonl` in artifact list (template + fixture + bootstrapped apps)

## 2.19.0 (2026-08-09)

**Gaps found in follow-up review (not caught by 2.18.0 verify alone):**

- **FinalizeOnly wiped `testsGitHead`** — code-check manifest rewrite dropped test-pass proof before `Update-ManifestMachineFixes`; finalize could not be repeated and broke step 3 economics
- **Git HEAD lookup** — finalize gate now uses **`RepoRoot`**, not parent of app folder (behavior fixture path was wrong)
- **No-git repos** — when git unavailable, step 1 stores `testsGitHead: __no_git__` so finalize works; documented limitation (cannot detect tree changes without git)
- **Behavior step 17** — manifest proof preserved across FinalizeOnly
- **Doc drift** — `audit.mdc`, `audit-protocol.mdc`, `agent-defaults-always.mdc`, reference app `AGENTS.md` / `AUDIT.md` aligned to three-step workflow

## 2.18.0 (2026-08-09)

**Process gap (why live audit exposed workflow bugs we missed):** verification targeted `verify-audit-system.ps1` + behavior fixture — not end-to-end **auditor economics** (double full test run, who owns semantic report). Fixed in this release.

- **`-FinalizeOnly` / `finalize_audit.cmd`** — step 3: skip tests when manifest has `testsPassedAt` + `testsGitHead` and HEAD unchanged; still runs machine + semantic verify + harness
- **Auto-write semantic template** after machine pass when file missing
- **`AGENT_WORKFLOW.md`** — one audit two commands; artifact ownership table
- **Skill rewrite** — three-step workflow; finalize as completion gate
- **Behavior step 16** — finalize blocked without manifest test proof

## 2.17.0 (2026-08-09)

- **Section L harness verify on complete pass** — `runLegacyVerify: true`; `verify-audit-system.ps1` runs only when semantic verify **and** sync drift both pass (skipped otherwise with explicit reason)
- **Docs aligned** — `AUDIT.md` L + machine layer table; `AGENT_WORKFLOW.md` prerequisites table (what unlocks harness verify vs product Fix lines)
- **Opening banner** — `run_audit_core` header matches "machine + semantic gate"

## 2.16.0 (2026-08-08)

Optional hardening from live-audit follow-up:

- **Behavior steps 14–15** — `auditGateFixes` manifest shape; gate fix patterns not bucketed under L
- **Domain map dedupe** — duplicate module names in a row collapsed (self-test)
- **Stale logs → Fix** — aligned with cache cruft (Section B machine layer)
- **Semantic guidance** — printed on any semantic verify failure (not only missing file)
- **Skip verify-audit-system** — when any `^Semantic report` fix exists (broader than missing-only)
- **Manifest** — initial write includes empty `auditGateFixes: []`; invalid semantic JSON → gate not L

## 2.15.0 (2026-08-08)

Live product audit hardening (reference app run):

- **`exec-call` pattern** — `(?<!\.)exec\(` excludes Qt `.exec()` false positives
- **`auditGateFixes`** in manifest — global blockers (semantic missing, incomplete audit) no longer mapped to Section L
- **Semantic missing guidance** — `run_audit_core` prints template cmd + section count + verify/re-run steps
- **`runLegacyVerify` default false** — full `verify-audit-system` skipped during product audit unless enabled; also skipped when semantic gate incomplete
- **Manifest** — copies `machineFixesBySection` from code-check JSON; merges at exit via `Update-ManifestMachineFixes`
- **Cache cruft** — `__pycache__` / `.pytest_cache` promoted to **Fix** (was Improve)
- **Report banner** — "machine + semantic gate"; ASCII hyphen for console encoding

## 2.14.0 (2026-08-08)

- **`domainMap.moduleSearchDirs`** — domain map module existence checks search extra dirs (e.g. `scripts/`) before flagging missing
- **Skill** — documents **`machineSectionsWithFixes`** quick scan in manifest

## 2.13.2 (2026-08-08)

- **Domain map module check** — runs when `domainMap` config is absent (behavior fixture + minimal projects)
- **Behavior step 2** — `$null -eq` for empty `machineSectionsWithFixes` array

## 2.13.1 (2026-08-08)

- **Behavior fixture in `packMirror`** — stub domain modules + config synced Desktop ↔ installed (fixes behavior steps 8/10 drift)
- **Behavior step 12** — uses temporary missing `catalog_cache.py` (not forbidden rule on non-checklist section L)
- **Behavior step 3 cleanup** — removes stale `.audit_agent_manifest.json` after SkipTests probe

## 2.13.0 (2026-08-08)

- **`machineSectionsWithFixes`** — sorted section letters in JSON output + agent manifest (quick scan for agents)
- **Section L gitignore check** — `gitignoreAuditArtifacts` in config; blocks committing `.audit_*` reports
- **Static patterns** — optional `allowLineRegex` per rule; template adds `yaml.load` / `pickle.loads` (section K)
- **Reference app config** — L requires `build_ci.bat` phrase in AGENTS.md (via existing agentsMd list expansion in reference project)

## 2.12.0 (2026-08-08)

- Semantic verify reads **`machineFixesBySection`** from manifest (merged with live machine checks) when blocking clean summaries

## 2.11.0 (2026-08-08)

- **`machineFixesBySection`** in agent manifest — per-section machine fix list; semantic report cannot claim clean when populated
- **`run_audit_core.ps1`** merges all machine Fix lines into manifest before exit
- **Section B** — optional `onedriveDoc` path check in config
- Semantic template instructions reference `machineFixesBySection`

## 2.10.0 (2026-08-08)

- **Domain map module existence** — reverse check: every concrete `*.py` in domain map must exist on disk (sections D–K)
- **Section test paths** — missing `sectionTests` files prefixed with section letter (feeds semantic vs machine alignment)
- **Section K** — static pattern for possible hardcoded credentials

## 2.9.0 (2026-08-08)

- **Semantic vs machine alignment** — semantic report cannot say "Nothing found." for a section when machine checks already flagged that section (`semanticBlockCleanWhenMachineFails`)
- Refactored machine fix collection via `collect_code_machine_fixes()` (shared by verify + main)

## 2.8.0 (2026-08-08)

- **Sync newer-wins** — `sync-audit-system.ps1` reconciles Desktop ↔ installed by **newer mtime** when hashes differ (fixes stale Desktop overwriting installed edits)
- **Section C machine check** — packaging files, bundled runtime when dist exists, forbid duplicate root DebuggingTools
- **Section B machine check** — `layoutRequiredPaths` vs PROJECT_LAYOUT
- **Section K static patterns** — `eval(`, `exec(`
- **verify-audit-system** — fails if `AUDIT_SYSTEM.md` / changelog version ≠ manifest
- **Behavior steps 2 + 11** — machineCoverage `agentFocus` / `machineCheckCount` shape

## 2.7.0 (2026-08-08)

- **`run_audit.cmd` requires semantic report** — after full tests pass, `run_audit_core.ps1` runs `--verify-semantic-report`; missing/invalid report fails the audit
- Config: `semanticReportRequiredInRunAudit` (default true)
- **Expanded `machineCoverage`** — maps all enabled config capabilities per section; adds `machineCheckCount` + `agentFocus` hints
- **Section F machine check** — AGENTS.md portable-first policy phrases
- **Section M HTML scan** — stale path patterns in `docs/*.html` mockups
- **Section K static patterns** — `subprocess shell=True`, `os.system(`

## 2.6.0 (2026-08-08)

- **Evidence-required semantic schema** — each section has `evidence[]` (`type` + `ref`); verify checks array shape and that `file`/`test` refs exist
- Config: `semanticReportRequireEvidence`, `semanticReportEvidenceMinWhenNotClean`, `semanticReportEvidenceRequireFileWhenNotClean`
- **Section M machine check** — `sectionMachineChecks.M` flags hardcoded `vX.Y.Z` in docs when `versionSync` canonical differs
- Behavior self-test step 10: evidence validation
- Multi-agent consensus — **not planned** (explicitly scrapped)

## 2.5.0 (2026-08-08)

- **Semantic cite validation** — non-clean summaries must include file/behavior cites or verify fails
- **Section L machine checks** — forbidden rules, duplicate skill, AGENTS.md phrases
- **Section N git hint** — recent VERSION commits block clean "Nothing found." in semantic report
- **machineCoverage** in agent manifest — maps checklist bullets to machine vs semantic
- Template scripts: `verify_semantic_audit.cmd`, `write_semantic_audit_template.cmd`

## 2.4.0 (2026-08-08)

- **Full A–N manifest** — parsed from `AUDIT.md` checklist headings + config hints + domain map
- **Machine-verifiable semantic report** — `docs/.audit_semantic_report.json` + `verify_semantic_audit.cmd`
- **`-SkipTests` lightweight** — skips import smoke/static scans; still fails incomplete
- Reference app `semanticReviewHints` extended to sections A–C, L–N

## 2.3.0 (2026-08-08)

- **Loop-back protocol for all projects** — `loop-back-protocol.mdc` (alwaysApply) + generic section in `AGENT_WORKFLOW.md`
- Repeat errors / same questions → re-read workstream start, validate state, diff intent vs reality; not audit-only
- Fix/Improve report format remains **audit-only**; other projects use project-appropriate format

## 2.2.0 (2026-08-08)

- Added **`AGENT_WORKFLOW.md`** — pre-flight, gap = Fix/Improve only, loop-back protocol
- Added **`AUDIT_SYSTEM_CHANGELOG.md`** (this file) — settled decisions log
- Skill + rules: any gap (process, coverage, semantic, tooling) → **Fix** (remove) or **Improve** (mitigate); no third category
- Loop-back: repeated “still broken” / “anything else” → re-read thread start + this changelog + run verify before editing

## 2.1.0 (2026-08-08)

- **One standard only:** full `run_audit.cmd` — never `-SkipTests` for an audit
- Fixed JSON parse in `run_audit_core.ps1` (multi-line output from `audit_code_checks.py`)
- Fixed domain-map parser for multi-module table rows
- Agent manifest = union of domain map + `sectionTests` + `semanticReviewHints`
- Added `verify-audit-behavior.ps1` + `pack/audit/behavior-fixture/`
- Removed orphan `pack/templates/AUDIT.md.template`; canonical stub: `pack/templates/docs/AUDIT.md.template`
- Added `sync_audit_system.cmd.template` to manifest push list
- Removed dead config `runSectionTestsWhenSkipFull`
- Skill: no `-SkipTests` loophole; cite every manifest section in report
- `install.ps1`: do not copy `agent-code-audit` skill into projects

## 2.0.0

- Manifest-driven sync (`pack/audit/manifest.json`)
- Replaced Phase A/B + add-ons menus with Fix + Improve only
- `AUDIT.config.json` machine checks + `audit_code_checks.py`
- Forbidden: overlays, `code-audit-checklist.mdc`, `run_tests_with_timeout.bat`

## 1.4.0 and earlier (deprecated)

- Phase A/B protocol, add-ons menus, project overlays — **removed**, do not restore

---

## How to add an entry

```markdown
## X.Y.Z (YYYY-MM-DD)

- What changed and **why** (one line per decision)
- Breaking changes for agents or projects
```

Then: `sync-audit-system.ps1` → `verify-audit-system.ps1` exit 0.
