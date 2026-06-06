#!/usr/bin/env bash
set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║        🗿 Dzeck installer                 ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 0. System dependencies (via Nix / nix-env) ────────────────────────────────
echo "▶ [0/7] Installing system dependencies..."
NIX_PKGS=(
    # Core utilities
    coreutils findutils gnugrep gnused gawk
    # Text editors
    nano vim
    # Network tools
    curl wget openssh rsync inetutils nmap dnsutils netcat-openbsd
    # Archive & compression
    zip unzip gnutar gzip bzip2 xz
    # Process & system management
    procps htop lsof
    # Media & document processing
    ffmpeg imagemagick pandoc
    # Data tools
    jq yq-go
    # File utilities
    file tree which
)
if command -v nix-env &>/dev/null; then
    nix-env -iA nixpkgs."${NIX_PKGS[@]}" 2>/dev/null \
        && echo "    ✓ Nix packages installed" \
        || echo "    ⚠ Some Nix packages skipped (may already be installed)"
else
    echo "    ⚠ nix-env not found — skipping system packages (they may already be available)"
fi

# ── 1. Python package (core dependencies dari pyproject.toml) ─────────────────
echo "▶ [1/7] Installing Python package (Dzeck engine)..."
pip install -e . -q
echo "    ✓ Dzeck engine installed"

# ── 2. Extra Python dependencies (tidak ada di pyproject.toml) ───────────────
echo "▶ [2/7] Installing extra Python dependencies..."
pip install -q \
    pymongo \
    bcrypt \
    discord.py \
    aiohttp \
    Pillow \
    requests \
    httpx \
    pytz
echo "    ✓ Extra Python dependencies installed"

# ── 3. Optional Python extras ─────────────────────────────────────────────────
echo "▶ [3/7] Installing optional Python extras..."
pip install -q -e ".[api,discord,msteams,azure,pdf,langsmith,olostep,weixin,wecom]"
echo "    ✓ Optional extras installed"

# ── 3b. Matrix extras (needs native libolm — skip if unavailable) ─────────────
echo "▶ [3b/7] Installing Matrix extras (may skip if native deps unavailable)..."
pip install -q -e ".[matrix]" 2>/dev/null && echo "    ✓ Matrix extras installed" || echo "    ⚠ Matrix extras skipped (missing native deps)"

# ── 4. Frontend dependencies ──────────────────────────────────────────────────
echo "▶ [4/7] Installing frontend dependencies (webui)..."
cd webui && npm install -q && cd ..
echo "    ✓ webui dependencies installed"

# ── 5. Root / e2e dependencies ────────────────────────────────────────────────
echo "▶ [5/7] Installing root dependencies (e2e/ws/playwright)..."
npm install -q
echo "    ✓ root dependencies installed"

# ── 6. Create dzeck config ──────────────────────────────────────────────────
echo "▶ [6/7] Setting up Dzeck config (~/.dzeck/config.json)..."
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

# Use ${VAR} references — values resolved at runtime from env vars
config.setdefault("providers", {})["custom"] = {
    "type": "openai",
    "apiKey": "${DZECK_API_KEY}",
    "apiBase": "${DZECK_API_BASE}",
}

defaults = config.setdefault("agents", {}).setdefault("defaults", {})
defaults["provider"] = "custom"
defaults["model"] = "${DZECK_MODEL}"
defaults["contextWindowTokens"] = 262144
defaults["timezone"] = "Asia/Jakarta"
defaults["botIcon"] = "🗿"

# Enable image generation by default
tools = config.setdefault("tools", {})
tools.setdefault("image", {})["enabled"] = True

ws = config.setdefault("channels", {}).setdefault("websocket", {})
ws["enabled"] = True
ws["host"]    = "0.0.0.0"
ws["port"]    = 8081
ws["path"]    = "/ws"
ws["tokenIssueSecret"] = password

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)

print(f"    ✓ Config ready → apiKey=${{DZECK_API_KEY}}, apiBase=${{DZECK_API_BASE}}, model=${{DZECK_MODEL}}")
PYEOF

# ── 7. Verify key commands ─────────────────────────────────────────────────────
echo "▶ [7/7] Verifying installed commands..."
for cmd in dzeck python3 node npm curl jq; do
    if command -v "$cmd" &>/dev/null; then
        echo "    ✓ $cmd → $(command -v $cmd)"
    else
        echo "    ⚠ $cmd not found"
    fi
done

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✅ Dzeck siap dijalankan!                ║"
echo "║                                          ║"
echo "║  Jalankan project:                       ║"
echo "║    Backend : dzeck gateway --port 8080   ║"
echo "║    Frontend: cd webui && npm run dev     ║"
echo "║                                          ║"
echo "║  Login password: admin123                ║"
echo "╚══════════════════════════════════════════╝"
echo ""
