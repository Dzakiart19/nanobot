#!/usr/bin/env bash
# install.sh — Install ALL dependencies for Dzeck (Python package + skill tools).
# Runs automatically on every project start via setup-dev.sh.
# Can also be run manually: bash scripts/install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_PKG="$HOME/workspace/.pythonlibs/lib/python3.11/site-packages"

echo "=== Dzeck Install ==="

# ── 1. Python package (dzeck engine) ─────────────────────────────────────────
# Remove stale non-editable install that would shadow the workspace source.
if [ -d "$SITE_PKG/dzeck" ]; then
    echo "  Removing stale dzeck install from site-packages..."
    rm -rf "$SITE_PKG/dzeck"
fi

if ! command -v dzeck &>/dev/null; then
    echo "  Installing Dzeck engine..."
    pip install -e . -q
    # Ensure no plain copy shadowed the editable install
    [ -d "$SITE_PKG/dzeck" ] && rm -rf "$SITE_PKG/dzeck"
    echo "  ✅ dzeck installed"
else
    echo "  ✅ dzeck already installed"
fi

# ── 2. Core binaries check ────────────────────────────────────────────────────
MISSING=()

check_bin() {
    local bin="$1" label="$2"
    if command -v "$bin" &>/dev/null; then
        echo "  ✅ $bin  ($label)"
    else
        echo "  ❌ $bin  MISSING  ($label)"
        MISSING+=("$bin")
    fi
}

echo ""
echo "Checking skill dependencies..."
check_bin "tmux"    "skill: tmux"
check_bin "gh"      "skill: github"
check_bin "npx"     "skill: clawhub"
check_bin "node"    "skill: clawhub"
check_bin "curl"    "skill: weather"
check_bin "python3" "core agent"
check_bin "pip"     "core agent"

# ── System utilities (declared in replit.nix — always available) ──────────────
echo ""
echo "Checking system utilities..."
check_bin "wget"   "file download"
check_bin "rsync"  "file sync"
check_bin "zip"    "archive"
check_bin "unzip"  "archive"
check_bin "tree"   "directory listing"
check_bin "bc"     "math"

# ── 3. summarize CLI ──────────────────────────────────────────────────────────
# steipete/summarize only ships macOS binaries — no Linux release available.
# We try an npm fallback; if that also fails the skill degrades to LLM fallback.
if command -v summarize &>/dev/null; then
    echo "  ✅ summarize"
else
    echo "  ⚙  summarize: macOS-only binary — trying npm fallback..."
    npm install -g summarize-cli --quiet 2>/dev/null \
        && echo "  ✅ summarize-cli (npm fallback)" \
        || echo "  ⚠  summarize unavailable on Linux — skill uses LLM fallback"
fi

# ── 4. clawhub (on-demand via npx) ───────────────────────────────────────────
if command -v clawhub &>/dev/null; then
    echo "  ✅ clawhub"
else
    echo "  ⚙  clawhub: loaded on demand via: npx --yes clawhub@latest"
fi

# ── 5. Python package check ───────────────────────────────────────────────────
echo ""
python3 -c "import pydantic, httpx, openai, loguru; print('  ✅ Core Python packages OK')" 2>/dev/null \
    || { echo "  ⚠  Core Python packages missing — reinstalling..."; pip install -e . -q; }

# ── 6. Result ─────────────────────────────────────────────────────────────────
echo ""
if [ ${#MISSING[@]} -eq 0 ]; then
    echo "=== ✅ All dependencies satisfied ==="
else
    echo "=== ⚠  Missing system tools: ${MISSING[*]} ==="
    echo "    Installed via Nix (replit.nix) — restart workspace if still missing."
fi
