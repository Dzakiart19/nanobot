# Deployment

## Docker

> [!TIP]
> The `-v ~/.Dzeck:/home/Dzeck/.Dzeck` flag mounts your local config directory into the container, so your config and workspace persist across container restarts.
> The container runs as the non-root user `Dzeck` (UID 1000) and reads config from `/home/Dzeck/.Dzeck`. Always mount your host config directory to `/home/Dzeck/.Dzeck`, not `/root/.Dzeck`.
> If you get **Permission denied**, fix ownership on the host first: `sudo chown -R 1000:1000 ~/.Dzeck`, or pass `--user $(id -u):$(id -g)` to match your host UID. Podman users can use `--userns=keep-id` instead.
>
> [!IMPORTANT]
> Official Docker usage currently means building from this repository with the included `Dockerfile`. Docker Hub images under third-party namespaces are not maintained or verified by HKUDS/Dzeck; do not mount API keys or bot tokens into them unless you trust the publisher.

> [!IMPORTANT]
> The gateway and WebSocket channel default to `host: "127.0.0.1"` in `config.json` (set in `Dzeck/config/schema.py`). Docker `-p` port forwarding cannot reach a container's loopback interface, so for the host or LAN to reach the exposed ports you must set both binds to `0.0.0.0` in `~/.Dzeck/config.json` before starting the container. To serve the bundled WebUI from Docker, enable the WebSocket channel and protect bootstrap with a secret:
>
> ```json
> {
>   "gateway": { "host": "0.0.0.0" },
>   "channels": {
>     "websocket": {
>       "enabled": true,
>       "host": "0.0.0.0",
>       "port": 8765,
>       "tokenIssueSecret": "your-secret-here"
>     }
>   }
> }
> ```
>
> When the WebSocket `host` is `0.0.0.0`, the channel refuses to start unless `token` or `tokenIssueSecret` is also configured — see [`webui/README.md`](../webui/README.md) for details.

### Docker Compose

```bash
docker compose run --rm Dzeck-cli onboard   # first-time setup
vim ~/.Dzeck/config.json                     # add API keys
docker compose up -d Dzeck-gateway           # start gateway
```

```bash
docker compose run --rm Dzeck-cli agent -m "Hello!"   # run CLI
docker compose logs -f Dzeck-gateway                   # view logs
docker compose down                                      # stop
```

### Docker

```bash
# Build the image
docker build -t Dzeck .

# Initialize config (first time only)
docker run -v ~/.Dzeck:/home/Dzeck/.Dzeck --rm Dzeck onboard

# Edit config on host to add API keys
vim ~/.Dzeck/config.json

# Run gateway (connects to enabled channels, e.g. Telegram/Discord/Mochat).
# Mirrors the security caps and port mappings declared in docker-compose.yml:
#   - `--cap-drop ALL --cap-add SYS_ADMIN` + unconfined apparmor/seccomp are required
#     when `tools.exec.sandbox: "bwrap"` is enabled (bwrap needs CAP_SYS_ADMIN for
#     user namespaces). Without them, `bwrap` exits with `clone3: Operation not permitted`.
#   - `-p 8765:8765` exposes the WebSocket channel / WebUI alongside the gateway health
#     endpoint on 18790.
docker run \
  --cap-drop ALL --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  --security-opt seccomp=unconfined \
  -v ~/.Dzeck:/home/Dzeck/.Dzeck \
  -p 18790:18790 -p 8765:8765 \
  Dzeck gateway

# Or run a single command
docker run -v ~/.Dzeck:/home/Dzeck/.Dzeck --rm Dzeck agent -m "Hello!"
docker run -v ~/.Dzeck:/home/Dzeck/.Dzeck --rm Dzeck status
```

## Linux Service

Run the gateway as a systemd user service so it starts automatically and restarts on failure.

**1. Find the Dzeck binary path:**

```bash
which Dzeck   # e.g. /home/user/.local/bin/Dzeck
```

**2. Create the service file** at `~/.config/systemd/user/Dzeck-gateway.service` (replace `ExecStart` path if needed):

```ini
[Unit]
Description=Dzeck Gateway
After=network.target

[Service]
Type=simple
ExecStart=%h/.local/bin/Dzeck gateway
Restart=always
RestartSec=10
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=%h

[Install]
WantedBy=default.target
```

**3. Enable and start:**

```bash
systemctl --user daemon-reload
systemctl --user enable --now Dzeck-gateway
```

**Common operations:**

```bash
systemctl --user status Dzeck-gateway        # check status
systemctl --user restart Dzeck-gateway       # restart after config changes
journalctl --user -u Dzeck-gateway -f        # follow logs
```

If you edit the `.service` file itself, run `systemctl --user daemon-reload` before restarting.

> **Note:** User services only run while you are logged in. To keep the gateway running after logout, enable lingering:
>
> ```bash
> loginctl enable-linger $USER
> ```

## macOS LaunchAgent

Use a LaunchAgent when you want `Dzeck gateway` to stay online after you log in, without keeping a terminal open.

**1. Get the absolute `Dzeck` path:**

```bash
which Dzeck   # e.g. /Users/youruser/.local/bin/Dzeck
```

Use that exact path in the plist. It keeps the Python environment from your install method.

**2. Create `~/Library/LaunchAgents/ai.Dzeck.gateway.plist`:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>ai.Dzeck.gateway</string>

  <key>ProgramArguments</key>
  <array>
    <string>/Users/youruser/.local/bin/Dzeck</string>
    <string>gateway</string>
    <string>--workspace</string>
    <string>/Users/youruser/.Dzeck/workspace</string>
  </array>

  <key>WorkingDirectory</key>
  <string>/Users/youruser/.Dzeck/workspace</string>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>

  <key>StandardOutPath</key>
  <string>/Users/youruser/.Dzeck/logs/gateway.log</string>

  <key>StandardErrorPath</key>
  <string>/Users/youruser/.Dzeck/logs/gateway.error.log</string>
</dict>
</plist>
```

**3. Load and start it:**

```bash
mkdir -p ~/Library/LaunchAgents ~/.Dzeck/logs
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.Dzeck.gateway.plist
launchctl enable gui/$(id -u)/ai.Dzeck.gateway
launchctl kickstart -k gui/$(id -u)/ai.Dzeck.gateway
```

**Common operations:**

```bash
launchctl list | grep ai.Dzeck.gateway
launchctl kickstart -k gui/$(id -u)/ai.Dzeck.gateway   # restart
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/ai.Dzeck.gateway.plist
```

After editing the plist, run `launchctl bootout ...` and `launchctl bootstrap ...` again.

> **Note:** if startup fails with "address already in use", stop the manually started `Dzeck gateway` process first.
