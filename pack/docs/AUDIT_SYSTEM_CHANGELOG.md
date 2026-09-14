## 2.22.123 (2026-09-11)

**WQ-480 — the fear was the finding.** Authorizing the OpenCode install, the maintainer attached a
warning: *"I fear we are changing one specific design for another instead of creating a tool that
will work on all AI inference engines/models."* He was right, and specifically so. 2.22.122 had
**named** the rule — decision data belongs in a host-neutral file, only plumbing may be
host-specific — and then shipped an OpenCode config next to a Cursor config without applying it.

**Three things were Cursor-shaped, and each would have forced a second implementation.**

| Was | Now | Why it would have cost an implementation |
|---|---|---|
| `pack/templates/cursor/hooks/preapproved.json` | `.agent-control/policy.json`, found by walking **up** the tree | Shared data inside one host's folder becomes that host's data, and the next adapter copies it rather than reading it |
| Patterns were **regexes** | Patterns are **globs** | A glob compiles to a regex losslessly; a regex does not compile to a glob **at all**. OpenCode takes globs, so regex authoring locks the policy to whichever adapter was written first |
| Semantics lived only in PowerShell | `conformance.json` vectors, run by step 83 | One file stops adapters disagreeing about *data*, not about which rule wins or what counts as an ask |

The third is the one that would have been missed. A shared list feels like enough, and it is not: the
judgements that make this control usable rather than muted — refuse beats allow, only the ask section
counts, prose naming a command is not a request to run it — were PowerShell control flow. A second
adapter that got them subtly wrong would not crash; it would look installed and quietly decide
differently, which is this pack's signature failure shape. **So an adapter is not finished when it
reads the policy. It is finished when it passes the vectors.**

**Verified by the host, not from the documentation — and the distinction earned its keep.** OpenCode
**1.18.30** installed here via winget `SST.opencode`. `opencode debug agent build` in a bootstrapped
project resolves **all 33 compiled rules**, `*run_audit.cmd*` as `allow` and `*install.ps1*` as `ask`.
**Neither documented schema was correct:** current docs describe a v1 `permission` object and a v2
per-agent `permissions` array, while the binary resolves `{permission, pattern, action}` and accepts
authoring as `permission.<action>` = a bare effect **or** a glob→effect map. A block written from the
docs — which is what shipping in 2.22.122 would have meant — would have been a phantom control.

**Two deliberate asymmetries.** Refuse compiles to **`ask`, never `deny`**: refuse means *this control
has no opinion, let normal review happen*, so compiling it to `deny` would remove the approval the
owner is entitled to give. And allow is emitted **before** refuse, so the narrower rule binds last —
copied from how the binary orders its own built-ins (`*` allow first, specific `ask` rules after)
rather than from an assumption about precedence.

**Step 83: 12 arms → 20**, and it now runs the hooks from a **staged project tree** instead of where
they ship, so the upward walk that finds the policy is exercised rather than the fallback. Re-proven
under its own mutation (`-Only 83`: baseline green, step reported a failure under mutation).

**Found by running rather than reading, again.** The prover's parameter is `-Only`, not `-Steps`; the
wrong name silently began proving all 82 mutations and was killed after 25 minutes, leaving an orphan
child chain to clean up. The repo was intact because the prover works on a copy — but the lesson is
the familiar one: a wrong argument that produces *plausible silence* costs more than one that errors.

**Not shipped, and named:** the OpenCode plugin `stop` handback. It is TypeScript, this host has no
JavaScript runtime (no node, npm or bun — OpenCode ships its own and exposes no generic runner), and
`opencode run` needs provider credentials. It could be shown to **load** but never to **fire**, and
WQ-476 set this pack's bar at proving a hook fires. Shipping it would lower that bar quietly, which is
worse than leaving the row open with its blocker stated.

---

## 2.22.122 (2026-09-11)

Two maintainer questions, both of which found real gaps rather than session failures.

**WQ-478 — nothing in this engine asked how work should be *shaped*, only whether enough of it was
done.** He had measured it himself: a validation list ran **over a week**, concurrency helped a
little, **batching helped far more**, and he asked why that had never come up. The answer indicts the
rule set. All fourteen prior always-on rules ask *did you do enough?* — depth contracts, completion
checklists, a registry of 82 mutations. **None asked *what is the cheapest correct way to do this?***,
and `generic-deep-task-execution.mdc` pushes the other way on purpose: run every step, with tools, in
this turn. **An agent optimizes for what is checked**, so exhaustive serial work was the predictable
output — the slowest correct answer available.

**Parallelism is visible; batching is not.** Several calls in one message is a thing you can see.
Batching stays invisible until someone measures, because **the repeated cost is usually the gate
rather than the work** — and this engine is the textbook case: `verify-guard-proofs.ps1` costs a full
suite run *per entry*, so five steps proven one at a time cost five suite runs and five proven in one
lane cost one. `generic-execution-strategy.mdc` ships as the fifteenth always-on rule, with a test
for each shape (*does any item need another's output? if not, it is not serial work*) and a
requirement to name the choice in the first tool-using turn, so a reader can object before the cost is
paid instead of after. The clause that keeps it honest: **batching changes the shape, never the
amount.** "I batched, so I checked a subset" is forbidden — a batch that drops items is a shortcut
wearing the word — and depth wins on any conflict.

**WQ-479 — the pack is tool-neutral everywhere except its newest controls, and he is moving to
OpenCode.** The honest split: the audit engine, verify scripts, bootstrap, work queue and handoff
discipline are PowerShell and Python and do not care what editor runs them, and the generic rules
already export as plain markdown. **What is host-specific is WQ-476/477** — `.cursor/hooks.json` plus
PowerShell, designed and certified against one editor's hook surface without anyone asking whether
the mechanism ports.

**It ports, but by luck rather than design, and the reason is the reusable part:** the *decision list*
lives in a host-neutral JSON file and only the *plumbing* is Cursor-specific. Recorded as a rule for
the next control: **when a control is built on a host-specific mechanism, the data it decides from
belongs in a host-neutral file, and only the plumbing may be host-specific.**

**Measured, and it inverts the matrix's framing: on the two capabilities this pack most depends on,
OpenCode is better provisioned than Cursor.** It has a global always-on rules path that actually
loads (`~/.config/opencode/AGENTS.md`), where Cursor's profile folder loads nothing — which WQ-456
spent a release proving. Its `instructions` globs can name `.cursor/rules/*.mdc` **directly**, so the
rules need no conversion and no duplicate copy. It pre-approves commands **declaratively** through
`permission` rules, which is what WQ-476 needed a hook script to achieve. The parity matrix had
claimed *no host has a global rules path* — false, and it was written as "Cursor plus fallbacks" in a
way that hid the finding.

**`-Targets OpenCode` ships and Phase 3 deliberately does not.** Bootstrap writes `opencode.json`
with the `instructions` globs, confirmed by two independent doc sources. The `permission` block and
the plugin `stop` handback are **not** shipped: the schema differs between the v1 `permission` object
and the v2 per-agent `permissions` array, and the pack folder has no OpenCode to run
`opencode debug config` against. **Shipping a config that cannot be verified is how a phantom control
gets built**, and this engine already carries that lesson at the cost of a release.

## 2.22.121 (2026-09-11)

**WQ-477: a decision the maintainer had stated three times was still being asked, and the reason was
in a file rather than in anyone's memory.** He settled it on **2026-08-27** — publishing and git
require StarterPack-Airlock on the host Desktop — restated it on **2026-09-03**, and restated it
again on **2026-09-11** after an agent ended a turn asking him to set up publish in the default path.

**The cause is the part worth keeping.** `docs/WORK_QUEUE.md` recorded WQ-465 as *"You decide to
publish as an open decision"* and WQ-455 as *blocked on WQ-465 as if publish were undecided*. An agent reading the queue
therefore re-derived the ask **correctly**, from the record, every session. Three restatements in
chat could not outvote one line in a file, because a new session reads the file and not the history.
**A settled decision recorded as an open one is not a stale note; it is an instruction to ask again.**

**A second cause, recorded because the shape will recur.** The decision used to be carried by a rule,
`.cursor/rules/no-publish-from-this-machine.mdc`, deleted in **WQ-459** for a sound reason: its
*premise* — the execute bit lives only in git, so the pack must be committed — was exactly what that
row retired. The **content** it also carried went with it, and nothing checked which one was leaving.
**Retiring a rule's premise is not retiring its content.**

**Fixed in two parts, because the first part alone is what already failed.** The record now states the
decision with its dates and quotes and says not to raise it, and the macOS CI row moved to **Parked**
behind StarterPack-Airlock CI rather than a default-path question. Then, since a paragraph telling
agents not to ask is precisely the thing that did not work, the WQ-476 control was extended:
`preapproved.json` gains a **`settled`** list, and `offload-detect.ps1` flags an ask section that
re-raises one, **citing where the decision is recorded** so the handback points at the record instead
of asserting from nowhere.

**Checked before the command list, and deliberately outside the refuse skip.** The refuse list exists
so that an ask naming `install.ps1` or `git push` stays clean — those are genuinely the maintainer's.
But *"this is the human's call"* is the exact framing that produced this defect, so a settled hit wins
even when the same line matches a refuse entry. Step 83's new arm uses such a line on purpose.

**Same hook, different question, and this is the worse failure.** WQ-476 caught asks naming a command
the agent was cleared to **run**; this catches asks naming a decision already **made**. Offloading a
command spends a turn. Re-asking a settled decision tells the owner their answer did not stick.

**Discrimination survives, which is what keeps it enabled:** stating what a settled decision *means*
for the work passes clean, because the check reads asks rather than mentions. Evidence that the
change bites: the scratch table's `ask is a publish decision -> clean` case **failed on the new
build, and that failure was the point** — the expectation encoded the old belief.

## 2.22.120 (2026-09-11)

**WQ-476 closed the one rule in this pack that had no mechanism, and it was closed by execution
rather than by rewording it a fourth time.** `agent-defaults-always.mdc` forbids ending a turn with
"run X to fix" when the agent can run X. That paragraph was present, loaded, and correctly worded;
it was violated across four sessions and closed three times with better prose. The maintainer's
question was not what the rule said — it was **how he was supposed to know it would hold**, having
been told before. This file already had the answer: **a status field cannot hold a proof.** A
sentence in chat promising compliance is a status field, stale the moment the context window rolls,
with nothing running to contradict it.

**Two hooks ship, and which event does what was measured rather than inferred.** The documentation
lists return fields for six events and `stop` is not among them, so the design was settled by
instrumenting the events and reading the payloads:

| Event | Carries | Can act |
|---|---|---|
| `afterAgentResponse` | the assistant's message in `text`, ~560ms earlier | no |
| `stop` | `status`, `loop_count`, `transcript_path` — **no text** | yes, via `followup_message` |

**The event that can see is not the event that can act**, which is the opposite of the single-hook
design that would have been written from the docs. So `offload-detect.ps1` judges the message and
leaves a verdict on disk, and `completion-gate.ps1` acts on it.

**What counts as a violation is a list, not a judgement call:** the ask section naming a command that
`preapproved.json` already clears the agent to run. Both hooks read that one file, because two copies
would drift silently — the detector would stop flagging exactly what the approver had started
allowing. The discrimination is what decides whether anyone leaves this enabled: an ask naming
`install.ps1` or ending in `git push` passes **clean**, because those are the two categories this
pack has always said belong to the maintainer, and prose that merely *mentions* `run_audit.cmd`
passes clean because a changelog entry is not an instruction. A checker without those exclusions is
muted within a week, which this file records as a lesson already paid for.

**Proven end to end, not installed and assumed.** A self-test sentinel fires the handback without
anyone committing a real violation: the detector flagged at 09:16:09.40, the gate handed back at
09:16:10.03, and the follow-up arrived as a turn. Before that run, "the hook emits a followup" and
"Cursor delivers it" were two claims and only the first had evidence. The sentinel ships, because a
control nobody can exercise on demand is a control nobody notices has died.

**Pre-approval ships available and unregistered, and the asymmetry is asserted by step 83.** The two
hooks above *tighten* what the agent gets away with, so shipping them on costs a project nothing it
would want. `shell-preapprove.ps1` *widens* what runs unattended, and widening someone else's review
posture is not a default to choose for them. A future edit that quietly registers it in
`hooks.json.template` fails the step.

**Step 83 runs the hooks instead of reading them, with every payload BOM-prefixed the way Cursor
sends them.** That is not caution: the first live version of `shell-preapprove.ps1` was installed,
logging, and approving **nothing** for four commands straight, because Cursor prefixes its payload
with a UTF-8 BOM and `ConvertFrom-Json` threw on the U+FEFF. It looked installed and did nothing,
which is this engine's signature failure shape. Proven able to fail by pointing the detector at a
heading no message carries — the hook still parses, still logs, still exits 0, and silently approves
every offload.

**One portability defect fixed on the way in:** the hooks resolve their state directory through a
guarded candidate list rather than `$env:LOCALAPPDATA`, which is empty off Windows and would have
thrown on `Join-Path` — the same null-input defect that took step 54 red one release earlier.

## 2.22.119 (2026-09-11)

**A step that guards bash wrappers failed with a message about a null `Path`, and the step was
right to fail — it just could not say so.** Step 54 assembles its bash candidates with three
`Join-Path` calls over `$env:ProgramFiles`, `${env:ProgramFiles(x86)}` and `$env:LOCALAPPDATA`. On a
shell where the x86 variable is **empty**, `Join-Path` throws on a null `Path`, and under this
suite's `$ErrorActionPreference = 'Stop'` that aborts the whole step with
`Cannot bind argument to parameter 'Path' because it is null` — naming neither the variable nor the
step's subject.

**The guard existed and could never run.** The candidate loop opens with
`if (-not $cand) { continue }`, so a missing candidate was anticipated; it was simply guarded in the
wrong place. `Join-Path` fails while building the array, before anything iterates it. Guarding a
result cannot protect against an input, and this is the second time that distinction has cost this
engine a red step for the wrong reason — the same shape as the zero that meant "unknown" in step 72.

**Fixed by guarding the inputs**: each candidate is a base plus a leaf, skipped when the base is
null or whitespace, so a machine missing any one of the three roots loses that candidate instead of
the step. The failure was never about bash and never about the wrappers, which is why it deserves a
release note rather than a silent patch — **a check that cannot name what it found is indistinguishable
from a check that is broken**, and for one gate run this one was both.

**Found by running the gate against new work, not by looking for it.** WQ-476's hooks were being
verified; step 54 went red beside step 61 and read convincingly like collateral from the new files. It
was not. Step 61's failure *was* the new work — `Set-Content -Encoding UTF8` in a hook, which writes a
BOM on 5.1 and none on 7 — and fixing it does not touch step 54 at all. **Two red steps in one run are
not one cause**, which this engine has now recorded twice.

## 2.22.118 (2026-09-11)

**WQ-467 closed the only way an unreproducible event honestly can: the forensics came back negative,
and the next occurrence is now detectable.** Three registry rows went from `exempt` to full mutation
specs inside an hour with no edit anyone could account for — the maintainer's own edits covered five
rows of eight. The specs were sound and all three were later proven by execution, so what was
unexplained was never the content. It was the **transition**, and nothing in the system disagreed with
it.

**Ruled out by reading every writer, not by assuming.** No script in this repo writes the source
registry. `sync-audit-system.ps1` writes back into the source only under `-PullFromInstalled`, which
was never passed. `verify-guard-proofs.ps1` applies every mutation to `$workCopy` and reads the source
registry with `Get-Content` alone. A sweep for writes anywhere under `pack/audit/` finds only probe
roots — fixtures written into throwaway trees, with the real manifest read as a `Copy-Item` source.
That leaves a human, an agent, or an editor buffer flushing over the file, and none of those is
reproducible a day later. **So the deliverable is detection, because the row's own re-open trigger was
"a second unexplained status change" and nothing was watching for one.**

**`exemptSteps` is now declared in the registry and compared to the rows.** Step 71 already printed
`mutation 81, exempt 1` every run, and **a printed count nobody recorded is a number, not a check** —
that is precisely how the first transition passed as scenery. The list names steps rather than
counting them, because a count cannot see a **swap**: one row retrofitted while another regresses to
exempt leaves the total intact. Both directions are reported, and the benign one matters as much as
the regression — a row that gained a proof without the declaration being updated is how a declaration
rots into a number nobody trusts, which is the state this one was found in. The practical effect is
that a status change must be edited in two places in the same change, and **that second edit is the
explanation the incident lacked.**

The printed line now reads `exempt 1 (declared: 62)`, so the run says which row carries the debt
rather than how much debt there is. **Three new in-process fixtures** cover a row that stopped being
exempt without the declaration changing, a row exempt without being declared, and a registry with no
declaration at all. Step 71 keeps its registered mutation and was **re-proven red under it** on a
quiet tree — baseline green, no collateral. Full suite `Summary: 0 fail(s)`.

## 2.22.117 (2026-09-11)

**WQ-469 closed: the release narrative moved out of a scanned `.py`, because the guard reading it was
never wrong.** Step 65 scans `pack/scripts` and `scripts` for strings that tell a reader to run a
Windows-only entry point, and it fired three times on **one physical line** of
`scripts/fill_pack_semantic_report.py` — 88,997 characters of canned audit prose. Each hit was
correct on its own terms: the line named `run_audit.cmd`, later gained the word for raising an
exception, and once carried `-fix ` inside the very phrase describing the forbidden behaviour, since
`-match` is case-insensitive. **A scanner cannot tell prose about an instruction from an
instruction**, and the exemption route was closed by the scanner's own comment — a file-level
exemption is how the next real offender gets in beside a tolerated one. Three hits on the same line
also showed the compounding shape: **new prose inherits every literal already on that line.**

**The fix is a relocation, not a reword.** The canned per-section text now lives in
`scripts/semantic_report_content.json`, and the script is a loader that reads it, merges the
manifest's required sections, and writes the report exactly as before. **Verified by equivalence**,
not by inspection: the report generated after the move is identical to the one generated before it,
field for field, with only `generatedAt` differing. The script's own docstring now says what it is for,
which is the part a future maintainer needs — the file has to stay a loader, since prose that creeps
back beside the code is read by a code scanner again.

**Two extra findings came out of the move.** The first is a small lie in the manifest:
`scripts/fill_pack_semantic_report.py` was a declared consumer of `machineLocalPaths` and
`maintainerOnlyPaths` in `listConsumers`, and it never read either — step 60 counts a **text mention**
of a key as reading it, and the mentions were in the narrative. So the script was a phantom reader,
declared to keep step 60's undeclared-reader arm quiet about its own prose. Both declarations are
gone; the keys are still honoured by the two distribution channels that matter, which is what that
registry exists to enforce. The second is the general lesson: **prose in a scanned file does not just
trip scanners, it satisfies them**, and a registry entry created by a sentence is worse than one
missing, because it reads as a verified fact.

**New arm 5c on step 65** is what stops the narrative moving back: no line in the scanned set may
exceed **600 characters**. The measurement makes that threshold uncontroversial — with the prose out,
the longest line anywhere in the scanned set is **239** characters, against the 88,997 it replaced. It
is added to step 65 rather than shipped as step 83 because it has the same subject: what those files
may contain. Step 65 keeps its registered mutation and was **re-proven red under it** after the arms
changed. Full suite `Summary: 0 fail(s)`, and zero `[FAIL]` lines printed on the green run, which is
the 2.22.116 invariant doing its job on the release right after it shipped.

## 2.22.116 (2026-09-11)

**WQ-472 closed: a `[FAIL]` line in this pack now means a real failure, and a passing run that prints
one is itself a failure.** The suite runs child verifies against deliberately broken fixtures on
purpose — that is how a guard is shown to be able to fail — so those children print findings that are
not findings. Step 57's absolute-path arm tried to discard its child's output with `2>&1 | Out-Null`,
and **an error-only redirect cannot touch `Write-Host`**, which is the stream this pack reports on. So
the finding printed to the host, the parent audit quoted it into its Fix line (correctly — that is
what `Get-PackChildFailureDetail` is for), and the 2.22.109 certification reported a `SESSION` path
that exists in no file in the pack folder. It cost a full diagnosis pass: the file was clean, the child
verify exited 0 against it, and the suite reported zero failures. Nothing was wrong except the
plumbing.

**The fix is an invariant, not a patched arm.** A run that exited 0 must not have printed a marked
failure line, and that is checkable only by the parent, which is the one layer that sees both the exit
code and everything the child wrote. `verify-audit-system.ps1` now tees the behavior suite's output
instead of piping it straight to the host, and asks `Get-PackStrayFailureLine` whether a green run
printed anything marked `[FAIL]`. **Tee rather than capture-then-print**, because the suite runs for
minutes and a human watching it is entitled to see the steps as they go. Only `[FAIL]` counts;
`[WARN]` and `[SKIP]` are things a passing run is expected to say.

**Suppressing the child would also satisfy the invariant, and is the one fix that was off the table.**
That is the WQ-463 defect in the other direction: a failing child that says nothing cost four audit
runs and two disproven theories. So step 57's arm now **captures** with `*>&1` — which serves both
halves, since the host stays quiet on a green run and the text is finally there to assert on. That arm
had been reading exit codes alone, so it gained two assertions on the way past: the rejection must
name the absolute path it found, and the accepting run must say it judged the roots.

**New step 82** tests the helper on fixtures rather than inferring it from the caller, which is the
same shape step 74 uses for `Get-PackChildFailureDetail` and for the same reason — the parent that
enforces this cannot be run from inside the suite it runs. Three arms cover the sides an exit-code
gate can get wrong (clean pass, passing leak, real failure), one covers a single captured string with
a blank line in it, and two ask whether the parent still keeps a copy of the output and still calls
the helper. **A sixth arm greps this suite's own source** for in-process script calls paired with an
error-only redirect, because the invariant only fires once a leak exists while the grep fires when one
is written.

**Measured before shipping, not after:** with step 57 fixed, a green suite prints **zero** `[FAIL]`
lines, so the invariant could be turned on without hunting for further leaks — one arm was the whole
population. **Proof:** steps 57 and 82 both red under their own mutations, one lane, baseline green,
runner exit **0**, no collateral. Step 82's mutation inverts the gate in `Get-PackStrayFailureLine` so
the detector goes quiet exactly where a leak can happen, and it reddens two arms rather than one.
Reproducing the original incident by reverting step 57's redirect was **rejected** as the mutation: no
step runs `verify-audit-system.ps1` against this suite — step 23 passes `-SkipBehavior` and step 73
exists to keep that recursion out — so only the grep would have caught it, and a mutation proven by a
grep is weaker than one proven by behaviour.

## 2.22.115 (2026-09-11)

**WQ-471 closed: the five guards that asserted only a zero exit now assert what was produced.**
WQ-466 swept the suite for steps that asserted *that* a child failed without asserting **which**
finding produced the failure, and fixed eleven. The mirror image was never swept — steps whose only
assertion is that a child **succeeded** — and it kept surfacing on its own, three times while proving
a different step. That is the argument for sweeping rather than waiting for a fourth.

**Step 32 was the worst of them: one exit code for the whole step, output piped to null.** The
portable export is the paste-at-session-start rules file for every tool that is not Cursor, and that
population cannot notice staleness any other way — they read what the file says, not what the pack
ships. A detector that had stopped comparing anything would have satisfied the old arm. It now
requires the verify to name `GENERIC_RULES.md`, and to have compared this repo's **loaded** rules,
because that arm skips silently where `.cursor/rules` is absent and here it must run (WQ-456). Then
the positive control the step never had: a disposable two-file pack, exports generated into it, and
four kinds of drift planted in turn — a hand-edited rules export, a deleted one, a stale skill mirror,
and a loaded rule diverging from `pack/rules` — each of which must be **named**, from a freshly synced
export each time so one plant cannot be proven by another's damage.

**Step 39's fix is where the shape is clearest.** Its first arm reads the tree and its second asserted
a zero exit, and under the step's own mutation the second arm reports *matches pack export* about a
file that is not on disk. It now requires the verify to name the export it judged, and a second
control deletes that export again and requires the rejection to name it — so the case the repair
exists for is the case the verify is proven to see.

**Step 33** asserted two zero exits and read nothing, so a bootstrap that generated nothing and a
verify that judged nothing both passed; it now reads the instructions hub, the rules export and the
bootstrap record, and requires the verify to state the Portable-only profile it was asked to enforce.
**The product-truth skip arm** claimed the pack repo *skips* overlay checks while only reading exit 0
— a skip and a full pass are the same exit code — and now requires the script to say it skipped.

**Step 56 could not be fixed by asserting output, and the reason generalises.** `update-agent-stack`
delegates without `-PassOutput`, so `verify-complete-picture` prints to the host and never reaches a
captured stream; the first attempt at the fix failed on exactly that. What discriminates is the
**verdict**, so the control is a project that must fail Step 5b — a `ROADMAP.md` still marking a
shipped WQ as **Next** — because a delegation that has stopped happening cannot report a failure. The
old arm's OK line claimed Step 5b had run, which the arm never checked.

**All five re-proven on the changed arms**, two lanes, each with its own green baseline, runner exit 0
in both. Collateral moved from suspected to confirmed in one place: step 32's mutation also fails
step 23, because that step drives a generated project through its own audit, which runs this same
verify — the earlier record listed steps 23 and 52 as *unverified* collateral measured under four
concurrent lanes, and step 52 was the contention artefact, not collateral.

**The new step 56 earned itself on the first certification run after it shipped.** The release note for
WQ-472 quoted the planted-fixture path verbatim into this repo's own `docs/handoffs/SESSION.md`, which
is exactly what the absolute-path check exists to reject, and `verify-complete-picture.ps1` went red on
the maintainer repo. The old arm — exit code only — would have passed while the delegation it guards
reported a failing project as aligned; the rewritten arm named `WORK_COMPLETION Step 5b` in its failure
text and pointed straight at the cause. One prose fix cleared all three reported failures. Where a
guard's own release note trips it, the guard is not too strict: prose about a bad path is still a bad
path once a reader copies the line.

## 2.22.114 (2026-09-11)

**WQ-433 closed: a `docs/`, `scripts/` or `tests/` path named by a rule, skill or pack doc now has a
declared owner, and the ones this pack delivers are checked for being deliverable.** Step 47 resolves
`pack/`-rooted cites only, which is why a design-reference doc that was cited but absent survived
until a manual sweep in 2.22.55. The other three roots were left out for a good reason rather than an
oversight: a doc naming `docs/ROADMAP.md` is describing the reader's project, and this pack has no
roadmap by decision. Measured before designing anything, an indiscriminate pass over those roots
reports **68 findings on a clean tree, every one of them correct advice about somebody else's tree** —
which is how the first attempt at this check got muted, and a muted check is worse than none.

**So the work was ownership, not scanning.** A cite under those roots has three possible owners and
only one of them is settled by asking whether the file is here:

* **the pack folder** — `docs/WORK_QUEUE.md`, `scripts/audit_code_checks.py`. Must resolve, and this is
  the **default for anything undeclared**, so a new cite is checked without anyone listing it.
* **delivered** — the reader's project gets it *from this pack*. Existence here is the wrong question;
  the right one is whether the pack can still produce it, which is a **stronger** check, because
  advice to keep a file no template writes is undeliverable. 14 paths, each declared with its
  deliverer: `docs/ROADMAP.md` from a template, `docs/AGENT_REFRESH.md` from the refresh script,
  `scripts/doc_version_sync.py` from `pack/scripts` (the one Python-stack file bootstrap copies
  rather than templating).
* **the reader's own** — `docs/PRODUCT_REFERENCE.md`, cited as "or equivalent". Nothing here can check
  it, so the only honest treatment is to say so: 3 paths, each carrying a why, **printed as INFO on
  every suite run**. An enumerated mute is the alternative to a quieter check.

**Ownership is declared per path, not guessed from the citing file, and prose-sniffing was tried and
rejected.** One paragraph cites both trees: `START_HERE.md` line 22 contrasts this repo's work queue
with a bootstrapped app's roadmap in a single sentence. A negation filter fares no better — the same
doc says "there is no `docs/AGENT_SESSION_START.md` here", which a filter reads as an exemption and a
reader reads as the truth. The declaration lives in `pack/audit/manifest.json` as
`citedPathOwnership`, and **a declaration nothing cites any more is a failure**, not a leftover, on
the same reasoning as a find that matches zero times.

**New behavior step 81, mutation-proven, and it found a defect in itself on its first run.**
`Get-PackCitedProjectPathReference` bound `[string[]]$Lines` without `AllowEmptyString`, so every
document with a blank line failed to bind and the scan reported **nothing** — the shape of failure
this pack keeps relearning, where a clean result and a blinded check are indistinguishable. It was
caught by the arm that requires at least 100 cites before believing a clean verdict, which is the
same argument step 80 shipped a fixture for. The step splits three ways: extraction tested in memory
(a backslash cite is the same path, `.md.template` must not truncate to `.md`, and a `pack/`-rooted
cite belongs to step 47), judgement tested against a synthetic tree with six planted defects
including a stale exemption, and the live surface. The mutation renames a cite in
`RULES_AND_VERIFY_MAP.md` and leaves the old one pointing at nothing — the original incident — and it
reddens the **undeclared default**, which is the arm that matters. Deleting a template to exercise
the deliverable arm was rejected: bootstrap copies it, so four steps would have gone red and four
failing steps prove less than one. Step 47 and step 81 now share `Get-PackCitedReferenceFile`, so a
new document class cannot arrive into one scan and not the other.

**The scan found no live defect**, which makes this a guarantee rather than a repair: 35 distinct
cites across 45 documents either resolve here, deliver from a template or script that exists, or are
declared unowned with a reason.

## 2.22.113 (2026-09-11)

**WQ-462 is finished: steps 4, 7, 15, 18, 23 and 34 proven, and no grandfathered exemption is left
in the registry.** Of the 70 steps seeded as `grandfathered-pre-wq443` when the registry shipped, 69
now carry a mutation the runner has applied and watched go red; the last, step 62, is
`not-applicable` because its subject is the git index on a checkout that keeps no git. Every proof
in this batch was taken twice — once to find out what was wrong, and again on the final tree with a
green baseline in its own lane.

**The runner could not express two of these steps, and that was the reason they were exempt.** A
mutation spec could only replace text, so a guard whose subject is a file's *absence* (step 4 keeps a
duplicate audit template out of the pack) or its *presence* (step 7 requires two agent docs) had no
spec that could reach it. The registry now has three actions — `replace`, `create`, `delete` — with
mirror-image staleness rules: a create whose target exists, or a delete whose target is already gone,
describes a tree where the guard should already be red, and is refused the same way a find matching
zero times is. Six new controls in step 73; `Get-PackMutationAction` is the single reader, so the
validator, the registry check and the runner cannot disagree about what a spec means.

**Step 15 was rewritten before it could be proven, because it observed nothing.** It matched four
sample strings against two regexes, and all six were literals written out in the step itself — no
change to the pack could make it fail, and it had passed unchanged through every rewording of the
messages it claimed to check. That is the WQ-443 defect, sitting in the suite built to catch it. It
now reads the classifier's patterns out of `run_audit_core.ps1` and the gate messages the engine
actually emits out of `audit_code_checks.py`, and fails when the two disagree — with a blind-guard
arm that fails loudly if either can no longer be found.

**A list argument does not survive `-File`, and two things were quietly wrong because of it.**
`powershell -File script.ps1 -Only 4 7` binds `4` and drops `7` without a word; the comma form is
worse, because `[int[]]'4,7'` does not throw — .NET reads the comma as a digit-group separator and
returns **47**. A run asked to prove steps 4 and 7 proved step 47 and exited 0, reporting success for
work nobody requested. Pairs of two-digit steps escaped only by luck.

The same transport had been lying inside **step 34** for far longer. It bootstrapped a project for
Claude, Copilot and Windsurf, received one for Claude, and the registration script reported the two
missing adapters as "skipped (not in bootstrap targets)" and exited 0 — so the step printed OK for
three editors having checked one. Nothing found this in review; the guard proof found it, because
mutating the Windsurf template changed nothing that was ever written to disk. Fixed at the transport
(`Expand-PackListArgument` in `pack-paths.ps1`, used by `bootstrap-project.ps1 -Targets` and
`register-tool-adapters.ps1 -Tool`, which drop their `ValidateSet` because a joined string fails it
before the body runs), in the runner (`-Only` parses through `Get-PackRequestedStepNumber`, seven
controls including the pair that once resolved to one step), and in the step itself, which now
asserts the recorded targets, the three adapter files on disk, and that the registration skipped
none of them.

**What this closes, and what it does not.** WQ-462 moves to Done with 79 mutations declared and
proven and one reasoned exemption. `WQ-471` — guards that assert only an exit code — is smaller than
it was, since step 34 was its worst instance and is now content-asserting, but steps 39 and 32 remain
open. The plan's Phase 5 is complete.

## 2.22.112 (2026-09-11)

**WQ-462 batch nineteen: steps 1 and 38 proven, the two that batch eighteen could not prove. Retrofit
count: 7 exempt, 63 proven of the 70 grandfathered steps.** Neither was provable by writing a better
mutation. Both were blocked by defects in the machinery around them, and both mutations had already
been written — what changed is the code they ran against.

**`WQ-475` — a child's stderr is output, not a terminating error.** Every pack script sets
`$ErrorActionPreference = 'Stop'`, and under it PowerShell wraps a native command's stderr in a
`NativeCommandError` that terminates the caller. So a tool reporting a problem the way Python reports
problems killed whatever was running it, before the exit code could be read. It cost two separate
runs to see the whole shape: the guard runner died at its invoke line, and once that was fixed the
**suite itself** died on its own first step and wrote no results at all. Fixed at the choke point
rather than the call site — `Invoke-PackPython` and `Invoke-PackScript` in `pack-paths.ps1` now run
children with the preference set to `Continue`, function-scoped, leaving the caller's untouched. The
verdict was always `$LASTEXITCODE`, which this does not change.

**`WQ-473` — the session hook's stdin drain is gone, not repaired, and the reason is measured.**
2.22.63 bounded the drain with `Task::Run` and a scriptblock, which needs a runspace that a
threadpool thread does not have: it faulted in ~6ms and never read anything, for three releases. The
obvious fix was written first — a real off-thread read via `BeginRead`, bounded by `WaitOne(250)` —
and measured, because that is the lesson this item taught. **In isolation it drains correctly and
exits in about half a second. Inside the hook, which goes on to spawn a Python child that inherits
the same handle, it hung past 15 seconds on both PowerShell hosts.** The working version of the
courtesy reintroduces the defect it was meant to fix. The hook never needed the payload — it reports
context freshness and ignores what Cursor sends — so it now reads stdin by no route at all, and says
so where the drain used to be. Measured after: 0.35–0.55s to exit on both hosts, stdin held open,
payload or none.

**Three things the hook fix broke, each caught by a green baseline rather than by review.**
*Detection read prose.* `repair-project-hooks.ps1` matched the file text, and the new template's
comment explains the stdin read it deliberately does not perform — so the shipped template reported
**itself** stale, and every project generated from it followed. It now tokenises and drops comments
before matching, which also closes the reverse hole: a comment mentioning the guard could have
vouched for a hook that still hangs. *Patterns matched source, not tokens.* The tokeniser splits
`[System.Threading.Tasks.Task]::Run` into five tokens, so `Task\]::Run` matched nothing until it
allowed the gaps. *A guard that hangs does not fail.* The arm running the hook on fresh context had
no bound, so restoring the original defect left a run going for **half an hour** instead of failing
in twenty seconds — the 2.22.63 incident reproducing inside the guard written to catch it. Both hook
invocations in step 38 are now bounded, and `verify-guard-proofs.ps1` takes `-TimeoutMinutes`
(default 12) so a hung mutation is killed and **reported as hung**, which is a different verdict from
"did not fail".

**Projects carrying the 2.22.63 hook are now repairable.** `repair-project-hooks.ps1` knows two stale
shapes rather than one: the pre-2.22.63 unbounded `ReadToEnd`, and the 2.22.63 drain that faults
instead of reading. Step 58 gained an arm that plants the second shape and requires the repair —
without it, a test written against the hang accepts a hook that never drains, which is how the shape
survived three releases.

**`WQ-474` did not reproduce.** Twenty-three suite executions today across three- and four-lane
concurrent runs, after the `export.ps1` `$PID` fix, with **zero** contention failures in steps 52, 54
or 23 — including step 54, which the previous release could not clear. No mechanism was ever found
for the step 54 sightings, so this is recorded as not reproducible rather than fixed, and the lane
cap is lifted to four.

**The two proofs.** Step 1 adds a module to the self-test's expected domain map for section F that
the fixture never had, so the engine's own proof reports the mismatch and exits 1; collateral is wide
and unavoidable — steps 21, 22, 23, 43 and 54 all gate on that one pass/fail signal. Step 38 restores
the unguarded `[Console]::In.ReadToEnd()` verbatim, in the file and at the point where it originally
sat; step 58 is declared collateral because the template becomes stale by definition, and step 23 is
left undeclared because it is the defect reaching a generated project rather than a witness.

**Twelve proofs re-taken.** Every step proved in 2.22.110 and 2.22.111 under `-SkipBaseline`, or in a
lane whose baseline had failed, was re-run on the current tree with a green control inside its own
run: steps 5, 17, 27, 29, 32, 33, 35, 40, 41, 42, 43 and 56, plus step 54 serially so contention
could not manufacture a false proof. All twelve held.

## 2.22.111 (2026-09-10)

**WQ-462 batch eighteen: steps 5, 17, 33, 35, 41 and 56 proven. Retrofit count: 9 exempt, 61 proven
of the 70 grandfathered steps.** The nine that remain are a named list with a reason each, not a
backlog.

