# Audit system (starter pack 2.22.43 — manifest-driven)

**One audit = closed scope.** Two report sections: Fix and Improve. **One standard:** full `run_audit.cmd` — never `-SkipTests` for an audit.

Every audit-related file is listed in **`pack/audit/manifest.json`**. Sync and verify use that manifest — no manual file lists.

**After any audit-system edit:** run `sync-audit-system.ps1` then `verify-audit-system.ps1` (exit 0). Do not hand-copy pack files between the pack folder / installed / user mirrors.

---

## Architecture

```
docs/AUDIT.md           Human checklist (the sections that file defines) + domain map
docs/AUDIT.config.json  Machine checks (paths, patterns, domain map rules)
run_audit.ps1           Thin wrapper → run_audit_core.ps1 (starter pack)
run_audit_core.ps1      Generic engine (all projects)
audit_code_checks.py    Import smoke, static patterns, agent manifest JSON
manifest.json           Every file that must stay in sync
sync-audit-system.ps1   Manifest-driven copy + hash verify (one-way: source pack -> installed)
verify-audit-system.ps1 Wiring + drift + behavior self-test
verify-audit-behavior.ps1  Fast behavioral checks (no product test suite)
```

**New project:** copy templates from `pack/templates/docs/` → customize `AUDIT.md` + `AUDIT.config.json` → `install.ps1 -Scope Project`.

**Optional reference application:** after audit changes in a mature bootstrapped app, `-PushFromProject -ProjectRoot …` updates pack templates and `AUDIT.config.app.reference.json`.

---

## Canonical sources (update order)

