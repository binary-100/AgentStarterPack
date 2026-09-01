#!/usr/bin/env python3
"""Primitives shared by the audit engine and its check modules.

`audit_code_checks.py` grew past the 2500-line threshold its own Section D check enforces, so the
version-doc and install-wiring checks moved into sibling modules. Those modules and the engine all
need the same four things - config, repo root, canonical version, manifest version - and this file
exists so they can share them without importing each other in a circle.

Not a general dumping ground: anything here has to be needed by more than one module.

Deliberately *not* shared with `doc_version_sync.py`. That module keeps its own copy of
`resolve_repo_root` and the version regexes because it is the build pipeline and must not depend on
the audit engine; behavior step 23 asserts the two copies agree rather than merging them.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

VERSION_IN_DOC_RE = re.compile(r"\bv(\d+\.\d+\.\d+)\b")


def load_config(app_root: Path) -> dict:
    # utf-8-sig everywhere this module reads project files: Windows PowerShell 5.1 writes a BOM for
    # -Encoding UTF8, so files produced by pack scripts (or edited in a Windows editor) carry one.
    # Plain "utf-8" made json.loads fail with "Unexpected UTF-8 BOM" on every bootstrapped project.
    cfg_path = app_root / "docs" / "AUDIT.config.json"
    if not cfg_path.is_file():
        return {}
    return json.loads(cfg_path.read_text(encoding="utf-8-sig"))


def resolve_repo_root(app_root: Path) -> Path:
    """Repo root for git, version-doc, and evidence lookups.

    This rule must stay in step with run_audit.ps1.template: two layers deriving the repo root from
    different rules is how the audit ended up scanning a folder above the project. The old rule here
    promoted the parent whenever it held a README.md, which swept in every sibling of a flat app
    that happened to live under a folder with a README, while the wrapper stayed on the app root.
    Behavior step 23 asserts both layers agree. Deliberately derived from app_root rather than taken
    from the wrapper: the behavior fixture's wrapper declares an outer repo root, and honouring that
    would tie its test-pass proof to the pack's git HEAD instead of the fixture's own files.
    """
    app_root = app_root.resolve()
    # .git is a file in worktrees and submodules, so test existence rather than is_dir().
    if (app_root / ".git").exists():
        return app_root
    parent = app_root.parent
    if (
        app_root.name.lower() == "app"
        and (app_root / "docs" / "AUDIT.md").is_file()
        and (parent / ".git").exists()
    ):
        return parent.resolve()
    return app_root


def read_canonical_version(app_root: Path, cfg: dict) -> str | None:
    try:
        from doc_version_sync import read_canonical_version as _read_vs

        v = _read_vs(app_root)
        if v:
            return v
    except ImportError:
        pass
    vs = cfg.get("versionSync")
    if not vs:
        return None
    txt = app_root / (vs.get("txtFile") or "VERSION.txt")
    if not txt.is_file():
        return None
    pat = re.compile(vs.get("txtPattern") or r"^Version:\s*(\S+)", re.M)
    m = pat.search(txt.read_text(encoding="utf-8", errors="replace"))
    return m.group(1) if m else None


def read_audit_manifest_version(app_root: Path, manifest_rel: str) -> str | None:
    repo_root = resolve_repo_root(app_root)
    manifest_path = repo_root / manifest_rel.replace("\\", "/")
    if not manifest_path.is_file():
        return None
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError):
        return None
    ver = data.get("version")
    return str(ver).strip() if ver else None
