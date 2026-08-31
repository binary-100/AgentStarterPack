# Audit — example application reference

Generic bootstrapped app audit checklist. Customize **`docs/AUDIT.md`** in your project from **`AUDIT.md.template`**.

When you ask for **an audit**, that means **everything** — one pass, closed scope. Report **only Fix and Improve**.

Pair with **`docs/AUDIT.config.json`** (from `AUDIT.config.json.template`).

## Coverage contract

- No partial audits, Phase A/B, or "extend coverage later"
- **One audit, three steps** — never `-SkipTests` for step 1
- Domain map gaps → **Fix** (auto-detected by `run_audit_core.ps1`)
- Audit file drift → **Fix** (auto-detected by `sync-audit-system.ps1 -VerifyOnly`)

## How to run

```bat
run_audit.cmd
scripts\verify_semantic_audit.cmd
scripts\finalize_audit.cmd
```

## Domain map (example — replace with your modules)

| Module | Section |
|--------|---------|
| `main.py` | D |
| `tests/test_*.py` | F |

See **`pack/audit/behavior-fixture/docs/AUDIT.md`** for a minimal working audit fixture in the starter pack.
