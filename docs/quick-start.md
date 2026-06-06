# Install and Quick Start

## Install

> [!IMPORTANT]
> This README may describe features that are available first in the latest source code.
> If you want the newest features and experiments, install from source.
> If you want the most stable day-to-day experience, install from PyPI or with `uv`.

**Install from source** (latest features, experimental changes may land here first; recommended for development)

```bash
git clone https://github.com/HKUDS/Dzeck.git
cd Dzeck
pip install -e .
```

**Install with [uv](https://github.com/astral-sh/uv)** (stable release, fast)

```bash
uv tool install Dzeck-ai
```

**Install from PyPI** (stable release)

```bash
pip install Dzeck-ai
```

### Update to latest version

**PyPI / pip**

```bash
pip install -U Dzeck-ai
Dzeck --version
```

**uv**

```bash
uv tool upgrade Dzeck-ai
Dzeck --version
```

**Using WhatsApp?** Rebuild the local bridge after upgrading:

```bash
rm -rf ~/.Dzeck/bridge
Dzeck channels login whatsapp
```

## Quick Start

> [!TIP]
> Set your API key in `~/.Dzeck/config.json`.
> Get API keys: [OpenRouter](https://openrouter.ai/keys) (Global)
>
> For other LLM providers, please see [`configuration.md`](./configuration.md).
>
> For web search capability setup, please see the web-search section in [`configuration.md`](./configuration.md#web-search).

**1. Initialize**

```bash
Dzeck onboard
```

Use `Dzeck onboard --wizard` if you want the interactive setup wizard.

**2. Configure** (`~/.Dzeck/config.json`)

Configure these **two parts** in your config (other options have defaults).

*Set your API key* (e.g. OpenRouter, recommended for global users):
```json
{
  "providers": {
    "openrouter": {
      "apiKey": "sk-or-v1-xxx"
    }
  }
}
```

*Set your model* (optionally pin a provider — defaults to auto-detection):
```json
{
  "agents": {
    "defaults": {
      "model": "anthropic/claude-opus-4-5",
      "provider": "openrouter"
    }
  }
}
```

**3. Chat**

```bash
Dzeck agent
```

That's it! You have a working AI agent in 2 minutes.
