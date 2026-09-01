"""Pack self-audit tests - audit engine, doc version sync, install launcher, MCP server."""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CODE = ROOT / "pack" / "scripts" / "audit_code_checks.py"
DOC_VERSION_SYNC = ROOT / "pack" / "scripts" / "doc_version_sync.py"
INSTALL_LAUNCHER = ROOT / "install_launcher.py"
MCP_SERVER = ROOT / "mcp" / "agent_hygiene_server.py"
FRESHNESS = ROOT / "pack" / "scripts" / "agent_context_freshness.py"


def test_audit_code_checks_self_test() -> None:
    r = subprocess.run(
        [sys.executable, str(CODE), "--self-test"],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert r.returncode == 0, (r.stderr or r.stdout or "self-test failed").strip()


def test_manifest_json_exists() -> None:
    manifest = ROOT / "pack" / "audit" / "manifest.json"
    assert manifest.is_file(), "pack/audit/manifest.json missing"


def _load_doc_version_sync():
    spec = importlib.util.spec_from_file_location("doc_version_sync", DOC_VERSION_SYNC)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_doc_version_sync_repo_root_stays_in_project() -> None:
    """This module writes: a wrong repo root rewrites files outside the project.

    The rule shipped here promoted the parent whenever it held a README.md, so `apply_version.py
    sync` in a flat project beside a README rewrote version cites in the parent folder. Three files
    decide this - run_audit.ps1.template, audit_code_checks.py, and this one - and they must agree.
    """
    mod = _load_doc_version_sync()
    with tempfile.TemporaryDirectory() as tmp:
        parent = Path(tmp)
        (parent / "README.md").write_text("# outside v0.0.1\n", encoding="utf-8")
        (parent / ".git").mkdir()
        proj = parent / "MyApp"
        (proj / "docs").mkdir(parents=True)
        (proj / "docs" / "AUDIT.md").write_text("# audit\n", encoding="utf-8")
        assert mod.resolve_repo_root(proj) == proj.resolve(), "flat project promoted its parent"

        nested = parent / "app"
        (nested / "docs").mkdir(parents=True)
        (nested / "docs" / "AUDIT.md").write_text("# audit\n", encoding="utf-8")
        assert mod.resolve_repo_root(nested) == parent.resolve(), "nested app layout not detected"

        own_git = parent / "Solo"
        (own_git / "docs").mkdir(parents=True)
        (own_git / "docs" / "AUDIT.md").write_text("# audit\n", encoding="utf-8")
        (own_git / ".git").mkdir()
        assert mod.resolve_repo_root(own_git) == own_git.resolve(), "project with own .git promoted parent"


def test_doc_version_sync_round_trip() -> None:
    """Stale cites are detected, syncing repairs them, and a second verify is clean."""
    mod = _load_doc_version_sync()
    with tempfile.TemporaryDirectory() as tmp:
        proj = Path(tmp) / "proj"
        (proj / "docs").mkdir(parents=True)
        (proj / ".git").mkdir()
        # Same shape a generated project gets: canonical.txtFile plus a pattern to read it with.
        (proj / "VERSION.txt").write_text("Version: 2.0.0\n", encoding="utf-8")
        (proj / "README.md").write_text("MyApp v1.0.0 - see docs.\n", encoding="utf-8")
        (proj / "docs" / "VERSION_SYNC.json").write_text(
            json.dumps(
                {
                    "canonical": {"txtFile": "VERSION.txt", "txtPattern": r"^Version:\s*(\S+)"},
                    "docSync": {"enabled": True, "scanFiles": ["README.md"]},
                }
            ),
            encoding="utf-8",
        )
        stale = mod.sync_documentation_versions(proj, dry_run=True)
        assert not stale["ok"] and stale["stale"], f"stale cite not detected: {stale}"
        applied = mod.sync_documentation_versions(proj, dry_run=False)
        assert applied["ok"] and applied["updated"], f"sync did not update: {applied}"
        assert "v2.0.0" in (proj / "README.md").read_text(encoding="utf-8")
        again = mod.sync_documentation_versions(proj, dry_run=True)
        assert again["ok"] and not again["stale"], f"not idempotent: {again}"


def test_sync_doc_versions_cli() -> None:
    """sync_doc_versions.py is the CLI wrapper: it must resolve the engine and emit JSON."""
    r = subprocess.run(
        [sys.executable, str(ROOT / "pack" / "scripts" / "sync_doc_versions.py"), str(ROOT), "--verify"],
        capture_output=True,
        text=True,
        timeout=120,
    )
    payload = json.loads(r.stdout[r.stdout.index("{") : r.stdout.rindex("}") + 1])
    assert set(payload) >= {"updated", "stale", "ok"}, f"unexpected payload: {payload}"
    assert r.returncode == (0 if payload["ok"] else 1), "exit code disagrees with ok flag"


def test_install_launcher_py() -> None:
    """Coverage hook for install_launcher.py (section F)."""
    spec = importlib.util.spec_from_file_location("install_launcher", INSTALL_LAUNCHER)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    root = mod._pack_root()
    assert root.is_dir()
    assert (root / "VERSION").is_file() or (root / "install.ps1").is_file()


def test_agent_hygiene_server_py() -> None:
    """Coverage hook for agent_hygiene_server.py (section G)."""
    spec = importlib.util.spec_from_file_location("agent_hygiene_server", MCP_SERVER)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    try:
        # The module prints to stderr when mcp is absent; swallow it so a passing run stays quiet
        # (PowerShell callers with $ErrorActionPreference='Stop' treat native stderr as a failure).
        with contextlib.redirect_stderr(io.StringIO()):
            spec.loader.exec_module(mod)
    except ModuleNotFoundError as exc:
        if "mcp" in str(exc).lower():
            # mcp is an optional requirement (MCP tools only); skip when it is not installed.
            return
        raise
    assert getattr(mod, "mcp", None) is not None


def _load_audit_code_checks():
    spec = importlib.util.spec_from_file_location("audit_code_checks", CODE)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_static_pattern_brace_glob_scans_files() -> None:
    """The pack's only content rule used a {a,b} glob, which rglob matched literally.

    It therefore scanned zero files and reported clean for as long as it existed. Nothing failed
    when that happened, which is why it survived; this test is what fails now.
    """
    mod = _load_audit_code_checks()
    assert mod.expand_brace_glob("*.{md,ps1}") == ["*.md", "*.ps1"]
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "doc.md").write_text("forbidden-token here\n", encoding="utf-8")
        (root / "script.ps1").write_text("clean\n", encoding="utf-8")
        rule = {
            "id": "probe",
            "section": "L",
            "glob": "*.{md,ps1}",
            "excludePathRegex": "",
            "forbiddenRegex": "forbidden-token",
            "message": "probe message",
        }
        hits = mod.scan_static_patterns(root, [rule])
        assert len(hits) == 1 and "doc.md:1" in hits[0], hits


