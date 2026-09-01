#!/usr/bin/env python3
"""Sections F, G and L: how this pack is installed and wired on the machine running the audit.

Split out of `audit_code_checks.py` when it passed the 2500-line threshold its own Section D check
enforces. What these checks have in common is that they look *outside* the repo - at the installed
copy in the profile, at `mcp.json`, at the reference templates the pack ships - so they are the
checks most likely to report on machine state rather than on the code.

`AGENT_STARTER_PACK_INSTALL_ROOT` is honoured here for that reason: PowerShell has read it since
2.22.4, and while Python did not, these checks read the real profile behind a redirect and made
their own tests depend on whatever the developer happened to have installed.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from audit_common import read_audit_manifest_version, resolve_repo_root


def check_pack_reference_config_improve(app_root: Path, cfg: dict) -> list[str]:
    """Improve when pack self-audit config diverges from the pack reference template."""
    improve: list[str] = []
    prc = (cfg.get("codeChecks") or {}).get("packReferenceConfig") or {}
    if not prc.get("enabled", False):
        return improve
    repo_root = resolve_repo_root(app_root)
    source = repo_root / (prc.get("source") or "docs/AUDIT.config.json").replace("\\", "/")
    reference = repo_root / (
        prc.get("reference") or "pack/templates/docs/AUDIT.config.pack.reference.json"
    ).replace("\\", "/")
    if not source.is_file() or not reference.is_file():
        return improve
    try:
        src = json.loads(source.read_text(encoding="utf-8-sig"))
        ref = json.loads(reference.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError):
        return improve
    if src != ref:
        improve.append(
            "Section L - docs/AUDIT.config.json differs from "
            "pack/templates/docs/AUDIT.config.pack.reference.json - sync reference copy"
        )
    # The checklist has a reference copy too, and nothing compared it: it had drifted 16 lines from
    # docs/AUDIT.md, so the template shipped to new pack-style projects described a different audit.
    src_md = repo_root / (prc.get("sourceMd") or "docs/AUDIT.md").replace("\\", "/")
    ref_md = repo_root / (
        prc.get("referenceMd") or "pack/templates/docs/AUDIT.pack.reference.md"
    ).replace("\\", "/")
    if src_md.is_file() and ref_md.is_file():
        left = src_md.read_text(encoding="utf-8-sig").replace("\r\n", "\n").strip()
        right = ref_md.read_text(encoding="utf-8-sig").replace("\r\n", "\n").strip()
        if left != right:
            improve.append(
                f"Section L - {src_md.name} differs from {ref_md.name} - sync reference copy"
            )
    return improve


def _installed_pack_root() -> Path | None:
    # Same precedence as Get-InstalledAgentStarterPack in pack-paths.ps1 and
    # resolve_pack_root in agent_context_freshness.py: the install-root override first, so a
    # test or a relocated profile moves this check with it instead of reading the real
    # %USERPROFILE% behind its back.
    override = os.environ.get("AGENT_STARTER_PACK_INSTALL_ROOT", "").strip()
    if override:
        root = Path(override).expanduser()
        return root.resolve() if (root / "pack" / "audit" / "manifest.json").is_file() else None
    preferred = Path(os.environ.get("USERPROFILE", "")) / ".cursor" / "AgentStarterPack"
    if (preferred / "pack" / "audit" / "manifest.json").is_file():
        return preferred.resolve()
    legacy = Path(os.environ.get("USERPROFILE", "")) / ".cursor" / "agent-starter-pack"
    if (legacy / "pack" / "audit" / "manifest.json").is_file():
        return legacy.resolve()
    return None


def _user_cursor_root() -> Path:
    """Profile folder holding rules\\, skills\\ and mcp.json - the parent of the install root.

    Mirrors Get-AgentStarterPackUserRoot: an install-root override moves the whole set, so a
    check that reads mcp.json must follow it rather than reading the real profile behind the
    redirect. Computed from the override path itself, since an override pointed at an empty
    directory still names where the install *would* be.
    """
    override = os.environ.get("AGENT_STARTER_PACK_INSTALL_ROOT", "").strip()
    if override:
        return Path(override).expanduser().resolve().parent
    return Path(os.environ.get("USERPROFILE", "")) / ".cursor"


def check_installed_vs_source_improve(app_root: Path, cfg: dict) -> list[str]:
    """Improve when the source pack folder differs from ~/.cursor/AgentStarterPack."""
    improve: list[str] = []
    ivs = (cfg.get("codeChecks") or {}).get("installedVsSource") or {}
    if not ivs.get("enabled", False):
        return improve
    repo_root = resolve_repo_root(app_root)
    if not (repo_root / "install.ps1").is_file():
        return improve
    installed = _installed_pack_root()
    if not installed or installed == repo_root.resolve():
        return improve
    manifest_rel = (ivs.get("manifestPath") or "pack/audit/manifest.json").replace("\\", "/")
    local_ver = read_audit_manifest_version(app_root, manifest_rel)
    installed_ver = read_audit_manifest_version(installed, manifest_rel)
    if local_ver and installed_ver and local_ver != installed_ver:
        improve.append(
            f"Section F - installed audit engine {installed_ver} != workspace {local_ver} "
            "- run install.ps1 -Scope User"
        )
    for rel in ivs.get("compareFiles") or []:
        local_f = repo_root / rel.replace("\\", "/")
        inst_f = installed / rel.replace("\\", "/")
        if not local_f.is_file() or not inst_f.is_file():
            continue
        if hashlib.sha256(local_f.read_bytes()).digest() != hashlib.sha256(inst_f.read_bytes()).digest():
            improve.append(
                f"Section F - installed copy differs from workspace for {rel} "
                "- run install.ps1 -Scope User"
            )
            break
    return improve


def check_mcp_wiring_improve(app_root: Path, cfg: dict) -> list[str]:
    """Improve when MCP hygiene server wiring or deps look wrong (pack section G)."""
    improve: list[str] = []
    mw = (cfg.get("codeChecks") or {}).get("mcpWiring") or {}
    if not mw.get("enabled", False):
        return improve
    repo_root = resolve_repo_root(app_root)
    req_rel = (mw.get("requirementsFile") or "mcp/requirements.txt").replace("\\", "/")
    req_path = repo_root / req_rel
    pin = (mw.get("pinPattern") or r"mcp\s*>=\s*[\d.]+\s*,\s*<\s*2")
    if not req_path.is_file():
        improve.append(f"Section G - missing {req_rel}")
    else:
        try:
            req_text = req_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            req_text = ""
        if req_text and not re.search(pin, req_text, re.I):
            improve.append(
                "Section G - mcp/requirements.txt should pin mcp<2 for FastMCP compatibility"
            )
    mcp_json = _user_cursor_root() / "mcp.json"
    server_name = mw.get("serverName") or "agent-hygiene"
    if not mcp_json.is_file():
        improve.append("Section G - mcp.json not found - run install.ps1 -RegisterMcp")
    else:
        try:
            data = json.loads(mcp_json.read_text(encoding="utf-8-sig"))
            entry = (data.get("mcpServers") or {}).get(server_name)
            if not entry:
                improve.append(
                    f"Section G - mcp.json missing {server_name} server - run install.ps1 -RegisterMcp"
                )
            else:
                server_py = next(
                    (a for a in (entry.get("args") or []) if "agent_hygiene_server.py" in str(a)),
                    None,
                )
                if server_py and not Path(str(server_py)).is_file():
                    improve.append(
                        "Section G - mcp.json agent-hygiene path stale - run install.ps1 -RegisterMcp"
                    )
        except (OSError, json.JSONDecodeError):
            improve.append("Section G - mcp.json parse error - run install.ps1 -RegisterMcp")
    if mw.get("requireImport", True):
        try:
            r = subprocess.run(
                [sys.executable, "-c", "import mcp"],
                capture_output=True,
                text=True,
                timeout=20,
            )
            if r.returncode != 0:
                improve.append(
                    "Section G - Python package mcp not importable - run install.ps1 -InstallMcpDeps"
                )
        except (OSError, subprocess.TimeoutExpired):
            improve.append("Section G - could not verify Python mcp import")
    return improve
