# Pack maintenance — one canonical source, no forks

**Audience:** Maintainers of Agent Starter Pack and bootstrapped application projects.

Last updated: **2026-08-27**

---

## Principle

| Layer | Owns | Do not |
|-------|------|--------|
| **Agent Starter Pack** (`pack/`) | Generic rules, skills, audit engine, bootstrap templates | Put product-specific logic here |
| **Each app repo** | Product rules, `AGENTS.md`, `AUDIT.config.json`, domain docs | Edit generic rules locally — sync from pack instead |

The pack is **portable** (flash drive, new machine): copy the folder, run `Install-AgentStarterPack.cmd`, agents get the same global rules everywhere.

---

## Where to edit

| What you are changing | Edit here | Then run |
|----------------------|-----------|----------|
| Generic always-on rule (full paths, loop-back, defaults, …) | `pack/rules/*.mdc` | `install.ps1` + `sync-project-rules.ps1` on app projects |
| Audit templates / machine checks | `pack/templates/`, `pack/scripts/` | `sync-audit-system.ps1` |
| Pack or audit **version** in maintainer docs | bump `VERSION` and/or `manifest.json` | **`sync-doc-versions.ps1`** or `Sync-DocVersions.cmd` (also runs on install/sync) |
| Pack docs | `pack/docs/` | `install.ps1` (mirrors to `%USERPROFILE%\.cursor\AgentStarterPack\`) |
| Product-only behavior (UI stack, product reference, upgrade tiers) | **App repo** `.cursor/rules/` **project-only** files | That app's tests / audit only |
| Product docs | App `docs/` | That app's `run_audit.cmd` when shipping |

**Preferred edit location for pack maintainers:** the portable pack folder you opened as the workspace — any drive or path, including removable media — then install to profile. Never edit the installed copy.

---

## Generic rules (pack-owned)

These files in `pack/rules/` are copied by `install.ps1` to `%USERPROFILE%\.cursor\rules\`:

- `agent-defaults-always.mdc`
- `full-paths-in-chat.mdc`
- `loop-back-protocol.mdc`
- `audit-protocol.mdc`
- `generic-agent-doc-hygiene.mdc`
- `generic-deep-task-execution.mdc`
- `generic-phased-feature-design.mdc`
- `generic-version-sync.mdc`
- `generic-terminal-and-build-hygiene.mdc`
- `new-project-bootstrap.mdc`

**Keep examples generic** — no product names, user paths, or repo-specific folders in pack rules. Use placeholders (`MyApp`, `C:\Users\alice\Projects\...`).

**Adding a rule:** drop the `.mdc` in `pack/rules/`, then add it to `packMirror` **and** `packToUser` in `pack/audit/manifest.json`. `install.ps1`, `doctor.ps1`, and `sync-project-rules.ps1` enumerate the folder, so they need no edit; behavior step 5b fails if the manifest entries are missing or if a rule does not reach a synced project.

---

## Sync workflows

### New machine / flash drive

1. Copy `AgentStarterPack\` folder
2. Run `Install-AgentStarterPack.cmd`
3. Restart Cursor
4. `doctor.ps1` → exit 0

### After editing the pack (maintainer)

```powershell
# From AgentStarterPack root
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Scope User -NoPause

# Push generic rules into a bootstrapped project
powershell -NoProfile -ExecutionPolicy Bypass -File .\pack\scripts\sync-project-rules.ps1 `
  -ProjectRoot "C:\Users\alice\Projects\MyApp" -RulesRelativePath ".cursor\rules"

# Verify no drift
powershell -NoProfile -ExecutionPolicy Bypass -File .\pack\scripts\sync-project-rules.ps1 `
  -ProjectRoot "C:\Users\alice\Projects\MyApp" -RulesRelativePath ".cursor\rules" -VerifyOnly
```

### Telling open chats that the pack changed

Nothing on disk reaches a chat that is already open — no agent re-reads its instructions when files
change. `Refresh-AgentContext.cmd` syncs the project and writes the brief you point the chat at:

```powershell
# This pack repo (maintainer mode)
.\Refresh-AgentContext.cmd

# A bootstrapped project - also runs sync-project-rules and sync-audit-system
.\Refresh-AgentContext.cmd "C:\Users\alice\Projects\MyApp"

# Reinstall the profile layer first
powershell -NoProfile -ExecutionPolicy Bypass -File .\pack\scripts\refresh-agent-context.ps1 `
  -ProjectRoot "C:\Users\alice\Projects\MyApp" -Install
```

Writes three files under the project's `docs/`:

| File | Contents |
|------|----------|
| `AGENT_CONTEXT.json` | Versions, per-layer state, `changedLayers` |
| `AGENT_REFRESH.md` | Short brief; the paste line in a fenced block |
| `AGENT_PASTE.txt` | The paste line alone — one ASCII line, no BOM, no trailing whitespace |

Getting it into a running chat, easiest first:

1. **Cursor:** type **refresh pack context** — `agent-defaults-always.mdc` sends the agent to the brief; nothing is copied.
2. **Clipboard:** the command already put the line there (`-NoClipboard` opts out); press Ctrl+V.
3. **File:** open `docs/AGENT_PASTE.txt` and copy the whole line.

Do not select the line out of the console window — wrapped output is where copies pick up line breaks
and stray spaces. The line ends by asking the agent to reply with the two version numbers, so a bare
"ok" tells you it never read the files and you should paste again.

Versions come from the pack at generation time, so the paste line never carries a stale number.
`Update-AgentRules.cmd` reports profile-level changes; this reports them per project and leaves a
file the agent can read later.

### After audit template changes in a reference application

```powershell
sync-audit-system.ps1 -PushFromProject -ProjectRoot "C:\Users\alice\Projects\MyApp"
```

Then `install.ps1` + `verify-audit-system.ps1` on the pack.

---

## Project-only rules (never in pack)

Examples — **stay in the app repo**, thin wrappers OK:

| File | Role |
|------|------|
| `agent-readiness.mdc` | Product session audit, stack-specific bootstrap |
| `audit.mdc` | Product audit entry |
| `product-reference.mdc` | Product truth pointer |
| `design-tier-gate.mdc` | Upgrade / ROADMAP build gate |
| `version-sync.mdc` | Product version source module |
| `terminal-and-build-hygiene.mdc` | Wrapper → generic rule + project build bats |

Pattern for wrappers: follow **`generic-terminal-and-build-hygiene.mdc`** style — link to pack rule, add only project paths/commands.

---

## Drift checks

| Command | Catches |
|---------|---------|
| **`Verify-AgentSetup.cmd`** (pack root) | Install + optional reference project checks |
| `Refresh-AgentContext.cmd` (pack root) | Syncs a project and writes `docs/AGENT_CONTEXT.json` + `docs/AGENT_REFRESH.md`; reports installed-vs-pack drift |
| `Update-AgentRules.cmd` (pack root) | Refreshes the install and reports what changed in the profile (`update-agents.ps1`); optional project rule sync (`%1` = ProjectRoot) |
| `doctor.ps1` | Missing global rules/skills/MCP |
| `sync-project-rules.ps1 -VerifyOnly` | Project copy of generic rules ≠ pack |
| `sync-audit-system.ps1 -VerifyOnly` | Audit template drift |
| `verify-audit-system.ps1` | Manifest + installed copies |
| `verify-audit-behavior.ps1 -DualShell` | Runs the whole suite on the *other* PowerShell host too |

---

## PowerShell hosts

The pack's floor is **Windows PowerShell 5.1** — it ships with Windows, so the pack works on a machine
with nothing installed. PowerShell 7 runs everything correctly but is not the host: a child shell costs
roughly 250 ms on 7 against 130 ms on 5.1, and an audit spawns dozens of them.

If you develop on a machine with PowerShell 7, know that **running a script directly from a `pwsh`
prompt hosts it on 7, while the `.cmd` entry points pin themselves to 5.1** — the same checkout, two
hosts. `doctor.ps1` names the host it ran under and warns when that is 7.

Before shipping changes that write files, run the suite on both:

```powershell
.\pack\scripts\verify-audit-behavior.ps1 -DualShell
```

Behavior step 29 already checks the difference that matters on every run (BOM-free writer bytes and
parsed-JSON parity), so `-DualShell` is for the belt-and-braces pass. All text output must go through
**`Write-Utf8NoBom`** / **`Add-Utf8NoBomLine`** in `pack-paths.ps1`; step 29 fails if a second copy or
an inline `UTF8Encoding($false)` write appears.

---

## Related

- `START_HERE.md` — install and onboarding
- `AUDIT_SYSTEM.md` — audit sync (`-PushFromProject`)
- `AGENT_WORKFLOW.md` — loop-back and audit workflow

---

## Deferred backlog (not scheduled)

| Item | When | Doc |
|------|------|-----|
| **Multi-agent coordination** | Revisit when moving to a **new agent program/model** (post–Cursor) | [`AGENT_COORDINATION_BACKLOG.md`](AGENT_COORDINATION_BACKLOG.md) |

No implementation until user directs — see backlog docs.
