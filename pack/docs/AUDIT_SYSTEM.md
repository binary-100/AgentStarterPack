# Audit system (starter pack 2.21.6 — manifest-driven)

**One audit = closed scope.** Two report sections: Fix and Improve. **One standard:** full `run_audit.cmd` — never `-SkipTests` for an audit.

Every audit-related file is listed in **`pack/audit/manifest.json`**. Sync and verify use that manifest — no manual file lists.

**After any audit-system edit:** run `sync-audit-system.ps1` then `verify-audit-system.ps1` (exit 0). Do not hand-copy pack files between Desktop / installed / user mirrors.

---

## Architecture

```
docs/AUDIT.md           Human checklist (sections A–N) + domain map
docs/AUDIT.config.json  Machine checks (paths, patterns, domain map rules)
run_audit.ps1           Thin wrapper → run_audit_core.ps1 (starter pack)
run_audit_core.ps1      Generic engine (all projects)
audit_code_checks.py    Import smoke, static patterns, agent manifest JSON
manifest.json           Every file that must stay in sync
sync-audit-system.ps1   Manifest-driven copy + hash verify (newer file wins)
verify-audit-system.ps1 Wiring + drift + behavior self-test
verify-audit-behavior.ps1  Fast behavioral checks (no product test suite)
```

**New project:** copy templates from `pack/templates/docs/` → customize `AUDIT.md` + `AUDIT.config.json` → `install.ps1 -Scope Project`.

**Reference project (BSOD):** after audit changes, `-PushFromProject` updates pack templates from `app/`.

---

## Canonical sources (update order)

| Priority | Location |
|----------|----------|
| 1 | `AgentStarterPack/` on Desktop |
| 2 | `%USERPROFILE%\.cursor\AgentStarterPack\` (install.ps1) |
| 3 | `%USERPROFILE%\.cursor\rules\` + `\skills\` |
| 4 | Each project's `docs/AUDIT.md` + `docs/AUDIT.config.json` |

Do **not** duplicate `agent-code-audit` skill in projects — use pack skill + project `audit.mdc`.

## Product audit workflow (auditor-facing)

One audit of the product — **not** two test runs unless git HEAD or source tree changed:

1. **`run_audit.cmd`** — full tests + machine layer; manifest + semantic template; appends **`docs/.audit_timing.jsonl`**
2. **Auditor** — fill `docs/.audit_semantic_report.json`; **`verify_semantic_audit.cmd`**
3. **`finalize_audit.cmd`** — semantic + harness verify; skips tests when manifest `testsGitHead` matches (git SHA or `tree:…` fingerprint)

Behavior acceptance: **`verify-audit-behavior.ps1`** steps 18–19 (full pass 1 → semantic → finalize exit 0 + timing log).

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

# BSOD reference → pack templates, then sync again
pack\scripts\sync-audit-system.ps1 -PushFromProject -ProjectRoot PATH
pack\scripts\sync-audit-system.ps1
```

From BSOD `app\`: `run_audit.cmd`, `scripts\sync_audit_system.cmd`

---

## What each layer enforces

| Layer | Enforces |
|-------|----------|
| `AUDIT.config.json` | Tests, version, paths, cruft, secrets, domain map, sectionMachineChecks |
| `manifest.json` | All audit files exist and match across pack / user / project |
| `AUDIT.md` domain map | Every production `*.py` at app root (configurable) |
| `run_audit_core.ps1` | Full tests + machine checks + semantic report verify |
| `audit_code_checks.py` | Import smoke, static patterns, evidence/cite validation, manifest JSON |
| `verify-audit-system.ps1` | Sync drift, doc version vs manifest, behavior self-test (steps 1–11) |
| `verify-audit-behavior.ps1` | JSON parse, semantic/evidence gates, machineCoverage shape |
| Agent + skill | Semantic review via `.audit_agent_manifest.json` + `.audit_semantic_report.json` |

---

## Forbidden artifacts

Listed in `manifest.json` → `forbiddenArtifacts`. Includes old checklists, overlays, `run_tests_with_timeout.bat`.

Orphan `pack/templates/AUDIT.md.template` is forbidden — use `pack/templates/docs/AUDIT.md.template` only.

---

## Update procedure (audit system changes)

1. Edit pack files (Desktop or installed — then **sync**).
2. Bump `pack/audit/manifest.json` `"version"` + `AUDIT_SYSTEM_CHANGELOG.md` + `AUDIT_SYSTEM.md` header.
3. BSOD: `sync-audit-system.ps1 -PushFromProject -ProjectRoot ...\BSODAnalyzer`
4. `sync-audit-system.ps1` (propagate to installed + user; newer file wins between Desktop and installed).
5. `verify-audit-system.ps1 -ProjectRoot ...` — must exit 0 (includes behavior steps 1–11).

**Product audit** (`run_audit.cmd` on a project) is separate — run only when audit **tooling** is trusted and you want Fix/Improve on the codebase.

**Pack self-audit:** this repo (`AgentStarterPack` on Desktop) has its own `docs/AUDIT.md` + `run_audit.cmd`. That run includes **`syncAndVerify`** (drift + `verify-audit-system.ps1`) so the engine validates its own mirrors. Use **`run_audit_tests.bat`** as the test suite (behavior + system verify).

`install.ps1` runs sync automatically after copy.

Add `docs/.audit_agent_manifest.json` and `docs/.audit_semantic_report.json` to project `.gitignore` (see `pack/templates/docs/gitignore.audit.snippet`).
