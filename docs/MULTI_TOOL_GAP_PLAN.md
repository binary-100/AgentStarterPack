# Multi-tool gap plan — Agent Starter Pack

**Work queue:** WQ-003 (Phase 1)  
**Last updated:** 2026-08-30  
**Tracks:** Editor/tool/model portability only — **not** OS/shell (see `docs/OS_PORTABILITY_PLAN.md` / WQ-304).

**Design goal (HANDOFF §1):** Work in as many agents/models/IDEs as practical via shared docs and scripts. Cursor keeps the deepest integration.

**Canonical queue:** `docs/WORK_QUEUE.md` — when any doc disagrees with Done/Parked there, **fix the doc** (not the queue).

---

## Phase ID map (one workstream — many labels)

The same slice was named in three places during design. **Use WQ IDs in handoffs and the work queue**; cite this table when you need a phase number.

| WQ ID | Work queue name | Implementer spec (deleted) | `AGENT_UPGRADE_PATH` | This plan |
|-------|-----------------|-------------------------|----------------------|-----------|
| **WQ-301** | Phase 6b MCP freshness tools | Phase **6b** | Phase **B** | Phase **5** |
| **WQ-308** | Phase D freshness adapter | — | Phase **D** | Phase **6** |
| **WQ-302** | Phase 6c mailbox *(parked)* | Phase **6c** | — | — |

**Status (2026-08-30):** WQ-301 and WQ-308 are **Done** (behavior steps **35**, **38–39**). Only **WQ-302** remains parked for multi-agent coordination.

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

