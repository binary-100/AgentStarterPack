# Agent Starter Pack

Portable **audit protocol**, **terminal/build hygiene**, and **new-project bootstrap** for AI coding agents (Cursor-first, multi-tool portable).

**New here?** Read **[pack/docs/START_HERE.md](pack/docs/START_HERE.md)** — install, agent pre-flight, project bootstrap, audits, and common pitfalls.

---

## Quick install

**Double-click:** `Install-AgentStarterPack.cmd`

Then verify:

```powershell
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\doctor.ps1"
& "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\verify-audit-system.ps1"
```

Restart Cursor after install (MCP).

Details: **[INSTALL.md](INSTALL.md)**

---

## Audits

| You say | What happens |
|---------|----------------|
| **audit** | `run_audit.cmd` + `docs/AUDIT.md` → **Fix** and **Improve** only |

One closed-scope audit per run. No Phase A/B. No add-ons menus.

Maintenance: **[pack/docs/AUDIT_SYSTEM.md](pack/docs/AUDIT_SYSTEM.md)**  
Agent workflow: **[pack/docs/AGENT_WORKFLOW.md](pack/docs/AGENT_WORKFLOW.md)**

**This repo (pack self-audit):** `run_audit.cmd` at the pack root — audits the pack itself including sync verify. See `docs/AUDIT.md`.

---

## What's inside

| Component | Purpose |
|-----------|---------|
| [pack/docs/START_HERE.md](pack/docs/START_HERE.md) | **Main guide** for agents and users |
| [pack/docs/README.md](pack/docs/README.md) | Documentation index |
| [docs/PORTABLE_SETUP.md](docs/PORTABLE_SETUP.md) | **Bootstrap any project for any AI tool** |
| [docs/MULTI_INSTANCE_GUIDE.md](docs/MULTI_INSTANCE_GUIDE.md) | Multi-project / multi-PC setup |
| [docs/VERSION_SYNC.md](docs/VERSION_SYNC.md) | Version single-source pattern (Python) |
| [pack/docs/PHASED_FEATURE_DESIGN.md](pack/docs/PHASED_FEATURE_DESIGN.md) | Multi-step features — phased plans |
| [pack/docs/AUDIT_SYSTEM.md](pack/docs/AUDIT_SYSTEM.md) | Audit engine architecture and sync |
| [pack/scripts/verify-audit-system.ps1](pack/scripts/verify-audit-system.ps1) | Wiring, drift, behavior self-test |
| [pack/scripts/doctor.ps1](pack/scripts/doctor.ps1) | Install verification |
| [pack/skills/](pack/skills/) | agent-code-audit, terminal/gui hygiene |
| [pack/templates/](pack/templates/) | Per-project audit and bootstrap stubs |

---

## New project

1. Install once per machine (above).
2. **`Bootstrap-Project.cmd D:\your\repo YourApp`** or **`bootstrap-project.ps1`** — see [docs/PORTABLE_SETUP.md](docs/PORTABLE_SETUP.md).
3. Customize `docs/AUDIT.md` domain map.

---

## Reference project

**BSOD Analyzer** (`Desktop\BSODAnalyzer\app\`) — full Python/Qt implementation with version sync and product audit.

---

## Versions

| File | Meaning |
|------|---------|
| Root **`VERSION`** | Starter pack release (**1.7.0**) |
| **`pack/audit/manifest.json`** | Audit engine version (**2.21.6**) |

Pack history: **[CHANGELOG.md](CHANGELOG.md)**  
Audit engine history: **[pack/docs/AUDIT_SYSTEM_CHANGELOG.md](pack/docs/AUDIT_SYSTEM_CHANGELOG.md)**
