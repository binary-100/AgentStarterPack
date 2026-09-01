# Handoff — bring the primary system up to this pack state and publish it

## Handoff registry

| Field | Value |
|-------|-------|
| **handoff_id** | HANDOFF_WQ011 |
| **kind** | build |
| **status** | active |
| **multi_agent** | no |
| **wq_id** | WQ-011 |
| **plan** | docs/WORK_QUEUE.md (Active → WQ-011) |
| **phases** | transfer → verify → install → publish |
| **agents_remaining** | |
| **completed** | |

**Session opener (only — give the other agent this single line):**

`Read D:\AgentStarterPack\docs\handoffs\active\HANDOFF_WQ011_primary_system_update.md and implement.`

On the primary system that path is wherever the checkout lives — substitute its root, keep the rest.

---

## What this is

The working copy this handoff ships with is **pack 1.8.0 / audit engine 2.22.53**, certified clean but
**never committed** — this machine does not publish, by policy. The primary system is where commits and
pushes happen, so the work has to land there, be verified on that machine, and be pushed from it.

Nothing here is a code change. Every task is transfer, reconciliation, or verification.

## Instructions (for the agent that opens this file)

### 1. Land the tree

Copy the pack folder onto the primary system, or unzip an `export.ps1` archive there, over the existing
checkout. Then, from the checkout root:

```powershell
git status
```

Expect a large diff. Three things in it need deliberate handling rather than a blanket commit:

| What | Why it needs attention |
|------|------------------------|
| **`HANDOVER_NEXT_AGENT.md` deleted, `HANDOFF_NEXT_AGENT.md` added** | Git records a rename as a delete plus an add. Stage the deletion (`git add -A`) or the old file survives beside the new one — the two-document state the rename removed |
| **Four root docs deleted** — two implementer specs, the implementer notes, one superseded transfer stub | Their work shipped; the changelog and `docs/WORK_QUEUE.md` Done log are the record. Do not restore them |
| **New untracked files** | `pack/scripts/audit_common.py`, `audit_version_docs.py`, `audit_install_wiring.py` (engine split), `pack/templates/docs/handoffs/`, `docs/handoffs/` |

```powershell
git add -A
git status        # confirm the deletions are staged, not just the additions
```

### 2. Do not carry the no-publish rule to the publishing machine

`.cursor/rules/no-publish-from-this-machine.mdc` tells an agent never to commit or push. That is true
of the machine it was written on and **false on the primary system** — an agent reading it there would
refuse the very thing you are asking for. It is gitignored for that reason. If it arrives via a folder
copy rather than git, delete it from the primary system's checkout; do not commit it.

### 3. Verify on that machine before publishing

The suite passed here, which says nothing about there — several tests used to grade the machine rather
than the pack, and that class of bug is only visible on a second machine.

```powershell
.\Check-Requirements.cmd          # PowerShell 5.1+, Python 3.8+, the py -3 launcher
.\run_audit_tests.bat             # expect exit 0: 19/19 unit tests, 49 behavior steps
run_audit.cmd                     # machine checks + semantic gate
```

If the semantic pass is incomplete, fill it and finalize per `docs/AUDIT.md`; `scripts\finalize_audit.cmd`
must exit 0 before you call the state good.

`run_audit_tests.bat` takes roughly two to four minutes. Set **`BUILD_NOPAUSE=1`** before running any
root `.cmd` launcher from an agent session, or it waits on a keypress nobody is there to press.

### 4. Update the installed copy on that machine

Only if the primary system actually uses the pack (not just hosts the repo). This writes to the user
profile — `%USERPROFILE%\.cursor\AgentStarterPack\`, `\rules\`, `\skills\`, and `mcp.json`:

```powershell
# mcp.json is the user's own config and the installer rewrites the whole file - back it up first
Copy-Item "$env:USERPROFILE\.cursor\mcp.json" "$env:USERPROFILE\.cursor\mcp.json.bak"
.\install.ps1 -Scope User -NoPause
.\pack\scripts\doctor.ps1 -ProjectRoot (Get-Location).Path
```

Do **not** use `-Scope Both` from the pack checkout: project scope copies every global rule into this
repo's `.cursor\rules\`, which is reserved for the four workspace-only rules.

After the install, confirm the profile no longer holds maintainer-only files: `HANDOFF_NEXT_AGENT.md`,
`docs/handoffs/` and `docs/handoff_archive/` are listed in `maintainerOnlyPaths` and must not appear
under `%USERPROFILE%\.cursor\AgentStarterPack\`.

### 5. Publish

```powershell
git commit        # message describing the batch, not this handoff
git push
```

Remote: `https://github.com/binary-100/AgentStarterPack.git`. The **Pack OS smoke** workflow
(`.github/workflows/pack-os-smoke.yml`) runs on push — check it goes green.

### 6. Close the slice

Set `status: completed` in the registry above, move `WQ-011` to the Done log in `docs/WORK_QUEUE.md`
with the evidence (engine version verified, suite result, push confirmed), then archive this file:

```powershell
.\pack\scripts\archive-completed-handoff.ps1              # preview
.\pack\scripts\archive-completed-handoff.ps1 -Apply       # moves to docs/handoff_archive/
```

The audit reports an archive-ready handoff as **Improve** and never deletes one itself.

## What changed in this batch

Read `pack/docs/AUDIT_SYSTEM_CHANGELOG.md` from **2.22.45** forward for the reasoning, and the
`docs/WORK_QUEUE.md` Done log for the evidence per item. The short version:

- **Tests made hermetic** — several graded whatever pack was installed in the profile instead of the pack under test
- **Audit engine split** under its own size ceiling into `audit_common.py`, `audit_version_docs.py`, `audit_install_wiring.py`
- **Rules that install everywhere stopped describing this repo** — plus a check (step 46) that fails when they do again
- **Three new mechanical guards:** cited pack paths must exist (47), root launchers must gate `pause` (48), one word for handoff (49)
- **`HANDOVER_NEXT_AGENT.md` renamed** to `HANDOFF_NEXT_AGENT.md` and trimmed from 788 lines to ~470; the history it duplicated lives in the changelog
- **Root cleanup** — four finished documents deleted, with the code that policed them removed too

## Acceptance checklist

- [ ] Working tree on the primary system matches this pack state, deletions staged
- [ ] `.cursor/rules/no-publish-from-this-machine.mdc` is absent there, or at least uncommitted
- [ ] `Check-Requirements.cmd` reports no missing required item
- [ ] `run_audit_tests.bat` exits 0 — 19/19 unit tests, 49 behavior steps
- [ ] `scripts\finalize_audit.cmd` exits 0 with Fix and Improve both empty
- [ ] Install refreshed (if that machine uses the pack) and `doctor.ps1` clean; no maintainer-only files in the profile copy
- [ ] Pushed, and **Pack OS smoke** green on GitHub
- [ ] `status: completed` here, `WQ-011` in the Done log, this file archived