def test_static_pattern_inert_glob_is_reported_when_required() -> None:
    """requireMatches turns "this rule stopped matching anything" into a finding."""
    mod = _load_audit_code_checks()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "doc.md").write_text("nothing to see\n", encoding="utf-8")
        base = {"id": "probe", "section": "L", "forbiddenRegex": "x", "excludePathRegex": ""}
        silent = mod.scan_static_patterns(root, [dict(base, glob="*.nomatch")])
        assert silent == [], silent
        loud = mod.scan_static_patterns(
            root, [dict(base, glob="*.nomatch", requireMatches=True)]
        )
        assert loud and "matched no files" in loud[0], loud
        unbalanced = mod.scan_static_patterns(root, [dict(base, glob="*.{md,ps1")])
        assert unbalanced and "unbalanced braces" in unbalanced[0], unbalanced


def test_section_n_semantic_check_is_opt_in() -> None:
    """N has no checklist heading, so a default-on check could demand a section with no stub."""
    mod = _load_audit_code_checks()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        assert mod.verify_section_n_semantic(root, {"codeChecks": {}}, {}) == []


def test_machine_improves_must_be_addressed_in_semantic_summary() -> None:
    """Fix lines blocked a clean summary; Improve lines blocked nothing.

    So a layout finding could sit in machineImprovesBySection.B while the section closed on
    "Nothing found." - which is how delete-only Section B reviews kept passing.
    """
    mod = _load_audit_code_checks()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "docs").mkdir()
        (root / "docs" / ".audit_agent_manifest.json").write_text(
            json.dumps(
                {
                    "machineImprovesBySection": {
                        "B": ["Layout - duplicate stable copy in repo - MyApp_v6_stable - use an external archive"]
                    }
                }
            ),
            encoding="utf-8",
        )
        cfg: dict = {"codeChecks": {}}
        clean = mod.verify_semantic_vs_machine_improves(
            root, cfg, {"B": {"summary": "Nothing found."}}, ["B"]
        )
        assert clean and "does not address" in clean[0], clean

        keyword = mod.verify_semantic_vs_machine_improves(
            root, cfg, {"B": {"summary": "Reviewed layout; naming is unclear."}}, ["B"]
        )
        assert keyword == [], keyword

        cited = mod.verify_semantic_vs_machine_improves(
            root, cfg, {"B": {"summary": "MyApp_v6_stable duplicates the release archive."}}, ["B"]
        )
        assert cited == [], cited

        # Off switch, and sections the project does not require, must both stay silent.
        off = mod.verify_semantic_vs_machine_improves(
            root,
            {"codeChecks": {"semanticRequireMachineImproveMention": False}},
            {"B": {"summary": "Nothing found."}},
            ["B"],
        )
        assert off == [], off
        other = mod.verify_semantic_vs_machine_improves(
            root, cfg, {"A": {"summary": "Nothing found."}}, ["A"]
        )
        assert other == [], other


