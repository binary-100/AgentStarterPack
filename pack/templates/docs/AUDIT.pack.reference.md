# Agent Starter Pack — self-audit

When you ask for **an audit** of this repo, that means **everything** — one pass, closed scope. Report **only Fix and Improve**.

Pair with **`docs/AUDIT.config.json`**.

**Application audit example:** `pack/templates/docs/AUDIT.app.reference.md` and `pack/audit/behavior-fixture/docs/AUDIT.md` (not this pack meta-audit).

## Coverage contract

- No partial audits or "extend coverage later"
- **One audit, three steps** — never `-SkipTests` for step 1
- Domain map gaps → **Fix** (auto-detected)
- Pack mirror drift → **Fix** (`sync-audit-system.ps1 -VerifyOnly` + `run_audit.cmd` sync gate)

## How to run

```bat
run_audit.cmd
scripts\verify_semantic_audit.cmd
scripts\finalize_audit.cmd
```

| Step | Command | Who |
|------|---------|-----|
| 1 — Machine | `run_audit.cmd` | Tooling (`run_audit_tests.bat` + machine checks + sync verify) |
| 2 — Semantic | Edit `docs/.audit_semantic_report.json` + `verify_semantic_audit.cmd` | Auditor |
| 3 — Finalize | `scripts\finalize_audit.cmd` | Tooling |

Re-run full **`run_audit.cmd`** if git HEAD or source tree changed since step 1.

## Checklist sections

### A. Test harness
- `run_audit_tests.bat` runs `verify-audit-behavior.ps1` + `verify-audit-system.ps1`
- `audit_code_checks.py --self-test`

### B. Scope / inventory
- `pack/audit/manifest.json` lists every mirrored audit file
- No orphan production `*.py` at repo root

### D. Python audit engine
- `pack/scripts/audit_code_checks.py` — manifest JSON, semantic gates, domain map

### E. PowerShell audit engine
- `pack/scripts/run_audit_core.ps1`, `sync-audit-system.ps1`, `verify-audit-system.ps1`, `verify-audit-behavior.ps1`

### F. Install / bootstrap
- `install.ps1`, `Install-AgentStarterPack.cmd`, `bootstrap-project.ps1`
- `export.ps1` ships every file `manifest.json` marks required (the export fails loudly otherwise)
- Nothing machine-local reaches the profile or the zip: no `.pyc`, `.tmp`, or `.audit_*` artifacts

### G. MCP hygiene server
- `mcp/agent_hygiene_server.py` + `mcp/requirements.txt` (pin `mcp<2` for FastMCP)

### H. Templates & portable bootstrap
- `pack/templates/AGENTS.md.template`, `pack/templates/portable/AI_INSTRUCTIONS.md.template`, `pack/templates/docs/AUDIT.config.json.template`
- No orphan `pack/templates/AUDIT.md.template` at templates root (reference lives under `pack/templates/docs/`)

Semantic gate: list **every template path above** in `modulesReviewed[]` for section H.

### I. Documentation
- `pack/docs/START_HERE.md`, `pack/docs/AUDIT_SYSTEM.md`, `docs/PORTABLE_SETUP.md`

Semantic gate: list **every path above** in `modulesReviewed[]` for section I.

### L. Agent wiring
- Use pack skill `agent-code-audit` — no duplicate project copy
- `AGENTS.md` references `run_audit.cmd`
- Legacy names (`CursorAgentStarterPack`, `agent-starter-pack`) removed from pack sources

### M. Version / changelog
- `VERSION`, `CHANGELOG.md`, `pack/docs/AUDIT_SYSTEM_CHANGELOG.md` aligned with manifest

### N. Release hygiene
- Recent commits touching `VERSION`, `CHANGELOG.md`, or the audit manifest are reflected in the docs
- Required here because `sectionMachineChecks.N` is enabled in `docs/AUDIT.config.json`; it is off by
  default elsewhere, and enabling it adds N to the report template

## Report format

**Fix** and **Improve** only. If none: **Nothing found.**

## Domain map

| Module / area | Section |
|---------------|---------|
| `install_launcher.py` | F |
| `audit_code_checks.py` | D |
| `doc_version_sync.py` | D |
| `sync_doc_versions.py` | D |
| `agent_hygiene_server.py` | G |

Note: `moduleSearchDirs` in `AUDIT.config.json` lists `pack/scripts` and `mcp`; those folders are both resolved *and* inventoried, so an unmapped module there is reported as a Section B orphan.

**Known scope limit:** this map covers Python only. The pack's PowerShell — `run_audit_core.ps1`, `sync-audit-system.ps1`, `bootstrap-project.ps1`, `install.ps1` and the rest, roughly **4,900 lines** across `pack/scripts/` — is not inventoried, because the code checks (import smoke, dead-code scan, static patterns) are Python-specific. That code is covered by the behavior suite in `run_audit_tests.bat`, not by this inventory. Do not read a clean Section B as "all pack code inspected."
