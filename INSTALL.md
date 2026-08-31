# Install Agent Starter Pack

Portable toolkit: **audits (Fix + Improve)**, **terminal hygiene MCP**, **CI builds**, **bootstrap**.

**Full guide:** [pack/docs/START_HERE.md](pack/docs/START_HERE.md)

**Pack version:** see root `VERSION` (**1.7.0**). Audit engine version: `pack/audit/manifest.json` (**2.22.37**).

---

## Requirements

Run this first on a new machine — it names what is missing and prints the command that fixes it:

```powershell
.\Check-Requirements.cmd          # add -Fix to install the Python packages
```

| Requirement | Needed for | If missing |
|-------------|-----------|------------|
| Windows PowerShell 5.1+ | every pack script | ships with Windows 10/11 |
| Python 3.8+ with the **`py -3`** launcher | audits, doc version sync, MCP server | `winget install -e --id Python.Python.3.12` |
| pip | installing the MCP packages | `py -3 -m ensurepip --upgrade` |
| Python package `mcp` — **optional** | agent-hygiene MCP tools | `install.ps1 -InstallMcpDeps` or `Check-Requirements.cmd -Fix` |
| git — **optional** | audit test-pass proof (falls back to a file-tree fingerprint) | `winget install -e --id Git.Git` |

`install.ps1` runs the same check first and stops if a required item is missing (`-SkipPreflight` overrides).

---

## Install

1. Double-click **`Install-AgentStarterPack.cmd`**
2. Restart Cursor
3. Verify:

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\doctor.ps1"
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\verify-audit-system.ps1"
```

Optional flags on first install:

```powershell
.\install.ps1 -Scope User -RegisterMcp -InstallMcpDeps -NoPause
```

`-Scope User` installs the global rules, skills, and MCP wiring. Add `-Scope Both` only when the
current folder is a project that should also get a local copy of the rules — run from the starter
pack folder it writes them into the pack's own `.cursor\rules\`, which is reserved for that
workspace's rules.

---

## Audits

Say **audit** in any project with `docs/AUDIT.md`:

- Agent runs `run_audit.cmd`
- Reports **Fix** and **Improve** only

Workflow: [pack/docs/AGENT_WORKFLOW.md](pack/docs/AGENT_WORKFLOW.md)  
Maintenance: [pack/docs/AUDIT_SYSTEM.md](pack/docs/AUDIT_SYSTEM.md)

---

## Per-project setup

**Recommended:** bootstrap script (see [docs/PORTABLE_SETUP.md](docs/PORTABLE_SETUP.md)):

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\bootstrap-project.ps1" `
    -ProjectRoot "D:\your\repo" -ProjectName "YourApp" -Stack Python -Targets All -NoPause
```

Or **`Bootstrap-Project.cmd D:\your\repo YourApp`** from the starter pack folder.

Legacy manual copy from `pack/templates/`:

- `docs/AUDIT.md.template` → `docs/AUDIT.md`
- `docs/AUDIT.config.json.template` → `docs/AUDIT.config.json`
- `run_audit.cmd.template` → `run_audit.cmd`
- `run_audit.ps1.template` → `scripts/run_audit.ps1`
- `audit.mdc.template` → `.cursor/rules/audit.mdc`
- `AGENTS.md.template` → `AGENTS.md`

---

## Upgrade

Re-run **`Install-AgentStarterPack.cmd`**, then verify:

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\verify-audit-system.ps1"
```

Projects with audit wiring: run `scripts\sync_audit_system.cmd` after pack upgrades.

Legacy Phase A/B overlays and `run_tests_with_timeout.bat` are removed in 1.4.0+ — use Fix/Improve audit protocol only.

---

## More documentation

| Doc | Topic |
|-----|-------|
| [pack/docs/README.md](pack/docs/README.md) | All pack docs index |
| [docs/README.md](docs/README.md) | Root guides index |
| [docs/MULTI_INSTANCE_GUIDE.md](docs/MULTI_INSTANCE_GUIDE.md) | Multi-PC, MCP, other IDEs |
| [docs/VERSION_SYNC.md](docs/VERSION_SYNC.md) | Python version sync pattern |
