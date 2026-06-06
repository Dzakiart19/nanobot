#!/usr/bin/env bash
set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║        🐈 Dzeck installer                 ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 1. Python package (core dependencies dari pyproject.toml) ─────────────────
echo "▶ [1/6] Installing Python package (Dzeck engine)..."
pip install -e . -q
echo "    ✓ Dzeck engine installed"

# ── 2. Extra Python dependencies (tidak ada di pyproject.toml) ───────────────
echo "▶ [2/6] Installing extra Python dependencies..."
pip install -q \
    pymongo \
    discord.py \
    aiohttp
echo "    ✓ Extra Python dependencies installed"

# ── 3. Optional Python extras ─────────────────────────────────────────────────
echo "▶ [3/6] Installing optional Python extras (api, discord)..."
pip install -q -e ".[api,discord]"
echo "    ✓ Optional extras installed"

# ── 4. Frontend dependencies ──────────────────────────────────────────────────
echo "▶ [4/6] Installing frontend dependencies (webui)..."
cd webui && npm install -q && cd ..
echo "    ✓ webui dependencies installed"

# ── 5. Root / e2e dependencies ────────────────────────────────────────────────
echo "▶ [5/6] Installing root dependencies (e2e/ws/playwright)..."
npm install -q
echo "    ✓ root dependencies installed"

# ── 6. Create nanobot config ──────────────────────────────────────────────────
echo "▶ [6/6] Setting up Dzeck config (~/.nanobot/config.json)..."
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
echo "║  ✅ Dzeck siap dijalankan!                ║"
echo "║                                          ║"
echo "║  Jalankan project:                       ║"
echo "║    Backend : nanobot gateway --port 8080 ║"
echo "║    Frontend: cd webui && npm run dev     ║"
echo "║                                          ║"
echo "║  Login password: admin123                ║"
echo "╚══════════════════════════════════════════╝"
echo ""
