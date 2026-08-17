# Portable setup — any AI tool, any project

Use this guide when the agent is **not** in Cursor, or when you want a new repo bootstrapped correctly **before** the iteration cycle that BSOD Analyzer went through.

**Cursor users:** still run **`Install-AgentStarterPack.cmd`** once per PC, then bootstrap each project below.

---

## Goals

From day one, every project should have:

| Piece | Why |
|-------|-----|
| **`AGENTS.md`** + **`AI_INSTRUCTIONS.md`** | Canonical commands and non-negotiables for any model |
| **`docs/AUDIT.md`** + **`docs/AUDIT.config.json`** | Closed-scope audits (Fix + Improve only) |
| **`run_audit.cmd`** + scripts | Machine + semantic audit pipeline |
| **`docs/ROADMAP.md`** | Parked product work (separate from audit Improve) |
| **`docs/KNOWN_LIMITATIONS.md`** | Stop agents re-"fixing" intentional trade-offs |
| Tool-specific files | Claude, Copilot, Windsurf, Cursor each get an entry point |
| Version sync (Python) | One `VERSION` source; tests catch drift early |
| Hygiene MCP (optional) | Terminal/orphan cleanup for long agent shell sessions |

---

## Quick start (recommended)

### 1. Install the pack (once per machine)

```text
Install-AgentStarterPack.cmd
```

Restart Cursor if you use it. For Claude Desktop MCP, also run:

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\register-portable-mcp.ps1" -Tool Claude -InstallDeps -NoPause
```

### 2. Bootstrap your project

**One-click (Python app, all tools):**

```text
Bootstrap-Project.cmd D:\path\to\your-repo YourProjectName
```

**PowerShell (full control):**

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\bootstrap-project.ps1" `
    -ProjectRoot "D:\path\to\your-repo" `
    -ProjectName "YourProjectName" `
    -Stack Python `
    -Targets All `
    -SourceModule "main.py" `
    -NoPause
```

| Parameter | Values | Notes |
|-----------|--------|-------|
| `-Stack` | `Python`, `Generic` | Python adds version sync, `build_ci.bat`, stub `main.py` |
| `-Targets` | `All`, `Cursor`, `Claude`, `Copilot`, `Windsurf` | Combinable: `-Targets Claude,Copilot` |
| `-Force` | switch | Overwrite existing bootstrapped files |

### 3. Customize (required)

1. **`docs/AUDIT.md`** — domain map: list every module agents must deep-scan
2. **`docs/AUDIT.config.json`** — paths, cruft dirs, version sync paths
3. Add real tests under **`tests/`** (bootstrap creates empty dir)
4. **`README.md`** — human overview; link `AGENTS.md`

### 4. Verify

```bat
run_tests.bat
run_audit.cmd
```

First audit will guide semantic report steps in **`docs/AUDIT.md`**.

---

## What bootstrap creates

```
your-repo/
├── AGENTS.md                    # Project agent instructions
├── AI_INSTRUCTIONS.md           # Universal entry (all tools)
├── CLAUDE.md                    # Claude Desktop (if targeted)
├── .windsurfrules               # Windsurf (if targeted)
├── .github/copilot-instructions.md
├── .cursor/rules/audit.mdc      # Cursor (if targeted)
├── docs/
│   ├── AUDIT.md
│   ├── AUDIT.config.json
│   ├── ROADMAP.md
│   ├── KNOWN_LIMITATIONS.md
│   └── portable/mcp-claude-desktop.json
├── run_audit.cmd
├── run_tests.bat
├── scripts/                     # audit + version sync
└── .agent-bootstrap.json   # record of bootstrap
```

---

## Per-tool setup

### Cursor

1. **`Install-AgentStarterPack.cmd`** (global rules, skills, MCP)
2. Bootstrap with `-Targets All` or `-Targets Cursor`
3. Project uses **global** `agent-code-audit` skill — do not copy skill into repo