| Artifact / capability | Cursor | OpenCode | Claude Desktop | GitHub Copilot | Windsurf | Generic CLI / other |
|------------------------|--------|----------|----------------|----------------|----------|---------------------|
| **`AGENTS.md`** | ✅ | ✅ **native, and first in precedence** | ✅ | ✅ | ✅ | ✅ — primary project entry |
| **`AI_INSTRUCTIONS.md`** | ✅ | ✅ (via `instructions`) | ✅ | ✅ | ✅ | ✅ — universal hub (2.22.8+) |
| **Bootstrap `-Targets`** | ✅ `Cursor`, `All` | ✅ `OpenCode`, `All` (2.22.122+) | ✅ `Claude`, `All` | ✅ `Copilot`, `All` | ✅ `Windsurf`, `All` | ✅ `Portable` (no editor files) |
| **Per-tool entry files** | `.cursor/rules/*.mdc` | `opencode.json` + `AGENTS.md` | `CLAUDE.md` | `.github/copilot-instructions.md` | `.windsurfrules` | N/A |
| **Global always-on rules** | ❌ none — `%USERPROFILE%\.cursor\rules\` is not a documented Cursor rule location (WQ-456); use project `.cursor/rules/` | ✅ **`~/.config/opencode/AGENTS.md`** — a real global load path, which is more than Cursor offers | ❌ | ❌ | ❌ | ❌ |
| **Loads the pack's rule files as-is** | ✅ `.cursor/rules/` | ✅ **`instructions` globs** can name `.cursor/rules/*.mdc` directly — no conversion, no second copy | ❌ paste/export only | ❌ | ❌ | ❌ |
| **Declarative command pre-approval** | ⚠️ `beforeShellExecution` hook script (WQ-476) | ✅ **native `permission.bash` glob→effect map** — compiled from `.agent-control/policy.json` and **confirmed adopted by the binary** (1.18.30, WQ-480) | ❌ | ❌ | ❌ | ❌ |
| **Hand a finished turn back to the agent** | ✅ `stop` hook → `followup_message` (WQ-476, proven 2026-09-11) | ⚠️ plugin `stop` hook can prevent stopping and send a prompt — **TypeScript, and unverifiable on this host** (no JS runtime; WQ-479 Phase 3) | ❌ | ❌ | ❌ | ❌ |
| **Decides from the host-neutral policy** | ✅ hooks compile the globs to regex at runtime | ✅ `permission.bash` compiled at bootstrap | ❌ no adapter yet | ❌ | ❌ | ❌ |
| **Skills (`agent-code-audit`, etc.)** | ✅ `.cursor/skills/` | ✅ `.opencode/skills/`, and reads `~/.claude/skills/` | ❌ | ❌ | ❌ | ⚠️ Content in pack; no auto-load |
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

### The Cursor-shaped assumption, named (WQ-479, 2026-09-11)

**This matrix was written as "Cursor plus fallbacks", and that framing hid a real finding: on the two
capabilities this pack cares most about, OpenCode is better provisioned than Cursor.** It has a global
rules path that actually loads (`~/.config/opencode/AGENTS.md`), where Cursor's profile folder loads
nothing — a fact WQ-456 spent a release proving the hard way. And it pre-approves commands
**declaratively**, where WQ-476 had to write a hook script to get the same behaviour.

**The lesson is about build order, not about editors.** The offload control (WQ-476/477) was designed,
built and certified against Cursor's hook surface without anyone asking whether the mechanism ports.
It happens to port well, because the *decision list* is a JSON file and only the *plumbing* is
Cursor-specific — but that was luck rather than design. The general rule, now recorded here: **when a
control is built on a host-specific mechanism, the data it decides from belongs in a host-neutral
file, and only the plumbing may be host-specific.**

### Acting on it, and the part luck did not cover (WQ-480, 2026-09-11)

The maintainer's objection to the paragraph above was that it describes a fix without applying one:
*"I fear we are changing one specific design for another instead of creating a tool that will work on
all AI inference engines/models."* He was right. The decision list was neutral in *format* and
Cursor-shaped in three ways that would each have forced a second implementation:

| Was | Now | Why it mattered |
|---|---|---|
| Lived in `pack/templates/cursor/hooks/preapproved.json` | `.agent-control/policy.json`, found by walking up | Shared data inside one host's folder becomes that host's data |
| Patterns were **regexes** | Patterns are **globs** | A glob compiles to a regex losslessly; a regex does not compile to a glob at all, and OpenCode takes globs |
| Semantics lived only in PowerShell | `conformance.json` vectors | One policy stops adapters disagreeing about data, not about which rule wins |

**A second adapter is not finished when it reads the policy — it is finished when it passes
`conformance.json`.** That file is the difference between porting a control and rewriting one, and it
exists because the subtle failure here is not an adapter that crashes; it is an adapter that looks
installed and quietly decides differently.

**What is deliberately still missing:** the OpenCode plugin that hands a finished turn back. Its
`stop` hook is TypeScript, this host has no JavaScript runtime, and `opencode run` needs provider
credentials — so a plugin shipped from here would be unverifiable. The pack has a standing answer for
that situation and it is the one applied: ship what the host can confirm, and say plainly what it
cannot. The permission half **was** confirmed — `opencode debug agent build` on 1.18.30 resolves all
33 compiled rules, `*run_audit.cmd*` as `allow` and `*install.ps1*` as `ask`.

### Gap summary (remaining — not model-specific)

0. **OpenCode is installed here now, and the docs were wrong about the schema.** OpenCode 1.18.30
   (winget `SST.opencode`) runs on this host, which retires the "unverified" caveat this item used to
   carry. Worth keeping as a warning: **neither documented shape was right.** The v1 `permission`
   object and the v2 per-agent `permissions` array both appear in current docs, while
   `opencode debug agent build` resolves rules as `{permission, pattern, action}` and accepts
   authoring as `permission.<action>` = a bare effect **or** a glob→effect object. Waiting for the
   binary instead of shipping from the documentation is the only reason the compiled block works.
   **Still open:** the plugin `stop` handback (WQ-479 Phase 3) — TypeScript, no JS runtime here, and
   `opencode run` needs provider credentials.
1. **Global auto-load — Cursor has none for rules; OpenCode does.** `%USERPROFILE%\.cursor\rules\` is not a documented Cursor rule location, so the profile copy binds nothing anywhere (WQ-456); every host needs project files. Rules go to a project's `.cursor/rules/` and `AGENTS.md` via `sync-project-rules.ps1`; `Refresh-AgentContext.cmd` reports `loadedRules: stale` when they did not arrive. Skills are the exception — `~/.cursor/skills/` **is** a documented global load path.
2. **Skills auto-load** — Cursor-native; non-Cursor agents read `docs/portable/skills/*.md` when auditing (documented in `AI_INSTRUCTIONS.md`).
3. **MCP registration** — Cursor + optional Claude; Copilot/Windsurf have no MCP path in pack.
4. **OS entry points** — `.cmd` + `powershell.exe` + `py -3` remain Windows-first; PS 7 runs the `.ps1` bodies cross-host but full macOS/Linux parity is **WQ-304**.
5. **Mid-session hot reload** — no tool reloads instructions when files change; refresh + re-read required.

### Already shipped (do not rebuild)

- Bootstrap `-Targets` (`All`, `Portable`, per-editor)
- Tool-neutral stale-context remediation in `AI_INSTRUCTIONS.md` + `AGENTS.md` (behavior step 30)
- `docs/PORTABLE_SETUP.md`, `docs/MULTI_INSTANCE_GUIDE.md`
- `refresh-agent-context.ps1` tool-neutral brief (does not point apps at pack `HANDOFF`)

---

## Phase 2 — Portable markdown exports (shipped - WQ-106, 2026-08-29)

**Goal:** Non-Cursor agents can load the same *content* as global rules/skills without `%USERPROFILE%\.cursor\`.

| Deliverable | Location (proposed) |
|-------------|-------------------|
| Concatenated generic rules | `pack/docs/portable/GENERIC_RULES.md` |
| Skill text mirrors | `pack/docs/portable/skills/*.md` |
| Refresh instructions | Already in `AI_INSTRUCTIONS.md` |

**Done when:** Maintainer runs one sync script; bootstrap `-Targets Portable` mentions paste path.

---

## Phase 3 — Bootstrap defaults (shipped - WQ-107, 2026-08-29)

**Goal:** Document and optionally default non-Cursor workflows.

- README / `PORTABLE_SETUP.md`: recommend `-Targets Portable` or explicit editor for non-Cursor-only repos.
- `Verify-AgentSetup.cmd` optional check: project has `AI_INSTRUCTIONS.md` + no orphan Cursor-only assumptions.

---

## Phase 4 — Per-tool install adapters (shipped - WQ-108, 2026-08-29)

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

**References:** `pack/docs/AUDIT_SYSTEM_CHANGELOG.md` §1, §8; `docs/PORTABLE_SETUP.md`; WQ-003 in `docs/WORK_QUEUE.md`.
