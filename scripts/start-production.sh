#!/usr/bin/env bash
set -e

CONFIG_DIR="${DZECK_CONFIG_DIR:-$HOME/.dzeck}"
CONFIG_FILE="$CONFIG_DIR/config.json"

mkdir -p "$CONFIG_DIR"

python3 - <<'PYEOF'
import json, os, sys

config_file = os.environ.get("DZECK_CONFIG_DIR", os.path.expanduser("~/.dzeck")) + "/config.json"

if os.path.exists(config_file):
    with open(config_file) as f:
        config = json.load(f)
else:
    config = {}

api_key  = os.environ.get("NANOBOT_API_KEY", "")
api_base = os.environ.get("NANOBOT_API_BASE", "")
model    = os.environ.get("NANOBOT_MODEL", "gpt-4o-mini")
password = os.environ.get("NANOBOT_PASSWORD", "")

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
    ws["token"]            = password
    ws["tokenIssueSecret"] = password
    ws["websocketRequiresToken"] = True

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)

print(f"Production config written → port 5000, model {model}", flush=True)
PYEOF

exec dzeck gateway --port 8080
