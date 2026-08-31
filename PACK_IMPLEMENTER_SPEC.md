# Agent Starter Pack — Implementer spec (Phase 6 + audit addendum)

**Status:** **Implemented on 2026-08-28** — Phase 6a shipped in audit engine **2.21.23**, Section 12 in **2.22.0**. Do **not** re-implement; see `HANDOVER_NEXT_AGENT.md` § "The two tracks from the other machine's handoff" and `pack/docs/AUDIT_SYSTEM_CHANGELOG.md`. Phase 6b (MCP tools) and 6c (mailbox) remain unbuilt by design.

| Track | Delivered as |
|-------|--------------|
| **Phase 6a** (§4) | `Refresh-AgentContext.cmd`, `pack/scripts/refresh-agent-context.ps1`, generated `docs/AGENT_CONTEXT.json` + `docs/AGENT_REFRESH.md`, `AGENT_CONTEXT.json.template` bootstrap stub, trigger in `agent-defaults-always.mdc`, behavior step 27 |
| **Section 12** (§12) | `layoutPolicy` in the config templates (disabled by default), layout checks + `machineImprovesBySection` in `run_audit_core.ps1`, `semanticRequireMachineImproveMention`, skill §B layout pass, `AUDIT.md` §B bullets, behavior step 28 |

Deviations from the spec as written: the pack repo had no `AGENT_CHAT_SYNC.md` to supersede (§4.8 is moot); the generated artifacts are **gitignored** because they record machine-specific absolute paths; `-SkipInstall` became an opt-in `-Install` switch since installing is a profile-wide change; the optional `verify-agent-setup.ps1` hook (§4.10) was not added — `refresh-agent-context.ps1` reports installed-vs-pack drift itself.

---

**Original status:** Design complete · Not implemented · Safe to build on another system without duplicating Phases 1–5 work

**Purpose:** Standalone blueprint so an agent on **another machine** can implement pack work without prior chat history.

---

## 0. General applicability (read first)

This spec is **not tied to any one product, IDE, or AI vendor.**

| Scope | Rule |
|-------|------|
| **Starter Pack source** | **Generic only** — `MyApp` placeholders, templates, behavior fixtures. **No product names, no customer paths, no “reference app” configs in pack.** |
| **Any bootstrapped project** | Python, Node, Rust, etc. Each project owns `PROJECT_LAYOUT.md`, `AGENTS.md`, and `docs/AUDIT.config.json` (including optional `layoutPolicy`). |
| **Any AI agent / model** | Contract is **files on disk** (`docs/AGENT_REFRESH.md`, paste blocks, JSON manifests, `run_audit.cmd` output). Agents read and report; no vendor-specific APIs required for core behavior. |
| **Cursor** | One supported consumer (global rules, optional MCP in Phase 6b). **Not required** — Copilot, Claude, Windsurf, CLI, or custom agents can follow the same files. |
| **Audit vs implement** | Audit **detects and reports** Fix/Improve. Cleanup and layout changes are **project work**, not automatic audit side effects. |

**Edit boundary for implementers:** If a sentence names a real product or a user’s Desktop tree, it does **not** belong in `pack/` — move it to that project’s docs or delete it.

**Pack baseline when spec was written:** `VERSION` **1.7.0** · audit manifest **2.21.13** · generic-only pack policy

**Related shipped work (do not re-build):**

| Already exists | Role |
|----------------|------|
| `install.ps1`, `Update-AgentRules.cmd`, `sync-audit-system.ps1`, `sync-project-rules.ps1` | Disk sync (global + project) |
| `AGENT_CHAT_SYNC.md` | Manual paste blocks for stale chats — **interim** until Phase 6a ships |
| `HANDOVER_NEXT_AGENT.md` | Session handover for pack maintainers |
| `verify-agent-setup.ps1 -ReferenceProjectRoot` | Optional app verify |
| `docs/VERSION_SYNC.json` + doc sync pipeline | Build-time version cites — **not** part of Phase 6 |

**Read first on implementing machine:** `AGENTS.md` → `HANDOVER_NEXT_AGENT.md` (for pack layout only)

---

## 1. Problem Phase 6 solves

### 1.1 Agent Context Refresh (Phase 6a — **implement first**)

