# OS portability plan (WQ-304)

**Status:** Phase 6 complete · **Reopened:** 2026-08-30 (user)  
**Supersedes:** WQ-004 interim “document Windows-first and defer” — that was maintainer scope documentation, not a permanent platform veto.

**Prior analysis:** `WEEKEND_HANDOFF.md` §3 (blocker inventory), `docs/PORTABLE_SETUP.md` § Platform scope.

---

## Goal

Run the **same maintainer workflows** on Windows, macOS, and Linux where PowerShell 7 (`pwsh`) is installed — without `.cmd` wrappers or hardcoded `powershell.exe` / `%USERPROFILE%` assumptions.

**Not in scope for WQ-304:** re-platforming Python to drop `py -3` on Windows projects; Cursor session hooks on non-Windows (Cursor layout differs).

---

## Phased checklist

| Phase | Deliverable | Status |
|-------|-------------|--------|
| **1** | `pack-paths.ps1` — `Get-PackPowerShellPath`, `Invoke-PackScript`, cross-platform user root (`$HOME/.cursor`) | ☑ |
| **1b** | `install.sh` delegates to `install.ps1` via `pwsh` when available | ☑ |
| **2** | Route nested spawns in core scripts through `Invoke-PackScript` (install, refresh, check-requirements, verify-audit-behavior, …) | ☑ |
| **3** | `Check-Requirements` / `doctor` — `python3` probe on non-Windows; drop Windows-only winget/OneDrive probes when not on Windows | ☑ |
| **4** | `.sh` entry points for bootstrap, refresh, audit (thin `pwsh -File` wrappers) | ☑ |
| **5** | Behavior step: mock `$IsLinux` user-root resolution + `Invoke-PackScript` smoke | ☑ |
| **6** | Document verified matrix in `PORTABLE_SETUP.md`; optional CI job on `ubuntu-latest` + `pwsh` | ☑ |

Runtime order = build order — no phase skips.

---

## Phase 1 detail

### Shell helper contract

- **Windows child spawns:** `powershell.exe` when present (speed — see `AUDIT_SYSTEM.md` § PowerShell hosts).
- **Non-Windows:** `pwsh` only.
- **Direct interactive use:** user may run any script from `pwsh` on any OS.

### User profile layout (all OS)

| Path | Role |
|------|------|
| `$HOME/.cursor/AgentStarterPack` | Installed pack mirror |
| `$HOME/.cursor/rules` | Global rules |
| `$HOME/.cursor/skills` | Global skills |

Override: `AGENT_STARTER_PACK_INSTALL_ROOT` (unchanged).

---

## Verification

| Gate | When |
|------|------|
| `verify-audit-behavior.ps1` step 40+ | After Phase 1 |
| `verify-audit-behavior.ps1` step 43 (mock Linux) | After Phase 5 |
| `test-os-portability-probe.ps1` on native Linux/macOS | After Phase 5–6; also in `.github/workflows/pack-os-smoke.yml` |
| Manual `pwsh install.ps1` on macOS/Linux | After Phase 2–4 |
| `sync-audit-system.ps1 -VerifyOnly` | Every engine bump |
