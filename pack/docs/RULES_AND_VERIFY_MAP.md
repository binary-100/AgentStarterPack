# Rules and verify scripts â€” map (canonical inventory)

**Audience:** Maintainers and agents auditing agent-process design.  
**Last updated:** 2026-09-01  
**Purpose:** One place to see **what each rule covers**, **what each verify script enforces**, **overlaps**, and **gaps**. Update this file when adding rules or verify scripts.

**Canonical status (ship / park / next):** `docs/WORK_QUEUE.md` only. Every other doc is a **derivative** that must be updated or must link here â€” never the other way around.

---

## Prevention vs detection

| Layer | Prevents drift? | How | Limit |
|-------|-----------------|-----|-------|
| **Rules (always-on)** | *Behavioral* â€” if the agent follows them | Tell the agent what to update when WQ/status changes | Open chats do not reload rules; agents skip steps under time pressure |
| **`WORK_COMPLETION.md`** | *Procedural* â€” closing checklist | Steps after each shipped slice | Only helps when the agent runs the checklist |
| **Verify scripts** | *Mechanical* â€” exit non-zero | `verify-*.ps1`, behavior steps | Runs at test/audit/setup time â€” not on every file save |
| **`repair-agent-docs.ps1`** | *Partial auto-repair* | Hub templates + portable export on refresh | Does **not** rewrite HANDOFF narrative, phase plans, or spec status headers |
| **`doc_version_sync.py`** | *Numeric cites only* | Version strings in configured doc paths incl. **`docs/WORK_QUEUE.md` header** | Does **not** know Done vs Parked semantics |

**There is no single auto-sync for narrative handoff docs.** Prevention = **one broad rule** + **WORK_COMPLETION** + **verify-complete-picture** on close.

---

## Generic rules (`pack/rules/`)

| Rule | Always on? | Primary concern | Does **not** cover |
|------|------------|-----------------|-------------------|
| `agent-defaults-always.mdc` | yes | Index: session start, loop-back, audit entry, refresh, work queue pointer, handoff pointer, doc hygiene pointer | Duplicates child rules; no WQ propagation detail |
| `loop-back-protocol.mdc` | yes | Repeat asks â†’ re-read workstream, validate, proceed differently | Status doc alignment |
| `generic-work-queue-discipline.mdc` | yes | WQ IDs, Done/Parked/Next, no chat-only priority lists | **Now includes** canonical status propagation (Â§ below) |
| `generic-agent-handoff-discipline.mdc` | yes | One opener, handoff registry, archive gates; SESSION pointers | HANDOFF/spec/plan rows â€” points to WORK_COMPLETION |
| `handoff-first.mdc` | yes | SESSION first on continue; lookup order; interrupt rule | Links AGENT_HANDOFFS |
| `generic-agent-doc-hygiene.mdc` | yes | Read before add; extend not duplicate; version cite sync | **Now includes** after-ship status alignment |
| `generic-deep-task-execution.mdc` | yes | Depth contracts; complete-picture when user asks status | Only binds on those triggers â€” not every WQ Done |
| `generic-phased-feature-design.mdc` | yes | Phase sequence, no skips | ROADMAP/work-queue promotion; Phase 0 detail in readiness rule |
| `generic-implementation-readiness.mdc` | yes | Phase 0 table before Phase 1 on multi-zone/multi-tree features; forbidden "sim pass = ready" | Concrete rows live in project `docs/*_PLAN.md` only |
| `generic-version-sync.mdc` | no | `VERSION` â†’ derived files + doc **version strings** | Semantic status (Done/parked) |
| `generic-terminal-and-build-hygiene.mdc` | no | Builds that finish without a human â€” `BUILD_NOPAUSE`, exit codes, prompt gating | Terminal diagnosis (skill) and the before/after sequence (agent-defaults) |
| `audit-protocol.mdc` | no | Audit = 3 steps, Fix/Improve only | WQ |
| `new-project-bootstrap.mdc` | no | Bootstrap layout, tests, audit wiring | Ongoing maintenance |
| `full-paths-in-chat.mdc` | yes | Absolute paths in user-facing chat | â€” |

**Project-only (this repo):** `.cursor/rules/starter-pack-repo.mdc`, `pack-only-edit-boundary.mdc`, `agent-recommendation-discipline.mdc`, `audit.mdc` â€” not installed globally.

---

## Verify scripts (`pack/scripts/`)