def test_section_e_requires_checklist_paths_in_modules_reviewed() -> None:
    """Section E lists PS paths in the checklist but not in the Python domain map."""
    mod = _load_audit_code_checks()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "docs").mkdir()
        audit_md = root / "docs" / "AUDIT.md"
        audit_md.write_text(
            "## Checklist sections\n"
            "### E. PowerShell audit engine\n"
            "- `pack/scripts/run_audit_core.ps1`, `sync-audit-system.ps1`\n",
            encoding="utf-8",
        )
        cfg: dict = {
            "codeChecks": {
                "semanticRequireModulesReviewed": True,
                "semanticChecklistPathSections": ["E"],
            }
        }
        checklist = mod.parse_checklist_sections(audit_md)
        empty = mod.verify_checklist_paths_reviewed(
            checklist, {"E": {"summary": "Nothing found.", "modulesReviewed": []}}, cfg
        )
        assert empty and "missing checklist paths" in empty[0], empty
        ok = mod.verify_checklist_paths_reviewed(
            checklist,
            {
                "E": {
                    "summary": "Nothing found.",
                    "modulesReviewed": [
                        "pack/scripts/run_audit_core.ps1",
                        "sync-audit-system.ps1",
                    ],
                }
            },
            cfg,
        )
        assert ok == [], ok


def test_layout_policy_is_disabled_in_the_generic_template() -> None:
    """A minimal project must not inherit MyApp folder names or a check it never configured."""
    template = ROOT / "pack" / "templates" / "docs" / "AUDIT.config.json.template"
    cfg = json.loads(template.read_text(encoding="utf-8-sig"))
    policy = cfg.get("layoutPolicy")
    assert policy is not None, "layoutPolicy missing from the generic template"
    assert policy.get("enabled") is False, "layoutPolicy must ship disabled"
    for key in ("buildOutputDir", "portableDataDirname", "forbiddenInRepoStableCopy"):
        assert policy.get(key) == "", f"{key} must ship empty, not a placeholder folder name"


def _load_script_module(name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / "pack" / "scripts" / f"{name}.py")
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def test_split_modules_keep_the_engine_under_its_own_threshold() -> None:
    """The engine enforces a LOC ceiling on every module; it was 92 lines over its own.

    Section M version cites and the checks that read outside the repo now live in siblings. If
    this file creeps back over the threshold, the audit reports it as an Improve, which is how the
    split was prompted in the first place.
    """
    cfg = json.loads((ROOT / "docs" / "AUDIT.config.json").read_text(encoding="utf-8-sig"))
    threshold = (cfg.get("codeChecks") or {}).get("largeModuleLocThreshold", 2000)
    loc = len(CODE.read_text(encoding="utf-8", errors="replace").splitlines())
    assert loc <= threshold, f"audit_code_checks.py is {loc} LOC, over its own {threshold} ceiling"


def test_moved_checks_are_still_reachable_through_the_engine() -> None:
    """Splitting a module must not move its public surface.

    `run_audit_core.ps1` and the self-test call these by name through `audit_code_checks`; the
    sibling modules are an implementation detail of where the bodies live.
    """
    sys.path.insert(0, str(ROOT / "pack" / "scripts"))
    try:
        engine = _load_script_module("audit_code_checks")
    finally:
        sys.path.pop(0)
    for name in (
        "resolve_repo_root",
        "read_canonical_version",
        "read_audit_manifest_version",
        "check_audit_version_docs_improve",
        "check_pack_version_docs_improve",
        "check_changelog_version_improve",
        "check_installed_vs_source_improve",
        "check_mcp_wiring_improve",
        "check_pack_reference_config_improve",
    ):
        assert hasattr(engine, name), f"audit_code_checks no longer exposes {name}"


