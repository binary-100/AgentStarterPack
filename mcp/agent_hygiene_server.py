#!/usr/bin/env python3
"""
MCP server: agent terminal hygiene (partial ideal fix).

Can: list/diagnose agent terminal logs, fix stale metadata, kill OS PIDs.
Cannot: dismiss Cursor Terminal UI tabs (no public Cursor API).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from mcp.server.fastmcp import FastMCP
except ImportError:
    print(
        "Missing package: pip install mcp",
        file=sys.stderr,
    )
    raise

mcp = FastMCP(
    "agent-hygiene",
    instructions=(
        "Terminal hygiene for Cursor agents: diagnose stale terminal logs, "
        "repair missing exit_code footers, kill stuck OS processes, "
        "scan/cleanup orphan py/python children after force-killed shells. "
        "Start with agent_hygiene_full_check. Does not control Cursor UI panels."
    ),
)


def _projects_root() -> Path:
    return Path(os.environ.get("USERPROFILE", Path.home())) / ".cursor" / "projects"


def _discover_terminal_dirs() -> list[Path]:
    root = _projects_root()
    if not root.is_dir():
        return []
    dirs: list[Path] = []
    for child in root.iterdir():
        t = child / "terminals"
        if t.is_dir():
            dirs.append(t)
    return sorted(dirs)


def _parse_header(content: str) -> dict[str, Any]:
    meta: dict[str, Any] = {}
    for line in content.splitlines()[:20]:
        if line.strip() == "---":
            break
        m = re.match(r"^(\w+):\s*(.+)$", line.strip())
        if m:
            key, val = m.group(1), m.group(2).strip().strip('"')
            if key == "pid":
                try:
                    meta["pid"] = int(val)
                except ValueError:
                    pass
            else:
                meta[key] = val
    meta["has_exit_code"] = bool(re.search(r"exit_code:\s*\d", content))
    meta["has_running_for_ms"] = "running_for_ms:" in content
    return meta


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if sys.platform == "win32":
        r = subprocess.run(
            ["tasklist", "/FI", f"PID eq {pid}"],
            capture_output=True,
            text=True,
            check=False,
        )
        return str(pid) in (r.stdout or "")
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _kill_pid(pid: int) -> tuple[bool, str]:
    if pid <= 0:
        return False, "invalid pid"
    if sys.platform == "win32":
        r = subprocess.run(
            ["taskkill", "/PID", str(pid), "/F"],
            capture_output=True,
            text=True,
            check=False,
        )
        ok = r.returncode == 0
        return ok, (r.stdout or r.stderr or "").strip()[:500]
    try:
        os.kill(pid, 9)
        return True, "sent SIGKILL"
    except OSError as exc:
        return False, str(exc)


def _repair_log(path: Path) -> dict[str, Any]:
    content = path.read_text(encoding="utf-8", errors="replace")
    meta = _parse_header(content)
    pid = int(meta.get("pid") or 0)
    if meta["has_exit_code"]:
        return {"file": str(path), "action": "skip", "reason": "already complete"}
    if meta.get("has_running_for_ms") and pid and _pid_alive(pid):
        return {"file": str(path), "action": "skip", "reason": f"process {pid} alive"}
    ended = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    content = re.sub(r"running_for_ms:\s*\d+\s*", f"ended_at: {ended}\n", content)
    code = 1 if re.search(r"(?i)error|failed", content) else 0
    footer = (
        f"\n---\nexit_code: {code}\nelapsed_ms: 0\n"
        f"ended_at: {ended}\nstale_metadata_repaired: true\n---\n"
    )
    path.write_text(content.rstrip() + footer, encoding="utf-8")
    return {"file": str(path), "action": "fixed", "exit_code": code}


@mcp.tool()
def list_terminal_sessions() -> str:
    """List Cursor agent terminal log files and basic status."""
    rows: list[dict[str, Any]] = []
    for tdir in _discover_terminal_dirs():
        for fp in sorted(tdir.glob("*.txt")):
            try:
                content = fp.read_text(encoding="utf-8", errors="replace")
            except OSError as exc:
                rows.append({"file": str(fp), "error": str(exc)})
                continue
            meta = _parse_header(content)
            pid = int(meta.get("pid") or 0)
            rows.append(
                {
                    "file": str(fp),
                    "pid": pid,
                    "pid_alive": _pid_alive(pid) if pid else False,
                    "complete": meta["has_exit_code"],
                    "stale": meta.get("has_running_for_ms") and not meta["has_exit_code"],
                    "command": meta.get("command", "")[:120],
                }
            )
    return json.dumps(rows, indent=2)


@mcp.tool()
def diagnose_terminal_sessions() -> str:
    """Summarize stale logs, alive PIDs, and recommended actions."""
    data = json.loads(list_terminal_sessions())
    stale = [r for r in data if r.get("stale") and not r.get("pid_alive")]
    alive = [r for r in data if r.get("pid_alive")]
    return json.dumps(
        {
            "total": len(data),
            "stale_repairable": len(stale),
            "processes_still_running": alive,
            "ui_note": (
                "Cursor Terminal UI tabs may still show spinners after repair; "
                "user may need Kill Terminal in the panel."
            ),
        },
        indent=2,
    )


@mcp.tool()
def fix_stale_terminal_logs() -> str:
    """Repair agent terminal logs missing exit_code (stale metadata)."""
    fixed: list[dict[str, Any]] = []
    for tdir in _discover_terminal_dirs():
        for fp in sorted(tdir.glob("*.txt")):
            try:
                content = fp.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            meta = _parse_header(content)
            if meta["has_exit_code"] or not meta.get("has_running_for_ms"):
                continue
            fixed.append(_repair_log(fp))
    return json.dumps({"fixed": fixed, "count": len(fixed)}, indent=2)


@mcp.tool()
def kill_terminal_process(pid: int) -> str:
    """Force-kill an OS process by PID (e.g. stuck build). Does not close Cursor UI tabs."""
    ok, msg = _kill_pid(pid)
    return json.dumps({"pid": pid, "ok": ok, "detail": msg})


_PROTECTED_CMD_MARKERS = (
    "agent_hygiene_server",
    "mcp.server.fastmcp",
)
_HUNG_CMD_MARKERS = (
    "test_gui_phase2",
    "offscreen_main_window",
    "run_tests.bat",
    "pytest",
)


def _running_pids() -> set[int]:
    if sys.platform != "win32":
        return set()
    r = subprocess.run(
        ["tasklist", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        check=False,
    )
    pids: set[int] = set()
    for line in (r.stdout or "").splitlines():
        parts = [p.strip('"') for p in line.split('","')]
        if not parts:
            continue
        try:
            pids.add(int(parts[1]))
        except (ValueError, IndexError):
            continue
    return pids


def _win32_process_rows() -> list[dict[str, Any]]:
    if sys.platform != "win32":
        return []
    ps = (
        "Get-CimInstance Win32_Process -Filter "
        "\"Name='python.exe' OR Name='py.exe'\" | "
        "Select-Object ProcessId,ParentProcessId,Name,CommandLine | "
        "ConvertTo-Json -Compress"
    )
    r = subprocess.run(
        ["powershell", "-NoProfile", "-Command", ps],
        capture_output=True,
        text=True,
        check=False,
    )
    if r.returncode != 0 or not (r.stdout or "").strip():
        return []
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError:
        return []
    if isinstance(data, dict):
        return [data]
    return [row for row in data if isinstance(row, dict)]


def _process_cpu_seconds(pid: int) -> float | None:
    if sys.platform != "win32":
        return None
    ps = f"(Get-Process -Id {int(pid)} -ErrorAction SilentlyContinue).CPU"
    r = subprocess.run(
        ["powershell", "-NoProfile", "-Command", ps],
        capture_output=True,
        text=True,
        check=False,
    )
    out = (r.stdout or "").strip()
    try:
        return float(out)
    except ValueError:
        return None


def _process_age_minutes(pid: int) -> float | None:
    if sys.platform != "win32":
        return None
    ps = (
        f"$p=Get-Process -Id {int(pid)} -ErrorAction SilentlyContinue; "
        "if ($p) { [math]::Round(((Get-Date) - $p.StartTime).TotalMinutes, 1) }"
    )
    r = subprocess.run(
        ["powershell", "-NoProfile", "-Command", ps],
        capture_output=True,
        text=True,
        check=False,
    )
    out = (r.stdout or "").strip()
    try:
        return float(out)
    except ValueError:
        return None


def _is_protected_command(command_line: str) -> bool:
    low = (command_line or "").lower()
    return any(m.lower() in low for m in _PROTECTED_CMD_MARKERS)


def _terminal_killed_pids() -> set[int]:
    """PIDs from terminal logs that ended via force-kill (4294967295) or stale repair."""
    killed: set[int] = set()
    for tdir in _discover_terminal_dirs():
        for fp in tdir.glob("*.txt"):
            try:
                content = fp.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            m = re.search(r"(?m)^pid:\s*(\d+)", content)
            if not m:
                continue
            pid = int(m.group(1))
            if re.search(r"exit_code:\s*4294967295", content):
                killed.add(pid)
                continue
            if "stale_metadata_repaired: true" in content and not _pid_alive(pid):
                killed.add(pid)
    return killed


def _scan_orphan_and_hung_processes(
    *,
    min_age_minutes: float = 10.0,
    max_cpu_seconds: float = 3.0,
) -> dict[str, Any]:
    alive = _running_pids()
    killed_parents = _terminal_killed_pids()
    orphans: list[dict[str, Any]] = []
    hung: list[dict[str, Any]] = []
    protected: list[dict[str, Any]] = []

    for row in _win32_process_rows():
        pid = int(row.get("ProcessId") or 0)
        parent = int(row.get("ParentProcessId") or 0)
        cmd = str(row.get("CommandLine") or "")
        name = str(row.get("Name") or "")
        if pid <= 0:
            continue
        if _is_protected_command(cmd):
            protected.append({"pid": pid, "name": name, "reason": "protected"})
            continue
        parent_dead = parent > 0 and parent not in alive
        parent_force_killed = parent in killed_parents
        if parent_dead or parent_force_killed:
            orphans.append(
                {
                    "pid": pid,
                    "parent_pid": parent,
                    "name": name,
                    "reason": (
                        "parent_force_killed" if parent_force_killed else "parent_dead"
                    ),
                    "command": cmd[:200],
                }
            )
            continue
        cpu = _process_cpu_seconds(pid)
        age_min = _process_age_minutes(pid)
        cmd_low = cmd.lower()
        looks_like_test = any(m in cmd_low for m in _HUNG_CMD_MARKERS)
        if (
            looks_like_test
            and cpu is not None
            and cpu <= max_cpu_seconds
            and age_min is not None
            and age_min >= min_age_minutes
        ):
            hung.append(
                {
                    "pid": pid,
                    "parent_pid": parent,
                    "name": name,
                    "cpu_seconds": cpu,
                    "age_minutes": age_min,
                    "reason": "low_cpu_test_process",
                    "command": cmd[:200],
                }
            )
    return {
        "platform": sys.platform,
        "orphan_processes": orphans,
        "suspect_hung_processes": hung,
        "protected_processes": protected,
        "killed_terminal_parent_pids": sorted(killed_parents),
    }


@mcp.tool()
def scan_orphan_agent_processes(
    min_age_minutes: float = 10.0,
    max_cpu_seconds: float = 3.0,
) -> str:
    """Find orphan py/python children and low-CPU suspect hung test processes.

    Use after force-killing a stuck terminal parent — children often survive.
    Protected: agent_hygiene_server and MCP server processes.
    """
    return json.dumps(
        _scan_orphan_and_hung_processes(
            min_age_minutes=min_age_minutes,
            max_cpu_seconds=max_cpu_seconds,
        ),
        indent=2,
    )


@mcp.tool()
def cleanup_orphan_agent_processes(
    dry_run: bool = True,
    include_suspect_hung: bool = True,
    min_age_minutes: float = 10.0,
    max_cpu_seconds: float = 3.0,
) -> str:
    """Kill orphan/hung agent-related py/python processes (dry_run defaults to True).

    Always call scan_orphan_agent_processes first. Set dry_run=False to terminate.
    """
    scan = _scan_orphan_and_hung_processes(
        min_age_minutes=min_age_minutes,
        max_cpu_seconds=max_cpu_seconds,
    )
    targets = list(scan["orphan_processes"])
    if include_suspect_hung:
        targets.extend(scan["suspect_hung_processes"])
    seen: set[int] = set()
    results: list[dict[str, Any]] = []
    for item in targets:
        pid = int(item["pid"])
        if pid in seen:
            continue
        seen.add(pid)
        if dry_run:
            results.append({"pid": pid, "action": "would_kill", "reason": item["reason"]})
            continue
        ok, msg = _kill_pid(pid)
        results.append(
            {"pid": pid, "action": "killed" if ok else "failed", "detail": msg, "reason": item["reason"]}
        )
    return json.dumps(
        {
            "dry_run": dry_run,
            "target_count": len(results),
            "results": results,
        },
        indent=2,
    )


@mcp.tool()
def agent_hygiene_full_check() -> str:
    """One-shot: terminal diagnosis + orphan process scan + recommended actions."""
    terminals = json.loads(diagnose_terminal_sessions())
    processes = _scan_orphan_and_hung_processes()
    actions: list[str] = []
    if terminals.get("stale_repairable"):
        actions.append("fix_stale_terminal_logs")
    if terminals.get("processes_still_running"):
        actions.append("kill_terminal_process on alive terminal PIDs if unwanted")
    if processes.get("orphan_processes"):
        actions.append("cleanup_orphan_agent_processes (dry_run=True first)")
    if processes.get("suspect_hung_processes"):
        actions.append("cleanup_orphan_agent_processes with include_suspect_hung=True")
    return json.dumps(
        {
            "terminals": terminals,
            "processes": processes,
            "recommended_actions": actions,
            "ui_note": (
                "Killing OS processes does not close Cursor Terminal UI tabs; "
                "user may still Kill Terminal in the panel."
            ),
        },
        indent=2,
    )


if __name__ == "__main__":
    mcp.run()
