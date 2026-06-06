#!/usr/bin/env bash
set -e

# Remove stale non-editable dzeck install that overrides workspace source.
# The editable .pth file (_editable_impl_dzeck_ai.pth) already points to
# /home/runner/workspace, so a plain "dzeck" directory in site-packages
# would shadow it and serve stale code.
SITE_PKG="$HOME/workspace/.pythonlibs/lib/python3.11/site-packages"
if [ -d "$SITE_PKG/dzeck" ]; then
    echo "Removing stale dzeck install from site-packages..."
    rm -rf "$SITE_PKG/dzeck"
fi

# Install Python package if dzeck command not found
if ! command -v dzeck &> /dev/null; then
    echo "Installing Dzeck engine (dzeck package)..."
    pip install -e . -q
    # After editable install, ensure no plain directory copy shadowed it
    if [ -d "$SITE_PKG/dzeck" ]; then
        rm -rf "$SITE_PKG/dzeck"
    fi
fi

# Create config using ${VAR} references so env vars are always the source of truth
CONFIG_DIR="${HOME}/.dzeck"
CONFIG_FILE="${CONFIG_DIR}/config.json"
mkdir -p "$CONFIG_DIR"

python3 - <<'PYEOF'
import json, os

config_dir = os.path.expanduser("~/.dzeck")
config_file = config_dir + "/config.json"
os.makedirs(config_dir, exist_ok=True)

if os.path.exists(config_file):
    with open(config_file) as f:
        config = json.load(f)
else:
    config = {}

password = os.environ.get("DZECK_PASSWORD", "admin123")

# Always use ${VAR} references — values resolved at runtime from env vars
config.setdefault("providers", {})["custom"] = {
    "type": "openai",
    "apiKey": "${DZECK_API_KEY}",
    "apiBase": "${DZECK_API_BASE}",
}
config.setdefault("agents", {}).setdefault("defaults", {})["provider"] = "custom"
config.setdefault("agents", {}).setdefault("defaults", {})["model"] = "${DZECK_MODEL}"

ws = config.setdefault("channels", {}).setdefault("websocket", {})
ws["enabled"] = True
ws["host"]    = "0.0.0.0"
ws["port"]    = 8081
ws["path"]    = "/ws"
ws["tokenIssueSecret"] = password

img = config.setdefault("tools", {}).setdefault("image_generation", {})
img["enabled"]  = True
img["provider"] = "custom"
img["model"]    = "dall-e-3"

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)

print("Config ready: apiKey=${DZECK_API_KEY}, apiBase=${DZECK_API_BASE}, model=${DZECK_MODEL}")

# Write AGENTS.md — agent instructions (file delivery + workspace conventions)
agents_md = os.path.expanduser("~/.dzeck/workspace/AGENTS.md")
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
Use the built-in `cron` tool to create/list/remove jobs (do not call `dzeck cron` via `exec`).
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

# Write SOUL.md — persona + vision capability
soul_md = os.path.expanduser("~/.dzeck/workspace/SOUL.md")
soul_content = """\
# Soul

I am Dzeck 🐈, a personal AI assistant.

## Core Principles

- Solve by doing, not by describing what I would do.
- Keep responses short unless depth is asked for.
- Say what I know, flag what I don't, and never fake confidence.
- Stay friendly and curious — I'd rather ask a good question than guess wrong.
- Treat the user's time as the scarcest resource, and their trust as the most valuable.

## Execution Rules

- Act immediately on single-step tasks — never end a turn with just a plan or promise.
- For multi-step tasks, outline the plan first and wait for user confirmation before executing.
- Read before you write — do not assume a file exists or contains what you expect.
- If a tool call fails, diagnose the error and retry with a different approach before reporting failure.
- When information is missing, look it up with tools first. Only ask the user when tools cannot answer.
- After multi-step changes, verify the result (re-read the file, run the test, check the output).

## Vision / Image Analysis

I can see and analyze images directly — no tool needed.
When the user sends an image, I look at it and respond based on what I see.
I never say "image tool not available" — I just describe, analyze, or answer questions about the image right away.
"""
with open(soul_md, "w") as f:
    f.write(soul_content)
print("SOUL.md written")
PYEOF
