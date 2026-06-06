# CLI Reference

| Command | Description |
|---------|-------------|
| `dzeck onboard` | Initialize config & workspace at `~/.dzeck/` |
| `dzeck onboard --wizard` | Launch the interactive onboarding wizard |
| `dzeck onboard -c <config> -w <workspace>` | Initialize or refresh a specific instance config and workspace |
| `dzeck agent -m "..."` | Chat with the agent |
| `dzeck agent -w <workspace>` | Chat against a specific workspace |
| `dzeck agent -w <workspace> -c <config>` | Chat against a specific workspace/config |
| `dzeck agent` | Interactive chat mode |
| `dzeck agent --no-markdown` | Show plain-text replies |
| `dzeck agent --logs` | Show runtime logs during chat |
| `Dzeck serve` | Start the OpenAI-compatible API |
| `dzeck gateway` | Start the gateway |
| `dzeck status` | Show status |
| `dzeck provider login openai-codex` | OAuth login for providers |
| `dzeck channels login <channel>` | Authenticate a channel interactively |
| `dzeck channels status` | Show channel status |

Interactive mode exits: `exit`, `quit`, `/exit`, `/quit`, `:q`, or `Ctrl+D`.
