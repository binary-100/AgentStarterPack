#!/usr/bin/env python3
"""Host-correct spelling for the pack's entry points - the Python twin of Get-PackEntryPoint.

Deliberately a second copy of the registry in pack-paths.ps1 rather than a shared data file. These
names appear *inside remediation text*, including text that prints when something is already broken,
so resolving one must not depend on finding and parsing a file: a missing or malformed JSON would
take out the very message that was supposed to explain the failure. verify-audit-behavior.ps1
renders every registered name in both layers and fails on any disagreement - the same treatment
resolve_repo_root gets in step 23, and the reason that check exists.

Kept out of audit_common.py on purpose: agent_context_freshness.py prints these hints and is not an
audit check module, so it must not start importing the audit engine to spell a filename.
"""

from __future__ import annotations

import os

# Must stay byte-for-byte equivalent to $script:PackEntryPoints in pack-paths.ps1. Names are
# asymmetric where the pack ships them that way - `install` is Install-AgentStarterPack.cmd and
# install.sh - so this maps per host instead of appending an extension to a shared base.
PACK_ENTRY_POINTS = {
    "run_audit": {"win": "run_audit.cmd", "posix": "run_audit.sh"},
    "run_audit_tests": {"win": "run_audit_tests.bat", "posix": "run_audit_tests.sh"},
    "Bootstrap-Project": {"win": "Bootstrap-Project.cmd", "posix": "Bootstrap-Project.sh"},
    "Check-Requirements": {"win": "Check-Requirements.cmd", "posix": "Check-Requirements.sh"},
    "Refresh-AgentContext": {
        "win": "Refresh-AgentContext.cmd",
        "posix": "Refresh-AgentContext.sh",
    },
    "Update-AgentStack": {"win": "Update-AgentStack.cmd", "posix": "Update-AgentStack.sh"},
    "Register-Tool-Adapters": {
        "win": "Register-Tool-Adapters.cmd",
        "posix": "Register-Tool-Adapters.sh",
    },
    "Sync-DocVersions": {"win": "Sync-DocVersions.cmd", "posix": "Sync-DocVersions.sh"},
    "install": {"win": "Install-AgentStarterPack.cmd", "posix": "install.sh"},
    # WQ-451: documented entry points that had no POSIX twin, so a message naming one was
    # unrunnable off Windows and neither registry could spell them.
    "Verify-AgentSetup": {"win": "Verify-AgentSetup.cmd", "posix": "Verify-AgentSetup.sh"},
    "Update-AgentRules": {"win": "Update-AgentRules.cmd", "posix": "Update-AgentRules.sh"},
    "Bootstrap-Portable-Project": {
        "win": "Bootstrap-Portable-Project.cmd",
        "posix": "Bootstrap-Portable-Project.sh",
    },
    "scripts/write_semantic_audit_template": {
        "win": "scripts/write_semantic_audit_template.cmd",
        "posix": "scripts/write_semantic_audit_template.sh",
    },
    "scripts/verify_semantic_audit": {
        "win": "scripts/verify_semantic_audit.cmd",
        "posix": "scripts/verify_semantic_audit.sh",
    },
    "scripts/finalize_audit": {
        "win": "scripts/finalize_audit.cmd",
        "posix": "scripts/finalize_audit.sh",
    },
    "scripts/sync_audit_system": {
        "win": "scripts/sync_audit_system.cmd",
        "posix": "scripts/sync_audit_system.sh",
    },
}

_NON_WINDOWS_TEST_VALUES = {"linux", "nonwindows", "non-windows", "darwin", "macos", "osx"}


def is_windows_host() -> bool:
    """Mirrors Test-PackIsWindows, including its AGENT_STARTER_PACK_TEST_OS override.

    Test-only override: the behavior suite exercises non-Windows remediation text from a Windows
    host. Never set AGENT_STARTER_PACK_TEST_OS in a production workflow.
    """
    test_os = (os.environ.get("AGENT_STARTER_PACK_TEST_OS") or "").strip().lower()
    if test_os in _NON_WINDOWS_TEST_VALUES:
        return False
    if test_os == "windows":
        return True
    return os.name == "nt"


def pack_entry_point(name: str, windows: bool | None = None) -> str:
    """Spell entry point `name` the way this host can run it.

    'run_audit.cmd' on Windows, './run_audit.sh' elsewhere, separators included, so the string is
    runnable as printed. Pass `windows=` to ask for a specific host's spelling.
    """
    entry = PACK_ENTRY_POINTS.get(name)
    if entry is None:
        raise KeyError(
            "unknown pack entry point {0!r}; register it in PACK_ENTRY_POINTS "
            "(pack_entry_points.py) and pack-paths.ps1, and ship both twins - an entry point with "
            "only one is an instruction that cannot be followed on the other host. Known: {1}".format(
                name, ", ".join(sorted(PACK_ENTRY_POINTS))
            )
        )
    if windows is None:
        windows = is_windows_host()
    if windows:
        return entry["win"].replace("/", "\\")
    # './' so the line is runnable as printed; a bare run_audit.sh is not on a default PATH.
    return "./" + entry["posix"]


def _main(argv: list[str]) -> int:
    """Exists so verify-audit-behavior.ps1 step 65 can compare this layer against pack-paths.ps1.

    --render prints name<TAB>windows<TAB>posix for every entry point, both spellings regardless of
    the running host, so the comparison does not depend on where the suite runs.
    """
    mode = argv[1] if len(argv) > 1 else "--render"
    if mode == "--render":
        for name in PACK_ENTRY_POINTS:
            win = pack_entry_point(name, windows=True)
            posix = pack_entry_point(name, windows=False)
            print(f"{name}\t{win}\t{posix}")
        return 0
    if mode == "--check-unknown":
        try:
            pack_entry_point("not-an-entry-point")
        except KeyError:
            print("refused")
            return 0
        print("accepted an unregistered entry point")
        return 1
    print(f"unknown mode {mode!r} (expected --render or --check-unknown)")
    return 2


if __name__ == "__main__":
    import sys

    raise SystemExit(_main(sys.argv))
