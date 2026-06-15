# Installation Guide

Detailed, step-by-step, for someone staring at a fresh VM.

## 0. Prerequisites

You need:

| Requirement   | Why                                                     | How to verify                  |
|---------------|---------------------------------------------------------|--------------------------------|
| Linux         | This is a Linux deploy                                  | `uname -a`                     |
| sudo / root   | The installer creates system users and systemd units   | `sudo -n true`                 |
| Python 3.11+  | nanobot requires it                                     | `python3 --version`            |
| curl          | Fetches the Ollama installer and pip wheels             | `curl --version`               |
| ~2 GB free    | nanobot venv + model + workspace                        | `df -h /`                      |
| Outbound HTTPS| PyPI + Ollama registry + GitHub                         | `curl -I https://pypi.org`     |

The installer will `apt-get install` (or equivalent) anything missing
on Debian / Ubuntu / RHEL / Fedora / Arch / openSUSE / Alpine.

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
