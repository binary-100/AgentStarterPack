# Phased feature design

**Scope:** All new features, refactors, and multi-step fixes in any project.

**Location:** `%USERPROFILE%\.cursor\AgentStarterPack\pack\docs\PHASED_FEATURE_DESIGN.md`

---

## Core rules

1. **One sequence** — Runtime order and build order are the **same** numbered phases (**0 → N** when readiness triggers apply, else **1 → N**).
2. **No phase skips** — Do not implement Phase 7 before Phase 4, or ship “Milestone A = Phases 2–4 + 7”.
3. **One checklist** — Single table; check off phases in order. Project is done when every phase is ☑.
4. **Optional work has an owner** — Nothing floats as “optional” in the main narrative without a phase number.
5. **Phase 0 when triggered** — Multi-zone or multi-tree features: **`generic-implementation-readiness.mdc`** before Phase 1 code.

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

## Phase 0 — Implementation readiness (when triggered)

**Rule:** `generic-implementation-readiness.mdc`  
**Use when:** Runtime is split across trees/zones, there is a separate publish/deploy lane, sync-before-ship, or proof mode differs by zone.

**Before Phase 1 implementation code or claiming “design complete”:**

1. Add **`## Implementation readiness`** to the feature plan.
2. Fill the table below — one row per track that must be proven.
3. Every required row must be **Done** (with evidence) or **Blocked** (owner + re-open when) — not **Not done**.

Copy the appendix table into `docs/FEATURE_NAME_PLAN.md` (or your project's plan path).

---

## Agent workflow

When planning or implementing a multi-step feature:

1. **Write or read** the phased plan before coding.
2. **Phase 0** — if readiness triggers apply, complete the implementation readiness table first.
3. **Implement** the next unchecked phase only (complete it before starting the following phase).
4. **Report progress** as “through Phase N” — not as unrelated milestone names; never claim Phase 1+ while Phase 0 rows are **Not done**.
5. **Add optional work** only via approach A (sub-steps) or B (appendix keyed to parent phase).

For sustained features, store the plan in project docs (e.g. `docs/FEATURE_NAME_PLAN.md`) and link from `AGENTS.md`.

---

## Reference example

**MyApp — Feature X (multi-phase)**  
Phases: evidence → design → implementation → tests → docs.  
Store the plan in the app repo: `docs/FEATURE_NAME_PLAN.md` and link from `AGENTS.md`.

---

## Appendix — Implementation readiness table (copy into feature plans)

```markdown
## Implementation readiness

**Triggers:** [which generic-implementation-readiness triggers apply — split tree, publish lane, sync-before-ship, etc.]

| # | Track | Check | Evidence required | Status |
|---|-------|-------|-------------------|--------|
| 1 | [e.g. Primary zone tests] | [what must pass] | [log path, exit code, command] | Not done / Done / Blocked |
| 2 | [e.g. Ship lane tests] | … | … | … |
| 3 | [e.g. Consumer inventory] | Every script/rule/CI that assumes old layout | List path + grep or read evidence | … |
| 4 | [e.g. End-to-end ship dry-run] | Full path from dev to deploy | Script sequence + exit codes | … |

**Rule:** Do not start Phase 1 implementation code while required rows are **Not done**.
If the maintainer asks "what could we be missing?", this table was incomplete.
```

### Example shapes (illustrative — replace with project-specific rows)

| Shape | Typical tracks |
|-------|----------------|
| Client + API | Unit/UI tests on client; contract + integration tests on API; staged deploy dry-run |
| Feature flag rollout | Off-path regression; on-path smoke; config sync between environments |
| Export bundle vs dev repo | Full test suite on dev tree; export hygiene; install-from-export proof |
| Credential-gated plugin | Load proof; fire proof (or **Blocked** until credential available) |

Project-specific worked examples belong in **that project's** plan doc — not in this generic appendix.

---

## Related starter-pack docs

| Doc | Use |
|-----|-----|
| `AGENT_WORKFLOW.md` | Loop-back, pre-flight, audits |
| `AUDIT_SYSTEM.md` | Audit tooling only |
| `generic-phased-feature-design.mdc` | Always-on rule — phase order |
| `generic-implementation-readiness.mdc` | Always-on rule — Phase 0 table |
