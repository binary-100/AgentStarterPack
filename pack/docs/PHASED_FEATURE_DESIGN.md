# Phased feature design

**Scope:** All new features, refactors, and multi-step fixes in any project.

**Location:** `%USERPROFILE%\.cursor\AgentStarterPack\pack\docs\PHASED_FEATURE_DESIGN.md`

---

## Core rules

1. **One sequence** — Runtime order and build order are the **same** numbered phases (1 → N).
2. **No phase skips** — Do not implement Phase 7 before Phase 4, or ship “Milestone A = Phases 2–4 + 7”.
3. **One checklist** — Single table; check off phases in order. Project is done when every phase is ☑.
4. **Optional work has an owner** — Nothing floats as “optional” in the main narrative without a phase number.

---

## How to handle optional / deferred work

Pick **one** approach per feature doc (stay consistent within that doc):

### A. Nested under the owning phase (preferred)

Put optional or incremental sub-work **inside** the phase it belongs to:

```text
Phase 4 — Local verification
  4a  Device Manager errors        [required]
  4b  Generic driver detection     [required]
  4c  HWID alignment               [required]
  4d  Cross-vendor mismatch        [optional — ship after 4a–4c if time-constrained]
  4e  Bad version heuristics       [optional]
```

- **Required** sub-steps block phase completion.
- **Optional** sub-steps are listed in place but may be deferred; the phase is ☑ when all **required** sub-steps are done.
- Optional sub-steps never move to a different phase number.

### B. Appendix at end of the plan (alternative)

If optional work is clearly “later polish,” add one appendix **after** the main phase list:

```text
Appendix — Optional extensions (by parent phase)
  Phase 4d  Cross-vendor mismatch
  Phase 4e  Bad version heuristics
  Phase 6b  Background catalog refresh
```

Rules for appendix items:

- **Must** prefix with parent phase (`Phase 4d`, not “Step 2”).
- Build **after** the parent phase’s required work is complete.
- Do **not** create a separate milestone that mixes non-contiguous phases.

### Do not

- Label something “optional” in prose without tying it to Phase N or Nx.
- Use milestones like “A = 2–4 + 7, B = 5–6”.
- Present a numbered “build order” that contradicts the phase list.

---

## Document template (copy for each feature)

```markdown
# [Feature name] — phased plan

**Goal:** [One sentence]

**Phases:** [N] — implement in order 1 → N. Runtime order = build order.

---

## Phase 1 — [Name]
**Status:** Done | To build
**Input:** …
**Output:** …
**Build:** …
**Done when:** …

## Phase 2 — [Name]
…

---

## Pipeline

Phase 1 → Phase 2 → … → Phase N

---

## Implementation checklist

| # | Phase | Work | Status |
|---|-------|------|--------|
| 1 | … | … | ☐ |
| 2 | … | … | ☐ |

**Complete when:** all rows ☑.

---

## Optional extensions (appendix) — only if using approach B

| ID | Parent | Work | Status |
|----|--------|------|--------|
| 4d | Phase 4 | … | ☐ |
```

---

## Agent workflow

When planning or implementing a multi-step feature:

1. **Write or read** the phased plan before coding.
2. **Implement** the next unchecked phase only (complete it before starting the following phase).
3. **Report progress** as “through Phase N” — not as unrelated milestone names.
4. **Add optional work** only via approach A (sub-steps) or B (appendix keyed to parent phase).

For sustained features, store the plan in project docs (e.g. `docs/FEATURE_NAME_PLAN.md`) and link from `AGENTS.md`.

---

## Reference example

**BSOD Analyzer — Driver verification (crash-linked)**  
Phases: evidence → suspect list → device mapping → local verification → catalog gate → catalog check → unified report.  
See project doc when present: `app/docs/DRIVER_VERIFICATION_PLAN.md`.

---

## Related starter-pack docs

| Doc | Use |
|-----|-----|
| `AGENT_WORKFLOW.md` | Loop-back, pre-flight, audits |
| `AUDIT_SYSTEM.md` | Audit tooling only |
| `generic-phased-feature-design.mdc` | Always-on rule pointer for agents |
