# Deploying on Lightning AI Studios

Detailed guide for the [Lightning AI Studio](https://lightning.ai/docs/overview/ai-studio)
variation of this deploy. If you want a 30-second quickstart, see
[`platform/lightning/README.md`](../platform/lightning/README.md).

## 1. Lightning Studio characteristics

Studios are essentially cloud-hosted containers with a web IDE. The
constraints that matter for this deploy:

### Free tier (good enough for nanobot + minicpm5)
- 1 free CPU Studio
- 4 vCPU, 16 GB RAM
- 15 free credits / month
- 1B-param CPU inference is comfortable here

### Persistence
- `/teamspace/` is mounted as a persistent drive (Lightning Drive) and
  survives Studio sleep, restart, and even deletion of the underlying
  compute.
- The Studio home is `/teamspace/studios/<studio-name>/`. Files there
  are yours across sessions.
- `/tmp` and `/root` are **ephemeral** — never put state there.
- After 10 min of "inactivity" the Studio auto-sleeps; the data still
  persists, but the running processes die and the Studio costs no
  credits.

### On-start hook
Lightning runs `.lightning_studio/on_start.sh` from the Studio home at
every launch (initial start, wake-from-sleep, restart). The script runs
from a bash login shell so environment variables set in
`.lightning_studio/.studiorc` are picked up.

### Background execution
Processes started with `nohup` continue running after the browser tab
closes. You don't need tmux / screen.

### Ports
- No firewall to configure — you can bind to `0.0.0.0`.
- The **Port Viewer** plugin exposes a port to a public URL of the
  form `https://<port>-<studio-id>.lightningapps.ai/`.
- The **API Builder** plugin can front a port with **token** or
  **basic** auth (recommended for anything public).

### 4-hour restart (free tier)
Free Studios are recycled roughly every 4 hours; on each cycle the
compute is replaced and `on_start.sh` re-runs against a clean
container. `/teamspace` content is preserved, but anything not on
`/teamspace` is gone.

Our installer copes with this because:
- `on_start.sh` is idempotent — already-running services aren't
  restarted.
- The venv lives under `/teamspace/<install-root>/venv` and survives.
- The model lives under `/teamspace/<install-root>/ollama/models` and
  survives.
- Config + env live under `/teamspace/<install-root>/` and survive.

## 2. End-to-end deployment

### Step 1: Create a Studio
1. Sign in at <https://lightning.ai>.
2. Go to **Studios** → **New Studio**.
3. Choose **CPU** (4 vCPU, 16 GB) for the free tier.
4. Name it `nanobot` (or whatever; the installer auto-detects).
5. Skip the template — we bring our own.

### Step 2: Get the repo in
In the Studio's web terminal:

```bash
git clone https://github.com/<you>/nanobot-vm-deploy.git
cd nanobot-vm-deploy
```

Or upload the repo as a zip via the file browser.

### Step 3: One-time install
```bash
cp .env.example .env
# (optional) edit .env — see "Configuration" below
bash platform/lightning/scripts/install.sh
```

This:
1. Installs Ollama if missing
2. Pulls `openbmb/minicpm5:latest` (~700 MB)
3. Creates a `minicpm5-ctx8192` alias with `num_ctx=8192`
4. Installs `nanobot-ai` into a venv under
   `/teamspace/studios/<studio>/venv/`
5. Writes `~/.nanobot/config.json` (loopback Ollama + WebSocket on 8765)
6. Stages `.lightning_studio/on_start.sh` in the Studio home
7. Stages `.lightning_studio/.studiorc` so manual commands see the env

### Step 4: First launch
Either restart the Studio (so `on_start.sh` runs from a clean state) or
bring it up immediately:

```bash
bash /teamspace/studios/<studio>/scripts/start.sh
```

Wait ~10s for Ollama to start, then check:

```bash
bash /teamspace/studios/<studio>/scripts/status.sh
```

All checks should be green.

### Step 5: Expose the WebUI
1. In the Studio's web UI, click the **plug-ins** icon (top right).
2. Open **Port viewer** → **Add port**.
3. Port: `8765` → **Add** → **Open**.
4. Lightning prints a public URL like
   `https://8765-<hash>.lightningapps.ai/`.
5. Open it — that's your WebUI.

### Step 6: Add auth (if you intend to share)
1. **Plug-ins** → **API builder** → **Create new API**.
2. Command: `bash /teamspace/studios/<studio>/scripts/start.sh`.
3. Pick **Token** or **Basic** auth, set a strong secret.
4. Lightning fronts the WebUI with auth and gives you a clean URL.

The WebUI's own `tokenIssueSecret` (in `nanobot.env`) is separate and
only governs WebSocket token issuance — it doesn't auth the user.

## 3. Configuration

Edit `.env` in the repo root, then re-run
`bash platform/lightning/scripts/install.sh`. The installer is
idempotent and only touches what changed.

Useful `.env` overrides:

```bash
# A different model
OLLAMA_MODEL=qwen2.5:7b
NANOBOT_MODEL_NAME=qwen2.5:7b
OLLAMA_CONTEXT_LENGTH=32768

# Custom install location (default: /teamspace/studios/${STUDIO_NAME})
NANOBOT_INSTALL_ROOT=/teamspace/studios/my-nanobot

# Ping cadence for the keep-alive (seconds)
KEEPALIVE_PING_INTERVAL=120
```

## 4. Day-to-day operations

All from the Studio's web terminal:

| Task                              | Command                                                       |
|-----------------------------------|---------------------------------------------------------------|
| Start the stack                   | `bash /teamspace/studios/<studio>/scripts/start.sh`           |
| Stop the stack                    | `bash /teamspace/studios/<studio>/scripts/stop.sh`            |
| Health check                      | `bash /teamspace/studios/<studio>/scripts/status.sh`          |
| Tail nanobot log                  | `tail -f /teamspace/studios/<studio>/logs/nanobot.log`        |
| Tail Ollama log                   | `tail -f /teamspace/studios/<studio>/logs/ollama.log`         |
| Tail keep-alive log               | `tail -f /teamspace/studios/<studio>/logs/keepalive.log`      |
| One-shot CLI agent call           | `nanobot agent -m "hello"`                                    |
| Get the public URL of the WebUI   | Look in the **Port viewer** plugin UI                         |

The `nanobot` binary is on `$PATH` in new shells (the `.studiorc`
puts it there), so `nanobot agent -m "..."`, `nanobot onboard`, etc.
all just work.

## 5. Common failure modes

### "Gateway won't start — refuses to bind 0.0.0.0 without tokenIssueSecret"
Re-run the installer. It always regenerates the secret.

### "Studio auto-sleeps after 10 min"
`keep_alive.sh` should prevent this. Check
`tail -f logs/keepalive.log`. If you see the ping succeeding (HTTP
200/404), but the Studio is still sleeping, you're on a paid tier
where Lightning ignores activity — disable auto-sleep in Studio
settings, or set `KEEPALIVE_PING_INTERVAL=0` to make it pure watchdog.

### "Studio restarted and ollama is empty"
You probably stored Ollama models in `/root/.ollama` (the default).
The installer moves them to
`/teamspace/studios/<studio>/ollama/models`. Re-pull the model:
```bash
OLLAMA_MODELS=/teamspace/studios/<studio>/ollama/models ollama pull <model>
```

### "Port 8765 is already in use"
Another process inside the Studio is using 8765. Check `ss -tlnp | grep
8765` and either kill that process or change `NANOBOT_WEBUI_PORT` in
`.env` and re-install.

### "I want to use a bigger model but it OOMs"
Free Studios have 16 GB RAM and no GPU. Big models (e.g. `qwen2.5:32b`)
won't fit. Either:
- Stay on a small model (≤3B)
- Switch to a paid Studio with GPU
- Use the API Builder plugin + an external API (OpenAI, Anthropic,
  etc.) instead of local Ollama

### "I want to share this with someone else"
1. Front the WebUI with the API Builder plugin (token or basic auth).
2. Share the resulting URL + credentials.
3. The `tokenIssueSecret` in `nanobot.env` is the *gateway's* secret
   for WebSocket token issuance — not user auth. The proxy is what
   authenticates the user.

## 6. Updating nanobot

```bash
# from a Studio terminal, with the venv active
source /teamspace/studios/<studio>/venv/bin/activate
pip install --upgrade nanobot-ai
deactivate
# then restart the gateway so the new version is loaded
bash /teamspace/studios/<studio>/scripts/stop.sh
bash /teamspace/studios/<studio>/scripts/start.sh
```

Or just re-run the installer; it will `pip install --upgrade` if the
venv exists.

## 7. Tearing it down

```bash
bash /teamspace/studios/<studio>/scripts/stop.sh        # stop processes
rm -rf /teamspace/studios/<studio>                       # wipe the install
# then in the Lightning UI, delete the Studio
```
