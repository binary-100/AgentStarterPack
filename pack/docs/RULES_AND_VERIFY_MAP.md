# Rules and verify scripts — map (canonical inventory)

**Audience:** Maintainers and agents auditing agent-process design.  
**Last updated:** 2026-08-30  
**Purpose:** One place to see **what each rule covers**, **what each verify script enforces**, **overlaps**, and **gaps**. Update this file when adding rules or verify scripts.

**Canonical status (ship / park / next):** `docs/WORK_QUEUE.md` only. Every other doc is a **derivative** that must be updated or must link here — never the other way around.

---

## Prevention vs detection

| Layer | Prevents drift? | How | Limit |
|-------|-----------------|-----|-------|
| **Rules (always-on)** | *Behavioral* — if the agent follows them | Tell the agent what to update when WQ/status changes | Open chats do not reload rules; agents skip steps under time pressure |
| **`WORK_COMPLETION.md`** | *Procedural* — closing checklist | Steps after each shipped slice | Only helps when the agent runs the checklist |
| **Verify scripts** | *Mechanical* — exit non-zero | `verify-*.ps1`, behavior steps | Runs at test/audit/setup time — not on every file save |
| **`repair-agent-docs.ps1`** | *Partial auto-repair* | Hub templates + portable export on refresh | Does **not** rewrite HANDOVER narrative, phase plans, or spec status headers |
| **`doc_version_sync.py`** | *Numeric cites only* | Version strings in configured doc paths incl. **`docs/WORK_QUEUE.md` header** | Does **not** know Done vs Parked semantics |

**There is no single auto-sync for narrative handoff docs.** Prevention = **one broad rule** + **WORK_COMPLETION** + **verify-complete-picture** on close.

---

## Generic rules (`pack/rules/`)

| Rule | Always on? | Primary concern | Does **not** cover |
|------|------------|-----------------|-------------------|
| `agent-defaults-always.mdc` | yes | Index: loop-back, audit entry, refresh, work queue pointer, handoff pointer, doc hygiene pointer | Duplicates child rules; no WQ propagation detail |
| `loop-back-protocol.mdc` | yes | Repeat asks → re-read workstream, validate, proceed differently | Status doc alignment |
| `generic-work-queue-discipline.mdc` | yes | WQ IDs, Done/Parked/Next, no chat-only priority lists | **Now includes** canonical status propagation (§ below) |
| `generic-agent-handoff-discipline.mdc` | yes | One opener, handoff registry, archive gates | HANDOVER/spec/plan rows — points to WORK_COMPLETION |
| `generic-agent-doc-hygiene.mdc` | yes | Read before add; extend not duplicate; version cite sync | **Now includes** after-ship status alignment |
| `generic-deep-task-execution.mdc` | yes | Depth contracts; complete-picture when user asks status | Only binds on those triggers — not every WQ Done |
| `generic-phased-feature-design.mdc` | yes | Phase sequence, no skips | ROADMAP/work-queue promotion |
| `generic-version-sync.mdc` | no | `VERSION` → derived files + doc **version strings** | Semantic status (Done/parked) |
| `generic-terminal-and-build-hygiene.mdc` | no | Terminals, BUILD_NOPAUSE, orphans | Docs |
| `audit-protocol.mdc` | no | Audit = 3 steps, Fix/Improve only | WQ |
| `new-project-bootstrap.mdc` | no | Bootstrap layout, tests, audit wiring | Ongoing maintenance |
| `full-paths-in-chat.mdc` | yes | Absolute paths in user-facing chat | — |

**Project-only (this repo):** `.cursor/rules/starter-pack-repo.mdc`, `pack-only-edit-boundary.mdc`, `agent-recommendation-discipline.mdc`, `audit.mdc` — not installed globally.

---

## Verify scripts (`pack/scripts/`)

