#!/usr/bin/env python3
"""Section M checks: version numbers docs claim vs the ones that are true.

Split out of `audit_code_checks.py` when it passed the 2500-line threshold its own Section D check
enforces. Three canonical numbers, three sets of patterns, because docs cite them in different
prose: the audit engine (`pack/audit/manifest.json`), the pack release (root `VERSION`), and an
application's own version (`versionSync`). A line can mention two of them at once, which is why
`_pack_version_line_segment` cuts the line before any audit-engine marker.

`doc_version_sync.py` carries its own copy of these patterns on purpose - it is the build pipeline
and must not import the audit engine.
"""

from __future__ import annotations

import re
from pathlib import Path

from audit_common import (
    VERSION_IN_DOC_RE,
    read_audit_manifest_version,
    read_canonical_version,
    resolve_repo_root,
)

DOC_INLINE_VERSION_RE = re.compile(
    r"\*\*(\d+\.\d+\.\d+)\*\*|\((\d+\.\d+\.\d+)\)|starter pack (\d+\.\d+\.\d+)",
    re.I,
)
AUDIT_ENGINE_VERSION_PATTERNS = (
    re.compile(r"manifest\.json[^|\n]*\(\*?\*?(\d+\.\d+\.\d+)\*?\*?\)", re.I),
    re.compile(r"audit engine[^|\n]*\(\*?\*?(\d+\.\d+\.\d+)\*?\*?\)", re.I),
    re.compile(r"audit engine version[^|\n]*\(\*?\*?(\d+\.\d+\.\d+)\*?\*?\)", re.I),
    re.compile(r"currently \*\*(\d+\.\d+\.\d+)\*\*", re.I),
    re.compile(r"starter pack (\d+\.\d+\.\d+)", re.I),
)

PACK_RELEASE_VERSION_PATTERNS = (
    re.compile(r"pack version[^.\n]*\(\*?\*?(\d+\.\d+\.\d+)\*?\*?\)", re.I),
    re.compile(r"starter pack release[^|\n]*\(\*?\*?(\d+\.\d+\.\d+)\*?\*?\)", re.I),
    re.compile(r"root `VERSION`[^|\n]*\(\*?\*?(\d+\.\d+\.\d+)\*?\*?\)", re.I),
    re.compile(r"see root `VERSION`[^|\n]*\(\*?\*?(\d+\.\d+\.\d+)\*?\*?\)", re.I),
    re.compile(r"pack version:[^.\n]*currently \*\*(\d+\.\d+\.\d+)\*\*", re.I),
)


def _extract_audit_engine_semvers(line: str) -> list[str]:
    found: list[str] = []
    for pat in AUDIT_ENGINE_VERSION_PATTERNS:
        for m in pat.finditer(line):
            found.append(m.group(1))
    return found


def check_audit_version_docs_improve(app_root: Path, cfg: dict) -> list[str]:
    """Improve when maintainer docs cite a stale audit-engine version vs manifest.json."""
    improve: list[str] = []
    avd = (cfg.get("codeChecks") or {}).get("auditVersionDocs") or {}
    if not avd.get("enabled", False):
        return improve
    manifest_rel = (avd.get("manifestPath") or "pack/audit/manifest.json").replace("\\", "/")
    canonical = read_audit_manifest_version(app_root, manifest_rel)
    if not canonical:
        return improve
    repo_root = resolve_repo_root(app_root)
    keywords = [k.lower() for k in (avd.get("contextKeywords") or ["manifest.json", "audit engine"])]
    reported: set[tuple[str, str]] = set()
    for rel in avd.get("scanFiles") or []:
        md = repo_root / rel.replace("\\", "/")
        if not md.is_file():
            continue
        try:
            lines = md.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            low = line.lower()
            if not any(k in low for k in keywords):
                continue
            for found in _extract_audit_engine_semvers(line):
                if found == canonical:
                    continue
                key = (rel, found)
                if key in reported:
                    continue
                reported.add(key)
                improve.append(
                    f"Section M - stale audit engine version {found} in {rel} "
                    f"(manifest.json is {canonical})"
                )
    return improve


def _pack_version_line_segment(line: str) -> str:
    """Use text before audit-engine mentions when both appear on one line."""
    low = line.lower()
    cut = len(line)
    for marker in ("audit engine", "manifest.json"):
        idx = low.find(marker)
        if idx >= 0:
            cut = min(cut, idx)
    return line[:cut]


