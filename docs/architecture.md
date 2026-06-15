# Architecture

## Bird's-eye view

```
┌──────────────────────────────────────────────────────────────┐
│  Browser (WebUI)                                             │
│   http://<vm>:8765/                                          │
└────────────┬─────────────────────────────────────────────────┘
             │ WebSocket (token-auth via tokenIssueSecret)
             ▼
┌──────────────────────────────────────────────────────────────┐
│  nanobot-gateway.service  (systemd)                          │
│  ────────────────────────                                    │
│  • runs as user `nanobot`                                    │
│  • serves the bundled WebUI on port 8765 (WebSocket channel) │
│  • exposes REST /health on port 18790                        │
│  • reads /var/lib/nanobot/.nanobot/config.json               │
│  • executes /opt/nanobot/venv/bin/nanobot gateway            │
└────────────┬─────────────────────────────────────────────────┘
             │ OpenAI-compatible HTTP
             │  http://127.0.0.1:11434/v1/chat/completions
             ▼
┌──────────────────────────────────────────────────────────────┐
│  ollama.service  (systemd)                                   │
│  ─────────────────────                                       │
│  • runs as user `ollama`                                     │
│  • binds 127.0.0.1:11434                                     │
│  • stores models in /var/lib/ollama/models                   │
│  • loads model into RAM/VRAM on first request               │
└────────────┬─────────────────────────────────────────────────┘
             │ llama.cpp
             ▼
┌──────────────────────────────────────────────────────────────┐
│  Model:  openbmb/minicpm5:latest                             │
│           └─ alias:  minicpm5-ctx8192  (num_ctx=8192)        │
└──────────────────────────────────────────────────────────────┘
```

## Filesystem layout after install

```
/opt/nanobot/venv/                       ← Python venv with nanobot-ai + deps
/usr/local/bin/nanobot                   ← symlink → /opt/nanobot/venv/bin/nanobot

/var/lib/nanobot/                        ← $NANOBOT_HOME (system user home)
└── .nanobot/
    ├── config.json                      ← nanobot runtime config
    └── workspace/                       ← agent scratch space
        ├── AGENTS.md                    ← (optional) agent instructions
        ├── memory/                      ← (auto) conversation memory
        └── skills/                      ← auto-discovered skills
            └── <name>/SKILL.md

/etc/nanobot/
├── nanobot.env                          ← generated env (model, ports, secret)
└── ollama.env                           ← generated ollama env (host, models, gpu)

/etc/systemd/system/
├── ollama.service                       ← (patched) sources ollama.env
└── nanobot-gateway.service              ← ours
```

## Startup order

On `systemctl start nanobot-gateway.service`:

1. systemd resolves the unit's `Requires=ollama.service` and
   `After=ollama.service` directives.
2. If `ollama` is not yet active, systemd starts it.
3. nanobot-gateway starts, which:
   - Sources `/etc/nanobot/nanobot.env` (picks up `HOME`, etc.)
   - Executes `/opt/nanobot/venv/bin/nanobot gateway`
4. The gateway reads `/var/lib/nanobot/.nanobot/config.json`,
   starts the WebSocket channel on `0.0.0.0:8765`, and exposes
   `/health` on `0.0.0.0:18790`.
5. On the first chat request, nanobot calls Ollama at
   `http://127.0.0.1:11434/v1/chat/completions`. Ollama lazily loads
   the model blob (no startup cost).

## Why a dedicated system user?

- **Least privilege.** The gateway doesn't need to write outside
  `/var/lib/nanobot` — `ProtectSystem=full` enforces that.
- **No surprise root code execution.** A compromised agent prompt
  cannot rewrite `/etc/passwd` or install system packages.
- **Clean uninstall.** `userdel -r nanobot` removes the home dir
  and every cached conversation, memory, and downloaded skill in
  one shot.

## Why a venv at /opt?

- `/opt` is the FHS-correct place for add-on application software.
- A venv keeps the system `python3` clean and lets us `pip install`
  ~40 dependencies without polluting the OS package manager.
- Symlinking `/opt/nanobot/venv/bin/nanobot` to `/usr/local/bin/`
  gives every user (and root) a stable `nanobot` on `$PATH`.

## Configuration flow

```
.env  (repo, edit me)
  │
  │  sourced by
  ▼
install.sh
  │  templates
  ▼
/etc/nanobot/nanobot.env
/etc/nanobot/ollama.env
/var/lib/nanobot/.nanobot/config.json
/etc/systemd/system/nanobot-gateway.service
  │
  │  sourced/read by
  ▼
systemd → nanobot-gateway → Ollama
```

To change anything, edit `.env` (or the template files) and re-run
`sudo ./install.sh`. The script is idempotent — it only rewrites
what's different and restarts the affected services.
