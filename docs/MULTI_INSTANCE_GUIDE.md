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
