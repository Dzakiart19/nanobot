#!/usr/bin/env bash
# install-deps.sh — Install all runtime dependencies for Dzeck AI agent skills.
# Run this once after cloning, or re-run to repair a broken environment.
# Called automatically by setup-dev.sh.

set -e

echo "=== Dzeck Dependency Installer ==="

# ── 1. System tools (via Nix / replit.nix) ───────────────────────────────────
# The following are declared in replit.nix and installed automatically by Replit:
#   tmux  — required by skill: tmux
# No action needed here; listed for documentation.

# ── 2. Verify core binaries ───────────────────────────────────────────────────
MISSING=()

check_bin() {
    local bin="$1" skill="$2"
    if command -v "$bin" &>/dev/null; then
        echo "  ✅ $bin (for skill: $skill)"
    else
        echo "  ❌ $bin — MISSING (for skill: $skill)"
        MISSING+=("$bin")
    fi
}

echo ""
echo "Checking required binaries..."
check_bin "tmux"    "tmux"
check_bin "gh"      "github"
check_bin "npx"     "clawhub"
check_bin "node"    "clawhub"
check_bin "curl"    "weather / summarize"
check_bin "python3" "core agent"
check_bin "pip"     "core agent"

# ── 3. summarize CLI ─────────────────────────────────────────────────────────
# summarize.sh (steipete/summarize) only ships macOS binaries.
# On Linux / Replit, we fall back to summarize-cli (npm alternative).
if command -v summarize &>/dev/null; then
    echo "  ✅ summarize"
else
    echo "  ⚙  summarize not found — installing npm fallback (summarize-cli)..."
    npm install -g summarize-cli 2>/dev/null \
        && echo "  ✅ summarize-cli installed" \
        || echo "  ⚠  summarize-cli install failed — skill will use LLM fallback"
fi

# ── 4. Node global tools ──────────────────────────────────────────────────────
echo ""
echo "Checking Node global tools..."
if command -v clawhub &>/dev/null; then
    echo "  ✅ clawhub"
else
    echo "  ⚙  clawhub not cached — will use: npx --yes clawhub@latest (on demand)"
fi

# ── 5. Python runtime check ───────────────────────────────────────────────────
echo ""
echo "Checking Python environment..."
python3 -c "import pydantic, httpx, openai, loguru; print('  ✅ Core Python packages OK')" 2>/dev/null \
    || echo "  ⚠  Some Python packages missing — run: pip install -e ."

# ── 6. Summary ────────────────────────────────────────────────────────────────
echo ""
if [ ${#MISSING[@]} -eq 0 ]; then
    echo "=== All dependencies satisfied ==="
else
    echo "=== WARNING: Missing binaries: ${MISSING[*]} ==="
    echo "    These are installed via replit.nix or Replit modules."
    echo "    If missing, restart the workspace or run: replit nix"
fi
