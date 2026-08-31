# Pack documentation index

All paths relative to the **pack folder** (this checkout, on any drive) or **`%USERPROFILE%\.cursor\AgentStarterPack\`** (after install).

---

## Start here

| Document | Summary |
|----------|---------|
| **[START_HERE.md](START_HERE.md)** | **Main entry point** — install, layout, agent pre-flight, bootstrap, audits, hygiene, pitfalls |

---

## Workflow and design

| Document | Summary |
|----------|---------|
| [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) | Loop-back protocol, pre-flight, audit Fix/Improve workflow, artifact ownership |
| [PHASED_FEATURE_DESIGN.md](PHASED_FEATURE_DESIGN.md) | Multi-step features — phased plans; runtime order = build order |
| [PACK_MAINTENANCE.md](PACK_MAINTENANCE.md) | Pack ↔ project sync — generic rules, no forks |
| [AGENT_COORDINATION_BACKLOG.md](AGENT_COORDINATION_BACKLOG.md) | Multi-agent coordination — deferred until new agent stack |
| [AUDIT_SYSTEM.md](AUDIT_SYSTEM.md) | Audit architecture, manifest, sync/verify commands, reference project flow |
| [AUDIT_SYSTEM_CHANGELOG.md](AUDIT_SYSTEM_CHANGELOG.md) | Audit engine version history and settled decisions (maintainers) |

---

## Root-level docs (`docs/`)

| Document | Summary |
|----------|---------|
| [../../docs/README.md](../../docs/README.md) | Index of root guides |
| [../../docs/PORTABLE_SETUP.md](../../docs/PORTABLE_SETUP.md) | Bootstrap any project for any AI tool |
| [../../docs/MULTI_INSTANCE_GUIDE.md](../../docs/MULTI_INSTANCE_GUIDE.md) | One install per PC, MCP, other IDEs, export |
| [../../docs/VERSION_SYNC.md](../../docs/VERSION_SYNC.md) | Single-source version pattern for Python apps |

---

## Folder map

What each top-level folder is for, so a reviewer can tell source from generated output at a glance.

| Folder | Role | Committed |
|--------|------|-----------|
| `pack/rules/` | Generic rules installed to `%USERPROFILE%\.cursor\rules\` | Yes — source |
| `pack/skills/` | Skills installed to `%USERPROFILE%\.cursor\skills\` | Yes — source |
| `pack/scripts/` | Install, sync, verify, audit engine | Yes — source |
| `pack/templates/` | Files copied into bootstrapped projects | Yes — source |
| `pack/audit/` | Audit manifest + behavior fixture (a fake project the suite audits) | Yes — source |
| `pack/docs/` | Pack documentation | Yes — source |
| `docs/` | This repo's own audit config, checklist, and guides | Yes, except `.audit_*` artifacts and the generated agent-context files |
| `scripts/` | This repo's own audit wrappers | Yes — source |
| `dist/` | Export output from `export.ps1` | No — ephemeral, recreated per export |
| `.tmp/` | Scratch roots for self-tests | No — ephemeral, per-process |

---

## Related files outside `pack/docs/`

| File | Summary |
|------|---------|
| [../../README.md](../../README.md) | Short overview + links |
| [../../INSTALL.md](../../INSTALL.md) | Install steps and verify commands |
| [../../CHANGELOG.md](../../CHANGELOG.md) | Starter pack release notes (1.x) |
| [../audit/manifest.json](../audit/manifest.json) | Audit engine file manifest and version |
| [../skills/agent-code-audit/SKILL.md](../skills/agent-code-audit/SKILL.md) | Audit skill loaded by Cursor agents |
| [../rules/](../rules/) | Generic rules copied to `%USERPROFILE%\.cursor\rules\` |
| [../templates/](../templates/) | Per-project bootstrap templates |

---

## Reading paths by role

### Cursor agent (any project)

1. Project `AGENTS.md` / `README`
2. [START_HERE.md](START_HERE.md) — if unfamiliar with the pack
3. [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) — before audits or sustained work
4. Skill `agent-code-audit` — when user says "audit"

### New project bootstrap

1. [START_HERE.md](START_HERE.md) → Bootstrap section
2. [../../docs/VERSION_SYNC.md](../../docs/VERSION_SYNC.md) — if Python
3. [AUDIT_SYSTEM.md](AUDIT_SYSTEM.md) — customize `AUDIT.md` + config
4. `pack/audit/behavior-fixture/` — minimal audit example in the pack repo

### Pack / audit-system maintainer

1. [START_HERE.md](START_HERE.md) → Maintaining the audit system
2. [PACK_MAINTENANCE.md](PACK_MAINTENANCE.md) — generic rules and reference-project sync
3. [AUDIT_SYSTEM.md](AUDIT_SYSTEM.md)
3. [AUDIT_SYSTEM_CHANGELOG.md](AUDIT_SYSTEM_CHANGELOG.md)
4. [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) → Audit pre-flight
