# Audit system changelog

Decisions already made — **do not re-debate**. Before changing audit design, read this + `AUDIT_SYSTEM.md` + `AGENT_WORKFLOW.md`.

Bump **`pack/audit/manifest.json`** `"version"` when you change synced audit files. Add an entry here in the same commit/sync.

---

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
- **`manifest.auditConfigTemplate.requiredKeys`** — `verify-audit-system.ps1` fails if template or BSOD reference missing keys
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
- **Gitignore / Section L** — `docs/.audit_timing.jsonl` in artifact list (BSOD + template + fixture)

## 2.19.0 (2026-08-09)

**Gaps found in follow-up review (not caught by 2.18.0 verify alone):**

- **FinalizeOnly wiped `testsGitHead`** — code-check manifest rewrite dropped test-pass proof before `Update-ManifestMachineFixes`; finalize could not be repeated and broke step 3 economics
- **Git HEAD lookup** — finalize gate now uses **`RepoRoot`**, not parent of app folder (behavior fixture path was wrong)
- **No-git repos** — when git unavailable, step 1 stores `testsGitHead: __no_git__` so finalize works; documented limitation (cannot detect tree changes without git)
- **Behavior step 17** — manifest proof preserved across FinalizeOnly
- **Doc drift** — `audit.mdc`, `audit-protocol.mdc`, `agent-defaults-always.mdc`, BSOD `AGENTS.md` / `AUDIT.md` aligned to three-step workflow

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

Live product audit hardening (BSOD reference run):

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
- **BSOD config** — L requires `build_ci.bat` phrase in AGENTS.md (via existing agentsMd list expansion in reference project)

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
- BSOD `semanticReviewHints` extended to sections A–C, L–N

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