| What works today | What fails |
|------------------|------------|
| `install.ps1` updates `%USERPROFILE%\.cursor\rules\`, installed pack mirror, MCP config | **Open agent chats do not hot-reload** rules or prior context |
| New Cursor chats after restart pick up global rules | Stale chats keep acting on pre-install assumptions |
| `AGENT_CHAT_SYNC.md` manual paste | User must craft/copy text; no machine-generated “what changed” brief |

**Universal limit (not Cursor-specific):** No LLM chat auto-reloads instructions when disk changes. Fix = **update disk + give agents an explicit, short re-read target**.

### 1.2 Multi-agent coordination (Phase 6c — **parked, do not implement with 6a**)

Multiple agents (planning, build, maintainer) need structured **user-directed** handoff without duplicating rules. **Deferred** until platform change — see Section 8.

---

## 2. Non-goals (do not build)

- Silent push to all open tabs (no API exists)
- Replacing `AGENTS.md` as project entry (refresh doc is a **delta overlay**)
- Product-specific paths or app names in pack source (`MyApp` placeholders only)
- Audit-engine coupling for context refresh
- Automatic agent-to-agent loops without user direction
- Cursor SDK as the canonical layer
- Duplicating Phases 1–5 (version sync, edit boundary, verify scripts, etc.)

---

## 3. Design principles

1. **Protocol first** — files + JSON schema + CLI in `pack/`; IDE/MCP adapters second
2. **Tool-neutral paths** — canonical artifacts under project **`docs/`**, not `.cursor/` only
3. **One command on disk, one short line in chat**
4. **Generic in pack** — product layout differences via parameters (`-ProjectRoot`, `-RulesRelativePath`)
5. **Extend `AGENT_CHAT_SYNC.md`** after 6a ships (auto-generated paste snippet at bottom of `AGENT_REFRESH.md`) — do not delete interim paste doc until 6a verified

---

## 4. Phase 6a — Agent Context Refresh (REQUIRED IMPLEMENTATION)

### 4.1 Architecture

```
User runs Refresh-AgentContext.cmd
        │
        ├─ optional: install.ps1 -Scope User -SkipInstall default skip
        ├─ sync-project-rules.ps1 (if -ProjectRoot)
        ├─ sync-audit-system.ps1 (if -ProjectRoot)
        │
        └─ writes per-project:
              docs/AGENT_CONTEXT.json     ← machine-readable stamp
              docs/AGENT_REFRESH.md         ← human + agent brief

