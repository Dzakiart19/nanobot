# Dzeck

An ultra-lightweight personal AI agent runtime. Self-host your own AI assistant with multi-model support, persistent memory, and integrations with popular chat platforms.

## Project Structure

- `dzeck/` — Core Python package (agent loop, channels, providers, tools)
- `webui/` — React + TypeScript + Vite frontend (chat UI)
- `bridge/` — Node.js WhatsApp bridge (optional)
- `docs/` — Project documentation

## Architecture

- **Frontend**: Vite dev server on port 5000 (proxies API calls to the backend)
- **Backend (Gateway)**: `dzeck gateway` on port 8080 (health/status endpoint)
- **WebSocket Channel**: `dzeck` websocket channel on port 8081 (serves WebUI HTTP + WebSocket)
- Config lives at `~/.dzeck/config.json`

## Running Locally

Two workflows are configured:
1. **Start application** — `cd webui && npm run dev` (frontend on port 5000)
2. **Backend Gateway** — `dzeck gateway --port 8080` (backend)

## Configuration

The dzeck config is at `~/.dzeck/config.json`. On first run it's configured with Ollama (local LLM) as a placeholder. Users can configure their preferred LLM provider (OpenAI, Anthropic, etc.) through the Settings UI in the WebUI.

## User Preferences

- Keep the frontend on port 5000 with `allowedHosts: true` for Replit proxy compatibility
- Backend health server on port 8080, WebSocket channel on port 8081
- Vite proxy routes `/webui`, `/api`, `/auth` to the backend websocket channel on port 8081
