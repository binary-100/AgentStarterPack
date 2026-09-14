# Portable setup — any AI tool, any project

Use this guide when the agent is **not** in Cursor, or when you want a new repo bootstrapped correctly **before** ad-hoc iteration cycles.

**Cursor users:** still run **`Install-AgentStarterPack.cmd`** once per PC, then bootstrap each project below.

---

## Goals

From day one, every project should have:

| Piece | Why |
|-------|-----|
| **`AGENTS.md`** + **`AI_INSTRUCTIONS.md`** | Canonical commands and non-negotiables for any model |
| **`docs/AUDIT.md`** + **`docs/AUDIT.config.json`** | Closed-scope audits (Fix + Improve only) |
| **`run_audit.cmd`** + scripts | Machine + semantic audit pipeline |
| **`docs/WORK_QUEUE.md`** | Maintainer/session task radar (stable WQ IDs) |
| **`docs/ROADMAP.md`** | Parked product work (separate from audit Improve) |
| **`docs/KNOWN_LIMITATIONS.md`** | Stop agents re-"fixing" intentional trade-offs |
| Tool-specific files | Claude, Copilot, Windsurf, Cursor each get an entry point |
| Version sync (Python) | One `VERSION` source; tests catch drift early |
| Hygiene MCP (optional) | Terminal/orphan cleanup for long agent shell sessions |

---

## Platform scope

**Two layers — do not conflate them:**

| Layer | Status | Detail |
|-------|--------|--------|
| **PowerShell language (5.1 floor, 7+ supported)** | **Cross-host on Windows; PS 7 runs on Linux/macOS too** | Every pack `.ps1` declares `#Requires -Version 5.1` (no 7-only syntax). The full behavior suite passes on **Windows PowerShell 5.1** and **PowerShell 7** (`verify-audit-behavior.ps1 -DualShell`). On your dev machine, **`pwsh` is a fine primary host** — the pack does not require 5.1 for interactive work. |
| **Pack entry points and install layout** | **Cross-host via `.sh` + `pwsh`** | Windows: `.cmd`/`.bat` wrappers. macOS/Linux: **`install.sh`**, **`Refresh-AgentContext.sh`**, **`Bootstrap-Project.sh`**, **`Check-Requirements.sh`**, **`run_audit.sh`** and the rest of the registry in `pack-paths.ps1` (thin `pwsh -File` delegates). Start them as **`bash install.sh User`** — see below. |

**Start a `.sh` entry point with `bash <file>`, not `./<file>`.** The execute bit is recorded by git and
by nothing else this folder travels through: a folder copy, an unzipped archive, and exFAT or FAT media
all deliver mode 644, and a Windows checkout has no bit to carry in the first place. `./install.sh` on
such a copy stops at `Permission denied` (exit 126), and it is the one command with no way back —
the chmod that would fix it (`Set-PackExecutableBit`) runs *inside* `install.ps1`, past the file that
will not start. `bash` runs a file it is handed at any mode, and everything after the install is
self-healing because install chmods every `.sh` it writes. Behavior **step 67** holds the instruction
form in the install docs; **step 62** holds the committed modes for anyone arriving by `git clone`.

| Supported today | Not supported yet |
|-----------------|-------------------|
| Windows 10/11 with PS 5.1 or PS 7 | Full parity for every maintainer `.cmd` on macOS/Linux |
| macOS/Linux with **pwsh** + **python3** for bootstrap, refresh, check-requirements, pack audit | Cursor session hooks on non-Windows (layout differs) |
| PS 7 on Linux/macOS for any pack `.ps1` invoked via `pwsh -File` | Windows `py -3` launcher (use `python3` off Windows) |
| Cursor, Claude Desktop, Copilot, Windsurf via portable entry files | |

Shell helper and nested spawns: **`pack/scripts/pack-paths.ps1`** (`Invoke-PackScript`, `Resolve-PackPythonInvoke`). Track: **`docs/OS_PORTABILITY_PLAN.md`**.

### Verified matrix (automation + entry points)

