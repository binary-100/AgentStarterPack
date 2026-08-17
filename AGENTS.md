# AGENTS.md

Instructions for AI coding agents working in **Agent Starter Pack** (this repo).

**Read first:** `pack/docs/START_HERE.md`

## Project

- **Name:** Agent Starter Pack
- **Version file:** `VERSION` (canonical)
- **Test command:** `run_audit_tests.bat` (behavior + system verify)
- **Self-audit:** `run_audit.cmd` → report per `docs/AUDIT.md` (Fix + Improve only)
- **Install:** `Install-AgentStarterPack.cmd` or `install.ps1 -Scope Both`
- **Bootstrap new apps:** `Bootstrap-Project.cmd`

## Before long shell commands

Use **agent-hygiene** MCP when available:

1. `agent_hygiene_full_check`
2. After force-kill: `cleanup_orphan_agent_processes` (`dry_run=True` first)

Without MCP: `pack\scripts\cleanup-orphan-processes.ps1`

## Audits

**Pack self-audit:** `run_audit.cmd` on this repo (machine + semantic + sync verify).

**Audit system maintenance** (after editing pack audit files): `pack\scripts\sync-audit-system.ps1` then `pack\scripts\verify-audit-system.ps1` exit 0.

**Product audits** (BSOD Analyzer, etc.): use that project's `run_audit.cmd` — not this pack's unless auditing the pack itself.

Say **audit** in this workspace → follow `docs/AUDIT.md`. Report only **Fix** and **Improve**.

## Verify install

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\doctor.ps1" -ProjectRoot (Get-Location).Path
```

## Documentation

| Doc | Purpose |
|-----|---------|
| `pack/docs/START_HERE.md` | Onboarding |
| `pack/docs/AUDIT_SYSTEM.md` | Audit architecture |
| `docs/PORTABLE_SETUP.md` | Multi-tool / portable MCP |
