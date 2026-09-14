#!/usr/bin/env python3
"""Machine code checks for audit - import smoke, static patterns, agent manifest.

Reads docs/AUDIT.config.json (codeChecks section). Emits JSON on stdout for
run_audit_core.ps1. Exit 1 if any fix-level issue.

Extra modes:
  --verify-semantic-report   Validate docs/.audit_semantic_report.json vs manifest
  --write-semantic-template  Write empty semantic report template for agent fill-in
  --sync-doc-versions        Update maintainer doc version cites from VERSION + manifest
  --verify-doc-versions      Exit 1 if maintainer docs cite stale version numbers
  --lightweight              Skip import smoke (debug / -SkipTests path)
  --self-test                Fast parser self-test
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

# Run as a script the pack scripts folder is already sys.path[0], but this module is also imported
# by tooling that loads it by path, and import smoke runs it with PYTHONPATH set to a single dir.
# One insert keeps the sibling check modules importable in every one of those cases.
_SCRIPT_DIR = str(Path(__file__).resolve().parent)
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)

# Re-exported rather than moved wholesale: callers (and the self-test) still reach these through
# audit_code_checks, and the split is meant to shrink this file, not rewrite its public surface.
from audit_common import (  # noqa: E402
    VERSION_IN_DOC_RE,
    load_config,
    read_audit_manifest_version,
    read_canonical_version,
    resolve_repo_root,
)
from pack_entry_points import pack_entry_point  # noqa: E402
from audit_install_wiring import (  # noqa: E402
    _installed_pack_root,
    _user_cursor_root,
    check_installed_vs_source_improve,
    check_mcp_wiring_improve,
    check_pack_reference_config_improve,
)
from audit_version_docs import (  # noqa: E402
    AUDIT_ENGINE_VERSION_PATTERNS,
    DOC_INLINE_VERSION_RE,
    PACK_RELEASE_VERSION_PATTERNS,
    _collect_app_version_doc_paths,
    _extract_audit_engine_semvers,
    _extract_pack_release_semvers,
    _pack_version_line_segment,
    check_app_version_docs_improve,
    check_audit_version_docs_improve,
    check_changelog_version_improve,
    check_pack_version_docs_improve,
)


def parse_checklist_sections(audit_md: Path) -> dict[str, dict]:
    """Parse ### A. Title sections from AUDIT.md checklist into letter -> {title, checklistItems}."""
    if not audit_md.is_file():
        return {}
    lines = audit_md.read_text(encoding="utf-8-sig").splitlines()
    start = next(
        (
            i
            for i, ln in enumerate(lines)
            if ln.startswith("## Full checklist") or ln.startswith("## Checklist")
        ),
        -1,
    )
    if start < 0:
        return {}
    sections: dict[str, dict] = {}
    heading_re = re.compile(r"^###\s+([A-N])\.\s+(.+)$")
    current: str | None = None
    for ln in lines[start + 1 :]:
        if ln.startswith("## Domain map") or ln.startswith("## Automation"):
            break
        if ln.startswith("### Reference only"):
            break
        hm = heading_re.match(ln.strip())
        if hm:
            current = hm.group(1)
            sections[current] = {"title": hm.group(2).strip(), "checklistItems": []}
            continue
        if current and ln.strip().startswith("- "):
            sections[current]["checklistItems"].append(ln.strip()[2:].strip())
    return sections


CHECKLIST_PATH_TOKEN_RE = re.compile(
    r"`([^`]+)`|"
    r"\b(?:pack/)?(?:[\w\-]+/)*[\w\-]+\.(?:ps1|cmd|bat|py|md|json|mdc)\b",
    re.I,
)


def normalize_checklist_path(path: str) -> str:
    return path.strip().replace("\\", "/")


def parse_checklist_paths(checklist_items: list[str]) -> list[str]:
    """Extract file paths from checklist bullets (Section E PS scripts, etc.)."""
    paths: list[str] = []
    seen: set[str] = set()
    for item in checklist_items:
        for match in CHECKLIST_PATH_TOKEN_RE.finditer(item):
            raw = normalize_checklist_path(match.group(1) or match.group(0))
            if raw and raw not in seen:
                seen.add(raw)
                paths.append(raw)
    return paths


def checklist_path_reviewed(expected: str, reviewed: set[str]) -> bool:
    """True when expected path or its basename appears in modulesReviewed[]."""
    exp = normalize_checklist_path(expected)
    base = exp.split("/")[-1]
    for r in reviewed:
        rn = normalize_checklist_path(r)
        if rn == exp or rn.endswith("/" + exp) or exp.endswith("/" + rn):
            return True
        if rn == base or rn.endswith("/" + base):
            return True
    return False


def verify_checklist_paths_reviewed(
    checklist_sections: dict[str, dict],
    sections: dict,
    cfg: dict,
) -> list[str]:
    """Require modulesReviewed[] for checklist file paths (sections without domain-map modules)."""
    cc = cfg.get("codeChecks") or {}
    if not cc.get("semanticRequireModulesReviewed", True):
        return []
    letters = cc.get("semanticChecklistPathSections") or []
    fixes: list[str] = []
    for letter in letters:
        chk = checklist_sections.get(letter) or {}
        expected = parse_checklist_paths(chk.get("checklistItems") or [])
        if not expected:
            continue
        entry = sections.get(letter) or {}
        reviewed = entry.get("modulesReviewed")
        if not isinstance(reviewed, list):
            fixes.append(
                f"Semantic report - section {letter} missing modulesReviewed[] "
                f"(list all {len(expected)} checklist paths reviewed this session)"
            )
            continue
        got = {normalize_checklist_path(str(x)) for x in reviewed if str(x).strip()}
        missing = [p for p in expected if not checklist_path_reviewed(p, got)]
        if missing:
            fixes.append(
                f"Semantic report - section {letter} modulesReviewed missing checklist paths "
                f"{', '.join(missing[:6])}"
                + (f" (+{len(missing) - 6} more)" if len(missing) > 6 else "")
            )
    return fixes


def parse_domain_map(audit_md: Path) -> dict[str, list[str]]:
    """Map section letter -> module filenames from the domain map table."""
    if not audit_md.is_file():
        return {}
    lines = audit_md.read_text(encoding="utf-8-sig").splitlines()
    start = next((i for i, ln in enumerate(lines) if ln.startswith("## Domain map")), -1)
    if start < 0:
        return {}
    sections: dict[str, list[str]] = {}
    row_re = re.compile(r"^\|\s*(.+?)\s*\|\s*([A-N](?:\s*,\s*[A-N])*)\s*\|$")
    for ln in lines[start + 1 :]:
        if ln.startswith("## ") and not ln.startswith("## Domain map"):
            break
        stripped = ln.strip()
        if not stripped.startswith("|") or stripped.startswith("|-"):
            continue
        if "Module / area" in stripped or "Module |" in stripped:
            continue
        m = row_re.match(stripped)
        if not m:
            continue
        mods_cell, sec_part = m.group(1), m.group(2)
        letters = [s.strip() for s in sec_part.split(",")]
        for quoted in re.findall(r"`([^`]+)`", mods_cell):
            name = quoted.strip()
            if not name:
                continue
            for letter in letters:
                sections.setdefault(letter, []).append(name)
        for mod in re.findall(r"([a-z_][a-z0-9_]*\.py)", mods_cell, re.I):
            for letter in letters:
                sections.setdefault(letter, []).append(mod)
    for letter, mods in list(sections.items()):
        seen: list[str] = []
        for name in mods:
            if name not in seen:
                seen.append(name)
        sections[letter] = seen
    return sections


def build_agent_sections(
    checklist_sections: dict[str, dict],
    domain_sections: dict[str, list[str]],
    section_tests: dict[str, list[str]],
    semantic_hints: dict[str, list],
) -> tuple[dict[str, dict], list[str]]:
    letters = (
        set(checklist_sections)
        | set(domain_sections)
        | set(section_tests)
        | set(semantic_hints)
    )
    required = sorted(letters)
    out: dict[str, dict] = {}
    for letter in required:
        chk = checklist_sections.get(letter, {})
        out[letter] = {
            "title": chk.get("title", ""),
            "checklistItems": chk.get("checklistItems", []),
            "modules": sorted(set(domain_sections.get(letter, []))),
            "machineTests": section_tests.get(letter, []),
            "semanticReview": semantic_hints.get(letter, []),
        }
    return out, required


def semantic_report_path(app_root: Path, cfg: dict) -> Path:
    cc = cfg.get("codeChecks") or {}
    rel = cc.get("semanticReportFile", "docs/.audit_semantic_report.json")
    return app_root / rel.replace("\\", "/")


CLEAN_SUMMARY_RE = re.compile(
    r"^(nothing found\.?|no issues?\.?|clean\.?|n/a\.?|none\.?|ok\.?)$",
    re.I,
)
CITE_RE = re.compile(
    r"(`[^`]+`|[a-zA-Z0-9_\-\\./]+\.(?:py|md|mdc|json|cmd|bat|ps1|spec|txt)|tests/|\\|/)"
)
EVIDENCE_TYPES = frozenset({"file", "test", "command", "behavior"})


def is_clean_summary(summary: str) -> bool:
    return bool(CLEAN_SUMMARY_RE.match(summary.strip()))


def summary_has_cite(summary: str) -> bool:
    return bool(CITE_RE.search(summary))


def resolve_evidence_path(app_root: Path, repo_root: Path, ref: str) -> Path | None:
    ref = ref.strip().strip("`")
    if not ref:
        return None
    norm = ref.replace("\\", "/")
    candidates: list[Path] = [app_root / norm]
    if norm.startswith("tests/"):
        candidates.append(app_root / norm)
    elif "/" not in norm and "\\" not in norm:
        candidates.append(app_root / "tests" / norm)
    candidates.append(repo_root / norm)
    seen: set[Path] = set()
    for p in candidates:
        rp = p.resolve()
        if rp in seen:
            continue
        seen.add(rp)
        if rp.is_file():
            return rp
    return None


def validate_section_evidence(
    app_root: Path,
    letter: str,
    entry: dict,
    summary: str,
    cfg: dict,
) -> list[str]:
    fixes: list[str] = []
    cc = cfg.get("codeChecks") or {}
    if not cc.get("semanticReportRequireEvidence", True):
        return fixes
    evidence = entry.get("evidence")
    if evidence is None:
        fixes.append(f"Semantic report - section {letter} missing evidence array")
        return fixes
    if not isinstance(evidence, list):
        fixes.append(f"Semantic report - section {letter} evidence must be an array")
        return fixes
    clean = is_clean_summary(summary)
    min_not_clean = int(cc.get("semanticReportEvidenceMinWhenNotClean", 1))
    if not clean and len(evidence) < min_not_clean:
        fixes.append(
            f"Semantic report - section {letter} needs >= {min_not_clean} evidence item(s) "
            "when summary is not 'Nothing found.'"
        )
    repo_root = resolve_repo_root(app_root)
    resolved_file = False
    for i, item in enumerate(evidence):
        if not isinstance(item, dict):
            fixes.append(f"Semantic report - section {letter} evidence[{i}] must be an object")
            continue
        etype = (item.get("type") or "").strip().lower()
        ref = (item.get("ref") or "").strip()
        if etype not in EVIDENCE_TYPES:
            fixes.append(
                f"Semantic report - section {letter} evidence[{i}] type must be one of "
                f"{sorted(EVIDENCE_TYPES)}"
            )
            continue
        if not ref:
            fixes.append(f"Semantic report - section {letter} evidence[{i}] missing ref")
            continue
        if etype in ("file", "test"):
            if resolve_evidence_path(app_root, repo_root, ref):
                resolved_file = True
            else:
                fixes.append(
                    f"Semantic report - section {letter} evidence[{i}] ref not found: {ref}"
                )
    if (
        not clean
        and cc.get("semanticReportEvidenceRequireFileWhenNotClean", True)
        and evidence
        and not resolved_file
    ):
        fixes.append(
            f"Semantic report - section {letter} needs at least one file/test evidence "
            "with an existing path when not clean"
        )
    return fixes


