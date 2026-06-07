#!/bin/bash
set -e

# Install/reinstall the dzeck Python package and skill dependencies
bash "$(dirname "$0")/install.sh"

# Install frontend dependencies (non-interactive)
cd webui && npm install --yes 2>/dev/null || true
cd ..
