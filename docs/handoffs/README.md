# Handoffs — Agent Starter Pack

Work handed from one chat to the next lives here. One file per slice, so the next agent reads a
document instead of a scrollback.

Convention: `pack/docs/AGENT_HANDOFFS.md` — after install,
`%USERPROFILE%\.cursor\AgentStarterPack\pack\docs\AGENT_HANDOFFS.md`.
Checked by `verify-agent-handoffs.ps1` during audit, which reports and **never deletes**.

## Current session handoff

**`active/` and `../handoff_archive/` are both empty as of 2026-09-01.** The slice for WQ-426 and two
completed archives were consolidated into a single transfer document written to the **root of the
transfer drive** — deliberately outside this checkout, so it never reaches a commit, an export or an
install, and so this folder stops accumulating parallel status documents. It is not referenced by path
here for the same reason: a tracked file must not record where the drive happened to be mounted.

**WQ-426 is still open** — the machine-local leak fix has to be landed and published from the primary
system, and the git index there is the part no script can fix from here. Its instructions live in that
transfer document; its status lives in `docs/WORK_QUEUE.md`.

**Status (always current):** `docs/WORK_QUEUE.md` - the Active queue and Done log. There is no separate session doc as of §11 and §14.

`active/` should be **empty** when no build slice is in progress. Completed handoffs live in `../handoff_archive/`.

## Layout

| Path | Holds |
|------|-------|
| `active/HANDOFF_WQnnn_<slug>.md` | Build slices in progress — one per work-queue item |
| `HANDOFF_<topic>.md` | Orientation notes; read and confirm, no code |
| `../handoff_archive/` | Completed or superseded, moved after audit Improve **and** a human's confirmation |

`<slug>` is lowercase with underscores and names the outcome, not the phase — `usb_data_recovery`,
not `phase_2`.

## Required on every handoff

A `## Handoff registry` table at the top (`handoff_id`, `kind`, `status`, `multi_agent`, `wq_id`,
`plan`, `phases`, `agents_remaining`, `completed`) and a session opener line giving a **root-anchored**
path to the file. Start from `HANDOFF_BUILD.md.template` in the pack rather than an empty file.

An absolute path is the normal form. When the slice is for **another machine**, use a placeholder root
instead — `<pack folder>\docs\handoffs\...` — because this pack folder is portable and a tracked file
must not record where it happened to live when the handoff was written. A bare relative path is still
rejected: it opens the wrong file in whichever workspace is current.

## The rule that catches drift

`status` here and the row in `docs/WORK_QUEUE.md` must agree. A handoff marked `completed` whose WQ
row is still Active — or the reverse — is what the audit reports, because that pair going out of
sync is how work gets silently dropped between sessions.
