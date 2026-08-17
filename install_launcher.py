#!/usr/bin/env python3
"""GUI-less launcher for Install-AgentStarterPack (PyInstaller onefile entry)."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def _pack_root() -> Path:
    if getattr(sys, "frozen", False):
        # PyInstaller extracts add-data next to _MEIPASS
        candidate = Path(sys._MEIPASS) / "starter-pack"
        if candidate.is_dir():
            return candidate
    return Path(__file__).resolve().parent


def main() -> int:
    root = _pack_root()
    script = root / "install.ps1"
    if not script.is_file():
        print(f"install.ps1 not found under {root}", file=sys.stderr)
        return 1
    cmd = [
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script),
        "-Scope",
        "User",
        "-RegisterMcp",
        "-InstallMcpDeps",
        "-NoPause",
    ]
    print("Installing Agent Starter Pack...")
    r = subprocess.run(cmd, cwd=str(root))
    if r.returncode == 0:
        print("\nDone. Restart Cursor. MCP: agent-hygiene")
    return r.returncode


if __name__ == "__main__":
    raise SystemExit(main())
