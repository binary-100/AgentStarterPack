# AGENTS.md

Instructions for AI coding agents working in **Agent Starter Pack** (this repo).

**Read first:** `pack/docs/START_HERE.md`

**Continuing from a prior session?** Read **`docs/WORK_QUEUE.md`** - the canonical radar and the only status claim (a separate session doc was retired in 2.22.65). Per-release reasoning: **`pack/docs/AUDIT_SYSTEM_CHANGELOG.md`**. Rules vs verify inventory: **`pack/docs/RULES_AND_VERIFY_MAP.md`**. Post-ship checklist: **`pack/docs/WORK_COMPLETION.md`**.

**Phase 6a is shipped.** Its spec and the implementer notes were deleted once implemented — `pack/docs/AUDIT_SYSTEM_CHANGELOG.md` and the `docs/WORK_QUEUE.md` Done log are the record. Do not re-build it.

## Edit boundary (hard stop)

**Only modify this repo** — the open workspace root (the folder holding `VERSION`, `install.ps1`, and `pack/`). The pack is portable, so that root can be any drive or path; never assume a machine-specific location.

Other projects (bootstrapped apps, external repos, etc.) may be **referenced** in docs and templates — that is **not** permission to edit them. Do not run pack sync/bootstrap scripts against external project paths. If work requires another repo, instruct the user or ask them to open that workspace.

Rules (always on in this workspace):

- `.cursor/rules/pack-only-edit-boundary.mdc` — edit boundary
- `.cursor/rules/agent-recommendation-discipline.mdc` — how to recommend and execute changes

Global (all projects, via `pack/rules/` + `install.ps1`):

- `pack/rules/generic-agent-doc-hygiene.mdc` — read existing agent docs before adding rules or `AGENTS.md`
- `pack/rules/generic-deep-task-execution.mdc` — mandatory depth contracts for deep compare / full scan; agent-owned, not user phrasing
- `pack/rules/generic-work-queue-discipline.mdc` — stable WQ IDs; update `docs/WORK_QUEUE.md` before changing priority lists

## Recommendations

When proposing or executing work here:

1. **Default first** — smallest correct fix; no invented alternatives.
2. **Scope before action and before Shell/Write** — target paths, layer, writes elsewhere?, does not affect, downside.
3. **Read before add** — follow `generic-agent-doc-hygiene.mdc`.
4. **Rule layers** — workspace-only in `.cursor/rules/`; generic in `pack/rules/` only.
5. **Optional extras** — only if needed; each needs mechanism, blast radius, and “skip unless.”
6. **Install** — only when you asked; call out `%USERPROFILE%\.cursor\` paths that will change.
7. **Scripts** — no hardcoded external project paths as defaults; use parameters.
8. **Version bumps** — build pipeline: `Sync-DocVersions.cmd` or `apply_version.py sync` / `run_tests.bat` (see `docs/VERSION_SYNC.json`). Not an audit step.

## Project

- **Name:** Agent Starter Pack
- **Version file:** `VERSION` (canonical)
- **Test command:** `run_audit_tests.bat` (behavior + system verify)
- **Self-audit:** `run_audit.cmd` → report per `docs/AUDIT.md` (Fix + Improve only)
- **Install:** `Install-AgentStarterPack.cmd` (or `install.ps1 -Scope User`). Do not run `-Scope Both`
  from this folder: project scope copies every global rule into this repo's `.cursor\rules\`,
  which is reserved for the workspace-only rules.
- **Bootstrap new apps:** `Bootstrap-Project.cmd`

## Before long shell commands

Use **agent-hygiene** MCP when available:

1. `agent_hygiene_full_check`
2. After force-kill: `cleanup_orphan_agent_processes` (`dry_run=True` first)

Without MCP: `pack\scripts\cleanup-orphan-processes.ps1`

## Audits

**Pack self-audit:** `run_audit.cmd` on this repo (machine + semantic + sync verify).

**Audit system maintenance** (after editing pack audit files): `pack\scripts\sync-audit-system.ps1` then `pack\scripts\verify-audit-system.ps1` exit 0.

**Product audits** (bootstrapped apps, etc.): use that project's `run_audit.cmd` — not this pack's unless auditing the pack itself.

Say **audit** in this workspace → follow `docs/AUDIT.md`. Report only **Fix** and **Improve**.

## Verify install

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\doctor.ps1" -ProjectRoot (Get-Location).Path
```

## Documentation

| Doc | Purpose |
|-----|---------|
| `pack/docs/START_HERE.md` | Onboarding |
| `pack/docs/PACK_MAINTENANCE.md` | Pack ↔ project sync — generic rules, no forks |
| `pack/docs/AUDIT_SYSTEM.md` | Audit architecture |
| `docs/PORTABLE_SETUP.md` | Multi-tool / portable MCP |
