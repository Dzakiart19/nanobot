#!/usr/bin/env bash
set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║        🐈 nanobot installer               ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 1. Python package ────────────────────────────────────────────────────────
echo "▶ [1/4] Installing Python package (nanobot)..."
pip install -e . -q
echo "    ✓ nanobot installed"

# ── 2. Frontend dependencies ─────────────────────────────────────────────────
echo "▶ [2/4] Installing frontend dependencies (webui)..."
cd webui && npm install -q && cd ..
echo "    ✓ webui dependencies installed"

# ── 3. Root / e2e dependencies ───────────────────────────────────────────────
echo "▶ [3/4] Installing root dependencies (e2e/ws)..."
npm install -q
echo "    ✓ root dependencies installed"

# ── 4. Create nanobot config ──────────────────────────────────────────────────
echo "▶ [4/4] Setting up nanobot config (~/.nanobot/config.json)..."
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

api_key  = os.environ.get("NANOBOT_API_KEY", "")
api_base = os.environ.get("NANOBOT_API_BASE", "")
model    = os.environ.get("NANOBOT_MODEL", "gpt-4o-mini")
password = os.environ.get("NANOBOT_PASSWORD", "admin123")

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
ws["port"]    = 8081
ws["path"]    = "/ws"
ws["tokenIssueSecret"] = password

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)

print(f"    ✓ Config written  →  model={model}, password={password}, ws_port=8081")
PYEOF

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✅ Installation complete!                ║"
echo "║                                          ║"
echo "║  Jalankan project:                       ║"
echo "║    Backend : nanobot gateway --port 8080 ║"
echo "║    Frontend: cd webui && npm run dev     ║"
echo "║                                          ║"
echo "║  Login password: admin123                ║"
echo "╚══════════════════════════════════════════╝"
echo ""
