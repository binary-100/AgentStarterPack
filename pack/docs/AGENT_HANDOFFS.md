# Agent handoffs — convention (all bootstrapped projects)

**Audience:** Humans handing work to another chat; agents authoring or implementing handoffs.

**Audit:** `verify-agent-handoffs.ps1` (wired into `run_audit_core.ps1` as **Improve** / **Fix** — never auto-deletes files).

---

## Folder layout

```
docs/
  handoffs/
    README.md              ← index + naming rules
    HANDOFF_<topic>.md     ← orientation (confirm only)
    active/
      HANDOFF_WQ001_<slug>.md   ← build slices in progress
  handoff_archive/         ← completed or superseded (like audit_archive)
  WORK_QUEUE.md            ← WQ IDs; Done log must match handoff status
```

Legacy `docs/AGENT_HANDOFF_*.md` — migrate; audit flags until removed.

---

## File naming

| Kind | Path pattern | Example |
|------|--------------|---------|
| **Build** | `docs/handoffs/active/HANDOFF_WQnnn_<slug>.md` | `HANDOFF_WQ001_maintenance_usb_data.md` |
| **Orientation** | `docs/handoffs/HANDOFF_<topic>.md` | `HANDOFF_orientation_tiers.md` |
| **Archive** | `docs/handoff_archive/<original-name>.md` | after audit Improve + human confirm |

`<slug>` — lowercase, underscores, outcome-based (not phase IDs alone).

---

## Registry table (required on every handoff)

```markdown
## Handoff registry

| Field | Value |
|-------|-------|
| **handoff_id** | HANDOFF_WQ001 |
| **kind** | build |
| **status** | active |
| **multi_agent** | no |
| **wq_id** | WQ-001 |
| **plan** | upgrade/plans/EXAMPLE_PLAN.md |
| **phases** | M1-M4 |
| **agents_remaining** | |
| **completed** | |
```

| Field | Values | Notes |
|-------|--------|-------|
| **kind** | `build` · `orientation` · `multi` | `multi` = sequential agents; stricter archive rules |
| **status** | `active` · `completed` | Must match WORK_QUEUE Done log |
| **multi_agent** | `yes` · `no` | If `yes`, fill `agents_remaining` until empty |
| **wq_id** | `WQ-nnn` or empty | Required for `kind: build` tied to work queue |
| **agents_remaining** | free text or empty | e.g. `implement agent` · `review agent` — empty when all done |

---

## Session opener (only line the human sends)

Place immediately after the title block:

**Build:**

```text
Read C:\Users\<you>\Projects\MyApp\docs\handoffs\active\HANDOFF_WQ001_<slug>.md and implement.
```

**Orientation:**

```text
Read C:\Users\<you>\Projects\MyApp\docs\handoffs\HANDOFF_<topic>.md and confirm.
```

Use **full absolute paths** (`full-paths-in-chat.mdc`). The handoff file contains all implement instructions — not BUILD_HANDOFF fences in chat.

---

## Handoff file skeleton (build)

```markdown
# Handoff — <title>

## Handoff registry
(table above)

**Session opener (only — give the other agent this single line):**

`Read <full path> and implement.`

---

## Instructions (for the agent that opens this file)
1. Read docs/upgrade/BUILD_HANDOFF.md (if upgrade slice).
2. Read the PLAN — phases listed in registry only.
3. run_tests.bat / project test entry before done.

## Acceptance checklist
- [ ] …
```

---

## Lifecycle

| Step | Who | Action |
|------|-----|--------|
| Promote to build | Human / planning agent | Create `active/HANDOFF_WQ…`, WORK_QUEUE **Next**, ROADMAP row |
| Hand to implementer | Human | **One session opener line only** |
| Implementer done | Implement agent | Checklist ☑, tests pass, set `status: completed`, WQ → Done |
| Multi-agent | Each agent | Remove self from `agents_remaining`; last agent sets `completed` |
| Before audit | Team | Active build handoffs should be **completed** or still **active** with honest status |
| Audit | `run_audit.cmd` | **Improve:** "verified complete — archive to handoff_archive/" (no auto-delete) |
| Archive | Human / agent after Improve + **explicit confirm** | Preview: `archive-completed-handoff.ps1` (no flags). Apply: same script with **`-Apply`**. Move to `docs/handoff_archive/` — **never delete** handoffs from audit output alone. See **`pack/docs/WORK_COMPLETION.md`**. |

**Invariant:** Audit verifies; it does **not** delete handoffs. Multi-agent handoffs are never flagged archive-ready until `agents_remaining` is empty.

---

## BUILD_HANDOFF.md (project)

Project `docs/upgrade/BUILD_HANDOFF.md` describes **how to author** handoffs — not a second paste block for the user.

---

## Pack files

| File | Role |
|------|------|
| `pack/docs/WORK_COMPLETION.md` | After build / audit — safe vs forbidden cleanup |
| `pack/scripts/archive-completed-handoff.ps1` | Preview (default) or `-Apply` move to `handoff_archive/` |
| `pack/rules/generic-agent-handoff-discipline.mdc` | Always-on rule |
| `pack/scripts/verify-agent-handoffs.ps1` | Structure + WQ reconciliation |
| `pack/templates/docs/handoffs/README.md.template` | Bootstrap |
| `pack/templates/docs/handoffs/HANDOFF_BUILD.md.template` | Build handoff starter |

---

## Related

- `generic-work-queue-discipline.mdc` — WQ Done log vs handoff status
- `AGENT_WORKFLOW.md` — loop-back before re-handoff
- Context refresh — separate protocol (`AGENT_REFRESH.md`)