| Script | Behavior step | Hard FAIL on | INFO / Improve only |
|--------|---------------|--------------|---------------------|
| `verify-work-queue.ps1` | 31 | WQ structure, duplicate IDs across sections, one **Next**, Done vs open sections, **header pack/audit vs VERSION/manifest** | â€” |
| `verify-agent-handoffs.ps1` | 36 | Registry layout, opener format, WQ vs handoff status | Archive-ready Improve |
| `verify-complete-picture.ps1` | 37 | HANDOFF inventory; Done-WQ vs stale text; **ROADMAP â†” Done WQ**; **pack:** WORK_QUEUE header â†” Active **Next**, parallel install docs, INSTALL.txt vs VERSION; **delegates** to `verify-product-truth-paths.ps1` and **`verify-session-handoff.ps1`** | Pending keyword scan |
| `verify-session-handoff.ps1` | 57 | SESSION present (pack repo); no duplicate Next table; clear vs open items; optional pointer vs WQ header | â€” |
| `verify-product-truth-paths.ps1` | 55 | Product-truth overlay paths exist; Done **WQ** prose not "not built/deferred"; optional `docs/.product_truth_verify.json` doc/code claims | Skips pack maintainer repo (no overlay); also invoked from complete-picture |
| `verify-portable-bootstrap.ps1` | 33 | Portable bootstrap files | â€” |
| `verify-audit-system.ps1` | (audit L) | Manifest mirror drift; **a behavior suite that exits 0 must have printed no `[FAIL]` line** (WQ-472) | Tees the suite output rather than capturing it, so a watched run still streams |
| `verify-audit-behavior.ps1` | (pack tests) | All of the above in regression; **step 45** an em dash survives AUDIT.md to the agent manifest; **step 46** shipped rules name no id, doc or section number that exists only in this repo; **step 47** every `pack/` path cited by a rule, skill or pack doc resolves on disk; **step 48** root `.cmd` launchers gate every `pause` behind `BUILD_NOPAUSE`; **step 49** one word for the handoff concept â€” the synonym stays retired; **step 50** no real user profile path in any file that travels, `machineLocalPaths` gitignored and unmirrored, `export.ps1` + `sanitize-machine-state.ps1` read that one list, sanitizer previews without deleting, **no machine-local file is tracked in git** (the arm that catches a tracked copy returning from a copied transfer, since machine-local files are exempt from the identity scan), **no travelling file records the pack folder's own absolute path**, **no machine-local file exists here at all** (since 2.22.59 nothing writes them here) and the state root resolves outside the checkout; **step 51** the PowerShell and Python state-root resolvers agree, and two checkouts stay distinct; **step 52** a real `export.ps1` run, unzipped, ships every mirrored file and no machine-local state; **step 53** every consumer of a manifest-declared list still reads it, rather than keeping a narrower private copy; **step 81** a project-relative cite either resolves in this checkout, or is declared in the manifest's `citedPathOwnership` as **delivered** by a template or script that still exists, or as **reader**-owned with a reason that prints every run; **step 65 arm 5c** no line in the scanned script set exceeds 600 characters, so release narrative cannot sit where an instruction scanner reads it (**WQ-469** â€” the canned audit text lives in `scripts/semantic_report_content.json`); **step 82** a run that exited 0 printed no `[FAIL]` line, tested on fixtures through `Get-PackStrayFailureLine` and enforced for real by `verify-audit-system.ps1`, plus a source scan for expected-fail arms that suppress with an error-only redirect (which cannot touch `Write-Host`); **step 83** the WQ-476 offload hooks are **executed**, not read â€” BOM-prefixed payloads as Cursor sends them, the detector flagging an ask that names a pre-approved command and staying clean on both an `install.ps1` ask and command-naming prose, the gate handing back once and declining a stale generation and a second loop, and `hooks.json.template` registering the two *tightening* hooks while leaving pre-approval **off** (widening a project's unattended execution is its owner's call); **step 83 arms 5-7** (WQ-477) an ask that re-raises a **settled** decision is flagged and cites where the decision is recorded, a *statement* of that decision stays clean, and the gate returns the settled instruction rather than the offload one â€” the settled list is checked **before** the command list and outside the refuse skip, because "this is the human's call" is the framing that produced the defect; **step 83 WQ-480 arms** the policy is authored in **globs**, so it compiles to a regex host and a glob host both (a regex-shaped entry fails the arm), it compiles to OpenCode's `permission.bash` map with refuse becoming **ask** and allow emitted first so the narrower rule binds last, `bootstrap-project.ps1` delivers the policy **outside** `.cursor/` and compiles it into `opencode.json`, and the Cursor adapter passes all **12 shared `conformance.json` cases** — run from a **staged project tree**, so the upward walk that finds `.agent-control/policy.json` is exercised rather than the fallback | â€” |
| `verify-guard-proofs.ps1` | 72, 73 (its logic) | Every `mutation` entry in `pack/audit/behavior-controls.json`: applies the spec to a **copy** and requires the named step to report a failure. Fails on a spec matching zero or 2+ times, a suite that stays green, or a failure in the wrong step | **Maintainer-invoked, not in `run_audit.cmd`** â€” each entry costs a full suite run. Runs a green baseline copy first, and refuses to interpret anything if it is red. Writes only into its own copy â€” it never edits the source registry (established while closing **WQ-467**) |
| `behavior-controls.json` (registry) | 71 | Every announced step declares a mutation or a written exemption; titles match the suite; the seal blocks grandfathering above step 70; **`exemptSteps` names the exempt rows and must agree with them in both directions** (WQ-467) | The status is `mutation`, not `proven` â€” a file cannot hold a proof; the runner's exit code is the proof |
| `verify-agent-setup.ps1` | doctor | Runs WQ + handoffs + complete-picture on pack + optional reference project | â€” |
| `repair-agent-docs.ps1` | 39 | Hub pattern repair on refresh | â€” |
| `sync-portable-docs.ps1` | 32 | Portable export drift vs `pack/rules` | â€” |
| `doc_version_sync.py` | 23 area | Version **string** drift in configured paths | â€” |

