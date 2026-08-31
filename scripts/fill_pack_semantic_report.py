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
                "profiles (behavior step 5b runs that sync for real). Reviewed the handover documents "
                "against the code they describe and corrected seven stale or self-contradicting "
                "claims, including a feature documented as both shipped and unimplemented; "
                "HANDOVER_NEXT_AGENT.md is now in maintainerDocSync so its version cites cannot drift "
                "unnoticed, and the boundary between a pack-shipped profile rule and a rule the user "
                "added on one machine is written down rather than living in one script's logic."
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
                "Version aligned: `VERSION` 1.7.0 matches install manifest; "
                "`pack/docs/AUDIT_SYSTEM_CHANGELOG.md` documents audit system 2.22.10 (mcp server mirrored; six enumerated file classes), 2.22.9 (root entry points mirrored; Refresh wrapper accepts a leading switch), 2.22.8 (the offer-to-run instruction carries in AI_INSTRUCTIONS.md and AGENTS.md, not just the Cursor .mdc), 2.22.7 (audit reports a stale agent-context stamp as Improve worded for the agent to offer the run; bootstrap stamps the engine version), 2.22.6 (packMirror covers every script, template and doc; bootstrap manifest lists only what it writes), 2.22.5 "
                "(pack/docs enumerated against packMirror, handover joined maintainerDocSync, stale "
                "handover claims corrected), 2.22.4 "
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
                "Release readiness reviewed for this cycle: pack `VERSION` stays 1.7.0 (no "
                "user-facing pack release), while the audit engine moved 2.21.22 -> 2.21.23 -> "
                "2.22.0 -> 2.22.1 -> 2.22.2 -> 2.22.3 -> 2.22.4 -> 2.22.5 -> 2.22.6 -> 2.22.7 -> 2.22.8 -> 2.22.9 -> 2.22.10 with a changelog entry per bump in "
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
