#!/usr/bin/env bash
set -e

# Install Python package if nanobot command not found
if ! command -v nanobot &> /dev/null; then
    echo "Installing Dzeck engine (nanobot package)..."
    pip install -e . -q
fi

# Create Dzeck config if it doesn't exist
CONFIG_DIR="${HOME}/.nanobot"
CONFIG_FILE="${CONFIG_DIR}/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating Dzeck config..."
    mkdir -p "$CONFIG_DIR"
    python3 - <<'PYEOF'
import json, os, secrets

config_dir = os.path.expanduser("~/.nanobot")
config_file = config_dir + "/config.json"
os.makedirs(config_dir, exist_ok=True)

config = {}
api_key  = os.environ.get("NANOBOT_API_KEY", "")
api_base = os.environ.get("NANOBOT_API_BASE", "")
model    = os.environ.get("NANOBOT_MODEL", "gpt-4o-mini")

if api_key and api_base:
    config.setdefault("providers", {})["custom"] = {
        "type": "openai",
        "apiKey": api_key,
        "apiBase": api_base,
    }
    config.setdefault("agents", {}).setdefault("defaults", {})["provider"] = "custom"
    config.setdefault("agents", {}).setdefault("defaults", {})["model"] = model

password = os.environ.get("NANOBOT_PASSWORD", "admin123")
ws = config.setdefault("channels", {}).setdefault("websocket", {})
ws["enabled"] = True
ws["host"]    = "0.0.0.0"
ws["port"]    = 8081
ws["path"]    = "/ws"
ws["tokenIssueSecret"] = password

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)

print(f"Config written: model={model}, ws_port=8081")
PYEOF
fi