def _extract_pack_release_semvers(line: str) -> list[str]:
    segment = _pack_version_line_segment(line)
    low = segment.lower()
    if not any(k in low for k in ("pack version", "starter pack release", "root `version`")):
        return []
    found: list[str] = []
    for pat in PACK_RELEASE_VERSION_PATTERNS:
        for m in pat.finditer(segment):
            found.append(m.group(1))
    return found


def check_pack_version_docs_improve(app_root: Path, cfg: dict) -> list[str]:
    """Improve when maintainer docs cite a stale pack release vs root VERSION."""
    improve: list[str] = []
    pvd = (cfg.get("codeChecks") or {}).get("packVersionDocs") or {}
    if not pvd.get("enabled", False):
        return improve
    canonical = read_canonical_version(app_root, cfg)
    if not canonical:
        return improve
    repo_root = resolve_repo_root(app_root)
    reported: set[tuple[str, str]] = set()
    for rel in pvd.get("scanFiles") or []:
        md = repo_root / rel.replace("\\", "/")
        if not md.is_file():
            continue
        try:
            lines = md.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            for found in _extract_pack_release_semvers(line):
                if found == canonical:
                    continue
                key = (rel, found)
                if key in reported:
                    continue
                reported.add(key)
                improve.append(
                    f"Section M - stale pack version {found} in {rel} "
                    f"(root VERSION is {canonical})"
                )
    return improve


def _collect_app_version_doc_paths(app_root: Path, repo_root: Path, avd: dict) -> list[Path]:
    exclude = set(
        avd.get("excludeFiles") or ["AUDIT.md", "ROADMAP.md", "KNOWN_LIMITATIONS.md"]
    )
    seen: set[Path] = set()
    out: list[Path] = []

    def add(path: Path) -> None:
        if not path.is_file() or path.name in exclude:
            return
        rp = path.resolve()
        if rp in seen:
            return
        seen.add(rp)
        out.append(path)

    for rel in avd.get("scanFiles") or []:
        norm = rel.replace("\\", "/")
        add(repo_root / norm)
        if app_root != repo_root:
            add(app_root / norm)
    for pattern in avd.get("scanGlobs") or []:
        pat = pattern.replace("\\", "/")
        for base in (app_root, repo_root):
            if base.is_dir():
                for p in base.glob(pat):
                    add(p)
    return out


def check_app_version_docs_improve(app_root: Path, cfg: dict) -> list[str]:
    """Improve when app docs cite vX.Y.Z that differs from versionSync canonical."""
    improve: list[str] = []
    avd = (cfg.get("codeChecks") or {}).get("appVersionDocs") or {}
    if not avd.get("enabled", False):
        return improve
    canonical = read_canonical_version(app_root, cfg)
    if not canonical:
        return improve
    repo_root = resolve_repo_root(app_root)
    reported: set[tuple[str, str]] = set()
    for path in _collect_app_version_doc_paths(app_root, repo_root, avd):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        try:
            rel = str(path.relative_to(repo_root))
        except ValueError:
            rel = str(path.relative_to(app_root))
        for m in VERSION_IN_DOC_RE.finditer(text):
            found = m.group(1)
            if found == canonical:
                continue
            key = (rel, found)
            if key in reported:
                continue
            reported.add(key)
            improve.append(
                f"Section M - stale app version v{found} in {rel} "
                f"(canonical v{canonical} from versionSync)"
            )
    return improve


def check_changelog_version_improve(app_root: Path, cfg: dict) -> list[str]:
    """Improve when CHANGELOG.md latest release does not match root VERSION."""
    improve: list[str] = []
    cvc = (cfg.get("codeChecks") or {}).get("changelogVersionDocs") or {}
    if not cvc.get("enabled", False):
        return improve
    canonical = read_canonical_version(app_root, cfg)
    if not canonical:
        return improve
    repo_root = resolve_repo_root(app_root)
    rel = (cvc.get("changelogFile") or "CHANGELOG.md").replace("\\", "/")
    chg = repo_root / rel
    if not chg.is_file():
        improve.append(f"Section M - missing {rel} for pack release history")
        return improve
    try:
        text = chg.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return improve
    m = re.search(r"^##\s+(\d+\.\d+\.\d+)", text, re.M)
    if not m:
        improve.append(f"Section M - {rel} has no ## X.Y.Z release entry")
    elif m.group(1) != canonical:
        improve.append(
            f"Section M - {rel} latest release {m.group(1)} != root VERSION {canonical}"
        )
    return improve
