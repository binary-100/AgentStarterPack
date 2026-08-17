---
name: agent-code-audit
description: >-
  Complete audit only: full tests + mandatory deep scan A–N of every domain-map
  module. Gate-only is forbidden. Gaps = Fix or Improve only.
---

# Agent Code Audit

Read **`docs/AUDIT.md`** first — especially **Incomplete audit (forbidden)**.

## Complete audit = machine + deep scan (same session)

| Step | Required work |
|------|----------------|
| 1 | **`run_audit.cmd`** — full `run_tests.bat`; never `-SkipTests` |
| 2 | Read **`docs/.audit_inventory.json`** + **`docs/.audit_domain_expanded.json`** (auto-generated) |
| 3 | **Deep scan** — inventory, §2/§2b static analysis, **open every module in expanded domain map** |
| 4 | **`docs/.audit_semantic_report.json`** — `testsGitHead` from manifest; `modulesReviewed[]` per D–K; `inventoryAck` on B |
| 5 | **`scripts\verify_semantic_audit.cmd`** — exit 0 |
| 6 | **`scripts\finalize_audit.cmd`** — exit 0 |
| 7 | Report **only** Fix and Improve to user |

**Forbidden:** bulk `"Nothing found."`; missing `modulesReviewed[]`; stale semantic before test pass; gate-only.

## Output (only this)

```markdown
## Fix
...

## Improve
...
```

## After fixes

Re-run **`run_audit.cmd`** if production code changed; else semantic + finalize (only if tree fingerprint unchanged).
