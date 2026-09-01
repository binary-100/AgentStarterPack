# Work completion — after build, audit, or handoff

**Audience:** Humans and agents closing a slice of work without deleting the wrong things.

**Principle:** **Verify first → human confirms → move to archive.** Audits **report**; they do **not** delete handoffs, source trees, or audit JSON. Build cruft Fix lines are **narrow** (named paths only).

Location after install: `%USERPROFILE%\.cursor\AgentStarterPack\pack\docs\WORK_COMPLETION.md`

---

## Three different "cleanup" channels (do not mix)

| Channel | What it is | Who acts | Safe action |
|---------|------------|----------|-------------|
| **Audit Fix** | Named gap in one audit run (e.g. committed `__pycache__`, stale script) | Agent in **that audit session** | Fix **only the named path** in the Fix line — not "clean up the repo" |
| **Audit Improve** | Mitigate / archive suggestion (e.g. handoff archive-ready) | Human or agent **after reading** | **Move** to archive folder — **never delete** handoffs from Improve alone |
| **Work completion** | Slice shipped (handoff + WQ + tests) | Implement agent + human confirm | Checklist below; optional archive script with **`-Apply`** |

**Forbidden:** Treating audit Fix as permission to bulk-delete `docs/`, handoffs, `.audit_*`, `tests/`, or anything not **explicitly named** in a Fix line.

---

## After a build slice (handoff) — required order

| Step | Action | Skip risk |
|------|--------|-----------|
| 1 | Acceptance checklist ☑ in handoff + PLAN phase row | False "done" |
| 2 | Project test entry (`run_tests.bat` or equivalent) exit **0** | Regressions shipped |
| 3 | Update product docs if **user-visible** behavior changed | Drift |
| 4 | Handoff registry: **`status: completed`**, **`completed:`** date (ISO) | Archive gates fail |
| 5 | **`docs/WORK_QUEUE.md`:** move WQ row to **Done log** with evidence | verify-agent-handoffs **Fix** |
| 5b | **Handoff alignment:** run `verify-complete-picture.ps1`; fix **FAIL** where Done WQ IDs still read parked/not built — see **`pack/docs/RULES_AND_VERIFY_MAP.md`** | Agents rebuild shipped work from stale HANDOFF/spec |
| 6 | **`run_audit.cmd`** (full tests + semantic report + finalize) exit **0** | Archive without verification |
| 7 | Read audit output: handoff **Improve** "archive-ready" (optional but recommended) | Archive while still active |
| 8 | **Human confirms** archive (or explicit user: "archive the handoff") | Agent archives too early |
| 9 | Archive: **move** (not delete) — see script below | — |

**Multi-agent:** do not archive while **`agents_remaining`** is non-empty (even if `multi_agent: no` but field is filled — treat as blocked).

**Orientation handoffs** (`docs/handoffs/HANDOFF_*.md`, not under `active/`): archive only when **superseded**, not tied to WQ Done.

---

## Archive handoff (move only)

**Script:** `pack/scripts/archive-completed-handoff.ps1`

| Mode | Flag | Effect |
|------|------|--------|
| **Preview (default)** | *(none)* | Lists what **would** move; **no filesystem changes** |
| **Apply** | `-Apply` | Moves files that pass all gates |
| **Overwrite archive copy** | `-Apply -Force` | Dangerous — only if human explicitly accepts overwrite |

**Gates (all required unless noted):**

- File under `docs/handoffs/active/HANDOFF_*.md`
- Registry **`kind: build`**
- Registry **`status: completed`**
- Registry **`completed:`** date non-empty
- Registry **`wq_id`** present and that ID in **WORK_QUEUE Done log**
- **`agents_remaining`** empty (always checked)
- Destination `docs/handoff_archive/<same-name>.md` **must not exist** (unless `-Force`)
- **`verify-agent-handoffs.ps1`** exit **0** for project (unless `-SkipVerify` — not recommended)

**Example (preview — safe for agents to run):**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\archive-completed-handoff.ps1" `
  -ProjectRoot "C:\Users\you\Projects\MyApp"
```

**Example (apply — human confirmed):**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\archive-completed-handoff.ps1" `
  -ProjectRoot "C:\Users\you\Projects\MyApp" -Apply
```

**Agents:** run **preview only** unless the user explicitly said to archive in this session.

---

## After an audit — what to keep vs what Fix may touch

### Keep (do not delete because audit finished)

| Path | Why |
|------|-----|
| `docs/.audit_*.json`, `.audit_run_output.txt`, `.audit_timing.jsonl` | Next audit / finalize gate; overwritten on next run |
| `docs/handoffs/active/*` with **status: active** | Live work |
| `docs/WORK_QUEUE.md`, `docs/ROADMAP.md` | Canonical radar |
| `docs/audit_archive/` | Historical record |
| Source, tests, scripts | Unless a **Fix line names one obsolete file** |

### Fix may touch (only when explicitly named in Fix)

| Typical Fix target | Action |
|--------------------|--------|
| `dist/`, `build/` (gitignored scratch) | Delete **that tree** if committed or audit names it |
| Committed `__pycache__` / `.pytest_cache` | Delete named trees |
| Legacy obsolete script named in Fix | Delete **that file** or archive per Improve |
| Legacy `docs/AGENT_HANDOFF_*.md` | **Migrate** to `docs/handoffs/` then archive — not raw delete |

### Improve → backlog (not delete)

Recurring themes → append **Engineering backlog** row in `docs/WORK_QUEUE.md` (new WQ ID). Do **not** rewrite the queue in chat only.

---

## What we deliberately do not automate

- Deleting handoffs (archive = **move** only)
- Deleting audit JSON / manifests
- Bulk "clean repo" after every task
- Archiving without WQ Done + completed handoff + human confirm
- Terminal/process cleanup (use agent-hygiene MCP / `cleanup-orphan-processes.ps1` — separate concern)

---

## Related

- `pack/docs/AGENT_HANDOFFS.md` — handoff lifecycle
- `pack/docs/AGENT_WORKFLOW.md` — loop-back, audit Fix/Improve
- `generic-agent-handoff-discipline.mdc` — one opener; no auto-delete
- `generic-work-queue-discipline.mdc` — WQ Done vs handoff status
- `verify-agent-handoffs.ps1` — structure + archive-ready **Improve**
