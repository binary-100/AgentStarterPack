#!/usr/bin/env python3
"""Build pipeline: sync documentation version cites to canonical VERSION.

Reads docs/VERSION_SYNC.json (not audit config). Used by apply_version.py,
run_tests.bat, build_ci.bat, and sync_doc_versions.py - not by audit step 1.

Legacy: falls back to docs/AUDIT.config.json versionSync / codeChecks if VERSION_SYNC.json missing.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

VERSION_IN_DOC_RE = re.compile(r"\bv(\d+\.\d+\.\d+)\b")

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


def resolve_repo_root(project_root: Path) -> Path:
    """Repo root for doc scanning. Must match run_audit.ps1.template and audit_code_checks.py.

    This module *writes*: _collect_doc_paths resolves scanFiles and scanGlobs against the returned
    root, so promoting the parent - as the old rule did whenever the parent held a README.md - made
    `apply_version.py sync` in a flat project rewrite version cites in files outside that project.
    Any project living beside a README.md was affected, which is the ordinary case. Kept standalone
    rather than imported: this is the build pipeline and must not depend on the audit engine.
    """
    project_root = project_root.resolve()
    # .git is a file in worktrees and submodules.
    if (project_root / ".git").exists():
        return project_root
    parent = project_root.parent
    if (
        project_root.name.lower() == "app"
        and (project_root / "docs" / "AUDIT.md").is_file()
        and (parent / ".git").exists()
    ):
        return parent.resolve()
    return project_root


def load_version_sync_config(project_root: Path) -> dict:
    project_root = project_root.resolve()
    vs_path = project_root / "docs" / "VERSION_SYNC.json"
    if vs_path.is_file():
        try:
            return json.loads(vs_path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError):
            pass
    audit_cfg_path = project_root / "docs" / "AUDIT.config.json"
    if audit_cfg_path.is_file():
        try:
            audit_cfg = json.loads(audit_cfg_path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError):
            audit_cfg = {}
        legacy: dict = {
            "canonical": audit_cfg.get("versionSync") or {},
            "docSync": (audit_cfg.get("versionSync") or {}).get("docSync")
            or (audit_cfg.get("codeChecks") or {}).get("appVersionDocs")
            or {},
        }
        mds = audit_cfg.get("maintainerDocSync")
        if mds:
            legacy["maintainerDocSync"] = mds
        cc = audit_cfg.get("codeChecks") or {}
        if cc.get("docVersionSync") or cc.get("auditVersionDocs") or cc.get("packVersionDocs"):
            legacy["maintainerDocSync"] = legacy.get("maintainerDocSync") or {
                "enabled": True,
                "packVersionScanFiles": (cc.get("packVersionDocs") or {}).get("scanFiles") or [],
                "auditVersionScanFiles": (cc.get("auditVersionDocs") or {}).get("scanFiles") or [],
                "auditManifestPath": (cc.get("auditVersionDocs") or {}).get(
                    "manifestPath", "pack/audit/manifest.json"
                ),
                "auditContextKeywords": (cc.get("auditVersionDocs") or {}).get(
                    "contextKeywords", ["manifest.json", "audit engine", "starter pack"]
                ),
                "extraReplacements": (cc.get("docVersionSync") or {}).get("extraReplacements") or [],
            }
        return legacy
    return {}


def read_canonical_version(project_root: Path, vs_cfg: dict | None = None) -> str | None:
    vs_cfg = vs_cfg if vs_cfg is not None else load_version_sync_config(project_root)
    canonical = vs_cfg.get("canonical") or {}
    txt_rel = (canonical.get("txtFile") or "VERSION.txt").replace("\\", "/")
    txt_path = project_root / txt_rel
    if not txt_path.is_file():
        return None
    text = txt_path.read_text(encoding="utf-8", errors="replace")
    pat = re.compile(canonical.get("txtPattern") or r"^Version:\s*(\S+)", re.M)
    m = pat.search(text)
    if m:
        return m.group(1).strip()
    plain = re.compile(r"^(\d+\.\d+\.\d+)\s*$", re.M)
    m2 = plain.search(text)
    return m2.group(1) if m2 else None


def read_audit_manifest_version(repo_root: Path, manifest_rel: str) -> str | None:
    manifest_path = repo_root / manifest_rel.replace("\\", "/")
    if not manifest_path.is_file():
        return None
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError):
        return None
    ver = data.get("version")
    return str(ver).strip() if ver else None


def _pack_version_line_segment(line: str) -> str:
    low = line.lower()
    cut = len(line)
    for marker in ("audit engine", "manifest.json"):
        idx = low.find(marker)
        if idx >= 0:
            cut = min(cut, idx)
    return line[:cut]


def _extract_audit_engine_semvers(line: str) -> list[str]:
    found: list[str] = []
    for pat in AUDIT_ENGINE_VERSION_PATTERNS:
        for m in pat.finditer(line):
            found.append(m.group(1))
    return found


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


def _sync_audit_versions_in_line(line: str, canonical: str, keywords: list[str]) -> str:
    low = line.lower()
    if not any(k in low for k in keywords):
        return line
    out = line
    for found in _extract_audit_engine_semvers(line):
        if found != canonical:
            out = out.replace(found, canonical, 1)
    return out


def _sync_pack_versions_in_line(line: str, canonical: str) -> str:
    out = line
    for found in _extract_pack_release_semvers(line):
        if found != canonical:
            out = out.replace(found, canonical, 1)
    return out


def _sync_app_versions_in_line(line: str, canonical: str) -> str:
    out = line
    for m in VERSION_IN_DOC_RE.finditer(line):
        found = m.group(1)
        if found != canonical:
            out = out.replace(f"v{found}", f"v{canonical}", 1)
    low = line.lower()
    if any(k in low for k in ("version", "currently", "release")):
        for m in re.finditer(r"\*\*(\d+\.\d+\.\d+)\*\*", out):
            found = m.group(1)
            if found != canonical:
                out = out.replace(f"**{found}**", f"**{canonical}**", 1)
    return out


def _collect_doc_paths(project_root: Path, repo_root: Path, doc_sync: dict) -> list[Path]:
    exclude = set(doc_sync.get("excludeFiles") or ["AUDIT.md", "ROADMAP.md", "KNOWN_LIMITATIONS.md"])
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

    for rel in doc_sync.get("scanFiles") or []:
        norm = rel.replace("\\", "/")
        add(repo_root / norm)
        if project_root != repo_root:
            add(project_root / norm)
    for pattern in doc_sync.get("scanGlobs") or []:
        pat = pattern.replace("\\", "/")
        for base in (project_root, repo_root):
            if base.is_dir():
                for p in base.glob(pat):
                    add(p)
    return out


def load_historical_regions(vs_cfg: dict | None) -> dict:
    """Files that carry a historical region, mapped to the heading where it starts.

    A work queue mixes two kinds of version cite in one file: the header says which engine is
    current, and every Done-log row says which engine shipped that item. The first must move on a
    bump; the second is a claim about the past and must never move. Nothing separated them, so the
    bump procedure was "split the file at the Done-log heading and replace only above it, by hand" -
    and four historical cites were rewritten anyway, twice in a single session (WQ-437).

    Declaring the boundary here makes it the tool's behaviour instead of a habit.
    """
    regions: dict[str, str] = {}
    for entry in (vs_cfg or {}).get("historicalRegions") or []:
        rel = (entry.get("file") or "").replace("\\", "/").strip()
        heading = (entry.get("fromHeading") or "").strip()
        if rel and heading:
            regions[rel] = heading
    return regions


def split_at_historical_heading(text: str, heading: str) -> tuple:
    """Split into (mutable head, frozen tail) at a markdown heading.

    Only lines that are themselves headings are considered, so prose quoting the heading - "the Done
    log is the one file where every version is a historical claim" - cannot move the boundary. An
    unanchored search for the same string is a bug this codebase has already paid for once, in the
    section parser these documents share.

    When the heading is absent the whole text stays mutable and the caller is told: a boundary that
    silently stopped existing is worse than never having had one.
    """
    want = heading.lstrip("#").strip().casefold()
    offset = 0
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if stripped.startswith("#") and stripped.lstrip("#").strip().casefold() == want:
            return text[:offset], text[offset:]
        offset += len(line)
    return text, ""


def _apply_extra_replacements(
    text: str, pack_ver: str | None, audit_ver: str | None, rules: list
) -> str:
    out = text
    for rule in rules:
        pattern = rule.get("pattern") or ""
        if not pattern:
            continue
        kind = (rule.get("versionKind") or "pack").lower()
        ver = audit_ver if kind == "audit" else pack_ver
        if not ver:
            continue
        repl = (rule.get("replace") or "").replace("{packVersion}", ver).replace(
            "{auditVersion}", ver
        )
        out = re.sub(pattern, repl, out)
    return out


def sync_documentation_versions(project_root: Path, *, dry_run: bool = False) -> dict:
    """Sync doc version cites. Build/compile pipeline entry point."""
    project_root = project_root.resolve()
    repo_root = resolve_repo_root(project_root)
    vs_cfg = load_version_sync_config(project_root)
    updated: list[str] = []
    stale: list[str] = []

    regions = load_historical_regions(vs_cfg)
    missing_regions: list[str] = []

    def split_frozen(rel: str, text: str) -> tuple:
        """Head to sync, tail to leave alone. Records a declared-but-absent heading."""
        heading = regions.get(rel.replace("\\", "/"))
        if not heading:
            return text, ""
        head, tail = split_at_historical_heading(text, heading)
        if not tail:
            missing_regions.append("{} (no heading '{}')".format(rel, heading))
        return head, tail

    app_ver = read_canonical_version(project_root, vs_cfg)
    doc_sync = vs_cfg.get("docSync") or {}
    has_doc_targets = bool(doc_sync.get("scanFiles") or doc_sync.get("scanGlobs"))
    if doc_sync.get("enabled", True) and app_ver and has_doc_targets:
        for path in _collect_doc_paths(project_root, repo_root, doc_sync):
            try:
                rel = str(path.relative_to(repo_root))
            except ValueError:
                rel = str(path.relative_to(project_root))
            original = path.read_text(encoding="utf-8-sig")
            mutable, frozen = split_frozen(rel, original)
            lines = mutable.splitlines(keepends=True)
            new_parts = []
            for line in lines:
                body = line.rstrip("\r\n")
                suffix = line[len(body) :]
                new_parts.append(_sync_app_versions_in_line(body, app_ver) + suffix)
            new_text = "".join(new_parts) + frozen
            if new_text != original:
                if dry_run:
                    stale.append(rel)
                else:
                    path.write_text(new_text, encoding="utf-8")
                    updated.append(rel)

    mds = vs_cfg.get("maintainerDocSync") or {}
    if mds.get("enabled", bool(mds.get("packVersionScanFiles") or mds.get("auditVersionScanFiles"))):
        pack_ver = app_ver
        manifest_rel = (mds.get("auditManifestPath") or "pack/audit/manifest.json").replace("\\", "/")
        audit_ver = read_audit_manifest_version(repo_root, manifest_rel)
        keywords = [
            k.lower()
            for k in (mds.get("auditContextKeywords") or ["manifest.json", "audit engine", "starter pack"])
        ]
        files: dict[str, str] = {}
        for rel in mds.get("auditVersionScanFiles") or []:
            files[rel.replace("\\", "/")] = "audit"
        for rel in mds.get("packVersionScanFiles") or []:
            key = rel.replace("\\", "/")
            files[key] = "both" if key in files else "pack"

        for rel, mode in sorted(files.items()):
            path = repo_root / rel
            if not path.is_file():
                continue
            original = path.read_text(encoding="utf-8-sig")
            mutable, frozen = split_frozen(rel, original)
            lines = mutable.splitlines(keepends=True)
            new_parts = []
            for line in lines:
                body = line.rstrip("\r\n")
                suffix = line[len(body) :]
                new_body = body
                if mode in ("audit", "both") and audit_ver:
                    new_body = _sync_audit_versions_in_line(new_body, audit_ver, keywords)
                if mode in ("pack", "both") and pack_ver:
                    new_body = _sync_pack_versions_in_line(new_body, pack_ver)
                new_parts.append(new_body + suffix)
            new_text = "".join(new_parts) + frozen
            if new_text != original:
                if dry_run:
                    stale.append(rel)
                else:
                    path.write_text(new_text, encoding="utf-8")
                    updated.append(rel)

        for rule in mds.get("extraReplacements") or []:
            rel = (rule.get("file") or "").replace("\\", "/")
            if not rel:
                continue
            path = repo_root / rel
            if not path.is_file():
                continue
            original = path.read_text(encoding="utf-8-sig")
            # extraReplacements are whole-file regex substitutions, which is the shape most likely
            # to reach into the past: the header-row rules below are anchored, but a rule written
            # with a looser pattern would rewrite every match in the Done log too.
            mutable, frozen = split_frozen(rel, original)
            new_text = _apply_extra_replacements(mutable, pack_ver, audit_ver, [rule]) + frozen
            if new_text != original:
                if dry_run:
                    stale.append(rel)
                else:
                    path.write_text(new_text, encoding="utf-8")
                    if rel not in updated:
                        updated.append(rel)

    stale = list(dict.fromkeys(stale))
    updated = list(dict.fromkeys(updated))
    missing_regions = list(dict.fromkeys(missing_regions))
    # A declared region whose heading cannot be found is a failure, not a note: the file is being
    # rewritten end to end while the config says part of it is protected.
    return {
        "updated": updated,
        "stale": stale,
        "frozenRegions": sorted(regions),
        "missingRegions": missing_regions,
        "ok": len(stale) == 0 and not missing_regions,
    }


def run_cli(project_root: Path, argv: list[str]) -> int:
    dry_run = "--verify" in argv or "--verify-only" in argv
    result = sync_documentation_versions(project_root, dry_run=dry_run)
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    flags = [a for a in sys.argv[2:] if a.startswith("-")]
    raise SystemExit(run_cli(root, flags))
