# Agent upgrade path (tool-neutral)

**After you change the pack or pull a new version** — disk sync first, then reach open chats.

| Step | Command | What it does |
|------|---------|--------------|
| 1 (optional) | `Install-AgentStarterPack.cmd` | Copy pack to `%USERPROFILE%\.cursor\AgentStarterPack\`, global rules/skills |
| 2 | `Update-AgentStack.cmd "<project>"` | Refresh project + write context contract (add `-Install` to combine step 1) |
| 2 alt | `Refresh-AgentContext.cmd "<project>"` | Project refresh only (no install) |
| 3 | Reach **open chats** | Paste, trigger phrase, or MCP (below) |

**Maintainer pack repo:** `Update-AgentStack.cmd` with no argument refreshes this checkout.

---

## Machine-readable contract (schema v2)

After step 2, the project has:

| File | Role |
|------|------|
| `docs/AGENT_CONTEXT.json` | Versions, layers, **`requiredReads`** (absolute paths), **`triggerPhrases`**, **`handshake`** |
| `docs/AGENT_REFRESH.md` | Human/agent brief + paste line |
| `docs/AGENT_PASTE.txt` | One-line paste (ASCII) |
| `docs/AGENT_SESSION_START.md` | Stale/fresh + required reads + execute/verify (any model) |

**`canonicalProjectRoot`** — from `.agent-bootstrap.json` when bootstrapped; use these paths even if Cursor opened a parent folder.

**Handshake** — after re-read, agent replies with **pack version** and **audit engine version** from the files it read.

---

## Reach open chats (nothing hot-reloads)

| Method | Tools |
|--------|-------|
| **Trigger phrase** | See `triggerPhrases` in `AGENT_CONTEXT.json` (e.g. *refresh pack context*) — works when global/project rules load the pack trigger |
| **Paste** | `docs/AGENT_PASTE.txt` or clipboard from refresh command |
| **Session start file** | `docs/AGENT_SESSION_START.md` — read on first turn (all tools); updated on every refresh |
| **Cursor sessionStart hook** | `.cursor/hooks.json` (bootstrap `-Targets Cursor`) or `install.ps1 -InstallSessionHooks` (user-level) |
| **MCP** | `check_pack_freshness`, `get_agent_refresh_brief` on **agent-hygiene** server (Cursor, Claude Desktop with MCP) |
| **Audit** | `run_audit.cmd` Improve line — agent should *offer* to run refresh |

Open chats **never** auto-update. Step 3 is always required.

---

## MCP (Phase 6b)

When **agent-hygiene** MCP is registered:

- **`check_pack_freshness`** — optional `projectRoot`; returns `stale`, `reasons`, `requiredReads`, versions
- **`get_agent_refresh_brief`** — returns `AGENT_REFRESH.md` body (or run refresh first)

Same facts as `AGENT_CONTEXT.json` — not a second source of truth.

---

## Related

| Doc | Topic |
|-----|-------|
| `docs/PORTABLE_SETUP.md` | Multi-tool setup |
| `pack/docs/PACK_MAINTENANCE.md` | Sync and install |
| `docs/MULTI_TOOL_GAP_PLAN.md` | Parity matrix |

**Deferred:** Cursor session hooks and wider session-start adapters (Phase D) — see [`docs/AGENT_FRESHNESS_ADAPTER_PLAN.md`](AGENT_FRESHNESS_ADAPTER_PLAN.md) (WQ-308). Phases A–C are stable; build when promoted from Parked.
