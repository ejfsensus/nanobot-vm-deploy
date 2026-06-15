# Adding MCP Servers

The Model Context Protocol (MCP) lets nanobot talk to external tools —
think "plugins for the agent". See `mcp/README.md` for the directory
contract; this doc is the longer-form how-to.

## Lifecycle on the VM

1. You commit an `mcp/servers/<name>/` folder to the repo.
2. `sudo ./install.sh` runs `scripts/post-install.sh`.
3. `post-install.sh` walks `mcp/servers/*/`, runs any `install.sh`,
   copies any `config.json` to `/var/lib/nanobot/.nanobot/<name>.mcp.json`.
4. The nanobot gateway picks up the new MCP server on its next start
   (we restart it as part of the install).
5. From the agent's POV, the MCP server's tools are now available —
   no further wiring.

## Two patterns for MCP servers

### Pattern A: Python package (most common)

```
mcp/servers/<name>/
├── install.sh       # pip-installs the package into the nanobot venv
└── config.json      # {"command": "/opt/nanobot/venv/bin/<name>-mcp-server", ...}
```

`install.sh` example:
```bash
#!/usr/bin/env bash
set -euo pipefail
/opt/nanobot/venv/bin/pip install <pip-package-name>
```

`config.json` example:
```json
{
  "command": "/opt/nanobot/venv/bin/<name>-mcp-server",
  "args": ["--transport", "stdio"],
  "env": {}
}
```

### Pattern B: System binary + Node/Python

```
mcp/servers/<name>/
├── install.sh       # apt-installs deps, npm-installs the server
└── config.json
```

`install.sh` example:
```bash
#!/usr/bin/env bash
set -euo pipefail
# Re-use the system helpers
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
. "${SCRIPT_DIR}/../../scripts/lib/os-detect.sh"
. "${SCRIPT_DIR}/../../scripts/lib/system.sh"
detect_os
pkg_install nodejs npm
npm install -g <npm-package>
```

`config.json` example:
```json
{
  "command": "npx",
  "args": ["-y", "<npm-package>", "--stdio"],
  "env": {}
}
```

## Enabling the wiring in `post-install.sh`

Out of the box the relevant block is **commented out** so empty repos
don't fail. Open `scripts/post-install.sh` and uncomment section 1.

## Verifying an MCP server

After `sudo ./install.sh`:

```bash
sudo -u nanobot -H -E /opt/nanobot/venv/bin/nanobot status
journalctl -u nanobot-gateway -n 100 | grep -i mcp
```

A working server logs something like:
```
[mcp] loaded server 'github-mcp' with 5 tools
```

## Debugging

If an MCP server fails to start:

1. Run the command **as the `nanobot` user**:
   ```bash
   sudo -u nanobot -H -E \
     /opt/nanobot/venv/bin/<your-server> <args>
   ```
   Most stdio MCP servers print JSON-RPC traffic to stderr — that's
   your best debugging signal.

2. Check ownership: nanobot can't read files owned by `root` with mode `600`.
   Default to `0640` and `root:nanobot`.

3. The systemd hardening (`ProtectSystem=full`,
   `ReadWritePaths=/var/lib/nanobot`) means the MCP server **cannot**
   write outside `/var/lib/nanobot`. If your server needs to write
   to e.g. `/var/log`, add another `ReadWritePaths=` line in
   `config/nanobot-gateway.service` and re-run `install.sh`.

## Secrets in MCP configs

`config.json` is world-readable (mode `0640`, group `nanobot`).
**Never** put API keys in there. Instead:

1. Add the key to `/etc/nanobot/nanobot.env`:
   ```bash
   GITHUB_TOKEN=ghp_xxxxxxxxxxxx
   ```
2. Reference it in the MCP config via env:
   ```json
   { "env": { "GITHUB_TOKEN": "${GITHUB_TOKEN}" } }
   ```
3. The gateway expands `${VAR}` from its own env at launch.

If the env var contains characters that JSON would object to, you
can also read the value at runtime from `/etc/nanobot/nanobot.env`
inside the MCP server process.