---

## Overlap hotspots (intentional vs redundant)

| Concern | Rules / docs that mention it | Canonical owner | Action |
|---------|------------------------------|-----------------|--------|
| WQ Done â†’ update files | work-queue, handoff, deep-task, WORK_COMPLETION, doc-hygiene Â§6 | **`WORK_COMPLETION.md`** + **work-queue Â§ propagation** + **doc-hygiene Â§ product-truth** | Handoff rule **links**; do not duplicate full checklist |
| What's next? | **`handoff-first.mdc`**, agent-defaults, work-queue, AGENT_HANDOFFS | **SESSION â†’ WORK_QUEUE** lookup order | deep-task only on explicit status asks |
| Version in docs | version-sync, doc-hygiene Â§5 | **build** `doc_version_sync.py` | Not audit (unless Section M enabled) |
| Handoff archive | handoff rule, WORK_COMPLETION, verify-agent-handoffs | **verify-agent-handoffs** + archive script | â€” |
| Hub doc patterns | repair-agent-docs, portable bootstrap | **repair-agent-docs** on refresh | Separate from narrative handoff |
| Complete picture grep | deep-task contract, verify-complete-picture | **Script** enforces; **rule** when user asks | Script is the backstop |
| Phase 0 readiness | implementation-readiness, phased-feature-design, deep-task readiness contract, PHASED_FEATURE_DESIGN.md | **`generic-implementation-readiness.mdc`** owns triggers + forbidden claims; phased rule owns order; deep-task owns evidence steps when user asks | Concrete rows only in project plan docs |
| Terminal + build hygiene | `agent-defaults-always` Â§Terminal (always-on), `generic-terminal-and-build-hygiene` (on-demand), skill `agent-terminal-hygiene` | Split by job, **WQ-207** | Each surface now owns one thing and says so: the always-on rule is the operational default (what to run before/after long commands), the **skill** owns diagnosis (stale metadata, orphans, what an agent cannot fix), the on-demand rule owns **builds that never wait on a prompt**. The duplicated MCP sequence and can/cannot table are gone from the rule |
| Audit entry triggers | `agent-defaults-always` Â§Audits, `audit-protocol`, skill, project `audit.mdc` | **`audit-protocol`** for the trigger list, **skill `agent-code-audit`** for the procedure | Aligned **WQ-208**: all three carry the same words â€” audit, full scan, check everything, find problems, repeated still broken / anything else. `generic-deep-task-execution` adds depth requirements on its own broader triggers and links here rather than defining a second vocabulary |
| Session start | `agent-defaults-always` Â§Session start, all 5 entry templates | **`docs/AGENT_SESSION_START.md`** itself | Rule added 2.22.47 â€” templates had said it for three releases while no rule did |

