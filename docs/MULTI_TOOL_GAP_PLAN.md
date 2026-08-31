# Multi-tool gap plan — Agent Starter Pack

**Work queue:** WQ-003 (Phase 1)  
**Last updated:** 2026-08-29  
**Tracks:** Editor/tool/model portability only — **not** OS/shell (Windows-only decided; see `docs/PORTABLE_SETUP.md`).

**Design goal (HANDOVER §1):** Work in as many agents/models/IDEs as practical via shared docs and scripts. Cursor keeps the deepest integration.

---

## Phase overview

| Phase | Scope | Status |
|-------|--------|--------|
| **1** | Parity matrix (this doc) — what each tool gets today | **Done 2026-08-29** |
| **2** | Export generic rules/skills as plain markdown under `pack/docs/portable/` for non-Cursor paste | **Done 2026-08-29** — `sync-portable-docs.ps1`, behavior step 32 |
| **3** | Bootstrap default `-Targets Portable` guidance for non-Cursor-only projects | **Done 2026-08-29** — `Bootstrap-Portable-Project.cmd`, `verify-portable-bootstrap.ps1`, step 33 |
| **4** | Per-tool install/register adapters (Claude/Copilot) without replacing Cursor `install.ps1` | **Done 2026-08-29** — `register-tool-adapters.ps1`, `Register-Tool-Adapters.cmd`, step 34 |
| **5** | Phase 6b MCP freshness tools | **Done 2026-08-30** — WQ-301; step 35 |
| **6** | Session-start + hub doc repair (any model) | **Done 2026-08-30** — WQ-308 D3; `repair-agent-docs.ps1`, step 39 |

Implement phases **in order** — see `pack/docs/PHASED_FEATURE_DESIGN.md`.

---

## Phase 1 — Parity matrix (read-only)

### Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Shipped and documented |
| ⚠️ | Partial — works with manual steps |
| ❌ | Cursor-only or not available |
| N/A | Not applicable to that tool |

### Artifact × tool

