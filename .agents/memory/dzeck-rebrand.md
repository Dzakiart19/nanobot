---
name: dzeck rebrand scope
description: Key facts about the nanobot→Dzeck rebrand so future agents stay consistent.
---

# Dzeck Rebrand Decisions

## Core rules
- Python package directory: `dzeck/` (was `nanobot/`)
- All imports: `from dzeck.xxx import ...`
- Programmatic facade: `dzeck/dzeck.py`, class `Dzeck` (was `dzeck/nanobot.py`, class `Nanobot`)
- CLI entrypoint: `dzeck` (was `nanobot`) — in `pyproject.toml` scripts section
- Config dir: `~/.dzeck/` (was `~/.nanobot/`)
- Auto-migration: `dzeck/config/loader.py` `_migrate_legacy_dir()` copies `~/.nanobot/` → `~/.dzeck/` on first run

## Frontend
- Client file: `webui/src/lib/dzeck-client.ts` (was `nanobot-client.ts`)
- Client class: `DzeckClient` / `DzeckClientOptions`
- localStorage prefix: `dzeck-webui.*` (was `nanobot-webui.*`)
- Debug key: `dzeck_debug_ws` (was `nanobot_debug_ws`)
- WS URL prefix: `dzeck-host://` (was `nanobot-host://`)
- Event names: `dzeck:cli-apps-changed`, `dzeck:mcp-presets-changed`

**Why:** Complete A–Z rebrand from nanobot to Dzeck brand.
