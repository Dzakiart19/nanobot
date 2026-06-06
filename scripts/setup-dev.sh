#!/usr/bin/env bash
set -e

# Remove stale non-editable nanobot install that overrides workspace source.
# The editable .pth file (_editable_impl_nanobot_ai.pth) already points to
# /home/runner/workspace, so a plain "nanobot" directory in site-packages
# would shadow it and serve stale code.
SITE_PKG="$HOME/workspace/.pythonlibs/lib/python3.11/site-packages"
if [ -d "$SITE_PKG/nanobot" ]; then
    echo "Removing stale nanobot install from site-packages..."
    rm -rf "$SITE_PKG/nanobot"
fi

# Install Python package if nanobot command not found
if ! command -v nanobot &> /dev/null; then
    echo "Installing Dzeck engine (nanobot package)..."
    pip install -e . -q
    # After editable install, ensure no plain directory copy shadowed it
    if [ -d "$SITE_PKG/nanobot" ]; then
        rm -rf "$SITE_PKG/nanobot"
    fi
fi

# Create config using ${VAR} references so env vars are always the source of truth
CONFIG_DIR="${HOME}/.nanobot"
CONFIG_FILE="${CONFIG_DIR}/config.json"
mkdir -p "$CONFIG_DIR"

python3 - <<'PYEOF'
import json, os

config_dir = os.path.expanduser("~/.nanobot")
config_file = config_dir + "/config.json"
os.makedirs(config_dir, exist_ok=True)

if os.path.exists(config_file):
    with open(config_file) as f:
        config = json.load(f)
else:
    config = {}

password = os.environ.get("NANOBOT_PASSWORD", "admin123")

# Always use ${VAR} references — values resolved at runtime from env vars
config.setdefault("providers", {})["custom"] = {
    "type": "openai",
    "apiKey": "${NANOBOT_API_KEY}",
    "apiBase": "${NANOBOT_API_BASE}",
}
config.setdefault("agents", {}).setdefault("defaults", {})["provider"] = "custom"
config.setdefault("agents", {}).setdefault("defaults", {})["model"] = "${NANOBOT_MODEL}"

ws = config.setdefault("channels", {}).setdefault("websocket", {})
ws["enabled"] = True
ws["host"]    = "0.0.0.0"
ws["port"]    = 8081
ws["path"]    = "/ws"
ws["tokenIssueSecret"] = password

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)

print("Config ready: apiKey=${NANOBOT_API_KEY}, apiBase=${NANOBOT_API_BASE}, model=${NANOBOT_MODEL}")

# Write AGENTS.md — agent instructions (file delivery + workspace conventions)
agents_md = os.path.expanduser("~/.nanobot/workspace/AGENTS.md")
agents_content = """\
# Agent Instructions

## Workspace Guidance

Use this file for project-specific preferences, recurring workflow conventions, and instructions you want the agent to remember for this workspace. Keep durable facts about the user in `USER.md`, personality/style guidance in `SOUL.md`, and long-term memory in `memory/MEMORY.md`.

## File Delivery After Task Completion

When you finish creating a file or project, **call the `deliver_file` tool** so the user gets a real download link.

- Directory → tool auto-zips it, give a clear filename like `my-project.zip`
- Single file → delivered as-is

After calling the tool, paste the link it returns into your reply. Never write a download link by hand — the link must come from the tool call result.

### When to call it
Any time you finish creating something the user will want to keep: code projects, documents, scripts, data exports, zip archives, etc.

### Do NOT
- Write `[📦 Download ...]` manually — that is not a real link, the tool must generate it.
- Tell the user "file ada di folder X" without calling the tool first.

## Scheduled Reminders

Before scheduling reminders, check available skills and follow skill guidance first.
Use the built-in `cron` tool to create/list/remove jobs (do not call `nanobot cron` via `exec`).
Get USER_ID and CHANNEL from the current session (e.g., `8281248569` and `telegram` from `telegram:8281248569`).

**Do NOT just write reminders to MEMORY.md** — that won't trigger actual notifications.

## Heartbeat Tasks

`HEARTBEAT.md` is checked periodically when registered as a cron job. Use the built-in `cron` tool to schedule it.

- Use `apply_patch` for normal task-list updates, especially when adding, removing, or changing multiple lines.
- Use `edit_file` only for small exact replacements copied from the current `HEARTBEAT.md`.
- Use `write_file` for first creation or intentional full-file rewrites.

When the user asks for a recurring/periodic task, update `HEARTBEAT.md` and register it via `cron` instead of creating a one-time reminder.
"""
os.makedirs(os.path.dirname(agents_md), exist_ok=True)
with open(agents_md, "w") as f:
    f.write(agents_content)
print("AGENTS.md written")
PYEOF
