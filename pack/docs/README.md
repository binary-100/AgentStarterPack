# Pack documentation index

All paths relative to **`AgentStarterPack/`** (Desktop) or **`%USERPROFILE%\.cursor\AgentStarterPack\`** (after install).

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
4. BSOD Analyzer `app/` — reference layout

### Pack / audit-system maintainer

1. [START_HERE.md](START_HERE.md) → Maintaining the audit system
2. [AUDIT_SYSTEM.md](AUDIT_SYSTEM.md)
3. [AUDIT_SYSTEM_CHANGELOG.md](AUDIT_SYSTEM_CHANGELOG.md)
4. [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) → Audit pre-flight
