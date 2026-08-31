# Work queue — Agent Starter Pack

**Canonical radar.** Items are **never deleted** when priorities shift — they move to **Done**, **Parked**, or stay in **Active** / **Inbox**.  
**Session pointer:** `HANDOVER_NEXT_AGENT.md` §11 summarizes; **this file is the full list.**

| Field | Value |
|-------|--------|
| **Next active ID** | **WQ-011** |
| **Last updated** | 2026-08-30 |
| **Pack version** | 1.8.0 |
| **Audit engine** | 2.22.43 |

---

## How to use (humans and agents)

1. **One “next”** — exactly one row in Active has status **Next**; everything else is **Queued**, **In progress**, **Open**, **Held**, **Blocked**, or **Parked**.
2. **Order can change** — reprioritize Active rows when dependencies or findings require it; reconcile every `WQ-xxx` before and after (nothing deleted — see `generic-work-queue-discipline.mdc`).
3. **New findings** — add to **Inbox** first; triage into Active / Parked / Done in the same session when possible.
4. **Replacing a list** — update this file; do not drop IDs. Mark old rows **Superseded by WQ-xxx** in Notes if merged.
5. **Audit run Fix/Improve** — ephemeral per `run_audit.cmd`; recurring engineering debt from reviews lives in **Engineering backlog** below.
6. **Product features** — not here; bootstrapped apps use `docs/ROADMAP.md`. This queue is **maintainer / pack / agent-process** work.

Rule: `generic-work-queue-discipline.mdc` (installed globally).

---

## Active queue (ordered)

Work **top to bottom**. Do not skip ahead without user approval or marking the row **Blocked** with reason.

| ID | Task | Status | Notes |
|----|------|--------|-------|
| WQ-011 | Flash drive / install on other PC | **Next** | Promoted from Parked 2026-08-30 after pack hygiene batch + profile install |
| WQ-004 | **OS portability (Windows-only interim doc)** | **Superseded** | 2026-08-30 user reopened OS track → **WQ-304**. Was maintainer “document honest limit” (see `WEEKEND_HANDOFF.md` §3), not a permanent veto. |

---

## Inbox (triage required)

| ID | Task | Source | Triage |
|----|------|--------|--------|
| *(empty)* | | | |

---

## Engineering backlog (from audit depth review — not ephemeral audit)

*(empty — WQ-204 and WQ-206 shipped 2026-08-30)*

| ID | Task | Priority hint |
|----|------|----------------|
| *(none)* | | |

---

## Parked / deferred (explicit — still on radar)

| ID | Task | Re-open when |
|----|------|----------------|
| WQ-302 | **Phase 6c** — multi-agent mailbox (`pack/docs/AGENT_COORDINATION_BACKLOG.md`) | Platform change / user asks |

---

## Done log

