# Agent Starter Pack — self-audit

When you ask for **an audit** of this repo, that means **everything** — one pass, closed scope. Report **only Fix and Improve**.

Pair with **`docs/AUDIT.config.json`**.

**Product reference:** BSOD Analyzer `app/docs/AUDIT.md` (application audit, not this pack meta-audit).

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
- `VERSION` matches install manifest

### G. MCP hygiene server
- `mcp/agent_hygiene_server.py` + `mcp/requirements.txt` (pin `mcp<2` for FastMCP)

### H. Templates & portable bootstrap
- `pack/templates/` complete; no orphan `pack/templates/AUDIT.md.template`

### I. Documentation
- `pack/docs/START_HERE.md`, `AUDIT_SYSTEM.md`, `docs/PORTABLE_SETUP.md`

### L. Agent wiring
- Use pack skill `agent-code-audit` — no duplicate project copy
- `AGENTS.md` references `run_audit.cmd`
- Legacy names (`CursorAgentStarterPack`, `agent-starter-pack`) removed from pack sources

### M. Version / changelog
- `VERSION`, `CHANGELOG.md`, `pack/docs/AUDIT_SYSTEM_CHANGELOG.md` aligned with manifest

## Report format

**Fix** and **Improve** only. If none: **Nothing found.**

## Domain map

| Module / area | Section |
|---------------|---------|
| `install_launcher.py` | F |
| `audit_code_checks.py` | D |
| `agent_hygiene_server.py` | G |

Note: `moduleSearchDirs` in `AUDIT.config.json` resolves `pack/scripts` and `mcp`.
