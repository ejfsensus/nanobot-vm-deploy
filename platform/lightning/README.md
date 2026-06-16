# Lightning.ai Studio variation

Deploys **nanobot + Ollama + the bundled WebUI** on a [Lightning AI
Studio](https://lightning.ai/docs/overview/ai-studio) (free CPU tier
supported).

## What's different from the standard VM deploy

| Concern              | VM deploy (top-level)           | Lightning variation (`platform/lightning/`)                  |
|----------------------|---------------------------------|-------------------------------------------------------------|
| Service manager      | `systemd` units                 | `nohup` + PID files (no systemd in Studios)                 |
| Install paths        | `/opt/nanobot`, `/var/lib/...`  | `/teamspace/studios/<studio>/...` — survives restarts        |
| Config locations     | `/etc/nanobot/*`                | `<install-root>/nanobot.env` + `<install-root>/.nanobot/`   |
| Auto-start           | `systemctl enable`              | `.lightning_studio/on_start.sh` hook                        |
| Idle sleep           | n/a                             | `scripts/keep_alive.sh` ping loop                           |
| Expose to internet   | Firewall / nginx                | **Port Viewer** plugin (or **API Builder** for auth)        |
| Process supervision  | `Restart=always`                | Watchdog inside `keep_alive.sh`                             |
| Logs                 | `journalctl`                    | Rolling `.log` files under `<install-root>/logs/`           |

Everything else — the nanobot config format, the Ollama model, the MCP /
skills wiring — is identical to the base deploy. The platform variation
is a **glue layer**, not a reimplementation.

## Quick start

1. **Create a Studio** at <https://lightning.ai/studios>:
   - Name it `nanobot` (or whatever you like — the installer auto-detects)
   - Pick a CPU machine (free tier is fine: 4 vCPU, 16 GB RAM)
   - Skip the template chooser — we bring our own

2. **Get this repo into the Studio**. Either:
   - In the Studio's web terminal, `git clone` your fork, OR
   - Upload the repo as a `.zip` via the Lightning file browser and unzip

3. **One-time install.** From the Studio's web terminal:
   ```bash
   cd <repo-root>
   cp .env.example .env                # edit if you want a different model
   bash platform/lightning/scripts/install.sh
   ```
   This pulls `openbmb/minicpm5:latest`, sets up the venv, writes the
   config, and stages `.lightning_studio/on_start.sh` for next launch.

4. **First start.** Either restart the Studio (so `on_start.sh` runs) or
   bring it up immediately from the terminal:
   ```bash
   bash <install-root>/scripts/start.sh
   ```
   Default install root: `/teamspace/studios/nanobot/`.

5. **Expose the WebUI.** Click the plug-ins icon (top right of the Studio) →
   **Port viewer** → **Add port 8765** → **Open**. Lightning prints a
   public URL like `https://8765-<id>.lightningapps.ai/`.

6. **Done.** Bookmark the URL. The WebUI survives Studio sleep, cold
   starts, and the 4-hour restart cycle (the on-start hook re-runs on
   every launch).

## File map

```
platform/lightning/
├── README.md                      ← you are here
├── .lightning_studio/
│   ├── on_start.sh                ← the on-launch hook
│   └── .studiorc                  ← env vars for new shells
├── scripts/
│   ├── install.sh                 ← one-time installer
│   ├── start.sh                   ← bring stack up manually
│   ├── stop.sh                    ← bring stack down cleanly
│   ├── status.sh                  ← health check
│   └── keep_alive.sh              ← ping loop + process watchdog
└── config/                        ← config templates (if you need to fork)
```

## What `on_start.sh` does

Runs at every Studio launch (incl. wake-from-sleep). It's idempotent:

1. Sources `<install-root>/nanobot.env` to pick up model + ports + paths
2. Starts `ollama serve` in the background (skipped if already running)
3. Starts `nanobot gateway` in the background (skipped if already running)
4. Starts `scripts/keep_alive.sh` (skipped if already running)
5. Logs everything to `<install-root>/logs/on_start.log`

## What `keep_alive.sh` does

Two concurrent jobs in a single process:

- **Anti-sleep ping** — every 2 minutes, `curl http://localhost:8765/`.
  Lightning sees this as activity and won't auto-sleep the Studio.
- **Watchdog** — if `nanobot` or `ollama` die, restart them.

Tunable via env: `KEEPALIVE_PING_INTERVAL=60` for more aggressive
keep-awake (or 600 if you're on a paid tier with auto-sleep disabled).

## Persistent vs ephemeral

| Path                                       | Lifetime          |
|--------------------------------------------|-------------------|
| `/teamspace/studios/<this_studio>/`        | PERSISTENT ✓      |
| `${HOME}/.lightning_studio/on_start.sh`    | PERSISTENT ✓ (mirrored from the install root) |
| `${HOME}/.nanobot/`, `${HOME}/.ollama/`    | PERSISTENT ✓ (within the Studio home) |
| `/tmp`                                     | EPHEMERAL ✗       |
| `/root`                                    | EPHEMERAL ✗ (wiped on Studio restart) |
| in-RAM state of `ollama` and `nanobot`     | Lost on Studio restart — `on_start.sh` re-launches |

## Exposing the WebUI

Lightning gives you three exposure paths, in increasing order of effort:

### 1. Port Viewer (default — no auth)
1. Plug-ins icon → **Port viewer**
2. Add port `8765`
3. Click **Open**

URL looks like `https://8765-<random>.lightningapps.ai/`.
The WebUI's own `tokenIssueSecret` is in `nanobot.env` if you want to
expose the WebSocket token machinery.

### 2. API Builder (with auth)
1. Plug-ins icon → **API builder**
2. Create a new API → command `bash <install-root>/scripts/start.sh`
3. Choose **Token** or **Basic** authentication
4. Lightning fronts the WebUI with auth and gives you a clean URL

This is what you want if you intend to share the agent with other people.

### 3. SSH tunnel (for personal use)
Lightning lets you SSH into the Studio. Forward the port locally:
```bash
ssh -L 8765:127.0.0.1:8765 <studio>
```
Then open `http://localhost:8765/` in your local browser. Easiest if
you're the only user.

## Why a `keep_alive.sh`?

The free tier auto-sleeps Studios after **10 minutes of inactivity**.
A running server counts as activity, so the gateway itself should be
enough to keep the Studio awake. `keep_alive.sh` is a safety net:

- The `ollama` and `nanobot` PIDs occasionally die (OOM, manual kill,
  Lightning maintenance, the 4-hour restart). `keep_alive.sh` detects
  that and brings them back.
- It pings the WebUI on a 2-minute cadence, so even when you're not
  actively using the agent the Studio doesn't slip into sleep mode.

If you're on a paid tier, you can disable auto-sleep entirely and
`keep_alive.sh` becomes optional. Set `KEEPALIVE_PING_INTERVAL=0` in
`.env` to make it a pure watchdog (no pings).

## Troubleshooting

Run from the Studio terminal:
```bash
bash /teamspace/studios/<this-studio>/scripts/status.sh
```

If something is red, tail the relevant log:
```bash
tail -f /teamspace/studios/<this-studio>/logs/on_start.log
tail -f /teamspace/studios/<this-studio>/logs/nanobot.log
tail -f /teamspace/studios/<this-studio>/logs/keepalive.log
```

If nothing helps, restart the Studio from the Lightning UI — that
forces `on_start.sh` to run from a clean slate.

See [`../../docs/lightning.md`](../../docs/lightning.md) for the full
Lightning-specific guide.
