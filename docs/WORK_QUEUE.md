# Work queue — Agent Starter Pack

**Canonical radar.** Items are **never deleted** when priorities shift — they move to **Done**, **Parked**, or stay in **Active** / **Inbox**.  
**Session pointer:** `HANDOFF_NEXT_AGENT.md` §11 summarizes; **this file is the full list.**

| Field | Value |
|-------|--------|
| **Next active ID** | **WQ-011** |
| **Last updated** | 2026-08-31 |
| **Pack version** | 1.8.0 |
| **Audit engine** | 2.22.53 |

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
| WQ-011 | Flash drive / install on other PC | **Next** | Handoff written 2026-08-31: `docs/handoffs/active/HANDOFF_WQ011_primary_system_update.md` — transfer, verify on that machine, install, publish. Promoted from Parked 2026-08-30 |
| WQ-004 | **OS portability (Windows-only interim doc)** | **Superseded** | 2026-08-30 user reopened OS track → **WQ-304**. Was maintainer “document honest limit” (see `docs/OS_PORTABILITY_PLAN.md`), not a permanent veto. |

---

## Inbox (triage required)

| ID | Task | Source | Triage |
|----|------|--------|--------|
| *(empty)* | | | |

---

## Engineering backlog (from audit depth review — not ephemeral audit)

*(empty — WQ-207, WQ-208 and WQ-209 shipped 2026-08-31)*

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
| WQ-214 | Root cleanup against the settled definitions | 2026-08-31 | Four finished root docs deleted (two specs, implementer notes, a superseded stub) with the checks that policed them; `HANDOFF_NEXT_AGENT.md` trimmed 788 → ~470 lines, section numbers preserved for the `## 11.` reader. Found two defects while doing it: `install.ps1` `SkipRelPaths` ignored folder entries, so `docs/handoffs/` would have shipped every work slice to every profile (**step 26** now asserts folder exclusion and its prefix boundary), and this repo's own handoffs README still read `{{PROJECT_NAME}}`. `no-publish-from-this-machine.mdc` gitignored — it is false on the machine that publishes. Engine 2.22.53 |
| WQ-213 | One word for one concept: handoff | 2026-08-31 | Two synonyms had been used as if they meant different things — 519 occurrences, 56 files. `HANDOVER_NEXT_AGENT.md` renamed to `HANDOFF_NEXT_AGENT.md` and every reference updated (`manifest.json`, `VERSION_SYNC.json` ×2, `export.ps1`, `AGENTS.md`, freshness `requiredReads`). Two matches narrowed by hand so the rename could not misfire: `verify-complete-picture.ps1` and step 46's token table both had to become `HANDOFF_NEXT_AGENT`, since bare `HANDOFF` also matches the legitimate `docs/handoffs/` convention. **Step 49** guards the vocabulary; glossary in `pack/docs/AGENT_HANDOFFS.md`. Engine 2.22.52 |
| WQ-212 | Generator sweep — run every generator and read its output | 2026-08-31 | Found 12 bare `pause` calls in 4 root launchers, violating the pack's own build-hygiene rule; the suite missed them because it always calls the `.ps1` with `-NoPause`. All gated behind `BUILD_NOPAUSE`, **step 48** guards it, verified both paths. Bootstrap clean across 6 stack/target combos: manifest matches disk, no placeholders/BOM/mojibake. Engine 2.22.51 |
| WQ-211 | Generated projects carry no unsubstituted placeholders | 2026-08-31 | `ensure-work-completion.ps1` plain-copied the handoffs README, so it landed with `{{PROJECT_NAME}}` in the title; now substitutes and writes BOM-free like the WORK_COMPLETION path beside it. **Step 23** fails on `{{[A-Z_]+}}` in any generated file. Verified by bootstrap: title renders `# Handoffs - ProbeApp`. Engine 2.22.50 |
| WQ-210 | Cited pack files must exist (rule advice, not just wording) | 2026-08-31 | Behavior **step 47**; found `ensure-work-completion.ps1` copying `pack/templates/docs/handoffs/README.md.template`, which was never created — both handoff templates written and mirrored. Proven to fire on a renamed script and to ignore project-relative paths, deliberately-forbidden files and globs. Engine 2.22.49 |
| WQ-209 | Mechanical check that shipped rules stay generic | 2026-08-31 | Behavior **step 46**; caught 11 further leaks the reading pass missed (`§11` refs, `HANDOFF_NEXT_AGENT.md` as a universal instruction), all reworded; proven to fail on a planted leak and to honour maintainer-scoped lines. Engine 2.22.48 |
| WQ-207 | Terminal hygiene split by job across its three surfaces | 2026-08-31 | `generic-terminal-and-build-hygiene.mdc` rewritten as build hygiene and states what it does **not** cover; diagnosis stays in skill `agent-terminal-hygiene`, the before/after sequence in `agent-defaults-always`. Note: the premise "cuts the always-on budget" was wrong — the duplication lived in an on-demand rule, so this buys one owner per concern, not context |
| WQ-208 | Audit trigger vocabulary aligned | 2026-08-31 | One list in `audit-protocol.mdc` (canonical), repeated verbatim in `agent-defaults-always` and this repo's `.cursor/rules/audit.mdc`; `generic-deep-task-execution` links to it instead of implying a second vocabulary |
| WQ-001 | Handoff doc cleanup | 2026-08-29 | Root transfer notes folded into `HANDOFF_NEXT_AGENT.md`; the superseded stubs were deleted 2026-08-31 (WQ-214) |
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
| `HANDOFF_NEXT_AGENT.md` | Session handoff + pitfalls; §11 points here |
| `docs/MULTI_TOOL_GAP_PLAN.md` | WQ-003 Phase 1 deliverable |
| `docs/AUDIT.md` | Audit protocol (Fix/Improve per run) |
| `pack/docs/AGENT_COORDINATION_BACKLOG.md` | WQ-302 detail |
| `pack/docs/RULES_AND_VERIFY_MAP.md` | Rules vs verify inventory; status propagation channels |
| `docs/ROADMAP.md` | *Not used in this repo* — product apps only |
