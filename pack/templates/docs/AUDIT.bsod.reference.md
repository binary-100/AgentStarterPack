# Audit

When you ask for **an audit**, that means **everything** — one pass, no gaps. Report **only Fix and Improve**.

---

## Coverage contract (read first)

This document is the **complete, closed scope** for every audit. There are:

- **No partial audits**
- **No “extend coverage later”**
- **No “worth adding to the checklist”** in audit reports
- **No Phase A/B, overlays, or add-ons menus**

The agent runs **`run_audit.cmd`** (machine checks) **and** executes **every section A–N** below (code review). Findings go under **Fix** or **Improve** only.

If the project gains a **new subsystem** (new top-level module or major folder), update **this file’s domain map** and **`run_audit.ps1`** in the same change — not as a follow-up audit suggestion.

---

## How to run

```bat
cd app
run_audit.cmd
```

**One standard:** full `run_tests.bat` + all machine/code checks. **Do not use `-SkipTests`** for an audit — that is incomplete and will fail Fix.

Machine script + agent together = full audit. Merge all findings into Fix and Improve.

---

## Full checklist (A–N, all mandatory)

### A. Tests & version
- `run_tests.bat` with `QT_QPA_PLATFORM=offscreen` — full suite
- `bsod_analyzer.py` ↔ `VERSION.txt` synced
- `BSODAnalyzer_v6\VERSION.txt` matches canonical `VERSION` when present
- `tests/test_version_consistency.py` passes