| Priority | Location |
|----------|----------|
| 1 | The pack folder you edit — any drive, folder, or removable disk |
| 2 | `%USERPROFILE%\.cursor\AgentStarterPack\` (install.ps1) |
| 3 | `%USERPROFILE%\.cursor\rules\` + `\skills\` |
| 4 | Each project's `docs/AUDIT.md` + `docs/AUDIT.config.json` |

Do **not** duplicate `agent-code-audit` skill in projects — use pack skill + project `audit.mdc`.

## Product audit workflow (auditor-facing)

One audit of the product — **not** two test runs unless git HEAD or source tree changed:

1. **`run_audit.cmd`** — full tests + machine layer; manifest + semantic template; appends **`docs/.audit_timing.jsonl`**
2. **Auditor** — fill `docs/.audit_semantic_report.json`; **`verify_semantic_audit.cmd`**
3. **`finalize_audit.cmd`** — semantic + harness verify; skips tests when manifest `testsGitHead` matches

### What the test-pass proof covers

`testsGitHead` is a hash of the **contents** of the audited files — the test runner, `docs/AUDIT.config.json`, `docs/AUDIT.md`, and production code across `scanDir` + `moduleSearchDirs` — recorded as `tree:<sha256>`, with the commit prefixed as `<sha>+tree:<sha256>` when git answers.

Both halves matter:

- **HEAD alone is not a proof.** It does not move for uncommitted edits, so a project could pass an audit, change code without committing, and keep reporting the pass. It stays as a prefix because a commit can touch files the fingerprint's globs never reach.
- **Size and mtime are not inputs.** They do not survive a copy to another drive — this pack ships on removable media — and they can be restored, so an mtime proof can be stale and matching at the same time.

`Get-AuditTreeFingerprint` (`run_audit_core.ps1`) and `compute_tree_fingerprint` (`audit_code_checks.py`) must produce the identical string; PowerShell asks Python first and only falls back to its own copy. Keys are lowercased app-relative paths sorted **ordinally** — `Sort-Object` is culture-aware and Python's `sorted()` is not.

### The tests gate trusts the runner, so the runner is checked

A runner that exits 0 without running anything used to satisfy the gate on its exit code alone. `codeChecks.testRunnerCoverage` requires every `tests/test_*.py` to be named by the test script, or covered by a glob or discovery (`tests\test_*.py`, `pytest`, `unittest discover`); one level of delegation to another in-project script is followed.

`--fill-semantic-fixture-test` marks every section reviewed with no findings — a whole semantic pass in one command. It requires `AUDIT_FIXTURE_TEST=1`, which only `verify-audit-behavior.ps1` sets.

Behavior acceptance: **`verify-audit-behavior.ps1`** steps 18–19 (full pass 1 → semantic → finalize exit 0 + timing log).

### Code that writes to the user profile

`install.ps1` cannot be run by a test — it would install the pack. Step 26 lifts `Copy-Tree` and `Merge-McpJson` out of the shipped file by AST and runs them against scratch paths, because the parts of the pack that touch `%USERPROFILE%` are otherwise verified only by reading them. That is how the MCP merge was found to delete every pre-existing server (see 2.21.22).

### Layout findings are Improve, and they have their own channel

Section B's machine checks were delete-only (`Build cruft - dist - delete`), so an agent that read `machineFixesBySection.B`, deleted what it named, and closed the section had done everything the machine asked while never looking at whether the tree makes sense. Optional `layoutPolicy` in `AUDIT.config.json` (disabled by default) adds checks for a folder glossary, an in-repo duplicate of a release archive, one runtime-data dirname living in two roles, ephemeral dirs, and scripts that recreate a forbidden path. They emit **Improve** into `machineImprovesBySection` in the agent manifest — a separate array, because sharing the Fix channel is what taught agents that B means deletion. Committed build output is the one Fix among them. Nothing here deletes or prompts. `semanticRequireMachineImproveMention` then requires the section summary to mention layout or cite the flagged path, so an Improve line cannot be silently dropped the way it could when only Fix lines blocked a clean summary.

### Telling open chats the pack changed

Installing updates the disk; it reaches no chat that is already open. `refresh-agent-context.ps1` syncs a project and writes `docs/AGENT_CONTEXT.json` (versions, `rulesRevision` over `pack/rules/*.mdc`, per-layer state, `changedLayers`) plus `docs/AGENT_REFRESH.md` (what to re-read, plus a paste line). Versions are read from the pack at generation time, never templated. Step 27 asserts that: an unchanged pack reports no changes but still restamps, a rule edit moves `rulesRevision`, a version bump is re-cited in the brief, and the app brief does not send agents to the pack's `HANDOVER_NEXT_AGENT.md`.

A brief nobody knows is stale is no better than no brief, and until 2.22.7 the only way to find out was
to run the refresh — the very thing you needed telling. So the audit now reads `docs/AGENT_CONTEXT.json`
and reports an **Improve** when its `auditEngineVersion` is behind the engine running the audit. Three
deliberate choices: it is **Improve**, because a stale stamp breaks nothing; it is **silent** when the
project has no stamp or a current one, so it cannot become wallpaper; and its remediation is **addressed
to the agent** — *offer to run `Refresh-AgentContext.cmd`* — because handing a user a command to type is
the friction that left projects stale in the first place. The matching instruction is carried by three
layers, and 2.22.8 exists because the first cut carried it in only one: `agent-defaults-always.mdc` is a
`.mdc` that only Cursor reads, so a Claude, Copilot or Windsurf agent received the audit line with none
of the behaviour around it. It now also lives in `AI_INSTRUCTIONS.md` (the pack's universal entry) and
`AGENTS.md`, which the per-tool files delegate to. Step 30 asserts all three, so passing on one editor
is not enough. Bootstrap stamps the engine
version it generated from for the same reason: a null stub would have made every brand-new project open
with this Improve while a genuinely old project stayed quiet. Step 30 asserts both directions.

See **`AGENT_WORKFLOW.md`** for artifact ownership and Section L harness gates.

**Agents:** read `pack/docs/AGENT_WORKFLOW.md` before audit-system changes; `AUDIT_SYSTEM_CHANGELOG.md` for settled decisions.

---

## Commands

```powershell
# After install or audit design change (REQUIRED — keeps all mirrors aligned)
pack\scripts\sync-audit-system.ps1

# Verify wiring + drift + behavior (no product tests)
pack\scripts\verify-audit-system.ps1 -ProjectRoot PATH

# Behavior only
pack\scripts\verify-audit-behavior.ps1

# Optional reference app → pack templates, then sync again
pack\scripts\sync-audit-system.ps1 -PushFromProject -ProjectRoot C:\Users\alice\Projects\MyApp
pack\scripts\sync-audit-system.ps1

# Recover edits made directly in %USERPROFILE%\.cursor\AgentStarterPack (newest wins, both directions)
pack\scripts\sync-audit-system.ps1 -PullFromInstalled
```

From a bootstrapped project: `run_audit.cmd`, `scripts\sync_audit_system.cmd`

### Mirror direction

The source pack wins on every conflict, including deletions: a manifest-listed file present only in the installed copy is **removed** from it, never copied back. That keeps `-VerifyOnly` and `-AutoFix` able to converge, and stops a stale machine-local install from writing into a pack carried on removable media. `-PullFromInstalled` is the one escape hatch.

`AGENT_STARTER_PACK_INSTALL_ROOT` redirects the mirror **destination** (default `%USERPROFILE%\.cursor\AgentStarterPack`; the user-rules mirror follows its parent). Behavior step 20 uses it to test the direction rules against a scratch folder instead of the real profile. Distinct from `AGENT_STARTER_PACK_ROOT`, which names a source pack to read.

---

## What each layer enforces

| Layer | Enforces |
|-------|----------|
| `AUDIT.config.json` | Tests, version, paths, cruft, secrets, domain map, sectionMachineChecks |
| `manifest.json` | All audit files exist and match across pack / user / project |
| `AUDIT.md` domain map | Every production `*.py` at app root (configurable) |
| `run_audit_core.ps1` | Full tests + machine checks + semantic report verify |
| `audit_code_checks.py` | Import smoke, static patterns, evidence/cite validation, manifest JSON |
| `verify-audit-system.ps1` | Sync drift, doc version vs manifest, behavior self-test (31 labelled steps, 1–30 plus 5b; skipped with `-SkipBehavior` outside the pack) |
| `verify-audit-behavior.ps1` | JSON parse, semantic/evidence gates, machineCoverage shape |
| Agent + skill | Semantic review via `.audit_agent_manifest.json` + `.audit_semantic_report.json` |

---

## PowerShell hosts (5.1 is the floor, 7 is supported)

Every pack script declares **`#Requires -Version 5.1`**, because Windows PowerShell 5.1 ships with
Windows and the pack has to work on a machine with nothing installed. `pack-paths.ps1` is the one
exception: it is dot-sourced, so the floor is declared by each script that sources it.

PowerShell 7 runs the pack correctly — the whole suite passes on both hosts — it is simply **not the
host**. Measured on Windows: a child shell costs about **130 ms on 5.1 and 250 ms on 7**, and an audit
spawns dozens of them, so preferring `pwsh` would slow every run down for no new capability. 7 wins on
in-process throughput, which is not the shape of this workload.

The risk that hosting split creates is silent: `.cmd` entry points and nested calls pin themselves to
5.1, while running a script directly from a `pwsh` prompt hosts it on 7. Three things keep that visible
and tested:

| Mechanism | What it does |
|-----------|--------------|
| `doctor.ps1` / `check-requirements.ps1` header | Names the host shell, and warns when it is Core that the floor is 5.1 |
| Behavior **step 29** (always on) | Runs a probe on both hosts and requires identical BOM-free writer bytes and identical parsed JSON. Skips with a note when only one host is installed |
| `verify-audit-behavior.ps1 -DualShell` | Runs the entire suite again on the other host. Opt-in: it doubles runtime (~70s to ~140s) |

**The one real behavioural difference is encoding.** `Set-Content -Encoding UTF8` writes a BOM on 5.1
and not on 7, and a BOM in generated JSON crashes Python's `json` module. So all text output goes
through **`Write-Utf8NoBom`** (or **`Add-Utf8NoBomLine`** for JSONL) in `pack-paths.ps1` — one
implementation, asserted by step 29, which also fails if a second copy or an inline
`UTF8Encoding($false)` write appears anywhere else.

Known and accepted: **`ConvertTo-Json` formats differently per host** (5.1 uses its own alignment, 7
uses two-space indent). Content is identical, so step 29 compares parsed data rather than raw text. Do
not add checks that hash generated JSON across hosts.

Not a version difference, despite looking like one: dot-assigning a new property onto a
`PSCustomObject` throws on **both** hosts. Use `Add-Member -Force`.

---

## Forbidden artifacts

Listed in `manifest.json` → `forbiddenArtifacts`. Includes old checklists, overlays, `run_tests_with_timeout.bat`.

Orphan `pack/templates/AUDIT.md.template` is forbidden — use `pack/templates/docs/AUDIT.md.template` only.

---

## Update procedure (audit system changes)

1. Edit pack files in the pack folder — then **sync**. Never edit the installed copy.
2. Bump `pack/audit/manifest.json` `"version"` + `AUDIT_SYSTEM_CHANGELOG.md` + `AUDIT_SYSTEM.md` header.
3. Optional: `sync-audit-system.ps1 -PushFromProject -ProjectRoot C:\Users\alice\Projects\MyApp`
4. `sync-audit-system.ps1` (propagate to installed + user; source pack always wins, including deletions).
5. `verify-audit-system.ps1 -ProjectRoot ...` — must exit 0 (runs the behavior suite when the audited root is the pack). `run_audit_tests.bat` runs the suite directly and passes `-SkipBehavior` here, so it is not paid for twice.

**Product audit** (`run_audit.cmd` on a project) is separate — run only when audit **tooling** is trusted and you want Fix/Improve on the codebase.

**Pack self-audit:** this repo (the pack folder you edit, wherever it lives) has its own `docs/AUDIT.md` + `run_audit.cmd`. That run includes **`syncAndVerify`** (drift + `verify-audit-system.ps1`) so the engine validates its own mirrors. Use **`run_audit_tests.bat`** as the test suite (behavior + system verify).

`install.ps1` runs sync automatically after copy.

Add `docs/.audit_agent_manifest.json` and `docs/.audit_semantic_report.json` to project `.gitignore` (see `pack/templates/docs/gitignore.audit.snippet`).

---

## Generated projects

Behavior step 23 bootstraps a Python project and a Generic project and audits them, so template changes are validated by running the output, not by reading it. A freshly bootstrapped project must reach **machine-clean** — only the auditor's semantic sections left — because a Fix item for a file or setting the generator itself produced is a bug in the generator.

Audit twice when changing templates: the second run takes different paths (`already synced` in the version script, artifacts present from run 1) and has caught defects the first run could not.

Step 23 walks a generated project through the whole documented workflow — bootstrap, machine pass, semantic fill, finalize — and requires it to reach a **clean** audit. It also pins two traps: a flat project named `app` must not audit its parent, and a product audit must never run this suite.

**Every generated project starts with a real gate.** Required sections are the union of the `## Checklist sections` in `docs/AUDIT.md`, the domain map, `sectionTests`, and semantic hints. The template defines six (A, B, C, D, K, L) so a new project cannot report a clean audit having reviewed nothing; an empty required-section set is a Fix, not a pass.

**Repo root is decided in two languages and must match.** `run_audit.ps1.template` (machine checks, required paths) and `resolve_repo_root()` in `audit_code_checks.py` (git history, test-pass proof, version-doc scan, evidence paths) apply the same rule: the app root, unless a folder named `app` with no local `.git` holding `docs/AUDIT.md` sits under a git parent. Step 23 asserts agreement with `--print-repo-root` against the wrapper's `Repo:` line, with a `README.md` planted in the probe's parent because that is the evidence the old Python rule promoted on. Do not replace the two rules by passing the wrapper's `-RepoRoot` into Python: the behavior fixture's wrapper declares an outer repo root, and honouring it would tie the fixture's proof to the pack's git HEAD and disable the staleness detection in steps 8-10.

**Behavior is the pack's own test suite, not a product check.** `run_audit_core.ps1` passes `-SkipBehavior` to `verify-audit-system.ps1` unless the audited root *is* the pack that supplies the engine (`RepoRoot` equals the resolved pack root — "a manifest exists somewhere below" also matched a product repo vendoring a pack copy), because the suite bootstraps probe projects inside the pack folder, costs ~30s, says nothing about the product, and via step 23 would re-enter itself. Those audits still prove the engine with `audit_code_checks.py --self-test`; drift and doc-version checks run either way.
