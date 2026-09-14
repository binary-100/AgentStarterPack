# StarterPack-Airlock — discovery consumers and overlay merge

**Status:** Phase 4 — discovery + refresh overlay merge shipped (2026-09-13, WQ-487)  
**Related:** `docs/STARTERPACK_AIRLOCK_PLAN.md`, `docs/AUDIT_AIRLOCK_COVERAGE.md`, WQ-465, WQ-483

---

## Discovery today (single-tree)

`Get-AgentStarterPackCandidates` in `pack/scripts/pack-paths.ps1` resolves, in order:

1. `Get-SourceAgentStarterPack` (script-relative checkout)
2. `$env:AGENT_STARTER_PACK_ROOT`
3. `$env:CURSOR_STARTER_PACK_ROOT`
4. `%USERPROFILE%\.cursor\AgentStarterPack` (and legacy profile folder names scanned by the same function)
5. Windows Desktop paths: OneDrive-redirected and native Desktop folders named like the pack root (see `Get-AgentStarterPackCandidates` in `pack/scripts/pack-paths.ps1`)

`Get-AgentStarterPackRoot` returns the **first** candidate where `Test-AgentStarterPackRoot` passes (manifest present).

**Shipped (M01):** `Find-StarterPackAirlock` resolves Desktop Airlock when the key and overlay validate; `Get-AgentStarterPackPublishRoot` returns `repo/` when active; **`refresh-agent-context.ps1`** merges overlay **`requiredReads`** when discovery is active (WQ-487). **Dual-zone verify (M05/B10/B11):** `verify-audit-system.ps1 -PublishRoot` + **`verify-airlock-publish-gate.ps1`** (WQ-488, behavior step **86**).

**Discovery API (Phase 1 shipped):**

| Function | Role after Airlock |
|----------|-------------------|
| `Get-AgentStarterPackRoot` | Primary pack tree for install, audit, develop — working copy or checkout |
| `Find-StarterPackAirlock` | Desktop Airlock when `publisher.key` + overlay manifest validate |
| `Get-AgentStarterPackPublishRoot` | Airlock `repo/` when active; else `$null` |

---

## Scripts that call pack discovery (inventory)

| Script | Uses | Airlock impact |
|--------|------|----------------|
| `pack/scripts/pack-paths.ps1` | Defines candidates | **Owner** — Phase 1 adds Airlock |
| `pack/scripts/verify-audit-behavior.ps1` | `Get-AgentStarterPackRoot`, `-PackRoot` param | Zone B: `-PackRoot` must accept Airlock `repo/` |
| `pack/scripts/verify-audit-system.ps1` | Candidates + root | **Shipped:** `-PublishRoot` Zone B behavior pass (WQ-488) |
| `pack/scripts/refresh-agent-context.ps1` | Root + install | **Shipped:** merge overlay `requiredReads` when Airlock active (WQ-487) |
| `pack/scripts/run_audit_core.ps1` | Root fallback | Publish audit targets `repo/` |
| `scripts/run_audit.ps1` | Candidates | Same |
| `pack/scripts/check-requirements.ps1` | Root | Unchanged |
| `pack/scripts/bootstrap-project.ps1` | Root | Must **not** create Airlock (S10) |
| `pack/scripts/sync-project-rules.ps1` | Root | Unchanged |
| `pack/scripts/sync-doc-versions.ps1` | Root | Unchanged |
| `pack/scripts/update-agent-stack.ps1` | Root | Unchanged |
| `pack/scripts/update-agents.ps1` | Root | Unchanged |
| `pack/scripts/verify-agent-setup.ps1` | Root | Optional `-PublishRoot` later |
| `pack/scripts/verify-guard-proofs.ps1` | Root | WQ-481: sandbox install root in job |
| `pack/scripts/register-portable-mcp.ps1` | Root | Unchanged |
| `pack/scripts/register-tool-adapters.ps1` | Root | Unchanged |
| `pack/scripts/repair-agent-docs.ps1` | Root | Unchanged |
| `pack/scripts/ensure-work-queue.ps1` | Root | Unchanged |
| `pack/scripts/ensure-work-completion.ps1` | Root | Unchanged |
| `pack/scripts/sanitize-machine-state.ps1` | Root | Unchanged |
| `pack/scripts/archive-completed-handoff.ps1` | Root | Unchanged |
| `pack/scripts/verify-portable-bootstrap.ps1` | Root | Unchanged |
| `pack/scripts/test-os-portability-probe.ps1` | Candidates | Document Airlock paths in probe notes |
| `pack/scripts/simulate-airlock-scenarios.ps1` | Root + sim discovery | Pre-Phase-1 harness |