### B. Files & folders (entire repo tree)
- Layout matches `PROJECT_LAYOUT.md` — canonical paths exist, no unexpected duplicates
- **All** active markdown (`*.md` at repo root, `app\docs\`, `app\AGENTS.md`) — no stale paths (Opus, junction, interim rename), no contradictions with current layout
- Build cruft: no `app\dist\`, `app\build\`, duplicate `BSODAnalyzer_v6_stable\`, stale `app\live_*.json`, stale `*.log` in repo root or `app\`
- Test/cache cruft: no committed `__pycache__` / `.pytest_cache` trees that should be gitignored
- No committed secrets: `.env`, API keys, tokens, private keys in tracked files (excluding test fixtures and bundled third-party trees)
- `proposed_patches\`, obsolete migration scripts, duplicate launchers — delete or **Improve** if still needed
- Stable policy: `Desktop\BSODAnalyzer_StableBuilds\` has exactly v6.1.20, v6.2.3, v6.4.61 (when Desktop exists)
- No forbidden audit artifacts: old overlay/checklist rules, `run_tests_with_timeout.bat`, active `CODE_AUDIT_*.md` outside `audit_archive\`
- Large or misplaced artifacts (old exports on Desktop, duplicate exes, stray Desktop folders) — **Fix** or **Improve**
- Phase 8 OneDrive cleanup status consistent with `ONEDRIVE_CLEANUP.md`

### C. Build, packaging & bundled runtime
- `BSODAnalyzer_v6\BSODAnalyzer.exe` exists; dist `VERSION.txt` matches code
- `build_and_deploy_v6.bat` does not auto-save stables
- `BSODAnalyzer.spec`, `finalize_portable_dist.py`, `build_ci.bat` — portable layout correct
- Bundled runtime paths valid: CDB / DebuggingTools, PowerShell 7, 7-Zip (`test_portable_build_smoke.py`, `test_powershell7.py`, `test_seven_zip_runtime.py`)
- Dist README synced (`sync_dist_readme.py` / `BSODAnalyzer_v6\README.txt`)

### D. Code — BSOD analysis, hardware & reports
- `bsod_analyzer.py` — analysis pipeline, recommendations, CDB/minidump, report formatting
- `gather_report_data`, `newest_minidump_analysis` — correct “latest” selection
- Event 1001 / minidump gaps — regressions only (not accepted limitations)
- Crash-linked driver workflow — `has_crash_faulting_driver`, deferred update checks
- `bsod_runtime.py` — PowerShell runner, paths, export helpers
- `bsod_hardware_wmi.py` — WMI/PnP inventory correctness

### E. Code — GUI, threads, workers & theme
- `bsod_gui_qt.py`, `gui_mixin_*`, `bsod_gui_workers.py`, `gui_signal_relay.py`
- Long work off main thread; no UI updates from workers (`test_gui_main_thread_guard.py`)
- Driver vs firmware vs export — mutual exclusion during scans (`test_pre_compile_hygiene.py`)
- Progress bars and flags reset on finish, error, cancel
- Shutdown: thread / `BackgroundJob` cleanup on window close
- Theme, accessibility, warning colors — regressions in catalog rows and data-gap HTML

### F. Code — settings, paths & portable-first
- `app_settings.py` — portable vs full-install; OneDrive settings fallback (6.4.61+)
- Catalog cache per machine fingerprint in portable mode (`catalog_cache.py`)
- **Portable-first policy** (`AGENTS.md`): new/changed code defaults to portable workflow; full-install-only paths need documented justification
- `tests/test_data_dir_settings.py` and related path tests pass

### G. Code — driver catalog, index & vendors
- `driver_catalog.py`, `driver_index.py`, `driver_list_build.py`
- `catalog_ps_module.py`, `catalog_ps_batch.py` — PS catalog batch pipeline
- `vendor_fetch.py`, `vendor_extractors.py`, `vendor_extractor_repair.py`, `vendor_endpoint_health.py`, `vendor_endpoint_audit.py`
- `oem_effective_version.py`, `gpu_vendor_maps.py`
- Hint vs verified scan; driver version identity
- Swallowed exceptions that hide failures → **Fix**
- Vendor URL rot: `test_catalog_audit_coverage`, `test_vendor_endpoint_health`, `test_parser_rot_detection`, `test_vendor_source_hardening`

### H. Code — firmware
- `firmware_catalog.py`, `vendor_firmware_fetch.py`
- `firmware_ssd_vendors.py`, `firmware_peripheral_vendors.py`, `firmware_peripheral_discovery.py`, `firmware_peripheral_installed.py`
- `gui_mixin_firmware.py` — firmware tab workers and UI
- SSD vs peripheral coverage; batch warm; attention filters
- Tests: `test_vendor_firmware_fetch`, `test_firmware_*`, `test_analysis_firmware_inventory`

### I. Code — export, install & backup
- `catalog_export.py` — export correctness, portable vs full-install paths
- Export blocked while driver/firmware scans run
- `driver_install.py`, `driver_backup.py` — install/backup flows
- `tests/test_catalog_export.py`, `test_driver_install_flow.py`, `test_update_reporting_policy.py`

### J. Code — session, logging & preferences
- `session_log.py` — session logging, rotation, no silent log loss
- `bsod_gui_preferences.py` — prefs persist correctly in portable and full-install modes
- `tests/test_session_log.py`

### K. Security & subprocess hygiene
- No hardcoded credentials or live tokens in source
- Subprocess / shell invocation — no unsafe string concatenation with untrusted paths in export, fetch, and install paths
- Vendor fetch and catalog scripts — timeouts and failure surfaces visible to UI/logs

### L. Agent / Cursor wiring
- Only `audit.mdc` + `docs/AUDIT.md` + `agent-code-audit` skill — no legacy audit rules
- `AGENTS.md` matches current commands (`run_tests.bat`, `run_audit.cmd`, `build_ci.bat`)
- Starter pack 1.4.0+ — `verify-audit-system.ps1` passes (also run by `run_audit.ps1`)
- Project rules do not contradict portable-first or audit protocol

### M. Docs & reference consistency
- Root `README.md`, `PROJECT_LAYOUT.md`, `BUILD_NOTES.md`, `CONSOLIDATION.md` — accurate or archived
- Prefer linking to `VERSION.txt` over stale hard-coded version numbers in doc headers
- HTML mockups under `docs\` — no dead Opus/junction paths unless archived

### N. Recent changes
- If `VERSION` bumped recently, re-read all files changed for that release against sections D–M

### Reference only (do not report unless wrong)
- [`IMPROVEMENT_BACKLOG.md`](IMPROVEMENT_BACKLOG.md) — future work
- [`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md) — accepted tradeoffs
- [`audit_archive/`](audit_archive/) — historical audits
- `app\scripts\` dev/diag tools — report only if broken, committed secrets, or blocking build/test

---

## Domain map (every production module → section)

| Module / area | Section |
|---------------|---------|
| `bsod_analyzer.py` | D |
| `bsod_events.py`, `bsod_workflow.py`, `device_enrichment.py` | D |
| `bsod_runtime.py` | D, I |
| `bsod_hardware_wmi.py` | D |
| `bsod_gui_qt.py`, `gui_mixin_shell.py`, `gui_mixin_system.py` | E |
| `gui_mixin_analysis.py` | D, E |
| `gui_mixin_drivers.py`, `gui_mixin_catalog.py` | E, G |
| `gui_mixin_firmware.py` | E, H |
| `gui_mixin_vendor_health.py` | E, G |
| `bsod_gui_workers.py`, `gui_signal_relay.py`, `gui_widgets.py`, `gui_*` chrome | E |
| `fix_progress.py`, `gui_catalog_parallel.py`, `gui_theme.py` | E |
| `app_settings.py`, `catalog_cache.py`, `hardware_cache.py` | F |
| `driver_catalog.py`, `driver_index.py`, `driver_list_build.py`, `driver_version_identity.py` | G |
| `catalog_ps_module.py`, `catalog_ps_batch.py` | G |
| `catalog_export.py` | G, I |
| `vendor_fetch.py`, `vendor_extractors.py`, `vendor_extractor_repair.py` | G |
| `vendor_download_resolve.py`, `vendor_page_render.py` | G |
| `vendor_endpoint_health.py`, `vendor_endpoint_audit.py` | G |
| `oem_effective_version.py`, `gpu_vendor_maps.py` | G |
| `firmware_catalog.py`, `vendor_firmware_fetch.py` | H |
| `firmware_ssd_vendors.py`, `firmware_peripheral_*.py` | H |
| `driver_install.py`, `driver_backup.py` | I |
| `session_log.py`, `bsod_gui_preferences.py` | J |
| `bsod_gui_log_cleanup.py`, `log_cleanup.py`, `maintenance_log.py`, `timestamped_log_io.py` | J |
| `product_version.py`, `BSODAnalyzer.spec`, `build_*.bat`, `finalize_portable_dist.py` | C |
| Tests: `tests\` | A (+ domain sections they cover) |
| Agent: `.cursor\`, `AGENTS.md`, starter pack | L |

**Dev-only (excluded from domain-map auto-check):** `preview_amd_logos.py`

---

## Automation (manifest 2.4)

| Check | How |
|-------|-----|
| **Tests** | Full **`run_tests.bat`** only — every `tests/test_*.py`; no subset, no `-SkipTests` |
| **sectionTests in config** | Coverage map for D–K; execution via full suite only |
| **Agent manifest** | `docs/.audit_agent_manifest.json` — **all sections A–N** from checklist + hints + domain map |
| **Semantic report (machine-verifiable)** | Agent writes `docs/.audit_semantic_report.json` with `evidence[]`; **`run_audit.cmd` verifies it** after tests pass |
| **machineCoverage** | Manifest maps every enabled machine check per section + `agentFocus` hints for semantic review |
| **Section F / L / M / N machine** | F: portable policy; L: wiring; M: version docs + HTML stale; N: git VERSION delta |
| **Template** | `scripts\write_semantic_audit_template.cmd` after machine pass |
| **`-SkipTests` debug** | Lightweight path (no import smoke); still fails incomplete |
| **Audit file set** | `pack/audit/manifest.json` |
| **Sync drift** | Every audit runs `sync-audit-system.ps1 -VerifyOnly` |

Scripts: `%USERPROFILE%\.cursor\AgentStarterPack\pack\scripts\` (`run_audit_core.ps1`, `audit_code_checks.py`, `sync-audit-system.ps1`)

---

## Report format (only this)

```markdown
## Fix
- **Item** — location — what's wrong and what to do

## Improve
- **Item** — location — suggestion
```

If none: **Nothing found.**

**Forbidden in reports:** P0/P1 labels, pass/fail banners, phase menus, “coverage gaps”, “worth adding to checklist”, or suggestions to expand audit scope instead of Fix/Improve on the project.

---

## After an audit

Say **“fix the audit items”** or pick bullets. Agent fixes, re-runs `run_audit.cmd`, re-audits.

---

## Entry points

| Piece | Location |
|-------|----------|
| Run | `app\run_audit.cmd` |
| Protocol | `app\docs\AUDIT.md` |
| Rule | `app\.cursor\rules\audit.mdc` |
| Skill | `agent-code-audit` |

Maintenance: `%USERPROFILE%\.cursor\AgentStarterPack\pack\docs\AUDIT_SYSTEM.md`
