# Agent chat sync — paste or @ this file after pack install

**Installed:** pack **1.7.0** · audit engine **2.21.13**

Use when **`install.ps1 -Scope User`** ran and an **open chat** may have stale context.

Pick **one** paste block below — **pack repo** vs **product app repo** — not both.

---

## A. Product / bootstrapped app (any application repo)

**Run on disk first** (PowerShell — set paths for your repo):

```powershell
$Repo = "C:\Users\binar\OneDrive\Desktop\YOUR_REPO"   # git root
$Rules = "app\.cursor\rules"                            # or ".cursor\rules" for flat layout

& "C:\Users\binar\OneDrive\Desktop\AgentStarterPack\Update-AgentRules.cmd" $Repo $Rules
& "C:\Users\binar\OneDrive\Desktop\AgentStarterPack\pack\scripts\sync-audit-system.ps1" -ProjectRoot $Repo
```

Optional verify (from pack):

```powershell
& "C:\Users\binar\OneDrive\Desktop\AgentStarterPack\pack\scripts\verify-agent-setup.ps1" `
  -ReferenceProjectRoot $Repo -RulesRelativePath $Rules
```

**Then paste into the open app chat:**

```text
Starter pack was refreshed on this PC (pack 1.7.0, audit engine 2.21.13). Treat earlier messages in this chat as stale.

This is a product app workspace — NOT Agent Starter Pack maintenance.

Before continuing:
1. Re-read AGENTS.md in this workspace (follow its path — e.g. app\AGENTS.md if the workspace root is the repo, not app\)
2. Re-read AI_INSTRUCTIONS.md only if this repo has one
3. Do NOT read HANDOVER_NEXT_AGENT.md — that file lives in the starter pack repo only
4. Version + doc sync here = this project's build pipeline (canonical VERSION in source + apply_version.py sync / docs\VERSION_SYNC.json if present) — not audit-engine version
5. Global generic rules were refreshed via install.ps1; project rules/audit templates were synced if Update-AgentRules + sync-audit-system ran

Reply with one line: which AGENTS.md path you read, and confirm you are continuing with post-refresh context. Then wait for my next task.
```

---

## B. Agent Starter Pack maintenance (Desktop pack repo only)

**Paste into open pack chat:**

```text
Starter pack was refreshed on this PC (pack 1.7.0, audit engine 2.21.13). Treat earlier messages in this chat as stale.

This workspace IS Agent Starter Pack maintenance.

Before continuing:
1. Read C:\Users\binar\OneDrive\Desktop\AgentStarterPack\HANDOVER_NEXT_AGENT.md
2. Re-read AGENTS.md in this repo
3. Version + doc sync = build pipeline (docs\VERSION_SYNC.json, Sync-DocVersions.cmd) — not audit codeChecks
4. Edit only C:\Users\binar\OneDrive\Desktop\AgentStarterPack — no external app repos

Reply confirming you read HANDOVER + AGENTS.md, then continue.
```

---

## C. New chats (any project)

Restart Cursor once after install. New chats load global rules from `C:\Users\binar\.cursor\rules\`. Still start from **AGENTS.md** in the open workspace.

---

## What a good agent reply looks like (app repo)

- Names the **actual AGENTS.md path** it read  
- Skips HANDOVER (correct for product repos)  
- Describes **this project's** version source (e.g. main module / apply_version.py), not pack maintainer docs  
- Does **not** assume pre-refresh chat context  

---

Canonical maintainer copy: `C:\Users\binar\OneDrive\Desktop\AgentStarterPack`  
Installed profile: `C:\Users\binar\.cursor\AgentStarterPack`