| ID | Task | Completed | Evidence |
|----|------|-----------|----------|
| WQ-001 | Handoff doc cleanup | 2026-08-29 | HANDOVER §11; WEEKEND_HANDOFF historical |
| WQ-002 | Audit depth review | 2026-08-29 | Behavior steps 1–30: **0 fail**; Findings → Engineering backlog WQ-201–206 |
| WQ-100 | D:\ vs Desktop deep compare + merger | 2026-08-29 | Desktop canonical; backup `_AgentStarterPack_merge_staging` |
| WQ-101 | `generic-deep-task-execution.mdc` complete-picture contract | 2026-08-29 | Engine 2.22.12 |
| WQ-102 | Work queue discipline in Starter Pack | 2026-08-29 | `generic-work-queue-discipline.mdc`, template, bootstrap, `docs/WORK_QUEUE.md` |
| WQ-103 | Multi-tool Phase 1 parity matrix | 2026-08-29 | `docs/MULTI_TOOL_GAP_PLAN.md` |
| WQ-104 | WORK_QUEUE backfill (`ensure-work-queue.ps1` + refresh) | 2026-08-29 | Engine 2.22.15 |
| WQ-105 | WORK_QUEUE automated verify (`verify-work-queue.ps1`, step 31) | 2026-08-29 | Engine 2.22.15 |
| WQ-009 | Refresh pack agent context | 2026-08-29 | `refresh-agent-context.ps1`; stamp 2.22.15 |
| WQ-106 | Multi-tool Phase 2 portable exports | 2026-08-29 | `sync-portable-docs.ps1`, `pack/docs/portable/` |
| WQ-107 | Multi-tool Phase 3 Portable bootstrap guidance | 2026-08-29 | `Bootstrap-Portable-Project.cmd`, `verify-portable-bootstrap.ps1`, step 33 |
| WQ-108 | Multi-tool Phase 4 tool adapter register | 2026-08-29 | `register-tool-adapters.ps1`, `Register-Tool-Adapters.cmd`, step 34 |
| WQ-003 | Multi-tool / reduce Cursor dependency | 2026-08-29 | Phases 1–6 complete (incl. WQ-301 freshness, WQ-308 session-start); see `docs/MULTI_TOOL_GAP_PLAN.md` |
| WQ-201 | Section E semantic hardening (checklist path modulesReviewed) | 2026-08-29 | `semanticChecklistPathSections`, engine 2.22.19 |
| WQ-203 | agent-code-audit skill Section E note | 2026-08-29 | Shipped with WQ-201 |
| WQ-005 | VERSION bump 1.7.0 → 1.8.0 | 2026-08-29 | `CHANGELOG.md`, doc sync |
| WQ-202 | Sections H/I semantic hardening | 2026-08-29 | `semanticChecklistPathSections` H+I, engine 2.22.20 |
| WQ-205 | PS LOC cite 3,300 → 4,900 | 2026-08-29 | `docs/AUDIT.md` + pack reference template |
| WQ-007 | Refresh BSODAnalyzer app agents | 2026-08-30 | `C:\Users\binar\OneDrive\Desktop\BSODAnalyzer\app` — pack 1.8.0 / engine 2.22.20 |
| WQ-306 | Agent context contract v2 + upgrade path doc (Phase A) | 2026-08-30 | schema v2, `docs/AGENT_UPGRADE_PATH.md`, behavior step 27 |
| WQ-301 | Phase 6b MCP freshness tools (Phase B) | 2026-08-30 | `agent_context_freshness.py`, MCP tools, step 35 |
| WQ-307 | Update-AgentStack.cmd unified upgrade (Phase C) | 2026-08-30 | `update-agent-stack.ps1`, root entry point |
| WQ-010 | Delete merge staging folder | 2026-08-30 | `_AgentStarterPack_merge_staging` removed from Desktop |
| WQ-012 | Desktop pack cleanup + sync | 2026-08-30 | Installed→Desktop mirror; backup folder removed; archive deleted; `D:\AgentStarterPack` deleted; manifest **2.22.24** on both |
| WQ-008 | Install with `-Prune` | 2026-08-30 | `install.ps1 -Prune` 2026-08-30; 0 stale files; profile at **2.22.24**; `doctor.ps1` user scope OK |
| WQ-204 | machineCoverage empty-section fix | 2026-08-30 | `collect_config_machine_checks` only lists domain map existence for sections with modules; engine **2.22.25** |
| WQ-206 | Complete-picture handoff verify | 2026-08-30 | `verify-complete-picture.ps1`; wired verify-agent-setup + behavior step 37 |
| WQ-303 | Global rules with workspace-specific boundaries | 2026-08-30 | **Rejected** — violates generic-only policy; profile-only preferences stay in `%USERPROFILE%\.cursor\rules\` |
| WQ-305 | Import smoke beyond root `*.py` | 2026-08-30 | import smoke `moduleSearchDirs`; bootstrap `$PackDir`; archive `Get-SectionBody` line-boundary fix; `hardware_cache.py` fixture stub; behavior **0 fail**; `install.ps1 -Prune`; engine **2.22.28** |
| WQ-308 | Phase D freshness adapter (D1-D3) | 2026-08-30 | session-start file + Cursor hook; `repair-agent-docs.ps1`; behavior steps 38-39 **0 fail**; engine **2.22.32**; BSOD hub rollout |
| WQ-304 | **`install.sh` / OS parity (Phases 1–6)** | 2026-08-30 | `pack-paths.ps1`, `.sh` wrappers, behavior steps 40–43 **0 fail**; `test-os-portability-probe.ps1`; CI `pack-os-smoke.yml`; engine **2.22.37** |
| WQ-006 | Git commit + remote | 2026-08-30 | `48968bf`→`968c4e9` pushed to `https://github.com/binary-100/AgentStarterPack.git`; **Pack OS smoke run #11 success** |
| WQ-413 | Maintainer hygiene backlog (P0–S2 scans) | 2026-08-30 | WORK_QUEUE fix; doc/portable sync; rules map; AGENT_CHAT_SYNC removed; Update-AgentStack verify; S2-9 WORK_QUEUE in VERSION_SYNC; profile install **2.22.43** |

---

## Cross-references

| Doc | Role |
|-----|------|
| `HANDOVER_NEXT_AGENT.md` | Session handoff + pitfalls; §11 points here |
| `docs/MULTI_TOOL_GAP_PLAN.md` | WQ-003 Phase 1 deliverable |
| `docs/AUDIT.md` | Audit protocol (Fix/Improve per run) |
| `pack/docs/AGENT_COORDINATION_BACKLOG.md` | WQ-302 detail |
| `pack/docs/RULES_AND_VERIFY_MAP.md` | Rules vs verify inventory; status propagation channels |
| `docs/ROADMAP.md` | *Not used in this repo* — product apps only |
