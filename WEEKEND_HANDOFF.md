# Weekend handoff — Agent Starter Pack

**Written:** 2026-08-28 · **Pack version:** `VERSION` (**1.7.0**) · **Audit engine version:** `pack/audit/manifest.json` (**2.22.10**)
**From:** the working copy at `D:\AgentStarterPack` (flash drive, not the author's main machine)
**For:** whoever picks this up at home over the weekend — human or agent

Standing context lives in **`HANDOVER_NEXT_AGENT.md`** (architecture, rule layers, version-sync model,
command cheat sheet). This file is the short-lived part: how to get the work onto the home machine, what
state it is in, the one portability limit that remains, and what must not be re-litigated.

The versions above are a **snapshot of when this was written**. This file is deliberately *not* in
`docs/VERSION_SYNC.json` — auto-bumping its header would make it claim to describe a state it never
described. If the numbers here are behind `pack/audit/manifest.json`, this file is stale: trust the
changelog and rewrite this one.

---

## 0. Read this first, in this order

1. This file, all of it — it is short.
2. `HANDOVER_NEXT_AGENT.md` — standing context. Section 0 is a five-minute orientation.
3. `pack/docs/START_HERE.md` — install paths, pre-flight, audit maintenance.
4. `pack/docs/AUDIT_SYSTEM_CHANGELOG.md`, newest entries first — the last ten bumps are all from this
   session and explain *why* things are shaped the way they are.

Do not start by running scripts. The repo is in a verified-clean state; read before you disturb it.

---

## 1. Getting the work home — do this before anything else

**There is a git remote.** `origin` → `https://github.com/binary-100/AgentStarterPack.git` (WQ-006, 2026-08-30). Prefer **flash drive copy** or **git pull** on arrival; see `docs/WORK_QUEUE.md` Done log.

```
branch:   master (tracks origin/master)
remote:   https://github.com/binary-100/AgentStarterPack.git
```

Pick one transfer path:

| Path | How | Use when |
|------|-----|----------|
| **Flash drive (simplest)** | Copy the pack folder as-is. Portable by design. | Recommended for offline/USB workflow (**WQ-011**). |
| **Git** | `git clone` or `git pull` from origin. | You want history and CI. |
| **Export archive** | Run `export.ps1` for a clean zip without machine-local `AGENT_*` stamps. | Snapshot without scratch files. |

**Whichever path you choose, verify on arrival before working:**

```
run_audit_tests.bat                      # expect: 0 fail(s), 0 warn(s)
pack\scripts\doctor.ps1 -ProjectRoot .   # expect: no failures
```

If `run_audit_tests.bat` is not clean on the home machine but was clean here, suspect the transfer
(line endings, missing files) before suspecting the code. `.gitattributes` pins `.sh` to LF and
`.cmd`/`.bat` to CRLF for exactly this reason.

---

## 2. State as of this handoff

| Item | State |
|------|-------|
| Audit engine | **2.22.10** |
| Pack release | **1.7.0** (unchanged this session — engine and release version are separate) |
| Test suite | `run_audit_tests.bat` — 0 fail, 0 warn |
| Behavior suite | 32 labelled steps (1–30 plus 5b and the doc/machinery enumerations) |
| Self-audit | Finalizes with **zero Fix and zero Improve** |
| Installed copy | Present at `%USERPROFILE%\.cursor\AgentStarterPack` **on the flash-drive machine only** — the home machine will not have one until someone installs |
| Sync verify | `sync-audit-system.ps1 -VerifyOnly` → OK |

**This session shipped 2.22.6 → 2.22.10.** In brief: doc/script/template/root-entry/MCP sync coverage,
a stale-agent-context finding in the audit, and the tool-neutrality fix for it. Read the changelog for
detail; do not re-derive it from the diff.

---

## 3. The portability limit that remains — the shell, not the editor

Editor neutrality is settled. As of 2.22.8 the pack's instructions live in `AI_INSTRUCTIONS.md` and
`AGENTS.md` (which the Claude, Copilot and Windsurf files delegate to) as well as the Cursor `.mdc`
rules, and behavior step 30 fails if an instruction exists only in the Cursor layer.

**The pack is still Windows-only in practice.** An agent on macOS or Linux cannot use it, even though
PowerShell 7 runs on both. Measured surface:

| Blocker | Count | Why it blocks |
|---------|-------|---------------|
| `.cmd` / `.bat` entry points | 13 | Every user-facing command is a Windows batch wrapper. Only `install.sh` has a shell equivalent. |
| Hardcoded `powershell` / `powershell.exe` calls | 78 across 12 files | `powershell.exe` does not exist off Windows; the cross-platform binary is `pwsh`. Concentrated in `verify-audit-behavior.ps1` (40) and `check-requirements.ps1` (11). |
| `$env:USERPROFILE` | 22 across 11 files | No such variable off Windows; the install root and rules/skills paths all derive from it. |
| Other Windows-only calls | ~10 | `Set-Clipboard` (paste line), `Get-CimInstance` (process hygiene), `OneDrive\Desktop` probing, `winget` suggestions. |

**Scope honestly:** this is not a weekend of typing, it is a design decision with a long tail. The
`.ps1` bodies are mostly portable already; the ties are the wrappers, the shell-invocation strings, and
the profile paths. A sane first slice, if you want to start:

1. Route every internal shell invocation through one helper in `pack-paths.ps1` that picks `pwsh` when
   present and `powershell.exe` otherwise. That single change removes 78 scattered assumptions and is
   testable with the existing `-DualShell` machinery.
2. Derive the install root from a helper instead of `$env:USERPROFILE` directly — `pack-paths.ps1`
   already has `Get-AgentStarterPackUserRoot` and an env override; the remaining 22 uses should go
   through it.
3. Only then consider `.sh` wrappers, and only for the commands a non-Windows user actually needs
   (`run_audit`, `Refresh-AgentContext`, `Bootstrap-Project`, `Check-Requirements`).

**Decide before building:** is non-Windows support a real goal, or is "Windows + any editor" the
intended reach? The pack's docs currently imply the latter without saying so. If it is the latter, say
so explicitly in `docs/PORTABLE_SETUP.md` and close this out — an honest limit beats an implied promise.
Guard against half-measures: a `.sh` wrapper that calls a script full of `powershell.exe` is worse than
no wrapper, because it looks supported.

---

## 4. Other things that need calling out

**The unmirrored-file defect appeared six times.** Rules, skills, docs, scripts + templates, root entry
points, and finally the MCP server. Each time, files shipped into the user's profile by `install.ps1`
were missing from `packMirror`, so a later fix in the pack never reached the installed copy that people
actually run. All six classes are now **enumerated** in behavior step 5b rather than listed by name.
**If you add a new class of shipped file, add a directory enumeration for it in the same step** — six
repeats say that listing filenames does not hold.

**Every engine bump makes this repo's own context stamp stale**, so a maintainer sees the new
"Agent context stale" Improve after each bump. That is correct behaviour (your open chats *are* stale),
and one approved `Refresh-AgentContext.cmd` clears it. If it becomes noise during heavy bumping,
suppressing it for the pack repo itself is a reasonable change — it was left in deliberately.

**Version citations must be parenthesized to be tracked.** `doc_version_sync.py` only rewrites cites
shaped like `(**2.22.10**)`. A bare `= **2.22.10**` is silently skipped, and `--verify` still reports
`ok: true` — a false green that already bit once. `docs/VERSION_SYNC.md` documents the pattern.

**Version sync is a build step, not an audit step.** Run `Sync-DocVersions.cmd` (or `apply_version.py
sync`) when versions change. Do not let an agent "fix" version drift during an audit.

**The audit workflow is three commands and the order matters.** `run_audit.cmd` (never with
`-SkipTests`), then fill `docs/.audit_semantic_report.json`, then `scripts\finalize_audit.cmd`. A
`-SkipTests` run wipes the test-pass proof and finalize will refuse to certify — that happened in this
session and the gate correctly blocked it.

**A machine-local rule lives outside the pack.** `structured-chat-output.mdc` sits in
`%USERPROFILE%\.cursor\rules\` on the flash-drive machine only. It is a response-formatting preference,
deliberately **not** part of the pack, and it will not exist at home. If home agents format differently,
that is why. Do not add it to `pack/rules/`.

**PowerShell:** 5.1 is the floor and the preferred host (faster process startup, which is what this
workload is bound by); 7.x is supported and verified. `verify-audit-behavior.ps1 -DualShell` runs the
whole suite on both hosts. Every pack script declares `#Requires -Version 5.1` except the dot-sourced
`pack-paths.ps1`.

**Edit boundary.** When this repo is the workspace, only write inside it. Other projects named in docs
are read-only references. Do not run sync/bootstrap scripts against external project paths.

---

## 5. Deliberately deferred — do not rebuild these

| Item | Status | Why |
|------|--------|-----|
| **Phase 6b** — MCP tools (`check_pack_freshness`, `get_agent_refresh_brief`) | **Shipped (WQ-301)** | Engine **2.22.21**; behavior step **35**. Historical row kept — see `docs/WORK_QUEUE.md` Done log. |
| **Phase 6c** — agent mailbox / coordination | Parked (**WQ-302**) | `pack/docs/AGENT_COORDINATION_BACKLOG.md` holds the design. |
| **Spec §4.10** — staleness warning in `verify-agent-setup.ps1` | Declined | It is another command you must remember to run, so it would only speak up in a session where you were already looking. The audit finding replaced it and reaches you unprompted. |
| **`AGENT_REFRESH.md.template`** | Not created | The brief is generated per refresh; a template stub would be a brief that states nothing while looking authoritative. |
| **Non-Windows support** | Open question | See § 3. Needs a decision before code. |

`PACK_IMPLEMENTER_SPEC.md` and `PACK_IMPLEMENTER_HANDOFF.txt` in this repo are **incoming** specs from
the other machine. Both assigned tracks (Phase 6a, Section 12) are fully implemented; their internal
"Not implemented" markers were corrected in this session. Treat them as history, not a work queue.

---

## 6. Suggested weekend order

1. **Transfer and verify** (§ 1). Do not skip the verify — it takes two minutes and tells you whether
   anything moved badly.
2. **Decide the non-Windows question** (§ 3). It is a decision, not a task; make it before writing code.
3. If the answer is *Windows-only*: state the limit plainly in `docs/PORTABLE_SETUP.md`, note it in
   `HANDOVER_NEXT_AGENT.md`, and this thread is closed.
4. If the answer is *support non-Windows*: do slice 1 only (single shell-invocation helper), run
   `-DualShell`, and stop there for the weekend. Resist adding `.sh` wrappers in the same pass.
5. Whatever you touch: bump `pack/audit/manifest.json`, add a changelog entry, run
   `sync-audit-system.ps1`, then `run_audit_tests.bat` to 0 fail before you stop.

**Leaving it mid-flight?** Update `HANDOVER_NEXT_AGENT.md` with what you actually changed, and delete or
rewrite this file — a stale weekend handoff is worse than none, which is the same lesson the six
unmirrored-file repeats taught.
