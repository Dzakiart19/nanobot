# CLI Reference

| Command | Description |
|---------|-------------|
| `Dzeck onboard` | Initialize config & workspace at `~/.Dzeck/` |
| `Dzeck onboard --wizard` | Launch the interactive onboarding wizard |
| `Dzeck onboard -c <config> -w <workspace>` | Initialize or refresh a specific instance config and workspace |
| `Dzeck agent -m "..."` | Chat with the agent |
| `Dzeck agent -w <workspace>` | Chat against a specific workspace |
| `Dzeck agent -w <workspace> -c <config>` | Chat against a specific workspace/config |
| `Dzeck agent` | Interactive chat mode |
| `Dzeck agent --no-markdown` | Show plain-text replies |
| `Dzeck agent --logs` | Show runtime logs during chat |
| `Dzeck serve` | Start the OpenAI-compatible API |
| `Dzeck gateway` | Start the gateway |
| `Dzeck status` | Show status |
| `Dzeck provider login openai-codex` | OAuth login for providers |
| `Dzeck channels login <channel>` | Authenticate a channel interactively |
| `Dzeck channels status` | Show channel status |

Interactive mode exits: `exit`, `quit`, `/exit`, `/quit`, `:q`, or `Ctrl+D`.
