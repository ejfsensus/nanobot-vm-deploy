# nanobot-vm-deploy

**One-command provisioning for a brand-new Linux VM that runs
[HKUDS/nanobot](https://github.com/HKUDS/nanobot) backed by a
local Ollama model — with the bundled WebUI served out of the box.**

Defaults to [`openbmb/minicpm5:latest`](https://ollama.com/openbmb/minicpm5)
(1B params, 128k context, ~700MB on disk). Swap to any other Ollama
model by editing one line of `.env` and re-running the installer.

Designed to be **forked and amended** — drop your own MCP servers and
nanobot skills into `mcp/` and `skills/`, commit, re-run, done.

**Targets:** Linux VMs (default) **and** [Lightning AI
Studios](https://lightning.ai/docs/overview/ai-studio) (free CPU tier
supported). The installer auto-detects which one it's on and dispatches
to the right platform overlay. See
[`platform/lightning/README.md`](platform/lightning/README.md).

---

## TL;DR — get a working agent in 4 commands

```bash
# 1. Get the repo onto the VM
git clone https://github.com/<you>/nanobot-vm-deploy.git
cd nanobot-vm-deploy

# 2. (Optional) customise — defaults work as-is
cp .env.example .env
$EDITOR .env

# 3. Install
sudo ./install.sh

# 4. Open the WebUI
xdg-open http://<vm-ip>:8765/        # or just paste the URL in a browser
```

That's it. The installer:

- Installs system deps + Python 3.11 venv
- Installs **Ollama** (and pulls your chosen model)
- Installs **nanobot-ai** into `/opt/nanobot/venv`
- Writes a pre-configured `config.json` (Ollama provider + WebSocket WebUI on `:8765`)
- Registers `ollama.service` and `nanobot-gateway.service` with systemd
- Runs the **post-install hook** so your custom MCP servers and skills get wired in
- Prints a final report with URLs, paths, and the next commands to run

Total time: ~3–5 min on a fresh Ubuntu 22.04 / Debian 12 VM with network access.

---

## What runs where

```
Browser  ──►  WebUI on :8765  ──►  nanobot-gateway.service  ──►  ollama.service
                                          │                            │
                                   /var/lib/nanobot            /var/lib/ollama
                                   (config, workspace,         (model blobs)
                                    memory, skills)
```

See [`docs/architecture.md`](docs/architecture.md) for the full picture.

## Repo layout

```
nanobot-vm-deploy/
├── install.sh                  ← platform-aware entry point (auto-dispatches VM or Lightning)
├── .env.example                ← every knob you might want to change
├── config/
│   ├── nanobot.config.json     ← reference config (install.sh generates the real one)
│   ├── ollama.env              ← Ollama env template
│   └── nanobot-gateway.service ← systemd unit template (VM only)
├── scripts/
│   ├── status.sh               ← health check (VM)
│   ├── update-model.sh         ← swap the model
│   ├── uninstall.sh            ← clean removal
│   ├── post-install.sh         ← YOUR HOOK for custom MCP/skills
│   └── lib/                    ← logging + OS detection + pkg helpers
├── platform/
│   ├── README.md               ← about the platform/ overlay system
│   └── lightning/              ← Lightning.ai Studio variation
│       ├── .lightning_studio/  ← on_start.sh + .studiorc
│       ├── scripts/            ← install / start / stop / status / keep_alive
│       ├── config/
│       └── README.md
├── mcp/servers/                ← drop custom MCP servers here
├── skills/                     ← drop custom nanobot skills here
└── docs/                       ← architecture, configuration, MCP, skills, troubleshooting, lightning
```

## Common operations

**On a VM:**

| You want to…                          | Do this                                                  |
|---------------------------------------|----------------------------------------------------------|
| Check it's healthy                    | `sudo ./scripts/status.sh`                               |
| Use a different model                 | `sudo ./scripts/update-model.sh qwen2.5:7b 32768`        |
| Change ports / bind addresses         | Edit `.env`, then `sudo ./install.sh`                    |
| Add an MCP server                     | Drop a folder in `mcp/servers/`, then `sudo ./install.sh`|
| Add a skill                           | Drop a folder in `skills/`, then `sudo ./install.sh`     |
| See live logs                         | `journalctl -u nanobot-gateway -f`                       |
| Tail Ollama logs                      | `journalctl -u ollama -f`                                |
| Run a one-shot agent command          | `sudo -u nanobot -E /opt/nanobot/venv/bin/nanobot agent -m "hello"` |
| Wipe everything and start over        | `sudo ./scripts/uninstall.sh --full && sudo ./install.sh` |

**On Lightning AI Studio** (auto-detected, but you can also invoke
`platform/lightning/scripts/install.sh` directly):

| You want to…                          | Do this                                                  |
|---------------------------------------|----------------------------------------------------------|
| Check it's healthy                    | `bash /teamspace/studios/<studio>/scripts/status.sh`     |
| Bring the stack up                    | `bash /teamspace/studios/<studio>/scripts/start.sh`      |
| Bring it down cleanly                 | `bash /teamspace/studios/<studio>/scripts/stop.sh`       |
| Expose the WebUI to the internet      | Open **Port Viewer** plugin → add port 8765 → **Open**   |
| Expose the WebUI with auth            | Open **API Builder** plugin → new API → token / basic    |
| One-shot agent command                | `nanobot agent -m "hello"` (binary is on `$PATH`)        |
| Survive the 4-hour restart            | It just works — `on_start.sh` re-runs on every launch    |
| Prevent the 10-min idle-sleep         | `keep_alive.sh` pings the WebUI every 2 min              |

## Requirements

- Linux VM (Ubuntu 22.04+ / Debian 12+ / RHEL 9+ / Fedora / Arch)
- `sudo` or root
- Outbound HTTPS to `pypi.org`, `ollama.com`, and the Ollama registry
- ~1GB free disk for the model, ~500MB for the nanobot venv
- A GPU is **not** required. Ollama runs on CPU; just slower. For the
  default `minicpm5` (1B) the CPU experience is fine.

## Security note

The WebUI binds to `0.0.0.0:8765` by default so you can reach it
from your laptop. **Do not expose this port to the public internet
without putting a reverse proxy with authentication in front of it.**
See [`docs/troubleshooting.md`](docs/troubleshooting.md#exposing-the-webui-to-the-internet--please-dont-but-if-you-must).

## License

MIT — see [`LICENSE`](LICENSE).