**A product defect fixed, found by running the suite in parallel.** Two lanes rather than four this
release, per the concurrency cap, and step 52 contended anyway — so the mechanism got tracked down
instead of worked around. `export.ps1` staged into
`Join-Path (Get-PackTempDir) "cursor-starter-export-$stamp"`, and `$stamp` is **`yyyyMMdd`**. Every
export on the same day therefore resolved to the same `%TEMP%` directory, and the line after it is
`Remove-Item $temp -Recurse -Force`. Two exports at once destroyed each other: one zipping a tree the
other had just deleted, which is exactly the two errors the lanes reported —
`Copy-Item : The process cannot access the file` and
`CreateFromDirectory ... Could not find a part of the path`. **This needs no test harness.** Two
users, or one user twice in a day, is enough. Fixed by adding `$PID` to the staging path and
**verified by deliberately re-running two lanes at once: zero step 52 failures in either, both proofs
intact.** Step **54** still contends under concurrency — seen once beside step 27 and once beside
step 41 — and its cause is not yet identified, so `WQ-474` stays open narrowed to that step and lanes
stay capped.

**The runner has a blind spot of its own, filed as `WQ-475`.** Step 1's mutation was authored, ran on
a green baseline, and the runner **crashed instead of recording the failure it had just caused**. The
mutation worked: the engine's self-test detected the stale expectation and printed
`parse_domain_map F: expected ...`. It printed to **stderr**, PowerShell wrapped that in a
`NativeCommandError`, and the runner's own `$ErrorActionPreference = 'Stop'` made it terminating at
the line that invokes the suite — no results file, no attribution, a call stack where a verdict
belongs, and the two steps sharing that lane never ran. Step 1 is therefore blocked on the runner
rather than on a better spec, because every mutation that reddens it must make the self-test print;
printing is how it reports. Reconnaissance also corrected a claim this project had carried in step 2's
`rejected` note since batch one: a `Fail` in step 1 does **not** abort the suite, and results are
written unconditionally.

**The six proofs.** Step 5 plants the loophole rather than removing the prohibition — a debug audit
script may run machine checks only — because that arm expects zero findings from a text scan, and a
scan that finds nothing looks identical whether the file is clean or the check is blind; the
prohibition appears exactly once in that skill, so removal was available and simply proves less. Its
proof is also narrower than the step number suggests: the manifest-coverage arms sharing step 5 are
still unproven and this does not claim them. Step 17 writes the timestamp into the field that holds
the test-pass proof, the copy-paste slip between two adjacent `Add-Member` lines, so the pairing
between a finalize pass and the tests it finalizes silently stops being checkable while both fields
still look populated — collateral in steps 18 and 23, both declared, both of which read that field.
Step 33 inverts the test for a Portable-only project so the verify recognises every target except the
one it is named for. Step 35 inverts the freshness module's own expectation about a fresh context, so
it reports a self-test failure when correct and passes when not. Step 41 points doctor at a Python
probe that does not exist, which is both a portability regression and a runtime error, since the
shared helper is what finds `python3` where there is no `py` launcher. Step 56 sends the
work-completion check to `verify_complete_picture.ps1` — underscores where the hyphens belong, the
slip this repo is built to produce, since its Python files use underscores and its PowerShell files
use hyphens.

**One candidate was measured instead of assumed, and it mattered.** Step 56's first spec dropped
`-AllowMissing` from the completion check, on the reasoning that strictness would fail on a repo with
no ROADMAP. Running it took seconds and showed exit **0** either way — the sources it would tolerate
as missing are present here — so the spec would have been inert and cost a lane to discover.

## 2.22.110 (2026-09-10)

**WQ-462 batch seventeen: steps 2, 8, 22, 27, 29, 32, 40, 42, 43 and 54 proven. Retrofit count: 15
exempt, 55 proven of the 70 grandfathered steps.** Ten steps in one release against two in each of
the previous four, and none of that came from the steps being easier.

**What changed is the release, not the mutations.** Certification — `run_audit.cmd`, then the
semantic fill, then `verify_semantic_audit`, then `finalize_audit` — costs about **12 minutes per
release and nothing per step**, because it runs the suite over the whole pack either way. Proving two
steps per release paid that toll five times for the same work. Nothing required the batch to be
small: the runner already copies the pack per entry and keeps its scratch under `guard-proofs-$PID`,
so entries are isolated from each other by construction.

**Four lanes, 8.7 minutes, seven steps.** One lane carried the baseline control and three ran
`-SkipBaseline`, on a tree frozen at 250 files for the duration — the fingerprint the runner takes at
both ends is what makes a frozen tree checkable rather than assumed. Serially those runs would have
been about 33 minutes. A suite run is process-startup bound, not CPU bound, so on 24 cores the lanes
overlap almost perfectly. The reconnaissance was parallel too: four read-only agents worked disjoint
step sets and returned candidate mutations with verified occurrence counts, which is the part of this
work that is judgement rather than waiting.

**The ten proofs, grouped by what they restore.** Three are inverted comparisons, the shape that
survives review because the code still runs: step 27 flips the front-matter test deciding whether a
rule is always-on, so the brief tells an agent the opposite of what its editor will do in both
directions — the WQ-456 failure exactly, where a rule was present, correct and never loaded; step 32
flips the export drift comparison, so a stale portable rules file verifies clean for the population
that has no other way to notice; step 2 lowercases a section key on the way into a domain map whose
keys are uppercase, so every module list arrives empty while the row still looks right, and a section
reports a complete review of a scope it was never given. Three restore a decision or a defect the
pack has already paid for: step 40 misses one site in a rename, so the override that points user-scope
paths at scratch is ignored and the real profile answers — the incident where asking a probe for a
scratch destination silently rewrote `%USERPROFILE%\.cursor`; step 43 marks the Windows Python
launcher required on the branch that only runs off Windows, telling every Mac and Linux user their
machine cannot run the engine; step 22 drops `-DualShell`, halving host coverage while every run still
says OK, for the defect class this pack has actually shipped (a BOM on one host, `-Include` matching
3723 files on one and 4 on the other). Two are entry points that only break where nobody looks: step
42 points the POSIX audit wrapper at a script that does not exist, which is inert on Windows and fatal
on the machines least able to diagnose it, and step 54 puts an off-by-one in the bootstrap usage guard
so a no-argument run generates a project into whatever directory the shell was in. Step 29 turns a
`#Requires` directive into a comment — a tidying edit that enforces nothing, which is why it is the
realistic one; nobody deletes a version floor on purpose. Step 8 stubs the test-pass proof head, so a
report written against an older tree can never be found stale and the freshness gate stops being a
gate.

**Step 38 refused to prove, and that is the most valuable thing in this release.** The mutation raised
the Cursor session hook's bounded stdin drain from `Wait(250)` to `Wait(60000)` — restoring the hang
that once held the whole audit for eleven minutes with no output — and the suite stayed green. The
reason is not a weak mutation. **The drain never runs at all.** A PowerShell scriptblock cast to
`[Func[string]]` and handed to `Task::Run` has no runspace on a threadpool thread, so the task faults
immediately and `Wait` returns at once whatever timeout it is holding. Measured directly with stdin
redirected and held open: `faulted=True, elapsed=6ms`, parent saw exit after 164ms. So the hook never
reads Cursor's payload — the promise in its own comment that a writer never sees a broken pipe is not
kept — and step 38's hang arm passes because of the fault rather than because of the bound, which
means a real regression in that timeout would go unseen. Filed as **WQ-473**; step 38 went back to
**exempt** rather than being declared proven, because a mutation that cannot reach the behaviour
proves nothing. This is the third distinct way a guard has been found green-by-accident, and the
first found by a mutation *failing* to make one red.

**Concurrency cost one lane and three collateral lists.** Steps **52** (export) and **23**
(bootstrap) fail under concurrent lanes with `Copy-Item : The process cannot access the file` — a
sharing violation, not an assertion — and they fail in every lane, because the suite runs all 80
steps no matter what `-Only` selects. That voided one lane's baseline, correctly taking its three
proofs with it, and planted phantom collateral in three others, so the collateral records for steps
27, 32 and 42 say **unverified** rather than claiming none. Lane 1 was re-run alone on a green
baseline, where steps 2, 8 and 22 proved with no collateral at all. Filed as **WQ-474**: capping
concurrency at two lanes is the cheap answer, but a probe that reaches outside the copy it is
supposed to exercise is also a probe that can pass while that copy is broken, which is the WQ-466
shape and worth fixing on its own merits.

**Also corrected here:** `docs/GUARD_PROOF_PLAN.md` still reported the retrofit at "3 of 70, 67
left" — sixteen batches stale, because the per-batch record went to this changelog and the queue and
nobody re-read the plan that aims the work.

## 2.22.109 (2026-09-10)

**WQ-462 batch sixteen: steps 21 and 26 proven. Retrofit count: 25 exempt, 45 proven of the 70
grandfathered steps.** Two of two, zero collateral, against a green baseline. Both mutations are one
token wide and both restore a decision rather than inventing a defect.

**Step 21 — a required git contradicts a settled decision.** The preflight sorts every requirement
into required (the engine cannot run) or optional (one feature degrades). The mutation promotes
**git** to required, which is the WQ-459 decision reversed: version control is optional to this pack,
and a download, a zip, a folder copy and a flash drive are all supported deliveries. Without git the
user loses a git-HEAD fingerprint in the test-pass proof and gets a file-tree one instead — that is
the whole cost. A required git would tell a first-time user their machine cannot run the audit
engine, and it would say the same about **the pack folder**, which keeps no repository at all.

The mutation lands in the branch that runs whenever git is present, so the preflight still exits 0
and still reports `ok`: the only thing that moves is the column saying whether the user has to act.
Breaking the Python probe to force a non-zero exit was rejected — that proves the gate rather than
the required-versus-optional split, and several steps depend on this preflight passing, so the
failure would have spread to steps that say nothing about requirements.

**Step 26 — the install that eats the user's other MCP servers.** `Merge-McpJson` adds an empty
server map only when the config lacks one. The mutation drops that negation, so a config that *does*
have servers has the map replaced with an empty one, and every server the user configured is gone
once the file is written back. That is the original incident's symptom exactly: the installer once
kept only `agent-hygiene` and destroyed the rest. It is the worst class of defect this pack can
ship — it happens during an install, to a file the pack does not own, on a machine where the user's
own servers are the reason that file exists.

Restoring the *cause* rather than the symptom was rejected on precision. The original was a
dot-assignment on a `PSCustomObject` from `ConvertFrom-Json`, which throws; the throw escapes to the
step's own catch, so the step fails through `installer probe error` instead of through the arm that
counts surviving servers. **A sign error that lets the function keep running proves the arm; an
exception only proves the try block.** The BOM arm keeps passing, since the write path is untouched.

No collateral either side, and step 26's reason is structural: `install.ps1` is the one script the
suite cannot run for real, so its functions reach the suite only through the AST extraction this step
performs, and no other step extracts `Merge-McpJson`.

**Two self-inflicted stops during this release, both instructive.** A `Set-Content -Encoding UTF8`
used to patch `scripts/fill_pack_semantic_report.py` from the shell wrote a **BOM** — the exact
construct step 61 bans, committed by hand in the session that proved it — found by reading the first
three bytes and removed with a byte-level rewrite. Then the word `throw ` entered that file's
narrative, putting a message-pattern token on the one physical line that already carries
`run_audit.cmd` and `run_tests.bat` from older release prose, so step 65's arm 5 reported instruction
text naming a Windows entry point. Both guards were right, and this is now the **third** hit of the
second kind on that same line, logged on **WQ-469**: new prose inherits every literal already on the
line, which argues for moving release narrative out of a scanned `.py` rather than for policing
adjectives.

**New Inbox row WQ-472, from diagnosing the above.** The failing audit quoted two `[FAIL]` lines, and
only one was real: the other — *SESSION names an absolute path … `E:\SomeCheckout\...`* — is a
**planted fixture** inside an expected-fail arm, printed to the host with the same prefix as a
genuine failure. `Get-PackChildFailureDetail` quotes child marked lines by design (WQ-463), so a
parent detail can carry a line that no file in the checkout contains and no verify actually failed
on. Attribution is unaffected, because it reads `Fail` calls rather than output; this is a reporting
defect, and the fix is for planted arms to mark or capture their child output.

## 2.22.108 (2026-09-10)

**WQ-462 batch fifteen: steps 30 and 39 proven. Retrofit count: 27 exempt, 43 proven of the 70
grandfathered steps.** Two of two, one collateral step each, both declared in advance and both worth
reading rather than narrowing.

**Step 30 — a warning that reports the opposite population.** The audit surfaces a stale
`AGENT_CONTEXT.json` stamp as **Improve**, addressed to the agent so it offers the refresh instead of
handing the user a command. The mutation inverts the staleness comparison, so the line goes silent on
the project that needed telling and fires on the one that is current. That is worse than the
pre-WQ-456 world it restores: before, nothing reported staleness and the only way to find out was to
run the refresh the warning would have told you to run — under the mutation the feature looks present
and reports the wrong half. Two arms fail, which is the payoff for asserting the check in both
directions: the stale arm loses its line, and the current-stamp arm — added so the warning could not
become wallpaper — sees a nag. The no-stamp and bootstrap-stub arms keep passing, since neither
reaches the mutated comparison.

Re-routing the line from **Improve** to **Fix** was the other candidate, and it was rejected on blast
radius rather than realism: an extra Fix changes the audit's exit code on a fixture several other
steps run, so the failure would have spread to steps with nothing to say about agent context.

**Step 39 — a flag defaulted the wrong way.** `Sync-ProjectPortableExports` decides whether to copy
the pack's rules export into a project, and its `$needsCopy` flag starts at `$true` so an absent
destination is copied. The mutation starts it at `$false`, so the one case the flag exists for is the
case it skips: a project whose `docs/portable/GENERIC_RULES.md` was deleted or never arrived keeps a
repair that reports success and restores nothing, and an agent on Claude, Copilot or Windsurf has no
rules export to read while every check says the project is fine.

**The second arm's silence is the finding.** After the mutated repair, `-VerifyOnly` reads the same
flag and reports *`GENERIC_RULES.md matches pack export`* about a file that is not there, exiting 0 —
and arm 2 only checks the exit code, so it cannot see it. That is a live instance of the **WQ-471**
shape (a guard asserting only that a child succeeded), found inside a step being proven for something
else. It is recorded on that row rather than patched here, because the fix is the sweep.

**Collateral, both correct.** Step 30's mutation also fails **step 23**, which drives a generated
project through its own audit — the same `run_audit_core.ps1`, so any change to the Improve set
reaches it. Step 39's also fails **step 33**, and that one is informative: bootstrap and repair share
one copy path, so the function named "repair" is also how a newly bootstrapped Portable project
receives its rules export at all. Narrowing either mutation would mean splitting a path the product
deliberately shares.

## 2.22.107 (2026-09-10)

**WQ-462 batch fourteen: steps 52 and 61 proven. Retrofit count: 29 exempt, 41 proven of the 70
grandfathered steps.** Two of two, zero collateral, against a green baseline.

**Step 52 — the arm with no second check.** Step 52 unzips a real export and asserts three things:
every mirrored file is present, no machine-local state travelled, and no maintainer-only path did.
The first of those is double-covered, because `export.ps1` already throws on its own when a
`packMirror` file is missing — so the mutation targets the maintainer-only strip, which nothing else
watches. It mistypes the separator normalisation (`-replace '/', '\'` becomes `-replace '/', '_'`),
so every entry resolves to a path that does not exist, nothing is removed, and the archive ships this
repo's session notes and its workspace-only rules to a recipient. The export still exits 0 and this
checkout stays green, because here those files belong.

Renaming the manifest property would have been the easier mutation and was rejected: the list is
declared in `listConsumers`, so steps 53 and 60 would have failed alongside, and three red steps
would have proved only that a key is mentioned somewhere. Keeping the read intact and breaking the
*use* is what separates "the strip is wired up" from "the strip works."

**Step 61 — a scanner cannot be proven by blinding it.** This step parses every `.ps1` in the pack
and rejects three constructs that differ between PowerShell 5.1 and 7. Its expected result is zero
hits, which means a blinded detector and a clean tree produce identical output — so the mutation
plants a defect instead: `Set-Content -Encoding UTF8`, the construct that writes a BOM on 5.1 and has
crashed Python's `json` reader on generated files. The plant sits behind `if ($false)`, so the parser
sees it and the process never runs it; no script changes behaviour, and the failure is attributable
to this step alone.

That mutation also documents a gap rather than closing it: **step 61 has no positive control.**
Nothing in it watches the detector fire, which is the same gap step 80 closed for the POSIX scanner
by shipping a fixture containing the banned constructs. Until step 61 gets one, this proof is the
only evidence the scan works, and it exists in the registry rather than in the suite. Recorded in
the step's registry note; it is a candidate for the same fixture treatment, not a defect in the
proof.

**Method note.** Two mutation ideas were discarded for being unsafe in a child process rather than
unrealistic — dropping `-Recurse` from a folder removal raises a confirmation prompt that a
non-interactive run can sit on instead of failing, which would hang the suite rather than fail a
step. A mutation has to fail loudly; one that blocks is worse than one that proves too little.

## 2.22.106 (2026-09-10)

**WQ-462 batch thirteen: steps 37 and 58 proven. Retrofit count: 31 exempt, 39 proven of the 70
grandfathered steps.** Two of two, zero collateral, against a green baseline. Both mutations are sign
errors rather than deletions, which is the shape that survives review.

**Step 37 — an early return that is legitimate one line earlier.** `Test-ProductTruthRoadmapAlignment`
returns immediately when no id is Done, because with nothing shipped there is nothing a roadmap can
contradict (the WQ-432 reasoning). The mutation changes that condition to one that is always true, so
a roadmap still marking a shipped id as **Next**, or still linking its active handoff, is never
reported. Nothing about the mutated line looks wrong, and the check's output is identical to a clean
run — it prints nothing either way. The pack-repo arm and the header-alignment arm keep passing
correctly, the latter because it is a different function, which is what makes the failing arm
attributable.

**Step 58 — the test that decides whether a hook is even a candidate.** `Test-HookIsStale` first asks
whether the hook drains stdin at all; the mutation inverts that one match, so every hook that drains
stdin — exactly the shape that hangs a session start — is declared current, and the repair reports
success with the hang still reachable. The rejected alternative is worth keeping: loosening the paired
requirement to "either guard is enough" proves nothing, because the planted hook has neither guard and
is stale under both readings.

**A step's assertions can be complete and still not discriminate, and step 34 is the positive-path
case.** WQ-466 swept the suite for guards asserting *that* a run failed without asserting *why*. The
mirror image was not swept: guards asserting only that a run **succeeded**. Step 34 bootstraps a
project for three editors and asserts that the adapter registrar exits 0 — and nothing else. A
registrar that wrote no adapter and exited 0 would satisfy it, which also means the only mutation that
can turn the step red is one that changes an exit code. Filed as **WQ-471** rather than half-fixed
here, because the value is in the sweep, not in one step.

**Method note.** Two registry entries were left with an orphan field after an in-place edit, and the
prover refused to run rather than reporting anything about the steps named — the JSON parse failure
surfaced as a rejected run. Worth stating because it is the desired behaviour: a registry that cannot
be read is not a registry that says everything is exempt. Validate the file with a parser after
editing it, not by eye.

## 2.22.105 (2026-09-10)

**WQ-462 batch twelve: steps 36, 55 and 64 proven. Retrofit count: 33 exempt, 37 proven of the 70
grandfathered steps.** Three of three went red under their own mutation against a green baseline, and
all three targets were chosen for the same reason: each guards a promise whose failure would be
discovered by a human losing something rather than by a check going red.

**Step 36 — a preview that is not a preview.** The archive script's documented contract is that
running it without `-Apply` changes nothing, which is why the docs tell agents to run it that way.
The mutation adds a second term to `if (-not $Apply)` so the preview branch is unreachable and a
preview run falls through to `Move-Item`. Two arms see it at once — the eligible-preview arm loses the
`Would move` line it asserts on, and finds the file already gone. The active-handoff arms keep
passing, correctly: the status gate stops the loop before the mutated branch, so those arms were
never evidence about `-Apply` in the first place.

**Step 55 — the phrase that carries the WQ-415 defect.** `$staleShippedPatterns` is what turns "this
doc still says a shipped slice is not built" into a finding. The mutation replaces `not built` with a
synonym nobody writes, so the probe's `WQ-042 is not built yet` sails through. Nothing about the list
looks broken afterwards, which is the point — an emptied list is visibly wrong, a near-miss pattern
reads as working code.

**Step 64 — one character in a config key.** `load_historical_regions` reads
`historicalRegions` in exactly one place; the mutation drops the plural, so no region loads, and the
sync rewrites the Done log while reporting `ok`. That is precisely how the protection would disappear
in practice, and it separates *the config declares protection* from *the tool honours it*: arms 1 to
3 read the config through `verify-work-queue.ps1` and still find the declaration, so only arm 4,
which runs the tool, can see the difference.

**The collateral is worth reading as a result, not as noise.** Step 64 also failed **step 22**, which
runs the unit suite, because `test_version_sync_leaves_the_historical_region_alone` asserts
`frozenRegions` contains the work queue. The same promise is guarded twice — once as a unit test on
the tool, once as a behavior arm on the config — so a mutation narrow enough to fail one and not the
other would mean the two had stopped testing the same thing. Registered on the row rather than
"narrowed".

**Also confirmed: the `-Only` list trap is in the runner's own invocation, not only in
`Start-Process`.** Passing `-Only 36,55,64` through `powershell -File` collapsed the list to
`365564`, and the runner refused the run rather than silently proving nothing — the rejection added
in 2.22.87 doing its job. Invoke the script with `-Command "& '<path>' -Only 36,55,64"` so the array
survives argument parsing.

## 2.22.104 (2026-09-10)

**WQ-470: the reporting contract required a closing line that turned every finished task into a
checkpoint.** The rule set told agents to end a reply with `Nothing needed from you` whenever they had
no ask. Two costs, and the second is the expensive one. The line is noise the reader still has to
read. Worse, it reads as the turn being returned: a finished work-queue row followed by "nothing
needed from you" looks exactly like a request to confirm, so the user spends a turn saying *continue*
for work they had already authorized in full. A status line that cannot distinguish "I am done with
everything" from "I am done with this one and waiting" is a false stop.

**The phrase was in no pack file, and that is the finding to carry forward.** A grep of the whole
checkout for it returned nothing: the instruction lived in the editor's own user-rules store, which
no pack guard reads, no sync writes, and no verify can see. The user reported it as a defect in this
tool, and the report was fair — the pack ships the reporting contract — but the literal instance was
reachable only through the editor's rules API. **Before editing pack text to change an agent
behavior, grep the checkout for the exact string the user quoted**; when it is absent, the pack can
still fix the *shape* it teaches, but the *instance* lives somewhere else and has to be corrected
there.

**What changed.** `generic-structured-chat-output.mdc` now forbids an action section with nothing in
it — an empty **What I need from you**, a standing "nothing needed" line, or any sentence whose only
content is that the agent has no ask — on the reasoning that the section's **absence** is the
message. It also forbids returning the turn to ask for work the user already authorized, and points
at the queue rule for the substance. `generic-work-queue-discipline.mdc` gains **Continuing without
being asked again**: under a standing instruction to work a queue or a project, the end of the turn
is the next **Active** row, not the finished one, and the agent stops only for a decision that is the
user's to make, credentials or hardware it does not have, or a conflict with something already
settled. The required bullet that used to read "when anything is left for the user" now reads "when —
and only when — something is genuinely the user's to do", because the permissive reading is what
allowed an empty section to satisfy it.

**No new behavior step.** Both changes are rule prose, and the suite cannot test what an agent writes
in chat; `schemaSealedAtStep` is untouched at 70 and the exempt count is unchanged. What is
mechanically verified is delivery: `sync-project-rules.ps1 -VerifyOnly` at 14 rules, which is the
only channel that puts these two files in a load path.

## 2.22.103 (2026-09-10)

**WQ-462 batches ten and eleven: steps 16, 19, 25, 28, 51 and 59 proven. Retrofit count: 36 exempt,
34 proven of the 70 grandfathered steps.** Two of the six could not fail as written, and both
failures were the same shape as WQ-466 rather than a repeat of it.

**Step 19 accepted an empty phases map.** `-not $tl.phases` is false for `{}`, because
`ConvertFrom-Json` returns an object with no properties rather than `$null`. The timing log could
therefore ship with a total, no breakdown, and a green step. The mutation is a guard that requires
the map to be non-empty before writing its first entry — a condition that can never become true —
and the assertion now counts the properties.

**Step 16 asserted `test|proof|manifest`.** WQ-466 gave that step a message check; nobody checked
that the message was *specific*. All three words occur in ordinary audit output, so bypassing the
finalize gate entirely left the step green: the run still exited non-zero over the incomplete
semantic report, and the loose pattern matched that instead. It now looks for
`Audit finalize blocked`, which only `Test-ManifestFinalizeAllowed` emits.

That second finding is the general one, so the suite was swept for it: **six assertions matched text
the run produces anyway.** `ROADMAP` is the clearest — `-notmatch` is case-insensitive and the
probe's own directory is named `cp-roadmap-probe`, so the assertion passed on any output that echoed
the project root. `Next`, `open`, `cite`, `evidence` and the bare `3` for an exit code were the rest.
Each now carries the producer's own sentence. **A message assertion is only as good as the narrowest
thing that can produce the message** — the WQ-466 sweep proved the assertions existed, not that they
discriminated.

The other four went green first try: **step 25** widens the fixture-filler opt-in so one shipped
command can mark every checklist section reviewed with no findings; **step 28** routes a layout
finding to `Add-LayoutFix`, a real function one word away, turning Section B back into a delete list;
**step 51** drops case folding from the Python half of the state-root key while PowerShell keeps it,
so the two halves address different directories on the one platform where paths are case-insensitive;
**step 59** drops the segment anchor from the illustration-name test, and since `Users` contains the
allowlisted `user`, every real machine path in a general doc becomes an example.

**Step 62 was considered and is already settled**, as `not-applicable` since 2.22.88: its subject is
the git index and the pack folder keeps no version control (WQ-459), so it takes its documented
`[SKIP]` every run and a content mutation has nothing to break. Recorded here because the batch
reached for it first, and the registry note — not memory — is what stopped a second look at it.

## 2.22.102 (2026-09-10)

**An approval retry that fails is the agent's mistake, not a broken dialog.**

A sync the agent could run ended up as a command handed to the user, after six approval retries came
back `Failed to find tool call context`. The agent called that a rendering failure. It was not: a held
command must be resent **byte-identical**, paired with the **exact** rejection text *that* command
produced. Every failed retry had been edited between the block and the resend — output shortened, a
comparison reworded — or paired with a reason string from an earlier, different block. The one retry
that succeeded that day was the one resent unchanged. With nothing to match the retry against, the
approval had nothing to attach to and never reached the user.

Two failures compounded: the wrong diagnosis, and then treating it as a blocker, which
`agent-defaults-always.mdc` already forbids — it says not to end with "run X to fix" when the agent
can run X. That rule now also carries the mechanism, under **When approval is required, resend the
command unchanged**, including the heuristic worth having: *if two retries fail, suspect the retry,
not the harness.*

Reported by the maintainer, who read "the approval card failed to render" and correctly answered that
this describes an unaddressed problem rather than an explanation.

**Second finding, from the same session: `request_smart_mode_approval` is a retry flag, not a request
flag.** Setting it on a call that has *not* just been rejected produces the identical
`Failed to find tool card` error, because there is no rejection for the approval to attach to. Call
plainly first; escalate only after a block. That is the half the first diagnosis missed, and it is
why the error kept recurring after the byte-identical rule was written.

**Third, and the reason step 65 fired twice on this release:** the semantic report's narrative lives
inside a scanned `.py`, and `-match` is **case-insensitive**. The phrase describing the forbidden
behaviour — a "run-this-to-**fix**" instruction — contains `-fix `, which is the scanner's `-Fix `
token, on a line that already carries two Windows entry-point names from an older entry. A
hand-rolled pre-check missed it twice: once by running before the last edit, once by being
case-sensitive when the scanner is not. A pre-check that does not evaluate `$msgPattern` from the
suite's own source is a guess about the guard, not a check of it.

## 2.22.101 (2026-09-09)

**WQ-462 batch nine: steps 63 and 70 newly specified, steps 65, 67 and 69 re-proven. 5 of 5, zero
collateral. Retrofit count: 42 exempt, 28 proven of the 70 grandfathered steps.**

**Step 63** turns the segment test back into a substring test, and its damage runs backwards from most
defects. A bare `__pycache__` also matches a file named `__pycache__.txt`, and `.git` swallows
`.gitignore` — so the filter gets *broader*, scans quietly exclude files they are supposed to judge,
and every step downstream reports clean on a smaller tree than it claims to have read. Collateral
from a mutation like this would show up as steps staying **green**, which is why the step tests the
primitive directly instead of trusting its callers to notice.

**Step 70** inverts the orphan test so the detector returns only rules the pack *does* ship — the
WQ-460 state, where no detection existed. The inversion is a better target than an empty return,
because the function keeps enumerating, keeps reading front matter and keeps producing results; it
just never produces the file that matters. A detector reporting nothing invites suspicion, one
reporting the wrong set looks like it is working.

**Steps 65, 67 and 69 were re-proven rather than assumed — see WQ-467.** At the start of batch seven
the registry read 52 exempt with those three among them; forty minutes later it read 43 exempt with
all three carrying full mutation specs, and my edits in that window account for five rows, not eight.
The installed mirror synced in between already had them, so the change happened in the source before
the sync rather than by pulling from the mirror. The specs are sound — all three fail under their own
mutation on demand — but the transition is unexplained, and an unexplained change to the file that
records what has been proven is worth its own row rather than a shrug. **The prover is the answer to
this class of doubt:** any row's truth can be settled by running it, which is why a stored `proven`
status was refused in 2.22.83.

## 2.22.100 (2026-09-09)

**WQ-462 batches seven and eight: steps 24, 44, 50, 60, 66 proven. Retrofit count: 47 exempt, 33
proven of 80.**

Three of the five restore the defect they were written from rather than an approximation of it:

| Step | Mutation |
|---|---|
| 24 | An em dash in a docstring of a file that runs — the character behind three separate encoding failures |
| 44 | The sync child's exit code kept and its output discarded, so a red run names no drifted file |
| 50 | The illustration name in a shipped doc overwritten with something indistinguishable from a real person |
| 60 | A declared reader inlines the manifest list it is supposed to look up |
| 66 | A required POSIX twin renamed in the only script that can write it |

**Step 66 needed a second spec, and the first one's failure was informative.** It broke
`run_tests.sh`, which `projectRequired` does not demand — so nothing became undeliverable and the
mutation was inert. Chasing that turned up a live overstatement in the guard: arm 1's comment claims
it checks **both** directions, but the loop only walks `projectRequired` asking whether each required
twin is deliverable. The reverse case it describes — a deliverable twin nobody requires — is not
implemented, and `run_tests.sh` is an instance of it right now. Harmless in practice, since the repair
writes it either way, but the comment promises more than the code does.

**Step 66's proof costs steps 18 and 23 as collateral, correctly.** Both drive a generated project
through its own audit, and a project whose `run_audit.sh` cannot be written fails from where they
stand too.

## 2.22.99 (2026-09-09)

**WQ-466: eight guards asserted "it failed" without asserting *why*. Two of them were proving
nothing.**

Three WQ-462 batches in a row hit the same shape — steps **9, 10 and 12** each stayed green under
their own mutation because the fixture was being rejected for a reason the step does not name. Rather
than trip over it a fourth time, the suite was swept for it: `if ($LASTEXITCODE -eq 0) { Fail ... }`
with the child's output thrown away.

**11 rejection assertions, 8 blind** — steps 16, 20, 37 (three), 55 (two), 57. All eight now capture
the output and assert which finding produced the rejection. **Two were defective rather than merely
weak, and the new assertions found both on their first run:**

1. **Step 37's product-truth arm had never exercised what it claims.** Its probe held only
   `WORK_COMPLETION.md`, so `verify-complete-picture.ps1` stopped at `no handoff sources found` and the
   arm passed on that exit code. The delegation it exists to prove was never reached. The probe now
   carries a `WORK_QUEUE.md`.
2. **Step 57's capture was blind.** It used an error-only redirect, but the script reports findings on
   the **information** stream — so the capture was an empty string and the arm was comparing against
   nothing. A full redirect fixes it. *A capture that cannot see the output is not a check.*

**Postscript: writing this entry tripped step 65, and the guard was right.** Naming the host-write
cmdlet as a bare literal in the semantic report's narrative put it on the same line as two Windows
entry-point names that had sat there harmlessly for four releases — and step 65 reads a Windows entry
point beside a print call as an instruction that cannot run off Windows. Certification failed with
three Fix lines that all traced to that one line. **The fix was the prose, not an allowlist entry:**
the scanner's own comment says a file-level exemption is how the next real offender gets in beside a
tolerated one, and it is right about that too. Worth knowing before writing narrative into a scanned
`.py` — the audit reads it as code because it is.

**The rule, stated once here rather than rediscovered per batch:**

> A step asserting a rejection must assert **which** rejection, and its fixture must be valid in every
> respect except the one defect under test.

An exit code is shared by every reason a run can fail, so it cannot attribute. This is the same
finding as WQ-443 — a guard must be proven able to fail — one level in: a guard can be provably able
to fail and still be measuring the wrong thing.

## 2.22.98 (2026-09-09)

**WQ-462 batch six: steps 6, 12, 14 proven, zero collateral. Retrofit count: 52 exempt, 28 proven of
80.**

**Step 12 was the third fixture in a row passing for a reason it did not name.** It removed
`hardware_cache.py` from section F's `modulesReviewed[]` as well as from disk, and that omission raises
its own coverage fix — so `--verify-semantic-report` was rejecting the report over coverage, and would
have kept rejecting it with the alignment test negated. Reproducing the fixture by hand showed
**eleven** other fixes in the same output.

The fixture now *keeps* the module listed, which is also the truer setup: the expanded domain map is
built from config rather than from disk, so a section listing a deleted module is precisely the
contradiction under test — it claims to have reviewed what the machine reports missing.

**This is now a rule, not an anecdote.** Three of the six steps in batches five and six were passing
on unrelated rejections. A step that only checks *that* a verify said no cannot tell a proof from a
coincidence:

> Any step asserting a rejection must assert **which** rejection, and its fixture must be valid in
> every respect except the one defect under test.

**Steps 14 and 3 stay separate on purpose.** Step 3 asserts `audit_code_checks.py` *raises* the
incomplete-audit fix; step 14 asserts `run_audit_core.ps1` files it into the gate channel instead of a
section. Raising it and then misfiling it is a different failure — a whole-audit gate that reappears as
Section L reads like one checklist item somebody can tick off. Mutating the recogniser rather than the
raiser keeps the two proofs from overlapping.

## 2.22.97 (2026-09-09)

**WQ-462 batch five: steps 9, 10, 11 proven. Two of the three were passing for reasons they did not
name — the most this exercise has returned in one batch.**

Retrofit count: **55 exempt, 25 proven** of 80.

**Steps 9 and 10 both survived their first mutation green.** Both fixtures omitted `modulesReviewed[]`,
which is required for sections D–K, so `--verify-semantic-report` was rejecting the report over *that* —
and would have gone on rejecting it with cite checking and the evidence minimum switched off entirely.
Step 9 compounded it by giving section D a lone `command` evidence item, which trips the file/test
requirement when not clean: a third unrelated ground for the same rejection.

Both are fixed the same way, and the fix has two halves:

1. The fixture is now valid in **every** respect except the one defect under test.
2. The step asserts the rejection **names** that defect.

The second half is the durable part. A step that only checks "the verify said no" cannot tell a proof
from a coincidence, and the coincidence is what it had.

**A mutation has to survive whatever runs before the step it aims at.** Step 9's obvious target was
`summary_has_cite` returning `True`. That is asserted directly by `audit_code_checks.py --self-test`,
so step **1** failed first, the suite aborted before writing a results file, and the runner could only
report "no results file" — no information about step 9 at all. The config default was mutated instead.
Recorded in the control's `rejected` field so the next person does not spend the same run finding out.

**Step 11 costs step 2 as collateral, correctly.** Step 2 reads the same manifest and asserts sections
F and K arrive complete, so a blanked `machineCheckCount` is a real defect from where it stands too.
Narrowing the mutation would mean singling out one section by letter, which is not a shape any refactor
produces.

## 2.22.96 (2026-09-09)

**WQ-464: the macOS risk that can be checked without a Mac, now is (new step 80, mutation-proven).
WQ-455 split and marked Blocked with the reason written down.**

The maintainer has no Mac, and the pack folder has **no `.git`** (by decision, WQ-459) — so no workflow
in `.github/workflows` can run at all, the nominally-blocking Linux job included. Waiting on hardware
to check something a script can decide is how a gap stays open for releases, so the decidable half was
split out and closed.

Two of the failure families behind WQ-436's macOS surprise are visible in the text:

| Family | Examples |
|---|---|
| GNU coreutils macOS does not ship | `sha256sum`, `md5sum`, `timeout`, `stat -c`, `grep -P`, `date -d`, `find -printf`, `base64 -w`, `readlink -f`, and `sed -i` with no backup argument — on BSD that eats the next word as the suffix |
| bash 4 syntax macOS will never have (pinned at 3.2) | `mapfile`, `declare -A`, `${v^^}`, `**/` |

