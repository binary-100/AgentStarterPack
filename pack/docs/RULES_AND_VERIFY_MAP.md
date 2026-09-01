# Rules and verify scripts — map (canonical inventory)

**Audience:** Maintainers and agents auditing agent-process design.  
**Last updated:** 2026-08-31  
**Purpose:** One place to see **what each rule covers**, **what each verify script enforces**, **overlaps**, and **gaps**. Update this file when adding rules or verify scripts.

**Canonical status (ship / park / next):** `docs/WORK_QUEUE.md` only. Every other doc is a **derivative** that must be updated or must link here — never the other way around.

---

## Prevention vs detection

| Layer | Prevents drift? | How | Limit |
|-------|-----------------|-----|-------|
| **Rules (always-on)** | *Behavioral* — if the agent follows them | Tell the agent what to update when WQ/status changes | Open chats do not reload rules; agents skip steps under time pressure |
| **`WORK_COMPLETION.md`** | *Procedural* — closing checklist | Steps after each shipped slice | Only helps when the agent runs the checklist |
| **Verify scripts** | *Mechanical* — exit non-zero | `verify-*.ps1`, behavior steps | Runs at test/audit/setup time — not on every file save |
| **`repair-agent-docs.ps1`** | *Partial auto-repair* | Hub templates + portable export on refresh | Does **not** rewrite HANDOFF narrative, phase plans, or spec status headers |
| **`doc_version_sync.py`** | *Numeric cites only* | Version strings in configured doc paths incl. **`docs/WORK_QUEUE.md` header** | Does **not** know Done vs Parked semantics |

**There is no single auto-sync for narrative handoff docs.** Prevention = **one broad rule** + **WORK_COMPLETION** + **verify-complete-picture** on close.

---

## Generic rules (`pack/rules/`)

| Rule | Always on? | Primary concern | Does **not** cover |
|------|------------|-----------------|-------------------|
| `agent-defaults-always.mdc` | yes | Index: session start, loop-back, audit entry, refresh, work queue pointer, handoff pointer, doc hygiene pointer | Duplicates child rules; no WQ propagation detail |
| `loop-back-protocol.mdc` | yes | Repeat asks → re-read workstream, validate, proceed differently | Status doc alignment |
| `generic-work-queue-discipline.mdc` | yes | WQ IDs, Done/Parked/Next, no chat-only priority lists | **Now includes** canonical status propagation (§ below) |
| `generic-agent-handoff-discipline.mdc` | yes | One opener, handoff registry, archive gates | HANDOFF/spec/plan rows — points to WORK_COMPLETION |
| `generic-agent-doc-hygiene.mdc` | yes | Read before add; extend not duplicate; version cite sync | **Now includes** after-ship status alignment |
| `generic-deep-task-execution.mdc` | yes | Depth contracts; complete-picture when user asks status | Only binds on those triggers — not every WQ Done |
| `generic-phased-feature-design.mdc` | yes | Phase sequence, no skips | ROADMAP/work-queue promotion |
| `generic-version-sync.mdc` | no | `VERSION` → derived files + doc **version strings** | Semantic status (Done/parked) |
| `generic-terminal-and-build-hygiene.mdc` | no | Builds that finish without a human — `BUILD_NOPAUSE`, exit codes, prompt gating | Terminal diagnosis (skill) and the before/after sequence (agent-defaults) |
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
| `verify-complete-picture.ps1` | 37 | HANDOFF §11 ↔ WORK_QUEUE; Done-WQ vs stale text; **pack: parallel install docs, INSTALL.txt vs VERSION** | Pending keyword scan |
| `verify-portable-bootstrap.ps1` | 33 | Portable bootstrap files | — |
| `verify-audit-system.ps1` | (audit L) | Manifest mirror drift | — |
| `verify-audit-behavior.ps1` | (pack tests) | All of the above in regression; **step 45** an em dash survives AUDIT.md to the agent manifest; **step 46** shipped rules name no id, doc or section number that exists only in this repo; **step 47** every `pack/` path cited by a rule, skill or pack doc resolves on disk; **step 48** root `.cmd` launchers gate every `pause` behind `BUILD_NOPAUSE`; **step 49** one word for the handoff concept — the synonym stays retired | — |
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
| Terminal + build hygiene | `agent-defaults-always` §Terminal (always-on), `generic-terminal-and-build-hygiene` (on-demand), skill `agent-terminal-hygiene` | Split by job, **WQ-207** | Each surface now owns one thing and says so: the always-on rule is the operational default (what to run before/after long commands), the **skill** owns diagnosis (stale metadata, orphans, what an agent cannot fix), the on-demand rule owns **builds that never wait on a prompt**. The duplicated MCP sequence and can/cannot table are gone from the rule |
| Audit entry triggers | `agent-defaults-always` §Audits, `audit-protocol`, skill, project `audit.mdc` | **`audit-protocol`** for the trigger list, **skill `agent-code-audit`** for the procedure | Aligned **WQ-208**: all three carry the same words — audit, full scan, check everything, find problems, repeated still broken / anything else. `generic-deep-task-execution` adds depth requirements on its own broader triggers and links here rather than defining a second vocabulary |
| Session start | `agent-defaults-always` §Session start, all 5 entry templates | **`docs/AGENT_SESSION_START.md`** itself | Rule added 2.22.47 — templates had said it for three releases while no rule did |