def collect_code_machine_fixes(
    app_root: Path,
    cfg: dict,
    lightweight: bool = False,
    domain_sections: dict[str, list[str]] | None = None,
) -> list[str]:
    """Run audit_code_checks machine fixers (no incomplete-audit gate)."""
    cc = cfg.get("codeChecks") or {}
    fixes: list[str] = []
    if cc.get("importSmoke", {}).get("enabled", True) and not lightweight:
        exclude = set((cc.get("importSmoke") or {}).get("exclude", []))
        fixes.extend(import_smoke(app_root, exclude, cfg))
    if not lightweight:
        allowlist = load_audit_allowlist(app_root, cfg)
        fixes.extend(scan_static_patterns(app_root, cc.get("staticPatterns") or [], allowlist))
    if domain_sections:
        fixes.extend(verify_domain_map_modules_exist(app_root, cfg, domain_sections))
        expanded = expand_domain_map_modules(app_root, cfg, domain_sections)
        fixes.extend(scan_domain_map_orphans(app_root, cfg, expanded))
    fixes.extend(verify_section_l_wiring(app_root, cfg))
    fixes.extend(verify_section_l_gitignore(app_root, cfg))
    fixes.extend(verify_section_m_version_docs(app_root, cfg))
    fixes.extend(verify_section_m_html_stale(app_root, cfg))
    fixes.extend(verify_section_f_portable_policy(app_root, cfg))
    fixes.extend(verify_section_c_packaging(app_root, cfg))
    fixes.extend(verify_section_b_layout(app_root, cfg))
    fixes.extend(verify_section_b_onedrive_doc(app_root, cfg))
    fixes.extend(verify_section_b_repo_root(app_root, cfg))
    return fixes


def verify_section_b_onedrive_doc(app_root: Path, cfg: dict) -> list[str]:
    fixes: list[str] = []
    bcfg = (cfg.get("codeChecks") or {}).get("sectionMachineChecks", {}).get("B") or {}
    rel = (bcfg.get("onedriveDoc") or "").strip()
    if not bcfg.get("enabled", False) or not rel:
        return fixes
    repo_root = resolve_repo_root(app_root)
    if not (repo_root / rel.replace("\\", "/")).is_file():
        fixes.append(f"Section B - missing {rel} (OneDrive cleanup doc)")
    return fixes


def map_fixes_to_sections(fixes: list[str]) -> dict[str, list[str]]:
    by_sec: dict[str, list[str]] = {}
    for f in fixes:
        m = re.match(r"^Section ([A-N]) ", f)
        if m:
            by_sec.setdefault(m.group(1), []).append(f)
        elif f.startswith("Import smoke"):
            by_sec.setdefault("A", []).append(f)
    return by_sec


_RUNNER_COMMENT_RE = re.compile(r"(?im)^\s*(?:#|::|rem\s|//)")
_RUNNER_ECHO_RE = re.compile(r"(?im)^\s*(?:echo|printf|write-host|write-output)\b")


def strip_inert_runner_lines(text: str) -> str:
    """Drop the lines of a test runner that cannot possibly run a test.

    Coverage is a substring search for each test file's name, so any line that merely *names* a
    test satisfies it - a comment pointing at the real suite, or an `echo` above `exit 0`. Both
    make an instant-pass runner look covered, which is the single failure this check exists to
    catch. A block comment is left alone: a runner's help text is not where names hide.

    An output line that also runs something (`echo x && python test_x.py`) keeps its statement, so
    the common "announce then run" shape is not mistaken for a stub.
    """
    kept: list[str] = []
    for line in text.splitlines():
        if _RUNNER_COMMENT_RE.match(line):
            continue
        if _RUNNER_ECHO_RE.match(line) and not re.search(r"&&|\|\||;|\|", line):
            continue
        kept.append(line)
    return "\n".join(kept)


def check_test_runner_coverage(app_root: Path, cfg: dict) -> list[str]:
    """A runner that exits 0 without running anything used to satisfy the whole test gate.

    Only the exit code was checked, so replacing run_tests.bat with `exit /b 0` printed
    "Tests: OK" while tests/ sat untouched. AUDIT.md already asks a reviewer to confirm the
    runner covers every test file; this is that promise, machine-checked.
    """
    cc = cfg.get("codeChecks") or {}
    if not (cc.get("testRunnerCoverage") or {}).get("enabled", True):
        return []
    tests_cfg = cfg.get("tests") or {}
    # Every declared runner, not just the Windows one: the promise is that whichever entry point
    # this OS uses covers the test files, so a project whose .bat runs the suite and whose .sh
    # quietly runs nothing must not pass. Both are checked on both platforms - the defect is in the
    # file, not in today's OS.
    script_rels = [r for r in (tests_cfg.get("script"), tests_cfg.get("scriptPosix")) if r]
    if not script_rels:
        return []
    test_files = sorted(app_root.glob("tests/test_*.py"))
    if not test_files:
        return []
    fixes: list[str] = []
    for script_rel in dict.fromkeys(script_rels):
        script = app_root / script_rel.replace("\\", "/")
        if not script.is_file():
            continue
        text = strip_inert_runner_lines(script.read_text(encoding="utf-8-sig", errors="replace"))
        # A runner is allowed to delegate, so follow one level of in-project scripts it calls.
        # The candidate may sit in a subdirectory: the separator has to be part of the pattern, or
        # `-File "scripts\run_tests.ps1"` does not match and a thin wrapper looks like a runner that
        # tests nothing. .sh counts too, now that the posix entry point is a wrapper as well.
        #
        # The leading token has to be an invocation of some kind - a bare mention must not count, or
        # `REM see scripts/run_tests.ps1` above `exit /b 0` would satisfy the check. The vocabulary
        # therefore lists the spellings that actually run something, including `source`/`.` and any
        # token naming powershell: a shell wrapper may reach the implementation through a helper
        # function (pack_pwsh_file) rather than by naming pwsh on the command line, and before that
        # was covered this check called the pack's own posix entry point a runner that tests nothing.
        nested_re = re.compile(
            r"(?im)(?:^|\s)(?:call|cmd\s+/c|exec|source|\.|-File|bash|sh"
            r"|[\w\-]*(?:pwsh|powershell)[\w\-]*)\s+\"?"
            r"([\w\-.$%~{}()/\\]*[\w\-.]+\.(?:bat|cmd|ps1|sh))\"?"
        )
        for match in nested_re.finditer(text):
            candidate = match.group(1).replace("\\", "/")
            # Strip the ways a script spells "my own directory" before resolving in the project.
            for prefix in ("%~dp0", "$ROOT", "$PSScriptRoot", "${ROOT}", "."):
                if candidate.startswith(prefix):
                    candidate = candidate[len(prefix):]
            candidate = candidate.lstrip("/")
            nested = app_root / candidate
            if nested.is_file() and nested.resolve() != script.resolve():
                text += "\n" + strip_inert_runner_lines(
                    nested.read_text(encoding="utf-8-sig", errors="replace")
                )
        # Globbed or discovered test runs cover files the runner never names.
        if re.search(r"test_\*\.py|pytest|unittest\s+discover|-m\s+unittest", text, re.IGNORECASE):
            continue
        missing = [p.name for p in test_files if p.name not in text]
        if not missing:
            continue
        shown = ", ".join(missing[:3])
        if len(missing) > 3:
            shown += f" +{len(missing) - 3} more"
        fixes.append(
            f"Test runner - {script_rel} never runs {shown} - "
            "name them or run tests\\test_*.py so the pass covers them"
        )
    return fixes


def verify_domain_map_modules_exist(
    app_root: Path, cfg: dict, domain_sections: dict[str, list[str]]
) -> list[str]:
    """Domain map lists modules - verify each concrete *.py exists on disk."""
    if not domain_sections:
        return []
    dm = cfg.get("domainMap") or {}
    fixes: list[str] = []
    scan_dir = app_root / (dm.get("scanDir") or ".").replace("\\", "/")
    exclude = set(dm.get("excludeModules") or [])
    search_dirs: list[Path] = []
    for rel in ["."] + list(dm.get("moduleSearchDirs") or []):
        rel_norm = str(rel).replace("\\", "/").strip() or "."
        candidate = app_root / rel_norm if rel_norm != "." else app_root
        if candidate not in search_dirs:
            search_dirs.append(candidate)
    if scan_dir not in search_dirs:
        search_dirs.insert(0, scan_dir)
    for letter, modules in domain_sections.items():
        for mod in modules:
            if not mod or mod in exclude or "*" in mod:
                continue
            if not mod.endswith(".py"):
                continue
            candidates = [sd / mod for sd in search_dirs]
            if not any(p.is_file() for p in candidates):
                fixes.append(f"Section {letter} - domain map module missing on disk {mod}")
    return fixes


def _domain_scan_dir(app_root: Path, cfg: dict) -> Path:
    dm = cfg.get("domainMap") or {}
    rel = (dm.get("scanDir") or ".").replace("\\", "/")
    return app_root if rel in (".", "") else app_root / rel


def _domain_scan_dirs(app_root: Path, cfg: dict) -> list[Path]:
    """Every directory this project calls its own code.

    scanDir alone described a single-folder layout. moduleSearchDirs was trusted to *resolve* modules
    named in the domain map but never scanned, so a project whose code lives in subfolders was
    inventoried on scanDir only: the pack's own audit reported 1 production module and 38 lines while
    holding a 2000-line engine under pack/scripts, and the orphan scan could not see an unmapped
    module there. Projects that leave moduleSearchDirs at ["."] are unaffected.
    """
    dm = cfg.get("domainMap") or {}
    rels = [dm.get("scanDir") or "."] + list(dm.get("moduleSearchDirs") or [])
    dirs: list[Path] = []
    seen: set[Path] = set()
    for rel in rels:
        rel = str(rel).replace("\\", "/").strip()
        p = app_root if rel in (".", "") else app_root / rel
        if not p.is_dir():
            continue
        try:
            key = p.resolve()
        except OSError:
            continue
        if key in seen:
            continue
        seen.add(key)
        dirs.append(p)
    return dirs


def _production_py_files(app_root: Path, cfg: dict) -> list[Path]:
    dm = cfg.get("domainMap") or {}
    exclude = set(dm.get("excludeModules") or [])
    glob_pat = dm.get("scanGlob") or "*.py"
    found: dict[str, Path] = {}
    for scan_dir in _domain_scan_dirs(app_root, cfg):
        for p in scan_dir.glob(glob_pat):
            # Modules are identified by filename throughout the domain map, so first match wins and
            # a duplicate name across folders cannot silently double-count.
            if p.is_file() and p.name not in exclude and p.name not in found:
                found[p.name] = p
    return [found[name] for name in sorted(found)]


