#!/usr/bin/env python3
"""CLI: sync doc version cites (build pipeline)."""
from __future__ import annotations

import sys
from pathlib import Path

from doc_version_sync import run_cli

if __name__ == "__main__":
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    flags = [a for a in sys.argv[2:] if a.startswith("-")]
    raise SystemExit(run_cli(root, flags))