---

## Canonical status propagation (when WQ changes)

**When moving a WQ to Done, Parked, or Active/Next**, update **all** that apply:

1. `docs/WORK_QUEUE.md` (required first)
2. `docs/handoffs/active/HANDOFF_WQ*.md` if tied to that WQ
3. Phase / gap plan row (e.g. `docs/MULTI_TOOL_GAP_PLAN.md`) — use **WQ id** in Notes, not conflicting phase-only labels
4. `HANDOFF_NEXT_AGENT.md` §11 — pointer only; no stale **Next** for Done IDs
5. Spec **status headers** (plan docs) — or add “superseded — see WORK_QUEUE”
6. Run `verify-complete-picture.ps1` (maintainer pack repo) — **exit 0** before claiming slice done

**Phase ID map:** `docs/MULTI_TOOL_GAP_PLAN.md` § Phase ID map — use when the same slice has multiple phase numbers.

---

## Known gaps (open engineering)

| Gap | Mitigation today | Better fix |
|-----|------------------|------------|
| HANDOFF body not auto-updated on WQ Done | verify-complete-picture FAIL | Optional `repair-handoff-status.ps1` (not built) |
| VERSION_SYNC scope (WORK_QUEUE header drift) | **Closed S2-9:** `docs/VERSION_SYNC.json` + verify-work-queue header checks | — |
| complete-picture rule only on user ask | WORK_COMPLETION step 5b | Consider `-VerifyOnly` on Update-AgentStack for pack root |
| Many handoff sources, no single index | This file + complete-picture inventory | — |
| 4 rules no verify script names | `generic-phased-feature-design`, `generic-terminal-and-build-hygiene`, `generic-version-sync`, `new-project-bootstrap` — the last two are covered indirectly (step 23, step 33) | Phased design is behavioural and may not be worth a script |
| Rule advice pointing at **project** files is unchecked | Step 47 resolves `pack/`-rooted citations; project-relative ones (`docs/ROADMAP.md`, `scripts/apply_version.py`) cannot be resolved from here, since they exist only in a bootstrapped app | Would need a check that runs inside a bootstrapped project, not in the pack |

---

## Related

| Doc | Role |
|-----|------|
| `pack/docs/WORK_COMPLETION.md` | Post-ship checklist |
| `pack/docs/PACK_MAINTENANCE.md` | Where to edit pack vs app |
| `pack/docs/AGENT_HANDOFFS.md` | Handoff file convention |
| `docs/MULTI_TOOL_GAP_PLAN.md` | Phase ID map |