`Get-PackPosixPortabilityHit` decides both; **step 80** runs it over every shipped `.sh`. **All 23
pass** — the surface was already clean, so this is a guarantee rather than a repair. The one `stat -c`
in the repo is inside the **Linux** job, where it is correct, and the macOS job was already written to
avoid it.

**Scoped to shipped `.sh` on purpose.** A Linux-only CI job may legitimately call GNU tools, and
failing it for that is how a check earns a mute — and a muted check is worse than none. Two controls
guard the opposite errors: every rule carries a positive case, because a detector nobody has watched
fire is a detector nobody has tested; and a portable sample that *names* the banned constructs in a
comment must pass, because naming a thing is not calling it.

**What still needs the hardware**, recorded on WQ-455 rather than implied: a case-insensitive
filesystem, a `pwsh` that must be installed rather than assumed, Python provisioning, Gatekeeper on a
downloaded copy, and the suite's 80 steps actually executing.

## 2.22.95 (2026-09-09)

**WQ-432 settled by reading the script, and the Inbox emptied.**

**Why the same verify appears at 3c and 5b.** `pack/docs/WORK_COMPLETION.md` carried an open note: step
3 says product-truth drift blocks the close, but the audit that catches it is step 6, *after* the row
is moved to Done at step 5. The contradiction is real in the prose and absent in the mechanism.
`verify-product-truth-paths.ps1` finds contradictions by reading the **Done log** and asking whether
any doc still calls those ids not built or deferred — and `Test-DoneWqProseContradictions` **returns
immediately when there are no Done ids**. Run at **3c**, the row being closed is not in the Done log
yet, so the check cannot see it: it passes vacuously. Run at **5b**, the row is Done and the check has
its subject.

So **5b is the gate and 3c is a preview.** No step was reordered — the table was already right, the
note explaining it was not. 3c stays because its other checks (files exist, ROADMAP no longer reads
**Next** for that id) do not depend on the Done log and are cheaper to fix before the row moves.

**Inbox is empty.** `WQ-433` (cited paths under `docs/`, `scripts/`, `tests/` unchecked) moved to the
Active queue as the only row describing a **detection gap** rather than a convenience. `WQ-418`,
`WQ-421` and `WQ-422` moved to Parked, each with a **Re-open when** that names the evidence that would
justify building it — not a date. All 93 ids reconcile; `verify-work-queue.ps1` and
`verify-complete-picture.ps1` both exit **0**.

## 2.22.94 (2026-09-09)

**WQ-462 batch four: steps 3, 13 and 20 now carry executable mutations. 3 of 3 proved; 58 grandfathered
steps left.**

| Step | Guards | Mutation restores |
|---|---|---|
| 3 | `-SkipTests` must exit 1 | A tests-skipped run that raises no incomplete-audit fix, so it exits 0 and reads as complete |
| 13 | Section L `.gitignore` audit artifacts | An inverted report condition: a `.gitignore` missing an artifact passes |
| 20 | Mirror direction | The installed copy overwriting the source pack |

**Target the fix, not the exit code (step 3).** The exit code is derived from the fix count, so
mutating the `exit` statement would produce a report saying the audit was incomplete while the process
said it passed — a different defect from the one the step guards. **Expect step 14 as collateral**: it
asserts the same fix reaches the manifest's gate list, so no mutation of that fix separates them.

**Invert, do not empty (step 13).** Emptying the default artifact list is a visibly broken config;
an inverted test looks like a working check right up to the point where a manifest full of machine
paths gets committed. Collateral is low by construction — under the mutation the check reports *fewer*
gaps, so other steps lose a fix rather than gain one.

**Step 20's indent is load-bearing**, in the now-familiar way: the same `Copy-File` call appears inside
a one-line `if` on the preceding branch, and a spec matching twice is rejected.

## 2.22.93 (2026-09-09)

**WQ-452: a project's `AGENTS.md` no longer has to name the *Windows* entry points (new step 79,
mutation-proven).**

Section L required the literal strings `run_audit.cmd` and `run_tests.bat`. A project whose
`AGENTS.md` correctly tells a Linux reader to run `./run_audit.sh` therefore **failed its own audit
for being correct** — the last place still carrying the assumption WQ-449 removed everywhere else.

`agentsMdRequiredPhrases` entries may now be a **list**, meaning *any one of these*. The default is:

| Requirement | Satisfied by |
|---|---|
| Audit entry point named | `run_audit.cmd` or `run_audit.sh` or `run_audit.ps1` |
| Test entry point named | `run_tests.bat` or `run_tests.sh` or `run_tests.ps1` |

A plain string still means that exact phrase, so **a config that pins names keeps pinning them** —
asserted, because a permissive check that quietly stopped enforcing anything would look identical from
the outside. Section F takes the same shape, so one key does not mean two things in one config file.

**Four places carried the assumption, not one**: the code default, the generated project's
`AUDIT.config.json.template`, and both reference configs. Fixing only the default would have left
every newly generated project pinned to Windows names in its own config.

Two of step 79's four controls exist to stop the fix going too far: an `AGENTS.md` naming **no** entry
point at all must still be caught, and a pinned config must still pin. Expect step 23 as collateral
when re-proving — under all-of, the generated projects it bootstraps cannot name every spelling
either.

## 2.22.92 (2026-09-09)

**WQ-447: a generated project's runners are now proven thin, not just the pack's own (new step 78,
mutation-proven).**

Step 22 has always proved the *pack's* `.bat`/`.sh` pair delegates to one implementation. Nothing
proved the same of the pair a **generated project** receives — and that is where drift costs most: a
project whose `.bat` grows a step its `.sh` lacks runs a different suite per platform, and the audit's
test-pass proof only ever observed whichever one ran.

Step 78 bootstraps a Generic project and reads the **generated files**, not the templates, because
reading a template is evidence about the template. For both pairs (`run_tests.bat`/`run_tests.sh` and
`run_audit.cmd`/`run_audit.sh`) it extracts the scripts each wrapper hands off to, ignoring comments,
and requires: both delegate to the shared implementation, both hand off to the **same set** of
scripts, and neither invokes anything beyond it. A last control requires the implementation to be
non-empty — two wrappers agreeing on nothing is not delegation.

Note the generated `.sh` wrappers deliberately do **not** use `pwsh-wrap.sh`, unlike the pack's own:
a generated project must run its own tests without the pack present. Step 22's rules could not simply
be copied.

**Expect step 23 as collateral when proving this** (the registry says so). Any mutation of a runner
template also reaches the generated projects step 23 bootstraps and runs, so no target isolates step
78 — the same situation as step 46.

## 2.22.91 (2026-09-09)

**WQ-444: five byte-identical copies of the markdown section slicer became one (new step 77,
mutation-proven).**

`Get-SectionBody` was defined, identically, in `archive-completed-handoff.ps1`,
`verify-agent-handoffs.ps1`, `verify-complete-picture.ps1`, `verify-work-queue.ps1` and
`verify-product-truth-paths.ps1`. That is not a tidiness complaint: one defect in it cost **five
patches** in 2.22.73. The start-header search was unanchored, so it matched a heading *quoted inside a
table cell*, began the Done section in the middle of the Active table, and reported every Active id as
both active and done.

It now lives once, as `Get-PackSectionBody` in `verify-lib.ps1`. Four of the five scripts did not load
the library at all and now do. All four verify scripts still exit **0**.

**Step 77 mutates the behavior, not the consolidation.** Removing the line anchor recreates the
2.22.73 defect exactly. Asserting only "there is one copy" would be satisfied by one copy of a broken
function, so the behavioral controls come first and the single-home scan is last.

**The first version of step 77 was not provable and the runner caught it**, which is the reusable
lesson. Its fixture quoted only the *end* header in a table cell, and start and end are matched by
separate code — so the suite stayed green with the start anchor deliberately removed. The fixture now
quotes **both** headers before their real heading. This is the fourth inert-fixture mistake in the
WQ-443 family, and every one of them was caught by running the mutation rather than by reading the
test.

## 2.22.90 (2026-09-09)

**WQ-463 closed. The cause was a version cite synced too late; a second, real defect was found on the
way there.** Two new steps, both mutation-proven: **75** and **76**.

