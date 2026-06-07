#!/usr/bin/env bash
set -e

CONFIG_DIR="${DZECK_CONFIG_DIR:-$HOME/.dzeck}"
CONFIG_FILE="$CONFIG_DIR/config.json"

mkdir -p "$CONFIG_DIR"

python3 - <<'PYEOF'
import json, os, secrets

config_file = os.environ.get("DZECK_CONFIG_DIR", os.path.expanduser("~/.dzeck")) + "/config.json"

if os.path.exists(config_file):
    with open(config_file) as f:
        config = json.load(f)
else:
    config = {}

api_key  = os.environ.get("DZECK_API_KEY", "")
api_base = os.environ.get("DZECK_API_BASE", "")
model    = os.environ.get("DZECK_MODEL", "gpt-4o-mini")
password = os.environ.get("DZECK_PASSWORD", "")

if api_key and api_base:
    config.setdefault("providers", {})["custom"] = {
        "type": "openai",
        "apiKey": api_key,
        "apiBase": api_base,
    }
    config.setdefault("agents", {}).setdefault("defaults", {})["provider"] = "custom"
    config.setdefault("agents", {}).setdefault("defaults", {})["model"] = model

ws = config.setdefault("channels", {}).setdefault("websocket", {})
ws["enabled"] = True
ws["host"]    = "0.0.0.0"
ws["port"]    = 5000
ws["path"]    = "/ws"

if password:
    # Explicit password set: require token auth
    ws["token"]                  = password
    ws["tokenIssueSecret"]       = password
    ws["websocketRequiresToken"] = True
else:
    # No password: generate/reuse a random tokenIssueSecret so the channel
    # can bind to 0.0.0.0 (required by Replit healthcheck on port 5000).
    # WebSocket connections do NOT require a token in this mode.
    existing_secret = ws.get("tokenIssueSecret", "")
    if not existing_secret:
        existing_secret = secrets.token_hex(32)
    ws["tokenIssueSecret"]       = existing_secret
    ws["websocketRequiresToken"] = False

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)

print(f"Production config written → port 5000, model {model}", flush=True)
PYEOF

exec dzeck gateway --port 8080
