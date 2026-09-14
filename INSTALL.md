# Install Agent Starter Pack

Portable toolkit: **audits (Fix + Improve)**, **terminal hygiene MCP**, **CI builds**, **bootstrap**.

**Human quick start:** [`INSTALL.txt`](INSTALL.txt) (new PC, flash drive, or this machine).  
**Agent / status:** [`docs/WORK_QUEUE.md`](docs/WORK_QUEUE.md).  
**Full guide:** [pack/docs/START_HERE.md](pack/docs/START_HERE.md)

**Pack version:** see root `VERSION` (**1.8.0**). Audit engine version: `pack/audit/manifest.json` (**2.22.123**).

---

## Flash drive or other PC (WQ-011)

Copy the pack folder to the stick — plain file copy is fine and fully supported; no git, and no Unix
permissions, need to survive the trip. On the destination host, open PowerShell in that folder and follow
**`INSTALL.txt`**. Downloading a zip from `https://github.com/binary-100/AgentStarterPack` works the
same way.

After install, agents on that PC read the **installed** mirror at `%USERPROFILE%\.cursor\AgentStarterPack\` unless the stick folder is the open workspace.

---

## Requirements

Run this first on a new machine — it names what is missing and prints the command that fixes it:

```powershell
.\Check-Requirements.cmd          # add -Fix to install the Python packages
```

On macOS/Linux, `bash Check-Requirements.sh` (same script, same flags).

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

### Windows

1. Double-click **`Install-AgentStarterPack.cmd`**
2. Restart Cursor
3. Verify:

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\doctor.ps1"
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\verify-audit-system.ps1"
```

### macOS / Linux

Requires **PowerShell 7 (`pwsh`)** — the entry points are thin shells over the same `.ps1` payloads.

```bash
bash install.sh User
```

Then restart Cursor and verify:

```bash
pwsh -File "$HOME/.cursor/AgentStarterPack/pack/scripts/doctor.ps1"
pwsh -File "$HOME/.cursor/AgentStarterPack/pack/scripts/verify-audit-system.ps1"
```

**Why `bash install.sh` and not `./install.sh`.** Assume the pack arrived with no Unix execute bit,
because that is the ordinary case: a folder copy, an unzipped archive, and exFAT or FAT media all
deliver mode 644, and Windows has no bit to copy in the first place. `./install.sh` on such a copy
answers `Permission denied` (exit 126) — and it is the one command that cannot repair the problem,
because the repair lives inside the file you cannot start. Naming the interpreter sidesteps it
entirely: `bash` reads a file it was handed regardless of mode. Everything afterwards is self-healing,
since `install.ps1` runs `chmod +x` over every `.sh` it delivers. `pwsh -File install.ps1` works for
the same reason if you prefer it. If you would rather have the bit, `chmod +x *.sh` first — but do not
change the documented command to depend on it.

### Optional flags on first install

```powershell
.\install.ps1 -Scope User -RegisterMcp -InstallMcpDeps -NoPause
```

The POSIX wrapper takes the scope as its first positional argument (`bash install.sh User`) and passes
`-NoPause` itself; for the other flags call `pwsh -File install.ps1 -Scope User -RegisterMcp` directly.

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
