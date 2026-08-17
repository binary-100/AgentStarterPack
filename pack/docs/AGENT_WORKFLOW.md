# Agent workflow

Loop-back and pre-flight for **all projects**. Audit-specific rules (Fix/Improve) are in the **Audit workstreams** section below.

**New to the pack?** Read **`START_HERE.md`** first (install, bootstrap, hygiene, pitfalls).

Location: `%USERPROFILE%\.cursor\AgentStarterPack\pack\docs\AGENT_WORKFLOW.md` (also on Desktop `AgentStarterPack`).

---

## Loop-back protocol (all projects)

Use whenever the user **repeats** the same concern, error, or question — not only for audits.

### Triggers (examples)

- “Still broken”, “same error”, “you already tried that”
- “Anything else?”, “what did you miss?”, “check everything again”
- “We keep going in circles”, “this didn’t work last time”
- Same ask after you said it was fixed or done
- User reframes the **same goal** with more frustration

### Stop — then loop back

1. **Conversation** — search/read from the **start of this workstream** (transcript, summary, prior attempts, what failed)
2. **Project docs** — `AGENTS.md`, `README`, design notes, open issues, **decisions already made** (do not re-debate without user request)
3. **Code/tests** — what is actually in the repo now vs what you assumed; run relevant tests or verify scripts
4. **Diff intent vs state** — list: decided → implemented → still broken; identify **regressions** (you broke something that worked)
5. **Proceed** — one coordinated plan; avoid isolated one-file patches that ignore prior work

Do **not** retry the same failed approach without new evidence from step 1–4.

### Report format (non-audit projects)

Use whatever the project or user expects (summary, bullet fixes, PR description, etc.).  
If no format is defined: state **what was wrong**, **what you re-read**, **what you’ll do differently**, then act.

### Report format (audit projects)

**Fix** and **Improve** only — see **Audit workstreams** below.

---

## Pre-flight (before a sustained change)

For any multi-step feature, refactor, or “fix it properly” work:

1. Read **`AGENTS.md`** / **`README`** if present
2. Skim **rules** and **skills** loaded for this repo
3. If the user has been in a long thread on one topic → **loop back** first (above)
4. **Multi-step features:** read or write a phased plan per **`PHASED_FEATURE_DESIGN.md`** (runtime order = build order)
5. After edits → run the project’s **test/build/verify** commands before claiming done

---

## Audit workstreams (Fix / Improve only)

When scope is **audit** (product or audit-system tooling):

### Gaps = Fix or Improve

| Category | Meaning |
|----------|---------|
| **Fix** | Remove the gap |
| **Improve** | Mitigate when removal isn’t possible yet |

No third category (“coverage gaps”, “system gaps”, etc.).

### Pre-flight (audit-system changes)

1. **`pack/docs/AUDIT_SYSTEM_CHANGELOG.md`**
2. **`pack/docs/AUDIT_SYSTEM.md`**
3. **`pack/audit/manifest.json`** — bump `"version"`; if adding `codeChecks` keys, extend **`auditConfigTemplate.requiredKeys`**
4. **`pack/templates/docs/AUDIT.config.json.template`** — same new keys as manifest list (generic defaults)
5. **BSOD reference** — `sync-audit-system.ps1 -PushFromProject -ProjectRoot BSODAnalyzer` updates `AUDIT.config.bsod.reference.json`
6. Product audit: **`docs/AUDIT.md`** + **`docs/AUDIT.config.json`** (reference implementation)
7. Skill **`agent-code-audit`**

`verify-audit-system.ps1` **fails** if the template or BSOD reference is missing any key in `manifest.auditConfigTemplate.requiredKeys`.

After audit-system edits:

```powershell
pack\scripts\sync-audit-system.ps1
pack\scripts\verify-audit-system.ps1 -ProjectRoot PATH
```

Changelog entry + bump manifest `"version"`.

### Product audit — one audit, two commands

**Not two audits.** One audit of the product = **machine layer** (automatic) + **semantic layer** (auditor). The semantic report is an **audit-run artifact** in `docs/` (gitignored), filled by the **auditor** using `docs/.audit_agent_manifest.json` — not maintained product source code.

| Step | Who | Command | Tests run? |
|------|-----|---------|------------|
| **1 — Machine pass** | Tooling | `run_audit.cmd` | **Yes** (full suite) |
| **2 — Semantic pass** | **Auditor** | Edit `docs/.audit_semantic_report.json` (template auto-written at step 1 if missing) | No |
| **2b — Verify semantic** | Tooling | `scripts\verify_semantic_audit.cmd` | No |
| **3 — Finalize** | Tooling | `scripts\finalize_audit.cmd` or `run_audit.cmd -FinalizeOnly` | **No** (reuses manifest `testsGitHead`; re-runs machine + semantic verify + harness) |

Use **full `run_audit.cmd` again** only if git HEAD or **source tree fingerprint** changed since step 1 (manifest `testsGitHead` is git SHA or `tree:…` hash when git unavailable).

**Why semantic cannot come before machine:** honest summaries require `machineFixesBySection` from step 1. Writing “Nothing found.” before machine runs would fail semantic-vs-machine alignment.

**Artifacts**

| File | Owner | Committed? |
|------|-------|------------|
| `docs/.audit_agent_manifest.json` | Tooling writes; auditor reads | No |
| `docs/.audit_semantic_report.json` | Tooling template; **auditor fills** | No |

### Product audit rules

- **`run_audit.cmd`** — full tests for step 1; never `-SkipTests` for an audit
- **`finalize_audit.cmd`** — step 3 only; blocked if no manifest test-pass proof or git HEAD changed
- Report **Fix** / **Improve** only
- Load skill **`agent-code-audit`**

**Section L — when `verify-audit-system.ps1` runs inside product audit**

| Gate | Required for harness verify |
|------|----------------------------|
| Semantic report | File exists; all sections reviewed; cites/evidence valid (`verify_semantic_audit.cmd` pass) |
| Sync drift | `sync-audit-system.ps1 -VerifyOnly` exit 0 on this repo |

If semantic is incomplete, harness verify is **skipped** (audit already blocked — completing the semantic report is what unlocks it). If sync drift fails, harness verify is **skipped** (fix sync first; verify would fail anyway).

**Harness verify does not care about** product machine Fix lines (stale README versions, cache cruft, etc.). Those are BSOD findings, not pack wiring failures.

**Keep harness verify passing:** after audit-system edits, run `sync-audit-system.ps1` → `verify-audit-system.ps1` exit 0 before relying on product audit.

### When to claim done (audit)

| Scope | Evidence |
|-------|----------|
| Audit **system** | `verify-audit-system.ps1` exit 0; changelog; sync |
| Product **audit** | Step 1 `run_audit.cmd` + auditor semantic + step 3 `finalize_audit.cmd` (or `-FinalizeOnly`) exit 0; **`machineSectionsWithFixes`** addressed in semantic report |

---

## Quick reference

| File | Scope |
|------|--------|
| `AGENT_WORKFLOW.md` | All projects (this file) |
| `PHASED_FEATURE_DESIGN.md` | Multi-step features — phased plans |
| `loop-back-protocol.mdc` | Always-on rule mirror |
| `AUDIT_SYSTEM_CHANGELOG.md` | Audit tooling decisions |
| `AUDIT_SYSTEM.md` | Audit architecture |
