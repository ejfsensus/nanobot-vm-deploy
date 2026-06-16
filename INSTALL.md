# Installation Guide

Detailed, step-by-step, for someone staring at a fresh VM or a fresh
Lightning AI Studio. The installer auto-detects the platform and
dispatches accordingly.

## Which platform are you on?

| Target                         | Detected by           | See section  |
|--------------------------------|-----------------------|--------------|
| **Linux VM** (Ubuntu, Debian, RHEL, Fedora, Arch, …) | No `/teamspace` directory | [§ A — Linux VM](#a--linux-vm) |
| **Lightning AI Studio** (free or paid) | `/teamspace` directory present | [§ B — Lightning Studio](#b--lightning-ai-studio) |

The same `install.sh` works for both. If it sees `/teamspace`, it
delegates to `platform/lightning/scripts/install.sh`. Otherwise it runs
the VM installer.

---

## A. Linux VM

## 1. Get the repo onto the VM

```bash
# Option A — clone your fork
git clone https://github.com/<you>/nanobot-vm-deploy.git
cd nanobot-vm-deploy

# Option B — bootstrap via curl (uses baked-in defaults; no MCP/skills)
curl -fsSL https://raw.githubusercontent.com/<you>/nanobot-vm-deploy/main/install.sh | sudo bash
```

**Strongly prefer Option A.** It gives you the `mcp/`, `skills/`,
and `docs/` directories so you can amend the deployment without
re-piping a script.

## 2. (Optional) Customise

```bash
cp .env.example .env
$EDITOR .env
```

The only thing most people change is the model:

```bash
# .env
OLLAMA_MODEL=qwen2.5:7b
NANOBOT_MODEL_NAME=qwen2.5:7b
OLLAMA_CONTEXT_LENGTH=32768
```

See [`docs/configuration.md`](docs/configuration.md) for every knob.

## 3. Run the installer

```bash
sudo ./install.sh
```

What happens (with approximate timing on a 2-vCPU / 4GB VM):

| Step                                                | Time      |
|-----------------------------------------------------|-----------|
| System package install                              | 30 s      |
| Create `nanobot` system user                        | < 1 s     |
| Install Ollama                                      | 30 s      |
| Pull `openbmb/minicpm5:latest`                      | 1–3 min   |
| Create venv at `/opt/nanobot/venv`                  | 5 s       |
| `pip install nanobot-ai` (40+ deps)                 | 1–2 min   |
| Write `config.json` + `/etc/nanobot/*`              | < 1 s     |
| Write + start `nanobot-gateway.service`             | 1 s       |
| Run `post-install.sh`                               | varies    |

## 4. Verify

```bash
sudo ./scripts/status.sh
```

You should see ~10 green checks and `everything looks healthy`.

## 5. Use it

- **WebUI** — open `http://<vm-ip>:8765/` in a browser.
  The bundled WebUI connects to the WebSocket channel on the same port.
- **CLI** — `sudo -u nanobot -E /opt/nanobot/venv/bin/nanobot agent -m "hello"`
- **Health** — `curl http://<vm-ip>:18790/health`
- **Logs** — `journalctl -u nanobot-gateway -f`

## 6. (Optional) Add custom MCP servers / skills

- MCP: drop folders into `mcp/servers/`, see
  [`docs/adding-mcp-servers.md`](docs/adding-mcp-servers.md)
- Skills: drop folders into `skills/`, see
  [`docs/adding-skills.md`](docs/adding-skills.md)

Then re-run `sudo ./install.sh`. The post-install hook wires them in.

## 7. (Recommended) Front the WebUI with a reverse proxy

The WebUI is a WebSocket app. nginx / Caddy / Traefik all handle it
fine. See [`docs/troubleshooting.md`](docs/troubleshooting.md#exposing-the-webui-to-the-internet--please-dont-but-if-you-must)
for a copy-pasteable nginx config.

## Troubleshooting

If anything goes wrong, start with:

```bash
sudo ./scripts/status.sh
sudo journalctl -u nanobot-gateway -n 200 --no-pager
sudo journalctl -u ollama          -n 200 --no-pager
```

If those don't surface it, [`docs/troubleshooting.md`](docs/troubleshooting.md)
has the worked examples for the common failure modes.

## Re-running

The installer is **idempotent**. Re-running it on an already-provisioned
VM is safe — it only touches files that have changed and restarts the
affected services. Use this as your "apply my latest config" command.

## Uninstalling

```bash
sudo ./scripts/uninstall.sh           # keep ollama + models
sudo ./scripts/uninstall.sh --full    # nuke ollama + models too
```

---

## B. Lightning AI Studio

Detailed Lightning-specific walkthrough is in
[`docs/lightning.md`](docs/lightning.md). The 30-second version:

### 0. Prerequisites

- A free Lightning account at <https://lightning.ai>
- A new CPU Studio (4 vCPU, 16 GB is the free tier; that runs
  `minicpm5` on CPU just fine)

### 1. Get the repo into the Studio

In the Studio's web terminal:

```bash
git clone https://github.com/<you>/nanobot-vm-deploy.git
cd nanobot-vm-deploy
cp .env.example .env       # edit if you want a different model
```

### 2. Run the Lightning installer

```bash
bash platform/lightning/scripts/install.sh
```

This:
1. Installs Ollama if missing
2. Pulls `openbmb/minicpm5:latest` (~700 MB)
3. Creates a `minicpm5-ctx8192` alias with `num_ctx=8192`
4. Installs `nanobot-ai` into a venv under `/teamspace/studios/<studio>/venv/`
5. Writes `~/.nanobot/config.json` (Ollama + WebSocket on 8765)
6. Stages `.lightning_studio/on_start.sh` in your Studio home
7. Stages `.lightning_studio/.studiorc` so manual commands see the env

### 3. Bring it up

Either restart the Studio (so `on_start.sh` runs from a clean state), or
bring it up immediately:

```bash
bash /teamspace/studios/<studio>/scripts/start.sh
```

### 4. Expose the WebUI

1. Click the **plug-ins** icon (top right of the Studio).
2. **Port viewer** → **Add port** → port `8765` → **Open**.
3. Lightning prints a public URL like `https://8765-<hash>.lightningapps.ai/`.
4. Open it. That's your WebUI.

If you want to share it with other people, use **API builder** instead
(token or basic auth).

### 5. Day-to-day

| Task                            | Command                                                       |
|---------------------------------|---------------------------------------------------------------|
| Start / restart                 | `bash /teamspace/studios/<studio>/scripts/start.sh`           |
| Stop                            | `bash /teamspace/studios/<studio>/scripts/stop.sh`            |
| Health check                    | `bash /teamspace/studios/<studio>/scripts/status.sh`          |
| Tail logs                       | `tail -f /teamspace/studios/<studio>/logs/{on_start,nanobot,ollama,keepalive}.log` |
| One-shot agent command          | `nanobot agent -m "hello"`                                    |
| Survive the 4-hour restart      | Automatic — `on_start.sh` re-runs on every launch             |
| Avoid the 10-min idle-sleep     | `keep_alive.sh` pings the WebUI every 2 min                   |

### 6. Re-running

```bash
# edit .env if needed
bash platform/lightning/scripts/install.sh    # idempotent
```

### 7. Tearing it down

```bash
bash /teamspace/studios/<studio>/scripts/stop.sh   # stop processes
rm -rf /teamspace/studios/<studio>                  # wipe the install
# then delete the Studio from the Lightning UI
```

See [`docs/lightning.md`](docs/lightning.md) for the full guide
including troubleshooting, updating nanobot, and using the API Builder
plugin.