**The cause (step 76).** Bumping the engine leaves `pack/docs/AUDIT_SYSTEM.md` carrying the old
version, and `verify-audit-system.ps1` fails on that mismatch. Inside a full audit the failure
surfaced two layers away — in a *generated project's* bootstrap check, as `verify-audit-system.ps1
failed against the starter pack itself` — and then vanished, because the audit's own later sync
repaired the header before the next run. That is the entire "first audit after a bump fails, the
second passes" effect, and it is not intermittent at all: it is deterministic on a version bump and
invisible on every run after one.

**It was found by the instrumentation shipped one release earlier**, which is the argument for
building that first. The very next failure said, in the Fix line, `AUDIT_SYSTEM.md header must mention
starter pack 2.22.90 (run sync-doc-versions.ps1)`. Six runs had produced nothing but "a verify
failed".

The sync now runs in `scripts/run_audit_tests.ps1`, the build/test entry point that owns derived
files — not in the audit, which must judge those files rather than rewrite them. Step 76 guards the
**order**, not the mere presence of a call: a sync that runs after the check repairs the next run and
proves nothing about this one. Its second control asserts the audit has *not* grown its own sync.

**The second defect (step 75): verification was validating the user's backup copy of the pack.**
Discovery is broad on purpose — a project outside the pack must be able to find one, so it searches
the profile, the Desktop and the OneDrive Desktop. `verify-audit-system.ps1` reused that list and
validated **every copy it found**. This machine exposes three: the checkout, the installed copy, and a
backup on a OneDrive Desktop still at 2.22.83; the certification log shows three `Pack:` headers, one
of them the backup. This was found while chasing the intermittent and is a genuine defect on its own —
a backup is not a stable input (OneDrive hydrates and re-syncs it, and it changes whenever a newer
pack is copied over it), and a failure in it is unactionable from where the message lands.

**A backup is not a delivery.** `Get-PackVerifyRoot` narrows verification to two copies: the pack
these scripts belong to, and the one installed on this machine. Skipped copies are **named on screen**
rather than silently dropped, so "why is my other copy not checked" has an answer without reading
source. Discovery itself is unchanged — narrowing that would break finding a pack from another project.

Step 75's controls include path spelling (case, trailing separators, slash direction), because a
normalization miss there drops the *real* pack instead of a backup and verifies nothing at all, which
reads as success. Two earlier theories were disproven by experiment along the way and are recorded in
`docs/WORK_QUEUE.md` so they are not raised again: a stale installed copy, and "first audit after an
edit".

## 2.22.89 (2026-09-09)

**A parent that reports "the child failed" now says what the child said (WQ-463).** New behavior step
**74**, mutation-proven, and the first step added since the seal — so it arrived with an executable
proof rather than an exemption, which is what the seal is for.

**The defect this fixes is not the intermittent; it is why the intermittent survived six runs.** Step
23's bootstrap checks failed twice with `verify-audit-system.ps1 failed against the starter pack
itself` and nothing more. The child's output went to the host, which the behavior harness swallows, so
each occurrence cost a full audit run and produced no reason at all. Two plausible causes were
investigated and **both disproven by experiment** — a stale installed copy (a suite run against a
deliberately mismatched install was clean) and "first audit after an edit" (a full audit on an edited
tree was clean). Neither could have been settled from the message, and neither should be re-raised
without new evidence.

`Get-PackChildFailureDetail` in `verify-lib.ps1` builds the reason: it quotes the child's marked lines,
caps the quote and says when it truncated, and — the case that made this expensive — **reports a
non-zero exit with no output as exactly that, naming the exit code**, rather than appending nothing.
An empty detail would read as "the child had nothing to say" instead of "it would not say". Step 74's
last control asserts `run_audit_core.ps1` actually calls the helper, because a tested function nobody
uses reports nothing.

**WQ-463 stays open, and deliberately so.** The instrumentation is complete; the cause is not known.
The next occurrence will name itself in the Fix line.

## 2.22.88 (2026-09-08)

**Third retrofit batch: steps 31, 57 and 68 are proven, and step 62 is reclassified rather than
retrofitted (WQ-462).** Twelve steps now carry executable mutations; 61 remain exempt.

**Step 62 will never be proven on the pack folder, and saying so is more honest than leaving it
grandfathered.** Its subject is the git index — the only place a file's execute bit durably lives,
since a folder copy, a zip and a Windows checkout all lose it — while the runner mutates file
*content*. On a pack that keeps no version control by decision (WQ-459) the step takes its documented
`[SKIP]` on every run, and **a skipped step cannot be proven able to fail**. It now carries the
`not-applicable` reason with that written out, and its real proof is a git-backed clone on Linux or
macOS, which is what `pack-os-smoke.yml` and WQ-455 are for.

**Step 57 could not be proven by breaking one of its checks, which is worth knowing before the next
multi-check guard.** It runs `verify-session-handoff.ps1` against a deliberately bad fixture and
requires a non-zero exit. That fixture trips three separate checks at once, so disabling any one of
them leaves the exit code non-zero and the step passes on the strength of the checks that still work.
The mutation that does prove it changes the exit threshold, so the script counts every failure, prints
every one, and still exits 0 — the exact shape WQ-443 was filed over.

**Step 68's first mutation was inert, and the detector was right.** Replacing the bolded negation in a
`START_HERE.md` table row left the cell label `Rules, best-effort copy` on the same line, and the
disclaimer window tolerates `best-effort` by design. The suite stayed green because the line still
read as a correct one. **A load-claim mutation has to remove every disclaimer word within one line
either side of the claim** — checked against the detector's own regexes before spending a proof run,
not by reading. The working target flips `is best-effort reference text` in `PACK_MAINTENANCE.md`.

Also of note: `behavior-controls.json` being `.json` is what keeps step 68's spec legal, since that
step scans `.md`, `.mdc`, `.template` and `.txt`. The constraint recorded in 2.22.86 — a spec cannot
hold text another guard bans — bites per guard, not universally.

## 2.22.87 (2026-09-08)

**Second retrofit batch: steps 45, 46 and 53 (WQ-462). The backlog drops from 67 to 64 — and one of
the three mutations found a guard that could not fail.**

**Step 53 stayed green under a mutation that broke exactly what it claims to check.** The step asserts
that each consumer of a manifest-declared list still *reads* that list, so a private copy cannot drift
away from the one home the list has. The mutation renamed the read
`$pbManifest.projectRequired.flatLayout` to `…projectRequiredPrivateCopy…`. The suite did not notice,
for two independent reasons: the check was a substring grep, and the renamed token still *contains*
`projectRequired`; and even a total rename would have left the explanatory comment above it, which the
grep counted just as happily as code. **A consumer could have stopped reading its list entirely and
kept the guard green so long as it still talked about it in prose.** Step 53 now strips comment lines
and matches whole tokens; every existing consumer passes unchanged, so the tightening cost nothing but
the hole it closed was real. This is the first case of the mutation runner finding a defect in the
guard rather than proving one — which is the outcome WQ-443 was funded for.

**Step 46 cannot be proven without collateral, and that is a property of the step.** It scans
`pack/rules/` only, so unlike step 47 there is no doc to mutate instead; a mutated rule necessarily
differs from its synced copy in `.cursor/rules/`, and the rule-sync step fails alongside it. The
runner reports collateral without failing, and the registry note says to expect it, so the next reader
does not go hunting for a narrower mutation that does not exist.

**`-Only` now takes a list, and rejects a step that declares no mutation.** A batch was paying a full
suite run for every step already proven in an earlier release. The rejection is not decoration: the
first attempt at this batch passed `-Only 45,46,53` through `Start-Process`, which collapsed it into
the single integer `454653`. Under the old signature that would have selected nothing and reported
success for three steps it never touched.

## 2.22.86 (2026-09-08)

**First retrofit batch: steps 47, 48 and 49 now carry executable proofs (WQ-462).** The grandfathered
backlog drops from 70 to **67**, and step 71 prints that number on every run, so it shrinks in public.
Six of six declared mutations proved, runner exit **0**.

**The baseline earned its cost on this batch, before a single mutation ran.** It refused the whole
run: adding step 49's spec had made the *pack itself* fail step 49. Step 49 bans the retired word
`handover` in every shipped file, `.json` included — and a spec that proves step 49 has to contain that
word. So the registry tripped the guard from the inside.

Step 49 already exempts two files on precisely this reasoning ("a linter has to spell the word it
bans, so it cannot lint itself"): its own source, and the changelog where the retired term is
explained. `behavior-controls.json` is the third and for the same reason — it stores the *defect* each
step is proven by. **The general constraint is worth stating, because it will recur:** a mutation spec
cannot hold text that another guard bans, or the registry violates that guard merely by describing
it. Step 68's load-path claims are the next case this will hit.

**Two of the three targets were chosen against the obvious one, and the reasons generalize.** Step
47's mutation dangles a cite in a pack **doc**, not in a `pack/rules/*.mdc`: mutating a rule also puts
it out of sync with the copy in `.cursor/rules/`, so the rule-sync step fails too and the proof gets
harder to read. Step 48's mutation replaces a **comment** with a bare `pause` rather than un-gating an
existing one, because `if not defined BUILD_NOPAUSE pause` appears twice in that launcher and a spec
matching more than once is rejected — the runner could not say which site it broke.

## 2.22.85 (2026-09-08)

**A declared control is now executable: the pack can break what a step guards and require that step
to go red (WQ-443, Phases 3–4 of `docs/GUARD_PROOF_PLAN.md`).** 2.22.84 made a control mandatory to
*declare*. This makes the declaration mean something — `pack/scripts/verify-guard-proofs.ps1` copies
the pack, applies a registry mutation to the copy, runs the suite there, and requires the named step
to report a failure.

**Phase 3's design was replaced before it was built, on a measurement.** The plan called for a `Step`
helper and a mechanical rewrite of all 71 announcements so `Fail` could tag its step. That sweep was
unnecessary: `Fail` can read its own step from `Get-PSCallStack` by taking the **last frame belonging
to the suite file** — the top-level scope — and mapping that line to the nearest announcement at or
before it. Probed on both hosts with identical output, including the case that looks hardest, where a
`Fail` raised inside a helper defined hundreds of lines earlier is credited to the step that *called*
the helper. Two consequences: the 71-line rewrite disappears, and so does the problem Phase 3 was
written to solve. Attribution never reads output, so step 57's child verify printing the identical
`[FAIL]` prefix cannot be mistaken for a failure — **only a real `Fail` call is ever recorded**. The
printed `[FAIL] msg` line is byte-for-byte unchanged; attribution rides in a separate `-ResultsPath`
JSON file, so nothing that greps the suite's output had to move.

**Step 72 failed on its first run, and the defect was in the check rather than the mechanism.** Its
live self-check used `$MyInvocation.ScriptLineNumber`, which is **0** at top-level scope — and 0 is
not an error value here, it resolves to "before every announcement" and attributes nothing. The
results file from that same run credited the failure to step 72 correctly, because `Fail` was already
using the call stack. A probe had printed the 0 an hour earlier and it was not applied. Both paths now
go through one helper, `Get-SuiteTopLevelLine`, so the check and the mechanism cannot use different
means and disagree, and a line of 0 fails explicitly rather than resolving to nothing.

**The runner's two judgements are where a mutation runner would silently prove nothing**, so they are
in `verify-lib.ps1` and planted against in-process. `Get-PackMutationSpecProblem` requires a spec to
match **exactly once** — zero means stale, more than one means the runner cannot say which site it
broke — and treats an unapplicable spec as an error, never a skip, because a no-op mutation leaves the
suite green and green reads as a proof. That is the `.Replace(a,b,1)` defect this pack shipped three
times, one layer up. `Test-PackMutationOutcome` asks whether **these** steps failed, not whether the
suite failed, so a mutation that breaks something unrelated does not count.

**A green baseline runs first, and it is the control on the runner itself.** Without it, a copy that
fails for an environmental reason would make every mutation look proven while proving nothing.

**Never the live tree.** A mutation whose restore path fails leaves a defect indistinguishable from a
real one, and the restore path is the code most likely to be wrong the first time it runs. This pack
also keeps no version control by decision (WQ-459), so there is nothing to restore from. Copies cost
minutes; the alternative costs the checkout.

**Step 73 asserts the runner uses those checks and must never call it.** The runner runs this suite —
invoking it from a step is the recursion that killed step 70 after twelve levels and 25 minutes. The
step's final arm is the standing guard on that, matching only an actual invocation rather than the
name appearing in a comment.

**The runner's first real execution found a defect in itself, and it is the most interesting thing in
this release.** It reported step 72 as **not proven**. Step 72's mutation disables
`Resolve-PackBehaviorStep` — which is the code `Fail` uses to record *which* step failed — so the
suite failed exactly as designed and wrote every failure with no step attached, leaving the runner
unable to name what it had just broken. **A proof defeated by the thing it was proving.** `Fail` now
records the raw line as well as the resolved step, and `Resolve-PackMutationFailureStep` recovers the
step by parsing the mutated copy's suite text with the runner's **own** unmutated functions, so only
the text comes from inside the blast radius. On the re-run, step 72's mutation produced three
unattributed failures, all three recovered, and the step was proven.

**A second finding was operator error worth a guard.** On that first execution, steps 23 and 31 also
failed in two of the three mutated runs, reading exactly like collateral from a mutation that was too
broad. They were neither: the tree was being edited — a version bump in progress — while the runner
took its copies, so the three copies were not the same pack. The runner now fingerprints the tree at
start and end and warns when it moved. On a quiet tree the collateral was gone and all three steps
proved cleanly.

**And the inert-fixture mistake was made a third time, in the arm added to catch the first finding.**
An announcement in source contains the two literal characters `` `n ``, written `'`n'`; writing
`"`n"` produces a real newline, splits the announcement across two lines and matches nothing. The
fixture therefore contained no announcement and its controls proved nothing. Every synthetic fixture
in this area now declares how many announcements it must parse to, which is what caught it.

Phase 5 — retrofitting the 70 grandfathered steps to executable mutations — remains open, and `seal`
stays pinned at 70 until it closes.

## 2.22.84 (2026-09-08)

**A behavior step can no longer be added without declaring how it is proven able to fail (WQ-443,
Phases 1–2 of `docs/GUARD_PROOF_PLAN.md`).** Six guards shipped in a single day reporting success
while observing nothing, and the discipline that catches them — plant the defect, watch the step go
red, restore — was applied by hand for seventy steps with nothing requiring number seventy-one to
have it.

**The obvious implementation was tried first and abandoned on evidence.** A scanner that reads each
step's body looking for a plant was written, run over all 70 steps, and **misjudged step 69** — seven
controls, two of them positive — as having none. The cause is not a weak regex: three legitimate
idioms are in use (plant-and-restore, an expectations table carrying both polarities, and a negative
fixture asserting non-zero exit), and a scan wide enough to accept all three also accepts a comment
that merely claims a control. **Text cannot distinguish a control that runs from a comment saying one
does**, so a scanner here would have been the WQ-443 defect wearing the WQ-443 fix as a costume.

**What shipped instead.** `pack/audit/behavior-controls.json` declares all 71 steps, each either
`mutation` (carrying a `file`/`find`/`replace` spec the Phase 4 runner can apply, plus the steps that
must report `[FAIL]` when it is) or `exempt` with a reason. Step **71** compares the suite's own
announcements against that registry — an exact comparison of two lists, not a heuristic — and
`Get-PackBehaviorControlProblem` in `verify-lib.ps1` holds the logic so the step tests it in-process
rather than shelling out, which is the recursion trap step 70 fell into.

**There is deliberately no `proven` status.** A proof is a run outcome, not a fact a file can hold: a
stored "proven" goes stale the first time nobody runs the runner, which is precisely the
inert-but-authoritative artifact 2.22.83 removed. The registry holds the specification; the run
produces the proof.

**The seal is what stops the declaration being free.** `schemaSealedAtStep: 70` makes
`grandfathered-pre-wq443` valid only at or below step 70, so a new step must carry a mutation spec or
argue `not-applicable` in writing — it cannot inherit the grandfathering covering the steps written
before the registry existed. Step 71 asserts the seal's value, because raising it is the easiest way
to abandon the discipline quietly. The 70 grandfathered steps are reported as `[INFO]` on **every**
run, since an exclusion list that accepts everything is the same thing as no checker.

**Step 71 failed twice on its own controls before it was right, and both failures were the shape it
polices.** First, its synthetic fixtures were written as literal announcements in a here-string — and
the checker reads the suite's own source, so **73 announcements were found for 71 steps**. Second,
after rewriting those fixtures in escaped form to avoid that, two planted defects became **inert**:
`Write-Host `"` does not match the announcement pattern, so the "undeclared step" was never in the
fixture and the control passed having planted nothing. Fixtures are now assembled from fragments, and
cases that add a step declare how many announcements their fixture must contain, so an inert plant
fails with its reason instead of passing as a caught defect. The duplicate-announcement arm is the
standing guard against the first bug returning.

**Registered as a file, not a manifest list.** `behavior-controls.json` is in `packMirror` so sync,
export and the installed copy carry it; it is **not** in `listConsumers`, which declares readers of
manifest *keys*. Adding the plan doc also made step 5 fail until `docs/GUARD_PROOF_PLAN.md` was
mirrored — every `docs/*.md` must be, or it installs once and is stale forever.

Phases 3–5 (step attribution, the mutation runner, and retrofitting the 70 grandfathered steps)
remain open in `docs/GUARD_PROOF_PLAN.md`. Phase 3's design changed on evidence from this release: a
trial parse attributed five `[FAIL]` lines to two steps while the suite's own summary said one,
because step 57's planted controls invoke a child verify whose output carries the identical `[FAIL]`
prefix. A runner trusting output position would credit a step for a failure its own control printed
on purpose.

## 2.22.83 (2026-09-08)

**The rule that started the "global rules do not load" investigation was still inert, and deleting it
would have been a bandaid (WQ-460).** `structured-chat-output.mdc` sat in
`%USERPROFILE%\.cursor\rules\` declaring `alwaysApply: true`, claiming to be "Referenced from
`agent-defaults-always.mdc` (always-on)" and to be "the canonical copy". All three claims were false:
that folder is not a load path, and a grep of the entire pack found the string `structured-chat-output`
in exactly one place — a changelog sentence describing the problem. Four one-step options were on the
table (delete it, promote it, strip the false claims, park it) and each closed one of **three**
defects, which is what made all four a bandaid.

**Defect one — the content was undelivered.** No folder that loads carried output-shape guidance, in
this repo or in any project the pack bootstraps. Promoted to
**`pack/rules/generic-structured-chat-output.mdc`**, registered in both manifest lists (`packMirror`
and `packToUser`), and delivered by `sync-project-rules.ps1` into `.cursor/rules/`, which is the only
mechanism ever shown to bind. It deliberately does **not** restate `full-paths-in-chat.mdc` (that rule
governs how a path inside a reply is written; this one governs the reply's shape) and it defers to
`generic-deep-task-execution.mdc` where a depth contract prescribes evidence before verdict — because
"answer first" and "evidence first" genuinely conflict there, and the depth contract wins.

**Defect two — a file that lied about itself.** Fixed by making the claim true rather than by deleting
the sentence: `agent-defaults-always.mdc` now carries a **Chat output shape** section that really does
reference the rule, so the cross-reference the orphan invented now exists. The orphan itself was then
deleted, which is an endpoint only because the promotion had already replaced its function.

**Defect three — nothing could detect the shape again, and this is the part every option missed.** An
orphan `.mdc` claiming to be always-on was invisible to everything: `doctor.ps1` enumerated
`pack/rules` and asked "did it arrive?", which by construction cannot see a file the pack never
shipped; step 68 scans only **shipped** docs; and `install.ps1 -Prune` structurally cannot help, since
pruning removes what a previous install recorded shipping and an orphan is absent from that record.
**`Get-PackOrphanAlwaysOnRule`** now reports them, wired into `doctor.ps1`. It matches
`alwaysApply: true` in **front matter only** — a body that merely discusses the flag, as these very
docs do, is not a file making the claim — and it ignores orphans that declare `alwaysApply: false`,
because somebody's private note is not a false claim and warning about it would train the reader to
tune out the warning that matters. Proven against the live file **before** it was deleted:
`[WARN] inert rule: ...structured-chat-output.mdc`, doctor exit **1**; after deletion,
`[OK] no orphan always-on rule`, exit **0**.

**A behavior step that recursed twelve levels deep, and the rule that came out of it.** Step 70's
first implementation shelled out to `doctor.ps1` against a redirected profile. `doctor.ps1` calls
`verify-audit-system.ps1`, which runs this suite, which called `doctor.ps1` — an unbounded loop that
ran for 25 minutes before being killed, leaving six `orphan-rule-probe-*` directories as the evidence
that it had re-entered itself six times. The detection logic was therefore **extracted** to
`pack-paths.ps1` so the step can test it in-process, and the step now carries a third arm asserting
that **no step in this suite invokes `doctor.ps1`** at all. Runtime returned to 227s from an unbounded
hang. The lesson generalises past this step: a maintainer script that runs the verifier cannot be
called *from* the verifier, and only a test can notice that, since reading either file alone shows
nothing wrong.

**All three arms watched to fail (WQ-443).** Detector forced to return nothing → `misses a planted
alwaysApply:true orphan`; `doctor.ps1` call removed → `no longer calls Get-PackOrphanAlwaysOnRule`;
a `-File $doctorPath` line re-added under `if ($false)` → `this suite invokes doctor.ps1 (1 site(s))`.
Suite exit **1** with all three planted, and the guarded-so-it-never-runs invocation proves the third
arm reads the text rather than waiting for a hang. Fixtures cover the shipped rule, the always-on
orphan, the `alwaysApply: false` orphan, the discussion-only file, an empty directory argument and a
missing directory.

**Also: a hardcoded rule count removed rather than incremented.** `starter-pack-repo.mdc` said "the 13
generic rules" and "never edit the 13 synced copies"; the fourteenth rule made both wrong. Since
`sync-project-rules.ps1 -VerifyOnly` compares the files themselves, the number was decoration that
could only ever go stale, so it is now phrased without one. The historical counts in this changelog
and in the work queue were **left alone** — they describe what was true at 2.22.79, and editing them
would be the defect those entries warn about.

## 2.22.82 (2026-09-04)

**"Does a `.git` entry exist" is not "is this a git work tree", and eleven guards asked the first one
meaning the second (WQ-461).** Found the way these things should be found — by doing the thing. The
`.git` directory was deleted from the pack folder an hour after 2.22.81 certified the pack as
git-optional, and the next audit **failed**, on a pack that had just been proven to certify with no
git at all. The 2.22.81 claim that "every functional git call guards for absence" was **true for
absence and false for unreadability**, which is not the same property.

**Why the probe missed it.** The 2.22.81 evidence was a copy of the tree with `.git` excluded, so
`.git` was *absent* and every `Test-Path` guard correctly reported "not a git checkout". Deleting the
real one left a `.git` **directory** behind, because the editor keeps its code-index cache at
`.git\cursor\crepe\` and holds those files open. So the path existed, the guard fell through, and
`git ls-files` answered `fatal: not a git repository`. A test that removes a thing cannot see the
states in which the thing is present but broken.

**Three sites, three different symptoms — which is why one of them looked fine.**
`verify-audit-behavior.ps1` step 62 turned it into `[FAIL] executable-bit check error`, failing the
suite and therefore `verify-audit-system.ps1`. `verify-work-queue.ps1` exited **1** from a raw
`git show HEAD:...` error. `run_audit_core.ps1` degraded correctly to a `tree:`-only proof but printed
a fatal git error into the audit's own output. Only the loudest of the three was diagnosable from the
report.

**`Test-PackGitRepo` in `pack-paths.ps1`** now answers the question by asking git —
`rev-parse --is-inside-work-tree`, any non-zero exit meaning "not usable here", since unreadable and
absent are the same outcome for every caller. It sets `safe.directory=*` deliberately: ownership is a
property of the disk rather than of the repository, and refusing a checkout on removable or
foreign-owned media would reintroduce a false negative on exactly the media this pack is carried on.
Used at step 62, in `verify-work-queue.ps1`, and at both `run_audit_core.ps1` sites. The remaining
`.git`-existence tests are left alone on purpose: `audit_common.py` and `doc_version_sync.py` use it
to *locate* a repo root, and a leftover `.git` still marks that root correctly.

**Controls in both directions (WQ-443), because the failure mode of this fix is silence.** A probe
that answered "not a repo" everywhere would skip forever and never catch a real mode regression —
strictly worse than the bug it replaced. Eight ad-hoc controls first: **False** for the pack folder, for
no `.git` at all, for a `.git` **file** pointing nowhere (the worktree and submodule shape, which
defeats a path test just as thoroughly), for a `.git` holding only an editor cache, for a missing path
and for an empty string; **True** for a fresh `git init` and for a subdirectory inside a real
repository. 8 of 8, 0 wrong. `AllowEmptyString` was added after the empty-root control threw a
parameter-binding exception instead of returning `$false`.

**Then the controls were made permanent, because a proof that lives in a scratch file is not a
guard.** Leaving them in `.tmp` would have reproduced the WQ-443 failure while claiming to have fixed
it. **Step 69** now builds the fixtures itself and carries two arms: the seven portable controls (the
eighth was specific to the pack folder), and an assertion that the four call sites still *call* the
helper — because an edit that reverts one to a path test would otherwise leave the step green while
the defect returned. Both arms were watched to fail: with the helper reduced to a path test and one
call site reverted, arm A reported three wrong answers and arm B reported
`verify-work-queue.ps1 (0 of 1)`, suite exit **1**. The most instructive of the three was
`subdirectory of a real repository: got False, want True` — a path test answers "not a repo" for every
subdirectory of a genuine checkout, because `.git` is not *in* it, which is the same class of wrong
answer in the opposite direction.

**A second, unrelated defect surfaced underneath it: `Copy-Tree` in `install.ps1` could not skip what
it could not read.** Its filters — `SkipDirNames`, `SkipRelPaths`, extensions, patterns — all run
*per file, after* the walk, so none of them can stop `Get-ChildItem -Recurse` entering a directory.
`.git\` has been on that skip list for releases, and an unreadable `.git\logs` still failed the whole
install. `Get-RelativeFileSet`, forty lines below in the same file, had been enumerating with
`-ErrorAction SilentlyContinue` all along: the correct pattern was already in the file, next to the
wrong one, which is the WQ-441 shape again. Now enumerates tolerantly and **captures** the errors
rather than discarding them, because the two cases are not equivalent — an unreadable folder on the
skip list is expected and silent, while any other one means files are missing from the install and a
silent success would be a lie. Proven live against the still-locked directory: the step passes, and
prints no warning, because `.git` is skipped by name.

## 2.22.81 (2026-09-04)

**Version control is optional to this pack by decision now, not only by construction (WQ-459).** The
code was already there: `verify-work-queue.ps1` carries three `[SKIP]` branches for git-absent,
git-not-on-PATH and git-refused-the-repo; `run_audit_core.ps1` returns `$null` when there is no
`.git`; `check-requirements.ps1` records git as `Required $false`; and the audit's test-pass proof is
a content fingerprint that merely *prefixes* HEAD when git answers. What had accumulated on top of
that was a layer of ceremony demanding git work from the maintainer, and it was expensive out of all
proportion to what it protected.

**Measured before touching anything.** 279 mentions of git across 38 files sounds like a rewrite, and
it is not. 69 are historical narrative in this changelog, `SESSION.md` and the WORK_QUEUE Done log,
where rewriting the record would be the actual defect. Most of the remainder are comments explaining
why a guard exists. The functional calls number about a dozen and every one already guards for
absence. So the change is confined to the files that told a human to run a git command.

**Removed.** `.cursor/rules/no-publish-from-this-machine.mdc` - the rule that split `commit` from
`push` and generated the whole commit-but-do-not-publish protocol. Its premise was that the execute
bit lives only in git and therefore had to be committed; that premise is what this release retires.
The `.gitignore` and `maintainerOnlyPaths` entries for it stay, because both mean "strip this if
present" and cost nothing when it is not - and the behavior step that names it builds the path as a
synthetic fixture in a temp directory rather than reading the real file, so deleting it changed
nothing there.

**Reframed, in `INSTALL.txt`, `INSTALL.md` and `README.md`.** These said the Unix execute bit "is
carried by git and by nothing else this folder travels through", which is true and was the wrong
thing to emphasise: it reads as *git is required*. They now say to assume the bit is absent, because
that is the ordinary case for a download, a copy, an archive and exFAT media alike. The operative
instruction is unchanged - `bash install.sh`, never `./install.sh`. The one-time
`git config --global --add safe.directory` line is gone from the flash-drive procedure, along with
the broken step numbering it left behind.

**The consumer/maintainer mix-up, which was a separate defect.** `AGENTS.md` is the file agents read
first, and it opened by framing the reader as a pack maintainer under an edit boundary with a work
queue to respect. A colleague handed a copy would have their agent follow maintainer instructions
instead of installing the thing. It now opens with a four-line install block for both hosts and sends
maintainers past a horizontal rule. `INSTALL.txt` had the same fault in one line - "Agents:
`docs\WORK_QUEUE.md`" pointed a consumer's agent at the maintainer radar.

**CI stopped requiring what the pack stopped promising.** The step asserting every tracked `.sh` is
`100755` is now `continue-on-error` and renamed to say it is informational: with a web upload or a
zip as a legitimate publish route, a red X there would report a cosmetic difference as a broken
product. The blocking guarantee moves to where it belongs - the step that strips `.git` and every
permission bit and requires the install to succeed anyway. Fixing that exposed a second-order
problem in the same file: nine CI invocations ran wrappers as `./Bootstrap-Project.sh`,
`./install.sh`, `./run_audit.sh` and so on, which depend on precisely the mode the step above had
just stopped requiring. All nine now use `bash <file>`, the documented form. The two deliberate
`./install.sh` invocations remain, because they assert it *fails* at mode 644 - remove those and the
mode-stripped test stops measuring anything.

**Proven by running it, not by reading the guards.** The tree was copied without `.git` (245 files,
`git rev-parse` answering `fatal: not a git repository`) and taken through the full cycle. The proof
it computed was `tree:eb3b2f29...` - byte-identical to the fingerprint half of the git-backed repo's
`a7feca5...+tree:eb3b2f29...`, so the two paths agree on the same tree. `Tests: OK`, semantic report
valid, **`finalize_audit.cmd` exit 0, `verify-audit-system: OK`, 0 fails and 0 warnings, Fix and
Improve both empty.** The skips were graceful and legible: `[INFO] not a git checkout (or git absent)
- index check skipped` and `[SKIP] not a git checkout - nothing records the mode here`.

## 2.22.80 (2026-09-04)

**The claim 2.22.79 corrected came back the same day, in the one file written for users of other
tools (WQ-457).** `pack/docs/portable/GENERIC_RULES.md` is the paste-at-session-start export for
Claude, Copilot, Windsurf and the CLI. It opened with a table headed **"Load path"** whose first row
was `%USERPROFILE%\.cursor\rules\*.mdc` -> "Cursor (after `install.ps1`)". That is precisely the
falsehood 2.22.79 removed from roughly fifteen documents, surviving in the export aimed at the
audience with the least ability to check it - a reader on another tool has no `.cursor/rules/` to
compare against.

**Two independent reasons the 2.22.79 sweep could not have found it, and step 68 exists for both.**

The first is that the text was not in a document. It was a string literal inside
`pack/scripts/sync-portable-docs.ps1`, assembled into a document at build time. A sweep of `*.md`
reads the output of the last build, not the instruction that produces the next one; a sweep of prose
never opens the generator. **A doc audit that greps prose does not reach text assembled by code.**

The second is subtler and is the reason a grep would have missed it even pointed at the right file.
No single line carried the claim. The row said only "Cursor (after `install.ps1`)" - the assertion
that this is a *load path* was made by the table header two rows above. The claim was distributed
across markdown structure, so a line-at-a-time scan is not merely unlucky here, it is structurally
incapable. **Step 68's scanner therefore carries table context:** a header row matching `load path`
governs the rows beneath it until a blank line closes the table, and a row naming the profile folder
under such a header is a claim whether or not it repeats the word.

**Both directions, over ~90 files that mention the path legitimately.** The profile folder appears
throughout the pack for correct reasons - `install.ps1` writes there, `doctor.ps1` checks it is
present, and several documents now explain at length that it does not load. A scanner that flagged
those would be turned off within a day, so step 68 asserts five planted claims are caught (bare
"load from", a load-path table, a "where rules are loaded" header, an `always-on ... apply to every
project` sentence, and the original row) and six correct mentions are not. It also needed a
two-line disclaimer window: prose wraps, and `docs/handoffs/SESSION.md` puts "is not" at the end of
one line and "a place any editor reads" at the start of the next. Widening the window was the right
fix; exempting the file would have created the blind spot the guard exists to close. Only two files
are exempt - this changelog and `docs/WORK_QUEUE.md` - because both must quote the false claim in
order to record it, and a guard that forbids naming the bug it prevents cannot be documented.

**The proof attempt failed first, and that failure is the useful part (WQ-443).** Planting the old
row directly into the generated `GENERIC_RULES.md` and running the suite produced
`[OK] 87 docs make no profile-rules load claim` - a clean pass over a file that contained the defect.
Step 39 (`repair-agent-docs restores hub patterns and portable GENERIC_RULES`) regenerates that
export mid-suite, so by the time step 68 read the file the plant had already been repaired away.
**A generated artifact cannot be tested by editing the generated artifact**; the plant has to go
into the generator, which is also the real regression path. Planted there, regeneration propagated
it and both arms fired, naming `pack\docs\portable\GENERIC_RULES.md -> line 10`. Restored, the suite
returns to zero. The first attempt would have shipped a guard that had never observed anything,
which is the seventh instance of the WQ-443 shape and the first where the masking step was a
*repair* rather than a filter.

A side effect worth recording: the planting command used `Set-Content -Encoding utf8`, which on
PowerShell 5.1 writes a BOM, and the existing generated-files check caught it immediately
(`generated files carry a UTF-8 BOM: GENERIC_RULES.md`). An unrelated guard proving itself on an
accident is the cheapest evidence available.

**WQ-458: the premise under 2.22.79's remedy, measured rather than assumed.** 2.22.79 routes changed
always-on rules into `requiredReads` on the stated grounds that "no editor reloads rules
mid-session." That sentence had never been tested, and evidence from the same session appeared to
contradict it: fourteen rules synced into this repo's `.cursor/rules/` mid-chat *did* reach agent
context without a restart. A throwaway probe rule with `alwaysApply: true` settled it. The probe was
absent from context across tool-call round trips **and** across a fresh user message, so the
fourteen had arrived only because a context summarization had rebuilt the prompt in between - a
boundary no user can invoke on demand. The premise holds, `requiredReads` remains the only channel
that reaches an open chat, and `docs/MULTI_INSTANCE_GUIDE.md` is now stating a measured fact rather
than a plausible one.

## 2.22.79 (2026-09-04)

**The folder this pack installs its "global rules" into is not a place any editor reads (WQ-456).**
`install.ps1` copies 13 `.mdc` files to `%USERPROFILE%\.cursor\rules\`, nine of them declaring
`alwaysApply: true`, and roughly fifteen documents describe them as always-on — `docs/PORTABLE_SETUP.md`
called it "the only place Cursor reads global rules and skills from." Cursor's rules reference documents
four locations: project `.cursor/rules/`, User Rules, Team Rules, and `AGENTS.md`. A home-folder rules
directory is not among them. It survives on a single Cursor 2.1 changelog bullet promising inclusion
"in context", with no `alwaysApply` semantics and no slot in the documented Team → Project → User
precedence. `~/.cursor/skills/` **is** documented as a global load path, in an explicit table — which is
exactly why the three pack skills worked and all 13 rules did not.

**Found by the symptom, not by the audit.** The user had asked repeatedly, across sessions, for replies
that were not walls of text and for action items to be called out explicitly. A machine-local
`structured-chat-output.mdc` had been saying precisely that since 2026-08-28, `alwaysApply: true`, sitting
in the profile folder. So had the pack's own `full-paths-in-chat.mdc`. Neither ever entered a session's
context, and the agent went on citing bare filenames and emitting prose blocks while both rules sat on
disk, present and verified. The complaint was the only working detector.

**Every guard was measuring the hand-off point.** `doctor.ps1` enumerates `pack/rules/*.mdc` and checks
the profile copy exists. `verify-agent-setup.ps1` walks `packToUser` and checks the same. Eight behavior
steps cover manifest completeness, `rulesRevision` hashing, `Copy-Tree` filters and prune safety. Not one
asked whether anything reads the destination — the single fact the whole feature depends on. All stayed
green for the life of the feature. New lesson in `docs/WORK_QUEUE.md`: **verifying delivery is not
verifying arrival**; when a feature's value depends on another program consuming an artifact, the test
has to observe that program, because presence at the hand-off point was never in doubt.

**The second half was worse, because it was the one channel that could still work.** Editors build rule
context at session start and never reload it, so a rule change cannot reach a chat that is already open —
except through the refresh brief, which is why `Refresh-AgentContext.cmd` exists. That brief listed
`AGENTS.md`, `SESSION.md`, `WORK_QUEUE.md` and `START_HERE.md`. No rule file, ever.
`changedLayers` already emitted `rules` when `rulesRevision` moved, and the prose already said "re-read
the rules before acting on remembered ones" — with no paths, pointing at a folder nobody reads. A rule
edit therefore had two routes to an agent and both were closed.

Delivery had to cover **any** AI editor or AI-powered IDE, not just Cursor. That rules out Cursor User
Rules (account-stored, no file to install) and a user-scope Cursor plugin (the one documented way to ship
machine-wide `.mdc` files, but Cursor-only and gated by Enterprise admins). Project `.cursor/rules/` plus
`AGENTS.md` is the only pair every AI editor loads, and the pack already had the mechanism —
`sync-project-rules.ps1`, previously treated as the fallback.

- **`sync-project-rules.ps1` run on the pack repo itself** — the 13 generic rules now live in
  `.cursor/rules/` alongside the five workspace-only ones, 18 total, `-VerifyOnly` clean. The pack becomes
  its own first customer of the path that actually binds.
- **`starter-pack-repo.mdc` and `AGENTS.md`** — the rule-layer table said `.cursor/rules/` was "this
  workspace only" and `pack/rules/` applied "all projects after `install.ps1`". Both were false in
  opposite directions. `pack/rules/` is now named a canonical source, not a load path, with an explicit
  instruction never to edit the synced copies.
- **`refresh-agent-context.ps1`** — new `ruleLoadPath`, `loadedRulesRevision` and `alwaysOnRules` fields;
  a `loadedRules` layer that reports `stale` when no `alwaysApply` rule reached the load path; and the
  always-on rule files added to `requiredReads`, each flagged in the brief as something the editor will
  not reload mid-session. Frontmatter-only detection, since a rule body may quote `alwaysApply: true`
  while describing another rule. Schema stays at 2 — added fields only.
- **Listed on change, not on every run.** Required reading that grows by eighteen entries per refresh is
  a list nobody follows, so the rule paths appear only when `loadedRulesRevision` moves, when the pack's
  rule text moves, on a first refresh, or when a stamp predates the fields — a one-time migration without
  which this ships and lies dormant on every install that already exists.
- **A standing defect is not a change.** A stale load path was invisible on a project's *first* refresh,
  where `changedLayers` is only `firstRefresh` — the one refresh that matters most. Stale layers now get
  a **Needs attention (standing, not new)** section driven by current status rather than by a diff.
- **`layers.globalRules` no longer reports a bare `ok`.** It was set to `ok` whenever the installed pack
  matched, asserting nothing about rules while reassuring the reader that a dead path was healthy. It now
  reads `best-effort (profile copy; no editor documents loading it)`.
- **Layer change detection compares by prefix**, so a status carrying its reason (`stale (no rules
  folder)`) still registers; equality would have silently stopped reporting.
- **The drift verify now covers the copy that binds.** `sync-portable-docs.ps1 -VerifyOnly` checked the
  portable export nobody auto-loads and skipped this repo's own `.cursor/rules/`, which is what actually
  governs an agent working here — so the first cut of this very change **audited clean while two rules
  had already diverged**, the same shape as the defect being fixed, one layer out. It now compares the
  loaded copies against `pack/rules/` and names `sync-project-rules.ps1` as the remedy. Proven by
  planting drift in a loaded rule: clean passes, planted drift fails, exit 1.
- **Step 27 grew six arms, in both directions** (WQ-443 discipline). The negative control plants an
  `alwaysApply: false` rule and requires `stale` plus the remedy command; the positive control adds one
  real always-on rule and requires the layer to flip, the path to land in `requiredReads`, and the
  mid-session warning to appear. A third arm requires an unchanged rule set *not* to be re-listed, and a
  fourth strips the new fields from a stamp to prove the migration fires. **Two of the six failed on
  first run** and both were the implementation, not the test: a project going from `stale` to `ok` — the
  exact moment rules first arrive — was not listed at all, because the change loop only reacted to
  `stale`/`updated` transitions; and the first-refresh case above.

## 2.22.78 (2026-09-03)

**Asked what would happen if git were not here at all, and the answer was one undocumented command
(WQ-454).** Git had been doing a job the real delivery channel cannot: the Unix execute bit and LF line
endings survive a clone and survive nothing else this pack travels through — a folder copy, an unzipped
archive, exFAT or FAT media, and a Windows checkout that has no bit to carry in the first place. The
pack is installed by an agent reading these docs, not by `git clone`, so that mattered more than it
looked.

**Measured on ext4 rather than reasoned about**, because `/mnt/d` is DrvFs and reports 777 for every
file, so a mode test run from there passes against a completely broken installer. A copy with every
bit stripped answered:

- `./install.sh` — **`Permission denied`, exit 126**
- `bash install.sh` — **succeeded**, and the destination came out **20 of 20 executable**

So the pack already survived a git-less delivery, through exactly one command, and **that command
appeared in zero documents**. `bash install.sh` was in none; `./install.sh` was in changelog narrative
about past bugs. All five primary install docs — `README.md`, `INSTALL.md`, `INSTALL.txt`, `AGENTS.md`,
`pack/docs/START_HERE.md` — told every reader on every OS to run `Install-AgentStarterPack.cmd`, and
`docs/PORTABLE_SETUP.md` listed `install.sh` in a table with no invocation syntax at all. The
capability was real and cross-platform; the instructions were Windows-only. An agent on a Mac was being
told to double-click a `.cmd`.

**The bootstrap paradox is the whole reason one command has to be exempt.** `install.ps1` already
chmods what it delivers, so everything after the first command self-heals — but off Windows it is
reached *through* `install.sh`, which means the file that fixes the execute bit is the file the missing
execute bit stops. `bash install.sh` breaks the loop because bash runs a file it is handed at any mode.
Every install doc now says so, and says why, because the `./` form is what a future editor will
"tidy" it back to.

**CI could not have caught any of this, because it manufactured the condition.** `pack-os-smoke.yml`
opened its wrapper step with `chmod +x ./*.sh`, setting the bit before asking whether the delivery
carried one — so the Linux job passed for the entire period in which every shipped `.sh` was committed
`100644` and no clone could run one (WQ-446). It was masking the defect it existed to catch, and
probably added because of it. Replaced by both real delivery shapes: a clone must arrive executable and
is *used* rather than chmodded, and a `chmod 644` copy must fail on `./install.sh` **and** succeed on
`bash install.sh`. The failing half is asserted too — if `./install.sh` ever starts working at mode
644, the test is measuring nothing.

**The installer now repairs both properties rather than trusting the transport.** Line endings before
the bit, because a CRLF file that is executable still fails and fails less legibly: `#!/usr/bin/env
bash\r` makes the interpreter path itself wrong, so bash answers `$'\r': command not found` and names
no file. Read as bytes, since the text reader strips line endings and cannot see the thing being
tested. It also chmods **the folder it ran from**, which install had never done — a recipient who
unzipped, installed cleanly, and then ran `./run_audit.sh` from that folder got `Permission denied`
from a pack that had just reported success. Proven against a delivery with all bits stripped and CRLF
planted in three payload scripts: 3 files repaired, 20 of 20 executable at the destination and at the
source, and the planted file starts.

**WQ-451's three twins shipped, and writing them found the payloads were not portable either.**
`Verify-AgentSetup.sh`, `Update-AgentRules.sh` and `Bootstrap-Portable-Project.sh` are the POSIX halves
of entry points `README.md` and `AGENTS.md` already documented as the way to verify a setup, refresh
rules, and bootstrap a portable project. The first run of `Update-AgentRules.sh` died inside
`update-agents.ps1` on `Join-Path $env:USERPROFILE` — that variable is Windows-only and `$null`
elsewhere, which surfaces as a null-binding error naming a parameter rather than the cause. **Shipping
the twin without that fix would have moved the dead end rather than closed it**, which is precisely the
WQ-450 shape one layer over. A sweep found seven scripts with unguarded uses: `update-agents.ps1`,
`verify-agent-setup.ps1` (unconditional, no fallback), `bootstrap-project.ps1`, `sync-audit-system.ps1`,
`doctor.ps1`, `run_audit_core.ps1` (twice, config-gated, which is why no Linux run had reached it), and
— worst behaved — `cleanup-orphan-processes.ps1` and `fix-stale-terminal.ps1`, where
`$ErrorActionPreference = 'SilentlyContinue'` turned the null into an *empty search root*, so both
scanned nothing and reported no orphans, which is indistinguishable from a clean machine. All now go
through `Get-PackHomeDir`, which returns `USERPROFILE` first so Windows behaviour is unchanged; the two
MCP hot-path scripts resolve inline to stay dependency-free. Both twins verified on Ubuntu:
`Verify-AgentSetup.sh` reports **Fail 0, Warn 0**. `pack_pwsh_run` joins `pwsh-wrap.sh` because
`pack_pwsh_file` uses `exec` and therefore can only ever be a wrapper's last line, which made a
multi-step twin impossible to express through the helper at all.

**A macOS job exists for the first time (WQ-436).** macOS had been treated as "Linux, near enough" on
the strength of both being non-Windows — the same assumption Linux itself disproved, where an estimate
of 24 Windows-only steps met a reality of 16 different real failures. It differs where this pack
actually reaches: a case-**insensitive** default filesystem (like Windows, unlike Linux), BSD userland
where `stat`, `sed` and `find` take different flags, and `pwsh` from a cask rather than a distro
package. Report-only, because the point of a first run is to produce a baseline and a red X against an
unknown baseline says nothing actionable; promote it the way Linux was promoted.

**Step 67 holds the instruction form, and its own negative controls corrected it before it shipped.**
The scanner asks two things of the six start docs: that no line *begins* with `./<entry point>`, and —
the direction that actually shipped — that each names a POSIX install path at all, since a doc can
satisfy the first by documenting nothing. The first draft keyed on the prefix and flagged its own
explanatory note: a bullet reading ``- `./install.sh` `` is an instruction, and a wrapped prose line
beginning ``` `./install.sh` on such a copy ... ``` is not, and both start identically. What separates
them is what *follows* — arguments, or English — so a line is prose if any remaining token is an
ordinary lowercase word, real arguments here being flags, paths, or capitalised (`User`, `Both`,
`MyApp`). Planted both ways per WQ-443: four instruction forms must be caught and five legal mentions
must not, because a scanner that flags nothing and one that flags its own documentation both read as a
clean sweep. Further arms pin the installer's three repairs, the absence of CI's blanket chmod, the
presence of the mode-stripped arm and the macOS job, and all three `pwsh-wrap.sh` helpers.

**Also fixed:** `INSTALL.txt` claimed audit engine **2.22.43** against a manifest reading 2.22.77 — 34
releases stale, in the file a human on a new machine reads first, because only its `QUICK INSTALL (v…)`
header was version-synced and `auditVersionScanFiles` scans `.md` only. It also restated `Next: WQ-011`,
duplicating a status claim `docs/WORK_QUEUE.md` owns and getting it wrong. Engine cite now synced;
duplicate claim replaced by a pointer.

## 2.22.77 (2026-09-03)

**2.22.76 fixed the pack and moved the defect in every project that already existed (WQ-450).**
The previous release taught every message to name the entry point the running host can execute, and
taught `bootstrap-project.ps1` to emit both twins. That was correct for the pack and for every project
generated afterwards. For a project generated *before* it, the upgrade changed which non-existent file
the audit named: it had `scripts/finalize_audit.cmd` and nothing else, so on Linux the instruction went
from a `.cmd` that host cannot run to a `.sh` that project does not have. Measured rather than assumed
— a fixture holding only the Windows twins was asked what the upgraded pack would tell it, and all
three answers named files absent from the fixture. The headline fix reached nobody who had used the
pack before.

**The order matters and was deliberate.** The twins were held out of the manifest's `projectRequired`
in 2.22.76 and are added here. That list only *reports* a missing project file — no sync command writes
into a project — so requiring them first would have produced drift with nothing able to clear it, which
is a worse failure than the one being fixed: every existing project failing its portability check with
no remedy. `pack/scripts/repair-project-scripts.ps1` is the remedy, and it exists before the
requirement.

**A twin can be present and still unrunnable, so the repair treats three defects, not one.** Missing
is the pre-2.22.77 bootstrap. **CRLF** is a file that exists and still fails, because `bash` answers
`$'\r': command not found` and names no file — an error that points at nothing. **No execute bit** is
the same story as step 62 one layer down: PowerShell creates files without it and no Windows filesystem
carries one, so any project copied from Windows answers `Permission denied` to the command its own
README prints. Missing twins are written from the shipped template; a CRLF one is repaired **in place**,
because rewriting from the template would silently discard a project's own edits and the carriage
returns are the whole defect. A project that never took an entry point is silent, not reported —
otherwise the check fails on every project without a test runner and people learn to ignore it.

**The CRLF case was found while fixing the first one, and it was latent in what 2.22.76 shipped.**
`.gitattributes` pinned `*.sh` to LF, and `*.sh` does not match `run_audit.sh.template`. So the six
shell-script templates fell through to `* text=auto`, and with `core.autocrlf=true` — the Git for
Windows default, and set on this machine — the next Windows checkout would have converted them. Every
project bootstrapped from that checkout would then have received CRLF shell entry points. Nothing in
the tree could see it: all six templates are still untracked, and the working copy of an uncommitted
file is whatever wrote it, so the conversion had not happened yet and would have arrived with the
commit. `*.sh.template` is now pinned to LF and `*.cmd.template`/`*.bat.template` to CRLF, which is the
same defect mirrored — bootstrap runs on Linux now, and a Batch file with LF endings is as broken there
as the reverse.

**Reachable from the two places a project already goes.** `run_audit_core.ps1` runs the check in
`-AuditMode` so the project's own audit reports the gap as **Fix**, and `update-agent-stack.ps1` runs
the repair after an upgrade, beside the hook repair and for the same reason: a repair nobody knows about
repairs nothing. Both couplings were removable without a test noticing until now.

**Step 66**, twelve arms, and **all fourteen negative controls caught their planted defect against a
green baseline**. The controls run step 66's *own source* against a planted copy rather than
restating its assertions, since a probe that re-implements a check tests the probe; the harness asserts
on itself first (non-empty slice, every arm present in the slice, baseline at 0 fail) because an empty
slice would have reported a clean sweep — the WQ-443 failure exactly. The load-bearing arm is a
cross-check rather than a shared read: the repair
script keeps its own table because a pair needs a template name, which `projectRequired` cannot express
— so the step fails if the manifest requires a twin the repair cannot write, **and** if the repair can
write one nothing requires. The rest repair a project shaped like the ones already out there and assert
what the modes promise: `-AuditMode` reports and writes nothing, `-VerifyOnly` rejects and writes
nothing, the repair delivers five LF twins, the CRLF arm keeps the project's own content, the repair
satisfies its own verify, an absent entry point stays absent, and `.gitattributes` pins both suffixes
with no carriage return anywhere in the tree.

**The behaviour fixture was one of the stranded projects.** Step 18 failed the moment the check went
in — `pack/audit/behavior-fixture` is `.cmd`-only, which is exactly the defect. It was fixed by running
the repair on it, so the delivery path is exercised on a real project rather than only on a probe.
Steps: **66**.

## 2.22.76 (2026-09-03)

**The audit told a Linux reader to run four commands, three of which did not exist (WQ-449).**
Finishing `./run_audit.sh` on Ubuntu printed a next-steps list naming
`scripts\write_semantic_audit_template.cmd`, `scripts\verify_semantic_audit.cmd` and
`scripts\finalize_audit.cmd` — Batch names, backslash separators, and on that host no such files at
all. Nothing failed, because the only consumer of those strings is a human. That is why it survived
the Linux port of the *engine* and several releases after it: the suite proves what the pack **does**,
and this was what the pack **says**.

**Two defects, not one.** The queue row had this filed as 34 wrong strings needing a speller. Half
right: the strings were wrong, but for four of the entry points they named there was no POSIX twin to
name, so a speller alone would have had nothing to spell. `scripts/` now ships
`write_semantic_audit_template.sh`, `verify_semantic_audit.sh`, `finalize_audit.sh` and
`sync_audit_system.sh`, and the root gains `Sync-DocVersions.sh`, `Update-AgentStack.sh` and
`Register-Tool-Adapters.sh` — each a thin twin of its `.cmd`, because the payload underneath
(`audit_code_checks.py`, `run_audit.ps1`, `sync-audit-system.ps1`) was already portable. `py-wrap.sh`
is the shell twin of `Invoke-PackPython`: the `.cmd` files call `py -3`, which is the Windows launcher
and exists nowhere else, so a literal port would have failed with `py: command not found` — a message
that reads like a missing Python rather than a Windows-only launcher.

**The speller, and why it is a registry rather than a string rule.** `Get-PackEntryPoint` in
`pack-paths.ps1` and `pack_entry_points.py` map a logical name to what each host can run, separators
included: `run_audit.cmd` on Windows, `./run_audit.sh` elsewhere. Names are asymmetric where the pack
ships them that way — `install` is `Install-AgentStarterPack.cmd` and `install.sh` — so a shared base
name with an appended extension would not have worked. An unregistered name **throws**, which is what
stops the next message inventing an entry point that has no twin. The Python copy is deliberate and its
docstring says why: these names appear in text that prints when something is already broken, so
resolving one must not depend on parsing a file that could be the broken thing.

**`Format-PackDisplayPath`** covers the adjacent half. `docs\.audit_semantic_report.json` is not merely
ugly off Windows — pasted into bash, `\.` collapses to `.` and names a different file. `$appPrefix` was
built with a hardcoded `\` and feeds eight Fix lines.

**Generated projects had the same hole, one layer down.** `pack/templates/scripts/` shipped `.cmd`-only
templates, so a bootstrapped project on Linux could run `run_audit.sh` and then had nothing to run for
the semantic and finalize steps its own audit named next. Four `.sh.template` files now ship, bootstrap
emits both twins on every OS, and they go through `Set-PackExecutableBit` — a `.sh` written by
PowerShell arrives without the execute bit, which is step 62's defect one layer up. These templates
inline their interpreter check instead of sourcing `py-wrap.sh`, following the rule
`run_audit.sh.template` already states: a generated project must audit itself without the pack present,
and sourcing a *new* pack helper would break against an older installed pack.

**Step 65, and the arm that matters.** Seven arms assert the speller answers, both registries agree,
every registered name ships both twins, an unregistered name is refused, and the templates and
bootstrap carry the twins through. The eighth is the one that keeps this closed: a scanner over 43
script files that fails when instruction text names a Windows entry point directly. It allows exactly
two lines and names both inline — a Windows-only branch describing the `.cmd` scripts, and an evidence
reference — because a file-level exemption would let the next bad string in beside a good one. Per
WQ-443 the scanner is planted against rather than trusted: three synthetic instructions must be caught
and two legitimate lines must not be flagged, since a scanner that flags nothing and a scanner that
exempts everything both report a clean sweep. All five file-level arms were then proven on a planted
copy of the pack — twin deleted, registries desynced, a bare `.cmd` added to `doctor.ps1`, a template
removed, bootstrap stopped emitting — and each failed with its own message while the other arms stayed
green.

**Deliberately not done.** The four `.sh` twins are *not* added to `projectRequired`. That list only
reports missing project files; `sync-audit-system.ps1 -AutoFix` mirrors pack-to-installed and never
writes into a project, so requiring them would produce drift on every pre-existing project that no
command could clear. Retrofitting them needs a delivery mechanism first, and that is filed rather than
half-built.

## 2.22.75 (2026-09-03)

**A bump can no longer reach into the past (WQ-437).** `docs/WORK_QUEUE.md` is the one document that
mixes both kinds of version cite: the header table says which engine is *current*, and every Done-log
row says which engine *shipped* that item. Nothing separated them, so the bump procedure was a habit —
"split the file at the Done-log heading and replace only above it, by hand" — and four historical cites
were rewritten in two days anyway, twice in a single session. The habit is now the tool's behaviour:
`historicalRegions` in `docs/VERSION_SYNC.json` declares where the past begins, and
`doc_version_sync.py` writes nothing below it, including via `extraReplacements` — whole-file regexes,
and so the rules likeliest to reach backwards.

**The measurement that killed the first design.** The obvious guard was to corroborate each Done row's
engine cite against the changelog entry for that version, on the theory that a rewritten cite would
stop matching. Measured before building: only **20 of 41** rows corroborate today, because changelog
entries do not reliably name every WQ ID. As a Fix that would have been 21 false positives on a clean
tree. The invariant that survived measurement is monotonic instead — **the set of engine versions the
Done log cites may only grow** — which held at 14-of-14 against `HEAD` with zero false positives.

**Three things hold the boundary, because one of them cannot see the actual cause.**

- **The tool** refuses to write below the heading. This closes a latent hazard as well as the known one:
  `WORK_QUEUE` was line-scanned with no boundary, so a Done row phrased `starter pack 2.22.x` was one
  bump away from being rewritten by the sync engine itself. Generated projects were exposed too — their
  `scanGlobs` includes `docs/*.md`, which sweeps up their work queue
- **The config** is checked rather than trusted: `verify-work-queue.ps1` fails when the entry is deleted,
  and fails differently when the entry names a heading that does not exist — the worst state, because the
  config still claims protection while the file is synced end to end
- **The backstop** compares the Done log's cited versions against git `HEAD`. Stated plainly: it cannot
  see a row added and corrupted before its first commit, which is exactly how all four known cases
  happened in a checkout carrying nine unpublished releases. It catches the repeat once history is
  committed, which is when the damage becomes permanent

**Step 64 plants a defect against all five arms** — declaration deleted, heading absent, sync run over a
Done row using the phrasing the engine does match, and a committed cite rewritten — because a guard
written in the same session as its fix is the one most likely to be checking nothing. Proving the fifth
arm exposed a real reporting bug: git declines to read a scratch repo on a filesystem that records no
ownership, and the check reported that as "no committed version yet", which is a true sentence about a
new file and a false one about a repo git refused. The probe went looking in the wrong place until the
two were separated.

**Method note.** The step's git arm passes `safe.directory` to the verify script's own git through
`GIT_CONFIG_*` environment variables rather than editing the user's global config. A test has no
business writing there, and without it the arm silently skipped — which is how an unproven guard looks
from the outside.

## 2.22.74 (2026-09-03)

**The suite runs on Linux: 63 steps, 0 fail — and Windows re-certified at 0 fail after every change.**
2.22.73 shipped a report-only CI job because porting 61 steps blind from a Windows desktop looked riskier
than measuring first. That was right, and the measurement corrected the estimate: the static pass had
guessed 24 Windows-only steps; the real run produced **16 failures**, a different set, and the first one
was not about Linux at all.

**A dead audit gate, found by running somewhere new.** The first Linux failure was a leftover `'-3'` in
`run_audit_core.ps1`'s `$codeArgs` — a survivor of the `py -3` → `Invoke-PackPython` migration, sitting in
a variable rather than at the call site. Python answered `Unknown option: -3`, so `audit_code_checks.py`
and the agent manifest it writes had been silently dead **on both hosts**. Nothing failed, because the
audit treated the missing output as nothing to report. A second host is a cheap way to find the bug your
only host has stopped being able to see.

**One spelling for a path.** `pack-paths.ps1` gained `ConvertTo-PackPathKey`, `Split-PackPathKey`,
`Get-PackRelPathKey`, `Test-PackPathKeyUnder` and `Test-PackPathHasSegment`; 357 `Join-Path` literals, 46
interpolated ones, 21 `Substring($Root.Length).TrimStart('\')` idioms and 6 `\.git\`-shaped filters were
rewritten to use them. The rewrites were AST-driven and extent-exact so messages and regexes were left
alone — and the AST is also what caught that `Join-Path $x ".tmp\probe-$PID"` is an *expandable* string,
a class the first pass had silently skipped. `TrimStart('\')` is the quiet one: it does not strip a
leading `/`, so on Linux every relative key kept its separator and no comparison against a manifest entry
could match — the filters passed everything through while looking like they filtered. Those five helpers
now decide roughly 430 path comparisons and had no test of their own, so **step 63** pins them: eight
cases, four of which are near-misses (`docs/handoffs` versus `docs/handoffs-archive`, a `.git/` segment
versus a file called `x.gitignore`), because the failure to fear is a helper that answers *uniformly*,
not one that answers wrongly. It asserts it built all eight cases before judging any of them.

**Test and audit entry points are one implementation with two wrappers.** `run_audit_tests.bat` *was* the
implementation — five steps of Batch — so the pack's own test command could not exist off Windows, and
the audit runs a project's declared test script to earn its test-pass proof. Now `scripts/run_audit_tests.ps1`
holds the logic behind `run_audit_tests.bat` and `run_audit_tests.sh`, matching `run_audit.cmd`/`.sh` →
`scripts/run_audit.ps1`. Generated projects get the same shape for `run_tests` and `run_audit`, plus
`tests.scriptPosix` in `AUDIT.config.json` (a **required key**, so the template cannot ship without one).
`Get-PackScriptRunner` picks the interpreter by extension, and a script this host cannot run is a **Fix**
that names the config key to add — never a skip, because a silent skip would let `finalize` collect a
test-pass proof no test ever earned. **Step 22 now asserts the property that matters** — both wrappers
delegate to one implementation — instead of grepping one wrapper for the work itself.

**Four defects only Linux could show.**

- **Every export made off Windows was broken.** `Copy-Item -Recurse` skips hidden children, and on Linux
  every dot-prefixed name is hidden — so `.cursor/rules/audit.mdc` and the fixture's `.gitignore` never
  reached the archive. `Compress-Archive` is worse: naming a dotfile explicitly fails outright with
  "Could not find item .gitattributes". Staging now enumerates with `-Force` and the archive is built with
  `ZipFile.CreateFromDirectory`
- **A generated project could not audit itself.** `run_audit.ps1.template` called `Join-Path
  $env:USERPROFILE` (null off Windows) and spawned `& powershell` (absent off Windows), so the audit
  exited 0 having audited nothing
- **The Cursor session hook** had both faults, so it produced no context at all off Windows
- **All six shipped `.sh` files were committed `100644`** — a fresh clone could not run `./install.sh`, the
  first command the install instructions give. No test could see it: Windows has no execute bit, and WSL
  reads `/mnt/*` as 777 regardless, so both hosts reported success on a pack nobody could start.
  **Step 62** reads the mode from git, the only place it survives a copy, and reports untracked `.sh`
  files with the `git add --chmod=+x` form rather than failing an uncommitted tree

**A guard that had been passing by luck.** Installing WSL put a second `bash` on PATH — `System32\bash.exe`
takes precedence over Git bash — and step 54 both preferred bare `bash` and hardcoded Git bash's `/d/x`
mapping, which WSL spells `/mnt/d/x`. Five wrappers then failed with "No such file or directory" on a
machine where nothing about the pack had changed. `Convert-PackPathToPosix` asks the chosen shell
(`cygpath`, then `wslpath`) instead of assuming, and the probe prefers Git bash because running these
wrappers inside a distro is a different OS than the step claims to cover.

**The wrapper shape broke the check that reads runners, and fixing it found a worse hole.** With both
entry points now delegating, the self-audit reported `run_audit_tests.sh never runs test_pack_audit.py`:
`check_test_runner_coverage` follows one level of delegation, but only through a fixed vocabulary of
invocation spellings, and the posix wrapper reaches the implementation through `pack_pwsh_file` rather
than by naming `pwsh` on the command line. Widening that vocabulary is only safe while a *mention* still
does not count — and it did. Coverage is a substring search over the whole runner file, so
`# real suite: scripts/run_tests.ps1 (test_thing.py)` above `exit /b 0` satisfied it, as did an `echo` of
a path. The one defect this check exists to catch could be waved through with a comment. Inert lines —
comments, and output statements that run nothing else — are now stripped before the search, and
`test_runner_coverage_follows_delegation_but_still_refuses_stubs` pins **both** directions: two real
wrapper shapes accepted, three stub shapes refused.

**Method note.** Two rewrites regressed Windows and the suite caught both within one run: an index
expression that needed parentheses, and `.tmp\*` exclusion patterns that stopped matching once the keys
they were compared against became forward-slashed. Both are the WQ-443 shape — a filter that silently
excludes nothing still looks like a filter — which is why Windows was re-run after every batch rather
than at the end.

**Method note, WQ-443 on the harness itself.** The negative-control run for these guards printed
`CAUGHT` for the path-key checks while its dot-source of `pack-paths.ps1` had failed and not one case had
been evaluated: the case list was built by calling the missing functions, so it came out empty, and an
empty list has no mismatches. A control harness is a guard, and it needs the same treatment — it now
asserts *how many* cases it compared before reporting on them. Worth stating plainly: the first thing the
negative controls caught was themselves.

## 2.22.73 (2026-09-02)

**One version of the pack, two hosts, and a gate that actually runs both.** The pack targets Windows
PowerShell 5.1 because it ships with Windows - that floor is what lets a single codebase run from a USB
stick on a machine with nothing installed, and run under `pwsh` on macOS and Linux through the `.sh`
wrappers. What was missing was enforcement: `-DualShell` existed but nothing invoked it, so "the suite
passes under both" was a comment in `pack-paths.ps1` rather than a tested claim. Windows contributors only
ever exercised 5.1; everyone else only ever exercised 7.

- **`run_audit_tests.bat` now passes `-DualShell`** when `pwsh` is present. 5.1 stays the launcher - it is
  the only host guaranteed to exist - and the second host is what the gate adds. Certification went from
  3m30s to 6m16s. `PACK_SKIP_DUALSHELL=1` for a single-host loop while iterating; the gate never skips it
- **Behavior step 61** refuses the three constructs that differ between the hosts, by AST rather than text
- **Step 22 asserts the runner still passes `-DualShell`**, so the gate cannot quietly lose its second host
- **The Linux job now runs the full suite, report-only** (WQ-446). 24 of 61 steps touch `.cmd` runners,
  `%USERPROFILE%\.cursor`, `powershell.exe` or `robocopy`; one real run will produce the authoritative
  list, which beats porting 61 steps blind from a Windows desktop

**The premise needed correcting first.** Sessions kept blaming 5.1, so both hosts were probed directly:

| Construct | 5.1 | 7.6.5 |
| --- | --- | --- |
| `.Replace(a, b, 1)` | throws - no such overload | returns `bbb`: the `1` binds to `StringComparison` and **every** match is replaced, silently |
| `-Include` without `-Recurse` | matched 3723 files in a folder of 3538 | matched 4 |
| `Write-Host` captured by `2>&1` | no | no - **identical**, and `6>&1` works on both |
| `Set-Content -Encoding UTF8` | writes a BOM | no BOM |

Only the last is a genuine version split, and it was already centralised in `Write-Utf8NoBom`. Two others
are wrong on every host - one of them *silently* wrong on 7, which is the more dangerous direction - and
one never differed at all. So the guard bans constructs, not versions.

**A real BOM bug fell out of the sweep.** `register-portable-mcp.ps1` wrote the MCP config with
`Set-Content -Encoding UTF8`, so a config registered from Windows 5.1 carried a BOM - in the *portable* MCP
registrar, whose whole job is producing a file another tool reads. Seventeen call sites moved to
`Write-Utf8NoBom`; sixteen were suite fixtures, which the suite itself then verified on both hosts.

**A guard for text written through an escape.** Adding a queue row from a PowerShell double-quoted string
turned `` `a `` into a bell character and `` `v `` into a vertical tab, eating the first letter of five
filenames. The row still rendered as a table, and a full audit certified it. `verify-work-queue.ps1` now
fails on any control character other than tab, CR and LF - and every project gets that check, not just
this one.

---

## 2.22.72 (2026-09-02)

**A list's readers are declared, not discovered (WQ-442).** `machineLocalPaths` got one home in 2.22.54 and
that held - but nothing enumerated its *readers*, so every consumer after that was found by shipping the
bug: WQ-425, WQ-426, WQ-429, WQ-430, WQ-439. One list, one home, six discoveries.

- **`listConsumers`** maps each manifest list to the scripts that must read it
- **`distributionChannels`** and **`distributionCriticalKeys`** name the ways this pack reaches a machine
  that did not build it, and the lists each of them must honour
- **Step 60** fails on three things: a declared reader that stopped reading, a channel honouring one
  critical list but not the others, and an *undeclared* reader - so a new channel has to be registered
  before it can quietly disagree with the existing ones

**WQ-425 closed as its instance, with its own premise corrected.** The row said installing from a
transferred folder could plant a foreign context stamp in the profile. It could not, quite: install runs
`sync-audit-system.ps1` out of the installed tree afterwards, and sync deletes machine-local files. That
was established by disabling both guards, at which point the planted stamp does arrive. The real defect
was narrower and still worth fixing - the profile **held another machine's context stamp until a later
step happened to clean it up**, and that cleanup depended on sync existing at the destination and
succeeding. `install.ps1` now skips the list at copy time, reading the same key `export.ps1` reads.

**The masking had already defeated the test.** The first version of step 60's install arm planted state,
installed, and asserted absence - and passed identically with the filter removed, because sync cleaned up
either way. A guard that cannot fail. The probe now disables sync in its scratch source so the arm tests
install's own filter, which is the thing this release changed. Negative control run both ways: with the
filter removed, step 60 fails naming `docs\AGENT_CONTEXT.json` and `docs\AGENT_PASTE.txt`; restored, the
suite is green.

**Two enumeration bugs of the same shape, found in one session.** `Get-ChildItem -LiteralPath X -Include
'*.ps1'` silently matches *everything*, because `-Include` needs `-Recurse` or a wildcard path. It first
made a reader survey look like two files out of eighty-five, and then made step 60 report `.gitignore` and
the semantic report as undeclared readers. Both now filter on `.Extension` explicitly.

**A section parser that could be fooled by a quotation.** Writing the WQ-437 row surfaced this: the row
mentioned the Done-log heading inside a table cell, and `Get-SectionBody` located its *start* header with
an unanchored `IndexOf` while anchoring every *end* header at line start. The Done section therefore began
in the middle of the Active table, and the queue verifier reported every active id as both active and done.
Anchored now - in all **five** scripts that define their own copy of that helper, which is WQ-441's finding
again in a different helper and is filed as WQ-444.
**WQ-437 promoted to Next, and WQ-443 filed.** This release bumped versions by splitting the queue at
`## Done log` and replacing only above it, by hand, because a blanket replace has corrupted historical
cites four times in two days. That belongs in the tooling. WQ-443 collects the day's six
checks-that-could-not-fail into one item: a behavior step should not be addable without a planted-defect
arm proving it can fail.

---

## 2.22.71 (2026-09-02)

**One home for the path vocabulary (WQ-441).** Prompted by a fair question - whether this run of releases
was solving root problems or patching instances. Measuring first was worth it, because it corrected the
premise twice.

**What the measurement showed.** Nine verify scripts, 5,108 lines, only `pack-paths.ps1` shared, four
sharing nothing at all. The first read of that said "one rule implemented three times". Reading the code
said otherwise: `verify-product-truth-paths.ps1` uses its drive-letter match to *normalise* a cited path by
stripping the project root, and `verify-agent-handoffs.ps1` uses its own to enforce the **opposite** rule -
a session opener must be root-anchored, absolute or placeholder, because a bare relative path opens the
wrong file. Three different rules that share a regex fragment.

**What actually duplicated** is the vocabulary underneath: four private answers to "is this string a
placeholder or a person". That is the mechanism behind WQ-440. `verify-session-handoff.ps1` shipped in
2.22.68 with no path rule at all, and the lesson it needed had lived in a *differently shaped* rule since
2.22.58 - so there was nothing to copy, and nothing to notice missing.

- **`pack/scripts/verify-lib.ps1`** - `Test-PackSubstitutionMarker`, `Test-PackRootAnchoredPath`,
  `Get-PackMachinePathHit` (**Strict** for files that travel, **Illustrative** for docs that must show a
  concrete example), `Get-PackIllustrationUserName`
- **Consumers migrated:** `verify-session-handoff.ps1`, `verify-agent-handoffs.ps1`, behavior step 50
- **Behavior step 59** fails when a script outside `pathRulePrimitiveAllowlist` grows its own copy

**A latent gap closed on the way.** The older rule anchored at line start (`^[A-Za-z]:\\`), so an absolute
path anywhere but the first character escaped it. The shared predicate has no such blind spot, which is
asserted directly in step 59 rather than assumed.

**The rules stay separate; only the vocabulary is shared.** Merging the three rules would have been the
wrong fix - they disagree on purpose. What they must not disagree about is what a placeholder *is*.

**Two of the author's own mistakes are the evidence it works.** Step 50 failed the build because step 59's
fixture contained a real user name, in a file that travels as far as prose does; the fixture now builds
that string at runtime from a name deliberately absent from the illustration list. And the migrated
pointer check failed a `SESSION.md` line naming two WQ ids, because the regex takes the furthest id within
120 characters. Both were caught by guards written for other reasons, which is the argument for having
them.

**Method note, fourth of the day.** Three `.Replace(old, new, 1)` calls in scaffolding silently did nothing
- PowerShell 5.1's string type has no count overload - while the success messages printed anyway, because
the exception was non-terminating at the default preference. The file state was verified afterwards and the
edits redone. Same shape as the zip separator, the in-process capture, and the syntax-error probe: a step
that reports success without observing the thing it claims.

---

## 2.22.70 (2026-09-02)

**A repair path for hooks that predate their own fix (WQ-435).** 2.22.63 fixed the generated Cursor
session hook - an unbounded `[Console]::In.ReadToEnd()` that returns instantly under Cursor, which closes
the handle, and never returns under bash, which does not. `install.ps1` rewrites the profile copy on every
install, so that one self-heals. `bootstrap-project.ps1` copies the project hook with `-ForceWrite:$Force`,
so every project bootstrapped before that release kept its broken copy, and the only remedy was
`bootstrap -Force`, which rewrites unrelated generated files too.

- **`pack/scripts/repair-project-hooks.ps1`** - `-ProjectRoot`, `-VerifyOnly`, `-AuditMode`
- **Wired into `update-agent-stack.ps1`** (the command already run after a pack upgrade) and surfaced as
  **Fix** by `run_audit_core.ps1`, so a project's own `run_audit.cmd` reports it
- **Behavior step 58** - current, stale, `-VerifyOnly`, `-AuditMode`, idempotence, no-hooks-at-all

**Three design choices worth keeping.**

**Detect the defect, not a difference.** The check matches the pre-fix shape - an unbounded `ReadToEnd`
with neither `IsInputRedirected` nor a bounded `Wait` - rather than comparing against the template. A hash
compare would report drift for every unrelated template edit and would overwrite a hook somebody
customised on purpose. The job is to name the hang, not to enforce sameness.

**Back up only when repairing.** A second run finds a current hook and stops, so `.bak` keeps the file the
project actually had. Copying on every invocation would bury the original under a copy of the repaired
file, which is the one thing a backup exists to prevent.

**A repair nobody knows to run is not a repair path.** Hence the audit surfacing rather than a script
mentioned in a document. The remedy text is addressed to the agent, matching the agent-context Improve, so
it offers the run instead of handing over a command to type. An absent `.cursor/hooks` is INFO, because a
project that never took the Cursor target is not broken and reporting it would train people to ignore the
check everywhere else.

**WQ-437 bit twice in one session.** The bump to 2.22.69 rewrote WQ-438's historical cite from 2.22.68,
and the bump to 2.22.70 rewrote WQ-439's and WQ-440's from 2.22.69 - both times a blanket replace on
`docs/WORK_QUEUE.md`, both times hand-corrected afterwards by reading the rows back. The queue's Done log
is the one file where every version number is a *historical* claim, so it is the one file a
release-wide replace must never touch blindly. That is now four hand-fixes across two days, which is the
whole argument for the backlog item.

**Method note.** Step 58's first version called the script in-process and asserted on the captured output.
`Write-Host` does not reach the success stream, so it captured an empty string and the step failed - which
is how it was found. Written the other way round, the assertion would have passed on nothing. That is the
third instance today of a check that could not fail, after the zip separator in WQ-439 and two assertions
in the smoke run that reported `True` on null input. The suite's own convention -
`Invoke-PackScript -PassOutput`, a child process whose stdout is real output - exists for this reason.

---

## 2.22.69 (2026-09-02)

**Two leaks found by reading a returned folder (WQ-439, WQ-440).** The tree came back from the primary
system at 2.22.68 and **failed its own suite on arrival** - one real failure, in a file written the day
before.

**`docs/handoffs/SESSION.md` named a machine.** It recorded the received copy's own checkout root twice, which step 50
forbids in any file that travels. **It passed on the machine that wrote it**, because that guard
compares against the checkout it is running in: a document naming a *different* root is invisible to it.
A leak of this shape is only ever caught by the machine it is wrong for. `verify-agent-handoffs.ps1` has
required the placeholder form for slice openers since 2.22.58, but `verify-session-handoff.ps1` shipped
one release earlier without it, so the new channel had no rule of its own. Added, with `<pack checkout>`,
`%LOCALAPPDATA%`-style env roots and `<you>` markers explicitly still legal - a blunter rule would ban
the syntax the pack tells people to use. **Step 57** now tests both directions.

**`export.ps1` shipped what `install.ps1` strips.** Same manifest list, two channels, one reader: the
export removed `machineLocalPaths` and never `maintainerOnlyPaths`, while copying `docs` and `.cursor`
wholesale. So a zip carried `.cursor/rules/no-publish-from-this-machine.mdc` - **a workspace rule
instructing the recipient's agent not to commit or push their own work**, which is exactly what that
rule's own text says to delete on arrival - together with `docs/handoffs` and its session notes. The
fix reads the manifest key `install.ps1` already reads, with the same folder-aware semantics.
**Step 52** fails on any maintainer-only path in the archive.

- Verified on a real 189-entry export: no maintainer-only content, every `packMirror` entry and audit
  entry point still present. With the filter disabled, four leaks return
- **Method note worth keeping:** the first archive read compared forward-slash names while
  `Compress-Archive` writes backslashes, so nested paths matched nothing and the export read *clean*
  before the fix existed. A check that cannot fail is worse than no check - and this is the second time
  that exact sentence has been earned by a separator
- **Writing up the defect reproduced it.** The Done row and this entry originally quoted the offending
  path verbatim, and step 50 failed the suite again - on the write-up. The guard forbids the string, not
  the intent, so a post-mortem cannot name what it is describing. Both now say *the pack folder's own
  drive root*, which is also the phrasing that stays true on the next machine

**Correction to the 2.22.65 entry below.** It claimed WQ-431 was "closed by construction" when the
session document was retired. Only half of it was: the queue header's **Next active ID** can still
disagree with the Active **Next** row, and 2.22.67 built that check. The entry has been amended in
place rather than left to contradict the Done log - the WQ-437 class, caught by reading rather than by a
guard, because nothing checks a changelog claim against a Done row yet.

---

## 2.22.68 (2026-09-02)

**Session handoff first on continue (WQ-438).** Retired `HANDOFF_NEXT_AGENT.md` removed the second
**Next** claim but left no session **now** channel — agents jumped straight to WORK_QUEUE or chat.

- **`docs/handoffs/SESSION.md`** — blockers, open items, pointers only (no duplicate WQ tables)
- **`pack/rules/handoff-first.mdc`** — always-on lookup order SESSION → WQ → unplanned; interrupt rule
- **`verify-session-handoff.ps1`** — wired from `verify-complete-picture.ps1`; behavior **step 57**
- **`refresh-agent-context.ps1`** — SESSION in `requiredReads` before WORK_QUEUE when present
- **`ensure-work-completion.ps1`** — scaffolds SESSION from template (never overwrites)

---

## 2.22.67 (2026-09-02)

**Wire product-truth into the close path (WQ-416, WQ-417, WQ-431, WQ-420).**

- **`verify-complete-picture.ps1`** — delegates to `verify-product-truth-paths.ps1`; **pack repo:** FAIL when
  WORK_QUEUE header **Next active ID** disagrees with Active **Next** row (WQ-431)
- **`update-agent-stack.ps1`** — **`-VerifyOnly`** runs Step 5b without refresh; Step 5b runs after refresh
  for pack and for **`-ProjectRoot`** app checkouts
- **`pack/templates/docs/DOC_MAP.md.template`** — product-truth owners table (WQ-420)
- **Portable skill** — product-truth drift on a closing slice → **Fix**, not Improve (WQ-419)

---

## 2.22.66 (2026-09-02)

**Product-truth verify — limitations/capability prose vs code (WQ-415).** Step 3c had human-only
"read the sections you touched"; agents could pass ROADMAP alignment while capability docs still said
*not built* for a Done **WQ** id, or while code no longer matched a documented capability.

- **`pack/scripts/verify-product-truth-paths.ps1`** — resolves product-truth paths from the
  `docs/WORK_COMPLETION.md` overlay (or defaults); **FAIL** when listed files are missing; **FAIL**
  when a Done **WQ** id appears beside not-built/deferred phrasing; optional
  `docs/.product_truth_verify.json` doc/code claims (example template shipped)
- **`pack/docs/WORK_COMPLETION.md`** Step **3c** — run the script before step 5b
- **Behavior step 55** — negative probes for missing overlay path, Done-WQ prose contradiction, and
  a passing JSON claim fixture

**WQ-416** (wire into `verify-complete-picture` / Update-AgentStack) remains queued.

---

## 2.22.65 - The session document is gone, and so are the checks that reconciled it

**One status claim.** `HANDOFF_NEXT_AGENT.md` is deleted; `docs/WORK_QUEUE.md` is canonical. Two
documents claiming what was next produced a contradiction three times (2.22.55, and twice on
2026-09-01), each caught by hand or by a check written specifically to compare them. Removing the
second claim removes the class.

**What this cost, and why it was not just a delete.** 21 files referenced that document, including
`verify-audit-behavior.ps1` (10), `verify-complete-picture.ps1`, `refresh-agent-context.ps1`,
`export.ps1`, `pack/audit/manifest.json` and `docs/VERSION_SYNC.json`.

| Consumer | Was | Now |
|---|---|---|
| `verify-complete-picture.ps1` | Read `## 11.` and compared Next, Done ids and a canonical pointer against the queue | Those three checks deleted - nothing left to disagree with. Reads the queue's own Active section for stale shipped-task phrases, and **fails FIX when an id sits in Active and Done at once** |
| `refresh-agent-context.ps1` | Pack-repo brief required the session doc; the paste line named it | Requires `pack/docs/START_HERE.md`; the paste line names the queue |
| `verify-audit-behavior.ps1` step 27 | Asserted the pack brief lists the session doc and the app brief does not | Same split on `pack/docs/START_HERE.md`, which is pack-only - `docs/WORK_QUEUE.md` could not be the discriminator because projects have one too |
| `verify-audit-behavior.ps1` install-filter probe | Used the session doc as its maintainer-only *file* fixture | Uses `.cursor/rules/no-publish-from-this-machine.mdc`, a real entry, with `docs/handoffs` still covering the folder case |
| `export.ps1`, `manifest.maintainerOnlyPaths`, `VERSION_SYNC.json` (x2) | Listed it for exclusion and version scanning | Entries removed |
| Step 46's banned-token table | Banned the name in shipped rules as a pack-only doc | Kept, reason changed to *retired - do not resurrect the name* |

**A latent bug came out with it.** `verify-complete-picture.ps1` exited early when no session document
was found, which skipped the Done-contradiction scan entirely - so a bootstrapped app, the case least
likely to have such a file, got the least checking. That scan now always runs.

**WQ-431 is narrowed, not closed.** The section-11 half of it is gone with the document. The queue's
own header still carries a **Next active ID** field that can disagree with the Active **Next** row, and
that half stayed open - 2.22.67 built the check for it and owns the Done row. *(Corrected 2026-09-02:
this entry originally claimed the id was closed by construction.)*

**The distilled lessons were absorbed, not discarded** - fifteen findings that outlive their release now
open `docs/WORK_QUEUE.md`. Everything else in the retired document already existed elsewhere: deferred
items are backlog rows, the last-session summary is this changelog, and the transfer procedure is the
drive-root document from earlier today.

**Verified:** two new probe arms (a stale phrase in the Active queue, an id in both Active and Done),
suite green, `finalize_audit.cmd` exit 0.

---

## 2.22.64 (2026-09-01)

**The active slice was telling the other machine to expect the wrong number.**
`docs/handoffs/active/HANDOFF_WQ426_publish_machine_local_fix.md` read *"Behavior steps are now 53; a
suite reporting 52 on that machine means the sync did not land"* — written as a tripwire for a stale
sync, and made wrong by step 54 an hour later. **A tripwire calibrated to the wrong value is worse than
none**, because it fires on the healthy state and stays quiet on the broken one. The slice now also
carries what 2.22.63 changes for that machine: the hook fix travels as source, but projects
bootstrapped there keep the blocking copy (**WQ-435**), and the four new CI steps get their **first real
execution** on that publish — validated here structurally only, since this machine has no PyYAML and
does not push.

**Three tracked gaps were invisible where a next agent looks for unfinished work.** **WQ-431**,
**WQ-432** and **WQ-433** were filed into `docs/WORK_QUEUE.md` in 2.22.62 and were absent from § *Still
deferred* in the session handoff — the inverse of the fault 2.22.62 fixed, and the same root cause:
**the queue is canonical, but nobody reads it first.** §7 now points to them by id without copying the
rows.

- **`pack/docs/WORK_COMPLETION.md` now states its own known tension.** Step 3 says product-truth drift
  blocks the close while the audit that detects it is step 6, *after* the WQ row moves to Done in step
  5. That is **WQ-432**, recommended twice before it had an id — and the document carrying the flaw said
  nothing about it, so anyone following the order in good faith would reproduce it
- **`docs/OS_PORTABILITY_PLAN.md`** verification table: added step 54 and the CI wrapper runs, which
  **supersede** its manual Linux gate; the manual gate is now scoped to macOS and marked open
- **WQ-436 filed** — the wrappers run on Windows-with-bash and on `ubuntu-latest`, and have **never run
  on macOS**. `pack-paths.ps1` treats all non-Windows alike, so what is untested is `pwsh` discovery and
  BSD shell tooling rather than the delegation itself. Stating it beats implying the matrix is covered

**WQ-437 filed against this release's own mistake.** Bumping the cites rewrote five *historical*
references — the WQ-434 Done row and three handoff cites became 2.22.64, claiming work shipped in a
release that postdates it — exactly as the WQ-430 row did in 2.22.62. **Three hand-fixes in one day, and
the repo's own standard is that a repeated correction becomes a check.** A Done row's `Engine 2.22.N`
must match a changelog section that names that WQ id, which is mechanical and would have caught all
three.

**Handoff documents consolidated to one transfer file (same release, later the same day).** At the
user's request the pack's *status* documents were reduced to one: a single transfer document written to
the **root of the portable media root**, deliberately outside the checkout so it cannot reach a commit, an
export or an install. Deleted after their content moved there:

| Deleted | Why it was safe |
|---|---|
| `docs/handoffs/active/HANDOFF_WQ426_publish_machine_local_fix.md` | Its full slice is section 2 of the transfer document |
| `docs/handoff_archive/HANDOFF_WQ414_product_truth_step3.md` | `status: completed`; open items are WQ-415–422, all still queued |
| `docs/handoff_archive/HANDOFF_WQ011_primary_system_update.md` | `status: completed` 2026-08-31; its live warning is now a policy note |
| `docs/HANDOFF_DESIGN_REFERENCE.md` | Unbuilt items already tracked as **WQ-431** and **WQ-433** |

**`HANDOFF_NEXT_AGENT.md` was kept, and that is a finding rather than a preference.** A grep for what
references it returned **21 files** — `verify-audit-behavior.ps1` (10 references),
`verify-complete-picture.ps1`, `refresh-agent-context.ps1`, `export.ps1`, `pack/audit/manifest.json`,
`docs/VERSION_SYNC.json`. It is not a status document; it is wired into the engine, so removing it is a
rewiring release, not a cleanup.

- **Every live citation to the four was repaired** — the WQ-426 queue row, `docs/handoffs/README.md`,
  three rows in the verify map and queue backlog, the docs tree and four §11/§14 pointers here. The
  paths are replaced with *unpathed* references on purpose: a tracked file must not record where the
  portable media root happened to be mounted, which is the same rule 2.22.58 enforces for the checkout path
- **Done-log and changelog evidence keeps its narrative** but no longer cites a path that cannot
  resolve. Historical entries above are left alone — they record what was true then
- **`docs/handoffs/active/` and `docs/handoff_archive/` stay** (now empty): they are destinations for
  `archive-completed-handoff.ps1` and `ensure-handoffs-scaffold.ps1`, and the behavior probe for
  archiving builds its own fixture, so an empty folder breaks nothing
- **`docs/HANDOFF_DESIGN_REFERENCE.md` stays in `maintainerOnlyPaths`** even though the file is gone.
  The entry means *if this exists, do not ship it*, which is still true and costs nothing

**A rule the docs claimed to rely on did not exist.** This file, `HANDOFF_NEXT_AGENT.md` and the
manifest all cite `.cursor/rules/no-publish-from-this-machine.mdc` as what stops an agent committing
from the received copy — and it was **absent from disk**. The policy was surviving on prose in the
handoff. Restored, with the reason it must not travel to the publishing machine written into it. The
suite stayed green throughout, which is the honest read: `maintainerOnlyPaths` is an exclusion list, so
nothing checks that its entries exist.

**No code changed** — the documents did, which is what this bump records.

---

## 2.22.63 (2026-09-01)

**Running a wrapper for the first time hung the audit for sixteen minutes.** WQ-434 was filed an hour
earlier as documentation debt: steps 40–43 assert each `.sh` wrapper's *text* delegates through
`pwsh-wrap.sh`, and `pack-os-smoke.yml` triggers on changes to `*.sh` and then runs the `.ps1` files
directly — so nothing had ever run `bash ./install.sh`. Executing one produced a defect immediately.

`./run_audit.sh` sat for 16 minutes. The diagnosis was in the process table rather than the output:
**`pwsh` had consumed 3 seconds of CPU** and its three PowerShell children were idle at 0.2–2.7s. Not
slow — blocked. The probe folders left behind dated the stall to step 39, the Cursor session hook.

**Cause:** `pack/templates/cursor/hooks/session-freshness.ps1` opened with an unbounded
`[Console]::In.ReadToEnd()`. Cursor writes its sessionStart payload and closes the handle, so the read
returned instantly and the step passed for four releases. bash holds the pipe open, and the read then
waits for an EOF that never arrives.

> The script's docstring promises *"fail-open: any error yields empty context so sessions are never
> blocked."* **A read that never returns raises nothing**, so the one failure mode that defeats
> fail-open was the one it could not catch.

- **Fix:** drain only when `[Console]::IsInputRedirected`, and then only through a task with a 250 ms
  wait — the payload is still consumed so a writer never sees a broken pipe, but nothing waits on it.
  A blocked threadpool read cannot hold up process exit
- **Proven both ways:** the old code, started with stdin held open, was killed at 20s; the fix returns
  in **440 ms** with valid hook JSON
- **Step 54** runs four wrappers under bash — argument pass-through (`-Json` returns parseable JSON),
  the usage guard (no args must exit non-zero), a real bootstrap, and both branches of the refresh
  wrapper's argument parsing. `install.sh` and `run_audit.sh` are deliberately excluded: one writes the
  user profile, the other would re-enter this suite. When bash is absent it prints **`[SKIP]` with the
  reason**, because a skip that reads as a pass is how this gap survived
- **New arm in step 39** starts the hook with stdin redirected and never written — the bash case, in the
  suite that already had the hook fixture
- **CI** now executes the wrappers on `ubuntu-latest`, including `install.sh User` against a throwaway
  profile and `run_audit.sh` under a 12-minute timeout

**Two method notes, both worth more than the fix.** Step 54's first run aborted rather than asserting:
`$ErrorActionPreference = 'Stop'` turns a native command's stderr into a terminating error, and the
usage-guard case writes to stderr *by design*. stderr is now merged inside bash. And the first negative
test was invalid — a regex planted a **syntax** error instead of the old semantics, so the step failed
for the wrong reason and the guard looked proven when it was not. Redone by replacing the exact span and
**parse-checking the planted defect before trusting the result.**

**Known limit (WQ-435):** only `bootstrap-project.ps1 -Force` writes that hook, and
`repair-agent-docs.ps1` does not cover `.cursor/hooks/`. Projects bootstrapped before this release keep
the blocking hook until re-bootstrapped.

---

## 2.22.62 (2026-09-01)

**The onboarding document was deferring two items that had already shipped.** A read of the whole
handoff set — session doc, both archived slices, the active slice, the design reference, the verify map,
four plan docs — found that §7 *Still deferred* listed:

- **Import smoke beyond root `*.py`** — shipped as **WQ-305** on 2026-08-30 (2.22.28). `import_smoke()`
  honours `useModuleSearchDirs` and iterates those directories; the Done log said so while §7 did not
- **`install.sh` does not mirror the installer's project-scope skill exclusion** — it is nine lines
  that delegate to `install.ps1` through `pwsh-wrap.sh`, so it cannot diverge

`AGENTS.md` tells the next agent not to rebuild finished work, and §7 is where they would look for what
is unfinished. **A stale deferred list is not a harmless leftover; it is an instruction to redo
something.** Both entries deleted, with the reason recorded beside the existing removals.
`docs/MULTI_TOOL_GAP_PLAN.md` had the same disease in reverse: its overview table marked phases 1–6
Done with evidence while three section headings below still read *(planned)*.

**Four gaps existed in prose and in no queue.** Each was written down — twice or three times — and
tracked nowhere, so none was on the radar the queue exists to be:

| ID | Gap | Where it was hiding |
|---|---|---|
| **WQ-431** | Session doc **header** status unchecked | Design reference pain point 7 + verify map. **Hand-fixed twice** |
| **WQ-432** | Audit runs *after* WQ Done while Step 3d says drift blocks the close | WQ-414 archive § Recommended next work #2, session handoff §14 |
| **WQ-433** | Cited paths under `docs/`, `scripts/`, `tests/` unchecked here | Verify map known gaps |
| **WQ-434** | The six `.sh` wrappers are **never executed** | Session handoff §7, OS plan's unticked manual gate |

**WQ-434 is the one worth reading twice.** Steps 40–43 grep each wrapper's text for markers like
`pwsh-wrap.sh`; `pack-os-smoke.yml` triggers on changes to `*.sh`, runs on `ubuntu-latest` where `pwsh`
is present — and then executes the `.ps1` files directly. Nothing anywhere runs `bash ./install.sh`. A
workflow that watches a file while exercising a different entry point is the same shape as the export
guard that passed a broken archive (2.22.60) and the 47 behavior steps that missed four bare `pause`
statements (2.22.51). It also contradicts a standing decision in the handoff itself: *prefer executing a
path over reading it.*

**No code changed in this release** — three mirrored pack docs did, which is what the bump records.

---

## 2.22.61 (2026-09-01)

**The same bug three times in four releases, so this release went looking for the rest of it.** The
shape: a script keeps its own copy of a list the manifest already declares, the two drift, and the
narrower copy reports success. `machineLocalPaths` across four consumers (2.22.56), `export.ps1`'s
`$items` (2.22.60). A scan of every literal file-name array in the pack's scripts found two more — both
green, both narrower than the thing they guard:

| Consumer | Was checking | Now |
|---|---|---|
| `verify-agent-setup.ps1` §2 | 5 named rules | all **15** `packToUser` entries (12 rules + 3 skills) |
| `verify-agent-setup.ps1` §4 | 10 hand-picked pack files | all **174** `packMirror` entries |
| `verify-portable-bootstrap.ps1` | 5 named files | **13** — portable extras ∪ `projectRequired.flatLayout` |
| `run_audit_core.ps1` | manifest, falling back to a stale literal | manifest only; an unreadable one is a **reported gap** |
| `verify-complete-picture.ps1` | 8 curated docs | unchanged — **curated on purpose**, now says so and why |

**Neither was wrong; both answered a smaller question than the one they appeared to answer.**
"Is the setup verified?" meant "are these five of twelve rules present?" — seven could fail to install
and the script still passed. "Is this project portable?" meant "are these five of nine audit entry
points present?" — the other four would fail on the recipient's machine instead.

`run_audit_core.ps1` is the interesting one: its literal fallback matched the manifest exactly, so it
had never *caused* a wrong answer. It also turned out to be unreachable while any pack manifest
resolves — hiding the pack folder's manifest falls through to the installed copy's. **Dead code holding a
duplicate of live data is a bug waiting for its first reader**, and the honest failure mode is a
reported gap, not a silent snapshot.

- **Step 53** asserts each consumer still reads its manifest key. It cannot prove the read is
  *correct* — only that the coupling was not quietly removed and replaced with a private array
- Negative-tested all three: a hidden `packMirror` file the old list ignored now fails; a deleted
  `finalize_audit.cmd` now fails a generated project; renaming `projectRequired` in one consumer fails
  step 53
- `verify-agent-setup.ps1` now **stops** on an unreadable manifest instead of iterating empty lists —
  with the lists manifest-derived, a missing manifest would otherwise mean "verified after checking
  nothing"

**Lesson, stated once so it stops recurring:** when a list has an owner, consumers read it. A second
copy is not defence in depth — it is two answers with no rule about which wins.

---

## 2.22.60 (2026-09-01)

**A downloaded pack could not run its own test suite.** Everything 2.22.56–2.22.59 verified was
verified *here* — in a checkout with git history, a synced install and a populated state directory. So
this cycle unzipped an export into a scratch folder and ran it as a first-time recipient. The identity
result held (180 files, no user name, no reference to the sending checkout), but the copy failed with
**seven `missing at pack root`** errors: `Update-AgentStack.cmd`, `Bootstrap-Portable-Project.cmd`,
`Register-Tool-Adapters.cmd`, and the four `.sh` launchers.

**Cause: `export.ps1` kept its own hand-written `$items` list** while `packMirror` declared what a
working copy needs, and the two drifted — the third time this shape of bug has surfaced in four
releases. The export's completeness guard did exist, but it checked `projectRequired.flatLayout` plus
three named files: **narrower than the thing it protects, so it reported success on a broken archive.**

- **`$items` now unions the root-level `packMirror` entries**, so adding a launcher to the manifest
  ships it automatically
- **The guard checks every `packMirror` entry**, not a curated subset, and still excludes
  `machineLocalPaths` (removed by design). Proven by hiding a launcher: export exits 1 with
  *Export incomplete*
- **Step 52 runs the real export** into a scratch folder, unzips it, and asserts both halves — every
  mirrored file present, no machine-local file carried. A guard that only reads the script's text
  would pass the day someone rewrites the copy loop

**The lesson is about where verification runs, not about the export.** A pack that is meant to travel
has to be tested somewhere other than the machine that built it; on the build machine, the missing
files are sitting right there and every check passes.

---

## 2.22.59 (2026-09-01)

**The pack folder no longer generates anything that describes the machine it is on.** Three releases
had policed this file class — gitignore it, list it in one place, guard the git index, reject
hard-coded checkout paths — while the files kept being written. The cause was never a copy method: the
pack **audits and refreshes itself through the same code path a bootstrapped app uses**, and that path
writes a per-machine brief into `docs/`, which is correct for an app pinned to one location and wrong
for a folder designed to travel on a stick, arrive as a download, or be cloned by anyone.

- **`Get-AgentStateRoot`** (`pack-paths.ps1`) and **`agent_state_root()`** (`agent_context_freshness.py`)
  decide where the four context artifacts live: a project's own `docs/`, or - when the project **is** a
  pack root - `%LOCALAPPDATA%\AgentStarterPack\state\<leaf>-<hash of checkout path>` (POSIX:
  `$XDG_STATE_HOME`). Keyed by path so a stick and a Desktop clone on one machine keep separate stamps
  instead of overwriting each other's
- **`ensure-work-completion.ps1` generates no overlay for a pack root.** The pack already ships the
  canonical `pack/docs/WORK_COMPLETION.md`; the generated copy existed only to hold this machine's
  absolute paths, and it held seven of them
- **`AGENT_STARTER_PACK_STATE_ROOT`** override, same shape as the install-root override, so behavior
  probes do not write their stamps into the real `%LOCALAPPDATA%` and leave them there
- **Step 50 gained the strongest arm:** any `machineLocalPaths` entry *existing* in the checkout is a
  failure, not just one that is tracked or content-checked. Plus an assertion that the state root
  resolves outside the checkout, since an override pointing inward would reintroduce the whole problem
- **Step 51 compares the two implementations.** Two hand-written copies of a hash rule is exactly the
  shape that drifted four ways for `machineLocalPaths`, and disagreement here would be silent: the
  refresh reports success, the freshness check reports *missing AGENT_CONTEXT.json*, and nothing names
  the cause. `--print-state-root` exists only so this comparison can be made
- **Consumers now resolve instead of assuming `docs\`:** `update-agent-stack.ps1` and
  `verify-agent-setup.ps1` would otherwise print or warn about paths that are correctly absent, and the
  session-start opener now names the brief's real path

**Ordinary projects are untouched** - `agent_state_root` returns their own `docs/`, bootstrap still
stamps `docs/AGENT_CONTEXT.json`, and the placeholder-substitution path for `WORK_COMPLETION.md` still
runs for them. The generic rule now says the session-start file may be absent in a repository that
keeps no per-machine files, so an agent runs the refresh and reads the printed paths rather than
concluding the project has no context.

---

## 2.22.58 (2026-09-01)

**A user name was never the whole disclosure — where the checkout lives is machine state too.** Step 50
allowed any drive-letter path that did not name a real person, on the reasoning that docs need concrete
examples. But a path like the sending machine's own pack folder is wrong on every other machine, it
reveals the layout of whoever wrote it, and unlike a generated stamp it **survives a clone and a
download** rather than only a folder copy. The pack's own standing rule already said never hard-code a
drive letter in scripts or docs; nothing enforced it.

- **Step 50 now fails when a travelling file contains the pack folder's own absolute path**, in any of
  the three forms a path takes in text (native, JSON-escaped, forward-slash). Machine-local files stay
  exempt — naming this machine is their purpose. Illustration paths (`C:\Users\alice\...`,
  `D:\your-project`) are unaffected: they are not the pack folder
- **Found two real cases** on the first run, both in archived handoffs that a download would carry: a
  session opener and a copy-notes block naming the portable media root's checkout. Also genericised three
  historical evidence rows in the changelog and `WORK_QUEUE.md`
- **Handoff openers may now use a placeholder root** (`<pack folder>\docs\...`, `%PACK_ROOT%\...`,
  `$env:X\...`) instead of an absolute path. The convention existed so an opener could not be a bare
  relative path that opens the wrong file in whichever workspace is current — a placeholder root
  satisfies that, and a handoff written *for another machine* cannot name a path that exists there
  anyway. `verify-agent-handoffs.ps1` accepts both; bare relative paths stay rejected

**Method note, since it nearly cost the finding:** the first run of the new arm reported clean because
it was invoked by dot-sourcing the script into an existing session rather than with `-File`, so its
`$PackRoot` was not the value the arm compares against. The same class of mistake as the `.tmp`
exclusion bug in 2.22.56 — a check that cannot fail looks exactly like a check that passes. Invoke
verify scripts as scripts.

---

## 2.22.57 (2026-09-01)

**2.22.56 fixed the leak but could not detect its return.** Classifying the three files as
machine-local exempted them from step 50's identity scan — correctly, since a machine-local file is
*supposed* to name the machine it was written on. The consequence was a blind spot on the round trip:
the other machine's git index still holds all three from its own history, and if those tracked copies
come back, the identity arm skips them and every other arm passes. **`.gitignore` does nothing once a
file is in the index** — that is precisely how a foreign `install-manifest.json` stayed tracked while
appearing to be ignored.

- **Step 50, index arm** — fails when any `machineLocalPaths` entry is tracked, naming the remedy
  (`git rm --cached` plus staging the deletion). Proven by force-adding a generated overlay in a
  throwaway repo
- **Reads output, not exit code.** `ls-files --error-unmatch` exits non-zero both when a path is
  untracked *and* when git itself fails, so on removable media — where git refuses the repo as
  dubious ownership, which is the pack's normal habitat — every file would have read as clean. The
  arm probes `rev-parse --is-inside-work-tree` first, passes `safe.directory=*` per invocation rather
  than touching the user's config, and treats printed output as the tracked signal. Skips with an
  `[INFO]` when there is no repo, since git is an optional requirement

**What a guard cannot do:** untrack files in a repository it is not running in. The fix travels as
source; the StarterPack-Airlock's index does not fix itself. **WQ-426** carries the one-time steps.

---

## 2.22.56 (2026-09-01)

**The pack folder was carrying one maintainer's user profile path, and had committed it.** A robocopy
transfer surfaced it — the receiving machine found an agent-context stamp describing a drive it does not
have — but the copy method was not the cause. Three files held another machine's identity and two of
them were **tracked in git**, so a clone or a zip carried them just as well:

- **`docs/WORK_COMPLETION.md`** — generated by `ensure-work-completion.ps1` with `{{PROJECT_ROOT}}`
 replaced by an absolute path, committed with a user profile path in seven places, and **listed in
 `packMirror`**, so it was also copied into installs
- **`docs/AGENT_SESSION_START.md`** — written per machine by the context refresh, five absolute paths in
 the committed copy, and in **no** exclusion list: not `.gitignore`, not the export
- **`install-manifest.json`** — the *other* machine's install record (profile path, `.cursor` root, pack
 1.7.0), tracked despite being gitignored, which `.gitignore` cannot undo once a file is in the index

**Root cause: four lists disagreed about what is machine-local** — `.gitignore`, `export.ps1`,
`install.ps1`, and a hardcoded array in `verify-audit-behavior.ps1`. The export dropped files that git
tracked anyway, and nothing compared the lists. **`machineLocalPaths`** in `pack/audit/manifest.json` is
now the only list; `export.ps1` and the behavior guard read it instead of restating it, and the three
files above are untracked, gitignored, and regenerated locally.

- **`sanitize-machine-state.ps1`** — the missing piece for transfers that are not `export.ps1`. Robocopy, drag-and-drop and sync clients read no exclusion list, so this removes the manifest's machine-local set plus the wildcard classes (`docs/.audit_*`, `__pycache__`, `*.pyc`, scratch roots). Previews by default; deletes only with `-Apply`
- **Behavior step 50** — fails when a real user profile path appears in any file that travels (illustration names like `alice` and substitution markers are allowed), when a `machineLocalPaths` entry is missing from `.gitignore` or also present in `packMirror`, when `export.ps1` or the sanitizer stops reading the manifest list, and when the sanitizer's preview deletes anything
- **The freshness check now names the cause.** It trusted `canonicalProjectRoot` out of a copied stamp, resolved every path against a root that does not exist here, and reported **"missing AGENT_CONTEXT.json"** while the file sat in `docs/`. A recorded root that does not exist is ignored, and the reason reads *written on another machine for `<root>`*. Its version arm also reset `stale` to `False`, so a foreign stamp whose engine version happened to match would have read as fresh — reasons now accumulate
- **`sync-audit-system.ps1` now clears copied machine-local files from an existing install.** Dropping the overlay from `packMirror` fixed the source but stranded the copy: the profile still held `docs/WORK_COMPLETION.md` with the other machine's paths, and nothing mirrored it any more, so nothing would ever refresh it. Removed on sync, the same way maintainer-only paths are — except `install-manifest.json`, which `install.ps1` writes into its target as that install's own record
- **One prose leak, not a mechanism:** a `WORK_QUEUE.md` Done row recorded an external app path on a different host. Reworded — that file is mirrored into installs and pushed
- **A guard that could not fail.** Steps 49 and 50 excluded `.git`, `__pycache__` and `.tmp` by matching the *absolute* path, and a probe pack root lives under `.tmp` — so every file in a scratch copy was excluded and the scan passed on a tree with a planted user path. Caught by trying to make the new check fail, which is the only reason it was found. Both now match on the path relative to the pack root

**Not shipped to bootstrapped projects.** A generated overlay naming its own absolute paths is correct in
an app that lives at one location; the pack folder is portable by policy, which is what makes it wrong
here. Step 50 scans the pack folder only.

## 2.22.55 (2026-09-01)

**The reference that documented the handoff layout was not in the layout.** `HANDOFF_NEXT_AGENT.md` §11 cited
`docs/HANDOFF_DESIGN_REFERENCE.md` as "(in repo)", and the reference itself said its maintainer copy "remains" at that
path — while the only copy sat at the root of the portable media root, outside the checkout. Nothing outside the pack folder
survives a clone, an `export.ps1` archive, or a folder copy, which are the three ways this pack moves. Now written
into `docs/` and added to **`maintainerOnlyPaths`**: it describes this repo's internal layout and means nothing in a
user's profile.

- **Two factual errors corrected while copying it in.** `docs/WORK_QUEUE.md` is listed in `packMirror`, so it **does**
 install to the profile — the reference claimed the opposite. And pain point 7 (a session doc header that lags the
 queue) now records the instance that proved it: the header read "Active queue empty" while §11 and the queue both
 said **WQ-415**. Header corrected; `verify-complete-picture.ps1` reads `## 11.` and never the header, so that guard
 is unbuilt and is now a listed redesign topic rather than an unremarked hole
- **Step 47 resolves `pack/`-rooted cites only**, which is why a missing `docs/` file went unnoticed. A one-off sweep
 of every `docs/`, `scripts/` and `tests/` path cited in this repo's markdown returned 16 candidates and exactly one
 defect; the remainder are project-relative paths that generic rules legitimately name for *other* repos, so the
 sweep is not worth automating here as-is (WQ-421 tracks running that class of check inside a bootstrapped project)
- **The two ownership mechanisms contradicted each other, and adding the file proved it.** The mirror-coverage
 guard requires every `docs/*.md` to appear in `packMirror`, and knew nothing about `maintainerOnlyPaths` — so
 marking any `docs/` file maintainer-only failed the suite. Only root files had been classified that way before, and
 root is not enumerated by that guard. A maintainer-only file is exempt now because it is never installed, so it
 cannot become the stale profile copy the guard exists to catch; a path listed in **both** lists is a new failure,
 since install would skip it while sync tried to refresh it

## 2.22.54 (2026-09-01)

**WORK_COMPLETION Step 3 — close product-truth propagation gaps.** Step 3 was one table cell; agents could pass tests and archive handoffs while ROADMAP/limitation docs stayed stale (version sync does not rewrite prose).

- **`pack/docs/WORK_COMPLETION.md`** — Step 3 expanded: **3a** decide gate, **3b** channel checklist, **3c** self-verify before WQ Done, **3d** audit Improve as blocker (not backlog)
- **`pack/templates/docs/WORK_COMPLETION.md.template`** — product-truth path table for bootstrapped projects
- **`verify-complete-picture.ps1`** — **FAIL** when `docs/ROADMAP.md` links `handoffs/active/HANDOFF_WQ…` or marks **Next** / **In progress** for a WQ id already in WORK_QUEUE Done log

## 2.22.53 (2026-08-31)

**Root cleanup, and the mechanism that made it unsafe.** With the vocabulary settled, four root
documents had no remaining job: two implementation specs and the implementer notes whose work shipped,
and a transfer stub that had already been reduced to a redirect. All four deleted, along with the code
that policed them — `verify-complete-picture.ps1` no longer collects a stub it will never find, and no
longer lists two specs among its pack sources.

- **`install.ps1` `SkipRelPaths` matched exact files only**, so a `maintainerOnlyPaths` entry naming a *folder* did nothing. `docs/handoffs/` accumulates a file per work slice, and listing them one at a time guarantees the next one ships into every user's profile. A listed folder now excludes everything under it, `sync-audit-system.ps1` removes a directory entry with `-Recurse`, and **step 26** asserts both — including that skipping `docs\handoffs` does not take a same-prefixed neighbour (`docs\handoffs-notes.md`) with it
- **`HANDOFF_NEXT_AGENT.md`: 788 lines to ~470.** Roughly 400 lines were a bump-by-bump history the changelog already holds, and it had started to contradict it. What replaced it: the standing decisions in one place, and the findings that generalise past the bump that produced them. Section numbering is unchanged, because `verify-complete-picture.ps1` reads `## 11.` for the queue pointer
- **The pack's own `docs/handoffs/README.md` still said `{{PROJECT_NAME}}`** — scaffolded before 2.22.50 fixed the substitution, so this repo carried the exact defect it had shipped a guard for. Generated projects were already correct; only this copy predated the fix
- **`.cursor/rules/no-publish-from-this-machine.mdc` is now gitignored.** It tells an agent never to commit or push, which is true of default git-free copies and false in StarterPack-Airlock — committing it would instruct an agent there to refuse the push it was asked for
- **`docs/handoffs/active/HANDOFF_WQ011_primary_system_update.md`** — the pack now uses its own handoff convention for the transfer to the StarterPack-Airlock, and passes `verify-agent-handoffs.ps1`

## 2.22.52 (2026-08-31)

**One word for one concept: handoff.** The pack had been using "handoff" and "handover" as if they
were distinct terms — 519 occurrences across 56 files, 132 of them the second spelling. They are not
distinct: English treats them as synonyms and the second is simply the British-leaning form, so no
reader, human or agent, can infer a difference that the language does not carry.

- **`HANDOVER_NEXT_AGENT.md` → `HANDOFF_NEXT_AGENT.md`**, with every reference updated: `manifest.json` `maintainerOnlyPaths`, `VERSION_SYNC.json` `scanFiles` (both entries), `export.ps1`, root `AGENTS.md`, the session-start and refresh docs, and the freshness `requiredReads`
- **Two spots a blind replace would have broken, fixed by hand.** `verify-complete-picture.ps1` picked the session doc out of a source list with `-match 'HANDOVER'`; that list also holds `docs/handoffs/active/HANDOFF_WQnnn` files, so a bare `HANDOFF` match would have grabbed a work slice and then failed to find a section it never had — now `HANDOFF_NEXT_AGENT`. Step 46's banned-token table had the same shape: bare `HANDOFF` would have flagged the shipped handoff convention that rules are *supposed* to name
- **Two words the sweep left alone on purpose:** `WEEKEND_HANDOFF.md` and `PACK_IMPLEMENTER_HANDOFF.txt` were already correct
- **Step 49** fails on any reappearance of the retired synonym in `.md`, `.mdc`, `.ps1`, `.py`, `.cmd`, `.bat`, `.json`, `.txt` or `.template`. Proved by planting a stray in `docs/` — which also tripped the unmapped-doc check, so two guards caught one file
- **Its first real run failed on the documentation of its own change**, which is how the exemptions got their final shape. A total ban meant no file could record what this one used to be called, so the old **filename** `HANDOVER_NEXT_AGENT.md` stays citable while the bare word does not; a search for the old name still has to land somewhere. The changelog is exempt because it records the retirement, and the checker because a linter has to spell the word it bans
- **Glossary in `pack/docs/AGENT_HANDOFFS.md`** states the decision and the two scales it covers: one work slice (`HANDOFF_WQnnn_<slug>.md` plus registry) and one session (`HANDOFF_NEXT_AGENT.md`). Same verb, different grain

**Encoding note for whoever reads a console during this work:** the sweep rewrote 31 files by reading
and writing UTF-8 explicitly, and a byte-level check afterward found 194 valid UTF-8 files, 74 with
real em dashes and zero mojibake. Terminal output during the pass *displayed* em dashes and section
signs as garbage — that is the console codepage, not the files. Check bytes before "repairing" them.

## 2.22.51 (2026-08-31)

**The pack broke its own rule, in the layer its tests never touch:**

- **Twelve bare `pause` statements across four root launchers** - `Bootstrap-Project.cmd`, `Bootstrap-Portable-Project.cmd`, `Install-AgentStarterPack.cmd`, `Register-Tool-Adapters.cmd` - while `generic-terminal-and-build-hygiene.mdc` tells every project to gate `pause` behind `BUILD_NOPAUSE`. All now read `if not defined BUILD_NOPAUSE pause`, so a double-clicked window still stays open and an agent run never waits for a keypress
- **Why no test caught it:** every behavior step invokes the `.ps1` underneath with `-NoPause`. The `.cmd` layer is the one a human double-clicks and an agent runs, and it was never exercised. Found by running the launchers instead of the scripts they wrap - `Bootstrap-Portable-Project.cmd` printed "Press any key to continue"
- **Behavior step 48** fails on any bare `pause` in a root `.cmd`. `START_HERE.md` and the always-on rule now say an agent should set `BUILD_NOPAUSE=1` before running a launcher, the same as for a project build
- **The rest of the generator sweep came back clean:** bootstrap across 6 stack/target combinations produces no unsubstituted placeholders, no BOM and no mojibake in any file type (including `.windsurfrules`, which the step 23 include list does not cover), and every path in `.agent-bootstrap.json` exists on disk. `bootstrapVersion` is covered by `VERSION_SYNC.json` `extraReplacements`, so it cannot go stale at the next bump. Two citations that looked wrong - `docs/VERSION_SYNC.md` and `docs/PORTABLE_SETUP.md` in generated docs - are correct pack-scoped references, verified rather than "fixed"

## 2.22.50 (2026-08-31)

**Found by using the fix from 2.22.49 instead of trusting it:**

- **The handoffs README shipped with `{{PROJECT_NAME}}` in its title.** `ensure-work-completion.ps1` substitutes `{{PROJECT_NAME}}` and `{{PROJECT_ROOT}}` and writes BOM-free for `WORK_COMPLETION.md`, but plain-copied the handoffs README - a branch written when no such template existed, so nothing ever exercised it. Both paths now use the same substitution and the same writer
- **Bootstrap smoke (step 23) fails on any unsubstituted placeholder.** Same shape as the BOM assertion beside it: both catch the generator handing a user a file it half-finished. `{{[A-Z_]+}}` anywhere in the generated `.md`, `.json`, `.cmd`, `.bat`, `.py` or `.mdc` output is a failure
- Verified by bootstrapping a project and reading the file: title renders as **`# Handoffs - ProbeApp`**, no BOM, zero placeholders remaining anywhere in the tree

## 2.22.49 (2026-08-31)

**A rule's wording was checked; its advice was not:**

- **`ensure-work-completion.ps1` copied a template that never existed.** It creates the `docs/handoffs/` scaffold for a project and then copies `pack\templates\docs\handoffs\README.md.template` - a file no one ever wrote. The copy sits behind `Test-Path`, so the promised README simply never appeared, no error was raised, and `pack/docs/AGENT_HANDOFFS.md` advertised that template plus `HANDOFF_BUILD.md.template` in its pack-files table. Both templates now exist and are in `packMirror`: the README explains the folder and the status/WORK_QUEUE invariant, the build starter carries the registry table, the absolute-path opener and an acceptance checklist that ends in "WQ row moved to Done"
- **Behavior step 47 resolves every `pack/`-rooted path cited by rules, skills and pack docs.** Only `pack/` paths: a doc naming `docs/ROADMAP.md` or `scripts/apply_version.py` is describing the reader's project, not this pack, and flagging those would make the check noise. Changelogs are excluded because describing a file that has since been renamed is their job
- **Three exclusions the discovery run earned.** A second extension after the first is not a match (`pack/templates/x.md.template` was reading as a missing `x.md`, and `.jsonl` as a missing `.json` - six phantom findings on the first pass); a line whose point is that a file *must not* exist is skipped, so `AUDIT_SYSTEM.md`'s "orphan `pack/templates/AUDIT.md.template` is forbidden" stays legal; globs and placeholders are skipped. Bare `.mdc` names are deliberately **not** resolved - `PACK_MAINTENANCE.md` lists `agent-readiness.mdc` and four others under **Project-only rules (never in pack)**, and a checker that cannot tell those from a pack rule would report the doc for being right

## 2.22.48 (2026-08-31)

**The rules scan's findings, closed mechanically instead of by memory:**

- **Behavior step 46 fails when a shipped rule describes this repo** (WQ-209) - `WQ-\d+`, `HANDOFF`, `WEEKEND_HANDOFF`, pack-only spec and plan names, `Phase 6x`, and section numbers like `§11`. A line may still name pack internals when it carries a scope marker (**Agent Starter Pack maintainer repo:**, **Maintainer pack**, or a **Pack maintenance** section), because the difference between guidance for every project and a note for the maintainer is the marker, not the reader's charity. Case-**sensitive** on purpose: a rule may say "the handoff's status section" in plain English, but naming `HANDOFF_NEXT_AGENT.md` points at a file only this repo has. `generic-work-queue-discipline.mdc` is exempt from the id ban - it owns the id convention, so its `WQ-001` examples are the subject matter
- **It immediately found 11 more leaks that reading had missed** - `§11` and `§5` cross-references, `HANDOFF*.md` in a doc-pattern list, and an instruction to overwrite `HANDOFF_NEXT_AGENT.md` given to every project. All reworded to name sections rather than number into documents the reader may not have
- **Terminal hygiene now has one owner per job** (WQ-207) - `generic-terminal-and-build-hygiene.mdc` is build hygiene (prompt gating, exit codes, reading output) and opens by saying what it does *not* cover; diagnosis stays in skill `agent-terminal-hygiene`; the before/after sequence stays in `agent-defaults-always.mdc`, which is the copy that actually loads. The queue row claimed this would cut the always-on budget - it does not, the duplication lived in a rule that never auto-loads, and the real gain is that three copies can no longer drift apart
- **One audit trigger list** (WQ-208) - canonical in `audit-protocol.mdc`, repeated verbatim in `agent-defaults-always.mdc` and the pack's own `audit.mdc`. Before this, "find problems" reached only one of the three surfaces

## 2.22.47 (2026-08-31)

**Rules that shipped this repo's private state to every project:**

- **`generic-deep-task-execution.mdc` no longer names WQ-301/302, phase 6b/6c, `HANDOFF` §1/§8/§11 or `WEEKEND_HANDOFF`.** Those lines told an agent in a bootstrapped app to check a work item, a phase number and two doc sections that do not exist there. The contract they encoded is real and stays - separate the tracks, keep deferred work on the list, do not close one track because a neighbour shipped - now stated in terms any project can satisfy. Source inventory (step 1) likewise says "every agent-doc folder the project uses" instead of `pack/docs/`, and the grep list ends in "the project's own recurring qualifiers" rather than this pack's
- **`generic-agent-doc-hygiene.mdc`** loses "Phase 6b not built" and the unscoped `docs/MULTI_TOOL_GAP_PLAN.md` cite; the maintainer-only step keeps its **Agent Starter Pack maintainer repo:** prefix, which is what made the neighbouring `INSTALL.txt` line acceptable all along
- **The agent's brief was corrupting itself, one audit at a time.** `Update-AgentManifest` re-read `docs\.audit_agent_manifest.json` with `Get-Content -Raw` and no `-Encoding UTF8`, so PowerShell 5.1 decoded a BOM-less UTF-8 file as ANSI, turned every em dash into three characters, and wrote them back as UTF-8 - compounding on each run. All five JSON reads in `run_audit_core.ps1` are pinned now, matching the fix the domain-map read already had. **Behavior step 45** copies the fixture, puts an em dash in a checklist bullet, runs the audit and fails if the manifest lost it or doubled it - the artifact is asserted, not the plumbing, because the first attempt at this fixed the wrong layer (the Python pipe, which was already ASCII-escaped and clean)
- **`agent-defaults-always.mdc` gains a Session start section.** All five tool entry templates tell agents to read `docs/AGENT_SESSION_START.md` on the first turn and no rule did, so a project bootstrapped before that template - or one with a hand-edited `AGENTS.md` - never heard about the file the freshness system writes. Four lines in the always-on rule rather than a thirteenth rule file, per the pack's own extend-over-duplicate guidance

## 2.22.46 (2026-08-31)

**The engine now passes the rule it enforces:**

- **`audit_code_checks.py` 2592 → 2174 LOC** against its own 2500 ceiling. Two groups moved out whole, no behavior change: **`audit_version_docs.py`** (Section M cites - audit engine, pack release, app docs, changelog) and **`audit_install_wiring.py`** (the checks that read *outside* the repo: installed-vs-source, `mcp.json`, reference templates). **`audit_common.py`** holds the four primitives all three need - config, repo root, canonical version, manifest version - so the modules do not import each other in a circle
- **Public surface unchanged** - the moved names are re-exported from `audit_code_checks`, because `run_audit_core.ps1` and the self-test call them by name; a test asserts all nine stay reachable, and another fails if the engine creeps back over the threshold
- **`doc_version_sync.py` untouched** - it keeps its own copy of `resolve_repo_root` and the version regexes on purpose (build pipeline must not depend on the audit engine); behavior step 23 still asserts the copies agree
- Three new production modules means three new domain-map rows, mirror entries and real tests - the split closes the Improve without opening a Section B orphan or a Section D test gap
- **`maintainerOnlyPaths` takes nested paths too** - a workspace rule describing one machine's publishing policy has no business in someone else's install, even sitting inert inside the copied tree

## 2.22.45 (2026-08-31)

**Tests that graded the machine instead of the pack, and a failure that said nothing:**

- **`agent_context_freshness.py`** — honours **`AGENT_STARTER_PACK_INSTALL_ROOT`**, which PowerShell has read since 2.22.4. Python resolving the install straight from `%USERPROFILE%` made the freshness verdict a property of the developer's profile: behavior **step 38** passed where the install happened to match the source pack, passed on a machine with no install at all, and failed on one carrying an older install. Same fix in **`audit_code_checks.py`** for the installed-vs-source check, and its `mcp.json` lookup now follows the override's user root
- **Step 38 is hermetic and proves both directions** — the probe builds its own scratch install to compare against, then repeats the check against an install one version behind and requires the verdict to flip. Previously a probe that found no install to compare against would have satisfied every assertion. It also sets `AGENT_STARTER_PACK_ROOT` for the generated Cursor hook, which otherwise ran the *installed* pack's freshness module rather than the code under test
- **`verify-audit-system.ps1` printed failures with no reason** — the sync and behavior children were invoked without `-PassOutput`, so a red run ended at `Summary: 1 fail(s)` with no `[DRIFT]` line above it and no remedy. Both now stream their output and emit a `Fail` naming what to run. Locked in by new behavior **step 44**
- **`maintainerOnlyPaths`** (manifest) — `install.ps1` copies the whole checkout, so session handoffs and implementation specs were landing in every user's profile, while `README.md`, `INSTALL.md`, `CHANGELOG.md`, `INSTALL.txt`, `VERSION` and `install_launcher.py` shipped *without* being mirrored and could only be refreshed by a full re-install. Root docs are now mirrored, maintainer notes are skipped by install and deleted from existing installs by sync, `.zip` release artifacts no longer ship, and a new guard requires every root file to be one or the other

## 2.22.44 (2026-08-31)

**Doc hygiene widen + enforce (no new rule):**

- **`generic-agent-doc-hygiene.mdc`** — maintainer entry docs in scope; forbid parallel `STICK_*` / `*_INSTALL.txt`; delete redundant copies when consolidating
- **`verify-complete-picture.ps1`** — pack repo: INSTALL.txt vs VERSION, WEEKEND redirect stub, no parallel install docs, HANDOFF must not primary-point WEEKEND
- **Doc consolidation:** `INSTALL.txt` / `INSTALL.md` / `HANDOFF` / `WEEKEND_HANDOFF` redirect; `INSTALL.txt` in `VERSION_SYNC.json`

## 2.22.43 (2026-08-30)

**Hygiene batch (WQ-413):**

- **`VERSION` → 1.8.0** + `CHANGELOG.md`; maintainer doc sync targets refreshed
- **`AGENT_CHAT_SYNC.md` deleted** — superseded by refresh pipeline
- **`HANDOFF_NEXT_AGENT.md` §6** — pointer-only (removed stale 2.22.4 block)
- **`verify-work-queue.ps1`** — allow empty Active **Next** when header says `(none)`
- **`update-agent-stack.ps1`** — runs **`verify-complete-picture.ps1`** on maintainer pack after refresh
- **`generic-agent-handoff-discipline.mdc`** — completion defers to **`WORK_COMPLETION.md`** (removed duplicate checklist)
- **`docs/VERSION_SYNC.json`** — **`docs/WORK_QUEUE.md`** in maintainer doc sync + table `extraReplacements` (S2-9)
- **`verify-work-queue.ps1`** — header **Pack version** / **Audit engine** vs `VERSION` + manifest

---

## 2.22.42 (2026-08-30)

**Rules / verify consolidation (status drift prevention):**

- **`pack/docs/RULES_AND_VERIFY_MAP.md`** — inventory of rules vs verify scripts, overlaps, prevention vs detection, canonical status propagation
- **`generic-work-queue-discipline.mdc`** — propagate status to all derivative docs + run `verify-complete-picture.ps1` on Done/Parked
- **`generic-agent-doc-hygiene.mdc`** — §6 after-ship status alignment (distinct from version sync)
- **`generic-agent-handoff-discipline.mdc`** — completion checklist defers to `WORK_COMPLETION.md` + map (less duplication)
- **`verify-complete-picture.ps1`** — scans more pack handoff sources; generic Done-WQ vs parked/not-built patterns for any Done id

---

## 2.22.41 (2026-08-30)

**Handoff / WQ alignment (post-ship doc hygiene):**

- **`verify-complete-picture.ps1`** — when a WQ id is in **Done log**, **FAIL** handoff/spec files that still say that slice is parked, not built, or deferred (WQ-301 / WQ-308 rules; changelog + WORK_QUEUE excluded)
- **`pack/docs/WORK_COMPLETION.md`** — step **5b**: run complete-picture verify after moving WQ to Done
- **Docs aligned:** Phase ID map in `docs/MULTI_TOOL_GAP_PLAN.md`; stale 6b/308 parked text removed from HANDOFF, WEEKEND_HANDOFF, PACK_IMPLEMENTER_SPEC, AGENT_COORDINATION_BACKLOG, AGENT_UPGRADE_PATH, AGENT_FRESHNESS_ADAPTER_PLAN
- **Spec field names:** Phase 6b MCP return shape uses shipped `installedEngineVersion` / `stampedEngineVersion` (not design-era `desktopVersion`)
- **`generic-deep-task-execution.mdc`** track **(F)** — deferred = **6c / WQ-302** only

---

## 2.22.40 (2026-08-30)

**Linux CI probe fix:**

- **`Invoke-PackScript`** — capture exit code without stdout pipeline (Linux `$LASTEXITCODE` loss)
- **`test-os-portability-probe.ps1`** — native Linux uses PATH python; absolute `-PythonCommand` only for mock

---

## 2.22.39 (2026-08-30)

**Linux CI probe fix:**

- **`Resolve-PackPythonInvoke`** — accept absolute `PythonCommand` paths (Linux CI passes `sys.executable`; `Get-Command` missed it)

---

## 2.22.38 (2026-08-30)

**Linux CI path fixes (WQ-304 / pack-os-smoke):**

- **`Get-PackManifestPath` / `Get-PackScriptPath`** in `pack-paths.ps1` — forward-slash-safe joins for manifest and script paths
- **`check-requirements.ps1`** — audit engine self-test path uses helper (fixes ubuntu CI probe)

---

## 2.22.37 (2026-08-30)

**OS portability Phases 5–6 (WQ-304):**

- **`Test-PackIsWindows`** — test-only `AGENT_STARTER_PACK_TEST_OS` hook for mock non-Windows probes on Windows hosts
- **`pack/scripts/test-os-portability-probe.ps1`** — HOME/.cursor resolution, pwsh path, preflight launcher optional, `Invoke-PackScript` smoke
- **Behavior step 43** — mock Linux portability probe
- **`docs/PORTABLE_SETUP.md`** — verified cross-host matrix
- **`.github/workflows/pack-os-smoke.yml`** — optional `ubuntu-latest` + `pwsh` CI smoke

---

## 2.22.36 (2026-08-30)

**OS portability Phase 4 (WQ-304):**

- **`pack/scripts/pwsh-wrap.sh`** — shared `pwsh` require + exec helper
- **Root `.sh` entry points:** `Refresh-AgentContext.sh`, `Bootstrap-Project.sh`, `Check-Requirements.sh`, `run_audit.sh` (plus existing `install.sh`)
- **`docs/PORTABLE_SETUP.md`** — cross-host entry point matrix updated
- **Behavior step 42** — `.sh` wrapper smoke

---

## 2.22.35 (2026-08-30)

**OS portability Phase 3 (WQ-304):**

- **`Resolve-PackPythonInvoke`** + install-fix helpers in `pack-paths.ps1` (`Get-PackPythonInstallFix`, etc.)
- **`check-requirements.ps1`** — `python3` first off Windows; `py -3` launcher required Windows-only; cross-platform fix hints
- **`doctor.ps1`** — `Get-AgentStarterPackUserRoot` / `Get-DefaultCursorUserRoot`; MCP smoke uses resolved Python
- **Behavior steps 21 (OS-aware) + 41** — preflight/doctor scope gates

---

## 2.22.34 (2026-08-30)

**OS portability Phase 2 (WQ-304):**

- **`Invoke-PackScript`** — `-PassOutput`, `ValueFromRemainingArguments` for script params; quiet mode returns exit code
- **Core scripts** — nested spawns routed through helper (install, refresh, bootstrap, sync, verify-*, run_audit_core, update-agents/stack, repair, adapters, archive, behavior suite)
- **Intentional exceptions** — DualShell + step 29 cross-host parity still invoke `$otherShell.Source` directly; hook JSON string in `install.ps1`

---

## 2.22.33 (2026-08-30)

**OS portability Phase 1 (WQ-304):**

- **`pack-paths.ps1`** — `Test-PackIsWindows`, `Get-DefaultCursorUserRoot`, `Get-PackPowerShellPath`, `Invoke-PackScript`; cross-platform `$HOME/.cursor` user root
- **`install.sh`** — full install via `pwsh -File install.ps1` when PS 7 is present (no partial copy-only path)
- **`install.ps1`** — post-install sync uses `Invoke-PackScript`
- **`docs/OS_PORTABILITY_PLAN.md`** — phased checklist (Phases 2–6 remain)
- **`docs/PORTABLE_SETUP.md`** — WQ-304 active; honest Windows-first entry points until Phase 4
- **Behavior step 40** — shell helper + `install.sh` delegation smoke

---

## 2.22.32 (2026-08-30)

**Hub repair preserve + rollout:**

- **`repair-agent-docs.ps1`** — skips rewriting **`AGENTS.md`** when project-specific markers detected (`PRODUCT_REFERENCE.md`, `AGENT_READINESS.md`, `bsod_analyzer.py`, etc.)
- **`AI_INSTRUCTIONS.md.template`** — execute/verify cites project-local `docs/portable/GENERIC_RULES.md` first

---

## 2.22.31 (2026-08-30)

**Multi-model hub coverage (WQ-308 Phase D3) — repair + verify + portable project copy:**

- **`repair-agent-docs.ps1`** — refreshes `AI_INSTRUCTIONS.md` / `AGENTS.md` when hub patterns missing; syncs **`docs/portable/GENERIC_RULES.md`** + skill mirrors; runs **`register-tool-adapters -Repair`**
- **`refresh-agent-context.ps1`** — calls repair after audit template sync (existing projects pick up template changes)
- **`bootstrap-project.ps1`** — calls repair at end (portable bootstrap always gets project-local rules)
- **`agent_context_freshness.py`** — session-start markdown includes execute/verify one-liner
- **`verify-portable-bootstrap.ps1`**, **`verify-agent-setup.ps1`** — hub pattern + portable copy + session-start checks
- **Behavior step 39** — repair probe + VerifyOnly gate
- **`docs/PORTABLE_SETUP.md`** — PS 7 cross-host vs Windows entry-point scope clarified

---

## 2.22.30 (2026-08-30)

**Agent freshness adapter Phase D2 (WQ-308) — Cursor sessionStart hooks:**

- **`pack/templates/cursor/hooks.json.template`** + **`session-freshness.ps1`** — inject `additional_context` from `agent_context_freshness.py`
- **`bootstrap-project.ps1`** — `-Targets Cursor` writes `.cursor/hooks.json` + hook script
- **`install.ps1 -InstallSessionHooks`** — optional user-level hook under `%USERPROFILE%\.cursor\hooks\`
- **Behavior step 38** — bootstrap hook files + stdout JSON smoke

---

## 2.22.29 (2026-08-30)

**Agent freshness adapter Phase D1 (WQ-308):**

- **`agent_context_freshness.py`** — `--session-brief`, `--write-session-start`; builds `docs/AGENT_SESSION_START.md`
- **`invoke-agent-freshness.ps1`** — wrapper for hooks/CLI (`-SessionBrief`, `-WriteSessionStart`, `-PrintOpener`)
- **`refresh-agent-context.ps1`** — writes session-start file after refresh
- **Templates** — `AI_INSTRUCTIONS.md`, `AGENTS.md`, gitignore snippet cite session-start file
- **Behavior step 38** — session-brief JSON + file write smoke

---

## 2.22.28 (2026-08-30)

**Handoff archive Done-log parse (WQ-305 follow-up):**

- **`Get-SectionBody`** (archive, handoffs, work-queue, complete-picture) — end markers match at line start only; fixes false truncate on markdown table `|---|` rows (behavior step 36)

---

## 2.22.27 (2026-08-30)

**Behavior suite follow-up (WQ-305):**

- **`behavior-fixture/hardware_cache.py`** — restore stub on disk (domain map listed it after `catalog_cache.py` removal; steps 8/10 failed on missing module)
- **`verify-audit-behavior.ps1`** — always dot-source `pack-paths.ps1` (fixes `Write-Utf8NoBom` when `-PackRoot` is passed)

---

## 2.22.26 (2026-08-30)

**Import smoke + behavior-suite fixes (WQ-305):**

- **`audit_code_checks.py`** — import smoke scans `domainMap.moduleSearchDirs` (and optional `importSmoke.searchDirs`), not only root `*.py`
- **`bootstrap-project.ps1`** — fix `$PackDir` / `ensure-work-completion.ps1` path (exit 0; behavior steps 23/33/34)
- **`archive-completed-handoff.ps1`** — trim registry values; resolve verify script via `pack-paths.ps1`
- **Behavior fixture** — drop removed `catalog_cache.py` from domain map + manifest
- **`verify-audit-behavior.ps1`** — steps 2/12/36 aligned; manifest tracks `audit_allowlist.json.template`

---

## 2.22.25 (2026-08-30)

**machineCoverage + complete-picture handoff verify (WQ-204, WQ-206):**

- **`audit_code_checks.py`** — `domain map module existence` in `machineCoverage` only for domain-map sections that list modules (not empty D–K)
- **`verify-complete-picture.ps1`** — inventories handoff sources, scans pending-work keywords (INFO), flags stale HANDOFF section 11 vs `docs/WORK_QUEUE.md` (Improve in audit mode)
- **`verify-agent-setup.ps1`** — runs complete-picture verify on pack + reference project
- **`verify-audit-behavior.ps1` step 37** — pack repo passes; probe proves stale phrase detection

---

## 2.22.24 (2026-08-30)

**Work completion + safe handoff archive (preview default):**

- **`pack/docs/WORK_COMPLETION.md`** — three cleanup channels (Fix vs Improve vs work completion); forbidden bulk deletes
- **`archive-completed-handoff.ps1`** — **preview by default**; **`-Apply`** required to move; gates: completed date, WQ Done, verify handoffs, no overwrite unless `-Force`
- **`ensure-work-completion.ps1`** — creates `docs/WORK_COMPLETION.md` + handoffs scaffold when missing (never overwrite)
- **`verify-audit-behavior.ps1` step 36** — proves preview never moves; `-Apply` refuses active/incomplete; moves only when all gates pass
- **`refresh-agent-context.ps1` / `bootstrap-project.ps1`** — call ensure-work-completion
- **`verify-agent-setup.ps1`** — checks WORK_COMPLETION + archive script present; ensure on reference project
- **`verify-agent-handoffs.ps1`** — session opener must use full absolute path

---

## 2.22.22 (2026-08-30)

**Agent handoff discipline + audit verification (no auto-delete):**

- **`generic-agent-handoff-discipline.mdc`** — one session opener per handoff; multi-agent `agents_remaining`; PC-local exempt paths unchanged
- **`pack/docs/AGENT_HANDOFFS.md`** — folder layout (`docs/handoffs/active/`), registry table, lifecycle
- **`verify-agent-handoffs.ps1`** — registry/WQ reconciliation; **Improve** when archive-safe (completed + Done log + empty `agents_remaining`); **Fix** when status/WQ drift
- **`run_audit_core.ps1`** — invokes handoff verify in machine phase (Improve/Fix only; never deletes files)
- **`verify-agent-setup.ps1`** — optional handoff check on reference project
- **`generic-work-queue-discipline.mdc`** — completing WQ updates handoff status before audit archive

---

## 2.22.21 (2026-08-30)

**Agent upgrade path Phases A–C (WQ-306, WQ-301, WQ-307):**

- **`docs/AGENT_CONTEXT.json` schema v2** — `canonicalProjectRoot`, absolute `requiredReads`, `triggerPhrases`, `handshake`
- **`docs/AGENT_UPGRADE_PATH.md`** — tool-neutral install → refresh → open-chat steps
- **`Update-AgentStack.cmd`** — optional `-Install` + project refresh + remediation printout
- **`pack/scripts/agent_context_freshness.py`** — shared freshness logic; **`--self-test`**
- **MCP `check_pack_freshness`**, **`get_agent_refresh_brief`** on agent-hygiene server
- **Behavior step 35** — Python self-test + MCP tool presence + Update-AgentStack entry point
- **`AI_INSTRUCTIONS.md.template`**, **`agent-defaults-always.mdc`** — v2 contract + MCP + handshake

**Phase D (Cursor session hooks)** — parked WQ-308; not in this release.

---

## 2.22.20 (2026-08-29)

**Sections H/I semantic hardening (WQ-202) + doc cite (WQ-205):**

- **`semanticChecklistPathSections`** extended to **H** and **I** — template and maintainer doc paths require `modulesReviewed[]`
- **`docs/AUDIT.md`** — PS LOC cite ~4,900 lines; explicit H/I checklist paths

---

## 2.22.19 (2026-08-29)

**Section E semantic hardening (WQ-201):**

- **`semanticChecklistPathSections`** in `AUDIT.config.json` — pack Section **E** requires `modulesReviewed[]` for every checklist file path
- **`parse_checklist_paths`**, **`verify_checklist_paths_reviewed`** in `audit_code_checks.py`
- **`agent-code-audit` skill** — Section E checklist paths called out explicitly

---

## 2.22.18 (2026-08-29)

**Multi-tool Phase 4 — per-tool register adapters (WQ-003):**

- **`register-tool-adapters.ps1`** — verify/repair Claude, Copilot, Windsurf project files; optional `-InstallMcp` for Claude Desktop
- **`Register-Tool-Adapters.cmd`** — one-click wrapper
- Behavior **step 34**; **`verify-agent-setup.ps1`** runs adapter verify when `-ReferenceProjectRoot` set

---

## 2.22.17 (2026-08-29)

**Multi-tool Phase 3 — Portable bootstrap guidance (WQ-003):**

- **`Bootstrap-Portable-Project.cmd`** — one-click `-Targets Portable`
- **`verify-portable-bootstrap.ps1`** — required files, GENERIC_RULES cite, no orphan editor files on Portable-only; wired into **`verify-agent-setup.ps1`** and behavior **step 33**
- **`docs/PORTABLE_SETUP.md`**, **`new-project-bootstrap.mdc`** — choose `-Targets` table

---

## 2.22.16 (2026-08-29)

**Multi-tool Phase 2 — portable markdown exports (WQ-003):**

- **`sync-portable-docs.ps1`** — exports `pack/docs/portable/GENERIC_RULES.md` + `skills/*.md` from `pack/rules` and `pack/skills`; `-VerifyOnly` for drift
- Wired into **`sync-audit-system.ps1`** (maintainer repo) and behavior **step 32**
- **`docs/PORTABLE_SETUP.md`**, **`AI_INSTRUCTIONS.md.template`**, bootstrap next-steps updated

---

## 2.22.15 (2026-08-29)

**Work queue automation (backfill + hard verify):**

- **`ensure-work-queue.ps1`** — creates `docs/WORK_QUEUE.md` from template when missing; called from **`refresh-agent-context.ps1`**
- **`verify-work-queue.ps1`** — required sections, unique WQ IDs, exactly one **Next**, Done vs open reconciliation; wired into **`verify-agent-setup.ps1`** and behavior **step 31**
- **Template** — ships valid placeholder `WQ-001` **Next** so new projects pass verify immediately

---

## 2.22.14 (2026-08-29)

**Work queue reprioritization (explicit):**

- **`generic-work-queue-discipline.mdc`** — **When reprioritizing** section: reorder Active rows for dependencies/blockers; reconcile all WQ IDs before/after; forbid deleting rows without Done/Parked/Superseded
- **`AI_INSTRUCTIONS.md.template`** — tool-neutral read-first + non-negotiable for `docs/WORK_QUEUE.md`
- **`new-project-bootstrap.mdc`** — layout includes `docs/WORK_QUEUE.md`

---

## 2.22.13 (2026-08-29)

**Work queue discipline (nothing slips off the radar when priorities change):**

- **`generic-work-queue-discipline.mdc`** — always-on rule: stable WQ IDs, Inbox triage, Done log, one Next; update `docs/WORK_QUEUE.md` before rewriting chat/handoff lists
- **`pack/templates/docs/WORK_QUEUE.md.template`** — bootstrapped with every project; **`docs/ROADMAP.md`** stays product-only
- **`docs/WORK_QUEUE.md`** — pack maintainer canonical queue; **`docs/MULTI_TOOL_GAP_PLAN.md`** — WQ-003 Phase 1 parity matrix
- **`bootstrap-project.ps1`** — copies `WORK_QUEUE.md` from template

---

## 2.22.12 (2026-08-29)

**Complete-picture contract for agent analysis (closes shallow handoff/doc reviews):**

- **`generic-deep-task-execution.mdc`** — new **complete picture** contract: inventory all handoff sources, grep pending-work patterns, separate OS vs tool/model vs audit vs git tracks, cross-check user callouts
- **`HANDOFF_NEXT_AGENT.md` §11** — multi-tool / reduce Cursor dependency restored as active track; OS portability split out

## 2.22.11 (2026-08-29)

**Merger integration — deep task execution rule (from Desktop session):**

- **`pack/rules/generic-deep-task-execution.mdc`** — mandatory depth contracts for deep compare, full scan, and exhaustive requests; forbids deflecting to user phrasing
- **`agent-defaults-always.mdc`**, **`loop-back-protocol.mdc`** — pointers and pushback triggers
- Merged the **transfer-drive checkout** (2.22.10) with Desktop-only docs (`PHASE_6_IMPLEMENTATION_SPEC.md`, `AGENT_CHAT_SYNC.md`)

## 2.22.10 (2026-08-28)

**`mcp/agent_hygiene_server.py` mirrored - sixth and last known instance of the unmirrored hole.** Found
by asking which class of shipped file had not been enumerated yet, rather than waiting for the next
symptom. This one mattered more than most: it is the server `install.ps1` writes into `mcp.json`, so a
stale copy in the profile is a stale MCP server for every agent on the machine. Step 5b now enumerates
`mcp/*.{py,json}` as well.

Enumerated classes are now rules, skills, `pack/docs` + repo `docs/*.md`, `pack/scripts/*.{ps1,py}`, all
of `pack/templates`, root `*.{cmd,bat,ps1,sh}`, and `mcp/`. A seventh class is still possible - the
lesson from six repeats is that the test must enumerate a directory, never list filenames.

---

## 2.22.9 (2026-08-28)

**The unmirrored hole, fifth and outermost appearance: the root entry points.** `install.ps1` copies the
repo root into the profile, so a user gets `Refresh-AgentContext.cmd`, `Bootstrap-Project.cmd`,
`Update-AgentRules.cmd` and the rest - but only two of them were in
`packMirror`. Every other wrapper was write-once: fixed in the pack, stale in the profile forever. (The
two that were tracked are `run_audit.cmd` and `run_audit_tests.bat`.) Found
while fixing the wrapper below, which would itself never have reached an installed copy.

- **Eleven root entry points added to `packMirror`**, and step 5b now enumerates root
  `*.cmd`/`*.bat`/`*.ps1`/`*.sh` the same way it enumerates rules, skills, docs, scripts and templates.
- **`Refresh-AgentContext.cmd` accepts a leading switch.** `Refresh-AgentContext.cmd -NoClipboard` bound
  `-NoClipboard` to `-ProjectRoot` and died with *"Missing an argument for parameter 'ProjectRoot'"*.
  A leading `-` now passes straight through; a first argument without one is still the project root.
- **`refresh-agent-context.ps1` no longer claims the clipboard was "UNAVAILABLE" when `-NoClipboard`
  asked it to skip.** A false status line in the tool people run to clear up confusion is the last place
  to have one.

---

## 2.22.8 (2026-08-28)

**2.22.7's instruction only reached Cursor.** The audit line is tool-neutral and carries its own
remediation, but the behaviour around it - offer the run, wait for approval, read the brief in the same
turn - was written into `pack/rules/agent-defaults-always.mdc` only. That is a `.mdc`, which no tool
but Cursor reads, and `AI_INSTRUCTIONS.md` is the pack's own universal entry point. So a Claude, Copilot
or Windsurf agent saw the audit line with none of the surrounding behaviour, in a pack whose whole point
is being tool-neutral.

- **The offer-to-run instruction now lives in `AI_INSTRUCTIONS.md.template` and
  `AGENTS.md.template`** as well as the Cursor rule. `CLAUDE.md`, `copilot-instructions.md` and
  `.windsurfrules` already delegate to those two, so they inherit it without duplicating text.
- **Step 30 asserts all three carriers**, naming which layer is missing when one is. A test that only
  checked the `.mdc` is what let a Cursor-only feature look finished.
- **The instruction states the mechanism generically:** any agent host that can run a shell command with
  user consent can do this - approving a proposed command is the entire interaction. No editor-specific
  UI is assumed.

---

## 2.22.7 (2026-08-28)

**Staleness now finds the user, and the agent does the work.** The refresh brief existed since 2.21.23,
but nothing told anyone it had gone stale — the only way to learn was to run the refresh, which is what
the warning would have told you to do. Spec §4.10 proposed putting the warning in
`verify-agent-setup.ps1`; that is another command you must remember to run, so it would only have spoken
up in a session where you were already looking.

- **The audit reports it.** `run_audit_core.ps1` reads `docs/AGENT_CONTEXT.json` and emits an **Improve**
  when `auditEngineVersion` is behind the engine running the audit, or when the stamp is a never-refreshed
  stub or unparseable. Improve, not Fix — nothing is broken. Silent when the project has no stamp or a
  current one, so it clears itself and cannot become wallpaper.
- **The remediation is addressed to the agent, not the user:** *offer to run `Refresh-AgentContext.cmd`
  for this project, then read `docs/AGENT_REFRESH.md`*. `agent-defaults-always.mdc` carries the matching
  instruction, so the user approves a run rather than copying a command — the friction that let projects
  go stale in the first place. The audit still only reports; it never mutates.
- **Bootstrap stamps the engine version it generated from.** The stub previously left
  `auditEngineVersion` null, which made every brand-new project open with this Improve while a genuinely
  old project stayed just as quiet. Caught by the bootstrap smoke tests before it shipped.
- **Step 30** asserts both directions: fires when the stamp is behind, names the engine it is behind,
  lands in Improve rather than Fix, uses the offer-to-run wording, and stays silent on a current stamp or
  no stamp at all. It also asserts the rule still carries the offer instruction, since an audit line with
  no one instructed to act on it is just text.

---

## 2.22.6 (2026-08-28)

**The unmirrored-file hole reached the machinery, not just the docs.** An independent pass over
`PACK_IMPLEMENTER_SPEC.md` confirmed both assigned tracks were complete, and its small parity findings
led here.

- **`bootstrap-project.ps1`, `doctor.ps1`, three hygiene scripts, and all nine project templates joined
  `packMirror`** (14 files). This is the same defect as 2.22.5 but with sharper teeth: bootstrapping
  *from the installed pack* is the documented normal path, so after a second pack update a new project
  would have been generated from the first update's templates - `AGENTS.md`, `AI_INSTRUCTIONS.md`,
  `CLAUDE.md`, the Copilot and Windsurf files, the version-sync rule. `doctor.ps1` was in the same
  state while the handoff tells you to run it out of the profile. Behavior step 5b now enumerates
  `pack/scripts/*.{ps1,py}` and all of `pack/templates`, so a new script or template is covered the
  moment it is created rather than when someone notices.
- **`AI_INSTRUCTIONS.md.template` carries all four refresh trigger phrases.** It listed three of the
  four in `agent-defaults-always.mdc`, so a non-Cursor agent would not have recognised
  **sync agent context**.
- **`.agent-bootstrap.json` no longer claims `docs/AGENT_REFRESH.md`.** Bootstrap never wrote it - the
  brief is generated by `Refresh-AgentContext.cmd` and is only meaningful once there is a real delta,
  so a stub would state nothing while looking authoritative. The manifest now lists only what bootstrap
  actually produced.
- **`PACK_IMPLEMENTER_SPEC.md` no longer contradicts itself.** Its Section 12 header still read
  "Not implemented" and its implementer checklist read as open work, four bumps after both shipped.

---

## 2.22.5 (2026-08-28)

**Handoff documents that contradicted themselves, and the unmirrored-file trap for the third time.**
Prompted by a plain question - is anything still missing from the handoff docs - answered by checking
each claim against the code instead of re-reading the prose.

- **`pack/docs/*.md` and `docs/*.md` are enumerated against `packMirror`** in behavior step 5b. Six
  files were in the state this check already covered for rules and skills: `install.ps1` copies the
  whole tree, so they reach a *fresh* install and are then frozen, because incremental syncs only walk
  manifest paths. An agent reading the installed copy would have been told the context refresh was
  "planned, not built", and `bootstrap-project.ps1` prints a path into the installed `docs\` folder, so
  a user could be sent to a stale `PORTABLE_SETUP.md`. All six are now mirrored, and the check
  enumerates both folders so a new doc is covered the moment it is created. `docs/AGENT_REFRESH.md` is
  excluded by name: it is generated per machine, so mirroring it would push one machine's absolute
  paths into the install.
- **`HANDOFF_NEXT_AGENT.md` joined `maintainerDocSync`** in `docs/VERSION_SYNC.json`. Its version
  cites were hand-maintained, and one had already drifted (the key file map still said 2.22.0). Adding
  it was verified safe first: the sync rewrote exactly that one line and left every historical version
  reference in the narrative alone.
- **Seven stale or self-contradicting claims corrected in the handoff**, each re-checked against code
  rather than assumed: the context refresh described as unimplemented in one section and shipped in
  another; a "still never prunes" note fixed in 2.21.22; a dead-code item deleted in 2.21.19; the MCP
  SDK reported absent after it was installed; `sync-project-rules.ps1` described by its old hardcoded
  rule count; a stated preference of "no install on this machine" that the user had since lifted; and
  no narrative at all for 2.22.1 through 2.22.4.
- **The machine-local rule boundary is now written down.** A rule in the profile that the pack does not
  ship belongs to the *user* - it must not be added to `pack/rules/` and must not be pruned. That
  distinction lived only in `update-agents.ps1` logic and in one chat.

---

## 2.22.4 (2026-08-28)

**The export shipped one machine's identity, and the installer ignored the one override that keeps
tests off a real profile.** Both were found by taking the portability claim literally: export the
pack, unzip it somewhere else, and run it as a receiving machine would.

- **`export.ps1` no longer ships the agent-context stamp.** `docs/AGENT_CONTEXT.json`,
  `docs/AGENT_REFRESH.md` and `docs/AGENT_PASTE.txt` are generated per machine: they record absolute
  paths (the sending drive letter, the sending user profile) and the versions current when they were
  written. A receiving machine inherited a brief telling its agents to read files at paths that do not
  exist there, plus a `previous` state for `refresh-agent-context.ps1` to diff against that belonged
  to another machine. Same reasoning that already excluded `.audit_*`: inherited state is worse than
  no state. The template under `pack/templates/docs/` still ships - that is what bootstrap copies.
- **`install.ps1` honours `AGENT_STARTER_PACK_INSTALL_ROOT`.** Every other script read the override
  through `pack-paths.ps1`; the installer hardcoded `%USERPROFILE%\.cursor`. Asking for a scratch
  destination therefore rewrote the real profile while the *later* steps of the same run reported the
  scratch path - a half-redirect. Rules, skills and `mcp.json` follow the override via
  `Get-AgentStarterPackUserRoot`, so the set moves together.
- **Behavior step 26 now runs a real redirected install.** It asserts the pack tree, rules and
  recorded canonical path land in the scratch destination and that the real profile `.cursor`
  directory is byte-for-byte untouched. Until this fix no test could exercise a full install without
  writing the maintainer's profile.

---

## 2.22.3 (2026-08-28)

**Five copies of the same encoding fix, and no test that the two PowerShell hosts agree.** Raised by a
maintainer whose development machine runs PowerShell 7 while the pack's floor is 5.1: code written on
one host and shipped to the other had produced BOM bugs before. Investigation found the drift was real
but narrower than assumed - and that the pack had no way to detect it.

What the measurements actually showed (worth recording, because the intuitions were wrong):

- **No PowerShell 7-only syntax anywhere** in 47 scripts and templates, and the full behavior suite
  passes under 7. The pack was already cross-version clean by luck, not by test
- **Only encoding truly differs.** `Set-Content -Encoding UTF8` writes a BOM on 5.1, not on 7.
  Dot-assigning a new property onto a `PSCustomObject` throws on *both* hosts, so the mcp.json data
  loss in 2.21.22 was a plain logic bug, not version drift. `ConvertTo-Json` truncates at depth 2 on
  both; 7 merely warns
- **7 is slower for this workload.** A child shell costs ~130 ms on 5.1 and ~250 ms on 7 (the Store
  package alias is not the cause; the real exe measures the same). An audit spawns dozens, so hosting
  the pack on 7 would cost seconds per run and buy nothing. 5.1 stays the host

Changes:

- **One writer.** `Write-Utf8NoBom` now lives in `pack-paths.ps1`, replacing `Write-TextNoBom`,
  `Set-TextNoBom`, a third `Write-Utf8NoBom`, and two inline `UTF8Encoding($false)` writes across 39
  call sites. The copies had already drifted - only one created the parent directory
- **`Add-Utf8NoBomLine`** for the JSONL timing log, which needed append rather than whole-file write
- **`#Requires -Version 5.1` on every script** (12 were missing it). `pack-paths.ps1` is exempt and
  says why: it is dot-sourced
- **Host shell is reported**, by `doctor.ps1` and `check-requirements.ps1`, with a warning when hosted
  on Core that the floor is 5.1. PowerShell 7 is listed as an optional requirement with its winget
  command - never auto-installed, matching the existing policy on runtimes
- **Behavior step 29 (always on)** runs a probe on both hosts: identical writer bytes, no BOM, identical
  parsed JSON. It also fails if a second BOM-free writer or an inline copy reappears, or if any script
  drops its `#Requires`. Skips with a note when only one host exists
- **`-DualShell`** runs the whole suite on the other host (~140s instead of ~70s). Opt-in

Two bugs surfaced while building this:

- **`run_audit_core.ps1` dot-sourced `pack-paths.ps1` inside a function**, which scopes the definitions
  to that function - the shared helpers were invisible in the rest of the file. Moved to script scope
- **The timing-log write was wrapped in an empty `catch {}`**, so the log silently vanished when that
  broke. It now warns; the audit still does not fail on a diagnostic write

## 2.22.2 (2026-08-28)

**The refresh's paste line was hard to copy correctly.** 6a printed it indented inside wrapped console
output, so selecting it dragged in leading spaces and line breaks, and it carried an ISO stamp with
microseconds. A mangled paste is worse than no paste: the agent half-reads it, answers as if it
refreshed, and the session continues on stale rules. Reported from real use - pasted updates "get
hung/misunderstood/or just plain wonky."

- **`docs/AGENT_PASTE.txt`** - the line alone, one line, ASCII only, BOM-free, no trailing whitespace.
  Nothing to select around
- **Clipboard by default.** The refresh puts the line on the clipboard; `-NoClipboard` opts out (tests
  use it, since a suite must not touch the user's clipboard)
- **Console leads with the clipboard state** (`COPIED TO YOUR CLIPBOARD ... press Ctrl+V`, or the file
  path when the clipboard is unavailable), then shows the line unindented between banner rules as
  reference. A clipboard note printed *after* a 380-character line reads as a footnote, and the user
  hand-selects text they already have
- **Line rewritten to be unambiguous.** Minute-precision UTC stamp, `PACK CONTEXT REFRESHED` prefix,
  imperative "Before your next action", absolute paths, and a closing request to reply with both
  version numbers - so a bare "ok" is visibly a failure to read rather than a silent one
- **Behavior step 27 asserts the copy properties**, not just that a line exists: single line, no BOM,
  no stray whitespace, ASCII, versions and absolute path present, and identical to the brief's copy
- **The paste line is pinned as a pointer.** A multi-change refresh must still produce one line under
  600 characters, and the line must not contain any of the per-change prose - that belongs in the brief,
  which the agent opens itself. An update notice that grows an entry per change turns into a document,
  and pasting a document is what makes agents skim it or stall partway through

**Also: `sync-audit-system.ps1` left drift behind on every run.** It mirrored the pack, then ran
doc-version sync - which rewrites `START_HERE.md` and `AUDIT_SYSTEM.md`, both mirrored files. The
install therefore held the pre-sync text and the next verify failed on a tree that had just been
synced, so `run_audit_tests.bat` needed two sync runs after any version bump. Doc sync now runs
*before* the mirror; one run leaves a clean `-VerifyOnly`.

## 2.22.1 (2026-08-28)

**A rule added to the pack reached user profiles but never projects.** `sync-project-rules.ps1`
carried its own hardcoded list of nine rule filenames - the same defect 2.21.21 fixed in `doctor.ps1`,
where a hardcoded list validated 5 of 9 rules, left live on the project-sync path. `install.ps1`
copies the whole `pack/rules` folder, so new rules did land in `%USERPROFILE%\.cursor\rules\`, and
nothing reported that projects were being skipped. Found by adding a tenth rule and watching it not
arrive.

- **`sync-project-rules.ps1` enumerates `pack/rules` now.** The folder is generic-only by policy, so
  everything in it belongs in a project that syncs; an empty folder is an error rather than a silent
  no-op
- **Behavior step 5b runs that sync for real** against a scratch project and requires every rule on
  disk to arrive. Manifest coverage alone could not catch this: the manifest was correct while
  delivery was incomplete, which is exactly the gap that let it survive 2.21.21

## 2.22.0 (2026-08-28)

**Section B could be closed by deleting a folder, so that is what agents did.** Every machine check
in B ended in `- delete`: `Build cruft - dist - delete`, `Cache cruft - ... - delete`. An agent that
read `machineFixesBySection.B`, deleted what it named, and wrote a clean summary had satisfied
everything the machine asked - while never asking whether a reader can tell build output from runtime
user data from a duplicate release copy. Worse, the delete-only framing is misleading: `dist/` comes
back on the next build, so "fixed" was never true. Layout clarity is now reported as **Improve**, in
its own channel:

- **`layoutPolicy` in `AUDIT.config.json`** (optional, **disabled by default**, `MyApp` placeholders
  only) checks for a folder glossary and heading, an in-repo duplicate of a release archive, one
  runtime-data dirname living both beside the source tree and inside the build output, ephemeral dirs,
  and scripts that recreate a path the policy forbids. `layoutPolicy.enabled` joined
  `auditConfigTemplate.requiredKeys`, so template and reference configs cannot drift apart
- **Findings are Improve, with one exception** - build output that is actually **committed to git** is
  a Fix, because that one does break the repo. Nothing deletes, nothing restructures, and the audit
  CLI never asks "want me to clean this up?"
- **`machineImprovesBySection` is a new array in `docs/.audit_agent_manifest.json`**, beside
  `machineFixesBySection`. Sharing the Fix channel is precisely what trained agents to read B as a
  delete list, so Improve lines get their own key and `machineSectionsWithImproves` alongside it
- **`semanticRequireMachineImproveMention`** closes the obvious hole: Fix lines already blocked a
  clean summary, Improve lines blocked nothing, so a layout finding could sit in the manifest while
  the section closed on "Nothing found." The summary must now mention layout or cite a flagged path
- **The skill gained a mandatory §B layout pass** - read the glossary doc, locate build output vs
  runtime data vs archive copy, address `machineImprovesBySection.B`, and it is explicitly forbidden
  to close B with "removed `dist/`" when the glossary and duplicate-copy workflow were never examined.
  `AUDIT.md.template` §B, `AUDIT_SYSTEM.md`, and `AGENT_WORKFLOW.md` carry the same Fix vs Improve
  taxonomy
- **Behavior step 28** creates the layout tree under the fixture, then asserts the findings appear,
  that **none of them landed in Fix**, that `machineImprovesBySection.B` carries them, and that a
  clean §B summary is rejected while a summary naming them passes. The fixture checklist gained a
  §B so the semantic half is exercised rather than skipped
- **Cruft remediation paths were still nested-only.** `Build cruft - app\dist - delete`,
  `Stale files - app\*.tmp`, and `Cache cruft - app\.pytest_cache` hardcoded `app\` - the bug fixed
  elsewhere in 2.21.x but missed in this block, so flat projects (what bootstrap generates) were told
  to delete paths they do not have. They use `$appPrefix` now

## 2.21.23 (2026-08-28)

**Updating the pack changed the disk and reached none of the agents already working.** No chat -
Cursor, Claude, Copilot, or otherwise - reloads its instructions when files change, so a session
opened before an install kept acting on the previous rules with nothing to signal otherwise. The only
answer available was for the user to hand-write what changed, including version numbers they had to
look up. `Refresh-AgentContext.cmd` (wrapping `pack/scripts/refresh-agent-context.ps1`) now syncs a
project and writes what changed as files the agent can read:

- **`docs/AGENT_CONTEXT.json`** - schema-versioned stamp: pack version, audit engine version, the
  installed pack's version when it differs, a `rulesRevision` hash over `pack/rules/*.mdc`, per-layer
  state (`ok` / `updated` / `stale` / `skipped` / `unknown`), and `changedLayers` computed against the
  previous stamp
- **`docs/AGENT_REFRESH.md`** - short brief: stale-chat notice, the files to re-read as absolute
  paths, plain-language change lines, and a paste line at the bottom carrying versions read from the
  pack at generation time, so it cannot cite a number that is already wrong
- **Given a project root it applies the syncs first** - `sync-project-rules.ps1` and
  `sync-audit-system.ps1` - so the brief describes a project that has actually been updated rather
  than one that is merely told about it. Run against the pack repo it skips those (the pack is the
  source) and writes the maintainer variant of the brief, which is the only one that names
  `HANDOFF_NEXT_AGENT.md`; an app brief says explicitly that the handoff is not its file
- **`agent-defaults-always.mdc` gained a six-line trigger** so **refresh pack context** (or *context
  refresh* / *pack update*) sends the agent to the brief without the user pasting anything, and
  `AI_INSTRUCTIONS.md.template` points non-Cursor agents at the same file
- **Bootstrap writes the stub** `docs/AGENT_CONTEXT.json` and lists both artifacts in
  `.agent-bootstrap.json`, so the path exists before the first refresh
- **Overlap with `Update-AgentRules.cmd` is deliberate and split**: that reports what changed in the
  *profile* at install time, this leaves a per-project file that an agent can still read tomorrow

## 2.21.22 (2026-08-27)

**Installing the pack destroyed every MCP server the user already had.** The first real install on a
profile with existing servers found it: `Merge-McpJson` read `mcp.json`, then set the new key with
`$existing.mcpServers."agent-hygiene" = $entry`. Dot-assigning a *new* property on the
`PSCustomObject` that `ConvertFrom-Json` returns throws on Windows PowerShell 5.1, the `catch` read
that exception as "could not parse existing mcp.json", and the rewrite that followed wrote the
freshly built single-server object - so a machine with 13 configured servers came out with one, under
a warning that blamed the user's file. Now `Add-Member -Force` adds the key (it also replaces, so
re-running is idempotent), a genuinely unparseable config is backed up and **left in place** with
nothing registered rather than overwritten, `-Depth` went 6 to 10 so deeply nested server configs
survive the round trip, and the file is written without a BOM.

- **The installer left bytecode in the profile it had just filtered.** 2.21.21 taught `Copy-Tree` to
  skip `__pycache__` and `.pyc`; the install then ran doc sync *out of the installed tree*, which
  regenerated them there. Python bytecode writing is suppressed for those steps and `__pycache__` is
  pruned from the installed tree at the end
- **Behavior step 26 covers the two functions that write to the user profile.** `install.ps1` is the
  one script a test cannot simply run, so both functions are lifted out of the shipped file by AST
  and exercised against scratch paths: pre-existing MCP servers survive with nested config intact,
  the merge is idempotent, an unparseable config is preserved and backed up, the output is BOM-free,
  and the copy filter still excludes artifacts while keeping hidden pack files. Reintroducing the old
  assignment fails the step with the exact PowerShell error as the reason
- **The installer never removed anything, so a dropped file lived in the profile forever** - and a
  rule the pack stopped shipping kept instructing agents in every project on the machine.
  `install.ps1 -Prune` (opt-in; reported either way) removes them. The canonical tree is entirely
  pack-owned, so anything there without a source counterpart is stale; profile rules and skills also
  hold the user's own files, so those are only removed when a **previous install recorded shipping
  them** - `install-manifest.json` now lists the rules and skills each install delivered. With no such
  record, no profile rule or skill is ever a prune candidate. `.tmp` scratch is spared because a
  concurrent run may hold it open. Behavior step 26 asserts the dangerous direction: a rule the user
  added themselves is never a candidate, and files the pack still ships are never candidates
- **Nothing checked shell scripts, and git could re-break the one that exists.** Step 24 scanned
  `.ps1`, `.py`, `.cmd`, and `.bat`, so `install.sh` - fixed in 2.21.21 for having CRLF endings that
  made its shebang unrunnable - was never covered by the check that would have caught it. `.sh` is now
  scanned, a CR in a shell script is a named failure, and a `.gitattributes` pins `*.sh` to LF (with
  `*.cmd` and `*.bat` to CRLF) so a checkout on another machine cannot reintroduce it. Proven by
  converting `install.sh` to CRLF and watching the step fail
- **`Update-AgentRules.cmd` now reports what an update changed** (`pack/scripts/update-agents.ps1`):
  rules, skills, and pack files added or updated by hash, MCP servers configured, files in the
  profile this pack no longer ships (the installer never deletes), then `doctor.ps1` and a sync
  verify, exiting non-zero if either complains. It also prints the line to paste into a chat that is
  already running, which otherwise keeps the old rule text in context

---

## 2.21.21 (2026-08-27)

**A transferred pack could not audit itself, and three checks were scanning nothing:**

- **`export.ps1` shipped a pack with no audit entry points.** The hand-maintained item list had drifted from the manifest: `run_audit.cmd`, `run_audit_tests.bat`, `AGENTS.md`, `scripts\`, `tests\`, and `.cursor\rules\audit.mdc` were all absent, so on the receiving machine the `run_audit.cmd` that every transfer doc tells you to run did not exist. `Test-Path` guarded each copy, so nothing ever failed. The export now verifies the staged tree against `manifest.json` `projectRequired.flatLayout` and throws with the missing paths named; a missing manifest is the loudest case rather than a reason to skip the check, and machine-local leftovers (`.pyc`, `.tmp`, `.audit_*`) are pruned so a receiving machine cannot inherit the sender's test-pass proof
- **The pack's only content rule matched zero files.** `"glob": "*.{md,ps1,mdc,cmd,bat,json,py}"` is shell syntax; `pathlib.rglob` treats it as a literal filename, so the legacy-path scan had never run. Braces are now expanded, and the revived rule found five real hits (all self-referential - the checklist line describing the rule and the config defining it), so it gained an `allowLineRegex` and excludes for generated artifacts. A rule may now declare `requireMatches`, which turns "this glob stopped matching anything" into a Fix; unbalanced braces are always a Fix. It is opt-in because an empty scope is legitimate - a Generic project has no `*.py` for the safety patterns to scan
- **`docs/AUDIT.md` had a reference copy that nothing compared,** and it had drifted 16 lines from the real checklist. `packReferenceConfig` now checks the markdown pair as well as the JSON pair
- **Section N could demand a semantic section that no template ever produced.** The N machine check defaulted to enabled, but N is not a checklist heading, so `--write-template` wrote no N stub: any config that left N alone hit an unfixable Fix the moment git showed a version commit. N is now opt-in, and where it is switched on it joins the required sections so the template stubs it. `fill_pack_semantic_report.py` leaves a required section it has no canned text for unreviewed instead of raising `KeyError`

**Installed and generated files that no check could see:**

- **Two of three skills were outside the manifest.** `install.ps1` `Copy-Tree`s the whole skills folder, so `agent-gui-test-hygiene` and `agent-terminal-hygiene` landed on a fresh install and then went stale forever - the same defect 2.21.19 fixed for four rules, with a step 5b that covered rules only. Step 5b now covers skills too
- **`doctor.ps1` validated 5 of the 9 installed rules** from a hardcoded list. It now enumerates `pack\rules` and `pack\skills`, so a rule cannot be installed and unverified at once
- **`install.ps1` copied the whole source tree into the profile,** including `.git`, a live `.tmp`, `__pycache__`, `.pyc` files, and the source machine's `.audit_*` results - and `Copy-Tree` only ever adds, so they stayed forever. Those are now skipped, and hidden files (the `.cursor` rules the audit requires) are no longer silently dropped
- **`run_audit_core.ps1` read `docs/AUDIT.md` without `-Encoding`,** so PowerShell 5.1 decoded a BOM-less UTF-8 file as ANSI and copied mangled em dashes straight into `docs\.audit_agent_manifest.json` - the brief the next agent reads
- **A non-Cursor bootstrap produced a project that failed its own first audit.** `.cursor\rules\audit.mdc` was written only for Cursor targets while the audit system requires it of every project, so `-Targets Portable`, `Claude`, or `Copilot` opened with a missing-file Fix and a sync drift. The rule is now written for every target. `version-sync.mdc.template` was copied verbatim despite carrying `{{PROJECT_NAME}}` and `{{SOURCE_MODULE}}`, shipping a rule whose frontmatter glob was the literal placeholder text; it now goes through the expanding writer
- **`run_audit_tests.bat` ran the behavior suite twice** (directly, then again inside `verify-audit-system.ps1`), and the pack self-audit made it three times. It now passes `-SkipBehavior` to the second call: the suite runs once in tests and once in the audit's Section L verify, and a full test run dropped from ~86s to ~56s. The fallback to the installed pack also warns instead of silently testing a different engine
- `install.sh` had CRLF line endings, so `#!/usr/bin/env bash\r` made it unrunnable on the Unix systems it exists for; `sync-doc-versions.ps1` had CR-CR-LF throughout; the `.gitignore` snippet merged into every generated project carried a non-ASCII dash

## 2.21.20 (2026-08-27)

**The test-pass proof did not cover the code, so in a git repo a clean audit survived a code change:**

- **`git HEAD` was the whole proof whenever git answered, and HEAD does not move for uncommitted edits.** A generated project was taken to a clean audit, then `def main()` was renamed to `def main_BROKEN()` without committing - same line count - and `run_audit.cmd -FinalizeOnly` still reported `Fix: Nothing found`, exit 0. The strictness was inverted from what matters: a project *without* working git fell back to the tree fingerprint and was policed properly, while an ordinary git repo was not. The first probe of this hid the bug - it ran on removable media where git refuses the repo as dubious ownership, so it silently took the strict path and the gate looked sound
- **The proof is now the content of the audited files, with HEAD prefixed when git answers** (`<sha>+tree:<sha256>`), so an uncommitted edit and a commit each invalidate it. Size and mtime are gone as inputs: mtimes do not survive a copy to another drive - which is how this pack ships - and can be restored, so an mtime proof can be stale and matching at the same time
- **The two implementations were never byte-identical.** PowerShell hashed `FullName|Length|LastWriteTimeUtc.Ticks`, Python hashed `resolved path|st_size|st_mtime_ns`; they agreed only because the wrapper asks Python first and uses its own answer as a fallback. A proof written on one path could never match the other. Both now hash file contents keyed by a lowercased app-relative path, sorted ordinally because `Sort-Object` is culture-aware and Python's `sorted()` is not
- Behavior step 23 git-initializes a probe project, takes it to a clean audit, asserts the recorded proof is commit+content, then makes a line-count-neutral edit and requires finalize to block

**A test runner that ran nothing satisfied the entire test gate:**

- Only the runner's exit code was checked, so replacing a generated `run_tests.bat` with `exit /b 0` printed `Tests: OK` while `tests/test_version_consistency.py` was never executed. `docs/AUDIT.md` already asked a reviewer to confirm the runner covers every test file; `check_test_runner_coverage` now checks that promise, gated by `codeChecks.testRunnerCoverage.enabled`. Globbed and discovered runs (`tests\test_*.py`, `pytest`, `unittest discover`) count as covering everything, and one level of delegation to another in-project script is followed
- It caught the pack's own `run_tests_stub.bat`, which was an instant `exit /b 0` beside two test files - the fixture was modelling the exact defect. The stub now loops `tests\test_*.py`

**One shipped command could stand in for an entire semantic review:**

- `--fill-semantic-fixture-test` marks every checklist section reviewed with `"Nothing found."`, empty evidence, and the `modulesReviewed` and `inventoryAck` values the gate cross-checks - a complete semantic pass in one command, ungated, in every install. It now requires `AUDIT_FIXTURE_TEST=1`, which only the behavior suite sets, and refuses with an explanation otherwise. New behavior step 25 fails if it ever runs without the opt-in

## 2.21.19 (2026-08-27)

**Accuracy of the gate itself. Two checks were lying, and one project audit was doing the pack's work:**

- **No project could pass an audit while reviewing nothing.** Required sections are the union of the checklist sections in `docs/AUDIT.md`, the domain map, `sectionTests`, and semantic hints - and the project template defined none of them, so a Generic project reported a clean audit with an empty gate. The template now ships six real sections (A test harness, B scope, C documentation, D core modules, K security, L agent wiring), and an empty required-section set is a Fix rather than a pass
- **A flat project named `app` audited its parent folder.** PowerShell compares strings case-insensitively, so the nested-layout check in `run_audit.ps1.template` matched `App`, `APP`, and `app`. Nested layout must now be proven: the app root has no `.git`, is named `app`, holds `docs\AUDIT.md`, and its parent is a git repo
- **The stale-semantics check fired on the documented workflow.** `testsPassedAt` was stamped at the *end* of the run - after the semantic template that same run writes - so an auditor who filled that template in place was told their deep scan predated the test pass. Root cause was a shadowed variable: PowerShell names are case-insensitive, so the local `$testsPassedAt = ''` **was** `$script:TestsPassedAt` and silently wiped it. The stamp is taken when the tests pass and is no longer reset
- **A product audit ran the pack's own 23-step behavior suite** (~50s), which bootstraps and audits probe projects *inside the pack folder*, and with step 23 present would re-enter itself. Behavior is the pack's test suite: `verify-audit-system.ps1 -SkipBehavior` is now used for anything that is not the pack, and the engine is still proven there by `audit_code_checks.py --self-test`. A Generic project audit now measures 4s; the suite it used to pull in takes ~33s by itself

**Found by an independent review of this same workstream - the parent-folder bug had a second half:**

- **The Python layer promoted the parent on evidence the wrapper ignored.** `run_audit.ps1.template` was fixed to keep the app root, but `resolve_repo_root()` in `audit_code_checks.py` still climbed whenever the parent held a `README.md` or a `.git` directory. Any flat project under a folder with a README - the normal case for `C:\Projects\MyApp` - had its machine checks scan the project while its git history, test-pass proof, version-doc scan, and evidence paths came from the parent. Both layers now apply the same rule, and `.git` is tested for existence so worktrees and submodules (where `.git` is a file) count
- The wrapper deliberately does **not** pass its repo root to Python. The behavior fixture's bespoke wrapper declares an outer repo root, and forcing that on Python would tie the fixture's test-pass proof to the pack's git HEAD, where edits to fixture code stop invalidating it - which is the staleness detection the fixture exists to test. Agreement is asserted instead: behavior step 23 compares `--print-repo-root` against the wrapper's `Repo:` line, with a `README.md` planted in the probe's parent so the old rule would fail the test
- **`$isPackSelfAudit` matched any repo containing `pack\audit\manifest.json`,** so a product repo that vendors a pack copy at its root would have run the pack's behavior suite. It now asks whether the repo being audited *is* the pack supplying the engine (`RepoRoot` equals the resolved pack root)

**The inventory only saw one folder, so the pack was auditing 38 of its own 3,053 Python lines:**

- **`moduleSearchDirs` was trusted to resolve modules but never scanned.** A project could declare where its code lives and still be inventoried on `scanDir` alone: the pack reported **1 production module / 38 lines** while holding a 2,168-line engine under `pack/scripts`, and the orphan scan could not see an unmapped module there. The domain scan now covers `scanDir` plus `moduleSearchDirs` for inventory, orphan detection, wildcard expansion, and the fingerprint. Projects that leave `moduleSearchDirs` at `["."]` - which is what the template ships - are unaffected. The pack now inventories **5 modules / 3,053 lines**
- **That immediately exposed a third copy of the repo-root rule - the one that writes.** `doc_version_sync.py` carried the old loose version, and `_collect_doc_paths` resolves `scanFiles` and `scanGlobs` against that root, so `apply_version.py sync` in any flat project sitting beside a `README.md` rewrote version cites **in the parent folder**. Reproduced on a generated project: the parent's `v0.0.1` became the project's `v0.1.0`. All three implementations now apply the same rule; behavior step 23 asserts all three agree *and* that the parent file is untouched after two audits
- Two modules surfaced as Section B orphans (`doc_version_sync.py`, `sync_doc_versions.py`) and are mapped to D, the section that requires a reviewed-module list. The test-gap hint that followed is closed by three new tests: repo-root resolution across flat, nested, and own-`.git` layouts; the stale-detect / sync / idempotent round trip; and the `sync_doc_versions.py` CLI contract (7 pack tests, up from 4)
- `docs/AUDIT.md` states the remaining limit plainly: roughly 3,300 lines of pack PowerShell are outside this inventory because the code checks are Python-specific, and are covered by the behavior suite instead. A clean Section B is not "all pack code inspected"

**Found by an adversarial verification pass that re-tested every claim above by running it:**

- **Four installed rules were invisible to sync and verify.** `install.ps1` `Copy-Tree`s the whole `pack/rules` folder, so all nine rules reach a profile, but the manifest listed only five in `packMirror` and `packToUser`. The other four - `generic-phased-feature-design`, `generic-terminal-and-build-hygiene`, `generic-version-sync`, `new-project-bootstrap` - landed once on a fresh install and then went stale permanently: incremental syncs never saw them, write-mode sync did not repair them, and no check reported it. This is the same defect this release fixed for `AGENT_WORKFLOW.md` and `verify-agent-setup.ps1`, left behind on four files. New behavior step 5b fails if any rule on disk is missing from either list, so a tenth rule cannot repeat it
- **The suite was re-adding a UTF-8 BOM to committed fixture code on every run.** `Set-Content -Encoding UTF8` writes a BOM on Windows PowerShell 5.1, and steps 12 and 13 restore tracked fixture files that way after mutating them - which is how `catalog_cache.py` came to be committed with a BOM *under the check meant to prevent exactly that*. Restores now go through a no-BOM writer, and the audit timing log is appended without one
- **Step 24 was not scanning `pack\audit`,** leaving 13 executed files unchecked, including the fixture wrappers this suite runs. It now scans that tree (65 files, up from 50) and includes `.gitignore`, where a BOM silently disables the file's first pattern
- **Flat projects were told to run a path they do not have.** `Add-Fix 'Audit sync drift - run app\scripts\sync_audit_system.cmd'` and `Missing path - app\...` hardcoded the nested-layout prefix, so bootstrap's default layout got unactionable remediation. The prefix is derived from whether the app root differs from the repo root
- The step 23 assertion could not tell "ran verify without `-SkipBehavior`" from "skipped verify entirely," and reported the former for the latter. The behavior probe root is now per-process, so a locked file or a concurrent run no longer fails the step with a message that reads like a product defect
- `.gitignore` shipped with an em dash already destroyed by an ANSI/UTF-8 round trip (`install record -?" written into...`); repaired, and the `description` fields in `pack/audit/manifest.json` and `docs/VERSION_SYNC.json` are ASCII

**Encoding class closed, not just patched:**

- All executed code is ASCII and BOM-free - 37 typographic characters normalized across `audit_code_checks.py`, `run_audit_core.ps1`, `sync-audit-system.ps1`, `pack-paths.ps1`, `verify-*.ps1`, `doc_version_sync.py`, `agent_hygiene_server.py`, `test_pack_audit.py`. This also clears the mojibake PowerShell 5.1 produced when reading BOM-less UTF-8 as ANSI
- Behavior step 24 enforces it for `.ps1`, `.py`, `.cmd`, `.bat`, and executable templates; Markdown keeps its typography

**Behavior suite (now 24 steps):** step 23 walks a generated project through the full documented workflow - bootstrap, machine pass, semantic fill, finalize - and asserts it reaches a clean audit, that a folder named `app` does not hijack the repo root, and that a product audit never runs the pack suite.

**An Improve line nobody could close:** `check_section_n_improve` asked for a release-delta review on every run where git showed recent `VERSION` commits, including runs whose semantic report already contained that review. It now stands down once section N is reviewed with a real summary; `verify_section_n_semantic` still enforces the quality of that review.

**Cleanup:** removed the dead duplicate `sync_doc_versions()` implementation and its four helpers from `audit_code_checks.py` (181 lines; `doc_version_sync.py` owns doc sync). `sync-project-rules.ps1` defaults to `.cursor\rules` instead of the nested-layout `app\.cursor\rules`. Superseded doc-sync bullets in 2.21.10 and 2.21.11 are marked as such.

## 2.21.18 (2026-08-27)

**Generated projects now pass their own audit. Six defects, all found by running bootstrap output instead of reading it:**

- **Every generated project audited its parent folder.** `run_audit.ps1.template` set `$RepoRoot = Split-Path -Parent $AppRoot`, which is only right for the nested `<repo>\app` layout — but bootstrap generates flat projects, where the app root *is* the repo root. A project at `C:\Projects\MyApp` therefore scanned `C:\Projects` for `.md` and `.env` files (sibling projects included), looked for `README.md` one level too high, and passed the wrong `-ProjectRoot` to `sync-audit-system.ps1`, which reported every audit file as drift. The template now keeps the app root and only steps up for a folder literally named `app` holding `docs\AUDIT.md`
- **The semantic gate could never be satisfied without git.** On a full run the test-pass proof was captured in the init phase, *before* the test script ran — and a generated project's test script runs the version/doc sync, which rewrites files the proof covers. With a git repo the proof is a stable HEAD so it never showed; in fingerprint mode (any project before `git init`) the verifier's recompute never matched and the audit reported `Semantic report stale` forever. The proof is now taken after tests pass
- **An empty file set produced a valid-looking proof.** Both fingerprint helpers hashed zero files into `sha256("")` — a constant that matches forever. No files now means no proof
- **Generated tests passed once, then failed on every later audit.** `apply_version.py.template` printed a `→` on the "already synced" path; redirected console output is cp1252, so it raised `UnicodeEncodeError` and failed the whole test step. Executable templates are ASCII-only now (`apply_version.py`, `run_tests.bat`, `build-ci.bat`, `run_tests.generic.bat`, `test_version_consistency.py`); Markdown keeps its typography
- **Domain map: every module looked unmapped.** The heading search matched any line *containing* `## Domain map`, including the template's own prose ("Include a **## Domain map** table..."), so the chunk ended at the next heading and the real table below was never read. The match is anchored to the line start, so trailing text like `## Domain map (example - replace ...)` still works. Also `scanDir` was joined with `-replace '/', '.'` instead of `'\'`, so any nested scan dir resolved to a bogus path
- **The audit created cruft it then reported.** Its own test run left `__pycache__` behind, which the cruft check flagged as a Fix the user could never clear; the test run now sets `PYTHONDONTWRITEBYTECODE`

**Bootstrap output matches the audit it ships with:**

- Writes `README.md` and `VERSION.txt` — both are required by the config it generates, and `VERSION.txt` was checked before the test script that would create it, so run 1 always reported it missing
- Python stack: `sectionTests` maps section D to the generated test file instead of shipping `{}`
- Generic stack: no longer describes a `main.py` it never creates — `versionSync` is null and the example domain-map row is dropped, which was four permanent Fix items on every Generic project
- Removed a duplicate `mcpWiring` key from the config template (JSON kept the last one, so the first was dead)

**`verify-audit-behavior.ps1` step 23 — bootstrap smoke:** generates a Python project and a Generic project, audits the Python one twice (the repeat run is what exposed the encoding crash), and asserts BOM-free output, repo root == app root, no phantom drift, no stale proof, tests still passing on re-run, machine-clean except the auditor's semantic sections, and that nothing was installed. The Generic probe disables `runLegacyVerify`: its audit reaches a complete semantic pass, which would re-enter this suite and recurse without end.

## 2.21.17 (2026-08-27)

**Dependencies are checked and named, not discovered by failure:**

- **`pack/scripts/check-requirements.ps1`** + **`Check-Requirements.cmd`** — environment preflight that runs from the pack folder with no install. Reports PowerShell, Python 3.8+, the `py -3` launcher, pip, `mcp`, and git as OK / MISSING (required) / WARN (optional), each with the exact install command. `-Fix` installs the Python packages; `-Json` for agents and `doctor.ps1`; `-PythonCommand` probes a non-PATH interpreter
- Required vs optional is explicit: without `mcp` the MCP tools are unavailable but audits and bootstrap work; without git the audit uses a file-tree fingerprint for test-pass proof
- Proof over presence — the preflight runs `audit_code_checks.py --self-test`, since an interpreter on PATH is not evidence the engine works on this machine
- **`'py -3' launcher` is its own required row** — a machine with only `python.exe` passed a naive Python check and still could not run `run_audit.cmd`, because every `.cmd` in the pack and in generated projects calls `py -3`
- **`install.ps1`** — preflight first, stops on a missing required item (`-SkipPreflight` to override); **`bootstrap-project.ps1`** warns; **`doctor.ps1`** delegates instead of keeping its own check
- **`doctor.ps1` false positive fixed** — it tested `import mcp`, which succeeds from the pack root because the pack's own `mcp\` folder becomes a namespace package. The probe now imports `mcp.server.fastmcp` (what the server needs) from outside the pack folder
- **`tests/test_pack_audit.py`** — runs standalone (`py -3 tests\test_pack_audit.py`) and is wired into **`run_audit_tests.bat`**. It was pytest-only, so nothing ever ran it while the audit inventory counted it as coverage; the pack now has no test dependency the preflight does not check
- **`verify-audit-behavior.ps1`** — steps 21 and 22 cover the preflight (JSON shape, required/optional split, missing-interpreter exit code and install hint, fastmcp probe) and the standalone pack tests

**Three defects found by actually bootstrapping a project and running its audit:**

- **BOM crash — every bootstrapped project's first audit failed.** `bootstrap-project.ps1` wrote files with `Set-Content -Encoding UTF8` (a BOM on Windows PowerShell 5.1) while `audit_code_checks.py` read them as plain `utf-8`, so `load_config` died with `Unexpected UTF-8 BOM` before any check ran. Reads now use `utf-8-sig` (`audit_code_checks.py`, `doc_version_sync.py`, `fill_pack_semantic_report.py`) and bootstrap writes plain UTF-8 via `Write-TextNoBom` — a BOM at the top of a generated `.cmd` was a hazard too
- **Auditing a project installed the pack.** With `syncAndVerify.autoFixDrift` enabled, a project's `run_audit.cmd` ran `sync-audit-system.ps1` in write mode, which *created* `%USERPROFILE%\.cursor\AgentStarterPack` plus profile `rules\` and `skills\`. The mirror is now skipped whenever no install exists, in write mode as well as `-VerifyOnly`: keeping an install aligned is this script's job, creating one is `install.ps1`'s. Locked in by behavior step 20 (`sync never creates an install`)
- **`bootstrap-project.ps1`** — creates the target folder instead of failing with a raw `Resolve-Path` error, and no longer prints a bare `True` after every generated file (the template writers returned a value no caller consumed)

## 2.21.16 (2026-08-27)

**Mirror direction is now tested, not just documented:**

- **`verify-audit-behavior.ps1`** — new step 20 builds a miniature pack plus a scratch install target under `.tmp/` and asserts: a newer installed file loses to the source pack, an installed-only file never lands in the source pack, `-VerifyOnly` reports drift without copying, and `-PullFromInstalled` still recovers installed edits. Nothing in the suite exercised the mirror before, because it needs an install to exist
- **`pack-paths.ps1`** — **`AGENT_STARTER_PACK_INSTALL_ROOT`** redirects the install *destination* (self-tests, relocated profiles); **`Get-AgentStarterPackUserRoot`** derives the profile rules/skills folder from it, so an override moves the whole mirror instead of half of it
- **`sync-audit-system.ps1`** — a manifest-listed file present only in the installed copy is now **removed** from it rather than skipped forever. Skipping (2.21.15) left `-VerifyOnly` permanently red and `-AutoFix` unable to converge; the source pack is authoritative about deletions too. `-PullFromInstalled` still copies it back instead
- Docs — `AUDIT_SYSTEM.md` mirror-direction section; dropped stale "newer file wins" and Desktop-as-canonical wording

## 2.21.15 (2026-08-27)

**Pack folder travels, install does not (removable-media safety):**

- **`sync-audit-system.ps1`** — mirror is now one-way, source pack → installed. A stale machine-local install can no longer overwrite the pack folder, and files deliberately deleted from it are no longer resurrected. New **`-PullFromInstalled`** restores the old newest-wins reconcile for recovering edits made inside `%USERPROFILE%\.cursor\AgentStarterPack`
- Rationale: mtime comparison across filesystems is unreliable — removable exFAT stores local time, NTFS stores UTC — so "newest wins" could pick the wrong side on a USB-hosted pack
- **`bootstrap-project.ps1`** — warns when the pack is not installed on this machine, because the generated project's MCP path then points at the pack folder's current location (breaks on drive-letter change or unplug)
- Docs — `PORTABLE_SETUP.md` USB workflow and per-machine install model; `AGENT_STARTER_PACK_ROOT` documented as a session override, not a permanent setting for removable drives

## 2.21.14 (2026-08-27)

**Portable pack root (runs from any drive or folder):**

- **`pack/scripts/pack-paths.ps1`** — resolves the pack the script runs from (`Get-SourceAgentStarterPack`) before env vars, the installed copy, or legacy Desktop paths; adds `Test-AgentStarterPackRoot` / `Test-AgentStarterPackInstalled`
- **`sync-audit-system.ps1`** — source pack replaces "Desktop pack"; a machine with no installed copy reports one actionable `[INFO]` instead of per-file drift
- **`verify-audit-system.ps1`** — `run_audit_core.ps1` accepted from the project, resolved pack, or installed copy
- **Project templates + behavior fixture** — `AGENT_STARTER_PACK_ROOT` honored, then the profile install; `run_audit.ps1.template` no longer needs `pack-paths.ps1` beside it (it was never copied into projects)
- **`run_audit_core.ps1`** — test-pass proof comes from `audit_code_checks.py` first, so the recorded proof matches the one semantic freshness recomputes; fixes finalize being reported stale when the app root sits inside an outer git repo

## 2.21.13 (2026-08-27)

**Generic-only pack (no product-specific references):**

- Removed product-specific audit reference configs — replaced with **`AUDIT.config.app.reference.json`** / **`AUDIT.app.reference.md`**
- **`manifest.referenceProject`** — no default external repo path; flat layout paths; env **`AUDIT_REFERENCE_PROJECT_ROOT`**
- **`verify-agent-setup.ps1`** — `-ReferenceProjectRoot` for optional app checks; removed product-specific file checks
- **`Update-AgentRules.cmd`** — install + optional `%1` ProjectRoot (no hardcoded app paths)
- Docs, templates, rules — generic placeholders (`MyApp`, `main.py`, behavior-fixture) only

## 2.21.12 (2026-08-26)

**Doc sync = build pipeline (decoupled from audit):**

- **`docs/VERSION_SYNC.json`** — build config for version + doc cite sync (not `AUDIT.config.json` codeChecks)
- **`pack/scripts/doc_version_sync.py`** + **`sync_doc_versions.py`** — standalone; no `audit_code_checks.py` on build path
- **`apply_version.py sync`** → version + docs; wired in **`run_tests.bat`** / **`build_ci.bat`** templates
- Bootstrap copies **`doc_version_sync.py`** + **`VERSION_SYNC.json`** to every project

## 2.21.11 (2026-08-26)

**App doc version sync (all bootstrapped projects):**

> **Superseded by 2.21.12:** doc sync moved to the build pipeline (`docs/VERSION_SYNC.json` +
> `doc_version_sync.py`). `docVersionSync` in `AUDIT.config.json` is a disabled fallback - do not
> re-enable it, and do not read the bullets below as the current model.

- **`appVersionDocs`** in `AUDIT.config.json` — sync `vX.Y.Z` in README/AGENTS/docs from `versionSync` canonical
- **Bootstrap template** — `docVersionSync` + `appVersionDocs` **enabled by default**
- **`apply_version.py`** — after sync/bump, runs `--sync-doc-versions` via installed pack
- **`scripts/sync_doc_versions.cmd.template`** — manual doc sync for Python projects
- Audit **Improve** — `check_app_version_docs_improve` when sync was skipped

## 2.21.10 (2026-08-26)

**Automated maintainer doc version sync:**

> **Superseded by 2.21.12:** `audit_code_checks.py` is no longer on the doc-sync path; its duplicate
> `sync_doc_versions()` body was removed in 2.21.19. Use `Sync-DocVersions.cmd` or
> `apply_version.py sync`.

- **`pack/scripts/sync-doc-versions.ps1`** + **`Sync-DocVersions.cmd`** — align version cites in README/INSTALL/START_HERE/AUDIT_SYSTEM/etc. from root `VERSION` + `manifest.json`
- **`audit_code_checks.py`** — `--sync-doc-versions` / `--verify-doc-versions` (uses `auditVersionDocs`, `packVersionDocs`, `docVersionSync` in `AUDIT.config.json`)
- **`install.ps1`**, **`sync-audit-system.ps1`** — run doc sync when `docVersionSync.enabled`
- **`generic-agent-doc-hygiene.mdc`** — run sync after version bumps; enable `docVersionSync` in project config

## 2.21.9 (2026-08-26)

**Agent doc hygiene + recommendation discipline:**

- **`pack/rules/generic-agent-doc-hygiene.mdc`** — read existing rules/`AGENTS.md` before adding agent docs (all projects via `install.ps1`)
- **`agent-defaults-always.mdc`** — pointer to generic-agent-doc-hygiene
- **`sync-project-rules.ps1`** — includes generic-agent-doc-hygiene in generic rule set
- **`.cursor/rules/agent-recommendation-discipline.mdc`** — scope before execute, install callout, rule layers, script path defaults
- **`verify-agent-setup.ps1`** — pack-only by default; `-ReferenceProjectRoot` optional for app checks; no hardcoded external defaults

## 2.21.8 (2026-08-25)

**Pack ↔ project sync (no forked generic rules):**

- **`pack/docs/PACK_MAINTENANCE.md`** — where to edit; generic vs project-only rules; drift checks
- **`pack/scripts/sync-project-rules.ps1`** — one-way copy `pack/rules/` → project `app/.cursor/rules/` (+ `-VerifyOnly`)
- **`full-paths-in-chat.mdc`** — examples generalized (no product-specific paths in pack)

## 2.21.7 (2026-08-25)

**Full paths in chat (always-on rule):**

- **`pack/rules/full-paths-in-chat.mdc`** — new canonical rule; `alwaysApply: true`
- **`agent-defaults-always.mdc`** — Chat paths pointer to `full-paths-in-chat.mdc`
- **`doctor.ps1`** — verifies `%USERPROFILE%\.cursor\rules\full-paths-in-chat.mdc` after install
- **`START_HERE.md`** — pre-flight step 8 (full absolute paths in chat)
- **`manifest.json`** — `packMirror` + `packToUser` include `full-paths-in-chat.mdc`

## 2.21.6 (2026-08-17)

**Final maintainer drift checks:**

- **`changelogVersionDocs`** — CHANGELOG.md latest release vs root `VERSION`
- **`mcpWiring`** — mcp.json, requirements pin, Python `import mcp` (section G)
- **`run_audit_core.ps1`** — Improve when verify-audit-system skipped (semantic/sync gates)
- **`AUDIT.config.json.template`** — disabled stubs for pack-only `codeChecks` keys

## 2.21.5 (2026-08-17)

**Maintainer drift Improve checks (pack self-audit):**

- **`packVersionDocs`** — README/INSTALL/START_HERE vs root `VERSION`
- **`auditVersionDocs`** — extended scan to `pack/docs/README.md`, `AGENT_WORKFLOW.md`
- **`packReferenceConfig`** — `docs/AUDIT.config.json` must match `AUDIT.config.pack.reference.json`
- **`installedVsSource`** — workspace vs `~/.cursor/AgentStarterPack` manifest/file drift
- **Section N** enabled for pack — git hints on VERSION/changelog/manifest edits

## 2.21.4 (2026-08-17)

**Pack root resolution (Fix):**

- **`run_audit_core.ps1`** — when `AppRoot` is the pack repo (`install.ps1` + `pack/audit/manifest.json`), use it for `audit_code_checks.py` and sync/verify instead of always preferring `~/.cursor/AgentStarterPack`

## 2.21.3 (2026-08-17)

**Maintainer doc drift (Improve):**

- **`auditVersionDocs`** in `AUDIT.config.json` — machine **Improve** when README/INSTALL/START_HERE/AUDIT_SYSTEM cite an audit-engine version that does not match `pack/audit/manifest.json`
- Pack self-audit reference config enables this check

## 2.21.2 (2026-08-17)

**Pack self-audit:**

- Root **`docs/AUDIT.md`** + **`docs/AUDIT.config.json`** — full machine + semantic workflow on AgentStarterPack repo
- **`run_audit_tests.bat`** — `verify-audit-behavior.ps1` + `verify-audit-system.ps1` as product test gate
- **`run_audit.cmd`** + **`scripts/*`** + **`.cursor/rules/audit.mdc`** — same three-step auditor workflow as products
- **`tests/test_pack_audit.py`** — section test hook for engine smoke
- **`syncAndVerify`** enabled — self-audit run also checks pack mirror drift

## 2.21.1 (2026-08-16)

**Template drift guard:**

- **`AUDIT.config.json.template`** — full 2.21.0 `codeChecks` keys for new projects
- **`manifest.auditConfigTemplate.requiredKeys`** — `verify-audit-system.ps1` fails if template or app reference missing keys
- **`AGENT_WORKFLOW.md`** — pre-flight checklist: template + reference + manifest keys stay in sync

## 2.21.0 (2026-08-16)

**Complete-audit anti-gaming (items 1–13):**

- **Orphan scan** — disk→map: unmapped `app/*.py` → Section B Fix
- **Expanded domain map** — `docs/.audit_domain_expanded.json` resolves wildcards (`gui_*`, etc.)
- **`modulesReviewed[]`** — semantic verify requires every D–K module listed
- **Semantic freshness** — `generatedAt` vs `testsPassedAt`; `testsGitHead` must match manifest
- **Inventory** — `docs/.audit_inventory.json` auto-written; Section B `inventoryAck` must match
- **LOC improve** — modules over threshold → machine Improve by section
- **Dead code hints** — optional unused-import scan → Improve
- **Test gap hints** — modules not referenced in tests → Improve
- **Repo root paths** — Section B verifies README, PROJECT_LAYOUT, etc.
- **`audit_allowlist.json`** — documented `except: pass` lines skip static check
- **Audit receipt** — `docs/.audit_receipt.json` on successful finalize
- **Tree drift block** — semantic stale when source changed since test pass
- **Sync AutoFix** — `sync-audit-system.ps1 -AutoFix` on drift when `autoFixDrift` enabled

## 2.20.0 (2026-08-09)

**Closed remaining workflow gaps (no deferrals):**

- **Tree fingerprint** — no-git repos store `testsGitHead: tree:…` (SHA256 of test script + domain-map sources + audit config); finalize detects source changes without git
- **Legacy `__no_git__` rejected** — forces one fresh pass 1 to pick up tree fingerprint
- **Audit phase timing** — `docs/.audit_timing.jsonl` appended each run (phases: tests, code_checks, semantic, sync_verify, totalSeconds)
- **Behavior fixture `run_tests_stub.bat`** — instant pass 1 for acceptance tests
- **Behavior steps 18–19** — full auditor E2E (pass 1 → semantic → finalize exit 0) + timing log verification
- **`AUDIT.md.template`** — three-step workflow for new projects
- **Gitignore / Section L** — `docs/.audit_timing.jsonl` in artifact list (template + fixture + bootstrapped apps)

## 2.19.0 (2026-08-09)

**Gaps found in follow-up review (not caught by 2.18.0 verify alone):**

- **FinalizeOnly wiped `testsGitHead`** — code-check manifest rewrite dropped test-pass proof before `Update-ManifestMachineFixes`; finalize could not be repeated and broke step 3 economics
- **Git HEAD lookup** — finalize gate now uses **`RepoRoot`**, not parent of app folder (behavior fixture path was wrong)
- **No-git repos** — when git unavailable, step 1 stores `testsGitHead: __no_git__` so finalize works; documented limitation (cannot detect tree changes without git)
- **Behavior step 17** — manifest proof preserved across FinalizeOnly
- **Doc drift** — `audit.mdc`, `audit-protocol.mdc`, `agent-defaults-always.mdc`, reference app `AGENTS.md` / `AUDIT.md` aligned to three-step workflow

## 2.18.0 (2026-08-09)

**Process gap (why live audit exposed workflow bugs we missed):** verification targeted `verify-audit-system.ps1` + behavior fixture — not end-to-end **auditor economics** (double full test run, who owns semantic report). Fixed in this release.

- **`-FinalizeOnly` / `finalize_audit.cmd`** — step 3: skip tests when manifest has `testsPassedAt` + `testsGitHead` and HEAD unchanged; still runs machine + semantic verify + harness
- **Auto-write semantic template** after machine pass when file missing
- **`AGENT_WORKFLOW.md`** — one audit two commands; artifact ownership table
- **Skill rewrite** — three-step workflow; finalize as completion gate
- **Behavior step 16** — finalize blocked without manifest test proof

## 2.17.0 (2026-08-09)

- **Section L harness verify on complete pass** — `runLegacyVerify: true`; `verify-audit-system.ps1` runs only when semantic verify **and** sync drift both pass (skipped otherwise with explicit reason)
- **Docs aligned** — `AUDIT.md` L + machine layer table; `AGENT_WORKFLOW.md` prerequisites table (what unlocks harness verify vs product Fix lines)
- **Opening banner** — `run_audit_core` header matches "machine + semantic gate"

## 2.16.0 (2026-08-08)

Optional hardening from live-audit follow-up:

- **Behavior steps 14–15** — `auditGateFixes` manifest shape; gate fix patterns not bucketed under L
- **Domain map dedupe** — duplicate module names in a row collapsed (self-test)
- **Stale logs → Fix** — aligned with cache cruft (Section B machine layer)
- **Semantic guidance** — printed on any semantic verify failure (not only missing file)
- **Skip verify-audit-system** — when any `^Semantic report` fix exists (broader than missing-only)
- **Manifest** — initial write includes empty `auditGateFixes: []`; invalid semantic JSON → gate not L

## 2.15.0 (2026-08-08)

Live product audit hardening (reference app run):

- **`exec-call` pattern** — `(?<!\.)exec\(` excludes Qt `.exec()` false positives
- **`auditGateFixes`** in manifest — global blockers (semantic missing, incomplete audit) no longer mapped to Section L
- **Semantic missing guidance** — `run_audit_core` prints template cmd + section count + verify/re-run steps
- **`runLegacyVerify` default false** — full `verify-audit-system` skipped during product audit unless enabled; also skipped when semantic gate incomplete
- **Manifest** — copies `machineFixesBySection` from code-check JSON; merges at exit via `Update-ManifestMachineFixes`
- **Cache cruft** — `__pycache__` / `.pytest_cache` promoted to **Fix** (was Improve)
- **Report banner** — "machine + semantic gate"; ASCII hyphen for console encoding

## 2.14.0 (2026-08-08)

- **`domainMap.moduleSearchDirs`** — domain map module existence checks search extra dirs (e.g. `scripts/`) before flagging missing
- **Skill** — documents **`machineSectionsWithFixes`** quick scan in manifest

## 2.13.2 (2026-08-08)

- **Domain map module check** — runs when `domainMap` config is absent (behavior fixture + minimal projects)
- **Behavior step 2** — `$null -eq` for empty `machineSectionsWithFixes` array

## 2.13.1 (2026-08-08)

- **Behavior fixture in `packMirror`** — stub domain modules + config synced Desktop ↔ installed (fixes behavior steps 8/10 drift)
- **Behavior step 12** — uses temporary missing `catalog_cache.py` (not forbidden rule on non-checklist section L)
- **Behavior step 3 cleanup** — removes stale `.audit_agent_manifest.json` after SkipTests probe

## 2.13.0 (2026-08-08)

- **`machineSectionsWithFixes`** — sorted section letters in JSON output + agent manifest (quick scan for agents)
- **Section L gitignore check** — `gitignoreAuditArtifacts` in config; blocks committing `.audit_*` reports
- **Static patterns** — optional `allowLineRegex` per rule; template adds `yaml.load` / `pickle.loads` (section K)
- **Reference app config** — L requires `build_ci.bat` phrase in AGENTS.md (via existing agentsMd list expansion in reference project)

## 2.12.0 (2026-08-08)

- Semantic verify reads **`machineFixesBySection`** from manifest (merged with live machine checks) when blocking clean summaries

## 2.11.0 (2026-08-08)

- **`machineFixesBySection`** in agent manifest — per-section machine fix list; semantic report cannot claim clean when populated
- **`run_audit_core.ps1`** merges all machine Fix lines into manifest before exit
- **Section B** — optional `onedriveDoc` path check in config
- Semantic template instructions reference `machineFixesBySection`

## 2.10.0 (2026-08-08)

- **Domain map module existence** — reverse check: every concrete `*.py` in domain map must exist on disk (sections D–K)
- **Section test paths** — missing `sectionTests` files prefixed with section letter (feeds semantic vs machine alignment)
- **Section K** — static pattern for possible hardcoded credentials

## 2.9.0 (2026-08-08)

- **Semantic vs machine alignment** — semantic report cannot say "Nothing found." for a section when machine checks already flagged that section (`semanticBlockCleanWhenMachineFails`)
- Refactored machine fix collection via `collect_code_machine_fixes()` (shared by verify + main)

## 2.8.0 (2026-08-08)

- **Sync newer-wins** — `sync-audit-system.ps1` reconciles Desktop ↔ installed by **newer mtime** when hashes differ (fixes stale Desktop overwriting installed edits)
- **Section C machine check** — packaging files, bundled runtime when dist exists, forbid duplicate root DebuggingTools
- **Section B machine check** — `layoutRequiredPaths` vs PROJECT_LAYOUT
- **Section K static patterns** — `eval(`, `exec(`
- **verify-audit-system** — fails if `AUDIT_SYSTEM.md` / changelog version ≠ manifest
- **Behavior steps 2 + 11** — machineCoverage `agentFocus` / `machineCheckCount` shape

## 2.7.0 (2026-08-08)

- **`run_audit.cmd` requires semantic report** — after full tests pass, `run_audit_core.ps1` runs `--verify-semantic-report`; missing/invalid report fails the audit
- Config: `semanticReportRequiredInRunAudit` (default true)
- **Expanded `machineCoverage`** — maps all enabled config capabilities per section; adds `machineCheckCount` + `agentFocus` hints
- **Section F machine check** — AGENTS.md portable-first policy phrases
- **Section M HTML scan** — stale path patterns in `docs/*.html` mockups
- **Section K static patterns** — `subprocess shell=True`, `os.system(`

## 2.6.0 (2026-08-08)

- **Evidence-required semantic schema** — each section has `evidence[]` (`type` + `ref`); verify checks array shape and that `file`/`test` refs exist
- Config: `semanticReportRequireEvidence`, `semanticReportEvidenceMinWhenNotClean`, `semanticReportEvidenceRequireFileWhenNotClean`
- **Section M machine check** — `sectionMachineChecks.M` flags hardcoded `vX.Y.Z` in docs when `versionSync` canonical differs
- Behavior self-test step 10: evidence validation
- Multi-agent consensus — **not planned** (explicitly scrapped)

## 2.5.0 (2026-08-08)

- **Semantic cite validation** — non-clean summaries must include file/behavior cites or verify fails
- **Section L machine checks** — forbidden rules, duplicate skill, AGENTS.md phrases
- **Section N git hint** — recent VERSION commits block clean "Nothing found." in semantic report
- **machineCoverage** in agent manifest — maps checklist bullets to machine vs semantic
- Template scripts: `verify_semantic_audit.cmd`, `write_semantic_audit_template.cmd`

## 2.4.0 (2026-08-08)

- **Full A–N manifest** — parsed from `AUDIT.md` checklist headings + config hints + domain map
- **Machine-verifiable semantic report** — `docs/.audit_semantic_report.json` + `verify_semantic_audit.cmd`
- **`-SkipTests` lightweight** — skips import smoke/static scans; still fails incomplete
- Reference app `semanticReviewHints` extended to sections A–C, L–N

## 2.3.0 (2026-08-08)

- **Loop-back protocol for all projects** — `loop-back-protocol.mdc` (alwaysApply) + generic section in `AGENT_WORKFLOW.md`
- Repeat errors / same questions → re-read workstream start, validate state, diff intent vs reality; not audit-only
- Fix/Improve report format remains **audit-only**; other projects use project-appropriate format

## 2.2.0 (2026-08-08)

- Added **`AGENT_WORKFLOW.md`** — pre-flight, gap = Fix/Improve only, loop-back protocol
- Added **`AUDIT_SYSTEM_CHANGELOG.md`** (this file) — settled decisions log
- Skill + rules: any gap (process, coverage, semantic, tooling) → **Fix** (remove) or **Improve** (mitigate); no third category
- Loop-back: repeated “still broken” / “anything else” → re-read thread start + this changelog + run verify before editing

## 2.1.0 (2026-08-08)

- **One standard only:** full `run_audit.cmd` — never `-SkipTests` for an audit
- Fixed JSON parse in `run_audit_core.ps1` (multi-line output from `audit_code_checks.py`)
- Fixed domain-map parser for multi-module table rows
- Agent manifest = union of domain map + `sectionTests` + `semanticReviewHints`
- Added `verify-audit-behavior.ps1` + `pack/audit/behavior-fixture/`
- Removed orphan `pack/templates/AUDIT.md.template`; canonical stub: `pack/templates/docs/AUDIT.md.template`
- Added `sync_audit_system.cmd.template` to manifest push list
- Removed dead config `runSectionTestsWhenSkipFull`
- Skill: no `-SkipTests` loophole; cite every manifest section in report
- `install.ps1`: do not copy `agent-code-audit` skill into projects

## 2.0.0

- Manifest-driven sync (`pack/audit/manifest.json`)
- Replaced Phase A/B + add-ons menus with Fix + Improve only
- `AUDIT.config.json` machine checks + `audit_code_checks.py`
- Forbidden: overlays, `code-audit-checklist.mdc`, `run_tests_with_timeout.bat`

## 1.4.0 and earlier (deprecated)

- Phase A/B protocol, add-ons menus, project overlays — **removed**, do not restore

---

## How to add an entry

```markdown
## X.Y.Z (YYYY-MM-DD)

- What changed and **why** (one line per decision)
- Breaking changes for agents or projects
```

Then: `sync-audit-system.ps1` → `verify-audit-system.ps1` exit 0.
