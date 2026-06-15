# Custom MCP Servers

This directory is the home for any **Model Context Protocol (MCP)** servers
you want to ship alongside nanobot on the deployed VM.

## Layout

Drop one folder per server. The folder name becomes the server name:

```
mcp/
└── servers/
    ├── github-mcp/
    │   ├── install.sh         # optional — runs once during post-install
    │   ├── config.json        # optional — copied to ~/.nanobot/<name>.mcp.json
    │   └── README.md          # optional — your notes
    ├── jira-mcp/
    │   └── …
    └── …
```

## How it gets wired

`scripts/post-install.sh` (which `install.sh` runs at the end of every
install) iterates over `mcp/servers/*/` and:

1. Runs `<server>/install.sh` if it exists and is executable
2. Copies `<server>/config.json` to `/var/lib/nanobot/.nanobot/<server>.mcp.json`
   with correct ownership
3. Logs each step

The block is **shipped commented-out** so a fresh install with an empty
`mcp/servers/` doesn't error. Open `scripts/post-install.sh`, uncomment
section 1, and you're live.

## Example: a "hello-world" MCP server

```bash
mkdir -p mcp/servers/hello-world
cat > mcp/servers/hello-world/config.json <<'JSON'
{
  "command": "python3",
  "args": ["-m", "hello_world_server"],
  "env": { "GREETING": "ahoy" }
}
JSON
cat > mcp/servers/hello-world/install.sh <<'BASH'
#!/usr/bin/env bash
# Install hello_world_server into the nanobot venv
set -euo pipefail
/opt/nanobot/venv/bin/pip install hello-world-server
BASH
chmod +x mcp/servers/hello-world/install.sh
```

Then `sudo ./install.sh` — the post-install hook will install the Python
package and drop the config into the right place.

## Tips

- MCP server **processes** are launched by nanobot on demand, not by
  systemd, so they don't need their own unit files.
- For servers that need system-level binaries (e.g. `git`, `gh`),
  install them in `install.sh` using the helpers in
  `scripts/lib/system.sh` (`pkg_install curl gh`).
- Secrets belong in `/etc/nanobot/nanobot.env`, not in `config.json`.
- If your MCP server uses `stdio`, make sure the command in `config.json`
  resolves correctly for the `nanobot` user (use absolute paths).