| Artifact / capability | Cursor | Claude Desktop | GitHub Copilot | Windsurf | Generic CLI / other |
|------------------------|--------|----------------|----------------|----------|---------------------|
| **`AGENTS.md`** | ✅ | ✅ | ✅ | ✅ | ✅ — primary project entry |
| **`AI_INSTRUCTIONS.md`** | ✅ | ✅ | ✅ | ✅ | ✅ — universal hub (2.22.8+) |
| **Bootstrap `-Targets`** | ✅ `Cursor`, `All` | ✅ `Claude`, `All` | ✅ `Copilot`, `All` | ✅ `Windsurf`, `All` | ✅ `Portable` (no editor files) |
| **Per-tool entry files** | `.cursor/rules/*.mdc` | `CLAUDE.md` | `.github/copilot-instructions.md` | `.windsurfrules` | N/A |
| **Global always-on rules** | ✅ `%USERPROFILE%\.cursor\rules\` via `install.ps1` | ❌ | ❌ | ❌ | ❌ |
| **Skills (`agent-code-audit`, etc.)** | ✅ `.cursor/skills/` | ❌ | ❌ | ❌ | ⚠️ Content in pack; no auto-load |
| **MCP agent-hygiene** | ✅ `mcp.json` under `.cursor\` | ⚠️ `register-tool-adapters.ps1 -InstallMcp` / `register-portable-mcp.ps1` | ❌ | ❌ | ❌ |
| **`run_audit.cmd` / scripts** | ✅ | ✅ | ✅ | ✅ | ✅ — PowerShell/Python CLI |
| **Audit skill invocation** | ✅ Cursor skill | ⚠️ Via `AGENTS.md` / `AI_INSTRUCTIONS.md` text | ⚠️ Same | ⚠️ Same | ⚠️ Same |
| **Agent context refresh** | ✅ `Refresh-AgentContext.cmd` | ✅ Tool-neutral brief in `docs/AGENT_REFRESH.md` | ✅ Same | ✅ Same | ✅ Same |
| **Stale context in audit** | ✅ Improve + offer run (2.22.7–8) | ✅ Same instruction in `AI_INSTRUCTIONS.md` | ✅ Same | ✅ Same | ✅ Same |
| **`install.ps1` destination** | ❌ `.cursor\` only | ❌ | ❌ | ❌ | ❌ |
| **`sync-project-rules.ps1`** | ✅ → `.cursor/rules/` | ❌ | ❌ | ❌ | ❌ |
| **`doctor.ps1` / verify scripts** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **`docs/WORK_QUEUE.md`** | ✅ | ✅ | ✅ | ✅ | ✅ — after bootstrap (2.22.13+) |
| **`pack/docs/portable/GENERIC_RULES.md`** | ⚠️ via install path | ✅ paste/attach | ✅ same | ✅ same | ✅ same (2.22.16+) |
| **`docs/portable/GENERIC_RULES.md` (project copy)** | ✅ after refresh | ✅ | ✅ | ✅ | ✅ (2.22.31+) |
| **`docs/AGENT_SESSION_START.md`** | ✅ hook + file | ✅ `CLAUDE.md` pointer | ✅ copilot pointer | ✅ windsurf pointer | ✅ `AI_INSTRUCTIONS.md` |
| **Execute/verify discipline (any model)** | ✅ global rule | ✅ hub + portable export | ✅ same | ✅ same | ✅ same (2.22.31+) |
| **`repair-agent-docs.ps1` on refresh** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **`docs/ROADMAP.md`** | ✅ apps | ✅ apps | ✅ apps | ✅ apps | ✅ apps |

### Gap summary (remaining — not model-specific)

1. **Global auto-load** — only Cursor reads `%USERPROFILE%\.cursor\rules\`; other hosts need project files or paste (mitigated by project-local `docs/portable/` copy on refresh).
2. **Skills auto-load** — Cursor-native; non-Cursor agents read `docs/portable/skills/*.md` when auditing (documented in `AI_INSTRUCTIONS.md`).
3. **MCP registration** — Cursor + optional Claude; Copilot/Windsurf have no MCP path in pack.
4. **OS entry points** — `.cmd` + `powershell.exe` + `py -3` remain Windows-first; PS 7 runs the `.ps1` bodies cross-host but full macOS/Linux parity is **WQ-304**.
5. **Mid-session hot reload** — no tool reloads instructions when files change; refresh + re-read required.

### Already shipped (do not rebuild)

- Bootstrap `-Targets` (`All`, `Portable`, per-editor)
- Tool-neutral stale-context remediation in `AI_INSTRUCTIONS.md` + `AGENTS.md` (behavior step 30)
- `docs/PORTABLE_SETUP.md`, `docs/MULTI_INSTANCE_GUIDE.md`
- `refresh-agent-context.ps1` tool-neutral brief (does not point apps at pack `HANDOVER`)

---

## Phase 2 — Portable markdown exports (planned)

**Goal:** Non-Cursor agents can load the same *content* as global rules/skills without `%USERPROFILE%\.cursor\`.

| Deliverable | Location (proposed) |
|-------------|-------------------|
| Concatenated generic rules | `pack/docs/portable/GENERIC_RULES.md` |
| Skill text mirrors | `pack/docs/portable/skills/*.md` |
| Refresh instructions | Already in `AI_INSTRUCTIONS.md` |

**Done when:** Maintainer runs one sync script; bootstrap `-Targets Portable` mentions paste path.

---

## Phase 3 — Bootstrap defaults (planned)

**Goal:** Document and optionally default non-Cursor workflows.

- README / `PORTABLE_SETUP.md`: recommend `-Targets Portable` or explicit editor for non-Cursor-only repos.
- `Verify-AgentSetup.cmd` optional check: project has `AI_INSTRUCTIONS.md` + no orphan Cursor-only assumptions.

---

## Phase 4 — Per-tool install adapters (planned)

**Goal:** Optional scripts that do **not** replace `install.ps1`:

| Tool | Proposed script | Writes |
|------|-----------------|--------|
| Claude | Extend `register-portable-mcp.ps1` pattern | Claude MCP config + doc pointer |
| Copilot | **`register-tool-adapters.ps1 -Tool Copilot`** | Validates `.github/copilot-instructions.md` |
| Windsurf | **`register-tool-adapters.ps1 -Tool Windsurf`** | Validates `.windsurfrules` |

**Skip unless** user actively uses that tool on every machine.

---

## Verification

Phase 1 is documentation-only. Phases 2+ should add behavior or verify steps only when they change shipped scripts.

**References:** `HANDOVER_NEXT_AGENT.md` §1, §8; `docs/PORTABLE_SETUP.md`; WQ-003 in `docs/WORK_QUEUE.md`.
