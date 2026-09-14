# Guard proof plan — WQ-443

**Goal:** a behavior step cannot be added to `pack/scripts/verify-audit-behavior.ps1` without a
control that proves the step is **able to fail**.

**Status:** **through Phase 5** (engine 2.22.113) — every phase is done. Report progress as "through Phase N".
**The seal is doing its job:** step **83** (WQ-476, engine 2.22.120) is the fifth step added since the
registry closed, and like 74, 80, 81 and 82 before it, it arrived with an executable mutation rather than
an exemption. That is the whole point of pinning the seal at 70 — a new step cannot inherit grandfathering.
Step 83's mutation is worth reading as a template for the shape: it points the offload detector at a
heading no message carries, so the hook still parses its payload, still writes its log, still exits 0 —
and silently approves every offload. **A control whose failure mode is silence needs a mutation that
produces silence**, not one that breaks it loudly.
**Owning queue row:** `docs/WORK_QUEUE.md` → **WQ-443** (Active, Next).
**Convention rule:** `pack/rules/generic-deep-task-execution.mdc` (depth), this plan (mechanism).

---

## The problem, stated precisely

Six guards in a single day reported success while observing nothing: a zip read with the wrong
separator, an in-process capture of `Write-Host`, a planted defect that was a syntax error, three
`.Replace(a,b,1)` no-ops, `-Include` against `-LiteralPath` matching everything twice, and an install
arm masked by a later sync step. None was *wrong* in the sense of asserting something false. Each
asserted something true about an input it never actually examined.