def expand_domain_map_modules(
    app_root: Path, cfg: dict, domain_sections: dict[str, list[str]]
) -> dict[str, list[str]]:
    """Resolve wildcard entries (e.g. gui_*, firmware_peripheral_*.py) to concrete filenames."""
    scan_dirs = _domain_scan_dirs(app_root, cfg)
    expanded: dict[str, list[str]] = {}
    for letter, modules in domain_sections.items():
        names: list[str] = []
        for mod in modules:
            if not mod.endswith(".py"):
                continue
            if "*" in mod:
                # Wildcards must see the same folders as the orphan scan, or a pattern matches
                # nothing while the module it was meant to cover is reported as an orphan.
                for scan_dir in scan_dirs:
                    for p in sorted(scan_dir.glob(mod)):
                        if p.is_file():
                            names.append(p.name)
            else:
                names.append(mod)
        seen: list[str] = []
        for n in names:
            if n not in seen:
                seen.append(n)
        expanded[letter] = seen
    return expanded


def all_mapped_module_names(expanded: dict[str, list[str]]) -> set[str]:
    out: set[str] = set()
    for mods in expanded.values():
        out.update(mods)
    return out


def scan_domain_map_orphans(
    app_root: Path, cfg: dict, expanded: dict[str, list[str]]
) -> list[str]:
    """Disk -> map: production *.py not covered by expanded domain map."""
    dm = cfg.get("domainMap") or {}
    if not dm or dm.get("orphanScanEnabled", True) is False:
        return []
    mapped = all_mapped_module_names(expanded)
    fixes: list[str] = []
    for py in _production_py_files(app_root, cfg):
        if py.name not in mapped:
            fixes.append(
                f"Section B - domain map orphan *.py {py.name} "
                "(add to AUDIT.md domain map or remove module)"
            )
    return fixes


def write_expanded_domain_map(
    app_root: Path, cfg: dict, expanded: dict[str, list[str]]
) -> Path:
    rel = (cfg.get("codeChecks") or {}).get(
        "expandedDomainMapFile", "docs/.audit_domain_expanded.json"
    )
    path = app_root / rel.replace("\\", "/")
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sections": expanded,
        "allModules": sorted(all_mapped_module_names(expanded)),
    }
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


def count_file_loc(path: Path) -> int:
    try:
        return len(path.read_text(encoding="utf-8", errors="replace").splitlines())
    except OSError:
        return 0


def write_audit_inventory(app_root: Path, cfg: dict) -> dict:
    rel = (cfg.get("codeChecks") or {}).get("inventoryFile", "docs/.audit_inventory.json")
    path = app_root / rel.replace("\\", "/")
    repo_root = resolve_repo_root(app_root)
    production = _production_py_files(app_root, cfg)
    tests = sorted(app_root.glob("tests/test_*.py"))
    production_loc = sum(count_file_loc(p) for p in production)
    md_count = len(list(app_root.glob("docs/**/*.md"))) + len(list(repo_root.glob("*.md")))
    inv = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "productionModules": len(production),
        "testFiles": len(tests),
        "productionLoc": production_loc,
        "markdownFiles": md_count,
        "productionModuleNames": [p.name for p in production],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(inv, indent=2) + "\n", encoding="utf-8")
    return inv


def load_audit_inventory(app_root: Path, cfg: dict) -> dict | None:
    rel = (cfg.get("codeChecks") or {}).get("inventoryFile", "docs/.audit_inventory.json")
    path = app_root / rel.replace("\\", "/")
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (json.JSONDecodeError, OSError):
        return None


def check_large_modules_improve(
    app_root: Path, cfg: dict, expanded: dict[str, list[str]] | None = None
) -> list[str]:
    cc = cfg.get("codeChecks") or {}
    threshold = int(cc.get("largeModuleLocThreshold", 2000))
    if threshold <= 0:
        return []
    mod_letter: dict[str, str] = {}
    for letter, mods in (expanded or {}).items():
        for mod in mods:
            mod_letter[mod] = letter
    improve: list[str] = []
    for py in _production_py_files(app_root, cfg):
        loc = count_file_loc(py)
        if loc >= threshold:
            letter = mod_letter.get(py.name, "G")
            improve.append(
                f"Section {letter} - `{py.name}` ~{loc} LOC exceeds {threshold} "
                "(maintainability - split per module plan)"
            )
    return improve


def verify_section_b_repo_root(app_root: Path, cfg: dict) -> list[str]:
    bcfg = (cfg.get("codeChecks") or {}).get("sectionMachineChecks", {}).get("B") or {}
    if not bcfg.get("enabled", False):
        return []
    repo_root = resolve_repo_root(app_root)
    fixes: list[str] = []
    for rel in bcfg.get("repoRootPaths") or []:
        p = repo_root / rel.replace("\\", "/")
        if not p.is_file():
            fixes.append(f"Section B - repo root path missing {rel}")
    return fixes