| Script | Behavior step | Hard FAIL on | INFO / Improve only |
|--------|---------------|--------------|---------------------|
| `verify-work-queue.ps1` | 31 | WQ structure, duplicate IDs across sections, one **Next**, Done vs open sections, **header pack/audit vs VERSION/manifest** | — |
| `verify-agent-handoffs.ps1` | 36 | Registry layout, opener format, WQ vs handoff status | Archive-ready Improve |
| `verify-complete-picture.ps1` | 37 | HANDOVER §11 ↔ WORK_QUEUE; **Done WQ vs stale parked/not-built text** in handoff sources | Pending keyword scan |
| `verify-portable-bootstrap.ps1` | 33 | Portable bootstrap files | — |
| `verify-audit-system.ps1` | (audit L) | Manifest mirror drift | — |
| `verify-audit-behavior.ps1` | (pack tests) | All of the above in regression | — |
| `verify-agent-setup.ps1` | doctor | Runs WQ + handoffs + complete-picture on pack + optional reference project | — |
| `repair-agent-docs.ps1` | 39 | Hub pattern repair on refresh | — |
| `sync-portable-docs.ps1` | 32 | Portable export drift vs `pack/rules` | — |
| `doc_version_sync.py` | 23 area | Version **string** drift in configured paths | — |

---

## Overlap hotspots (intentional vs redundant)

| Concern | Rules / docs that mention it | Canonical owner | Action |
|---------|------------------------------|-----------------|--------|
| WQ Done → update files | work-queue, handoff, deep-task, WORK_COMPLETION | **`WORK_COMPLETION.md`** + **work-queue § propagation** | Handoff rule **links**; do not duplicate full checklist |
| What's next? | agent-defaults, work-queue, deep-task complete-picture | **WORK_QUEUE** + work-queue rule | deep-task only on explicit status asks |
| Version in docs | version-sync, doc-hygiene §5 | **build** `doc_version_sync.py` | Not audit (unless Section M enabled) |
| Handoff archive | handoff rule, WORK_COMPLETION, verify-agent-handoffs | **verify-agent-handoffs** + archive script | — |
| Hub doc patterns | repair-agent-docs, portable bootstrap | **repair-agent-docs** on refresh | Separate from narrative handoff |
| Complete picture grep | deep-task contract, verify-complete-picture | **Script** enforces; **rule** when user asks | Script is the backstop |

---

## Canonical status propagation (when WQ changes)

**When moving a WQ to Done, Parked, or Active/Next**, update **all** that apply:

1. `docs/WORK_QUEUE.md` (required first)
2. `docs/handoffs/active/HANDOFF_WQ*.md` if tied to that WQ
3. Phase / gap plan row (e.g. `docs/MULTI_TOOL_GAP_PLAN.md`) — use **WQ id** in Notes, not conflicting phase-only labels
4. `HANDOVER_NEXT_AGENT.md` §11 — pointer only; no stale **Next** for Done IDs
5. Spec **status headers** (`PACK_IMPLEMENTER_SPEC.md`, plan docs) — or add “superseded — see WORK_QUEUE”
6. Run `verify-complete-picture.ps1` (maintainer pack repo) — **exit 0** before claiming slice done

**Phase ID map:** `docs/MULTI_TOOL_GAP_PLAN.md` § Phase ID map — use when the same slice has multiple phase numbers.

---

## Known gaps (open engineering)

| Gap | Mitigation today | Better fix |
|-----|------------------|------------|
| HANDOVER body not auto-updated on WQ Done | verify-complete-picture FAIL | Optional `repair-handoff-status.ps1` (not built) |
| VERSION_SYNC scope (WORK_QUEUE header drift) | **Closed S2-9:** `docs/VERSION_SYNC.json` + verify-work-queue header checks | — |
| complete-picture rule only on user ask | WORK_COMPLETION step 5b | Consider `-VerifyOnly` on Update-AgentStack for pack root |
| Many handoff sources, no single index | This file + complete-picture inventory | — |

---

## Related

| Doc | Role |
|-----|------|
| `pack/docs/WORK_COMPLETION.md` | Post-ship checklist |
| `pack/docs/PACK_MAINTENANCE.md` | Where to edit pack vs app |
| `pack/docs/AGENT_HANDOFFS.md` | Handoff file convention |
| `docs/MULTI_TOOL_GAP_PLAN.md` | Phase ID map |
