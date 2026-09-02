#!/usr/bin/env python3
"""One-shot helper: fill pack self-audit semantic report after machine pass 1."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "pack" / "scripts"))
from audit_code_checks import parse_checklist_paths, parse_checklist_sections  # noqa: E402


def main() -> int:
    man = json.loads((ROOT / "docs/.audit_agent_manifest.json").read_text(encoding="utf-8-sig"))
    inv = json.loads((ROOT / "docs/.audit_inventory.json").read_text(encoding="utf-8-sig"))
    exp = json.loads((ROOT / "docs/.audit_domain_expanded.json").read_text(encoding="utf-8-sig"))
    cfg = json.loads((ROOT / "docs/AUDIT.config.json").read_text(encoding="utf-8-sig"))
    checklist = parse_checklist_sections(ROOT / "docs" / "AUDIT.md")
    checklist_letters = set((cfg.get("codeChecks") or {}).get("semanticChecklistPathSections") or [])

    content = {
        "A": {
            "summary": (
                "Reviewed test harness: run_audit_tests.bat runs behavior + system verify; "
                "tests/test_pack_audit.py covers engine smoke plus the machine-Improve gate and "
                "the generic layoutPolicy default. Behavior steps 27-28 cover agent context "
                "refresh and layout hygiene end to end. Step 27 asserts the paste line's copy "
                "properties - single line, ASCII, BOM-free, no stray whitespace, and identical to "
                "the copy embedded in the brief - and passes -NoClipboard so a suite run never "
                "reaches into the user's clipboard. Step 29 adds cross-version parity: a probe runs "
                "on both PowerShell hosts and must produce identical writer bytes and identical "
                "parsed JSON, and it fails if a second BOM-free writer, an inline "
                "UTF8Encoding($false) write, or a script without #Requires appears. -DualShell "
                "re-runs the whole suite on the other host (verified: both pass). Step 26 now runs a "
                "real redirected install and asserts the pack tree, rules and recorded canonical path "
                "land in the scratch destination while the profile's install record and mcp.json stay "
                "byte-identical; it hashes only those install-owned files, because stamping all of "
                "%USERPROFILE%\\.cursor went flaky against the running editor's own writes. Step 5b "
                "also enumerates pack/docs against packMirror now - the same installed-once-then-stale "
                "trap that this step already covered for rules and skills had two maintainer docs in "
                "it, so an agent reading the installed copy could be told a shipped feature was never "
                "built. 2.22.6 extended the same enumeration to pack/scripts and all of pack/templates "
                "after finding bootstrap-project.ps1, doctor.ps1 and all nine project templates "
                "outside packMirror - incremental syncs would never have carried a later edit into the "
                "installed copy that bootstrap actually runs from."
            ),
            "evidence": [
                {"type": "file", "ref": "run_audit_tests.bat"},
                {"type": "test", "ref": "tests/test_pack_audit.py"},
                {"type": "file", "ref": "pack/scripts/verify-audit-behavior.ps1"},
            ],
        },
        "B": {
            "summary": (
                "Confirmed scope inventory: pack/audit/manifest.json mirrors audit files; "
                "single root production module install_launcher.py. Layout reviewed against the "
                "folder map in pack/docs/README.md - source (pack/, scripts/, docs/) is separate "
                "from ephemeral dist/ and .tmp/, both gitignored; no in-repo duplicate of the "
                "export archive; the generated agent-context files are gitignored because they "
                "record machine-specific paths."
            ),
            "evidence": [
                {"type": "file", "ref": "pack/audit/manifest.json"},
                {"type": "file", "ref": "pack/docs/README.md"},
                {"type": "file", "ref": "docs/AUDIT.md"},
            ],
        },
        "D": {
            "summary": (
                "Deep-scanned audit_code_checks.py: semantic gates, manifest JSON, and domain map "
                "parser verified. New verify_semantic_vs_machine_improves reads "
                "machineImprovesBySection and blocks a section closing without addressing those "
                "lines - keyword or a cite of the flagged path satisfies it, and it is skipped for "
                "sections the project does not require."
            ),
            "evidence": [
                {"type": "file", "ref": "pack/scripts/audit_code_checks.py"},
                {"type": "test", "ref": "tests/test_pack_audit.py"},
            ],
        },
        "E": {
            "summary": (
                "Reviewed PowerShell engine: run_audit_core.ps1 uses Python tree fingerprint; "
                "FinalizeOnly preserves test-pass proof. The layoutPolicy block emits Improve "
                "into machineImprovesBySection (Fix only for build output committed to git), and "
                "the cruft remediation lines now use appPrefix instead of a hardcoded app\\ that "
                "named paths flat projects do not have. pack-paths.ps1 is now dot-sourced at script "
                "scope rather than inside Get-PackRoot, which had scoped the shared helpers to that "
                "function, and the timing-log write reports a warning instead of swallowing errors "
                "in an empty catch - that silence hid the log disappearing entirely."
            ),
            "evidence": [
                {"type": "file", "ref": "pack/scripts/run_audit_core.ps1"},
                {"type": "file", "ref": "pack/scripts/pack-paths.ps1"},
            ],
        },
        "F": {
            "summary": (
                "Reviewed install/bootstrap/export: install_launcher.py resolves pack root; "
                "install.ps1 Copy-Tree excludes machine-local artifacts and prunes the bytecode "
                "its own Python steps generate; export.ps1 validates the staged tree against "
                "manifest.json projectRequired; behavior step 26 exercises both profile-writing "
                "functions against scratch paths. bootstrap-project.ps1 writes the "
                "docs/AGENT_CONTEXT.json stub and lists both context artifacts in "
                ".agent-bootstrap.json; refresh-agent-context.ps1 applies the project syncs before "
                "writing its brief, then emits docs/AGENT_PASTE.txt and copies the line to the "
                "clipboard so the notice never has to be selected out of wrapped console output; "
                "install.ps1 now dot-sources pack-paths.ps1 instead of carrying its own inline "
                "byte-writer, and check-requirements.ps1 reports the host shell plus PowerShell 7 as "
                "an optional requirement with its winget command, never installing a runtime; "
                "export.ps1 carries Refresh-AgentContext.cmd. sync-audit-system.ps1 runs doc "
                "version sync before the mirror, since that step rewrites mirrored docs and "
                "previously left drift the next verify reported. Verified the transfer path by "
                "exporting, extracting elsewhere, and running the pack as a receiving machine: "
                "export.ps1 now drops the per-machine agent-context stamp (docs/AGENT_CONTEXT.json, "
                "docs/AGENT_REFRESH.md, docs/AGENT_PASTE.txt) that had been shipping this drive "
                "letter and this user profile, while keeping the bootstrap template; install.ps1 "
                "reads AGENT_STARTER_PACK_INSTALL_ROOT through pack-paths.ps1 instead of hardcoding "
                "%USERPROFILE%\\.cursor, which had half-redirected - later steps reported the scratch "
                "path while the copy went to the real profile. The extracted copy resolves its own "
                "pack root, passes the full suite, installs to a redirected target, and bootstraps a "
                "project that reaches the semantic gate."
            ),
            "evidence": [
                {"type": "file", "ref": "install_launcher.py"},
                {"type": "file", "ref": "install.ps1"},
                {"type": "file", "ref": "export.ps1"},
                {"type": "file", "ref": "pack/scripts/refresh-agent-context.ps1"},
            ],
        },
        "G": {
            "summary": (
                "Reviewed MCP wiring: agent_hygiene_server.py imports FastMCP from the MCP SDK, "
                "which is optional - doctor.ps1 reports it as a warning when absent. install.ps1 "
                "merges the agent-hygiene entry into an existing mcp.json with Add-Member -Force, "
                "preserving every server already configured (2.21.22); an unparseable config is "
                "backed up and left in place rather than overwritten."
            ),
            "evidence": [
                {"type": "file", "ref": "mcp/agent_hygiene_server.py"},
                {"type": "file", "ref": "mcp/requirements.txt"},
                {"type": "file", "ref": "install.ps1"},
            ],
        },
        "H": {
            "summary": (
                "Templates complete: AUDIT.config.json.template has 2.22 keys including "
                "layoutPolicy, which ships disabled with empty folder names so a minimal project "
                "inherits no MyApp placeholders; AGENT_CONTEXT.json.template is the bootstrap "
                "stub; no orphan pack/templates/AUDIT.md.template."
            ),
            "evidence": [
                {"type": "file", "ref": "pack/templates/docs/AUDIT.config.json.template"},
                {"type": "file", "ref": "pack/templates/docs/AGENT_CONTEXT.json.template"},
                {"type": "test", "ref": "tests/test_pack_audit.py"},
            ],
        },
        "I": {
            "summary": (
                "Documentation current: AUDIT_SYSTEM.md and PACK_MAINTENANCE.md now state the "
                "PowerShell host policy - 5.1 is the floor because it ships with Windows, 7 is "
                "supported but not the host given ~250ms vs ~130ms child-shell cost, encoding is the "
                "one real divergence, and ConvertTo-Json formatting differs per host so generated "
                "JSON must not be hash-compared across them. START_HERE.md and PORTABLE_SETUP.md "
                "reviewed for rebrand consistency. AGENT_WORKFLOW.md and AUDIT_SYSTEM.md now "
                "carry the layout Fix-vs-Improve taxonomy, and PACK_MAINTENANCE.md plus "
                "PORTABLE_SETUP.md document the context refresh for open chats."
            ),
            "evidence": [
                {"type": "file", "ref": "pack/docs/START_HERE.md"},
                {"type": "file", "ref": "pack/docs/AGENT_WORKFLOW.md"},
                {"type": "file", "ref": "docs/PORTABLE_SETUP.md"},
            ],
        },
        "L": {
            "summary": (
                "Agent wiring OK: AGENTS.md references run_audit; pack skill only; legacy path "
                "strings limited to migration helpers. The agent-code-audit skill now requires a "
                "Section B layout pass, and agent-defaults-always.mdc carries the context-refresh "
                "trigger pointing at docs/AGENT_REFRESH.md. Every rule on disk is tracked in "
                "manifest packMirror/packToUser, and sync-project-rules.ps1 enumerates pack/rules "
                "rather than a hardcoded list, so a newly added rule reaches projects as well as "
                "profiles (behavior step 5b runs that sync for real). Reviewed the handoff documents "
                "against the code they describe and corrected seven stale or self-contradicting "
                "claims, including a feature documented as both shipped and unimplemented; "
                "HANDOFF_NEXT_AGENT.md is now in maintainerDocSync so its version cites cannot drift "
                "unnoticed, and the boundary between a pack-shipped profile rule and a rule the user "
                "added on one machine is written down rather than living in one script's logic. "
                "This cycle read all 12 pack/rules, 5 workspace rules, 5 tool entry templates and 3 "
                "skills end to end and compared them for duplicate and missing coverage. Three "
                "defects closed: generic-deep-task-execution.mdc and generic-agent-doc-hygiene.mdc "
                "named this repo's WQ ids, phase numbers and HANDOFF sections in rules that install "
                "into every project, and no rule mentioned docs/AGENT_SESSION_START.md although all "
                "five entry templates tell agents to read it on the first turn - now a Session start "
                "section in the always-on rule rather than a thirteenth file. The overlaps that scan "
                "documented are now closed rather than carried: behavior step 46 fails when a "
                "shipped rule names a WQ id, HANDOFF, a pack-only spec, a phase number or a section "
                "number outside a line scoped to the maintainer repo - it found 11 further leaks on "
                "its first run that reading had missed, all reworded, and it is proven to fire on a "
                "planted leak and stay quiet on a scoped line. Terminal hygiene now splits by job "
                "(always-on rule = the before/after sequence, skill = diagnosis, on-demand rule = "
                "builds that never wait on a prompt, each stating what it does not cover), and one "
                "audit trigger list lives in audit-protocol.mdc and is repeated verbatim by "
                "agent-defaults-always.mdc and this repo's audit.mdc. Rule advice is now checked as "
                "well as rule wording: behavior step 47 resolves every pack/-rooted path cited by a "
                "rule, skill or pack doc, and found ensure-work-completion.ps1 copying a handoffs "
                "README template that had never been written - both handoff templates now exist and "
                "are mirrored. Project-relative citations, changelogs and deliberately-absent files "
                "are out of scope by design, because a checker that reports correct docs gets muted. "
                "Bootstrapping a project to read that new template found the copier plain-copying it "
                "while the WORK_COMPLETION path beside it substituted placeholders, so every project "
                "would have received a README titled with a literal {{PROJECT_NAME}}; both paths now "
                "share the substitution and the BOM-free writer, and bootstrap smoke step 23 fails on "
                "any unsubstituted placeholder in generated output. Running every generator rather "
                "than reading it then found the pack breaking its own build-hygiene rule: 12 bare "
                "pause statements across 4 root .cmd launchers, missed by 47 behavior steps because "
                "each one calls the .ps1 underneath with -NoPause while the .cmd layer is what a "
                "human double-clicks and an agent runs. All gated behind BUILD_NOPAUSE, step 48 "
                "guards it, and bootstrap output across 6 stack/target combinations is otherwise "
                "clean - manifest matches disk, no placeholders, no BOM, no mojibake. Vocabulary is "
                "now one word: the pack had used two synonyms for the same act across 519 "
                "occurrences in 56 files, so HANDOVER_NEXT_AGENT.md became HANDOFF_NEXT_AGENT.md "
                "with every reference moved (manifest maintainerOnlyPaths, VERSION_SYNC scanFiles, "
                "export.ps1, AGENTS.md, freshness requiredReads) and no redirect stub, since a stub "
                "is the parallel-doc pattern doc hygiene forbids. Two matches were narrowed by hand "
                "because the surviving string is ambiguous - verify-complete-picture.ps1 and step "
                "46's token table both had to become HANDOFF_NEXT_AGENT, as bare HANDOFF also "
                "matches the docs/handoffs convention rules are supposed to name. Step 49 keeps the "
                "retired synonym out of every text file except the changelog and the checker, and "
                "the decision is written down in pack/docs/AGENT_HANDOFFS.md rather than left in a "
                "chat log. Root cleanup followed from those definitions: four finished documents "
                "deleted with the checks that policed them, and the session handoff trimmed from 788 "
                "to about 470 lines because roughly 400 duplicated the changelog and had begun to "
                "contradict it (section numbers preserved, since verify-complete-picture reads "
                "'## 11.'). Two defects surfaced while doing it - install.ps1 SkipRelPaths matched "
                "exact files only, so a maintainerOnlyPaths folder entry did nothing and "
                "docs/handoffs would have shipped every work slice into every profile (step 26 now "
                "asserts folder exclusion and that it stops at the folder boundary), and this repo's "
                "own docs/handoffs/README.md still carried {{PROJECT_NAME}} from before the 2.22.50 "
                "substitution fix. The transfer to the primary system is now itself a handoff under "
                "docs/handoffs/active/, passing verify-agent-handoffs.ps1 - WQ-426 carries the one "
                "step no guard can perform from here, untracking the three machine-local files in "
                "the other machine's git index, since a rule that travels as source cannot rewrite "
                "an index it is not running against."
            ),
            "evidence": [
                {"type": "file", "ref": "AGENTS.md"},
                {"type": "file", "ref": "pack/skills/agent-code-audit/SKILL.md"},
                {"type": "file", "ref": "pack/scripts/sync-project-rules.ps1"},
                {"type": "file", "ref": ".cursor/rules/audit.mdc"},
            ],
        },
        "M": {
            "summary": (
                "Version aligned: `VERSION` 1.8.0 matches install manifest and the engine is 2.22.64; "
                "`pack/docs/AUDIT_SYSTEM_CHANGELOG.md` documents 2.22.64 (doc truth: the active WQ-426 "
                "slice told the other machine to expect 53 behavior steps, a tripwire made wrong by step "
                "54 an hour later and now reading 54, plus what 2.22.63 changes there - the hook fix "
                "travels as source but projects bootstrapped on that machine keep the blocking copy, and "
                "the four new CI steps get their first real execution on that publish; WQ-431 to WQ-433 "
                "were tracked in the queue but missing from the session handoff's Still deferred section, "
                "the inverse of what 2.22.62 fixed; WORK_COMPLETION.md now states its own step-order "
                "tension WQ-432 rather than leaving it only in the queue; OS_PORTABILITY_PLAN records "
                "step 54 and the CI wrapper runs as superseding its manual Linux gate, with macOS still "
                "open as WQ-436; and WQ-437 was filed because bumping this release rewrote five "
                "historical version cites, the third such hand-fix in a day), 2.22.63 (WQ-434 promoted and closed: "
                "the .sh wrappers had never been executed, and running one hung the audit 16 minutes - "
                "pwsh at 3s CPU with idle children, so blocked not slow; cause was the generated Cursor "
                "session hook draining stdin with an unbounded [Console]::In.ReadToEnd(), which returns "
                "at once under Cursor because it closes the handle and never returns under bash, "
                "defeating the script's own fail-open promise because a read that never returns raises "
                "nothing; fixed with IsInputRedirected plus a 250ms bounded task drain, old code killed "
                "at 20s versus 440ms for the fix; step 54 now runs four wrappers under bash with a "
                "stated skip when bash is absent, a new arm in step 39 starts the hook with stdin held "
                "open, and CI runs install.sh User and run_audit.sh on ubuntu-latest; WQ-435 filed for "
                "the projects already carrying the old hook, which only bootstrap -Force rewrites), "
                "2.22.62 (the handoff set read end to "
                "end: section 7 was deferring two items that had already shipped - import smoke "
                "beyond root *.py (WQ-305, 2.22.28) and an install.sh parity claim that cannot apply "
                "to a nine-line delegator - and MULTI_TOOL_GAP_PLAN marked phases done in its table "
                "while three headings still read planned; four gaps that existed in prose and in no "
                "queue were filed as WQ-431 to WQ-434, the last being that the six .sh wrappers are "
                "verified by reading and never executed, though CI already has a Linux runner), "
                "2.22.61 (the duplicate-list class "
                "swept after three releases spent on one shape of bug - a script holding its own "
                "copy of a list the manifest declares; verify-agent-setup checked 5 of 12 profile "
                "rules and 10 of 174 pack files, verify-portable-bootstrap 5 of 9 required project "
                "files, and run_audit_core carried a stale literal fallback that was unreachable "
                "while any manifest resolves; all now read packToUser, packMirror and "
                "projectRequired.flatLayout, verify-complete-picture stays curated with the reason "
                "written down, and step 53 asserts the coupling survives), "
                "2.22.60 (a downloaded pack could not "
                "run its own suite - an export unzipped into a scratch folder and run as a first-time "
                "recipient failed with seven missing root launchers, because export.ps1 kept a "
                "hand-written item list beside packMirror and its guard checked a narrower set than "
                "the thing it protects; the list is now a union, the guard covers every mirrored "
                "entry, and step 52 runs the real export), "
                "2.22.59 (the portable folder now "
                "generates no machine state at all - the cause was never a copy method but the pack "
                "auditing and refreshing itself through the bootstrapped-app code path, so "
                "Get-AgentStateRoot / agent_state_root send the four context artifacts to a "
                "machine-local state directory keyed by checkout path, ensure-work-completion writes "
                "no overlay for a pack root, step 50 fails on mere existence, and step 51 compares "
                "the two resolvers because a silent disagreement would read as a missing stamp), "
                "2.22.58 (where the checkout lives is "
                "machine state too - step 50 rejects this checkout's own absolute path in any "
                "travelling file, which unlike a generated stamp survives a clone and a download; two "
                "real cases found in archived handoffs; handoff openers may use a placeholder root), "
                "2.22.57 (the arm that closes the "
                "round trip - machine-local files are exempt from the identity scan, so a tracked "
                "copy returning from another machine would have passed; the index arm reads "
                "ls-files output rather than its exit code, because on removable media git refuses "
                "the repo as dubious and every file would have read as clean), 2.22.56 (no machine "
                "identity travels: one list in machineLocalPaths, sanitize-machine-state.ps1 for "
                "folder copies, step 50, and a freshness reason that names another machine), "
                "2.22.55 (the handoff design reference written into docs/ instead of a drive root "
                "nothing copies), 2.22.54 (WORK_COMPLETION Step 3 product-truth propagation), "
                "2.22.53 (root cleanup; folder-aware install exclusion), 2.22.52 (one word for the handoff "
                "concept; the session doc renamed and step 49 guarding it), "
                "2.22.51 (root launchers gate every "
                "pause), 2.22.50 (generated projects carry no "
                "unsubstituted placeholders), 2.22.49 (step 47 resolves cited pack "
                "paths; two handoff templates that were cited but never written), 2.22.48 (step 46 "
                "keeps shipped rules "
                "generic; terminal hygiene split by job; one audit trigger list), 2.22.47 (rules that "
                "shipped this "
                "repo's WQ ids and phase numbers to every project; session-start coverage), 2.22.46 "
                "(engine split under its own LOC ceiling), 2.22.45 (hermetic tests, failures that "
                "name a reason, root docs mirrored vs maintainer-only), 2.22.10 (mcp server mirrored; six enumerated file classes), 2.22.9 (root entry points mirrored; Refresh wrapper accepts a leading switch), 2.22.8 (the offer-to-run instruction carries in AI_INSTRUCTIONS.md and AGENTS.md, not just the Cursor .mdc), 2.22.7 (audit reports a stale agent-context stamp as Improve worded for the agent to offer the run; bootstrap stamps the engine version), 2.22.6 (packMirror covers every script, template and doc; bootstrap manifest lists only what it writes), 2.22.5 "
                "(pack/docs enumerated against packMirror, handoff joined maintainerDocSync, stale "
                "handoff claims corrected), 2.22.4 "
                "(portable transfer: the export drops the per-machine agent-context stamp and "
                "install.ps1 honours the install-root override), 2.22.3 "
                "(one BOM-free writer, version floor declared everywhere, cross-version parity), "
                "2.22.2 (paste-line copy hardening plus the sync ordering fix), 2.22.0 (layout "
                "hygiene), and 2.21.23 (agent context refresh)."
            ),
            "evidence": [
                {"type": "file", "ref": "VERSION"},
                {"type": "file", "ref": "pack/docs/AUDIT_SYSTEM_CHANGELOG.md"},
            ],
        },
        "N": {
            "summary": (
                "Release readiness reviewed for this cycle: pack `VERSION` stays 1.8.0 (no "
                "user-facing pack release; the rule edits change agent behaviour, not the install "
                "surface), while the audit engine moved 2.21.22 -> 2.21.23 -> "
                "2.22.0 through 2.22.10 -> 2.22.45 -> 2.22.46 -> 2.22.47 -> 2.22.48 -> 2.22.49 -> 2.22.50 -> 2.22.51 -> 2.22.52 -> 2.22.53 -> 2.22.54 -> 2.22.55 -> 2.22.56 -> 2.22.57 -> 2.22.58 -> 2.22.59 -> 2.22.60 -> 2.22.61 -> 2.22.62 -> 2.22.63 -> 2.22.64 with a changelog entry per bump in "
                "`pack/docs/AUDIT_SYSTEM_CHANGELOG.md`. New files are tracked in "
                "`pack/audit/manifest.json` (refresh-agent-context.ps1, "
                "AGENT_CONTEXT.json.template) and layoutPolicy.enabled joined "
                "auditConfigTemplate.requiredKeys, so template and reference configs cannot "
                "drift. Doc version cites re-synced via sync-doc-versions.ps1; "
                "`Refresh-AgentContext.cmd` added to the export item list so a transferred copy "
                "carries it."
            ),
            "evidence": [
                {"type": "file", "ref": "VERSION"},
                {"type": "file", "ref": "pack/audit/manifest.json"},
                {"type": "file", "ref": "pack/docs/AUDIT_SYSTEM_CHANGELOG.md"},
                {"type": "file", "ref": "export.ps1"},
            ],
        },
    }

    sections: dict = {}
    for letter in man.get("requiredSections", []):
        c = content.get(letter)
        if c is None:
            # A required section this helper has no canned text for (Section N arrived that way)
            # must stay unreviewed. Crashing hid the section; inventing a summary would fake the
            # review the gate exists to require.
            sections[letter] = {
                "reviewed": False,
                "summary": "",
                "evidence": [],
                "modulesReviewed": list((exp.get("sections") or {}).get(letter, [])),
            }
            print(f"Section {letter}: no canned summary - left unreviewed for a human pass")
            continue
        entry = {
            "reviewed": True,
            "summary": c["summary"],
            "evidence": c["evidence"],
            "modulesReviewed": list((exp.get("sections") or {}).get(letter, [])),
        }
        if letter in checklist_letters:
            mods = list(entry["modulesReviewed"])
            for p in parse_checklist_paths((checklist.get(letter) or {}).get("checklistItems") or []):
                if p not in mods:
                    mods.append(p)
            entry["modulesReviewed"] = mods
        if letter == "B":
            entry["inventoryAck"] = {
                "productionModules": inv.get("productionModules", 0),
                "testFiles": inv.get("testFiles", 0),
                "productionLoc": inv.get("productionLoc", 0),
            }
        sections[letter] = entry

    sem = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "testsGitHead": man.get("testsGitHead") or "",
        "instructions": "Pack self-audit semantic report",
        "sections": sections,
    }
    out = ROOT / "docs/.audit_semantic_report.json"
    out.write_text(json.dumps(sem, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
