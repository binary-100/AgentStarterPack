#!/usr/bin/env python3
"""Pack agent-context freshness - shared logic for MCP and tests.

Reads docs/AGENT_CONTEXT.json and the installed pack manifest; does not duplicate
refresh-agent-context.ps1 write path.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

TRIGGER_PHRASES = (
    "refresh pack context",
    "sync agent context",
    "context refresh",
    "pack update",
)


def resolve_pack_root() -> Path | None:
    env = os.environ.get("AGENT_STARTER_PACK_ROOT", "").strip()
    if env:
        root = Path(env)
        if (root / "pack" / "audit" / "manifest.json").is_file():
            return root.resolve()
    profile = Path(os.environ.get("USERPROFILE", Path.home())) / ".cursor" / "AgentStarterPack"
    if (profile / "pack" / "audit" / "manifest.json").is_file():
        return profile.resolve()
    return None


def resolve_project_root(project_root: str | None) -> Path:
    if project_root and project_root.strip():
        return Path(project_root).expanduser().resolve()
    return Path.cwd().resolve()


def load_json(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (json.JSONDecodeError, OSError):
        return None


def canonical_project_root(project_root: Path) -> Path:
    boot = load_json(project_root / ".agent-bootstrap.json")
    if boot and boot.get("projectRoot"):
        return Path(str(boot["projectRoot"])).resolve()
    ctx = load_json(project_root / "docs" / "AGENT_CONTEXT.json")
    if ctx and ctx.get("canonicalProjectRoot"):
        return Path(str(ctx["canonicalProjectRoot"])).resolve()
    return project_root


def context_paths(project_root: Path) -> tuple[Path, Path, Path, Path]:
    canonical = canonical_project_root(project_root)
    docs = canonical / "docs"
    return (
        docs / "AGENT_CONTEXT.json",
        docs / "AGENT_REFRESH.md",
        docs / "AGENT_PASTE.txt",
        docs / "AGENT_SESSION_START.md",
    )


def installed_engine_version(pack_root: Path | None) -> str | None:
    if not pack_root:
        return None
    manifest = load_json(pack_root / "pack" / "audit" / "manifest.json")
    if manifest:
        ver = manifest.get("version")
        return str(ver) if ver else None
    return None


def check_freshness(project_root: str | None = None) -> dict[str, Any]:
    proj = resolve_project_root(project_root)
    pack_root = resolve_pack_root()
    ctx_path, refresh_path, paste_path, session_start_path = context_paths(proj)
    ctx = load_json(ctx_path)
    current_engine = installed_engine_version(pack_root)
    canonical = canonical_project_root(proj)

    reasons: list[str] = []
    layers: dict[str, str] = {}

    if not ctx:
        reasons.append("missing AGENT_CONTEXT.json - run Refresh-AgentContext.cmd")
        stale = True
    else:
        stamped = ctx.get("auditEngineVersion")
        if not stamped:
            reasons.append("bootstrap stub - never refreshed")
            stale = True
        elif current_engine and str(stamped) != str(current_engine):
            reasons.append(f"stamped {stamped}, installed engine {current_engine}")
            stale = True
        else:
            stale = False

        raw_layers = ctx.get("layers") or {}
        if isinstance(raw_layers, dict):
            layers = {str(k): str(v) for k, v in raw_layers.items()}
            if layers.get("installedPack") == "stale":
                reasons.append("installed profile pack differs from source")
                stale = True

    required_reads: list[str] = []
    if ctx and isinstance(ctx.get("requiredReads"), list):
        required_reads = [str(p) for p in ctx["requiredReads"]]
    elif refresh_path.is_file():
        required_reads = [str(canonical / "AGENTS.md"), str(refresh_path)]

    return {
        "stale": stale,
        "reasons": reasons,
        "projectRoot": str(proj),
        "canonicalProjectRoot": str(canonical),
        "workspaceMatchesCanonical": proj == canonical,
        "contextPath": str(ctx_path),
        "refreshBriefPath": str(refresh_path) if refresh_path.is_file() else None,
        "pastePath": str(paste_path) if paste_path.is_file() else None,
        "sessionStartPath": str(session_start_path),
        "installedEngineVersion": current_engine,
        "stampedEngineVersion": (ctx or {}).get("auditEngineVersion"),
        "packVersion": (ctx or {}).get("packVersion"),
        "schemaVersion": (ctx or {}).get("schemaVersion"),
        "layers": layers,
        "requiredReads": required_reads,
        "triggerPhrases": list(TRIGGER_PHRASES),
        "handshake": (ctx or {}).get("handshake") or {"required": True, "fields": ["packVersion", "auditEngineVersion"]},
        "installedPackRoot": str(pack_root) if pack_root else None,
    }


def _handshake_line(handshake: dict[str, Any] | None) -> str:
    hs = handshake or {"required": True, "fields": ["packVersion", "auditEngineVersion"]}
    if not hs.get("required"):
        return "No handshake required."
    fields = hs.get("fields") or ["packVersion", "auditEngineVersion"]
    labels = " and ".join(str(f) for f in fields)
    return f"Reply with the {labels} from the files you read."


def _build_opener_line(freshness: dict[str, Any]) -> str:
    pack = freshness.get("packVersion") or "unknown"
    engine = freshness.get("stampedEngineVersion") or freshness.get("installedEngineVersion") or "unknown"
    canonical = freshness.get("canonicalProjectRoot") or freshness.get("projectRoot") or ""
    session_path = freshness.get("sessionStartPath") or ""
    if freshness.get("stale"):
        reasons = "; ".join(freshness.get("reasons") or []) or "context stale"
        line = (
            f"AGENT CONTEXT STALE ({reasons}). Before substantial work read {session_path} "
            f"and docs/AGENT_REFRESH.md under {canonical}. "
            f"Handshake: pack {pack}, audit engine {engine}."
        )
    else:
        line = (
            f"Agent context OK (pack {pack}, audit engine {engine}). "
            "No mandatory re-read this session."
        )
    return " ".join(line.split())


def build_session_start_markdown(freshness: dict[str, Any]) -> str:
    canonical = freshness.get("canonicalProjectRoot") or freshness.get("projectRoot") or ""
    stamped = freshness.get("stampedEngineVersion") or "(none)"
    installed = freshness.get("installedEngineVersion") or "(unknown)"
    pack = freshness.get("packVersion") or "(none)"
    refresh_path = freshness.get("refreshBriefPath")
    session_path = freshness.get("sessionStartPath") or ""
    handshake = _handshake_line(freshness.get("handshake"))
    reads = freshness.get("requiredReads") or []
    read_lines = "\n".join(f"- `{p}`" for p in reads) if reads else "- (none listed - run refresh)"
    reasons = freshness.get("reasons") or []
    reason_cell = "; ".join(reasons) if reasons else "(none)"
    workspace_ok = freshness.get("workspaceMatchesCanonical", True)

    if freshness.get("stale"):
        verdict = "**Context: STALE** - re-read before substantial work."
        remediation = (
            f"Run `Update-AgentStack.cmd \"{canonical}\"` or offer to run "
            f"`Refresh-AgentContext.cmd` for this project (agent runs it after approval)."
        )
        refresh_note = (
            f"\nFull brief: `{refresh_path}`\n" if refresh_path else "\n"
        )
    else:
        verdict = f"**Context: OK** (audit engine {stamped}). No mandatory re-read this session."
        remediation = "Optional: `docs/WORK_QUEUE.md` when prioritizing work."
        refresh_note = ""

    workspace_note = ""
    if not workspace_ok:
        workspace_note = (
            f"\n\n> **Workspace mismatch:** editor root `{freshness.get('projectRoot')}` "
            f"!= canonical `{canonical}`. Open the canonical folder or use absolute paths below.\n"
        )

    execute_verify_note = (
        "\n**Agent runs commands; user verifies outcomes** - you execute sync/tests/fixes; "
        "report exit codes so the user can pivot. Do not ask them to type commands you can run. "
        "See `AI_INSTRUCTIONS.md` and `docs/portable/GENERIC_RULES.md` section agent-defaults-always.\n"
    )

    return f"""# Agent session start

