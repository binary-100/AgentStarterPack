"""Pack self-audit tests — audit engine, install launcher, MCP server."""
from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CODE = ROOT / "pack" / "scripts" / "audit_code_checks.py"
INSTALL_LAUNCHER = ROOT / "install_launcher.py"
MCP_SERVER = ROOT / "mcp" / "agent_hygiene_server.py"


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
        spec.loader.exec_module(mod)
    except ModuleNotFoundError as exc:
        if "mcp" in str(exc).lower():
            # Doctor installs mcp<2 for FastMCP; skip only when deps missing locally.
            return
        raise
    assert getattr(mod, "mcp", None) is not None
