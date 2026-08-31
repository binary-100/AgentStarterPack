# Agent coordination — parked (deferred)

**Status:** **Parked** · **Not on work queue** · **No implementation**

| | |
|---|---|
| **Last updated** | 2026-08-28 |
| **Owner when built** | Agent Starter Pack (`pack/`) — tool-neutral |

---

## When to revisit

**Defer until we move to a new agent program and model** (post–Cursor / Composer). Capabilities, APIs, and integration patterns may differ — designing and building now risks throwaway work and Cursor lock-in.

Until then: **user handoff + shared docs + git** (see [`PACK_MAINTENANCE.md`](PACK_MAINTENANCE.md)).

---

## Problem (future)

Multiple agents working the same program (planning, build, pack maintainer) need structured handoff **when the user directs** — without duplicating rules or forking docs.

---

## Explored (2026-08-25) — not chosen for v1

| Option | Verdict |
|--------|---------|
| Disk mailbox + JSONL + CLI | Portable; fits leaving Cursor — **preferred direction when resumed** |
| MCP adapter (thin wrapper over CLI) | Optional Cursor convenience only — not the canonical layer |
| Cursor SDK orchestrator | **Avoid as core** — high lock-in |
| Native Cursor tab-to-tab chat | Not available today |

User decision: **skip entirely for now**; re-added to backlog pending platform change.

---

## Design constraints (when resumed)

1. **Protocol first** — files + schema + CLI in `pack/`; MCP/other adapters optional  
2. **Opt-in only** — when user explicitly says “coordinate with …”  
3. **Git remains ground truth** for code; mail for intent/handoff  
4. **Generic in pack** — product role names live in app docs only  
5. Re-read [`MULTI_INSTANCE_GUIDE.md`](../../docs/MULTI_INSTANCE_GUIDE.md) and [`PORTABLE_SETUP.md`](../../docs/PORTABLE_SETUP.md) for multi-tool context

---

## Not in scope

- Audit “multi-agent consensus” (scrapped in audit engine — different feature)
- Automatic agent-to-agent loops without user direction

---

## Related

**Agent context refresh — shipped** (audit engine 2.21.23, hardened 2.22.2).
`Refresh-AgentContext.cmd` / `refresh-agent-context.ps1` write `docs/AGENT_CONTEXT.json`,
`docs/AGENT_REFRESH.md` and the one-line `docs/AGENT_PASTE.txt` per project, and put that line on the
clipboard. See [`PACK_MAINTENANCE.md`](PACK_MAINTENANCE.md). **Do not rebuild it.**

**Also parked: MCP surface for the refresh** (called *Phase 6b* in `PACK_IMPLEMENTER_SPEC.md`) — tools
such as `check_pack_freshness` and `get_agent_refresh_brief`, which would let an agent ask whether its
context is stale instead of the user pasting a line. Deferred for the same reason as the mailbox, plus
one of its own: the user chose to keep the workflow at **one command**, and the paste line already
carries a version challenge that exposes an agent which did not re-read the files. Revisit only if the
paste step proves unreliable in practice.