{verdict}

| Check | Value |
|-------|-------|
| Pack version | {pack} |
| Stamped engine | {stamped} |
| Installed engine | {installed} |
| Reason | {reason_cell} |

**Required reads (absolute paths):**
{read_lines}

**Handshake:** {handshake}
{execute_verify_note}
{refresh_note}
**Remediation:** {remediation}
{workspace_note}
Generated by `agent_context_freshness.py` - re-run refresh to update. Path: `{session_path}`
"""


def get_session_brief(project_root: str | None = None) -> dict[str, Any]:
    freshness = check_freshness(project_root)
    _, _, _, session_start_path = context_paths(resolve_project_root(project_root))
    freshness["sessionStartPath"] = str(session_start_path)
    opener = _build_opener_line(freshness)
    permission = "inject" if freshness.get("stale") else "none"
    return {
        "stale": freshness.get("stale"),
        "openerLine": opener,
        "markdownPath": str(session_start_path),
        "requiredReads": freshness.get("requiredReads") or [],
        "handshake": freshness.get("handshake"),
        "permission": permission,
        "freshness": freshness,
    }


def write_session_start(project_root: str | None = None) -> Path:
    proj = resolve_project_root(project_root)
    _, _, _, session_start_path = context_paths(proj)
    freshness = check_freshness(str(proj))
    freshness["sessionStartPath"] = str(session_start_path)
    body = build_session_start_markdown(freshness)
    session_start_path.parent.mkdir(parents=True, exist_ok=True)
    session_start_path.write_text(body, encoding="utf-8")
    return session_start_path


def get_refresh_brief(project_root: str | None = None) -> dict[str, Any]:
    proj = resolve_project_root(project_root)
    _, refresh_path, _, _ = context_paths(proj)
    freshness = check_freshness(str(proj))
    if refresh_path.is_file():
        body = refresh_path.read_text(encoding="utf-8-sig")
    else:
        body = (
            "No docs/AGENT_REFRESH.md yet. Run Refresh-AgentContext.cmd or Update-AgentStack.cmd "
            f"for: {freshness['canonicalProjectRoot']}"
        )
    return {
        "path": str(refresh_path),
        "exists": refresh_path.is_file(),
        "body": body,
        "freshness": freshness,
    }


def _self_test() -> int:
    import tempfile

    failures: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "proj"
        docs = root / "docs"
        docs.mkdir(parents=True)
        pack = Path(tmp) / "pack"
        (pack / "pack" / "audit").mkdir(parents=True)
        (pack / "pack" / "audit" / "manifest.json").write_text(
            '{"version": "2.0.0-test"}', encoding="utf-8"
        )
        os.environ["AGENT_STARTER_PACK_ROOT"] = str(pack)
        (root / "AGENTS.md").write_text("# app\n", encoding="utf-8")

        r = check_freshness(str(root))
        if not r["stale"]:
            failures.append("missing context should be stale")
        if r["workspaceMatchesCanonical"] is not True:
            failures.append("workspace should match canonical in flat project")

        (docs / "AGENT_CONTEXT.json").write_text(
            json.dumps(
                {
                    "schemaVersion": 2,
                    "auditEngineVersion": "1.0.0-old",
                    "canonicalProjectRoot": str(root),
                    "requiredReads": [str(root / "AGENTS.md")],
                    "layers": {"installedPack": "ok"},
                }
            ),
            encoding="utf-8",
        )
        r2 = check_freshness(str(root))
        if not r2["stale"]:
            failures.append("old stamp should be stale")
        if r2["stampedEngineVersion"] != "1.0.0-old":
            failures.append("stamped version mismatch")

        brief = get_refresh_brief(str(root))
        if brief["exists"]:
            failures.append("brief should not exist yet")
        (docs / "AGENT_REFRESH.md").write_text("# refresh\n", encoding="utf-8")
        brief2 = get_refresh_brief(str(root))
        if not brief2["exists"] or "# refresh" not in brief2["body"]:
            failures.append("brief read failed")

        session = get_session_brief(str(root))
        if not session.get("stale"):
            failures.append("old stamp session brief should be stale")
        if session.get("permission") != "inject":
            failures.append("stale session brief permission should be inject")
        if not session.get("openerLine"):
            failures.append("session brief missing openerLine")

        written = write_session_start(str(root))
        if not written.is_file():
            failures.append("write_session_start did not create file")
        text = written.read_text(encoding="utf-8")
        if "STALE" not in text:
            failures.append("session start markdown should show STALE")

        (docs / "AGENT_CONTEXT.json").write_text(
            json.dumps(
                {
                    "schemaVersion": 2,
                    "auditEngineVersion": "2.0.0-test",
                    "packVersion": "1.0.0-test",
                    "canonicalProjectRoot": str(root),
                    "requiredReads": [str(root / "AGENTS.md")],
                    "layers": {"installedPack": "ok"},
                }
            ),
            encoding="utf-8",
        )
        fresh_brief = get_session_brief(str(root))
        if fresh_brief.get("stale"):
            failures.append("matching stamp should be fresh")
        if fresh_brief.get("permission") != "none":
            failures.append("fresh session brief permission should be none")

    if failures:
        for f in failures:
            print(f"FAIL: {f}", file=sys.stderr)
        return 1
    print("agent_context_freshness self-test OK")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Agent context freshness checks")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--brief", action="store_true")
    parser.add_argument("--session-brief", action="store_true")
    parser.add_argument("--write-session-start", action="store_true")
    parser.add_argument("--project-root", default="")
    args = parser.parse_args()
    if args.self_test:
        return _self_test()
    root = args.project_root or None
    if args.write_session_start:
        path = write_session_start(root)
        print(str(path))
        return 0
    if args.session_brief:
        print(json.dumps(get_session_brief(root), indent=2))
        return 0
    if args.brief:
        print(json.dumps(get_refresh_brief(root), indent=2))
        return 0
    if args.check:
        print(json.dumps(check_freshness(root), indent=2))
        return 0
    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
