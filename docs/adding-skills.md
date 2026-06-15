# Adding Skills

A nanobot **skill** is a prompt + tool bundle that teaches the agent
how to handle a particular kind of task. They're cheaper than MCP
servers (no separate process) and you can ship dozens of them.

## Directory contract

```
skills/<skill-name>/
└── SKILL.md              # required
```

Optional but common:

```
skills/<skill-name>/
├── SKILL.md
├── prompts/              # additional prompt fragments
├── tools/                # local tool definitions
└── examples/             # few-shot examples
```

`post-install.sh` copies the whole folder under
`/var/lib/nanobot/.nanobot/workspace/skills/<skill-name>/`.

## SKILL.md schema

The upstream schema is at
<https://github.com/HKUDS/nanobot/blob/main/docs/skills.md>. A robust
minimal example:

```markdown
# sql-helper

You are a meticulous SQL assistant. Use this skill whenever the user
asks for queries, schema exploration, or data analysis against a
relational database.

## When to use
- The user asks a question that would benefit from a SQL query
- The user pastes a schema and asks "what would X look like"
- The user wants query optimisation advice

## When NOT to use
- Pure NoSQL data (Mongo, Redis) — out of scope
- ORM-specific questions unrelated to SQL

## Tools you have
- `run_query`      — executes a read-only SQL query and returns rows
- `explain_query`  — returns the EXPLAIN plan for a query
- `list_schemas`   — introspects the available databases

## Style
- Always EXPLAIN before recommending a query
- Prefer CTEs over nested subqueries
- Use snake_case for aliases
- Add a one-line comment above every CTE in non-trivial queries

## Safety
- Refuse DROP / TRUNCATE / DELETE without explicit confirmation
- Never interpolate user input directly into a query string
```

## Hot-reload vs restart

The gateway scans `~/.nanobot/workspace/skills/` at startup. To pick up
new skills:

```bash
sudo systemctl restart nanobot-gateway
```

(There's no file watcher; this is intentional — skills can change
agent behaviour and you want explicit control over when.)

## Versioning skills

Tie skill versions to the agent's behaviour:

- Bump the skill name to `<name>-v2` for breaking prompt changes.
- For additive changes, just edit in place; the next gateway restart
  picks it up.

If you want zero-downtime skill changes, run two nanobot instances
behind a load balancer with different `modelPresets` — one stable,
one canary. Out of scope for this deploy script.

## Skills vs MCP

| Aspect            | Skill                              | MCP server                       |
|-------------------|------------------------------------|----------------------------------|
| Lives in          | `~/.nanobot/workspace/skills/`     | Separate process                 |
| Cost              | Just a markdown file               | RAM + startup time               |
| Tooling           | Uses nanobot's built-in tools       | Can bring its own tools + deps   |
| Auth              | N/A (same agent)                   | Can have its own auth/creds      |
| Best for          | Prompt engineering, conventions    | External systems, heavy backends |

When in doubt, start with a skill. Promote to MCP when you need
auth, a separate process lifetime, or a tool that doesn't fit
nanobot's tool interface.
