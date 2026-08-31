# Changelog

## 1.8.0 — 2026-08-30

### Maintainer hygiene + rules consolidation

- Canonical status propagation in work-queue / doc-hygiene rules; `pack/docs/RULES_AND_VERIFY_MAP.md`
- `verify-complete-picture.ps1` — Done-WQ vs stale parked/not-built checks; more handoff sources
- `Update-AgentStack` runs complete-picture verify on maintainer pack repo
- Removed legacy **`AGENT_CHAT_SYNC.md`** (superseded by `Refresh-AgentContext.cmd` / `AGENT_REFRESH.md`)
- `docs/VERSION_SYNC.json` — **`docs/WORK_QUEUE.md`** header in maintainer doc sync (S2-9)

## 1.7.0 — 2026-08-16

### Rebrand: Agent Starter Pack

- **Renamed** product from "Cursor Agent Starter Pack" to **Agent Starter Pack** / **AgentStarterPack**
- **Folder:** `CursorAgentStarterPack` → `AgentStarterPack` (Desktop + canonical `%USERPROFILE%\.cursor\AgentStarterPack\`)
- **Installer:** `Install-CursorAgentStarterPack.cmd` → `Install-AgentStarterPack.cmd`
- **Added:** `pack/scripts/pack-paths.ps1` — path resolution with legacy fallbacks (`agent-starter-pack`, `CursorAgentStarterPack`, `CURSOR_STARTER_PACK_ROOT`)
- **Migration:** `install.ps1` moves legacy `.cursor\agent-starter-pack` to `.cursor\AgentStarterPack` on upgrade
- **Updated:** all docs, templates, app reference paths, bootstrap scripts

## 1.6.0 — 2026-08-16

### Portable / multi-tool bootstrap

- **Added:** `pack/scripts/bootstrap-project.ps1` — one command to wire audit, AGENTS, ROADMAP, tool-specific instruction files
- **Added:** `Bootstrap-Project.cmd` — one-click Python + All targets bootstrap
- **Added:** `pack/scripts/register-portable-mcp.ps1` — Claude Desktop MCP registration
- **Added:** `docs/PORTABLE_SETUP.md` — any AI tool, any project (avoid ad-hoc iteration cycles)
- **Added templates:** `portable/` (CLAUDE, Copilot, Windsurf, AI_INSTRUCTIONS, MCP snippet), `ROADMAP.md`, `KNOWN_LIMITATIONS.md`
- **Updated:** `AGENTS.md.template`, `START_HERE.md`, `README.md`, `MULTI_INSTANCE_GUIDE.md`, `new-project-bootstrap.mdc`
- **Fixed:** `install.ps1` parse error (Unicode em dash in Write-Host string)

## 1.5.0 — 2026-08-10

### Phased feature design (all projects)

- **Added:** `pack/docs/PHASED_FEATURE_DESIGN.md` — one pipeline; runtime order = build order; optional work nested or appendix
- **Added:** `pack/rules/generic-phased-feature-design.mdc` — always-on agent rule
- **Updated:** `AGENT_WORKFLOW.md`, `new-project-bootstrap.mdc`, `AGENTS.md.template`, `README.md`
- Reference example: bootstrapped app phased plan in `docs/*_PLAN.md`

## 1.4.0 — 2026-08-07

### Audit redesign (Fix + Improve only)

- **Removed:** Phase A/B protocol, add-ons menus, `project-audit-overlay.mdc.template`, `run_tests_with_timeout.bat.template`
- **Removed:** `generic-code-audit-checklist.mdc` (replaced by `audit-protocol.mdc`)
- **Added:** `pack/docs/AUDIT_SYSTEM.md` — single maintenance guide for all Cursor touchpoints
- **Added:** `pack/scripts/verify-audit-system.ps1` — detects old audit leftovers
- **Added templates:** `AUDIT.md.template`, `run_audit.ps1.template`, `run_audit.cmd.template`, `audit.mdc.template`
- **Updated:** `agent-code-audit` skill, `agent-defaults-always.mdc`, `AGENTS.md.template`, `new-project-bootstrap.mdc`, `doctor.ps1`
- Reference implementation: `pack/audit/behavior-fixture/` + bootstrap templates

## 1.3.0 — 2026-05-30

### Version sync pattern (from early production apps)

- Rule: `pack/rules/generic-version-sync.mdc`
- Templates: `apply_version.py.template`, `test_version_consistency.py.template`, `version-sync.mdc.template`
- `run_tests.bat.template` — documented sync hook
- Doc: `docs/VERSION_SYNC.md`

## 1.2.0 — 2026-06-10

- MCP terminal hygiene, GUI test skill, AGENTS.md.template

## 1.1.0 — 2026-06-10

- Orphan process scan/cleanup

## 1.0.0

- Initial starter pack