The discipline that catches this — plant the defect, watch the guard go red, then restore — is
already applied by hand, repeatedly, and it works. It has caught defects **before** they shipped
(step 66's fourteen controls, step 67's contradicting controls, step 70's recursion). What it has
never had is enforcement: the suite has 70 steps, and nothing stops number 71 from arriving with no
control at all.

## Why a text scan cannot be the mechanism

The obvious implementation — scan each step block for evidence of a planted defect — was tried
first and **abandoned on evidence**. A heuristic classifier over all 70 steps (searching for plant
wording, failing exit codes, and `[FAIL]` reads) misjudged **step 69**, a step written the same week
with seven explicit controls including two positive ones. It scored `NONE`.

The reason is not a weak regex. There is more than one legitimate idiom:

| Idiom | Shape | Example |
|---|---|---|
| **Plant / restore** | Write a defective fixture, run the real guard, require `[FAIL]`, restore | Step 68 (five planted load claims) |
| **Expectations table** | Rows of `@{ label; want = $true/$false }`, run the function, compare | Step 69 (`Test-PackGitRepo`, 7 controls) |
| **Negative fixture** | A fixture built wrong from the start; assert non-zero exit | Step 3, step 16 |

A scan wide enough to accept all three accepts prose that merely *claims* a control, and a scan
narrow enough to reject the claim rejects real steps. **Text cannot distinguish a control that runs
from a comment that says one does.** Only running it can. That is the whole design constraint, and
the reason this plan builds a registry and a mutation runner instead of a scanner.

Consequence worth stating plainly: **the current true coverage number is unknown**, and no command
can produce it. It is established by human review, one step at a time, recorded in the registry —
which is Phase 1 and Phase 5, not a measurement to be run once.

---

## Design

Three artifacts, each with one job.

1. **Registry** — `pack/audit/behavior-controls.json`. Every step number in the suite appears
   exactly once, as either `proven` (carries a machine-applicable mutation) or `exempt` (carries a
   reason from a closed vocabulary). The registry, not the script text, is the source of truth for
   "does this step have a control".

2. **Coverage guard** — a new step in the suite. Asserts the registry and the suite agree: every
   announced step is registered, every registered step exists, exactly once each. This is an exact
   comparison of two lists, not a heuristic, which is why it is sound. It makes a control
   **required**.

3. **Mutation runner** — `pack/scripts/verify-guard-proofs.ps1`, run by maintainers, **not** in the
   audit's hot path. For each `proven` entry: copy the pack, apply the mutation to the copy, run the
   suite there, require the named step to report `[FAIL]`, discard the copy. It makes a control
   **proven** rather than declared.

### Why a copy and not the live tree

A mutation that fails to restore would leave a defect in the pack indistinguishable from a real one,
and the restore path is exactly the code most likely to be wrong on first write. Copies cost minutes;
a corrupted checkout with no version control (this pack keeps none by decision, WQ-459) costs the
tree.

### Anti-mute devices

This repo's own lesson: *a checker without exclusions gets muted within a week* — and its converse,
that an exclusion list which accepts everything is the same thing as no checker. Both apply here,
because seeding will mark most existing steps `exempt`.

- Exemption **reasons are a closed set**, and `grandfathered-pre-wq443` is **closed to new entries**.
  A step added after this plan ships may only claim `not-applicable` with a written justification.
- The coverage guard **prints the exempt count every run** as visible debt. Debt that is reported
  shrinks; debt that is silent is what this plan exists to prevent.
- **The exempt rows are declared as a list, and the list is compared to the rows** (`exemptSteps`,
  WQ-467). A printed count is not a check: three rows once changed status with no edit anyone could
  account for, and the count moved with them without disagreeing with anything. Steps are named
  rather than totalled because a count cannot see a swap — one row retrofitted while another
  regresses keeps the total intact. Both directions fail, so a status change has to be edited in two
  places at once, and that second edit is the record of why it changed.
- Phase 5 retrofits the grandfathered set under its own queue id, so the backlog cannot be closed by
  declaring victory in this plan.
- **A scan needs a floor on what it found.** Where the expected result is zero findings, a blinded
  scanner and a clean tree produce identical output, so the step must also assert that it *looked* at
  something — a minimum count of inputs, not just a clean verdict. Step 81 proved the point on its
  first run: a parameter that rejected blank lines made every document fail to bind, and the scan
  reported nothing; the count floor was the only arm that noticed. Step 61 still has this gap and
  step 80 closed it with a fixture.
- **A guard that must be able to fail will print failures that are not failures, and those have to be
  contained.** Planting a defect and watching the guard go red is the mechanism this whole plan rests
  on, so the suite prints `[FAIL]` lines from fixtures by design — and one of them reached a
  certification report as though the pack had failed (WQ-472, step 82). The containment rule: an
  expected-fail arm **captures** its child with `*>&1` and asserts on the text. Not `2>&1`, which
  cannot touch `Write-Host` and therefore neither captures nor discards, and never by suppressing the
  child, which is the WQ-463 defect in the other direction. Enforced from the parent, since only the
  parent sees both the exit code and everything the child wrote.

---

## Phase checklist

Build order equals runtime order: the registry is read by both consumers, the guard makes
declaration mandatory, attribution is what lets a runner name a failing step, and the runner
upgrades declarations to proofs.

- [x] **Phase 1 — Registry.** `pack/audit/behavior-controls.json`, 71 entries, seal 70, in
      `packMirror`.
  - [x] 1a `[required]` Schema and vocabulary fixed, documented in this file. **`proven` was dropped
        during implementation** in favour of `mutation`: a proof is a run outcome, and a status field
        saying "proven" is a claim that goes stale the moment the runner is not run.
  - [x] 1b `[required]` All 70 steps seeded as `exempt` / `grandfathered-pre-wq443`. **Nothing is
        seeded `proven`**, because `proven` requires a mutation the runner can execute and the runner
        does not exist until Phase 4 — marking a step proven before then would be the claim this plan
        exists to stop. An optional free-text `note` may record where a step's existing control lives,
        to aim Phase 5; a note is not a status.
  - [x] 1c `[required]` Register the file in `manifest.json` → `packMirror`, so sync, export and the
        installed copy carry it. **Not `listConsumers`** — that map declares readers of manifest
        *keys*, and this is a separate file, so the entry would be a category error. The registry
        cannot go unread by construction instead: the Phase 2 guard is its reader and fails when the
        file is missing or malformed.
- [x] **Phase 2 — Coverage guard.** Behavior **step 71**, logic in
      `Get-PackBehaviorControlProblem` (`verify-lib.ps1`) so the step tests it in-process. Accepts a
      correct pair, catches **13** planted defects, asserts the seal, and reports the grandfathered
      count as `[INFO]` every run.
      **It failed twice on its own controls first, both times in the shape it polices:** its fixtures
      were literal announcements, so the checker read its own test data as real steps (73 for 71);
      then, rewritten in escaped form, two plants became inert because `Write-Host `"` does not match
      the pattern. Fixtures are now assembled from fragments and declare the announcement count they
      must parse to.
- [x] **Phase 3 — Step attribution.** The runner has to know *which* step went red, and
      position-based parsing of `[FAIL]` lines is **not enough** — measured, not assumed. A trial
      parse during Phase 1 attributed five `[FAIL]` lines to two steps while the suite's own summary
      said **one** failure: four belonged to step 57's planted controls, which invoke a child verify
      whose output contains the identical `[FAIL]` prefix. A runner trusting position would credit a
      step for a failure its own control printed on purpose — the WQ-443 shape, reproduced inside the
      WQ-443 fix.
      **Design replaced before implementation, on a measurement.** The original plan here was a
      `Step` helper plus a mechanical rewrite of all 71 announcements. That is unnecessary: `Fail` can
      resolve its own step from `Get-PSCallStack`, by taking the **last frame belonging to the suite
      file** — the top-level scope — and mapping that line to the last announcement at or before it.
      Probed on both hosts with identical results, including the case that looks hardest: a `Fail`
      raised inside a helper function defined hundreds of lines earlier attributes to the *step that
      called the helper*, not to the helper.

      Two things fall out. The 71-line sweep disappears, and with it the risk of a mechanical rewrite
      changing output. More importantly the child-`[FAIL]` problem disappears **by construction**:
      attribution no longer reads output at all, so a planted control's child verify cannot be
      mistaken for a failure — only a real `Fail` call is ever recorded.
  - [x] 3a `[required]` `Resolve-PackBehaviorStep` in `verify-lib.ps1` — pure function, line to step,
        testable in-process
  - [x] 3b `[required]` `Fail` records step-attributed failures; `-ResultsPath` writes them as JSON
        for the Phase 4 runner. Printed output stays **unchanged**, so nothing that greps `[FAIL]` moves
  - [x] 3c `[required]` Behavior **step 72**, with its own mutation spec — it is above the seal, so it
        could not be grandfathered.
        **It failed on its first run, and the failure was in the check rather than in the thing
        checked.** `$MyInvocation.ScriptLineNumber` is **0** at top-level scope, and 0 is not an error
        value here — it resolves to "before every announcement" and attributes nothing. Meanwhile `Fail`,
        already using the call stack, attributed that very failure to step 72 correctly. Both now go
        through one helper, `Get-SuiteTopLevelLine`, so the check and the mechanism it checks cannot
        drift apart, and a line of 0 is failed explicitly instead of resolving to nothing.
- [x] **Phase 4 — Mutation runner.** `pack/scripts/verify-guard-proofs.ps1`: copy, mutate, run,
      require the named step red, discard. Maintainer-invoked, **not** in `run_audit.cmd` — each entry
      costs a full suite run and the audit already runs the suite once.
  - [x] 4a `[required]` `Get-PackMutationSpecProblem` — a spec must match **exactly once**. Zero means
        stale, more than one means the runner cannot say which site it broke. An unapplicable spec is an
        error, never a skip, because a no-op mutation leaves the suite green and green reads as proof.
  - [x] 4b `[required]` `Test-PackMutationOutcome` — the question is not "did the suite fail" but "did
        *these* steps fail". A mutation that breaks something unrelated must not count.
  - [x] 4c `[required]` A **green baseline** run before any mutation. Without it, a copy that fails for
        an environmental reason makes every mutation look proven. This is the control on the runner.
  - [x] 4d `[required]` Behavior **step 73** plants against both judgements in-process (8 + 8 controls)
        and asserts the runner uses them. It must **not** invoke the runner: the runner runs this suite,
        which is the recursion that killed step 70. The last arm is the standing guard on that.
  - [x] 4e `[required]` **Re-attribution**, which exists because the runner's first real execution
        reported step 72 as **not proven**. Step 72's mutation disables `Resolve-PackBehaviorStep` — the
        very code `Fail` uses to say which step failed — so the suite failed exactly as designed and
        recorded every failure with no step at all. A proof defeated by the thing it was proving. `Fail`
        now records the raw **line** as well, and the runner recovers the step by parsing the copy's
        suite text with its **own** unmutated functions, so only the text comes from the blast radius.
        `Resolve-PackMutationFailureStep`, 4 controls in step 73.
  - [x] 4f `[required]` **Tree stamp.** The runner copies the live tree once per entry, so an edit
        mid-run means the copies were not the same pack. On the first execution two unrelated steps (23
        and 31) failed in two of three runs, reading exactly like collateral from a broad mutation; they
        were a version bump being edited while the copies were taken. The runner now fingerprints the
        tree at both ends and warns when it moved. On a quiet tree the collateral was gone.

**Phase 4 evidence** (quiet tree, engine 2.22.85): baseline copy green, then **3 of 3** proven —
step 71, step 72 (via re-attribution of 3 unattributed failures), step 73 — runner **exit 0**.
- [x] **Phase 5 — Retrofit** (**`WQ-462`**, complete: **69 of 70 proven, 1 not-applicable** — engine 2.22.113).
      Convert grandfathered
      exemptions to `mutation` — not `proven`, which does not exist as a status. Tracked under its own
      id, and not closable by Phases 1–4.
      **First batch, 2.22.86:** steps 47, 48, 49 — 6 of 6 declared mutations proved, runner exit 0.
      Three constraints learned there, all of which will recur:
  - **A spec cannot hold text another guard bans.** Step 49 bans the retired synonym for *handoff* in
        every shipped file, `.json` included, so storing its spec made the pack fail step 49 — caught by
        the **baseline** before any mutation ran. This plan cannot spell the word either; only the
        changelog may, which is one of the two files step 49 has always exempted. `behavior-controls.json` joined the two files step 49 already exempts
        for the same documented reason. **Step 68 (load-path claims) is the next case this will hit.**
  - **Prefer a doc over a rule.** Mutating `pack/rules/*.mdc` also desyncs the copy in
        `.cursor/rules/`, so the rule-sync step fails alongside the step under test and the proof reads
        as ambiguous.
  - **Watch the occurrence count.** Step 48's gated `pause` line appears twice in its launcher, so its
        spec replaces a neighbouring **comment** instead; a find matching more than once is rejected by
        design, since the runner could not say which site it broke.
  - **Batch big and prove in parallel (2.22.110).** Certification costs ~12 minutes **per release**
        and nothing per step, so a two-step batch pays that toll five times for the same work. Entries
        are isolated by construction — a pack copy each, scratch under `guard-proofs-$PID` — so lanes
        can run concurrently: one with the baseline control, the rest `-SkipBaseline`, on a **frozen
        tree**. Ten steps proved in one release; four lanes took 8.7 minutes where serial would have
        taken ~33. The contention that forced a two-lane cap in 2.22.110–111 was one product defect —
        `export.ps1` staging into a day-granular `%TEMP%` path it then deletes — and after the `$PID`
        fix, 23 executions across three- and four-lane runs showed none of it. **Four lanes, with two
        caveats:** a lane that runs `-SkipBaseline` cannot attribute its own failures, so prefer a
        baseline per lane over one shared control; and prove any step whose subject *is* concurrency
        serially, since contention could otherwise manufacture the failure the proof is looking for.
  - **Re-prove anything taken without a live green control.** Twelve proofs from 2.22.110–111 were
        re-taken in 2.22.112 for exactly this reason and all twelve held — but "held" was not knowable
        until they were re-run, and a proof whose baseline failed is not evidence of anything.
  - **A mutation that cannot reach the behaviour is a finding, not a failure (2.22.110).** Step 38
        stayed green under a 250ms→60s change to the session hook's stdin drain because the drain never
        runs — a scriptblock cast to `[Func[string]]` has no runspace on a threadpool thread, so the
        task faults in ~6ms. The step passes for a reason unrelated to its subject. Record it
        (`WQ-473`) and leave the step **exempt**; do not weaken the mutation until it goes red.
  - **Fixing the blocker is the batch (2.22.112).** Steps 1 and 38 were both proven without writing a
        better mutation: the specs were already right, and what changed was a child's stderr killing
        its caller (`WQ-475`) and a hook whose drain could not be made to work (`WQ-473`). Expect an
        exempt step's blocker to be product code, not spec quality — and expect the fix to break
        something the baseline catches. Three regressions came out of that hook edit, including a
        detector that read comments as code and declared the shipped template stale.
  - **A guard that hangs does not fail (2.22.112).** Restoring the hook's unbounded read left a run
        going for half an hour instead of failing in 20s, because the arm that runs the hook on fresh
        context had no bound and the runner had no timeout. Both now do — `-TimeoutMinutes`, default
        12, reporting **hung** rather than *did not fail*. When a mutation restores a hang, check that
        every consumer of the hung thing is bounded, not only the arm that names it.
  - **A step that cannot be expressed is not a step that cannot fail (2.22.113).** Steps 4 and 7
        survived eighteen batches as exempt because a spec could only *replace text*, and their
        subjects are a file's absence and a file's presence. The gap was in the runner's vocabulary,
        not in the guards. Before writing off a step as unprovable, ask whether the mutation language
        can describe the defect at all — `create` and `delete` exist because the answer was no.
  - **A guard with no subject is the defect, not an exemption (2.22.113).** Step 15 matched literals
        against regexes written out beside them. It could not fail, it had passed through every
        rewording of the messages it named, and the honest fix was to give it a subject rather than
        to record why it had none. When a retrofit finds this, rewrite the step in the same release
        and prove the rewrite — `not-applicable` is for a subject the runner cannot reach, not for a
        step that never had one.
  - **The proof reads what the step reads, which is how it catches a step reading the wrong thing
        (2.22.113).** Step 34's mutation came back green because the project it inspected had never
        contained the file being mutated: a list argument sent through `-File` loses every element
        after the first, so a step naming three editors bootstrapped one and reported OK for all
        three. No review had found it in the months it shipped. A mutation that cannot make a step
        fail is worth as much as one that can — treat green as a finding and chase it before
        weakening the spec.
      Batch order: load-bearing guards first (5, 23, 31, 53, 57, 68), not the lowest numbers.
      **Step 62 cannot be proven on a checkout with no git** — it reports `[SKIP]`, so any mutation
      there is inert here and must stay `exempt` with that reason rather than be declared proven.
      **Phase 5 evidence** (engine 2.22.113): steps 4, 7, 15, 18, 23, 34 proven in three lanes, each
      with its own green baseline, runner exit 0 in all three. Registry: 79 mutation, 1 exempt
      (`not-applicable`), 0 grandfathered.

## Fail-fast workflow (2026-09-13)

When a proof or environment check fails, **stop, fix, re-run narrow** — do not burn a full registry
run to learn the same thing at the end.

```powershell
# One step (~2-3 min) after a fix; profile checked after every mutation
powershell -NoProfile -ExecutionPolicy Bypass -File pack\scripts\verify-guard-proofs.ps1 `
  -PackRoot (Get-Location).Path -Only 60 -SkipBaseline -FailFast

# Full registry — only on a quiet tree, after sandbox + recurring-drift UX (WQ-481, Done 2026-09-13)
powershell -NoProfile -ExecutionPolicy Bypass -File pack\scripts\verify-guard-proofs.ps1 `
  -PackRoot (Get-Location).Path -FailFast
```

| Switch | Effect |
|--------|--------|
| **`-Only N,M`** | Prove only those steps (use after touching one guard) |
| **`-SkipBaseline`** | Skip the unmutated control when the live suite is already green |
| **`-FailFast`** | Exit on first failed proof, profile drift, or pack-tree edit mid-run |

**Environment checks (WQ-481):** each suite job runs with `AGENT_STARTER_PACK_INSTALL_ROOT` pointing
at a sandbox under the work dir; the runner sets the same override on the parent process. Profile
stamp is compared **after every mutation**, not only at the end. A lock file at
`%TEMP%\guard-proofs.lock` records PID and start time so a second run can refuse to start while one
is active. **`sync-audit-system.ps1 -VerifyOnly`** keeps `sync-drift-session.json` under
`Get-AgentStateRoot`; when the same installed path drifts on a second verify-only run it prints
`[RECURRING DRIFT]` and cites an active guard-proof lock when present (**behavior step 85**).

**Do not overlap with other audits.** A concurrent `run_audit.cmd` on a pack checkout with
`syncAndVerify.autoFixDrift` enabled will sync into `%USERPROFILE%\.cursor\AgentStarterPack\` and
look exactly like a mutation leak. The S27 publish-path probe did this once while step **26** was
proving; re-run the proof alone and the stamp held.

## Evidence required per phase

A phase is done when its own controls pass **and** the full gate is green: `run_audit_tests.bat`
exit 0, then `run_audit.cmd` (never `-SkipTests`) → semantic → `finalize_audit.cmd` exit 0 with
`verify-audit-system: OK`. Record the engine bump and rationale in
`pack/docs/AUDIT_SYSTEM_CHANGELOG.md`, and the WQ-443 status in `docs/WORK_QUEUE.md`.