---

## Overlay and work-queue merge (H04)

Two channels exist after Airlock ships:

| Channel | Location | Owns |
|---------|----------|------|
| **Project WQ** | Working copy `docs/WORK_QUEUE.md` | Maintainer dev priority — **canonical Next** for day-to-day work |
| **Overlay reads** | `StarterPack-Airlock/overlay/docs/` | Publish/CI maintainer notes — **requiredReads only**, not a second Next |

**Merge rules (Phase 4 `refresh-agent-context.ps1`):**

1. **Never** copy overlay `WORK_QUEUE.md` into the working copy tree.
2. Append overlay `requiredReads` (absolute paths under Airlock) to `AGENT_CONTEXT.json` when discovery is active.
3. **`handoff-first.mdc` order unchanged:** SESSION → project `WORK_QUEUE.md` → overlay reads are **extra requiredReads**, not a second priority table.
4. Overlay `WORK_QUEUE.md` (if present) is **publish-lane status only** — rows reference WQ ids from the project file; it does not define a competing **Next**.
5. Agents in the **working copy** must not treat overlay prose as overriding project WQ **Next**.

**Verify (shipped):** behavior step **84** — when Airlock active, refresh merge includes overlay `requiredReads`; project `docs/WORK_QUEUE.md` remains the only WQ file in the working copy.

---

## Which folder to open in Cursor (M02)

| You are doing | Open this workspace root | Proof mode |
|---------------|--------------------------|------------|
| **Day-to-day pack development** | Working copy (`AgentStarterPack/` on Desktop or this checkout) | Zone A — git-free OK; hooks + `.cursor/rules/` load; `run_audit.cmd` uses content fingerprint |
| **Publish / CI / git operations** | `StarterPack-Airlock/repo/` only | Zone B — git index arms (step 62) run; **human** `git push` from here |
| **Never for routine dev** | `StarterPack-Airlock/` overlay folder alone | No pack tree — discovery only |

Opening `repo/` for daily edits loads git proof and may SKIP Zone A assumptions; opening the working copy for push hits policy refusal on `git push` (by design — H01). **Before push:** run **`Verify-AirlockPublishGate.cmd`** from the working copy (Zone A + sync + Zone B).

### Parallel period (both trees have git — WQ-489)

After **`Initialize-StarterPackAirlock.cmd -GitMode Copy`**, the working copy **still has `.git`** while `repo/` receives a copy. Dev and git history stay on the familiar checkout until **`Complete-StarterPackAirlockCutover.cmd`** removes working-copy `.git` only. Sim **S29** proves the sequence.

---

## Agent policy by zone (H01 preview)

| Zone | Policy source | Publish `git push` |
|------|---------------|-------------------|
| Working copy | `.agent-control/policy.json` (synced template) | **Refuse/ask** — human or Airlock repo workspace |
| Airlock `repo/` | Planned: `repo/.agent-control/policy.json` overlay at sync | **Allow ask path** for maintainer publish commands only |

Working-copy policy stays strict. Publish policy is compiled into `repo/` during `sync-working-copy-to-airlock-repo.ps1` (Phase 2/3), not by editing the working copy template alone.

Sim **S21** exercises working-copy refusal; **S26** exercises B09 sync. Repo overlay policy compile at sync is still Phase 2/3 (H01).
