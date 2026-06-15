# Troubleshooting

Quick health check:

```bash
sudo ./scripts/status.sh
```

If that passes, skip this doc. If something's red, start here.

## Common symptoms

### `status.sh` reports "ollama API does not respond"

```bash
sudo systemctl status ollama
sudo journalctl -u ollama -n 100 --no-pager
```

Common causes:

- **Port mismatch.** `OLLAMA_HOST` in `/etc/nanobot/ollama.env` ≠
  what `nanobot.config.json` has. Both come from `.env` — re-run
  `sudo ./install.sh` to re-sync.
- **Ollama not installed.** The `install.sh --skip-ollama` flag
  suppresses the install; if you used it, install Ollama yourself
  and make sure it binds the right address.
- **OOM-killed.** Check `dmesg | tail -50` — Ollama is the
  usual victim because models are huge.

### `status.sh` reports "service nanobot-gateway is active" FAIL

```bash
sudo systemctl status nanobot-gateway
sudo journalctl -u nanobot-gateway -n 200 --no-pager
```

Most common reason: the gateway refuses to start because the
WebSocket channel is bound to `0.0.0.0` with no `tokenIssueSecret`.

Fix: edit `.env`, re-run `sudo ./install.sh`. (If `.env` is missing
the secret, `install.sh` regenerates one and writes it to
`/etc/nanobot/nanobot.env`.)

### WebUI loads but the agent times out / 500s

```bash
sudo journalctl -u nanobot-gateway -f
# in another shell, hit the WebUI
```

If you see `connection refused` to Ollama:

```bash
curl -v http://127.0.0.1:11434/api/tags
```

If Ollama responds but nanobot still fails, check that the
model alias actually exists:

```bash
ollama list
```

The `NANOBOT_MODEL_NAME` in `nanobot.env` must appear in that list.
If it doesn't, run:

```bash
sudo ./scripts/update-model.sh   # re-creates the alias
```

### `tokenIssueSecret missing` error in gateway logs

The gateway refuses to bind on `0.0.0.0` without a token secret.
This is intentional. Two options:

1. **Recommended:** stay on `0.0.0.0` and let `install.sh` generate
   the secret. It lives in `/etc/nanobot/nanobot.env`.
2. **Local-only:** set `NANOBOT_WEBUI_HOST=127.0.0.1` in `.env`
   and re-run `install.sh`. The secret becomes optional.

### Ollama is slow on first request

Expected. The model loads from disk on first use. Check
`OLLAMA_KEEP_ALIVE` — bump it (e.g. `1h`) to keep the model
resident between requests.

### "Module not found" when starting nanobot

The venv is at `/opt/nanobot/venv`. If you re-installed Python at
the OS level, the venv's `pip` may need re-installing:

```bash
sudo /opt/nanobot/venv/bin/pip install --upgrade nanobot-ai
```

### Permission denied on /var/lib/nanobot

The `nanobot` user owns its home. If you ran `nanobot agent` as
the wrong user and the directory got chowned:

```bash
sudo chown -R nanobot:nanobot /var/lib/nanobot
sudo systemctl restart nanobot-gateway
```

### I changed the model but the agent is still using the old one

The gateway caches the model on first use (per `OLLAMA_KEEP_ALIVE`).
Either:

```bash
sudo systemctl restart nanobot-gateway
```

…or just wait for the keep-alive timer.

### WebUI returns 404 on /

That's actually fine in some nanobot versions — the bundled WebUI
is a single-page app and only `/index.html` is served. Try:

```
http://<vm>:8765/index.html
```

If you get a blank page, the WebUI bundle is missing. Reinstall
with the full wheel:

```bash
sudo /opt/nanobot/venv/bin/pip install --force-reinstall nanobot-ai
```

## Clean slate

If everything is on fire:

```bash
sudo ./scripts/uninstall.sh --full
sudo ./install.sh
```

This nixes Ollama, the nanobot venv, the system users, and the
configs, then re-installs from your current `.env`.

## Exposing the WebUI to the internet — please don't, but if you must

**Don't expose `0.0.0.0:8765` directly.** Anyone who can reach it
can drive the agent and through it, anything in `/var/lib/nanobot`.

The right way:

1. Front the VM with nginx / Caddy / Traefik.
2. Terminate TLS (Let's Encrypt).
3. Enforce auth (Basic, OIDC, Cloudflare Access, mTLS, etc.).
4. Optionally rate-limit.

Example nginx snippet:

```nginx
server {
  listen 443 ssl;
  server_name bot.example.com;

  ssl_certificate     /etc/letsencrypt/live/bot.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/bot.example.com/privkey.pem;

  # Some kind of auth — pick one
  auth_basic "nanobot";
  auth_basic_user_file /etc/nginx/.htpasswd;

  location / {
    proxy_pass         http://127.0.0.1:8765;
    proxy_http_version 1.1;
    proxy_set_header   Upgrade $http_upgrade;
    proxy_set_header   Connection "upgrade";
    proxy_set_header   Host $host;
    proxy_set_header   X-Real-IP $remote_addr;
    proxy_read_timeout 3600s;   # WebSockets are long-lived
  }
}
```

Then set `NANOBOT_WEBUI_HOST=127.0.0.1` in `.env` and re-run
`install.sh` so the gateway binds to loopback only.