| Workflow | Windows PS 5.1 / `.cmd` | Windows / Unix `pwsh -File` | Unix `.sh` | Automated gate |
|----------|-------------------------|-----------------------------|------------|----------------|
| Install pack | `Install-AgentStarterPack.cmd` | `install.ps1` | `install.sh` | Behavior step 40, 42 |
| Check requirements | `Check-Requirements.cmd` | `check-requirements.ps1` | `Check-Requirements.sh` | Steps 21, 41, 43 |
| Refresh agent context | `Refresh-AgentContext.cmd` | `refresh-agent-context.ps1` | `Refresh-AgentContext.sh` | Step 42 |
| Bootstrap project | `Bootstrap-Project.cmd` | `bootstrap-project.ps1` | `Bootstrap-Project.sh` | Step 42 |
| Pack maintainer audit | `run_audit_tests.bat` | `run_audit.ps1` (via core) | `run_audit.sh` | Step 42 |
| Cross-platform path helpers | — | `pack-paths.ps1` | same via `pwsh` | Steps 40–43 |
| Native Linux smoke | — | — | `pwsh` + probe script | `.github/workflows/pack-os-smoke.yml` (optional) |

**Step 43** mocks non-Windows on Windows via `AGENT_STARTER_PACK_TEST_OS=linux` (test-only; never set in production). **CI** runs `test-os-portability-probe.ps1` on real `ubuntu-latest` when the workflow is enabled.

Multi-tool **model** neutrality is separate and **shipped** — instructions live in `AI_INSTRUCTIONS.md` / `AGENTS.md` / `docs/portable/GENERIC_RULES.md`, not only Cursor `.mdc` rules.

---

## Quick start (recommended)

### 1. Install the pack (once per machine)

```text
Install-AgentStarterPack.cmd
```

Run it from wherever the pack folder lives — any drive, a clone, or a USB stick. Pack scripts resolve the pack they were launched from, so no fixed location is required.

**The pack folder travels; the install does not.** Install writes into `%USERPROFILE%\.cursor\` on the machine you run it on. That is where Cursor reads **skills** from — `~/.cursor/skills/` is a documented global load path. It is **not** where any editor reads **rules** from: Cursor documents four rule locations (project `.cursor/rules/`, User Rules, Team Rules, `AGENTS.md`) and a home-folder rules directory is not one of them, so the profile rule copy is best-effort and binds nothing by itself (WQ-456). Rules reach an agent through a project's `.cursor/rules/` and `AGENTS.md` — see **Global rules without Cursor** below. Each machine still needs its own install; that copy is machine-local and disposable, and the pack folder stays the source of truth.

### Carrying the pack on a USB stick

| Step | Command | Notes |
|------|---------|-------|
| 1. Plug in, open the pack folder | — | Drive letter does not matter |
| 2. Sanity check | `.\run_audit_tests.bat` | Expect exit 0, plus one warning until step 3 |
| 3. Integrate this machine | `Install-AgentStarterPack.cmd` | Copies rules, skills, MCP, and the pack into `%USERPROFILE%\.cursor\` |
| 4. Work | project `run_audit.cmd`, `Bootstrap-Project.cmd`, … | Projects use the machine's installed copy, so they keep working after you unplug |

Editing the pack on the stick and pushing to a machine: `pack\scripts\sync-audit-system.ps1`. It only ever copies **from** the pack folder **to** the installed copy, so a stale install on some machine cannot overwrite your stick. (`-PullFromInstalled` reverses that; use it only to recover edits made directly in `%USERPROFILE%\.cursor\AgentStarterPack`.)

Do not bootstrap a project while the pack is unavailable to that machine — an uninstalled pack makes the project's MCP config point at the pack folder's current path, which breaks when the drive letter changes or the stick is removed. Bootstrap warns when this would happen.

`AGENT_STARTER_PACK_ROOT` overrides pack discovery for one shell session — useful for testing a pack folder without installing it. Avoid making it permanent (`setx`) for removable media: the drive letter changes between machines and a stale value is worse than no value.

Restart Cursor if you use it. For Claude Desktop MCP, also run:

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\register-portable-mcp.ps1" -Tool Claude -InstallDeps -NoPause
```

### 2. Bootstrap your project

**Choose `-Targets` first:**

| You use | Recommended bootstrap |
|---------|------------------------|
| **Cursor** (primary) or several editors on one repo | `Bootstrap-Project.cmd` or `-Targets All` |
| **Claude only** | `-Targets Claude` (or `All`) |
| **Copilot / Windsurf only** | `-Targets Copilot` / `-Targets Windsurf` |
| **Non-Cursor only** (CLI, ChatGPT, custom bots) | **`Bootstrap-Portable-Project.cmd`** or `-Targets Portable` |

