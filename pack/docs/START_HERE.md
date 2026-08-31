# Agent Starter Pack — start here

**Audience:** AI coding agents, maintainers, and anyone setting up or using this pack.

**Pack version:** root `VERSION` file (currently **1.8.0**).  
**Audit engine version:** `pack/audit/manifest.json` → `"version"` (currently **2.22.43**). These numbers track different things — both are normal.

---

## What this is

The **Agent Starter Pack** is portable tooling for AI-assisted development across Cursor, Claude, Copilot, Windsurf, and other agents — not an application repo.

| Component | Purpose |
|-----------|---------|
| **Audit system** | One closed-scope audit per project: machine checks + human semantic review → **Fix** and **Improve** only |
| **Rules & skills** | Always-on defaults, loop-back protocol, terminal/build hygiene, audit skill |
| **MCP (agent-hygiene)** | Terminal log repair, orphan process scan/cleanup, pre/post shell hygiene |
| **Templates** | Bootstrap new repos: `AUDIT.md`, `run_audit.cmd`, version sync, CI test/build stubs |
| **Behavior fixture** | `pack/audit/behavior-fixture/` — minimal working audit example in the pack repo |

There is **no starter-pack product roadmap** (`docs/ROADMAP.md` is for bootstrapped apps). Maintainer work is tracked in **`docs/WORK_QUEUE.md`** at the pack root (stable WQ IDs — see `generic-work-queue-discipline.mdc`).

---

## Requirements (check before anything else)

```powershell
.\Check-Requirements.cmd          # add -Fix to install the Python packages
```

Names every missing prerequisite and the command that installs it. **Required:** PowerShell 5.1+, Python 3.8+ with the `py -3` launcher (every `.cmd` in the pack and in generated projects calls it), and a passing `audit_code_checks.py --self-test`. **Optional:** the `mcp` package (agent-hygiene MCP tools only) and git (without it, audits use a file-tree fingerprint instead of git HEAD for test-pass proof).

`install.ps1` and `bootstrap-project.ps1` run the same check — install stops on a missing required item, bootstrap only warns. Full table: **`INSTALL.md`**.

---

## Install (once per machine)

1. Double-click **`Install-AgentStarterPack.cmd`** (or run `install.ps1` from this folder).
2. **Restart Cursor** so MCP loads.
3. Verify:

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\doctor.ps1"
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\verify-audit-system.ps1"
```

Both should exit **0**. See **`INSTALL.md`** at the pack root for flags (`-RegisterMcp`, `-InstallMcpDeps`, project scope).

### Where files land after install

| What | Path |
|------|------|
| Canonical pack (scripts, templates, audit engine) | `%USERPROFILE%\.cursor\AgentStarterPack\` |
| Global skills | `%USERPROFILE%\.cursor\skills\` |
| Global rules | `%USERPROFILE%\.cursor\rules\` |
| MCP server | `%USERPROFILE%\.cursor\AgentStarterPack\mcp\agent_hygiene_server.py` |
| MCP config | `%USERPROFILE%\.cursor\mcp.json` |

The **pack folder** you edit is the source of truth, and it travels: pack scripts resolve the pack they were launched from, so it runs from a clone, an external disk, or a USB stick with no fixed location and no drive-letter assumption.

**The install does not travel.** The paths above live under `%USERPROFILE%\.cursor\` on one machine, so every machine you carry the pack to needs its own `install.ps1` run. That copy is machine-local and disposable; `sync-audit-system.ps1` only pushes pack folder → installed, never the reverse (see `-PullFromInstalled` for recovery).

USB workflow, per-machine steps, and the MCP-path caveat: **`docs/PORTABLE_SETUP.md`**.

**Keeping pack and reference projects aligned:** `pack/docs/PACK_MAINTENANCE.md` — generic rules live in `pack/rules/` only; projects sync via `sync-project-rules.ps1`.

---

## Documentation map

Read in this order when you are new to the pack:

| Order | Document | Read when |
|-------|----------|-----------|
| 1 | **`START_HERE.md`** (this file) | First visit — orientation |
| 2 | **`pack/docs/README.md`** | Index of all pack docs |
| 3 | **`docs/PORTABLE_SETUP.md`** | Bootstrap any project for any AI tool |
| 4 | **`docs/MULTI_INSTANCE_GUIDE.md`** | Multi-project / multi-PC / MCP |
| 5 | **`pack/docs/AGENT_WORKFLOW.md`** | Before sustained work or any audit |
| 6 | **`pack/docs/AUDIT_SYSTEM.md`** | Before changing audit tooling or templates |
| 7 | **`docs/VERSION_SYNC.md`** | Bootstrapping version sync in a Python app |
| 8 | **`pack/docs/PACK_MAINTENANCE.md`** | Generic rules vs project rules — sync, no forks |
| 9 | **`pack/docs/AGENT_COORDINATION_BACKLOG.md`** | Multi-agent coordination — deferred backlog |
| 10 | **`pack/docs/PHASED_FEATURE_DESIGN.md`** | Multi-step features in any project |
| 11 | **`pack/docs/AUDIT_SYSTEM_CHANGELOG.md`** | Settled audit-system decisions (maintainers) |

Root **`README.md`** and **`INSTALL.md`** are short entry points that link back here.

---

## Agents — pre-flight checklist

Before a multi-step change in **any** project:

1. Read the project's **`AGENTS.md`** and **`README`** if present.
2. Note which **rules** and **skills** Cursor loaded for this workspace.
3. If the user is repeating the same concern → follow **loop-back** in `AGENT_WORKFLOW.md` (do not retry the same failed approach).
4. For multi-step features → read **`PHASED_FEATURE_DESIGN.md`** (runtime order = build order; no phase skips).
5. Before/after long shell commands → use **agent-hygiene** MCP when available (`agent_hygiene_full_check`).
6. Windows agent builds → set **`BUILD_NOPAUSE=1`** or use **`build_ci.bat`**; never leave batch files on `pause`.
7. After edits → run the project's test/build/verify commands before claiming done.
8. When telling the user where files live on disk → **full absolute paths** in chat (`full-paths-in-chat.mdc`, always on).

### Working in the starter pack repo itself

This workspace **is** the pack — not a bootstrapped application repo.

- Read **`.cursor/rules/starter-pack-repo.mdc`**
- Do not mix application code here
- After audit-system edits: `sync-audit-system.ps1` → `verify-audit-system.ps1` exit 0
- Bump `manifest.json` `"version"` and add a **`AUDIT_SYSTEM_CHANGELOG.md`** entry

---

## Bootstrap a new project

**Recommended (any AI tool):** see **`docs/PORTABLE_SETUP.md`**.

One command:

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\bootstrap-project.ps1" `
    -ProjectRoot "D:\your\repo" -ProjectName "YourApp" -Stack Python -Targets All -NoPause