def load_audit_allowlist(app_root: Path, cfg: dict) -> dict:
    rel = (cfg.get("codeChecks") or {}).get("allowlistFile", "docs/audit_allowlist.json")
    path = app_root / rel.replace("\\", "/")
    if not path.is_file():
        return {"exceptPass": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        return data if isinstance(data, dict) else {"exceptPass": []}
    except (json.JSONDecodeError, OSError):
        return {"exceptPass": []}


def _line_allowlisted(allowlist: dict, rel: str, line_no: int, rule_id: str) -> bool:
    if rule_id not in ("except-pass", "bare-except"):
        return False
    for item in allowlist.get("exceptPass") or []:
        if not isinstance(item, dict):
            continue
        f = (item.get("file") or "").replace("\\", "/")
        ln = int(item.get("line") or 0)
        if f and ln and f == rel.replace("\\", "/") and ln == line_no:
            return True
    return False


def scan_unused_imports_improve(app_root: Path, cfg: dict) -> list[str]:
    cc = cfg.get("codeChecks") or {}
    if not cc.get("deadCodeScan", {}).get("enabled", False):
        return []
    max_reports = int((cc.get("deadCodeScan") or {}).get("maxReports", 8))
    improve: list[str] = []
    import_re = re.compile(r"^\s*(?:from\s+(\S+)|import\s+(\S+))")
    for py in _production_py_files(app_root, cfg):
        try:
            lines = py.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        body = "\n".join(lines)
        for i, line in enumerate(lines, 1):
            m = import_re.match(line)
            if not m:
                continue
            mod = (m.group(1) or m.group(2) or "").split(".")[0].strip()
            if not mod or mod in ("__future__", "typing", "types"):
                continue
            if not re.search(rf"\b{re.escape(mod)}\b", body[i:]):
                improve.append(
                    f"Section G - `{py.name}`:{i} unused import `{mod}` (dead code candidate)"
                )
                if len(improve) >= max_reports:
                    return improve
    return improve


def find_test_gap_improves(
    app_root: Path, expanded: dict[str, list[str]], cfg: dict
) -> list[str]:
    cc = cfg.get("codeChecks") or {}
    if not cc.get("testGapHints", {}).get("enabled", True):
        return []
    test_blob = ""
    for tp in app_root.glob("tests/test_*.py"):
        try:
            test_blob += tp.read_text(encoding="utf-8", errors="replace") + "\n"
        except OSError:
            continue
    improve: list[str] = []
    letters = (cc.get("testGapHints") or {}).get("sections") or list("DEFGHIJK")
    max_per = int((cc.get("testGapHints") or {}).get("maxModulesListed", 5))
    for letter in letters:
        untested: list[str] = []
        for mod in expanded.get(letter, []):
            stem = mod[:-3] if mod.endswith(".py") else mod
            if stem not in test_blob and mod not in test_blob:
                untested.append(mod)
        if untested:
            sample = ", ".join(f"`{m}`" for m in untested[:max_per])
            suffix = f" (+{len(untested) - max_per} more)" if len(untested) > max_per else ""
            improve.append(
                f"Section {letter} - production modules with no test file reference: {sample}{suffix}"
            )
    return improve


def parse_iso_timestamp(raw: str) -> datetime | None:
    s = (raw or "").strip()
    if not s:
        return None
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def load_manifest(app_root: Path) -> dict:
    path = app_root / "docs" / ".audit_agent_manifest.json"
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (json.JSONDecodeError, OSError):
        return {}


def audit_proof_paths(app_root: Path, cfg: dict) -> list[Path]:
    """Files the test-pass proof covers: the runner, the audit contract, and production code."""
    paths: list[Path] = []
    test_script = (cfg.get("tests") or {}).get("script")
    if test_script:
        tp = app_root / test_script.replace("\\", "/")
        if tp.is_file():
            paths.append(tp)
    for rel in ("docs/AUDIT.config.json", "docs/AUDIT.md"):
        p = app_root / rel
        if p.is_file():
            paths.append(p)
    paths.extend(_production_py_files(app_root, cfg))
    return paths


def proof_rel_key(app_root: Path, path: Path) -> str:
    try:
        rel = path.relative_to(app_root).as_posix()
    except ValueError:
        rel = path.as_posix()
    return rel.lower()


_PROOF_TEXT_SUFFIXES = frozenset(
    {".py", ".md", ".json", ".ps1", ".mdc", ".txt", ".yml", ".yaml", ".sh", ".bat", ".cmd", ".template"}
)


def proof_file_content_hash(path: Path) -> str:
    """SHA256 of file bytes; text files normalized to LF for cross-host proof parity (WQ B12 / CI)."""
    suffix = path.suffix.lower()
    if suffix in _PROOF_TEXT_SUFFIXES:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""
        normalized = text.replace("\r\n", "\n").replace("\r", "\n")
        return hashlib.sha256(normalized.encode("utf-8")).hexdigest()
    fh = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            fh.update(chunk)
    return fh.hexdigest()


def compute_tree_fingerprint(app_root: Path, cfg: dict) -> str | None:
    """Hash the *contents* of the audited files.

    Size and mtime were the old inputs and both are wrong here: mtimes do not survive a copy to
    another drive (this pack ships on removable media), and they can be restored, so a proof
    built on them can be stale and identical at the same time. Get-AuditTreeFingerprint in
    run_audit_core.ps1 builds the identical string - keep the two in step.
    """
    app_root = app_root.resolve()
    entries: dict[str, Path] = {}
    for p in audit_proof_paths(app_root, cfg):
        if p.is_file():
            entries[proof_rel_key(app_root, p.resolve())] = p
    # sha256 of nothing is a constant, so an empty set would pass as a proof that matches forever.
    if not entries:
        return None
    h = hashlib.sha256()
    for rel in sorted(entries):
        h.update(f"{rel}|{proof_file_content_hash(entries[rel])}\n".encode("utf-8"))
    return h.hexdigest()


def git_head(repo_root: Path) -> str | None:
    """Return HEAD sha when git sees a usable work tree (WQ-461 / G01 parity with Test-PackGitRepo).

    Do not test (.git) path existence - a stale directory, worktree file, or unreadable index
    can make Test-Path true while rev-parse fails; asking git matches the PowerShell guards.
    """
    try:
        r = subprocess.run(
            [
                "git",
                "-c",
                "safe.directory=*",
                "-C",
                str(repo_root),
                "rev-parse",
                "HEAD",
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return None


def get_current_tests_proof_head(app_root: Path, cfg: dict) -> str | None:
    """Proof that the tree an agent reviewed is the tree the tests passed on.

    HEAD alone was not enough. It does not move for uncommitted edits, so a project could pass
    an audit, change code without committing, and keep reporting the pass - and because git is
    only consulted when it answers, the strict path was the one that ran where git was absent.
    The fingerprint is the proof; HEAD is prefixed when git answers so a commit invalidates it
    too, which covers files the fingerprint's globs do not reach.
    """
    fingerprint = compute_tree_fingerprint(app_root, cfg)
    head = git_head(resolve_repo_root(app_root))
    if fingerprint is None:
        return head
    if head:
        return f"{head}+tree:{fingerprint}"
    return f"tree:{fingerprint}"


def verify_semantic_freshness(app_root: Path, cfg: dict, data: dict) -> list[str]:
    cc = cfg.get("codeChecks") or {}
    if not cc.get("semanticFreshnessCheck", True):
        return []
    fixes: list[str] = []
    manifest = load_manifest(app_root)
    tests_passed_at = parse_iso_timestamp(str(manifest.get("testsPassedAt") or ""))
    generated_at = parse_iso_timestamp(str(data.get("generatedAt") or ""))
    if tests_passed_at and generated_at and generated_at < tests_passed_at:
        fixes.append(
            "Semantic report stale - generatedAt is before manifest testsPassedAt "
            "(complete deep scan in same session as test pass)"
        )
    manifest_head = (manifest.get("testsGitHead") or "").strip()
    current_head = get_current_tests_proof_head(app_root, cfg)
    semantic_head = (data.get("testsGitHead") or "").strip()
    if manifest_head and current_head and manifest_head != current_head:
        fixes.append(
            "Semantic report stale - source tree changed since test pass "
            f"(re-run full {pack_entry_point('run_audit')})"
        )
    if cc.get("semanticRequireTestsGitHead", True) and manifest_head:
        if not semantic_head:
            fixes.append(
                "Semantic report - missing testsGitHead (copy from docs/.audit_agent_manifest.json)"
            )
        elif semantic_head != manifest_head:
            fixes.append(
                "Semantic report - testsGitHead does not match manifest "
                "(re-run deep scan after code changes)"
            )
    return fixes


def verify_section_b_inventory(app_root: Path, cfg: dict, sections: dict) -> list[str]:
    cc = cfg.get("codeChecks") or {}
    if not cc.get("inventoryRequireAck", True):
        return []
    inv = load_audit_inventory(app_root, cfg)
    if not inv:
        return [
            "Section B - missing docs/.audit_inventory.json "
            f"(re-run {pack_entry_point('run_audit')} to generate inventory)"
        ]
    if "B" not in sections:
        return []
    entry = sections.get("B") or {}
    ack = entry.get("inventoryAck")
    if not isinstance(ack, dict):
        return ["Section B - missing inventoryAck object (copy counts from docs/.audit_inventory.json)"]
    fixes: list[str] = []
    for key in ("productionModules", "testFiles", "productionLoc"):
        if ack.get(key) != inv.get(key):
            fixes.append(
                f"Section B - inventoryAck.{key}={ack.get(key)!r} "
                f"does not match .audit_inventory.json ({inv.get(key)!r})"
            )
    return fixes


def verify_modules_reviewed(
    expanded: dict[str, list[str]], sections: dict, cfg: dict
) -> list[str]:
    cc = cfg.get("codeChecks") or {}
    if not cc.get("semanticRequireModulesReviewed", True):
        return []
    letters = cc.get("semanticModulesReviewedSections") or list("DEFGHIJK")
    fixes: list[str] = []
    for letter in letters:
        expected = set(expanded.get(letter, []))
        if not expected:
            continue
        entry = sections.get(letter) or {}
        reviewed = entry.get("modulesReviewed")
        if not isinstance(reviewed, list):
            fixes.append(
                f"Semantic report - section {letter} missing modulesReviewed[] "
                f"(list all {len(expected)} domain-map modules reviewed this session)"
            )
            continue
        got = {str(x).strip() for x in reviewed if str(x).strip()}
        missing = sorted(expected - got)
        if missing:
            fixes.append(
                f"Semantic report - section {letter} modulesReviewed missing "
                f"{', '.join(missing[:6])}"
                + (f" (+{len(missing) - 6} more)" if len(missing) > 6 else "")
            )
    return fixes


def verify_duplicate_summaries(sections: dict, required_sections: list[str]) -> list[str]:
    summaries = []
    for letter in required_sections:
        s = ((sections.get(letter) or {}).get("summary") or "").strip()
        if s:
            summaries.append(s)
    if len(summaries) >= 8 and len(set(summaries)) == 1:
        return [
            "Semantic report - all section summaries identical "
            "(bulk paste forbidden - per-section deep scan required)"
        ]
    return []


def write_audit_receipt(app_root: Path, cfg: dict, manifest: dict) -> Path:
    rel = (cfg.get("codeChecks") or {}).get("receiptFile", "docs/.audit_receipt.json")
    path = app_root / rel.replace("\\", "/")
    inv = load_audit_inventory(app_root, cfg) or {}
    sem_path = semantic_report_path(app_root, cfg)
    sem_at = ""
    if sem_path.is_file():
        try:
            sem_at = json.loads(sem_path.read_text(encoding="utf-8-sig")).get("generatedAt") or ""
        except (json.JSONDecodeError, OSError):
            pass
    payload = {
        "finalizedAt": datetime.now(timezone.utc).isoformat(),
        "testsGitHead": manifest.get("testsGitHead"),
        "testsPassedAt": manifest.get("testsPassedAt"),
        "semanticGeneratedAt": sem_at,
        "version": read_canonical_version(app_root, cfg),
        "inventory": {
            k: inv.get(k)
            for k in ("productionModules", "testFiles", "productionLoc")
            if k in inv
        },
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


def load_machine_fixes_from_manifest(app_root: Path) -> dict[str, list[str]]:
    path = app_root / "docs" / ".audit_agent_manifest.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        raw = data.get("machineFixesBySection") or {}
        return {k: list(v) for k, v in raw.items() if v}
    except (json.JSONDecodeError, OSError, TypeError):
        return {}


def merge_fixes_by_section(*maps: dict[str, list[str]]) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for m in maps:
        for letter, items in m.items():
            bucket = out.setdefault(letter, [])
            for item in items:
                if item not in bucket:
                    bucket.append(item)
    return out


def load_machine_improves_from_manifest(app_root: Path) -> dict[str, list[str]]:
    path = app_root / "docs" / ".audit_agent_manifest.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        raw = data.get("machineImprovesBySection") or {}
        return {k: list(v) for k, v in raw.items() if v}
    except (json.JSONDecodeError, OSError, TypeError):
        return {}


def verify_semantic_vs_machine_improves(
    app_root: Path,
    cfg: dict,
    sections: dict,
    required_sections: list[str],
) -> list[str]:
    """Machine Improve lines must be answered in that section's summary, not silently dropped.

    Fix lines already block a clean summary. Improve lines did not, so a layout finding could sit in
    the manifest while the agent closed the section on the cruft it had deleted.
    """
    cc = cfg.get("codeChecks") or {}
    if not cc.get("semanticRequireMachineImproveMention", True):
        return []
    by_sec = load_machine_improves_from_manifest(app_root)
    fixes: list[str] = []
    for letter in sorted(by_sec.keys()):
        if required_sections and letter not in required_sections:
            continue
        entry = sections.get(letter) or {}
        summary = (entry.get("summary") or "").strip()
        if not summary:
            continue
        lowered = summary.lower()
        if "layout" in lowered:
            continue
        # Or name what the machine flagged - a specific cite beats the keyword. Only tokens that
        # look like a path or folder name count, so ordinary prose in the message cannot match.
        cited = False
        for line in by_sec[letter]:
            for token in re.findall(r"[\w.\-]*[\\/_][\w.\-\\/_]*", line):
                token = token.strip("\\/_-.")
                if len(token) < 4:
                    continue
                if token.lower() in lowered:
                    cited = True
                    break
            if cited:
                break
        if not cited:
            fixes.append(
                f"Semantic report - section {letter} does not address "
                f"{len(by_sec[letter])} machine Improve line(s) - mention layout or cite them "
                f"(see machineImprovesBySection.{letter} in docs/.audit_agent_manifest.json)"
            )
    return fixes


def verify_semantic_vs_machine(
    app_root: Path,
    cfg: dict,
    sections: dict,
    required_sections: list[str],
    lightweight: bool = False,
    domain_sections: dict[str, list[str]] | None = None,
) -> list[str]:
    """Block clean semantic summaries when machine checks already found issues in that section."""
    cc = cfg.get("codeChecks") or {}
    if not cc.get("semanticBlockCleanWhenMachineFails", True):
        return []
    live = map_fixes_to_sections(
        collect_code_machine_fixes(app_root, cfg, lightweight, domain_sections)
    )
    from_manifest = load_machine_fixes_from_manifest(app_root)
    by_sec = merge_fixes_by_section(live, from_manifest)
    fixes: list[str] = []
    for letter in sorted(by_sec.keys()):
        if letter not in sections:
            continue
        entry = sections.get(letter) or {}
        summary = (entry.get("summary") or "").strip()
        if is_clean_summary(summary):
            fixes.append(
                f"Semantic report - section {letter} cannot be 'Nothing found.' "
                f"while machine checks report {len(by_sec[letter])} issue(s)"
            )
    return fixes


def verify_semantic_report(
    app_root: Path,
    cfg: dict,
    required_sections: list[str],
    lightweight: bool = False,
    domain_sections: dict[str, list[str]] | None = None,
) -> list[str]:
    fixes: list[str] = []
    if not required_sections:
        # With no sections the loop below verifies nothing and the audit reports a clean pass
        # having reviewed nothing at all. An empty gate is never a pass.
        return [
            "Audit scope - no checklist sections found - add '## Checklist sections' with "
            "'### A. Title' entries to docs/AUDIT.md (the semantic gate has nothing to verify)"
        ]
    path = semantic_report_path(app_root, cfg)
    if not path.is_file():
        fixes.append(
            f"Semantic report missing - {path.relative_to(app_root)} - "
            f"run {pack_entry_point('scripts/write_semantic_audit_template')} then review all "
            "sections before audit is complete"
        )
        return fixes
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (json.JSONDecodeError, OSError) as exc:
        fixes.append(f"Semantic report invalid - {path.name} - {exc}")
        return fixes
    sections = data.get("sections") or {}
    cc = cfg.get("codeChecks") or {}
    require_cites = cc.get("semanticReportRequireCites", True)
    for letter in required_sections:
        entry = sections.get(letter)
        if not entry:
            fixes.append(f"Semantic report - section {letter} missing")
            continue
        if not entry.get("reviewed"):
            fixes.append(f"Semantic report - section {letter} not marked reviewed")
            continue
        summary = (entry.get("summary") or "").strip()
        if not summary:
            fixes.append(f"Semantic report - section {letter} empty summary")
            continue
        if require_cites and not is_clean_summary(summary) and not summary_has_cite(summary):
            fixes.append(
                f"Semantic report - section {letter} needs file/behavior cite "
                "(use `path/file.py` or tests/...) when not 'Nothing found.'"
            )
        fixes.extend(validate_section_evidence(app_root, letter, entry, summary, cfg))
    fixes.extend(verify_semantic_freshness(app_root, cfg, data))
    fixes.extend(verify_section_b_inventory(app_root, cfg, sections))
    if domain_sections:
        expanded = expand_domain_map_modules(app_root, cfg, domain_sections)
        fixes.extend(verify_modules_reviewed(expanded, sections, cfg))
    audit_md = app_root / "docs" / "AUDIT.md"
    checklist_sections = parse_checklist_sections(audit_md)
    fixes.extend(verify_checklist_paths_reviewed(checklist_sections, sections, cfg))
    fixes.extend(verify_duplicate_summaries(sections, required_sections))
    fixes.extend(verify_section_n_semantic(app_root, cfg, sections))
    fixes.extend(
        verify_semantic_vs_machine(
            app_root, cfg, sections, required_sections, lightweight, domain_sections
        )
    )
    fixes.extend(
        verify_semantic_vs_machine_improves(app_root, cfg, sections, required_sections)
    )
    return fixes


def verify_section_l_wiring(app_root: Path, cfg: dict) -> list[str]:
    fixes: list[str] = []
    lcfg = (cfg.get("codeChecks") or {}).get("sectionMachineChecks", {}).get("L") or {}
    if not lcfg.get("enabled", True):
        return fixes
    rules_dir = app_root / ".cursor" / "rules"
    for name in lcfg.get("forbiddenRules") or [
        "code-audit-checklist.mdc",
        "generic-code-audit-checklist.mdc",
        "product-audit-overlay.mdc",
    ]:
        if (rules_dir / name).is_file():
            fixes.append(f"Section L - forbidden rule app/.cursor/rules/{name}")
    for overlay in rules_dir.glob("*audit-overlay*"):
        fixes.append(f"Section L - forbidden overlay {overlay.name}")
    skill_name = lcfg.get("forbidDuplicateSkill", "agent-code-audit")
    dup = app_root / ".cursor" / "skills" / skill_name / "SKILL.md"
    if dup.is_file():
        fixes.append(f"Section L - duplicate project skill {skill_name} (use pack skill)")
    agents = app_root / "AGENTS.md"
    if agents.is_file():
        text = agents.read_text(encoding="utf-8", errors="replace")
        # An entry may be a string (that exact phrase) or a list (any one of them). The default is
        # any-of because the requirement is that AGENTS.md names the audit and test entry points, not
        # that it names the *Windows* ones: a project telling a Linux reader to run ./run_audit.sh was
        # failing its own audit for being correct (WQ-452). Config may still pin exact strings.
        for entry in lcfg.get("agentsMdRequiredPhrases") or [
            ["run_audit.cmd", "run_audit.sh", "run_audit.ps1"],
            ["run_tests.bat", "run_tests.sh", "run_tests.ps1"],
        ]:
            alternatives = entry if isinstance(entry, list) else [entry]
            if not any(alt in text for alt in alternatives):
                wanted = " or ".join(str(a) for a in alternatives)
                fixes.append(f"Section L - AGENTS.md missing required phrase: {wanted}")
    return fixes


def verify_section_l_gitignore(app_root: Path, cfg: dict) -> list[str]:
    fixes: list[str] = []
    lcfg = (cfg.get("codeChecks") or {}).get("sectionMachineChecks", {}).get("L") or {}
    if not lcfg.get("enabled", True):
        return fixes
    artifacts = lcfg.get("gitignoreAuditArtifacts") or [
        "docs/.audit_agent_manifest.json",
        "docs/.audit_semantic_report.json",
    ]
    repo_root = resolve_repo_root(app_root)
    combined = ""
    for gi in (app_root / ".gitignore", repo_root / ".gitignore"):
        if gi.is_file():
            combined += gi.read_text(encoding="utf-8", errors="replace") + "\n"
    if not combined.strip():
        fixes.append("Section L - no .gitignore found for audit artifact entries")
        return fixes
    for rel in artifacts:
        norm = str(rel).replace("\\", "/").strip()
        if not norm:
            continue
        found = any(
            line.strip().replace("\\", "/") == norm
            or line.strip().endswith(norm)
            for line in combined.splitlines()
            if line.strip() and not line.strip().startswith("#")
        )
        if not found and norm not in combined.replace("\\", "/"):
            fixes.append(f"Section L - .gitignore missing audit artifact: {norm}")
    return fixes


def git_recent_changes(repo_root: Path, paths: list[str], max_commits: int = 5) -> bool:
    if not (repo_root / ".git").is_dir():
        return False
    try:
        r = subprocess.run(
            ["git", "log", f"-{max_commits}", "--oneline", "--", *paths],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=30,
        )
        if r.returncode != 0:
            return False
        return bool(r.stdout.strip())
    except (OSError, subprocess.TimeoutExpired):
        return False


def verify_section_n_semantic(
    app_root: Path, cfg: dict, sections: dict
) -> list[str]:
    fixes: list[str] = []
    ncfg = (cfg.get("codeChecks") or {}).get("sectionMachineChecks", {}).get("N") or {}
    # Opt-in, not opt-out. Section N is not a checklist heading in any shipped AUDIT.md, so with a
    # default of True a config that never mentioned N could still demand an N entry the moment git
    # showed a version commit - and the report template had no N stub to fill. Where N is switched
    # on deliberately, main() adds it to the required sections so the template does stub it.
    if not ncfg.get("enabled", False):
        return fixes
    repo_root = resolve_repo_root(app_root)
    paths = ncfg.get("gitLogPaths") or ["VERSION.txt"]
    if not git_recent_changes(repo_root, paths, int(ncfg.get("gitMaxCommits", 5))):
        return fixes
    entry = sections.get("N") or {}
    summary = (entry.get("summary") or "").strip()
    if ncfg.get("blockCleanSummaryIfGitHits", True) and is_clean_summary(summary):
        fixes.append(
            "Section N - recent VERSION/release file commits in git; "
            "summary cannot be 'Nothing found.' - cite files reviewed for this release"
        )
    elif summary and not is_clean_summary(summary) and not summary_has_cite(summary):
        fixes.append(
            "Section N - recent VERSION changes; summary must cite changed files (e.g. `main.py`)"
        )
    if ncfg.get("blockCleanSummaryIfGitHits", True) and not is_clean_summary(summary):
        evidence = entry.get("evidence") or []
        has_file = any(
            isinstance(e, dict)
            and e.get("type") in ("file", "test")
            and resolve_evidence_path(app_root, repo_root, (e.get("ref") or ""))
            for e in evidence
        )
        if not has_file:
            fixes.append(
                "Section N - recent VERSION changes; evidence must include at least one "
                "existing file/test path reviewed for this release"
            )
    return fixes


def verify_section_m_version_docs(app_root: Path, cfg: dict) -> list[str]:
    fixes: list[str] = []
    mcfg = (cfg.get("codeChecks") or {}).get("sectionMachineChecks", {}).get("M") or {}
    if not mcfg.get("enabled", False):
        return fixes
    canonical = read_canonical_version(app_root, cfg)
    if not canonical:
        return fixes
    repo_root = resolve_repo_root(app_root)
    exclude = set(
        mcfg.get("excludeFiles")
        or ["AUDIT.md", "IMPROVEMENT_BACKLOG.md", "KNOWN_LIMITATIONS.md"]
    )
    scan_paths: list[Path] = []
    for pattern in mcfg.get("scanGlobs") or ["docs/*.md"]:
        scan_paths.extend(app_root.glob(pattern))
    if mcfg.get("scanRepoReadme", True):
        for name in mcfg.get("repoFiles") or ["README.md", "PROJECT_LAYOUT.md"]:
            p = repo_root / name
            if p.is_file():
                scan_paths.append(p)
    seen: set[Path] = set()
    reported: set[tuple[str, str]] = set()
    for md in scan_paths:
        if md.name in exclude:
            continue
        rp = md.resolve()
        if rp in seen:
            continue
        seen.add(rp)
        try:
            text = md.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for m in VERSION_IN_DOC_RE.finditer(text):
            found = m.group(1)
            if found != canonical:
                try:
                    rel = str(md.relative_to(app_root))
                except ValueError:
                    rel = str(md.relative_to(repo_root))
                key = (rel, found)
                if key in reported:
                    continue
                reported.add(key)
                fixes.append(
                    f"Section M - hardcoded version v{found} in {rel} "
                    f"(canonical {canonical} from VERSION.txt)"
                )
    return fixes


def verify_section_c_packaging(app_root: Path, cfg: dict) -> list[str]:
    fixes: list[str] = []
    ccfg = (cfg.get("codeChecks") or {}).get("sectionMachineChecks", {}).get("C") or {}
    if not ccfg.get("enabled", False):
        return fixes
    for rel in ccfg.get("requiredPaths") or []:
        p = app_root / rel.replace("\\", "/")
        if not p.is_file():
            fixes.append(f"Section C - missing packaging file {rel}")
    dist_marker = (ccfg.get("distMarker") or "dist/MyApp/MyApp.exe").replace(
        "\\", "/"
    )
    dist_exe = app_root / dist_marker
    dist_dir_name = dist_marker.split("/")[0] if "/" in dist_marker else "dist/MyApp"
    dist_dir = app_root / dist_dir_name
    if dist_exe.is_file() or dist_dir.is_dir():
        for rel in ccfg.get("bundledRuntimePaths") or []:
            p = app_root / rel.replace("\\", "/")
            if not p.is_file():
                fixes.append(f"Section C - missing bundled runtime {rel}")
        for rel in ccfg.get("forbidDuplicateRootPaths") or []:
            p = app_root / rel.replace("\\", "/")
            if p.exists():
                fixes.append(f"Section C - duplicate root path must not exist {rel}")
    for rel in ccfg.get("sectionTests") or []:
        if not (app_root / rel.replace("\\", "/")).is_file():
            fixes.append(f"Section C - missing section test {rel}")
    return fixes


def verify_section_b_layout(app_root: Path, cfg: dict) -> list[str]:
    fixes: list[str] = []
    bcfg = (cfg.get("codeChecks") or {}).get("sectionMachineChecks", {}).get("B") or {}
    if not bcfg.get("enabled", False):
        return fixes
    repo_root = resolve_repo_root(app_root)
    for rel in bcfg.get("layoutRequiredPaths") or []:
        p = repo_root / rel.replace("\\", "/")
        if not p.exists():
            fixes.append(f"Section B - layout path missing (PROJECT_LAYOUT) {rel}")
    return fixes


def verify_section_f_portable_policy(app_root: Path, cfg: dict) -> list[str]:
    fixes: list[str] = []
    fcfg = (cfg.get("codeChecks") or {}).get("sectionMachineChecks", {}).get("F") or {}
    if not fcfg.get("enabled", False):
        return fixes
    agents = app_root / "AGENTS.md"
    if not agents.is_file():
        fixes.append("Section F - AGENTS.md missing (portable-first policy)")
        return fixes
    text = agents.read_text(encoding="utf-8", errors="replace")
    # Same any-of shape as Section L, so one key does not mean two things in one config file.
    for entry in fcfg.get("agentsMdRequiredPhrases") or [
        "portable first",
        "Portable-first",
    ]:
        alternatives = entry if isinstance(entry, list) else [entry]
        if not any(alt in text for alt in alternatives):
            wanted = " or ".join(str(a) for a in alternatives)
            fixes.append(f"Section F - AGENTS.md missing portable policy phrase: {wanted}")
    return fixes


def verify_section_m_html_stale(app_root: Path, cfg: dict) -> list[str]:
    fixes: list[str] = []
    mcfg = (cfg.get("codeChecks") or {}).get("sectionMachineChecks", {}).get("M") or {}
    if not mcfg.get("enabled", False):
        return fixes
    stale_pat = (cfg.get("staleDocs") or {}).get("pattern") or ""
    if not stale_pat.strip():
        return fixes
    try:
        stale_re = re.compile(stale_pat)
    except re.error:
        return fixes
    for pattern in mcfg.get("htmlScanGlobs") or ["docs/*.html"]:
        for html in app_root.glob(pattern):
            if not html.is_file():
                continue
            try:
                text = html.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if stale_re.search(text):
                rel = html.relative_to(app_root)
                fixes.append(f"Section M - stale path pattern in HTML mockup {rel}")
    return fixes


def collect_config_machine_checks(
    cfg: dict, domain_sections: dict[str, list[str]] | None = None
) -> dict[str, list[str]]:
    """Map enabled AUDIT.config.json capabilities to checklist sections (run_audit_core + codeChecks)."""
    by_sec: dict[str, list[str]] = {}

    def add(letter: str, item: str) -> None:
        by_sec.setdefault(letter, [])
        if item not in by_sec[letter]:
            by_sec[letter].append(item)

    vs = cfg.get("versionSync")
    if vs:
        add("A", "versionSync code<->VERSION.txt")
        if vs.get("distTxtFile"):
            add("A", "versionSync dist VERSION.txt")
            add("C", "versionSync dist VERSION.txt")
    test_script = (cfg.get("tests") or {}).get("script")
    if test_script:
        add("A", f"full {test_script}")
    rp = cfg.get("requiredPaths") or {}
    if rp.get("app"):
        add("C", "requiredPaths app (exe/dist)")
        add("B", "requiredPaths app")
    if rp.get("repo"):
        add("B", "requiredPaths repo")
        add("M", "requiredPaths repo docs")
    sd = cfg.get("staleDocs") or {}
    if sd.get("pattern"):
        add("B", "staleDocs pattern scan")
        add("M", "staleDocs pattern scan")
    if cfg.get("cruft"):
        add("B", "cruft/cache/logs")
    if (cfg.get("secretsScan") or {}).get("enabled"):
        add("B", "secretsScan")
        add("K", "secretsScan")
    if cfg.get("obsoletePaths"):
        add("B", "obsoletePaths/desktopFolder")
    if (cfg.get("stables") or {}).get("enabled"):
        add("B", "stables policy")
    add("B", "forbiddenArtifacts")
    add("B", "CODE_AUDIT*.md outside audit_archive")
    cc = cfg.get("codeChecks") or {}
    if cfg.get("domainMap"):
        add("B", "domain map orphan *.py")
        add("B", "domain map expanded wildcards")
        if (cfg.get("domainMap") or {}).get("moduleSearchDirs"):
            add("B", "domain map moduleSearchDirs")
        if domain_sections:
            for letter, mods in domain_sections.items():
                if mods:
                    add(letter, "domain map module existence")
    inv = (cc.get("inventoryFile") or "docs/.audit_inventory.json") if cc else "docs/.audit_inventory.json"
    if cc.get("inventoryRequireAck", True):
        add("B", "audit inventory ack")
    if cc.get("semanticRequireModulesReviewed", True):
        for letter in cc.get("semanticModulesReviewedSections") or list("DEFGHIJK"):
            add(str(letter), "semantic modulesReviewed verify")
        for letter in cc.get("semanticChecklistPathSections") or []:
            add(str(letter), "semantic checklist paths modulesReviewed verify")
    if cc.get("semanticFreshnessCheck", True):
        for letter in "ABCDEFGHIJKLMN":
            add(letter, "semantic freshness vs test pass")
    if cc.get("largeModuleLocThreshold", 2000):
        add("G", "large module LOC improve")
    if (cc.get("deadCodeScan") or {}).get("enabled"):
        add("G", "unused import scan")
    if (cc.get("testGapHints") or {}).get("enabled", True):
        for letter in (cc.get("testGapHints") or {}).get("sections") or list("DEFGHIJK"):
            add(str(letter), "test gap hints")
    if (cc.get("auditVersionDocs") or {}).get("enabled", False):
        add("M", "auditVersionDocs manifest version in maintainer docs")
    if (cc.get("packVersionDocs") or {}).get("enabled", False):
        add("M", "packVersionDocs VERSION in maintainer docs")
    if (cc.get("packReferenceConfig") or {}).get("enabled", False):
        add("L", "packReferenceConfig parity with docs/AUDIT.config.json")
    if (cc.get("installedVsSource") or {}).get("enabled", False):
        add("F", "installedVsSource workspace vs ~/.cursor/AgentStarterPack")
    if (cc.get("changelogVersionDocs") or {}).get("enabled", False):
        add("M", "changelogVersionDocs CHANGELOG vs VERSION")
    if (cc.get("mcpWiring") or {}).get("enabled", False):
        add("G", "mcpWiring MCP deps and mcp.json")
    if (cc.get("sectionMachineChecks") or {}).get("B", {}).get("repoRootPaths"):
        add("B", "repo root path verify")
    if cc.get("allowlistFile"):
        add("K", "audit allowlist except-pass")
    sync = cfg.get("syncAndVerify") or {}
    if sync.get("runSyncVerify"):
        add("L", "sync-audit-system -VerifyOnly")
    if sync.get("runLegacyVerify"):
        add("L", "verify-audit-system.ps1")
    smc = cc.get("sectionMachineChecks") or {}
    if (cc.get("importSmoke") or {}).get("enabled", True):
        extra = list((cfg.get("domainMap") or {}).get("moduleSearchDirs") or [])
        ism_dirs = list((cc.get("importSmoke") or {}).get("searchDirs") or [])
        if extra or ism_dirs:
            add("A", "import smoke (root + moduleSearchDirs)")
        else:
            add("A", "import smoke (root *.py)")
    for rule in cc.get("staticPatterns") or []:
        add(str(rule.get("section", "?")), f"staticPattern:{rule.get('id', '?')}")
    for letter, files in (cc.get("sectionTests") or {}).items():
        if files:
            add(letter, "sectionTests (via full suite)")
    if smc.get("L", {}).get("enabled", True):
        add("L", "sectionMachineChecks.L")
        if smc.get("L", {}).get("gitignoreAuditArtifacts"):
            add("L", "sectionMachineChecks.L gitignore audit artifacts")
    if smc.get("M", {}).get("enabled", False):
        add("M", "sectionMachineChecks.M version docs")
        add("M", "sectionMachineChecks.M HTML stale scan")
    if smc.get("F", {}).get("enabled", False):
        add("F", "sectionMachineChecks.F portable policy")
    if smc.get("C", {}).get("enabled", False):
        add("C", "sectionMachineChecks.C packaging/runtime")
    if smc.get("B", {}).get("enabled", False):
        add("B", "sectionMachineChecks.B layout paths")
        if smc.get("B", {}).get("onedriveDoc"):
            add("B", "sectionMachineChecks.B onedriveDoc")
    if smc.get("N", {}).get("enabled", True):
        add("N", "sectionMachineChecks.N git hint")
    if cc.get("semanticReportRequireEvidence"):
        for letter in "ABCDEFGHIJKLMN":
            add(letter, "semantic report evidence verify")
    if cc.get("semanticReportRequireCites", True):
        for letter in "ABCDEFGHIJKLMN":
            add(letter, "semantic report cite verify")
    if cc.get("semanticReportRequiredInRunAudit", True):
        add("L", "semantic report required at run_audit end")
    if cc.get("semanticBlockCleanWhenMachineFails", True):
        for letter in "ABCDEFGHIJKLMN":
            add(letter, "semantic vs machine alignment")
    if cc.get("semanticRequireMachineImproveMention", True):
        for letter in "ABCDEFGHIJKLMN":
            add(letter, "semantic vs machine Improve alignment")
    if (cfg.get("layoutPolicy") or {}).get("enabled"):
        add("B", "layout policy (glossary, duplicate copies, ephemeral dirs, contradiction scripts)")
    return by_sec


def build_machine_coverage(
    agent_sections: dict[str, dict],
    cfg: dict,
    semantic_hints: dict[str, list],
    domain_sections: dict[str, list[str]] | None = None,
) -> dict[str, dict]:
    cc = cfg.get("codeChecks") or {}
    config_machine = collect_config_machine_checks(cfg, domain_sections)
    coverage: dict[str, dict] = {}
    for letter, sec in agent_sections.items():
        machine = list(config_machine.get(letter, []))
        if sec.get("machineTests") and "sectionTests (via full suite)" not in machine:
            machine.append("sectionTests (via full suite)")
        checklist_count = len(sec.get("checklistItems") or [])
        hints = semantic_hints.get(letter, [])
        coverage[letter] = {
            "machineCovered": machine,
            "checklistItemCount": checklist_count,
            "machineCheckCount": len(machine),
            "semanticRequired": True,
            "agentFocus": hints,
        }
    return coverage


def check_section_n_improve(app_root: Path, cfg: dict) -> list[str]:
    improve: list[str] = []
    ncfg = (cfg.get("codeChecks") or {}).get("sectionMachineChecks", {}).get("N") or {}
    if not ncfg.get("enabled", True):
        return improve
    repo_root = resolve_repo_root(app_root)
    paths = ncfg.get("gitLogPaths") or ["VERSION.txt"]
    if not git_recent_changes(repo_root, paths, int(ncfg.get("gitMaxCommits", 5))):
        return improve
    # Asking for the review is only useful until it exists. Repeating it on a report that already
    # reviews section N leaves an Improve line nobody can close, which is how people learn to skim
    # the list. verify_section_n_semantic still enforces the quality of that review.
    try:
        data = json.loads(semantic_report_path(app_root, cfg).read_text(encoding="utf-8-sig"))
    except (json.JSONDecodeError, OSError):
        data = {}
    entry = ((data.get("sections") or {}).get("N")) or {}
    summary = (entry.get("summary") or "").strip()
    if entry.get("reviewed") and summary and not is_clean_summary(summary):
        return improve
    improve.append(
        "Section N - recent VERSION/release commits in git; "
        "agent must review release delta in semantic report"
    )
    return improve


def write_semantic_template(app_root: Path, cfg: dict, required_sections: list[str]) -> Path:
    path = semantic_report_path(app_root, cfg)
    path.parent.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest(app_root)
    section_entry = {
        "reviewed": False,
        "summary": "",
        "evidence": [],
        "modulesReviewed": [],
    }
    template = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "testsGitHead": manifest.get("testsGitHead") or "",
        "instructions": (
            "Set reviewed=true and summary per section. Use 'Nothing found.' when clean ONLY if "
            "docs/.audit_agent_manifest.json machineFixesBySection has no entries for that section. "
            "Copy testsGitHead from manifest. For sections D-K list every domain-map module in "
            "modulesReviewed[]. For sections in semanticChecklistPathSections (pack: E), list every "
            "checklist file path in modulesReviewed[]. Section B: copy inventoryAck from "
            "docs/.audit_inventory.json. "
            "When not clean, cite files in summary AND evidence[] "
            "({type: file|test|command|behavior, ref: path or note})."
        ),
        "sections": {
            letter: dict(section_entry) for letter in required_sections
        },
    }
    if "B" in template["sections"]:
        template["sections"]["B"]["inventoryAck"] = {
            "productionModules": 0,
            "testFiles": 0,
            "productionLoc": 0,
        }
    path.write_text(json.dumps(template, indent=2) + "\n", encoding="utf-8")
    return path


def fill_semantic_fixture(
    app_root: Path, cfg: dict, required_sections: list[str], expanded_domain: dict[str, list[str]]
) -> Path:
    """Populate semantic report for behavior-fixture tests (modulesReviewed + inventoryAck)."""
    write_audit_inventory(app_root, cfg)
    write_expanded_domain_map(app_root, cfg, expanded_domain)
    path = semantic_report_path(app_root, cfg)
    if not path.exists():
        write_semantic_template(app_root, cfg, required_sections)
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    exp_rel = (cfg.get("codeChecks") or {}).get("expandedDomainMapFile") or "docs/.audit_domain_expanded.json"
    expanded_raw = json.loads((app_root / exp_rel).read_text(encoding="utf-8-sig"))
    expanded = expanded_raw.get("sections") or {}
    audit_md = app_root / "docs" / "AUDIT.md"
    checklist_sections = parse_checklist_sections(audit_md)
    cc = cfg.get("codeChecks") or {}
    checklist_letters = set(cc.get("semanticChecklistPathSections") or [])
    inv = load_audit_inventory(app_root, cfg) or {}
    manifest = load_manifest(app_root)
    data["testsGitHead"] = manifest.get("testsGitHead") or data.get("testsGitHead") or ""
    for letter, entry in (data.get("sections") or {}).items():
        entry["reviewed"] = True
        entry["summary"] = "Nothing found."
        entry["evidence"] = []
        mods = list(expanded.get(letter, []))
        if letter in checklist_letters:
            chk = checklist_sections.get(letter) or {}
            for p in parse_checklist_paths(chk.get("checklistItems") or []):
                if p not in mods:
                    mods.append(p)
        entry["modulesReviewed"] = mods
    if "B" in (data.get("sections") or {}):
        data["sections"]["B"]["inventoryAck"] = {
            "productionModules": inv.get("productionModules", 0),
            "testFiles": inv.get("testFiles", 0),
            "productionLoc": inv.get("productionLoc", 0),
        }
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return path


def _optional_import_dep_available(dep: str) -> bool:
    """True when an optional third-party dep is importable (mcp is optional per check-requirements)."""
    try:
        import importlib.util

        return importlib.util.find_spec(dep) is not None
    except (ImportError, AttributeError, ValueError):
        return False


def import_smoke(app_root: Path, exclude: set[str], cfg: dict | None = None) -> list[str]:
    fixes: list[str] = []
    cc = (cfg or {}).get("codeChecks") or {}
    ism = cc.get("importSmoke") or {}
    if ism.get("enabled", True) is False:
        return fixes
    skip_prefixes: list[tuple[str, str]] = []
    for entry in ism.get("skipWhenDepMissing") or []:
        if isinstance(entry, dict):
            prefix = str(entry.get("pathPrefix") or "").replace("\\", "/").strip()
            dep = str(entry.get("import") or "").strip()
            if prefix and dep:
                skip_prefixes.append((prefix.rstrip("/") + "/", dep))
    if not skip_prefixes and ism.get("skipMcpWhenPackageMissing", True):
        skip_prefixes.append(("mcp/", "mcp.server"))

    search_dirs: list[Path] = []
    dm = (cfg or {}).get("domainMap") or {}
    scan_rel = (dm.get("scanDir") or ".").replace("\\", "/").strip() or "."
    scan_dir = app_root if scan_rel in (".", "") else app_root / scan_rel
    if scan_dir.is_dir():
        search_dirs.append(scan_dir.resolve())
    if ism.get("useModuleSearchDirs", True):
        for rel in dm.get("moduleSearchDirs") or []:
            rel_norm = str(rel).replace("\\", "/").strip()
            if not rel_norm or rel_norm == ".":
                continue
            candidate = (app_root / rel_norm).resolve()
            if candidate.is_dir() and candidate not in search_dirs:
                search_dirs.append(candidate)
    for rel in ism.get("searchDirs") or []:
        rel_norm = str(rel).replace("\\", "/").strip()
        if not rel_norm or rel_norm == ".":
            continue
        candidate = (app_root / rel_norm).resolve()
        if candidate.is_dir() and candidate not in search_dirs:
            search_dirs.append(candidate)
    if not search_dirs:
        search_dirs = [app_root.resolve()]

    seen: set[str] = set()
    for scan_dir in search_dirs:
        env_base = {**os.environ, "QT_QPA_PLATFORM": "offscreen"}
        py_paths = sorted(scan_dir.glob("*.py"))
        for py in py_paths:
            rel_key = str(py.relative_to(app_root)).replace("\\", "/")
            if py.name in exclude or rel_key in seen:
                continue
            skip_optional = False
            for prefix, dep in skip_prefixes:
                if rel_key.startswith(prefix) and not _optional_import_dep_available(dep):
                    skip_optional = True
                    break
            if skip_optional:
                continue
            seen.add(rel_key)
            mod = py.stem
            env = {
                **env_base,
                "PYTHONPATH": str(scan_dir) + os.pathsep + str(app_root),
            }
            r = subprocess.run(
                [sys.executable, "-c", f"import {mod}"],
                cwd=str(app_root),
                env=env,
                capture_output=True,
                text=True,
            )
            if r.returncode != 0:
                err = (r.stderr or r.stdout or "import failed").strip().splitlines()[-1]
                fixes.append(f"Import smoke - {rel_key} - {err}")
    return fixes


def expand_brace_glob(pattern: str) -> list[str]:
    """Expand shell-style {a,b} alternatives, which pathlib.rglob does not understand.

    This pack's one content rule was written as "*.{md,ps1,mdc,cmd,bat,json,py}". rglob treats that
    as a literal filename, so the rule matched zero files and reported clean for as long as it
    existed. Expanding here keeps the config readable and makes the pattern mean what it looks like.
    """
    match = re.search(r"\{([^{}]*)\}", pattern)
    if not match:
        return [pattern]
    head, tail = pattern[: match.start()], pattern[match.end() :]
    out: list[str] = []
    for alt in match.group(1).split(","):
        out.extend(expand_brace_glob(f"{head}{alt.strip()}{tail}"))
    return out


def scan_static_patterns(
    app_root: Path, patterns: list[dict], allowlist: dict | None = None
) -> list[str]:
    fixes: list[str] = []
    allowlist = allowlist or {}
    for rule in patterns:
        rid = rule.get("id", "pattern")
        section = rule.get("section", "?")
        glob_pat = rule.get("glob", "*.py")
        exclude_re = rule.get("excludePathRegex", r"\\tests\\")
        forbidden = rule.get("forbiddenRegex", "")
        message = rule.get("message", "forbidden pattern")
        allow_line = rule.get("allowLineRegex", "")
        if not forbidden:
            continue
        try:
            forbidden_re = re.compile(forbidden, re.MULTILINE)
            allow_re = re.compile(allow_line) if allow_line else None
            exclude = re.compile(exclude_re) if exclude_re else None
        except re.error as exc:
            fixes.append(f"Static check config - {rid} - bad regex: {exc}")
            continue
        expanded_globs = expand_brace_glob(glob_pat)
        if any("{" in g or "}" in g for g in expanded_globs):
            # Unbalanced braces cannot expand, and rglob treats what is left as a literal filename,
            # so the rule would match nothing and report clean forever.
            fixes.append(
                f"Static check config - {rid} - glob '{glob_pat}' has unbalanced braces, so it "
                "matches nothing - fix the pattern"
            )
            continue
        candidates: list[Path] = []
        seen: set[str] = set()
        for expanded in expanded_globs:
            for hit in app_root.rglob(expanded):
                key = str(hit).lower()
                if key not in seen:
                    seen.add(key)
                    candidates.append(hit)
        # Opt-in, because an empty scope is legitimate: a Generic project has no *.py for the safety
        # patterns to scan. Set requireMatches on a rule whose scope must exist, and a glob that
        # stops matching is reported instead of quietly passing.
        if rule.get("requireMatches") and not any(c.is_file() for c in candidates):
            fixes.append(
                f"Static check config - {rid} - glob '{glob_pat}' matched no files, so this "
                "check never runs - fix the glob or remove the rule"
            )
            continue
        for py in candidates:
            if not py.is_file():
                continue
            rel = py.relative_to(app_root)
            if exclude and exclude.search(str(rel)):
                continue
            rel_str = str(rel).replace("\\", "/")
            try:
                text = py.read_text(encoding="utf-8-sig", errors="replace")
            except OSError as exc:
                fixes.append(f"Static check - {rel} - unreadable: {exc}")
                continue
            for i, line in enumerate(text.splitlines(), 1):
                if forbidden_re.search(line):
                    if allow_re and allow_re.search(line):
                        continue
                    if _line_allowlisted(allowlist, rel_str, i, rid):
                        continue
                    fixes.append(
                        f"Section {section} static - {rel}:{i} - {message} ({rid})"
                    )
                    break
    return fixes


def verify_section_test_files(app_root: Path, section_tests: dict[str, list[str]]) -> list[str]:
    fixes: list[str] = []
    seen: set[str] = set()
    for _section, files in sorted(section_tests.items()):
        for rel in files:
            rel_norm = rel.replace("\\", "/")
            if rel_norm in seen:
                continue
            seen.add(rel_norm)
            if not (app_root / rel_norm).is_file():
                fixes.append(f"Section {_section} - missing test file {rel_norm}")
    return fixes


def verify_sections_have_tests(
    domain_sections: dict[str, list[str]], section_tests: dict[str, list[str]]
) -> list[str]:
    fixes: list[str] = []
    for letter in sorted(domain_sections):
        if letter not in "DEFGHIJK":
            continue
        if letter not in section_tests or not section_tests[letter]:
            fixes.append(f"Section {letter} - no sectionTests in AUDIT.config.json codeChecks")
    return fixes


def run_self_test() -> int:
    md = """## Full checklist (A-N, all mandatory)

### A. Tests & version
- run_tests.bat

### F. Settings
- `app_settings.py`, `catalog_cache.py` | portable

## Domain map
| Module / area | Section |
|---------------|---------|
| `app_settings.py`, `catalog_cache.py`, `hardware_cache.py` | F |
| `main.py` | D |
"""
    with tempfile.TemporaryDirectory() as tmp:
        audit_md = Path(tmp) / "AUDIT.md"
        audit_md.write_text(md, encoding="utf-8")
        checklist = parse_checklist_sections(audit_md)
        parsed = parse_domain_map(audit_md)
        errors: list[str] = []
        if "A" not in checklist or "F" not in checklist:
            errors.append(f"parse_checklist_sections missing letters: {list(checklist)}")
        if not checklist.get("A", {}).get("checklistItems"):
            errors.append("checklist A missing bullets")
        for letter, expected in {
            "F": {"app_settings.py", "catalog_cache.py", "hardware_cache.py"},
            "D": {"main.py"},
        }.items():
            got = set(parsed.get(letter, []))
            if not expected.issubset(got):
                errors.append(f"parse_domain_map {letter}: expected {expected}, got {got}")
        section_tests = {"F": ["tests/t_f.py"], "K": ["tests/t_k.py"]}
        hints = {"A": ["version sync"], "F": ["portable paths"], "K": ["bare except policy"]}
        manifest, required = build_agent_sections(checklist, parsed, section_tests, hints)
        if "A" not in manifest:
            errors.append("manifest missing checklist-only section A")
        if "K" not in manifest:
            errors.append("manifest missing K from sectionTests/hints")
        if "A" not in required:
            errors.append("requiredSections missing A")
        if not is_clean_summary("Nothing found."):
            errors.append("is_clean_summary failed")
        if not summary_has_cite("Issue in `foo.py` line 10"):
            errors.append("summary_has_cite failed on good cite")
        if summary_has_cite("vague issue with no path"):
            errors.append("summary_has_cite false positive")
        e_paths = parse_checklist_paths(
            [
                "`pack/scripts/run_audit_core.ps1`, `sync-audit-system.ps1`",
                "`install.ps1`, `bootstrap-project.ps1`",
            ]
        )
        if "pack/scripts/run_audit_core.ps1" not in e_paths or "install.ps1" not in e_paths:
            errors.append(f"parse_checklist_paths: {e_paths}")
        with tempfile.TemporaryDirectory() as ev_tmp:
            ev_root = Path(ev_tmp)
            (ev_root / "docs").mkdir()
            (ev_root / "foo.py").write_text("# x\n", encoding="utf-8")
            ev_cfg = {"codeChecks": {"semanticReportRequireEvidence": True}}
            bad_ev = validate_section_evidence(
                ev_root,
                "D",
                {"evidence": [{"type": "file", "ref": "missing.py"}]},
                "Issue in missing module",
                ev_cfg,
            )
            if not bad_ev:
                errors.append("validate_section_evidence should fail on missing file")
            good_ev = validate_section_evidence(
                ev_root,
                "D",
                {"evidence": [{"type": "file", "ref": "foo.py"}]},
                "Issue in `foo.py`",
                ev_cfg,
            )
            if good_ev:
                errors.append(f"validate_section_evidence false positive: {good_ev}")
        if map_fixes_to_sections(["Section M - x"]) != {"M": ["Section M - x"]}:
            errors.append("map_fixes_to_sections failed")
        dup_md = """## Domain map
| Module / area | Section |
|---------------|---------|
| `main.py`, `main.py` | D |
"""
        with tempfile.TemporaryDirectory() as dup_tmp:
            dup_path = Path(dup_tmp) / "AUDIT.md"
            dup_path.write_text(dup_md, encoding="utf-8")
            dup_parsed = parse_domain_map(dup_path)
            if dup_parsed.get("D") != ["main.py"]:
                errors.append(f"parse_domain_map dedupe failed: {dup_parsed.get('D')}")
        with tempfile.TemporaryDirectory() as dm_tmp:
            dm_root = Path(dm_tmp)
            (dm_root / "docs").mkdir()
            (dm_root / "exists.py").write_text("# ok\n", encoding="utf-8")
            dm_cfg = {"domainMap": {"scanDir": ".", "excludeModules": []}}
            dm_fix = verify_domain_map_modules_exist(
                dm_root, dm_cfg, {"D": ["exists.py", "missing.py"]}
            )
            if len(dm_fix) != 1 or "missing.py" not in dm_fix[0]:
                errors.append(f"verify_domain_map_modules_exist: {dm_fix}")
        cfg_with_dm = {"domainMap": {"scanDir": "."}, "codeChecks": {}}
        mc = collect_config_machine_checks(cfg_with_dm, parsed)
        if "domain map module existence" in mc.get("A", []):
            errors.append("machineCoverage: section A has no domain modules")
        if "domain map module existence" not in mc.get("F", []):
            errors.append("machineCoverage: section F missing domain map module existence")
        if "domain map module existence" not in mc.get("D", []):
            errors.append("machineCoverage: section D missing domain map module existence")
        if "domain map module existence" in mc.get("K", []):
            errors.append("machineCoverage: section K has no domain modules")
        try:
            exec_re = re.compile(r"(?<!\.)exec\(")
        except re.error as exc:
            errors.append(f"exec-call pattern bad regex: {exc}")
        else:
            if exec_re.search("dlg.exec()") or exec_re.search("app.exec()"):
                errors.append("exec-call pattern matched Qt .exec()")
            if not exec_re.search("exec(code)"):
                errors.append("exec-call pattern missed bare exec(")
        if errors:
            for e in errors:
                print(e, file=sys.stderr)
            return 1
        print("audit_code_checks self-test: OK")
        return 0


def main() -> int:
    if "--self-test" in sys.argv:
        return run_self_test()

    app_root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    if "--print-repo-root" in sys.argv:
        print(resolve_repo_root(app_root))
        return 0
    full_tests_ran = "--full-tests-ran" in sys.argv
    lightweight = "--lightweight" in sys.argv
    verify_report = "--verify-semantic-report" in sys.argv
    write_template = "--write-semantic-template" in sys.argv
    write_inventory = "--write-audit-inventory" in sys.argv
    write_expanded = "--write-expanded-domain-map" in sys.argv
    write_receipt = "--write-audit-receipt" in sys.argv
    fill_fixture = "--fill-semantic-fixture-test" in sys.argv
    print_tests_head = "--print-tests-git-head" in sys.argv
    sync_doc_versions_flag = "--sync-doc-versions" in sys.argv
    verify_doc_versions_flag = "--verify-doc-versions" in sys.argv

    cfg = load_config(app_root)

    if sync_doc_versions_flag or verify_doc_versions_flag:
        from doc_version_sync import sync_documentation_versions

        result = sync_documentation_versions(
            app_root, dry_run=verify_doc_versions_flag
        )
        print(json.dumps(result, indent=2))
        return 0 if result.get("ok") else 1

    cc = cfg.get("codeChecks") or {}
    audit_md = app_root / "docs" / "AUDIT.md"
    checklist_sections = parse_checklist_sections(audit_md)
    domain_sections = parse_domain_map(audit_md)
    expanded_domain = expand_domain_map_modules(app_root, cfg, domain_sections)
    section_tests: dict[str, list[str]] = cc.get("sectionTests") or {}
    semantic_hints: dict[str, list] = cc.get("semanticReviewHints") or {}
    agent_sections, required_sections = build_agent_sections(
        checklist_sections, domain_sections, section_tests, semantic_hints
    )
    # Section N (release hygiene) has a machine check but no checklist heading, so it never reached
    # required_sections: --write-template produced no N stub while the check demanded N content, a
    # Fix with no remedy. Where the check is enabled, N is a section like any other.
    if (cc.get("sectionMachineChecks") or {}).get("N", {}).get("enabled", False):
        if "N" not in agent_sections:
            agent_sections["N"] = {
                "title": "Release hygiene (version, changelog, manifest)",
                "checklistItems": [],
                "modules": [],
                "machineTests": [],
                "semanticReview": semantic_hints.get("N", []),
            }
        if "N" not in required_sections:
            required_sections = sorted(set(required_sections) | {"N"})

    if write_inventory:
        inv = write_audit_inventory(app_root, cfg)
        print(json.dumps({"inventoryFile": (cc.get("inventoryFile") or "docs/.audit_inventory.json"), "inventory": inv}))
        return 0

    if write_expanded:
        path = write_expanded_domain_map(app_root, cfg, expanded_domain)
        print(f"Wrote expanded domain map: {path}")
        return 0

    if write_receipt:
        manifest = load_manifest(app_root)
        path = write_audit_receipt(app_root, cfg, manifest)
        print(f"Wrote audit receipt: {path}")
        return 0

    if write_template:
        path = write_semantic_template(app_root, cfg, required_sections)
        print(f"Wrote semantic report template: {path}")
        return 0

    if fill_fixture:
        # This flag marks every checklist section reviewed with no findings. That is a harness
        # shortcut for the behavior fixtures, and it is also a one-command way to fake a whole
        # semantic review, so it stays behind an opt-in the suite sets and nobody else does.
        if os.environ.get("AUDIT_FIXTURE_TEST") != "1":
            print(
                "Refusing --fill-semantic-fixture-test: it marks every section reviewed with no "
                "findings, which is a test harness shortcut, not an audit. The suite sets "
                "AUDIT_FIXTURE_TEST=1; to review a real project, fill the semantic report."
            )
            return 2
        path = fill_semantic_fixture(app_root, cfg, required_sections, expanded_domain)
        print(f"Filled semantic fixture report: {path}")
        return 0

    if print_tests_head:
        head = get_current_tests_proof_head(app_root, cfg) or ""
        print(head)
        return 0 if head else 1

    if verify_report:
        fixes = verify_semantic_report(
            app_root, cfg, required_sections, lightweight=lightweight, domain_sections=domain_sections
        )
        result = {"fixes": fixes, "improve": [], "semanticReportValid": len(fixes) == 0}
        print(json.dumps(result))
        return 1 if fixes else 0

    fixes: list[str] = []
    improve: list[str] = []

    if not lightweight:
        fixes.extend(collect_code_machine_fixes(app_root, cfg, False, domain_sections))
    else:
        fixes.extend(collect_code_machine_fixes(app_root, cfg, True, domain_sections))

    fixes.extend(verify_sections_have_tests(domain_sections, section_tests))
    fixes.extend(verify_section_test_files(app_root, section_tests))
    fixes.extend(check_test_runner_coverage(app_root, cfg))
    improve.extend(check_section_n_improve(app_root, cfg))
    improve.extend(check_audit_version_docs_improve(app_root, cfg))
    improve.extend(check_pack_version_docs_improve(app_root, cfg))
    improve.extend(check_pack_reference_config_improve(app_root, cfg))
    improve.extend(check_installed_vs_source_improve(app_root, cfg))
    improve.extend(check_changelog_version_improve(app_root, cfg))
    improve.extend(check_mcp_wiring_improve(app_root, cfg))
    improve.extend(check_large_modules_improve(app_root, cfg, expanded_domain))
    improve.extend(scan_unused_imports_improve(app_root, cfg))
    improve.extend(find_test_gap_improves(app_root, expanded_domain, cfg))

    if not lightweight and full_tests_ran:
        write_audit_inventory(app_root, cfg)
        write_expanded_domain_map(app_root, cfg, expanded_domain)

    if not full_tests_ran:
        fixes.append(
            "Incomplete audit - full run_tests.bat required (never use -SkipTests for audit)"
        )

    report_rel = (cc.get("semanticReportFile") or "docs/.audit_semantic_report.json").replace(
        "\\", "/"
    )
    machine_coverage = build_machine_coverage(
        agent_sections, cfg, semantic_hints, domain_sections
    )
    machine_fixes_by_section = map_fixes_to_sections(
        [f for f in fixes if not f.startswith("Incomplete audit")]
    )

    result = {
        "fixes": fixes,
        "improve": improve,
        "requiredSections": required_sections,
        "semanticReportFile": report_rel,
        "machineCoverage": machine_coverage,
        "machineFixesBySection": machine_fixes_by_section,
        "machineSectionsWithFixes": sorted(machine_fixes_by_section.keys()),
        "agentSections": agent_sections,
        "machineClosed": len(fixes) == 0,
        "expandedDomainMapFile": (cc.get("expandedDomainMapFile") or "docs/.audit_domain_expanded.json"),
        "inventoryFile": (cc.get("inventoryFile") or "docs/.audit_inventory.json"),
    }
    print(json.dumps(result))
    return 1 if fixes else 0


if __name__ == "__main__":
    raise SystemExit(main())