User pastes one line into stale chat OR agent reads files on demand
```

**Pack maintainer repo** also gets both files under its own `docs/` when `-ProjectRoot` is the pack root (or a dedicated `-PackMaintainer` switch).

### 4.2 Artifacts to create

| File | Location | Notes |
|------|----------|-------|
| `refresh-agent-context.ps1` | `pack/scripts/` | Core logic |
| `Refresh-AgentContext.cmd` | repo root | Wrapper; `%~dp0` for pack path |
| `AGENT_CONTEXT.json.template` | `pack/templates/docs/` | Bootstrap stub |
| `AGENT_REFRESH.md.template` | `pack/templates/docs/` | Bootstrap stub (optional — CLI can generate from scratch) |
| Bootstrap hook | `bootstrap-project.ps1` | Copy template or empty stub; document in manifest |
| Rule pointer | `pack/rules/agent-defaults-always.mdc` | Trigger phrases (short) |
| Rule pointer | `AI_INSTRUCTIONS.md.template` | “On refresh, read docs/AGENT_REFRESH.md” |
| Docs | `pack/docs/PACK_MAINTENANCE.md`, `docs/PORTABLE_SETUP.md` | One section each |
| Manifest | `pack/audit/manifest.json` | Bump version; add new files to `packMirror` |
| Changelog | `pack/docs/AUDIT_SYSTEM_CHANGELOG.md` | Entry for manifest bump |

### 4.3 CLI — `refresh-agent-context.ps1`

```powershell
param(
    [string]$ProjectRoot = '',      # Bootstrapped app or pack repo; required for project layer
    [string]$RulesRelativePath = '.cursor\rules',
    [switch]$SkipInstall,           # DEFAULT: skip install.ps1 (user runs install separately)
    [switch]$Install,               # Run install.ps1 -Scope User -NoPause
    [string]$PackRoot = ''           # Default: resolve via pack-paths.ps1
)
```

**Behavior (order matters):**

1. Resolve `$PackRoot` (desktop or installed canonical).
2. If `-Install` or `-Install:$true` (and not `-SkipInstall`): run `install.ps1 -Scope User -NoPause`.
3. If `$ProjectRoot`:
   - Run `sync-project-rules.ps1 -ProjectRoot $ProjectRoot -RulesRelativePath $RulesRelativePath` (not `-VerifyOnly` — **apply** sync).
   - Run `sync-audit-system.ps1 -ProjectRoot $ProjectRoot`.
4. Collect versions:
   - Pack `VERSION` file
   - `pack/audit/manifest.json` `"version"`
   - Installed pack manifest (if present) — note drift
   - Optional: hash of generic rules in `pack/rules/` (single combined hash or per-file map)
5. Compare to previous `docs/AGENT_CONTEXT.json` in `$ProjectRoot` (if exists) → compute `changedLayers[]`.
6. Write **`docs/AGENT_CONTEXT.json`** and **`docs/AGENT_REFRESH.md`** under `$ProjectRoot`.
7. Exit 0; print **copy-paste line** for stale chat (see 4.5).
8. If `$ProjectRoot` omitted: support **pack-only refresh** writing into pack repo `docs/` (maintainer mode) or print error — pick one behavior and document it.

**Exit codes:** 0 success; non-zero if sync subprocess fails.

### 4.4 `docs/AGENT_CONTEXT.json` schema

```json
{
  "schemaVersion": 1,
  "packVersion": "1.7.0",
  "auditEngineVersion": "2.21.13",
  "rulesRevision": "sha256:abc123...",
  "syncedAt": "2026-08-27T19:00:00Z",
  "packRootUsed": "C:\\Users\\alice\\.cursor\\AgentStarterPack",
  "projectRoot": "C:\\Users\\alice\\Projects\\MyApp",
  "layers": {
    "globalRules": "ok",
    "installedPack": "ok",
    "projectRules": "updated",
    "auditTemplates": "ok"
  },
  "changedLayers": ["projectRules"],
  "previousSyncedAt": "2026-08-26T10:00:00Z"
}
```

**Layer values:** `ok` | `updated` | `stale` | `skipped` | `unknown`

**`rulesRevision`:** SHA-256 of sorted concatenation of `pack/rules/*.mdc` file hashes, or document alternative — must be stable across runs.

### 4.5 `docs/AGENT_REFRESH.md` content (generated)

Keep **under ~40 lines**. Suggested sections:

```markdown
# Agent context refresh

**Generated:** {syncedAt} · Pack {packVersion} · Audit engine {auditEngineVersion}

## Stale chat notice

If this chat started before **{syncedAt}**, treat earlier messages as possibly stale.

## Re-read (required)

1. `{absolutePathToAGENTS.md}`
2. `AI_INSTRUCTIONS.md` — if present
3. (Pack repo only) `HANDOVER_NEXT_AGENT.md` at repo root

## What changed since last refresh

- {bullet list from changedLayers — plain language}

## Reminders

- Version/doc sync = build pipeline (`docs/VERSION_SYNC.json` / `apply_version.py sync`) — not audit
- (App repo) Do not read pack-only HANDOVER unless workspace is Agent Starter Pack

## Paste into open chat

{single-line copy block — see AGENT_CHAT_SYNC.md style, parameterized}
```

**Pack vs app detection:** If `$ProjectRoot` contains `pack/audit/manifest.json` at expected pack layout, use **pack maintainer** paste; else **product app** paste (no HANDOVER).

### 4.6 Trigger phrases (add to `agent-defaults-always.mdc`)

When user says **"refresh pack context"**, **"sync agent context"**, **"context refresh"**, or **"pack update"**:

1. Read `docs/AGENT_REFRESH.md` in the **current workspace** if present.
2. Re-read files listed there + `AGENTS.md`.
3. If unclear, read `docs/AGENT_CONTEXT.json`.

Keep **≤ 8 lines** — link to full doc, no duplication.

### 4.7 Bootstrap integration

In `bootstrap-project.ps1`, for **all stacks**:

- Ensure `docs/` exists.
- Write initial `docs/AGENT_CONTEXT.json` with `"syncedAt": null` or bootstrap timestamp and `"note": "Run Refresh-AgentContext.cmd after first pack sync"`.
- Do **not** add product-specific content.

Add to `.agent-bootstrap.json` docs list: `docs/AGENT_CONTEXT.json`, `docs/AGENT_REFRESH.md`.

### 4.8 Relationship to `AGENT_CHAT_SYNC.md`

| Before 6a | After 6a |
|-----------|----------|
| User copies static blocks from `AGENT_CHAT_SYNC.md` | CLI generates project-specific `AGENT_REFRESH.md` + paste line |
| Manual version numbers in paste | Versions pulled from `VERSION` + manifest at generation time |

**After 6a ships:** Update `AGENT_CHAT_SYNC.md` to say “prefer `Refresh-AgentContext.cmd`; paste section lives at bottom of generated `docs/AGENT_REFRESH.md`.”

### 4.9 Acceptance criteria (Phase 6a done when all pass)

1. `Refresh-AgentContext.cmd -ProjectRoot <packRoot>` → creates/updates `docs/AGENT_CONTEXT.json` + `docs/AGENT_REFRESH.md` in pack repo; exit 0.
2. Same for a bootstrapped test fixture under `pack/audit/behavior-fixture/` or temp dir.
3. Second run without pack changes → `changedLayers` empty or `ok`; still updates `syncedAt`.
4. After intentional edit to `pack/rules/*.mdc`, run refresh → `globalRules` or `rulesRevision` reflects change.
5. `verify-audit-system.ps1` still exit 0 after manifest bump.
6. No product-specific names in new files (grep clean).
7. `AGENT_REFRESH.md` paste block works in manual test (user pastes into stale chat; agent re-reads AGENTS.md).

### 4.10 Optional verify hook

Add to `verify-agent-setup.ps1` (optional, non-breaking):

- If `-ReferenceProjectRoot` and `docs/AGENT_CONTEXT.json` exists: warn if `auditEngineVersion` ≠ installed manifest (Improve-style message, not fail).

---

## 5. Phase 6b — MCP adapters (OPTIONAL, after 6a)

**Server:** extend existing `mcp/agent_hygiene_server.py` (or separate server only if hygiene bloats).

| Tool | Input | Returns |
|------|-------|---------|
| `check_pack_freshness` | optional `projectRoot` | `{ stale: bool, layers: {...}, installedVersion, desktopVersion }` |
| `get_agent_refresh_brief` | `projectRoot` | Markdown body of `docs/AGENT_REFRESH.md` or generated on the fly if missing |

**Rules:**

- MCP reads same JSON/files as CLI — **not** a second source of truth.
- Cursor/Claude Desktop only; Copilot/web agents use files.

**Skip unless:** User wants mid-session check without paste.

---

## 6. Phase 6c — Multi-agent coordination mailbox (PARKED — spec only)

**Do not implement alongside 6a** unless user explicitly expands scope.

### 6.1 Problem

User-directed coordination between agents (planner, builder, pack maintainer) without rule forks or duplicate docs.

### 6.2 Preferred direction (when resumed)

**Disk mailbox + JSONL + CLI** in `pack/`:

```
pack/coordination/          # or project-local .agent-mailbox/
  inbox/
  outbox/
  schema.json
  README.md
pack/scripts/agent-mail.ps1   # send, list, ack, expire
```

**Message shape (sketch):**

```json
{
  "id": "uuid",
  "fromRole": "maintainer",
  "toRole": "builder",
  "createdAt": "ISO8601",
  "intent": "one paragraph",
  "filesTouched": ["docs/PLAN.md"],
  "expiresAt": "ISO8601"
}
```

### 6.3 Constraints

1. Opt-in — user says “post handoff to builder”
2. Git = code truth; mailbox = intent only
3. Generic roles in pack; product role names in app docs
4. MCP wrapper optional over CLI
5. **Avoid** Cursor SDK as core

### 6.4 Explicitly out of scope

- Audit multi-agent consensus (removed from audit engine)
- Auto loops without user direction

**Status doc:** `pack/docs/AGENT_COORDINATION_BACKLOG.md` — update when 6c starts.

---

## 7. Portability matrix

| Component | Cursor | Claude | Copilot | Windsurf | Custom agent |
|-----------|--------|--------|---------|----------|--------------|
| `docs/AGENT_CONTEXT.json` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `docs/AGENT_REFRESH.md` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `Refresh-AgentContext.cmd` | ✓ | ✓ (run manually) | ✓ | ✓ | ✓ |
| `agent-defaults-always.mdc` | ✓ global | — | — | — | — |
| MCP 6b | ✓ (+ Claude Desktop) | ✓ | — | — | if MCP |

---

## 8. Implementer checklist (avoid duplicate work)

> **This checklist is complete.** Phase 6a shipped in audit engine 2.21.23, Section 12 in 2.22.0, and
> the boxes below were all worked then — including the sync/verify runs and the `HANDOVER_NEXT_AGENT.md`
> update. The boxes are left unticked as the original text; do not treat them as open work. Deviations
> from this spec are listed in the status note at the top of this file.

**Do:**

- [ ] Implement Section 4 only (6a) unless user asks for 6b/6c
- [ ] Bump `pack/audit/manifest.json` + changelog
- [ ] Run `sync-audit-system.ps1`, `verify-audit-system.ps1`, `verify-agent-setup.ps1`, `run_audit_tests.bat`
- [ ] Update `HANDOVER_NEXT_AGENT.md` § Phase 6 → “implemented”
- [ ] Keep edit boundary: generic examples only in pack

**Do not:**

- [ ] Re-implement doc version sync (`VERSION_SYNC.json` pipeline)
- [ ] Re-add product-specific reference configs
- [ ] Hardcode any user Desktop paths in scripts (parameters + env `AUDIT_REFERENCE_PROJECT_ROOT` only)
- [ ] Remove `AGENT_CHAT_SYNC.md` until 6a paste generation verified

---

## 9. Suggested implementation order (6a)

1. `refresh-agent-context.ps1` — write JSON + MD only (no sync) — prove schema
2. Wire sync calls + version/hash collection
3. `Refresh-AgentContext.cmd` + manifest/changelog
4. Bootstrap stub + `agent-defaults-always.mdc` trigger
5. Update `AI_INSTRUCTIONS.md.template`, `PACK_MAINTENANCE.md`
6. Manual E2E: install → refresh → paste → agent confirms
7. (Optional) 6b MCP tools

---

## 10. Copy-paste for implementing agent (start message)

```text
Implement Phase 6a from PACK_IMPLEMENTER_SPEC.md in the Agent Starter Pack repo only.

Do not redo Phases 1–5 (version sync, generic-only cleanup, verify scripts already shipped at audit 2.21.13).

Deliver: refresh-agent-context.ps1, Refresh-AgentContext.cmd, docs/AGENT_CONTEXT.json + docs/AGENT_REFRESH.md generation, bootstrap hook, short rule trigger, manifest bump, verify exit 0.

Phase 6b/6c are out of scope unless I ask.
```

**Optional second track** (audit layout reporting — Section 12): use the paste block in `PACK_IMPLEMENTER_HANDOFF.txt` § “AUDIT LAYOUT TRACK” when the user assigns that work separately or after 6a.

---

## 11. Document history

| Date | Change |
|------|--------|
| 2026-08-27 | Initial spec exported from design sessions (Phases 1–5 shipped; 6 not built) |
| 2026-08-28 | Added Section 12 — audit layout hygiene reporting (generic); Section 0 general applicability; consolidated to two Desktop files (`PACK_IMPLEMENTER_*` only) |

---

## 12. Audit engine addendum — layout hygiene reporting (manifest 2.21.13+)

**Status:** **Implemented** in audit engine **2.22.0** (the "separate audit-engine bump" this section asked for). Do **not** re-implement — see `pack/docs/AUDIT_SYSTEM_CHANGELOG.md` §2.22.0 and behavior step 28. *Original status: generic pack enhancement, not implemented, to be built as a separate bump.*

**Gap this closes:** On bootstrapped projects, audits often surface delete-only cruft **Fix** lines (`dist/`, `build/`) but miss structural **Improve** items (folder naming, build output vs runtime data vs release archive). Agents may explain tooling limits instead of reporting layout Improve the user should see in Fix/Improve output.

**Design stance:**

| Class | Layout / hygiene examples |
|-------|---------------------------|
| **Fix** | Wrong paths that break builds/tests; committed secrets; scripts that write paths the audit checklist forbids; contradictory machine vs documented policy |
| **Improve** | Folder naming clarity, redundant copies, missing layout glossary in `PROJECT_LAYOUT.md`, gitignore gaps for temp patterns, workflows that recreate “expected ephemeral” dirs — **clean easy-to-follow layout is Improve**, not optional nicety |

**Do not** auto-delete folders without user/agent action. **Do** report structural layout issues proactively in audit output even when machine cruft checks are clean.

### 12.1 Illustrative pattern (MyApp placeholders only)

Example bootstrapped tree — **configure names per project** in `layoutPolicy`; do not hardcode in pack:

| Folder | Typical role | Common confusion |
|--------|--------------|------------------|
| `MyApp_v6/` | **Build output** (shipped binary + bundled runtime) | Looks like “the app” — often correct, but undocumented |
| `MyApp_portable/` | **Runtime user data** beside binary (settings, exports, cache) — **not a second product** | Name sounds like another distribution |
| `MyApp_v6_stable/` | **In-repo duplicate** of release archive stored outside dev tree | Created by a publish script; audit §B may forbid duplicate |

Additional patterns (any stack):

- `build/`, `dist/` — **ephemeral** build scratch (recreated each build); usually gitignored
- Same **runtime data dirname** beside source tree (dev/tests) vs beside packaged binary — one name, two locations
- Machine cruft check emits **Fix** “delete `dist/`” only; semantic pass skips **Improve** for naming/workflow/glossary
- A project script **recreates** paths the checklist forbids — **policy contradiction** (Fix or Improve)
- `autoFixDrift` in `AUDIT.config.json` applies to **version/doc sync only** — not layout (easy to mis-attribute)

**Expected behavior:** Audit output includes **Improve** for layout/design clarity **before** the user must ask for a folder-structure review. Report in Fix/Improve output; **no** “want me to clean up?” prompt in audit CLI; user decides when to act.

### 12.2 Root cause (agent + tooling)

1. **`run_audit_core.ps1` cruft block** — `Add-Fix "Build cruft - app\$bad - delete"` only; no **Improve** channel for structural layout.
2. **`agent-code-audit` skill** — output is Fix/Improve only, but agents treated §B as “delete listed dirs” not “review layout vs PROJECT_LAYOUT + report Improve.”
3. **`AUDIT.md` template §B** — lists cruft dirs but not **mandatory layout glossary / naming review**.
4. **`finalize_audit.cmd` / harness verify** — does not block on product cruft Fix lines (`AGENT_WORKFLOW.md`); agents may close audit while layout Improve unreported.
5. **Ephemeral regeneration** — passing audit after deleting `dist/` then rebuilding recreates cruft; without Improve guidance, user thinks issue is “fixed permanently.”

### 12.3 Proposed pack changes (implement in Agent Starter Pack — generic only)

Use **`MyApp`** placeholders in templates; each bootstrapped project configures paths in its own `docs/AUDIT.config.json`.

#### A. Taxonomy — `pack/docs/AUDIT_SYSTEM.md` + `pack/docs/AGENT_WORKFLOW.md`

Add subsection **“Layout hygiene = Improve”**:

- Distinguish **ephemeral build scratch** (expected after build; Improve to document, not panic Fix every time)
- Distinguish **runtime user-data dirs** (gitignored; beside exe; not product folders)
- Distinguish **stable archive outside dev tree** vs **in-repo duplicate copies**
- Agents **must** report layout/naming Improve in §B semantic summary even when `machineFixesBySection.B` is empty

#### B. Machine layer — `pack/scripts/run_audit_core.ps1`

Add optional `AUDIT.config.json` block (template in `pack/templates/docs/AUDIT.config.json.template`):

```json
"layoutPolicy": {
  "enabled": true,
  "buildOutputDir": "MyApp_v6",
  "portableDataDirname": "MyApp_portable",
  "forbiddenInRepoStableCopy": "MyApp_v6_stable",
  "ephemeralDirs": ["build", "dist"],
  "contradictionScripts": [
    {
      "script": "scripts/publish_release.bat",
      "createsForbiddenDir": "MyApp_v6_stable",
      "flag": "Improve",
      "message": "Script creates in-repo release copy; policy prefers external release archive only"
    }
  ]
}
```

**Behavior:**

| Check | Output type | Example message |
|-------|-------------|-----------------|
| Forbidden in-repo stable copy exists | **Improve** (or Fix if checklist says forbidden) | `Layout - duplicate stable folder in repo - use external stable archive` |
| Ephemeral dirs exist | **Improve** (not Fix unless committed to git) | `Layout - ephemeral build dirs present (normal after build) - document or delete` |
| `layoutPolicy.glossaryDoc` missing/outdated | **Improve** | `Layout - PROJECT_LAYOUT.md missing folder glossary` |
| Script creates forbidden path | **Fix** or **Improve** | See `contradictionScripts` |

Emit machine lines into **`machineImprovesBySection.B`** (new array) **and/or** existing Improve channel — do not overload Fix with “delete” only.

#### C. Semantic / skill — `pack/skills/agent-code-audit/SKILL.md` (or template)

Add **§B layout pass (mandatory)** before “Nothing found”:

1. Read project `PROJECT_LAYOUT.md` (or `layoutPolicy.glossaryDoc`)
2. List folders matching `buildOutputDir`, `portableDataDirname`, forbidden copies
3. Report **Improve** for naming confusion, missing glossary, workflow contradictions
4. Report **Fix** only when policy violation breaks build or contradicts committed audit checklist

**Forbidden:** Closing §B with only “removed dist/build” when layout glossary or duplicate-stable workflow was never mentioned.

#### D. `AUDIT.md` template §B — add bullets

- Folder **glossary** present and matches tree (build output vs build input vs runtime user data vs stable archive)
- No **in-repo duplicate** of user-approved stable if policy says external-only
- Scripts must not **recreate** paths the checklist forbids (or checklist must be updated)
- Ephemeral dirs (`build`, `dist`) — note as **expected after build** in Improve, not silent

#### E. `verify_semantic_audit` — optional alignment rule

If `machineImprovesBySection.B` lists layout items → semantic §B summary must mention “layout” or cite those lines (same pattern as existing machine Fix alignment).

#### F. Behavior fixture — `pack/audit/behavior-fixture/`

Add fixture tree:

```
app/MyApp_v6/MyApp.exe
app/MyApp_v6/MyApp_portable/settings.json
app/MyApp_v6_stable/MyApp.exe   ← should trigger Improve/Fix
app/build/                       ← should trigger Improve (ephemeral)
```

Test: `run_audit_tests.bat` expects machine layout Improve lines when enabled.

### 12.4 Acceptance criteria (Section 12 done when all pass)

1. Behavior fixture triggers **Improve** layout lines without relying on delete-only Fix cruft messages.
2. `agent-code-audit` template requires §B layout pass — documented in skill.
3. `AUDIT_SYSTEM.md` + `AGENT_WORKFLOW.md` state: **audit detects and reports; agents/implementers act; no auto-delete; layout clarity = Improve.**
4. `AUDIT.config.json.template` includes optional `layoutPolicy` (disabled by default for minimal projects).
5. `verify-audit-system.ps1` and `run_audit_tests.bat` exit 0 after manifest bump.
6. No product-specific names in pack source (MyApp placeholders only).
7. Changelog entry in `AUDIT_SYSTEM_CHANGELOG.md` explaining Fix vs Improve for layout hygiene.

### 12.5 Explicit non-goals (Section 12)

- Auto-delete cruft folders during `run_audit.cmd`
- Interactive “do you want cleanup?” prompts in audit CLI
- Product-specific paths or names in pack templates (each project configures `layoutPolicy` locally)
- Coupling to Phase 6a context refresh (optional cross-link in `AGENT_REFRESH.md` reminders only)

### 12.6 Suggested implementation order (Section 12)

1. Docs + skill template (taxonomy Fix vs Improve for layout)
2. `layoutPolicy` schema in `AUDIT.config.json.template`
3. `run_audit_core.ps1` layout checks + `machineImprovesBySection`
4. Semantic verify alignment (if feasible without breaking existing projects)
5. Behavior fixture + tests
6. Manifest bump + changelog

---

*Pair with:* **`PACK_IMPLEMENTER_HANDOFF.txt`** (paste blocks) on Desktop.  
*Copy spec to:* Agent Starter Pack repo root as **`PACK_IMPLEMENTER_SPEC.md`** (same folder as `AGENTS.md` and `install.ps1`).