def test_audit_version_docs_flags_only_stale_cites() -> None:
    """A doc citing the current engine version is clean; one citing an older one is an Improve."""
    sys.path.insert(0, str(ROOT / "pack" / "scripts"))
    try:
        _load_script_module("audit_common")
        mod = _load_script_module("audit_version_docs")
    finally:
        sys.path.pop(0)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "pack" / "audit").mkdir(parents=True)
        (root / "pack" / "audit" / "manifest.json").write_text(
            json.dumps({"version": "3.0.0"}), encoding="utf-8"
        )
        (root / "docs").mkdir()
        (root / "NOTES.md").write_text(
            "Audit engine version: `pack/audit/manifest.json` (**3.0.0**)\n", encoding="utf-8"
        )
        cfg = {
            "codeChecks": {
                "auditVersionDocs": {
                    "enabled": True,
                    "manifestPath": "pack/audit/manifest.json",
                    "scanFiles": ["NOTES.md"],
                }
            }
        }
        assert mod.check_audit_version_docs_improve(root, cfg) == []
        (root / "NOTES.md").write_text(
            "Audit engine version: `pack/audit/manifest.json` (**2.9.9**)\n", encoding="utf-8"
        )
        found = mod.check_audit_version_docs_improve(root, cfg)
        assert len(found) == 1 and "2.9.9" in found[0] and "3.0.0" in found[0], found


def test_install_wiring_reads_the_install_root_override() -> None:
    """The installed-vs-source check must follow the override, not the real profile."""
    sys.path.insert(0, str(ROOT / "pack" / "scripts"))
    try:
        _load_script_module("audit_common")
        mod = _load_script_module("audit_install_wiring")
    finally:
        sys.path.pop(0)
    with tempfile.TemporaryDirectory() as tmp:
        installed = Path(tmp) / "installed"
        (installed / "pack" / "audit").mkdir(parents=True)
        (installed / "pack" / "audit" / "manifest.json").write_text(
            json.dumps({"version": "1.2.3"}), encoding="utf-8"
        )
        prev = os.environ.get("AGENT_STARTER_PACK_INSTALL_ROOT")
        os.environ["AGENT_STARTER_PACK_INSTALL_ROOT"] = str(installed)
        try:
            assert mod._installed_pack_root() == installed.resolve()
            assert mod._user_cursor_root() == installed.resolve().parent
        finally:
            if prev is None:
                os.environ.pop("AGENT_STARTER_PACK_INSTALL_ROOT", None)
            else:
                os.environ["AGENT_STARTER_PACK_INSTALL_ROOT"] = prev


def _load_agent_context_freshness():
    spec = importlib.util.spec_from_file_location("agent_context_freshness", FRESHNESS)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_freshness_resolves_the_install_root_override() -> None:
    """The override decides which install a project's stamp is compared against.

    PowerShell has honoured AGENT_STARTER_PACK_INSTALL_ROOT since 2.22.4. While Python read
    %USERPROFILE% instead, the freshness verdict - and the behavior step built on it - was a
    property of the developer's machine rather than of the pack.
    """
    mod = _load_agent_context_freshness()
    with tempfile.TemporaryDirectory() as tmp:
        scratch = Path(tmp) / "installed"
        (scratch / "pack" / "audit").mkdir(parents=True)
        (scratch / "pack" / "audit" / "manifest.json").write_text(
            json.dumps({"version": "9.9.9"}), encoding="utf-8"
        )
        prev = os.environ.get("AGENT_STARTER_PACK_INSTALL_ROOT")
        os.environ["AGENT_STARTER_PACK_INSTALL_ROOT"] = str(scratch)
        try:
            resolved = mod.resolve_pack_root()
            assert resolved == scratch.resolve(), f"override ignored, resolved {resolved}"
            assert mod.installed_engine_version(resolved) == "9.9.9"
        finally:
            if prev is None:
                os.environ.pop("AGENT_STARTER_PACK_INSTALL_ROOT", None)
            else:
                os.environ["AGENT_STARTER_PACK_INSTALL_ROOT"] = prev


def test_freshness_trigger_phrases_match_the_rules() -> None:
    """Every phrase the docs tell a user to type has to be one the module recognises."""
    mod = _load_agent_context_freshness()
    documented = (ROOT / "pack" / "templates" / "portable" / "AI_INSTRUCTIONS.md.template").read_text(
        encoding="utf-8-sig"
    ).lower()
    missing = [p for p in mod.TRIGGER_PHRASES if p not in documented]
    assert not missing, f"trigger phrases absent from the portable instructions: {missing}"


def main() -> int:
    """Run without pytest, so the pack has no test dependency the preflight does not check.

    Matches the runner the pack generates for projects (`py -3 tests\\test_x.py`); pytest still
    collects the test_* functions unchanged if it happens to be installed.
    """
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    failed = []
    for fn in tests:
        try:
            fn()
        except Exception as exc:  # noqa: BLE001 - report every failure, do not stop at the first
            failed.append((fn.__name__, exc))
            print(f"FAIL {fn.__name__}: {exc}")
        else:
            print(f"ok   {fn.__name__}")
    print(f"\n{len(tests) - len(failed)}/{len(tests)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
