# Work completion — AgentStarterPack

**Canonical rules:** `%USERPROFILE%\.cursor\AgentStarterPack\pack\docs\WORK_COMPLETION.md` (read that first).

This file is the **project overlay** — paths and test entry only. Do not duplicate lifecycle rules here.

---

## Project paths

| Item | Path |
|------|------|
| Project root | `C:\Users\binar\OneDrive\Desktop\AgentStarterPack` |
| Work queue | `C:\Users\binar\OneDrive\Desktop\AgentStarterPack\docs\WORK_QUEUE.md` |
| Active handoffs | `C:\Users\binar\OneDrive\Desktop\AgentStarterPack\docs\handoffs\active\` |
| Handoff archive | `C:\Users\binar\OneDrive\Desktop\AgentStarterPack\docs\handoff_archive\` |
| Audit | `C:\Users\binar\OneDrive\Desktop\AgentStarterPack\run_audit.cmd` |

Replace `C:\Users\binar\OneDrive\Desktop\AgentStarterPack` with your machine path if this template was not customized at bootstrap.

---

## Archive preview (safe — no changes)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.cursor\AgentStarterPack\pack\scripts\archive-completed-handoff.ps1" `
  -ProjectRoot "C:\Users\binar\OneDrive\Desktop\AgentStarterPack"
```

**Apply only after explicit human confirm** — add `-Apply` to the command above.

---

## Audit Fix reminder

Audit **Fix** lines name specific paths only (e.g. committed cache trees). They do **not** authorize deleting handoffs, `docs/WORK_QUEUE.md`, or `.audit_*` JSON files.