---

## Canonical status propagation (when WQ changes)

**When moving a WQ to Done, Parked, or Active/Next**, update **all** that apply:

1. `docs/WORK_QUEUE.md` (required first)
2. `docs/handoffs/active/HANDOFF_WQ*.md` if tied to that WQ
3. Phase / gap plan row (e.g. `docs/MULTI_TOOL_GAP_PLAN.md`) â€” use **WQ id** in Notes, not conflicting phase-only labels
4. `docs/WORK_QUEUE.md` Active queue Â§11 â€” pointer only; no stale **Next** for Done IDs
5. Spec **status headers** (plan docs) â€” or add â€œsuperseded â€” see WORK_QUEUEâ€
6. **Product-truth docs** when the slice changed runtime behavior â€” capability reference, known limitations/tradeoffs, install/layout tables (project `DOC_MAP.md` if present); **not** covered by version-string sync alone
7. Run `verify-complete-picture.ps1` (maintainer pack repo) â€” **exit 0** before claiming slice done

**Phase ID map:** `docs/MULTI_TOOL_GAP_PLAN.md` Â§ Phase ID map â€” use when the same slice has multiple phase numbers.

---

## Known gaps (open engineering)

| Gap | Mitigation today | Better fix |
|-----|------------------|------------|
| HANDOFF body not auto-updated on WQ Done | verify-complete-picture FAIL | Optional `repair-handoff-status.ps1` (not built) |
| VERSION_SYNC scope (WORK_QUEUE header drift) | **Closed S2-9:** `docs/VERSION_SYNC.json` + verify-work-queue header checks | â€” |
| Product doc drift after ship | WORK_COMPLETION Â§ Step 3 + **complete-picture** (ROADMAP + product-truth + pack header) + **Update-AgentStack -VerifyOnly** | **Closed 2.22.67** for mechanical path â€” audits still report semantic drift |
| complete-picture rule only on user ask | WORK_COMPLETION step 5b + **Update-AgentStack -VerifyOnly** | **Closed 2.22.67** |
| Install from an unsanitized transferred folder | `install.ps1` copies the checkout, so a foreign `docs/AGENT_CONTEXT.json` or overlay could reach the profile; step 50 keeps them out of git and `sanitize-machine-state.ps1` clears a copied folder | Wire `machineLocalPaths` into `install.ps1`'s skip list as well (WQ-425) |
| Session doc **header** status is unchecked (**WQ-431**) | **Closed 2.22.67:** WORK_QUEUE header **Next active ID** vs Active **Next** row (pack repo) | â€” |
| Cited paths under `docs/`, `scripts/`, `tests/` are unchecked in this repo (**WQ-433**) | Step 47 covers `pack/`-rooted cites; a doc cited under `docs/` but absent went unnoticed until a manual sweep (2.22.55) | Same obstacle as the row below â€” most such cites are project-relative by design, so a check needs per-path ownership to avoid noise |
| Generated Cursor hooks have no refresh path (**WQ-435**) | `bootstrap-project.ps1 -Force` is the only writer; `repair-agent-docs.ps1` covers docs, not `.cursor/hooks/` | A project bootstrapped before 2.22.63 keeps the hook that blocks on an open stdin, and the pack cannot reach it - needs a repair command run in that project |
| Many handoff sources, no single index | This file + complete-picture inventory | â€” |
| 5 rules no verify script names | `generic-phased-feature-design`, `generic-implementation-readiness`, `generic-terminal-and-build-hygiene`, `generic-version-sync`, `new-project-bootstrap` â€” the last two are covered indirectly (step 23, step 33) | Readiness table enforcement is behavioural; optional future behavior step on plan docs with stale Phase 0 rows |
| Rule advice pointing at **project** files is unchecked | Step 47 resolves `pack/`-rooted citations; project-relative ones (`docs/ROADMAP.md`, `scripts/apply_version.py`) cannot be resolved from here, since they exist only in a bootstrapped app | Would need a check that runs inside a bootstrapped project, not in the pack |

---

## Related

| Doc | Role |
|-----|------|
| `pack/docs/WORK_COMPLETION.md` | Post-ship checklist |
| `pack/docs/PACK_MAINTENANCE.md` | Where to edit pack vs app |
| `pack/docs/AGENT_HANDOFFS.md` | Handoff file convention |
| `docs/MULTI_TOOL_GAP_PLAN.md` | Phase ID map |