```

Or double-click **`Bootstrap-Project.cmd`** from the starter pack folder.

Target layout after bootstrap:

```text
project/
├── AGENTS.md
├── AI_INSTRUCTIONS.md          # universal entry for non-Cursor agents
├── CLAUDE.md / .windsurfrules / .github/copilot-instructions.md  # per -Targets
├── .cursor/rules/audit.mdc
├── docs/AUDIT.md
├── docs/AUDIT.config.json
├── docs/ROADMAP.md
├── docs/KNOWN_LIMITATIONS.md
├── run_audit.cmd
├── scripts/run_audit.ps1
├── run_tests.bat
├── build_ci.bat
└── tests/
```

### Manual steps (if not using bootstrap script)

1. **User install** (once per machine) — see Install above.
2. **Project install** (optional Cursor extras):

```powershell
cd D:\your\repo
& "$env:USERPROFILE\.cursor\AgentStarterPack\install.ps1" -Scope Project -ProjectRoot . -NoPause
```

3. **Copy templates** from `pack/templates/`:

| Template | Destination |
|----------|-------------|
| `docs/AUDIT.md.template` | `docs/AUDIT.md` |
| `docs/AUDIT.config.json.template` | `docs/AUDIT.config.json` |
| `run_audit.cmd.template` | `run_audit.cmd` |
| `run_audit.ps1.template` | `scripts/run_audit.ps1` |
| `audit.mdc.template` | `.cursor/rules/audit.mdc` |
| `AGENTS.md.template` | `AGENTS.md` |
| `docs/gitignore.audit.snippet` | merge into `.gitignore` |

4. **Customize** `docs/AUDIT.md` checklist and `docs/AUDIT.config.json` paths/patterns for your repo.
5. **Version sync** (Python apps): copy templates listed in **`docs/VERSION_SYNC.md`**.
6. First **audit** — user says "audit"; agent loads skill **`agent-code-audit`** and runs **`run_audit.cmd`**.

Do **not** duplicate the **`agent-code-audit`** skill inside the project — use the user-global pack skill + project **`audit.mdc`**.

Do **not** add legacy Phase A/B checklists, add-ons menus, or `*-audit-overlay.mdc` files.

---

## Running an audit in a project

**One audit = two layers, two commands (usually three steps):**

| Step | Who | Action |
|------|-----|--------|
| 1 — Machine | Tooling | `run_audit.cmd` (full test suite; never `-SkipTests` for a real audit) |
| 2 — Semantic | **Auditor** (agent) | Fill `docs/.audit_semantic_report.json`; run `scripts\verify_semantic_audit.cmd` |
| 3 — Finalize | Tooling | `scripts\finalize_audit.cmd` or `run_audit.cmd -FinalizeOnly` |

Report to the user: **Fix** and **Improve** only. No third category.

**Artifacts** (gitignored, not product source):

- `docs/.audit_agent_manifest.json` — written by step 1; read by auditor
- `docs/.audit_semantic_report.json` — template from step 1; **auditor fills**

Re-run full **`run_audit.cmd`** only if git HEAD or source tree fingerprint changed since step 1.

Full detail: **`AGENT_WORKFLOW.md`** → Audit workstreams.

---

## Terminal and build hygiene

| Situation | Action |
|-----------|--------|
| Before/after long commands | MCP `agent_hygiene_full_check` |
| Terminal tab spins after force-kill | User clicks **Kill Terminal** in Cursor UI; agent runs orphan scan (`dry_run=True` first) |
| Stale terminal metadata | MCP `fix_stale_terminal_logs` |
| GUI/offscreen tests hang | Skill **`agent-gui-test-hygiene`**; `QT_QPA_PLATFORM=offscreen` for Qt |
| MCP unavailable | `pack/scripts/cleanup-orphan-processes.ps1` |

MCP cannot dismiss Cursor terminal **UI tabs** — that requires the user.

See **`docs/MULTI_INSTANCE_GUIDE.md`** for MCP capabilities table.

---

## Maintaining the audit system

When changing `audit_code_checks.py`, templates, manifest, or sync/verify scripts:

1. Read **`AUDIT_SYSTEM_CHANGELOG.md`** and **`AUDIT_SYSTEM.md`**
2. Edit in the pack **checkout** (wherever it lives); re-install to refresh the profile copy
3. Bump **`pack/audit/manifest.json`** `"version"`
4. If adding `AUDIT.config.json` keys → update **`manifest.auditConfigTemplate.requiredKeys`** and **`AUDIT.config.json.template`**
5. Optional app reference config: `sync-audit-system.ps1 -PushFromProject -ProjectRoot C:\Users\alice\Projects\MyApp`
6. Run:

```powershell
pack\scripts\sync-audit-system.ps1
pack\scripts\verify-audit-system.ps1 -ProjectRoot (Get-Location).Path
```

7. Changelog entry in **`AUDIT_SYSTEM_CHANGELOG.md`**
8. Re-run **`Install-AgentStarterPack.cmd`** on dev machines if user-global copies need refresh

**Never hand-copy** individual pack files between the checkout, installed, and project mirrors — use **`sync-audit-system.ps1`**.

---

## Example bootstrapped application

After **`bootstrap-project.ps1`**, a typical Python app has:

| Piece | Location |
|-------|----------|
| Agent entry | `AGENTS.md`, `AI_INSTRUCTIONS.md` |
| Product audit checklist | `docs/AUDIT.md` |
| Machine config | `docs/AUDIT.config.json` |
| Product roadmap (not pack) | `docs/ROADMAP.md` |
| Version sync | source module (`main.py`) → `VERSION.txt`; `scripts/apply_version.py` |

When audit templates change in a mature app, push to the pack with **`-PushFromProject -ProjectRoot …`**. When the pack changes, projects run **`scripts/sync_audit_system.cmd`**.

**In-repo example:** `pack/audit/behavior-fixture/` — minimal audit harness used by pack tests.

---

## Common mistakes

| Mistake | Correct approach |
|---------|------------------|
| Phase A/B or "add-ons menu" language | Fix + Improve only; closed-scope audit |
| `-SkipTests` on a real audit | Full `run_audit.cmd` for step 1 |
| Semantic report before machine pass | Step 1 first — semantic needs `machineFixesBySection` |
| Duplicate `agent-code-audit` in project | User-global skill + project `audit.mdc` |
| Hand-copy pack files | `sync-audit-system.ps1` |
| Edit `VERSION.txt` by hand | Bump `VERSION` in source module; run `apply_version.py sync` |
| Treat audit Improve as product ROADMAP | Improve = ephemeral audit finding; ROADMAP = parked product work |
| Starter-pack feature backlog doc | Not needed — pack scope is stable |

---

## Quick command reference

```powershell
# Install verify
pack\scripts\doctor.ps1 -ProjectRoot (Get-Location).Path
pack\scripts\verify-audit-system.ps1

