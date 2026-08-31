# Portable exports (non-Cursor agents)

Plain-markdown mirrors of Cursor global rules and skills.

| File | Purpose |
|------|---------|
| [GENERIC_RULES.md](GENERIC_RULES.md) | All ``pack/rules/*.mdc`` bodies (no YAML frontmatter) |
| [skills/](skills/) | One ``.md`` per pack skill |

**Cursor users:** ``install.ps1`` installs ``.mdc`` rules automatically - you do not need these files.

**Other tools:** At session start, attach or paste ``GENERIC_RULES.md``, or the sections you need,
plus this project's ``AI_INSTRUCTIONS.md`` and ``AGENTS.md``.

Regenerate after pack rule edits:

```powershell
pack\scripts\sync-portable-docs.ps1
```

See also: ``docs/PORTABLE_SETUP.md`` at the pack root.