`-Targets Portable` writes **`AI_INSTRUCTIONS.md`**, **`AGENTS.md`**, audit wiring, and **`docs/WORK_QUEUE.md`** — **no** `CLAUDE.md`, Copilot file, Windsurf file, or Cursor **`version-sync.mdc`**. Every project still gets **`.cursor/rules/audit.mdc`** (audit standard; inert for non-Cursor agents).

At session start for Portable projects, attach **`pack/docs/portable/GENERIC_RULES.md`** plus this repo's **`AI_INSTRUCTIONS.md`**.

**One-click — Cursor + all editor entry files (Python app):**

```text
Bootstrap-Project.cmd D:\path\to\your-repo YourProjectName
```

**One-click — non-Cursor / portable-only (Python app):**

```text
Bootstrap-Portable-Project.cmd D:\path\to\your-repo YourProjectName
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
| `-Targets` | `All`, `Cursor`, `Portable`, `Claude`, `Copilot`, `Windsurf` | Combinable: `-Targets Claude,Copilot`. `Portable` means the tool-agnostic `AI_INSTRUCTIONS.md` and no editor-specific files (that file is written for every project) |
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
│   ├── AGENT_CONTEXT.json       # context stamp (stub until first refresh)
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
2. Verify project adapters and optionally register MCP:

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\register-tool-adapters.ps1" `
    -ProjectRoot "D:\path\to\your-repo" -Tool Claude -InstallMcp -NoPause
```

Or merge **`docs/portable/mcp-claude-desktop.json`** into  
`%APPDATA%\Claude\claude_desktop_config.json` manually via **`register-portable-mcp.ps1 -Tool Claude`**.

3. Restart Claude Desktop
4. Claude reads **`CLAUDE.md`** → follow **`AGENTS.md`**

### GitHub Copilot

1. Bootstrap with `-Targets Copilot` or `All`
2. Verify adapter file:

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\register-tool-adapters.ps1" `
    -ProjectRoot "D:\path\to\your-repo" -Tool Copilot -NoPause
```

Or **`Register-Tool-Adapters.cmd D:\path\to\your-repo Copilot`** from the pack root.

3. Copilot reads **`.github/copilot-instructions.md`** (repo-level instructions)
4. Ensure **`AGENTS.md`** stays accurate — Copilot defers to it for commands

### Windsurf

1. Bootstrap with `-Targets Windsurf` or `All`
2. Verify adapter file:

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\register-tool-adapters.ps1" `
    -ProjectRoot "D:\path\to\your-repo" -Tool Windsurf -NoPause
