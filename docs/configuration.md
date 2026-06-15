# Configuration

Everything in this deployment is driven by the `.env` file in the repo root
plus a few template files in `config/`. None of the runtime files on the
target VM should be hand-edited — change the source, re-run `install.sh`.

## The two layers

| Layer               | Lives in            | Edited by            | Read by                  |
|---------------------|---------------------|----------------------|--------------------------|
| Source of truth     | `.env`              | you                  | `install.sh`             |
| Generated runtime   | `/etc/nanobot/*`    | `install.sh`         | systemd + nanobot        |
| Template fallbacks  | `config/*`          | you (rare)           | `install.sh`             |

## Knobs in `.env`

| Variable                    | Default                       | What it does                                |
|-----------------------------|-------------------------------|---------------------------------------------|
| `NANOBOT_USER`              | `nanobot`                     | System user that runs the gateway           |
| `NANOBOT_HOME`              | `/var/lib/nanobot`            | Home directory for that user                |
| `NANOBOT_GATEWAY_HOST`      | `0.0.0.0`                     | Bind address for gateway REST/health        |
| `NANOBOT_GATEWAY_PORT`      | `18790`                       | Gateway REST/health port                    |
| `NANOBOT_WEBUI_HOST`        | `0.0.0.0`                     | Bind address for WebUI/WebSocket            |
| `NANOBOT_WEBUI_PORT`        | `8765`                        | WebUI/WebSocket port                        |
| `OLLAMA_HOST`               | `127.0.0.1:11434`             | Where Ollama listens                        |
| `OLLAMA_MODELS_DIR`         | `/var/lib/ollama/models`      | Where Ollama stores model blobs             |
| `OLLAMA_NUM_PARALLEL`       | `1`                           | Concurrent request slots                    |
| `OLLAMA_MAX_LOADED_MODELS`  | `1`                           | Max models resident in VRAM                 |
| `OLLAMA_KEEP_ALIVE`         | `10m`                         | Idle unload timeout                         |
| `OLLAMA_FLASH_ATTENTION`    | `1`                           | Enable flash attention (GPU)                |
| `OLLAMA_MODEL`              | `openbmb/minicpm5:latest`     | Ollama model to pull                        |
| `NANOBOT_MODEL_NAME`        | `minicpm5:latest`             | Alias used inside nanobot config            |
| `OLLAMA_CONTEXT_LENGTH`     | `8192`                        | `num_ctx` baked into the alias              |

## Swapping the model (the common case)

You have two choices:

### A. Edit `.env` and re-run install

```bash
# .env
OLLAMA_MODEL=qwen2.5:7b
NANOBOT_MODEL_NAME=qwen2.5:7b
OLLAMA_CONTEXT_LENGTH=32768
```

```bash
sudo ./install.sh    # idempotent — only re-pulls + rewrites config
```

### B. Use the helper script (no edit)

```bash
sudo ./scripts/update-model.sh qwen2.5:7b 32768
```

This:

1. `ollama pull` the new model
2. `ollama create` a `<leaf>-ctx<num>` alias with the right `num_ctx`
3. Rewrites `config.json` and `nanobot.env`
4. Restarts `nanobot-gateway.service`

The base model name is used as-is; pick anything from
<https://ollama.com/library>.

## Changing ports

Edit `.env`, re-run `install.sh`. The script updates
`/etc/systemd/system/nanobot-gateway.service` and the JSON config
in one pass, then restarts.

## Changing the bind address

`127.0.0.1` instead of `0.0.0.0` is the right choice when:

- The VM is behind a reverse proxy (nginx/Caddy/Traefik) that
  terminates TLS.
- You're SSH-tunneling in (`ssh -L 8765:127.0.0.1:8765 vm`).

If you go back to `127.0.0.1`, the gateway will accept the missing
`tokenIssueSecret` and you can delete the one in `nanobot.env`.

## Auth on the WebUI

`nanobot-gateway` requires either `token` or `tokenIssueSecret` in
the WebSocket channel config when the host is `0.0.0.0`. We bake in
`tokenIssueSecret` because it's a one-time setup, not a per-user token.

**Production note:** the WebUI on `0.0.0.0:8765` is **not** user-authenticated
out of the box — `tokenIssueSecret` only signs tokens the WebUI itself
mints. If you expose the VM to the internet, you MUST front it with a
reverse proxy that enforces authentication. See `docs/troubleshooting.md`.

## Where the agent's memory and skills live

Everything the agent accumulates is under:

```
/var/lib/nanobot/.nanobot/workspace/
├── memory/          ← conversation history, MEMORY.md
├── skills/          ← custom skills you drop in
├── sessions/        ← session state
└── AGENTS.md        ← (optional) root agent instructions
```

`/var/lib/nanobot` is the home of the `nanobot` system user. To back up
the agent, archive that whole tree.
