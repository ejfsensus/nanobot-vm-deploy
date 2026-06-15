# Custom nanobot Skills

Drop one folder per skill. The folder must contain a `SKILL.md` describing
the skill in the format nanobot expects.

## Layout

```
skills/
├── research-assistant/
│   ├── SKILL.md              # required — the skill manifest
│   ├── prompts/              # optional — supporting prompt files
│   │   └── deep-dive.md
│   └── tools/                # optional — tool definitions
│       └── web_search.py
├── sql-helper/
│   └── SKILL.md
└── …
```

## How it gets wired

`scripts/post-install.sh` iterates over `skills/*/` and copies any folder
that contains a `SKILL.md` to:

```
/var/lib/nanobot/.nanobot/workspace/skills/<skill-name>/
```

…with correct ownership. The nanobot gateway auto-discovers skills from
that location at startup.

## SKILL.md format

The exact schema is documented in the upstream nanobot repo
(<https://github.com/HKUDS/nanobot/blob/main/docs/skills.md>). A minimal
example:

```markdown
# research-assistant

A skill that turns the agent into a focused research assistant.

## When to use
- The user asks for a literature review, market scan, or competitive analysis.
- The user wants a citation-backed summary.

## Tools
- web_search
- fetch_url

## Style
- Cite sources inline as [n]
- Prefer recent (<2y) sources unless told otherwise
- If the query is ambiguous, ask one clarifying question before searching
```

## Tips

- Skill names should be kebab-case.
- Keep `SKILL.md` under ~200 lines — the agent reads it every turn.
- Heavy dependencies for a skill's tools belong in the venv at
  `/opt/nanobot/venv` (install them from `scripts/post-install.sh`).
- After editing skills, bounce the gateway:
  `sudo systemctl restart nanobot-gateway`.