### Claude Desktop

1. Bootstrap with `-Targets Claude` or `All`
2. Register MCP:

```powershell
pack\scripts\register-portable-mcp.ps1 -Tool Claude -InstallDeps
```

Or merge **`docs/portable/mcp-claude-desktop.json`** into  
`%APPDATA%\Claude\claude_desktop_config.json` manually.

3. Restart Claude Desktop
4. Claude reads **`CLAUDE.md`** → follow **`AGENTS.md`**

### GitHub Copilot

1. Bootstrap with `-Targets Copilot` or `All`
2. Copilot reads **`.github/copilot-instructions.md`** (repo-level instructions)
3. Ensure **`AGENTS.md`** stays accurate — Copilot defers to it for commands

### Windsurf

1. Bootstrap with `-Targets Windsurf` or `All`
2. **`.windsurfrules`** in repo root points to **`AGENTS.md`**

### Any other agent (ChatGPT, custom bots, CI agents)

1. Bootstrap with `-Targets Portable` or include in `All`
2. Put **`AI_INSTRUCTIONS.md`** and **`AGENTS.md`** in the agent's system/context prompt, or reference them at session start
3. Scripts (`run_audit.cmd`, `run_tests.bat`) work from any terminal

There is still **no universal auto-installer** for every IDE — bootstrap gives you **files and scripts** that every tool can consume.

---

## MCP hygiene (all tools that support MCP)

The **agent-hygiene** server lives at:

```text
%USERPROFILE%\.cursor\AgentStarterPack\mcp\agent_hygiene_server.py
```

| Tool | Config file |
|------|-------------|
| Cursor | `%USERPROFILE%\.cursor\mcp.json` (install.cmd registers) |
| Claude Desktop | `%APPDATA%\Claude\claude_desktop_config.json` |

Useful tools: `agent_hygiene_full_check`, `scan_orphan_agent_processes`, `cleanup_orphan_agent_processes`, `fix_stale_terminal_logs`.

Without MCP: `pack\scripts\cleanup-orphan-processes.ps1`

---

## Avoiding the BSOD-style fix cycle

Lessons baked into bootstrap:

| Problem we hit | Bootstrap prevention |
|----------------|---------------------|
| Version drift (`VERSION` vs `VERSION.txt`) | Python stack: `apply_version.py` + test + `run_tests.bat` sync hook |
| Ad-hoc audit rules | `docs/AUDIT.md` + machine config from day one |
| Phase A/B confusion | Fix + Improve only; written in every instruction file |
| Audit Improve vs product backlog | Separate **`ROADMAP.md`** and **`KNOWN_LIMITATIONS.md`** |
| Agents skipping deep scan | Domain map in `AUDIT.md`; machine inventory in audit run |
| Interactive build hangs | `build_ci.bat` template + `BUILD_NOPAUSE=1` in all agent docs |
| Wrong tool entry point | Per-tool files + **`AI_INSTRUCTIONS.md`** hub |

**Reference:** BSOD Analyzer `app/` — production example after these patterns matured.

---

## Upgrading the pack on a bootstrapped project

1. Re-run **`Install-AgentStarterPack.cmd`** on your PC
2. In the project: **`scripts\sync_audit_system.cmd`**
3. Re-run **`run_audit.cmd`** if audit templates changed

---

## Related docs

| Doc | Topic |
|-----|-------|
| [pack/docs/START_HERE.md](../pack/docs/START_HERE.md) | Pack orientation |
| [MULTI_INSTANCE_GUIDE.md](MULTI_INSTANCE_GUIDE.md) | Multi-PC, Cursor scope |
| [VERSION_SYNC.md](VERSION_SYNC.md) | Python version pattern |
| [pack/docs/PHASED_FEATURE_DESIGN.md](../pack/docs/PHASED_FEATURE_DESIGN.md) | Multi-step features |