```

Or **`Register-Tool-Adapters.cmd D:\path\to\your-repo Windsurf`**.

3. **`.windsurfrules`** in repo root points to **`AGENTS.md`**

### Any other agent (ChatGPT, custom bots, CI agents)

1. Bootstrap with `-Targets Portable` or include in `All`
2. Put **`AI_INSTRUCTIONS.md`** and **`AGENTS.md`** in the agent's system/context prompt, or reference them at session start
3. Scripts (`run_audit.cmd`, `run_tests.bat`) work from any terminal

There is still **no universal auto-installer** for every IDE — bootstrap gives you **files and scripts** that every tool can consume.

### Global rules without Cursor (`install.ps1`)

**`install.ps1` copies the rules to `%USERPROFILE%\.cursor\rules\`, and no editor is documented as reading that folder** — not even Cursor, whose four rule locations are project `.cursor/rules/`, User Rules, Team Rules and `AGENTS.md` (WQ-456). Treat the profile copy as best-effort: it is a convenient place to read the canonical text from, not a mechanism that makes a rule apply.

**What does load, in every AI editor:** a project's own `.cursor/rules/*.mdc` and its `AGENTS.md`. Deliver
them per project with `sync-project-rules.ps1 -ProjectRoot <project>` (or `Bootstrap-Project.cmd`, which
does it for you) and verify with the same script plus `-VerifyOnly`. `Refresh-AgentContext.cmd` reports a
`loadedRules` layer of `stale` when no always-on rule reached that folder, and names the always-on rule
files as required reading whenever they change — the only way a rule change reaches a chat that is
already open, since editors build rule context at session start and never reload it.

The pack ships plain-markdown exports (WQ-003 Phase 2):

| File | Purpose |
|------|---------|
| `%USERPROFILE%\.cursor\AgentStarterPack\pack\docs\portable\GENERIC_RULES.md` | All generic rules (after install on this PC) |
| Same path under your **pack checkout** | When working from USB / Desktop folder without profile install |
| `pack/docs/portable/skills/*.md` | Skill text mirrors |

Regenerate after rule edits on the maintainer repo: `pack\scripts\sync-portable-docs.ps1` (also runs during `sync-audit-system.ps1`).

**Non-Cursor session start:** attach or paste `GENERIC_RULES.md` (or needed sections) plus this project's `AI_INSTRUCTIONS.md` and `AGENTS.md`.

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

## Avoiding the ad-hoc fix cycle

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

**In-repo example:** `pack/audit/behavior-fixture/` — minimal audit harness after these patterns matured.

---

## Upgrading the pack on a bootstrapped project

1. Re-run **`Install-AgentStarterPack.cmd`** on your PC
2. In the project: **`scripts\sync_audit_system.cmd`**
3. Re-run **`run_audit.cmd`** if audit templates changed

Or do steps 2–3's sync in one command and get a brief for your agents:

```bat
Refresh-AgentContext.cmd "C:\Users\alice\Projects\MyApp"
```

---

## Telling an already-open chat that things changed

No agent — Cursor, Claude, Copilot, Windsurf, or your own — reloads its instructions when files on
disk change. A chat opened before an upgrade keeps working from the old rules until you tell it not to.

**You should not have to remember any of this.** From audit engine 2.22.7 a project's own audit reports
an Improve when its context stamp is behind the pack, and the wording tells the agent to *offer to run
the refresh for you* — so the normal path is that your agent proposes the command and you approve it,
with nothing to copy or type. The rest of this section is what sits under that, and what to do when you
want to drive it yourself or update a chat in another window.

`Refresh-AgentContext.cmd <project>` writes these files and prints the full path of each:

| File | For |
|------|-----|
| `AGENT_CONTEXT.json` | Machines — pack version, audit engine version, rules hash, per-layer state, `changedLayers` |
| `AGENT_REFRESH.md` | Humans and agents — what changed, what to re-read, and the paste line |
| `AGENT_PASTE.txt` | Copying — the paste line by itself, one ASCII line, no BOM |
| `AGENT_SESSION_START.md` | The first-turn read: stale/fresh verdict and the paths you should have read |

**Where they land depends on the project.** A project you bootstrapped gets them in its own `docs/` —
it lives at one path on one machine, so a brief naming that path is right there. **The pack checkout
itself gets them outside the folder**, in `%LOCALAPPDATA%\AgentStarterPack\state\<checkout>` (POSIX:
`$XDG_STATE_HOME`), because that folder is meant to travel on a stick or arrive as a download, and a
file recording one machine's drive letters and user profile is both wrong elsewhere and nobody else's
business. Use the paths the command prints rather than assuming `docs/`.

Getting it into the chat, easiest first:

1. **Cursor:** type **refresh pack context** — the global rule sends the agent to the brief, nothing to copy.
2. **Clipboard:** the command already copied the line; press Ctrl+V.
3. **File:** open the `AGENT_PASTE.txt` path the command printed and copy the whole line.

Avoid selecting it from the console window — wrapped output is where a copy picks up line breaks. The
line asks the agent to reply with the pack and audit engine versions; if it answers without them, it
did not read the files, so paste again instead of continuing.

Other tools read the same files; the contract is on disk, not in any vendor API.

---

## Related docs

| Doc | Topic |
|-----|-------|
| [pack/docs/START_HERE.md](../pack/docs/START_HERE.md) | Pack orientation |
| [MULTI_INSTANCE_GUIDE.md](MULTI_INSTANCE_GUIDE.md) | Multi-PC, Cursor scope |
| [VERSION_SYNC.md](VERSION_SYNC.md) | Python version pattern |
| [pack/docs/PHASED_FEATURE_DESIGN.md](../pack/docs/PHASED_FEATURE_DESIGN.md) | Multi-step features |
