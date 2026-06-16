# Platform variations

nanobot-vm-deploy is designed to run on **any Linux box that has
Python 3.11+ and a reachable filesystem**. Different targets want
different glue:

```
platform/
├── vm/         ← (no overlay needed; the top-level install.sh is the VM installer)
└── lightning/  ← the Lightning.ai Studio variation
```

## How a "platform" is structured

Every platform overlay ships the same five pieces:

1. **`.lightning_studio/on_start.sh`** *(or systemd equivalent)* —
   auto-launches the stack when the platform boots / the Studio
   starts.
2. **`scripts/install.sh`** — one-time installer tailored to the
   platform's quirks (paths, package manager, service manager).
3. **`scripts/keep_alive.sh`** *(optional)* — keeps idle platforms
   awake and watchdog-restarts dead processes.
4. **`scripts/{start,stop,status}.sh`** — manual control.
5. **`config/`** *(optional)* — platform-tuned nanobot config
   (different ports, different hosts, etc.).

## Sharing between platforms

The `mcp/`, `skills/`, and `scripts/post-install.sh` from the repo
root are **platform-agnostic**. Every platform installer sources
`post-install.sh` after writing its own config, so your custom MCP
servers and skills work uniformly across all targets.

## Adding a new platform

Want to add Docker / Colab / RunPod / Vast.ai / etc.?

1. Create `platform/<name>/`
2. Mirror the structure in `platform/lightning/`
3. Make the top-level `install.sh` auto-detect your platform and
   delegate, OR have users invoke the platform installer directly
4. Add a `docs/<name>.md` and link it from the main `README.md`

The base `install.sh` looks for these to dispatch:

- `/teamspace` exists → **lightning**
- `$RUNPOD_POD_ID` is set → could be **runpod** (future)
- `$COLAB_GPU` is set → could be **colab** (future)

Extend the dispatch in `install.sh` to wire your platform in.
