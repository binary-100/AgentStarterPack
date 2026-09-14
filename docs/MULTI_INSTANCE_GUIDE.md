# Multi-instance & multi-agent guide

How to ensure audit rules, terminal hygiene, and MCP tools work **everywhere you work**.

**Bootstrap any project (any AI tool):** [PORTABLE_SETUP.md](PORTABLE_SETUP.md)

---

## Cursor: one user install covers all projects on a PC

Run once per machine:

```text
Install-AgentStarterPack.cmd
```

Or:

```powershell
.\install.ps1 -Scope User -RegisterMcp -InstallMcpDeps -NoPause
```

This installs to:

| What | Path |
|------|------|
| Skills (global) | `%USERPROFILE%\.cursor\skills\` |
| Rules (global) | `%USERPROFILE%\.cursor\rules\` |
| Canonical pack | `%USERPROFILE%\.cursor\AgentStarterPack\` |
| MCP config | `%USERPROFILE%\.cursor\mcp.json` |

**Restart Cursor** after install so MCP loads.

### Per-project setup (recommended)

Use **`bootstrap-project.ps1`** — see [PORTABLE_SETUP.md](PORTABLE_SETUP.md).

Legacy Cursor-only scope install:

```powershell
.\install.ps1 -Scope Project -ProjectRoot "D:\my-app" -NoPause
```

Adds `.cursor\skills` (except `agent-code-audit`) and `.cursor\rules` in that repo. Use project `audit.mdc` + `docs/AUDIT.md`.

### New machine checklist

1. Copy `AgentStarterPack` folder or zip (`export.ps1`)
2. Run `Install-AgentStarterPack.cmd`
3. Restart Cursor
4. Settings → MCP → confirm **agent-hygiene** is enabled
5. Run `doctor.ps1` from `%USERPROFILE%\.cursor\AgentStarterPack\pack\scripts\`
6. Bootstrap each project with `Bootstrap-Project.cmd` or `bootstrap-project.ps1`

### Updating a machine that already has the pack

```text
Update-AgentRules.cmd
```

Re-runs the user-scope install, then prints what actually moved: rules and skills added or updated,
pack files added or updated, MCP servers configured, and files in the profile the pack no longer
ships. It finishes with `doctor.ps1` and a sync verify, and exits non-zero if either reports a
problem.

Leftovers are reported in two groups, and the distinction matters because one group is deletable and
the other is yours:

| Group | Meaning |
|-------|---------|
| **stale** | A previous install delivered it and this pack no longer ships it. A stale *rule* keeps instructing agents in every project, so these are worth removing |
| **not from this pack** | Never installed by the pack - your own rules and skills. Never touched |

Add `-Prune` to remove the stale group (`Update-AgentRules.cmd` has no switch of its own; call
`pack\scripts\update-agents.ps1 -Prune` or `install.ps1 -Scope User -Prune`). Pruning relies on
`install-manifest.json` recording what each install shipped, so an install predating that record
removes nothing from `rules\` or `skills\`.

For agents:

| Agent state | What it needs |
|-------------|---------------|
| New chat or session | Reads updated **skills** automatically, and updated **rules** from the project's `.cursor/rules/` - run `sync-project-rules.ps1 -ProjectRoot <project>` first, because the profile copy does not load (WQ-456) |
| Chat already in progress | Has the old rule text in context and no editor reloads rules mid-session. Run `Refresh-AgentContext.cmd`: it names the always-on rule files as required reading, which is the only channel that reaches an open chat |
| MCP tools | Restart Cursor when a server was added |

### MCP tools need one Python package

`agent-hygiene` will not start without the MCP SDK. Installing the pack does **not** install it
unless asked:

```powershell
.\install.ps1 -Scope User -InstallMcpDeps -NoPause
# or directly:
py -3 -m pip install --user -r mcp\requirements.txt
```

`doctor.ps1` reports this as a warning, not a failure - audits and bootstrap work without it.
Note that `import mcp` is not a valid check from the pack folder: the pack ships its own `mcp\`
directory, which shadows the real package. Check `from mcp.server.fastmcp import FastMCP` instead,
run from any other directory.

### Sync across PCs

- Copy zip from `export.ps1`
- Or sync `%USERPROFILE%\.cursor\rules`, `skills`, `mcp.json`, `AgentStarterPack\` via OneDrive (optional)

---

## What the MCP "ideal fix" does and does not do

| Capability | agent-hygiene MCP |
|------------|-------------------|
| List agent terminal log files | Yes |
| Detect stale metadata (no `exit_code`) | Yes |
| Repair log files | Yes |
| Kill stuck OS process by PID | Yes |
| Scan orphan py/python after force-killed parents | Yes (`scan_orphan_agent_processes`) |
| Cleanup orphans / suspect hung tests | Yes (`cleanup_orphan_agent_processes`, dry-run default) |
| One-shot terminals + orphans check | Yes (`agent_hygiene_full_check`) |
| Dismiss Cursor Terminal **UI tab** | **No** (Cursor has no public API) |

Agents call MCP tools instead of manual PowerShell when MCP is enabled.

**After any force-killed terminal:** run `agent_hygiene_full_check` — parent death often leaves zombie `python.exe` children (common with offscreen Qt tests).

---

## Other agents (not Cursor)

Use **`bootstrap-project.ps1 -Targets ...`** to generate the right files. Full guide: [PORTABLE_SETUP.md](PORTABLE_SETUP.md).

| Tool | Bootstrap target | Entry file |
|------|------------------|------------|
| **Claude Desktop** | `-Targets Claude` | `CLAUDE.md` + MCP via `register-portable-mcp.ps1` |
| **GitHub Copilot** | `-Targets Copilot` | `.github/copilot-instructions.md` |
| **Windsurf** | `-Targets Windsurf` | `.windsurfrules` |
| **Any agent** | `-Targets All` or core bootstrap | `AI_INSTRUCTIONS.md` + `AGENTS.md` |

There is **no single executable** that configures every AI IDE automatically. Bootstrap gives **portable files and scripts** every tool can consume; Cursor gets the deepest integration (rules, skills, MCP).

---

## Verify install

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\doctor.ps1"
```

In Cursor chat: "Use agent-hygiene MCP to diagnose terminal sessions."

---

## Optional: build a single .exe installer

```powershell
.\build_installer_exe.ps1
```

Produces `dist\Install-AgentStarterPack.exe` (requires Python + PyInstaller). The `.cmd` installer is equivalent without a compile step.