# Pack self-audit (this repo — machine + semantic + sync verify)
run_audit.cmd
scripts\verify_semantic_audit.cmd
scripts\finalize_audit.cmd

# Audit system sync (from pack root)
pack\scripts\sync-audit-system.ps1
pack\scripts\verify-audit-behavior.ps1

# Export pack zip for another PC
.\export.ps1
```

The export deliberately drops everything that identifies the sending machine: `.audit_*` results,
`install-manifest.json`, `__pycache__`, and the agent-context stamp (`docs/AGENT_CONTEXT.json`,
`docs/AGENT_REFRESH.md`, `docs/AGENT_PASTE.txt`). Those record absolute paths and the versions current
when they were written, so inheriting them is worse than starting without them. On the receiving
machine, `Refresh-AgentContext.cmd` regenerates the stamp and the first `run_audit.cmd` regenerates
the audit results.

To exercise a full install without touching your profile, set `AGENT_STARTER_PACK_INSTALL_ROOT` to a
scratch path before running `install.ps1`; the pack tree, `rules\`, `skills\` and `mcp.json` all
follow it.

In a bootstrapped project:

```bat
run_audit.cmd
scripts\verify_semantic_audit.cmd
scripts\finalize_audit.cmd
```

---

## Need more detail?

- **All pack docs:** `pack/docs/README.md`
- **Root-level guides:** `docs/README.md` (version sync, multi-instance)
- **Pack release history:** `CHANGELOG.md` (pack **1.x**)
- **Audit engine history:** `AUDIT_SYSTEM_CHANGELOG.md` (audit **2.x**)
